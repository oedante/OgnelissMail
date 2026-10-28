// lib/services/mail/engine/mail_engine_service.dart
// Адаптер между единым движком (пакет mail_engine) и моделями приложения.
// Заменяет разрозненные транспорты (activesync/ews/imap) единым контрактом.
// UI и БД не трогаем: отдаём те же FolderModel / EmailModel.

import '../../../core/utils/category_colors.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'dart:math';
import '../../../core/errors/app_exceptions.dart' show PushAuthFailure, NetworkException, ServerUnavailableException;
import '../../../core/device/device_user_agent.dart';
import '../../../core/platform/device_time_zone.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:drift/drift.dart';

import '../../../core/logging/app_logger.dart';
import '../../sync/push_health.dart';
import '../../../data/database/app_database.dart';
import '../../../features/compose/providers/attachment_limit_provider.dart';
import '../../../core/network/corporate_http_client.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/free_busy_view.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/note_model.dart';
import '../../../data/models/task_model.dart';
import '../dav/dav_credentials.dart';
import '../dav/dav_pim_service.dart';
import '../ews/ews_service.dart';
import '../ews/ews_directory_extras.dart';
import '../ews/ews_mail_tips.dart';
import '../oauth/oauth_proxy_client.dart';
import '../oauth/oauth_service.dart' show OAuthService;
import '../imap/imap_service.dart';
import '../../calendar/eas_recurrence.dart';
import '../../calendar/itip_reply.dart';
import '../../../data/providers/database_provider.dart';
import '../../security/remote_wipe_service.dart';
import '../../security/eas_policy_store.dart';
import '../../security/mail_classification.dart' show MailLabel;
import '../../../features/settings/providers/settings_provider.dart' show settingsProvider, EmailFetchMode;
import '../../security/smime_service.dart' show smimeServiceProvider;

/// Результат синхронизации папки для слоя приложения.
class EngineFolderSync {
  final List<EmailModel> added;
  /// Письма, удалённые на сервере (id в формате приложения).
  final List<String> deletedIds;
  /// Изменения «прочитано/флаг», сделанные на других устройствах.
  final List<me.MailFlagChange> flagChanges;
  final String? newSyncToken;
  final bool moreAvailable;
  const EngineFolderSync({
    this.added = const [],
    this.deletedIds = const [],
    this.flagChanges = const [],
    this.newSyncToken,
    this.moreAvailable = false,
  });
}

/// Сервис-обёртка вокруг движка mail_engine для одного аккаунта.
class MailEngineService {
  final SecureStorageService _secureStorage;
  final SharedPreferences _prefs;
  /// [_ref] нужен для доступа к БД (сохранение адреса EWS при гибридном
  /// режиме). Опционален, чтобы не ломать вызовы в тестах.
  MailEngineService(this._secureStorage, this._prefs, [this._ref]);

  final Ref? _ref;

  String _tokKey(String accountId, String folderId, String kind) =>
      'synctok_${kind}_${accountId}_$folderId';

  /// Последовательное выполнение команд движка ActiveSync на аккаунт.
  /// Синхронизация папки и действие пользователя (прочитано, флаг, удаление)
  /// используют один SyncKey папки: выполненные одновременно, они отправляли
  /// серверу один и тот же ключ, сервер отвечал Status 3, и папка
  /// перечитывалась с нуля (а удаления с других устройств терялись).
  final Map<String, Future<void>> _engineLocks = {};

  Future<T> _serial<T>(String accountId, Future<T> Function() action) async {
    final previous = _engineLocks[accountId];
    final gate = Completer<void>();
    _engineLocks[accountId] = gate.future;
    try {
      if (previous != null) {
        // 1.6.12: ожидание предыдущей команды ящика — с отметкой в журнале.
        // Зависшая команда держала очередь молча: после «подключено» в
        // журнале не было ни одного запроса, и синхронизация стояла до
        // перезапуска (журналы 14–15.10.2026).
        final warn = Timer(const Duration(seconds: 60), () {
          AppLogger.warning('MailEngine ${_emailOf[accountId] ?? accountId}: команда ждёт предыдущую больше 60 с');
        });
        try { await previous; } catch (_) {} finally { warn.cancel(); }
      }
      // SyncKey папок живут в общем хранилище, а SharedPreferences кэширует
      // его в каждом изоляте: фоновая синхронизация (WorkManager) сдвигала
      // ключ, а приложение продолжало со старым — Status 3 и папка заново.
      // Не дольше 5 с: в фоновом изоляте канал плагина может не ответить
      // («Channel was closed before receiving a response»), и без предела
      // команда ждала бы вечно, а за ней — вся очередь ящика.
      try {
        await _prefs.reload().timeout(const Duration(seconds: 5));
      } catch (e) {
        if (e is TimeoutException) AppLogger.warning('MailEngine: настройки не перечитаны за 5 с — работаем с прежними');
      }
      return await action();
    } finally {
      gate.complete();
      if (identical(_engineLocks[accountId], gate.future)) _engineLocks.remove(accountId)?.ignore();
    }
  }

  /// Кеш подключённых движков по accountId (живут в рамках сессии приложения).
  final Map<String, me.MailEngine> _engines = {};

  /// Сервер Exchange просил подождать (503/ограничение): до этого времени
  /// команды аккаунта не отправляются. null — ограничения нет.
  DateTime? serverBusyUntil(String accountId) {
    final e = _engines[accountId];
    return e is me.EasEngine ? e.busyUntil : null;
  }

  /// Текст последней ошибки подключения по аккаунту (например, «401 Unauthorized»).
  final Map<String, String> _lastConnectError = {};

  /// Последняя ошибка подключения аккаунта (для пакета диагностики).
  String? lastConnectError(String accountId) => _lastConnectError[accountId];

  /// Убедиться, что подключение к серверу есть; иначе — исключение с причиной.
  ///
  /// Методы фасада при неудачном подключении тихо возвращают пустые списки —
  /// для экранов это удобно, но синхронизация тогда не отличала «писем нет»
  /// от «пароль сменили»: отметка об ошибке входа для EAS не ставилась
  /// никогда. Синхронизация вызывает этот метод первым.
  Future<void> ensureConnected(AccountModel account) async {
    // 1.6.24: первая синхронизация нового ящика на iPhone стояла на этом
    // шаге 2 минуты без единой строки в журнале, хотя движок подключился
    // за 15 мс (журнал 18.10.2026). Теперь видно, какой шаг держит.
    final warn = Timer(const Duration(seconds: 30), () {
      final s = _connectStep[account.id];
      final why = s != null
          ? 'шаг «${s.step}», ${DateTime.now().difference(s.since).inSeconds} с'
          : (_engines[account.id] != null ? 'движок уже готов, ожидание не завершилось' : 'шаг не отмечен');
      AppLogger.warning('MailEngine ${account.email}: подключение идёт больше 30 с ($why)');
    });
    final engine = await _awaitEngine(account, _engineFor(account)).whenComplete(warn.cancel);
    if (engine == null) {
      throw Exception('Подключение к серверу не удалось: '
          '${_lastConnectError[account.id] ?? 'нет учётных данных'}');
    }
  }

  /// Ключ кэша вложений. id вложения уникален не во всех протоколах: в IMAP
  /// это номер части MIME («2» есть почти в каждом письме), и кэш по голому
  /// id открывал бы файл из ДРУГОГО письма.
  static String attachmentCacheKey(String accountId, String emailId, String attachmentId) =>
      '$accountId|$emailId|$attachmentId';

  /// Папка результатов поиска на сервере ActiveSync (письма в ней — не
  /// письма папок ящика).
  static const easSearchFolderId = me.EasEngine.searchFolderId;

  /// Подключиться (или переиспользовать активное подключение) для аккаунта.
  /// Пробное подключение Exchange через движок (OPTIONS → Provision → подбор
  /// версии/UA — как в рабочем connect_test). Возвращает простую запись без
  /// типов движка. Используется при входе для проверки доступности.
  Future<({bool ok, String? transport, String? host, String? error})> probeConnect(
      AccountModel account) async {
    // Проверка входа — всегда по-настоящему: сохранённый сеанс ActiveSync
    // пропустил бы OPTIONS/Provision и «принял» неверный пароль.
    forgetEasSession(account.email);
    final cfg = await _buildConfig(account, probe: true);
    if (cfg == null) return (ok: false, transport: null, host: null, error: 'нет учётных данных');
    final logger = _newEngineLog();
    final (engine, res) = await me.EngineFactory.connect(
      cfg,
      logger: logger,
      httpClient: createCorporateHttpClient(compat: DeviceUserAgent.compatFor(account.id)),
    );
    try { await engine?.dispose(); } catch (_) {}
    _dumpEngineLog(account, res, logger);
    final t = res.transport == me.MailTransportKind.eas
        ? 'eas'
        : (res.transport == me.MailTransportKind.ews ? 'ews' : null);
    return (ok: res.success, transport: t, host: res.resolvedHost, error: res.error);
  }

  /// Подключения, которые идут сейчас: одно на ящик. Раньше при запуске
  /// синхронизация, открытие письма и предзагрузка подключались к одному
  /// ящику одновременно — четыре OPTIONS и три Provision подряд (журнал
  /// 13.10.2026); один Provision получил 502 от шлюза, движок перешёл на
  /// протокол 14.1, и Exchange сбросил синхронизацию всех папок.
  final Map<String, Future<me.MailEngine?>> _connecting = {};

  Future<me.MailEngine?> _engineFor(AccountModel account) {
    final existing = _engines[account.id];
    if (existing != null) return Future.value(existing);
    final pending = _connecting[account.id];
    if (pending != null) return _joinPending(account, pending);
    return _startConnect(account);
  }

  Future<me.MailEngine?> _startConnect(AccountModel account) {
    late final Future<me.MailEngine?> f;
    f = _connectEngine(account).whenComplete(() {
      if (identical(_connecting[account.id], f)) _connecting.remove(account.id);
    });
    _connecting[account.id] = f;
    return f;
  }

  /// Шаг подключения, который идёт сейчас (для журнала и самолечения).
  final Map<String, ({String step, DateTime since})> _connectStep = {};
  static const _stepServer = 'запросы к серверу';

  /// Присоединиться к подключению, начатому другим вызовом. Движок может
  /// оказаться готов раньше, чем завершится этот Future, — проверяем каждые
  /// 2 с. Подключение, застрявшее ДО запросов к серверу (хранилище паролей,
  /// настройки) дольше 40 с, бросаем и начинаем заново; идущее к серверу не
  /// трогаем — второй параллельный OPTIONS/Provision шлюзы не любят.
  Future<me.MailEngine?> _joinPending(AccountModel account, Future<me.MailEngine?> pending) async {
    final started = DateTime.now();
    while (true) {
      try {
        return await pending.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        final ready = _engines[account.id];
        if (ready != null) return ready;
        final step = _connectStep[account.id];
        final stuckLocal = step == null || step.step != _stepServer;
        if (stuckLocal && DateTime.now().difference(started) >= const Duration(seconds: 40)) {
          AppLogger.warning('MailEngine ${account.email}: подключение стоит на шаге '
              '«${step?.step ?? 'не отмечен'}» больше 40 с — подключаемся заново');
          if (identical(_connecting[account.id], pending)) _connecting.remove(account.id)?.ignore();
          final again = _connecting[account.id];
          return again ?? _startConnect(account);
        }
      }
    }
  }

  /// Дождаться подключения, но вернуть движок, как только он готов: если
  /// ожидание по какой-то причине не завершается, а движок ящика уже
  /// подключён (так было в журнале 18.10.2026), синхронизация не стоит.
  Future<me.MailEngine?> _awaitEngine(AccountModel account, Future<me.MailEngine?> f) async {
    while (true) {
      try {
        return await f.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        final ready = _engines[account.id];
        if (ready != null) {
          AppLogger.warning('MailEngine ${account.email}: движок готов, а ожидание подключения '
              'не завершилось — продолжаем с готовым');
          return ready;
        }
      }
    }
  }

  void _markStep(String accountId, String step) =>
      _connectStep[accountId] = (step: step, since: DateTime.now());

  Future<me.MailEngine?> _connectEngine(AccountModel account) async {
    try {
      return await _connectEngineImpl(account);
    } finally {
      _connectStep.remove(account.id);
    }
  }

  Future<me.MailEngine?> _connectEngineImpl(AccountModel account) async {
    _emailOf[account.id] = account.email;

    _markStep(account.id, 'учётные данные');
    final cfg = await _buildConfig(account);
    if (cfg == null) {
      AppLogger.error('MailEngine: нет учётных данных для ${account.email}');
      return null;
    }

    _markStep(account.id, _stepServer);
    final logger = _newEngineLog();
    final (engine, res) = await me.EngineFactory.connect(
      cfg,
      logger: logger,
      httpClient: createCorporateHttpClient(compat: DeviceUserAgent.compatFor(account.id)),
    );
    _dumpEngineLog(account, res, logger);
    _markStep(account.id, 'сохранение настроек ящика');
    if (engine == null || !res.success) {
      _lastConnectError[account.id] = res.error ?? 'неизвестная ошибка';
      return null;
    }
    _lastConnectError.remove(account.id);
    AppLogger.info('MailEngine: ${account.email} → транспорт ${res.transport}, хост ${res.resolvedHost}');
    // Лимит вложений из политики сервера (EAS Provision/MaxAttachmentSize).
    // Раньше лимит узнавался только постфактум — из ошибки отклонённой отправки;
    // теперь известен сразу после подключения, и пользователь видит ограничение
    // ещё при прикреплении файла.
    // ── Гибридный режим EAS + EWS ──────────────────────────────────────────
    // Подключились по EAS, а Autodiscover попутно отдал адрес EWS. Сохраняем
    // его в аккаунт: почта/календарь/контакты продолжают идти по EAS (Direct
    // Push, экономия батареи), а операции, которых в EAS нет — автоответы,
    // занятость коллег, категории Outlook, серверные правила, отзыв письма —
    // пойдут через EWS. Именно так работают Nine/OfficeMail.
    final companion = res.companionEwsUrl;
    if (companion != null && companion.isNotEmpty &&
        (account.ewsUrl == null || account.ewsUrl!.isEmpty)) {
      try {
        final db = _ref?.read(databaseProvider);
        if (db != null) {
          // Тип «corporate» означает «транспорт определить автоматически», а
          // usesEas у него истинно, только пока ewsUrl ПУСТ. Сохрани мы адрес
          // EWS как есть — после перезапуска аккаунт молча переключился бы на
          // EWS, и идентификаторы папок/писем, полученные по EAS, перестали бы
          // совпадать. Поэтому вместе с адресом закрепляем фактический
          // транспорт: подключились по EAS — значит activesync.
          await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
              .write(AccountsCompanion(
            ewsUrl: Value(companion),
            type: account.type == AccountType.corporate
                ? Value(AccountType.activesync.index)
                : const Value.absent(),
          ));
          AppLogger.info('Гибрид EAS+EWS включён для ${account.email}: $companion');
        }
      } catch (e) {
        AppLogger.warning('Не удалось сохранить EWS-адрес для гибрида: $e');
      }
    }

    final pol = res.policy;
    if (pol != null) {
      try {
        await EasPolicyStore(_prefs).save(
            account.id,
            StoredEasPolicy(
              pinRequired: pol.devicePasswordEnabled,
              minPinLength: (pol.minPasswordLength ?? 4).clamp(4, 6),
              maxInactivitySeconds: pol.maxInactivitySeconds ?? 0,
              minPasswordLength: pol.minPasswordLength ?? 0,
              allowSimplePassword: pol.allowSimplePassword,
              alphanumericRequired: pol.alphanumericRequired,
              requireEncryption: pol.requireDeviceEncryption,
              maxFailedAttempts: pol.maxFailedAttempts ?? 0,
            ));
        _ref?.invalidate(easPolicyProvider);
      } catch (e) {
        AppLogger.warning('Не удалось сохранить политику EAS: $e');
      }
    }
    final maxAtt = res.policy?.maxAttachmentSize;
    if (maxAtt != null && maxAtt > 0) {
      try {
        await AttachmentLimitStore(_prefs).setLimit(account.id, maxAtt);
        AppLogger.info('Лимит вложений от сервера: $maxAtt Б (${account.email})');
      } catch (e) {
        AppLogger.warning('Не удалось сохранить лимит вложений: $e');
      }
    }
    if (engine is me.EasEngine) {
      final saved = _prefs.getString('easfolders_${account.id}');
      if (saved != null) engine.importFolderState(saved);
    }
    _engines[account.id] = engine;
    return engine;
  }

  /// Журнал движка пишется в журнал приложения сразу, по мере работы:
  /// раньше он копился в памяти и попадал в файл только при неудачном
  /// подключении — ошибки синхронизации, 403 от шлюза, повторный Provision
  /// и строка «Политики: …» при успешном входе терялись.
  /// В обычном режиме — шаги и коды ответов; в подробном (AppLogger.detailed)
  /// ещё заголовки, фрагменты тел и деревья WBXML.
  me.DebugLog _newEngineLog() {
    return me.DebugLog(
      // Проверяется на каждой записи: подробный режим выключается сам через
      // сутки, а движок подключённого ящика живёт всю сессию.
      isVerbose: () => AppLogger.detailed,
      echo: false,
      sink: (e) {
        final line = '[${e.transport}] ${e.message}';
        switch (e.level) {
          case me.LogLevel.debug:
            if (AppLogger.detailed) AppLogger.debug(line);
          case me.LogLevel.info:
            AppLogger.info(line);
          case me.LogLevel.warn:
            AppLogger.warning(line);
          case me.LogLevel.error:
            AppLogger.error(line);
        }
      },
    );
  }

  /// Перенести журнал движка в общий лог приложения.
  ///
  /// Движок ведёт подробную запись всех шагов (Autodiscover, выбор URL,
  /// Provision, версии протокола, коды ответов) в собственный `DebugLog`.
  /// Раньше он создавался с `echo: false`, и этот журнал никуда не попадал:
  /// при сбое подключения в логе оставалась одна строка с текстом ошибки, а
  /// причину — не тот сервер, отказ политики, неподдерживаемая версия — узнать
  /// было нельзя. Теперь при ошибке журнал пишется целиком, при успехе —
  /// только итог, чтобы не раздувать файл.
  void _dumpEngineLog(AccountModel account, me.ConnectResult res, me.DebugLog logger) {
    try {
      if (res.success) {
        AppLogger.info(
            'MailEngine ${account.email}: подключено (${res.transport}, ${res.resolvedHost})');
        return;
      }
      // Шаги подключения уже записаны в журнал по ходу (см. _newEngineLog);
      // в обычном режиме debug-строки (Autodiscover, перебор адресов) не
      // пишутся — при неудаче они нужны, дописываем их сейчас.
      AppLogger.error('MailEngine ${account.email}: подключение не удалось — ${res.error}');
      if (!AppLogger.detailed) {
        for (final e in logger.entries) {
          if (e.level == me.LogLevel.debug) AppLogger.debug('  [${e.transport}] ${e.message}');
        }
      }
    } catch (e) {
      AppLogger.warning('Не удалось перенести журнал движка: $e');
    }
  }

  /// Построить AccountConfig движка из модели аккаунта приложения.
  Future<me.AccountConfig?> _buildConfig(AccountModel account, {bool probe = false}) async {
    final password = await _readSecret(account, 'пароль', () => _secureStorage.getAccountPassword(account.id));
    final accessToken = await _readSecret(account, 'токен', () => _secureStorage.getAccessToken(account.id));

    me.AuthKind authKind;
    switch (account.type) {
      case AccountType.google:
      case AccountType.yandex:
      case AccountType.yahoo:
      case AccountType.mailru:
      case AccountType.outlook:
        authKind = accessToken != null ? me.AuthKind.oauth2 : me.AuthKind.appPassword;
        break;
      default:
        // Exchange Online (Microsoft 365) по OAuth — Bearer (1.6.2).
        authKind = account.isExchangeOnlineOAuth ? me.AuthKind.oauth2 : me.AuthKind.basic;
    }
    // Токен Exchange Online живёт час, а движок — дольше: он просит новый у
    // приложения при подключении и после ответа 401.
    final oauth = OAuthService(_secureStorage);
    Future<String?> tokenSource({bool force = false}) => oauth.validAccessToken(account, force: force);

    // iPhone, режим совместимости, вход по паролю (1.6.17): новый вход и
    // ящики ActiveSync — в форме Почты iOS (только EAS). Ящик, сохранённый
    // как EWS, опрашивает только EWS: раньше он после отказа EWS пробовал и
    // EAS со старыми заголовками — шлюз блокировал хост на 15 минут, и
    // новый вход в тот же ящик сразу получал «пауза».
    final iosCompat = _iosCompatBasic(account, authKind);
    me.MailTransportKind? forced;
    if (account.usesEas) {
      forced = me.MailTransportKind.eas;
    } else if (iosCompat && !probe && account.usesEws) {
      forced = me.MailTransportKind.ews;
    } else if (account.type == AccountType.imap ||
        account.type == AccountType.google ||
        account.type == AccountType.yandex ||
        account.type == AccountType.mailru ||
        account.type == AccountType.outlook ||
        account.type == AccountType.yahoo) {
      forced = me.MailTransportKind.imapSmtp;
    }

    return me.AccountConfig(
      email: account.email,
      password: password,
      oauthAccessToken: accessToken,
      oauthTokenSource: account.isExchangeOnlineOAuth ? tokenSource : null,
      authKind: authKind,
      domain: account.domain,
      exchangeServer: account.exchangeServer,
      imapHost: account.imapServer,
      imapPort: account.imapPort ?? 993,
      smtpHost: account.smtpServer,
      smtpPort: account.smtpPort ?? 465,
      forceTransport: forced,
      // HTML, а не простой текст: корпоративная почта — это таблицы, списки,
      // выделения; в plain text они превращались в кашу. Обрезка на синке —
      // 64 КБ: так целиком приходит большинство корпоративных писем (Outlook
      // кладёт в HTML десятки килобайт стилей; при 20 КБ почти каждое письмо
      // догружалось при открытии). Остальное докачивают «Письма на телефоне»
      // (OfflineStoreService) в фоне после синхронизации.
      bodyType: 2,
      // Режим «до 50 КБ» — не больше и при синхронизации.
      bodyTruncationBytes:
          _ref?.read(settingsProvider).emailFetchMode == EmailFetchMode.partial50k ? 51200 : 65536,
      mailFilterType: _filterTypeForDays(account.syncDays),
      // Честный User-Agent/DeviceType из реальных системных данных устройства
      // (не имитируем чужое устройство).
      // Режим совместимости со шлюзом — свой у каждого ящика.
      userAgent: DeviceUserAgent.valueFor(account.id),
      deviceType: DeviceUserAgent.deviceTypeFor(account.id),
      deviceModel: DeviceUserAgent.deviceModel,
      deviceOs: DeviceUserAgent.deviceOs,
      deviceFriendlyName: DeviceUserAgent.deviceFriendlyName,
      deviceLanguage: DeviceUserAgent.deviceLanguage,
      // Всегда, а не только для EAS: пробное подключение при входе идёт с
      // типом «Exchange» и тоже делает Provision — с другим id сервер увидел
      // бы два устройства (пробное и настоящее).
      deviceId: await _deviceIdFor(account),
      // iPhone в режиме совместимости (1.6.17): запросы в форме Почты iOS —
      // порядок командной строки, только заголовки ActiveSync (язык и сжатие
      // ставит система), без опроса EWS. Только вход по логину и паролю.
      appleMailProfile: iosCompat && (probe || account.usesEas),
    );
  }

  /// Чтение из хранилища паролей с пределом: на iPhone чтение сразу после
  /// записи (новый ящик) может не вернуться, и подключение ждало молча.
  static Future<String?> _readSecret(
      AccountModel account, String what, Future<String?> Function() read) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await read().timeout(const Duration(seconds: 10));
      } on TimeoutException {
        AppLogger.warning('MailEngine ${account.email}: хранилище паролей не ответило за 10 с '
            '($what, попытка $attempt из 3)');
        if (attempt >= 3) rethrow;
      }
    }
  }

  /// iPhone и приложение не на экране (свёрнуто или переключается): iOS
  /// вот-вот заморозит или уже заморозила процесс.
  static bool get _iosSuspended =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;

  static bool _iosCompatBasic(AccountModel account, me.AuthKind authKind) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      authKind == me.AuthKind.basic &&
      account.type != AccountType.imap &&
      DeviceUserAgent.compatFor(account.id);

  /// DeviceId ActiveSync — свой на каждую установку и ящик.
  ///
  /// Раньше он вычислялся из адреса почты: телефон и планшет одного
  /// человека представлялись серверу ОДНИМ устройством, сбрасывали друг
  /// другу SyncKey (бесконечная полная пересинхронизация, «письма пропадают
  /// и появляются») и делили одну запись в списке устройств администратора.
  ///
  /// Уже подключённые ящики сохраняют прежний id (он записан при первом
  /// подключении): новый означал бы новое партнёрство — повторную загрузку
  /// всего ящика и, при карантине устройств, повторное одобрение
  /// администратором.
  Future<String> _deviceIdFor(AccountModel account) async {
    final key = 'eas_device_id_${account.id}';
    final saved = _prefs.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;
    final String id;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS &&
        DeviceUserAgent.compatFor(account.id)) {
      // iPhone в режиме «как Почта iPhone» (1.6.13): DeviceId того же вида,
      // что у Почты iOS — 26 символов A–Z и 0–9 (снимок сервера 17.10.2026:
      // «T5KCOR7PBL5A3E1GONS10002AG»), а не «OGNL…» Android-сборки.
      const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random.secure();
      id = List.generate(26, (_) => abc[rnd.nextInt(abc.length)]).join();
    } else {
      // Длина прежняя (28 символов: префикс и 24 шестнадцатеричных знака).
      // С 1.7.3 у новых ящиков префикс «OGNL»; у подключённых раньше id
      // сохранён и не меняется.
      final rnd = Random.secure();
      id = 'OGNL${List.generate(12, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
    }
    // Сохраняем до первого запроса: фоновый процесс (WorkManager) читает
    // тот же id, а не придумывает свой.
    await _prefs.setString(key, id);
    return id;
  }

  /// Переводит «дни синхронизации» из настроек аккаунта в EAS FilterType.
  /// Для почты ActiveSync знает окна только до месяца (FilterType 1–5);
  /// 3 и 6 месяцев (6, 7) — лишь для календаря. Поэтому «полгода» и «год» —
  /// без фильтра на сервере, а лишнее отсекается при сохранении по дате
  /// (SyncService) и автоочисткой.
  int _filterTypeForDays(int days) {
    if (days <= 0) return 0; // всё
    if (days <= 1) return 1;
    if (days <= 3) return 2;
    if (days <= 7) return 3;
    if (days <= 14) return 4;
    if (days <= 31) return 5;
    return 0; // > месяца — без фильтра на сервере, срез по дате в приложении
  }

  /// Папки аккаунта в виде FolderModel (только почтовые — PIM идёт отдельно).
  Future<List<FolderModel>> getFolders(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    final folders = await engine.listFolders();
    if (engine is me.EasEngine && folders.isNotEmpty) {
      unawaited(_prefs.setString('easfolders_${account.id}', engine.exportFolderState()));
    }
    const mailTypes = {
      me.MailFolderType.inbox, me.MailFolderType.sent, me.MailFolderType.drafts,
      me.MailFolderType.trash, me.MailFolderType.junk, me.MailFolderType.outbox,
      me.MailFolderType.archive, me.MailFolderType.user,
    };
    return [
      for (final f in folders)
        if (mailTypes.contains(f.type)) _toFolderModel(account.id, f),
    ];
  }

  // ──────────────────── PIM: календарь/контакты/заметки/задачи ────────────────────

  Future<List<me.MailFolder>> _foldersOfType(AccountModel account, me.MailFolderType type) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    final all = await engine.listFolders();
    return all.where((f) => f.type == type).toList();
  }

  /// Синхронизация PIM с сохранением sync-токена между запусками (SharedPreferences).
  Future<List<me.PimItem>> _pimSync(
      AccountModel account, me.MailEngine engine, String folderId, String dataClass) async {
    final kind = 'pim_$dataClass';
    final all = <me.PimItem>[];
    // Сервер отдаёт элементы порциями (WindowSize). Без цикла календарь из
    // 300 событий догружался бы по сотне за каждый плановый синк.
    // Ключ подтверждается (пишется в prefs) только после того, как
    // синхронизация сохранила элементы в БД — commitPimSync(). До этого он
    // ждёт в _pendingPimKeys, а следующие порции идут с ключом из памяти.
    final prefKey = _tokKey(account.id, folderId, kind);
    String? current = _pendingPimKeys[account.id]?[dataClass]?[prefKey] ??
        _prefs.getString(prefKey);
    // Изменений нет по оценке сервера — Sync в эту папку не нужен.
    if (engine is me.EasEngine && current != null && current != '0') {
      final est = await _pimEstimate(account, engine);
      if (est[folderId] == 0) return const [];
    }
    for (var round = 0; round < 10; round++) {
      final items = await engine.syncPim(folderId,
          dataClass: dataClass, since: current != null ? me.SyncState(current) : null);
      all.addAll(items);
      if (engine is! me.EasEngine) break;
      final nk = engine.pimSyncKeyFor(folderId);
      if (nk != null) {
        current = nk;
        ((_pendingPimKeys[account.id] ??= {})[dataClass] ??= {})[prefKey] = nk;
        ((_pendingPimFolders[account.id] ??= {})[dataClass] ??= <String>{}).add(folderId);
      }
      if (!engine.lastPimMoreAvailable) break;
    }
    // Удалённые на сервере элементы запоминаем: экраны их пропускают, а
    // синхронизация забирает список и удаляет строки из локальной базы.
    final deleted = [for (final it in all) if (it.deleted) 'eas_${it.serverId}'];
    if (deleted.isNotEmpty) {
      (_pimDeleted[account.id] ??= {}).putIfAbsent(dataClass, () => <String>{}).addAll(deleted);
    }
    return all;
  }

  /// Оценка изменений во всех PIM-папках аккаунта — один GetItemEstimate на
  /// проход синхронизации (календарь, контакты, задачи, заметки), а не Sync в
  /// каждую папку. Результат живёт 30 секунд: этого хватает на один проход.
  final Map<String, ({DateTime at, Map<String, int?> est})> _pimEstimates = {};

  Future<Map<String, int?>> _pimEstimate(AccountModel account, me.EasEngine engine) async {
    final cached = _pimEstimates[account.id];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 30)) {
      return cached.est;
    }
    const classOf = {
      me.MailFolderType.calendar: 'Calendar',
      me.MailFolderType.contacts: 'Contacts',
      me.MailFolderType.tasks: 'Tasks',
      me.MailFolderType.notes: 'Notes',
    };
    final folders = <String, ({String key, String dataClass})>{};
    try {
      for (final f in await engine.listFolders()) {
        final cls = classOf[f.type];
        if (cls == null) continue;
        final key = _pendingPimKeys[account.id]?[cls]?[_tokKey(account.id, f.id, 'pim_$cls')] ??
            _prefs.getString(_tokKey(account.id, f.id, 'pim_$cls'));
        if (key != null && key != '0') folders[f.id] = (key: key, dataClass: cls);
      }
    } catch (_) {}
    Map<String, int?> est = const {};
    if (folders.isNotEmpty) {
      try {
        est = await engine.estimateChanges(folders);
      } catch (e) {
        AppLogger.debug('GetItemEstimate PIM: $e');
      }
    }
    _pimEstimates[account.id] = (at: DateTime.now(), est: est);
    return est;
  }

  /// Неподтверждённые ключи PIM: accountId → dataClass → ключ prefs → SyncKey.
  final Map<String, Map<String, Map<String, String>>> _pendingPimKeys = {};
  /// Папки с неподтверждёнными ключами: accountId → dataClass → folderId.
  final Map<String, Map<String, Set<String>>> _pendingPimFolders = {};

  /// Элементы класса [dataClass] сохранены в БД — подтвердить SyncKey.
  Future<void> commitPimSync(String accountId, String dataClass) async {
    final keys = _pendingPimKeys[accountId]?.remove(dataClass);
    _pendingPimFolders[accountId]?.remove(dataClass);
    if (keys == null) return;
    for (final e in keys.entries) {
      await _prefs.setString(e.key, e.value);
    }
  }

  /// Сохранить элементы не удалось — забыть неподтверждённые ключи и вернуть
  /// движок к сохранённым: следующая синхронизация получит те же элементы.
  void discardPimSync(String accountId, String dataClass) {
    _pendingPimKeys[accountId]?.remove(dataClass);
    final folders = _pendingPimFolders[accountId]?.remove(dataClass);
    _pimDeleted[accountId]?.remove(dataClass);
    final engine = _engines[accountId];
    if (folders == null || engine is! me.EasEngine) return;
    for (final f in folders) {
      engine.resetPimSyncKey(f);
    }
  }

  /// Перечитать контакты Exchange целиком при следующей синхронизации
  /// (1.6.32, «Пересинхронизировать контакты»): сервер пришлёт все контакты
  /// заново, лишние на телефоне уберутся.
  Future<void> requestFullContactsResync(AccountModel account) =>
      _prefs.setBool('contactsfull_req_${account.id}', true);

  /// Ящики, у которых контакты только что пришли целиком (см. выше).
  final Set<String> _contactsFull = {};

  /// Контакты ящика пришли целиком — можно убрать лишние (один раз).
  bool takeContactsFull(String accountId) => _contactsFull.remove(accountId);

  /// Перечитать календарь целиком при следующей синхронизации (после
  /// создания повторяющейся встречи в приложении).
  Future<void> requestFullCalendarResync(AccountModel account) =>
      _prefs.setBool('calfull_req_${account.id}', true);

  /// Начать синхронизацию почтовой папки заново (SyncKey «0»): сервер
  /// пришлёт всё содержимое окна синхронизации. Нужна, когда локальное
  /// изменение не применилось на сервере, а строку уже убрали (удаление) —
  /// иначе письмо, оставшееся на сервере, в клиент не вернётся.
  Future<void> resetMailFolderSync(AccountModel account, String folderId) => _serial(account.id, () async {
        await _prefs.remove(_tokKey(account.id, folderId, 'mail'));
        final engine = _engines[account.id];
        if (engine is me.EasEngine) engine.restoreMailSyncKey(folderId, '0');
      });

  /// Удалённые на сервере PIM-элементы: accountId → dataClass → id приложения.
  final Map<String, Map<String, Set<String>>> _pimDeleted = {};

  /// Забрать (и очистить) список удалённых на сервере элементов класса
  /// [dataClass] ('Calendar', 'Contacts', 'Tasks', 'Notes').
  List<String> takePimDeletions(String accountId, String dataClass) {
    final s = _pimDeleted[accountId]?.remove(dataClass);
    return s == null ? const [] : s.toList();
  }

  /// Календарь аккаунта перечитан целиком (раз в неделю): окно, в котором
  /// развёрнуты события. Синхронизация удаляет в этом окне события, которых
  /// в ответе не было, — раньше удалённые за это время встречи оставались.
  final Map<String, ({DateTime from, DateTime to})> _calendarFull = {};
  ({DateTime from, DateTime to})? takeCalendarFullWindow(String accountId) =>
      _calendarFull.remove(accountId);

  /// Главный список категорий Outlook (имена и цвета) — раз в сутки, у
  /// ящиков с EWS (1.6.5). Нужен, чтобы цвет встречи совпадал с Outlook и в
  /// окне встречи были категории ящика, а не угаданные по названию.
  Future<void> _refreshCategoryList(AccountModel account) async {
    if (!account.hasEwsExtras) return;
    final key = 'cat_master_at_${account.id}';
    final last = DateTime.tryParse(_prefs.getString(key) ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    final list = await _ews.getCategoryList(account).timeout(const Duration(seconds: 25), onTimeout: () => null);
    if (list == null) return;
    await _prefs.setString(key, DateTime.now().toIso8601String());
    if (list.isEmpty) return;
    await CategoryColors.save(_prefs, list);
    AppLogger.info('Категории Outlook: ${list.length} (${AppLogger.mask(account.email)})');
  }

  Future<List<CalendarEventModel>> getCalendarEvents(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    try {
      await _refreshCategoryList(account);
    } catch (_) {}
    final out = <CalendarEventModel>[];
    var allFull = true;
    final now = DateTime.now();
    // Окно развёртки повторяющихся событий: как у синхронизации календаря
    // (3 месяца назад) и на год вперёд.
    final windowStart = now.subtract(const Duration(days: 92));
    final windowEnd = now.add(const Duration(days: 366));
    for (final f in await _foldersOfType(account, me.MailFolderType.calendar)) {
      // Вхождения повторяющихся встреч разворачиваются на год вперёд в момент,
      // когда сервер присылает серию. Неизменная серия повторно не приходит,
      // поэтому раз в неделю (и сразу после создания серии в приложении —
      // ActiveSync не возвращает клиенту созданные им же элементы) календарь
      // перечитывается целиком, и окно развёртки сдвигается.
      final fullKey = 'calfull_${account.id}_${f.id}';
      final last = DateTime.tryParse(_prefs.getString(fullKey) ?? '');
      final forced = _prefs.getBool('calfull_req_${account.id}') ?? false;
      if (forced || last == null || now.difference(last).inDays >= 7) {
        await _prefs.remove(_tokKey(account.id, f.id, 'pim_Calendar'));
        if (engine is me.EasEngine) engine.resetPimSyncKey(f.id);
      }
      final items = await _pimSync(account, engine, f.id, 'Calendar');
      // Сервер заставил загрузить календарь заново (Status 3): пришёл весь
      // календарь с новыми ServerId — это полная выгрузка, прежние строки
      // убираются (иначе встречи двоились).
      final reinit = engine is me.EasEngine && engine.takePimReinit(f.id);
      if (forced || reinit || last == null || now.difference(last).inDays >= 7) {
        await _prefs.setString(fullKey, now.toIso8601String());
      } else {
        allFull = false;
      }
      for (final it in items) {
        if (it.deleted) continue;
        var start = _easDate(it.f('StartTime'));
        var end = _easDate(it.f('EndTime'));
        if (start == null || end == null) continue;
        // Весь день: полночь в поясе организатора, переданная в UTC, — в
        // другом поясе событие съезжало на день. Приводим к местным полуночам.
        if (it.f('AllDayEvent') == '1') {
          start = allDayDate(start);
          end = allDayDate(end);
          if (!end.isAfter(start)) end = DateTime(start.year, start.month, start.day + 1);
        }
        // Место встречи: до AS 16 — Calendar:Location, в AS 16 —
        // AirSyncBase:Location/DisplayName.
        final location = it.f('Location') ?? it.f('Location.DisplayName');
        CalendarEventModel make(String id, DateTime s, DateTime e, Map<String, String> o) =>
            CalendarEventModel(
              id: id,
              accountId: account.id,
              title: o['Subject'] ?? it.f('Subject') ?? '(без темы)',
              description: it.f('Body.Data') ?? it.f('Data'),
              location: o['Location'] ?? location,
              startTime: s,
              endTime: e,
              isAllDay: it.f('AllDayEvent') == '1',
              organizerEmail: it.f('Organizer_Email'),
              // Категория Outlook → цвет события (стандартные — по цвету в
              // названии, свои — постоянный цвет палитры).
              colorValue: CategoryColors.valueOf([if (it.f('Category') case final c?) c]),
              attendees: [
                for (final a in it.attendees)
                  if ((a['Email'] ?? '').isNotEmpty)
                    EventAttendee(email: a['Email']!, displayName: a['Name'], isRequired: a['Type'] != '2',
                        response: EventAttendee.responseFromEas(a['Status'])),
              ],
              // Calendar:Reminder — минуты до начала; нет элемента — без напоминания.
              reminders: [
                if (int.tryParse(it.f('Reminder') ?? '') case final m? when m >= 0)
                  EventReminder(minutesBefore: m),
              ],
              createdAt: now,
            );
        final rule = it.recurrence;
        if (rule == null || rule.isEmpty) {
          out.add(make('eas_${it.serverId}', start, end, const {}));
          continue;
        }
        // Повторяющаяся серия: ActiveSync присылает один элемент с правилом,
        // разворачиваем во вхождения. id вхождения — «eas_<ServerId>#<день>»:
        // по префиксу до «#» вхождения находятся при удалении/изменении серии.
        final occ = EasRecurrence.expand(
          start: start,
          end: end,
          rule: rule,
          exceptions: it.exceptions,
          windowStart: windowStart,
          windowEnd: windowEnd,
        );
        for (final o in occ) {
          out.add(make('eas_${it.serverId}#${EasRecurrence.dayKey(o.originalStart)}',
              o.start, o.end, o.overrides));
        }
      }
    }
    await _prefs.remove('calfull_req_${account.id}');
    // Порция не уместилась (MoreAvailable) — список неполный, удалять нельзя.
    if (allFull && !(engine is me.EasEngine && engine.lastPimMoreAvailable)) {
      _calendarFull[account.id] = (from: windowStart, to: windowEnd);
    }
    return out;
  }

  /// id события-вхождения повторяющейся серии (см. getCalendarEvents).
  static bool isOccurrenceId(String modelId) => modelId.contains('#');

  Future<List<ContactModel>> getContacts(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    final out = <ContactModel>[];
    final full = _prefs.getBool('contactsfull_req_${account.id}') ?? false;
    for (final f in await _foldersOfType(account, me.MailFolderType.contacts)) {
      if (full) {
        await _prefs.remove(_tokKey(account.id, f.id, 'pim_Contacts'));
        if (engine is me.EasEngine) engine.resetPimSyncKey(f.id);
      }
      for (final it in await _pimSync(account, engine, f.id, 'Contacts')) {
        if (it.deleted) continue;
        final email = _stripEmail(it.f('Email1Address'));
        final first = it.f('FirstName');
        final last = it.f('LastName');
        final display = it.f('FileAs') ??
            [first, last].where((e) => e != null && e.isNotEmpty).join(' ');
        out.add(ContactModel(
          id: 'eas_${it.serverId}',
          accountId: account.id,
          email: email ?? '',
          displayName: display.isEmpty ? (email ?? '(контакт)') : display,
          firstName: first,
          lastName: last,
          // Отчества нет отдельным полем — из «Фамилия Имя Отчество» (1.6.49).
          middleName: it.f('MiddleName') ?? middleFromDisplay(display, first, last),
          manager: it.f('ManagerName'),
          jobTitle: it.f('JobTitle'),
          department: it.f('Department'),
          company: it.f('CompanyName'),
          office: it.f('OfficeLocation'),
          phoneWork: it.f('BusinessPhoneNumber'),
          phoneMobile: it.f('MobilePhoneNumber'),
          // Фото контакта Exchange — JPEG в base64 (Contacts:Picture).
          avatarUrl: _pictureUri(it.f('Picture')),
          source: ContactSource.personal,
        ));
      }
    }
    if (full) {
      await _prefs.remove('contactsfull_req_${account.id}');
      _contactsFull.add(account.id);
      AppLogger.info('Контакты ${account.email}: перечитаны целиком — ${out.length}');
    }
    return out;
  }

  static String? _pictureUri(String? b64) {
    final v = b64?.replaceAll(RegExp(r'\s'), '');
    if (v == null || v.length < 32) return null;
    return 'data:image/jpeg;base64,$v';
  }

  Future<List<NoteModel>> getNotes(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    final out = <NoteModel>[];
    for (final f in await _foldersOfType(account, me.MailFolderType.notes)) {
      for (final it in await _pimSync(account, engine, f.id, 'Notes')) {
        if (it.deleted) continue;
        final mod = _easDate(it.f('LastModifiedDate')) ?? DateTime.now();
        out.add(NoteModel(
          id: 'eas_${it.serverId}',
          accountId: account.id,
          title: it.f('Subject') ?? '',
          body: it.f('Data') ?? '',
          serverId: it.serverId,
          createdAt: mod,
          modifiedAt: mod,
        ));
      }
    }
    return out;
  }

  Future<List<TaskModel>> getTasks(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) return const [];
    final out = <TaskModel>[];
    for (final f in await _foldersOfType(account, me.MailFolderType.tasks)) {
      for (final it in await _pimSync(account, engine, f.id, 'Tasks')) {
        if (it.deleted) continue;
        final imp = it.f('Importance');
        out.add(TaskModel(
          id: 'eas_${it.serverId}',
          accountId: account.id,
          title: it.f('Subject') ?? '',
          description: it.f('Body.Data'),
          status: it.f('Complete') == '1' ? TaskStatus.completed : TaskStatus.pending,
          priority: imp == '2'
              ? TaskPriority.high
              : (imp == '0' ? TaskPriority.low : TaskPriority.normal),
          createdAt: DateTime.now(),
          dueDate: _easDate(it.f('UtcDueDate') ?? it.f('DueDate')),
          completedAt: _easDate(it.f('DateCompleted')),
          // Напоминание Outlook (MS-ASTASK ReminderSet/ReminderTime).
          reminderAt: it.f('ReminderSet') == '1' ? _easDate(it.f('ReminderTime')) : null,
        ));
      }
    }
    return out;
  }

  /// Разбор даты EAS: ISO 8601 или формат yyyyMMddTHHmmssZ.
  DateTime? _easDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {}
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})').firstMatch(s);
    if (m != null) {
      return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
              int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!))
          .toLocal();
    }
    return null;
  }

  String? _stripEmail(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'<([^>]+)>').firstMatch(raw);
    return (m != null ? m.group(1) : raw)?.trim();
  }

  // ──────────────────── PIM: запись (создание/изменение/удаление) ────────────────────

  /// Формат даты EAS: yyyyMMddTHHmmssZ (UTC).
  /// День события «на весь день»: сервер отдаёт полночь в поясе
  /// организатора, переведённую в UTC (для UTC+5 — 19:00Z накануне). Пояс
  /// организатора неизвестен, поэтому округляем к ближайшей полуночи UTC —
  /// верно для поясов от −11 до +11 — и возвращаем местную полночь той даты.
  static DateTime allDayDate(DateTime t) {
    final u = t.toUtc();
    final d = u.hour >= 12 ? DateTime.utc(u.year, u.month, u.day + 1) : DateTime.utc(u.year, u.month, u.day);
    return DateTime(d.year, d.month, d.day);
  }

  /// TIME_ZONE_INFORMATION (MS-ASDTYPE, 172 байта) для пояса устройства:
  /// Bias = −смещение в минутах, без перехода на летнее время. Раньше всегда
  /// уходил UTC — и событие на весь день, созданное в UTC+5, сервер видел как
  /// 19:00–19:00 по UTC (в Outlook — на два дня или со сдвигом).
  ///
  /// 1.6.2: и имя пояса Windows (StandardName/DaylightName). По одному
  /// смещению Exchange брал первый пояс с ним — «Ашхабад, Ташкент» вместо
  /// «Екатеринбурга» в приглашении у участников (замечание 13.10.2026).
  static String easTimeZone(DateTime at, {String? windowsName}) {
    final b = ByteData(172);
    b.setInt32(0, -at.toLocal().timeZoneOffset.inMinutes, Endian.little);
    final names = DeviceTimeZone.tziNames(windowsName ?? DeviceTimeZone.windowsName());
    if (names != null) {
      // StandardName — WCHAR[32] со смещения 4, DaylightName — со смещения 88.
      // 1.6.4: как в реестре Windows — «… Standard Time» / «… Daylight Time»
      // (в 1.6.2 в оба поля шло одно имя). Если сервер такое не примет,
      // EasEngine повторит запрос без имён.
      for (final (base, name) in [(4, names.std), (88, names.dlt)]) {
        final units = name.codeUnits.take(31).toList();
        for (var i = 0; i < units.length; i++) {
          b.setUint16(base + i * 2, units[i], Endian.little);
        }
      }
    }
    return base64.encode(b.buffer.asUint8List());
  }

  String _fmtEas(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Дата задачи EAS (UTC): 2026-10-01T09:00:00.000Z.
  /// UTC в формате MS-ASDTYPE (ровно три знака долей секунды: 2026-10-01T10:00:00.000Z).
  /// toIso8601String() печатает и микросекунды, если они есть, — такой
  /// формат сервер отвергает.
  String _isoEas(DateTime dt) {
    final u = dt.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second).toIso8601String();
  }

  /// «Локальная» дата задачи EAS: локальное время в том же формате с Z
  /// (так её передают Outlook и Exchange для DueDate/StartDate).
  String _isoEasLocal(DateTime dt) {
    final l = dt.toLocal();
    return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second).toIso8601String();
  }

  /// Язык названий стандартных категорий Outlook — по языку приложения
  /// (названия в Exchange локализованы по языку ящика; обычно совпадают).
  bool _mailboxRussian() {
    try {
      final l = _ref?.read(settingsProvider).locale;
      if (l != null) return l.languageCode == 'ru';
    } catch (_) {}
    return true;
  }

  /// ItemId EWS — длинная строка base64; локальные id (uuid) короче.
  static bool _isEwsItemId(String id) => id.length > 60 && !id.startsWith('eas_');

  /// Убирает префикс 'eas_' из id модели приложения, получая серверный ServerId.
  String _serverId(String modelId) {
    var id = modelId.startsWith('eas_') ? modelId.substring(4) : modelId;
    // Вхождение повторяющейся серии: «<ServerId>#<день>» — элемент на сервере один.
    final hash = id.indexOf('#');
    if (hash >= 0) id = id.substring(0, hash);
    return id;
  }

  Future<me.EasEngine?> _easEngine(AccountModel account) async {
    // Только для аккаунтов ActiveSync. Раньше подключение создавалось для
    // ЛЮБОГО аккаунта: сохранение задачи у Gmail открывало IMAP-сессию, а у
    // EWS-аккаунта — перебор EWS(Basic)→EAS с лишними попытками входа.
    if (!account.usesEas) return null;
    final engine = await _engineFor(account);
    return engine is me.EasEngine ? engine : null;
  }

  /// Запись в PIM-папку ActiveSync с правильным SyncKey: перед командой —
  /// ключ из общего хранилища (его могла сдвинуть фоновая синхронизация в
  /// другом изоляте), после — новый ключ туда же. Раньше ключ после записи
  /// оставался только в памяти, и следующая синхронизация шла со старым:
  /// сервер повторял прошлый ответ или отвечал Status 3 (папка заново).
  Future<T> _pimKeyed<T>(AccountModel account, me.EasEngine eas, String fid, String dataClass,
      Future<T> Function() op) async {
    try {
      await _prefs.reload();
    } catch (_) {}
    final prefKey = _tokKey(account.id, fid, 'pim_$dataClass');
    final pending = _pendingPimKeys[account.id]?[dataClass]?[prefKey];
    final saved = pending ?? _prefs.getString(prefKey);
    if (saved != null && saved.isNotEmpty && saved != '0') eas.restorePimSyncKey(fid, saved);
    final r = await op();
    final nk = eas.pimSyncKeyFor(fid);
    if (nk != null && nk.isNotEmpty && nk != '0' && nk != saved) {
      if (pending != null) {
        _pendingPimKeys[account.id]![dataClass]![prefKey] = nk;
      } else {
        await _prefs.setString(prefKey, nk);
      }
    }
    return r;
  }

  Future<String?> _pimFolderId(AccountModel account, me.MailFolderType type) async {
    final folders = await _foldersOfType(account, type);
    return folders.isEmpty ? null : folders.first.id;
  }

  /// [attachments] (1.6.12) — файлы письма, из которого создаётся встреча:
  /// ActiveSync 16 передаёт их вместе с новой встречей.
  Future<String?> saveEvent(AccountModel account, CalendarEventModel e,
      {List<({String name, String? contentType, Uint8List bytes})> attachments = const []}) async {
    // Отдельное вхождение серии в ActiveSync меняется через исключение
    // повторения; изменение «всего элемента» сдвинуло бы всю серию.
    if (isOccurrenceId(e.id)) {
      throw UnsupportedError('Изменение отдельного вхождения повторяющейся встречи '
          'пока доступно только в Outlook');
    }
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, me.MailFolderType.calendar);
    if (eas == null || fid == null) return null;
    final isNew = !e.id.startsWith('eas_');
    final sid = await _pimKeyed(account, eas, fid, 'Calendar', () => eas.upsertPim(fid,
        dataClass: 'Calendar',
        serverId: isNew ? null : _serverId(e.id),
        fields: {
          'TimeZone': easTimeZone(e.startTime),
          'Subject': e.title,
          'StartTime': _fmtEas(e.startTime),
          'EndTime': _fmtEas(e.endTime),
          'Location': e.location,
          'AllDayEvent': e.isAllDay ? '1' : '0',
          if (isNew) 'BusyStatus': '2',
          if (e.reminders.isNotEmpty) 'Reminder': '${e.reminders.first.minutesBefore}',
          // «Приватная встреча» (1.6.4): раньше не передавалась.
          'Sensitivity': e.isPrivate ? '2' : '0',
          // Собрание (1.6.7): только отличия от умолчаний сервера.
          if (isNew && e.attendees.isNotEmpty && !e.allowNewTimeProposal) 'DisallowNewTimeProposal': '1',
          if (isNew && e.attendees.isNotEmpty && !e.responseRequested) 'ResponseRequested': '0',
        },
        body: e.description,
        // Цвет — стандартной категорией Outlook (1.6.4). Важности у встреч в
        // ActiveSync нет (MS-ASCAL) — она уходит только через EWS.
        categories: [
          if (CategoryColors.categoryFor(e.colorValue, russian: _mailboxRussian()) case final c?) c,
        ],
        // Участников и повторение передаём только при создании: у существующей
        // встречи они «призрачные» (Supported) и сохраняются сервером сами.
        attendees: isNew
            ? [
                for (final a in e.attendees)
                  if (a.email.isNotEmpty)
                    (email: a.email, name: a.displayName, required: a.isRequired),
              ]
            : const [],
        recurrence: isNew ? _easRecurrenceRule(e) : null,
        attachments: isNew ? attachments : const []));
    return sid;
  }

  /// Правило повторения EAS (MS-ASCAL) по выбору в форме события.
  Map<String, String>? _easRecurrenceRule(CalendarEventModel e) {
    final l = e.startTime.toLocal();
    final dowBit = '${1 << (l.weekday % 7)}';
    switch (e.recurrence) {
      case RecurrenceType.none:
        return null;
      case RecurrenceType.daily:
        return {'Type': '0', 'Interval': '1'};
      case RecurrenceType.weekly:
        return {'Type': '1', 'Interval': '1', 'DayOfWeek': dowBit};
      case RecurrenceType.biweekly:
        return {'Type': '1', 'Interval': '2', 'DayOfWeek': dowBit};
      case RecurrenceType.monthly:
        return {'Type': '2', 'Interval': '1', 'DayOfMonth': '${l.day}'};
      case RecurrenceType.yearly:
        return {'Type': '5', 'Interval': '1', 'DayOfMonth': '${l.day}', 'MonthOfYear': '${l.month}'};
    }
  }

  Future<String?> saveTask(AccountModel account, TaskModel t) async {
    // CalDAV (списки дел Яндекса, Mail.ru и др.): полный id «davt_…».
    if (_usesDav(account)) {
      final auth = await _davAuth(account);
      if (auth == null) return null;
      return DavPimService().saveTask(account, auth, t);
    }
    // EWS: задача с сервера (длинный ItemId) — UpdateItem, иначе создание.
    if (!account.usesEas && _ewsPrimary(account)) {
      if (_isEwsItemId(t.id)) {
        final ok = await _ews.updateTask(account, t);
        if (!ok) throw Exception('EWS: задача не изменена');
        return t.id;
      }
      return _ews.createTask(account, t);
    }
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, me.MailFolderType.tasks);
    if (eas == null || fid == null) return null;
    return _pimKeyed(account, eas, fid, 'Tasks', () => eas.upsertPim(fid,
        dataClass: 'Tasks',
        serverId: t.id.startsWith('eas_') ? _serverId(t.id) : null,
        fields: {
          'Subject': t.title,
          'Importance': t.priority == TaskPriority.high
              ? '2'
              : (t.priority == TaskPriority.low ? '0' : '1'),
          'Complete': t.status == TaskStatus.completed ? '1' : '0',
          // MS-ASTASK: даты задач — ISO 8601 с миллисекундами (не компактный
          // формат календаря); DueDate передаётся только парой с UtcDueDate,
          // а Complete=1 — вместе с DateCompleted. Иначе сервер отвергает.
          if (t.status == TaskStatus.completed)
            'DateCompleted': _isoEas(t.completedAt ?? DateTime.now()),
          if (t.dueDate != null) 'DueDate': _isoEasLocal(t.dueDate!),
          if (t.dueDate != null) 'UtcDueDate': _isoEas(t.dueDate!),
          // Change без Supported заменяет задачу целиком — напоминание
          // передаём всегда (выключенное тоже), иначе сервер его сотрёт или
          // оставит старое.
          'ReminderSet': t.reminderAt != null ? '1' : '0',
          if (t.reminderAt != null) 'ReminderTime': _isoEas(t.reminderAt!),
        },
        body: t.description));
  }

  Future<String?> saveNote(AccountModel account, NoteModel n) async {
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, me.MailFolderType.notes);
    if (eas == null || fid == null) return null;
    return _pimKeyed(account, eas, fid, 'Notes', () => eas.upsertPim(fid,
        dataClass: 'Notes',
        serverId: n.serverId,
        fields: {'Subject': n.title},
        body: n.body));
  }

  Future<String?> saveContact(AccountModel account, ContactModel c) async {
    // CardDAV (Google, Яндекс, Yahoo): создание и правка. Возвращается
    // полный id модели («dav_<аккаунт>_<ключ>»), а не ServerId.
    if (_usesDavContacts(account)) {
      final auth = await _davAuth(account, contacts: true);
      if (auth == null) return null;
      return DavPimService().saveContact(account, auth, c);
    }
    // EWS: создание — createContactEntry; правка контакта EWS пока остаётся
    // локальной (повторное создание при каждой правке плодило бы дубли).
    if (!account.usesEas) return null;
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, me.MailFolderType.contacts);
    if (eas == null || fid == null) return null;
    return _pimKeyed(account, eas, fid, 'Contacts', () => eas.upsertPim(fid,
        dataClass: 'Contacts',
        serverId: c.id.startsWith('eas_') ? _serverId(c.id) : null,
        fields: {
          'FirstName': c.firstName,
          'LastName': c.lastName,
          'MiddleName': c.middleName,
          'Email1Address': c.email.isEmpty ? null : c.email,
          'CompanyName': c.company,
          'JobTitle': c.jobTitle,
          'Department': c.department,
          'OfficeLocation': c.office,
          'BusinessPhoneNumber': c.phoneWork,
          'MobilePhoneNumber': c.phoneMobile,
          // Руководитель — в другом пространстве имён ActiveSync (1.6.49).
          'Contacts2:ManagerName': c.manager,
          // «Отображать как» — иначе после правки имени Outlook продолжал
          // показывать старое (FileAs не входит в Supported и не стирается).
          if (c.displayName.isNotEmpty) 'FileAs': c.displayName,
        }));
  }

  /// Выгрузить контакт из БД (все поля строки). Созданный офлайн контакт
  /// после Add получает серверный ServerId — строка переименовывается в
  /// «eas_<ServerId>», иначе синхронизация добавила бы второй такой же, а
  /// следующая правка снова ушла бы как Add (дубль на сервере).
  Future<void> pushContact(AccountModel account, String id) async {
    final db = _ref?.read(databaseProvider);
    if (db == null) return;
    final row = await (db.select(db.contacts)
          ..where((c) => c.id.equals(id) & c.accountId.equals(account.id)))
        .getSingleOrNull();
    if (row == null) return;
    final sid = await saveContact(account, contactFromRow(row));
    if (sid == null || id.startsWith('eas_')) return;
    // CardDAV возвращает готовый id (ключ мог смениться вместе с e-mail).
    final newId = _usesDavContacts(account) ? sid : 'eas_$sid';
    if (newId == id) return;
    await db.transaction(() async {
      final exists = await (db.select(db.contacts)
            ..where((c) => c.id.equals(newId) & c.accountId.equals(account.id)))
          .getSingleOrNull();
      if (exists != null) {
        await (db.delete(db.contacts)
              ..where((c) => c.id.equals(id) & c.accountId.equals(account.id)))
            .go();
      } else {
        await (db.update(db.contacts)
              ..where((c) => c.id.equals(id) & c.accountId.equals(account.id)))
            .write(ContactsCompanion(id: Value(newId)));
      }
      await (db.update(db.syncQueue)..where((q) => q.targetId.equals(id)))
          .write(SyncQueueCompanion(targetId: Value(newId)));
    });
  }

  /// То же для задачи (см. [pushContact]).
  Future<void> pushTask(AccountModel account, String id) async {
    final db = _ref?.read(databaseProvider);
    if (db == null) return;
    final row = await (db.select(db.tasks)
          ..where((t) => t.id.equals(id) & t.accountId.equals(account.id)))
        .getSingleOrNull();
    if (row == null) return;
    final sid = await saveTask(account, taskFromRow(row));
    if (sid == null || id.startsWith('eas_') || sid == id) return;
    // ActiveSync — «eas_<ServerId>», EWS — сам ItemId (как при синхронизации).
    final newId = account.usesEas ? 'eas_$sid' : sid;
    await db.transaction(() async {
      final exists = await (db.select(db.tasks)
            ..where((t) => t.id.equals(newId) & t.accountId.equals(account.id)))
          .getSingleOrNull();
      if (exists != null) {
        await (db.delete(db.tasks)
              ..where((t) => t.id.equals(id) & t.accountId.equals(account.id)))
            .go();
      } else {
        await (db.update(db.tasks)
              ..where((t) => t.id.equals(id) & t.accountId.equals(account.id)))
            .write(TasksCompanion(id: Value(newId)));
      }
      await (db.update(db.syncQueue)..where((q) => q.targetId.equals(id)))
          .write(SyncQueueCompanion(targetId: Value(newId)));
    });
  }

  Future<void> deletePim(AccountModel account, me.MailFolderType type, String modelId) async {
    if (!account.usesEas && _ewsPrimary(account)) {
      // EWS: у элемента свой ItemId, папка не нужна.
      switch (type) {
        case me.MailFolderType.calendar:
          await _ews.deleteCalendarEvent(account, itemId: modelId);
          return;
        case me.MailFolderType.contacts:
          await _ews.deleteContact(account, itemId: modelId);
          return;
        case me.MailFolderType.notes:
          await _ews.deleteNote(account, itemId: modelId);
          return;
        case me.MailFolderType.tasks:
          if (_isEwsItemId(modelId)) await _ews.deleteTask(account, itemId: modelId);
          return;
        default:
          return;
      }
    }
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, type);
    if (eas == null || fid == null) return;
    const cls = {
      me.MailFolderType.calendar: 'Calendar',
      me.MailFolderType.contacts: 'Contacts',
      me.MailFolderType.tasks: 'Tasks',
      me.MailFolderType.notes: 'Notes',
    };
    final dataClass = cls[type] ?? 'Calendar';
    await _pimKeyed(account, eas, fid, dataClass,
        () => eas.deletePim(fid, _serverId(modelId), dataClass: dataClass));
  }

  /// Создать/изменить заметку (примитивы — без связки с моделью провайдера).
  Future<String?> createOrUpdateNote(AccountModel account,
      {String? serverId, required String title, required String body}) async {
    if (!account.usesEas && _ewsPrimary(account)) {
      if (serverId != null) {
        final ok = await _ews.updateNote(account, itemId: serverId, title: title, body: body);
        if (!ok) throw Exception('EWS: заметка не изменена');
        return serverId;
      }
      final id = await _ews.createNote(account, title: title, body: body);
      return id.isEmpty ? null : id;
    }
    final eas = await _easEngine(account);
    final fid = await _pimFolderId(account, me.MailFolderType.notes);
    if (eas == null || fid == null) return null;
    return _pimKeyed(account, eas, fid, 'Notes',
        () => eas.upsertPim(fid, dataClass: 'Notes', serverId: serverId, fields: {'Subject': title}, body: body));
  }

  /// Выгрузить заметки аккаунта, изменённые локально: созданные (получают
  /// ServerId и id строки как у синхронизированных — без этого синхронизация
  /// добавляла вторую такую же), изменённые (раньше правка на сервер не
  /// уходила вовсе) и удалённые (раньше при сбое оставались навсегда).
  /// Ошибка сети прерывает выгрузку — строки ждут следующей попытки.
  Future<void> pushPendingNotes(AccountModel account) async {
    final db = _ref?.read(databaseProvider);
    if (db == null) return;
    final eas = account.usesEas;
    if (!eas && !_ewsPrimary(account)) {
      // IMAP (1.6.2): заметки — в папке «Notes» в формате Apple Notes.
      final imap = _ref?.read(imapServiceProvider);
      if (imap != null && (account.isImap || account.isOAuth)) {
        await _pushImapNotes(account, db, imap);
        return;
      }
      // Ящик без серверных заметок: удалённые просто убираем.
      await (db.delete(db.notes)
            ..where((n) => n.accountId.equals(account.id) & n.isDeleted.equals(true)))
          .go();
      return;
    }
    final rows = await (db.select(db.notes)
          ..where((n) => n.accountId.equals(account.id) & n.isLocallyModified.equals(true)))
        .get();
    for (final n in rows) {
      final sid = n.serverId;
      String? newSid;
      try {
        if (n.isDeleted) {
          if (sid != null && sid.isNotEmpty) await deleteNoteServer(account, sid);
          await (db.delete(db.notes)..where((t) => t.id.equals(n.id))).go();
          continue;
        }
        // Новая — создание, с ServerId — изменение (EAS Change, EWS UpdateItem).
        newSid = await createOrUpdateNote(account,
            serverId: (sid == null || sid.isEmpty) ? null : sid, title: n.title, body: n.body);
      } catch (e) {
        // Сервер окончательно отверг элемент (4 — протокол, 6 — преобразование,
        // 7 — конфликт, 8 — элемент не найден): повтор ничего не даст, а
        // раньше повторялся при каждой синхронизации и мешал ей. Заметка
        // остаётся на устройстве; удалённую на сервере — просто убираем.
        final m = RegExp(r'элемент: Status=(\d+)').firstMatch('$e');
        final code = m?.group(1);
        if (code != null && const {'4', '6', '7', '8'}.contains(code)) {
          AppLogger.warning('Заметка ${n.id}: сервер отверг (Status=$code) — остаётся только на устройстве');
          if (n.isDeleted) {
            await (db.delete(db.notes)..where((t) => t.id.equals(n.id))).go();
          } else {
            await (db.update(db.notes)..where((t) => t.id.equals(n.id)))
                .write(const NotesCompanion(isLocallyModified: Value(false)));
          }
          continue;
        }
        rethrow;
      }
      if (newSid == null) continue;
      final newId = noteRowId(eas: eas, accountId: account.id, serverId: newSid);
      await db.transaction(() async {
        if (newId != n.id) {
          await (db.delete(db.notes)..where((t) => t.id.equals(newId))).go();
        }
        await (db.update(db.notes)..where((t) => t.id.equals(n.id))).write(NotesCompanion(
          id: Value(newId),
          serverId: Value(newSid),
          isLocallyModified: const Value(false),
        ));
      });
    }
  }

  /// Выгрузка заметок IMAP: новая и изменённая — новым письмом в «Notes»
  /// (прежняя копия удаляется), удалённая — удаляется на сервере. Ошибка
  /// сети прерывает выгрузку — строки ждут следующей попытки.
  Future<void> _pushImapNotes(AccountModel account, AppDatabase db, ImapService imap) async {
    final rows = await (db.select(db.notes)
          ..where((n) => n.accountId.equals(account.id) & n.isLocallyModified.equals(true)))
        .get();
    for (final n in rows) {
      final sid = n.serverId;
      if (n.isDeleted) {
        if (sid != null && sid.isNotEmpty) await imap.deleteImapNote(account, sid);
        await (db.delete(db.notes)..where((t) => t.id.equals(n.id))).go();
        continue;
      }
      final uuid = await imap.saveImapNote(account,
          uuid: (sid == null || sid.isEmpty) ? null : sid, title: n.title, body: n.body);
      final newId = imapNoteRowId(account.id, uuid);
      await db.transaction(() async {
        if (newId != n.id) await (db.delete(db.notes)..where((t) => t.id.equals(newId))).go();
        await (db.update(db.notes)..where((t) => t.id.equals(n.id))).write(NotesCompanion(
          id: Value(newId),
          serverId: Value(uuid),
          isLocallyModified: const Value(false),
        ));
      });
    }
  }

  Future<void> deleteNoteServer(AccountModel account, String serverId) =>
      deletePim(account, me.MailFolderType.notes, serverId);

  /// Создать/изменить контакт (примитивы).
  Future<String?> createOrUpdateContact(AccountModel account, ContactModel c) =>
      saveContact(account, c);

  Future<void> deleteEventServer(AccountModel account, String modelId) =>
      deletePim(account, me.MailFolderType.calendar, modelId);

  Future<void> deleteTaskServer(AccountModel account, String modelId) async {
    if (_usesDav(account)) {
      final auth = await _davAuth(account);
      if (auth == null) throw Exception('Нет доступа к списку дел');
      await DavPimService().deleteTask(account, auth, modelId);
      return;
    }
    await deletePim(account, me.MailFolderType.tasks, modelId);
  }

  Future<void> deleteContactServer(AccountModel account, String modelId) =>
      deletePim(account, me.MailFolderType.contacts, modelId);

  // ════════════ Фасад EWS-специфичных операций ════════════
  // UI зовёт только этот сервис. Внутри: EAS → движок, EWS → ews_service,
  // прочие — операция недоступна (UI её и не показывает).
  // Общий экземпляр с синхронизацией: одно NTLM-подключение и один кэш
  // адреса EWS на аккаунт (раньше у фасада был свой — двойные входы).
  late final EwsService _ews =
      _ref?.read(ewsServiceProvider) ?? EwsService(secureStorage: _secureStorage);

  /// Доступны ли EWS-операции. Учитывает гибридный режим: аккаунт может
  /// работать по EAS (Direct Push), но иметь адрес EWS для функций, которых
  /// в ActiveSync нет — автоответы, занятость коллег, категории Outlook,
  /// серверные правила, отзыв письма. Раньше проверка была только на основной
  /// транспорт, и EAS-аккаунты этих возможностей лишались.
  bool _isEws(AccountModel a) => a.hasEwsExtras || a.isExchange;

  /// EWS — ОСНОВНОЙ транспорт аккаунта. Нужен для операций над конкретными
  /// письмами и папками: их идентификаторы получены тем транспортом, которым
  /// шла синхронизация. В гибридном режиме (EAS + EWS) письма и папки пришли
  /// по EAS — у них ServerId вида «5:12», а EWS ждёт свой ItemId/FolderId.
  /// Отправить EAS-идентификатор в EWS значит гарантированно получить ошибку
  /// (а для пересылки — ещё и откат на обычную отправку без вложений).
  /// Поэтому EWS-«спутник» используется только для операций без ссылок на
  /// элементы: автоответ, занятость, разрешение имён, уведомление о прочтении.
  bool _ewsPrimary(AccountModel a) => a.usesEws || a.isExchange;

  /// Автоответ (Out-of-Office): ActiveSync — команда Settings движка,
  /// EWS — ews_service.
  Future<OofSettings?> getOof(AccountModel account) async {
    if (account.usesEas) {
      final eas = await _easEngine(account);
      final o = await eas?.getOof();
      if (o == null) return null;
      return OofSettings(
        enabled: o.state != 0,
        internalReply: o.internalReply ?? '',
        externalReply: o.externalReply ?? '',
        scheduled: o.state == 2,
        start: o.start?.toLocal(),
        end: o.end?.toLocal(),
        externalOn: o.externalEnabled,
      );
    }
    return _isEws(account) ? _ews.getOofSettings(account) : null;
  }

  Future<bool> setOof(AccountModel account, {
    required bool enabled,
    DateTime? startTime,
    DateTime? endTime,
    String? internalReply,
    String? externalReply,
    bool sendToExternal = false,
  }) async {
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return false;
      final scheduled = enabled && startTime != null && endTime != null;
      return eas.setOof(me.EasOof(
        state: !enabled ? 0 : (scheduled ? 2 : 1),
        start: startTime,
        end: endTime,
        internalReply: internalReply,
        externalReply: externalReply,
        externalEnabled: sendToExternal,
      ));
    }
    if (!_isEws(account)) return false;
    return _ews.setOofSettings(account,
        enabled: enabled, startTime: startTime, endTime: endTime,
        internalReply: internalReply, externalReply: externalReply,
        sendToExternal: sendToExternal);
  }

  /// Владелец ящика по данным сервера ActiveSync: все адреса и имя.
  Future<me.EasUserInfo?> easUserInfo(AccountModel account) async {
    if (!account.usesEas) return null;
    final eas = await _easEngine(account);
    return eas?.getUserInformation();
  }

  /// Фото человека из адресной книги организации: в высоком качестве через
  /// EWS (1.6.49), иначе миниатюра ActiveSync 14.1+ (GAL с Picture). data URI
  /// или null (нет фото, нет в книге, старый сервер).
  Future<String?> lookupGalPhoto(AccountModel account, String email) async {
    // 1.6.49: сначала фото в высоком качестве (EWS), миниатюра ActiveSync —
    // если его нет.
    final hi = await lookupHiResPhoto(account, email);
    if (hi != null) return hi;
    if (!account.usesEas) return null;
    final eas = await _easEngine(account);
    if (eas == null) return null;
    final e = email.toLowerCase();
    final list = await eas.searchGal(e, maxResults: 3, withPictures: true);
    for (final g in list) {
      if (g.email.toLowerCase() == e) return _pictureUri(g.picture);
    }
    return null;
  }

  /// Карточка человека из адресной книги организации: должность, отдел,
  /// телефоны, кабинет, руководитель, фото. null — нет в книге или ящик не
  /// Exchange. ActiveSync даёт фото, должность и телефоны; отдел и
  /// руководителя — EWS (у EAS-ящика — если известен адрес EWS).
  Future<ContactModel?> lookupPerson(AccountModel account, String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !e.contains('@')) return null;
    ContactModel? out;
    try {
      if (account.usesEas) {
        final eas = await _easEngine(account);
        if (eas != null) {
          final list = await eas.searchGal(e, maxResults: 5, withPictures: true);
          final g = list.where((g) => g.email.toLowerCase() == e).firstOrNull;
          if (g != null) {
            out = ContactModel(
              id: 'gal_${e.hashCode}',
              accountId: account.id,
              email: g.email,
              displayName: g.displayName,
              firstName: g.firstName,
              lastName: g.lastName,
              // В адресной книге ActiveSync отчества нет, но в имени
              // «Фамилия Имя Отчество» оно есть (1.6.49).
              middleName: middleFromDisplay(g.displayName, g.firstName, g.lastName),
              company: g.company,
              jobTitle: g.title,
              phoneWork: g.phone,
              phoneMobile: g.mobilePhone,
              office: g.office,
              avatarUrl: _pictureUri(g.picture),
              source: ContactSource.exchangeGal,
            );
          }
        }
      }
      // Отдел, руководитель, кабинет — только в адресной книге EWS. У ящика
      // ActiveSync — по адресу EWS того же сервера, если он отвечает (1.6.49).
      final dir = await _directoryEws(account);
      if (dir != null) {
        final list = await _ews.resolveNames(dir, query: e, maxResults: 5);
        final m = list.where((c) => c.email.toLowerCase() == e).firstOrNull;
        if (m != null) out = out == null ? m : _mergePerson(out, m);
      }
      // Фото в высоком качестве (1.6.49) — поверх миниатюры ActiveSync.
      final found = out;
      if (found != null && dir != null) {
        final hi = await lookupHiResPhoto(account, e);
        if (hi != null) {
          out = _mergePerson(
              ContactModel(id: found.id, accountId: found.accountId, email: found.email, displayName: found.displayName, avatarUrl: hi),
              found);
        }
      }
    } catch (err) {
      AppLogger.warning('Карточка человека из адресной книги: $err');
    }
    return out;
  }

  /// Запись адресной книги организации без фото — для сверки контактов
  /// коллег (1.8.0+118, `SyncService._refreshColleagues`). null — такого
  /// адреса в адресной книге нет; сбой связи — исключение (контакт сверится в
  /// другой раз). Через EWS (там есть отдел и руководитель), без EWS — поиск
  /// ActiveSync по адресной книге.
  Future<ContactModel?> directoryEntry(AccountModel account, String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !e.contains('@')) return null;
    final dir = await _directoryEws(account);
    if (dir != null) {
      final list = await _ews.resolveNames(dir, query: e, maxResults: 5, directoryOnly: true);
      return list.where((c) => c.email.toLowerCase() == e).firstOrNull;
    }
    if (!account.usesEas) return null;
    final eas = await _easEngine(account);
    if (eas == null) throw StateError('ActiveSync недоступен');
    final g = (await eas.searchGal(e, maxResults: 5)).where((g) => g.email.toLowerCase() == e).firstOrNull;
    if (g == null) return null;
    return ContactModel(
      id: 'gal_${e.hashCode}',
      accountId: account.id,
      email: g.email,
      displayName: g.displayName,
      firstName: g.firstName,
      lastName: g.lastName,
      company: g.company,
      jobTitle: g.title,
      phoneWork: g.phone,
      phoneMobile: g.mobilePhone,
      office: g.office,
      source: ContactSource.exchangeGal,
    );
  }

  /// Отчество из имени «Фамилия Имя Отчество» (1.6.49): в адресной книге
  /// ActiveSync и у контактов Outlook отдельного поля обычно нет, а в
  /// отображаемом имени оно есть. Третье слово — отчество, если первые два —
  /// фамилия и имя (или, без них, если слово похоже на отчество).
  static String? middleFromDisplay(String? display, String? first, String? last) {
    final words = (display ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length != 3 || words.any((w) => w.contains('@'))) return null;
    String low(String? s) => (s ?? '').trim().toLowerCase();
    final f = low(first), l = low(last);
    if (f.isNotEmpty && l.isNotEmpty) {
      return (low(words[0]) == l && low(words[1]) == f) ? words[2] : null;
    }
    final m = low(words[2]);
    const ends = ['вич', 'вна', 'ична', 'инична', 'оглы', 'кызы'];
    return ends.any(m.endsWith) ? words[2] : null;
  }

  /// Адресная книга EWS для ящика ActiveSync (1.6.49). В адресной книге
  /// ActiveSync нет отдела, руководителя и кабинета — они есть только в EWS
  /// (ResolveNames). Адрес EWS того же сервера пробуем раз; ответил — он
  /// запоминается и служит только для поиска людей (почта, календарь и
  /// остальное по-прежнему идут по ActiveSync); не ответил — повтор через
  /// неделю. Ящику с отказом входа не пробуем: лишние попытки входа
  /// блокируют учётную запись домена.
  final Map<String, Future<AccountModel?>> _dirProbe = {};

  Future<AccountModel?> _directoryEws(AccountModel account) async {
    if (account.hasEwsExtras || account.isExchange) return account;
    if (!account.usesEas || account.authFailedAt != null) return null;
    final host = (account.exchangeServer ?? '').trim();
    if (host.isEmpty) return null;
    final key = 'ews_dir_${account.id}';
    final saved = _prefs.getString(key) ?? '';
    if (saved.startsWith('https://')) return account.copyWith(ewsUrl: saved);
    final at = int.tryParse(saved.replaceFirst('none:', ''));
    if (at != null && DateTime.now().millisecondsSinceEpoch - at < const Duration(days: 7).inMilliseconds) {
      return null;
    }
    return _dirProbe[account.id] ??= () async {
      final url = EwsService.ewsUrlFromServer(host);
      final probe = account.copyWith(ewsUrl: url);
      try {
        await _ews.resolveNames(probe, query: account.email, maxResults: 1).timeout(const Duration(seconds: 25));
        await _prefs.setString(key, url);
        AppLogger.info('Адресная книга EWS для ${AppLogger.mask(account.email)}: доступна — отдел, руководитель');
        return probe;
      } catch (err) {
        await _prefs.setString(key, 'none:${DateTime.now().millisecondsSinceEpoch}');
        AppLogger.info('Адресная книга EWS для ${AppLogger.mask(account.email)}: недоступна ($err), повтор через неделю');
        return null;
      } finally {
        unawaited(Future<void>.delayed(const Duration(seconds: 1), () => _dirProbe.remove(account.id)));
      }
    }();
  }

  /// Подсказки Exchange для адресатов письма (MailTips, 1.6.49): автоответ
  /// («в отпуске до …»), переполненный ящик, большая рассылка — как в
  /// Outlook, ещё до отправки. Через EWS (у ящика ActiveSync — адресная
  /// книга EWS того же сервера, см. [_directoryEws]); нет EWS или сбой —
  /// пустой список. Ответы — 10 минут в памяти: адресаты меняются по одному.
  final Map<String, ({DateTime at, MailTip? tip})> _tipsCache = {};

  Future<List<MailTip>> mailTips(AccountModel account, List<String> emails) async {
    final wanted = {for (final e in emails) e.trim().toLowerCase()}..removeWhere((e) => !e.contains('@'));
    if (wanted.isEmpty) return const [];
    final now = DateTime.now();
    String key(String e) => '${account.id}|$e';
    final ask = [
      for (final e in wanted)
        if (_tipsCache[key(e)] == null || now.difference(_tipsCache[key(e)]!.at) > const Duration(minutes: 10)) e,
    ];
    if (ask.isNotEmpty) {
      final dir = await _directoryEws(account);
      if (dir == null) return const [];
      try {
        final got = await _ews
            .getMailTips(dir, sender: account.email, recipients: ask.take(50).toList())
            .timeout(const Duration(seconds: 20));
        final byEmail = {for (final t in got) t.email: t};
        for (final e in ask) {
          _tipsCache[key(e)] = (at: now, tip: byEmail[e]);
        }
      } catch (err) {
        AppLogger.debug('MailTips: $err');
        return const [];
      }
    }
    return [
      for (final e in wanted)
        if (_tipsCache[key(e)]?.tip case final t? when t.notable) t,
    ];
  }

  /// Фото человека в высоком качестве (1.6.49, EWS GetUserPhoto, 240×240):
  /// в адресной книге ActiveSync — миниатюра 96×96, на экране телефона она
  /// размыта. data URI или null (фото нет, нет EWS). Сервер без
  /// GetUserPhoto (Exchange 2010) — пауза на неделю. Сбой связи — исключение
  /// (очередь фото повторит позже).
  Future<String?> lookupHiResPhoto(AccountModel account, String email) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return null;
    final offKey = 'ews_photo_off_${account.id}';
    final off = _prefs.getInt(offKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - off < const Duration(days: 7).inMilliseconds) return null;
    final dir = await _directoryEws(account);
    if (dir == null) return null;
    try {
      final bytes = await _ews.getUserPhoto(dir, e).timeout(const Duration(seconds: 25));
      if (bytes == null) return null;
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } on TimeoutException {
      rethrow;
    } on NetworkException {
      // Нет связи — наверх: очередь фото повторит позже.
      rethrow;
    } on ServerUnavailableException {
      rethrow;
    } catch (err) {
      final t = '$err';
      // Сервер не знает GetUserPhoto (Exchange 2010): ошибка схемы запроса.
      if (t.contains('schema validation') || t.contains('invalid child element') || t.contains('ErrorInvalidServerVersion')) {
        await _prefs.setInt(offKey, DateTime.now().millisecondsSinceEpoch);
        AppLogger.info('Фото в высоком качестве (EWS) недоступны у ${AppLogger.mask(account.email)}: $t');
      }
      // Остальное (фото нет, нет доступа) — «нет фото».
      return null;
    }
  }

  /// Переговорные организации (1.6.49): списки (здания, этажи) и комнаты.
  /// Через EWS (у ящика ActiveSync — EWS того же сервера). Нет EWS или
  /// списков не заведено — пусто. Ответы — 30 минут в памяти.
  final Map<String, ({DateTime at, List<DirectoryRoom> items})> _roomsCache = {};

  Future<List<DirectoryRoom>> roomLists(AccountModel account) =>
      _rooms(account, 'lists', (dir) => _ews.getRoomLists(dir));

  Future<List<DirectoryRoom>> roomsOf(AccountModel account, String listEmail) =>
      _rooms(account, 'list:${listEmail.toLowerCase()}', (dir) => _ews.getRooms(dir, listEmail));

  Future<List<DirectoryRoom>> _rooms(
      AccountModel account, String what, Future<List<DirectoryRoom>> Function(AccountModel dir) load) async {
    final key = '${account.id}|$what';
    final hit = _roomsCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 30)) return hit.items;
    final dir = await _directoryEws(account);
    if (dir == null) return const [];
    final items = await load(dir).timeout(const Duration(seconds: 25));
    _roomsCache[key] = (at: DateTime.now(), items: items);
    return items;
  }

  /// Занятость каждого на отрезке [from, to) (1.6.49: переговорные при
  /// создании собрания): адрес (нижний регистр) → 0 свободен, 1 под
  /// вопросом, 2 занят, 3 нет на месте. Нет в ответе — данных нет.
  Future<Map<String, int>> busyStatus(AccountModel account, List<String> emails, DateTime from, DateTime to) async {
    if (emails.isEmpty || !to.isAfter(from)) return const {};
    // Окно — с начала получаса: шаг занятости 30 минут.
    final start = DateTime(from.year, from.month, from.day, from.hour, from.minute < 30 ? 0 : 30);
    final Map<String, String> strings;
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return const {};
      final map = await eas.freeBusy(emails, startUtc: start.toUtc(), endUtc: to.toUtc());
      strings = {for (final e in map.entries) e.key.toLowerCase(): e.value};
    } else {
      final dir = await _directoryEws(account);
      if (dir == null) return const {};
      strings = await _ews.getFreeBusyStrings(dir, emails: emails, startLocal: start, endLocal: to, intervalMinutes: 30);
    }
    final out = <String, int>{};
    for (final e in emails) {
      final key = e.trim().toLowerCase();
      final str = strings[key];
      if (str == null) continue;
      final st = FreeBusyView.statusFor(str, start, 30, from, to);
      if (st != null) out[key] = st;
    }
    return out;
  }

  /// Есть ли у ящика архив Exchange (1.6.49). [mailbox] — общий ящик.
  /// null — нет EWS (у ящика ActiveSync — и EWS того же сервера); false —
  /// архива нет. Сбой связи — исключение.
  Future<bool?> hasOnlineArchive(AccountModel account, {String? mailbox}) async {
    final dir = await _directoryEws(account);
    if (dir == null) return null;
    final id = await _ews.archiveRootId(dir, mailbox: mailbox).timeout(const Duration(seconds: 25));
    return id != null;
  }

  /// Доступ к общему ящику [email] под учётной записью [parent] (1.6.49):
  /// почта (корень папок ящика) и календарь. null — EWS нет (у ящика
  /// ActiveSync — и EWS того же сервера). Сбой связи — исключение.
  Future<({bool mail, bool calendar, String ewsUrl})?> checkSharedAccess(AccountModel parent, String email) async {
    final url = await directoryEwsUrl(parent);
    if (url == null) return null;
    final probe = parent.copyWith(ewsUrl: url);
    final mail = await _ews.canOpenFolder(probe, 'msgfolderroot', mailbox: email).timeout(const Duration(seconds: 25));
    final calendar = await _ews.canOpenFolder(probe, 'calendar', mailbox: email).timeout(const Duration(seconds: 25));
    return (mail: mail, calendar: calendar, ewsUrl: url);
  }

  /// Адрес EWS для ящика ActiveSync (EWS того же сервера), если он
  /// отвечает; у ящика EWS — свой. null — EWS нет (1.6.49: общий ящик и
  /// архив для ящика ActiveSync).
  Future<String?> directoryEwsUrl(AccountModel account) async {
    final dir = await _directoryEws(account);
    if (dir == null) return null;
    final url = (dir.ewsUrl ?? '').trim();
    if (url.isNotEmpty) return url;
    final server = (dir.exchangeServer ?? '').trim();
    return server.isEmpty ? null : EwsService.ewsUrlFromServer(server);
  }

  /// Известно ли, есть ли у ящика EWS (1.7.3, без запроса к серверу): true —
  /// есть (свой или того же сервера у ActiveSync), false — сервер его не
  /// открывает (проверено за последнюю неделю), null — ещё не проверяли.
  bool? ewsKnown(AccountModel account) {
    if (account.hasEwsExtras || account.isExchange) return true;
    if (!account.usesEas) return false;
    final saved = _prefs.getString('ews_dir_${account.id}') ?? '';
    if (saved.startsWith('https://')) return true;
    final at = int.tryParse(saved.replaceFirst('none:', ''));
    if (at != null && DateTime.now().millisecondsSinceEpoch - at < const Duration(days: 7).inMilliseconds) {
      return false;
    }
    return null;
  }

  /// Проверить EWS ящика ActiveSync заново (1.7.3, «Повторить» на экране
  /// правил Exchange): отказ запоминается на неделю — здесь он забывается.
  Future<void> forgetDirectoryEws(String accountId) async {
    // Идущая проверка не отменяется — её результат просто не берётся.
    _dirProbe.remove(accountId)?.ignore();
    final key = 'ews_dir_$accountId';
    if ((_prefs.getString(key) ?? '').startsWith('none:')) await _prefs.remove(key);
  }

  /// Дополнить карточку ActiveSync полями EWS (отдел, руководитель, ФИО).
  static ContactModel _mergePerson(ContactModel a, ContactModel b) {
    String? pick(String? x, String? y) => (x ?? '').trim().isNotEmpty ? x : y;
    return ContactModel(
      id: a.id,
      accountId: a.accountId,
      email: a.email,
      displayName: b.displayName.split(' ').length > a.displayName.split(' ').length ? b.displayName : a.displayName,
      firstName: pick(a.firstName, b.firstName),
      lastName: pick(a.lastName, b.lastName),
      middleName: pick(a.middleName, b.middleName),
      jobTitle: pick(a.jobTitle, b.jobTitle),
      department: pick(a.department, b.department),
      company: pick(a.company, b.company),
      phoneWork: pick(a.phoneWork, b.phoneWork),
      phoneMobile: pick(a.phoneMobile, b.phoneMobile),
      office: pick(a.office, b.office),
      manager: pick(a.manager, b.manager),
      city: pick(a.city, b.city),
      avatarUrl: pick(a.avatarUrl, b.avatarUrl),
      source: ContactSource.exchangeGal,
    );
  }

  /// Разрешение имён (GAL) — только EWS; иначе пустой список.
  Future<List<ContactModel>> resolveNames(AccountModel account, String query,
      {int maxResults = 20}) async {
    if (account.isExchange || account.usesEws) {
      return _ews.resolveNames(account, query: query, maxResults: maxResults);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return const [];
      // Адресная книга организации: поиск по части имени/адреса с
      // должностью и телефонами; если GAL недоступен — разрешение имён.
      final gal = await eas.searchGal(query, maxResults: maxResults);
      if (gal.isNotEmpty) {
        return [
          for (final g in gal)
            ContactModel(
              id: 'gal_${g.email.toLowerCase().hashCode}',
              accountId: account.id,
              email: g.email,
              displayName: g.displayName,
              firstName: g.firstName,
              lastName: g.lastName,
              company: g.company,
              jobTitle: g.title,
              phoneWork: g.phone,
              phoneMobile: g.mobilePhone,
              office: g.office,
              isGroup: _looksLikeGroup(g),
            ),
        ];
      }
      final hits = await eas.resolveRecipients(query, maxResults: maxResults);
      return hits
          .map((h) => ContactModel(
                id: 'gal_${h.email.hashCode}',
                accountId: account.id,
                email: h.email,
                displayName: h.displayName.isNotEmpty ? h.displayName : h.email,
              ))
          .toList();
    }
    return const [];
  }

  /// ActiveSync не сообщает тип записи адресной книги. У списков рассылки
  /// нет имени/фамилии, должности и телефонов — только отображаемое имя и
  /// адрес; у сотрудников хотя бы одно из этих полей заполнено.
  static bool _looksLikeGroup(me.EasGalEntry g) {
    bool empty(String? v) => v == null || v.trim().isEmpty;
    return empty(g.firstName) && empty(g.lastName) && empty(g.title) &&
        empty(g.phone) && empty(g.mobilePhone) && empty(g.office);
  }

  /// Участники группы рассылки. Через EWS (ExpandDL): у ActiveSync такой
  /// команды нет, поэтому для EAS-ящика нужен адрес EWS (гибридный режим,
  /// Autodiscover). null — раскрыть нельзя (нет EWS или не Exchange).
  Future<List<ContactModel>?> expandGroup(AccountModel account, String email) async {
    if (!account.hasEwsExtras && !account.isExchange) return null;
    try {
      return await _ews.expandDl(account, email);
    } catch (e) {
      AppLogger.warning('Раскрытие группы $email: $e');
      rethrow;
    }
  }

  /// Коллеги из того же подразделения (поле «Офис/подразделение» карточки
  /// владельца в адресной книге). Поиск по адресной книге находит по этому
  /// полю (неоднозначное разрешение имён Exchange), затем отбираем совпадение.
  ///
  /// 1.6.26: адресная книга ActiveSync не отдаёт поле «Отдел» — только
  /// «Офис», а в нём часто кабинет («РММ, к. 12 (3й этаж)»): находились лишь
  /// соседи по кабинету (журнал 18.10.2026). Теперь ищем и по началу поля до
  /// запятой или скобки («РММ» — здание/подразделение). [near] — точное
  /// совпадение (их отмечаем сразу), остальные — в списке без отметки.
  Future<({String unit, String wider, Set<String> near, List<ContactModel> people})> departmentColleagues(
      AccountModel account) async {
    final card = cachedSelfCard(account.id);
    final unit = (card['office'] ?? '').trim();
    if (unit.isEmpty) return (unit: '', wider: '', near: <String>{}, people: const <ContactModel>[]);
    final me = account.email.toLowerCase();
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    bool person(ContactModel c) => !c.isGroup && c.email.toLowerCase() != me;
    final exact = (await resolveNames(account, unit, maxResults: 100))
        .where((c) => person(c) && (norm(c.office) == norm(unit) || norm(c.department) == norm(unit)))
        .toList();
    final wider = widerUnit(unit);
    var broad = const <ContactModel>[];
    if (wider.isNotEmpty) {
      try {
        broad = (await resolveNames(account, wider, maxResults: 100))
            .where((c) => person(c) &&
                (norm(c.office).startsWith(norm(wider)) || norm(c.department).startsWith(norm(wider))))
            .toList();
      } catch (e) {
        AppLogger.warning('Моё подразделение: поиск «$wider» — $e');
      }
    }
    final near = {for (final c in exact) c.email.toLowerCase()};
    final byEmail = <String, ContactModel>{
      for (final c in [...exact, ...broad]) c.email.toLowerCase(): c,
    };
    final people = byEmail.values.toList()
      ..sort((a, b) {
        final na = near.contains(a.email.toLowerCase()) ? 0 : 1;
        final nb = near.contains(b.email.toLowerCase()) ? 0 : 1;
        if (na != nb) return na - nb;
        final o = norm(a.office).compareTo(norm(b.office));
        return o != 0 ? o : a.displayName.compareTo(b.displayName);
      });
    AppLogger.info('Моё подразделение: «$unit» — ${exact.length}'
        '${wider.isEmpty ? '' : ', «$wider» — ${broad.length}'}');
    return (unit: unit, wider: wider, near: near, people: people);
  }

  /// Начало поля «Офис» до запятой или скобки: «РММ, к. 12 (3й этаж)» →
  /// «РММ». Пустая строка — сузить нечего (или слишком коротко для поиска).
  static String widerUnit(String unit) {
    final cut = unit.indexOf(RegExp(r'[,(;/]'));
    if (cut <= 0) return '';
    final w = unit.substring(0, cut).trim();
    return (w.length < 2 || w.toLowerCase() == unit.trim().toLowerCase()) ? '' : w;
  }

  // ════════════ Карточка владельца ящика (адресная книга) ════════════

  static String _selfKey(String accountId) => 'selfcard_$accountId';

  /// Сохранённая карточка владельца: ФИО, должность, отдел, организация,
  /// телефоны из адресной книги организации. Для подписи и имени ящика.
  Map<String, String> cachedSelfCard(String accountId) {
    final raw = _prefs.getString(_selfKey(accountId));
    if (raw == null) return const {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  /// Обновить карточку из GAL (ActiveSync) раз в сутки (до 1.8.0+119 — раз
  /// в неделю: замечание владельца 27.10.2026 — «контакты обновились, а в
  /// моей подписи всё равно старое обозначение»: компания в подписи —
  /// поле {company} из этой карточки). Возвращает ФИО, если удалось найти
  /// себя в адресной книге.
  Future<String?> refreshSelfCard(AccountModel account, {bool force = false}) async {
    final ewsOnly = !account.usesEas && (account.usesEws || account.isExchange);
    if (!account.usesEas && !ewsOnly) return null;
    final cached = cachedSelfCard(account.id);
    final at = DateTime.tryParse(cached['updatedAt'] ?? '');
    // Карточки без попытки получить фото (старые версии) обновляем сразу.
    if (!force && at != null && cached.containsKey('photoTried') &&
        DateTime.now().difference(at).inHours < 24) {
      return cached['name'];
    }
    // Ящик только по EWS: карточка из ResolveNames (раньше её не было —
    // подпись, имя ящика и «Моё подразделение» оставались без данных).
    if (ewsOnly) {
      final list = await _ews.resolveNames(account, query: account.email, maxResults: 5);
      final mine = list.where((c) => c.email.toLowerCase() == account.email.toLowerCase()).firstOrNull;
      if (mine == null) return null;
      final unit = (mine.department ?? '').isNotEmpty ? mine.department! : (mine.office ?? '');
      final photo = await _selfHiResPhoto(account);
      final card = <String, String>{
        'name': mine.displayName,
        if (photo != null) 'photo': photo,
        if ((mine.jobTitle ?? '').isNotEmpty) 'title': mine.jobTitle!,
        if ((mine.company ?? '').isNotEmpty) 'company': mine.company!,
        if (unit.isNotEmpty) 'office': unit,
        if ((mine.phoneWork ?? '').isNotEmpty) 'phone': mine.phoneWork!,
        if ((mine.phoneMobile ?? '').isNotEmpty) 'mobile': mine.phoneMobile!,
        'photoTried': '1',
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await _prefs.setString(_selfKey(account.id), jsonEncode(card));
      AppLogger.info('Карточка владельца ${account.email}: найдена (EWS)');
      return mine.displayName;
    }
    final eas = await _easEngine(account);
    if (eas == null) return null;
    final me_ = account.email.toLowerCase();
    final local = me_.split('@').first;
    me.EasGalEntry? hit;
    for (final q in [local, me_]) {
      final list = await eas.searchGal(q, maxResults: 10, withPictures: true);
      for (final g in list) {
        if (g.email.toLowerCase() == me_) {
          hit = g;
          break;
        }
      }
      if (hit != null) break;
    }
    if (hit == null) return null;
    // Своё фото — в высоком качестве, если сервер отдаёт (1.6.49).
    final hiPhoto = await _selfHiResPhoto(account);
    final card = <String, String>{
      'name': hit.displayName,
      if (hit.title != null) 'title': hit.title!,
      if (hit.company != null) 'company': hit.company!,
      if (hit.office != null) 'office': hit.office!,
      if (hit.phone != null) 'phone': hit.phone!,
      if (hit.mobilePhone != null) 'mobile': hit.mobilePhone!,
      if (hiPhoto != null)
        'photo': hiPhoto
      else if (_pictureUri(hit.picture) != null)
        'photo': _pictureUri(hit.picture)!,
      'photoTried': '1',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _prefs.setString(_selfKey(account.id), jsonEncode(card));
    AppLogger.info('Карточка владельца ${account.email}: найдена в адресной книге');
    return hit.displayName;
  }

  Future<String?> _selfHiResPhoto(AccountModel account) async {
    try {
      return await lookupHiResPhoto(account, account.email);
    } catch (_) {
      return null;
    }
  }

  /// Отзыв письма — только EWS; иначе false.
  /// Отзыв письма недоступен ни в одном протоколе приложения (см.
  /// TransportCapabilities.ews): прежний вызов EWS «отзывал» только на словах.
  Future<bool> recall(AccountModel account, String emailId) async => false;

  /// Ответ на приглашение-встречу (accept/tentative/decline). Пока EWS.
  /// Серверные категории Outlook — EWS. Для не-EWS возвращает false (категории
  /// сохраняются только локально вызывающим кодом).
  Future<bool> setCategories(AccountModel account,
      {required String itemId, required List<String> categories, String? folderId}) async {
    if (account.usesEas) {
      if (folderId == null) return false;
      // Категории письма меняются командой Sync той же папки, что и почта:
      // в общей очереди аккаунта и с тем же сохранённым SyncKey — иначе
      // параллельная синхронизация получала Status 3 и папка перечитывалась.
      return _serial(account.id, () async {
        final eas = await _easEngine(account);
        if (eas == null) return false;
        final fid = _serverId(folderId);
        _seedKey(account, eas, fid);
        await eas.setEmailCategories(
            me.MessageRef(id: itemId, folderId: fid, serverId: _serverId(itemId)), categories);
        await _persistKey(account, eas, fid);
        return true;
      });
    }
    return _ewsPrimary(account)
        ? _ews.setCategories(account, itemId: itemId, categories: categories)
        : false;
  }

  /// Управление папками на сервере — EWS (EAS folderCreate/Update/Delete отложены).
  /// Занятость участников (free/busy) — EWS. Для не-EWS вернёт пустой вид.
  Future<FreeBusyView> getFreeBusy(AccountModel account,
      {required List<String> emails, required DateTime startLocal, required DateTime endLocal,
      int intervalMinutes = 30}) async {
    if (account.usesEas) {
      // ActiveSync: занятость по каждому сотруднику, интервал всегда 30 мин.
      // Объединяем: в каждом интервале — самый «занятый» статус.
      final eas = await _easEngine(account);
      final map = eas == null
          ? const <String, String>{}
          : await eas.freeBusy(emails, startUtc: startLocal.toUtc(), endUtc: endLocal.toUtc());
      if (map.isEmpty) {
        return FreeBusyView(startLocal: startLocal, intervalMinutes: 30, statuses: const []);
      }
      const rank = {'0': 0, '4': 0, '1': 1, '2': 2, '3': 3};
      final len = map.values.map((v) => v.length).reduce((a, b) => a > b ? a : b);
      final merged = StringBuffer();
      for (var i = 0; i < len; i++) {
        var best = '?';
        var bestRank = -1;
        for (final v in map.values) {
          if (i >= v.length) continue;
          final r = rank[v[i]];
          if (r != null && r > bestRank) {
            bestRank = r;
            best = v[i];
          }
        }
        merged.write(best == '?' ? '4' : best);
      }
      return FreeBusyView(
          startLocal: startLocal,
          intervalMinutes: 30,
          statuses: FreeBusyView.parseMerged(merged.toString()));
    }
    if (!_isEws(account)) return FreeBusyView(startLocal: startLocal, intervalMinutes: intervalMinutes, statuses: const []);
    return _ews.getFreeBusy(account, emails: emails, startLocal: startLocal, endLocal: endLocal, intervalMinutes: intervalMinutes);
  }

  /// Создать папку: EWS → ews_service, EAS → движок (FolderCreate, code page 7).
  /// Для остальных транспортов (IMAP) — пока false.
  /// Создать папку в корне ящика или внутри [parentId] (id папки в базе).
  Future<bool> createFolder(AccountModel account, String displayName, {String? parentId}) async {
    final parent = (parentId == null || parentId.isEmpty) ? null : parentId;
    if (_ewsPrimary(account)) {
      return parent == null
          ? _ews.createFolder(account, displayName)
          : _ews.createFolder(account, displayName, parentId: parent);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return false;
      return (await eas.createFolderRemote(displayName, parentId: parent == null ? '0' : _serverId(parent))) != null;
    }
    final imap = _ref?.read(imapServiceProvider);
    if (imap != null) return (await imap.createFolder(account, displayName, parentPath: parent)) != null;
    return false;
  }

  /// Родитель папки по базе (null — корень ящика).
  Future<String?> _folderParent(AccountModel account, String folderId) async {
    final db = _ref?.read(databaseProvider);
    if (db == null) return null;
    final row = await (db.select(db.folders)
          ..where((f) => f.id.equals(folderId) & f.accountId.equals(account.id))
          ..limit(1))
        .getSingleOrNull();
    final p = row?.parentId;
    return (p == null || p.isEmpty || p == '0') ? null : p;
  }

  /// Переименовать папку: EWS → ews_service, EAS → движок (FolderUpdate),
  /// IMAP → RENAME. `folderId` для EAS — это ServerId.
  /// У EAS в FolderUpdate обязателен родитель: раньше передавался корень, и
  /// переименованная подпапка уезжала в корень ящика.
  Future<bool> renameFolder(AccountModel account, {required String folderId, required String newName}) async {
    if (_ewsPrimary(account)) return _ews.renameFolder(account, folderId: folderId, newName: newName);
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return false;
      final parent = await _folderParent(account, folderId);
      return eas.updateFolderRemote(folderId, newName, parentId: parent == null ? '0' : _serverId(parent));
    }
    final imap = _ref?.read(imapServiceProvider);
    if (imap != null) return imap.renameFolder(account, path: folderId, newName: newName);
    return false;
  }

  /// Переместить папку внутрь [newParentId] (null — в корень ящика).
  Future<bool> moveFolder(AccountModel account,
      {required String folderId, required String displayName, String? newParentId}) async {
    final parent = (newParentId == null || newParentId.isEmpty) ? null : newParentId;
    if (_ewsPrimary(account)) {
      return parent == null
          ? _ews.moveFolder(account, folderId: folderId)
          : _ews.moveFolder(account, folderId: folderId, toParentId: parent);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return false;
      return eas.updateFolderRemote(folderId, displayName, parentId: parent == null ? '0' : _serverId(parent));
    }
    final imap = _ref?.read(imapServiceProvider);
    if (imap != null) return imap.renameFolder(account, path: folderId, newParentPath: parent ?? '');
    return false;
  }

  /// Сервер ActiveSync сообщил, что список папок изменился (папку удалили
  /// или переместили в Outlook) — флаг сбрасывается при чтении (1.6.12).
  bool takeFolderHierarchyChanged(String accountId) {
    final e = _engines[accountId];
    return e is me.EasEngine && e.takeHierarchyChanged();
  }

  /// Удалить папку: EWS → ews_service, EAS → движок (FolderDelete), IMAP → DELETE.
  Future<bool> deleteFolder(AccountModel account, {required String folderId}) async {
    if (_ewsPrimary(account)) return _ews.deleteFolder(account, folderId: folderId);
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return false;
      return eas.deleteFolderRemote(folderId);
    }
    final imap = _ref?.read(imapServiceProvider);
    if (imap != null) return imap.deleteFolder(account, path: folderId);
    return false;
  }

  /// Ответ на приглашение, как в Outlook (1.5.12): «Отправить ответ
  /// сейчас», с комментарием ([comment]), «Не отправлять ответ»
  /// ([send] = false) и «Предложить новое время» ([proposedStart],
  /// [proposedEnd] — для «Под вопросом» и «Отклонить»).
  ///
  /// ActiveSync до 16.0 сам ответ организатору не отправляет — тогда он
  /// уходит письмом с iCalendar (iMIP): [meeting] даёт UID и организатора,
  /// [mailSubject] и [mailBody] — тема и текст письма на языке приложения.
  ///
  /// Результат: [ok] — ответ принят сервером; [sent] — организатор получит
  /// ответ; [proposed] — предложенное время ушло полем встречи (иначе —
  /// только текстом комментария).
  Future<({bool ok, bool sent, bool proposed})> respondToMeeting(
    AccountModel account, {
    required String itemId,
    required String response,
    String? folderId,
    bool send = true,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
    EmailMeeting? meeting,
    String? title,
    String? mailSubject,
    String? mailBody,
  }) async {
    const fail = (ok: false, sent: false, proposed: false);
    if (response == 'accept') {
      proposedStart = null;
      proposedEnd = null;
    }
    if (_ewsPrimary(account)) {
      final r = await _ews.respondToMeeting(account,
          itemId: itemId,
          response: response,
          send: send,
          comment: comment,
          proposedStart: proposedStart,
          proposedEnd: proposedEnd);
      return (ok: r.ok, sent: r.ok && send, proposed: r.proposed);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null || folderId == null) return fail;
      final userResponse = response == 'accept'
          ? 1
          : response == 'tentative'
              ? 2
              : 3;
      final res = await eas.meetingResponse(
        collectionId: _serverId(folderId),
        requestId: _serverId(itemId),
        userResponse: userResponse,
        notifyOrganizer: send,
        comment: comment,
        proposedStart: proposedStart,
        proposedEnd: proposedEnd,
      );
      if (res == null) return fail;
      if (!send || res.sent) return (ok: true, sent: res.sent, proposed: res.proposed);
      // Сервер (ActiveSync до 16.0) ответ не отправил — письмо организатору.
      final organizer = ItipReply.organizerEmail(meeting?.organizer);
      final uid = meeting?.uid;
      if (organizer == null || uid == null || uid.isEmpty) {
        AppLogger.warning('Ответ на приглашение: нет организатора или UID — письмо не отправлено');
        return (ok: true, sent: false, proposed: false);
      }
      final counter = proposedStart != null && proposedEnd != null;
      final ics = ItipReply.build(
        uid: uid,
        organizer: organizer,
        attendee: account.email,
        attendeeName: account.displayName,
        response: response,
        start: meeting?.start,
        end: meeting?.end,
        allDay: meeting?.allDay ?? false,
        occurrence: meeting?.isOccurrence ?? false,
        summary: title,
        comment: comment,
        proposedStart: proposedStart,
        proposedEnd: proposedEnd,
      );
      try {
        await eas.send(me.OutgoingMessage(
          to: [me.MailAddress(organizer, null)],
          subject: mailSubject ?? title ?? '',
          bodyPlain: (comment ?? '').trim().isNotEmpty ? comment!.trim() : (mailBody ?? ''),
          calendar: ics,
          calendarMethod: counter ? 'COUNTER' : 'REPLY',
        ));
        AppLogger.info('Ответ на приглашение отправлен письмом (ActiveSync < 16)');
        return (ok: true, sent: true, proposed: counter);
      } catch (e) {
        AppLogger.warning('Ответ на приглашение письмом не отправлен: $e');
        return (ok: true, sent: false, proposed: false);
      }
    }
    return fail;
  }

  /// Уведомление о прочтении — только EWS.
  Future<void> sendReadReceipt(AccountModel account, {
    required String originalMessageId,
    required String toEmail,
    required String subject,
  }) async {
    if (account.usesEas) {
      // В ActiveSync отдельной команды нет — обычное письмо-уведомление.
      await send(account,
          to: [EmailAddress(email: toEmail)],
          subject: 'Прочитано: $subject',
          bodyPlain: 'Ваше сообщение «$subject» прочитано ${account.email} '
              '${DateTime.now().toLocal().toString().substring(0, 16)}.',
          inReplyTo: originalMessageId);
      return;
    }
    if (!_isEws(account)) return;
    await _ews.sendReadReceipt(account,
        originalMessageId: originalMessageId, toEmail: toEmail, subject: subject);
  }

  /// Создать событие календаря. Возвращает id для локальной базы — в том
  /// виде, в каком событие придёт при синхронизации (EAS: «eas_<ServerId>»,
  /// EWS: ItemId), чтобы после синка не появлялся дубль. null — id заранее
  /// неизвестен: событие появится после ближайшей синхронизации.
  ///
  /// Встречу с участниками у ActiveSync-аккаунта создаём через EWS-спутник,
  /// если он есть: приглашения тогда рассылает Exchange гарантированно
  /// (в ActiveSync до версии 16 сервер их не рассылает).
  ///
  /// [created] = false — сервер событие НЕ создал (нет подключения, отказ):
  /// вызывающий сохраняет его локально, чтобы оно не пропало.
  Future<({bool created, String? id})> createEvent(AccountModel account, CalendarEventModel e,
      {List<({String name, String? contentType, Uint8List bytes})> attachments = const []}) async {
    if (account.usesEas) {
      // С ActiveSync 16 встречу с участниками создаёт сам EAS — сервер
      // рассылает приглашения. Через EWS идём только для старых серверов:
      // у многих организаций EWS снаружи закрыт (401), и встреча не
      // создавалась вовсе (ENGINE_AUDIT, P1-14).
      final eas16 = (double.tryParse((await _easEngine(account))?.protocolVersion ?? '') ?? 0) >= 16;
      // Важность встречи ActiveSync не передаёт (в MS-ASCAL её нет) — при
      // доступном EWS такая встреча создаётся через него (1.6.4). EWS закрыт
      // или ошибся — создаём через ActiveSync, без важности.
      // Вложения письма (1.6.12) важнее важности: их передаёт ActiveSync 16,
      // встреча через EWS ушла бы без файлов.
      if (e.priority != EventPriority.normal && account.hasEwsExtras && !(eas16 && attachments.isNotEmpty)) {
        try {
          final id = await _ews.createCalendarEvent(account, event: e,
              category: CategoryColors.categoryFor(e.colorValue, russian: _mailboxRussian()));
          if (id.isNotEmpty) {
            if (e.recurrence != RecurrenceType.none) await requestFullCalendarResync(account);
            return (created: true, id: null);
          }
        } catch (err) {
          AppLogger.warning('createEvent: EWS не создал встречу с важностью ($err) — через ActiveSync');
        }
      }
      if (e.attendees.isNotEmpty && account.hasEwsExtras && !eas16) {
        if (attachments.isNotEmpty) {
          AppLogger.warning('createEvent: вложения письма через EWS не передаются (ActiveSync ниже 16)');
        }
        final id = await _ews.createCalendarEvent(account, event: e, category: CategoryColors.categoryFor(e.colorValue, russian: _mailboxRussian()));
        if (id.isNotEmpty && e.recurrence != RecurrenceType.none) {
          await requestFullCalendarResync(account);
        }
        return (created: id.isNotEmpty, id: null);
      }
      final sid = await saveEvent(account, e, attachments: attachments);
      if (sid == null) return (created: false, id: null);
      // Серия: ActiveSync не вернёт созданный нами элемент при синке, и
      // вхождения не развернулись бы — перечитаем календарь целиком.
      if (e.recurrence != RecurrenceType.none) await requestFullCalendarResync(account);
      return (created: true, id: 'eas_$sid');
    }
    if (_usesDav(account)) {
      final auth = await _davAuth(account);
      if (auth == null) return (created: false, id: null);
      final id = await DavPimService().createEvent(account, auth, e);
      return (created: id != null, id: id);
    }
    if (!_ewsPrimary(account)) return (created: false, id: null);
    final id = await _ews.createCalendarEvent(account, event: e, category: CategoryColors.categoryFor(e.colorValue, russian: _mailboxRussian()));
    return (created: id.isNotEmpty, id: id.isEmpty ? null : id);
  }

  /// Календарь по CalDAV (Google, Яндекс, Mail.ru, Yahoo). Раньше создание
  /// события у таких ящиков уходило в EWS и молча не удавалось — событие
  /// оставалось только на телефоне; изменить и удалить его на сервере было
  /// нельзя совсем.
  bool _usesDav(AccountModel account) =>
      !account.usesEas && !_ewsPrimary(account) && DavPimService.isSupported(account);

  /// Можно ли менять календарь аккаунта на сервере из приложения.
  bool canWriteCalendar(AccountModel account) =>
      account.usesEas || _ewsPrimary(account) || _usesDav(account);

  /// Удаляется ли вхождение серии отдельно (CalDAV — EXDATE), а не вся серия.
  bool deletesSingleOccurrence(AccountModel account) => _usesDav(account);

  /// Хранит ли календарь ящика несколько напоминаний у встречи (1.7.2+110):
  /// CalDAV — да (несколько VALARM), Exchange — одно (ActiveSync Reminder,
  /// EWS ReminderMinutesBeforeStart; остальные — только на телефоне).
  bool keepsManyReminders(AccountModel account) => _usesDav(account);

  Future<String?> _davAuth(AccountModel account, {bool contacts = false}) => DavCredentials.authorization(
        account,
        _secureStorage,
        proxy: OAuthProxyClient(_secureStorage),
        contacts: contacts,
      );

  /// Черновик ActiveSync в серверные «Черновики» (только AS 16). В общей
  /// очереди аккаунта и с сохранённым SyncKey папки — синхронизация
  /// «Черновиков» продолжает ту же цепочку ключей. Возвращает папку и
  /// ServerId или null (протокол ниже 16, папка не найдена, отказ).
  /// [attachments] — файлы черновика (1.7.2+111); [files] в ответе — их
  /// список на сервере (ActiveSync не возвращает клиенту добавленный им
  /// элемент — список берётся отдельным запросом; null — не получен).
  Future<({String folderId, String id, List<EmailAttachment>? files})?> saveDraftEas(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
  }) =>
      _serial(account.id, () async {
        final eas = await _easEngine(account);
        if (eas == null) return null;
        final drafts = await _foldersOfType(account, me.MailFolderType.drafts);
        if (drafts.isEmpty) return null;
        final fid = drafts.first.id;
        _seedKey(account, eas, fid);
        me.MailAddress m(EmailAddress a) => me.MailAddress(a.email, a.displayName);
        String? sid;
        try {
          sid = await eas.addDraft(fid,
              to: [for (final a in to) m(a)],
              cc: [for (final a in cc) m(a)],
              bcc: [for (final a in bcc) m(a)],
              subject: subject,
              bodyHtml: bodyHtml,
              attachments: attachments);
        } finally {
          await _persistKey(account, eas, fid);
        }
        // Шлюз перед Exchange не пропустил черновик с большими файлами
        // (1.7.2+114) — исключением: выгрузка не будет повторять его, пока
        // черновик не изменится.
        if (sid == null && eas.lastWasGatewaySize) {
          throw me.GatewaySizeRejected(attachments.fold<int>(0, (s, a) => s + a.bytes.length));
        }
        if (sid == null) return null;
        List<EmailAttachment>? files;
        if (attachments.isNotEmpty) {
          try {
            final full = await eas.fetchMessage(me.MessageRef(id: sid, folderId: fid, serverId: sid));
            files = [
              for (final a in full.attachments)
                EmailAttachment(
                  id: a.id,
                  name: a.name,
                  mimeType: (a.contentType != null && a.contentType!.isNotEmpty) ? a.contentType! : _mimeByName(a.name),
                  size: a.size ?? 0,
                  isInline: a.isInline,
                  contentId: EmailAttachment.normalizeCid(a.contentId),
                ),
            ];
          } catch (e) {
            AppLogger.warning('EAS: список файлов черновика не получен — $e');
          }
        }
        return (folderId: fid, id: sid, files: files);
      });

  /// Список вложений письма с сервера (1.7.2+111): черновик из «Черновиков»
  /// перед правкой. EWS — GetItem, ActiveSync — ItemOperations; IMAP —
  /// null (список приходит с синхронизацией).
  Future<List<EmailAttachment>?> fetchAttachmentList(AccountModel account,
      {required String folderId, required String emailId}) async {
    if (_ewsPrimary(account)) {
      final full = await _ews.getEmailDetail(account, emailId: emailId);
      return full.attachments;
    }
    if (!account.usesEas) return null;
    final engine = await _engineFor(account);
    if (engine == null) return null;
    final m = await engine.fetchMessage(me.MessageRef(id: emailId, folderId: folderId, serverId: emailId));
    return [
      for (final a in m.attachments)
        EmailAttachment(
          id: a.id,
          name: a.name,
          mimeType: (a.contentType != null && a.contentType!.isNotEmpty) ? a.contentType! : _mimeByName(a.name),
          size: a.size ?? 0,
          isInline: a.isInline,
          contentId: EmailAttachment.normalizeCid(a.contentId),
        ),
    ];
  }

  /// Изменить встречу на сервере. ActiveSync — Change, EWS — UpdateItem
  /// с рассылкой изменений участникам. Локальное событие (не с сервера) —
  /// только в базе (вызывающий обновляет строку сам).
  ///
  /// 1.6.7 (замечание 13.10.2026, «как в Outlook»):
  /// * [onlyChanged] — обновление получают только добавленные и удалённые
  ///   участники (SendToChangedAndSaveCopy), остальным ничего не уходит;
  /// * [wholeSeries] — у вхождения серии меняется вся серия (сдвиг времени
  ///   переносится на главный элемент), иначе только это вхождение;
  /// * [original] — встреча до изменения: по ней элемент находится в EWS у
  ///   ящиков ActiveSync (у EAS и EWS разные идентификаторы).
  /// ActiveSync сам этого не умеет — нужен EWS ([canManageMeetings]); без
  /// него вхождение отдельно не меняется (UnsupportedError с пояснением).
  Future<void> updateEvent(AccountModel account, CalendarEventModel e,
      {bool onlyChanged = false, bool wholeSeries = false, MeetingOriginal? original}) async {
    final sendTo = onlyChanged ? 'SendToChangedAndSaveCopy' : 'SendToAllAndSaveCopy';
    if (account.usesEas) {
      if (!e.id.startsWith('eas_')) return;
      final occurrence = isOccurrenceId(e.id);
      if ((occurrence || onlyChanged) && account.hasEwsExtras && original != null) {
        try {
          if (await _updateViaEws(account, e, original: original, sendTo: sendTo, wholeSeries: occurrence && wholeSeries)) {
            if (occurrence || e.recurrence != RecurrenceType.none) await requestFullCalendarResync(account);
            return;
          }
          AppLogger.warning('updateEvent: встреча в EWS не найдена — через ActiveSync');
        } catch (err) {
          AppLogger.warning('updateEvent: EWS не изменил встречу ($err) — через ActiveSync');
        }
      }
      final sid = await saveEvent(account, e);
      if (sid == null) throw Exception('Сервер не принял изменение встречи');
      if (e.recurrence != RecurrenceType.none) await requestFullCalendarResync(account);
      return;
    }
    if (_usesDav(account)) {
      if (DavPimService.parseId(account.id, e.id) == null) return; // только локальное
      final auth = await _davAuth(account);
      if (auth == null) throw Exception('Нет доступа к календарю');
      await DavPimService().updateEvent(account, auth, e);
      return;
    }
    if (_ewsPrimary(account)) {
      final ok = await _updateViaEws(account, e, original: original, sendTo: sendTo, wholeSeries: wholeSeries);
      if (!ok) throw Exception('Сервер не принял изменение встречи');
    }
  }

  /// Можно ли у встреч выбирать получателей обновления, менять и удалять
  /// вхождение отдельно от серии и пересылать приглашение (1.6.7): всё это
  /// делает EWS (у ящиков ActiveSync — дополнительный адрес EWS).
  bool canManageMeetings(AccountModel account) =>
      account.usesEas ? account.hasEwsExtras : _ewsPrimary(account);

  /// Входит ли событие в повторяющуюся серию. ActiveSync — по id вхождения
  /// («…#день»); EWS разворачивает серии сам, у вхождения нет правила —
  /// спрашиваем сервер, есть ли у него главный элемент серии.
  Future<bool> isSeriesOccurrence(AccountModel account, String id, int recurrence) async {
    if (isOccurrenceId(id)) return true;
    if (account.usesEas || !_ewsPrimary(account)) return false;
    if (recurrence != 0) return true;
    return await _ews.getRecurringMaster(account, id) != null;
  }

  /// ItemId встречи в EWS: у EWS-ящика — сам id, у ActiveSync — поиск по
  /// началу и теме.
  Future<String?> _ewsItemIdOf(AccountModel account, String id, MeetingOriginal? original) async {
    if (!account.usesEas) return id;
    if (original == null) return null;
    return _ews.findCalendarItemId(account, start: original.start, end: original.end, subject: original.title);
  }

  Future<bool> _updateViaEws(AccountModel account, CalendarEventModel e,
      {MeetingOriginal? original, required String sendTo, bool wholeSeries = false}) async {
    var id = await _ewsItemIdOf(account, e.id, original);
    if (id == null) return false;
    var ev = e;
    if (wholeSeries) {
      final m = await _ews.getRecurringMaster(account, id);
      if (m == null) return false;
      // Сдвиг времени вхождения переносится на всю серию: начало и конец
      // главного элемента сдвигаются на ту же величину.
      final ds = original == null ? Duration.zero : e.startTime.difference(original.start);
      final de = original == null ? Duration.zero : e.endTime.difference(original.end);
      ev = e.copyWith(startTime: m.start.add(ds).toLocal(), endTime: m.end.add(de).toLocal());
      id = m.id;
    }
    final ck = await _ews.getChangeKey(account, id);
    if (ck == null) return false;
    return _ews.updateCalendarEvent(account,
        itemId: id,
        changeKey: ck,
        event: ev,
        category: CategoryColors.categoryFor(e.colorValue, russian: _mailboxRussian()),
        sendTo: sendTo);
  }

  /// Переслать приглашение на встречу (1.6.7): Exchange отправляет
  /// получателям приглашение от имени организатора и сообщает ему об этом.
  /// false — EWS недоступен или встреча на сервере не найдена.
  Future<bool> forwardMeeting(AccountModel account, String id,
      {required MeetingOriginal original, required List<EmailAddress> to, String note = ''}) async {
    if (!canManageMeetings(account) || to.isEmpty) return false;
    final itemId = await _ewsItemIdOf(account, id, original);
    if (itemId == null) return false;
    return _ews.forwardCalendarItem(account, itemId: itemId, to: to, note: note);
  }

  /// Удалить событие календаря: EAS → движок, EWS → ews_service.
  /// Отклонить встречу, на которую нас пригласили, и убрать её из
  /// календаря — как «Удалить» у чужой встречи в Outlook (1.5.12). Раньше
  /// встреча просто удалялась: организатор считал, что участник придёт.
  /// false — сервер так не умеет (ActiveSync до 16.0) или отказал: вызывающий
  /// удаляет встречу как раньше.
  ///
  /// [wholeSeries] = false у вхождения серии ActiveSync — отклонить только
  /// его через EWS (1.6.7); сам ActiveSync отвечает на всю серию.
  Future<bool> declineEvent(AccountModel account, String itemId,
      {String? comment, bool wholeSeries = true, MeetingOriginal? original}) async {
    final master = isOccurrenceId(itemId) ? itemId.substring(0, itemId.indexOf('#')) : itemId;
    if (account.usesEas && !wholeSeries && isOccurrenceId(itemId) && account.hasEwsExtras) {
      final id = await _ewsItemIdOf(account, itemId, original);
      if (id == null) return false;
      final r = await _ews.respondToMeeting(account, itemId: id, response: 'decline', comment: comment);
      if (!r.ok) return false;
      try {
        await _ews.deleteCalendarEvent(account, itemId: id);
      } catch (_) {}
      await requestFullCalendarResync(account);
      return true;
    }
    if (!account.usesEas && _ewsPrimary(account)) {
      final r = await _ews.respondToMeeting(account, itemId: itemId, response: 'decline', comment: comment);
      if (!r.ok) return false;
      // Exchange обычно сам убирает отклонённую встречу; если нет — удаляем.
      try {
        await _ews.deleteCalendarEvent(account, itemId: itemId);
      } catch (_) {}
      return true;
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null || (double.tryParse(eas.protocolVersion) ?? 0) < 16) return false;
      final fid = await _pimFolderId(account, me.MailFolderType.calendar);
      if (fid == null) return false;
      final res = await eas.meetingResponse(
          collectionId: fid, requestId: _serverId(master), userResponse: 3, comment: comment);
      if (res == null) return false;
      try {
        await deleteEventServer(account, master);
      } catch (_) {}
      return res.sent;
    }
    return false;
  }

  /// Можно ли ответить на встречу прямо из календаря (1.6.34): ActiveSync
  /// 16+ (MeetingResponse по элементу календаря) или EWS.
  bool canRespondToEvent(AccountModel account) => account.usesEas || _ewsPrimary(account);

  /// Ответ на встречу из календаря (1.6.34, замечание 18.10.2026: «от
  /// встречи нельзя отказаться или предложить перенести»): принять, под
  /// вопросом, отклонить; с комментарием, без отправки организатору или с
  /// новым временем — как в письме-приглашении. ActiveSync отвечает на всю
  /// серию (элемент на сервере один); нужен протокол 16+ — раньше сервер
  /// ответ по элементу календаря не принимает.
  Future<({bool ok, bool sent, bool proposed})> respondToEvent(
    AccountModel account,
    String eventId, {
    required String response,
    bool send = true,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
  }) async {
    const fail = (ok: false, sent: false, proposed: false);
    if (response == 'accept') {
      proposedStart = null;
      proposedEnd = null;
    }
    if (!account.usesEas && _ewsPrimary(account)) {
      final r = await _ews.respondToMeeting(account,
          itemId: eventId,
          response: response,
          send: send,
          comment: comment,
          proposedStart: proposedStart,
          proposedEnd: proposedEnd);
      return (ok: r.ok, sent: r.ok && send, proposed: r.proposed);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return fail;
      if ((double.tryParse(eas.protocolVersion) ?? 0) < 16) {
        AppLogger.warning('Ответ на встречу из календаря: ActiveSync ${eas.protocolVersion} < 16');
        return fail;
      }
      final fid = await _pimFolderId(account, me.MailFolderType.calendar);
      if (fid == null) return fail;
      final res = await eas.meetingResponse(
        collectionId: fid,
        requestId: _serverId(eventId),
        userResponse: response == 'accept' ? 1 : (response == 'tentative' ? 2 : 3),
        notifyOrganizer: send,
        comment: comment,
        proposedStart: proposedStart,
        proposedEnd: proposedEnd,
      );
      if (res == null) return fail;
      AppLogger.info('Ответ на встречу из календаря: $response, организатору: ${res.sent}');
      return (ok: true, sent: res.sent, proposed: res.proposed);
    }
    return fail;
  }

  /// Переслать приглашение силами ActiveSync (1.6.34): SmartForward элемента
  /// календаря — Exchange отправляет получателям настоящее приглашение
  /// (с кнопками ответа), организатор получает уведомление о пересылке.
  /// Раньше без EWS была только «Поделиться» текстом.
  Future<bool> forwardMeetingEas(AccountModel account, String eventId,
      {required List<EmailAddress> to, required String title, String note = ''}) async {
    if (!account.usesEas || to.isEmpty) return false;
    final eas = await _easEngine(account);
    if (eas == null) return false;
    final fid = await _pimFolderId(account, me.MailFolderType.calendar);
    if (fid == null) return false;
    try {
      await eas.smartForward(
        folderId: fid,
        itemId: _serverId(eventId),
        message: me.OutgoingMessage(
          to: [for (final a in to) me.MailAddress(a.email, a.displayName)],
          subject: title.trim().isEmpty ? 'FW:' : 'FW: ${title.trim()}',
          // HTML, а не текст (1.6.37): Exchange дописывает под текстом шапку
          // пересылки (От, Отправлено, Кому, Тема, Когда, Где) в HTML; в
          // текстовое письмо она попадала с кодами букв — «When: 31
          // &#1086;&#1082;…» (замечание 18.10.2026).
          bodyHtml: '<div>${const HtmlEscape().convert(note.trim()).replaceAll('\n', '<br>')}</div>',
        ),
      );
      AppLogger.info('Приглашение переслано (ActiveSync): получателей ${to.length}');
      return true;
    } catch (e) {
      AppLogger.warning('Пересылка приглашения (ActiveSync): $e');
      return false;
    }
  }

  /// [wholeSeries] = false у вхождения серии — удалить только его (1.6.7;
  /// у ActiveSync — через EWS: сам ActiveSync удаляет только всю серию).
  Future<void> deleteEvent(AccountModel account, String itemId,
      {bool wholeSeries = true, MeetingOriginal? original}) async {
    if (account.usesEas) {
      if (!wholeSeries && isOccurrenceId(itemId)) {
        final id = account.hasEwsExtras ? await _ewsItemIdOf(account, itemId, original) : null;
        if (id == null) throw Exception('Вхождение встречи на сервере не найдено');
        if (!await _ews.deleteCalendarEvent(account, itemId: id)) {
          throw Exception('Сервер не удалил вхождение встречи');
        }
        await requestFullCalendarResync(account);
        return;
      }
      await deleteEventServer(account, itemId);
      return;
    }
    if (_usesDav(account)) {
      if (DavPimService.parseId(account.id, itemId) == null) return; // только локальное
      final auth = await _davAuth(account);
      if (auth == null) throw Exception('Нет доступа к календарю');
      await DavPimService().deleteEvent(account, auth, itemId);
      return;
    }
    if (!_ewsPrimary(account)) return;
    await _ews.deleteCalendarEvent(account, itemId: itemId, series: wholeSeries && await isSeriesOccurrence(account, itemId, 0));
  }

  /// Создать контакт: EAS → движок, EWS → ews_service.
  Future<String?> createContactEntry(AccountModel account, ContactModel c) async {
    if (account.usesEas || _usesDavContacts(account)) return saveContact(account, c);
    if (!_ewsPrimary(account)) return null;
    return _ews.createContact(account, contact: c);
  }

  /// Контакты по CardDAV (у Mail.ru CardDAV нет).
  bool _usesDavContacts(AccountModel account) =>
      _usesDav(account) && DavPimService.canWriteContacts(account);

  /// Можно ли менять контакты аккаунта на сервере из приложения.
  bool canWriteContacts(AccountModel account) =>
      account.usesEas || _ewsPrimary(account) || _usesDavContacts(account);

  /// Удалить контакт: EAS → движок, EWS → ews_service.
  Future<void> deleteContactEntry(AccountModel account, String itemId) async {
    if (account.usesEas) { await deletePim(account, me.MailFolderType.contacts, itemId); return; }
    if (_usesDavContacts(account)) {
      final auth = await _davAuth(account, contacts: true);
      if (auth == null) throw Exception('Нет доступа к контактам');
      await DavPimService().deleteContact(account, auth, itemId);
      return;
    }
    if (!_ewsPrimary(account)) return;
    await _ews.deleteContact(account, itemId: itemId);
  }

  /// Серверный поиск (EWS AQS); для прочих — пусто (локальный FTS остаётся в UI).
  Future<List<EmailModel>> serverSearch(AccountModel account, String query,
      {int maxResults = 50}) async {
    if (_ewsPrimary(account)) {
      return _ews.searchEmails(account, query: query, maxResults: maxResults);
    }
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return const [];
      final hits = await eas.searchMailbox(query, limit: maxResults);
      return hits.map((h) => _hitToEmail(account, h)).toList();
    }
    // IMAP (Gmail, Яндекс, Mail.ru, Yahoo, свой сервер): UID SEARCH.
    final imap = _ref?.read(imapServiceProvider);
    if (imap != null) return imap.searchMailbox(account, query, limit: maxResults);
    return const [];
  }

  /// Папка (CollectionId) писем из серверного поиска ActiveSync:
  /// «аккаунт|id письма» → папка. Нужна, чтобы отметку «прочитано» или флаг
  /// на найденном письме донести до сервера (см. applyFlagsToSearchHit).
  final Map<String, String> _searchHitFolders = {};

  /// Прочитано/флаг для письма из серверного поиска ActiveSync. У такого
  /// письма есть только LongId, а команда Sync меняет письмо по ServerId
  /// папки. ServerId находим командой Find (ActiveSync 16.1) в папке письма
  /// по теме, отправителю и дате. true — сервер принял изменение.
  Future<bool> applyFlagsToSearchHit(
    AccountModel account, {
    required String emailId,
    required String subject,
    required String fromEmail,
    required DateTime receivedAt,
    bool? read,
    bool? flagged,
  }) async {
    final folder = _searchHitFolders['${account.id}|$emailId'];
    if (folder == null || !account.usesEas) return false;
    final eas = await _easEngine(account);
    if (eas == null) return false;
    String norm(String v) => v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final query = subject.trim().isNotEmpty ? subject.trim() : fromEmail;
    final hits = await eas.findInFolder(folder, query.length > 120 ? query.substring(0, 120) : query);
    if (hits == null || hits.isEmpty) return false;
    me.EasFindHit? match;
    for (final h in hits) {
      if (norm(h.subject ?? '') != norm(subject)) continue;
      final from = (h.from ?? '').toLowerCase();
      if (fromEmail.isNotEmpty && !from.contains(fromEmail.toLowerCase())) continue;
      final d = DateTime.tryParse(h.dateReceived ?? '');
      if (d != null && d.difference(receivedAt).abs() > const Duration(minutes: 2)) continue;
      match = h;
      break;
    }
    if (match == null) {
      AppLogger.info('Поиск: письмо «$subject» не найдено командой Find — изменение только на телефоне');
      return false;
    }
    final hit = match;
    return _serial(account.id, () async {
      _seedKey(account, eas, hit.collectionId);
      if (!eas.hasMailSyncKey(hit.collectionId)) {
        AppLogger.info('Поиск: папка ${hit.collectionId} не синхронизируется — изменение только на телефоне');
        return false;
      }
      try {
        await eas.applyFlags(
          me.MessageRef(id: hit.serverId, folderId: hit.collectionId, serverId: hit.serverId),
          read: read,
          flagged: flagged,
          strict: true,
        );
        AppLogger.info('Поиск: изменение письма «$subject» отправлено на сервер');
        return true;
      } catch (e) {
        AppLogger.warning('Поиск: сервер не принял изменение письма «$subject»: $e');
        return false;
      } finally {
        await _persistKey(account, eas, hit.collectionId);
      }
    });
  }

  /// EAS-результат поиска → EmailModel (минимальный: тело догружается при открытии).
  EmailModel _hitToEmail(AccountModel account, me.EasSearchHit h) {
    final col = h.collectionId;
    if (col != null && col.isNotEmpty) {
      if (_searchHitFolders.length > 2000) _searchHitFolders.clear();
      _searchHitFolders['${account.id}|eas_${h.serverId}'] = col;
    }
    // From может быть "Имя <адрес>" или просто адрес.
    String email = h.from ?? '';
    String? name;
    final m = RegExp(r'^(.*?)<([^>]+)>').firstMatch(h.from ?? '');
    if (m != null) {
      name = m.group(1)!.trim().replaceAll('"', '');
      email = m.group(2)!.trim();
    }
    return EmailModel(
      // Найденное письмо открывается по LongId (ItemOperations), а не по
      // ServerId папки: раньше оно не открывалось — в базе его не было,
      // а папка и id не совпадали с синхронизированными.
      id: 'eas_${h.serverId}',
      accountId: account.id,
      folderId: me.EasEngine.searchFolderId,
      from: EmailAddress(email: email, displayName: name?.isNotEmpty == true ? name : null),
      to: const [],
      subject: h.subject ?? '',
      receivedAt: DateTime.tryParse(h.dateReceived ?? '') ?? DateTime.now(),
      bodyPreview: h.preview,
    );
  }

  /// Полная карточка письма по EWS (для дозагрузки тела на Exchange).
  Future<EmailModel?> fetchEmailDetailEws(AccountModel account, String emailId) async =>
      _ewsPrimary(account) ? _ews.getEmailDetail(account, emailId: emailId) : null;

  /// Поддерживает ли аккаунт ПЕРЕСЫЛКУ НА СЕРВЕРЕ (без скачивания вложений).
  /// EWS — ForwardItem, EAS — SmartForward. IMAP/SMTP такого не умеют в
  /// принципе: в IMAP нет команды пересылки, а SMTP требует готовый MIME от
  /// клиента.
  bool supportsServerForward(AccountModel account) =>
      _ewsPrimary(account) || account.usesEas;

  /// Переслать письмо силами сервера: оригинальные вложения не скачиваются на
  /// устройство и не отправляются обратно. Возвращает false, если протокол так
  /// не умеет — тогда вызывающий собирает письмо сам.
  Future<bool> forwardOnServer(
    AccountModel account, {
    required String itemId,
    String? changeKey,
    required String folderId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    required String subject,
    required String bodyHtml,
    String? clientId,
    /// Пометка Outlook и гриф в MIME («Confidential|dsp|no-forward»).
    String sensitivity = 'Normal',
    /// Шапка цитаты («От / Отправлено / Кому / Тема» под линией) — для
    /// ActiveSync: SmartForward дописывает исходное письмо без неё.
    String? easQuoteHeader,
  }) async {
    if (_ewsPrimary(account)) {
      // ForwardItem EWS не принимает своих заголовков письма: с грифом в
      // MIME пересылаем обычной отправкой (CreateItem с заголовками).
      if (sensitivity.contains('|')) return false;
      return _ews.forwardOnServer(
        account,
        referenceItemId: itemId,
        referenceChangeKey: changeKey,
        to: to,
        cc: cc,
        bodyHtml: bodyHtml,
        newSubject: subject,
      );
    }
    // Подписанное/зашифрованное письмо сервер дополнить не может.
    if (MailLabel.decode(sensitivity).smime) return false;
    if (account.usesEas) {
      // SmartForward — тем же подключением движка, что и синхронизация
      // (раньше — отдельным старым стеком со своим PolicyKey).
      final eas = await _easEngine(account);
      if (eas == null) return false;
      try {
        await eas.smartForward(
          folderId: _serverId(folderId),
          itemId: _serverId(itemId),
          message: me.OutgoingMessage(
            to: [for (final a in to) me.MailAddress(a.email, a.displayName)],
            cc: [for (final a in cc) me.MailAddress(a.email, a.displayName)],
            subject: subject,
            bodyHtml: withEasQuoteHeader(bodyHtml, easQuoteHeader),
            sensitivity: sensitivity,
            clientId: clientId,
          ),
        );
        return true;
      } catch (e) {
        AppLogger.warning('EAS SmartForward ${account.email}: $e');
        return false;
      }
    }
    return false;
  }

  /// Новый текст ответа или пересылки ActiveSync + пустая строка + шапка
  /// цитаты, как у Outlook: сервер допишет исходное письмо сразу после неё.
  @visibleForTesting
  static String withEasQuoteHeader(String bodyHtml, String? header) =>
      (header == null || header.isEmpty) ? bodyHtml : '$bodyHtml<div><br></div>$header';

  /// Ответ силами сервера (ActiveSync SmartReply, EWS ReplyToItem): исходное письмо с
  /// вложениями не скачивается и не отправляется заново, цитату добавляет
  /// сервер. [bodyHtml] — только новый текст ответа, без цитаты.
  /// false — протокол так не умеет или сервер отказал: вызывающий отправляет
  /// обычное письмо с цитатой.
  Future<bool> replyOnServer(
    AccountModel account, {
    required String itemId,
    required String folderId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    required String subject,
    required String bodyHtml,
    String? clientId,
    /// Пометка Outlook и гриф в MIME («Confidential|dsp|no-forward»).
    String sensitivity = 'Normal',
    /// «Ответить всем» — для EWS (получателей там выбирает сервер).
    bool replyAll = false,
    /// Шапка цитаты для ActiveSync: SmartReply дописывает исходное письмо
    /// без шапки и без отступа — ответ и исходное письмо сливались под
    /// подписью (замечание владельца 27.10.2026). EWS (ReplyToItem) шапку
    /// добавляет сам.
    String? easQuoteHeader,
  }) async {
    if (MailLabel.decode(sensitivity).smime) return false;
    if (_ewsPrimary(account)) {
      // Как и ForwardItem: своих заголовков письма (гриф в MIME) EWS здесь
      // не принимает — такое письмо уходит обычной отправкой.
      if (sensitivity.contains('|')) return false;
      return _ews.replyOnServer(
        account,
        referenceItemId: itemId,
        all: replyAll,
        bodyHtml: bodyHtml,
        newSubject: subject,
      );
    }
    if (!account.usesEas) return false;
    final eas = await _easEngine(account);
    if (eas == null) return false;
    try {
      await eas.smartReply(
        folderId: _serverId(folderId),
        itemId: _serverId(itemId),
        message: me.OutgoingMessage(
          to: [for (final a in to) me.MailAddress(a.email, a.displayName)],
          cc: [for (final a in cc) me.MailAddress(a.email, a.displayName)],
          subject: subject,
          bodyHtml: withEasQuoteHeader(bodyHtml, easQuoteHeader),
          sensitivity: sensitivity,
          clientId: clientId,
        ),
      );
      return true;
    } catch (e) {
      AppLogger.warning('EAS SmartReply ${account.email}: $e');
      return false;
    }
  }

  /// Direct Push для ActiveSync: поток списков папок, в которых сервер
  /// сообщил об изменениях. Ping идёт тем же подключением движка, что и
  /// синхронизация, — один DeviceId и один PolicyKey на устройство.
  /// Поток бесконечный; останавливается отменой подписки.
  Stream<List<String>> easPushChanges(AccountModel account, List<String> folderIds) {
    // Цикл на StreamController, а не async*: отписка от async*-генератора
    // срабатывает только на следующем yield, а он бывает лишь при новых
    // письмах. Остановка push (выход из аккаунта, перезапуск) ждала бы его
    // часами, а старый цикл Ping продолжал бы работать параллельно новому.
    late final StreamController<List<String>> ctrl;
    var stopped = false;
    Future<void> loop() async {
      // Сервер ограничивает число папок в Ping (Status 6); «Входящие» и
      // несколько пользовательских папок — практический предел.
      final ids = folderIds.take(25).toList();
      // 8 минут — проходит через типичные прокси и NAT. Интервал, который
      // выдерживает шлюз этого ящика, запоминается: раньше после каждого
      // перезапуска push (смена сети — до 17 раз в день) первый Ping снова
      // шёл на 8 минут и обрывался шлюзом (журнал 11.10.2026).
      final hbKey = 'eas_ping_heartbeat_${account.id}';
      final prefs = _ref?.read(sharedPrefsProvider);
      var heartbeat = (prefs?.getInt(hbKey) ?? 480).clamp(60, 1680);
      var errors = 0;
      var lastOk = DateTime.now(); // последний успешный Ping
      int? lastDropWaited; // время прошлого обрыва без HTTP-ответа (сек)
      // Обрывы Ping шлюзом за последние 10 минут. Если их много, долгий
      // запрос через этот шлюз не живёт: на 10 минут переходим на короткие
      // запросы — раз в минуту синхронизация «Входящих» (запрос < 1 с),
      // раз в 5 минут — всех папок push. Затем снова пробуем Ping.
      final cuts = <DateTime>[];
      DateTime? pollUntil;
      var pollTick = 0;
      // Ping подряд отвечает «изменения» сразу (< 3 с): изменения не
      // забираются — синхронизация ящика занята или падает. Без паузы это
      // два запроса в секунду (журнал 13.10.2026: 144 Ping за 90 с, пока
      // ящик держала аренда прежнего процесса).
      var quickChanges = 0;
      Future<void> pause(int seconds) async {
        // Пауза короткими шагами, чтобы остановка не ждала её окончания.
        for (var t = 0; t < seconds && !stopped; t++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      while (!stopped) {
        // Любое исключение (сеть, разбор ответа, движок) раньше завершало
        // цикл навсегда: подписка оставалась «живой», а Ping больше не шёл —
        // push молчал до перезапуска приложения. Теперь — пауза и повтор.
        try {
        markPushAlive(account.id);
        final pu = pollUntil;
        if (pu != null) {
          if (DateTime.now().isBefore(pu)) {
            pollTick++;
            ctrl.add(pollTick % 5 == 0 ? ids : [ids.first]);
            // Свёрнуто — раз в 2 минуты: каждый короткий запрос будит радио,
            // а на экране письма важнее сразу.
            final open = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
            await pause(open ? 60 : 120);
            continue;
          }
          pollUntil = null;
          cuts.clear();
          AppLogger.info('EAS push ${account.email}: снова пробуем Ping');
        }
        // iPhone: свёрнутое приложение iOS замораживает, и начатый Ping
        // «висит» до пробуждения, а потом падает по тайм-ауту (журнал
        // 20.10.2026: каждые 15 минут при фоновой проверке). Пока свёрнуто —
        // новый Ping не начинаем: почту проверяет фоновая задача iOS, а при
        // открытии приложения Ping начнётся снова (в течение 2 с).
        if (_iosSuspended) {
          await pause(2);
          continue;
        }
        final eas = await _easEngine(account);
        if (stopped) break;
        if (eas == null) {
          errors++;
          await pause((15 * errors).clamp(15, 300));
          continue;
        }
        eas.quietPingErrors = () => _iosSuspended;
        final sw = Stopwatch()..start();
        final r = await eas.ping(ids, heartbeatSeconds: heartbeat);
        sw.stop();
        if (stopped) break;
        // Ping прервало сворачивание на iPhone — это не сбой связи: не
        // считаем его ни ошибкой, ни обрывом шлюзом (иначе интервал Ping
        // напрасно уменьшался бы).
        if (r.status != 1 && r.status != 2 && (_iosSuspended ||
            sw.elapsed > Duration(seconds: heartbeat + 90))) {
          continue;
        }
        markPushAlive(account.id);
        // После серии сбоев Ping не знает, что пришло за время обрыва, —
        // просим синхронизировать папки один раз.
        // Короткий обрыв (502 от шлюза перед Exchange — у этого сервера
        // случается несколько раз в час) не требует синхронизировать все
        // папки: сервер сам сообщит в Ping о неполученных изменениях. Раньше
        // каждый такой обрыв запускал синхронизацию пяти папок подряд.
        if (errors > 0 && (r.status == 1 || r.status == 2) &&
            DateTime.now().difference(lastOk) > const Duration(minutes: 3)) {
          AppLogger.info('EAS push ${account.email}: связь восстановлена — догоняем пропущенное');
          if (r.status == 1) ctrl.add(ids);
        }
        if (r.status == 1 || r.status == 2) lastOk = DateTime.now();
        switch (r.status) {
          case 1: // таймаут ожидания — изменений нет
            errors = 0;
            quickChanges = 0;
            lastDropWaited = null;
            break;
          case 2:
            errors = 0;
            lastDropWaited = null;
            ctrl.add(r.changed.isEmpty ? ids : r.changed);
            if (sw.elapsed < const Duration(seconds: 3)) {
              quickChanges++;
              if (quickChanges >= 3) {
                final wait = (5 * (1 << (quickChanges - 3).clamp(0, 3))).clamp(5, 30);
                if (quickChanges == 3) {
                  AppLogger.info('EAS push ${account.email}: изменения не забираются — пауза между Ping');
                }
                await pause(wait);
              }
            } else {
              quickChanges = 0;
            }
            break;
          case 5: // сервер просит другой интервал
            if (r.heartbeat != null && r.heartbeat! > 0) heartbeat = r.heartbeat!;
            break;
          case 7:
            // Иерархия папок изменилась: без FolderSync сервер будет отвечать 7
            // на каждый Ping. Обновляем список папок, затем синхронизируем.
            try {
              await eas.listFolders();
            } catch (e) {
              AppLogger.warning('EAS push ${account.email}: FolderSync — $e');
            }
            ctrl.add(ids);
            await pause(5);
            break;
          default:
            errors++;
            // Ping оборвался заметно раньше интервала: обычно его режет
            // обратный прокси перед Exchange (у nginx по умолчанию 60 с) —
            // 502/504 или обрыв соединения. С тем же интервалом push не
            // заработает никогда, поэтому уменьшаем его до фактического
            // времени ожидания минус запас (не меньше 60 с — минимум Exchange).
            // 502/504 — прокси сказал об этом явно. Обрыв без ответа (код 0)
            // бывает и при плохой связи, поэтому считается только если
            // повторился дважды подряд примерно в одно время.
            final waited = sw.elapsed.inSeconds;
            final explicitCut = eas.lastStatus == 502 || eas.lastStatus == 504;
            final drop = eas.lastStatus == 0;
            final prevDrop = lastDropWaited;
            final repeatedDrop = drop && prevDrop != null && (waited - prevDrop).abs() <= 10;
            lastDropWaited = drop ? waited : null;
            final cut = explicitCut || repeatedDrop;
            // Обрыв раньше, чем сервер ответил бы сам (через heartbeat
            // секунд). Раньше требовалось «на 30 с раньше»: шлюз, режущий
            // на 240 с, при интервале 246 с обрывал каждый Ping — 502 раз
            // в 4 минуты весь день (журнал 11.10.2026: 87 раз).
            if (cut && waited >= 45 && waited <= heartbeat - 3 && heartbeat > 60) {
              lastDropWaited = null;
              final next = (waited - 15).clamp(60, heartbeat);
              AppLogger.warning('EAS push ${account.email}: Ping оборван через $waited с '
                  '(HTTP ${eas.lastStatus}) — интервал $heartbeat → $next с');
              heartbeat = next;
              try {
                await prefs?.setInt(hbKey, next);
              } catch (_) {}
              errors = 0;
              break;
            }
            // Обрыв шлюзом (502/503/504) или без ответа: считаем; при
            // частых — режим коротких запросов (см. pollUntil).
            final st = eas.lastStatus;
            if (st == 0 || st == 502 || st == 503 || st == 504) {
              final now = DateTime.now();
              cuts.add(now);
              cuts.removeWhere((t) => now.difference(t) > const Duration(minutes: 10));
              if (cuts.length >= 4) {
                pollUntil = now.add(const Duration(minutes: 10));
                pollTick = 0;
                errors = 0;
                AppLogger.warning('EAS push ${account.email}: Ping обрывается '
                    '(${cuts.length} раз за 10 мин) — 10 минут проверяем почту короткими запросами');
                ctrl.add(ids); // забрать пришедшее за время обрывов
                break;
              }
            }
            if (st == 503) {
              // Шлюз просит подождать с Ping (не с остальными командами):
              // пока ждём — одна короткая синхронизация «Входящих».
              final until = eas.pingBusyUntil;
              ctrl.add([ids.first]);
              final secs = until == null ? 30 : until.difference(DateTime.now()).inSeconds.clamp(5, 120);
              await pause(secs);
              break;
            }
            if (st == 401) {
              // Повторять Ping с отвергнутым паролем нельзя: каждый повтор —
              // неудачный вход, и через несколько попыток AD блокирует учётную
              // запись. Останавливаем push; решение (пароль сменили или это
              // сбой шлюза) принимает обычная синхронизация — PushAuthFailure.
              disconnect(account.id);
              AppLogger.warning('EAS push ${account.email}: 401 — push остановлен до проверки входа');
              stopped = true;
              if (!ctrl.isClosed) {
                ctrl.addError(const PushAuthFailure());
                await ctrl.close();
              }
              return;
            }
            // Явный обрыв шлюзом (502/504) — шум прокси, а не недоступность
            // сервера: первые повторы через 3 с (Ping сам сообщит о
            // накопившихся изменениях). Остальное — нарастающая пауза.
            await pause(explicitCut && errors <= 3 ? 3 : (10 * errors).clamp(10, 300));
        }
        } catch (e) {
          if (stopped) break;
          errors++;
          AppLogger.warning('EAS push ${account.email}: сбой цикла — $e; повтор');
          await pause((10 * errors).clamp(10, 300));
        }
      }
    }

    ctrl = StreamController<List<String>>(
      onListen: () => unawaited(loop().catchError((Object e) {
        AppLogger.warning('EAS push ${account.email}: $e');
      })),
      onCancel: () {
        stopped = true;
      },
    );
    return ctrl.stream;
  }

  /// Байты вложения письма — для ЛЮБОГО транспорта.
  ///
  /// Раньше метод всегда шёл в EWS, а экраны выбирали ветку по
  /// `account.isExchange`: у ActiveSync-аккаунтов (основной сценарий) запрос
  /// уходил в IMAP-ветку и вложение не открывалось вовсе.
  ///  · EAS — ItemOperations/Fetch по FileReference (это и есть id вложения);
  ///  · EWS — GetAttachment;
  ///  · IMAP — номер части MIME; id письма имеет вид «папка:uid».
  Future<Uint8List> getAttachmentBytes(AccountModel account, String attachmentId,
      {String? emailId}) async {
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) {
        throw Exception('Подключение к серверу не удалось: '
            '${_lastConnectError[account.id] ?? 'нет учётных данных'}');
      }
      return eas.fetchAttachment(attachmentId);
    }
    if (_ewsPrimary(account)) {
      return _ews.getAttachment(account, attachmentId: attachmentId);
    }
    final ref = _ref;
    if (ref == null || emailId == null) {
      throw UnsupportedError('IMAP: для скачивания вложения нужен id письма');
    }
    final sep = emailId.lastIndexOf(':');
    final uid = sep > 0 ? int.tryParse(emailId.substring(sep + 1)) : null;
    if (uid == null) throw StateError('Не удалось определить UID письма: $emailId');
    return ref.read(imapServiceProvider).fetchAttachment(account,
        folderId: emailId.substring(0, sep), uid: uid, partNumber: attachmentId);
  }

  /// Сервер ActiveSync не принял несколько Fetch в одном ItemOperations —
  /// дальше в этом сеансе по одному.
  bool _easBatchOff = false;

  /// Несколько вложений одного письма (встроенные картинки подписи): у
  /// ActiveSync — одним запросом, у остальных — по очереди. Ключ — id
  /// вложения; чего нет в ответе — не получено (1.5.6). Нет связи — ошибка.
  Future<Map<String, Uint8List>> getAttachmentsBytes(AccountModel account, List<String> attachmentIds,
      {required String emailId}) async {
    if (attachmentIds.isEmpty) return const {};
    if (account.usesEas) {
      final eas = await _easEngine(account);
      // Нет подключения — ошибка, а не «сервер ничего не отдал»: иначе
      // «Письма на телефоне» сочли бы картинки недоступными до перезапуска.
      if (eas == null) throw Exception('Подключение к серверу не удалось: ${_lastConnectError[account.id] ?? 'нет учётных данных'}');
      if (attachmentIds.length > 1 && !_easBatchOff) {
        final got = await eas.fetchAttachments(attachmentIds);
        if (got != null) return got;
        _easBatchOff = true;
        AppLogger.info('ActiveSync: сервер не принял несколько вложений в одном запросе — дальше по одному');
      }
      final out = <String, Uint8List>{};
      for (final id in attachmentIds) {
        try {
          out[id] = await eas.fetchAttachment(id);
        } catch (e) {
          AppLogger.debug('Вложение $id: $e');
        }
      }
      return out;
    }
    final out = <String, Uint8List>{};
    for (final id in attachmentIds) {
      try {
        out[id] = await getAttachmentBytes(account, id, emailId: emailId);
      } catch (e) {
        AppLogger.debug('Вложение $id: $e');
      }
    }
    return out;
  }

  /// Тексты нескольких писем ActiveSync одним запросом («Письма на
  /// телефоне», 1.5.6). Ключ — ServerId письма; чего нет — не получено.
  /// Нет связи — ошибка.
  Future<Map<String, ({String? bodyPlain, String? bodyHtml})>> fetchFullBodiesEas(
      AccountModel account, List<({String folderId, String serverId})> items) async {
    if (items.isEmpty) return const {};
    final eas = await _easEngine(account);
    // Нет подключения — ошибка: пустой ответ значил бы «у писем нет текста»,
    // и докачка не спрашивала бы их полсуток.
    if (eas == null) throw Exception('Подключение к серверу не удалось: ${_lastConnectError[account.id] ?? 'нет учётных данных'}');
    final refs = [
      for (final i in items) me.MessageRef(id: i.serverId, folderId: i.folderId, serverId: i.serverId),
    ];
    if (!_easBatchOff) {
      final got = await eas.fetchBodies(refs);
      if (got != null) return got;
      _easBatchOff = true;
      AppLogger.info('ActiveSync: сервер не принял несколько писем в одном запросе — дальше по одному');
    }
    final out = <String, ({String? bodyPlain, String? bodyHtml})>{};
    for (final r in refs) {
      final m = await eas.fetchMessage(r);
      if ((m.bodyHtml ?? '').isNotEmpty || (m.bodyPlain ?? '').isNotEmpty) {
        out[r.id] = (bodyPlain: m.bodyPlain, bodyHtml: m.bodyHtml);
      }
    }
    return out;
  }

  /// Очистить корзину: удалить [trashIds] из папки [trashFolderId]
  /// безвозвратно. Возвращает id, удалённые на сервере (их можно убрать
  /// локально; остальные останутся до следующей попытки).
  ///
  /// Раньше для EAS передавалась папка с именем 'trash' (у ActiveSync папки —
  /// числовые CollectionId, команда уходила в никуда), а IMAP не
  /// обрабатывался вовсе.
  Future<List<String>> emptyTrash(AccountModel account, List<String> trashIds,
      {required String trashFolderId}) async {
    final done = <String>[];
    if (account.usesEas) {
      for (final id in trashIds) {
        try {
          await deleteMessage(account, folderId: trashFolderId, serverId: id);
          done.add(id);
        } catch (e) {
          AppLogger.warning('emptyTrash EAS $id: $e');
        }
      }
    } else if (_ewsPrimary(account)) {
      for (final id in trashIds) {
        try {
          await _ews.deleteEmail(account, emailId: id, hardDelete: true);
          done.add(id);
        } catch (e) {
          AppLogger.warning('emptyTrash EWS: $e');
        }
      }
    } else {
      final imap = _ref?.read(imapServiceProvider);
      if (imap == null) return done;
      for (final id in trashIds) {
        try {
          await imap.deleteEmail(account, folderId: trashFolderId, uid: id, hard: true);
          done.add(id);
        } catch (e) {
          AppLogger.warning('emptyTrash IMAP $id: $e');
        }
      }
    }
    return done;
  }

  /// Синхронизировать папку, вернуть новые письма + токен состояния.
  ///
  /// Сервер EAS отдаёт изменения порциями по 25 (WindowSize) и сообщает
  /// MoreAvailable. Раньше бралась только первая порция, а следующая — лишь
  /// при следующем плановом синке: первичная загрузка ящика за неделю
  /// растягивалась на часы. Теперь порции забираются в цикле (с пределом,
  /// чтобы один большой ящик не держал синхронизацию остальных аккаунтов).
  ///
  /// [onBatch] — сохранить порцию в БД. Новый SyncKey записывается ТОЛЬКО
  /// после того, как порция сохранена: сервер считает письма доставленными,
  /// как только выдал следующий ключ, и повторно их не пришлёт. Раньше ключ
  /// писался в prefs до записи писем — убитый процесс, занятая фоновым
  /// изолятом БД или ошибка на следующей порции теряли письма навсегда.
  /// Если [onBatch] бросает исключение, ключ остаётся прежним, и следующая
  /// синхронизация получит ту же порцию заново (сервер повторяет ответ на
  /// предыдущий ключ; на более старый — Status 3 и полная перезагрузка папки,
  /// тоже без потерь).
  /// ActiveSync: в каких папках есть изменения — один запрос на все папки.
  /// Папка → число изменений; null — неизвестно (синхронизировать). Для
  /// остальных транспортов — пустой ответ.
  Future<Map<String, int?>> estimateMailChanges(AccountModel account, List<String> folderIds) =>
      _serial(account.id, () async {
        final engine = await _engineFor(account);
        if (engine is! me.EasEngine) return const <String, int?>{};
        final keys = <String, String>{
          for (final f in folderIds) f: _prefs.getString(_tokKey(account.id, f, 'mail')) ?? '0',
        };
        try {
          return await engine.estimateMailChanges(keys);
        } catch (e) {
          AppLogger.debug('GetItemEstimate: $e');
          return const <String, int?>{};
        }
      });

  /// Есть ли у папки сохранённый SyncKey почты. false — первая загрузка
  /// (или после сброса): уведомлять о «новых» письмах в этом случае нельзя.
  /// Сервер заставил загрузить папку ActiveSync заново (Status 3) с
  /// прошлого вызова — у писем новые ServerId (флаг сбрасывается).
  bool takeMailReinit(String accountId, String folderId) {
    final e = _engines[accountId];
    return e is me.EasEngine && e.takeMailReinit(folderId);
  }

  bool hasMailSyncState(String accountId, String folderId) {
    final k = _prefs.getString(_tokKey(accountId, folderId, 'mail'));
    return k != null && k.isNotEmpty && k != '0';
  }

  Future<EngineFolderSync> syncFolder(
    AccountModel account,
    String folderId, {
    String? sinceToken,
    int maxRounds = 20,
    Future<void> Function(EngineFolderSync batch)? onBatch,
  }) => _serial(account.id, () => _syncFolderImpl(account, folderId,
      sinceToken: sinceToken, maxRounds: maxRounds, onBatch: onBatch));

  Future<EngineFolderSync> _syncFolderImpl(
    AccountModel account,
    String folderId, {
    String? sinceToken,
    int maxRounds = 20,
    Future<void> Function(EngineFolderSync batch)? onBatch,
  }) async {
    final engine = await _engineFor(account);
    if (engine == null) {
      throw Exception('Подключение к серверу не удалось: '
          '${_lastConnectError[account.id] ?? 'нет учётных данных'}');
    }
    final added = <EmailModel>[];
    final deleted = <String>[];
    final flags = <me.MailFlagChange>[];
    String? token;
    var more = false;
    // Ключ, с которого идёт очередная порция: сначала сохранённый, дальше —
    // полученный в предыдущей порции (уже подтверждённый сохранением).
    String? current = sinceToken ?? _prefs.getString(_tokKey(account.id, folderId, 'mail'));
    for (var round = 0; round < maxRounds; round++) {
      final res = await engine.syncFolder(
        folderId,
        since: current != null ? me.SyncState(current) : null,
      );
      // Пароль сменили (или учётку заблокировали), пока приложение работало:
      // команда вернула 401. Сбрасываем подключение и сообщаем наверх — иначе
      // синхронизация тихо получала «пусто», и ошибка входа не показывалась.
      if (engine is me.EasEngine && engine.lastStatus == 401) {
        disconnect(account.id);
        throw Exception('EAS: 401 Unauthorized');
      }
      // Ответа не было (обрыв, 5xx, таймаут, «сервер просил подождать»):
      // раньше это выглядело как «изменений нет», папка считалась
      // синхронизированной, а проход шёл дальше и ждал таймаута на каждой
      // следующей папке. Теперь — ошибка: проход останавливается сразу.
      if (engine is me.EasEngine && res.newState == null && engine.lastStatus != 200) {
        // Сетевая причина — в тексте ошибки: по ней «сервер не найден (DNS)»,
        // «нет связи» и т. п. видны в ящике, а не только «HTTP 0».
        final net = engine.lastStatus == 0 ? engine.lastNetError : null;
        throw Exception('EAS Sync: нет ответа (HTTP ${engine.lastStatus})${net == null ? '' : ' — $net'}');
      }
      final batch = EngineFolderSync(
        added: [for (final m in [...res.added, ...res.changed]) _toEmailModel(account.id, m)],
        deletedIds: res.deleted.map((r) => r.id).toList(),
        flagChanges: res.flagChanges,
        newSyncToken: res.newState?.token,
        moreAvailable: res.moreAvailable,
      );
      // Сначала порция в БД, потом ключ. Исключение из onBatch прерывает
      // цикл, ключ в prefs остаётся прежним.
      if (onBatch != null) {
        try {
          await onBatch(batch);
        } catch (_) {
          if (engine is me.EasEngine) engine.restoreMailSyncKey(folderId, current ?? '0');
          rethrow;
        }
      }
      final newKey = res.newState?.token;
      if (newKey != null) {
        await _prefs.setString(_tokKey(account.id, folderId, 'mail'), newKey);
        current = newKey;
        token = newKey;
      }
      added.addAll(batch.added);
      deleted.addAll(batch.deletedIds);
      flags.addAll(batch.flagChanges);
      more = res.moreAvailable;
      if (!more) break;
    }
    if (more) {
      AppLogger.info('Синк ${account.email}/$folderId: часть изменений осталась '
          'на сервере — заберём в следующий раз');
    }
    return EngineFolderSync(
      added: added,
      deletedIds: deleted,
      flagChanges: flags,
      newSyncToken: token,
      moreAvailable: more,
    );
  }

  /// Отправить письмо.
  Future<bool> send(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    String subject = '',
    String? bodyPlain,
    String? bodyHtml,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String? inReplyTo,
    String importance = 'Normal',
    String sensitivity = 'Normal',
    String? clientId,
    EmailAddress? from,
  }) async {
    // Ошибка отправки — исключение, а не false: вызывающие (очередь
    // отправки) по исключению оставляют письмо в «Исходящих» и повторяют.
    // Раньше false молча проглатывался, и неотправленное письмо считалось
    // ушедшим.
    final engine = await _requireEngine(account);
    // S/MIME (подпись, шифрование) — ключ ящика у приложения; движок
    // отдаёт готовый MIME на обработку перед SendMail.
    final ref = _ref;
    final smime = ref?.read(smimeServiceProvider).senderFor(
        account.id, sensitivity, [for (final a in [...to, ...cc, ...bcc]) a.email]);
    if (smime == null && MailLabel.decode(sensitivity).smime) {
      throw StateError('S/MIME: сервис недоступен');
    }
    // Готовый MIME обрабатывает только ActiveSync (SendMail) — иначе письмо
    // ушло бы без подписи и шифрования, а это хуже, чем не уйти.
    if (smime != null && engine is! me.EasEngine) {
      throw StateError('S/MIME: этот способ подключения не поддерживает отправку');
    }
    try {
      await engine.send(me.OutgoingMessage(
        to: [for (final a in to) me.MailAddress(a.email, a.displayName)],
        cc: [for (final a in cc) me.MailAddress(a.email, a.displayName)],
        bcc: [for (final a in bcc) me.MailAddress(a.email, a.displayName)],
        subject: subject,
        bodyPlain: bodyPlain,
        bodyHtml: bodyHtml,
        attachments: [
          for (final a in attachments)
            me.MailAttachment(
              id: a.name,
              name: a.name,
              contentType: a.contentType,
              size: a.bytes.length,
              bytes: a.bytes,
            ),
        ],
        inReplyTo: inReplyTo,
        importance: importance,
        sensitivity: sensitivity,
        clientId: clientId,
        mimeTransform: smime,
        from: from == null ? null : me.MailAddress(from.email, from.displayName),
      ));
      return true;
    } catch (e) {
      AppLogger.error('MailEngine send ${account.email}: $e');
      if (engine is me.EasEngine && engine.lastStatus == 401) disconnect(account.id);
      rethrow;
    }
  }

  /// Сбросить подключение (например, при смене пароля/выходе). Сохранённый
  /// сеанс ActiveSync тоже забывается: следующее подключение — полное.
  void disconnect(String accountId) {
    _engines.remove(accountId)?.dispose();
    final email = _emailOf[accountId];
    if (email != null) forgetEasSession(email);
  }

  /// Адрес ящика по id — чтобы забыть сеанс ActiveSync при сбросе подключения.
  final Map<String, String> _emailOf = {};

  /// Забыть сохранённый сеанс ActiveSync ящика (eas_engine.dart, «сеанс между
  /// запусками»).
  void forgetEasSession(String email) {
    unawaited(_prefs.remove('eassession_${email.toLowerCase()}'));
  }

  Future<void> setRead(AccountModel account,
      {required String folderId, required String serverId, required bool isRead}) => _serial(account.id, () async {
    final engine = await _requireEngine(account);
    _seedKey(account, engine, folderId);
    await engine.applyFlags(
      me.MessageRef(id: serverId, folderId: folderId, serverId: serverId),
      read: isRead,
    );
    await _persistKey(account, engine, folderId);
  });

  Future<void> setFlag(AccountModel account,
      {required String folderId, required String serverId, required bool isFlagged}) => _serial(account.id, () async {
    final engine = await _requireEngine(account);
    _seedKey(account, engine, folderId);
    await engine.applyFlags(
      me.MessageRef(id: serverId, folderId: folderId, serverId: serverId),
      flagged: isFlagged,
    );
    await _persistKey(account, engine, folderId);
  });

  Future<void> moveMessage(AccountModel account,
      {required String fromFolderId, required String serverId, required String toFolderId}) => _serial(account.id, () async {
    final engine = await _requireEngine(account);
    await engine.move(
      me.MessageRef(id: serverId, folderId: fromFolderId, serverId: serverId),
      toFolderId,
    );
    // EAS выдаёт перемещённому письму НОВЫЙ ServerId. Если оставить старый,
    // синхронизация папки назначения пришлёт письмо под новым id — и в списке
    // окажутся два одинаковых письма, а действия над старым будут падать.
    if (engine is me.EasEngine) {
      final dst = engine.lastMoveDstId;
      final db = _ref?.read(databaseProvider);
      if (dst != null && dst.isNotEmpty && dst != serverId && db != null) {
        try {
          await (db.update(db.emails)
                ..where((e) => e.id.equals(serverId) & e.accountId.equals(account.id)))
              .write(EmailsCompanion(id: Value(dst), folderId: Value(toFolderId)));
          // Поисковый индекс ключуется id письма — переносим запись, иначе
          // поиск находил бы письмо по старому id (и не открывал его).
          try {
            await db.removeEmailFts(serverId, accountId: account.id);
            final row = await db.getEmailById(dst, accountId: account.id);
            if (row != null) {
              await db.indexEmailFts(
                emailId: dst,
                accountId: account.id,
                subject: row.subject,
                fromText: '${row.fromName ?? ''} ${row.fromEmail}',
                body: row.bodyPlain ?? row.bodyPreview ?? '',
              );
            }
          } catch (_) {}
        } catch (_) {
          // Строка с новым id уже пришла синком — старая просто лишняя.
          await (db.delete(db.emails)
                ..where((e) => e.id.equals(serverId) & e.accountId.equals(account.id)))
              .go();
        }
      }
    }
  });

  Future<void> deleteMessage(AccountModel account,
      {required String folderId, required String serverId}) => _serial(account.id, () async {
    final engine = await _requireEngine(account);
    _seedKey(account, engine, folderId);
    await engine.delete(
      me.MessageRef(id: serverId, folderId: folderId, serverId: serverId),
    );
    await _persistKey(account, engine, folderId);
  });

  /// Движок для ОПЕРАЦИИ (прочитано/флаг/перемещение/удаление). Нет
  /// подключения — исключение, а не тихий выход: иначе офлайн-очередь
  /// считала бы операцию выполненной и удаляла её.
  Future<me.MailEngine> _requireEngine(AccountModel account) async {
    final engine = await _engineFor(account);
    if (engine == null) {
      throw Exception('Подключение к серверу не удалось: '
          '${_lastConnectError[account.id] ?? 'нет учётных данных'}');
    }
    return engine;
  }

  /// SyncKey папки живёт в prefs между запусками; движок после перезапуска
  /// его не знает — подставляем перед операцией.
  void _seedKey(AccountModel account, me.MailEngine engine, String folderId) {
    if (engine is! me.EasEngine) return;
    final saved = _prefs.getString(_tokKey(account.id, folderId, 'mail'));
    // Сохранённый ключ — самый свежий (его пишет каждая операция в любом
    // изоляте); ключ в памяти мог устареть.
    if (saved != null && saved.isNotEmpty && saved != '0') engine.restoreMailSyncKey(folderId, saved);
  }

  /// Операция в EAS сдвигает SyncKey — сохраняем новый, иначе после
  /// перезапуска сервер отверг бы старый ключ и папка загружалась бы заново.
  Future<void> _persistKey(AccountModel account, me.MailEngine engine, String folderId) async {
    if (engine is! me.EasEngine) return;
    final k = engine.mailSyncKeyFor(folderId);
    if (k != null && k.isNotEmpty && k != '0') {
      await _prefs.setString(_tokKey(account.id, folderId, 'mail'), k);
    }
  }

  /// Загрузить ПОЛНОЕ тело письма (когда в списке оно было усечено).
  Future<({String? bodyPlain, String? bodyHtml})?> fetchFullBody(
    AccountModel account, {
    required String folderId,
    required String serverId,
  }) async {
    final engine = await _engineFor(account);
    if (engine == null) return null;
    final sid = folderId == me.EasEngine.searchFolderId ? _serverId(serverId) : serverId;
    final m = await engine.fetchMessage(
      me.MessageRef(id: sid, folderId: folderId, serverId: sid),
    );
    return (bodyPlain: m.bodyPlain, bodyHtml: m.bodyHtml);
  }

  /// Письмо целиком в исходном виде (MIME) — для проверки подписи S/MIME
  /// обычного подписанного письма. null — сервер не отдал.
  Future<Uint8List?> fetchRawMime(AccountModel account,
      {required String folderId, required String emailId}) async {
    if (account.usesEas) {
      final eas = await _easEngine(account);
      if (eas == null) return null;
      return eas.fetchMime(me.MessageRef(id: emailId, folderId: _serverId(folderId), serverId: _serverId(emailId)));
    }
    if (account.usesEws || account.isExchange) {
      return _ews.getMimeContent(account, emailId);
    }
    final ref = _ref;
    if (ref == null) return null;
    final sep = emailId.lastIndexOf(':');
    final uid = sep > 0 ? int.tryParse(emailId.substring(sep + 1)) : int.tryParse(emailId);
    if (uid == null) return null;
    return ref.read(imapServiceProvider).fetchRawMessage(account, folderId: folderId, uid: uid);
  }

  /// Заголовки письма ActiveSync (List-Unsubscribe, Authentication-Results):
  /// ActiveSync их не отдаёт — читаются из начала MIME. null — не ActiveSync
  /// или сервер не ответил.
  Future<Map<String, String>?> fetchEasHeaders(AccountModel account,
      {required String folderId, required String serverId}) async {
    final eas = await _easEngine(account);
    if (eas == null) return null;
    try {
      return await eas.fetchHeaders(me.MessageRef(id: serverId, folderId: folderId, serverId: serverId));
    } catch (e) {
      AppLogger.debug('EAS заголовки письма: $e');
      return null;
    }
  }

  void disconnectAll() {
    for (final e in _engines.values) {
      e.dispose();
    }
    _engines.clear();
  }

  // ──────────────────── Маппинг моделей ────────────────────

  FolderModel _toFolderModel(String accountId, me.MailFolder f) {
    // Автосинхронизируем только основной почтовый ящик. «Архив» и
    // пользовательские папки (в них годами копятся десятки тысяч писем)
    // остаются видимыми в списке, но не тянутся автоматически.
    const autoSync = {
      me.MailFolderType.inbox, me.MailFolderType.sent, me.MailFolderType.drafts,
      me.MailFolderType.outbox, me.MailFolderType.junk, me.MailFolderType.trash,
    };
    return FolderModel(
      id: f.id,
      accountId: accountId,
      // В ActiveSync корневые папки имеют ParentId «0» — для приложения это
      // «нет родителя» (иначе экран выбора папок не находил ни одного корня).
      parentId: (f.parentId == null || f.parentId == '0' || f.parentId!.isEmpty)
          ? null
          : f.parentId,
      displayName: f.displayName,
      type: _folderType(f.type),
      serverPath: f.id,
      isSynced: autoSync.contains(f.type),
      // «Вся почта» — общее правило для всех протоколов (входящие,
      // отправленные и папки писем; без черновиков, удалённых, спама).
      showInUnified: FolderModel.unifiedByDefault(_folderType(f.type)),
    );
  }

  FolderType _folderType(me.MailFolderType t) {
    switch (t) {
      case me.MailFolderType.inbox:
        return FolderType.inbox;
      case me.MailFolderType.sent:
        return FolderType.sent;
      case me.MailFolderType.drafts:
        return FolderType.drafts;
      case me.MailFolderType.trash:
        return FolderType.trash;
      case me.MailFolderType.junk:
        return FolderType.junk;
      case me.MailFolderType.outbox:
        return FolderType.outbox;
      case me.MailFolderType.archive:
        return FolderType.archive;
      case me.MailFolderType.user:
        return FolderType.custom;
      case me.MailFolderType.calendar:
      case me.MailFolderType.contacts:
      case me.MailFolderType.tasks:
      case me.MailFolderType.notes:
      case me.MailFolderType.journal:
        return FolderType.custom;
    }
  }

  static const _mimeByExt = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
    'bmp': 'image/bmp', 'tif': 'image/tiff', 'tiff': 'image/tiff', 'webp': 'image/webp',
    'heic': 'image/heic',
    'txt': 'text/plain', 'csv': 'text/csv', 'htm': 'text/html', 'html': 'text/html',
    'xml': 'application/xml', 'rtf': 'application/rtf',
    'zip': 'application/zip', 'rar': 'application/vnd.rar', '7z': 'application/x-7z-compressed',
    'eml': 'message/rfc822', 'msg': 'application/vnd.ms-outlook', 'ics': 'text/calendar',
    'mp3': 'audio/mpeg', 'mp4': 'video/mp4', 'mov': 'video/quicktime',
    'dwg': 'image/vnd.dwg', 'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  };

  static String _mimeByName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return _mimeByExt[name.substring(dot + 1).toLowerCase()] ?? '';
  }

  EmailModel _toEmailModel(String accountId, me.MailMessage m) {
    return EmailModel(
      id: m.id,
      accountId: accountId,
      folderId: m.folderId,
      internetMessageId: m.internetMessageId,
      conversationId: m.conversationId,
      from: EmailAddress(email: m.from.email, displayName: m.from.name),
      to: [for (final a in m.to) EmailAddress(email: a.email, displayName: a.name)],
      cc: [for (final a in m.cc) EmailAddress(email: a.email, displayName: a.name)],
      replyTo: [for (final a in m.replyTo) EmailAddress(email: a.email, displayName: a.name)],
      subject: m.subject,
      bodyPlain: m.bodyPlain,
      bodyHtml: m.bodyHtml,
      bodyPreview: m.preview,
      attachments: [
        for (final a in m.attachments)
          EmailAttachment(
            id: a.id,
            name: a.name,
            // EAS не сообщает тип вложения в Sync — определяем по расширению,
            // иначе предпросмотр и значки работали бы как для «прочего файла».
            mimeType: (a.contentType != null && a.contentType!.isNotEmpty)
                ? a.contentType!
                : _mimeByName(a.name),
            size: a.size ?? 0,
            isInline: a.isInline,
            contentId: EmailAttachment.normalizeCid(a.contentId),
          ),
      ],
      receivedAt: m.date ?? DateTime.now(),
      sentAt: m.date,
      isRead: m.isRead,
      isFlagged: m.isFlagged,
      hasAttachments: m.hasAttachments,
      meetingJson: m.meeting == null
          ? null
          : jsonEncode({...m.meeting!.toMap(), if (m.messageClass != null) 'class': m.messageClass}),
    );
  }
}

/// Riverpod-провайдер сервиса движка (один на приложение).
final mailEngineServiceProvider = Provider<MailEngineService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  final service = MailEngineService(secureStorage, prefs, ref);
  DeviceTimeZone.restore(prefs);
  CategoryColors.load(prefs);
  ref.onDispose(service.disconnectAll);
  // Команда удалённого стирания от Exchange (движок уже подтвердил её серверу).
  me.EasEngine.remoteWipeHandler = (email, kind) {
    unawaited(ref.read(remoteWipeProvider).handleRemoteWipe(email: email, kind: kind));
  };
  // Сеанс ActiveSync между запусками: фоновая проверка не повторяет OPTIONS и
  // Provision каждые 15 минут (экономия батареи и трафика, 10.10.2026).
  // Выключатель — «Настройки → Почта → Открытие писем → Быстрое подключение Exchange».
  me.EasEngine.loadSession = (email) => prefs.getBool('eas_session_cache') == false
      ? null
      : prefs.getString('eassession_${email.toLowerCase()}');
  me.EasEngine.saveSession = (email, data) {
    final k = 'eassession_${email.toLowerCase()}';
    if (data == null) {
      unawaited(prefs.remove(k));
    } else {
      unawaited(prefs.setString(k, data));
    }
  };
  return service;
});

/// Встреча до изменения (1.6.7): по началу, концу и теме она находится в
/// EWS у ящиков ActiveSync.
typedef MeetingOriginal = ({DateTime start, DateTime end, String title});

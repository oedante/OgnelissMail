// lib/services/sync/sync_service.dart
// Синхронизация:
// - Batch INSERT в БД (одна транзакция, не по одному)
// - Прогресс-индикация через провайдер UI
// - Параллельная синхронизация папок (max 3)
// - Уведомления о новых письмах
// - Автоправила для новых писем (если включены)
// - Обработка очереди офлайн-операций
// - fetchMode support

import '../calendar/event_reminders.dart';
import '../../features/settings/providers/quiet_hours_provider.dart' show QuietHours;
import 'sync_schedule.dart';
import '../background/work_scheduler.dart';
import '../../core/utils/person_names.dart';
import '../../core/utils/subject_prefix.dart';
import '../device/phone_mirror_service.dart' show phoneMirrorProvider;
import '../../core/utils/text_safe.dart';
import '../contacts/mail_contacts_service.dart';
import '../contacts/colleague_directory.dart';
import '../../core/utils/mail_domains.dart' show mailDomainOf, isPublicMailDomain;
import '../../core/errors/app_exceptions.dart' show looksLikeAuthError, OAuthRefreshFailure;
import '../mail/offline_send_service.dart';
import '../mail/draft_sync_service.dart';
import '../mail/dav/dav_pim_service.dart';
import '../mail/dav/dav_credentials.dart';
import '../mail/oauth/oauth_proxy_client.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/mail_body_processor.dart';
import 'dart:convert';
import '../mail/control_service.dart';
import '../mail/email_actions_service.dart' show emailActionsProvider;
import 'package:http/http.dart' as http;
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'push_health.dart';
import '../../data/models/note_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/calendar_event_model.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/email_model.dart';
import '../mail/focus_mode_service.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../services/mail/ews/ews_service.dart';
import '../../services/mail/imap/imap_service.dart';
import '../../services/mail/engine/mail_engine_service.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/notifications/notification_text.dart';
import '../../services/rules/auto_rules_service.dart';
import '../../widgets/common/sync_progress_indicator.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../mail/own_identity_service.dart' show ownIdentityServiceProvider;
import '../mail/own_addresses.dart';
import '../mail/thread_linker.dart';
import '../mail/special_folders.dart';
import '../security/mail_classification.dart' show MailLabel;
import '../rules/device_rules_service.dart' show deviceRulesProvider, RuleNotify, RuleOutcome;
import '../notifications/reminder_scheduler_service.dart';
import '../notifications/follow_up_service.dart';
import '../mail/oauth/oauth_service.dart';
import '../notifications/account_notify_mode.dart';
import '../../core/platform/finish_in_background.dart';
import 'dart:async';
import 'dart:io' show SocketException, HandshakeException, pid;
import 'imap_push_service.dart' show imapPushServiceProvider;
import 'offline_store_service.dart';
import '../mail/attachment_cache_service.dart';
import '../mail/ews/ews_delta_sync.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mail/shared_access.dart';
import 'conflict_resolver.dart';
import '../mail/auto_responder_service.dart';
import '../mail/transport/mail_transport.dart';
import '../home_widget_service.dart';
import '../../features/mail/providers/mail_providers.dart'
    show emailModelFromRow, accountsProvider, activeAccountProvider, folderFromRow, controlRevisionProvider;

/// Провайдер синхронизации
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref);
});

// Фоновое планирование (WorkManager + foreground-таймеры) целиком у
// BackgroundService (lib/services/background/background_service.dart). Прежние
// дубли syncCallbackDispatcher/initBackgroundSync здесь удалены, чтобы не было
// двойной регистрации задачи 'periodic_sync' с разными dispatcher'ами.

class SyncService {
  final Ref _ref;
  bool _isSyncing = false;

  /// Идёт ли сейчас синхронизация (для индикаторов и сторожа push).
  bool get isSyncing => _isSyncing;

  /// Сколько идёт текущий проход; null — не идёт (сторож самовосстановления,
  /// 1.6.48: не мешать обычному проходу, но заметить зависший).
  Duration? get runningFor => _inFlight == null ? null : DateTime.now().difference(_inFlightSince);
  Future<void>? _inFlight;
  DateTime _inFlightSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// Одна синхронизация за раз в изоляте. Раньше вызов при идущей
  /// синхронизации молча возвращался: обновление жестом гасло сразу и
  /// «не срабатывало», «Полная пересинхронизация» ничего не делала, а при
  /// зависшей синхронизации не работало вообще ничего до перезапуска.
  /// Теперь второй вызов ждёт идущую (индикатор крутится до конца), а
  /// идущую дольше 20 минут считает зависшей и запускает новую.
  ///
  /// [fresh] (1.6.43, фоновая задача): идущая синхронизация могла начаться
  /// до того, как система заморозила процесс, и висит на мёртвом запросе
  /// (журнал iPhone 18.10: FolderSync начат при пробуждении в 16:12, ответ
  /// «таймаут» — лишь в 16:27, при следующем пробуждении). Ждём её не больше
  /// 20 секунд и затем делаем свой проход — фоновой задаче нужен результат
  /// сейчас, пока система даёт процессу сеть.
  Future<void> _single(Future<void> Function() body, {bool fresh = false}) async {
    final running = _inFlight;
    if (running != null) {
      final age = DateTime.now().difference(_inFlightSince);
      if (age < const Duration(minutes: 20)) {
        try {
          await running.timeout(fresh ? const Duration(seconds: 20) : const Duration(minutes: 5));
        } catch (_) {}
        if (!fresh) return;
        AppLogger.info('Синхронизация для фоновой задачи: после идущей — свой проход');
      } else {
        AppLogger.warning('Синхронизация идёт ${age.inMinutes} мин — считаю зависшей, запускаю новую');
      }
    }
    final done = Completer<void>();
    _inFlight = done.future;
    _inFlightSince = DateTime.now();
    _isSyncing = true;
    try {
      await body();
    } finally {
      if (identical(_inFlight, done.future)) {
        _inFlight = null;
        _isSyncing = false;
      }
      done.complete();
    }
  }
  /// Параллельные папки синхронизации — через общий планировщик (1.5.9):
  /// не больше трёх (как раньше `_maxParallel`), пока открыто письмо — одна.
  /// Раньше ожидание места было опросом каждые 50 мс: таймер будил главный
  /// изолят ~20 раз в секунду на всё время синхронизации большого ящика.
  Future<void> _acquireSlot() => WorkScheduler.instance.acquire(WorkPriority.sync);

  void _releaseSlot() => WorkScheduler.instance.release(WorkPriority.sync);

  SyncService(this._ref);

  /// Синхронизировать все аккаунты
  /// [scheduled] — синхронизация по таймеру или в фоне (не по действию
  /// пользователя): учитываются настройки аккаунта «Проверка почты» и
  /// «Только по Wi‑Fi». [respectInterval] — пропускать аккаунты, которые
  /// синхронизировались недавно (меньше их интервала назад). [fresh] — см.
  /// [_single]: не довольствоваться уже идущей синхронизацией.
  Future<void> syncAll({bool scheduled = false, bool respectInterval = false, bool fresh = false}) =>
      FinishInBackground.guard(
          () => _single(() => _syncAllBody(scheduled: scheduled, respectInterval: respectInterval), fresh: fresh));

  /// Окно доставки режима фокуса — одно сводное уведомление о письмах,
  /// пришедших в тишине. Фокус выключили — тоже показываем, чтобы не потерять.
  Future<void> _releaseFocusDigest() async {
    try {
      final focus = _ref.read(focusModeProvider.notifier);
      final st = _ref.read(focusModeProvider);
      if (st.isEnabled && !focus.inDeliveryWindow) return;
      // Тихие часы — сводку не теряем, покажем после них.
      if (QuietHours.isQuietNow(_prefs)) return;
      final d = await FocusDigest.take(_prefs);
      if (d == null) return;
      await _ref.read(notificationServiceProvider).showSummaryNotification(
            accountId: '',
            accountEmail: _l10n().tr('focusDigestTitle'),
            count: d.count,
            lines: d.lines,
          );
      AppLogger.info('Режим фокуса: сводка о ${d.count} письмах');
    } catch (e) {
      AppLogger.debug('Сводка фокуса: $e');
    }
  }

  Future<void> _syncAllBody({required bool scheduled, required bool respectInterval}) async {
    // Плановый тик (раз в 5 минут) обычно ничего не делает — ящикам ещё рано.
    // Индикатор синхронизации включается, только когда работа есть: раньше
    // лента и шапка перестраивались на каждом пустом тике.
    if (!scheduled) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      _ref.read(syncProgressProvider.notifier).state = 0.0;
    }

    try {
      final connectivity = _ref.read(connectivityServiceProvider);
      if (!connectivity.isConnected) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return;
      }

      final settings = _ref.read(settingsProvider);
      if (settings.syncOnlyWifi && !connectivity.isWifi) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return;
      }

      final accounts = _ref.read(accountsProvider);
      // Аккаунты с отметкой «требуется вход» в автоматическую синхронизацию
      // не берём: каждая попытка со старым паролем — это неудачный вход, и
      // политика домена после нескольких таких блокирует учётную запись
      // (а с ней — доступ ко всем корпоративным системам). Повторить можно
      // вручную (обновление списка) или после ввода нового пароля.
      var activeAccounts = accounts.where((a) => a.isActive && a.authFailedAt == null).toList();
      if (scheduled) {
        final db = _ref.read(databaseProvider);
        final keep = <AccountModel>[];
        for (final a in activeAccounts) {
          if (a.syncInterval == SyncInterval.manual) continue; // только вручную
          if (a.syncOnlyWifi && !connectivity.isWifi) continue;
          if (respectInterval) {
            // Push жив (событие или ожидание за последние 5 минут) — новые
            // письма он доставляет сам, полная проверка ящика нужна реже:
            // раз в 30 минут вместо 15 (папки без push и PIM). Экономия
            // заряда без потери доставки.
            final alive = pushLastAlive(a.id);
            final pushOk = SyncSchedule.pushNow(a) &&
                alive != null && DateTime.now().difference(alive) < const Duration(minutes: 5);
            final minutes = switch (a.syncInterval) {
              SyncInterval.minutes5 => 5,
              SyncInterval.minutes30 => 30,
              SyncInterval.hour1 => 60,
              // «По расписанию» вне рабочих часов — свой интервал (15/30/60).
              SyncInterval.scheduled when !SyncSchedule.inWindow() => SyncSchedule.offMinutes,
              _ => pushOk ? 30 : 15, // push (резервная проверка) и 15 минут
            };
            final row = await (db.select(db.accounts)..where((x) => x.id.equals(a.id))).getSingleOrNull();
            final last = row?.lastSyncAt;
            // Небольшой запас: таймер срабатывает «примерно» через интервал.
            if (last != null &&
                DateTime.now().difference(last) < Duration(minutes: minutes) - const Duration(minutes: 1)) {
              continue;
            }
          }
          keep.add(a);
        }
        activeAccounts = keep;
      }
      for (final a in accounts.where((a) => a.isActive && a.authFailedAt != null)) {
        AppLogger.info('Синхронизация пропущена — требуется вход: ${a.email}');
      }
      // Плановый тик, а ящикам ещё рано (интервал не прошёл): ничего не
      // делаем. Раньше и в этом случае перевыставлялись напоминания и шли
      // служебные проверки — каждые 5 минут впустую (журнал 11.10.2026).
      if (scheduled && activeAccounts.isEmpty) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return;
      }
      if (scheduled) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
        _ref.read(syncProgressProvider.notifier).state = 0.0;
      }

      // Аккаунт, открытый у пользователя на экране, синхронизируем ПЕРВЫМ:
      // остальные ящики работают в фоне, и ждать их не нужно. Раньше порядок
      // был как в списке — при трёх аккаунтах пользователь мог ждать чужой
      // почты, пока обновится его собственная.
      final currentId = _ref.read(activeAccountProvider)?.id;
      if (currentId != null) {
        final idx = activeAccounts.indexWhere((a) => a.id == currentId);
        if (idx > 0) {
          final current = activeAccounts.removeAt(idx);
          activeAccounts.insert(0, current);
        }
      }

      for (int i = 0; i < activeAccounts.length; i++) {
        _ref.read(syncMessageProvider.notifier).state =
            _l10n().tr('syncingAccount').replaceAll('{email}', activeAccounts[i].email);
        _ref.read(syncProgressProvider.notifier).state =
            (i + 0.5) / activeAccounts.length;

        await _syncAccountSafe(activeAccounts[i], settings);

        _ref.read(syncProgressProvider.notifier).state =
            (i + 1) / activeAccounts.length;
      }

      _finishStatus(activeAccounts);
      // Черновики, сохранённые без сети, — в серверные «Черновики».
      final drafts = _ref.read(draftSyncServiceProvider).uploadPending().catchError((_) {});
      // С сервера могли прийти новые встречи и задачи — перевыставляем
      // напоминания. Не ждём: на UI это не влияет.
      final reminders = _ref.read(reminderSchedulerProvider).rescheduleAll().catchError((Object _) {});
      // Проверка «нет ответа»: письма с наступившим follow-up. Стоит один
      // запрос по частичному индексу + по одному на каждое отслеживаемое
      // письмо (их единицы), поэтому вешаем на обычную синхронизацию, а не
      // на отдельный таймер.
      final followUps = (() async {
        try {
          final accounts = _ref.read(accountsProvider);
          if (accounts.isEmpty) return;
          // Все адреса владельца — ответ с основного адреса тоже «мой».
          final map = {for (final a in accounts) a.id: OwnAddresses.of(a).join(',')};
          // «На контроле»: пришёл ответ / я ответил → «Исполнено». До проверки
          // сроков: исполненное к сроку не напоминает.
          if (_ref.read(settingsProvider).mailControl) {
            await ControlService.check(_ref.read(databaseProvider), map);
            if (ControlService.lastChanges > 0) {
              try {
                _ref.read(controlRevisionProvider.notifier).state++;
              } catch (_) {}
            }
          }
          await FollowUpService(
            _ref.read(databaseProvider),
            _ref.read(notificationServiceProvider),
          ).checkDue(map);
          // «Посмотреть позже»: срок наступил — письмо снова непрочитанное
          // (в фоне тоже: уведомление ОС уже пришло, а отметка ставится здесь).
          await _ref.read(emailActionsProvider).returnDueLater();
          // Контакты и календарь ящиков в телефоне (если включено).
          await _ref.read(phoneMirrorProvider).syncAll();
          // Виджет «Мой день» на рабочем столе — свежие встречи и счётчики.
          await HomeWidgetService.updateFrom(_ref);
        } catch (e) {
          AppLogger.warning('follow-up check failed: $e');
        }
      }());
      // Фоновая задача (WorkManager) дожидается этих работ (settle): раньше
      // она завершалась раньше их, контейнер закрывался, и проверка «нет
      // ответа», напоминания и виджет падали с «Ref … disposed» и «Channel
      // was closed» (журнал 13.10.2026).
      _afterSync = Future.wait<void>([drafts, reminders, followUps]).then((_) {}, onError: (Object _) {});
    } catch (e) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      AppLogger.error('Sync error', e);
    } finally {}
  }

  /// Итог синхронизации. Если Exchange попросил подождать (перегрузка,
  /// ограничение ActiveSync) — красная точка у названия папки с пояснением
  /// по нажатию; раньше это выглядело как «синхронизировано, писем нет».
  void _finishStatus(List<AccountModel> accounts) {
    final engine = _ref.read(mailEngineServiceProvider);
    // Ящики, которые не синхронизировались (нет связи с сервером, ошибка
    // протокола) или синхронизировались частично. Раньше итог был «успех»
    // при любой ошибке, кроме неверного пароля, — отсюда жалобы «почта не
    // приходит», хотя приложение показывало, что всё обновлено.
    final failed = <String>[
      for (final a in accounts)
        if (_accountErrors[a.id] != null) '${a.email}: ${_accountErrors[a.id]}'
        else if (_partialErrors[a.id] != null) '${a.email} (${_l10n().tr('syncSomeFolders')}): ${_partialErrors[a.id]}',
    ];
    final busy = <String>[];
    for (final a in accounts) {
      final until = engine.serverBusyUntil(a.id);
      if (until == null) continue;
      final t = until.toLocal();
      busy.add('${a.email} — ${_l10n().tr('syncBusyUntil').replaceAll('{time}', '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')}');
    }
    // Сводка режима фокуса — и при частичных ошибках ящиков.
    unawaited(_releaseFocusDigest());
    if (busy.isEmpty && failed.isEmpty) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      _ref.read(syncMessageProvider.notifier).state = null;
      return;
    }
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    _ref.read(syncMessageProvider.notifier).state = [
      if (failed.isNotEmpty) '${_l10n().tr('syncFailedFor')}: ${failed.join('; ')}',
      if (busy.isNotEmpty) '${_l10n().tr('syncServerBusy')}: ${busy.join('; ')}',
    ].join('\n');
  }

  /// Ошибка синхронизации по ящику (последний проход) — для экрана аккаунта
  /// и строки статуса. null — последний проход успешен.
  String? accountError(String accountId) => _accountErrors[accountId] ?? _partialErrors[accountId];

  final Map<String, String> _accountErrors = {};
  final Map<String, String> _partialErrors = {};
  final Map<String, List<String>> _ewsFolderErrors = {};

  /// Короткий понятный текст ошибки: без стека, типа исключения и простыней.
  String _shortError(Object e) {
    final l10n = _l10n();
    var t = '$e'.replaceFirst(RegExp(r'^(Exception|[A-Za-z]+Exception|[A-Za-z]+Error):\s*'), '');
    final l = t.toLowerCase();
    if (l.contains('failed host lookup') ||
        l.contains('no address associated') ||
        l.contains('unable to resolve host') ||
        l.contains('nodename nor servname')) {
      return l10n.tr('syncErrDns');
    }
    if (l.contains('connection refused')) return l10n.tr('syncErrRefused');
    if (l.contains('timed out') || l.contains('timeout')) return l10n.tr('syncErrTimeout');
    if (l.contains('handshake') || l.contains('certificate')) return l10n.tr('syncErrCert');
    if (l.contains('network is unreachable') || l.contains('socketexception')) return l10n.tr('syncErrNoLink');
    t = t.split('\n').first;
    return t.length > 140 ? '${cutSafe(t, 140)}…' : t;
  }

  /// Короткая фоновая проверка для iOS: BGAppRefreshTask даёт около 30 с,
  /// полный проход (папки, календарь, контакты) в них не укладывается, и iOS
  /// снимал бы задачу, а при частых снятиях — реже запускал бы её.
  /// Поэтому только «Входящие» каждого ящика (и очередь отправки — её
  /// разбирает syncSingleFolder) в пределах [budget].
  Future<void> quickInboxSync({Duration budget = const Duration(seconds: 22)}) async {
    final started = DateTime.now();
    final connectivity = _ref.read(connectivityServiceProvider);
    if (!connectivity.isConnected) return;
    final settings = _ref.read(settingsProvider);
    if (settings.syncOnlyWifi && !connectivity.isWifi) return;
    final db = _ref.read(databaseProvider);
    final accounts = _ref.read(accountsProvider).where((a) =>
        a.isActive &&
        a.authFailedAt == null &&
        a.syncInterval != SyncInterval.manual &&
        !(a.syncOnlyWifi && !connectivity.isWifi));
    for (final a in accounts) {
      final left = budget - DateTime.now().difference(started);
      if (left < const Duration(seconds: 3)) {
        AppLogger.info('Фоновая проверка iOS: время вышло, остальные ящики — в следующий раз');
        break;
      }
      try {
        final row = await (db.select(db.folders)
              ..where((f) => f.accountId.equals(a.id) & f.type.equals(FolderType.inbox.index))
              ..limit(1))
            .getSingleOrNull();
        if (row == null) continue;
        await syncSingleFolder(a, folderFromRow(row)).timeout(left);
      } catch (e) {
        AppLogger.warning('Фоновая проверка iOS ${a.email}: $e');
      }
    }
  }

  /// Пересинхронизировать контакты ящика (1.6.32): Exchange — все контакты
  /// заново с сервера (лишние уберутся), остальные — внеочередная
  /// синхронизация контактов и календаря.
  Future<void> resyncContacts(AccountModel account) async {
    if (account.usesEas) {
      await _ref.read(mailEngineServiceProvider).requestFullContactsResync(account);
    }
    // Коллеги сверяются с адресной книгой все сразу, без суточной паузы.
    _dirForce.add(account.id);
    // И своя карточка (компания, должность, отдел для подписи) — сразу.
    try {
      await _ref.read(mailEngineServiceProvider).refreshSelfCard(account, force: true)
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      AppLogger.warning('Своя карточка из адресной книги: $e');
    }
    await syncAccount(account);
  }

  // ── Коллеги из адресной книги организации (1.8.0+118) ──
  // Личный контакт Exchange — копия: название компании, отдел, должность в
  // ней сами не меняются (`colleague_directory.dart`). У коллег эти поля раз
  // в сутки сверяются с адресной книгой; за проход — не дольше 20 секунд на
  // экране и 8 в фоне, остальные — в следующий раз; «Обновить с сервера» —
  // все сразу. Запросы по одному. Сбой — пауза на час: повторы с неверным
  // паролем могут заблокировать учётную запись.
  final Set<String> _dirForce = {};
  final Set<String> _dirRunning = {};
  final Map<String, DateTime> _dirPauseUntil = {};

  /// Сверенные контакты ящика: id → что пришло из адресной книги.
  Future<Map<String, DirectoryOrg>> _dirOrgs(AppDatabase db, String accountId) async {
    final rows = await (db.select(db.contacts)
          ..where((t) => t.accountId.equals(accountId) & t.dirOrg.isNotNull()))
        .get();
    final out = <String, DirectoryOrg>{};
    for (final r in rows) {
      final d = DirectoryOrg.parse(r.dirOrg);
      if (d != null) out[r.id] = d;
    }
    return out;
  }

  Future<void> _refreshColleagues(AccountModel account) async {
    final force = _dirForce.remove(account.id);
    final pause = _dirPauseUntil[account.id];
    if (!force && pause != null && DateTime.now().isBefore(pause)) return;
    if (!_dirRunning.add(account.id)) return;
    var checked = 0, changed = 0;
    try {
      final acc = _ref.read(accountsProvider).where((a) => a.id == account.id).firstOrNull;
      if (acc == null || !acc.isActive || acc.authFailedAt != null) return;
      if (!(acc.usesEas || acc.hasEwsExtras || acc.isExchange)) return;
      final mine = mailDomainOf(acc.email);
      if (mine.isEmpty || isPublicMailDomain(mine)) return;
      final db = _ref.read(databaseProvider);
      final dayAgo = DateTime.now().subtract(const Duration(hours: 24));
      final rows = await (db.select(db.contacts)..where((t) => t.accountId.equals(acc.id))).get();
      final due = [
        for (final r in rows)
          if (isColleagueEmail(r.email, acc.email) &&
              (force || r.dirCheckedAt == null || r.dirCheckedAt!.isBefore(dayAgo)))
            r,
      ]..sort((a, b) => (a.dirCheckedAt ?? DateTime(2000)).compareTo(b.dirCheckedAt ?? DateTime(2000)));
      if (due.isEmpty) return;
      final open = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      final budget = force ? const Duration(minutes: 3) : Duration(seconds: open ? 20 : 8);
      final engine = _ref.read(mailEngineServiceProvider);
      final sw = Stopwatch()..start();
      for (var i = 0; i < due.length && sw.elapsed < budget; i += 10) {
        final part = due.sublist(i, i + 10 > due.length ? due.length : i + 10);
        final found = <ContactModel?>[];
        for (final r in part) {
          found.add(await engine.directoryEntry(acc, r.email));
        }
        final now = DateTime.now();
        await db.batch((b) {
          for (var j = 0; j < part.length; j++) {
            final r = part[j];
            final p = found[j];
            // Нет в адресной книге — остаётся как есть, сверится через сутки.
            final dir = p == null ? null : DirectoryOrg.of(r.email, p);
            final ch = dir?.changesFor({
                  'company': r.company,
                  'department': r.department,
                  'jobTitle': r.jobTitle,
                  'office': r.office,
                  'manager': r.manager,
                  'phoneWork': r.phoneWork,
                }) ??
                const <String, String>{};
            if (ch.isNotEmpty) changed++;
            Value<String?> v(String field) => ch.containsKey(field) ? Value(ch[field]) : const Value.absent();
            b.update(
              db.contacts,
              ContactsCompanion(
                company: v('company'),
                department: v('department'),
                jobTitle: v('jobTitle'),
                office: v('office'),
                manager: v('manager'),
                phoneWork: v('phoneWork'),
                dirCheckedAt: Value(now),
                dirOrg: dir == null ? const Value.absent() : Value(dir.toJson()),
              ),
              where: (t) => t.id.equals(r.id) & t.accountId.equals(acc.id),
            );
          }
        });
        checked += part.length;
      }
    } catch (e) {
      _dirPauseUntil[account.id] = DateTime.now().add(const Duration(hours: 1));
      AppLogger.warning('Коллеги из адресной книги: $e — пауза на час');
    } finally {
      _dirRunning.remove(account.id);
      if (checked > 0) {
        AppLogger.info('Коллеги из адресной книги (${AppLogger.mask(account.email)}): '
            'сверено $checked, изменено $changed');
      }
    }
  }

  /// Публичная синхронизация одного аккаунта (вызывается из UI при refresh).
  /// Явное обновление — календарь и контакты тоже, без паузы.
  Future<void> syncAccount(AccountModel account) {
    _pimForce.add(account.id);
    _folderSyncForce.add(account.id);
    return FinishInBackground.guard(() => _single(() => _syncAccountBody(account)));
  }

  /// Последний FolderSync ActiveSync (папки не чаще раза в час) и ящики,
  /// для которых его нужно сделать в ближайший проход (жест «обновить»).
  final Map<String, DateTime> _easFolderSyncAt = {};
  final Set<String> _folderSyncForce = {};

  /// Время последней синхронизации календаря/контактов/заметок/задач Exchange.
  final Map<String, DateTime> _pimAt = {};
  final Set<String> _pimForce = {};

  bool _pimDue(String accountId) {
    final now = DateTime.now();
    final last = _pimAt[accountId];
    // Приложение на экране — календарь и контакты свежие (раз в 5 минут);
    // свёрнуто или фоновая задача — раз в 20 минут: встречи и контакты
    // меняются редко, а каждый проход — десяток запросов и пробуждение радио.
    final open = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final every = open ? const Duration(minutes: 5) : const Duration(minutes: 20);
    if (_pimForce.remove(accountId) || last == null || now.difference(last) >= every) {
      _pimAt[accountId] = now;
      return true;
    }
    return false;
  }

  Future<void> _syncAccountBody(AccountModel account) async {
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final connectivity = _ref.read(connectivityServiceProvider);
      if (!connectivity.isConnected) {
        _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return;
      }
      final settings = _ref.read(settingsProvider);
      _ref.read(syncMessageProvider.notifier).state = _l10n().tr('syncingAccount').replaceAll('{email}', account.email);
      await _syncAccountSafe(account, settings);
      _finishStatus([account]);
    } catch (e) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      AppLogger.error('Sync account error', e);
    } finally {}
  }

  // ─── Синхронизация одной папки по требованию (архив/пользовательские) ───
  final Set<String> _foldersSyncing = {};

  /// Последовательность работы с аккаунтом внутри изолята: полная
  /// синхронизация, синхронизация папки по push и pull-to-refresh одного
  /// ящика не должны идти одновременно (у ActiveSync это одна цепочка SyncKey).
  final Map<String, Future<void>> _accountLocks = {};

  /// Идентификатор этого изолята для аренды синхронизации в БД.
  /// «p<pid>:» — номер процесса: аренду мёртвого процесса забираем сразу
  /// (см. [AppDatabase.tryAcquireSyncLease]).
  static final String _leaseOwner = '${_procPrefix()}'
      'iso_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(Object())}';

  static String _procPrefix() {
    try {
      return 'p$pid:';
    } catch (_) {
      return '';
    }
  }

  static const _leaseTtl = Duration(minutes: 4);
  static const _leaseRenew = Duration(seconds: 90);
  static const _maxHold = Duration(minutes: 20);

  /// Потолок в фоновой задаче: WorkManager обрывает её через 9 минут, а
  /// зависшее действие держало аренду ещё до 20 — приложение на экране всё
  /// это время писало «уже идёт в другом процессе — пропуск» (журнал 15.10).
  static const _maxHoldBackground = Duration(minutes: 8);

  /// Этап синхронизации ящика (1.6.12): затянувшийся этап отмечается в
  /// журнале через минуту, а этап с пределом [limit] прерывается — раньше
  /// зависание (после «подключено» ни одного запроса) было не видно и
  /// держало ящик до перезапуска приложения.
  Future<T> _stage<T>(AccountModel account, String name, Future<T> Function() run, {Duration? limit}) async {
    final sw = Stopwatch()..start();
    _currentStage[account.id] = (name: name, since: DateTime.now());
    // Этап — и в аренду ящика: другой изолят, получив «уже идёт», напишет
    // в журнал, где именно стоит синхронизация (фон или приложение).
    final role = AppLogger.isBackground ? 'фон' : 'приложение';
    unawaited(_ref
        .read(databaseProvider)
        .setSyncLeaseStage(account.id, _leaseOwner, '$role: $name')
        .then((_) {}, onError: (_) {}));
    final warn = Timer(const Duration(seconds: 60), () {
      AppLogger.warning('Синхронизация ${account.email}: «$name» идёт больше минуты ($role)');
    });
    try {
      final f = run();
      return limit == null ? await f : await f.timeout(limit);
    } on TimeoutException {
      AppLogger.error('Синхронизация ${account.email}: «$name» не завершился за ${limit?.inSeconds} с — прерван');
      rethrow;
    } finally {
      warn.cancel();
      _currentStage.remove(account.id);
      (_stageTimes[account.id] ??= []).add((name: name, ms: sw.elapsedMilliseconds));
      if (sw.elapsed > const Duration(seconds: 60)) {
        AppLogger.info('Синхронизация ${account.email}: «$name» — ${sw.elapsed.inSeconds} с');
      }
    }
  }

  /// Этап, который идёт сейчас в этом изоляте (для журнала ожидания).
  final Map<String, ({String name, DateTime since})> _currentStage = {};

  /// Длительность этапов текущего прохода — итог в «EAS sync done».
  final Map<String, List<({String name, int ms})>> _stageTimes = {};

  /// «за 12,3 с: подключение 0,4 · папка Входящие 8,1» — этапы от 0,5 с.
  String _stageSummary(String accountId, Stopwatch total) {
    final times = _stageTimes.remove(accountId) ?? const [];
    String sec(int ms) => (ms / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final slow = [for (final t in times) if (t.ms >= 500) '${t.name} ${sec(t.ms)}'];
    return 'за ${sec(total.elapsedMilliseconds)} с${slow.isEmpty ? '' : ': ${slow.join(' · ')}'}';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    return d.inMinutes > 0 ? '${d.inMinutes} мин ${d.inSeconds % 60} с' : '${d.inSeconds} с';
  }

  Future<T?> _exclusive<T>(String accountId, Future<T> Function() action) async {
    final previous = _accountLocks[accountId];
    final gate = Completer<void>();
    _accountLocks[accountId] = gate.future;
    try {
      if (previous != null) {
        final warn = Timer(const Duration(seconds: 60), () {
          final cur = _currentStage[accountId];
          AppLogger.warning('Синхронизация $accountId ждёт предыдущую операцию с ящиком больше минуты'
              '${cur == null ? '' : ' (этап «${cur.name}», ${_ago(cur.since)})'}');
        });
        try { await previous; } catch (_) {} finally { warn.cancel(); }
      }
      final db = _ref.read(databaseProvider);
      // Аренда короткая и продлевается, пока идёт работа. Прежде — 15 минут
      // без продления: длинная синхронизация теряла аренду посреди работы, а
      // после убийства процесса ящик «залипал» на 15 минут.
      var leased = true;
      try {
        leased = await db.tryAcquireSyncLease(accountId, _leaseOwner, _leaseTtl);
      } catch (_) {/* нет таблицы аренды — работаем без неё */}
      if (!leased) {
        var where = '';
        try {
          final info = await db.syncLeaseInfo(accountId).timeout(const Duration(seconds: 5));
          if (info != null) {
            where = info.stage == null
                ? ' (этап не отмечен)'
                : ' (${info.stage}${info.stageAt == null ? '' : ', ${_ago(info.stageAt!)}'})';
          }
        } catch (_) {}
        AppLogger.info('Синхронизация $accountId уже идёт в другом процессе$where — пропуск');
        return null;
      }
      final role = AppLogger.isBackground ? 'фон' : 'приложение';
      unawaited(db.setSyncLeaseStage(accountId, _leaseOwner, '$role: начало').then((_) {}, onError: (_) {}));
      final renew = Timer.periodic(_leaseRenew, (_) {
        unawaited(db.tryAcquireSyncLease(accountId, _leaseOwner, _leaseTtl).then((_) {}, onError: (_) {}));
      });
      try {
        // Потолок работы с ящиком: аренда продлевается, пока действие идёт,
        // и зависшее действие держало ящик вечно — в том числе после
        // перезапуска приложения, если зависло в фоновом изоляте
        // («уже идёт в другом процессе — пропуск» два часа подряд, 06.10).
        final hold = AppLogger.isBackground ? _maxHoldBackground : _maxHold;
        return await action().then<T?>((v) => v).timeout(hold, onTimeout: () {
          AppLogger.error('Синхронизация $accountId не завершилась за ${hold.inMinutes} мин — '
              'ящик освобождён');
          return null;
        });
      } finally {
        renew.cancel();
        try { await db.releaseSyncLease(accountId, _leaseOwner); } catch (_) {}
      }
    } finally {
      gate.complete();
      if (identical(_accountLocks[accountId], gate.future)) _accountLocks.remove(accountId)?.ignore();
    }
  }

  /// Идёт ли сейчас синхронизация конкретной папки (для индикатора в UI).
  bool isFolderSyncing(String folderId) => _foldersSyncing.any((k) => k.endsWith('|$folderId'));

  /// Синхронизировать ОДНУ папку по требованию. По умолчанию тянется только
  /// основной ящик; архив и пользовательские папки — только по этому вызову
  /// (не весь архив разом). Per-folder guard от повторного запуска. После
  /// успеха папка помечается синхронизируемой (дальше обновляется штатно).
  Future<void> syncSingleFolder(AccountModel account, FolderModel folder) =>
      FinishInBackground.guard(() => _exclusive(account.id, () => _syncSingleFolderImpl(account, folder)));

  Future<void> _syncSingleFolderImpl(AccountModel account, FolderModel folder) async {
    // Ключ — аккаунт и папка: id папки («INBOX», «5») совпадает у разных ящиков.
    final key = '${account.id}|${folder.id}';
    if (_foldersSyncing.contains(key)) return;
    _foldersSyncing.add(key);
    try {
      final db = _ref.read(databaseProvider);
      final settings = _ref.read(settingsProvider);
      // Очередь (отправка, прочитано, перемещения) — и при синхронизации
      // одной папки: раньше она разбиралась только полным проходом, и после
      // сбоя связи письмо в «Исходящих» ждало следующего прохода, хотя push
      // уже синхронизировал папки.
      // Связь только что пропала (предыдущая папка упала по сети) — остальные
      // папки пачки push («догоняем 25 папок») не дёргаем: каждая падала за
      // 10 мс, в журнале было по сотне ошибок подряд (09.10.2026). Догонит
      // следующий push после восстановления сети.
      if (account.usesEas) {
        final at = _easOutageAt[account.id];
        if (at != null && DateTime.now().difference(at) < const Duration(seconds: 20)) {
          AppLogger.debug('syncSingleFolder(${folder.id}): нет связи с сервером — пропуск');
          return;
        }
      }
      await _flushQueueQuiet(account);
      if (account.usesEas) {
        final engine = _ref.read(mailEngineServiceProvider);
        await _syncEasMailFolder(engine, db, account, folder, settings);
        _easOutageAt.remove(account.id);
      } else if (account.usesEws || account.isExchange) {
        final ews = _ref.read(ewsServiceProvider);
        await _syncFolder(account, folder, ews, db, settings);
      } else {
        await _syncImapFolder(_ref.read(imapServiceProvider), db, account, folder, settings);
      }
      // ВАЖНО: раньше здесь принудительно ставился isSynced = true — открыл папку,
      // и она попадала в автосинк. С появлением пользовательской настройки это
      // ошибка: отключённая техническая папка молча включалась бы обратно.
      // Разовая загрузка писем при открытии выше остаётся, а участие в
      // автоматическом синке определяет только настройка.
    } catch (e) {
      if (account.usesEas && _isNetworkError(e)) _easOutageAt[account.id] = DateTime.now();
      AppLogger.warning('syncSingleFolder(${folder.id}) failed: $e');
      rethrow;
    } finally {
      _foldersSyncing.remove(key);
    }
  }

  /// Разобрать очередь аккаунта, если в ней что-то есть (без ошибок наверх).
  Future<void> _flushQueueQuiet(AccountModel account) async {
    try {
      final db = _ref.read(databaseProvider);
      final any = await (db.select(db.syncQueue)
            ..where((q) => q.accountId.equals(account.id))
            ..limit(1))
          .get();
      if (any.isEmpty) return;
      await _processQueue(account.id);
    } catch (e) {
      AppLogger.debug('Очередь ${account.email}: $e');
    }
  }

  /// Обновить «Отправленные» вскоре после отправки: раньше отправленное
  /// письмо появлялось в папке только при следующей синхронизации, и
  /// пользователь думал, что оно не ушло. Пауза — сервер успевает положить
  /// копию (EAS SaveInSentItems, IMAP APPEND).
  void refreshSentSoon(AccountModel account) {
    // Сервер кладёт копию в «Отправленные» не сразу (Exchange — через
    // несколько секунд после приёма): если через 3 с её ещё нет (остался
    // временный быстрый ответ), — ещё раз через 15 и 45 с (1.7.1).
    Future<void> attempt(int i) async {
      try {
        final db = _ref.read(databaseProvider);
        final row = await (db.select(db.folders)
              ..where((f) => f.accountId.equals(account.id) & f.type.equals(FolderType.sent.index))
              ..limit(1))
            .getSingleOrNull();
        if (row == null) return;
        await syncSingleFolder(account, folderFromRow(row));
        final left = await dropQuickReplyPlaceholders(db, account.id);
        if (left > 0 && i < 2) {
          Future.delayed(Duration(seconds: i == 0 ? 12 : 30), () => attempt(i + 1));
        }
      } catch (e) {
        AppLogger.debug('Обновление «Отправленных» после отправки: $e');
      }
    }

    Future.delayed(const Duration(seconds: 3), () => attempt(0));
  }

  /// Временные строки быстрых ответов (id «qr_…», 1.7.1): ответ из строки
  /// внизу письма или беседы виден в беседе сразу, а не после синхронизации
  /// «Отправленных». Строка убирается, когда пришла серверная копия (то же
  /// письмо в той же папке: тема и время), и в любом случае через 30 минут.
  /// Возвращает, сколько временных строк осталось.
  static Future<int> dropQuickReplyPlaceholders(AppDatabase db, String accountId) async {
    final rows = await db.customSelect(
      "SELECT id, folder_id, subject, received_at FROM emails WHERE account_id = ? AND id LIKE 'qr\\_%' ESCAPE '\\'",
      variables: [Variable.withString(accountId)],
      readsFrom: {db.emails},
    ).get();
    var left = 0;
    final now = DateTime.now();
    for (final r in rows) {
      final id = r.read<String>('id');
      final at = r.read<DateTime>('received_at');
      var drop = now.difference(at) > const Duration(minutes: 30);
      if (!drop) {
        final real = await db.customSelect(
          "SELECT 1 FROM emails WHERE account_id = ? AND folder_id = ? AND id NOT LIKE 'qr\\_%' ESCAPE '\\' "
          'AND lower(subject) = lower(?) AND received_at >= ? LIMIT 1',
          variables: [
            Variable.withString(accountId),
            Variable.withString(r.read<String>('folder_id')),
            Variable.withString(r.read<String>('subject')),
            Variable.withDateTime(at.subtract(const Duration(minutes: 5))),
          ],
          readsFrom: {db.emails},
        ).getSingleOrNull();
        drop = real != null;
      }
      if (drop) {
        await (db.delete(db.emails)..where((e) => e.id.equals(id) & e.accountId.equals(accountId))).go();
      } else {
        left++;
      }
    }
    return left;
  }

  /// Безопасная синхронизация одного аккаунта (не параллельно с другой
  /// синхронизацией того же ящика — ни в этом изоляте, ни в фоновом).
  Future<void> _syncAccountSafe(AccountModel account, AppSettings settings) async {
    await _exclusive(account.id, () => _syncAccountSafeImpl(account, settings));
    if (account.usesEas && _pimWanted.remove(account.id)) {
      await _syncEasPimSessions(account);
    }
    // «Письма на телефоне»: полные тексты и картинки — в фоне, вне очереди
    // синхронизации (push и отправка не ждут докачки).
    unawaited(_ref.read(offlineStoreProvider).run(account));
  }

  /// Аккаунты ActiveSync, которым после почты нужна синхронизация PIM.
  final Set<String> _pimWanted = {};

  /// Сбой связи с сервером ActiveSync (нет ответа, 5xx, таймаут) — до этого
  /// момента PIM-сеансы и оставшиеся папки прохода не запускаются: каждый
  /// запрос в такие минуты ждал бы таймаута, а очередь — их всех.
  final Map<String, DateTime> _easOutageAt = {};
  bool _easOutage(String accountId) {
    final at = _easOutageAt[accountId];
    return at != null && DateTime.now().difference(at) < const Duration(minutes: 2);
  }

  static bool _isNetworkError(Object e) {
    final t = '$e';
    return t.contains('нет ответа') ||
        RegExp(r'HTTP (0|5\d\d)\b').hasMatch(t) ||
        t.contains('TimeoutException') ||
        t.contains('SocketException') ||
        t.contains('ClientException') ||
        t.contains('Connection');
  }

  /// Календарь, контакты, заметки, задачи ActiveSync — каждый своим коротким
  /// сеансом: ящик освобождается между ними, поэтому синхронизация папки по
  /// push, отправка из очереди и действия с письмами встают в очередь между
  /// шагами, а не ждут всю PIM-синхронизацию. Раньше всё шло одним проходом,
  /// и сбой связи на одном шаге задерживал остальные на минуты.
  Future<void> _syncEasPimSessions(AccountModel account) async {
    final engine = _ref.read(mailEngineServiceProvider);
    final db = _ref.read(databaseProvider);
    final steps = <Future<void> Function(MailEngineService, AppDatabase, AccountModel)>[
      _easPimCalendar, _easPimContacts, _easPimNotes, _easPimTasks,
    ];
    for (final step in steps) {
      if (_easOutage(account.id)) {
        AppLogger.info('EAS PIM ${account.email}: связь с сервером нестабильна — '
            'оставшиеся шаги в следующий раз');
        // Следующий проход попробует снова, не дожидаясь 5 минут.
        _pimAt.remove(account.id);
        return;
      }
      await _exclusive(account.id, () => step(engine, db, account));
    }
  }

  Future<void> _syncAccountSafeImpl(AccountModel account, AppSettings settings) async {
    _stageTimes[account.id] = []; // этапы этого прохода — итог в «sync done»
    _partialErrors.remove(account.id);
    try {
      // Сначала отправляем локальные изменения (outbox + флаги/перемещения),
      // чтобы сервер отдал уже актуальное состояние и не было гонки, при которой
      // серверная перезапись (insertOrReplace) затирает несинхронизированные
      // локальные правки. Conflict resolution: приоритет сервера ПОСЛЕ выгрузки
      // наших изменений.
      // OAuth-токен мог истечь, пока приложение было закрыто. Обновляем ДО
      // синхронизации: иначе сервер вернёт 401, и аккаунт будет ошибочно
      // помечен как «требуется вход», хотя достаточно освежить токен.
      // (Обновление было только в фоновом сервисе — при обычном открытии
      // приложения не выполнялось.)
      if (account.usesOAuthTokens) {
        try {
          await _ref.read(oauthServiceProvider).ensureValidToken(account);
          AppLogger.debug('OAuth-токен проверен перед синхронизацией: ${account.email}');
        } on OAuthRefreshFailure catch (e) {
          if (e.needsSignIn) {
            // Вход отозван — сразу «требуется вход» (плашка «Войти снова»).
            // Раньше ящик молча не синхронизировался, без объяснения.
            await _authFailure(account, e.reason);
            return;
          }
          // Сбой прокси или сети. Если токен ещё действует — работаем им;
          // если истёк, в почту не входим: вход просроченным токеном — это
          // неудачный вход, а их серверы считают (до блокировки).
          final exp = await _ref.read(secureStorageProvider).getTokenExpiry(account.id);
          if (exp == null || DateTime.now().isAfter(exp)) {
            AppLogger.warning('Синхронизация ${account.email} пропущена: $e');
            _ref.read(syncMessageProvider.notifier).state = '${account.email}: ${e.reason}';
            return;
          }
          AppLogger.warning('Токен ${account.email} не обновлён, текущий ещё действует: ${e.reason}');
        } catch (e) {
          AppLogger.warning('Не удалось обновить токен ${account.email}: $e');
        }
      }

      // Очередь — не дольше 3 минут: зависшая операция не должна держать
      // загрузку почты (письма к отправке подберёт следующий проход).
      try {
        await _stage(account, 'очередь изменений', () => _processQueue(account.id),
            limit: const Duration(minutes: 3));
      } on TimeoutException {
        // уже в журнале — продолжаем синхронизацию
      }

      if (account.usesEas) {
        // организации / ActiveSync — синхронизация через EAS (WBXML)
        await _syncEas(account, settings);
      } else if (account.usesEws || account.isExchange) {
        await _stage(account, 'синхронизация EWS', () => _syncExchange(account, settings));
      } else {
        await _syncImap(account, settings);
      }

      // Контакты из уже загруженной почты (один раз на ящик) и фото коллег
      // из адресной книги организации (понемногу за синк).
      unawaited(() async {
        try {
          final db = _ref.read(databaseProvider);
          final sent = await (db.select(db.folders)
                ..where((f) => f.accountId.equals(account.id) & f.type.equals(FolderType.sent.index))
                ..limit(1))
              .getSingleOrNull();
          final mc = _ref.read(mailContactsServiceProvider);
          await mc.backfillOnce(account, sentFolderId: sent?.id);
          // Фото коллег — только пока приложение открыто: в фоне их никто
          // не видит, а это лишние запросы к адресной книге на каждом проходе.
          if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
            await mc.fetchPhotos(account);
          }
        } catch (e) {
          AppLogger.debug('Контакты из переписки: $e');
        }
      }());

      // Настоящие адреса и имя владельца ящика (раз в сутки): вход под
      // одним адресом, ящик — под другим (см. own_addresses.dart).
      unawaited(_ref.read(ownIdentityServiceProvider).learn(account).catchError((Object e) {
        AppLogger.debug('Свои адреса: $e');
      }));

      _accountErrors.remove(account.id);

      // Время последней успешной синхронизации — показывается на экране
      // аккаунта (вместо постоянно крутящегося индикатора в списке писем).
      try {
        final db = _ref.read(databaseProvider);
        await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
            .write(AccountsCompanion(lastSyncAt: Value(DateTime.now())));
      } catch (_) {}

      // Синхронизация прошла — снимаем отметку об ошибке входа, если она была
      // (пользователь обновил пароль). Иначе метка осталась бы навсегда, и
      // аккаунт вечно выглядел бы проблемным.
      if (account.authFailedAt != null) {
        try {
          final db = _ref.read(databaseProvider);
          await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
              .write(const AccountsCompanion(authFailedAt: Value(null)));
          _authStrike.remove(account.id);
          AppLogger.info('Аккаунт ${account.email}: вход восстановлен');
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.error('Sync ${account.email}: $e');
      _accountErrors[account.id] = _shortError(e);
      // Учётные данные отвергнуты ПОСЛЕ успешного подключения: сменили пароль
      // по политике, заблокировали учётку, отозвали токен. Продолжать попытки
      // опасно — на многих серверах несколько неудачных входов приводят к
      // блокировке. Помечаем аккаунт и сообщаем пользователю.
      if (_isAuthError(e)) {
        await _authFailure(account, '$e');
      } else {
        _retryFirstSync(account);
      }
    }
  }

  /// Ящики, которым уже назначен повтор первой синхронизации в этом сеансе.
  final Set<String> _firstSyncRetried = {};

  /// Первая синхронизация нового ящика не удалась (не из-за пароля) — один
  /// повтор через 15 с. Раньше письма появлялись только после жеста
  /// «обновить» или через 5 минут (журнал iPhone 18.10.2026).
  void _retryFirstSync(AccountModel account) {
    if (account.lastSyncAt != null || AppLogger.isBackground) return;
    if (!_firstSyncRetried.add(account.id)) return;
    AppLogger.info('Первая синхронизация ${account.email} не удалась — повтор через 15 с');
    Timer(const Duration(seconds: 15), () {
      final still = _ref.read(accountsProvider).any((a) => a.id == account.id);
      if (still) unawaited(syncAccount(account));
    });
  }

  /// Синхронизация через ActiveSync (EAS): почта + календарь + контакты + задачи.
  Future<void> _syncEas(AccountModel account, AppSettings settings) async {
    final engine = _ref.read(mailEngineServiceProvider);
    final db = _ref.read(databaseProvider);
    final total = Stopwatch()..start();

    // 0. Подключение. При ошибке (в том числе 401 — сменили пароль) бросает
    // исключение с причиной: его разбирает _syncAccountSafe и ставит отметку
    // «требуется вход». Раньше неудачное подключение выглядело как «писем нет».
    await _stage(account, 'подключение', () => engine.ensureConnected(account),
        limit: const Duration(minutes: 2));

    // Имя владельца из адресной книги: при входе известен только логин
    // («i.petrov»), а в приветствии, подписи и списке аккаунтов нужно ФИО.
    try {
      await _stage(account, 'карточка владельца', () => _refreshOwnerCard(engine, db, account),
          limit: const Duration(seconds: 60));
    } catch (e) {
      AppLogger.warning('Адресная книга (карточка владельца): $e');
    }

    // 1. Папки (через единый движок mail_engine). Список папок меняется
    // редко, а на медленном шлюзе FolderSync — 4–6 с каждого прохода
    // (журнал 11.10.2026: каждые 15 минут FolderSync «без изменений»).
    // Поэтому — не чаще раза в час, по «обновить» и при открытии экрана
    // аккаунта — всегда; в остальные проходы папки берутся из базы.
    List<FolderModel> folders;
    final lastFs = _easFolderSyncAt[account.id];
    final fresh = lastFs != null &&
        DateTime.now().difference(lastFs) < const Duration(minutes: 60) &&
        !_folderSyncForce.remove(account.id);
    final stored = fresh
        ? [
            for (final r in await (db.select(db.folders)..where((f) => f.accountId.equals(account.id))).get())
              folderFromRow(r)
          ]
        : const <FolderModel>[];
    if (stored.isNotEmpty) {
      folders = stored;
    } else {
      folders = await _stage(account, 'список папок', () => engine.getFolders(account),
          limit: const Duration(minutes: 3));
      if (folders.isNotEmpty) {
        folders = await _batchSaveFolders(db, account.id, folders);
        await _pruneVanishedEasFolders(db, account, folders);
        _easFolderSyncAt[account.id] = DateTime.now();
      }
    }

    // 2. Почта по синхронизируемым папкам (через единый движок). Выбор берём
    // из базы («Настройки → Синхронизация папок»), а не из ответа сервера:
    // там isSynced — лишь умолчание по типу папки, и включённые
    // пользователем папки никогда не синхронизировались.
    final chosen = await _chosenFolders(db, account.id, folders);
    // Сначала одним запросом узнаём, где есть изменения, и ходим только туда.
    final estimate = await _stage(account, 'оценка изменений',
        () => engine.estimateMailChanges(account, [for (final f in chosen) f.id]),
        limit: const Duration(minutes: 3));
    final easFailed = <String>[];
    var easTried = 0;
    for (final folder in chosen) {
      if (estimate[folder.id] == 0) continue; // изменений нет — запрос не нужен
      easTried++;
      try {
        await _stage(account, 'папка ${folder.displayName}',
            () => _syncEasMailFolder(engine, db, account, folder, settings));
      } catch (e) {
        AppLogger.error('EAS sync ${folder.displayName}: $e');
        // Ошибка входа касается всего аккаунта — пробрасываем наверх, чтобы
        // отметить аккаунт и не долбить сервер неверным паролем по каждой папке.
        if (_isAuthError(e)) rethrow;
        easFailed.add('${folder.displayName}: ${_shortError(e)}');
        // Связь оборвалась — остальные папки этого прохода не ждём (каждая
        // ждала бы таймаута). Их подберёт следующий push или проход.
        if (_isNetworkError(e)) {
          _easOutageAt[account.id] = DateTime.now();
          AppLogger.warning('EAS ${account.email}: сбой связи — остальные папки в следующий раз');
          break;
        }
      }
    }
    // Папку удалили или перенесли в Outlook (Sync ответил Status 8/12) —
    // список папок сразу, а не через час: иначе удалённая папка висела в
    // меню, а каждый проход запрашивал её снова (замечание 15.10.2026).
    if (engine.takeFolderHierarchyChanged(account.id)) {
      try {
        final fresh = await _stage(account, 'список папок (изменён на сервере)',
            () => engine.getFolders(account), limit: const Duration(minutes: 3));
        if (fresh.isNotEmpty) {
          folders = await _batchSaveFolders(db, account.id, fresh);
          await _pruneVanishedEasFolders(db, account, folders);
          _easFolderSyncAt[account.id] = DateTime.now();
        }
      } catch (e) {
        AppLogger.warning('Список папок ${account.email} после изменения на сервере: $e');
        _easFolderSyncAt.remove(account.id);
      }
    }
    if (easFailed.isEmpty && easTried > 0) _easOutageAt.remove(account.id);
    // Не обновилась ни одна папка — синхронизация не удалась (видно в
    // статусе и на экране аккаунта); часть — отмечаем частичной.
    if (easFailed.isNotEmpty && easFailed.length >= easTried) {
      throw Exception(easFailed.first);
    } else if (easFailed.isNotEmpty) {
      _partialErrors[account.id] = easFailed.join('; ');
    }

    // 3–4. Календарь, контакты, заметки, задачи — не чаще раза в 5 минут
    // (по жесту «обновить» — всегда) и ОТДЕЛЬНЫМИ короткими сеансами после
    // почты (_syncEasPimSessions): ящик освобождается между ними, и
    // письмо по push или очередь отправки не ждут календаря и контактов.
    if (_pimDue(account.id)) _pimWanted.add(account.id);

    // 5. Непрочитанные
    final unread = await db.countUnread(account.id);
    unawaited(_ref.read(accountsProvider.notifier).updateUnreadCount(account.id, unread));
    AppLogger.info('EAS sync done: ${account.email} ${_stageSummary(account.id, total)}');
  }

  /// ActiveSync: календарь (отдельный короткий сеанс).
  Future<void> _easPimCalendar(MailEngineService engine, AppDatabase db, AccountModel account) async {
    // 3. Календарь
    try {
      final events = await engine.getCalendarEvents(account);
      if (events.isNotEmpty) {
        // Повторяющиеся серии ActiveSync развёрнуты во вхождения
        // («eas_<ServerId>#<день>»). Изменённая серия приходит целиком —
        // старые вхождения убираем, иначе после переноса встречи остались бы
        // и прежние даты.
        final masters = {
          for (final e in events)
            e.id.contains('#') ? e.id.substring(0, e.id.indexOf('#')) : e.id,
        };
        final keepReminders = await _existingReminders(db, account.id);
        for (final m in masters) {
          await (db.delete(db.calendarEvents)
                ..where((t) => t.accountId.equals(account.id) & (t.id.equals(m) | t.id.like('$m#%'))))
              .go();
        }
        await db.batch((batch) {
          for (final event in events) {
            batch.insert(db.calendarEvents,
              CalendarEventsCompanion.insert(
                id: event.id, accountId: event.accountId, title: event.title,
                description: Value(event.description), location: Value(event.location),
                startTime: event.startTime, endTime: event.endTime,
                isAllDay: Value(event.isAllDay), organizerEmail: Value(event.organizerEmail),
                attendeesJson: Value(event.attendees.isEmpty
                    ? null
                    : jsonEncode([
                        for (final a in event.attendees)
                          {'email': a.email, 'displayName': a.displayName, 'isRequired': a.isRequired, if (a.response != 0) 'response': a.response},
                      ])),
                recurrence: Value(event.recurrence.index), priority: Value(event.priority.index),
                colorValue: Value(event.colorValue), isPrivate: Value(event.isPrivate),
                remindersJson: Value(_remindersJson(event, keepReminders)),
                createdAt: event.createdAt,
              ), mode: InsertMode.insertOrReplace);
          }
        });
        AppLogger.info('EAS Calendar: ${events.length} событий');
      }
      // Полная перечитка: события сервера в окне, которых нет в ответе,
      // удалены на сервере (удаление могло не дойти, пока ключ сбрасывался).
      final full = engine.takeCalendarFullWindow(account.id);
      if (full != null) {
        final fresh = {for (final e in events) e.id};
        final local = await (db.select(db.calendarEvents)
              ..where((t) =>
                  t.accountId.equals(account.id) &
                  t.id.like(r'eas\_%', escapeChar: '\\') &
                  t.startTime.isBiggerOrEqualValue(full.from) &
                  t.startTime.isSmallerOrEqualValue(full.to)))
            .get();
        final gone = [for (final r in local) if (!fresh.contains(r.id)) r.id];
        for (var i = 0; i < gone.length; i += 400) {
          final part = gone.sublist(i, i + 400 > gone.length ? gone.length : i + 400);
          await (db.delete(db.calendarEvents)
                ..where((t) => t.accountId.equals(account.id) & t.id.isIn(part)))
              .go();
        }
        if (gone.isNotEmpty) AppLogger.info('EAS Calendar: убрано удалённых на сервере — ${gone.length}');
      }
      await _deletePim(account.id, 'Calendar', (ids) async {
        var n = 0;
        for (final id in ids) {
          // Вместе с элементом — все вхождения его серии.
          n += await (db.delete(db.calendarEvents)
                ..where((t) => t.accountId.equals(account.id) & (t.id.equals(id) | t.id.like('$id#%'))))
              .go();
        }
        return n;
      });
      await engine.commitPimSync(account.id, 'Calendar');
    } catch (e) {
      engine.discardPimSync(account.id, 'Calendar');
      AppLogger.error('EAS calendar sync: $e');
    }
  }

  /// ActiveSync: контакты (отдельный короткий сеанс).
  Future<void> _easPimContacts(MailEngineService engine, AppDatabase db, AccountModel account) async {
    // 4. Контакты
    try {
      final contacts = await engine.getContacts(account);
      if (contacts.isNotEmpty) {
        // Сверенные с адресной книгой коллеги (1.8.0+118): компания, отдел,
        // должность — из неё, а не из копии в личных контактах.
        final dirs = await _dirOrgs(db, account.id);
        await db.batch((batch) {
          for (final c in contacts) {
            final known = dirs[c.id];
            final dir = known != null && known.matches(c.email) ? known : null;
            String? org(String field, String? server) => dir == null ? server : dir.pick(field, server);
            // Адрес контакта сменился — сверка с адресной книгой заново.
            final reset = known != null && dir == null;
            // Обновляются только серверные поля: insertOrReplace сбрасывал
            // локальные (избранное, VIP, счётчик писем) при каждой правке
            // контакта на сервере, а отчество и отдел вовсе не сохранялись.
            final row = ContactsCompanion.insert(
              id: c.id, accountId: Value(c.accountId), email: c.email,
              displayName: c.displayName, firstName: Value(c.firstName),
              middleName: Value(c.middleName),
              lastName: Value(c.lastName), company: Value(org('company', c.company)),
              jobTitle: Value(org('jobTitle', c.jobTitle)), department: Value(org('department', c.department)),
              manager: Value(org('manager', c.manager)),
              // Кабинет (Contacts:OfficeLocation) — с 1.6.49.
              office: Value(org('office', c.office)),
              phoneWork: Value(org('phoneWork', c.phoneWork)),
              dirCheckedAt: reset ? const Value(null) : const Value.absent(),
              dirOrg: reset ? const Value(null) : const Value.absent(),
              phoneMobile: Value(c.phoneMobile), source: Value(c.source.index),
              // Нет фото в ответе сервера — фото из адресной книги организации
              // (записанное отдельно) не стирается (1.5.12).
              avatarUrl: (c.avatarUrl ?? '').isEmpty ? const Value.absent() : Value(c.avatarUrl),
            );
            batch.insert(db.contacts, row, onConflict: DoUpdate((_) => row));
          }
        });
        AppLogger.info('EAS Contacts: ${contacts.length}');
      }
      // Пересинхронизация (1.6.32): пришли все контакты сервера — контакты
      // Exchange этого ящика, которых на сервере нет, убираются.
      if (engine.takeContactsFull(account.id)) {
        final keep = {for (final c in contacts) c.id};
        final stale = await (db.select(db.contacts)
              ..where((t) => t.accountId.equals(account.id) & t.id.like(r'eas\_%', escapeChar: '\\')))
            .map((r) => r.id)
            .get();
        final gone = [for (final id in stale) if (!keep.contains(id)) id];
        if (gone.isNotEmpty) {
          await (db.delete(db.contacts)..where((t) => t.accountId.equals(account.id) & t.id.isIn(gone))).go();
          AppLogger.info('EAS Contacts: убрано отсутствующих на сервере — ${gone.length}');
        }
      }
      await _deletePim(account.id, 'Contacts', (ids) =>
          (db.delete(db.contacts)
                ..where((t) => t.accountId.equals(account.id) & t.id.isIn(ids)))
              .go());
      await engine.commitPimSync(account.id, 'Contacts');
      unawaited(_refreshColleagues(account));
    } catch (e) {
      engine.discardPimSync(account.id, 'Contacts');
      AppLogger.error('EAS contacts sync: $e');
    }
  }

  /// ActiveSync: заметки (отдельный короткий сеанс).
  Future<void> _easPimNotes(MailEngineService engine, AppDatabase db, AccountModel account) async {
    // 4b. Заметки (EAS). Сначала выгружаем локальные правки, затем берём
    // серверные — не затирая строки, правка которых ещё не ушла.
    try {
      try {
        await _ref.read(mailEngineServiceProvider).pushPendingNotes(account);
      } catch (e) {
        AppLogger.warning('EAS notes push: $e');
      }
      final pending = (await (db.select(db.notes)
                ..where((n) => n.accountId.equals(account.id) & n.isLocallyModified.equals(true)))
              .get())
          .map((n) => n.serverId)
          .whereType<String>()
          .toSet();
      final notes = (await engine.getNotes(account))
          .where((n) => !pending.contains(n.serverId))
          .toList();
      if (notes.isNotEmpty) {
        final now = DateTime.now().toUtc();
        await db.batch((batch) {
          for (final n in notes) {
            batch.insert(db.notes,
              NotesCompanion.insert(
                id: noteRowId(eas: true, accountId: account.id, serverId: n.serverId ?? n.id),
                accountId: Value(account.id),
                title: Value(n.title),
                body: Value(n.body),
                serverId: Value(n.serverId),
                categoriesStr: Value(n.categories.isEmpty ? null : n.categories.join(',')),
                createdAt: now,
                modifiedAt: now,
              ), mode: InsertMode.insertOrReplace);
          }
        });
        AppLogger.info('EAS Notes: ${notes.length}');
      }
      // У заметок id строки строится иначе, поэтому удаляем по serverId.
      await _deletePim(account.id, 'Notes', (ids) =>
          (db.delete(db.notes)
                ..where((t) =>
                    t.accountId.equals(account.id) &
                    t.serverId.isIn([for (final i in ids) i.startsWith('eas_') ? i.substring(4) : i])))
              .go());
      await engine.commitPimSync(account.id, 'Notes');
    } catch (e) {
      engine.discardPimSync(account.id, 'Notes');
      AppLogger.error('EAS notes sync: $e');
    }
  }

  /// ActiveSync: задачи (отдельный короткий сеанс).
  Future<void> _easPimTasks(MailEngineService engine, AppDatabase db, AccountModel account) async {
    // 4c. Задачи (EAS)
    try {
      final tasks = await engine.getTasks(account);
      if (tasks.isNotEmpty) {
        await db.batch((batch) {
          for (final t in tasks) {
            // Серверные поля обновляются, локальные (исполнитель, теги,
            // подзадачи, дата создания) сохраняются; описание — с сервера.
            final row = TasksCompanion.insert(
              id: t.id,
              accountId: t.accountId,
              title: t.title,
              description: Value(t.description),
              status: Value(t.status.index),
              priority: Value(t.priority.index),
              createdAt: t.createdAt,
              dueDate: Value(t.dueDate),
              completedAt: Value(t.completedAt),
              // ActiveSync хранит напоминание на сервере (ReminderTime) —
              // берём его оттуда, как и срок.
              reminderAt: Value(t.reminderAt),
            );
            batch.insert(db.tasks, row,
                onConflict: DoUpdate((_) => row.copyWith(createdAt: const Value.absent())));
          }
        });
        AppLogger.info('EAS Tasks: ${tasks.length}');
      }
      await _deletePim(account.id, 'Tasks', (ids) =>
          (db.delete(db.tasks)
                ..where((t) => t.accountId.equals(account.id) & t.id.isIn(ids)))
              .go());
      await engine.commitPimSync(account.id, 'Tasks');
    } catch (e) {
      engine.discardPimSync(account.id, 'Tasks');
      AppLogger.error('EAS tasks sync: $e');
    }
  }

  MailTransport _transportFor(AccountModel account) =>
      _ref.read(mailTransportFactoryProvider).forAccount(account);

  /// Папка письма для операции из очереди: из payload (новые записи) или из
  /// БД (записи, поставленные до появления этого поля).
  Future<String> _queueFolder(
      AppDatabase db, String accountId, String emailId, Object? fromPayload) async {
    if (fromPayload is String && fromPayload.isNotEmpty) return fromPayload;
    final row = await (db.selectOnly(db.emails)
          ..addColumns([db.emails.folderId])
          ..where(db.emails.id.equals(emailId) & db.emails.accountId.equals(accountId)))
        .getSingleOrNull();
    return row?.read(db.emails.folderId) ?? '';
  }

  Future<void> _clearLocalMark(AppDatabase db, String accountId, String emailId) async {
    await (db.update(db.emails)
          ..where((e) => e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(const EmailsCompanion(isLocallyModified: Value(false)));
  }

  /// Применить удаления и смену флагов, пришедшие с сервера.
  ///
  /// Письмо, прочитанное или удалённое в Outlook на компьютере, раньше так и
  /// оставалось на телефоне непрочитанным и «живым». Локально изменённые
  /// строки (isLocallyModified — правка ещё в очереди на отправку) не трогаем:
  /// иначе сервер откатил бы действие пользователя до того, как оно ушло.
  /// Синхронизация почтовой папки EAS: каждая порция сохраняется в БД
  /// внутри движка ДО записи нового SyncKey (см. MailEngineService.syncFolder).
  /// Уведомление — одно на папку после всех порций, а не на каждую порцию.
  Future<void> _syncEasMailFolder(
    MailEngineService engine,
    AppDatabase db,
    AccountModel account,
    FolderModel folder,
    AppSettings settings,
  ) async {
    final received = <EmailModel>[];
    var addedTotal = 0;
    // Первая загрузка — и все её продолжения (догрузка остатка): старые
    // письма из хвоста первичной загрузки — тоже не «новая почта».
    final noKey = !engine.hasMailSyncState(account.id, folder.id);
    final initial = noKey || _continuations.containsKey('${account.id}|${folder.id}');
    // Начало прохода (секунды, как cached_at в базе): строки, которые
    // загрузка папки заново не обновила, после неё убираются.
    final startedSec = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
    final reinitKey = 'eas_reinit:${account.id}:${folder.id}';
    if (noKey && _prefs.getInt(reinitKey) == null && await _folderHasEmails(db, account.id, folder.id)) {
      // Ключа нет, а письма папки на телефоне есть (ключ потерян, папку
      // включили снова) — это тоже загрузка заново.
      await _prefs.setInt(reinitKey, startedSec);
    }
    final res = await engine.syncFolder(account, folder.id, onBatch: (batch) async {
      if (engine.takeMailReinit(account.id, folder.id) && _prefs.getInt(reinitKey) == null) {
        await _prefs.setInt(reinitKey, startedSec);
        AppLogger.warning('ActiveSync ${folder.displayName}: сервер сбросил синхронизацию — папка загружается заново');
      }
      if (batch.added.isNotEmpty) {
        addedTotal += await _batchSaveEmails(db, account.id, folder, batch.added);
        received.addAll(batch.added);
      }
      await _applyServerChanges(db, account.id, batch);
    });
    if (engine.takeMailReinit(account.id, folder.id) && _prefs.getInt(reinitKey) == null) {
      await _prefs.setInt(reinitKey, startedSec);
    }
    // Загрузка заново закончена: письма, которых сервер больше не прислал
    // (удалены за время сброса или остались со старыми ServerId), — прочь.
    // Иначе они висели бы в ленте вечно: сервер о них не знает и удаления
    // не пришлёт.
    final since = _prefs.getInt(reinitKey);
    if (since != null && !res.moreAvailable) {
      await _prefs.remove(reinitKey);
      final n = await db.customUpdate(
        'DELETE FROM emails WHERE account_id = ? AND folder_id = ? AND is_locally_modified = 0 '
        'AND (cached_at IS NULL OR cached_at < ?)',
        variables: [Variable.withString(account.id), Variable.withString(folder.id), Variable.withInt(since)],
        updates: {db.emails},
        updateKind: UpdateKind.delete,
      );
      if (n > 0) AppLogger.info('ActiveSync ${folder.displayName}: после загрузки заново убрано устаревших писем — $n');
    }
    // Первая загрузка ящика — это не «новая почта»: без уведомлений.
    if (received.isNotEmpty && !initial) {
      await _notifyNewMail(account, folder, received, addedTotal, settings);
    }
    if (received.isNotEmpty) {
      unawaited(_prefetchAttachments(account, received, settings));
    }
    if (res.moreAvailable) {
      _scheduleContinuation(account, folder);
    } else {
      _continuations.remove('${account.id}|${folder.id}');
    }
  }

  /// Продолжение синхронизации папки, если сервер ответил MoreAvailable после
  /// лимита раундов. Раньше остаток ждал следующего синка (push/таймер) —
  /// первичная загрузка большого ящика растягивалась на часы. Теперь
  /// догружаем сразу, но с паузой (не держим блокировку аккаунта подряд —
  /// push и отправка успевают пройти) и с ограничением цепочки.
  final Map<String, int> _continuations = {};
  static const _maxContinuations = 40; // 40 × 20 раундов × 50 писем ≈ 40 000

  void _scheduleContinuation(AccountModel account, FolderModel folder) {
    final key = '${account.id}|${folder.id}';
    final n = (_continuations[key] ?? 0) + 1;
    if (n > _maxContinuations) {
      AppLogger.warning('Синк ${account.email}/${folder.displayName}: '
          'достигнут лимит продолжений, остаток — при следующей синхронизации');
      _continuations.remove(key);
      return;
    }
    _continuations[key] = n;
    AppLogger.info('Синк ${account.email}/${folder.displayName}: '
        'догружаем остаток (шаг $n)');
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        await syncSingleFolder(account, folder);
      } catch (e) {
        _continuations.remove(key);
        AppLogger.warning('Продолжение синхронизации ${folder.displayName}: $e');
      }
    });
  }

  Future<void> _applyServerChanges(
      AppDatabase db, String accountId, EngineFolderSync r) async {
    if (r.deletedIds.isEmpty && r.flagChanges.isEmpty) return;
    try {
      await db.transaction(() async {
        if (r.deletedIds.isNotEmpty) {
          await (db.delete(db.emails)
                ..where((e) =>
                    e.accountId.equals(accountId) &
                    e.id.isIn(r.deletedIds) &
                    e.isLocallyModified.equals(false)))
              .go();
        }
        for (final c in r.flagChanges) {
          await (db.update(db.emails)
                ..where((e) =>
                    e.accountId.equals(accountId) &
                    e.id.equals(c.id) &
                    e.isLocallyModified.equals(false)))
              .write(EmailsCompanion(
            isRead: c.read == null ? const Value.absent() : Value(c.read!),
            isFlagged: c.flagged == null ? const Value.absent() : Value(c.flagged!),
          ));
        }
      });
      AppLogger.info('С сервера: удалено ${r.deletedIds.length}, '
          'изменено флагов ${r.flagChanges.length}');
    } catch (e) {
      // Пробрасываем: порция не применена — SyncKey не должен сдвинуться,
      // иначе удаления с сервера потеряются навсегда (см. _syncEasMailFolder).
      AppLogger.warning('Не удалось применить изменения с сервера: $e');
      rethrow;
    }
  }

  /// Удалить локально PIM-элементы, удалённые на сервере.
  Future<void> _deletePim(String accountId, String dataClass,
      Future<int> Function(List<String> ids) delete) async {
    final ids = _ref.read(mailEngineServiceProvider).takePimDeletions(accountId, dataClass);
    if (ids.isEmpty) return;
    final n = await delete(ids);
    AppLogger.info('EAS $dataClass: удалено на сервере — $n');
  }

  // ════════════════════════ EXCHANGE ════════════════════════

  Future<void> _syncExchange(AccountModel account, AppSettings settings) async {
    final ews = _ref.read(ewsServiceProvider);
    final db = _ref.read(databaseProvider);
    // Архив Exchange (1.6.49) — только почта: ни календаря, ни карточки.
    final archive = account.isOnlineArchive;

    // Карточка владельца из адресной книги (раз в сутки): для подписи и
    // «Моего подразделения». Ошибка не мешает синхронизации почты.
    if (!archive) {
      try {
        await _ref.read(mailEngineServiceProvider).refreshSelfCard(account);
      } catch (e) {
        AppLogger.debug('Карточка владельца (EWS): $e');
      }
    }

    // Общий ящик, к почте которого доступа нет (только календарь, 1.6.49):
    // папки не просим — раз в сутки проверка, не выдали ли доступ.
    final shared = account.isSharedMailbox && !archive;
    var calendarOnly =
        shared && SharedAccess.calendarOnly(_prefs, account.id) && !SharedAccess.recheckDue(_prefs, account.id);

    int totalNew = 0;
    if (!calendarOnly) {
      // 1. Папки
      var folders = await ews.getFolders(account);
      if (shared && folders.isEmpty) {
        // Сервер ответил «нет доступа» к папкам — дальше только календарь.
        if (!SharedAccess.calendarOnly(_prefs, account.id)) {
          AppLogger.info('Общий ящик ${AppLogger.mask(account.email)}: доступа к почте нет — только календарь');
        }
        await SharedAccess.setCalendarOnly(_prefs, account.id, true);
        calendarOnly = true;
      } else {
        if (shared && SharedAccess.calendarOnly(_prefs, account.id)) {
          await SharedAccess.setCalendarOnly(_prefs, account.id, false);
          AppLogger.info('Общий ящик ${AppLogger.mask(account.email)}: доступ к почте появился');
        }
        folders = await _batchSaveFolders(db, account.id, folders);

        // 2. Письма — параллельно (max 3)
        // Выбор пользователя — из базы (см. _chosenFolders), а не умолчание сервера.
        final foldersToSync = await _chosenFolders(db, account.id, folders);

        final futures = <Future<int>>[];
        for (final folder in foldersToSync) {
          // Ждём свободного места среди параллельных
          await _acquireSlot();
          futures.add(
            _syncFolder(account, folder, ews, db, settings).whenComplete(_releaseSlot),
          );
        }

        _ewsFolderErrors.remove(account.id);
        final results = await Future.wait(futures);
        totalNew = results.fold(0, (sum, n) => sum + n);
        // Ошибки папок раньше только писались в журнал, синхронизация считалась
        // успешной — человек видел «синхронизировано» при неработающем ящике.
        final folderErrors = _ewsFolderErrors.remove(account.id) ?? const <String>[];
        if (folderErrors.isNotEmpty && folderErrors.length >= foldersToSync.length) {
          throw Exception(folderErrors.first);
        } else if (folderErrors.isNotEmpty) {
          _partialErrors[account.id] = folderErrors.join('; ');
        }
      }
    }

    // 3. Уведомления о письмах показывает _syncFolder (по папкам) вместе со
    //    сводкой группы — отдельная сводка здесь дублировала бы её.

    // 4. Непрочитанные
    final unread = await db.countUnread(account.id);
    unawaited(_ref.read(accountsProvider.notifier).updateUnreadCount(account.id, unread));

    if (archive) {
      AppLogger.info('Sync done: архив ${AppLogger.mask(account.email)} ($totalNew new)');
      return;
    }

    // 5. Календарь
    await _syncCalendar(account, ews, db);

    if (!calendarOnly) {
      // 6. Контакты
      await _syncContacts(account, ews, db);

      // 7. Заметки
      await _syncNotes(account, ews, db);
      await _syncEwsTasks(account, ews, db);
    }

    AppLogger.info('Sync done: ${account.email} ($totalNew new${calendarOnly ? ', только календарь' : ''})');
  }

  /// Синхронизация одной папки — возвращает количество новых
  Future<int> _syncFolder(
    AccountModel account,
    FolderModel folder,
    EwsService ews,
    AppDatabase db,
    AppSettings settings,
  ) async {
    try {
      // ── DELTA-СИНХРОНИЗАЦИЯ ──
      // Раньше здесь всегда был FindItem — ПОЛНАЯ перезагрузка списка при каждом
      // синке. `ews_delta_sync` (SyncFolderItems) был написан и не вызывался:
      // он тянет только изменения (Create/Update/Delete) и, по замеру автора,
      // экономит 90%+ трафика на повторных синхронизациях. Для Exchange это
      // основной сценарий.
      //
      // Как работает состояние: при syncState=null сервер отдаёт всё содержимое
      // порциями, каждый раз возвращая новый токен; когда includesLastItem=true —
      // токен указывает на КОНЕЦ, и дальше приходят только изменения. Поэтому
      // первый проход нужно ДОЧИТАТЬ до конца: если сохранить токен раньше,
      // следующая дельта отдаст остаток как «новые письма» и перекачает всё.
      final List<EmailModel> emails;
      final stateKey = _ewsDeltaKey(account.id, folder.id);
      final deletedIds = <String>[];
      final readChanges = <String, bool>{};
      String? state = _prefs.getString(stateKey);
      final initialLoad = state == null;
      var reachedLast = false;
      var deltaFailed = false;
      final collected = <EmailModel>[];

      // ── БОЛЬШИЕ ЯЩИКИ ──
      // SyncFolderItems перечисляет папку целиком, от старых писем к новым:
      // в ящике на десятки тысяч писем первая синхронизация скачивала до 4000
      // писем за проход (и все — за много проходов), хотя хранится только
      // период аккаунта. Теперь при первой синхронизации: свежие письма — через
      // FindItem (от новых к старым, до среза периода), а курсор дельты
      // «перематывается» до конца запросами только с идентификаторами.
      final primeKey = 'ews_prime_${account.id}_${folder.id}';
      final cutoff = _cutoffFor(account.id);
      var skipDelta = false;
      if ((state == null && cutoff != null) || (_prefs.getBool(primeKey) ?? false)) {
        if (state == null) {
          for (var off = 0; off < 2000; off += 200) {
            final page = await ews.getEmails(account,
                folderId: folder.id, offset: off, count: 200, fetchMode: settings.emailFetchMode);
            collected.addAll(page);
            if (page.length < 200 || page.any((e) => e.receivedAt.isBefore(cutoff!))) break;
          }
          await _prefs.setBool(primeKey, true);
        }
        var reachedEnd = false;
        for (var p = 0; p < 100; p++) {
          final d = await _ewsDelta.syncFolder(
              account: account, folderId: folder.id, syncState: state, maxChanges: 512, idOnly: true);
          if (d.error != null) break;
          state = d.syncState;
          if (state != null) await _prefs.setString(stateKey, state);
          if (d.includesLastItem) {
            reachedEnd = true;
            break;
          }
        }
        // Письма, пришедшие за время перемотки, курсор «проглотил» —
        // свежие подтягиваем ещё раз.
        collected.addAll(await ews.getEmails(account,
            folderId: folder.id, offset: 0, count: 50, fetchMode: settings.emailFetchMode));
        if (reachedEnd) {
          await _prefs.remove(primeKey);
        } else {
          skipDelta = true; // перемотка продолжится в следующий проход
        }
      }

      // Ограничение на число страниц: у первой синхронизации большого ящика их
      // может быть много, а мы не должны зациклиться при странном ответе.
      const maxPages = 20;
      for (var page = 0; page < (skipDelta ? 0 : maxPages); page++) {
        final d = await _ewsDelta.syncFolder(
          account: account,
          folderId: folder.id,
          syncState: state,
          // До 512 по протоколу; 200 — разумная порция для первой загрузки.
          maxChanges: 200,
        );
        if (d.error != null) {
          AppLogger.warning('EWS delta (${folder.displayName}): ${d.error}');
          deltaFailed = true;
          break;
        }
        collected..addAll(d.created)..addAll(d.updated);
        deletedIds.addAll(d.deletedIds);
        readChanges.addAll(d.readChanges);
        state = d.syncState;
        if (d.includesLastItem) {
          reachedLast = true;
          break; // токен дошёл до конца — можно сохранять
        }
      }

      if (deltaFailed) {
        // Оптимизация не должна ронять синхронизацию: откат на полный список.
        emails = await ews.getEmails(
          account,
          folderId: folder.id,
          count: AppConstants.emailsPerPage,
          fetchMode: settings.emailFetchMode,
        );
        await _prefs.remove(stateKey); // состояние могло испортиться
      } else {
        emails = collected;
        if (state != null) await _prefs.setString(stateKey, state);
        if (collected.isNotEmpty || deletedIds.isNotEmpty) {
          AppLogger.info('EWS delta (${folder.displayName}): '
              '${collected.length} изменений, удалено ${deletedIds.length}');
        }
      }

      // Удалённые на сервере — убираем локально. Без этого письма, стёртые с
      // другого устройства, оставались бы в списке навсегда: delta сообщает о
      // них один раз.
      if (deletedIds.isNotEmpty) {
        await (db.delete(db.emails)
              ..where((e) => e.accountId.equals(account.id) & e.id.isIn(deletedIds)))
            .go();
      }
      // «Прочитано» изменили на другом устройстве. Строки с неотправленной
      // локальной правкой не трогаем — иначе сервер откатил бы действие.
      for (final entry in readChanges.entries) {
        await (db.update(db.emails)
              ..where((e) =>
                  e.accountId.equals(account.id) &
                  e.id.equals(entry.key) &
                  e.isLocallyModified.equals(false)))
            .write(EmailsCompanion(isRead: Value(entry.value)));
      }

      // Автоправила (если включены). Локальный ИИ-анализ при синхронизации
      // убран вместе с модулем ИИ (этап 1 плана).
      final processed = <EmailModel>[];
      for (final email in emails) {
        var e = email;

        if (kRulesAndCategoriesEnabled && settings.autoRulesEnabled) {
          try {
            final rules = _ref.read(autoRulesProvider.notifier);
            final actions = rules.getMatchingActions(e);
            for (final action in actions) {
              switch (action.type) {
                case RuleActionType.addTag:
                  e = e.copyWith(tags: {...e.tags, action.value}.toList());
                  break;
                case RuleActionType.markAsRead:
                  e = e.copyWith(isRead: action.value == 'true');
                  break;
                case RuleActionType.markFlagged:
                  e = e.copyWith(isFlagged: action.value == 'true');
                  break;
                case RuleActionType.setCategory:
                  e = e.copyWith(categories: [...e.categories, action.value]);
                  break;
                case RuleActionType.moveTo:
                case RuleActionType.moveToFolder:
                  // Правило перемещения: письмо попадает в целевую папку
                  // (применяется локально при сохранении; серверное отражение —
                  // через email_actions при ручном перемещении).
                  if (action.value.isNotEmpty) {
                    e = e.copyWith(folderId: action.value, folderName: action.value);
                  }
                  break;
                default:
                  break;
              }
            }
          } catch (_) {}
        }

        processed.add(e);
      }

      // Batch save
      // Уведомляем только о действительно новых письмах: дельта EWS отдаёт и
      // изменённые (прочитано на другом устройстве и т.п.), и раньше
      // уведомление могло прийти о старом письме.
      final fresh = <EmailModel>[];
      final added = await _batchSaveEmails(db, account.id, folder, processed, collectNewInto: fresh);

      // Уведомление о новых письмах (кроме удалённых/архива/спама/служебных).
      // Первая загрузка папки — не «новая почта».
      if (!initialLoad) await _notifyNewMail(account, folder, fresh, added, settings);
      // Остаток на сервере (перемотка курсора или 20 страниц не хватило) —
      // догружаем сразу, а не при следующем синке.
      if (!deltaFailed && (skipDelta || !reachedLast)) {
        _scheduleContinuation(account, folder);
      } else {
        _continuations.remove('${account.id}|${folder.id}');
      }
      return added;
    } catch (e) {
      AppLogger.error('Sync folder ${folder.displayName}: $e');
      (_ewsFolderErrors[account.id] ??= []).add('${folder.displayName}: ${_shortError(e)}');
      if (_isAuthError(e)) rethrow; // неверный пароль — не «часть папок»
      return 0;
    }
  }

  /// Message-ID писем, о которых уже уведомили (по аккаунту, последние 500).
  static final Map<String, List<String>> _notifiedIds = {};

  static bool _firstNotification(String accountId, EmailModel e) {
    final mid = e.internetMessageId?.trim().toLowerCase();
    if (mid == null || !mid.contains('@')) return true;
    final list = _notifiedIds.putIfAbsent(accountId, () => <String>[]);
    if (list.contains(mid)) return false;
    list.add(mid);
    if (list.length > 500) list.removeRange(0, list.length - 500);
    return true;
  }

  /// Папки, для которых НЕ показываем уведомления о новых письмах: свои
  /// письма (отправленные, черновики, исходящие), корзина и спам. Архив и
  /// пользовательские папки уведомляют (07.10.2026): туда почту раскладывают
  /// серверные правила, и раньше о таких письмах телефон молчал.
  static const _noNotifyFolderTypes = <FolderType>{
    FolderType.trash, FolderType.junk,
    FolderType.sent, FolderType.drafts, FolderType.outbox,
  };

  /// Сколько писем одной пачки показываем отдельными уведомлениями;
  /// остальные — строками сводки.
  static const _maxSingleNotifications = 4;

  /// Уведомление о новых письмах в папке: каждое новое письмо (до
  /// [_maxSingleNotifications] самых свежих) — своим уведомлением с кнопками,
  /// сводка — только для писем сверх этого числа (1.6.4). Раньше показывалось
  /// только последнее письмо пачки — о трёх письмах подряд человек узнавал
  /// как об одном.
  /// Новые письма папки: сначала правила на устройстве (только «Входящие»,
  /// только свежие и не свои), затем уведомления с учётом правил.
  Future<void> _notifyNewMail(
    AccountModel account,
    FolderModel folder,
    List<EmailModel> processed,
    int added,
    AppSettings settings,
  ) async {
    if (added <= 0) return;
    var ruled = const <String, RuleOutcome>{};
    if (folder.type == FolderType.inbox) {
      try {
        final rules = _ref.read(deviceRulesProvider.notifier);
        await rules.reload();
        final recent = DateTime.now().subtract(const Duration(days: 2));
        final fresh = [
          for (final e in processed)
            if (!e.isDraft && e.receivedAt.isAfter(recent) && !OwnAddresses.isMine(account, e.from.email)) e,
        ];
        ruled = await rules.apply(account, folder.id, fresh);
      } catch (e) {
        AppLogger.warning('Правила на устройстве: $e');
      }
    }
    await _showNewMailNotifications(account, folder, processed, added, settings, ruled);
  }

  Future<void> _showNewMailNotifications(
    AccountModel account,
    FolderModel folder,
    List<EmailModel> processed,
    int added,
    AppSettings settings,
    Map<String, RuleOutcome> ruled,
  ) async {
    if (!settings.notificationsEnabled) {
      AppLogger.info('Уведомления: выключены в настройках приложения — новых писем $added не показаны');
      return;
    }
    if (_noNotifyFolderTypes.contains(folder.type)) return;
    // Виртуальные папки Gmail («Вся почта», «Важные», «Помеченные») — те же
    // письма, что во «Входящих»: уведомление приходило дважды.
    if (!folder.showInUnified) return;
    try {
      // Только недавние: «новое для базы» письмо бывает старым (первая
      // загрузка ящика, повторная загрузка после автоочистки) — уведомлять о
      // письме недельной давности как о новом нельзя.
      final recent = DateTime.now().subtract(const Duration(days: 2));
      final focus = _ref.read(focusModeProvider.notifier);
      // Уведомления этого ящика (1.6.45): все, без звука или только VIP.
      final accMode = AccountNotify.of(_prefs, account.id);
      // Папка без уведомлений (1.7.2, «Синхронизация папок» → колокольчик):
      // молчит для всех писем, кроме правила «уведомлять всегда».
      final folderMuted = FolderNotify.isMuted(_prefs, account.id, folder.id);
      // Беседа без уведомлений (1.8.13, «Без уведомлений» в беседе) — тоже
      // молчит; правило «уведомлять всегда» пробивает и её.
      bool mutedByAccount(EmailModel e) =>
          folderMuted ||
          ConversationNotify.isMuted(_prefs, account.id, e.conversationId) ||
          (accMode == AccountNotifyMode.vipOnly && !focus.isVip(e));
      // Фокус-режим: тихие часы и расписание доставки. Внутри shouldNotify VIP и
      // письма с высоким приоритетом пробивают тишину.
      final fresh = processed
          .where((e) => !e.isRead && !e.isDraft && e.receivedAt.isAfter(recent))
          .where((e) => !OwnAddresses.isMine(account, e.from.email))
          // Одно письмо в двух папках (ярлыки Gmail, копия правилом) — одно
          // уведомление: по Message-ID.
          .where((e) => _firstNotification(account.id, e))
          .toList();
      // Правила: «не уведомлять», переложено или прочитано правилом — тихо;
      // «всегда» — как VIP, и в тихие часы.
      bool byRules(EmailModel e) {
        final r = ruled[e.id];
        if (r?.notify == RuleNotify.always) return true;
        if (mutedByAccount(e)) return false;
        if (r == null) return focus.shouldNotify(e);
        if (r.notify == RuleNotify.none || r.quietlyHandled) return false;
        return focus.shouldNotify(e);
      }
      // Режим фокуса промолчал, а правила не запрещали — копим для сводки
      // в окно доставки (FocusDigest).
      final held = <String>[];
      for (final e in fresh) {
        final r = ruled[e.id];
        if (r != null && (r.notify == RuleNotify.none || r.notify == RuleNotify.always || r.quietlyHandled)) continue;
        // «Только VIP» у ящика — молчание выбрано, в сводку фокуса не копим.
        if (mutedByAccount(e)) continue;
        if (focus.shouldNotify(e)) continue;
        final subj = e.subject.trim().isEmpty ? '—' : e.subject.trim();
        held.add(NotificationText.summaryLine(PersonNames.short(e.from.displayName, email: e.from.email), subj));
      }
      if (held.isNotEmpty) await FocusDigest.hold(_prefs, held);
      final unread = fresh
          .where(byRules)
          .toList()
        // Порядок писем зависит от протокола (delta-синк EWS отдаёт их не по дате).
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      // В журнал — почему уведомления не было: «письмо пришло, а
      // уведомления нет» чаще всего фокус-режим или старые/прочитанные письма.
      AppLogger.info('Уведомления ${AppLogger.mask(account.email)}/${folder.displayName}: новых $added, '
          'непрочитанных свежих ${fresh.length}, к показу ${unread.length}'
          '${fresh.length > unread.length ? ' (фокус-режим, правила или «только VIP» скрыли ${fresh.length - unread.length})' : ''}'
          '${accMode == AccountNotifyMode.all ? '' : ' · у ящика: ${accMode.name}'}'
          '${folderMuted ? ' · папка без уведомлений' : ''}');
      if (unread.isEmpty) return;

      final service = _ref.read(notificationServiceProvider);
      // Подпись ящика показываем, когда аккаунтов несколько: с одним она
      // была бы лишним шумом. Для общего ящика — всегда: реагировать на
      // чужую почту как на свою нельзя.
      // Короткая подпись («i.petrov» или домен, если имена совпадают) —
      // полный адрес занимал полстроки в шапке уведомления (10.10.2026).
      final active = _ref.read(accountsProvider).where((a) => a.isActive).toList();
      final shortLabel = NotificationText.shortMailbox(account.email, [for (final a in active) a.email]);
      final mailboxLabel = (active.length > 1 || account.isSharedMailbox) ? shortLabel : null;
      final folderLabel = folder.type == FolderType.inbox ? null : folder.displayName;

      // Самые старые из показываемых — первыми: в шторке сверху окажется самое свежее.
      final singles = unread.take(_maxSingleNotifications).toList().reversed.toList();
      for (var i = 0; i < singles.length; i++) {
        final e = singles[i];
        await service.showEmailNotification(
          accountId: account.id,
          emailId: e.id,
          // «Фамилия И.О.» (1.5.9): полное ФИО не помещалось в строку.
          senderName: PersonNames.short(e.from.displayName, email: e.from.email),
          subject: e.subject,
          mailboxLabel: mailboxLabel,
          isSharedMailbox: account.isSharedMailbox,
          preview: e.bodyPreview,
          fromEmail: e.from.email,
          folderId: folder.id,
          isVip: focus.isVip(e) || ruled[e.id]?.notify == RuleNotify.always,
          folderLabel: folderLabel,
          receivedAt: e.receivedAt,
          // Звонит только самое свежее письмо пачки.
          silent: i < singles.length - 1,
          // Правило «без звука» или ящик «без звука»: тихий канал, без звука
          // и вибрации (VIP — всё равно со звуком).
          quiet: ruled[e.id]?.notify == RuleNotify.silent || accMode == AccountNotifyMode.quiet,
          isInvite: e.meeting?.isRequest == true,
        );
      }

      // Сводка «N новых писем» — только когда писем больше, чем отдельных
      // уведомлений (1.6.4, замечание 13.10.2026): на части прошивок (nubia
      // MyOS) она показывалась в шторке отдельной строкой рядом с
      // уведомлениями о каждом письме, повторяя их. Теперь в ней лишь те
      // письма, о которых отдельного уведомления нет.
      if (unread.length > singles.length) {
        final rest = unread.skip(singles.length).take(6).map((e) {
          final subj = e.subject.trim().isEmpty ? '—' : e.subject.trim();
          return NotificationText.summaryLine(PersonNames.short(e.from.displayName, email: e.from.email), subj);
        }).toList();
        await service.showSummaryNotification(
          accountId: account.id,
          accountEmail: active.length > 1 ? shortLabel : '',
          count: unread.length,
          lines: rest,
          quiet: accMode == AccountNotifyMode.quiet,
        );
      }
    } catch (e) {
      AppLogger.warning('Не удалось показать уведомление: $e');
    }
  }

  /// Локальный автоответчик (Out of Office) для аккаунтов БЕЗ серверного OOF —
  /// IMAP/EAS. Для EWS автоответ настраивается на сервере (auto_reply_screen),
  /// поэтому здесь такие аккаунты пропускаются. Отвечает ОДИН раз на отправителя
  /// в пределах окна отсутствия; служебные/автоматические письма и петли
  /// отсекаются. Вызывается только для реально НОВЫХ писем Входящих (иначе на
  /// первом синке разослали бы автоответ на весь бэклог).
  Future<void> _maybeAutoReply(
    AccountModel account, FolderModel folder, List<EmailModel> fresh,
  ) async {
    if (fresh.isEmpty) return;
    if (account.usesEws || account.isExchange) return; // серверный OOF
    if (folder.type != FolderType.inbox) return;

    final st = _ref.read(autoResponderProvider);
    if (!st.isActive) return;
    // Автоответчик настроен на конкретный аккаунт — не отвечаем от чужого имени.
    if (st.accountId != null && st.accountId != account.id) return;

    final responder = _ref.read(autoResponderProvider.notifier);
    // Свои домены — по всем адресам ящика (адрес входа, основной, алиасы).
    final myDomains = OwnAddresses.domains(account);

    // Отвечаем только на письма, пришедшие после включения автоответа и не
    // старше суток: «новые» для базы письма бывают и старыми (первая
    // синхронизация ящика, полная пересинхронизация, повторная загрузка
    // после автоочистки) — раньше автоответ уходил на весь этот бэклог.
    final since = DateTime.now().subtract(const Duration(days: 1));
    final from = st.startDate;
    for (final e in fresh) {
      if (e.isDraft) continue;
      if (e.receivedAt.isBefore(since)) continue;
      if (from != null && e.receivedAt.isBefore(from)) continue;
      final sender = e.from.email.trim();
      if (sender.isEmpty) continue;
      if (OwnAddresses.isMine(account, sender)) continue; // самому себе
      if (AutoResponderNotifier.isAutomatedSender(sender, e.subject)) continue;
      if (responder.hasRepliedTo(sender)) continue;

      final isInternal = myDomains.any((d) => sender.toLowerCase().endsWith('@$d'));
      final reply = responder.getAutoReplyFor(sender, isInternal: isInternal);
      if (reply == null || reply.trim().isEmpty) continue;

      // Дедуп ставим ДО отправки: при сбое лучше не отправить, чем зациклить.
      await responder.recordReplied(sender);
      try {
        final subj = SubjectPrefix.reply(e.subject);
        await _ref.read(offlineSendProvider).sendOrQueue(
              accountId: account.id,
              to: [e.from],
              subject: subj,
              bodyHtml: _plainToHtml(reply),
              inReplyTo: e.internetMessageId,
            );
        AppLogger.info('Автоответ отправлен: $sender');
      } catch (ex) {
        AppLogger.warning('Автоответ не отправлен ($sender): $ex');
      }
    }
  }

  /// Простой текст → безопасный HTML (экранирование + переводы строк).
  String _plainToHtml(String text) {
    final esc = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return '<div>$esc</div>';
  }

  // ════════════════════════ IMAP ════════════════════════

  /// Папки, которые пользователь выбрал для синхронизации («Настройки →
  /// Синхронизация папок»). Значение — из базы; у сервера isSynced лишь
  /// умолчание по типу папки. Прежде EWS и IMAP брали серверное умолчание:
  /// выключенные папки синхронизировались, включённые вручную — нет.
  Future<List<FolderModel>> _chosenFolders(AppDatabase db, String accountId, List<FolderModel> folders) async {
    final chosen = {
      for (final r in await (db.select(db.folders)..where((t) => t.accountId.equals(accountId))).get())
        r.id: r.isSynced,
    };
    return folders.where((f) => chosen[f.id] ?? f.isSynced).toList();
  }

  /// Одна папка IMAP: письма, удаления на сервере, уведомление о новых,
  /// автоответ. Общая для полной синхронизации и push (IDLE) — прежде push
  /// шёл через загрузку без уведомлений, и о новом письме телефон молчал.
  Future<int> _syncImapFolder(
      ImapService imap, AppDatabase db, AccountModel account, FolderModel folder, AppSettings settings) async {
    // Инкрементально по UID: новые письма, флаги и удаления во всём
    // загруженном диапазоне, догрузка истории (ENGINE_AUDIT P1-11). Раньше —
    // 50 последних писем на каждом проходе, остальное было не видно.
    final stateKey = 'imap_state:${account.id}:${folder.id}';
    final known = ImapFolderState.fromJson(_prefs.getString(stateKey));
    final cutoff = _cutoffFor(account.id);
    // История догружается, пока не дошли до начала папки или до среза
    // периода синхронизации. Период увеличили — догрузка возобновится.
    final days = account.syncDays;
    final historyDone = known != null && known.historyDone && known.syncDays == days;
    final delta = await imap.syncFolderDelta(account,
        folderId: folder.id, known: known, backfill: historyDone ? 0 : 200);
    String idOf(int uid) => '${folder.id}:$uid';
    int uidOf(String id) => int.tryParse(id.substring(id.lastIndexOf(':') + 1)) ?? -1;

    // Сменился UIDVALIDITY (папку пересоздали на сервере): старые id
    // указывают на другие письма — убираем их, кроме ждущих отправки правок.
    if (known != null && known.uidValidity != delta.state.uidValidity) {
      await (db.delete(db.emails)
            ..where((e) =>
                e.accountId.equals(account.id) &
                e.folderId.equals(folder.id) &
                e.isLocallyModified.equals(false)))
          .go();
      AppLogger.info('IMAP ${folder.displayName}: UIDVALIDITY изменился — папка загружается заново');
    }

    final fresh = <EmailModel>[];
    final added = delta.added.isEmpty
        ? 0
        : await _batchSaveEmails(db, account.id, folder, delta.added, collectNewInto: fresh);

    // Флаги (прочитано, флажок), изменённые на другом устройстве. Локальные
    // правки, ждущие отправки, не трогаем.
    if (delta.flags.isNotEmpty) {
      final groups = <(bool, bool), List<String>>{};
      for (final e in delta.flags.entries) {
        (groups[(e.value.read, e.value.flagged)] ??= []).add(idOf(e.key));
      }
      await db.transaction(() async {
        for (final g in groups.entries) {
          for (var i = 0; i < g.value.length; i += 500) {
            final part = g.value.sublist(i, i + 500 > g.value.length ? g.value.length : i + 500);
            await (db.update(db.emails)
                  ..where((e) =>
                      e.accountId.equals(account.id) &
                      e.id.isIn(part) &
                      e.isLocallyModified.equals(false) &
                      (e.isRead.equals(g.key.$1).not() | e.isFlagged.equals(g.key.$2).not())))
                .write(EmailsCompanion(isRead: Value(g.key.$1), isFlagged: Value(g.key.$2)));
          }
        }
      });
    }

    // Удалённые или перенесённые на сервере: в проверенном диапазоне UID
    // письма нет. Пустая папка на сервере — пусто и у нас.
    final from = delta.empty ? 0 : (delta.reset ? delta.state.minUid : delta.checkedFrom);
    final to = delta.empty ? 1 << 62 : (delta.reset ? delta.state.maxUid : delta.checkedTo);
    if (from != null && to != null) {
      // Только id: раньше здесь читались строки целиком — с текстами всех
      // писем папки, при каждой синхронизации папки.
      final local = await (db.selectOnly(db.emails)
            ..addColumns([db.emails.id])
            ..where(db.emails.accountId.equals(account.id) &
                db.emails.folderId.equals(folder.id) &
                db.emails.isLocallyModified.equals(false)))
          .map((r) => r.read(db.emails.id)!)
          .get();
      final gone = local.where((id) {
        final u = uidOf(id);
        return u >= from && u <= to && !delta.present.contains(u);
      }).toList();
      if (gone.isNotEmpty) {
        for (var i = 0; i < gone.length; i += 500) {
          final part = gone.sublist(i, i + 500 > gone.length ? gone.length : i + 500);
          await (db.delete(db.emails)..where((e) => e.accountId.equals(account.id) & e.id.isIn(part))).go();
        }
        AppLogger.info('IMAP ${folder.displayName}: удалено на сервере — ${gone.length}');
      }
    }

    final older = delta.backfilled;
    final done = historyDone ||
        delta.empty ||
        delta.complete ||
        (!delta.reset && older.isEmpty) ||
        (cutoff != null && older.isNotEmpty && older.every((e) => e.receivedAt.isBefore(cutoff)));
    await _prefs.setString(
        stateKey, jsonEncode(delta.state.copyWith(historyDone: done, syncDays: days).toJson()));
    // Уведомляем только о действительно новых: догруженная история и первая
    // загрузка уведомлений не дают.
    final newest = known?.maxUid ?? 1 << 62;
    final notify = fresh.where((e) => uidOf(e.id) > newest).toList();
    if (notify.isNotEmpty) await _notifyNewMail(account, folder, notify, notify.length, settings);
    if (fresh.isNotEmpty) await _maybeAutoReply(account, folder, notify);
    // Тексты новых писем «Входящих» — заранее: письмо открывается сразу,
    // без секунды ожидания сервера.
    if (notify.isNotEmpty) unawaited(_prefetchImapBodies(imap, db, account, folder, notify, settings));
    // История ещё не догружена — продолжаем сразу (порциями по 200), а не
    // при следующем синке через 15 минут.
    if (!done) {
      _scheduleContinuation(account, folder);
    } else {
      _continuations.remove('${account.id}|${folder.id}');
    }
    return added;
  }

  /// Предзагрузка текста (без вложений, BODY.PEEK — прочитанными не
  /// становятся) до 10 самых свежих новых писем «Входящих».
  Future<void> _prefetchImapBodies(ImapService imap, AppDatabase db, AccountModel account,
      FolderModel folder, List<EmailModel> fresh, AppSettings settings) async {
    if (folder.type != FolderType.inbox) return;
    if (settings.emailFetchMode == EmailFetchMode.headersOnly) return;
    final list = [...fresh]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    // Текст — в базу вместе с превью (у IMAP его в строке нет) и в поиск;
    // лента перечитывается один раз в конце, а не после каждого письма.
    // Раньше превью не появлялось, а текст не попадал в поисковый индекс.
    final got = <EmailModel, EmailModel>{};
    for (final e in list.take(10)) {
      try {
        final uid = int.tryParse(e.id.split(':').last) ?? 0;
        if (uid <= 0) continue;
        final full = await imap.getEmailDetail(account,
            folderId: folder.id, uid: uid, fetchMode: EmailFetchMode.noAttachments);
        if (full == null || ((full.bodyHtml ?? '').isEmpty && (full.bodyPlain ?? '').isEmpty)) continue;
        got[e] = full;
      } catch (err) {
        AppLogger.debug('IMAP предзагрузка текста: $err');
        break; // соединение занято или оборвалось — следующий синк повторит
      }
    }
    if (got.isEmpty) return;
    try {
      final htmls = <String, String>{
        for (final f in got.values)
          if ((f.bodyPlain ?? '').trim().isEmpty && (f.bodyHtml ?? '').isNotEmpty) f.id: f.bodyHtml!,
      };
      final fromHtml = htmls.isEmpty ? const <String, String>{} : await MailBodyProcessor.htmlToPlainAll(htmls);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = <String, Map<String, Object?>>{};
      final index = <({String emailId, String subject, String fromText, String body})>[];
      got.forEach((e, full) {
        final text = (full.bodyPlain ?? '').trim().isNotEmpty ? full.bodyPlain! : (fromHtml[e.id] ?? '');
        final preview = (e.bodyPreview ?? '').trim().isEmpty ? previewOf(text) : null;
        rows[e.id] = {
          'body_plain': full.bodyPlain,
          'body_html': full.bodyHtml,
          'loaded_level': AppDatabase.levelIndexed,
          'cached_at': now,
          if (full.attachments.isNotEmpty)
            'attachments_json': jsonEncode(full.attachments.map((a) => a.toMap()).toList()),
          if (preview != null) 'body_preview': preview,
        };
        index.add((
          emailId: e.id,
          subject: e.subject,
          fromText: '${e.from.displayName ?? ''} ${e.from.email}',
          body: cutSafe(text, 20000),
        ));
      });
      await db.storeBodiesQuietly(account.id, rows);
      try {
        await db.indexEmailFtsBatch(account.id, index);
      } catch (_) {/* FTS недоступен — поиск откатится на LIKE */}
      db.notifyUpdates({TableUpdate.onTable(db.emails, kind: UpdateKind.update)});
      AppLogger.info('IMAP ${folder.displayName}: заранее загружен текст ${got.length} писем');
    } catch (err) {
      AppLogger.debug('IMAP предзагрузка текста — запись: $err');
    }
  }

  Future<void> _syncImap(AccountModel account, AppSettings settings) async {
    final imap = _ref.read(imapServiceProvider);
    final db = _ref.read(databaseProvider);
    final total = Stopwatch()..start();

    final folders = await _batchSaveFolders(
        db,
        account.id,
        await _stage(account, 'список папок', () => imap.getFolders(account),
            limit: const Duration(minutes: 3)));
    final synced = await _chosenFolders(db, account.id, folders);
    AppLogger.info('IMAP sync: ${account.email} — папок ${folders.length}, синхронизируем ${synced.length}');

    int totalEmails = 0;
    final failedFolders = <String>[];
    for (final folder in synced) {
      try {
        totalEmails += await _stage(account, 'папка ${folder.displayName}',
            () => _syncImapFolder(imap, db, account, folder, settings));
      } catch (e) {
        failedFolders.add('${folder.displayName}: ${_shortError(e)}');
        AppLogger.error('IMAP sync папка "${folder.displayName}": $e');
        if (_isAuthError(e)) rethrow;
      }
    }
    if (failedFolders.isNotEmpty && failedFolders.length >= synced.length) {
      throw Exception(failedFolders.first);
    } else if (failedFolders.isNotEmpty) {
      _partialErrors[account.id] = failedFolders.join('; ');
    }
    // PIM по DAV (календарь/контакты): Google, Яндекс, Mail.ru, Yahoo, iCloud
    await _stage(account, 'календарь и контакты (DAV)', () => _syncDavPim(account, db));

    // Заметки в папке «Notes» (формат Apple Notes, 1.6.2) — раз в полчаса:
    // меняются редко, а папка читается целиком.
    await _stage(account, 'заметки', () => _syncImapNotes(account, db));
    AppLogger.info('IMAP sync завершён: ${account.email} — загружено $totalEmails писем'
        '${failedFolders.isNotEmpty ? ', сбой в папках: ${failedFolders.join(', ')}' : ''} '
        '${_stageSummary(account.id, total)}');

    final unread = await db.countUnread(account.id);
    unawaited(_ref.read(accountsProvider.notifier).updateUnreadCount(account.id, unread));
  }

  /// Синхронизация календаря/контактов по CalDAV/CardDAV (Google, Яндекс,
  /// Mail.ru, Yahoo), где PIM не приходит по IMAP.
  /// Фото профиля Google — портрет аккаунта. Раз в неделю; нужен доступ
  /// «profile» (если сервер входа его не запрашивает, фото просто нет).
  Future<void> _maybeGoogleProfilePhoto(AccountModel account, String authorization) async {
    if (account.type != AccountType.google) return;
    final key = 'acc_photo_checked:${account.id}';
    final last = DateTime.tryParse(_prefs.getString(key) ?? '');
    if (last != null && DateTime.now().difference(last).inDays < 7 && account.avatarUrl != null) return;
    try {
      final r = await http.get(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
          headers: {'Authorization': authorization}).timeout(const Duration(seconds: 15));
      await _prefs.setString(key, DateTime.now().toIso8601String());
      if (r.statusCode != 200) return;
      final pic = (jsonDecode(r.body) as Map<String, dynamic>)['picture'] as String?;
      if (pic != null && pic.startsWith('https://') && pic != account.avatarUrl) {
        await _ref.read(accountsProvider.notifier).setAccountPhoto(account.id, pic);
      }
    } catch (e) {
      AppLogger.debug('Фото профиля Google: $e');
    }
  }

  /// Календарь и контакты по DAV — не чаще раза в 15 минут: почта Gmail
  /// проверяется каждые несколько минут, а события и контакты меняются
  /// редко; раньше на каждую проверку почты шли и запросы CalDAV/CardDAV
  /// (журнал 11.10.2026: по 60 раз за день «без изменений»).
  final Map<String, DateTime> _lastDav = {};
  static const _davEvery = Duration(minutes: 15);

  Future<void> _syncDavPim(AccountModel account, AppDatabase db) async {
    if (!DavPimService.isSupported(account)) return;
    final lastDav = _lastDav[account.id];
    if (lastDav != null && DateTime.now().difference(lastDav) < _davEvery) return;
    _lastDav[account.id] = DateTime.now();
    final token = await DavCredentials.authorization(
      account,
      _ref.read(secureStorageProvider),
      proxy: OAuthProxyClient(_ref.read(secureStorageProvider)),
    );
    if (token == null) return;
    await _maybeGoogleProfilePhoto(account, token);

    final dav = DavPimService();
    // Календарь: события периода, серии развёрнуты во вхождения
    // («dav_<аккаунт>_<UID>#<день>»), напоминания и участники — с сервера.
    try {
      final hasLocalEvents = await (db.select(db.calendarEvents)
            ..where((t) => t.accountId.equals(account.id) & t.id.like('dav\\_%', escapeChar: '\\'))
            ..limit(1))
          .getSingleOrNull();
      final r = await dav.fetchEventsResult(account, token, allowSkip: hasLocalEvents != null);
      final events = r.events;
      if (events.isNotEmpty) {
        final keepReminders = await _existingReminders(db, account.id);
        await db.batch((batch) {
          for (final event in events) {
            batch.insert(db.calendarEvents,
              CalendarEventsCompanion.insert(
                id: event.id, accountId: event.accountId, title: event.title,
                description: Value(event.description), location: Value(event.location),
                onlineMeetingUrl: Value(event.onlineMeetingUrl),
                startTime: event.startTime, endTime: event.endTime,
                isAllDay: Value(event.isAllDay), organizerEmail: Value(event.organizerEmail),
                attendeesJson: Value(event.attendees.isEmpty
                    ? null
                    : jsonEncode([
                        for (final a in event.attendees)
                          {'email': a.email, 'displayName': a.displayName, 'isRequired': a.isRequired, if (a.response != 0) 'response': a.response},
                      ])),
                recurrence: Value(event.recurrence.index),
                remindersJson: Value(_remindersJson(event, keepReminders)),
                createdAt: event.createdAt,
              ), mode: InsertMode.insertOrReplace);
          }
        });
        AppLogger.info('CalDAV: ${events.length} событий (${account.email})');
      }
      // Удалённые на сервере события периода убираются — только если все
      // календари прочитались (иначе сбой сети стёр бы календарь).
      if (r.ok) {
        final fresh = {for (final e in events) e.id};
        final local = await (db.select(db.calendarEvents)
              ..where((t) =>
                  t.accountId.equals(account.id) &
                  t.id.like('dav\\_%', escapeChar: '\\') &
                  t.endTime.isBiggerOrEqualValue(r.from) &
                  t.startTime.isSmallerOrEqualValue(r.to)))
            .get();
        final gone = [for (final row in local) if (!fresh.contains(row.id)) row.id];
        for (var i = 0; i < gone.length; i += 400) {
          final part = gone.sublist(i, i + 400 > gone.length ? gone.length : i + 400);
          await (db.delete(db.calendarEvents)
                ..where((t) => t.accountId.equals(account.id) & t.id.isIn(part)))
              .go();
        }
        if (gone.isNotEmpty) AppLogger.info('CalDAV: удалено на сервере ${gone.length}');
      }
    } catch (e) {
      AppLogger.error('CalDAV sync: $e');
    }
    // Задачи: списки дел CalDAV (Яндекс, Mail.ru…). Локальные поля
    // (подзадачи, теги, связанное письмо, «важная») не затираются; правки
    // в офлайн-очереди — тоже.
    try {
      final r = await dav.fetchTasks(account, token);
      if (r.tasks.isNotEmpty || r.ok) {
        final pending = (await (db.select(db.syncQueue)
                  ..where((q) =>
                      q.accountId.equals(account.id) &
                      q.operationType.isIn(const ['upsert_task', 'delete_task'])))
                .get())
            .map((q) => q.targetId)
            .toSet();
        await db.batch((batch) {
          for (final t in r.tasks) {
            if (pending.contains(t.id)) continue;
            final row = TasksCompanion.insert(
              id: t.id,
              accountId: account.id,
              title: t.title,
              description: Value(t.description),
              status: Value(t.status.index),
              priority: Value(t.priority.index),
              createdAt: t.createdAt,
              dueDate: Value(t.dueDate),
              completedAt: Value(t.completedAt),
              reminderAt: Value(t.reminderAt),
            );
            batch.insert(db.tasks, row,
                onConflict: DoUpdate((_) => row.copyWith(createdAt: const Value.absent())));
          }
        });
        if (r.ok) {
          final fresh = {for (final t in r.tasks) t.id};
          final local = await (db.select(db.tasks)
                ..where((t) => t.accountId.equals(account.id) & t.id.like('davt\\_%', escapeChar: '\\')))
              .get();
          final gone = [for (final row in local) if (!fresh.contains(row.id) && !pending.contains(row.id)) row.id];
          if (gone.isNotEmpty) {
            await (db.delete(db.tasks)..where((t) => t.accountId.equals(account.id) & t.id.isIn(gone))).go();
          }
        }
        if (r.tasks.isNotEmpty) AppLogger.info('CalDAV: задач ${r.tasks.length} (${account.email})');
      }
    } catch (e) {
      AppLogger.error('CalDAV tasks sync: $e');
    }
    // Контакты
    try {
      // Пропуск выгрузки по метке изменений — только если контакты аккаунта
      // уже есть локально (после очистки данных книга выгрузится заново).
      final hasLocal = await (db.select(db.contacts)
            ..where((t) => t.accountId.equals(account.id) & t.id.like('dav\\_%', escapeChar: '\\'))
            ..limit(1))
          .getSingleOrNull();
      // У Яндекса пароль приложения «Контакты» свой (1.7.2+110).
      final contactsToken = await DavCredentials.authorization(
            account,
            _ref.read(secureStorageProvider),
            proxy: OAuthProxyClient(_ref.read(secureStorageProvider)),
            contacts: true,
          ) ??
          token;
      final cr = await dav.fetchContactsResult(account, contactsToken, allowSkip: hasLocal != null);
      final contacts = cr.contacts;
      // Правки контактов, ещё не ушедшие на сервер, не затираются.
      final pendingContacts = (await (db.select(db.syncQueue)
                ..where((q) => q.accountId.equals(account.id) & q.operationType.equals('upsert_contact')))
              .get())
          .map((q) => q.targetId)
          .toSet();
      if (contacts.isNotEmpty) {
        await db.batch((batch) {
          for (final c in contacts) {
            if (pendingContacts.contains(c.id)) continue;
            // Локальные поля (избранное, VIP) не сбрасываются.
            final row = ContactsCompanion.insert(
              id: c.id, accountId: Value(c.accountId), email: c.email,
              displayName: c.displayName, firstName: Value(c.firstName),
              lastName: Value(c.lastName), middleName: Value(c.middleName), company: Value(c.company),
              jobTitle: Value(c.jobTitle), phoneWork: Value(c.phoneWork),
              phoneMobile: Value(c.phoneMobile), source: Value(c.source.index),
              // Нет фото в ответе сервера — фото из адресной книги организации
              // (записанное отдельно) не стирается (1.5.12).
              avatarUrl: (c.avatarUrl ?? '').isEmpty ? const Value.absent() : Value(c.avatarUrl),
            );
            batch.insert(db.contacts, row, onConflict: DoUpdate((_) => row));
          }
        });
        // Сколько пришло с фото и в каком виде — чтобы по журналу было видно,
        // теряются ли фото на сервере, при разборе или при показе.
        final withPhoto = contacts.where((c) => (c.avatarUrl ?? '').isNotEmpty).toList();
        final asData = withPhoto.where((c) => c.avatarUrl!.startsWith('data:')).length;
        AppLogger.info('CardDAV: ${contacts.length} контактов (${account.email}), с фото ${withPhoto.length}'
            '${withPhoto.isEmpty ? '' : ' (встроенных $asData, ссылкой ${withPhoto.length - asData})'}');
      }
      // Все адресные книги прочитаны — контакты, удалённые на сервере,
      // убираем (если хоть одна книга не прочиталась, её контакты стёрлись бы).
      if (cr.ok) {
        final fresh = {for (final c in contacts) c.id};
        final local = await (db.select(db.contacts)
              ..where((t) => t.accountId.equals(account.id) & t.id.like('dav\\_%', escapeChar: '\\')))
            .get();
        final gone = [for (final r in local) if (!fresh.contains(r.id) && !pendingContacts.contains(r.id)) r.id];
        for (var i = 0; i < gone.length; i += 400) {
          final part = gone.sublist(i, i + 400 > gone.length ? gone.length : i + 400);
          await (db.delete(db.contacts)
                ..where((t) => t.accountId.equals(account.id) & t.id.isIn(part)))
              .go();
        }
      }
    } catch (e) {
      AppLogger.error('CardDAV sync: $e');
    }
  }

  /// Напоминания встреч, уже сохранённые на устройстве (id → JSON).
  Future<Map<String, String>> _existingReminders(AppDatabase db, String accountId) async {
    final rows = await (db.select(db.calendarEvents)
          ..where((t) => t.accountId.equals(accountId) & t.remindersJson.isNotNull()))
        .get();
    return {for (final r in rows) r.id: r.remindersJson!};
  }

  /// Напоминания встречи с сервера (формат планировщика: [{"minutesBefore": N}]).
  /// Сервер не прислал — оставляем те, что были на устройстве: прежде поле не
  /// заполнялось вовсе, и встречи с сервера приходили без напоминаний ОС, а
  /// заданные на телефоне стирались следующей синхронизацией. С 1.7.2+110
  /// напоминаний несколько: Exchange хранит одно, остальные — на телефоне
  /// с отметкой "local" и при синхронизации сохраняются ([EventReminders.merge]).
  String? _remindersJson(CalendarEventModel e, Map<String, String> existing) =>
      EventReminders.merge([for (final r in e.reminders) r.minutesBefore], existing[e.id]);

  Future<void> _syncCalendar(AccountModel account, EwsService ews, AppDatabase db) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 7));
      final to = now.add(const Duration(days: AppConstants.cachedCalendarDays));
      final events = await ews.getCalendarEvents(account, startDate: from, endDate: to);

      // Встречи, отменённые или перенесённые за пределы окна в Outlook,
      // раньше оставались в календаре навсегда. Удаляем серверные события
      // окна, которых больше нет в ответе. Локальные (ещё не выгруженные,
      // с короткими id вида uuid) не трогаем: ItemId EWS — длинная base64-строка.
      // Пустой ответ (ошибка разбора, лимит сервера) — повод НЕ чистить.
      final fresh = events.map((e) => e.id).toSet();
      if (fresh.isNotEmpty) {
        await (db.delete(db.calendarEvents)
              ..where((e) =>
                  e.accountId.equals(account.id) &
                  e.startTime.isBiggerOrEqualValue(from) &
                  e.startTime.isSmallerOrEqualValue(to) &
                  e.id.length.isBiggerThanValue(60) &
                  e.id.isNotIn(fresh)))
            .go();
      }

      final keepReminders = await _existingReminders(db, account.id);
      await db.batch((batch) {
        for (final event in events) {
          batch.insert(
            db.calendarEvents,
            CalendarEventsCompanion.insert(
              id: event.id,
              accountId: event.accountId,
              title: event.title,
              description: Value(event.description),
              location: Value(event.location),
              onlineMeetingUrl: Value(event.onlineMeetingUrl),
              startTime: event.startTime,
              endTime: event.endTime,
              isAllDay: Value(event.isAllDay),
              organizerEmail: Value(event.organizerEmail),
              // Участники EWS разбирались, но не сохранялись: у встреч
              // Exchange (EWS) в карточке не было ни участников, ни ответов.
              attendeesJson: Value(event.attendees.isEmpty
                  ? null
                  : jsonEncode([
                      for (final a in event.attendees)
                        {'email': a.email, 'displayName': a.displayName, 'isRequired': a.isRequired, if (a.response != 0) 'response': a.response},
                    ])),
              recurrence: Value(event.recurrence.index),
              priority: Value(event.priority.index),
              showAs: Value(event.showAs.index),
              colorValue: Value(event.colorValue),
              isPrivate: Value(event.isPrivate),
              remindersJson: Value(_remindersJson(event, keepReminders)),
              createdAt: event.createdAt,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    } catch (e) {
      AppLogger.error('Calendar sync: $e');
    }
  }

  /// Синхронизация контактов (EWS). Личные контакты из папки Contacts.
  Future<void> _syncContacts(AccountModel account, EwsService ews, AppDatabase db) async {
    try {
      final contacts = await ews.getContacts(account, maxResults: 500);
      if (contacts.isEmpty) return;
      // Строки старого формата id ('ews_<хеш>') заменяются строками с ItemId,
      // а контакты, удалённые на сервере (длинный ItemId, которого больше нет
      // в ответе), убираются. Локальные ('local_…') не трогаем.
      final fresh = contacts.map((c) => c.id).toSet();
      await (db.delete(db.contacts)
            ..where((c) =>
                c.accountId.equals(account.id) &
                (c.id.like(r'ews\_%', escapeChar: '\\') |
                    (c.id.length.isBiggerThanValue(60) & c.id.isNotIn(fresh)))))
          .go();
      // Сверенные с адресной книгой коллеги (1.8.0+118) — как у ActiveSync.
      final dirs = await _dirOrgs(db, account.id);
      await db.batch((batch) {
        for (final c in contacts) {
          final known = dirs[c.id];
          final dir = known != null && known.matches(c.email) ? known : null;
          String? org(String field, String? server) => dir == null ? server : dir.pick(field, server);
          final reset = known != null && dir == null;
          final row = ContactsCompanion.insert(
              id: c.id,
              accountId: Value(c.accountId),
              email: c.email,
              displayName: c.displayName,
              firstName: Value(c.firstName),
              lastName: Value(c.lastName),
              middleName: Value(c.middleName),
              jobTitle: Value(org('jobTitle', c.jobTitle)),
              department: Value(org('department', c.department)),
              company: Value(org('company', c.company)),
              phoneWork: Value(org('phoneWork', c.phoneWork)),
              phoneMobile: Value(c.phoneMobile),
              office: Value(org('office', c.office)),
              manager: Value(org('manager', c.manager)),
              dirCheckedAt: reset ? const Value(null) : const Value.absent(),
              dirOrg: reset ? const Value(null) : const Value.absent(),
              city: Value(c.city),
              source: Value(c.source.index),
              // Нет фото в ответе сервера — фото из адресной книги организации
              // (записанное отдельно) не стирается (1.5.12).
              avatarUrl: (c.avatarUrl ?? '').isEmpty ? const Value.absent() : Value(c.avatarUrl),
          );
          // Локальные поля (избранное, VIP) не сбрасываются.
          batch.insert(db.contacts, row, onConflict: DoUpdate((_) => row));
        }
      });
      AppLogger.info('Contacts sync: ${contacts.length} (${account.email})');
      unawaited(_refreshColleagues(account));
    } catch (e) {
      AppLogger.error('Contacts sync: $e');
    }
  }

  /// Задачи (EWS). Полный список папки «Задачи»: новые и изменённые
  /// обновляются (локальные поля — исполнитель, теги, подзадачи — остаются),
  /// удалённые на сервере убираются. Правки, ещё не ушедшие на сервер
  /// (в офлайн-очереди), не затираются.
  Future<void> _syncEwsTasks(AccountModel account, EwsService ews, AppDatabase db) async {
    try {
      final tasks = await ews.getTasks(account);
      final pending = (await (db.select(db.syncQueue)
                ..where((q) => q.accountId.equals(account.id) & q.operationType.equals('upsert_task')))
              .get())
          .map((q) => q.targetId)
          .toSet();
      await db.batch((batch) {
        for (final t in tasks) {
          if (pending.contains(t.id)) continue;
          final row = TasksCompanion.insert(
            id: t.id,
            accountId: account.id,
            title: t.title,
            description: Value(t.description),
            status: Value(t.status.index),
            priority: Value(t.priority.index),
            createdAt: t.createdAt,
            dueDate: Value(t.dueDate),
            completedAt: Value(t.completedAt),
          );
          batch.insert(db.tasks, row,
              onConflict: DoUpdate((_) => row.copyWith(createdAt: const Value.absent())));
        }
      });
      if (tasks.length < 300) {
        final fresh = {for (final t in tasks) t.id};
        final local = await (db.select(db.tasks)..where((t) => t.accountId.equals(account.id))).get();
        final gone = [
          for (final r in local)
            if (r.id.length > 60 && !r.id.startsWith('eas_') && !fresh.contains(r.id) && !pending.contains(r.id))
              r.id,
        ];
        for (var i = 0; i < gone.length; i += 400) {
          final part = gone.sublist(i, i + 400 > gone.length ? gone.length : i + 400);
          await (db.delete(db.tasks)..where((t) => t.accountId.equals(account.id) & t.id.isIn(part))).go();
        }
      }
      AppLogger.info('EWS Tasks: ${tasks.length} (${account.email})');
    } catch (e) {
      AppLogger.error('EWS tasks sync: $e');
    }
  }

  /// Когда заметки IMAP ящика читались в последний раз (в этом процессе).
  final Map<String, DateTime> _imapNotesAt = {};

  /// Заметки IMAP: сначала выгрузка своих правок, затем папка «Notes»
  /// целиком. Правки, ещё не ушедшие на сервер, серверной версией не
  /// затираются; заметки, удалённые на сервере, убираются.
  Future<void> _syncImapNotes(AccountModel account, AppDatabase db, {bool force = false}) async {
    final last = _imapNotesAt[account.id];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    _imapNotesAt[account.id] = DateTime.now();
    try {
      try {
        await _ref.read(mailEngineServiceProvider).pushPendingNotes(account);
      } catch (e) {
        AppLogger.warning('IMAP notes push: $e');
      }
      final notes = await _ref.read(imapServiceProvider).getImapNotes(account);
      if (notes == null) return; // папки «Notes» нет
      final pending = (await (db.select(db.notes)
                ..where((n) => n.accountId.equals(account.id) & n.isLocallyModified.equals(true)))
              .get())
          .map((n) => n.serverId)
          .whereType<String>()
          .toSet();
      await db.batch((batch) {
        for (final n in notes) {
          if (pending.contains(n.uuid)) continue;
          final at = n.modified.toUtc();
          batch.insert(
            db.notes,
            NotesCompanion.insert(
              id: imapNoteRowId(account.id, n.uuid),
              accountId: Value(account.id),
              title: Value(n.title),
              body: Value(n.body),
              serverId: Value(n.uuid),
              createdAt: at,
              modifiedAt: at,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
      if (notes.length < 500) {
        final fresh = {for (final n in notes) n.uuid};
        await (db.delete(db.notes)
              ..where((n) =>
                  n.accountId.equals(account.id) &
                  n.id.like('imap%') &
                  n.serverId.isNotIn(fresh) &
                  n.isLocallyModified.equals(false)))
            .go();
      }
      AppLogger.info('IMAP notes: ${notes.length} (${account.email})');
    } catch (e) {
      AppLogger.warning('IMAP notes sync: $e');
    }
  }

  /// Синхронизация заметок (EWS). Папка Notes (IPM.StickyNote).
  Future<void> _syncNotes(AccountModel account, EwsService ews, AppDatabase db) async {
    try {
      try {
        await _ref.read(mailEngineServiceProvider).pushPendingNotes(account);
      } catch (e) {
        AppLogger.warning('EWS notes push: $e');
      }
      final notes = await ews.getNotes(account, maxResults: 500);
      if (notes.isEmpty) return;
      final now = DateTime.now().toUtc();
      // Правки, ещё не ушедшие на сервер, серверной версией не затираем.
      final pending = (await (db.select(db.notes)
                ..where((n) => n.accountId.equals(account.id) & n.isLocallyModified.equals(true)))
              .get())
          .map((n) => n.serverId)
          .whereType<String>()
          .toSet();
      await db.batch((batch) {
        for (final n in notes) {
          final serverId = n['serverId'] ?? '';
          if (serverId.isEmpty || pending.contains(serverId)) continue;
          batch.insert(
            db.notes,
            NotesCompanion.insert(
              id: noteRowId(eas: false, accountId: account.id, serverId: serverId),
              accountId: Value(account.id),
              title: Value(n['title'] ?? ''),
              body: Value(n['body'] ?? ''),
              serverId: Value(serverId),
              createdAt: now,
              modifiedAt: now,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
      // Заметки, удалённые на сервере (в полном списке их нет), — убираем;
      // несохранённые правки не трогаем.
      if (notes.length < 500) {
        final fresh = {for (final n in notes) n['serverId'] ?? ''};
        await (db.delete(db.notes)
              ..where((n) =>
                  n.accountId.equals(account.id) &
                  n.serverId.isNotNull() &
                  n.serverId.isNotIn(fresh) &
                  n.isLocallyModified.equals(false)))
            .go();
      }
      AppLogger.info('Notes sync: ${notes.length} (${account.email})');
    } catch (e) {
      AppLogger.error('Notes sync: $e');
    }
  }

  // ════════════════════════ BATCH DB ════════════════════════

  /// Batch сохранение папок
  /// Обновить список папок с сервера в локальную БД (после создания/удаления
  /// папки, чтобы подтянуть актуальные server-id).
  Future<void> refreshFolders(AccountModel account) async {
    final db = _ref.read(databaseProvider);
    // Папки берём тем же транспортом, что и синхронизация: для EWS и IMAP у
    // них свои идентификаторы. Раньше всегда шёл запрос через движок, и у
    // EWS-аккаунта список папок подменялся пятью «стандартными» с чужими id.
    final List<FolderModel> folders;
    if (account.usesEas) {
      folders = await _ref.read(mailEngineServiceProvider).getFolders(account);
    } else if (account.usesEws || account.isExchange) {
      folders = await _ref.read(ewsServiceProvider).getFolders(account);
    } else {
      folders = await _ref.read(imapServiceProvider).getFolders(account);
    }
    if (folders.isEmpty) return; // нет связи — не затираем известный список
    await _batchSaveFolders(db, account.id, folders);
  }

  /// Имя и фото владельца из адресной книги (вынесено из _syncEas, 1.6.12:
  /// этап с пределом времени — в фоновой задаче после «подключено» он мог
  /// держать синхронизацию до обрыва WorkManager).
  Future<void> _refreshOwnerCard(MailEngineService engine, AppDatabase db, AccountModel account) async {
    final fio = await engine.refreshSelfCard(account).timeout(const Duration(seconds: 45));
    // Фото владельца из адресной книги организации — портрет аккаунта.
    final photo = engine.cachedSelfCard(account.id)['photo'];
    // Фото, выбранное вручную, адресная книга не заменяет.
    final manual = (_ref.read(sharedPrefsProvider).getStringList('account_photo_manual') ?? const [])
        .contains(account.id);
    if (!manual && photo != null && photo != account.avatarUrl) {
      await _ref.read(accountsProvider.notifier).setAccountPhoto(account.id, photo);
    }
    final login = account.email.split('@').first.toLowerCase();
    final current = account.displayName.trim();
    final looksLikeLogin = current.isEmpty ||
        current.toLowerCase() == login ||
        current.toLowerCase() == account.email.toLowerCase();
    if (fio != null && fio.trim().isNotEmpty && looksLikeLogin && fio != current) {
      await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
          .write(AccountsCompanion(displayName: Value(fio.trim())));
      await _ref.read(accountsProvider.notifier).reload();
      AppLogger.info('Имя ящика ${account.email} обновлено из адресной книги');
    }
  }

  /// Папки, которых больше нет на сервере ActiveSync (удалены в Outlook), —
  /// убрать с телефона вместе с письмами (1.6.12). Раньше список папок только
  /// пополнялся: удалённая папка оставалась в меню навсегда, а её
  /// синхронизация каждый проход получала ошибку. Только папки с
  /// идентификатором сервера и только если список с сервера правдоподобен.
  Future<void> _pruneVanishedEasFolders(AppDatabase db, AccountModel account, List<FolderModel> server) async {
    if (server.length < 3) return; // обрывок списка — не трогаем ничего
    final ids = {for (final f in server) f.id};
    final local = await (db.select(db.folders)..where((f) => f.accountId.equals(account.id))).get();
    final gone = [
      for (final f in local)
        if (!ids.contains(f.id) && f.id != MailEngineService.easSearchFolderId && RegExp(r'^[0-9:]+$').hasMatch(f.id)) f,
    ];
    if (gone.isEmpty) return;
    final goneIds = [for (final f in gone) f.id];
    await db.transaction(() async {
      await (db.delete(db.emails)..where((e) => e.accountId.equals(account.id) & e.folderId.isIn(goneIds))).go();
      await (db.delete(db.folders)..where((f) => f.accountId.equals(account.id) & f.id.isIn(goneIds))).go();
    });
    for (final f in gone) {
      AppLogger.info('Папки «${f.displayName}» на сервере больше нет — убрана с телефона');
    }
  }

  /// Сохранить список папок с сервера. Возвращает тот же список с типами
  /// «Архив» и «Спам» (1.7.2+106, [SpecialFolders]): ActiveSync их не
  /// различает, и вызывающий проход синхронизации должен видеть те же типы,
  /// что в базе (спам — без уведомлений).
  Future<List<FolderModel>> _batchSaveFolders(AppDatabase db, String accountId, List<FolderModel> serverFolders) async {
    final folders = SpecialFolders.apply(serverFolders,
        archiveId: SpecialFolders.chosen(_prefs, accountId, SpecialKind.archive),
        junkId: SpecialFolders.chosen(_prefs, accountId, SpecialKind.junk));
    // Выбор пользователя «синхронизировать эту папку» НЕ должен затираться при
    // обновлении списка с сервера: insertOrReplace ниже перезаписывает строку
    // целиком, а серверные источники ставят isSynced по типу папки (IMAP — всегда
    // true). Поэтому для уже известных папок сохраняем текущее значение, а
    // серверное умолчание применяем только к новым.
    final known = await (db.select(db.folders)
          ..where((t) => t.accountId.equals(accountId)))
        .get();
    final knownSync = {for (final k in known) k.id: k.isSynced};
    // То же для избранного и ручного порядка: insertOrReplace сбрасывал их
    // в умолчание при каждой синхронизации — звёздочка папки «не работала».
    final knownRow = {for (final k in known) k.id: k};
    // В журнал — только когда тип особой папки меняется (первое
    // распознавание, ручной выбор), а не при каждом проходе.
    final retyped = [
      for (final f in folders)
        if (knownRow[f.id] case final k? when k.type != f.type.index &&
            (f.type == FolderType.archive || f.type == FolderType.junk ||
                k.type == FolderType.archive.index || k.type == FolderType.junk.index))
          '«${f.displayName}» → ${f.type.name}',
    ];
    if (retyped.isNotEmpty) AppLogger.info('Папки «Архив» и «Спам»: ${retyped.join(', ')}');

    await db.batch((batch) {
      for (final f in folders) {
        batch.insert(
          db.folders,
          FoldersCompanion.insert(
            id: f.id,
            accountId: f.accountId,
            parentId: Value(f.parentId),
            displayName: f.displayName,
            type: Value(f.type.index),
            serverPath: Value(f.serverPath),
            unreadCount: Value(f.unreadCount),
            totalCount: Value(f.totalCount),
            showInUnified: Value(f.showInUnified),
            isSynced: Value(knownSync[f.id] ?? f.isSynced),
            isFavorite: Value(knownRow[f.id]?.isFavorite ?? f.isFavorite),
            sortOrder: Value(knownRow[f.id]?.sortOrder ?? f.sortOrder),
            iconName: Value(knownRow[f.id]?.iconName ?? f.iconName),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    return folders;
  }

  /// Предзагрузка вложений в кэш — только в режиме «полное письмо с вложениями».
  ///
  /// До этого настройка `EmailFetchMode` была ПУСТЫШКОЙ: значение доходило до
  /// ews.getEmails параметром и там не использовалось вообще, а IMAP её и не
  /// принимал. Пользователь выбирал «с вложениями», а вложения всё равно
  /// качались только по нажатию. Теперь режим full означает конкретное:
  /// после синхронизации кладём вложения новых писем в кэш, чтобы открывались
  /// мгновенно и работали офлайн.
  ///
  /// Осторожность по трафику и месту:
  ///  · по умолчанию только по Wi-Fi (настройка attachmentsWifiOnly);
  ///  · пропускаем крупные файлы — иначе один архив на 200 МБ вымоет весь кэш;
  ///  · пропускаем встроенные (inline) — они уже в теле письма;
  ///  · ошибки не мешают синхронизации.
  Future<void> _prefetchAttachments(
    AccountModel account,
    List<EmailModel> emails,
    AppSettings settings,
  ) async {
    if (settings.emailFetchMode != EmailFetchMode.full) return;
    if (emails.isEmpty) return;

    final net = _ref.read(connectivityServiceProvider);
    if (!net.isConnected) return;
    if (settings.attachmentsWifiOnly && !net.isWifi) {
      AppLogger.info('Предзагрузка вложений пропущена: не Wi-Fi');
      return;
    }

    const maxEach = 10 * 1024 * 1024; // 10 МБ на файл — разумный предел
    final cache = _ref.read(attachmentCacheProvider);
    var done = 0;

    for (final email in emails) {
      for (final att in email.attachments) {
        if (att.isInline) continue;
        if (att.size > maxEach) continue;
        final key = MailEngineService.attachmentCacheKey(account.id, email.id, att.id);
        if (await cache.get(key) != null) continue; // уже есть

        try {
          // Фасад сам выбирает протокол (EAS/EWS/IMAP). Раньше ветка
          // выбиралась по isExchange, и для ActiveSync предзагрузка шла в
          // IMAP-ветку и всегда падала.
          final bytes = await _ref
              .read(mailEngineServiceProvider)
              .getAttachmentBytes(account, att.id, emailId: email.id);
          await cache.put(key, att.name, bytes);
          done++;
        } catch (e) {
          AppLogger.debug('Предзагрузка ${att.name}: $e');
        }
      }
    }
    if (done > 0) AppLogger.info('Предзагружено вложений: $done');
  }

  /// Delta-синхронизация EWS. Экземпляр один на сервис: он без состояния,
  /// состояние (syncState) храним в prefs по паре «аккаунт+папка».
  late final EwsDeltaSync _ewsDelta = EwsDeltaSync(_ref.read(ewsServiceProvider));

  /// Хранилище syncState. Берём лениво через провайдер: у SyncService в
  /// конструкторе только Ref.
  SharedPreferences get _prefs => _ref.read(sharedPrefsProvider);

  /// Работы после синхронизации (черновики, напоминания, «нет ответа»,
  /// виджет), которые идут без ожидания.
  Future<void>? _afterSync;

  /// Дождаться работ после синхронизации (фоновая задача — перед выходом).
  Future<void> settle({Duration timeout = const Duration(seconds: 40)}) async {
    final f = _afterSync;
    if (f == null) return;
    try {
      await f.timeout(timeout);
    } catch (_) {}
  }

  String _ewsDeltaKey(String accountId, String folderId) =>
      'ews_delta_${accountId}_$folderId';

  /// Самая ранняя дата писем, которые хранит аккаунт; null — весь период.
  DateTime? _cutoffFor(String accountId) {
    final a = _ref.read(accountsProvider).where((x) => x.id == accountId).firstOrNull;
    if (a == null || a.syncDays <= 0) return null;
    return DateTime.now().subtract(Duration(days: a.syncDays));
  }

  /// Сервер прислал текст письма (а не только заголовки и превью).
  static bool _hasText(EmailModel e) => (e.bodyPlain ?? '').isNotEmpty || (e.bodyHtml ?? '').isNotEmpty;

  Future<bool> _folderHasEmails(AppDatabase db, String accountId, String folderId) async {
    final r = await db.customSelect(
      'SELECT 1 FROM emails WHERE account_id = ? AND folder_id = ? LIMIT 1',
      variables: [Variable.withString(accountId), Variable.withString(folderId)],
    ).get();
    return r.isNotEmpty;
  }

  /// Отпечаток письма для сопоставления после смены ServerId.
  static String emailFingerprint(String folderId, String fromEmail, String subject, DateTime receivedAt, int? size) =>
      '$folderId|${fromEmail.trim().toLowerCase()}|${subject.trim()}|'
      '${receivedAt.millisecondsSinceEpoch ~/ 1000}|${size ?? ''}';

  /// Прежние строки писем, пришедших с новыми ServerId, получают новый id.
  /// Возвращает новые id сопоставленных писем.
  Future<List<String>> _rekeyEasCopies(
      AppDatabase db, String accountId, List<EmailModel> fresh, Set<String> batchIds) async {
    final t = db.emails;
    final folders = {for (final e in fresh) e.folderId};
    final times = {for (final e in fresh) e.receivedAt};
    final q = db.selectOnly(t)
      ..addColumns([t.id, t.folderId, t.fromEmail, t.subject, t.receivedAt, t.size])
      ..where(t.accountId.equals(accountId) & t.folderId.isIn(folders) & t.receivedAt.isIn(times));
    final byFp = <String, List<String>>{};
    for (final r in await q.get()) {
      final id = r.read(t.id)!;
      if (batchIds.contains(id)) continue;
      final fp = emailFingerprint(
          r.read(t.folderId)!, r.read(t.fromEmail)!, r.read(t.subject)!, r.read(t.receivedAt)!, r.read(t.size));
      (byFp[fp] ??= []).add(id);
    }
    if (byFp.isEmpty) return const [];
    final out = <String>[];
    await db.transaction(() async {
      for (final e in fresh) {
        final list = byFp[emailFingerprint(e.folderId, e.from.email, e.subject, e.receivedAt, e.size)];
        if (list == null || list.isEmpty) continue;
        final old = list.removeAt(0);
        await db.customUpdate(
          'UPDATE emails SET id = ? WHERE account_id = ? AND id = ?',
          variables: [Variable.withString(e.id), Variable.withString(accountId), Variable.withString(old)],
          updates: {db.emails},
        );
        out.add(e.id);
      }
    });
    if (out.isNotEmpty) {
      AppLogger.info('ActiveSync: письма с новыми ServerId сопоставлены с прежними — ${out.length}');
    }
    return out;
  }

  Future<int> _batchSaveEmails(
    AppDatabase db,
    String accountId,
    FolderModel folder,
    List<EmailModel> emails, {
    List<EmailModel>? collectNewInto,
  }) async {
    // Период синхронизации аккаунта (месяц / полгода / год / всё): письма
    // старше среза не сохраняем. ActiveSync для окон больше месяца отдаёт
    // всё, IMAP догружает историю — срез здесь общий для всех протоколов.
    final cutoff = _cutoffFor(accountId);
    if (cutoff != null) {
      emails = emails.where((e) => !e.receivedAt.isBefore(cutoff)).toList();
    }
    if (emails.isEmpty) return 0;
    // Беседы IMAP — по ссылкам на письма и по теме с собеседником (1.8.13):
    // ответ из Outlook, где в References только родитель, уходил в
    // отдельную беседу.
    final owner = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (owner != null && ThreadLinker.appliesTo(owner)) {
      emails = await ThreadLinker.link(db, owner, emails);
    }

    // Существующие письма этой папки — целиком (нужны их локальные поля для
    // слияния, а не только id). Раньше брались лишь id, и запись шла через
    // insertOrReplace: SQLite удалял строку и вставлял заново, обнуляя ВСЕ
    // столбцы, которых нет в companion — снуз (remindAt), теги, isReplied/
    // isForwarded, classification, extractedDeadline, loadedLevel. Плюс сервер
    // затирал офлайн-правки пользователя (побеждала последняя запись). Теперь:
    // новое письмо — insert; существующее — update только серверных полей, с
    // разрешением конфликтов и сохранением локальных.
    // По id (а не по папке): если письмо локально перемещено в другую папку,
    // сервер старой папки ещё вернёт его — при выборке «по папке» мы бы не нашли
    // строку и вставили дубль в старую папку, откатив перемещение. Поиск по id
    // находит её, и conflict_resolver сохраняет локальную папку (merge → local).
    final ids = emails.map((e) => e.id).toList();
    // Строки без тел: для слияния нужны флаги, папка, теги и отметки, а
    // тексты всех писем пакета читались из базы на каждую синхронизацию.
    // Обратно эти строки целиком не пишутся — только update полей ниже.
    final existing =
        await db.emailsLight((e) => e.accountId.equals(accountId) & e.id.isIn(ids)).get();
    final existingById = {for (final e in existing) e.id: e};
    final rekeyed = <String>{};
    // ActiveSync: после сброса синхронизации на сервере (Status 3/9, смена
    // версии протокола) Exchange присылает те же письма заново с новыми
    // ServerId. Строка с прежним id находится по «отпечатку» (папка,
    // отправитель, тема, время получения, размер) и получает новый id:
    // остаются текст, «Позже», «На контроле», теги. Раньше появлялась
    // вторая строка — письма в ленте задваивались (замечание 13.10.2026).
    if (_ref.read(accountsProvider).any((a) => a.id == accountId && a.usesEas)) {
      final fresh = [for (final e in emails) if (!existingById.containsKey(e.id)) e];
      if (fresh.isNotEmpty) {
        final moved = await _rekeyEasCopies(db, accountId, fresh, ids.toSet());
        if (moved.isNotEmpty) {
          rekeyed.addAll(moved);
          for (final r in await db.emailsLight((e) => e.accountId.equals(accountId) & e.id.isIn(moved)).get()) {
            existingById[r.id] = r;
          }
        }
      }
    }
    // Письма, правка которых ещё ждёт отправки на сервер в очереди: для них
    // побеждает локальное состояние (пользователь уже сделал действие).
    // Без ожидающей операции побеждает сервер. Раньше «слияние» делало
    // local || server: «отметить непрочитанным» и «снять флаг», сделанные
    // офлайн, при синке тихо отменялись сервером.
    final pendingOps = (await (db.select(db.syncQueue)
              ..where((q) => q.accountId.equals(accountId) & q.targetId.isIn(ids)))
            .get())
        .map((q) => q.targetId)
        .toSet();

    final resolver = _ref.read(conflictResolverProvider);
    int newCount = 0;
    final newEmails = <EmailModel>[];

    await db.batch((batch) {
      for (final email in emails) {
        final prevRow = existingById[email.id];

        if (prevRow == null) {
          // ── Новое письмо: обычная вставка ──
          newCount++;
          collectNewInto?.add(email);
          newEmails.add(email);
          batch.insert(
            db.emails,
            EmailsCompanion.insert(
              id: email.id,
              accountId: accountId,
              folderId: email.folderId,
              folderName: Value(folder.displayName),
              conversationId: Value(email.conversationId),
              parentId: Value(email.parentId),
              internetMessageId: Value(email.internetMessageId),
              referencesStr: Value(email.references?.join(' ')),
              fromEmail: email.from.email,
              fromName: Value(email.from.displayName),
              toRecipients: jsonEncode(email.to.map((a) => a.toMap()).toList()),
              ccJson: Value(email.cc.isNotEmpty ? jsonEncode(email.cc.map((a) => a.toMap()).toList()) : null),
              replyToEmail: Value(
                  email.replyTo.isNotEmpty ? jsonEncode(email.replyTo.map((a) => a.toMap()).toList()) : null),
              subject: email.subject,
              bodyPlain: Value(email.bodyPlain),
              bodyHtml: Value(email.bodyHtml),
              bodyPreview: Value(email.bodyPreview),
              authResults: Value(email.authResults),
              listUnsubscribe: Value(email.listUnsubscribe),
              meetingJson: Value(email.meetingJson),
              attachmentsJson: Value(email.attachments.isNotEmpty ? jsonEncode(email.attachments.map((a) => a.toMap()).toList()) : null),
              receivedAt: email.receivedAt,
              sentAt: Value(email.sentAt),
              isRead: Value(email.isRead),
              isFlagged: Value(email.isFlagged),
              isDraft: Value(email.isDraft),
              hasAttachments: Value(email.hasAttachments),
              size: Value(email.size),
              sensitivity: Value(email.sensitivity),
              priority: Value(email.priority.index),
              status: Value(email.status.index),
              tagsStr: Value(email.tags.join(';')),
              categoriesStr: Value(email.categories.join(';')),
              aiCategory: Value(email.aiCategory),
              sentimentScore: Value(email.sentimentScore),
              aiRecommendation: Value(email.aiRecommendation),
              // Текст пришёл с синхронизацией (ActiveSync) — он сразу идёт в
              // поисковый индекс ниже; уровень 0 оставил бы его фоновой
              // доиндексации второй раз.
              loadedLevel: Value(_hasText(email) ? AppDatabase.levelIndexed : 0),
              cachedAt: Value(DateTime.now()),
            ),
            mode: InsertMode.insertOrReplace,
          );
          continue;
        }

        // ── Существующее письмо: слияние ──
        final local = emailModelFromRow(prevRow);

        // Конфликтные поля (isRead/isFlagged/folderId/tags) разрешаем ТОЛЬКО
        // если пользователь менял письмо локально. Иначе сервер авторитетен.
        // Каждое поле — независимо от ИСХОДНОГО серверного письма (не накапливаем
        // на serverSide: merge folderId возвращает целую локальную модель, и
        // накопление затирало бы серверные значения соседних полей). Теги —
        // отдельным объединением ниже.
        var serverSide = email;
        final keepLocal = local.isLocallyModified && pendingOps.contains(email.id);
        if (keepLocal) {
          serverSide = serverSide.copyWith(
            isRead: local.isRead,
            isFlagged: local.isFlagged,
            folderId: local.folderId,
            folderName: local.folderName,
          );
        } else if (local.isLocallyModified) {
          // Пометка осталась без операции в очереди (операция выполнена или
          // отброшена) — применяем разрешение конфликтов как раньше.
          for (final c in resolver.detectConflicts(local, email)) {
            final r = resolver.resolveConflict(c, local, email);
            switch (c.field) {
              case 'folderId':
                serverSide = serverSide.copyWith(folderId: r.folderId, folderName: r.folderName);
                break;
              // isRead/isFlagged — сервер авторитетен; теги — объединение ниже.
            }
          }
        }

        // Теги/категории — объединение локальных и серверных (теги локальны,
        // сервер их не знает; союз не даёт потерять пользовательские/ИИ-теги).
        final mergedTags = {...local.tags, ...serverSide.tags}.toList();
        final mergedCats = {...local.categories, ...serverSide.categories}.toList();

        // Обновляем только серверные + ИИ-поля. Локальные (remindAt, loadedLevel,
        // classification, extractedDeadline) НЕ входят в companion → сохраняются.
        batch.update(
          db.emails,
          EmailsCompanion(
            folderId: Value(serverSide.folderId),
            // Если письмо осталось в локально выбранной папке (merge переместил),
            // имя берём из его модели, а не из синхронизируемой папки.
            folderName: Value(serverSide.folderId == folder.id ? folder.displayName : serverSide.folderName),
            conversationId: Value(email.conversationId),
            parentId: Value(email.parentId),
            internetMessageId: Value(email.internetMessageId),
            referencesStr: Value(email.references?.join(' ')),
            fromEmail: Value(email.from.email),
            fromName: Value(email.from.displayName),
            // Списки получателей EWS в синке не присылает (только при открытии
            // письма) — пустой список не должен стирать уже известных.
            toRecipients: email.to.isEmpty
                ? const Value.absent()
                : Value(jsonEncode(email.to.map((a) => a.toMap()).toList())),
            ccJson: email.cc.isEmpty
                ? const Value.absent()
                : Value(jsonEncode(email.cc.map((a) => a.toMap()).toList())),
            replyToEmail: email.replyTo.isEmpty
                ? const Value.absent()
                : Value(jsonEncode(email.replyTo.map((a) => a.toMap()).toList())),
            subject: Value(email.subject),
            // Тело и список вложений приходят не всегда: EAS присылает обрезок
            // (его мы не сохраняем как тело), EWS FindItem — без тела и без
            // списка вложений. Пустое значение с сервера означает «не прислали»,
            // а не «стало пустым»: иначе повторный синк стирал бы тело,
            // догруженное при открытии письма.
            bodyPlain: Value.absentIfNull(email.bodyPlain),
            bodyHtml: Value.absentIfNull(email.bodyHtml),
            bodyPreview: Value.absentIfNull(email.bodyPreview),
            authResults: Value.absentIfNull(email.authResults),
            listUnsubscribe: Value.absentIfNull(email.listUnsubscribe),
            meetingJson: Value.absentIfNull(email.meetingJson),
            attachmentsJson: email.attachments.isNotEmpty
                ? Value(jsonEncode(email.attachments.map((a) => a.toMap()).toList()))
                : const Value.absent(),
            receivedAt: Value(email.receivedAt),
            sentAt: Value(email.sentAt),
            isRead: Value(serverSide.isRead),
            isFlagged: Value(serverSide.isFlagged),
            isDraft: Value(email.isDraft),
            hasAttachments: Value(email.hasAttachments),
            size: Value(email.size),
            // Гриф из заголовков (прочитан при открытии) список с сервера не стирает.
            sensitivity: Value(MailLabel.merge(email.sensitivity, local.sensitivity)),
            priority: Value(email.priority.index),
            status: Value(email.status.index),
            tagsStr: Value(mergedTags.isEmpty ? null : mergedTags.join(';')),
            categoriesStr: Value(mergedCats.isEmpty ? null : mergedCats.join(';')),
            aiCategory: Value(email.aiCategory ?? local.aiCategory),
            sentimentScore: Value(email.sentimentScore ?? local.sentimentScore),
            aiRecommendation: Value(email.aiRecommendation ?? local.aiRecommendation),
            // Пока правка ждёт отправки, пометка остаётся — иначе следующий
            // синк до выгрузки очереди откатил бы её.
            isLocallyModified: Value(keepLocal),
            // Новый текст с сервера индексируется ниже.
            loadedLevel: _hasText(email) ? const Value(AppDatabase.levelIndexed) : const Value.absent(),
            cachedAt: Value(DateTime.now()),
          ),
          where: (t) => t.id.equals(email.id) & t.accountId.equals(accountId),
        );
      }
    });

    // Контакты из переписки: кто пишет и кому пишем (подсказки адресатов,
    // фото). Не ждём — на синхронизацию не влияет.
    if (newEmails.isNotEmpty) {
      final acc = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
      if (acc != null) {
        unawaited(_ref
            .read(mailContactsServiceProvider)
            .harvest(acc, newEmails, sent: folder.type == FolderType.sent)
            .catchError((Object e) => AppLogger.debug('Контакты из переписки: $e')));
      }
    }

    // Индексация в FTS5 для полнотекстового поиска — одной транзакцией на
    // пакет. Только новые письма и те, у которых изменилось индексируемое:
    // тема, отправитель, текст с сервера, id (сопоставление ActiveSync).
    // Раньше каждая синхронизация (и смена флага «прочитано») перечитывала
    // из базы тексты всех писем пакета, переводила HTML в текст и
    // переписывала индекс тем же содержимым.
    final toIndex = <EmailModel>[];
    final readStored = <String>[];
    for (final email in emails) {
      final prev = existingById[email.id];
      if (prev == null || _hasText(email)) {
        toIndex.add(email);
      } else if (rekeyed.contains(email.id) ||
          prev.subject != email.subject ||
          prev.fromEmail != email.from.email ||
          (prev.fromName ?? '') != (email.from.displayName ?? '')) {
        // Изменение с сервера пришло без текста: текст для индекса — из базы
        // (иначе индекс полного текста, догруженного при открытии письма,
        // перезаписался бы превью).
        toIndex.add(email);
        readStored.add(email.id);
      }
    }
    final stored = <String, Email>{};
    for (var i = 0; i < readStored.length; i += 400) {
      final part = readStored.sublist(i, i + 400 > readStored.length ? readStored.length : i + 400);
      for (final r in await (db.select(db.emails)
            ..where((t) => t.accountId.equals(accountId) & t.id.isIn(part)))
          .get()) {
        stored[r.id] = r;
      }
    }
    // Текст из HTML для индекса — пачкой в отдельном изоляте.
    final needPlain = <String, String>{
      for (final email in toIndex)
        if ((email.bodyPlain ?? stored[email.id]?.bodyPlain) == null &&
            (email.bodyHtml ?? stored[email.id]?.bodyHtml) != null)
          email.id: (email.bodyHtml ?? stored[email.id]?.bodyHtml)!,
    };
    final plain = needPlain.isEmpty
        ? const <String, String>{}
        : await MailBodyProcessor.htmlToPlainAll(needPlain);
    String? nz(String? s) => (s == null || s.isEmpty) ? null : s;
    if (toIndex.isNotEmpty) {
    await db.transaction(() async {
    for (final email in toIndex) {
      try {
        final r = stored[email.id];
        // Пустая строка с сервера — «не прислали», а не текст письма.
        final body = nz(email.bodyPlain) ??
            nz(r?.bodyPlain) ??
            nz(plain[email.id]) ??
            nz(email.bodyPreview) ??
            nz(r?.bodyPreview) ??
            '';
        await db.indexEmailFts(
          emailId: email.id,
          accountId: accountId,
          subject: email.subject,
          fromText: '${email.from.displayName ?? ''} ${email.from.email}',
          body: body.length > 20000 ? body.substring(0, 20000) : body,
        );
      } catch (_) {/* FTS недоступен — поиск откатится на LIKE */}
    }
    });
    }

    // «На контроле» при отправке: отправленное письмо получает отметку,
    // когда появляется в «Отправленных».
    if (folder.type == FolderType.sent && newEmails.isNotEmpty) {
      await ControlService.matchSent(db, accountId, newEmails);
    }

    // Уведомлять список не нужно: он подписан на поток из БД (.watch()) и
    // переизлучится сам, как только drift увидит запись в таблицу писем.
    return newCount;
  }

  // ════════════════════════ ОЧЕРЕДЬ OFFLINE ════════════════════════

  /// Похожа ли ошибка на отказ в аутентификации (а не на сетевой сбой).
  /// Различать важно: при нестабильной сети «401» не приходит, а таймаут —
  /// не повод помечать аккаунт как проблемный.
  bool _isAuthError(Object e) => looksLikeAuthError(e);

  /// Пометить аккаунт как требующий повторного входа и уведомить пользователя.
  /// Локализация без BuildContext (синхронизация идёт и в фоне).
  AppLocalizations _l10n() => AppLocalizations(_ref.read(settingsProvider).locale);

  /// Первый отказ во входе по ящику: когда случился (в памяти изолята).
  final Map<String, DateTime> _authStrike = {};

  /// Отказ во входе — «требуется вход» только после ПОДТВЕРЖДЕНИЯ: второй
  /// отказ не раньше чем через 2 минуты после первого. Одиночный отказ
  /// бывает и без вины пользователя: шлюз Exchange под нагрузкой отвечает
  /// 401, защищённое хранилище Android после перезагрузки или обновления
  /// системы на миг не отдаёт токен. Раньше это сразу помечало ящик и
  /// присылало уведомление «войдите заново». Цена — одна лишняя попытка
  /// входа, до блокировки учётной записи она не доводит.
  Future<void> _authFailure(AccountModel account, String error) async {
    final now = DateTime.now();
    final first = _authStrike[account.id];
    if (first == null || now.difference(first) > const Duration(hours: 2)) {
      _authStrike[account.id] = now;
      AppLogger.warning('Аккаунт ${account.email}: отказ во входе ($error) — '
          'перепроверю через 3 мин, прежде чем просить войти заново');
      Timer(const Duration(minutes: 3), () {
        final fresh = _ref.read(accountsProvider).where((a) => a.id == account.id).firstOrNull;
        if (fresh != null && fresh.authFailedAt == null) unawaited(syncAccount(fresh));
      });
      return;
    }
    if (now.difference(first) < const Duration(minutes: 2)) return; // тот же сбой, ещё рано
    _authStrike.remove(account.id);
    await _markAuthFailed(account, error);
  }

  Future<void> _markAuthFailed(AccountModel account, String error) async {
    try {
      final db = _ref.read(databaseProvider);
      final row = await (db.select(db.accounts)..where((a) => a.id.equals(account.id)))
          .getSingleOrNull();
      // Уведомляем только при ПЕРВОМ обнаружении, иначе каждое обновление
      // будет присылать одно и то же сообщение.
      final alreadyKnown = row?.authFailedAt != null;
      await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
          .write(AccountsCompanion(authFailedAt: Value(DateTime.now())));
      AppLogger.warning('Аккаунт ${account.email}: ошибка входа — $error');
      // Push-подписки (IDLE / Ping / EWS Streaming) тоже входят на сервер —
      // останавливаем их, иначе они продолжали бы попытки со старым паролем.
      try {
        await _ref.read(imapPushServiceProvider).stopForAccount(account.id);
      } catch (_) {}
      try {
        await _ref.read(accountsProvider.notifier).reload();
      } catch (_) {}
      if (!alreadyKnown) {
        await _ref.read(notificationServiceProvider).showReminderNotification(
              id: 'auth_${account.id}'.hashCode & 0x7FFFFFFF,
              title: _l10n().tr('authRequiredTitle').replaceAll('{email}', account.email),
              body: _l10n().tr('authRequiredBody'),
              payload: 'account:${account.id}',
            );
      }
    } catch (e) {
      AppLogger.warning('Не удалось пометить ошибку входа: $e');
    }
  }

  /// Добавить в очередь.
  ///
  /// Дублирующие операции по одному объекту схлопываются: если пользователь
  /// офлайн трижды переключил флаг у письма или дважды правил задачу, в очереди
  /// должна остаться ОДНА запись с последним состоянием. Иначе при длительной
  /// работе без связи (вахта, командировка) очередь разрастается, а при
  /// восстановлении сети на сервер уходит череда бессмысленных повторов.
  Future<void> enqueueOperation({
    required String accountId,
    required String operationType,
    required String targetId,
    Map<String, dynamic>? payload,
  }) async {
    final db = _ref.read(databaseProvider);
    // Повторная операция того же типа по тому же объекту обновляет уже
    // стоящую запись, а не пересоздаёт её: так сохраняется её место в
    // очереди (порядок «перенести → удалить» не переворачивается). Для
    // переноса сохраняется ИСХОДНАЯ папка первой записи — промежуточной папки
    // на сервере письмо так и не увидело.
    final existing = await (db.select(db.syncQueue)
          ..where((q) =>
              q.accountId.equals(accountId) &
              q.targetId.equals(targetId) &
              q.operationType.equals(operationType))
          ..limit(1))
        .get();
    if (existing.isNotEmpty) {
      final merged = <String, dynamic>{...?payload};
      if (operationType == 'move') {
        try {
          final old = jsonDecode(existing.first.payloadJson) as Map<String, dynamic>;
          if (old['fromFolderId'] != null) merged['fromFolderId'] = old['fromFolderId'];
        } catch (_) {}
      }
      await (db.update(db.syncQueue)..where((q) => q.id.equals(existing.first.id))).write(
        SyncQueueCompanion(payloadJson: Value(jsonEncode(merged)), retryCount: const Value(0)),
      );
      return;
    }
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          accountId: accountId,
          operationType: operationType,
          targetId: targetId,
          payloadJson: payload != null ? jsonEncode(payload) : '{}',
          createdAt: DateTime.now(),
        ));
  }

  /// Обработать очередь
  Future<void> _processQueue(String accountId) async {
    final db = _ref.read(databaseProvider);

    // 1. Отправка писем из очереди (офлайн outbox + отложенная отправка).
    // Этот сервис сам учитывает scheduledAt, backoff и выбирает транспорт.
    try {
      await _ref.read(offlineSendProvider).processQueue(accountId);
    } catch (e) {
      AppLogger.error('Outbox processQueue: $e');
    }

    // 2. Прочие операции (mark_read/flag/move/delete) для офлайн-изменений.
    // Белый список: только операции, которые здесь умеют выполнять. Раньше
    // выбиралось «всё, кроме отправки», и недоставленное письмо (send_failed)
    // при следующем синке попадало сюда, не находило ветки и удалялось как
    // «успешно выполненное» — вместе с текстом и вложениями.
    // Порядок — по времени постановки: перенос и удаление одного письма
    // должны выполниться именно в том порядке, в каком их сделал пользователь.
    final ops = await (db.select(db.syncQueue)
          ..where((q) => q.accountId.equals(accountId))
          ..where((q) => q.operationType.isIn(_queueOps))
          ..orderBy([
            (q) => OrderingTerm(expression: q.priority, mode: OrderingMode.desc),
            (q) => OrderingTerm(expression: q.createdAt),
            (q) => OrderingTerm(expression: q.id),
          ]))
        .get();

    if (ops.isEmpty) return;

    final accounts = _ref.read(accountsProvider);
    // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
    // firstWhere без orElse бросал бы StateError и ронял операцию.
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      // Ящик удалён, а его операции остались в очереди — убираем их (1.6.12):
      // раньше при каждом запуске в журнале было по 8 строк «не найден».
      final n = await (db.delete(db.syncQueue)..where((q) => q.accountId.equals(accountId))).go();
      AppLogger.info('Очередь удалённого ящика $accountId очищена: операций $n');
      return;
    }

    final now = DateTime.now();
    for (final op in ops) {
      // Экспоненциальная пауза между попытками (2, 4, 8 … 64 с): иначе
      // недоступный сервер получал запрос на каждом синке без передышки.
      // Для «сервер недоступен» пауза растёт дальше — до ~17 мин.
      if (op.lastAttemptAt != null && op.retryCount > 0) {
        final wait = Duration(seconds: 1 << op.retryCount.clamp(1, 10));
        if (now.isBefore(op.lastAttemptAt!.add(wait))) continue;
      }
      try {
        final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;

        // Найденные на сервере письма ActiveSync лежат в псевдопапке «search»:
        // такой папки на сервере нет, и каждая операция с ними получала
        // Status 8 и висела в очереди, задерживая синхронизацию ящика.
        // (У EWS id найденного письма — настоящий ItemId: операции идут как обычно.)
        if (account.usesEas &&
            (payload['folderId'] == 'search' ||
                (await _queueFolder(db, account.id, op.targetId, null)) == 'search')) {
          await _clearLocalMark(db, account.id, op.targetId);
          await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
          continue;
        }

        // EWS-семейство (exchange + корпоративный usesEws) — операции через
        // ews_service. Раньше проверялся только isExchange, из-за чего офлайн-
        // правки корпоративных EWS-аккаунтов не выгружались.
        switch (op.operationType) {
          // Почтовые операции — через транспорт аккаунта (EWS, EAS или IMAP).
          // Раньше здесь была только ветка EWS: у ActiveSync и IMAP операции из
          // очереди «выполнялись» без обращения к серверу и удалялись.
          case 'mark_read':
            await _transportFor(account).setRead(account,
                emailId: op.targetId,
                folderId: await _queueFolder(db, account.id, op.targetId, payload['folderId']),
                isRead: payload['isRead'] as bool? ?? true);
            await _clearLocalMark(db, account.id, op.targetId);
            break;
          case 'flag':
            await _transportFor(account).setFlag(account,
                emailId: op.targetId,
                folderId: await _queueFolder(db, account.id, op.targetId, payload['folderId']),
                isFlagged: payload['isFlagged'] as bool? ?? true);
            await _clearLocalMark(db, account.id, op.targetId);
            break;
          case 'move':
            final newId = await _transportFor(account).move(account,
                emailId: op.targetId,
                // Исходная папка: после локального перемещения строка уже
                // в целевой, поэтому берём её из payload (старые записи очереди
                // её не содержат — тогда EWS обойдётся без неё).
                fromFolderId: (payload['fromFolderId'] as String?) ?? '',
                toFolderId: payload['targetFolderId'] as String);
            await _clearLocalMark(db, account.id, op.targetId);
            if (newId != null && newId != op.targetId) {
              await renameEmailId(db, account.id, op.targetId, newId);
            }
            break;
          // PIM-правки, отложенные из-за офлайна. Читаем актуальную строку из
          // БД (за время в очереди её могли изменить ещё раз) и выгружаем.
          case 'upsert_task':
            // Все поля строки; созданная офлайн задача получает id eas_<sid>.
            await _ref.read(mailEngineServiceProvider).pushTask(account, op.targetId);
            break;
          case 'upsert_contact':
            await _ref.read(mailEngineServiceProvider).pushContact(account, op.targetId);
            break;
          case 'delete_task':
            // Задача удалена офлайн — без этого она воскресала при синке.
            await _ref.read(mailEngineServiceProvider).deleteTaskServer(account, op.targetId);
            break;
          case 'delete':
            await _transportFor(account).delete(account,
                emailId: op.targetId,
                // Строка письма уже удалена локально — папка только из payload.
                folderId: (payload['folderId'] as String?) ?? '',
                hard: payload['hard'] as bool? ?? false);
            break;
          default:
            continue; // неизвестный тип не трогаем
        }

        // Успех — удаляем
        await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
      } catch (e) {
        // Status 8 — «объект не найден»: письмо уже удалено или перенесено на
        // сервере (или другим клиентом). Повторять бессмысленно — убираем
        // операцию сразу, следующая синхронизация вернёт серверное состояние.
        // Раньше она пять раз повторялась и висела в очереди.
        if (RegExp(r'Status=8\b').hasMatch('$e') ||
            '$e'.contains('ErrorItemNotFound')) {
          AppLogger.info('Операция ${op.operationType} для ${op.targetId}: на сервере не найдено — убрана');
          await _clearLocalMark(db, account.id, op.targetId);
          await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
          continue;
        }
        await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id))).write(SyncQueueCompanion(
          retryCount: Value(op.retryCount + 1),
          lastAttemptAt: Value(DateTime.now()),
          errorMessage: Value('$e'),
        ));

        // Сервер недоступен (VPN выключен, корпоративная сеть, шлюз, таймаут)
        // — это не отказ сервера: операция ждёт, сколько нужно (до недели),
        // а не откатывается через шесть синхронизаций. Раньше «есть сеть, но
        // нет сервера» сжигало попытки и откатывало офлайн-правки.
        final unreachable = _isServerUnreachable(e);
        final expired = now.difference(op.createdAt) > const Duration(days: 7);
        if (unreachable && !expired) {
          AppLogger.info('Операция ${op.operationType} ждёт сервер: $e');
          continue;
        }
        if (op.retryCount >= 5 || expired) {
          // Операция исчерпала попытки. Раньше она удалялась, а письмо
          // навсегда оставалось «изменённым локально»: оно больше не получало
          // изменений с сервера и расходилось с ним без всякого сигнала.
          // Теперь локальная правка откатывается к серверному состоянию
          // (где это возможно) и пользователь получает уведомление.
          AppLogger.warning(
              'Операция ${op.operationType} для ${op.targetId} отброшена после '
              '${op.retryCount + 1} попыток. Последняя ошибка: $e');
          await _rollbackFailedOp(db, account, op);
          await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
        }
      }
    }
  }

  static const _queueOps = ['mark_read', 'flag', 'move', 'delete', 'upsert_task', 'upsert_contact', 'delete_task'];

  /// Ошибка «сервер не достигнут»: сеть, DNS, таймаут, шлюз, перегрузка.
  /// Такие операции повторяются без счёта попыток (см. _processQueue).
  static bool _isServerUnreachable(Object e) {
    if (e is SocketException || e is TimeoutException || e is HandshakeException) return true;
    final s = '$e'.toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('network is unreachable') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('http 502') || s.contains('http 503') || s.contains('http 504') ||
        s.contains('(502)') || s.contains('(503)') || s.contains('(504)') ||
        s.contains('подключение к серверу не удалось') ||
        s.contains('waf') ||
        s.contains('нет подключения') ||
        s.contains('сервер недоступен');
  }

  /// Папки выключены в «Синхронизации папок», письма — убрать с телефона
  /// (1.5.9; на сервере всё остаётся). Состояние синхронизации папок
  /// сбрасывается: включённые снова, они загрузятся с начала, а не только
  /// новые письма. Возвращает число удалённых писем.
  Future<int> dropLocalFolderMail(AccountModel account, List<String> folderIds,
      {void Function(int removed)? onProgress}) async {
    final db = _ref.read(databaseProvider);
    final n = await db.deleteLocalFolderEmails(account.id, folderIds, onProgress: onProgress);
    for (final id in folderIds) {
      await _resetFolderSync(account, id);
      await _prefs.remove('imap_state:${account.id}:$id');
    }
    AppLogger.info('Синхронизация папок: с телефона убрано писем — $n (папок: ${folderIds.length})');
    return n;
  }

  /// Сбросить состояние синхронизации папки (EAS SyncKey / EWS SyncState),
  /// чтобы следующая синхронизация получила её содержимое заново.
  Future<void> _resetFolderSync(AccountModel account, String folderId) async {
    try {
      if (account.usesEas) {
        await _ref.read(mailEngineServiceProvider).resetMailFolderSync(account, folderId);
      } else if (account.usesEws || account.isExchange) {
        await _prefs.remove(_ewsDeltaKey(account.id, folderId));
      }
      // IMAP: окно последних писем сверяется при каждой синхронизации.
    } catch (e) {
      AppLogger.warning('Сброс синхронизации папки $folderId: $e');
    }
  }

  /// Откат локальной правки, которую сервер так и не принял.
  Future<void> _rollbackFailedOp(AppDatabase db, AccountModel account, SyncQueueData op) async {
    try {
      final p = jsonDecode(op.payloadJson) as Map<String, dynamic>;
      final mine = (db.update(db.emails)
        ..where((e) => e.id.equals(op.targetId) & e.accountId.equals(account.id)));
      switch (op.operationType) {
        case 'mark_read':
          await mine.write(EmailsCompanion(
              isRead: Value(!(p['isRead'] as bool? ?? true)), isLocallyModified: const Value(false)));
          break;
        case 'flag':
          await mine.write(EmailsCompanion(
              isFlagged: Value(!(p['isFlagged'] as bool? ?? true)), isLocallyModified: const Value(false)));
          break;
        case 'move':
          final from = p['fromFolderId'] as String?;
          await mine.write(EmailsCompanion(
            folderId: from == null || from.isEmpty ? const Value.absent() : Value(from),
            isLocallyModified: const Value(false),
          ));
          break;
        case 'delete':
          // Строки письма уже нет, а на сервере оно осталось. Синхронизация
          // папки начинается заново — письмо вернётся в клиент.
          final folderId = p['folderId'] as String?;
          if (folderId != null && folderId.isNotEmpty) await _resetFolderSync(account, folderId);
          break;
        default:
          await _clearLocalMark(db, account.id, op.targetId);
      }
      await _ref.read(notificationServiceProvider).showReminderNotification(
            id: 'queue_${op.id}'.hashCode & 0x7FFFFFFF,
            title: _l10n().tr('opRejectedTitle'),
            body: _l10n()
                .tr('opRejectedBody')
                .replaceAll('{email}', account.email)
                .replaceAll('{op}', _opLabel(op.operationType)),
            payload: 'account:${account.id}',
          );
    } catch (e) {
      AppLogger.warning('Откат операции ${op.id}: $e');
    }
  }

  String _opLabel(String type) => switch (type) {
        'mark_read' => _l10n().tr('opMarkRead'),
        'flag' => _l10n().tr('opFlag'),
        'move' => _l10n().tr('opMove'),
        'delete' => _l10n().tr('opDelete'),
        'upsert_task' => _l10n().tr('opTaskChange'),
        'upsert_contact' => _l10n().tr('opContactChange'),
        'delete_task' => _l10n().tr('opTaskDelete'),
        _ => type,
      };

  /// Письмо получило на сервере новый id (EWS после переноса): переименовать
  /// строку и перенацелить ещё не выполненные операции очереди на новый id.
  Future<void> renameEmailId(AppDatabase db, String accountId, String oldId, String newId) async {
    try {
      await (db.update(db.emails)..where((e) => e.id.equals(oldId) & e.accountId.equals(accountId)))
          .write(EmailsCompanion(id: Value(newId)));
      await (db.update(db.syncQueue)
            ..where((q) => q.accountId.equals(accountId) & q.targetId.equals(oldId)))
          .write(SyncQueueCompanion(targetId: Value(newId)));
      await db.removeEmailFts(oldId, accountId: accountId);
      final row = await db.getEmailById(newId, accountId: accountId);
      if (row != null) {
        await db.indexEmailFts(
          emailId: newId,
          accountId: accountId,
          subject: row.subject,
          fromText: '${row.fromName ?? ''} ${row.fromEmail}',
          body: row.bodyPlain ?? row.bodyPreview ?? '',
        );
      }
    } catch (e) {
      // Строка с новым id уже пришла синхронизацией — старая лишняя.
      await (db.delete(db.emails)..where((e) => e.id.equals(oldId) & e.accountId.equals(accountId))).go();
    }
  }
}

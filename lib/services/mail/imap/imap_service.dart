// lib/services/mail/imap/imap_service.dart
// Полная IMAP/SMTP реализация через enough_mail:
// - IMAP IDLE для push-уведомлений
// - Получение папок, писем с пагинацией
// - Отправка через SMTP
// - Обработка charset (CP1251, KOI8-R)
// - Chunked download для больших вложений
// - Reconnect при разрыве

import '../../../core/utils/text_safe.dart';
import '../../../core/errors/app_exceptions.dart' show looksLikeAuthError, PushAuthFailure, OAuthRefreshFailure;
import 'dart:async';
import 'dart:math' show Random;
import 'dart:io';
import 'dart:convert';
import '../unsubscribe_service.dart' show encodeListUnsubscribe;
import '../../security/mail_classification.dart' show MailLabel;
import '../../security/smime_mime.dart' show SmimeMime;
import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../sync/push_health.dart';
import '../../../core/security/secure_storage_service.dart';
import '../oauth/oauth_service.dart';
import '../../../core/utils/charset_handler.dart';
import '../../../data/database/app_database.dart' show EmailsCompanion;
import '../../../data/providers/database_provider.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../core/network/certificate_pinning_bridge.dart';
import '../../../data/models/mail_quota.dart';
import '../../../features/settings/providers/settings_provider.dart' show EmailFetchMode;

final imapServiceProvider = Provider<ImapService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final service = ImapService(secureStorage);
  // Подключаем обновление OAuth-токена (refresh при истечении).
  service.tokenRefresher =
      (account, force) => ref.read(oauthServiceProvider).ensureValidToken(account, force: force);
  // После переноса на сервере у письма НОВЫЙ UID в папке назначения, а
  // локальная строка осталась со старым id («из_папки:UID»). Действия над ней
  // ушли бы с чужим UID. Переименовываем строку (если сервер сообщил новый
  // UID) или убираем — синхронизация папки назначения принесёт её заново.
  service.onMoved = (accountId, oldId, toFolderId, newId) async {
    try {
      final db = ref.read(databaseProvider);
      await db.removeEmailFts(oldId, accountId: accountId);
      if (newId != null) {
        await (db.update(db.emails)
              ..where((e) => e.accountId.equals(accountId) & e.id.equals(oldId)))
            .write(EmailsCompanion(id: Value(newId), folderId: Value(toFolderId)));
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
      } else {
        await (db.delete(db.emails)
              ..where((e) => e.accountId.equals(accountId) & e.id.equals(oldId)))
            .go();
      }
    } catch (e) {
      AppLogger.debug('IMAP onMoved: $e');
    }
  };
  // Закрываем все соединения при пересоздании провайдера (logout/смена аккаунта),
  // чтобы не оставлять висящие IMAP/SMTP-сокеты.
  ref.onDispose(service.dispose);
  return service;
});

/// Операция IMAP не завершилась за отведённое время (см. ImapService._withClient).
class ImapOperationHung implements Exception {
  final Duration limit;
  const ImapOperationHung(this.limit);
  @override
  String toString() => 'IMAP: операция не завершилась за ${limit.inMinutes} мин';
}

class ImapService {
  final SecureStorageService _secureStorage;
  final Map<String, ImapClient> _imapClients = {};
  final Map<String, SmtpClient> _smtpClients = {};

  // ── Мьютекс на аккаунт (КРИТИЧНО) ────────────────────────────────────────
  // IMAP имеет СОСТОЯНИЕ: сначала SELECT папки, потом FETCH/STORE в ней.
  // Клиент у аккаунта один и общий. Внутренняя очередь enough_mail сериализует
  // отдельные команды, но НЕ группирует их в транзакцию. Поэтому две
  // параллельные операции чередуются так:
  //     SELECT «Отправленные» · SELECT «Входящие» · FETCH · FETCH
  // и FETCH первой операции читает ЧУЖУЮ папку — письма сохраняются не туда.
  // Сценарий реальный: фоновый синк идёт по одной папке, пользователь тянет
  // вниз в другой. Ниже — последовательная очередь на аккаунт: пара
  // «выбрать папку + работа с ней» выполняется целиком.
  final Map<String, Future<void>> _accountLocks = {};

  Future<T> _withAccountLock<T>(String accountId, Future<T> Function() action) async {
    final previous = _accountLocks[accountId];
    final gate = Completer<void>();
    _accountLocks[accountId] = gate.future;
    if (previous != null) {
      try {
        await previous; // ждём завершения предыдущей операции этого аккаунта
      } catch (_) {
        // ошибка предыдущей операции не должна блокировать следующую
      }
    }
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_accountLocks[accountId], gate.future)) {
        unawaited(_accountLocks.remove(accountId));
      }
    }
  }


  /// Операция на общем клиенте аккаунта — под мьютексом и с ОДНИМ повтором
  /// на новом соединении, если старое оборвалось.
  ///
  /// Сервер закрывает простаивающее IMAP-соединение (обычно через 30 минут),
  /// мобильная сеть меняет адрес, ноутбук просыпается — а клиент в пуле
  /// по-прежнему считает себя «вошедшим». Раньше после этого любая операция
  /// падала до перезапуска приложения.
  ///
  /// [limit] — потолок времени одной операции. Операции аккаунта идут по
  /// очереди, и одна зависшая (сокет не закрыт, ответ не пришёл, таймаут
  /// клиента не сработал) раньше останавливала ВСЕ следующие: синхронизация
  /// Яндекса 06.10 не завершилась ни разу за два часа, а пересинхронизация и
  /// обновление жестом становились в очередь за ней. Теперь по истечении
  /// срока соединение закрывается, операция падает с таймаутом, очередь идёт.
  Future<T> _withClient<T>(AccountModel account, Future<T> Function(ImapClient client) action,
      {Duration limit = const Duration(minutes: 5), bool Function()? canRetry}) {
    return _withAccountLock(account.id, () async {
      for (var attempt = 0;; attempt++) {
        final client = await _getImapClient(account).timeout(const Duration(seconds: 90));
        try {
          return await action(client).timeout(limit, onTimeout: () {
            AppLogger.warning('IMAP ${account.email}: операция не завершилась за '
                '${limit.inMinutes} мин — соединение закрыто');
            _dropClient(account.id);
            throw ImapOperationHung(limit);
          });
        } on ImapOperationHung {
          rethrow; // не повторяем: зависание — не обрыв, повтор ждал бы снова
        } catch (e) {
          // [canRetry] — для APPEND: обрыв после начала записи мог случиться,
          // когда сервер письмо уже сохранил, и повтор дал бы дубль. Обрыв
          // мёртвого соединения ДО записи (простой пула) повторяем как обычно.
          if (attempt > 0 || !(canRetry?.call() ?? true) || !_isConnectionError(e)) rethrow;
          AppLogger.info('IMAP ${account.email}: соединение потеряно ($e) — переподключаюсь');
          _dropClient(account.id);
        }
      }
    });
  }

  static bool _isConnectionError(Object e) {
    if (e is SocketException || e is TimeoutException || e is HandshakeException || e is StateError) {
      return true;
    }
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('connection') ||
        s.contains('closed') ||
        s.contains('broken pipe') ||
        s.contains('not connected') ||
        s.contains('timeout') ||
        s.contains('timed out');
  }

  void _dropClient(String accountId) {
    final c = _imapClients.remove(accountId);
    if (c != null) {
      // disconnect() асинхронный: ошибку закрытия мёртвого сокета ловим
      // в самом Future, иначе она всплывала бы как необработанная.
      unawaited(c.disconnect().catchError((Object _) {}));
    }
  }

  /// Путь папки для MOVE/APPEND. enough_mail кодирует последний сегмент
  /// пути в modified UTF-7 ещё раз, поэтому передаём его РАСКОДИРОВАННЫМ:
  /// иначе «&BBoEPgRABDcEOAQ9BDA-» превращался в «&-BBoE...» и перенос в
  /// кириллическую папку («Удалённые» у Яндекса/Mail.ru) отвергался.
  static String _pathForEnoughMail(ImapClient client, String encodedPath) {
    if (client.serverInfo.supportsUtf8) return encodedPath;
    final sep = client.serverInfo.pathSeparator ?? '/';
    final i = encodedPath.lastIndexOf(sep);
    if (i < 0) return decodeMutf7(encodedPath);
    return '${encodedPath.substring(0, i)}$sep${decodeMutf7(encodedPath.substring(i + sep.length))}';
  }

  /// Раскодировать modified UTF-7 (RFC 3501, 5.1.3).
  static String decodeMutf7(String s) {
    if (!s.contains('&')) return s;
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c != '&') {
        out.write(c);
        i++;
        continue;
      }
      final end = s.indexOf('-', i + 1);
      if (end < 0) {
        out.write(s.substring(i));
        break;
      }
      final chunk = s.substring(i + 1, end);
      if (chunk.isEmpty) {
        out.write('&');
      } else {
        var b64 = chunk.replaceAll(',', '/');
        while (b64.length % 4 != 0) {
          b64 += '=';
        }
        try {
          final bytes = base64Decode(b64);
          final units = <int>[
            for (var k = 0; k + 1 < bytes.length; k += 2) (bytes[k] << 8) | bytes[k + 1],
          ];
          out.write(String.fromCharCodes(units));
        } catch (_) {
          out.write(s.substring(i, end + 1));
        }
      }
      i = end + 1;
    }
    return out.toString();
  }

  /// Колбэк обновления OAuth-токена (устанавливается из провайдера, где есть ref).
  /// Вызывается перед использованием access-токена, чтобы обновить истёкший.
  /// (аккаунт, принудительно) — обновление OAuth-токена (OAuthService:
  /// через прокси или напрямую у провайдера).
  Future<void> Function(AccountModel account, bool force)? _ensureToken;
  set tokenRefresher(Future<void> Function(AccountModel account, bool force)? cb) => _ensureToken = cb;

  ImapService(this._secureStorage);

  // ════════════════════════ CONNECT ════════════════════════

  /// Когда общий клиент аккаунта последний раз выдавался в работу.
  final Map<String, DateTime> _lastUsed = {};

  /// Общий клиент аккаунта для обычных операций (под мьютексом _withAccountLock).
  Future<ImapClient> _getImapClient(AccountModel account) async {
    if (_imapClients.containsKey(account.id)) {
      final client = _imapClients[account.id]!;
      final idle = DateTime.now().difference(_lastUsed[account.id] ?? DateTime(2000));
      if (client.isLoggedIn && idle < const Duration(minutes: 2)) {
        _lastUsed[account.id] = DateTime.now();
        return client;
      }
      // Соединение простояло: сервер или NAT могли его закрыть, а сокет об
      // этом не знает. Без проверки первая команда ждала ответа весь таймаут
      // (3 минуты: «IMAP getFolders error: timeout» в журнале 06.10, Яндекс
      // после паузы). NOOP с коротким таймаутом — и, если молчит, новое.
      if (client.isLoggedIn) {
        try {
          await client.noop().timeout(const Duration(seconds: 10));
          _lastUsed[account.id] = DateTime.now();
          return client;
        } catch (_) {
          AppLogger.info('IMAP ${account.email}: простоявшее соединение не отвечает — новое');
        }
      }
      _imapClients.remove(account.id);
      unawaited(client.disconnect().catchError((Object _) {}));
    }
    final client = await _connectAndLogin(account);
    _imapClients[account.id] = client;
    _lastUsed[account.id] = DateTime.now();
    AppLogger.info('IMAP подключён ✓: ${account.email}');
    return client;
  }

  /// Новое соединение + вход. Вынесено, чтобы IDLE мог держать ОТДЕЛЬНЫЙ клиент:
  /// IDLE занимает соединение постоянно, и на общем клиенте он блокировал бы
  /// обычные операции (или конфликтовал с их SELECT).
  Future<ImapClient> _connectAndLogin(AccountModel account,
      {bool forIdle = false, bool tokenRetried = false}) async {
    // Таймаут ответа — только для обычного клиента: IDLE по определению
    // ждёт ответа сервера долго.
    final host = _imapHost(account);
    final port = account.imapPort ?? AppConstants.defaultImapPort;
    // Сертификат, не прошедший системную проверку, — по тем же правилам, что
    // и для HTTPS: принятый пользователем по отпечатку (экран аккаунта →
    // «Безопасность») или корпоративный домен. Раньше IMAP и SMTP эти
    // правила не учитывали, и сервер с собственным сертификатом не работал.
    final client = forIdle
        ? ImapClient(isLogEnabled: false, onBadCertificate: (c) => _acceptCert(c, host, port))
        : ImapClient(
            isLogEnabled: false,
            defaultWriteTimeout: const Duration(seconds: 30),
            // С запасом: полное письмо с вложениями по медленной сети.
            defaultResponseTimeout: const Duration(minutes: 3),
            onBadCertificate: (c) => _acceptCert(c, host, port),
          );

    // Шифрование не задано (аккаунты OAuth его не сохраняют) — по порту:
    // 993 — неявный TLS. Раньше null означал «без TLS», и подключение к 993
    // открытым текстом зависало до таймаута.
    final enc = account.imapEncryption ??
        (port == 143 ? EncryptionType.starttls : EncryptionType.ssl);
    final useSSL = enc == EncryptionType.ssl;
    AppLogger.info('IMAP → подключение $host:$port (SSL=$useSSL)');

    try {
      await client
          .connectToServer(host, port, isSecure: useSSL)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      AppLogger.warning('IMAP: не удалось подключиться к $host:$port — $e '
          '(проверьте сервер/порт/сеть)');
      rethrow;
    }

    if (enc == EncryptionType.starttls) {
      AppLogger.info('IMAP: STARTTLS...');
      await client.startTls();
    }

    // Аутентификация
    if (account.isOAuth) {
      // Обновляем access-токен, если он истёк (иначе IMAP-вход упадёт через ~1 час).
      if (_ensureToken != null) {
        try { await _ensureToken!(account, false); } catch (e) {
          AppLogger.warning('IMAP: не удалось обновить OAuth-токен — $e');
          // Отозванный вход или истёкший токен — в IMAP не входим: вход
          // заведомо плохим токеном засчитывается как неудачный.
          final exp = await _secureStorage.getTokenExpiry(account.id);
          final expired = exp == null || DateTime.now().isAfter(exp);
          if ((e is OAuthRefreshFailure && e.needsSignIn) || expired) {
            unawaited(client.disconnect().catchError((Object _) {}));
            rethrow;
          }
        }
      }
      final token = await _secureStorage.getAccessToken(account.id);
      if (token != null) {
        try {
          await client.authenticateWithOAuth2(account.email, token);
        } catch (e) {
          if (tokenRetried) rethrow;
          // Токен мог быть отозван/просрочен, хотя срок ещё «не истёк»
          // (смена пароля, выход на всех устройствах). Один раз
          // принудительно обновляем и пробуем снова.
          AppLogger.warning('IMAP XOAUTH2 отклонён — обновляю токен: $e');
          unawaited(client.disconnect().catchError((Object _) {}));
          await _ensureToken?.call(account, true);
          final fresh = await _secureStorage.getAccessToken(account.id);
          if (fresh == null || fresh == token) rethrow;
          return _connectAndLogin(account, forIdle: forIdle, tokenRetried: true);
        }
      } else {
        throw Exception('IMAP: No OAuth token');
      }
    } else {
      final password = await _secureStorage.getAccountPassword(account.id);
      if (password == null) throw Exception('IMAP: No password');
      // Логин IMAP — полный email; fallback на email, если username пуст.
      final loginName = account.username.isNotEmpty ? account.username : account.email;
      try {
        await client.login(loginName, password);
      } catch (e) {
        AppLogger.warning('IMAP: вход не удался для $loginName — $e '
            '(неверный логин/пароль или требуется пароль приложения)');
        rethrow;
      }
    }

    return client;
  }

  /// Серверы по умолчанию для почтовых сервисов (аккаунты OAuth хранят
  /// только тип, без адресов). Раньше при пустом адресе подставлялся Gmail —
  /// и ящик Яндекса/Mail.ru пытался войти на imap.gmail.com.
  static const _providerHosts = <AccountType, ({String imap, String smtp})>{
    AccountType.google: (imap: 'imap.gmail.com', smtp: 'smtp.gmail.com'),
    AccountType.yandex: (imap: 'imap.yandex.ru', smtp: 'smtp.yandex.ru'),
    AccountType.mailru: (imap: 'imap.mail.ru', smtp: 'smtp.mail.ru'),
    // Outlook.com/Hotmail/Live и Office 365 — один сервер; SMTP только 587 STARTTLS.
    AccountType.outlook: (imap: 'outlook.office365.com', smtp: 'smtp.office365.com'),
    AccountType.yahoo: (imap: 'imap.mail.yahoo.com', smtp: 'smtp.mail.yahoo.com'),
  };

  String _imapHost(AccountModel account) {
    final h = account.imapServer?.trim() ?? '';
    if (h.isNotEmpty) return h;
    final byType = _providerHosts[account.type]?.imap;
    if (byType != null) return byType;
    final byDomain = AppConstants.serverConfigForEmail(account.email)?['imap'] as String?;
    return byDomain ?? 'imap.${account.email.split('@').last}';
  }

  String _smtpHost(AccountModel account) {
    final h = account.smtpServer?.trim() ?? '';
    if (h.isNotEmpty) return h;
    final byType = _providerHosts[account.type]?.smtp;
    if (byType != null) return byType;
    final byDomain = AppConstants.serverConfigForEmail(account.email)?['smtp'] as String?;
    return byDomain ?? 'smtp.${account.email.split('@').last}';
  }

  /// Новое SMTP-соединение с входом — НА КАЖДУЮ отправку.
  ///
  /// Раньше SMTP-клиент хранился в пуле. SMTP-серверы закрывают простаивающее
  /// соединение через несколько минут, а клиент продолжал считать себя
  /// «вошедшим»: каждая следующая отправка падала, письмо уходило в очередь и
  /// падало снова — до перезапуска приложения. Отправка редкая, лишнее
  /// TLS-рукопожатие на неё ничего не стоит.
  /// Решение по сертификату, отклонённому системой (см. CertificatePinningService).
  static bool _acceptCert(X509Certificate cert, String host, int port) =>
      CertificatePinningBridge.instance?.evaluate(cert, host, port) ?? false;

  Future<SmtpClient> _openSmtp(AccountModel account, {bool tokenRetried = false}) async {
    final smtpServer = _smtpHost(account);
    final client = SmtpClient(
      account.email.split('@').last,
      isLogEnabled: false,
      onBadCertificate: (c) => _acceptCert(c, smtpServer, account.smtpPort ?? 465),
    );

    // Для сервисов OAuth и при незаданном порте — 465 (неявный TLS): он
    // работает у всех четырёх провайдеров и не зависит от STARTTLS.
    final smtpPort = account.smtpPort ?? (account.isOAuth ? 465 : AppConstants.defaultSmtpPort);
    // Порт 465 = неявный SSL; 587/25 = STARTTLS.
    var useSSL = smtpPort == 465 ||
        (account.smtpEncryption == EncryptionType.ssl && smtpPort != 587);

    var connectedPort = smtpPort;
    try {
      await client.connectToServer(smtpServer, smtpPort, isSecure: useSSL)
          .timeout(const Duration(seconds: 15));
      await client.ehlo().timeout(const Duration(seconds: 10));
      if (!useSSL && account.smtpEncryption != EncryptionType.none) {
        await client.startTls().timeout(const Duration(seconds: 10));
        await client.ehlo().timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      // Fallback: если 465 (SSL) не подключился — пробуем 587 STARTTLS
      AppLogger.warning('SMTP $smtpServer:$smtpPort (SSL=$useSSL) не удался: $e — пробуем 587 STARTTLS');
      if (smtpPort == 465) {
        try { await client.disconnect(); } catch (_) {}
        useSSL = false;
        connectedPort = 587;
        await client.connectToServer(smtpServer, 587, isSecure: false)
            .timeout(const Duration(seconds: 15));
        await client.ehlo().timeout(const Duration(seconds: 10));
        await client.startTls().timeout(const Duration(seconds: 10));
        await client.ehlo().timeout(const Duration(seconds: 10));
      } else {
        rethrow;
      }
    }

    if (account.isOAuth) {
      try { await _ensureToken?.call(account, false); } catch (_) {}
      final token = await _secureStorage.getAccessToken(account.id);
      if (token == null) {
        try { await client.disconnect(); } catch (_) {}
        throw Exception('SMTP: нет OAuth-токена — войдите в аккаунт заново');
      }
      try {
        await client.authenticate(account.email, token, AuthMechanism.xoauth2)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        try { await client.disconnect(); } catch (_) {}
        if (tokenRetried) rethrow;
        // Токен отозван раньше срока — принудительно обновляем один раз.
        AppLogger.warning('SMTP XOAUTH2 отклонён — обновляю токен: $e');
        await _ensureToken?.call(account, true);
        final fresh = await _secureStorage.getAccessToken(account.id);
        if (fresh == null || fresh == token) rethrow;
        return _openSmtp(account, tokenRetried: true);
      }
    } else {
      final password = await _secureStorage.getAccountPassword(account.id);
      if (password == null) {
        try { await client.disconnect(); } catch (_) {}
        throw Exception('SMTP: пароль не найден');
      }
      final smtpUser = account.username.contains('@') ? account.username : account.email;
      try {
        await client.authenticate(smtpUser, password, AuthMechanism.plain)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // Часть серверов принимает только AUTH LOGIN.
        if (!client.serverInfo.supportsAuth(AuthMechanism.login)) rethrow;
        AppLogger.info('SMTP: AUTH PLAIN не принят ($e) — пробую AUTH LOGIN');
        await client.authenticate(smtpUser, password, AuthMechanism.login)
            .timeout(const Duration(seconds: 15));
      }
    }

    AppLogger.info('SMTP connected: ${account.email} ($smtpServer:$connectedPort, SSL=$useSSL)');
    return client;
  }

  /// Текст последней ошибки входа (для сообщения на экране входа).
  String? lastConnectError;

  /// Тест подключения
  Future<bool> testConnection(AccountModel account) async {
    lastConnectError = null;
    try {
      final client = await _getImapClient(account);
      final mailboxes = await client.listMailboxes(recursive: true);
      AppLogger.info('IMAP test: ${mailboxes.length} mailboxes');
      return mailboxes.isNotEmpty;
    } catch (e) {
      AppLogger.error('IMAP test failed', e);
      lastConnectError = '$e';
      _dropClient(account.id);
      return false;
    }
  }

  // ════════════════════════ FOLDERS ════════════════════════

  Future<List<FolderModel>> getFolders(AccountModel account) async {
    // Последовательно на аккаунт: SELECT+операция не должны перемешаться
    // с параллельным запросом к другой папке (см. _withAccountLock).
    return _withClient(account, (client) async {
    try {
      final mailboxes = await client.listMailboxes(recursive: true);
      final trash = mailboxes.where((mb) => mb.isTrash).firstOrNull;
      if (trash != null) _trashPath[account.id] = trash.encodedPath;

      // Рекурсивный список: у Gmail «Отправленные», «Корзина» и др. лежат
      // внутри [Gmail]/. Сам [Gmail] — контейнер с \Noselect: открыть его
      // нельзя («Unknown Mailbox»), в список папок не берём.
      final selectable = {
        for (final mb in mailboxes)
          if (!mb.flags.contains(MailboxFlag.noSelect)) mb.encodedPath,
      };
      return mailboxes
          .where((mb) => !mb.flags.contains(MailboxFlag.noSelect))
          .map((mb) {
        final name = mb.name;
        // Родитель — папка уровнем выше, если её можно открыть (контейнер
        // Gmail «[Gmail]» с \Noselect — не родитель: папки в нём — корневые).
        // Раньше дерева у IMAP не было: подпапки шли плоским списком.
        final sep = mb.pathSeparator;
        final cut = mb.encodedPath.lastIndexOf(sep);
        final parentPath = cut > 0 ? mb.encodedPath.substring(0, cut) : null;
        final type = _mapMailboxType(mb);

        // Виртуальные папки Gmail («Вся почта» \All, «Помеченные» \Flagged)
        // повторяют письма из других папок — не синхронизируем, иначе в
        // «Вся почта» приложения каждое письмо будет дважды.
        final virtual = mb.flags.contains(MailboxFlag.all) ||
            mb.flags.contains(MailboxFlag.flagged);
        return FolderModel(
          id: mb.encodedPath,
          accountId: account.id,
          parentId: parentPath != null && selectable.contains(parentPath) ? parentPath : null,
          displayName: name,
          type: type,
          serverPath: mb.encodedPath,
          isSynced: !virtual,
          showInUnified: !virtual && FolderModel.unifiedByDefault(type),
          sortOrder: _folderOrder(type),
        );
      }).toList();
    } catch (e) {
      AppLogger.error('IMAP getFolders error', e);
      rethrow;
    }
  });
  }

  // ════════════════════════ ПАПКИ НА СЕРВЕРЕ ════════════════════════
  // Раньше у IMAP-ящиков создание папки всегда «не удавалось»: движок
  // поддерживал только Exchange. Пути — как в getFolders (encodedPath);
  // последний сегмент enough_mail кодирует сам, поэтому передаётся
  // раскодированным (см. _pathForEnoughMail).

  /// Создать папку в корне или внутри [parentPath]. Возвращает её путь.
  Future<String?> createFolder(AccountModel account, String name, {String? parentPath}) =>
      _withClient(account, (client) async {
        final sep = client.serverInfo.pathSeparator ?? '/';
        final path = (parentPath == null || parentPath.isEmpty) ? name : '$parentPath$sep$name';
        final box = await client.createMailbox(path);
        AppLogger.info('IMAP: папка создана ${box.encodedPath}');
        return box.encodedPath;
      }, canRetry: () => false);

  /// Переименовать и/или переместить папку: [newName] — новое имя (null —
  /// прежнее), [newParentPath] — новый родитель ('' — корень, null — прежний).
  Future<bool> renameFolder(AccountModel account,
          {required String path, String? newName, String? newParentPath}) =>
      _withClient(account, (client) async {
        final sep = client.serverInfo.pathSeparator ?? '/';
        final boxes = await client.listMailboxes(recursive: true);
        final box = boxes.where((b) => b.encodedPath == path).firstOrNull;
        if (box == null) return false;
        final i = path.lastIndexOf(sep);
        final parent = newParentPath ?? (i < 0 ? '' : path.substring(0, i));
        final last = newName ?? decodeMutf7(i < 0 ? path : path.substring(i + sep.length));
        final target = parent.isEmpty ? last : '$parent$sep$last';
        await client.renameMailbox(box, target);
        AppLogger.info('IMAP: папка $path → $target');
        return true;
      }, canRetry: () => false);

  /// Удалить папку на сервере.
  Future<bool> deleteFolder(AccountModel account, {required String path}) =>
      _withClient(account, (client) async {
        final boxes = await client.listMailboxes(recursive: true);
        final box = boxes.where((b) => b.encodedPath == path).firstOrNull;
        if (box == null) return false;
        await client.deleteMailbox(box);
        return true;
      }, canRetry: () => false);

  FolderType _mapMailboxType(Mailbox mb) {
    if (mb.isInbox) return FolderType.inbox;
    if (mb.isSent) return FolderType.sent;
    if (mb.isDrafts) return FolderType.drafts;
    if (mb.isTrash) return FolderType.trash;
    if (mb.isJunk) return FolderType.junk;
    if (mb.isArchive) return FolderType.archive;
    // Без SPECIAL-USE «Архив» и «Спам» узнаются по названию на разных языках
    // при сохранении списка папок (SpecialFolders, 1.7.2+106). Раньше архивом
    // считалась любая папка со словом «archive» или «архив» в имени — и
    // «Архив 2019» внутри проекта тоже, а «В архив» выбирала из них первую.
    final lower = mb.name.toLowerCase();
    if (lower.contains('outbox') || lower.contains('исходящие')) return FolderType.outbox;
    return FolderType.custom;
  }

  int _folderOrder(FolderType type) {
    switch (type) {
      case FolderType.inbox: return 0;
      case FolderType.drafts: return 1;
      case FolderType.sent: return 2;
      case FolderType.outbox: return 3;
      case FolderType.archive: return 4;
      case FolderType.junk: return 5;
      case FolderType.trash: return 6;
      case FolderType.custom: return 10;
    }
  }

  // ════════════════════════ EMAILS ════════════════════════

  Future<List<EmailModel>> getEmails(
    AccountModel account, {
    required String folderId,
    int pageSize = 50,
    int page = 1,
  }) async {
    // Последовательно на аккаунт: SELECT и операция не должны перемешаться с
    // параллельным запросом к другой папке — IMAP-сессия одна на соединение,
    // и чужой SELECT переключит текущую папку посреди работы.
    return _withClient(account, (client) async {
    try {
      final mailbox = await client.selectMailboxByPath(folderId);

      final total = mailbox.messagesExists;
      if (total <= 0) {
        AppLogger.info('IMAP: папка $folderId пуста (total=0)');
        return [];
      }
      final start = total - (page * pageSize) + 1;
      final end = total - ((page - 1) * pageSize);

      if (end < 1) return [];

      final sequence = MessageSequence.fromRange(start.clamp(1, total), end.clamp(1, total));

      FetchImapResult messages;
      try {
        messages = await client.fetchMessages(
          sequence,
          // UID обязателен: id письма строится из него, а действия (прочитано,
          // перенос, удаление) выполняются UID-командами. Без UID в запросе
          // поле оставалось пустым, вместо него брался порядковый номер, и
          // действие применялось к ДРУГОМУ письму.
          '(UID FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE BODY.PEEK[HEADER.FIELDS (REFERENCES IN-REPLY-TO AUTHENTICATION-RESULTS LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST LIST-ID SENSITIVITY X-OGNELISS-CLASSIFICATION X-OGNELISS-HANDLING)])',
        );
      } catch (e) {
        // Некоторые серверы (Яндекс/Mail.ru) капризны к составному FETCH —
        // пробуем упрощённый запрос, чтобы письма всё же загрузились.
        AppLogger.warning('IMAP: расширенный FETCH не прошёл, упрощаю: $e');
        messages = await client.fetchMessages(sequence, '(UID FLAGS ENVELOPE RFC822.SIZE)');
      }

      final result = messages.messages
          .map((msg) => _parseMessage(msg, account.id, folderId))
          .whereType<EmailModel>()
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      AppLogger.info('IMAP: загружено ${result.length} писем из $folderId');
      return result;
    } catch (e) {
      AppLogger.error('IMAP getEmails error ($folderId)', e);
      rethrow;
    }
    });
  }

  static const _listSpec =
      '(UID FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE BODY.PEEK[HEADER.FIELDS (REFERENCES IN-REPLY-TO AUTHENTICATION-RESULTS LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST LIST-ID SENSITIVITY X-OGNELISS-CLASSIFICATION X-OGNELISS-HANDLING)])';

  /// Заголовки писем по последовательности (UID или порядковые номера) с
  /// упрощённым запросом для капризных серверов (Яндекс/Mail.ru).
  Future<List<EmailModel>> _fetchList(
      ImapClient client, MessageSequence seq, AccountModel account, String folderId) async {
    FetchImapResult r;
    try {
      r = seq.isUidSequence
          ? await client.uidFetchMessages(seq, _listSpec)
          : await client.fetchMessages(seq, _listSpec);
    } catch (e) {
      AppLogger.warning('IMAP: расширенный FETCH не прошёл, упрощаю: $e');
      const simple = '(UID FLAGS ENVELOPE RFC822.SIZE)';
      r = seq.isUidSequence
          ? await client.uidFetchMessages(seq, simple)
          : await client.fetchMessages(seq, simple);
    }
    return r.messages
        .map((m) => _parseMessage(m, account.id, folderId))
        .whereType<EmailModel>()
        .toList();
  }

  /// Инкрементальная синхронизация папки по UID (ENGINE_AUDIT P1-11).
  ///
  /// Раньше каждый проход брал 50 последних писем по порядковым номерам: всё
  /// старше пропадало из приложения, флаги и удаления за окном не были видны,
  /// а смена UIDVALIDITY (пересоздание папки) не замечалась.
  ///
  /// Теперь: первый проход — [initial] последних писем; дальше — только
  /// новые (UID больше известного), флаги и наличие писем во всём уже
  /// загруженном диапазоне (один лёгкий FETCH FLAGS) и догрузка истории
  /// порциями по [backfill], пока в папке меньше [keep] писем.
  Future<ImapFolderDelta> syncFolderDelta(
    AccountModel account, {
    required String folderId,
    ImapFolderState? known,
    int initial = 200,
    int backfill = 100,
    int keep = 10000,
  }) {
    return _withClient(account, (client) async {
      final box = await client.selectMailboxByPath(folderId);
      final total = box.messagesExists;
      final validity = box.uidValidity ?? 0;
      final reset = known == null || known.uidValidity != validity || known.maxUid <= 0;
      if (total <= 0) {
        return ImapFolderDelta(
          added: const [], flags: const {}, present: const {},
          state: ImapFolderState(uidValidity: validity, minUid: 0, maxUid: 0),
          reset: reset, empty: true, complete: true,
        );
      }

      if (reset) {
        final start = (total - initial + 1).clamp(1, total);
        final list = await _fetchList(client, MessageSequence.fromRange(start, total), account, folderId);
        final uids = list.map((e) => _uidOf(e.id)).where((u) => u > 0);
        final st = ImapFolderState(
          uidValidity: validity,
          minUid: uids.isEmpty ? 0 : uids.reduce((a, b) => a < b ? a : b),
          maxUid: uids.isEmpty ? 0 : uids.reduce((a, b) => a > b ? a : b),
        );
        AppLogger.info('IMAP $folderId: первичная загрузка — ${list.length} из $total');
        return ImapFolderDelta(
            added: list, flags: const {}, present: uids.toSet(), state: st, reset: true,
            complete: start <= 1);
      }

      // 1. Новые письма: UID больше известного. «n:*» всегда возвращает
      // хотя бы последнее письмо, даже если его UID меньше n, — фильтруем.
      var added = <EmailModel>[];
      final next = box.uidNext;
      if (next == null || next > known.maxUid + 1) {
        added = (await _fetchList(client,
                MessageSequence.fromRangeToLast(known.maxUid + 1, isUidSequence: true), account, folderId))
            .where((e) => _uidOf(e.id) > known.maxUid)
            .toList();
      }

      // 2. Флаги и наличие во всём загруженном диапазоне — только UID и FLAGS.
      final flags = <int, ({bool read, bool flagged})>{};
      final r = await client.uidFetchMessages(
          MessageSequence.fromRange(known.minUid, known.maxUid, isUidSequence: true), '(UID FLAGS)');
      for (final m in r.messages) {
        final uid = m.uid;
        if (uid == null) continue;
        flags[uid] = (
          read: m.flags?.contains(MessageFlags.seen) ?? false,
          flagged: m.flags?.contains(MessageFlags.flagged) ?? false,
        );
      }

      // 3. История: порция писем старше загруженных, пока их немного.
      var minUid = known.minUid;
      var older = <EmailModel>[];
      var complete = known.minUid <= 1;
      final kept = flags.length + added.length;
      if (backfill > 0 && known.minUid > 1 && kept < keep) {
        // Порядковый номер последнего письма старше окна: все письма окна и
        // новые идут подряд в конце папки.
        final seqEnd = total - kept;
        if (seqEnd < 1) complete = true;
        if (seqEnd >= 1) {
          final seqStart = (seqEnd - backfill + 1).clamp(1, seqEnd);
          if (seqStart <= 1) complete = true;
          older = (await _fetchList(client, MessageSequence.fromRange(seqStart, seqEnd), account, folderId))
              .where((e) => _uidOf(e.id) < known.minUid)
              .toList();
          if (older.isNotEmpty) {
            added = [...added, ...older];
            minUid = older.map((e) => _uidOf(e.id)).reduce((a, b) => a < b ? a : b);
          }
        }
      }

      final maxUid = added.isEmpty
          ? known.maxUid
          : [known.maxUid, ...added.map((e) => _uidOf(e.id))].reduce((a, b) => a > b ? a : b);
      return ImapFolderDelta(
        added: added,
        backfilled: older,
        flags: flags,
        present: {...flags.keys, ...added.map((e) => _uidOf(e.id))},
        state: ImapFolderState(uidValidity: validity, minUid: minUid, maxUid: maxUid),
        checkedFrom: known.minUid,
        checkedTo: known.maxUid,
        reset: false,
        complete: complete,
      );
    });
  }

  /// Вернуть вложениям параметры типа, которые MediaType отбрасывает:
  /// ответ на приглашение должен идти как «text/calendar; method=REPLY» —
  /// по этому параметру Outlook и Exchange узнают ответ участника.
  static void _applyPartParams(MimeMessage message,
      List<({String name, String? contentType, Uint8List bytes})> files) {
    for (final a in files) {
      final ct = a.contentType;
      if (ct == null || !ct.contains(';')) continue;
      try {
        // Через dynamic: эти методы enough_mail нигде больше не используются, и
        // при их отсутствии письмо уйдёт как раньше (без параметра), а не
        // сломает сборку.
        final dynamic msg = message;
        for (final dynamic part in msg.allPartsFlat as Iterable) {
          final dynamic disp = part.getHeaderContentDisposition();
          final dynamic type = part.getHeaderContentType();
          final fn = (disp?.filename as String?) ?? ((type?.parameters as Map?)?['name'] as String?);
          if (fn != a.name) continue;
          part.setHeader('Content-Type', '$ct; name="${a.name}"');
        }
      } catch (e) {
        AppLogger.debug('Параметры вложения ${a.name} не заданы: $e');
      }
    }
  }

  static int _uidOf(String id) => int.tryParse(id.substring(id.lastIndexOf(':') + 1)) ?? -1;

  /// Серверный поиск: находит письма вне загруженного окна (старше
  /// нескольких сотен последних). Раньше у IMAP-ящиков (Gmail, Яндекс,
  /// Mail.ru…) искалось только среди писем на телефоне.
  ///
  /// Gmail — по всей почте («Вся почта», X-GM-RAW: тот же синтаксис, что в
  /// веб-интерфейсе, включая текст письма). Остальные — до 12 папок
  /// («Входящие», «Отправленные», «Архив» первыми; без корзины, спама и
  /// черновиков): тема, отправитель, получатели. Возвращает новые письма
  /// первыми. Нужен для писем, которых нет в телефоне (загружена только часть
  /// ящика).
  ///
  /// Кириллица и прочий не-ASCII текст — ЛИТЕРАЛОМ `{N}` с CHARSET UTF-8
  /// (RFC 3501, 6.4.4): в кавычках 8-битный текст сервер принимать не обязан —
  /// Gmail отвечал «BAD Could not parse command» (журнал 09.10.2026).
  /// enough_mail отправляет части команды, разделённые переводом строки,
  /// после приглашения сервера «+» — так и передаётся литерал.
  Future<List<EmailModel>> searchMailbox(AccountModel account, String query, {int limit = 50}) =>
      _withClient(account, (client) async {
        final q = query.replaceAll(RegExp(r'["\\\r\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (q.length < 2) return const <EmailModel>[];
        final boxes = (await client.listMailboxes(recursive: true))
            .where((b) => !b.flags.contains(MailboxFlag.noSelect))
            .toList();
        final domain = account.email.split('@').last.toLowerCase();
        final gmail = account.type == AccountType.google || domain == 'gmail.com' || domain == 'googlemail.com';
        final allMail = gmail ? boxes.where((b) => b.flags.contains(MailboxFlag.all)).firstOrNull : null;
        bool skip(Mailbox b) => b.isTrash || b.isJunk || b.isDrafts;
        final targets = allMail != null
            ? [allMail]
            : [
                ...boxes.where((b) => b.isInbox),
                ...boxes.where((b) => b.isSent || b.isArchive),
                ...boxes.where((b) => !b.isInbox && !b.isSent && !b.isArchive && !skip(b)),
              ].take(12).toList();
        final ascii = q.codeUnits.every((c) => c < 128);
        final variants = imapSearchVariants(q, gmail: allMail != null);
        if (!ascii) AppLogger.debug('IMAP поиск: запрос не латиницей — литералом, CHARSET UTF-8');
        final out = <EmailModel>[];
        for (final box in targets) {
          try {
            await client.selectMailbox(box);
            SearchImapResult? found;
            Object? lastError;
            for (final v in [...variants]) {
              try {
                found = await client.uidSearchMessages(searchCriteria: v);
                variants
                  ..clear()
                  ..add(v);
                break;
              } catch (e) {
                lastError = e;
              }
            }
            if (found == null) throw lastError ?? StateError('SEARCH не выполнен');
            final seq = found.matchingSequence;
            if (seq == null || seq.isEmpty) continue;
            final uids = seq.toList()..sort();
            final last = uids.length > limit ? uids.sublist(uids.length - limit) : uids;
            final fetch = MessageSequence(isUidSequence: true);
            for (final u in last) {
              fetch.add(u);
            }
            out.addAll(await _fetchList(client, fetch, account, box.encodedPath));
          } catch (e) {
            AppLogger.warning('IMAP поиск в ${box.name}: $e');
          }
        }
        out.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
        AppLogger.info('IMAP поиск: папок ${targets.length}, найдено ${out.length}');
        return out.length > limit ? out.sublist(0, limit) : out;
      });

  /// Получить полное тело письма
  Future<EmailModel?> getEmailDetail(AccountModel account,
      {required String folderId,
      required int uid,
      EmailFetchMode fetchMode = EmailFetchMode.noAttachments}) async {
    // Последовательно на аккаунт: SELECT+операция не должны перемешаться
    // с параллельным запросом к другой папке (см. _withAccountLock).
    return _withClient(account, (client) async {
    try {
      await client.selectMailboxByPath(folderId);

      final sequence = MessageSequence.fromId(uid, isUid: true);

      // ЧТО именно просим у сервера — зависит от режима загрузки.
      // Раньше здесь всегда стоял BODY[] — «всё сообщение целиком, включая
      // вложения». Письмо с вложением на 20 МБ незаметно качало 20 МБ, а при
      // нажатии на вложение качало его ВТОРОЙ раз. Именно это и обещает
      // предотвращать режим «без вложений» (он по умолчанию).
      //
      // ВАЖНО: этот метод вызывается, когда пользователь ОТКРЫЛ письмо — тело
      // нужно ВСЕГДА. Поэтому headersOnly здесь не означает «не грузить тело»:
      // режим экономит трафик на СПИСКЕ (там и так тянутся только заголовки), а
      // открытое письмо обязано показать текст. Иначе экран был бы пустым.
      final String fetchSpec;
      switch (fetchMode) {
        case EmailFetchMode.full:
          fetchSpec = '(UID FLAGS ENVELOPE BODY.PEEK[] RFC822.SIZE)';
          break;
        // Частичные режимы прежде запрашивали BODY.PEEK[]<0.N>: сервер
        // отвечает «BODY[]<0>», а разборщик enough_mail такой ключ не
        // принимает — тело терялось. Тексты письма малы и без вложений,
        // поэтому все режимы, кроме «целиком», берут структуру и только
        // текстовые части.
        case EmailFetchMode.partial500k:
        case EmailFetchMode.partial100k:
        case EmailFetchMode.partial50k:
        case EmailFetchMode.headersOnly:
        case EmailFetchMode.noAttachments:
          fetchSpec = '(UID FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE)';
          break;
      }

      final messages = await client.uidFetchMessages(sequence, fetchSpec);

      if (messages.messages.isEmpty) return null;

      final msg = messages.messages.first;

      final email = _parseMessage(msg, account.id, folderId);

      if (email == null) return null;

      String? bodyHtml;
      String? bodyPlain;

      if (fetchMode != EmailFetchMode.full) {
        // Письмо без вложений: по структуре тянем только text/html и
        // text/plain — вложения остаются на сервере до явного запроса.
        final texts = await _fetchTextBodies(client, sequence, msg);
        bodyHtml = texts.html;
        bodyPlain = texts.plain;
      } else {
        // Письмо целиком (BODY[]): enough_mail сам разбирает MIME и charset.
        try { bodyHtml = msg.decodeTextHtmlPart(); } catch (_) {}
        try { bodyPlain = msg.decodeTextPlainPart(); } catch (_) {}
      }

      // 2) Fallback: через реконструкцию MIME, если напрямую пусто
      if ((bodyHtml == null || bodyHtml.isEmpty) && (bodyPlain == null || bodyPlain.isEmpty)) {
        try {
          final mime = msg.decodeContentMessage();
          if (mime != null) {
            bodyHtml ??= mime.decodeTextHtmlPart();
            bodyPlain ??= mime.decodeTextPlainPart();
          }
        } catch (_) {}
      }

      // 3) Последний fallback: plain-часть ещё раз (на случай гонок декодера)
      if ((bodyHtml == null || bodyHtml.isEmpty) && (bodyPlain == null || bodyPlain.isEmpty)) {
        try { bodyPlain = msg.decodeTextPlainPart(); } catch (_) {}
      }

      // Вложения
      final attachments = <EmailAttachment>[];
      final structure = msg.body;
      if (structure != null) {
        _collectAttachments(structure, attachments);
      }

      return email.copyWith(
        bodyHtml: bodyHtml,
        bodyPlain: bodyPlain,
        attachments: attachments,
      );
    } catch (e) {
      AppLogger.error('IMAP getEmailDetail error', e);
      rethrow;
    }
  });
  }

  // ignore: unused_element
  String _extractCharset(MimeMessage mime, String contentType) {
    try {
      final ct = mime.getHeaderValue('content-type') ?? '';
      return CharsetHandler.detectCharset(ct);
    } catch (_) {
      return 'utf-8';
    }
  }

  /// Имя из конверта: битое при раскодировании («Ол�» — закодированное
  /// слово разорвано посреди буквы) не сохраняем — подставится имя из
  /// контактов (1.6.33).
  static String? _cleanName(String? n) => (n == null || n.contains('\uFFFD')) ? null : n;

  /// Имя вложения: почтовые программы (Mail.ru, Outlook) кодируют
  /// кириллицу по RFC 2047 — «=?UTF-8?B?…?=». Прежде имя показывалось как есть.
  static String? _decodeFileName(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    if (v.length > 1 && v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
    if (!v.contains('=?')) return v;
    try {
      // decodeHeader сам склеивает соседние закодированные слова.
      final d = MailCodec.decodeHeader(v);
      return (d == null || d.isEmpty) ? v : d;
    } catch (_) {
      return v;
    }
  }

  void _collectAttachments(BodyPart part, List<EmailAttachment> result) {
    final top = part.contentType?.mediaType.top;
    final isAttachment = part.contentDisposition?.disposition == ContentDisposition.attachment ||
        (part.contentType?.mediaType.sub == MediaSubtype.applicationOctetStream);
    // Встроенная часть с Content-ID (картинка в подписи/теле, на которую
    // ссылается HTML как cid:) — прежде не собиралась вовсе, и картинки
    // в письмах были «битыми».
    final isInlineWithCid = !isAttachment &&
        part.cid != null &&
        top != MediaToptype.text &&
        top != MediaToptype.multipart;
    // Приглашение на встречу внутри письма (text/calendar в multipart/
    // alternative, как шлют Outlook и Яндекс) — как встроенное вложение,
    // чтобы карточка приглашения могла его прочитать и ответить.
    final isCalendar = !isAttachment &&
        (part.contentType?.mediaType.text.toLowerCase().startsWith('text/calendar') ?? false) &&
        !result.any((a) => a.mimeType.toLowerCase().contains('calendar'));
    if (isAttachment || isInlineWithCid || isCalendar) {
      result.add(EmailAttachment(
        id: part.fetchId ?? part.contentType?.parameters['name'] ?? '',
        name: _decodeFileName(part.contentDisposition?.filename ?? part.contentType?.parameters['name']) ??
            (isInlineWithCid ? 'image' : (isCalendar ? 'invite.ics' : 'attachment')),
        mimeType: part.contentType?.mediaType.text ?? 'application/octet-stream',
        size: part.size ?? 0,
        isInline: isInlineWithCid || isCalendar || part.contentDisposition?.disposition == ContentDisposition.inline,
        contentId: EmailAttachment.normalizeCid(part.cid),
      ));
    }

    if (part.parts != null) {
      for (final child in part.parts!) {
        _collectAttachments(child, result);
      }
    }
  }

  EmailModel? _parseMessage(MimeMessage msg, String accountId, String folderId) {
    try {
      final envelope = msg.envelope;
      if (envelope == null) return null;

      final uid = msg.uid;
      if (uid == null) return null; // без UID письмо нельзя адресовать
      final from = envelope.from?.isNotEmpty == true
          ? EmailAddress(email: envelope.from!.first.email, displayName: _cleanName(envelope.from!.first.personalName))
          : const EmailAddress(email: '');

      final to = (envelope.to ?? []).map((a) => EmailAddress(email: a.email, displayName: _cleanName(a.personalName))).toList();
      final cc = (envelope.cc ?? []).map((a) => EmailAddress(email: a.email, displayName: _cleanName(a.personalName))).toList();
      final replyTo =
          (envelope.replyTo ?? []).map((a) => EmailAddress(email: a.email, displayName: _cleanName(a.personalName))).toList();

      final subject = envelope.subject != null
          ? CharsetHandler.decodeMimeEncodedWord(envelope.subject!)
          : '';

      final isRead = msg.flags?.contains(MessageFlags.seen) ?? false;
      final isFlagged = msg.flags?.contains(MessageFlags.flagged) ?? false;
      final isReplied = msg.flags?.contains(MessageFlags.answered) ?? false;

      final dateReceived = envelope.date ?? DateTime.now();
      final messageId = envelope.messageId;
      final inReplyTo = msg.getHeaderValue('in-reply-to');
      final references = msg.getHeaderValue('references');
      final authResults = msg.getHeaderValue('authentication-results') ?? msg.getHeaderValue('received-spf');
      // Пометка Outlook и гриф в MIME (X-Ogneliss-*) — одной строкой, см. MailLabel.
      final sensitivity = MailLabel.fromHeaders(
        sensitivity: msg.getHeaderValue('sensitivity'),
        classification: msg.getHeaderValue('x-ogneliss-classification'),
        handling: msg.getHeaderValue('x-ogneliss-handling'),
      );
      // Рассылка: как отписаться (RFC 2369) и «в одно нажатие» (RFC 8058).
      final listUnsubscribe = encodeListUnsubscribe(
        unsubscribe: msg.getHeaderValue('list-unsubscribe'),
        post: msg.getHeaderValue('list-unsubscribe-post'),
        listId: msg.getHeaderValue('list-id'),
      );

      final size = msg.size;

      // Preview
      String? preview;
      try {
        final text = msg.decodeTextPlainPart();
        if (text != null) {
          // Без сущностей HTML и невидимых символов прехедера рассылок:
          // иначе первые 200 знаков бывали сплошным «&zwnj; &zwnj; …».
          preview = previewKeepingLines(text);
        }
      } catch (_) {}

      return EmailModel(
        // UID уникален только внутри папки → делаем глобально-уникальный id
        // вида "folderId:uid", иначе письма из разных папок с одинаковым UID
        // конфликтуют по первичному ключу {id, accountId}.
        id: '$folderId:$uid',
        accountId: accountId,
        folderId: folderId,
        internetMessageId: messageId,
        references: references?.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
        conversationId: imapConversationId(references, inReplyTo, messageId),
        from: from,
        to: to,
        cc: cc,
        replyTo: replyTo,
        subject: subject,
        bodyPreview: preview,
        authResults: authResults,
        listUnsubscribe: listUnsubscribe,
        receivedAt: dateReceived,
        isRead: isRead,
        isFlagged: isFlagged,
        isReplied: isReplied,
        hasAttachments: msg.body?.parts?.any((p) =>
            p.contentDisposition?.disposition == ContentDisposition.attachment) ?? false,
        size: size,
        sensitivity: sensitivity,
      );
    } catch (e) {
      AppLogger.warning('IMAP parse message error: $e');
      return null;
    }
  }

  /// Тексты письма по структуре BODYSTRUCTURE: первая text/html и первая
  /// text/plain часть, не являющиеся вложением.
  ///
  /// Раньше обход шёл по MimePart.parts, а после FETCH BODYSTRUCTURE это поле
  /// пустое (структура лежит в msg.body — дереве BodyPart). Поэтому всегда
  /// скачивалась только часть «1»: у multipart/alternative (почти вся почта
  /// Gmail) это text/plain без HTML, у multipart/mixed — вложенный multipart
  /// без текста, у одночастного text/html — данные без заголовков, которые
  /// никто не декодировал. Итог — «тело письма не отображается».
  ///
  /// Теперь номер части берётся из дерева BodyPart, а кодировка передачи и
  /// charset — из той же структуры: часть, скачанная отдельно, своих
  /// заголовков не содержит.
  Future<({String? html, String? plain})> _fetchTextBodies(
    ImapClient client,
    MessageSequence sequence,
    MimeMessage msg,
  ) async {
    final found = <({String id, bool html, String? encoding, String? charset})>[];
    void walk(BodyPart part) {
      final ct = part.contentType;
      final top = ct?.mediaType.top;
      final sub = ct?.mediaType.sub;
      if (top == MediaToptype.multipart) {
        for (final child in part.parts ?? const <BodyPart>[]) {
          walk(child);
        }
        return;
      }
      // Вложенное письмо (message/rfc822) — вложение, его текст не наш.
      if (sub == MediaSubtype.messageRfc822) return;
      if (part.contentDisposition?.disposition == ContentDisposition.attachment) return;
      if (sub == MediaSubtype.textHtml || sub == MediaSubtype.textPlain) {
        // У одночастного письма корень без родителя: fetchId == null, а тело —
        // часть «1» (RFC 3501, 6.4.5).
        found.add((
          id: part.fetchId ?? '1',
          html: sub == MediaSubtype.textHtml,
          encoding: part.encoding,
          charset: ct?.charset,
        ));
      }
    }

    final root = msg.body;
    if (root != null) walk(root);
    // Структура не пришла (редкие серверы) — пробуем часть «1» как текст.
    if (found.isEmpty) found.add((id: '1', html: false, encoding: null, charset: null));

    final html = found.where((t) => t.html).firstOrNull;
    final plain = found.where((t) => !t.html).firstOrNull;
    final wanted = [if (html != null) html, if (plain != null) plain];
    try {
      final spec = '(${wanted.map((t) => 'BODY.PEEK[${t.id}]').join(' ')})';
      final res = await client.uidFetchMessages(sequence, spec);
      if (res.messages.isEmpty) return (html: null, plain: null);
      final loaded = res.messages.first;
      String? decode(({String id, bool html, String? encoding, String? charset})? t) {
        if (t == null) return null;
        final data = loaded.getPart(t.id)?.mimeData;
        try {
          if (data is TextMimeData) return MailCodec.decodeAnyText(data.text, t.encoding, t.charset);
          if (data is BinaryMimeData) return MailCodec.decodeAsText(data.data, t.encoding, t.charset);
        } catch (e) {
          AppLogger.debug('IMAP: часть ${t.id} не декодирована — $e');
        }
        return null;
      }

      return (html: decode(html), plain: decode(plain));
    } catch (e) {
      AppLogger.warning('IMAP: не удалось загрузить текст письма — $e');
      return (html: null, plain: null);
    }
  }

  // ════════════════════════ IDLE (PUSH) ════════════════════════
  //
  // IDLE занимает соединение ПОСТОЯННО. Поэтому у него СВОЙ клиент на аккаунт:
  //  · на общем клиенте IDLE блокировал бы обычные операции (или конфликтовал
  //    с их SELECT — см. _withAccountLock);
  //  · состояние — на аккаунт, а не глобальный флаг: раньше `bool _isIdling`
  //    был один на весь сервис, поэтому IDLE работал бы лишь для ОДНОГО ящика;
  //  · при обрыве переподключаем ТОЛЬКО idle-клиент, не трогая общий пул
  //    (раньше ошибка IDLE выбрасывала из пула общий клиент, ломая чужие
  //    операции).

  final Map<String, ImapClient> _idleClients = {};

  /// Номер цикла IDLE ящика (1.6.44). Раньше признаком «слушаем» был общий
  /// набор ящиков: остановленный цикл, который в этот момент подключался,
  /// после перезапуска push видел флаг НОВОГО цикла и продолжал работать —
  /// два цикла на одном ящике делили одно соединение и роняли друг друга.
  /// Теперь цикл работает, пока номер ящика — его собственный.
  final Map<String, int> _idleGen = {};
  int _idleSeq = 0;

  /// «Толчок» циклу IDLE ящика: завершить текущее ожидание и проверить связь.
  final Map<String, StreamController<void>> _idlePokes = {};

  /// Плановый перезапуск IDLE. Было 20 минут: NAT мобильных операторов
  /// забывает молчащее соединение и за 10 минут, после чего сервер уже не
  /// может сообщить о письме, а приложение об обрыве не знает.
  static const _idleCycle = Duration(minutes: 9);

  /// Таймаут ответа на команды IDLE-соединения. У IDLE-клиента нет общего
  /// таймаута (IDLE по определению ждёт долго), поэтому раньше DONE/NOOP на
  /// оборванном соединении ждали ВЕЧНО: цикл стоял, push молчал до
  /// перезапуска приложения. Это и был «push через какое-то время пропадает».
  static const _idleStep = Duration(seconds: 30);

  /// Разбудить IDLE ящика: прервать ожидание, выполнить DONE + NOOP (с
  /// таймаутом) и начать заново; мёртвое соединение при этом обнаружится и
  /// переподключится. Зовёт сторож push — по будильнику ОС, при смене сети,
  /// при возврате в приложение. В глубоком сне собственный таймер цикла не
  /// срабатывает, будит только будильник.
  void pokeIdle(String accountId) {
    final c = _idlePokes[accountId];
    if (c != null && !c.isClosed) c.add(null);
  }

  /// Закрыть IDLE-соединение, не дожидаясь мёртвого сокета.
  static Future<void> _closeIdleClient(ImapClient? c) async {
    if (c == null) return;
    try { await c.logout().timeout(const Duration(seconds: 5)); } catch (_) {}
    try { await c.disconnect(); } catch (_) {}
  }

  /// Push для папки: поток отдаёт число писем в папке при EXISTS, -1 при
  /// EXPUNGE и -2 после переподключения (письма, пришедшие за время обрыва,
  /// IDLE не сообщит — их забирает синхронизация папки).
  /// Держится сам: при обрыве переподключается с растущей паузой (15 с → 10 мин).
  /// Отказ во входе — поток завершается ошибкой [PushAuthFailure]: повторять
  /// вход с неверным паролем нельзя (раньше — каждые 15 с, бесконечно).
  ///
  /// Остановка — [stopIdle] (номер цикла снимается, ожидание прерывается):
  /// отмена подписки на async*-поток сама по себе срабатывает лишь на
  /// следующем yield, то есть при следующем письме.
  Stream<int> startIdle(AccountModel account, String folderId) async* {
    if (_idleGen.containsKey(account.id)) return; // уже слушаем этот ящик
    final gen = ++_idleSeq;
    _idleGen[account.id] = gen;
    bool alive() => _idleGen[account.id] == gen;
    final poke = StreamController<void>.broadcast();
    _idlePokes[account.id] = poke;
    AppLogger.info('IMAP IDLE: старт ${account.email} / $folderId');
    var failures = 0;
    var connectedOnce = false;
    // Соединение этого цикла (в _idleClients — только пока цикл свой).
    ImapClient? client;

    Future<void> drop() async {
      final c = client;
      client = null;
      if (c != null && identical(_idleClients[account.id], c)) _idleClients.remove(account.id);
      await _closeIdleClient(c);
    }

    try {
      while (alive()) {
        try {
          var c = client;
          var fresh = false;
          if (c == null || !c.isLoggedIn) {
            if (c != null) await drop();
            c = await _connectAndLogin(account, forIdle: true) // ОТДЕЛЬНОЕ соединение
                .timeout(const Duration(seconds: 60));
            if (!alive()) {
              // Остановили, пока подключались, — соединение не нужно.
              await _closeIdleClient(c);
              break;
            }
            client = c;
            _idleClients[account.id] = c;
            fresh = true;
          }
          await c.selectMailboxByPath(folderId).timeout(_idleStep);
          await c.idleStart().timeout(_idleStep);
          markPushAlive(account.id);
          if (fresh && connectedOnce) {
            AppLogger.info('IMAP IDLE (${account.email}): переподключён — догоняем пропущенное');
            yield -2;
          }
          connectedOnce = true;

          // Ждём событие сервера, плановый перезапуск или «толчок» сторожа.
          final wake = StreamController<ImapEvent?>();
          final subs = <StreamSubscription<dynamic>>[
            c.eventBus.on<ImapEvent>().listen((e) {
              if (!wake.isClosed) wake.add(e);
            }),
            poke.stream.listen((_) {
              if (!wake.isClosed) wake.add(null);
            }),
          ];
          final cycle = Timer(_idleCycle, () {
            if (!wake.isClosed) wake.add(null);
          });
          try {
            await for (final event in wake.stream) {
              if (event == null || !alive()) break;
              markPushAlive(account.id);
              if (event is ImapMessagesExistEvent) {
                AppLogger.info('IMAP IDLE: новое письмо (EXISTS ${event.newMessagesExists})');
                yield event.newMessagesExists;
              } else if (event is ImapExpungeEvent) {
                AppLogger.info('IMAP IDLE: письмо удалено (EXPUNGE)');
                yield -1;
              }
            }
          } finally {
            cycle.cancel();
            for (final sub in subs) {
              await sub.cancel();
            }
            await wake.close();
          }
          // Перезапуск: DONE и NOOP с таймаутом — заодно проверка, что
          // соединение живо. Мёртвое даст TimeoutException → переподключение.
          if (alive()) {
            await c.idleDone().timeout(_idleStep);
            await c.noop().timeout(_idleStep);
            markPushAlive(account.id);
          }
          failures = 0; // цикл IDLE прошёл целиком — связь в порядке
        } catch (e) {
          // Роняем ТОЛЬКО idle-соединение этого цикла; общий пул не трогаем.
          await drop();
          if (!alive()) break;
          if (looksLikeAuthError(e)) {
            AppLogger.warning('IMAP IDLE (${account.email}): отказ во входе — push остановлен');
            throw const PushAuthFailure();
          }
          failures++;
          final pause = (15 << (failures - 1).clamp(0, 6)).clamp(15, 600);
          AppLogger.warning('IMAP IDLE (${account.email}): обрыв — $e; повтор через $pause с');
          // Пауза прерывается «толчком»: сменилась сеть или сработал будильник —
          // нет смысла ждать до 10 минут.
          await Future.any([
            Future<void>.delayed(Duration(seconds: pause)),
            poke.stream.first.catchError((Object _) {}),
          ]);
          markPushAlive(account.id); // пауза — штатное состояние, не зависание
        }
      }
    } finally {
      if (alive()) _idleGen.remove(account.id);
      if (identical(_idlePokes[account.id], poke)) _idlePokes.remove(account.id);
      await poke.close();
      await drop();
      AppLogger.info('IMAP IDLE: остановлен ${account.email}');
    }
  }

  /// Остановить IDLE конкретного ящика: цикл выходит из ожидания сразу, не
  /// дожидаясь события сервера.
  Future<void> stopIdle(String accountId) async {
    _idleGen.remove(accountId);
    pokeIdle(accountId); // выйти из ожидания, не дожидаясь события
    final client = _idleClients.remove(accountId);
    if (client == null) return;
    try {
      await client.idleDone().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _closeIdleClient(client);
  }

  /// Остановить IDLE всех ящиков (выход из приложения, смена аккаунтов).
  Future<void> stopAllIdle() async {
    for (final id in _idleGen.keys.toList()) {
      await stopIdle(id);
    }
  }

  // ════════════════════════ SEND ════════════════════════

  /// Письмо целиком (BODY.PEEK[], флаг «прочитано» не меняется) — для
  /// проверки подписи S/MIME.
  Future<Uint8List?> fetchRawMessage(AccountModel account,
      {required String folderId, required int uid}) async {
    return _withClient<Uint8List?>(account, (client) async {
      await client.selectMailboxByPath(folderId);
      final r = await client.uidFetchMessages(MessageSequence.fromId(uid, isUid: true), '(BODY.PEEK[])');
      final m = r.messages.firstOrNull;
      if (m == null) return null;
      return Uint8List.fromList(utf8.encode(m.renderMessage()));
    });
  }

  /// Исходящее письмо (MIME) — общее для SMTP и для отправки готовым
  /// текстом через EWS (S/MIME): текст и HTML, вложения, цепочка, важность,
  /// гриф.
  static MimeMessage buildOutgoingMessage({
    required String fromName,
    required String fromEmail,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
  }) {
    final files = attachments.where((a) => a.bytes.isNotEmpty).toList();
    final plain = bodyHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();

    // С вложениями — multipart/mixed, внутри которого multipart/alternative
    // (текст + HTML) и файлы. Раньше файлы добавлялись прямо в
    // multipart/alternative: почтовые программы считали вложение «ещё одним
    // вариантом текста» и показывали его вместо письма либо прятали.
    final MessageBuilder builder;
    if (files.isEmpty) {
      builder = MessageBuilder.prepareMultipartAlternativeMessage(
          plainText: plain, htmlText: bodyHtml);
    } else {
      builder = MessageBuilder.prepareMultipartMixedMessage()
        ..addMultipartAlternative(plainText: plain, htmlText: bodyHtml);
      for (final a in files) {
        // Параметры типа («; method=REPLY») — отдельно: MediaType их не хранит.
        final type = (a.contentType != null && a.contentType!.isNotEmpty)
            ? MediaType.fromText(a.contentType!.split(';').first.trim())
            : MediaType.guessFromFileName(a.name);
        builder.addBinary(a.bytes, type, filename: a.name);
      }
    }
    builder.from = [MailAddress(fromName, fromEmail)];
    builder.to = to.map((a) => MailAddress(a.displayName, a.email)).toList();
    if (cc.isNotEmpty) builder.cc = cc.map((a) => MailAddress(a.displayName, a.email)).toList();
    if (bcc.isNotEmpty) builder.bcc = bcc.map((a) => MailAddress(a.displayName, a.email)).toList();
    builder.subject = subject;

    final thread = replyThreadHeaders(inReplyTo);
    if (thread != null) {
      builder.setHeader('In-Reply-To', thread.inReplyTo);
      builder.setHeader('References', thread.references);
    }
    if (importance == 'High') {
      builder.setHeader('Importance', 'High');
      builder.setHeader('X-Priority', '1');
    } else if (importance == 'Low') {
      builder.setHeader('Importance', 'Low');
      builder.setHeader('X-Priority', '5');
    }
    // Гриф: пометка Outlook и заголовки Ogneliss (гриф в MIME, MailLabel).
    final label = MailLabel.decode(sensitivity);
    if (label.outlook == 'Personal') {
      builder.setHeader('Sensitivity', 'Personal');
    } else if (label.outlook == 'Private') {
      builder.setHeader('Sensitivity', 'Private');
    } else if (label.outlook == 'Confidential') {
      builder.setHeader('Sensitivity', 'Company-Confidential');
    }
    label.headers.forEach((k, v) => builder.setHeader(k, v));

    final message = builder.buildMimeMessage();
    _applyPartParams(message, files);
    applyAddressHeaders(message,
        fromName: fromName,
        fromEmail: fromEmail,
        to: [for (final a in to) (name: a.displayName, email: a.email)],
        cc: [for (final a in cc) (name: a.displayName, email: a.email)]);
    return message;
  }

  Future<void> sendEmail(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    /// S/MIME: обработка готового письма перед отправкой (подпись,
    /// шифрование). Письмо тогда уходит готовым текстом.
    Future<Uint8List> Function(Uint8List mime)? mimeTransform,
    /// Адрес отправки (псевдоним, 1.6.27); null — адрес ящика.
    EmailAddress? from,
  }) async {
    final message = buildOutgoingMessage(
      fromName: from == null ? account.displayName : (from.displayName ?? ''),
      fromEmail: from?.email ?? account.email,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyHtml: bodyHtml,
      inReplyTo: inReplyTo,
      attachments: attachments,
      importance: importance,
      sensitivity: sensitivity,
    );
    // S/MIME: письмо собрано — подписываем/шифруем его текст и отправляем
    // как есть (заголовок Bcc получателям не уходит, адреса — в конверте).
    String? protectedText;
    if (mimeTransform != null) {
      var raw = Uint8List.fromList(utf8.encode(message.renderMessage()));
      raw = SmimeMime.withoutHeaders(raw, const {'bcc'});
      raw = await mimeTransform(raw);
      protectedText = utf8.decode(raw, allowMalformed: true);
    }
    final client = await _openSmtp(account);
    try {
      if (protectedText != null) {
        await client.sendMessageText(
          protectedText,
          MailAddress(from == null ? account.displayName : (from.displayName ?? ''), from?.email ?? account.email),
          [for (final a in [...to, ...cc, ...bcc]) MailAddress(a.displayName, a.email)],
          use8BitEncoding: client.serverInfo.supports8BitMime,
        );
      } else {
        await client.sendMessage(message,
            use8BitEncoding: client.serverInfo.supports8BitMime);
      }
      AppLogger.info('SMTP sent: $subject');
    } catch (e) {
      AppLogger.error('SMTP send error', e);
      rethrow;
    } finally {
      try { await client.quit(); } catch (_) {}
    }

    // Копия в «Отправленные». Gmail, Яндекс, Mail.ru и Yahoo кладут её сами;
    // обычный IMAP-сервер — нет, и отправленные письма «исчезали».
    if (account.type == AccountType.imap) {
      try {
        var appending = false;
        await _withClient(account, canRetry: () => !appending, (c) async {
          final boxes = await c.listMailboxes(recursive: true);
          final sent = boxes.where((b) => b.isSent).firstOrNull;
          if (sent == null) return;
          appending = true;
          final text = protectedText;
          if (text != null) {
            await c.appendMessageText(text,
                flags: [MessageFlags.seen],
                targetMailboxPath: _pathForEnoughMail(c, sent.encodedPath));
          } else {
            await c.appendMessage(message,
                flags: [MessageFlags.seen],
                targetMailboxPath: _pathForEnoughMail(c, sent.encodedPath));
          }
        });
      } catch (e) {
        AppLogger.warning('IMAP: копия в «Отправленные» не сохранена — $e');
      }
    }
  }

  // ════════════════════════ DRAFTS ════════════════════════

  /// Сохранить черновик в серверную папку «Черновики» (APPEND с флагом
  /// \Draft): его видно в веб-почте и других программах. [messageId] —
  /// заголовок Message-ID, по нему потом находится и удаляется прежняя копия.
  /// Возвращает путь папки черновиков или null, если её на сервере нет.
  /// [attachments] — файлы черновика (1.7.2+111): как у отправки,
  /// multipart/mixed с текстом и файлами.
  Future<String?> saveDraft(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    required String messageId,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
  }) async {
    final plain = bodyHtml
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
    final files = attachments.where((a) => a.bytes.isNotEmpty).toList();
    final MessageBuilder builder;
    if (files.isEmpty) {
      builder = MessageBuilder.prepareMultipartAlternativeMessage(plainText: plain, htmlText: bodyHtml);
    } else {
      builder = MessageBuilder.prepareMultipartMixedMessage()
        ..addMultipartAlternative(plainText: plain, htmlText: bodyHtml);
      for (final a in files) {
        final type = (a.contentType != null && a.contentType!.isNotEmpty)
            ? MediaType.fromText(a.contentType!.split(';').first.trim())
            : MediaType.guessFromFileName(a.name);
        builder.addBinary(a.bytes, type, filename: a.name);
      }
    }
    builder.from = [MailAddress(account.displayName, account.email)];
    if (to.isNotEmpty) builder.to = to.map((a) => MailAddress(a.displayName, a.email)).toList();
    if (cc.isNotEmpty) builder.cc = cc.map((a) => MailAddress(a.displayName, a.email)).toList();
    if (bcc.isNotEmpty) builder.bcc = bcc.map((a) => MailAddress(a.displayName, a.email)).toList();
    builder.subject = subject;
    builder.setHeader('Message-ID', messageId);
    final message = builder.buildMimeMessage();
    applyAddressHeaders(message,
        fromName: account.displayName,
        fromEmail: account.email,
        to: [for (final a in to) (name: a.displayName, email: a.email)],
        cc: [for (final a in cc) (name: a.displayName, email: a.email)]);
    var appending = false;
    return _withClient(account, canRetry: () => !appending, (c) async {
      final boxes = await c.listMailboxes(recursive: true);
      final drafts = boxes.where((b) => b.isDrafts).firstOrNull;
      if (drafts == null) return null;
      final path = _pathForEnoughMail(c, drafts.encodedPath);
      appending = true;
      await c.appendMessage(message,
          flags: [MessageFlags.draft, MessageFlags.seen], targetMailboxPath: path);
      return drafts.encodedPath;
    });
  }

  /// Удалить из «Черновиков» письма с заданным Message-ID (прежние копии
  /// черновика, ещё не попавшие в локальную базу).
  Future<void> deleteDraftByMessageId(AccountModel account, String messageId) async {
    await _withClient(account, (c) async {
      final boxes = await c.listMailboxes(recursive: true);
      final drafts = boxes.where((b) => b.isDrafts).firstOrNull;
      if (drafts == null) return;
      await c.selectMailboxByPath(_pathForEnoughMail(c, drafts.encodedPath));
      final found = await c.uidSearchMessages(
          searchCriteria: 'HEADER Message-ID "${messageId.replaceAll('"', '')}"');
      final seq = found.matchingSequence;
      if (seq == null || seq.isEmpty) return;
      await c.uidStore(seq, [MessageFlags.deleted], action: StoreAction.add, silent: true);
      // Без UIDPLUS EXPUNGE удалил бы и чужие помеченные письма папки —
      // тогда копия остаётся помеченной, сервер уберёт её сам.
      if (c.serverInfo.supportsUidPlus) await c.uidExpunge(seq);
    });
  }

  // ════════════════════════ ЗАМЕТКИ IMAP (1.6.2) ════════════════════════
  // Заметки в папке «Notes» в формате Apple Notes: так их хранят «Заметки»
  // iPhone и Mac для ящиков Gmail, Яндекса, iCloud и любого IMAP. Каждая
  // заметка — письмо с заголовками X-Uniform-Type-Identifier:
  // com.apple.mail-note и X-Universally-Unique-Identifier (постоянный id:
  // при правке Apple кладёт новое письмо и удаляет старое — UID меняется).

  static const noteUti = 'com.apple.mail-note';
  static const _noteUuidHeader = 'X-Universally-Unique-Identifier';

  Future<Mailbox?> _notesBox(ImapClient c, {bool create = false}) async {
    final boxes = await c.listMailboxes(recursive: true);
    final found = boxes.where((b) {
      final n = b.name.toLowerCase();
      return n == 'notes' || n == 'заметки';
    }).firstOrNull;
    if (found != null || !create) return found;
    return c.createMailbox('Notes');
  }

  /// Заметки ящика: null — папки «Notes» нет (заметок на сервере нет).
  Future<List<({String uuid, String title, String body, DateTime modified})>?> getImapNotes(
      AccountModel account, {int max = 500}) {
    return _withClient(account, (c) async {
      final box = await _notesBox(c);
      if (box == null) return null;
      final sel = await c.selectMailboxByPath(_pathForEnoughMail(c, box.encodedPath));
      final total = sel.messagesExists;
      if (total <= 0) return const <({String uuid, String title, String body, DateTime modified})>[];
      final seq = MessageSequence.fromRange((total - max + 1).clamp(1, total), total);
      final r = await c.fetchMessages(seq, '(UID FLAGS BODY.PEEK[])');
      final out = <({String uuid, String title, String body, DateTime modified})>[];
      final seen = <String>{};
      // Новые — в конце папки: идём с конца, чтобы при дублях одной заметки
      // (правка с другого устройства ещё не удалила старую) взять свежую.
      for (final m in r.messages.reversed) {
        if (m.flags?.contains(MessageFlags.deleted) ?? false) continue;
        final uuid = (m.getHeaderValue(_noteUuidHeader) ??
                m.getHeaderValue('message-id') ??
                'uid:${m.uid}')
            .trim();
        if (!seen.add(uuid)) continue;
        String body = '';
        try {
          final html = m.decodeTextHtmlPart();
          body = (html != null && html.trim().isNotEmpty)
              ? noteHtmlToText(html)
              : (m.decodeTextPlainPart() ?? '').trim();
        } catch (_) {}
        out.add((
          uuid: uuid,
          title: (m.decodeSubject() ?? '').trim(),
          body: body,
          modified: m.decodeDate() ?? DateTime.now(),
        ));
      }
      return out;
    });
  }

  /// Создать или изменить заметку: новое письмо в «Notes», прежняя копия
  /// (тот же UUID) удаляется. Возвращает UUID заметки.
  Future<String> saveImapNote(AccountModel account,
      {String? uuid, required String title, required String body}) async {
    final id = (uuid == null || uuid.isEmpty || uuid.startsWith('uid:')) ? _newNoteUuid() : uuid;
    final html = noteTextToHtml(body);
    final builder = MessageBuilder.prepareMultipartAlternativeMessage(plainText: body, htmlText: html);
    builder.from = [MailAddress(account.displayName, account.email)];
    builder.subject = title.trim().isEmpty ? body.split('\n').first.trim() : title.trim();
    builder.setHeader('X-Uniform-Type-Identifier', noteUti);
    builder.setHeader(_noteUuidHeader, id);
    final message = builder.buildMimeMessage();
    var appended = false;
    await _withClient(account, canRetry: () => !appended, (c) async {
      final box = await _notesBox(c, create: true);
      if (box == null) throw Exception('IMAP: нет папки Notes');
      final path = _pathForEnoughMail(c, box.encodedPath);
      appended = true;
      await c.appendMessage(message, flags: [MessageFlags.seen], targetMailboxPath: path);
      // Прежние копии (тот же UUID) — удалить, кроме только что добавленной.
      if (uuid != null && uuid.isNotEmpty) await _deleteNoteCopies(c, path, uuid, keepNewest: true);
    });
    return id;
  }

  /// Удалить заметку на сервере (все копии с этим UUID).
  Future<void> deleteImapNote(AccountModel account, String uuid) =>
      _withClient(account, (c) async {
        final box = await _notesBox(c);
        if (box == null) return;
        await _deleteNoteCopies(c, _pathForEnoughMail(c, box.encodedPath), uuid, keepNewest: false);
      });

  Future<void> _deleteNoteCopies(ImapClient c, String path, String uuid, {required bool keepNewest}) async {
    await c.selectMailboxByPath(path);
    final MessageSequence seq;
    if (uuid.startsWith('uid:')) {
      final u = int.tryParse(uuid.substring(4));
      if (u == null) return;
      seq = MessageSequence.fromId(u, isUid: true);
    } else {
      final found = await c.uidSearchMessages(
          searchCriteria: 'HEADER $_noteUuidHeader "${uuid.replaceAll('"', '')}"');
      final ids = [...?found.matchingSequence?.toList()]..sort();
      final drop = keepNewest && ids.isNotEmpty ? ids.sublist(0, ids.length - 1) : ids;
      if (drop.isEmpty) return;
      seq = MessageSequence.fromIds(drop, isUid: true);
    }
    await c.uidStore(seq, [MessageFlags.deleted], action: StoreAction.add, silent: true);
    await _expungeOnly(c, seq);
  }

  static String _newNoteUuid() {
    final r = Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join().toUpperCase();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16).toUpperCase()}${hex(3)}-${hex(12)}';
  }

  /// HTML заметки Apple → текст с переводами строк (div/br/p — строки).
  static String noteHtmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<(head|style|script)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>\s*</div>', caseSensitive: false), '</div>')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(div|p|li|h[1-6]|tr)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Текст → HTML, как пишут «Заметки» Apple: строка — <div>, пустая — <br>.
  static String noteTextToHtml(String text) {
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final lines = text.split('\n').map((l) => l.isEmpty ? '<div><br></div>' : '<div>${esc(l)}</div>').join();
    return '<html><head></head><body>$lines</body></html>';
  }

  // ════════════════════════ ATTACHMENTS ════════════════════════

  /// Скачать вложение
  Future<Uint8List> fetchAttachment(AccountModel account, {required String folderId, required int uid, required String partNumber}) async {
    // Последовательно на аккаунт: SELECT+операция не должны перемешаться
    // с параллельным запросом к другой папке (см. _withAccountLock).
    // Большое вложение по медленной сети качается дольше обычной операции.
    return _withClient(account, limit: const Duration(minutes: 20), (client) async {
    try {
      await client.selectMailboxByPath(folderId);

      final sequence = MessageSequence.fromId(uid, isUid: true);
      // PEEK — открытие вложения не должно помечать письмо прочитанным.
      // BODYSTRUCTURE — ради кодировки передачи части: скачанная отдельно
      // часть своих заголовков не содержит, и без неё base64 сохранялся в
      // файл как есть (PDF/картинка «битые»).
      final messages = await client.uidFetchMessages(
          sequence, '(BODYSTRUCTURE BODY.PEEK[$partNumber])');

      if (messages.messages.isEmpty) throw Exception('Message not found');

      final msg = messages.messages.first;
      final part = msg.getPart(partNumber);

      if (part == null) throw Exception('Part not found: $partNumber');

      final encoding = msg.body?.getChildPart(partNumber)?.encoding?.toLowerCase();
      final raw = part.mimeData;
      Uint8List? data;
      if (encoding != null) {
        if (raw is TextMimeData) {
          data = MailCodec.decodeBinary(raw.text, encoding);
        } else if (raw is BinaryMimeData) {
          data = (encoding == 'base64' || encoding == 'quoted-printable')
              ? MailCodec.decodeBinary(latin1.decode(raw.data, allowInvalid: true), encoding)
              : raw.data;
        }
      }
      data ??= part.decodeContentBinary();
      if (data == null) throw Exception('Could not decode attachment');

      AppLogger.info('IMAP attachment: $partNumber (${data.length} bytes)');
      return data;
    } catch (e) {
      AppLogger.error('IMAP fetch attachment error', e);
      rethrow;
    }
  });
  }

  // ════════════════════════ ДЕЙСТВИЯ НАД ПИСЬМАМИ ════════════════════════

  /// Извлекает числовой UID из id вида "folderId:uid" или просто "uid".
  int _uidInt(String id) => int.tryParse(id.split(':').last) ?? 0;

  // Все действия — UID-командами (UID STORE / UID MOVE). Раньше вызывался
  // обычный STORE с UID в качестве ПОРЯДКОВОГО номера: «прочитано», флаг и
  // удаление (с EXPUNGE!) применялись к совсем другому письму. Ошибки
  // больше не глотаются — иначе офлайн-очередь считала операцию выполненной.

  Future<void> markAsRead(AccountModel account, {required String folderId, required String uid, required bool isRead}) {
    return _withClient(account, (client) async {
      await client.selectMailboxByPath(folderId);
      await client.uidStore(MessageSequence.fromId(_uidInt(uid), isUid: true), [MessageFlags.seen],
          action: isRead ? StoreAction.add : StoreAction.remove, silent: true);
    });
  }

  Future<void> flagEmail(AccountModel account, {required String folderId, required String uid, required bool isFlagged}) {
    return _withClient(account, (client) async {
      await client.selectMailboxByPath(folderId);
      await client.uidStore(MessageSequence.fromId(_uidInt(uid), isUid: true), [MessageFlags.flagged],
          action: isFlagged ? StoreAction.add : StoreAction.remove, silent: true);
    });
  }

  /// Колбэк после успешного переноса: (аккаунт, старый id, папка, новый id|null).
  Future<void> Function(String accountId, String oldId, String toFolderId, String? newId)? onMoved;

  Future<void> moveEmail(AccountModel account, {required String fromFolderId, required String toFolderId, required String uid}) async {
    // Новый id письма («папка:UID»), если сервер его сообщил (UIDPLUS,
    // COPYUID). Локальная переменная, а не поле: переносы в разных ящиках
    // идут параллельно и не должны путать id друг друга.
    String? newId;
    await _withClient(account, (client) async {
      await client.selectMailboxByPath(fromFolderId);
      final seq = MessageSequence.fromId(_uidInt(uid), isUid: true);
      final target = _pathForEnoughMail(client, toFolderId);
      GenericImapResult res;
      if (client.serverInfo.supportsMove) {
        res = await client.uidMove(seq, targetMailboxPath: target);
      } else {
        // Сервер без MOVE: копия + пометка на удаление + удаление только ЭТОГО
        // письма (UID EXPUNGE), а не всех помеченных в папке.
        res = await client.uidCopy(seq, targetMailboxPath: target);
        await client.uidStore(seq, [MessageFlags.deleted], action: StoreAction.add, silent: true);
        await _expungeOnly(client, seq);
      }
      try {
        final newUid = res.responseCodeCopyUid?.targetSequence.toList().firstOrNull;
        if (newUid != null) newId = '$toFolderId:$newUid';
      } catch (_) {}
    });
    await onMoved?.call(account.id, uid, toFolderId, newId);
  }

  /// Путь корзины аккаунта (из LIST, special-use \Trash).
  final Map<String, String> _trashPath = {};

  /// Удалить письмо. [hard] = false (по умолчанию) — в Корзину, как у EWS и
  /// ActiveSync; безвозвратно — только из самой Корзины или по [hard].
  /// Раньше IMAP всегда удалял безвозвратно (\Deleted + EXPUNGE).
  Future<void> deleteEmail(AccountModel account, {required String folderId, required String uid, bool hard = false}) async {
    var trash = _trashPath[account.id];
    if (!hard && trash == null) {
      trash = await _withClient(account, (client) async {
        final boxes = await client.listMailboxes(recursive: true);
        return boxes.where((b) => b.isTrash).firstOrNull?.encodedPath;
      });
      if (trash != null) _trashPath[account.id] = trash;
    }
    if (!hard && trash != null && trash != folderId) {
      await moveEmail(account, fromFolderId: folderId, toFolderId: trash, uid: uid);
      return;
    }
    await _withClient(account, (client) async {
      await client.selectMailboxByPath(folderId);
      final seq = MessageSequence.fromId(_uidInt(uid), isUid: true);
      await client.uidStore(seq, [MessageFlags.deleted], action: StoreAction.add, silent: true);
      await _expungeOnly(client, seq);
    });
  }

  /// Стереть помеченные письма [seq], не трогая остальные. Без UIDPLUS
  /// команда EXPUNGE стёрла бы ВСЕ письма папки с флагом \Deleted — в том
  /// числе помеченные другой почтовой программой (Thunderbird так «удаляет»
  /// без стирания, и человек может их ещё восстановить). Поэтому: снимаем
  /// \Deleted с чужих помеченных, EXPUNGE, возвращаем флаг.
  Future<void> _expungeOnly(ImapClient client, MessageSequence seq) async {
    if (client.serverInfo.supportsUidPlus) {
      await client.uidExpunge(seq);
      return;
    }
    final mine = seq.toList().toSet();
    MessageSequence? others;
    try {
      final found = await client.uidSearchMessages(searchCriteria: 'DELETED');
      final ids = (found.matchingSequence?.toList() ?? const <int>[])
          .where((u) => !mine.contains(u))
          .toList();
      if (ids.isNotEmpty) {
        others = MessageSequence.fromIds(ids, isUid: true);
        await client.uidStore(others, [MessageFlags.deleted],
            action: StoreAction.remove, silent: true);
      }
    } catch (e) {
      // Не удалось узнать чужие помеченные — не рискуем: письмо остаётся
      // помеченным (сервер или другая программа сотрёт его позже).
      AppLogger.warning('IMAP: EXPUNGE пропущен (нет UIDPLUS, поиск не удался): $e');
      return;
    }
    try {
      await client.expunge();
    } finally {
      if (others != null) {
        try {
          await client.uidStore(others, [MessageFlags.deleted],
              action: StoreAction.add, silent: true);
        } catch (_) {}
      }
    }
  }

  // ════════════════════════ CLEANUP ════════════════════════

  // ════════════════════════ QUOTA (RFC 2087) ════════════════════════

  /// Квота ящика на сервере. null — сервер не поддерживает QUOTA,
  /// лимит не объявлен, или запрос не удался (не критично — не мешаем работе).
  Future<MailQuota?> getServerQuota(AccountModel account) async {
    // Последовательно на аккаунт: SELECT+операция не должны перемешаться
    // с параллельным запросом к другой папке (см. _withAccountLock).
    return _withClient(account, (client) async {
    try {
      if (!client.serverInfo.supports('QUOTA')) {
        AppLogger.info('IMAP QUOTA: сервер не поддерживает (${account.email})');
        return null;
      }
      // GETQUOTAROOT отдаёт и имена root-ов, и сами квоты — одним запросом.
      final rootResult = await client.getQuotaRoot(mailboxName: 'INBOX');
      for (final entry in rootResult.quotaRoots.entries) {
        final q = _quotaFrom(entry.value, entry.key);
        if (q != null) return q;
      }
      // Некоторые серверы возвращают только имена root-ов — добираем GETQUOTA.
      for (final rootName in rootResult.rootNames) {
        final qr = await client.getQuota(
          quotaRoot: rootName.isEmpty ? '""' : rootName,
        );
        final q = _quotaFrom(qr, rootName);
        if (q != null) return q;
      }
      AppLogger.info('IMAP QUOTA: сервер не объявил лимит STORAGE');
      return null;
    } catch (e) {
      AppLogger.warning('IMAP QUOTA: не удалось получить — $e');
      return null;
    }
  });
  }

  /// Достать лимит STORAGE из ответа. Значения приходят в КИЛОБАЙТАХ.
  MailQuota? _quotaFrom(QuotaResult qr, String? rootName) {
    for (final limit in qr.resourceLimits) {
      if (limit.name.toUpperCase() != 'STORAGE') continue;
      final usedKb = limit.currentUsage;
      if (usedKb == null) continue;
      final limitKb = limit.usageLimit;
      return MailQuota(
        usedBytes: usedKb * 1024,
        limitBytes: (limitKb != null && limitKb > 0) ? limitKb * 1024 : null,
        rootName: qr.rootName ?? rootName,
      );
    }
    return null;
  }

  void dispose() {
    stopAllIdle(); // закрывает и отдельные idle-соединения
    for (final client in _imapClients.values) {
      unawaited(client.disconnect().catchError((Object _) {}));
    }
    for (final client in _smtpClients.values) {
      unawaited(client.disconnect().catchError((Object _) {}));
    }
    _imapClients.clear();
    _smtpClients.clear();
  }
}

/// Корень переписки для IMAP: ПЕРВЫЙ Message-ID из References (исходное
/// письмо цепочки), иначе In-Reply-To, иначе собственный Message-ID.
/// Раньше брался In-Reply-To — родитель, а не корень: в длинной переписке
/// каждый ответ попадал в свою «беседу» из двух писем.
String? imapConversationId(String? references, String? inReplyTo, String? messageId) {
  final ids = RegExp(r'<[^<>\s]+>').allMatches(references ?? '').map((m) => m.group(0)!).toList();
  if (ids.isNotEmpty) return ids.first;
  final r = inReplyTo?.trim();
  if (r != null && r.isNotEmpty) {
    final m = RegExp(r'<[^<>\s]+>').firstMatch(r);
    return m?.group(0) ?? r;
  }
  return messageId;
}

/// Что известно о папке IMAP между синхронизациями.
class ImapFolderState {
  final int uidValidity;
  final int minUid;
  final int maxUid;
  /// История загружена до начала папки или до среза периода синхронизации.
  final bool historyDone;
  /// Период синхронизации (дни), при котором история признана загруженной.
  final int syncDays;
  const ImapFolderState({
    required this.uidValidity,
    required this.minUid,
    required this.maxUid,
    this.historyDone = false,
    this.syncDays = 0,
  });

  ImapFolderState copyWith({bool? historyDone, int? syncDays}) => ImapFolderState(
        uidValidity: uidValidity,
        minUid: minUid,
        maxUid: maxUid,
        historyDone: historyDone ?? this.historyDone,
        syncDays: syncDays ?? this.syncDays,
      );

  Map<String, int> toJson() => {
        'v': uidValidity,
        'min': minUid,
        'max': maxUid,
        if (historyDone) 'd': 1,
        if (historyDone) 'days': syncDays,
      };
  static ImapFolderState? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return ImapFolderState(
        uidValidity: m['v'] as int,
        minUid: m['min'] as int,
        maxUid: m['max'] as int,
        historyDone: m['d'] == 1,
        syncDays: (m['days'] as int?) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Изменения папки IMAP за один проход.
class ImapFolderDelta {
  /// Новые письма и догруженная история (с флагами).
  final List<EmailModel> added;
  /// Из них — догруженная история (письма старше загруженных ранее).
  final List<EmailModel> backfilled;
  /// UID → флаги писем, которые уже были в приложении.
  final Map<int, ({bool read, bool flagged})> flags;
  /// UID, которые есть на сервере в проверенном диапазоне.
  final Set<int> present;
  final ImapFolderState state;
  /// Диапазон UID, в котором отсутствие письма означает удаление на сервере.
  final int? checkedFrom;
  final int? checkedTo;
  /// Первая загрузка или смена UIDVALIDITY: прежние письма папки недействительны.
  final bool reset;
  final bool empty;
  /// Загружена вся папка — догружать историю больше нечего. Раньше пустые
  /// папки (Черновики, Спам, Notes) после каждого прохода снова считались
  /// «первой загрузкой», и продолжение крутилось до лимита в 40 шагов.
  final bool complete;

  const ImapFolderDelta({
    required this.added,
    this.backfilled = const [],
    required this.flags,
    required this.present,
    required this.state,
    this.checkedFrom,
    this.checkedTo,
    required this.reset,
    this.empty = false,
    this.complete = false,
  });
}

/// Заголовки цепочки ответа. [chain] — Message-ID родителя или вся цепочка
/// «References родителя + его Message-ID» через пробел. In-Reply-To —
/// последний id, References — вся цепочка (первый и последние 19, как
/// советует RFC 5322). Раньше в References был только родитель, и почтовые
/// программы собирали длинную переписку в несколько бесед.
({String inReplyTo, String references})? replyThreadHeaders(String? chain) {
  final raw = chain?.trim() ?? '';
  if (raw.isEmpty) return null;
  var ids = RegExp(r'<[^<>\s]+>').allMatches(raw).map((m) => m.group(0)!).toList();
  if (ids.isEmpty) ids = [raw.startsWith('<') ? raw : '<$raw>'];
  final seen = <String>{};
  ids = [for (final i in ids) if (seen.add(i)) i];
  if (ids.length > 20) ids = [ids.first, ...ids.sublist(ids.length - 19)];
  return (inReplyTo: ids.last, references: ids.join(' '));
}

/// Адрес для заголовка письма с именем по RFC 2047: кириллица — словами
/// «=?UTF-8?B?…?=», каждое не длиннее 75 знаков и только из целых символов.
/// enough_mail кодировал длинное имя так, что при переносе строки слово
/// разрывалось посреди символа, и получатели видели «Ермишин Ол?=В 5г».
String rfc2047Address(String? name, String email) {
  final n = (name ?? '').trim();
  if (n.isEmpty || n == email) return email;
  if (RegExp(r'^[\x20-\x7E]*$').hasMatch(n)) {
    return '"${n.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" <$email>';
  }
  final words = <String>[];
  final buf = StringBuffer();
  var bytes = 0;
  for (final r in n.runes) {
    final ch = String.fromCharCode(r);
    final len = utf8.encode(ch).length;
    if (bytes + len > 39 && buf.isNotEmpty) {
      words.add('=?UTF-8?B?${base64.encode(utf8.encode(buf.toString()))}?=');
      buf.clear();
      bytes = 0;
    }
    buf.write(ch);
    bytes += len;
  }
  if (buf.isNotEmpty) words.add('=?UTF-8?B?${base64.encode(utf8.encode(buf.toString()))}?=');
  return '${words.join(' ')} <$email>';
}

/// Заголовки From/To/Cc письма — нашим кодированием имён (см. [rfc2047Address]).
void applyAddressHeaders(MimeMessage message,
    {required String fromName, required String fromEmail,
    List<({String? name, String email})> to = const [],
    List<({String? name, String email})> cc = const []}) {
  message.setHeader('From', rfc2047Address(fromName, fromEmail));
  if (to.isNotEmpty) message.setHeader('To', to.map((a) => rfc2047Address(a.name, a.email)).join(', '));
  if (cc.isNotEmpty) message.setHeader('Cc', cc.map((a) => rfc2047Address(a.name, a.email)).join(', '));
}

/// Варианты критериев IMAP SEARCH для строки [q] (кавычки и переводы строки
/// уже убраны). ASCII — в кавычках. Не-ASCII — литералом `{N}` + CHARSET
/// UTF-8; запасной вариант — в кавычках с CHARSET (часть серверов принимает
/// 8-битный текст и так). Первый принятый сервером вариант используется для
/// остальных папок.
List<String> imapSearchVariants(String q, {required bool gmail}) {
  final ascii = q.codeUnits.every((c) => c < 128);
  if (ascii) {
    return [gmail ? 'X-GM-RAW "$q"' : 'OR OR SUBJECT "$q" FROM "$q" TO "$q"'];
  }
  final lit = '{${utf8.encode(q).length}}\n$q';
  final literal = gmail
      ? 'CHARSET UTF-8 X-GM-RAW $lit'
      : 'CHARSET UTF-8 OR OR SUBJECT $lit FROM $lit TO $lit';
  final quoted = gmail
      ? 'CHARSET UTF-8 X-GM-RAW "$q"'
      : 'CHARSET UTF-8 OR OR SUBJECT "$q" FROM "$q" TO "$q"';
  return [literal, quoted];
}

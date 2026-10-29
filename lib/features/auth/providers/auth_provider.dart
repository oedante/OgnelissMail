// lib/features/auth/providers/auth_provider.dart
// Провайдер аутентификации:
// - Rate limiting (5 попыток → 15 мин блокировка)
// - Аудит всех действий
// - Таймаут подключения
// - Поддержка Exchange, OAuth2, IMAP, биометрия
// - Сохранение аккаунтов в БД (не требует повторного ввода)

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/oauth/graph_tokens.dart' show graphTokensProvider;
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/device/device_user_agent.dart';
import '../../../services/mail/ews/ews_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/security/certificate_pinning_service.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/security/security_utils.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../services/mail/imap/imap_service.dart';
import '../../../services/mail/oauth/oauth_service.dart';
import '../../../services/mail/oauth/cross_platform_oauth.dart';
import '../../../services/mail/oauth/proxy_pkce.dart' show OAuthProviderError;
import '../../mail/providers/mail_providers.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../services/mail/signature_import_service.dart';
import '../../../services/mail/signature_service.dart';
import 'dart:async';
import '../../../services/sync/sync_service.dart' show syncServiceProvider;

/// Состояние авторизации
enum AuthStatus { idle, connecting, success, error }

/// Что делать после неудачного входа (1.8.0, п. 6 плана): экран входа
/// показывает у строки ошибки кнопку — «Проверить пароль», «Создать пароль
/// приложения», «Открыть настройки почты», «Повторить».
enum AuthErrorKind { generic, password, appPassword, imapDisabled, network }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  /// Вид ошибки — для кнопки у строки ошибки (null — без кнопки).
  final AuthErrorKind? errorKind;
  final bool isBiometricAvailable;
  /// Вход не удался из-за сертификата, которому устройство не доверяет:
  /// экран входа предлагает сверить отпечаток и доверять ему.
  final RejectedCertificate? untrustedCert;

  const AuthState({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.errorKind,
    this.isBiometricAvailable = false,
    this.untrustedCert,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    AuthErrorKind? errorKind,
    bool? isBiometricAvailable,
    RejectedCertificate? untrustedCert,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      errorKind: errorKind,
      isBiometricAvailable: isBiometricAvailable ?? this.isBiometricAvailable,
      untrustedCert: untrustedCert,
    );
  }
}

/// Вид ошибки по тексту отказа сервера (IMAP, Exchange). [appPassword] —
/// служба пускает почтовые программы только по паролю приложения.
AuthErrorKind authErrorKindOf(String? error, {bool appPassword = false}) {
  final e = (error ?? '').toLowerCase();
  if (e.contains('host lookup') || e.contains('no address associated') || e.contains('dns') ||
      e.contains('timed out') || e.contains('timeout') || e.contains('таймаут') ||
      e.contains('connection refused') || e.contains('network is unreachable') ||
      e.contains('connection reset') || e.contains('socketexception')) {
    return AuthErrorKind.network;
  }
  if (e.contains('401') || e.contains('unauthorized') || e.contains('authenticationfailed') ||
      e.contains('authentication failed') || e.contains('invalid credentials') ||
      e.contains('login failed') || e.contains('logon failure') || e.contains('incorrect password') ||
      e.contains('учётн') || e.contains('неверн') || e.contains('bad credentials') ||
      e.contains('[auth]') || e.contains('password')) {
    return appPassword ? AuthErrorKind.appPassword : AuthErrorKind.password;
  }
  return AuthErrorKind.generic;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AppLocalizations _l10n() => AppLocalizations(_ref.read(settingsProvider).locale);
  final LocalAuthentication _localAuth = LocalAuthentication();
  final _uuid = const Uuid();

  AuthNotifier(this._ref) : super(const AuthState()) {
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      state = state.copyWith(isBiometricAvailable: canAuth && isSupported);
    } catch (_) {}
  }

  /// Аудит действия
  Future<void> _audit(String action, {String? details}) async {
    try {
      final db = _ref.read(databaseProvider);
      await db.into(db.auditLog).insert(AuditLogCompanion.insert(
            action: action,
            details: Value(details),
            timestamp: DateTime.now(),
          ));
    } catch (_) {}
  }

  // ════════════════════════ EXCHANGE ════════════════════════

  Future<bool> loginExchange({
    required String email,
    required String password,
    String? username,
    String? domain,
    String? server,
  }) async {
    if (!SecurityUtils.isValidEmail(email)) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authInvalidEmail'));
      return false;
    }

    // Сертификаты, отклонённые с этого момента, относятся к этой попытке входа.
    final loginStarted = DateTime.now();
    final pinning = _ref.read(certPinningProvider);
    pinning.clearRejected();
    try {
      state = state.copyWith(status: AuthStatus.connecting, errorMessage: null);

      final accountId = _uuid.v4();
      // Пустые поля формы — то же, что «не задано» (иначе NTLM уходил с
      // пустым именем пользователя, а адрес сервера получался «https:///»).
      String? nz(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
      final effectiveUsername = nz(username) ?? email.split('@').first;
      final effectiveDomain = nz(domain) ?? AppConstants.defaultDomain;
      final effectiveServer = (nz(server) ?? AppConstants.defaultExchangeServer)
          .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
          .split('/')
          .first;

      final secureStorage = _ref.read(secureStorageProvider);
      await secureStorage.saveAccountPassword(accountId, password);

      // Единый Exchange через движок: EWS (SOAP) и EAS (ActiveSync).
      // Покрывает и стандартный Exchange, и корпоративные шлюзы (организации).
      final baseAccount = AccountModel(
        id: accountId,
        // Новый ящик — проверка раз в 15 минут (решение 10.10.2026);
        // «Мгновенно» и «По расписанию» включаются на экране ящика.
        syncInterval: SyncInterval.minutes15,
        type: AccountType.exchange,
        email: email,
        displayName: effectiveUsername,
        username: effectiveUsername,
        domain: effectiveDomain,
        exchangeServer: effectiveServer,
        exchangeAuthMethod: ExchangeAuthMethod.ntlm,
        createdAt: DateTime.now(),
      );

      // Хосты организации для перебора (рабочий — сервер, см. логи NINE).
      final hostsToTry = effectiveServer.isNotEmpty
          ? <String>[effectiveServer, ...AppConstants.probeServers.where((h) => h != effectiveServer)]
          : AppConstants.probeServers;
      // Сервер не указан и списка хостов нет — движок сам найдёт сервер через
      // Autodiscover (пустой хост). Раньше при пустом поле «Сервер» шаг с
      // движком и перебор EAS не выполнялись вовсе.
      final engineHosts = hostsToTry.isEmpty ? const <String>[''] : hostsToTry;

      // Попытка 0: через движок (OPTIONS → Provision → подбор версии/UA — тот же
      // путь, что в рабочем connect_test, который проходил авторизацию организации).
      String? wafError;
      try {
        final engineSvc = _ref.read(mailEngineServiceProvider);
        // iPhone: один вариант — выбранный режим (по умолчанию «как Почта
        // iPhone»). Второй вариант без совместимости (1.6.12) убран в 1.6.17:
        // он шёл через сетевой стек Dart, а такие запросы шлюз ServicePipe
        // считает ботом — лишние отказы с того же адреса и устройства.
        final variants = <bool?>[null];
        variantLoop:
        for (final compat in variants) {
        if (compat != null) {
          if (wafError != null) break;
          await DeviceUserAgent.setCompatFor(accountId, compat);
          AppLogger.info('Проверка доступа: вариант «${compat ? 'как Почта iPhone' : 'Ogneliss (без совместимости)'}»');
        }
        for (final host in engineHosts) {
          final probe = await engineSvc
              .probeConnect(baseAccount.copyWith(exchangeServer: host))
              .timeout(const Duration(seconds: 40),
                  onTimeout: () => (ok: false, transport: null, host: null, error: 'таймаут'));
          if (probe.ok) {
            final h = (probe.host != null && probe.host!.isNotEmpty) ? probe.host! : host;
            AppLogger.info('Exchange: подключение через движок ✓ (${probe.transport}@$h)');
            final acc = probe.transport == 'eas'
                ? baseAccount.copyWith(type: AccountType.activesync, exchangeServer: h)
                : baseAccount.copyWith(ewsUrl: 'https://$h/EWS/Exchange.asmx');
            await _finishExchangeLogin(acc, password, email, 'движок:${probe.transport}@$h');
            return true;
          }
          if ((probe.error ?? '').contains('EAS 403')) {
            wafError = probe.error;
            break variantLoop; // шлюз блокирует — другие хосты и варианты только продлят блокировку
          }
        }
        }
        if (variants.length > 1 && wafError == null) {
          // Ни один вариант не подошёл — возвращаем режим по умолчанию.
          await DeviceUserAgent.setCompatFor(accountId, !variants.last!);
        }
        if (wafError == null) {
          AppLogger.info('Exchange: движок не подключился ни на одном хосте — пробуем legacy EWS/EAS');
        }
      } catch (e) {
        AppLogger.info('Exchange: движок недоступен ($e) — пробуем legacy EWS/EAS');
      }
      if (wafError != null) {
        final i = wafError.indexOf('EAS 403');
        state = state.copyWith(status: AuthStatus.error, errorMessage: wafError.substring(i));
        return false;
      }

      // Пробник движка проверяет EWS только Basic-авторизацией. Сервер, где
      // EWS принимает лишь NTLM (частый вариант on-premise), а ActiveSync
      // выключен, пробник отвергал, хотя рабочий EWS-стек приложения (NTLM)
      // подключился бы. Последняя попытка — GetFolder через него.
      // На iPhone в режиме «как Почта iPhone» (1.6.17) — не делаем: этот стек
      // работает через Dart, а не через сетевой стек iOS.
      final iosCompat = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          DeviceUserAgent.compatFor(accountId);
      if (!iosCompat) {
      try {
        final ews = _ref.read(ewsServiceProvider);
        for (final host in hostsToTry.where((h) => h.trim().isNotEmpty)) {
          final acc = baseAccount.copyWith(
              exchangeServer: host, ewsUrl: EwsService.ewsUrlFromServer(host));
          ews.clearClientCache(accountId); // кэш адреса — от прошлого хоста
          final ok = await ews
              .testConnection(acc)
              .timeout(const Duration(seconds: 25), onTimeout: () => false);
          ews.clearClientCache(accountId);
          if (ok) {
            AppLogger.info('Exchange: EWS (NTLM) ✓ на $host — пробник движка его не видел');
            await _finishExchangeLogin(acc, password, email, 'ews-ntlm@$host');
            return true;
          }
        }
      } on InvalidCredentialsException {
        AppLogger.warning('Exchange: EWS (NTLM) — неверные учётные данные');
      } catch (e) {
        AppLogger.info('Exchange: EWS (NTLM) недоступен: $e');
      }
      }

      // Движок не подключился. Прежний запасной путь (отдельные старые
      // реализации EWS и ActiveSync) убран: движок сам перебирает EWS, EAS и
      // Autodiscover, а повтор через dart:io шлюз организации отвечает 403 и
      // продлевает блокировку адреса. Остаётся разобрать причину отказа.
      await secureStorage.deleteAccountPassword(accountId);
      final triedHosts = hostsToTry.join(', ');
      // Сервер ответил, но его сертификату устройство не доверяет (внутренний
      // центр сертификации или сервер не передаёт промежуточный сертификат).
      final rejected = pinning.lastRejected(since: loginStarted, hosts: hostsToTry);
      if (rejected != null && rejected.pinMismatch) {
        // Сертификат не совпал с закреплённым: доверять не предлагаем.
        AppLogger.warning('Exchange: сертификат ${rejected.host} не совпал с закреплённым');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: _l10n().tr('certPinMismatchLogin').replaceAll('{host}', rejected.host),
        );
        await _audit('login_failed', details: '$email: pin mismatch ${rejected.host}');
        return false;
      }
      if (rejected != null) {
        AppLogger.warning('Exchange: сертификат ${rejected.host} не прошёл проверку '
            '(выдан: ${rejected.issuer}; SHA-256 ${rejected.fingerprintHex})');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: _l10n().tr('certUntrustedLogin').replaceAll('{host}', rejected.host),
          untrustedCert: rejected,
        );
        await _audit('login_failed', details: '$email: untrusted certificate ${rejected.host}');
        return false;
      }
      final engineErr = _ref.read(mailEngineServiceProvider).lastConnectError(accountId);
      AppLogger.warning('Exchange: подключение не удалось ($triedHosts): ${engineErr ?? '—'}');
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _explainExchangeError(_l10n(), engineErr, triedHosts),
        errorKind: authErrorKindOf(engineErr),
      );
      await _audit('login_failed', details: email);
      return false;
    } on AppException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.localizedMessage(_l10n()));
      await _audit('login_error', details: '$email: ${e.code}');
      return false;
    } catch (e) {
      state = state.copyWith(
          status: AuthStatus.error, errorMessage: _l10n().tr('connectionError'), errorKind: AuthErrorKind.network);
      await _audit('login_error', details: '$email: $e');
      return false;
    }
  }

  /// Понятная причина отказа входа в Exchange вместо технического текста
  /// движка. Самое частое — неверный логин/пароль и нет сети до сервера.
  static String _explainExchangeError(AppLocalizations l10n, String? err, String hosts) {
    final e = (err ?? '').toLowerCase();
    final tech = (err == null || err.isEmpty)
        ? ''
        : '\n\n${l10n.tr('authErrDetails').replaceAll('{err}', err)}';
    String msg(String key) => l10n.tr(key).replaceAll('{hosts}', hosts) + tech;
    if (e.contains('401') || e.contains('unauthorized') || e.contains('учётн')) {
      return msg('authExBadCredentials');
    }
    if (e.contains('host lookup') || e.contains('no address associated') || e.contains('dns')) {
      return msg('authExHostNotFound');
    }
    if (e.contains('timed out') || e.contains('timeout') || e.contains('таймаут') ||
        e.contains('connection refused') || e.contains('network is unreachable')) {
      return msg('authExNoResponse');
    }
    if (e.contains('certificate') || e.contains('handshake') || e.contains('сертификат')) {
      return msg('authExCert');
    }
    if (e.contains('403')) {
      return l10n.tr('authEx403').replaceAll('{setting}', l10n.tr('easCompatUa')) + tech;
    }
    return msg('authExGeneric');
  }

  /// Завершение успешного входа Exchange (общее для EWS и EAS).
  Future<void> _finishExchangeLogin(AccountModel account, String password, String email, String via) async {
    // Режим совместимости, с которым вход удался, закрепляем за ящиком:
    // смена значения по умолчанию потом не сломает уже работающий ящик.
    await DeviceUserAgent.setCompatFor(account.id, DeviceUserAgent.compatMode);
    await _ref.read(accountsProvider.notifier).addAccount(
          account.copyWith(isPrimary: _ref.read(accountsProvider).isEmpty),
          password: password,
        );
    await _ref.read(settingsProvider.notifier).setActiveAccountId(account.id);
    unawaited(_tryImportSignature(account));
    state = state.copyWith(status: AuthStatus.success);
    await _audit('login_success', details: '${SecurityUtils.maskEmail(email)} (Exchange/$via)');
    AppLogger.info('Exchange вход успешен через $via');
  }



  /// Best-effort импорт подписи из ящика при подключении. Сразу работает для API-путей
  /// (Gmail/Graph/EWS при наличии scope/доступа); эвристика по «Отправленным» — после
  /// первой синхронизации (тогда вручную через «Импорт из ящика»).
  Future<void> _tryImportSignature(AccountModel account) async {
    try {
      final has = _ref.read(signaturesProvider).any((sg) => sg.accountId == account.id);
      if (has) return;
      final imported = await _ref.read(signatureImportServiceProvider).importSignature(account);
      if (imported != null &&
          (imported.html.trim().isNotEmpty || imported.plain.trim().isNotEmpty)) {
        unawaited(_ref.read(signaturesProvider.notifier).addSignature(SignatureModel(
              id: 'sig_import_${account.id}',
              name: account.email,
              htmlContent: imported.html,
              plainContent: imported.plain,
              accountId: account.id,
              isDefault: true,
              useForNewEmails: true,
            )));
      }
    } catch (_) {}
  }

  // ════════════════════════ EXCHANGE ONLINE (OAuth) ════════════════════════

  /// Exchange Online (Microsoft 365) по OAuth (1.6.2): вход в браузере
  /// Microsoft (пароль и второй фактор — у Microsoft, приложение их не
  /// видит), почта, календарь и контакты — по ActiveSync с токеном,
  /// автоответы, правила и занятость коллег — по EWS с тем же токеном.
  /// Обычный вход по паролю в Exchange Online Microsoft закрыл в 2022 году.
  /// 1.8.10: при входе — и согласие на Microsoft Graph (адресная книга,
  /// MailTips, правила сервера вместо EWS, который Microsoft отключает);
  /// токен Graph — сразу после входа (graph_tokens.dart).
  Future<bool> loginExchangeOnline() async {
    final secureStorage = _ref.read(secureStorageProvider);
    String? accountId;
    try {
      state = state.copyWith(status: AuthStatus.connecting, errorMessage: null);
      final result = await _ref.read(crossPlatformOAuthProvider).authenticate('exchange');
      final email = result.email;
      if (email == null || email.isEmpty) {
        state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authOAuthNoEmail'));
        return false;
      }
      if (_ref.read(accountsProvider).any((a) => a.email.toLowerCase() == email.toLowerCase())) {
        throw AccountAlreadyExistsException(email: email);
      }
      final id = accountId = _uuid.v4();
      await secureStorage.saveOAuthTokens(
        accountId: id,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiry: result.expiry,
      );
      await secureStorage.saveOAuthClient(id, result.directClient);
      final account = AccountModel(
        id: id,
        syncInterval: SyncInterval.minutes15,
        type: AccountType.activesync,
        email: email,
        displayName: (result.displayName ?? '').trim().isNotEmpty ? result.displayName!.trim() : email.split('@').first,
        username: email,
        exchangeServer: AppConstants.exchangeOnlineHost,
        ewsUrl: 'https://${AppConstants.exchangeOnlineHost}/EWS/Exchange.asmx',
        exchangeAuthMethod: ExchangeAuthMethod.bearer,
        createdAt: DateTime.now(),
      );
      final probe = await _ref
          .read(mailEngineServiceProvider)
          .probeConnect(account)
          .timeout(const Duration(seconds: 40),
              onTimeout: () => (ok: false, transport: null, host: null, error: 'таймаут'));
      if (!probe.ok) {
        await secureStorage.deleteAccountTokens(id);
        AppLogger.warning('Exchange Online: ActiveSync не подключился — ${probe.error}');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: _l10n().tr('authExoFailed').replaceAll('{err}', probe.error ?? '—'),
        );
        return false;
      }
      await DeviceUserAgent.setCompatFor(id, DeviceUserAgent.compatMode);
      await _ref.read(accountsProvider.notifier).addAccount(
            account.copyWith(isPrimary: _ref.read(accountsProvider).isEmpty));
      await _ref.read(settingsProvider.notifier).setActiveAccountId(id);
      unawaited(_tryImportSignature(account));
      // Токен Graph — сразу: в настройках ящика видно, дала ли организация
      // согласие (1.8.10).
      unawaited(_ref.read(graphTokensProvider).token(account));
      state = state.copyWith(status: AuthStatus.success);
      await _audit('login_success', details: '${SecurityUtils.maskEmail(email)} (Exchange Online/OAuth)'
          '${result.graphConsent ? ', Graph' : ''}');
      return true;
    } on AppException catch (e) {
      if (accountId != null) await secureStorage.deleteAccountTokens(accountId);
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.localizedMessage(_l10n()));
      return false;
    } on OAuthProviderError catch (e) {
      state = e.cancelled
          ? state.copyWith(status: AuthStatus.idle, errorMessage: null)
          : state.copyWith(status: AuthStatus.error, errorMessage: e.localizedMessage(_l10n()));
      return false;
    } catch (e) {
      if (accountId != null) await secureStorage.deleteAccountTokens(accountId);
      state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authOAuthErr').replaceAll('{e}', '$e'));
      return false;
    }
  }

  // ════════════════════════ OAUTH2 ════════════════════════

  /// Вход через страницу службы. [loginHint] — адрес, введённый на первом
  /// шаге входа (1.8.0): служба подставит его сама.
  Future<bool> loginOAuth(AccountType type, {String? loginHint}) async {
    try {
      state = state.copyWith(status: AuthStatus.connecting, errorMessage: null);

      final oauthService = _ref.read(crossPlatformOAuthProvider);
      final secureStorage = _ref.read(secureStorageProvider);

      final providerName = switch (type) {
        AccountType.google => 'google',
        AccountType.yandex => 'yandex',
        AccountType.yahoo => 'yahoo',
        AccountType.mailru => 'mailru',
        AccountType.outlook => 'microsoft',
        _ => throw const AuthException(userMessage: 'Неподдерживаемый OAuth', messageKey: 'authUnsupportedOAuth'),
      };
      final OAuthResult result = await oauthService.authenticate(providerName, loginHint: loginHint);

      final accountId = _uuid.v4();
      await secureStorage.saveOAuthTokens(
        accountId: accountId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiry: result.expiry,
      );
      await secureStorage.saveOAuthClient(accountId, result.directClient);

      // Прокси и десктопный поток возвращают только токены. Адрес нужен для
      // входа по XOAUTH2 — узнаём его у провайдера. Раньше подставлялся
      // «user@gmail.com», и IMAP отвечал отказом при любом входе через прокси.
      var email = result.email;
      var name = result.displayName;
      if (email == null || email.isEmpty) {
        final id = await _ref.read(oauthServiceProvider).fetchIdentity(type, result.accessToken);
        email = id.email;
        name ??= id.name;
      }
      if (email == null || email.isEmpty) {
        await secureStorage.deleteAccountTokens(accountId);
        state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: _l10n().tr('authOAuthNoEmail'));
        return false;
      }
      final emailAddr = email;
      final account = AccountModel(
        id: accountId,
        // Новый ящик — проверка раз в 15 минут (решение 10.10.2026);
        // «Мгновенно» и «По расписанию» включаются на экране ящика.
        syncInterval: SyncInterval.minutes15,
        type: type,
        email: emailAddr,
        displayName: (name != null && name.isNotEmpty) ? name : emailAddr.split('@').first,
        username: emailAddr,
        imapPort: 993,
        imapEncryption: EncryptionType.ssl,
        // Microsoft принимает SMTP только на 587 со STARTTLS.
        smtpPort: type == AccountType.outlook ? 587 : 465,
        smtpEncryption: type == AccountType.outlook ? EncryptionType.starttls : EncryptionType.ssl,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        tokenExpiry: result.expiry,
        isPrimary: _ref.read(accountsProvider).isEmpty,
        createdAt: DateTime.now(),
      );

      // Тест IMAP
      final imap = _ref.read(imapServiceProvider);
      final connected = await imap.testConnection(account);

      if (!connected) {
        await secureStorage.deleteAccountTokens(accountId);
        final why = imap.lastConnectError ?? '';
        final l10n = _l10n();
        final base = why.isNotEmpty
            ? l10n.tr('authOAuthImapRejectedWhy').replaceAll('{why}', why)
            : l10n.tr('authOAuthImapRejected');
        final imapSwitch = type == AccountType.mailru || type == AccountType.yandex;
        final hint = imapSwitch ? ' ${l10n.tr('authImapEnableHint')}' : '';
        state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: '$base$hint',
            errorKind: imapSwitch ? AuthErrorKind.imapDisabled : authErrorKindOf(why));
        return false;
      }

      await _ref.read(accountsProvider.notifier).addAccount(account);
      unawaited(_tryImportSignature(account));
      await _ref.read(settingsProvider.notifier).setActiveAccountId(accountId);

      state = state.copyWith(status: AuthStatus.success);
      await _audit('login_success', details: '${SecurityUtils.maskEmail(emailAddr)} (${type.name})');
      return true;
    } on AppException catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.localizedMessage(_l10n()));
      return false;
    } on OAuthProviderError catch (e) {
      // Отказ провайдера, возвращённый прокси: «отменено» — не ошибка.
      state = e.cancelled
          ? state.copyWith(status: AuthStatus.idle, errorMessage: null)
          : state.copyWith(status: AuthStatus.error, errorMessage: e.localizedMessage(_l10n()));
      return false;
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authOAuthErr').replaceAll('{e}', '$e'));
      return false;
    }
  }


  /// Повторный вход в существующий аккаунт (пароль сменился, доступ отозван,
  /// срок токена истёк). Раньше единственным способом было удалить аккаунт
  /// и добавить заново — со всей локальной почтой, черновиками и настройками.
  /// Возвращает текст ошибки или null при успехе.
  Future<String?> reauthenticate(AccountModel account, {String? password}) async {
    try {
      final storage = _ref.read(secureStorageProvider);
      if (account.usesOAuthTokens) {
        final name = account.isExchangeOnlineOAuth
            ? 'exchange'
            : switch (account.type) {
                AccountType.google => 'google',
                AccountType.yandex => 'yandex',
                AccountType.yahoo => 'yahoo',
                AccountType.mailru => 'mailru',
                AccountType.outlook => 'microsoft',
                _ => null,
              };
        if (name == null) return 'OAuth';
        final result = await _ref.read(crossPlatformOAuthProvider).authenticate(name, loginHint: account.email);
        // Вошли под другим адресом — не подменяем чужой ящик.
        var email = result.email;
        if (email == null || email.isEmpty) {
          email = (await _ref.read(oauthServiceProvider).fetchIdentity(account.type, result.accessToken)).email;
        }
        // Яндекс: один ящик под разными доменами (yandex.ru, ya.ru, yandex.com),
        // а без права login:email известен только логин — сравниваем логин.
        String norm(String e) {
          final s = e.trim().toLowerCase();
          return account.type == AccountType.yandex ? s.split('@').first : s;
        }
        if (email != null && email.isNotEmpty && norm(email) != norm(account.email)) {
          return 'mismatch:$email';
        }
        await storage.saveOAuthTokens(
          accountId: account.id,
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          expiry: result.expiry,
        );
        // Как получен токен: прямо у провайдера или через сервер входа —
        // по этому обновляется он сам.
        await storage.saveOAuthClient(account.id, result.directClient);
        if (account.isExchangeOnlineOAuth) {
          _ref.read(mailEngineServiceProvider).disconnect(account.id);
          // Согласие на Graph могло появиться — проверить заново (1.8.10).
          final graph = _ref.read(graphTokensProvider);
          await graph.reset(account.id);
          unawaited(graph.token(account));
        }
      } else {
        if (password == null || password.isEmpty) return 'password';
        await storage.saveAccountPassword(account.id, password);
      }
      // Пауза после отказа обновления токена — снять: вход новый.
      OAuthService.clearRefreshFailure(account.id);
      await _ref.read(accountsProvider.notifier).clearAuthFailure(account.id);
      final fresh = _ref.read(accountsProvider).where((a) => a.id == account.id).firstOrNull;
      if (fresh != null) unawaited(_ref.read(syncServiceProvider).syncAccount(fresh));
      await _audit('reauth', details: SecurityUtils.maskEmail(account.email));
      return null;
    } on AppException catch (e) {
      return e.localizedMessage(_l10n());
    } on OAuthProviderError catch (e) {
      return e.localizedMessage(_l10n());
    } catch (e) {
      return '$e';
    }
  }

  // ════════════════════════ IMAP ════════════════════════

  /// [appPassword] — служба пускает только по паролю приложения (Mail.ru,
  /// iCloud, Yahoo…): при отказе экран предложит его создать.
  Future<bool> loginImap({
    required String email,
    required String password,
    required String imapServer,
    required int imapPort,
    required String smtpServer,
    required int smtpPort,
    EncryptionType imapEncryption = EncryptionType.ssl,
    EncryptionType smtpEncryption = EncryptionType.starttls,
    bool appPassword = false,
  }) async {
    try {
      state = state.copyWith(status: AuthStatus.connecting, errorMessage: null);

      final accountId = _uuid.v4();
      final secureStorage = _ref.read(secureStorageProvider);
      await secureStorage.saveAccountPassword(accountId, password);

      final account = AccountModel(
        id: accountId,
        // Новый ящик — проверка раз в 15 минут (решение 10.10.2026);
        // «Мгновенно» и «По расписанию» включаются на экране ящика.
        syncInterval: SyncInterval.minutes15,
        type: AccountType.imap,
        email: email,
        displayName: email.split('@').first,
        username: email,
        imapServer: imapServer,
        imapPort: imapPort,
        imapEncryption: imapEncryption,
        smtpServer: smtpServer,
        smtpPort: smtpPort,
        smtpEncryption: smtpEncryption,
        isPrimary: _ref.read(accountsProvider).isEmpty,
        createdAt: DateTime.now(),
      );

      final imap = _ref.read(imapServiceProvider);
      final connected = await imap.testConnection(account);

      if (!connected) {
        await secureStorage.deleteAccountPassword(accountId);
        final why = imap.lastConnectError ?? '';
        state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: why.isNotEmpty
                ? _l10n().tr('authImapFailedWhy').replaceAll('{why}', why)
                : _l10n().tr('authImapFailed'),
            errorKind: authErrorKindOf(why, appPassword: appPassword));
        return false;
      }

      await _ref.read(accountsProvider.notifier).addAccount(account, password: password);
      unawaited(_tryImportSignature(account));
      await _ref.read(settingsProvider.notifier).setActiveAccountId(accountId);

      state = state.copyWith(status: AuthStatus.success);
      await _audit('login_success', details: '${SecurityUtils.maskEmail(email)} (IMAP)');
      return true;
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authErrGeneric').replaceAll('{e}', '$e'));
      return false;
    }
  }

  // ════════════════════════ БИОМЕТРИЯ ════════════════════════

  Future<bool> loginBiometric() async {
    try {
      if (!state.isBiometricAvailable) {
        state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authBioUnavailable'));
        return false;
      }

      final accounts = _ref.read(accountsProvider);
      if (accounts.isEmpty) {
        state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authNoSavedAccounts'));
        return false;
      }

      state = state.copyWith(status: AuthStatus.connecting);

      final authenticated = await _localAuth.authenticate(
        localizedReason: _l10n().tr('authBioReason'),
      ).timeout(const Duration(seconds: 30), onTimeout: () => false);

      if (!authenticated) {
        state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authBioRejected'));
        await _audit('biometric_failed');
        return false;
      }

      state = state.copyWith(status: AuthStatus.success);
      await _audit('biometric_success');
      return true;
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _l10n().tr('authBioError'));
      return false;
    }
  }

  void reset() {
    state = AuthState(isBiometricAvailable: state.isBiometricAvailable);
  }

  /// Снять ошибку прошлой попытки (новый экран входа).
  void clearError() {
    if (state.status == AuthStatus.connecting) return;
    state = state.copyWith(status: state.status == AuthStatus.error ? AuthStatus.idle : state.status);
  }
}

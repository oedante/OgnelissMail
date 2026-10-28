// lib/services/mail/oauth/oauth_service.dart
// OAuth2 для Google, Яндекс, Yahoo, Mail.ru.
// Через flutter_appauth (системный браузер).

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import 'oauth_proxy_client.dart';
import 'direct_oauth.dart';

final oauthServiceProvider = Provider<OAuthService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return OAuthService(secureStorage);
});

class OAuthResult {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiry;
  final String? email;
  final String? displayName;
  /// Вход без сервера входа (DirectOAuthClient.marker): по этой отметке
  /// токен ящика обновляется прямо у провайдера. null — через сервер входа.
  final String? directClient;

  const OAuthResult({required this.accessToken, this.refreshToken, this.expiry, this.email, this.displayName,
      this.directClient});
}

class OAuthService {
  final SecureStorageService _secureStorage;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  OAuthService(this._secureStorage);

  /// OAuth доступен на всех платформах. Если для провайдера/платформы ещё не
  /// зарегистрирован clientId (плейсхолдер YOUR_...), бросаем понятную ошибку
  /// «вход через этот сервис в сборке не настроен» — пользователь сможет
  /// войти по паролю, а OAuth заработает после регистрации приложения.
  void _ensureOAuthConfigured(String clientId) {
    if (clientId.isEmpty || clientId.startsWith('YOUR_') || clientId.contains('YOUR_')) {
      throw const OAuthNotConfiguredException();
    }
  }

  // ═══════════════ GOOGLE ═══════════════

  Future<OAuthResult> authenticateGoogle() async {
    try {
      _ensureOAuthConfigured(AppConstants.googleClientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConstants.googleClientId,
          AppConstants.googleRedirectUri,
          issuer: 'https://accounts.google.com',
          scopes: ['openid', 'email', 'profile', 'https://mail.google.com/', 'https://www.googleapis.com/auth/calendar', 'https://www.googleapis.com/auth/carddav'],
          preferEphemeralSession: false,
        ),
      );

      if (result == null) throw Exception('Google OAuth: cancelled');

      // Получаем email из userinfo
      final userInfo = await _getUserInfo('https://www.googleapis.com/oauth2/v3/userinfo', result.accessToken!);

      return OAuthResult(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
        email: userInfo?['email'] as String?,
        displayName: userInfo?['name'] as String?,
      );
    } catch (e) {
      AppLogger.error('Google OAuth error', e);
      rethrow;
    }
  }

  // ═══════════════ ЯНДЕКС ═══════════════

  Future<OAuthResult> authenticateYandex() async {
    try {
      _ensureOAuthConfigured(AppConstants.yandexClientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConstants.yandexClientId,
          AppConstants.googleRedirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://oauth.yandex.ru/authorize',
            tokenEndpoint: 'https://oauth.yandex.ru/token',
          ),
          // calendar:all и addressbook:all — CalDAV/CardDAV (caldav/carddav.yandex.ru).
          // Те же права должны быть отмечены в приложении на oauth.yandex.ru.
          scopes: ['mail:imap_full', 'mail:smtp', 'login:info', 'login:email', 'calendar:all', 'addressbook:all'],
        ),
      );

      if (result == null) throw Exception('Yandex OAuth: cancelled');

      final userInfo = await _getUserInfo('https://login.yandex.ru/info?format=json', result.accessToken!);

      return OAuthResult(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
        email: userInfo?['default_email'] as String?,
        displayName: userInfo?['display_name'] as String?,
      );
    } catch (e) {
      AppLogger.error('Yandex OAuth error', e);
      rethrow;
    }
  }

  // ═══════════════ YAHOO ═══════════════

  Future<OAuthResult> authenticateYahoo() async {
    try {
      _ensureOAuthConfigured(AppConstants.yahooClientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConstants.yahooClientId,
          AppConstants.googleRedirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://api.login.yahoo.com/oauth2/request_auth',
            tokenEndpoint: 'https://api.login.yahoo.com/oauth2/get_token',
          ),
          scopes: ['openid', 'email', 'profile', 'mail-w'],
        ),
      );

      if (result == null) throw Exception('Yahoo OAuth: cancelled');

      final userInfo = await _getUserInfo('https://api.login.yahoo.com/openid/v1/userinfo', result.accessToken!);

      return OAuthResult(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
        email: userInfo?['email'] as String?,
        displayName: userInfo?['name'] as String?,
      );
    } catch (e) {
      AppLogger.error('Yahoo OAuth error', e);
      rethrow;
    }
  }

  // ═══════════════ MAIL.RU ═══════════════

  Future<OAuthResult> authenticateMailru() async {
    try {
      _ensureOAuthConfigured(AppConstants.mailruClientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConstants.mailruClientId,
          AppConstants.googleRedirectUri,
          clientSecret: AppConstants.mailruClientSecret,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://oauth.mail.ru/login',
            tokenEndpoint: 'https://oauth.mail.ru/token',
          ),
          // Документация OAuth Mail (2025): openid обязателен, mail.imap —
          // только вместе с ним, refresh_token — с offline_access и
          // prompt=consent. PKCE flutter_appauth добавляет сам.
          scopes: ['openid', 'email', 'profile', 'mail.imap', 'offline_access'],
          additionalParameters: const {'prompt': 'consent'},
        ),
      );

      if (result == null) throw Exception('Mail.ru OAuth: cancelled');

      // Новый адрес userinfo — POST с Bearer; прежний — GET ?access_token=.
      final userInfo = await _postUserInfo('https://oauth.mail.ru/api/v1/oidc/userinfo', result.accessToken!) ??
          await _getUserInfo('https://oauth.mail.ru/userinfo?access_token=${Uri.encodeQueryComponent(result.accessToken!)}', null);

      return OAuthResult(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
        email: userInfo?['email'] as String?,
        displayName: userInfo?['name'] as String?,
      );
    } catch (e) {
      AppLogger.error('Mail.ru OAuth error', e);
      rethrow;
    }
  }

  // ═══════════════ TOKEN REFRESH ═══════════════

  /// Обновить access-токен, если он истёк (или [force] — сервер его уже
  /// отверг). Срок берётся из защищённого хранилища, а не из модели
  /// аккаунта: модель создаётся при входе и хранит срок ПЕРВОГО токена.
  ///
  /// Сборка с OAuth-прокси: обновление через прокси по зашифрованному
  /// refresh-blob (секреты только на сервере). Без прокси — прямой запрос к
  /// token endpoint провайдера по HTTP: работает на всех платформах (раньше
  /// использовался flutter_appauth — на Windows его нет, а Yahoo и Mail.ru
  /// не поддерживались вовсе).
  /// Обновление токена, идущее сейчас, по аккаунту. Одновременные запросы
  /// (синхронизация, push, отправка) ждут одно обновление: раньше каждый
  /// обновлял сам, и провайдеры с одноразовым refresh-токеном (Mail.ru,
  /// Yahoo) отзывали вход после второго обновления тем же токеном.
  static final Map<String, Future<void>> _inflight = {};

  /// Пауза после неудачного обновления: аккаунт → (до какого времени, причина).
  /// Без неё каждая синхронизация, каждый вход IMAP и каждый цикл push снова
  /// шли в прокси (в журнале 06.10 — три запроса на одну синхронизацию Gmail,
  /// и так каждые несколько минут).
  static final Map<String, ({DateTime until, OAuthRefreshFailure failure})> _cooldown = {};

  /// Сбросить паузу (после «Войти снова»).
  static void clearRefreshFailure(String accountId) => _cooldown.remove(accountId);

  Future<void> ensureValidToken(AccountModel account, {bool force = false}) {
    final cd = _cooldown[account.id];
    if (cd != null) {
      if (DateTime.now().isBefore(cd.until)) return Future.error(cd.failure);
      _cooldown.remove(account.id);
    }
    final running = _inflight[account.id];
    if (running != null) return running;
    final f = _ensureValidToken(account, force: force);
    _inflight[account.id] = f;
    return f.whenComplete(() => _inflight.remove(account.id));
  }

  /// Действующий токен ящика (обновляется при необходимости) — для движка
  /// Exchange Online: он просит токен при подключении и после ответа 401.
  Future<String?> validAccessToken(AccountModel account, {bool force = false}) async {
    await ensureValidToken(account, force: force);
    return _secureStorage.getAccessToken(account.id);
  }

  Future<void> _ensureValidToken(AccountModel account, {bool force = false}) async {
    if (!account.usesOAuthTokens) return;
    final exp = await _secureStorage.getTokenExpiry(account.id) ?? account.tokenExpiry;
    if (!force && exp != null && DateTime.now().isBefore(exp.subtract(const Duration(minutes: 2)))) {
      return;
    }

    final refreshToken = await _secureStorage.getRefreshToken(account.id);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException(
          userMessage: 'Сеанс входа истёк — войдите в аккаунт заново',
          messageKey: 'errSessionExpired',
          code: 'OAUTH_NO_REFRESH');
    }
    final provider = _providerName(account.type);

    try {
      // Вход без сервера входа (1.6.2): токен — прямо у провайдера тем же
      // публичным клиентом, что выдал его при входе.
      final marker = await _secureStorage.getOAuthClient(account.id);
      final direct = marker == null ? null : DirectOAuth.fromMarker(marker);
      if (direct != null) {
        final res = await DirectOAuth.refresh(direct, refreshToken);
        await _secureStorage.saveOAuthTokens(
          accountId: account.id,
          accessToken: res.accessToken,
          refreshToken: res.refreshToken ?? refreshToken,
          expiry: res.expiry,
        );
        AppLogger.info('Token refreshed (${direct.provider}, без сервера входа): ${account.email}');
        return;
      }
      final proxy = OAuthProxyClient(_secureStorage);
      if (proxy.isEnabled && provider != null) {
        final res = await proxy.refreshWithBlob(refreshToken, provider);
        await _secureStorage.saveOAuthTokens(
          accountId: account.id,
          accessToken: res.accessToken,
          refreshToken: res.rt,
          expiry: res.expiresAt,
        );
        AppLogger.info('Token refreshed (proxy): ${account.email}');
        return;
      }

      final ep = _tokenEndpoint(account.type);
      if (ep == null) throw Exception('Token refresh not supported for ${account.type}');
      final resp = await http.post(Uri.parse(ep.url), headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      }, body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': ep.clientId,
        if (ep.clientSecret != null && ep.clientSecret!.isNotEmpty) 'client_secret': ep.clientSecret!,
        if (account.type == AccountType.yahoo) 'redirect_uri': AppConstants.googleRedirectUri,
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        // Тело целиком не логируем (может быть токен) — только поле error.
        final why = OAuthProxyClient.describeFailure(resp.statusCode, resp.body);
        throw OAuthRefreshFailure('провайдер: HTTP ${resp.statusCode} ${why.text}',
            needsSignIn: why.needsSignIn, temporary: resp.statusCode >= 500);
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final at = m['access_token'] as String?;
      if (at == null || at.isEmpty) throw Exception('Token refresh: нет access_token');
      final expiresIn = (m['expires_in'] as num?)?.toInt() ?? 3600;
      await _secureStorage.saveOAuthTokens(
        accountId: account.id,
        accessToken: at,
        refreshToken: (m['refresh_token'] as String?) ?? refreshToken,
        expiry: DateTime.now().add(Duration(seconds: expiresIn)),
      );
      AppLogger.info('Token refreshed: ${account.email}');
    } on OAuthRefreshFailure catch (e) {
      // Пауза: отозванный вход — 2 мин (синхронизация перепроверяет его
      // через 3 мин и только тогда просит войти заново; дальше ящик с
      // отметкой «требуется вход» не синхронизируется), сбой прокси или
      // настройки — 10 мин, сеть — 1 мин.
      final pause = e.needsSignIn
          ? const Duration(minutes: 2)
          : e.temporary
              ? const Duration(minutes: 1)
              : const Duration(minutes: 10);
      _cooldown[account.id] = (until: DateTime.now().add(pause), failure: e);
      AppLogger.error('Token refresh failed: ${account.email} — ${e.reason}'
          '${e.needsSignIn ? ' (нужен повторный вход)' : ', повтор через ${pause.inMinutes} мин'}');
      rethrow;
    } catch (e) {
      AppLogger.error('Token refresh failed: ${account.email}', e);
      final f = OAuthRefreshFailure('$e', temporary: true);
      _cooldown[account.id] = (until: DateTime.now().add(const Duration(minutes: 1)), failure: f);
      throw f;
    }
  }

  static String? _providerName(AccountType t) {
    switch (t) {
      case AccountType.google:
        return 'google';
      case AccountType.yandex:
        return 'yandex';
      case AccountType.mailru:
        return 'mailru';
      case AccountType.yahoo:
        return 'yahoo';
      case AccountType.outlook:
        return 'microsoft';
      default:
        return null;
    }
  }

  static ({String url, String clientId, String? clientSecret})? _tokenEndpoint(AccountType t) {
    switch (t) {
      case AccountType.google:
        return (url: 'https://oauth2.googleapis.com/token', clientId: AppConstants.googleClientId, clientSecret: null);
      case AccountType.yandex:
        return (url: 'https://oauth.yandex.ru/token', clientId: AppConstants.yandexClientId, clientSecret: null);
      case AccountType.mailru:
        return (
          url: 'https://oauth.mail.ru/token',
          clientId: AppConstants.mailruClientId,
          clientSecret: AppConstants.mailruClientSecret,
        );
      case AccountType.yahoo:
        return (url: 'https://api.login.yahoo.com/oauth2/get_token', clientId: AppConstants.yahooClientId, clientSecret: null);
      default:
        return null;
    }
  }

  /// Адрес и имя владельца токена. Вход через OAuth-прокси и десктопный
  /// поток возвращают только токены — без адреса XOAUTH2 не войти (раньше
  /// подставлялся «user@gmail.com», и IMAP отвечал отказом).
  Future<({String? email, String? name})> fetchIdentity(AccountType type, String accessToken) async {
    Map<String, dynamic>? info;
    switch (type) {
      case AccountType.google:
        info = await _getUserInfo('https://www.googleapis.com/oauth2/v3/userinfo', accessToken);
        return (email: info?['email'] as String?, name: info?['name'] as String?);
      case AccountType.yandex:
        info = await _getUserInfo('https://login.yandex.ru/info?format=json', accessToken, scheme: 'OAuth');
        // Адрес приходит только с правом login:email; без него (прокси
        // запрашивает лишь права почты) — логин: «ivan» → ivan@yandex.ru,
        // IMAP Яндекса принимает такой адрес для XOAUTH2.
        final login = (info?['login'] as String?)?.trim();
        return (
          email: (info?['default_email'] as String?) ??
              ((info?['emails'] as List?)?.isNotEmpty == true ? (info!['emails'] as List).first as String? : null) ??
              ((login != null && login.isNotEmpty)
                  ? (login.contains('@') ? login : '$login@yandex.ru')
                  : null),
          name: (info?['display_name'] ?? info?['real_name']) as String?,
        );
      case AccountType.mailru:
        // Токен — в теле POST, не в адресе: адрес попадает в журналы и в
        // тексты ошибок (раньше токен Mail.ru мог оказаться в логе).
        // Новый адрес (документация OAuth Mail, 2025) — Bearer в заголовке.
        info = await _postUserInfo('https://oauth.mail.ru/api/v1/oidc/userinfo', accessToken);
        if (info != null && (info['email'] as String?)?.isNotEmpty == true) {
          return (email: info['email'] as String?, name: info['name'] as String?);
        }
        try {
          final r = await http.post(Uri.parse('https://oauth.mail.ru/userinfo'),
              headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {'access_token': accessToken}).timeout(const Duration(seconds: 10));
          if (r.statusCode == 200) info = jsonDecode(r.body) as Map<String, dynamic>;
        } catch (_) {}
        return (email: info?['email'] as String?, name: info?['name'] as String?);
      case AccountType.yahoo:
        info = await _getUserInfo('https://api.login.yahoo.com/openid/v1/userinfo', accessToken);
        return (email: info?['email'] as String?, name: info?['name'] as String?);
      default:
        return (email: null, name: null);
    }
  }

  // ═══════════════ HELPER ═══════════════

  Future<Map<String, dynamic>?> _postUserInfo(String url, String accessToken) async {
    try {
      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body);
        if (j is Map<String, dynamic> && j['error'] == null) return j;
      }
    } catch (e) {
      AppLogger.warning('postUserInfo failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getUserInfo(String url, String? accessToken, {String scheme = 'Bearer'}) async {
    try {
      final response = await http
          .get(Uri.parse(url),
              headers: accessToken == null ? const {} : {'Authorization': '$scheme $accessToken'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.warning('getUserInfo failed: $e');
    }
    return null;
  }
}

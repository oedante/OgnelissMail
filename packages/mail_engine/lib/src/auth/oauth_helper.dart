// lib/src/auth/oauth_helper.dart
// OAuth2 (code-flow + PKCE) для Yandex / Google / Mail.ru.
// Построение URL авторизации и обмен кода на токен.
// PKCE: вызывающий код передаёт готовый codeChallenge (S256) — сам хелпер
// не тянет crypto, чтобы остаться без лишних зависимостей.

import 'dart:convert';
import 'package:http/http.dart' as http;

class OAuthToken {
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  OAuthToken(this.accessToken, {this.refreshToken, this.expiresIn});
}

enum OAuthProvider { yandex, google, mailru }

class OAuthHelper {
  /// Scope по умолчанию для доступа к почте (IMAP/SMTP) у каждого провайдера.
  static List<String> defaultScopes(OAuthProvider p) {
    switch (p) {
      case OAuthProvider.yandex:
        // Почта. Для CalDAV/CardDAV нужны доп. scopes Яндекса — добавьте после
        // сверки с актуальной докой (через переменную YANDEX_SCOPE прокси или сюда).
        return ['mail:imap_full', 'mail:smtp', 'login:email'];
      case OAuthProvider.google:
        // Почта + календарь (CalDAV) + контакты (CardDAV).
        return [
          'https://mail.google.com/',
          'https://www.googleapis.com/auth/userinfo.email',
          'https://www.googleapis.com/auth/calendar.readonly',
          'https://www.googleapis.com/auth/carddav',
        ];
      case OAuthProvider.mailru:
        // openid обязателен (документация OAuth Mail), offline_access — для refresh_token.
        return ['openid', 'email', 'profile', 'mail.imap', 'offline_access'];
    }
  }

  static Uri _authEndpoint(OAuthProvider p) {
    switch (p) {
      case OAuthProvider.yandex:
        return Uri.parse('https://oauth.yandex.ru/authorize');
      case OAuthProvider.google:
        return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
      case OAuthProvider.mailru:
        return Uri.parse('https://oauth.mail.ru/login');
    }
  }

  static Uri _tokenUri(OAuthProvider p) {
    switch (p) {
      case OAuthProvider.yandex:
        return Uri.parse('https://oauth.yandex.ru/token');
      case OAuthProvider.mailru:
        return Uri.parse('https://oauth.mail.ru/token');
      case OAuthProvider.google:
        return Uri.parse('https://oauth2.googleapis.com/token');
    }
  }

  /// URL авторизации. [redirectUri] обязателен для loopback/redirect-флоу
  /// (desktop/web/mobile-scheme). PKCE через [codeChallenge] (метод S256).
  static String authorizeUrl(
    OAuthProvider p,
    String clientId, {
    String? redirectUri,
    List<String>? scopes,
    String? state,
    String? codeChallenge,
    String codeChallengeMethod = 'S256',
  }) {
    final scope = (scopes ?? defaultScopes(p)).join(' ');
    final params = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'scope': scope,
      if (redirectUri != null) 'redirect_uri': redirectUri,
      if (state != null) 'state': state,
      if (codeChallenge != null) ...{
        'code_challenge': codeChallenge,
        'code_challenge_method': codeChallengeMethod,
      },
    };
    // Доп. параметры, специфичные для провайдера.
    switch (p) {
      case OAuthProvider.google:
        params['access_type'] = 'offline';
        params['prompt'] = 'consent';
        break;
      case OAuthProvider.yandex:
        params['force_confirm'] = 'yes';
        break;
      case OAuthProvider.mailru:
        break;
    }
    return _authEndpoint(p).replace(queryParameters: params).toString();
  }

  /// Обмен кода авторизации на токен. [clientSecret] не обязателен для
  /// публичных клиентов с PKCE (desktop/mobile); [codeVerifier] — PKCE.
  static Future<OAuthToken?> exchangeCode({
    required OAuthProvider provider,
    required String clientId,
    String? clientSecret,
    required String code,
    String? redirectUri,
    String? codeVerifier,
  }) async {
    final body = {
      'grant_type': 'authorization_code',
      'code': code.trim(),
      'client_id': clientId,
      if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
      if (redirectUri != null) 'redirect_uri': redirectUri,
      if (codeVerifier != null) 'code_verifier': codeVerifier,
    };
    final resp = await http.post(_tokenUri(provider),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body);
    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = j['access_token'] as String?;
      if (token == null) return null;
      return OAuthToken(token,
          refreshToken: j['refresh_token'] as String?,
          expiresIn: (j['expires_in'] as num?)?.toInt());
    }
    throw Exception('Token exchange HTTP ${resp.statusCode}: ${resp.body}');
  }

  /// Обновление access-token по refresh-token.
  static Future<OAuthToken?> refresh({
    required OAuthProvider provider,
    required String clientId,
    String? clientSecret,
    required String refreshToken,
  }) async {
    final body = {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
      if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
    };
    final resp = await http.post(_tokenUri(provider),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body);
    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = j['access_token'] as String?;
      if (token == null) return null;
      return OAuthToken(token,
          refreshToken: (j['refresh_token'] as String?) ?? refreshToken,
          expiresIn: (j['expires_in'] as num?)?.toInt());
    }
    throw Exception('Token refresh HTTP ${resp.statusCode}: ${resp.body}');
  }
}

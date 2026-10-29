// lib/services/mail/oauth/direct_oauth.dart
// Вход без сервера входа (1.6.2, решение владельца 13.10.2026): приложение
// само — публичный клиент провайдера (OAuth 2.0 для установленных
// приложений, RFC 8252) с PKCE (RFC 7636). Секретов в приложении нет;
// код обменивается на токены прямо у провайдера, обновление токена — тоже.
//
// Провайдеры:
//   • google    — Gmail (IMAP/SMTP), календарь и контакты Google;
//   • microsoft — Outlook.com / Hotmail (IMAP/SMTP);
//   • exchange  — Exchange Online (Microsoft 365) по ActiveSync и EWS.
//
// Идентификаторы клиентов — при сборке (config/dart_defines.json, не
// секреты, но свои у каждой сборки):
//   GOOGLE_ANDROID_CLIENT_ID — клиент «Android» в Google Cloud Console
//     (пакет com.ogneliss.mail + SHA-1 ключа подписи Google Play), в его
//     «Дополнительных настройках» включить «Custom URI scheme»;
//   GOOGLE_IOS_CLIENT_ID — клиент «iOS» (Bundle ID com.ogneliss.mail);
//   GOOGLE_DESKTOP_CLIENT_ID / GOOGLE_DESKTOP_CLIENT_SECRET — клиент
//     «Desktop app» (секрет такого клиента Google секретом не считает);
//   MS_CLIENT_ID — регистрация приложения в Microsoft Entra: «Accounts in any
//     organizational directory and personal Microsoft accounts», платформа
//     «Mobile and desktop applications», адреса возврата
//     com.ogneliss.mail://oauth/microsoft и http://localhost; «Allow public
//     client flows» = Yes. Адреса возврата — именно в платформе «Mobile and
//     desktop applications» (не «Web»): иначе login.live.com отвечает
//     «redirect_uri is not valid». Exchange Online входит через
//     /organizations (только рабочие учётные записи), Outlook.com — /common. API permissions (Delegated): Office 365 Exchange
//     Online → EAS.AccessAsUser.All, EWS.AccessAsUser.All; IMAP.AccessAsUser.All,
//     SMTP.Send; offline_access, openid, email, profile.
//     Microsoft Graph для Exchange Online (1.8.10, [graphConsentScopes]):
//     User.Read, User.ReadBasic.All, People.Read, Mail.ReadWrite,
//     MailboxSettings.ReadWrite; по желанию (согласие администратора) —
//     Place.Read.All (переговорные) и GroupMember.Read.All (состав рассылок).
// Клиент не задан — вход идёт как раньше (через сервер входа, если он есть).
//
// Microsoft Graph (1.8.10, замечание владельца 29.10.2026: Microsoft
// переводит Exchange Online с EWS на Graph — EWS отключается с октября 2026,
// окончательно в апреле 2027). При входе в Exchange Online приложение просит
// согласие и на права Graph; токен Graph — отдельный, его выдаёт тот же
// refresh-токен (graph_tokens.dart; запросы — движок, me.GraphEngine). Организация не
// разрешает такие права без администратора — вход повторяется без них
// (ActiveSync работает и так).
//
// Адреса возврата: телефон — своя схема приложения (com.ogneliss.mail),
// её перехватывает flutter_web_auth_2 (Custom Tabs / ASWebAuthenticationSession);
// компьютер — loopback 127.0.0.1/localhost на свободном порту.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/app_logger.dart';
import 'oauth_service.dart' show OAuthResult;
import 'proxy_pkce.dart' show OAuthProviderError;

/// Публичный клиент провайдера для этой платформы.
class DirectOAuthClient {
  /// 'google' | 'microsoft' | 'exchange'.
  final String provider;
  final String clientId;
  /// Только у клиента Google «Desktop app» (Google требует его при обмене
  /// кода и не считает секретом).
  final String? clientSecret;
  final Uri authorizeEndpoint;
  final Uri tokenEndpoint;
  final List<String> scopes;

  /// Права, на которые просится согласие при входе, если их больше, чем у
  /// токена ([scopes]): Exchange Online — ещё и Microsoft Graph. Токен
  /// выдаётся только на [scopes] (один ресурс на токен), токен Graph — по
  /// тому же refresh-токену отдельно. null — как [scopes].
  final List<String>? consentScopes;
  final Map<String, String> extraParams;

  const DirectOAuthClient({
    required this.provider,
    required this.clientId,
    this.clientSecret,
    required this.authorizeEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
    this.consentScopes,
    this.extraParams = const {},
  });

  /// Тот же клиент без дополнительных прав при входе.
  DirectOAuthClient withoutExtraConsent() => DirectOAuthClient(
        provider: provider,
        clientId: clientId,
        clientSecret: clientSecret,
        authorizeEndpoint: authorizeEndpoint,
        tokenEndpoint: tokenEndpoint,
        scopes: scopes,
        extraParams: extraParams,
      );

  /// Отметка для хранилища: по ней обновляется токен ящика.
  String get marker => '$provider|$clientId';
}

class DirectOAuth {
  DirectOAuth._();

  static const _googleAndroid = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
  static const _googleIos = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const _googleDesktop = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _googleDesktopSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const _ms = String.fromEnvironment('MS_CLIENT_ID');

  /// Своя схема приложения (AndroidManifest, Info.plist).
  static const appScheme = 'com.ogneliss.mail';

  static bool get _mobile => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  static bool get _desktop => Platform.isWindows || Platform.isLinux;

  static final _googleAuth = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
  static final _googleToken = Uri.parse('https://oauth2.googleapis.com/token');
  static final _msAuth = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
  static final _msToken = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/token');
  // Exchange Online (1.6.9): только рабочие и учебные учётные записи. Через
  // «common» личная учётная запись (Outlook.com, адрес Gmail как логин
  // Microsoft) уходила на login.live.com, и тот отвечал «redirect_uri is not
  // valid» — а ActiveSync и EWS по OAuth личным ящикам и не положены.
  static final _orgAuth = Uri.parse('https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize');
  static final _orgToken = Uri.parse('https://login.microsoftonline.com/organizations/oauth2/v2.0/token');

  static const _googleScopes = [
    'openid', 'email', 'profile',
    'https://mail.google.com/',
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/carddav',
  ];
  static const _outlookScopes = [
    'openid', 'email', 'profile', 'offline_access',
    'https://outlook.office.com/IMAP.AccessAsUser.All',
    'https://outlook.office.com/SMTP.Send',
  ];
  /// ActiveSync и EWS — один ресурс (outlook.office365.com), один токен.
  static const _exchangeScopes = [
    'openid', 'email', 'profile', 'offline_access',
    'https://outlook.office365.com/EAS.AccessAsUser.All',
    'https://outlook.office365.com/EWS.AccessAsUser.All',
  ];

  /// Microsoft Graph для Exchange Online (1.8.10): права, на которые
  /// просится согласие при входе (список — в движке,
  /// me.GraphEngine.consentScopes). Все — без согласия администратора:
  /// User.Read — своя карточка и фото; User.ReadBasic.All — фото коллег;
  /// People.Read — должность, отдел и телефоны коллег; Mail.ReadWrite —
  /// подсказки MailTips и «Восстановить удалённые»;
  /// MailboxSettings.ReadWrite — правила сервера. Права с согласием
  /// администратора (Place.Read.All, GroupMember.Read.All) при входе не
  /// просятся: обычный сотрудник не смог бы войти; если администратор их
  /// выдал организации, токен ([graphScopes]) получит их сам.
  static const graphConsentScopes = me.GraphEngine.consentScopes;

  /// Токен Graph — со всеми правами, на которые есть согласие (свои при
  /// входе и выданные администратором организации).
  static const graphScopes = me.GraphEngine.tokenScopes;

  /// Клиент для токена Graph ящика Exchange Online по отметке клиента входа
  /// ([DirectOAuthClient.marker]); null — ящик вошёл не как Exchange Online.
  static DirectOAuthClient? graphClient(String marker) {
    final i = marker.indexOf('|');
    if (i <= 0 || marker.substring(0, i) != 'exchange') return null;
    return DirectOAuthClient(
      provider: 'exchange',
      clientId: marker.substring(i + 1),
      authorizeEndpoint: _orgAuth,
      tokenEndpoint: _orgToken,
      scopes: graphScopes,
    );
  }

  /// Отказ, после которого вход стоит повторить без дополнительных прав
  /// (1.8.10): организация требует согласия администратора (AADSTS90094,
  /// 90095, 65001), человек отказался от новых прав (65004), права неизвестны
  /// регистрации (650057, invalid_scope).
  static bool isConsentError(String code, String? detail) {
    final d = (detail ?? '').toUpperCase();
    const codes = {'consent_required', 'invalid_scope', 'interaction_required'};
    const aadsts = ['AADSTS65001', 'AADSTS65004', 'AADSTS90094', 'AADSTS90095', 'AADSTS650057', 'AADSTS90008'];
    return codes.contains(code) || aadsts.any(d.contains);
  }

  /// Клиент для [provider] на этой платформе; null — в сборке не задан.
  static DirectOAuthClient? clientFor(String provider) {
    switch (provider) {
      case 'google':
        final id = Platform.isAndroid
            ? _googleAndroid
            : (Platform.isIOS || Platform.isMacOS)
                ? _googleIos
                : _desktop
                    ? _googleDesktop
                    : '';
        if (id.isEmpty) return null;
        return DirectOAuthClient(
          provider: 'google',
          clientId: id,
          clientSecret: _desktop && _googleDesktopSecret.isNotEmpty ? _googleDesktopSecret : null,
          authorizeEndpoint: _googleAuth,
          tokenEndpoint: _googleToken,
          scopes: _googleScopes,
          // refresh_token выдаётся только с access_type=offline; consent —
          // чтобы он пришёл и при повторном входе.
          extraParams: const {'access_type': 'offline', 'prompt': 'consent'},
        );
      case 'microsoft':
      case 'exchange':
        if (_ms.isEmpty || !(_mobile || _desktop)) return null;
        return DirectOAuthClient(
          provider: provider,
          clientId: _ms,
          authorizeEndpoint: provider == 'exchange' ? _orgAuth : _msAuth,
          tokenEndpoint: provider == 'exchange' ? _orgToken : _msToken,
          scopes: provider == 'exchange' ? _exchangeScopes : _outlookScopes,
          consentScopes: provider == 'exchange' ? [..._exchangeScopes, ...graphConsentScopes] : null,
          extraParams: const {'prompt': 'select_account'},
        );
    }
    return null;
  }

  /// Клиент по отметке, сохранённой при входе (для обновления токена).
  /// Секрет клиента Google «Desktop app» берётся из сборки.
  static DirectOAuthClient? fromMarker(String marker) {
    final i = marker.indexOf('|');
    if (i <= 0) return null;
    final provider = marker.substring(0, i);
    final id = marker.substring(i + 1);
    final isGoogle = provider == 'google';
    final List<String> scopes = switch (provider) {
      'google' => _googleScopes,
      'exchange' => _exchangeScopes,
      _ => _outlookScopes,
    };
    return DirectOAuthClient(
      provider: provider,
      clientId: id,
      clientSecret: isGoogle && id == _googleDesktop && _googleDesktopSecret.isNotEmpty ? _googleDesktopSecret : null,
      authorizeEndpoint: isGoogle ? _googleAuth : (provider == 'exchange' ? _orgAuth : _msAuth),
      tokenEndpoint: isGoogle ? _googleToken : (provider == 'exchange' ? _orgToken : _msToken),
      scopes: scopes,
    );
  }

  /// Адрес возврата на телефоне. Google принимает для клиентов Android и iOS
  /// схему пакета с одним «/», Microsoft — любой адрес из регистрации.
  static String _mobileRedirect(String provider) =>
      provider == 'google' ? '$appScheme:/oauth2redirect' : '$appScheme://oauth/microsoft';

  /// Вход: браузер → провайдер → код → токены. [loginHint] — адрес ящика
  /// («Войти снова»), чтобы провайдер сразу предложил нужную учётную запись.
  static Future<OAuthResult> authenticate(DirectOAuthClient c, {String? loginHint}) async {
    try {
      return await _authenticate(c, loginHint: loginHint);
    } on OAuthProviderError catch (e) {
      // Права Graph организация без администратора не даёт (или человек от
      // них отказался) — вход заново без них: ActiveSync работает и так.
      if (c.consentScopes == null || !isConsentError(e.code, e.detail)) rethrow;
      AppLogger.warning('OAuth (${c.provider}): согласие на Microsoft Graph не получено (${e.code}) — вход без Graph');
      return _authenticate(c.withoutExtraConsent(), loginHint: loginHint);
    }
  }

  static Future<OAuthResult> _authenticate(DirectOAuthClient c, {String? loginHint}) async {
    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(24);

    HttpServer? loopback;
    final String redirect;
    if (_desktop) {
      loopback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // Google — IP петли, Microsoft регистрирует http://localhost (любой порт).
      redirect = c.provider == 'google'
          ? 'http://127.0.0.1:${loopback.port}/'
          : 'http://localhost:${loopback.port}/';
    } else {
      redirect = _mobileRedirect(c.provider);
    }
    final url = c.authorizeEndpoint.replace(queryParameters: {
      'response_type': 'code',
      'client_id': c.clientId,
      'redirect_uri': redirect,
      'scope': (c.consentScopes ?? c.scopes).join(' '),
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
      ...c.extraParams,
    });
    AppLogger.info('OAuth (${c.provider}): вход без сервера входа, возврат на '
        '${_desktop ? 'loopback' : redirect}');

    Map<String, String> q;
    try {
      if (loopback != null) {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw const AuthException(
              userMessage: 'Не удалось открыть браузер для OAuth', messageKey: 'oauthBrowserFailed');
        }
        final req = await loopback.first.timeout(const Duration(minutes: 5));
        q = req.uri.queryParameters;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<html><head><meta charset="utf-8"></head><body style="font-family:sans-serif;'
              'text-align:center;padding-top:48px"><h3>Ogneliss Mail</h3><p>✓</p></body></html>');
        await req.response.close();
      } else {
        final result = await FlutterWebAuth2.authenticate(
          url: url.toString(),
          callbackUrlScheme: appScheme,
          // Системный браузер: Google и Microsoft не пускают во встроенный.
          options: const FlutterWebAuth2Options(useWebview: false, timeout: 300),
        );
        q = Uri.parse(result).queryParameters;
      }
    } finally {
      await loopback?.close(force: true);
    }

    final err = q['error'];
    if (err != null && err.isNotEmpty) {
      AppLogger.warning('OAuth (${c.provider}): провайдер вернул $err');
      throw OAuthProviderError(err, q['error_description']);
    }
    // Ответ без нашего state — не наш вход (CSRF).
    if (q['state'] != state) {
      throw const AuthException(
          userMessage: 'OAuth: несовпадение state (защита от CSRF)', messageKey: 'oauthStateMismatch');
    }
    final code = q['code'];
    if (code == null || code.isEmpty) {
      throw const AuthException(userMessage: 'OAuth: код авторизации не получен', messageKey: 'oauthNoCode');
    }

    final resp = await http.post(c.tokenEndpoint, headers: const {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    }, body: {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': c.clientId,
      if (c.clientSecret != null) 'client_secret': c.clientSecret!,
      'redirect_uri': redirect,
      'code_verifier': verifier,
      // Microsoft: права токена — одного ресурса (без Graph, если согласие
      // на него просилось вместе со входом).
      if (c.provider != 'google') 'scope': c.scopes.join(' '),
    }).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final why = describeRefreshFailure(c, resp.statusCode, resp.body);
      AppLogger.error('OAuth (${c.provider}): обмен кода — HTTP ${resp.statusCode} ${why.text}');
      throw OAuthProviderError('token_exchange', why.text);
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    final at = m['access_token'] as String?;
    if (at == null || at.isEmpty) {
      throw const AuthException(userMessage: 'OAuth: токен не получен', messageKey: 'oauthNoToken');
    }
    final claims = idTokenClaims(m['id_token'] as String?);
    final email = (claims['email'] ?? claims['preferred_username'] ?? claims['upn']) as String?;
    AppLogger.info('OAuth (${c.provider}): токен получен');
    return OAuthResult(
      accessToken: at,
      refreshToken: m['refresh_token'] as String?,
      expiry: DateTime.now().add(Duration(seconds: (m['expires_in'] as num?)?.toInt() ?? 3600)),
      email: (email != null && email.contains('@')) ? email : null,
      displayName: claims['name'] as String?,
      directClient: c.marker,
      graphConsent: c.consentScopes != null,
    );
  }

  /// Обновить токен прямо у провайдера. Microsoft может прислать новый
  /// refresh-токен — его нужно сохранить вместо прежнего.
  static Future<({String accessToken, String? refreshToken, DateTime expiry})> refresh(
      DirectOAuthClient c, String refreshToken) async {
    final resp = await http.post(c.tokenEndpoint, headers: const {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    }, body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': c.clientId,
      if (c.clientSecret != null) 'client_secret': c.clientSecret!,
      if (c.provider != 'google') 'scope': c.scopes.join(' '),
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      final f = describeRefreshFailure(c, resp.statusCode, resp.body,
          currentClientId: clientFor(c.provider)?.clientId);
      throw OAuthRefreshFailure(f.text, needsSignIn: f.needsSignIn, temporary: resp.statusCode >= 500);
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    final at = m['access_token'] as String?;
    if (at == null || at.isEmpty) throw OAuthRefreshFailure('${c.provider}: нет access_token', temporary: true);
    return (
      accessToken: at,
      refreshToken: m['refresh_token'] as String?,
      expiry: DateTime.now().add(Duration(seconds: (m['expires_in'] as num?)?.toInt() ?? 3600)),
    );
  }

  /// Причина отказа обновления токена у самого провайдера (1.6.9). Раньше
  /// текст был общим с сервером входа — «провайдер не принял клиент прокси,
  /// проверьте CLIENT_ID/CLIENT_SECRET на сервере», хотя сервера входа здесь
  /// нет. Поля error и error_description токенов не содержат.
  ///
  /// invalid_client / unauthorized_client: провайдер не знает клиента, которым
  /// выполнен вход (клиент удалён или пересоздан, у сборки другой клиент) —
  /// этим входом обновить токен уже нельзя, нужен повторный вход.
  static ({String text, bool needsSignIn}) describeRefreshFailure(
      DirectOAuthClient c, int status, String body, {String? currentClientId}) {
    var err = '';
    var desc = '';
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        if (m['error'] is String) err = m['error'] as String;
        if (m['error_description'] is String) desc = (m['error_description'] as String).split('\n').first.trim();
      }
    } catch (_) {}
    if (desc.length > 160) desc = '${desc.substring(0, 160)}…';
    final who = switch (c.provider) { 'google' => 'Google', _ => 'Microsoft' };
    final detail = [if (err.isNotEmpty) err, if (desc.isNotEmpty) desc].join(': ');
    final e = err.toLowerCase();
    if (e == 'invalid_client' || e == 'unauthorized_client') {
      final changed = currentClientId != null && currentClientId != c.clientId;
      return (
        text: '$who не принял клиент приложения, которым выполнен вход ($detail)'
            '${changed ? ' — в этой сборке другой клиент' : ''}; нужен повторный вход',
        needsSignIn: true,
      );
    }
    if (e == 'invalid_grant' || e == 'interaction_required') {
      return (text: '$who: вход отозван или истёк ($detail) — нужен повторный вход', needsSignIn: true);
    }
    return (
      text: '$who: HTTP $status${detail.isEmpty ? '' : ' ($detail)'}',
      needsSignIn: false,
    );
  }

  /// Поля id_token (JWT) без проверки подписи: токен пришёл напрямую от
  /// провайдера по TLS в ответ на наш запрос (OpenID Connect 3.1.3.7, п. 6),
  /// и из него берутся только адрес и имя для показа.
  static Map<String, dynamic> idTokenClaims(String? idToken) {
    if (idToken == null) return const {};
    final parts = idToken.split('.');
    if (parts.length < 2) return const {};
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final v = jsonDecode(json);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _random(int n) {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(n, (_) => r.nextInt(256))).replaceAll('=', '');
  }
}

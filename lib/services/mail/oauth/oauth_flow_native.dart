// lib/services/mail/oauth/oauth_flow_native.dart
// Desktop (Windows/Linux) OAuth: loopback HTTP-сервер на 127.0.0.1 + системный
// браузер. PKCE (S256). Используется и как заглушка-замена web-варианта при
// сборке под io (web-функция тут не вызывается).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import 'proxy_pkce.dart';

Future<me.OAuthToken?> runOAuth({
  required me.OAuthProvider provider,
  required String clientId,
  String? clientSecret,
  String doneTitle = 'Authorization complete',
  String doneText = 'You can close this window and return to the app.',
}) async {
  final verifier = _verifier();
  final challenge = _challenge(verifier);
  final state = _verifier().substring(0, 16);

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = 'http://127.0.0.1:${server.port}/';
  final url = me.OAuthHelper.authorizeUrl(
    provider,
    clientId,
    redirectUri: redirectUri,
    state: state,
    codeChallenge: challenge,
  );

  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    await server.close(force: true);
    throw const AuthException(
        userMessage: 'Не удалось открыть браузер для OAuth', messageKey: 'oauthBrowserFailed');
  }

  try {
    final req = await server.first.timeout(const Duration(minutes: 5));
    final code = req.uri.queryParameters['code'];
    final returnedState = req.uri.queryParameters['state'];
    final err = req.uri.queryParameters['error'];
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_donePage(doneTitle, doneText));
    await req.response.close();

    if (err != null) throw Exception('OAuth error: $err');
    if (code == null) {
      throw const AuthException(
          userMessage: 'OAuth: код авторизации не получен', messageKey: 'oauthNoCode');
    }
    // Ответ без state тоже отвергаем: иначе посторонняя страница могла бы
    // прислать на localhost свой code без state (CSRF).
    if (returnedState != state) {
      throw const AuthException(
          userMessage: 'OAuth: несовпадение state (защита от CSRF)', messageKey: 'oauthStateMismatch');
    }
    return await me.OAuthHelper.exchangeCode(
      provider: provider,
      clientId: clientId,
      clientSecret: clientSecret,
      code: code,
      redirectUri: redirectUri,
      codeVerifier: verifier,
    );
  } finally {
    await server.close(force: true);
  }
}

/// Страница, которую браузер показывает после возврата на loopback.
String _donePage(String title, String text) {
  const esc = HtmlEscape();
  return '<html><head><meta charset="utf-8"></head>'
      '<body style="font-family:sans-serif;text-align:center;padding-top:48px">'
      '<h3>${esc.convert(title)}</h3>'
      '<p>${esc.convert(text)}</p>'
      '</body></html>';
}

String _verifier() {
  final r = Random.secure();
  final bytes = List<int>.generate(64, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _challenge(String v) =>
    base64Url.encode(sha256.convert(ascii.encode(v)).bytes).replaceAll('=', '');

/// Desktop-вход через корпоративный OAuth-прокси (loopback + браузер).
/// Прокси сам обменивает код и возвращает на loopback `?at&exp&rt&provider`.
/// at → accessToken, rt (зашифрованный refresh-blob) → refreshToken.
Future<me.OAuthToken?> runOAuthViaProxy({
  required String proxyBaseUrl,
  required String provider,
  String doneTitle = 'Authorization complete',
  String doneText = 'You can close this window and return to the app.',
}) async {
  // Без ключа POST /exchange вернёт 401 уже после входа у провайдера.
  if (AppConstants.oauthProxyApiKey.isEmpty) {
    throw AuthException(
      userMessage: 'OAuth ($provider): приложение собрано без ключа OAuth-прокси '
          '(OAUTH_PROXY_KEY). Обратитесь к администратору.',
      messageKey: 'oauthNoProxyKey',
      messageArgs: {'provider': provider},
    );
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = 'http://127.0.0.1:${server.port}/';
  final base = proxyBaseUrl.replaceAll(RegExp(r'/$'), '');
  final pkce = ProxyPkce.generate();
  final url = '$base/oauth/$provider/login?redirect=${Uri.encodeComponent(redirectUri)}'
      '&cc=${pkce.challenge}';

  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    await server.close(force: true);
    throw const AuthException(
        userMessage: 'Не удалось открыть браузер для OAuth (прокси)', messageKey: 'oauthBrowserFailed');
  }
  try {
    final req = await server.first.timeout(const Duration(minutes: 5));
    final raw = req.uri.queryParameters;
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_donePage(doneTitle, doneText));
    await req.response.close();

    final p = await pkce.resolve(base, raw);
    final at = p['at'];
    if (at == null || at.isEmpty) {
      final err = p['error'];
      final details = err != null ? ' ($err)' : '';
      throw AuthException(
        userMessage: 'OAuth (прокси): токен не получен$details',
        messageKey: 'oauthNoToken',
        messageArgs: {'provider': provider, 'details': details},
      );
    }
    final expMs = int.tryParse(p['exp'] ?? '') ?? 0;
    var expiresIn = expMs > 0
        ? ((expMs - DateTime.now().millisecondsSinceEpoch) / 1000).round()
        : 3600;
    if (expiresIn <= 0) expiresIn = 3600;
    return me.OAuthToken(at, refreshToken: p['rt'], expiresIn: expiresIn);
  } finally {
    await server.close(force: true);
  }
}

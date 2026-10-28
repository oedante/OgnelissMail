// lib/services/mail/oauth/oauth_flow_web.dart
// Web OAuth: всплывающее окно + callback-страница web/oauth2redirect.html,
// которая возвращает код через postMessage. PKCE (S256).

import 'dart:async';
import 'dart:convert';
// Файл подключается только в веб-сборке (условный импорт).
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/errors/app_exceptions.dart';

Future<me.OAuthToken?> runOAuth({
  required me.OAuthProvider provider,
  required String clientId,
  String? clientSecret,
  // Для совместимости с native-версией: страницу возврата здесь
  // показывает web/oauth2redirect.html.
  String doneTitle = '',
  String doneText = '',
}) async {
  final verifier = _verifier();
  final challenge = _challenge(verifier);
  final state = _verifier().substring(0, 16);
  final origin = html.window.location.origin;
  final redirectUri = '$origin/oauth2redirect.html';

  final url = me.OAuthHelper.authorizeUrl(
    provider,
    clientId,
    redirectUri: redirectUri,
    state: state,
    codeChallenge: challenge,
  );

  final popup = html.window.open(url, 'oauth_popup', 'width=520,height=660');
  final completer = Completer<String?>();
  late StreamSubscription<html.MessageEvent> sub;
  sub = html.window.onMessage.listen((event) {
    final data = event.data;
    if (data is! String || !data.startsWith('oauth-result:')) return;
    final params = Uri.splitQueryString(data.substring('oauth-result:'.length));
    if (params['error'] != null) {
      if (!completer.isCompleted) completer.completeError(Exception('OAuth error: ${params['error']}'));
    } else if (params['code'] != null && params['state'] == state) {
      if (!completer.isCompleted) completer.complete(params['code']);
    }
    sub.cancel();
    popup.close();
  });

  final code = await completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      sub.cancel();
      popup.close();
      return null;
    },
  );
  if (code == null) return null;

  return me.OAuthHelper.exchangeCode(
    provider: provider,
    clientId: clientId,
    clientSecret: clientSecret,
    code: code,
    redirectUri: redirectUri,
    codeVerifier: verifier,
  );
}

String _verifier() {
  final r = Random.secure();
  final bytes = List<int>.generate(64, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _challenge(String v) =>
    base64Url.encode(sha256.convert(ascii.encode(v)).bytes).replaceAll('=', '');

/// На web вход через прокси пока не поддерживается (используется popup-флоу).
Future<me.OAuthToken?> runOAuthViaProxy({
  required String proxyBaseUrl,
  required String provider,
  String doneTitle = '',
  String doneText = '',
}) async {
  throw const AuthException(
      userMessage: 'OAuth через прокси на web пока не поддерживается',
      messageKey: 'oauthProxyWebUnsupported');
}

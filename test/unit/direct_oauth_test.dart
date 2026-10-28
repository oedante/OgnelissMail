// Вход без сервера входа (1.6.2): отметка клиента для обновления токена и
// адрес из id_token Microsoft/Google.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.sig';
}

void main() {
  test('id_token: адрес и имя', () {
    final c = DirectOAuth.idTokenClaims(_jwt({'preferred_username': 'ivan@corp.onmicrosoft.com', 'name': 'Иван Петров'}));
    expect(c['preferred_username'], 'ivan@corp.onmicrosoft.com');
    expect(c['name'], 'Иван Петров');
  });

  test('id_token: мусор и отсутствие — пусто', () {
    expect(DirectOAuth.idTokenClaims(null), isEmpty);
    expect(DirectOAuth.idTokenClaims('abc'), isEmpty);
    expect(DirectOAuth.idTokenClaims('a.%%%.c'), isEmpty);
  });

  test('отметка клиента: провайдер, адреса и права', () {
    final ex = DirectOAuth.fromMarker('exchange|11111111-2222-3333-4444-555555555555')!;
    expect(ex.provider, 'exchange');
    expect(ex.clientId, '11111111-2222-3333-4444-555555555555');
    expect(ex.tokenEndpoint.host, 'login.microsoftonline.com');
    expect(ex.scopes, contains('https://outlook.office365.com/EAS.AccessAsUser.All'));
    expect(ex.scopes, contains('offline_access'));
    expect(ex.clientSecret, isNull);
    expect(ex.marker, 'exchange|11111111-2222-3333-4444-555555555555');

    final g = DirectOAuth.fromMarker('google|123-abc.apps.googleusercontent.com')!;
    expect(g.tokenEndpoint.host, 'oauth2.googleapis.com');
    expect(g.scopes, contains('https://mail.google.com/'));

    expect(DirectOAuth.fromMarker('без разделителя'), isNull);
  });
}

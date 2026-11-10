// Вход в Яндекс без сервера (2.2.0, решение владельца 10.11.2026): адрес
// возврата yx<ClientID>:///auth/finish, как у LoginSDK Яндекса; схему ловит
// CallbackActivity в AndroidManifest; адрес и имя — из login.yandex.ru/info.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/constants/app_constants.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';

void main() {
  test('адрес возврата Яндекса — схема yx<ClientID>, платформа телефона', () {
    const id = AppConstants.yandexClientId;
    expect(DirectOAuth.mobileRedirect('yandex', android: true), 'yx$id:///auth/finish?platform=android');
    expect(DirectOAuth.mobileRedirect('yandex'), 'yx$id:///auth/finish?platform=ios');
    expect(DirectOAuth.mobileRedirect('google'), 'com.ogneliss.mail:/oauth2redirect');
    expect(DirectOAuth.mobileRedirect('microsoft'), 'com.ogneliss.mail://oauth/microsoft');
    // Ответ Яндекса — тот же адрес с кодом: разбирается обычным Uri.
    final back = Uri.parse('yx$id:///auth/finish?platform=android&code=1234567&state=abc');
    expect(back.scheme, 'yx$id');
    expect(back.queryParameters['code'], '1234567');
    expect(back.queryParameters['state'], 'abc');
  });

  test('AndroidManifest ловит схему Яндекса из AppConstants', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:scheme="${DirectOAuth.yandexScheme(AppConstants.yandexClientId)}"'));
    expect(AppConstants.yandexClientId, matches(RegExp(r'^[0-9a-f]+$')), reason: 'схема Android — строчные буквы');
  });

  test('обновление токена по отметке yandex|<id> — у oauth.yandex.ru', () {
    final c = DirectOAuth.fromMarker('yandex|${AppConstants.yandexClientId}')!;
    expect(c.provider, 'yandex');
    expect(c.tokenEndpoint.toString(), 'https://oauth.yandex.ru/token');
    expect(c.clientSecret, isNull);
    expect(c.scopes, isEmpty, reason: 'права — из регистрации приложения');
  });

  test('адрес и имя из login.yandex.ru/info', () {
    expect(
        DirectOAuth.yandexClaims({
          'login': 'ivan.petrov',
          'default_email': 'ivan.petrov@yandex.ru',
          'real_name': 'Иван Петров',
          'display_name': 'ivan.petrov',
        }),
        {'email': 'ivan.petrov@yandex.ru', 'name': 'Иван Петров'});
    expect(DirectOAuth.yandexClaims({'login': 'anna', 'emails': ['anna@ya.ru']}), {'email': 'anna@ya.ru'});
    expect(DirectOAuth.yandexClaims({'login': 'oleg', 'display_name': 'Олег'}), {'email': 'oleg@yandex.ru', 'name': 'Олег'});
    expect(DirectOAuth.yandexClaims('мусор'), isEmpty);
  });

  test('отказ обновления — «Яндекс», invalid_grant — повторный вход', () {
    final c = DirectOAuth.fromMarker('yandex|${AppConstants.yandexClientId}')!;
    final f = DirectOAuth.describeRefreshFailure(c, 400, '{"error":"invalid_grant","error_description":"expired"}');
    expect(f.text, startsWith('Яндекс'));
    expect(f.needsSignIn, isTrue);
  });
}

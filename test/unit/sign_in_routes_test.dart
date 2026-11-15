// Маршруты входа (2.5.5, решение владельца 15.11.2026): Google, Microsoft и
// Яндекс на телефонах и Mac — напрямую у службы; сервер входа — только для
// Яндекса на Windows и Linux. Google и Microsoft через сервер не идут
// никогда — на сервере нет их ключей, токены Google его не касаются.

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/oauth/cross_platform_oauth.dart';

void main() {
  test('через сервер входа — только Яндекс и только на Windows и Linux', () {
    final desktop = Platform.isWindows || Platform.isLinux;
    expect(CrossPlatformOAuthService.yandexViaServer('yandex'), desktop);
    for (final p in ['google', 'microsoft', 'exchange', 'mailru', 'yahoo']) {
      expect(CrossPlatformOAuthService.yandexViaServer(p), isFalse, reason: p);
    }
  });

  test('без клиента службы в сборке — вход через службу недоступен (кроме Яндекса на компьютере)', () {
    const s = CrossPlatformOAuthService();
    // В тестах клиентов служб нет (ключи сборки не заданы).
    expect(s.available('google'), isFalse);
    expect(s.available('microsoft'), isFalse);
    expect(s.available('yandex'), Platform.isWindows || Platform.isLinux);
  });
}

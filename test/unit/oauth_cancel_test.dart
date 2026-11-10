// Отмена входа — не ошибка (2.2.1, журнал владельца 10.11.2026: закрытое
// окно входа Google показывалось строкой «PlatformException(CANCELED…)»).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/oauth/proxy_pkce.dart';

void main() {
  test('закрытое окно входа — отмена, как access_denied', () {
    expect(OAuthProviderError.isUserCancel(PlatformException(code: 'CANCELED', message: 'User canceled authentication')),
        isTrue);
    expect(OAuthProviderError.isUserCancel(PlatformException(code: 'TIMEOUT')), isFalse);
    expect(OAuthProviderError.isUserCancel(Exception('CANCELED')), isFalse);
    expect(const OAuthProviderError('access_denied').cancelled, isTrue);
    expect(const OAuthProviderError('invalid_scope').cancelled, isFalse);
  });
}

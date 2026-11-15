// Лимит пользователей Google у непроверенного приложения (2.5.4): Google
// пускает не больше 100 новых пользователей. Ответ Google об этом (вход
// напрямую у Google) — не «отмена», а объяснение и вход паролем приложения.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/oauth/proxy_pkce.dart';

void main() {
  test('ответ Google про лимит или непроверенное приложение — user_cap', () {
    for (final d in [
      'This app has reached its user cap',
      'unverified_app user_cap',
      'This app has not been verified by Google',
      'has not completed the Google verification process',
    ]) {
      final e = OAuthProviderError.of('access_denied', d, provider: 'google');
      expect(e.code, OAuthProviderError.userCap, reason: d);
      expect(e.cancelled, isFalse, reason: 'не отмена — человеку нужно другое действие');
    }
    // Обычная отмена и чужие службы — как пришло.
    expect(OAuthProviderError.of('access_denied', null, provider: 'google').cancelled, isTrue);
    expect(OAuthProviderError.of('access_denied', 'user cap', provider: 'microsoft').code, 'access_denied');
    expect(OAuthProviderError.of('invalid_scope', 'bad scope', provider: 'google').code, 'invalid_scope');
  });

  test('лимит пользователей — текст на языке интерфейса с выходом', () {
    final text = const OAuthProviderError(OAuthProviderError.userCap).localizedMessage(AppLocalizations(const Locale('ru')));
    expect(text, contains('100'));
    expect(text, contains('паролем приложения'));
  });
}

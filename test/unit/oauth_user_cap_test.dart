// Лимит пользователей Google у непроверенного приложения (2.5.4): Google
// пускает не больше 100 новых пользователей. Сервер входа отвечает
// error=user_cap (флаг GOOGLE_USER_CAP) или передаёт ответ Google — в
// приложении это не «отмена», а объяснение и вход паролем приложения.

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

  test('ответ сервера входа error=user_cap — отказ user_cap, текст на языке интерфейса', () async {
    final pkce = ProxyPkce.generate();
    await expectLater(
      pkce.resolve('https://www.ogneliss.ru/oauth', {'provider': 'google', 'error': 'user_cap'}),
      throwsA(isA<OAuthProviderError>().having((e) => e.code, 'code', OAuthProviderError.userCap)),
    );
    await expectLater(
      pkce.resolve('https://www.ogneliss.ru/oauth',
          {'provider': 'google', 'error': 'access_denied', 'desc': 'This app has reached its user cap'}),
      throwsA(isA<OAuthProviderError>().having((e) => e.code, 'code', OAuthProviderError.userCap)),
    );
    final text = const OAuthProviderError(OAuthProviderError.userCap).localizedMessage(AppLocalizations(const Locale('ru')));
    expect(text, contains('100'));
    expect(text, contains('паролем приложения'));
  });
}

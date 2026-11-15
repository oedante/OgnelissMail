// 1.8.0: адрес, введённый на первом шаге входа, подставляется на странице
// входа службы (login_hint) — приложением, сервер входа его не получает.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/oauth/oauth_proxy_flow.dart';

void main() {
  test('подсказка — только похожая на адрес почты', () {
    expect(OAuthProxyFlow.hintParam(' ivan@gmail.com '), 'ivan@gmail.com');
    expect(OAuthProxyFlow.hintParam('ivan'), isNull);
    expect(OAuthProxyFlow.hintParam('a b@c.ru'), isNull);
    expect(OAuthProxyFlow.hintParam(null), isNull);
    expect(OAuthProxyFlow.hintParam('${'a' * 250}@x.ru'), isNull);
  });

  test('Google: login_hint дописан, остальное как было', () {
    const u = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=x&scope=a+b'
        '&state=s.t&access_type=offline&prompt=consent';
    expect(OAuthProxyFlow.withHint(u, 'google', 'ivan+work@gmail.com'), '$u&login_hint=ivan%2Bwork%40gmail.com');
  });

  test('Microsoft: без выбора учётной записи', () {
    const u = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize?response_type=code&client_id=x'
        '&state=s&prompt=select_account';
    final r = OAuthProxyFlow.withHint(u, 'microsoft', 'a@corp.example');
    expect(r, contains('login_hint=a%40corp.example'));
    expect(r, isNot(contains('prompt=')));
    expect(r, startsWith('https://login.microsoftonline.com/common/oauth2/v2.0/authorize?response_type=code&client_id=x&state=s'));
    const first = 'https://login.microsoftonline.com/x?prompt=select_account&client_id=y';
    expect(OAuthProxyFlow.withHint(first, 'microsoft', 'a@b.ru'), 'https://login.microsoftonline.com/x?client_id=y&login_hint=a%40b.ru');
  });

  test('Exchange Online через сервер входа (1.8.11): как Microsoft', () {
    const u = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?response_type=code&client_id=x'
        '&state=s&prompt=select_account';
    final r = OAuthProxyFlow.withHint(u, 'exchange', 'ivan@contoso.example');
    expect(r, endsWith('&state=s&login_hint=ivan%40contoso.example'));
  });
}

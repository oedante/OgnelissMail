// Раздельный User-Agent для EWS и ActiveSync (11.11.2026, журнал Windows
// владельца): ящик «Exchange (авто)» в режиме совместимости пробует EWS, затем
// ActiveSync, и ActiveSync уходил с UA Outlook (UA для EWS) — шлюз видел
// Outlook с типом устройства WindowsMail. Теперь EWS — со своим UA, ActiveSync
// — со своим.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  const outlook = 'Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook 16.0.18129; Pro)';
  const windowsMail = 'MSFT-WIN-3/10.0.26300';

  test('EWS-запрос идёт с UA для EWS, а не с UA ActiveSync', () async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add(req.headers['User-Agent'] ?? '');
      return http.Response('Forbidden', 403);
    });
    final engine = EwsEngine(httpClient: client);
    await engine.connect(const AccountConfig(
      email: 'user@example.com',
      password: 'x',
      exchangeServer: 'mail.example.com',
      userAgent: windowsMail,
      ewsUserAgent: outlook,
    ));
    expect(seen, isNotEmpty);
    expect(seen.toSet(), {outlook});
  });

  test('UA для EWS не задан — EWS идёт с общим UA', () {
    const cfg = AccountConfig(email: 'a@b.c', userAgent: windowsMail);
    expect(cfg.ewsUa, windowsMail);
    const both = AccountConfig(email: 'a@b.c', userAgent: windowsMail, ewsUserAgent: outlook);
    expect(both.ewsUa, outlook);
    expect(both.userAgent, windowsMail, reason: 'ActiveSync — штатная почта ActiveSync');
    expect(both.withUserAgent('X').ewsUserAgent, outlook, reason: 'смена UA ActiveSync не теряет UA EWS');
  });
}

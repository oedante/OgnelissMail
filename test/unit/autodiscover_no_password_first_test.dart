// Autodiscover без пароля в первом запросе (план 08.11.2026 п. 1): корневой
// домен почты (https://<домен>/Autodiscover) часто у стороннего хостинга
// сайта, и пароль домена уходил ему первым же запросом. Теперь учётные
// данные — только серверу, который сам попросил вход (401).

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _outlookOk = '<?xml version="1.0" encoding="utf-8"?>'
    '<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">'
    '<Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a">'
    '<Account><Protocol><Type>EXCH</Type><EwsUrl>https://mail.example.com/EWS/Exchange.asmx</EwsUrl>'
    '</Protocol></Account></Response></Autodiscover>';

const _mobileOk = '<?xml version="1.0" encoding="utf-8"?>'
    '<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">'
    '<Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">'
    '<Action><Settings><Server><Type>MobileSync</Type>'
    '<Url>https://mail.example.com/Microsoft-Server-ActiveSync</Url></Server></Settings></Action>'
    '</Response></Autodiscover>';

void main() {
  test('пароль — только серверу, ответившему 401; хостинг сайта его не получает', () async {
    final withAuth = <String>[];
    final client = MockClient((req) async {
      final host = req.url.host;
      if (req.headers.containsKey('Authorization')) withAuth.add(host);
      if (host == 'autodiscover.example.com') return http.Response('', 404);
      if (host == 'example.com') {
        // Сайт на стороннем хостинге: страница вместо Autodiscover.
        return http.Response('<html>Наш сайт</html>', 200);
      }
      return http.Response('', 404);
    });
    final r = await Autodiscover.discover(
        email: 'user@example.com', authHeader: 'Basic c2VjcmV0', userAgent: 'test', httpClient: client);
    expect(r.ewsUrl, isNull);
    expect(withAuth, isEmpty, reason: 'ни один сервер не просил вход — пароль не отправлен никому');
  });

  test('401 без пароля — повтор с паролем тем же адресом, дальше сразу с паролем', () async {
    final requests = <String>[];
    final client = MockClient((req) async {
      final auth = req.headers.containsKey('Authorization');
      requests.add('${req.url.host}${auth ? ' +пароль' : ''}');
      if (req.url.host != 'autodiscover.example.com') return http.Response('', 404);
      if (!auth) return http.Response('', 401, headers: {'www-authenticate': 'Basic realm="ex"'});
      return http.Response(req.body.contains('mobilesync/requestschema') ? _mobileOk : _outlookOk, 200);
    });
    final r = await Autodiscover.discover(
        email: 'user@example.com', authHeader: 'Basic c2VjcmV0', userAgent: 'test', httpClient: client);
    expect(r.ewsUrl, 'https://mail.example.com/EWS/Exchange.asmx');
    expect(r.easUrl, 'https://mail.example.com/Microsoft-Server-ActiveSync');
    expect(requests, [
      'autodiscover.example.com',
      'autodiscover.example.com +пароль',
      'autodiscover.example.com +пароль',
    ]);
  });
}

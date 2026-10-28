// test/unit/engine_audit_fixes_test.dart
// Аудит движка от 07.10.2026 (разбор — docs/plan/ENGINE_AUDIT_REVIEW_1.7.2.md),
// исправления 1.7.2:
//  · E4 — Autodiscover: перенаправление <Action>redirectUrl и HTTP 302 на
//    POST; пароль уходит только серверам в домене почты;
//  · E6 — версия ActiveSync по списку сервера: 14.0 (без DeviceInformation в
//    Provision) и понятный отказ для серверов только с 12.x;
//  · E8 — Provision «политики нет» (Status 2): без ключа, без отката на 14.1,
//    сеанс сохраняется.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _email = 'user@example.com';

AccountConfig _cfg() => const AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: 'mail.example.com',
      deviceId: 'TESTDEVICE0001',
      forceTransport: MailTransportKind.eas,
    );

/// Ответ Provision «для этого клиента политики нет».
Uint8List _provisionNoPolicy() {
  final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
  root.addChild('Status', namespace: 'Provision', text: '1');
  final policy = root
      .addChild('Policies', namespace: 'Provision')
      .addChild('Policy', namespace: 'Provision');
  policy.addChild('PolicyType', namespace: 'Provision', text: 'MS-EAS-Provisioning-WBXML');
  policy.addChild('Status', namespace: 'Provision', text: '2');
  return WbxmlEncoder().encode(WbxmlDocument(root: root));
}

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

String _redirectUrl(String to) => '<?xml version="1.0" encoding="utf-8"?>'
    '<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">'
    '<Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a">'
    '<Account><Action>redirectUrl</Action><RedirectUrl>$to</RedirectUrl></Account>'
    '</Response></Autodiscover>';

void main() {
  late Map<String, String?> saved;

  setUp(() {
    saved = {};
    EasEngine.loadSession = null;
    EasEngine.saveSession = (email, data) => saved[email] = data;
  });

  tearDown(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  group('E6: версия ActiveSync по списку сервера', () {
    test('только 12.x — понятный отказ без команд', () async {
      var posts = 0;
      final eng = EasEngine(
        httpClient: MockClient((req) async {
          if (req.method == 'OPTIONS') {
            return http.Response('', 200, headers: {'ms-asprotocolversions': '2.5,12.0,12.1'});
          }
          posts++;
          return http.Response('', 500);
        }),
      );
      final r = await eng.connect(_cfg());
      expect(r.success, isFalse);
      expect(r.error, contains('12.1'));
      expect(posts, 0, reason: 'ни одной команды на версии, которой сервер не знает');
    });

    test('14.0 — Provision без DeviceInformation; Status 2 — без ключа и без отката', () async {
      final versions = <String>[];
      var devInfo = true;
      final eng = EasEngine(
        httpClient: MockClient((req) async {
          if (req.method == 'OPTIONS') {
            return http.Response('', 200,
                headers: {'ms-asprotocolversions': '12.1,14.0', 'ms-asprotocolcommands': 'Sync,FolderSync,Provision'});
          }
          versions.add(req.headers['MS-ASProtocolVersion'] ?? '');
          final doc = WbxmlDecoder().decode(Uint8List.fromList(req.bodyBytes));
          devInfo = doc.root.findChild('DeviceInformation') != null;
          return http.Response.bytes(_provisionNoPolicy(), 200,
              headers: {'content-type': 'application/vnd.ms-sync.wbxml'});
        }),
      );
      final r = await eng.connect(_cfg());
      expect(r.success, isTrue);
      expect(versions, ['14.0'], reason: 'один Provision, без перехода на 14.1');
      expect(devInfo, isFalse);
      final s = saved[_email];
      expect(s, isNotNull, reason: 'сеанс сохранён');
      final m = jsonDecode(s!) as Map<String, dynamic>;
      expect(m['key'], '0');
      expect(m['proto'], '14.0');
    });
  });

  group('E4: перенаправления Autodiscover', () {
    test('302 на POST — повтор по новому адресу в домене почты', () async {
      final eng = MockClient((req) async {
        final u = req.url.toString();
        if (req.method == 'POST' && u.startsWith('https://autodiscover.example.com/')) {
          return http.Response('', 302, headers: {'location': 'https://mail.example.com/autodiscover/autodiscover.xml'});
        }
        if (req.method == 'POST' && u.startsWith('https://mail.example.com/autodiscover/')) {
          return http.Response(req.body.contains('mobilesync/requestschema') ? _mobileOk : _outlookOk, 200);
        }
        return http.Response('', 404);
      });
      final r = await Autodiscover.discover(
          email: _email, authHeader: 'Basic eA==', userAgent: 'test', httpClient: eng);
      expect(r.ewsUrl, 'https://mail.example.com/EWS/Exchange.asmx');
      expect(r.easUrl, 'https://mail.example.com/Microsoft-Server-ActiveSync');
    });

    test('redirectUrl на другой домен — не следуем, пароль чужому серверу не уходит', () async {
      final hosts = <String>{};
      final eng = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.method == 'POST' && req.url.host == 'autodiscover.example.com') {
          return http.Response(_redirectUrl('https://autodiscover.attacker.test/Autodiscover/Autodiscover.xml'), 200);
        }
        if (req.method == 'GET') {
          // Метод HTTP-перенаправления по http:// — тоже на чужой домен.
          return http.Response('', 302, headers: {'location': 'https://autodiscover.attacker.test/a.xml'});
        }
        return http.Response('', 404);
      });
      final r = await Autodiscover.discover(
          email: _email, authHeader: 'Basic eA==', userAgent: 'test', httpClient: eng);
      expect(r.ewsUrl, isNull);
      expect(hosts.contains('autodiscover.attacker.test'), isFalse);
      expect(r.log.any((l) => l.contains('другой домен')), isTrue);
    });

    test('redirectUrl в домене почты — следуем', () async {
      final eng = MockClient((req) async {
        if (req.method == 'POST' && req.url.host == 'autodiscover.example.com') {
          return http.Response(_redirectUrl('https://ad2.example.com/Autodiscover/Autodiscover.xml'), 200);
        }
        if (req.method == 'POST' && req.url.host == 'ad2.example.com') {
          return http.Response(req.body.contains('mobilesync/requestschema') ? _mobileOk : _outlookOk, 200);
        }
        return http.Response('', 404);
      });
      final r = await Autodiscover.discover(
          email: _email, authHeader: 'Basic eA==', userAgent: 'test', httpClient: eng);
      expect(r.ewsUrl, isNotNull);
      expect(r.easUrl, isNotNull);
    });
  });
}

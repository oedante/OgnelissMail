// test/unit/eas_apple_profile_test.dart
// Профиль запросов «как Почта iPhone» (1.6.17): командная строка с Cmd в конце
// (порядок Почты iOS по журналам Exchange), в запросе только заголовки
// ActiveSync (Accept / Accept-Language / Accept-Encoding ставит система), при
// автоопределении — только ActiveSync, без POST к EWS. Без профиля всё как
// раньше (Android-режим не меняется).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  late List<http.BaseRequest> sent;

  // OPTIONS — 200 с версиями протокола, любой POST — 403 со страницей шлюза:
  // так отвечал шлюз ServicePipe 17.10.2026.
  MockClient gateway() => MockClient((req) async {
        sent.add(req);
        if (req.method == 'OPTIONS') {
          return http.Response('', 200, headers: {
            'ms-asprotocolversions': '14.0,14.1,16.0,16.1',
            'ms-asprotocolcommands': 'Sync,FolderSync,Provision,Ping',
          });
        }
        return http.Response('<html><body>Forbidden. If you are not a bot...</body></html>', 403,
            headers: {'content-type': 'text/html'});
      });

  AccountConfig cfg(String host, {required bool apple}) => AccountConfig(
        email: 'user@example.com',
        password: 'secret',
        domain: 'msk',
        exchangeServer: host,
        userAgent: apple ? 'Apple-iPhone15C2/2401.446' : 'Android-Android/13 (Pixel 6/TP1A)',
        deviceType: apple ? 'iPhone' : 'Android',
        deviceId: 'T5KCOR7PBL5A3E1GONS10002AG',
        appleMailProfile: apple,
      );

  setUp(() {
    sent = [];
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  test('профиль Почты iPhone: только ActiveSync, Cmd в конце, без Accept-Language', () async {
    final (engine, res) = await EngineFactory.connect(cfg('apple-profile.example', apple: true),
        logger: DebugLog(verbose: false, echo: false), httpClient: gateway());
    expect(engine, isNull);
    expect(res.success, isFalse);
    expect(res.error, contains('EAS 403'));
    expect(sent.any((r) => r.url.path.toLowerCase().contains('/ews/')), isFalse,
        reason: 'EWS не опрашивается');
    final post = sent.firstWhere((r) => r.method == 'POST');
    expect(post.url.query,
        'User=msk%5Cuser&DeviceId=T5KCOR7PBL5A3E1GONS10002AG&DeviceType=iPhone&Cmd=Provision');
    expect(post.headers.containsKey('Accept-Language'), isFalse);
    expect(post.headers.containsKey('Accept'), isFalse);
    expect(post.headers.containsKey('Accept-Encoding'), isFalse);
    expect(post.headers['User-Agent'], 'Apple-iPhone15C2/2401.446');
    expect(post.headers['MS-ASProtocolVersion'], '16.1');
    expect(post.headers['X-MS-PolicyKey'], '0');
    expect(sent.where((r) => r.method == 'POST'), hasLength(1),
        reason: 'после отказа шлюза — ни одного повтора');
  });

  test('без профиля (Android): порядок и заголовки прежние', () async {
    final (_, res) = await EngineFactory.connect(
        cfg('android-profile.example', apple: false).withTransport(MailTransportKind.eas),
        logger: DebugLog(verbose: false, echo: false), httpClient: gateway());
    expect(res.success, isFalse);
    final post = sent.firstWhere((r) => r.method == 'POST');
    expect(post.url.query, startsWith('Cmd=Provision&User=msk%5Cuser&DeviceId='));
    expect(post.headers['Accept-Language'], 'en-US,en;q=0.9');
  });
}

extension on AccountConfig {
  AccountConfig withTransport(MailTransportKind t) => AccountConfig(
        email: email,
        password: password,
        domain: domain,
        exchangeServer: exchangeServer,
        userAgent: userAgent,
        deviceType: deviceType,
        deviceId: deviceId,
        forceTransport: t,
        appleMailProfile: appleMailProfile,
      );
}

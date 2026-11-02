// Адресная книга Exchange (1.10.3, журнал владельца 02.11.2026): встреча со
// 120 участниками — 120 запросов Search разом, шлюз перед Exchange ответил
// 502 на все. Теперь не больше трёх запросов сразу; после 502–504 или
// обрыва — пауза 5 минут без запросов.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _email = 'user@example.com';
const _server = 'mail.example.com';
const _device = 'TESTDEVICE0001';

AccountConfig _cfg() => const AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: _server,
      deviceId: _device,
      forceTransport: MailTransportKind.eas,
    );

String _session() => jsonEncode({
      'v': 1,
      'server': _server,
      'device': _device,
      'url': 'https://$_server/Microsoft-Server-ActiveSync',
      'host': _server,
      'proto': '16.1',
      'b64': false,
      'versions': ['14.1', '16.0', '16.1'],
      'cmds': ['Sync', 'FolderSync', 'Ping', 'Search'],
      'key': '1234567890',
      'at': DateTime.now().millisecondsSinceEpoch,
    });

http.Response _empty() {
  final root = WbxmlElement(name: 'Search', namespace: 'Search');
  root.addChild('Status', namespace: 'Search', text: '1');
  final store = root.addChild('Response', namespace: 'Search').addChild('Store', namespace: 'Search');
  store.addChild('Status', namespace: 'Search', text: '1');
  return http.Response.bytes(WbxmlEncoder().encode(WbxmlDocument(root: root)), 200,
      headers: {'content-type': 'application/vnd.ms-sync.wbxml'});
}

void main() {
  tearDown(() => EasEngine.loadSession = null);

  Future<EasEngine> engine(MockClient c) async {
    EasEngine.loadSession = (_) => _session();
    final eng = EasEngine(httpClient: c);
    expect((await eng.connect(_cfg())).success, isTrue);
    return eng;
  }

  test('не больше трёх запросов к адресной книге одновременно', () async {
    var active = 0, peak = 0, total = 0;
    final eng = await engine(MockClient((req) async {
      total++;
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      active--;
      return _empty();
    }));
    await Future.wait([for (var i = 0; i < 12; i++) eng.searchGal('person$i@example.com')]);
    expect(total, 12);
    expect(peak, lessThanOrEqualTo(3));
  });

  test('502 от шлюза — пауза: дальше без запросов к серверу', () async {
    var total = 0;
    final eng = await engine(MockClient((req) async {
      total++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return http.Response('Bad Gateway', 502);
    }));
    final results = await Future.wait([for (var i = 0; i < 20; i++) eng.searchGal('person$i@example.com')]);
    expect(results.every((r) => r.isEmpty), isTrue);
    expect(eng.galPaused, isTrue);
    expect(total, lessThanOrEqualTo(6), reason: 'после первого 502 очередь не ходит на сервер');
    final before = total;
    expect(await eng.searchGal('later@example.com'), isEmpty);
    expect(total, before);
  });
}

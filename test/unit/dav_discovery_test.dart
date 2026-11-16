// Календарь и контакты рабочей почты (2.6.0, RFC 6764): SRV и
// /.well-known; пароль — только серверам, что ответили как DAV, и только в
// домене организации.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/dav/dav_discovery.dart';
import 'package:ogneliss/services/mail/dav/dav_pim_service.dart';
import 'package:ogneliss/services/net/system_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _principal = '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>'
    '<d:propstat><d:prop><d:current-user-principal><d:href>/dav/principals/ivanov/</d:href>'
    '</d:current-user-principal></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';

AccountModel _acc({String imap = 'imap.corp.example'}) => AccountModel(
      id: 'w1',
      type: AccountType.imap,
      email: 'ivanov@corp.example',
      displayName: 'Иванов',
      username: 'ivanov',
      imapServer: imap,
      createdAt: DateTime(2026),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DavDiscovery.reset();
  });

  group('адрес DAV без учётных данных', () {
    test('перенаправление с .well-known и 401 — DAV; на сайте домена без перенаправления 401 — нет', () async {
      final c = MockClient((r) async {
        expect(r.headers['Authorization'], isNull, reason: 'без пароля');
        if (r.url.path == '/.well-known/caldav') {
          return http.Response('', 301, headers: {'location': '/remote.php/dav/'});
        }
        return http.Response('', 401, headers: {'www-authenticate': 'Basic realm="x"'});
      });
      expect(await DavDiscovery.davStart(c, 'https://corp.example/.well-known/caldav', domain: 'corp.example', trusted: false),
          'https://corp.example/remote.php/dav/');
      final plain401 = MockClient((r) async => http.Response('', 401));
      expect(await DavDiscovery.davStart(plain401, 'https://corp.example/.well-known/caldav', domain: 'corp.example', trusted: false),
          isNull);
      // Сервер IMAP — пароль ему и так доверен: 401 достаточно.
      expect(await DavDiscovery.davStart(plain401, 'https://imap.corp.example/.well-known/caldav',
              domain: 'corp.example', trusted: true),
          'https://imap.corp.example/.well-known/caldav');
    });

    test('перенаправление на чужой домен или на http — не идём', () async {
      final away = MockClient((r) async => http.Response('', 302, headers: {'location': 'https://hosting.example/dav/'}));
      expect(await DavDiscovery.davStart(away, 'https://corp.example/.well-known/caldav', domain: 'corp.example', trusted: true),
          isNull);
      final insecure = MockClient((r) async => http.Response('', 302, headers: {'location': 'http://corp.example/dav/'}));
      expect(await DavDiscovery.davStart(insecure, 'https://corp.example/.well-known/caldav', domain: 'corp.example', trusted: true),
          isNull);
      final page = MockClient((r) async => http.Response('<html>', 200));
      expect(await DavDiscovery.davStart(page, 'https://corp.example/.well-known/caldav', domain: 'corp.example', trusted: true),
          isNull);
    });
  });

  test('SRV _caldavs и путь из TXT; CardDAV — на сервере IMAP; пароль — только им', () async {
    final authed = <String>[];
    final c = MockClient((r) async {
      final auth = r.headers['Authorization'];
      if (auth != null) authed.add(r.url.host);
      final dav = (r.url.host == 'dav.corp.example' && r.url.path == '/sogo/dav/') ||
          (r.url.host == 'imap.corp.example' && r.url.path == '/.well-known/carddav');
      if (!dav) return http.Response('', 404);
      return auth == null ? http.Response('', 401) : http.Response(_principal, 207);
    });
    final found = await DavDiscovery.discover(_acc(), 'Basic eA==', client: c, dns: (q) async => [
          [const DnsRecord(DnsType.srv, 'dav.corp.example', port: 443)],
          [const DnsRecord(DnsType.txt, 'path=/sogo/dav/')],
          const <DnsRecord>[],
          const <DnsRecord>[],
        ]);
    expect(found.cal, 'https://dav.corp.example/sogo/dav/');
    expect(found.card, 'https://imap.corp.example/.well-known/carddav');
    expect(authed.toSet(), {'dav.corp.example', 'imap.corp.example'});
  });

  test('найденное — провайдер «custom» у ящика; контакты — только если нашлись', () async {
    final a = _acc();
    expect(DavPimService.providerOf(a), isNull);
    DavDiscovery.put(a.email, (cal: 'https://dav.corp.example/dav/', card: null));
    expect(DavPimService.providerOf(a), 'custom');
    expect(DavPimService.isSupported(a), isTrue);
    expect(DavPimService.hasContacts('custom', a.email), isFalse);
    expect(DavPimService.knownProviderOf(a), isNull);
  });

  test('ensure: ищет раз в неделю и запоминает; известная служба — не ищет', () async {
    var calls = 0;
    final c = MockClient((r) async {
      calls++;
      return http.Response('', 404);
    });
    Future<List<List<DnsRecord>?>> noDns(List<DnsQuestion> q) async => List.filled(q.length, const <DnsRecord>[]);
    await DavDiscovery.ensure(_acc(), null, () async => 'Basic eA==', dns: noDns, client: c);
    final first = calls;
    expect(first, greaterThan(0));
    await DavDiscovery.ensure(_acc(), null, () async => 'Basic eA==', dns: noDns, client: c);
    expect(calls, first, reason: 'повтор — через неделю');
    await DavDiscovery.ensure(_acc(imap: 'imap.yandex.ru'), 'yandex', () async => 'Basic eA==', dns: noDns, client: c);
    expect(calls, first);
  });

  test('узел из SRV вне домена организации — пароль ему не уходит', () async {
    final asked = <String>{};
    final c = MockClient((r) async {
      asked.add(r.url.host);
      // Чужой узел отвечает как настоящий сервер DAV.
      if (r.url.host == 'dav.attacker.example') {
        return r.headers['Authorization'] == null ? http.Response('', 401) : http.Response(_principal, 207);
      }
      return http.Response('', 404);
    });
    final found = await DavDiscovery.discover(_acc(), 'Basic eA==', client: c, dns: (q) async => [
          [const DnsRecord(DnsType.srv, 'dav.attacker.example', port: 443)],
          const <DnsRecord>[],
          [const DnsRecord(DnsType.srv, 'dav.attacker.example', port: 443)],
          const <DnsRecord>[],
        ]);
    expect(found.cal, isNull);
    expect(found.card, isNull);
    expect(asked.contains('dav.attacker.example'), isFalse);
  });
}

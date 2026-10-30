// test/unit/dav_client_test.dart
// DavClient: метка изменений коллекции (getctag / sync-token) и декодирование
// тела ответа в UTF-8.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/mail/dav/dav_client.dart';

DavClient _client(String body, {int status = 207, void Function(http.Request)? onRequest}) =>
    DavClient('Basic x', httpClient: MockClient((req) async {
      onRequest?.call(req);
      return http.Response.bytes(utf8.encode(body), status,
          headers: {'content-type': 'application/xml'});
    }));

void main() {
  group('collectionTag', () {
    test('getctag (Яндекс, Mail.ru)', () async {
      String? method;
      final c = _client('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
 <d:response><d:href>/addressbook/</d:href>
  <d:propstat><d:prop><cs:getctag>"1696-42"</cs:getctag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  <d:propstat><d:prop><d:sync-token/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
 </d:response>
</d:multistatus>''', onRequest: (r) => method = r.method);
      expect(await c.collectionTag('https://dav.example/addressbook/'), '"1696-42"');
      expect(method, 'PROPFIND');
    });

    test('только sync-token (Google)', () async {
      final c = _client('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
 <d:response><d:href>/carddav/v1/principals/x/lists/default/</d:href>
  <d:propstat><d:prop><cs:getctag/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
  <d:propstat><d:prop><d:sync-token>https://www.google.com/carddav/sync/abc</d:sync-token></d:prop>
   <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
 </d:response>
</d:multistatus>''');
      expect(await c.collectionTag('https://www.googleapis.com/carddav/v1/x/'),
          'https://www.google.com/carddav/sync/abc');
    });

    test('сервер метку не дал — null', () async {
      final c = _client('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:"><d:response><d:href>/c/</d:href>
 <d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>''');
      expect(await c.collectionTag('https://dav.example/c/'), isNull);
    });

    test('адрес без HTTPS — запрос не уходит (1.8.13)', () async {
      var asked = 0;
      final c = _client('<d:multistatus xmlns:d="DAV:"/>', onRequest: (_) => asked++);
      expect(await c.collectionTag('http://dav.example/c/'), isNull);
      expect(asked, 0);
    });

    test('ошибка HTTP — null', () async {
      final c = _client('nope', status: 500);
      expect(await c.collectionTag('https://dav.example/c/'), isNull);
    });
  });

  test('iCloud: календари на другом узле — адреса от узла, который ответил (1.8.13)', () async {
    final asked = <String>[];
    final c = DavClient('Basic x', httpClient: MockClient((req) async {
      asked.add('${req.method} ${req.url}');
      final body = switch (req.url.toString()) {
        'https://caldav.icloud.com/' => '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/</d:href><d:propstat><d:prop>'
            '<d:current-user-principal><d:href>/123/principal/</d:href></d:current-user-principal></d:prop></d:propstat>'
            '</d:response></d:multistatus>',
        'https://caldav.icloud.com/123/principal/' => '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '<d:response><d:href>/123/principal/</d:href><d:propstat><d:prop><c:calendar-home-set>'
            '<d:href>https://p52-caldav.icloud.com:443/123/calendars/</d:href></c:calendar-home-set></d:prop></d:propstat>'
            '</d:response></d:multistatus>',
        _ => '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '<d:response><d:href>/123/calendars/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
            '</d:prop></d:propstat></d:response>'
            '<d:response><d:href>/123/calendars/home/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/>'
            '</d:resourcetype><d:displayname>Дом</d:displayname></d:prop></d:propstat></d:response></d:multistatus>',
      };
      return http.Response.bytes(utf8.encode(body), 207, headers: {'content-type': 'application/xml'});
    }));
    final cals = await c.discoverCalendars('https://caldav.icloud.com/');
    expect(cals, hasLength(1));
    expect(Uri.parse(cals.single.url).host, 'p52-caldav.icloud.com');
    expect(Uri.parse(cals.single.url).path, '/123/calendars/home/');
    expect(cals.single.name, 'Дом');
  });

  test('utf8Body: без charset тело читается как UTF-8', () {
    final r = http.Response.bytes(utf8.encode('Иван Петров'), 200, headers: {'content-type': 'text/vcard'});
    expect(DavClient.utf8Body(r), 'Иван Петров');
  });
}

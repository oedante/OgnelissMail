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

    test('ошибка HTTP — null', () async {
      final c = _client('nope', status: 500);
      expect(await c.collectionTag('https://dav.example/c/'), isNull);
    });
  });

  test('utf8Body: без charset тело читается как UTF-8', () {
    final r = http.Response.bytes(utf8.encode('Иван Петров'), 200, headers: {'content-type': 'text/vcard'});
    expect(DavClient.utf8Body(r), 'Иван Петров');
  });
}

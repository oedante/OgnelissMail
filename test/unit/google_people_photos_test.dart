// Фото собеседников из профилей Google (17.11.2026): разбор ответа People
// API, заглушки Google пропускаются, нет разрешения — без ошибки.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/contacts/google_people_photos.dart';

void main() {
  test('основное фото — по всем адресам человека; заглушка и http — нет', () {
    final m = GooglePeoplePhotos.parse([
      {
        'emailAddresses': [{'value': 'Oleg@Example.com'}, {'value': 'o.e@work.example'}],
        'photos': [
          {'url': 'https://lh3.googleusercontent.com/a/x=s100', 'default': true},
          {'url': 'https://lh3.googleusercontent.com/a/real=s100', 'metadata': {'primary': true}},
        ],
      },
      {
        'emailAddresses': [{'value': 'letter@example.com'}],
        'photos': [{'url': 'https://lh3.googleusercontent.com/a/def=s100', 'default': true}],
      },
      {
        'emailAddresses': [{'value': 'plain@example.com'}],
        'photos': [{'url': 'http://example.com/p.png'}],
      },
    ]);
    expect(m, {
      'oleg@example.com': 'https://lh3.googleusercontent.com/a/real=s100',
      'o.e@work.example': 'https://lh3.googleusercontent.com/a/real=s100',
    });
  });

  test('сохранённые и «Другие контакты» со страницами; 403 — источник без разрешения', () async {
    final asked = <String>[];
    final client = MockClient((r) async {
      asked.add('${r.url.path}?${r.url.query}');
      expect(r.headers['Authorization'], 'Bearer t');
      if (r.url.path.endsWith('/connections')) {
        if (r.url.queryParameters['pageToken'] == null) {
          return http.Response(jsonEncode({
            'connections': [
              {'emailAddresses': [{'value': 'a@x.ru'}], 'photos': [{'url': 'https://p/a'}]},
            ],
            'nextPageToken': 'n2',
          }), 200);
        }
        return http.Response(jsonEncode({
          'connections': [
            {'emailAddresses': [{'value': 'b@x.ru'}], 'photos': [{'url': 'https://p/b'}]},
          ],
        }), 200);
      }
      return http.Response('{"error":{"code":403}}', 403);
    });
    final r = await GooglePeoplePhotos.fetch('Bearer t', client: client);
    expect(r.photos, {'a@x.ru': 'https://p/a', 'b@x.ru': 'https://p/b'});
    expect(r.denied, ['other']);
    expect(asked.first, contains('personFields=emailAddresses%2Cphotos'));
    expect(asked.last, contains('/otherContacts'));
    expect(asked.last, contains('readMask=emailAddresses%2Cphotos'));
  });
}

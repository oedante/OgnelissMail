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
    expect(r.found, {'contacts': 2});
  });

  // Журнал владельца 18.11.2026: «в профилях 5» — у «Других контактов» без
  // источника PROFILE Google отдаёт одни заглушки.
  test('«Другие контакты» — с источником профиля Google; у сохранённых — источник по умолчанию', () async {
    final asked = <Uri>[];
    final client = MockClient((r) async {
      asked.add(r.url);
      if (r.url.path.endsWith('/otherContacts')) {
        return http.Response(jsonEncode({
          'otherContacts': [
            {
              'emailAddresses': [{'value': 'friend@gmail.com'}],
              'photos': [
                {'url': 'https://lh3.googleusercontent.com/a/letter', 'default': true},
                {'url': 'https://lh3.googleusercontent.com/a/profile'},
              ],
            },
          ],
        }), 200);
      }
      return http.Response(jsonEncode({'connections': []}), 200);
    });
    final r = await GooglePeoplePhotos.fetch('Bearer t', client: client);
    final other = asked.firstWhere((u) => u.path.endsWith('/otherContacts'));
    expect(other.queryParametersAll['sources'], ['READ_SOURCE_TYPE_CONTACT', 'READ_SOURCE_TYPE_PROFILE']);
    final saved = asked.firstWhere((u) => u.path.endsWith('/connections'));
    expect(saved.queryParametersAll.containsKey('sources'), isFalse);
    expect(r.photos, {'friend@gmail.com': 'https://lh3.googleusercontent.com/a/profile'});
    expect(r.found, {'other': 1});
    expect(r.denied, isEmpty);
  });

  test('итог для журнала и диагностики', () {
    expect(GooglePeoplePhotos.summary({'contacts': 5, 'other': 120}, 123, 40, const []),
        'в профилях 123 (сохранённые 5, «Другие контакты» 120), поставлено 40');
    expect(GooglePeoplePhotos.summary({'contacts': 5}, 5, 0, const ['other']),
        'в профилях 5 (сохранённые 5, «Другие контакты» — нет разрешения), поставлено 0; '
        'фото появятся после повторного входа, если Google выдаст разрешения');
    expect(GooglePeoplePhotos.summary(const {}, 0, 0, const ['contacts', 'other'], apiDisabled: true),
        contains('People API не включён'));
  });
}

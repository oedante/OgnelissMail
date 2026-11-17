// lib/services/contacts/google_people_photos.dart
// Фото собеседников из профилей Google (17.11.2026, решение владельца):
// Gmail показывает у писем фото профилей Google, у нас было только то, что
// пользователь сам поставил контакту (CardDAV фото профиля не отдаёт).
//
// Google People API, доступ — токеном ящика Google (вход напрямую у Google,
// серверы Ogneliss не участвуют):
//  · people/me/connections — сохранённые контакты
//    (разрешение contacts.readonly);
//  · otherContacts — «Другие контакты»: люди, с которыми была переписка
//    (разрешение contacts.other.readonly).
// Берётся только адрес и ссылка на фото; заглушки Google (буква на цветном
// фоне, photos[].default = true) пропускаются — у нас своя буква.
// Ящик, вошедший до 2.6.2, этих разрешений не имеет: ответ 403 — тихо,
// фото появятся после повторного входа.

import 'dart:convert';

import 'package:http/http.dart' as http;

class GooglePeoplePhotos {
  GooglePeoplePhotos._();

  static const _base = 'https://people.googleapis.com/v1';

  /// Страниц на источник не больше этого (по 1000 человек).
  static const maxPages = 10;

  /// Адрес (в нижнем регистре) → ссылка на фото по обоим источникам.
  /// [denied] — источники, на которые нет разрешения (403).
  static Future<({Map<String, String> photos, List<String> denied})> fetch(String authorization,
      {http.Client? client}) async {
    final c = client ?? http.Client();
    final photos = <String, String>{};
    final denied = <String>[];
    try {
      for (final (name, path, param) in const [
        ('contacts', '/people/me/connections', 'personFields'),
        ('other', '/otherContacts', 'readMask'),
      ]) {
        String? page;
        for (var i = 0; i < maxPages; i++) {
          final uri = Uri.parse('$_base$path').replace(queryParameters: {
            param: 'emailAddresses,photos',
            'pageSize': '1000',
            if (page != null) 'pageToken': page,
          });
          final r = await c.get(uri, headers: {'Authorization': authorization}).timeout(const Duration(seconds: 20));
          if (r.statusCode == 401 || r.statusCode == 403) {
            denied.add(name);
            break;
          }
          if (r.statusCode != 200) throw http.ClientException('People API $path: HTTP ${r.statusCode}', uri);
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final list = (j[path == '/otherContacts' ? 'otherContacts' : 'connections'] as List?) ?? const [];
          for (final e in parse(list).entries) {
            photos.putIfAbsent(e.key, () => e.value);
          }
          page = j['nextPageToken'] as String?;
          if (page == null || page.isEmpty) break;
        }
      }
    } finally {
      if (client == null) c.close();
    }
    return (photos: photos, denied: denied);
  }

  /// Люди из ответа People API → адрес → фото. Фото — основное (primary),
  /// иначе первое не-заглушка; ссылка — только https.
  static Map<String, String> parse(List<dynamic> people) {
    final out = <String, String>{};
    for (final p in people) {
      if (p is! Map) continue;
      final photos = [
        for (final ph in (p['photos'] as List?) ?? const [])
          if (ph is Map && ph['default'] != true && '${ph['url'] ?? ''}'.startsWith('https://')) ph,
      ];
      if (photos.isEmpty) continue;
      final best = photos.firstWhere(
          (ph) => (ph['metadata'] is Map) && (ph['metadata'] as Map)['primary'] == true,
          orElse: () => photos.first);
      final url = '${best['url']}';
      for (final e in (p['emailAddresses'] as List?) ?? const []) {
        final v = e is Map ? '${e['value'] ?? ''}'.trim().toLowerCase() : '';
        if (v.contains('@')) out.putIfAbsent(v, () => url);
      }
    }
    return out;
  }
}

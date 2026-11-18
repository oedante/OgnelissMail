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
//
// Журнал владельца 18.11.2026 («пользователи Gmail не отображаются»):
// «в профилях 5» — фото пришли только у сохранённых контактов. У
// otherContacts источник по умолчанию — только READ_SOURCE_TYPE_CONTACT:
// у «Других контактов» там одни заглушки (буква), а фото профиля Google —
// в источнике READ_SOURCE_TYPE_PROFILE, который надо попросить явно (вместе
// с CONTACT — один PROFILE Google не принимает). У connections по умолчанию
// оба источника.

import 'dart:convert';

import 'package:http/http.dart' as http;

class GooglePeoplePhotos {
  GooglePeoplePhotos._();

  static const _base = 'https://people.googleapis.com/v1';

  /// Страниц на источник не больше этого (по 1000 человек).
  static const maxPages = 10;

  /// Ключ настроек проверки (время; «:denied», «:grant», «:last» — итог для
  /// пакета диагностики). «v2» (18.11.2026) — после обновления проверка
  /// сразу, а не через сутки по отметке старой версии.
  static const prefsKey = 'people_photos_v2';

  /// Итог проверки фото собеседников Google — для журнала и диагностики.
  static String summary(Map<String, int> found, int total, int set, List<String> denied,
      {bool apiDisabled = false}) {
    String src(String name, String title) =>
        denied.contains(name) ? '$title — нет разрешения' : '$title ${found[name] ?? 0}';
    final out = StringBuffer('в профилях $total (${src('contacts', 'сохранённые')}, '
        '${src('other', '«Другие контакты»')}), поставлено $set');
    if (apiDisabled) {
      out.write('; People API не включён в проекте Google Cloud (консоль → «API и сервисы» → «Библиотека» → '
          'Google People API) — повторный вход не поможет');
    } else if (denied.isNotEmpty) {
      out.write('; фото появятся после повторного входа, если Google выдаст разрешения');
    }
    return out.toString();
  }

  /// Адрес (в нижнем регистре) → ссылка на фото по обоим источникам.
  /// [denied] — источники, на которые нет разрешения (401/403);
  /// [apiDisabled] — отказ не из-за разрешения, а потому что People API не
  /// включён в проекте Google Cloud (повторный вход тут не поможет).
  /// [found] — сколько адресов с фото дал каждый источник (для журнала).
  static Future<({Map<String, String> photos, List<String> denied, bool apiDisabled, Map<String, int> found})> fetch(
      String authorization,
      {http.Client? client}) async {
    final c = client ?? http.Client();
    final photos = <String, String>{};
    final denied = <String>[];
    final found = <String, int>{};
    var apiDisabled = false;
    try {
      for (final (name, path, param, sources) in const [
        ('contacts', '/people/me/connections', 'personFields', <String>[]),
        ('other', '/otherContacts', 'readMask', ['READ_SOURCE_TYPE_CONTACT', 'READ_SOURCE_TYPE_PROFILE']),
      ]) {
        String? page;
        for (var i = 0; i < maxPages; i++) {
          final uri = Uri.parse('$_base$path').replace(queryParameters: <String, dynamic>{
            param: 'emailAddresses,photos',
            'pageSize': '1000',
            if (sources.isNotEmpty) 'sources': sources,
            if (page != null) 'pageToken': page,
          });
          final r = await c.get(uri, headers: {'Authorization': authorization}).timeout(const Duration(seconds: 20));
          if (r.statusCode == 401 || r.statusCode == 403) {
            denied.add(name);
            if (isApiDisabled(r.body)) apiDisabled = true;
            break;
          }
          if (r.statusCode != 200) throw http.ClientException('People API $path: HTTP ${r.statusCode}', uri);
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final list = (j[path == '/otherContacts' ? 'otherContacts' : 'connections'] as List?) ?? const [];
          for (final e in parse(list).entries) {
            found[name] = (found[name] ?? 0) + 1;
            photos.putIfAbsent(e.key, () => e.value);
          }
          page = j['nextPageToken'] as String?;
          if (page == null || page.isEmpty) break;
        }
      }
    } finally {
      if (client == null) c.close();
    }
    return (photos: photos, denied: denied, apiDisabled: apiDisabled, found: found);
  }

  /// Ответ 403 Google: API выключен в проекте (SERVICE_DISABLED,
  /// accessNotConfigured), а не нехватка разрешений
  /// (ACCESS_TOKEN_SCOPE_INSUFFICIENT).
  static bool isApiDisabled(String body) =>
      body.contains('SERVICE_DISABLED') || body.contains('accessNotConfigured') || body.contains('has not been used in project');

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

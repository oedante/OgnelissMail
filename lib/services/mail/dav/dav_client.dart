// lib/services/mail/dav/dav_client.dart
// Клиент CalDAV/CardDAV поверх HTTP (WebDAV: PROPFIND/REPORT). Заголовок
// авторизации готовит DavCredentials: «Bearer» (Google), «OAuth» (Яндекс),
// «Basic» с паролем приложения (Mail.ru, Yahoo, Яндекс без OAuth).
// Обнаружение коллекций (principal → home-set → collections) и выборка данных
// (calendar-data / address-data). Парсинг — ICalParser / VCardParser.

import 'dart:convert' show utf8;

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../../core/logging/app_logger.dart';

class DavClient {
  /// Полное значение заголовка Authorization.
  final String authorization;
  final http.Client _http;
  DavClient(this.authorization, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  /// Сервер отказал в доступе (401/403) хотя бы на одном запросе — обычно у
  /// токена нет scope календаря/контактов или API не включён в консоли.
  /// 404 сюда не относится: это неверный адрес, а не отказ, и прежде из-за
  /// него синхронизация замолкала на 6 часов.
  bool denied = false;

  Map<String, String> _headers({int? depth, String contentType = 'application/xml; charset=utf-8'}) => {
        'Authorization': authorization,
        'Content-Type': contentType,
        if (depth != null) 'Depth': '$depth',
      };

  Future<String?> _dav(String method, String url, {String? body, int? depth}) async {
    try {
      final req = http.Request(method, Uri.parse(url));
      req.headers.addAll(_headers(depth: depth));
      if (body != null) req.body = body;
      final streamed = await _http.send(req).timeout(const Duration(seconds: 25));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 207 || resp.statusCode == 200) {
        return utf8Body(resp);
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        denied = true;
      }
      // Адрес без e-mail и пути: в журнал не попадают персональные данные.
      // Для отказа — начало ответа сервера: Google, например, пишет здесь
      // причину («CalDAV API has not been used in project …»).
      var reason = '';
      if (resp.statusCode >= 400 && resp.statusCode < 500) {
        final b = utf8Body(resp).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (b.isNotEmpty) reason = ': ${b.length > 300 ? '${b.substring(0, 300)}…' : b}';
      }
      AppLogger.warning('DAV $method ${Uri.parse(url).host} → HTTP ${resp.statusCode}$reason');
      return null;
    } catch (e) {
      AppLogger.warning('DAV $method ${Uri.tryParse(url)?.host ?? ''} ошибка: $e');
      return null;
    }
  }

  /// Тело ответа. Без charset в Content-Type пакет http декодирует latin1 —
  /// кириллица в событиях и контактах превращалась в «Ð¾Ñ», а правка
  /// (GET → изменение → PUT) записывала испорченный текст обратно на сервер.
  /// CalDAV/CardDAV по стандарту в UTF-8: декодируем его, если сервер явно не
  /// назвал другую кодировку.
  static String utf8Body(http.Response r) {
    try {
      final ct = (r.headers['content-type'] ?? '').toLowerCase();
      final m = RegExp(r'charset=\s*"?([\w-]+)').firstMatch(ct);
      final cs = m?.group(1);
      if (cs != null && cs != 'utf-8' && cs != 'utf8') return r.body;
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  // ── Обнаружение коллекций ──

  /// Найти URL коллекций (календарей/адресных книг) от базового адреса.
  /// homeProp: 'calendar-home-set' | 'addressbook-home-set'.
  /// collType: локальное имя resourcetype-метки ('calendar' | 'addressbook').
  /// [fallback] — известные адреса коллекций на случай, если сервер не отдал
  /// список (у Google — основной календарь и адресная книга по умолчанию).
  Future<List<String>> discoverCollections(String baseUrl,
      {required String homeProp, required String collType, List<String> fallback = const []}) async {
    final base = Uri.parse(baseUrl);
    // 1) current-user-principal
    final principalXml = await _dav('PROPFIND', baseUrl, depth: 0, body:
        '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>');
    final principal = _href(principalXml, 'current-user-principal') ?? baseUrl;
    final principalUrl = _abs(base, principal);

    // 2) home-set (calendar-home-set / addressbook-home-set)
    final ns = homeProp.contains('calendar')
        ? 'urn:ietf:params:xml:ns:caldav'
        : 'urn:ietf:params:xml:ns:carddav';
    final homeXml = await _dav('PROPFIND', principalUrl, depth: 0, body:
        '<d:propfind xmlns:d="DAV:" xmlns:x="$ns"><d:prop><x:$homeProp/></d:prop></d:propfind>');
    final home = _href(homeXml, homeProp) ?? principalUrl;
    final homeUrl = _abs(base, home);

    // 3) список коллекций нужного типа
    final listXml = await _dav('PROPFIND', homeUrl, depth: 1, body:
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>');
    if (listXml == null) return fallback.isNotEmpty ? fallback : [homeUrl];
    final result = <String>[];
    final doc = XmlDocument.parse(listXml);
    for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
      final isType = resp.descendants.whereType<XmlElement>().any((e) => e.name.local == collType);
      if (!isType) continue;
      final href = resp.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'href').firstOrNull?.innerText.trim();
      if (href != null) result.add(_abs(base, href));
    }
    if (result.isEmpty) return fallback.isNotEmpty ? fallback : [homeUrl];
    return result;
  }

  /// Календари пользователя со свойствами: какие компоненты принимает
  /// (VEVENT/VTODO — у Яндекса списки дел тоже календари), можно ли писать
  /// (подписки на праздники у Google только для чтения).
  Future<List<DavCalendar>> discoverCalendars(String baseUrl, {List<String> fallback = const []}) async {
    final base = Uri.parse(baseUrl);
    final principalXml = await _dav('PROPFIND', baseUrl, depth: 0, body:
        '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>');
    final principalUrl = _abs(base, _href(principalXml, 'current-user-principal') ?? baseUrl);
    final homeXml = await _dav('PROPFIND', principalUrl, depth: 0, body:
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><c:calendar-home-set/></d:prop></d:propfind>');
    final homeUrl = _abs(base, _href(homeXml, 'calendar-home-set') ?? principalUrl);
    final listXml = await _dav('PROPFIND', homeUrl, depth: 1, body:
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><d:resourcetype/><d:displayname/><d:current-user-privilege-set/>'
        '<c:supported-calendar-component-set/></d:prop></d:propfind>');
    List<DavCalendar> fb() => [for (final f in fallback) DavCalendar(url: f)];
    if (listXml == null) return fallback.isNotEmpty ? fb() : [DavCalendar(url: homeUrl)];
    final out = <DavCalendar>[];
    try {
      final doc = XmlDocument.parse(listXml);
      for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
        final els = resp.descendants.whereType<XmlElement>().toList();
        if (!els.any((e) => e.name.local == 'calendar')) continue;
        final href = els.where((e) => e.name.local == 'href').firstOrNull?.innerText.trim();
        if (href == null) continue;
        final comps = [
          for (final c in els.where((e) => e.name.local == 'comp'))
            (c.getAttribute('name') ?? '').toUpperCase()
        ];
        final privs = els.where((e) => e.name.local == 'current-user-privilege-set').firstOrNull;
        final privNames = privs == null
            ? const <String>{}
            : {for (final p in privs.descendants.whereType<XmlElement>()) p.name.local};
        out.add(DavCalendar(
          url: _abs(base, href),
          name: els.where((e) => e.name.local == 'displayname').firstOrNull?.innerText.trim(),
          events: comps.isEmpty || comps.contains('VEVENT'),
          todos: comps.contains('VTODO'),
          // Сервер не сообщил права — считаем, что писать можно.
          writable: privs == null ||
              privNames.length <= 1 || // пустой набор (свойство не найдено) — права неизвестны
              privNames.contains('write') ||
              privNames.contains('write-content') ||
              privNames.contains('all') ||
              privNames.contains('bind'),
        ));
      }
    } catch (_) {}
    if (out.isEmpty) return fallback.isNotEmpty ? fb() : [DavCalendar(url: homeUrl)];
    return out;
  }

  /// События коллекции с адресом и ETag ресурса. [from]/[to] — период
  /// (серии возвращаются целиком, если хоть одно вхождение попадает в
  /// период). Сервер не понял фильтр по времени — повтор без него.
  /// null — запрос не удался (в отличие от пустого календаря).
  Future<List<DavItem>?> reportCalendarItems(String calendarUrl,
      {DateTime? from, DateTime? to, String component = 'VEVENT'}) async {
    String body(bool range) => '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><d:getetag/><c:calendar-data/></d:prop>'
        '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="$component">'
        '${range && from != null && to != null ? '<c:time-range start="${_utcStamp(from)}" end="${_utcStamp(to)}"/>' : ''}'
        '</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>';
    var xml = await _dav('REPORT', calendarUrl, depth: 1, body: body(true));
    if (xml == null && !denied && from != null) {
      xml = await _dav('REPORT', calendarUrl, depth: 1, body: body(false));
    }
    if (xml == null) return null;
    final base = Uri.parse(calendarUrl);
    final out = <DavItem>[];
    try {
      final doc = XmlDocument.parse(xml);
      for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
        final els = resp.descendants.whereType<XmlElement>().toList();
        final data = els.where((e) => e.name.local == 'calendar-data').firstOrNull?.innerText ?? '';
        if (data.trim().isEmpty) continue;
        final href = els.where((e) => e.name.local == 'href').firstOrNull?.innerText.trim() ?? '';
        out.add(DavItem(
          href: href.isEmpty ? '' : _abs(base, href),
          etag: els.where((e) => e.name.local == 'getetag').firstOrNull?.innerText.trim(),
          data: data,
        ));
      }
    } catch (_) {
      return null;
    }
    return out;
  }

  static String _utcStamp(DateTime d) {
    final u = d.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Метка изменений коллекции: CS:getctag (Apple/Яндекс/Mail.ru) или
  /// DAV:sync-token (RFC 6578, Google). Меняется при любом изменении
  /// содержимого — если совпала с прошлой, коллекцию можно не выгружать.
  /// null — сервер метку не дал.
  Future<String?> collectionTag(String url) async {
    final xml = await _dav('PROPFIND', url, depth: 0, body:
        '<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">'
        '<d:prop><cs:getctag/><d:sync-token/></d:prop></d:propfind>');
    if (xml == null) return null;
    try {
      final doc = XmlDocument.parse(xml);
      String? pick(String local) {
        for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == local)) {
          // Свойство в блоке 404 («не найдено») приходит пустым.
          final v = e.innerText.trim();
          if (v.isNotEmpty) return v;
        }
        return null;
      }

      return pick('getctag') ?? pick('sync-token');
    } catch (_) {
      return null;
    }
  }

  // ── Запись: GET / PUT / DELETE ресурса ──

  Future<http.Response?> _raw(String method, String url,
      {String? body, Map<String, String> headers = const {}}) async {
    try {
      final req = http.Request(method, Uri.parse(url));
      req.headers['Authorization'] = authorization;
      req.headers.addAll(headers);
      if (body != null) req.body = body;
      final streamed = await _http.send(req).timeout(const Duration(seconds: 25));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 401 || resp.statusCode == 403) denied = true;
      if (resp.statusCode >= 400) {
        AppLogger.warning('DAV $method ${Uri.parse(url).host} → HTTP ${resp.statusCode}');
      }
      return resp;
    } catch (e) {
      AppLogger.warning('DAV $method ${Uri.tryParse(url)?.host ?? ''} ошибка: $e');
      return null;
    }
  }

  /// Прочитать ресурс: текст и ETag. null — нет ресурса или ошибка.
  Future<({String body, String? etag})?> getResource(String url) async {
    final r = await _raw('GET', url);
    if (r == null || r.statusCode != 200) return null;
    return (body: utf8Body(r), etag: r.headers['etag']);
  }

  /// Записать ресурс. [create] — только если его ещё нет (If-None-Match: *),
  /// [ifMatch] — только если не изменился с прочитанной версии.
  /// Возвращает HTTP-статус (0 — сеть) и новый ETag, если сервер его дал.
  Future<({int status, String? etag})> putResource(String url, String body,
      {String? ifMatch, bool create = false, String contentType = 'text/calendar; charset=utf-8'}) async {
    final r = await _raw('PUT', url, body: body, headers: {
      'Content-Type': contentType,
      if (create) 'If-None-Match': '*',
      if (ifMatch != null && ifMatch.isNotEmpty) 'If-Match': ifMatch,
    });
    return (status: r?.statusCode ?? 0, etag: r?.headers['etag']);
  }

  /// Удалить ресурс. Возвращает HTTP-статус (0 — сеть); 404 — уже удалён.
  Future<int> deleteResource(String url, {String? ifMatch}) async {
    final r = await _raw('DELETE', url,
        headers: {if (ifMatch != null && ifMatch.isNotEmpty) 'If-Match': ifMatch});
    return r?.statusCode ?? 0;
  }

  /// Выгрузить сырые блоки calendar-data из коллекции (REPORT calendar-query).
  Future<List<String>> reportCalendarData(String calendarUrl) async {
    const body = '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><c:calendar-data/></d:prop>'
        '<c:filter><c:comp-filter name="VCALENDAR">'
        '<c:comp-filter name="VEVENT"/></c:comp-filter></c:filter></c:calendar-query>';
    final xml = await _dav('REPORT', calendarUrl, depth: 1, body: body);
    return _extractData(xml, 'calendar-data');
  }

  /// Выгрузить сырые блоки address-data (REPORT addressbook-query).
  Future<List<String>> reportAddressData(String addressbookUrl) async =>
      [for (final i in await reportAddressItems(addressbookUrl) ?? const <DavItem>[]) i.data];

  /// Карточки адресной книги с адресом и ETag (для правки и удаления).
  /// null — запрос не удался.
  /// Серверы, отвечающие 400 на addressbook-query (Google, Яндекс): дальше —
  /// сразу PROPFIND + multiget, без заведомо неудачного запроса и строки
  /// WARN в журнале на каждой синхронизации (журнал 09.10.2026).
  static final Set<String> _noAddressQuery = {'www.googleapis.com', 'carddav.yandex.ru'};

  Future<List<DavItem>?> reportAddressItems(String addressbookUrl) async {
    final host = Uri.parse(addressbookUrl).host;
    if (_noAddressQuery.contains(host)) return _multigetAddressItems(addressbookUrl);
    const body = '<c:addressbook-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
        '<d:prop><d:getetag/><c:address-data/></d:prop></c:addressbook-query>';
    final xml = await _dav('REPORT', addressbookUrl, depth: 1, body: body);
    if (xml != null) return _extractItems(xml, 'address-data', Uri.parse(addressbookUrl));
    if (denied) return null;
    _noAddressQuery.add(host);
    // Google CardDAV не поддерживает addressbook-query (HTTP 400) — только
    // addressbook-multiget и sync-collection. Тогда: список карточек через
    // PROPFIND и выгрузка порциями через multiget.
    return _multigetAddressItems(addressbookUrl);
  }

  Future<List<DavItem>?> _multigetAddressItems(String addressbookUrl) async {
    final base = Uri.parse(addressbookUrl);
    final listXml = await _dav('PROPFIND', addressbookUrl, depth: 1, body:
        '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getcontenttype/></d:prop></d:propfind>');
    if (listXml == null) return null;
    final hrefs = <String>[];
    try {
      final doc = XmlDocument.parse(listXml);
      final self = base.path.endsWith('/') ? base.path : '${base.path}/';
      for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
        final href = resp.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 'href').firstOrNull?.innerText.trim();
        if (href == null || href.isEmpty) continue;
        final path = Uri.parse(_abs(base, href)).path;
        if (path == self || path == base.path) continue; // сама коллекция
        hrefs.add(href);
      }
    } catch (_) {
      return null;
    }
    final out = <DavItem>[];
    for (var i = 0; i < hrefs.length; i += 100) {
      final part = hrefs.sublist(i, i + 100 > hrefs.length ? hrefs.length : i + 100);
      final buf = StringBuffer('<c:addressbook-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
          '<d:prop><d:getetag/><c:address-data/></d:prop>');
      for (final h in part) {
        buf.write('<d:href>${_xmlEscape(h)}</d:href>');
      }
      buf.write('</c:addressbook-multiget>');
      final xml = await _dav('REPORT', addressbookUrl, depth: 1, body: buf.toString());
      if (xml == null) return out.isEmpty ? null : out;
      out.addAll(_extractItems(xml, 'address-data', base));
    }
    AppLogger.info('CardDAV multiget: карточек ${hrefs.length}, получено ${out.length}');
    return out;
  }

  static List<DavItem> _extractItems(String xml, String localName, Uri base) {
    final out = <DavItem>[];
    try {
      final doc = XmlDocument.parse(xml);
      for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
        final els = resp.descendants.whereType<XmlElement>().toList();
        final data = els.where((e) => e.name.local == localName).firstOrNull?.innerText ?? '';
        if (data.trim().isEmpty) continue;
        final href = els.where((e) => e.name.local == 'href').firstOrNull?.innerText.trim() ?? '';
        out.add(DavItem(
          href: href.isEmpty ? '' : _abs(base, href),
          etag: els.where((e) => e.name.local == 'getetag').firstOrNull?.innerText.trim(),
          data: data,
        ));
      }
    } catch (_) {}
    return out;
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // ── Вспомогательные ──

  static List<String> _extractData(String? xml, String localName) {
    if (xml == null) return [];
    try {
      final doc = XmlDocument.parse(xml);
      return doc.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == localName)
          .map((e) => e.innerText)
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String? _href(String? xml, String propLocalName) {
    if (xml == null) return null;
    try {
      final doc = XmlDocument.parse(xml);
      for (final el in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == propLocalName)) {
        final href = el.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 'href').firstOrNull;
        if (href != null) return href.innerText.trim();
      }
    } catch (_) {}
    return null;
  }

  static String _abs(Uri base, String href) {
    if (href.startsWith('http')) return href;
    return base.resolve(href).toString();
  }

  void dispose() => _http.close();
}

/// Календарь (коллекция CalDAV).
class DavCalendar {
  final String url;
  final String? name;
  final bool events;
  final bool todos;
  final bool writable;
  const DavCalendar({required this.url, this.name, this.events = true, this.todos = false, this.writable = true});
}

/// Ресурс календаря: адрес, версия и содержимое.
class DavItem {
  final String href;
  final String? etag;
  final String data;
  const DavItem({required this.href, this.etag, required this.data});
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

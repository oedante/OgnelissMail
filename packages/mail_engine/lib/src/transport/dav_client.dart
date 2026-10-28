// lib/src/transport/dav_client.dart
// CalDAV (RFC 4791) и CardDAV (RFC 6352) клиенты — универсальные.
// Поддерживают Basic и OAuth2 (Bearer). Реализованы реально:
//   - discover(): .well-known → current-user-principal → home-set → коллекции
//   - fetchSome(): выборка нескольких элементов (VEVENT/vCard) с минимальным парсингом
// Этого достаточно для подтверждения работоспособности подключения и синхронизации.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/models.dart';

/// Простой элемент PIM (событие/контакт) для теста.
class DavItem {
  final String href;
  final String summary; // SUMMARY (событие) или FN (контакт)
  final String? extra; // дата начала / email
  const DavItem({required this.href, required this.summary, this.extra});
}

class DavResult {
  final bool success;
  final String? principal;
  final String? homeSet;
  final List<String> collections;
  final List<DavItem> items;
  final String? error;
  final List<String> log;
  const DavResult({
    required this.success,
    this.principal,
    this.homeSet,
    this.collections = const [],
    this.items = const [],
    this.error,
    this.log = const [],
  });
}

enum DavKind { caldav, carddav }

class DavClient {
  final DavKind kind;
  final List<String> _log = [];
  DavClient(this.kind);

  void _l(String m) => _log.add(m);

  Map<String, String> _authHeaders(AccountConfig cfg) {
    if (cfg.authKind == AuthKind.oauth2) {
      return {'Authorization': 'Bearer ${cfg.oauthAccessToken ?? ''}', 'User-Agent': cfg.userAgent};
    }
    final user = cfg.domain != null && cfg.domain!.isNotEmpty
        ? '${cfg.domain}\\${cfg.email.split('@').first}'
        : cfg.email;
    final basic = base64.encode(utf8.encode('$user:${cfg.password ?? ''}'));
    return {'Authorization': 'Basic $basic', 'User-Agent': cfg.userAgent};
  }

  String get _homeProp => kind == DavKind.caldav
      ? '<c:calendar-home-set xmlns:c="urn:ietf:params:xml:ns:caldav"/>'
      : '<a:addressbook-home-set xmlns:a="urn:ietf:params:xml:ns:carddav"/>';

  String get _wellKnown => kind == DavKind.caldav ? '/.well-known/caldav' : '/.well-known/carddav';

  /// Базовый URL: явный (cfg.exchangeServer как DAV base) или из домена email.
  String _baseUrl(AccountConfig cfg) {
    if (cfg.exchangeServer != null && cfg.exchangeServer!.isNotEmpty) {
      final h = cfg.exchangeServer!;
      return h.startsWith('http') ? h : 'https://$h';
    }
    final domain = cfg.email.contains('@') ? cfg.email.split('@').last : '';
    final prefix = kind == DavKind.caldav ? 'caldav' : 'carddav';
    return 'https://$prefix.$domain';
  }

  Future<http.Response> _propfind(Uri url, Map<String, String> headers, String body, {int depth = 0}) {
    final req = http.Request('PROPFIND', url)
      ..headers.addAll({...headers, 'Depth': '$depth', 'Content-Type': 'application/xml; charset=utf-8'})
      ..body = body;
    return http.Client().send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
  }

  /// Discovery + выборка нескольких элементов.
  Future<DavResult> discoverAndFetch(AccountConfig cfg, {int maxItems = 5}) async {
    final headers = _authHeaders(cfg);
    final base = _baseUrl(cfg);
    _l('${kind.name}: база $base');

    try {
      // 1) current-user-principal через .well-known.
      String? principal = await _findPrincipal(Uri.parse('$base$_wellKnown'), headers)
          ?? await _findPrincipal(Uri.parse(base), headers);
      if (principal == null) {
        return DavResult(success: false, error: 'Не найден principal', log: _log);
      }
      principal = _absolute(base, principal);
      _l('${kind.name}: principal $principal');

      // 2) home-set.
      final home = await _findHomeSet(Uri.parse(principal), headers);
      if (home == null) {
        return DavResult(success: false, error: 'Не найден home-set', log: _log);
      }
      final homeAbs = _absolute(base, home);
      _l('${kind.name}: home $homeAbs');

      // 3) Список коллекций (Depth:1).
      final collections = await _listCollections(Uri.parse(homeAbs), headers);
      _l('${kind.name}: коллекций ${collections.length}');

      // 4) Из первой коллекции тянем несколько элементов.
      final items = <DavItem>[];
      if (collections.isNotEmpty) {
        final col = _absolute(base, collections.first);
        items.addAll(await _fetchItems(Uri.parse(col), headers, maxItems));
        _l('${kind.name}: получено элементов ${items.length} из ${collections.first}');
      }

      return DavResult(
        success: true, principal: principal, homeSet: homeAbs,
        collections: collections, items: items, log: _log,
      );
    } catch (e) {
      _l('${kind.name} ошибка: $e');
      return DavResult(success: false, error: '$e', log: _log);
    }
  }

  Future<String?> _findPrincipal(Uri url, Map<String, String> headers) async {
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>';
    try {
      final resp = await _propfind(url, headers, body, depth: 0);
      _l('${kind.name} PROPFIND principal ${url.host} → HTTP ${resp.statusCode}');
      if (resp.statusCode == 301 || resp.statusCode == 302) {
        final loc = resp.headers['location'];
        if (loc != null) return await _findPrincipal(Uri.parse(loc), headers);
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final doc = XmlDocument.parse(resp.body);
        final href = doc.findAllElements('current-user-principal').firstOrNull
            ?.findAllElements('href').firstOrNull?.innerText;
        return href;
      }
    } catch (e) {
      _l('${kind.name} principal ошибка: $e');
    }
    return null;
  }

  Future<String?> _findHomeSet(Uri url, Map<String, String> headers) async {
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>$_homeProp</d:prop></d:propfind>';
    final resp = await _propfind(url, headers, body, depth: 0);
    _l('${kind.name} PROPFIND home ${url.host} → HTTP ${resp.statusCode}');
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final doc = XmlDocument.parse(resp.body);
      final tag = kind == DavKind.caldav ? 'calendar-home-set' : 'addressbook-home-set';
      return doc.findAllElements(tag).firstOrNull?.findAllElements('href').firstOrNull?.innerText;
    }
    return null;
  }

  Future<List<String>> _listCollections(Uri url, Map<String, String> headers) async {
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>';
    final resp = await _propfind(url, headers, body, depth: 1);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return [];
    final doc = XmlDocument.parse(resp.body);
    final want = kind == DavKind.caldav ? 'calendar' : 'addressbook';
    final result = <String>[];
    for (final r in doc.findAllElements('response')) {
      final rt = r.findAllElements('resourcetype').firstOrNull;
      final isTarget = rt?.descendantElements.any((e) => e.name.local == want) ?? false;
      if (isTarget) {
        final href = r.findAllElements('href').firstOrNull?.innerText;
        if (href != null) result.add(href);
      }
    }
    return result;
  }

  Future<List<DavItem>> _fetchItems(Uri collection, Map<String, String> headers, int maxItems) async {
    // PROPFIND Depth:1 — получаем список href элементов, затем GET первых N.
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>';
    final resp = await _propfind(collection, headers, body, depth: 1);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return [];
    final doc = XmlDocument.parse(resp.body);
    final hrefs = <String>[];
    for (final r in doc.findAllElements('response')) {
      final href = r.findAllElements('href').firstOrNull?.innerText;
      if (href != null && (href.endsWith('.ics') || href.endsWith('.vcf'))) hrefs.add(href);
    }
    final items = <DavItem>[];
    final base = '${collection.scheme}://${collection.host}';
    for (final href in hrefs.take(maxItems)) {
      try {
        final get = await http.get(Uri.parse(_absolute(base, href)), headers: headers)
            .timeout(const Duration(seconds: 15));
        if (get.statusCode == 200) {
          items.add(_parseItem(href, get.body));
        }
      } catch (_) {}
    }
    return items;
  }

  DavItem _parseItem(String href, String body) {
    if (kind == DavKind.caldav) {
      final summary = _icalField(body, 'SUMMARY') ?? '(без названия)';
      final dtstart = _icalField(body, 'DTSTART');
      return DavItem(href: href, summary: summary, extra: dtstart);
    } else {
      final fn = _icalField(body, 'FN') ?? '(без имени)';
      final email = _icalField(body, 'EMAIL');
      return DavItem(href: href, summary: fn, extra: email);
    }
  }

  /// Извлекает значение поля iCalendar/vCard (с учётом возможных параметров после ';').
  String? _icalField(String body, String field) {
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.toUpperCase().startsWith('$field:') || line.toUpperCase().startsWith('$field;')) {
        final idx = line.indexOf(':');
        if (idx > 0 && idx < line.length - 1) return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  String _absolute(String base, String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    final b = Uri.parse(base);
    return '${b.scheme}://${b.host}${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }

  List<String> get log => _log;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

// lib/services/security/bimi/site_icon_service.dart
// Значки сайтов отправителей (2.6.1; просьба владельца 16.11.2026: «логотипы
// компаний — Google, Microsoft, Яндекс, Apple, Сбер»). BIMI публикуют
// немногие компании, поэтому у остальных писем вместо буквы — значок сайта
// домена отправителя (apple-touch-icon или favicon), как в браузере.
//
// Решения владельца (16.11.2026): значок берёт сам телефон, напрямую с
// сайта отправителя — без серверов Ogneliss; Gravatar не используется.
// Отсюда правила:
//  · только по настройке «Значки сайтов отправителей» (по умолчанию
//    выключена) и не при запрете внешних служб (MDM block_external_services);
//  · только у писем, отправителя которых подтвердил сервер ящика (DMARC,
//    [bimiDmarcDomain]), — иначе подделка «от банка» получила бы настоящий
//    значок банка; рабочая почта Exchange не участвует;
//  · запрос — по домену, а не по письму: один раз в 30 дней на домен (нет
//    значка — раз в 7 дней), так что сайт не узнаёт, какие письма открыты;
//    бесплатные почтовые домены (gmail.com, mail.ru…) не запрашиваются;
//  · только HTTPS, без cookies, перенаправления — в пределах домена
//    организации; только PNG (в том числе внутри .ico) от 32 до 1024 точек и
//    не больше 100 КБ; SVG и HTML не показываются.
// Сам значок рисует [BimiAvatar], когда логотипа BIMI нет.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/mail_domains.dart' show isPublicMailDomain;
import '../managed_config.dart' show ManagedPolicy;
import 'bimi_rules.dart' show siteDomainOf;

/// Счётчики для диагностики.
abstract final class SiteIconStats {
  static int requests = 0;
  static int found = 0;
  static int empty = 0;
  static int cached = 0;

  /// Последние домены без значка и отправители без подтверждения DMARC
  /// (17.11.2026: по сводке было не понять, почему у Ozon и Сбера буква).
  static final missing = <String>[];
  static final unverified = <String>[];

  static void _remember(List<String> list, String v) {
    list.remove(v);
    list.add(v);
    if (list.length > 12) list.removeAt(0);
  }

  static void noIcon(String domain) => _remember(missing, domain);

  /// Отправитель не подтверждён сервером ящика ([why] — коротко почему).
  static void notVerified(String fromDomain, String why) => _remember(unverified, '$fromDomain ($why)');

  static String summary() => 'запросов к сайтам $requests: найдено $found, без значка $empty; из кэша $cached'
      '${missing.isEmpty ? '' : '; без значка: ${missing.join(', ')}'}'
      '${unverified.isEmpty ? '' : '; без подтверждения DMARC: ${unverified.join(', ')}'}';
}

/// Где хранятся значки: папка в каталоге приложения, в тестах — память.
abstract class SiteIconStore {
  /// Домен → срок (мс от эпохи): больше нуля — значок есть, меньше — нет.
  Future<Map<String, int>> readIndex();
  Future<void> writeIndex(Map<String, int> index);
  Future<Uint8List?> readIcon(String domain);
  Future<void> writeIcon(String domain, Uint8List png);
  Future<void> deleteIcon(String domain);
}

class SiteIconFileStore implements SiteIconStore {
  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/site_icons');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String domain) async => File('${(await _dir()).path}/$domain.png');

  @override
  Future<Map<String, int>> readIndex() async {
    try {
      final f = File('${(await _dir()).path}/index.json');
      if (!await f.exists()) return {};
      final m = jsonDecode(await f.readAsString());
      return m is Map ? {for (final e in m.entries) if (e.value is int) '${e.key}': e.value as int} : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> writeIndex(Map<String, int> index) async {
    final f = File('${(await _dir()).path}/index.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(index), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<Uint8List?> readIcon(String domain) async {
    try {
      final f = await _file(domain);
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeIcon(String domain, Uint8List png) async => (await _file(domain)).writeAsBytes(png, flush: true);

  @override
  Future<void> deleteIcon(String domain) async {
    try {
      final f = await _file(domain);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

class SiteIconMemoryStore implements SiteIconStore {
  final index = <String, int>{};
  final icons = <String, Uint8List>{};
  @override
  Future<Map<String, int>> readIndex() async => Map.of(index);
  @override
  Future<void> writeIndex(Map<String, int> i) async => index
    ..clear()
    ..addAll(i);
  @override
  Future<Uint8List?> readIcon(String domain) async => icons[domain];
  @override
  Future<void> writeIcon(String domain, Uint8List png) async => icons[domain] = png;
  @override
  Future<void> deleteIcon(String domain) async => icons.remove(domain);
}

/// Значок сайта домена: поиск и кэш. Ошибок не бросает.
class SiteIconService {
  SiteIconService({SiteIconStore? store, http.Client? client, DateTime Function()? now})
      : _store = store ?? SiteIconFileStore(),
        _client = client,
        _now = now ?? DateTime.now;

  static const found = Duration(days: 30);
  static const missing = Duration(days: 7);
  static const failed = Duration(days: 1);
  static const maxBytes = 100 * 1024;
  static const maxPage = 256 * 1024;
  static const maxEntries = 600;
  static const _timeout = Duration(seconds: 6);

  final SiteIconStore _store;
  final http.Client? _client;
  final DateTime Function() _now;

  Map<String, int>? _index;
  final _memory = <String, Uint8List>{};
  final _inflight = <String, Future<Uint8List?>>{};
  final _starts = Queue<DateTime>();
  int _active = 0;
  final _waiters = Queue<Completer<void>>();

  /// Версия записей «значка нет»: ответы прежних версий (до поиска на www и
  /// подробного журнала, 2.6.2) забываются один раз — домен спрашивается
  /// заново (17.11.2026: у Ozon и Сбера оставалась буква).
  static const _version = 3;
  static const _versionKey = '~v';

  Map<String, int> _migrate(Map<String, int> index) {
    if (index[_versionKey] == _version) return index;
    index.removeWhere((k, v) => v < 0 || k == _versionKey);
    index[_versionKey] = _version;
    unawaited(_store.writeIndex(index).catchError((Object _) {}));
    return index;
  }

  /// Только сохранённое (первый шаг цепочки иконок): hit — по домену уже
  /// есть ответ (со значком или без), сайт не спрашивается.
  Future<({bool hit, Uint8List? png})> cached(String fromDomain) async {
    final domain = siteDomainOf(fromDomain);
    if (ManagedPolicy.current.blockExternalServices ||
        domain == null ||
        isPublicMailDomain(domain) ||
        isPublicMailDomain(fromDomain)) {
      return (hit: true, png: null);
    }
    final mem = _memory[domain];
    if (mem != null) return (hit: true, png: mem);
    final index = _index ??= _migrate(await _store.readIndex());
    final until = index[domain];
    if (until == null || until.abs() <= _now().millisecondsSinceEpoch) return (hit: false, png: null);
    if (until < 0) return (hit: true, png: null);
    final png = await _store.readIcon(domain);
    if (png == null) return (hit: false, png: null);
    SiteIconStats.cached++;
    return (hit: true, png: _memory[domain] = png);
  }

  /// Значок домена отправителя [fromDomain] (PNG) или null.
  Future<Uint8List?> iconFor(String fromDomain) async {
    if (ManagedPolicy.current.blockExternalServices) return null;
    final domain = siteDomainOf(fromDomain);
    if (domain == null || isPublicMailDomain(domain) || isPublicMailDomain(fromDomain)) return null;
    final mem = _memory[domain];
    if (mem != null) {
      SiteIconStats.cached++;
      return mem;
    }
    return _inflight[domain] ??= _resolve(domain).whenComplete(() {
      _inflight.remove(domain);
    });
  }

  Future<Uint8List?> _resolve(String domain) async {
    final index = _index ??= _migrate(await _store.readIndex());
    final until = index[domain];
    final nowMs = _now().millisecondsSinceEpoch;
    if (until != null && until.abs() > nowMs) {
      if (until < 0) return null;
      final png = await _store.readIcon(domain);
      if (png != null) {
        SiteIconStats.cached++;
        return _memory[domain] = png;
      }
    }
    // Не больше двух запросов сразу и 20 доменов в минуту: лента с сотней
    // новых отправителей не должна разом стучаться в сотню сайтов.
    await _acquire();
    Uint8List? png;
    var ok = true;
    final trace = <String>[];
    try {
      SiteIconStats.requests++;
      png = await fetchIcon(domain, client: _client, trace: trace);
    } catch (e) {
      ok = false;
    } finally {
      _release();
    }
    // Почему значка нет — в журнал одной строкой (раз на домен, повтор не
    // раньше чем через сутки или неделю).
    if (png == null) {
      SiteIconStats.noIcon(domain);
      AppLogger.info('Значок сайта $domain: ${ok ? 'нет' : 'сбой'} — '
          '${trace.isEmpty ? 'нет ответа' : trace.take(8).join('; ')}');
    }
    final ttl = png != null ? found : (ok ? missing : failed);
    final next = _now().add(ttl).millisecondsSinceEpoch;
    index[domain] = png != null ? next : -next;
    if (png != null) {
      SiteIconStats.found++;
      _memory[domain] = png;
      await _store.writeIcon(domain, png);
    } else {
      SiteIconStats.empty++;
      await _store.deleteIcon(domain);
    }
    while (index.length > maxEntries + 1) {
      final old = index.keys.firstWhere((k) => k != _versionKey);
      index.remove(old);
      await _store.deleteIcon(old);
    }
    try {
      await _store.writeIndex(index);
    } catch (_) {}
    return png;
  }

  Future<void> _acquire() async {
    while (true) {
      final now = _now();
      while (_starts.isNotEmpty && now.difference(_starts.first) > const Duration(minutes: 1)) {
        _starts.removeFirst();
      }
      if (_active < 2 && _starts.length < 20) {
        _active++;
        _starts.add(now);
        return;
      }
      if (_active >= 2) {
        final c = Completer<void>();
        _waiters.add(c);
        await c.future;
      } else {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  void _release() {
    _active--;
    if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
  }

  /// Поиск значка на сайте [domain]: apple-touch-icon в корне, значок из
  /// `<link rel="…icon…">` главной страницы, PNG внутри favicon.ico.
  @visibleForTesting
  static Future<Uint8List?> fetchIcon(String domain, {http.Client? client, List<String>? trace}) async {
    final c = client ?? http.Client();
    try {
      Object? err;
      try {
        final png = await _fetchFrom(c, domain, domain, trace);
        if (png != null) return png;
      } catch (e) {
        err = e;
        trace?.add('$domain: ${_short(e)}');
      }
      // Голый домен без HTTPS или без значка, а сайт — на www (16.11.2026:
      // у рассылок с поддоменов — sender.ozon.ru, info.sberbank.ru — значка
      // не было).
      if (!domain.startsWith('www.')) {
        try {
          final png = await _fetchFrom(c, 'www.$domain', domain, trace);
          if (png != null) return png;
        } catch (e) {
          err ??= e;
          trace?.add('www.$domain: ${_short(e)}');
        }
      }
      // Сбой сети — повторить раньше, чем «значка нет».
      if (err != null) throw err;
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Значок с узла [host] (переходы — в пределах домена [org]).
  static String _short(Object e) {
    final s = e.toString();
    if (s.contains('Timeout')) return 'тайм-аут';
    if (s.contains('Failed host lookup')) return 'нет такого узла';
    if (s.contains('Handshake') || s.contains('CERTIFICATE')) return 'ошибка TLS';
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  static Future<Uint8List?> _fetchFrom(http.Client c, String host, String org, [List<String>? trace]) async {
    final domain = host;
    for (final p in const ['/apple-touch-icon.png', '/apple-touch-icon-precomposed.png']) {
      final r = await _get(c, Uri.https(domain, p), org, maxBytes, trace: trace);
      final png = r == null ? null : pngIcon(r.bytes);
      if (png != null) return png;
    }
    final page = await _get(c, Uri.https(domain, '/'), org, maxPage, html: true, trace: trace);
    if (page != null) {
      final text = latin1.decode(page.bytes, allowInvalid: true);
      final links = iconLinks(text, page.url);
      if (links.isEmpty) trace?.add('$domain/: значков в странице нет');
      for (final u in links.take(3)) {
        final r = await _get(c, u, null, maxBytes, trace: trace);
        final png = r == null ? null : (pngIcon(r.bytes) ?? icoPng(r.bytes));
        if (png != null) return png;
      }
    }
    final ico = await _get(c, Uri.https(domain, '/favicon.ico'), org, maxBytes, trace: trace);
    if (ico != null) return icoPng(ico.bytes) ?? pngIcon(ico.bytes);
    return null;
  }

  /// GET без cookies, с переходами только по HTTPS (и, если задан [org], —
  /// только в пределах домена организации). Ответ больше [limit] байт —
  /// null.
  static Future<({Uint8List bytes, Uri url})?> _get(http.Client c, Uri url, String? org, int limit,
      {bool html = false, List<String>? trace}) async {
    var u = url;
    String at() => '${u.host}${u.path}';
    for (var hop = 0; hop < 4; hop++) {
      if (u.scheme != 'https') {
        trace?.add('${at()}: не https');
        return null;
      }
      if (org != null && !_sameOrg(u.host, org)) {
        trace?.add('${url.host}${url.path}: переход на ${u.host}');
        return null;
      }
      final req = http.Request('GET', u)
        ..followRedirects = false
        ..headers['Accept'] = html ? 'text/html' : 'image/png,image/x-icon,image/*;q=0.8'
        ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; OgnelissMail)';
      final r = await c.send(req).timeout(_timeout);
      if (r.statusCode >= 300 && r.statusCode < 400) {
        unawaited(r.stream.drain<void>().catchError((_) {}));
        final loc = r.headers['location'];
        if (loc == null) return null;
        u = u.resolve(loc);
        continue;
      }
      if (r.statusCode != 200) {
        unawaited(r.stream.drain<void>().catchError((_) {}));
        trace?.add('${at()}: HTTP ${r.statusCode}');
        return null;
      }
      final len = r.contentLength;
      if (len != null && len > limit) {
        unawaited(r.stream.drain<void>().catchError((_) {}));
        trace?.add('${at()}: больше ${limit ~/ 1024} КБ');
        return null;
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in r.stream.timeout(_timeout)) {
        b.add(chunk);
        if (b.length > limit) {
          if (!html) return null;
          break; // страница — достаточно начала (значки в <head>)
        }
      }
      return (bytes: b.takeBytes(), url: u);
    }
    return null;
  }

  static bool _sameOrg(String host, String org) {
    final h = host.toLowerCase();
    return h == org || h.endsWith('.$org');
  }

  /// PNG от 32 до 1024 точек — как есть; иначе null.
  @visibleForTesting
  static Uint8List? pngIcon(Uint8List b) {
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (b.length < 33 || b.length > maxBytes) return null;
    for (var i = 0; i < 8; i++) {
      if (b[i] != sig[i]) return null;
    }
    final d = ByteData.sublistView(b);
    final w = d.getUint32(16), h = d.getUint32(20);
    if (w < 32 || h < 32 || w > 1024 || h > 1024) return null;
    return b;
  }

  /// Самый крупный PNG внутри .ico (у старых значков внутри BMP — такие
  /// мелкие, их не берём).
  @visibleForTesting
  static Uint8List? icoPng(Uint8List b) {
    if (b.length < 6 || b[0] != 0 || b[1] != 0 || b[2] != 1 || b[3] != 0) return null;
    final d = ByteData.sublistView(b);
    final n = d.getUint16(4, Endian.little);
    Uint8List? best;
    var bestW = 0;
    for (var i = 0; i < n && i < 32; i++) {
      final e = 6 + i * 16;
      if (e + 16 > b.length) break;
      final w = b[e] == 0 ? 256 : b[e];
      final size = d.getUint32(e + 8, Endian.little);
      final off = d.getUint32(e + 12, Endian.little);
      if (off + size > b.length || size < 33) continue;
      final png = pngIcon(Uint8List.sublistView(b, off, off + size));
      if (png != null && w > bestW) {
        best = Uint8List.fromList(png);
        bestW = w;
      }
    }
    return best;
  }

  /// Адреса значков из `<link rel="…icon…">` страницы — сначала крупные
  /// PNG (apple-touch-icon, sizes); SVG и маски Safari пропускаются.
  @visibleForTesting
  static List<Uri> iconLinks(String html, Uri base) {
    final head = html.length > maxPage ? html.substring(0, maxPage) : html;
    final found = <({Uri url, int score})>[];
    for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final tag = m.group(0)!;
      String? attr(String name) => RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
          .firstMatch(tag)
          ?.let((a) => a.group(2) ?? a.group(3) ?? a.group(4));
      final rel = (attr('rel') ?? '').toLowerCase();
      if (!rel.contains('icon') || rel.contains('mask-icon')) continue;
      final href = attr('href')?.trim();
      if (href == null || href.isEmpty || href.startsWith('data:')) continue;
      final type = (attr('type') ?? '').toLowerCase();
      if (type.contains('svg') || href.toLowerCase().split('?').first.endsWith('.svg')) continue;
      Uri u;
      try {
        u = base.resolve(href);
      } catch (_) {
        continue;
      }
      if (u.scheme != 'https') continue;
      final sizes = RegExp(r'(\d+)x(\d+)').firstMatch(attr('sizes') ?? '');
      // Без sizes размер неизвестен — проверяется после загрузки (pngIcon).
      var score = sizes != null ? int.parse(sizes.group(1)!) : (rel.contains('apple-touch-icon') ? 180 : 48);
      if (score > 1024) score = 0;
      if (href.toLowerCase().split('?').first.endsWith('.png') || type.contains('png')) score += 1;
      found.add((url: u, score: score));
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    return [for (final f in found) if (f.score >= 32) f.url];
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

final siteIconServiceProvider = Provider<SiteIconService>((ref) => SiteIconService());

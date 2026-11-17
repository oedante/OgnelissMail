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
//  · только HTTPS, без cookies; только картинки (PNG, ICO, JPEG, GIF, WebP,
//    BMP — приводятся к PNG) от 32 точек; сохраняется не больше 256 точек и
//    100 КБ; SVG и HTML не показываются.
//
// 17.11.2026 (журнал владельца: из 46 сайтов значок нашёлся у 10):
//  · перенаправления — на любой домен по HTTPS (statuspage.io → atlassian.com,
//    withgoogle.com → google.com). Ограничение «в пределах домена» ничего не
//    защищало: домен уже подтверждён DMARC, и его сайт может отдать любой
//    значок и без перенаправления;
//  · .ico с картинками BMP внутри (google.com), JPEG, GIF, WebP — раньше
//    брались только PNG;
//  · значки из манифеста сайта (`<link rel="manifest">`) — у сайтов-приложений
//    в странице их нет;
//  · запрос — как у браузера телефона: защита от роботов (Qrator, DDoS-Guard)
//    отвечала 418 и 503 на «OgnelissMail»;
//  · «&amp;» в адресе значка раскрывается (stripe.com: HTTP 400).
// Сам значок рисует [BimiAvatar], когда логотипа BIMI нет.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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
  /// Скачиваемый значок (.ico с несколькими размерами бывает 200–400 КБ);
  /// сохраняется — до [maxBytes] после сжатия до [maxSide] точек.
  static const maxDownload = 512 * 1024;
  static const maxSide = 256;
  static const maxPage = 256 * 1024;
  static const maxManifest = 64 * 1024;
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

  /// Версия записей «значка нет»: ответы прежних версий забываются один раз
  /// — домен спрашивается заново (3 — поиск на www и подробный журнал;
  /// 4 — любые картинки, переходы на другие домены, манифест, 17.11.2026).
  static const _version = 4;
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
          '${trace.isEmpty ? 'нет ответа' : trace.take(14).join('; ')}');
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
  /// `<link rel="…icon…">` главной страницы, из манифеста сайта, favicon.ico.
  @visibleForTesting
  static Future<Uint8List?> fetchIcon(String domain, {http.Client? client, List<String>? trace}) async {
    final c = client ?? http.Client();
    final hosts = <String>{};
    try {
      Object? err;
      try {
        final png = await _fetchFrom(c, domain, trace, hosts);
        if (png != null) return png;
      } catch (e) {
        err = e;
        trace?.add('$domain: ${_short(e)}');
      }
      // Голый домен без HTTPS или без значка, а сайт — на www (16.11.2026:
      // у рассылок с поддоменов — sender.ozon.ru, info.sberbank.ru — значка
      // не было). Голый домен сам перевёл на www — там уже искали.
      if (!domain.startsWith('www.') && !hosts.contains('www.$domain')) {
        try {
          final png = await _fetchFrom(c, 'www.$domain', trace, hosts);
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

  static String _short(Object e) {
    final s = e.toString();
    if (s.contains('Timeout')) return 'тайм-аут';
    if (s.contains('Failed host lookup')) return 'нет такого узла';
    if (s.contains('Handshake') || s.contains('CERTIFICATE')) return 'ошибка TLS';
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  /// Значок с узла [host]. [hosts] — узлы, до которых дошли запросы (после
  /// перенаправлений).
  static Future<Uint8List?> _fetchFrom(http.Client c, String host, [List<String>? trace, Set<String>? hosts]) async {
    for (final p in const ['/apple-touch-icon.png', '/apple-touch-icon-precomposed.png']) {
      final png = await _image(c, Uri.https(host, p), trace, hosts);
      if (png != null) return png;
    }
    final page = await _get(c, Uri.https(host, '/'), maxPage, html: true, trace: trace, hosts: hosts);
    // Главная перевела на другой узел (www, другой домен) — favicon там же.
    var site = host;
    if (page != null) {
      site = page.url.host;
      final text = latin1.decode(page.bytes, allowInvalid: true);
      final links = iconLinks(text, page.url);
      final manifest = manifestLink(text, page.url);
      if (links.isEmpty && manifest == null) trace?.add('${page.url.host}/: значков в странице нет');
      for (final u in links.take(3)) {
        final png = await _image(c, u, trace);
        if (png != null) return png;
      }
      if (manifest != null) {
        final m = await _get(c, manifest, maxManifest, trace: trace);
        final icons = m == null ? const <Uri>[] : manifestIcons(utf8.decode(m.bytes, allowMalformed: true), m.url);
        if (m != null && icons.isEmpty) trace?.add('${m.url.host}${m.url.path}: значков в манифесте нет');
        for (final u in icons.take(2)) {
          final png = await _image(c, u, trace);
          if (png != null) return png;
        }
      }
      if (site != host) {
        final png = await _image(c, Uri.https(site, '/apple-touch-icon.png'), trace, hosts);
        if (png != null) return png;
      }
    }
    return _image(c, Uri.https(site, '/favicon.ico'), trace, hosts);
  }

  /// Картинка по адресу [u] → PNG; почему не подошла — в [trace].
  static Future<Uint8List?> _image(http.Client c, Uri u, List<String>? trace, [Set<String>? hosts]) async {
    final r = await _get(c, u, maxDownload, trace: trace, hosts: hosts);
    if (r == null) return null;
    final res = await iconPng(r.bytes);
    if (res.png == null) trace?.add('${r.url.host}${r.url.path}: ${res.why}');
    return res.png;
  }

  /// Заголовки как у браузера телефона: защита сайтов от роботов отвечала
  /// 418 и 503 на «Mozilla/5.0 (compatible; OgnelissMail)» (17.11.2026: cdek.ru,
  /// aeroflot.ru). Cookies не передаются и не сохраняются.
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static String _acceptLanguage() {
    try {
      final l = Platform.localeName.split('.').first.replaceAll('_', '-');
      final lang = l.split('-').first.toLowerCase();
      if (lang.isEmpty || lang == 'c' || lang == 'posix') return 'en;q=0.9';
      return lang == 'en' ? '$l,en;q=0.9' : '$l,$lang;q=0.9,en;q=0.8';
    } catch (_) {
      return 'en;q=0.9';
    }
  }

  /// GET без cookies, с переходами только по HTTPS. Ответ больше [limit]
  /// байт — null (у страницы — её начало).
  static Future<({Uint8List bytes, Uri url})?> _get(http.Client c, Uri url, int limit,
      {bool html = false, List<String>? trace, Set<String>? hosts}) async {
    var u = url;
    String at() => '${u.host}${u.path}';
    for (var hop = 0; hop < 5; hop++) {
      if (u.scheme != 'https') {
        trace?.add('${at()}: не https');
        return null;
      }
      hosts?.add(u.host.toLowerCase());
      final req = http.Request('GET', u)
        ..followRedirects = false
        ..headers['Accept'] = html
            ? 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            : 'image/webp,image/apng,image/png,image/x-icon,image/*;q=0.8,*/*;q=0.5'
        ..headers['Accept-Language'] = _acceptLanguage()
        ..headers['User-Agent'] = _userAgent;
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
      if (len != null && len > limit && !html) {
        unawaited(r.stream.drain<void>().catchError((_) {}));
        trace?.add('${at()}: больше ${limit ~/ 1024} КБ');
        return null;
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in r.stream.timeout(_timeout)) {
        b.add(chunk);
        if (b.length > limit) {
          if (!html) {
            trace?.add('${at()}: больше ${limit ~/ 1024} КБ');
            return null;
          }
          break; // страница — достаточно начала (значки в <head>)
        }
      }
      return (bytes: b.takeBytes(), url: u);
    }
    trace?.add('${url.host}${url.path}: много перенаправлений');
    return null;
  }

  /// Значок → PNG для сохранения: PNG от 32 до 1024 точек — как есть, PNG
  /// внутри .ico — как есть; остальное (ICO с BMP, JPEG, GIF, WebP, BMP,
  /// крупный PNG) — разбирается в отдельном потоке и сжимается до 256 точек.
  /// [why] — почему не подошло (для журнала).
  @visibleForTesting
  static Future<({Uint8List? png, String why})> iconPng(Uint8List b) async {
    final png = pngIcon(b) ?? icoPng(b);
    if (png != null) return (png: png, why: '');
    final kind = imageKind(b);
    if (kind == null) return (png: null, why: _notImage(b));
    try {
      return await Isolate.run(() => convertIcon(b, kind));
    } catch (_) {
      return (png: null, why: 'не разобран ($kind)');
    }
  }

  /// Вид картинки по первым байтам; null — не картинка из разрешённых.
  @visibleForTesting
  static String? imageKind(Uint8List b) {
    bool at(int off, List<int> sig) {
      if (b.length < off + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[off + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (at(0, const [0, 0, 1, 0])) return 'ico';
    if (at(0, const [0xFF, 0xD8, 0xFF])) return 'jpeg';
    if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'gif';
    if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return 'webp';
    if (at(0, const [0x42, 0x4D])) return 'bmp';
    return null;
  }

  static String _notImage(Uint8List b) {
    final head = latin1.decode(b.length > 256 ? Uint8List.sublistView(b, 0, 256) : b, allowInvalid: true).toLowerCase();
    if (head.contains('<svg')) return 'SVG';
    if (head.contains('<html') || head.contains('<!doctype') || head.contains('<head')) return 'не картинка (страница)';
    return 'не картинка';
  }

  /// Разбор картинки и сжатие в PNG (в отдельном потоке: JPEG и ICO
  /// разбираются на Dart, это десятки миллисекунд).
  @visibleForTesting
  static ({Uint8List? png, String why}) convertIcon(Uint8List b, String kind) {
    final img.Decoder dec = switch (kind) {
      'png' => img.PngDecoder(),
      'ico' => img.IcoDecoder(),
      'jpeg' => img.JpegDecoder(),
      'gif' => img.GifDecoder(),
      'webp' => img.WebPDecoder(),
      _ => img.BmpDecoder(),
    };
    final info = dec.startDecode(b);
    if (info == null) return (png: null, why: 'не разобран ($kind)');
    // Картинка-«бомба»: маленький файл, огромный размер в точках.
    if (dec is! img.IcoDecoder && info.width * info.height > 4096 * 4096) {
      return (png: null, why: 'слишком большой ${info.width}×${info.height}');
    }
    var im = dec is img.IcoDecoder ? dec.decodeImageLargest(b) : dec.decodeFrame(0);
    if (im == null) return (png: null, why: 'не разобран ($kind)');
    if (im.width < 32 || im.height < 32) return (png: null, why: 'мал ${im.width}×${im.height}');
    if (im.width > maxSide || im.height > maxSide) {
      im = im.width >= im.height
          ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
    }
    final out = img.encodePng(im);
    if (out.length > maxBytes) return (png: null, why: 'больше ${maxBytes ~/ 1024} КБ после сжатия');
    return (png: Uint8List.fromList(out), why: '');
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

  /// Самый крупный PNG внутри .ico (картинки BMP внутри разбирает
  /// [convertIcon]).
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

  /// Значение атрибута [name] тега [tag] («&amp;» и подобное раскрыты).
  static String? _attr(String tag, String name) {
    final a = RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(tag);
    final v = a == null ? null : (a.group(2) ?? a.group(3) ?? a.group(4));
    return v == null ? null : _unescape(v);
  }

  static String _unescape(String v) => v
      .replaceAll(RegExp('&amp;|&#0*38;|&#x0*26;', caseSensitive: false), '&')
      .replaceAll(RegExp('&quot;|&#0*34;', caseSensitive: false), '"')
      .replaceAll(RegExp('&#0*39;|&#x0*27;|&apos;', caseSensitive: false), "'");

  /// Адреса значков из `<link rel="…icon…">` страницы — сначала крупные
  /// (apple-touch-icon, sizes); SVG и маски Safari пропускаются.
  @visibleForTesting
  static List<Uri> iconLinks(String html, Uri base) {
    final head = html.length > maxPage ? html.substring(0, maxPage) : html;
    final found = <({Uri url, int score})>[];
    for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final tag = m.group(0)!;
      final rel = (_attr(tag, 'rel') ?? '').toLowerCase();
      if (!rel.contains('icon') || rel.contains('mask-icon')) continue;
      final href = _attr(tag, 'href')?.trim();
      if (href == null || href.isEmpty || href.startsWith('data:')) continue;
      final type = (_attr(tag, 'type') ?? '').toLowerCase();
      if (type.contains('svg') || href.toLowerCase().split('?').first.endsWith('.svg')) continue;
      Uri u;
      try {
        u = base.resolve(href);
      } catch (_) {
        continue;
      }
      if (u.scheme != 'https') continue;
      final sizes = RegExp(r'(\d+)x(\d+)').firstMatch(_attr(tag, 'sizes') ?? '');
      // Без sizes размер неизвестен — проверяется после загрузки.
      var score = sizes != null ? int.parse(sizes.group(1)!) : (rel.contains('apple-touch-icon') ? 180 : 48);
      if (score > 1024) score = 0;
      if (href.toLowerCase().split('?').first.endsWith('.png') || type.contains('png')) score += 1;
      found.add((url: u, score: score));
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    return [for (final f in found) if (f.score >= 32) f.url];
  }

  /// Адрес манифеста сайта (`<link rel="manifest">`).
  @visibleForTesting
  static Uri? manifestLink(String html, Uri base) {
    final head = html.length > maxPage ? html.substring(0, maxPage) : html;
    for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final tag = m.group(0)!;
      if (!(_attr(tag, 'rel') ?? '').toLowerCase().split(RegExp(r'\s+')).contains('manifest')) continue;
      final href = _attr(tag, 'href')?.trim();
      if (href == null || href.isEmpty || href.startsWith('data:')) return null;
      try {
        final u = base.resolve(href);
        return u.scheme == 'https' ? u : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Значки из манифеста сайта: сначала обычные (purpose any) от 48 до 512
  /// точек, «maskable» — после них; SVG пропускаются.
  @visibleForTesting
  static List<Uri> manifestIcons(String json, Uri base) {
    Object? j;
    try {
      j = jsonDecode(json);
    } catch (_) {
      return const [];
    }
    final icons = j is Map ? j['icons'] : null;
    if (icons is! List) return const [];
    final found = <({Uri url, int score})>[];
    for (final i in icons) {
      if (i is! Map) continue;
      final src = '${i['src'] ?? ''}'.trim();
      final type = '${i['type'] ?? ''}'.toLowerCase();
      if (src.isEmpty || src.startsWith('data:') || type.contains('svg') || src.toLowerCase().split('?').first.endsWith('.svg')) {
        continue;
      }
      Uri u;
      try {
        u = base.resolve(src);
      } catch (_) {
        continue;
      }
      if (u.scheme != 'https') continue;
      var size = 0;
      for (final s in RegExp(r'(\d+)x(\d+)').allMatches('${i['sizes'] ?? ''}')) {
        final v = int.parse(s.group(1)!);
        if (v > size) size = v;
      }
      if (size != 0 && (size < 32 || size > 1024)) continue;
      // Ближе к 192 — лучше; «maskable» (с полями под маску) — в конце.
      var score = 2000 - (size == 0 ? 400 : (size - 192).abs());
      if ('${i['purpose'] ?? ''}'.contains('maskable') && !'${i['purpose']}'.contains('any')) score -= 1000;
      found.add((url: u, score: score));
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    return [for (final f in found) f.url];
  }
}

final siteIconServiceProvider = Provider<SiteIconService>((ref) => SiteIconService());

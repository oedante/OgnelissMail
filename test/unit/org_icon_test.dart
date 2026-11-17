// Иконки организаций (2.6.1): цепочка «сохранённое → BIMI → значок сайта»
// и поиск значка на сайте отправителя.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/services/security/bimi/bimi_rules.dart';
import 'package:ogneliss/services/security/bimi/bimi_service.dart';
import 'package:ogneliss/services/security/bimi/org_icon.dart';
import 'package:ogneliss/services/security/bimi/site_icon_service.dart';

const _logo = '<svg xmlns="http://www.w3.org/2000/svg" version="1.2" baseProfile="tiny-ps" viewBox="0 0 10 10">'
    '<title>Brand</title><circle cx="5" cy="5" r="4" fill="#c00"/></svg>';

/// Заголовок PNG с размером [w]×[h] (разборщику значка достаточно IHDR).
Uint8List _png(int w, int h, {int pad = 40}) {
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add([0, 0, 0, 13])
    ..add(ascii.encode('IHDR'));
  final d = ByteData(8)
    ..setUint32(0, w)
    ..setUint32(4, h);
  b
    ..add(d.buffer.asUint8List())
    ..add(List.filled(pad, 0));
  return b.takeBytes();
}

/// .ico с одним PNG внутри.
Uint8List _ico(Uint8List png, int w) {
  final head = ByteData(22)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 1, Endian.little)
    ..setUint8(6, w >= 256 ? 0 : w)
    ..setUint8(7, w >= 256 ? 0 : w)
    ..setUint32(14, png.length, Endian.little)
    ..setUint32(18, 22, Endian.little);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...png]);
}

/// .ico с картинкой BMP 32×32 внутри (как favicon.ico google.com).
Uint8List _icoBmp(int w) {
  final dib = BytesBuilder();
  final head = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, w, Endian.little)
    ..setInt32(8, w * 2, Endian.little) // высота с маской AND
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little)
    ..setUint32(20, w * w * 4, Endian.little);
  dib.add(head.buffer.asUint8List());
  for (var i = 0; i < w * w; i++) {
    dib.add(const [0x20, 0x40, 0xC0, 0xFF]); // BGRA
  }
  dib.add(List.filled(w * ((w + 31) ~/ 32) * 4, 0)); // маска AND
  final data = dib.takeBytes();
  final dir = ByteData(22)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 1, Endian.little)
    ..setUint8(6, w)
    ..setUint8(7, w)
    ..setUint16(10, 1, Endian.little)
    ..setUint16(12, 32, Endian.little)
    ..setUint32(14, data.length, Endian.little)
    ..setUint32(18, 22, Endian.little);
  return Uint8List.fromList([...dir.buffer.asUint8List(), ...data]);
}

(int, int) _size(Uint8List png) {
  final d = ByteData.sublistView(png);
  return (d.getUint32(16), d.getUint32(20));
}

class _BimiMem implements BimiCacheStore {
  String? data;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String d) async => data = d;
}

void main() {
  group('значок сайта отправителя', () {
    test('apple-touch-icon в корне', () async {
      final asked = <String>[];
      final png = _png(180, 180);
      final c = MockClient((r) async {
        asked.add(r.url.toString());
        expect(r.headers['Cookie'], isNull);
        return r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(png, 200) : http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('sber.ru', client: c), png);
      expect(asked, ['https://sber.ru/apple-touch-icon.png']);
    });

    test('значок из <link rel="icon"> главной страницы (перенаправление на www)', () async {
      final png = _png(192, 192);
      final c = MockClient((r) async {
        if (r.url.host == 'example.ru' && r.url.path == '/') {
          return http.Response('', 301, headers: {'location': 'https://www.example.ru/'});
        }
        if (r.url.host == 'www.example.ru' && r.url.path == '/') {
          return http.Response(
              '<html><head><link rel="mask-icon" href="/m.svg"><link rel="icon" sizes="16x16" href="/s.png">'
              '<link rel="icon" type="image/png" sizes="192x192" href="/static/i192.png"></head></html>',
              200);
        }
        if (r.url.toString() == 'https://www.example.ru/static/i192.png') return http.Response.bytes(png, 200);
        return http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('example.ru', client: c), png);
    });

    test('PNG внутри favicon.ico', () async {
      final png = _png(64, 64);
      final c = MockClient((r) async =>
          r.url.path == '/favicon.ico' ? http.Response.bytes(_ico(png, 64), 200) : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('ya.example', client: c), png);
    });

    test('http, мелкий и большой значок, страница вместо картинки, бесконечные переходы — нет', () async {
      final loop = MockClient((r) async => http.Response('', 302, headers: {'location': 'https://tracker.example/i.png'}));
      expect(await SiteIconService.fetchIcon('bank.ru', client: loop), isNull);
      final insecure = MockClient((r) async => http.Response('', 302, headers: {'location': 'http://bank.ru/i.png'}));
      expect(await SiteIconService.fetchIcon('bank.ru', client: insecure), isNull);
      final tiny = MockClient((r) async =>
          r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(_png(16, 16), 200) : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('bank.ru', client: tiny), isNull);
      final huge = MockClient((r) async => r.url.path == '/apple-touch-icon.png'
          ? http.Response.bytes(_png(180, 180, pad: 600 * 1024), 200)
          : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('bank.ru', client: huge), isNull);
      final trace = <String>[];
      final html = MockClient((r) async => http.Response('<html>not an image</html>', 200));
      expect(await SiteIconService.fetchIcon('bank.ru', client: html, trace: trace), isNull);
      expect(trace.join('; '), contains('bank.ru/apple-touch-icon.png: не картинка (страница)'));
    });

    test('переход на другой домен — значок того сайта (statuspage.io → atlassian.com, 17.11.2026)', () async {
      final png = _png(180, 180);
      final c = MockClient((r) async {
        if (r.url.host.endsWith('statuspage.io')) {
          return http.Response('', 301, headers: {'location': 'https://www.atlassian.com${r.url.path}'});
        }
        if (r.url.host == 'www.atlassian.com' && r.url.path == '/apple-touch-icon.png') return http.Response.bytes(png, 200);
        return http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('statuspage.io', client: c), png);
    });

    test('.ico с BMP внутри, JPEG и GIF — в PNG (google.com, 17.11.2026)', () async {
      final ico = MockClient((r) async =>
          r.url.path == '/favicon.ico' ? http.Response.bytes(_icoBmp(32), 200) : http.Response('', 404));
      final fromIco = await SiteIconService.fetchIcon('google.com', client: ico);
      expect(fromIco, isNotNull);
      expect(_size(fromIco!), (32, 32));
      expect(img.decodePng(fromIco)!.getPixel(5, 5).r, 0xC0);

      final jpg = img.encodeJpg(img.Image(width: 600, height: 300));
      final cj = MockClient((r) async =>
          r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(jpg, 200) : http.Response('', 404));
      final fromJpg = await SiteIconService.fetchIcon('jpeg.example', client: cj);
      expect(_size(fromJpg!), (256, 128), reason: 'крупный — сжат до 256 точек');

      final gif = img.encodeGif(img.Image(width: 48, height: 48));
      final cg = MockClient((r) async =>
          r.url.path == '/favicon.ico' ? http.Response.bytes(gif, 200) : http.Response('', 404));
      expect(_size((await SiteIconService.fetchIcon('gif.example', client: cg))!), (48, 48));

      final trace = <String>[];
      final small = MockClient((r) async =>
          r.url.path == '/favicon.ico' ? http.Response.bytes(_icoBmp(16), 200) : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('small.example', client: small, trace: trace), isNull);
      expect(trace.join('; '), contains('мал 16×16'));
    });

    test('«&amp;» в адресе значка и значки из манифеста сайта', () async {
      final png = _png(192, 192);
      final c = MockClient((r) async {
        if (r.url.path == '/') {
          return http.Response('<link rel="icon" href="https://cdn.example/f.png?w=180&amp;h=180">', 200);
        }
        if (r.url.toString() == 'https://cdn.example/f.png?w=180&h=180') return http.Response.bytes(png, 200);
        return http.Response('', r.url.path.contains('f.png') ? 400 : 404);
      });
      expect(await SiteIconService.fetchIcon('stripe.example', client: c), png);

      final m = MockClient((r) async {
        if (r.url.path == '/') return http.Response('<head><link rel="manifest" href="/site.webmanifest"></head>', 200);
        if (r.url.path == '/site.webmanifest') {
          return http.Response(
              '{"icons":[{"src":"/m.svg","type":"image/svg+xml"},'
              '{"src":"/mask512.png","sizes":"512x512","purpose":"maskable"},'
              '{"src":"/i192.png","sizes":"192x192","type":"image/png"}]}',
              200);
        }
        if (r.url.path == '/i192.png') return http.Response.bytes(png, 200);
        return http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('spa.example', client: m), png);
    });

    test('голый домен перевёл на www — второй раз www не спрашивается', () async {
      final asked = <String>[];
      final c = MockClient((r) async {
        asked.add('${r.url.host}${r.url.path}');
        if (r.url.host == 'rzd.example' && r.url.path == '/') {
          return http.Response('', 301, headers: {'location': 'https://www.rzd.example/'});
        }
        if (r.url.path == '/') return http.Response('<html></html>', 200);
        return http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('rzd.example', client: c), isNull);
      expect(asked.where((a) => a == 'www.rzd.example/').length, 1);
      expect(asked, contains('www.rzd.example/favicon.ico'));
    });

    test('голый домен без значка или без HTTPS — значок с www (16.11.2026)', () async {
      final png = _png(180, 180);
      final c = MockClient((r) async {
        if (r.url.host == 'ozon.ru') throw http.ClientException('handshake');
        if (r.url.host == 'www.ozon.ru' && r.url.path == '/apple-touch-icon.png') {
          return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
        }
        return http.Response('', 404);
      });
      expect(await SiteIconService.fetchIcon('ozon.ru', client: c), png);
      // Оба узла недоступны — ошибка сети (повторить раньше, чем «нет значка»).
      final down = MockClient((r) async => throw http.ClientException('offline'));
      expect(SiteIconService.fetchIcon('sberbank.ru', client: down), throwsA(isA<http.ClientException>()));
    });

    test('домен сайта — базовый; бесплатная почта не спрашивается; повтор — из сохранённого', () async {
      expect(siteDomainOf('news.sber.ru'), 'sber.ru');
      expect(siteDomainOf('mail.example.co.uk'), 'example.co.uk');
      var calls = 0;
      final png = _png(180, 180);
      final c = MockClient((r) async {
        calls++;
        return r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(png, 200) : http.Response('', 404);
      });
      final s = SiteIconService(store: SiteIconMemoryStore(), client: c);
      expect(await s.iconFor('gmail.com'), isNull);
      expect(await s.iconFor('mail.ru'), isNull);
      expect(calls, 0);
      expect((await s.cached('news.sber.ru')).hit, isFalse);
      expect(await s.iconFor('news.sber.ru'), png);
      expect(await s.iconFor('sber.ru'), png);
      expect(calls, 1);
      expect((await s.cached('sber.ru')).png, png);
    });
  });

  test('«значка нет» прежних версий забывается один раз; почему нет — в сводке (17.11.2026)', () async {
    final store = SiteIconMemoryStore();
    final future = DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch;
    store.index['ozon.ru'] = -future; // ответ 2.6.1: «значка нет» ещё 5 дней
    var calls = 0;
    final c = MockClient((r) async {
      calls++;
      return http.Response('', 403);
    });
    final s = SiteIconService(store: store, client: c);
    expect((await s.cached('sender.ozon.ru')).hit, isFalse, reason: 'старая запись не мешает спросить сайт');
    expect(await s.iconFor('sender.ozon.ru'), isNull);
    expect(calls, greaterThan(0));
    expect(SiteIconStats.summary(), contains('без значка: ozon.ru'));
    // Новая запись «значка нет» действует: второй раз сайт не спрашивается.
    final before = calls;
    final s2 = SiteIconService(store: store, client: c);
    expect((await s2.cached('sender.ozon.ru')).hit, isTrue);
    expect(calls, before);
  });

  group('цепочка: сохранённое → BIMI → сайт', () {
    late List<String> asked;
    late BimiResolver bimi;
    late SiteIconService sites;
    final png = _png(180, 180);

    void setUpChain({required bool bimiLogo}) {
      asked = [];
      final c = MockClient((r) async {
        asked.add(r.url.host == 'proxy.example' ? 'bimi:${r.url.queryParameters['d']}' : 'site:${r.url}');
        if (r.url.host == 'proxy.example') {
          return http.Response(jsonEncode({'policy': 'reject', if (bimiLogo) 'logo': _logo}), 200);
        }
        return r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(png, 200) : http.Response('', 404);
      });
      bimi = BimiResolver(baseUrl: 'https://proxy.example/weather', apiKey: '', cache: BimiCache(_BimiMem()), client: c);
      sites = SiteIconService(store: SiteIconMemoryStore(), client: c);
    }

    test('есть BIMI — логотип, сайт не спрашивается; повтор — без сети', () async {
      setUpChain(bimiLogo: true);
      const k = (bimi: 'bank.ru', site: 'bank.ru');
      expect((await resolveOrgIcon(k, bimi: bimi, sites: sites))?.svg, isNotNull);
      expect(asked, ['bimi:bank.ru']);
      asked.clear();
      expect((await resolveOrgIcon(k, bimi: bimi, sites: sites))?.svg, isNotNull);
      expect(asked, isEmpty);
    });

    test('BIMI нет — значок сайта; повтор — из сохранённого, без BIMI и сайта', () async {
      setUpChain(bimiLogo: false);
      const k = (bimi: 'sber.ru', site: 'sber.ru');
      expect((await resolveOrgIcon(k, bimi: bimi, sites: sites))?.png, png);
      expect(asked, ['bimi:sber.ru', 'site:https://sber.ru/apple-touch-icon.png']);
      asked.clear();
      expect((await resolveOrgIcon(k, bimi: bimi, sites: sites))?.png, png);
      expect(asked, isEmpty);
    });

    test('сохранённый значок сайта — раньше запроса BIMI', () async {
      setUpChain(bimiLogo: true);
      await sites.iconFor('shop.ru');
      asked.clear();
      expect((await resolveOrgIcon((bimi: 'shop.ru', site: 'shop.ru'), bimi: bimi, sites: sites))?.png, png);
      expect(asked, isEmpty, reason: 'сначала локальное');
    });

    test('ящик Google: BIMI не спрашивается, значок сайта — да', () async {
      setUpChain(bimiLogo: true);
      expect((await resolveOrgIcon((bimi: null, site: 'ozon.ru'), bimi: bimi, sites: sites))?.png, png);
      expect(asked.where((a) => a.startsWith('bimi:')), isEmpty);
    });
  });
}

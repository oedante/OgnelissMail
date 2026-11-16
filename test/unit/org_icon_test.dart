// Иконки организаций (2.6.1): цепочка «сохранённое → BIMI → значок сайта»
// и поиск значка на сайте отправителя.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('чужой домен, http, мелкий и большой значок — нет', () async {
      final away = MockClient((r) async => http.Response('', 302, headers: {'location': 'https://tracker.example/i.png'}));
      expect(await SiteIconService.fetchIcon('bank.ru', client: away), isNull);
      final insecure = MockClient((r) async => http.Response('', 302, headers: {'location': 'http://bank.ru/i.png'}));
      expect(await SiteIconService.fetchIcon('bank.ru', client: insecure), isNull);
      final tiny = MockClient((r) async =>
          r.url.path == '/apple-touch-icon.png' ? http.Response.bytes(_png(16, 16), 200) : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('bank.ru', client: tiny), isNull);
      final huge = MockClient((r) async => r.url.path == '/apple-touch-icon.png'
          ? http.Response.bytes(_png(180, 180, pad: 200 * 1024), 200)
          : http.Response('', 404));
      expect(await SiteIconService.fetchIcon('bank.ru', client: huge), isNull);
      final html = MockClient((r) async => http.Response('<html>not an image</html>', 200));
      expect(await SiteIconService.fetchIcon('bank.ru', client: html), isNull);
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

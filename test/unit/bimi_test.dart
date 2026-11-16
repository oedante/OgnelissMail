// Логотипы отправителей BIMI (1.9.x): разбор Authentication-Results, фильтр
// SVG, кэш со сроками и запросы к серверу через подменённый HTTP-клиент.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart' show AccountType;
import 'package:ogneliss/widgets/common/bimi_avatar.dart' show isGoogleMailbox;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/security/bimi/bimi_rules.dart';
import 'package:ogneliss/services/security/bimi/bimi_service.dart';

const _logo = '<svg xmlns="http://www.w3.org/2000/svg" version="1.2" baseProfile="tiny-ps" viewBox="0 0 10 10">'
    '<title>Brand</title><defs><linearGradient id="g"><stop offset="0" stop-color="#c00"/></linearGradient></defs>'
    '<circle cx="5" cy="5" r="4" fill="url(#g)"/></svg>';

class _MemStore implements BimiCacheStore {
  String? data;
  int writes = 0;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String d) async {
    data = d;
    writes++;
  }
}

void main() {
  // 2.5.5: ящики Google — не «свои» серверы. Письма Gmail проверку DMARC
  // получают от mx.google.com, ему логотип не доверяет — домен отправителя
  // на сервер Ogneliss не уходит, данные Google остаются на устройстве.
  test('ящик Google: логотип не ищется, у остальных ящиков — как раньше', () {
    expect(isGoogleMailbox(AccountType.google, const []), isTrue);
    expect(isGoogleMailbox(AccountType.imap, const ['imap.gmail.com', 'smtp.gmail.com']), isTrue,
        reason: 'Gmail паролем приложения или Google Workspace на своём домене');
    expect(isGoogleMailbox(AccountType.yandex, const ['imap.yandex.ru', 'smtp.yandex.ru']), isFalse);
    const gmail = 'mx.google.com; dkim=pass header.i=@bank.example; dmarc=pass (p=REJECT) header.from=bank.example';
    // Только Яндекс — письмо, проверенное Google, не «своё».
    final own = ownMailServerDomains([(email: 'i@yandex.ru', hosts: ['imap.yandex.ru'])]);
    expect(bimiDmarcDomain(gmail, 'news@bank.example', ownServers: own), isNull);
    // Раньше ящик Gmail делал mx.google.com «своим».
    final withGmail = ownMailServerDomains([(email: 'i@gmail.com', hosts: ['imap.gmail.com'])]);
    expect(bimiDmarcDomain(gmail, 'news@bank.example', ownServers: withGmail), 'bank.example');
  });

  group('Authentication-Results', () {
    test('dmarc=pass для домена From в верхнем заголовке', () {
      const ar = 'mx.google.com; dkim=pass header.i=@example.com; spf=pass smtp.mailfrom=example.com; '
          'dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=example.com';
      expect(bimiDmarcDomain(ar, 'News <news@Example.com>'), 'example.com');
      expect(bimiDmarcDomain(ar, 'other@example.org'), isNull, reason: 'header.from другого домена');
    });

    test('dmarc=fail, none и запасной Received-SPF — без логотипа', () {
      expect(bimiDmarcDomain('mx.yandex.ru; dmarc=fail header.from=example.com', 'a@example.com'), isNull);
      expect(bimiDmarcDomain('mx.yandex.ru; none', 'a@example.com'), isNull);
      expect(bimiDmarcDomain('none', 'a@example.com'), isNull);
      expect(bimiDmarcDomain('spf=pass', 'a@example.com'), isNull);
      // 2.6.1: без строки dmarc= — по согласованию: SPF для домена From
      // и есть DMARC (RFC 7489), для чужого домена — нет.
      expect(bimiDmarcDomain('mx.example.net; spf=pass smtp.mailfrom=example.com', 'a@example.com'), 'example.com');
      expect(bimiDmarcDomain('mx.example.net; spf=pass smtp.mailfrom=other.example', 'a@example.com'), isNull);
      expect(bimiDmarcDomain(null, 'a@example.com'), isNull);
    });

    test('учитывается только верхний (доверенный) заголовок', () {
      // Верхний — сервер пользователя: DMARC не прошёл. Ниже — заголовок,
      // который мог вписать сам отправитель, с «dmarc=pass».
      const headers = [
        'mx.own-provider.ru; dmarc=fail header.from=example.com',
        'evil.example; dmarc=pass header.from=example.com',
      ];
      expect(bimiDmarcDomain(headers.first, 'a@example.com'), isNull);
      // ActiveSync склеивает одноимённые заголовки через «; ».
      expect(bimiDmarcDomain('mx.own-provider.ru; spf=pass smtp.mailfrom=other.example; '
          'evil.example; dmarc=pass header.from=example.com', 'a@example.com'), isNull);
      expect(bimiDmarcDomain('mx.own-provider.ru; dmarc=pass header.from=example.com; '
          'relay.example; dmarc=fail', 'a@example.com'), 'example.com');
    });

    test('домен From: IDN не в punycode и IP — без логотипа', () {
      expect(bimiFromDomain('a@пример.рф'), isNull);
      expect(bimiFromDomain('a@[1.2.3.4]'), isNull);
      expect(bimiFromDomain('a@xn--e1afmkfd.xn--p1ai'), 'xn--e1afmkfd.xn--p1ai');
    });
  });

  group('фильтр SVG', () {
    test('допустимый логотип проходит', () {
      expect(BimiSvgFilter.isSafe(_logo), isTrue);
      expect(BimiSvgFilter.isSafe('<?xml version="1.0"?>\n$_logo'), isTrue);
    });

    test('скрипт, foreignObject, внешние ссылки, обработчики — отказ', () {
      const head = '<svg xmlns="http://www.w3.org/2000/svg">';
      for (final bad in [
        '$head<script>alert(1)</script><path d="M0 0"/></svg>',
        '$head<foreignObject><div/></foreignObject><path d="M0 0"/></svg>',
        '$head<image href="https://e.example/x.png"/><path d="M0 0"/></svg>',
        '$head<use href="https://e.example/s.svg#a"/></svg>',
        '$head<use xlink:href="data:image/svg+xml;base64,AAAA"/></svg>',
        '$head<path d="M0 0" fill="url(https://e.example/x)"/></svg>',
        '$head<path d="M0 0" style="fill:url(http://e.example/x)"/></svg>',
        '$head<path d="M0 0" onclick="x()"/></svg>',
        '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><path d="M0 0"/></svg>',
        '<!DOCTYPE svg [<!ENTITY x "y">]><svg><path d="M0 0"/></svg>',
        '$head<text><![CDATA[x]]></text></svg>',
        '<html><path d="M0 0"/></html>',
        '$head<title>пусто</title></svg>',
        '$head<path d="M0 0"></svg>',
      ]) {
        expect(BimiSvgFilter.isSafe(bad), isFalse, reason: bad);
      }
    });

    test('больше 32 КБ — отказ', () {
      final big = '<svg xmlns="http://www.w3.org/2000/svg"><path d="${'M0 0 ' * 7000}"/></svg>';
      expect(big.length > BimiSvgFilter.maxBytes, isTrue);
      expect(BimiSvgFilter.isSafe(big), isFalse);
    });
  });

  group('кэш', () {
    test('логотип — 7 дней, «нет» — 1 день, сбой — 30 минут и не на диск', () async {
      var now = DateTime(2026, 11, 1, 12);
      final store = _MemStore();
      final cache = BimiCache(store, now: () => now);
      await cache.load();
      cache.put('brand.example', _logo);
      cache.put('none.example', null);
      cache.put('down.example', null, transient: true);
      await cache.flush();
      expect(cache.lookup('brand.example'), (hit: true, svg: _logo));
      expect(cache.lookup('none.example'), (hit: true, svg: null));
      expect(cache.lookup('down.example').hit, isTrue);

      final saved = jsonDecode(store.data!) as Map;
      expect(saved.keys, unorderedEquals(['brand.example', 'none.example']));

      now = now.add(const Duration(minutes: 31));
      expect(cache.lookup('down.example').hit, isFalse);
      now = now.add(const Duration(days: 1));
      expect(cache.lookup('none.example').hit, isFalse);
      expect(cache.lookup('brand.example').hit, isTrue);

      // После перезапуска — с диска, срок прежний.
      final again = BimiCache(store, now: () => now);
      await again.load();
      expect(again.lookup('brand.example').svg, _logo);
      expect(again.lookup('none.example').hit, isFalse);
      now = now.add(const Duration(days: 6));
      expect(again.lookup('brand.example').hit, isFalse);
    });

    test('испорченный логотип в файле не загружается', () async {
      final store = _MemStore()
        ..data = jsonEncode({
          'bad.example': {'u': DateTime(2030).millisecondsSinceEpoch, 's': '<svg><script/></svg>'},
        });
      final cache = BimiCache(store, now: () => DateTime(2026, 11, 1));
      await cache.load();
      expect(cache.lookup('bad.example').hit, isFalse);
    });
  });

  group('запросы к серверу', () {
    BimiResolver resolver(MockClient client, _MemStore store) => BimiResolver(
          baseUrl: 'https://proxy.example/oauth/',
          apiKey: 'k',
          cache: BimiCache(store, now: () => DateTime(2026, 11, 1)),
          client: client,
        );

    test('логотип при reject; ключ и адрес; повтор — из кэша', () async {
      final seen = <http.Request>[];
      final client = MockClient((req) async {
        seen.add(req);
        return http.Response(jsonEncode({'policy': 'reject', 'logo': _logo}), 200);
      });
      final r = resolver(client, _MemStore());
      final results = await Future.wait([r.logoFor('brand.example'), r.logoFor('brand.example')]);
      expect(results, [_logo, _logo]);
      expect(await r.logoFor('brand.example'), _logo);
      expect(seen, hasLength(1));
      expect(seen.single.url.toString(), 'https://proxy.example/oauth/bimi?d=brand.example');
      expect(seen.single.headers['x-api-key'], 'k');
    });

    test('политика none, опасный SVG, сбой — без логотипа', () async {
      final client = MockClient((req) async {
        switch (req.url.queryParameters['d']) {
          case 'none.example':
            return http.Response(jsonEncode({'policy': 'none', 'logo': _logo}), 200);
          case 'evil.example':
            return http.Response(
                jsonEncode({'policy': 'reject', 'logo': '<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>'}), 200);
          default:
            return http.Response('{"error":"unavailable"}', 503);
        }
      });
      final r = resolver(client, _MemStore());
      expect(await r.logoFor('none.example'), isNull);
      expect(await r.logoFor('evil.example'), isNull);
      expect(await r.logoFor('down.example'), isNull);
      expect(r.cache.lookup('down.example').hit, isTrue, reason: 'сбой — коротко в памяти');
    });

    test('счётчики для диагностики: логотип, без логотипа, ошибка, кэш (1.10.1)', () async {
      final before = (BimiStats.requests, BimiStats.logos, BimiStats.empty, BimiStats.errors, BimiStats.cached);
      final client = MockClient((req) async => switch (req.url.queryParameters['d']) {
            'brand.example' => http.Response(jsonEncode({'policy': 'reject', 'logo': _logo}), 200),
            'plain.example' => http.Response(jsonEncode({'policy': 'none', 'logo': null}), 200),
            _ => http.Response('{"error":"unavailable"}', 503),
          });
      final r = resolver(client, _MemStore());
      await r.logoFor('brand.example');
      await r.logoFor('brand.example');
      await r.logoFor('plain.example');
      await r.logoFor('down.example');
      BimiStats.eligible('brand.example');
      expect(BimiStats.requests - before.$1, 3);
      expect(BimiStats.logos - before.$2, 1);
      expect(BimiStats.empty - before.$3, 1);
      expect(BimiStats.errors - before.$4, 1);
      expect(BimiStats.cached - before.$5, 1);
      expect(BimiStats.summary(), contains('с логотипом'));
      expect(BimiStats.summary(), isNot(contains('brand.example')), reason: 'домены в диагностику не пишутся');
    });

    test('сервер без /bimi — запросы прекращаются', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('not found', 404);
      });
      final r = resolver(client, _MemStore());
      expect(await r.logoFor('a.example'), isNull);
      expect(await r.logoFor('b.example'), isNull);
      expect(calls, 1);
    });

    test('не больше двух запросов одновременно', () async {
      var active = 0;
      var peak = 0;
      final client = MockClient((req) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return http.Response(jsonEncode({'policy': 'none', 'logo': null}), 200);
      });
      final r = resolver(client, _MemStore());
      await Future.wait([for (var i = 0; i < 6; i++) r.logoFor('d$i.example')]);
      expect(peak, 2);
    });
  });

  group('2.0.0: заголовок — только от сервера своего ящика', () {
    final own = ownMailServerDomains([
      (email: 'o.e@yamalspg.ru', hosts: ['https://mail.yamalspg.ru/EWS/Exchange.asmx', null]),
      (email: 'me@gmail.com', hosts: ['imap.gmail.com']),
      (email: 'me@yandex.ru', hosts: ['imap.yandex.ru']),
    ]);

    test('домены ящиков, их серверов и подписей крупных служб', () {
      expect(own, containsAll(['yamalspg.ru', 'gmail.com', 'google.com', 'yandex.ru', 'yandex.net']));
    });

    test('свой сервер — логотип; чужой верхний заголовок — нет', () {
      const pass = 'dmarc=pass header.from=bank.ru';
      expect(bimiDmarcDomain('mx.google.com; $pass', 'info@bank.ru', ownServers: own), 'bank.ru');
      expect(bimiDmarcDomain('mxfront1o.mail.yandex.net; $pass', 'info@bank.ru', ownServers: own), 'bank.ru');
      expect(bimiDmarcDomain('mx1.attacker.example; $pass', 'info@bank.ru', ownServers: own), isNull,
          reason: 'Exchange организации заголовок не ставит — верхний написал чужой сервер');
      expect(bimiDmarcDomain('google.com.attacker.example; $pass', 'info@bank.ru', ownServers: own), isNull);
    });

    test('authserv-id с версией и точкой в конце', () {
      expect(isOwnAuthServ('mx.google.com 1', own), isTrue);
      expect(isOwnAuthServ('mail.yamalspg.ru.', own), isTrue);
      expect(isOwnAuthServ('notyamalspg.ru', own), isFalse);
    });
  });

  group('2.6.1: Яндекс, Mail.ru и iCloud — логотипы были недоступны', () {
    final yandex = ownMailServerDomains([(email: 'i@yandex.ru', hosts: ['imap.yandex.ru'])]);
    final icloud = ownMailServerDomains([(email: 'e@icloud.com', hosts: ['imap.mail.me.com'])]);
    final mailru = ownMailServerDomains([(email: 'm@mail.ru', hosts: ['imap.mail.ru'])]);

    test('Яндекс: без dmarc=, authserv-id без домена — DKIM домена From засчитан', () {
      // Настоящий заголовок письма с Яндекса (12.11.2026).
      const real = 'mail-nwsmtp-mxback-production-main-39; dkim=pass header.i=@yandex.ru';
      expect(bimiDmarcDomain(real, 's2552844@yandex.ru', ownServers: yandex), 'yandex.ru');
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-production-main-7; dkim=pass header.d=sberbank.ru', 'info@sberbank.ru',
              ownServers: yandex),
          'sberbank.ru');
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-production-main-7; dkim=pass header.d=mail.sberbank.ru',
              'info@sberbank.ru', ownServers: yandex),
          'sberbank.ru', reason: 'поддомен — нестрогое согласование DMARC');
    });

    test('подпись чужого домена, провал и чужой сервер — без логотипа', () {
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-1; dkim=pass header.d=attacker.example', 'info@sberbank.ru',
              ownServers: yandex),
          isNull, reason: 'DKIM есть, но домен подписи не совпадает с From');
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-1; dkim=fail header.d=sberbank.ru', 'info@sberbank.ru',
              ownServers: yandex),
          isNull);
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-1; dkim=pass header.d=notsberbank.ru', 'info@sberbank.ru',
              ownServers: yandex),
          isNull);
      expect(bimiDmarcDomain('mail-nwsmtp-mxfront-1; dkim=pass header.d=sberbank.ru', 'info@sberbank.ru',
              ownServers: mailru),
          isNull, reason: 'имя сервера Яндекса без домена доверяется только у ящиков Яндекса');
      expect(bimiDmarcDomain('mxs.mail.ru; dkim=pass header.d=sberbank.ru; dmarc=fail header.from=sberbank.ru',
              'info@sberbank.ru', ownServers: mailru),
          isNull, reason: 'провал DMARC важнее пройденного DKIM');
    });

    test('Mail.ru: SPF домена From засчитан', () {
      expect(bimiDmarcDomain('mxs.mail.ru; spf=pass smtp.mailfrom=noreply@news.ozon.ru', 'info@ozon.ru',
              ownServers: mailru),
          'ozon.ru');
    });

    test('iCloud: результаты разными заголовками — берутся все заголовки iCloud сверху', () {
      final merged = ownAuthResultsHeader([
        'bimi.icloud.com; bimi=skipped reason="insufficient dmarc"',
        'dmarc.icloud.com; dmarc=pass header.from=apple.com',
        'dkim-verifier.icloud.com;\r\n\tdkim=pass (2048-bit key) header.d=apple.com',
        // Ниже — добавлено раньше по пути письма: не берётся.
        'mx.attacker.example; dmarc=pass header.from=sberbank.ru',
        'dmarc.icloud.com; dmarc=pass header.from=sberbank.ru',
      ]);
      expect(merged, isNot(contains('attacker')));
      expect(merged, isNot(contains('sberbank')));
      expect(bimiDmarcDomain(merged, 'news@apple.com', ownServers: icloud), 'apple.com');
      expect(bimiDmarcDomain(merged, 'info@sberbank.ru', ownServers: icloud), isNull);
      expect(ownAuthResultsHeader(const []), isNull);
      expect(ownAuthResultsHeader(['mx.google.com; dkim=pass header.d=a.ru', 'mx.google.com; spf=pass']),
          'mx.google.com; dkim=pass header.d=a.ru; mx.google.com; spf=pass');
    });
  });
}

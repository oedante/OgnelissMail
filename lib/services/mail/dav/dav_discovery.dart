// lib/services/mail/dav/dav_discovery.dart
// Календарь и контакты рабочей почты по IMAP (2.6.0): где у организации
// CalDAV и CardDAV — по RFC 6764.
//
// Для почты на своём сервере организации (Nextcloud, SOGo, Zimbra, Kerio,
// Communigate, Radicale, Baïkal…) адрес календаря и контактов не известен
// заранее. Ищем так, как велит RFC 6764:
//  1. записи SRV _caldavs._tcp.<домен> / _carddavs._tcp.<домен> (DNS
//     устройства, system_dns.dart) и путь из TXT («path=/dav/»), иначе
//     /.well-known/caldav на найденном узле;
//  2. /.well-known/caldav (carddav) на сервере IMAP ящика, на mail.<домен>
//     и на самом домене.
// Сначала адрес проверяется без учётных данных (ответ DAV: 207, 401 после
// перенаправления с .well-known, заголовок DAV), и только потом — с
// логином и паролем ящика (principal пользователя). Пароль уходит лишь
// серверам домена организации и тем, что опубликовал её администратор, и
// только тем, что ответили как сервер DAV, — не сайту на чужом хостинге.
// Серверы Ogneliss и посторонние службы не участвуют.
//
// Найденное хранится по ящику (SharedPreferences), ничего не найдено —
// повтор через неделю.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/mail_domains.dart' show mailDomainOf, sameOrgDomain;
import '../../../data/models/account_model.dart';
import '../../net/system_dns.dart';
import 'dav_client.dart';

/// Что нашли: начальные адреса календаря и контактов (null — нет).
typedef DavFound = ({String? cal, String? card});

class DavDiscovery {
  DavDiscovery._();

  static const _prefix = 'dav_found_';
  static const _recheck = Duration(days: 7);

  /// Найденное по адресу ящика (нижний регистр).
  static final Map<String, DavFound> _byEmail = {};
  static bool _loaded = false;
  static final Set<String> _running = {};

  static String _k(String email) => email.trim().toLowerCase();

  static String? calendarFor(String email) => _byEmail[_k(email)]?.cal;
  static String? contactsFor(String email) => _byEmail[_k(email)]?.card;
  static bool has(String email) => calendarFor(email) != null || contactsFor(email) != null;

  @visibleForTesting
  static void put(String email, DavFound f) => _byEmail[_k(email)] = f;

  @visibleForTesting
  static void reset() {
    _byEmail.clear();
    _loaded = false;
  }

  /// Найденное ранее — из настроек (один раз за запуск).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        final m = jsonDecode(prefs.getString(key) ?? '{}');
        if (m is! Map) continue;
        final email = m['email'] as String?;
        if (email == null) continue;
        final f = (cal: m['cal'] as String?, card: m['card'] as String?);
        if (f.cal != null || f.card != null) _byEmail[_k(email)] = f;
      }
    } catch (_) {}
  }

  static Future<void> forget(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$accountId');
      if (raw != null) {
        final email = (jsonDecode(raw) as Map)['email'] as String?;
        if (email != null) _byEmail.remove(_k(email));
      }
      await prefs.remove('$_prefix$accountId');
    } catch (_) {}
  }

  /// Ящик IMAP с паролем, у которого календарь и контакты не известны по
  /// домену ([knownProvider] — провайдер по домену или null), — найти,
  /// если не искали последнюю неделю. [authorization] — заголовок входа
  /// (Basic с логином ящика). Ошибок не бросает.
  static Future<void> ensure(AccountModel account, String? knownProvider, Future<String?> Function() authorization,
      {DnsLookup? dns, http.Client? client}) async {
    await load();
    if (account.type != AccountType.imap || account.isOAuth || knownProvider != null) return;
    if (has(account.email) || !_running.add(account.id)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix${account.id}');
      final at = raw == null ? null : DateTime.tryParse(((jsonDecode(raw) as Map)['at'] as String?) ?? '');
      if (at != null && DateTime.now().difference(at) < _recheck) return;
      final auth = await authorization();
      if (auth == null) return;
      final found = await discover(account, auth, dns: dns, client: client).timeout(const Duration(seconds: 45),
          onTimeout: () => (cal: null, card: null));
      if (found.cal != null || found.card != null) _byEmail[_k(account.email)] = found;
      await prefs.setString(
          '$_prefix${account.id}',
          jsonEncode({
            'email': account.email,
            'cal': found.cal,
            'card': found.card,
            'at': DateTime.now().toIso8601String(),
          }));
      AppLogger.info('Календарь и контакты рабочей почты: календарь ${found.cal != null ? 'найден' : 'нет'}, '
          'контакты ${found.card != null ? 'найдены' : 'нет'}');
    } catch (e) {
      AppLogger.info('Календарь и контакты рабочей почты: поиск не удался — $e');
    } finally {
      _running.remove(account.id);
    }
  }

  /// Поиск по RFC 6764 (см. описание файла).
  static Future<DavFound> discover(AccountModel account, String authorization,
      {DnsLookup? dns, http.Client? client}) async {
    final domain = mailDomainOf(account.email);
    if (domain.isEmpty) return (cal: null, card: null);
    final look = dns ?? SystemDns.lookup;
    final c = client ?? http.Client();
    try {
      final rec = await look([
        DnsQuestion('_caldavs._tcp.$domain', DnsType.srv),
        DnsQuestion('_caldavs._tcp.$domain', DnsType.txt),
        DnsQuestion('_carddavs._tcp.$domain', DnsType.srv),
        DnsQuestion('_carddavs._tcp.$domain', DnsType.txt),
      ]);
      final imapHost = (account.imapServer ?? '').trim().toLowerCase();
      Future<String?> find(String kind, DnsRecord? srv, List<DnsRecord>? txt) async {
        final candidates = <({String url, bool trusted})>[
          if (srv != null)
            (url: _srvUrl(srv, kind, _txtPath(txt)), trusted: true),
          if (imapHost.isNotEmpty) (url: 'https://$imapHost/.well-known/$kind', trusted: true),
          if ('mail.$domain' != imapHost) (url: 'https://mail.$domain/.well-known/$kind', trusted: false),
          (url: 'https://$domain/.well-known/$kind', trusted: false),
        ];
        for (final cand in candidates) {
          final start = await davStart(c, cand.url, domain: domain, trusted: cand.trusted);
          if (start == null) continue;
          final principal = await DavClient(authorization, httpClient: c).principalOf(start);
          if (principal != null) return start;
        }
        return null;
      }

      final cal = await find('caldav', SystemDns.bestSrv(rec[0]), rec[1]);
      final card = await find('carddav', SystemDns.bestSrv(rec[2]), rec[3]);
      return (cal: cal, card: card);
    } finally {
      if (client == null) c.close();
    }
  }

  static String _srvUrl(DnsRecord srv, String kind, String? path) {
    final host = srv.target.toLowerCase();
    final port = srv.port == 443 ? '' : ':${srv.port}';
    final p = (path == null || path.isEmpty) ? '/.well-known/$kind' : (path.startsWith('/') ? path : '/$path');
    return 'https://$host$port$p';
  }

  /// «path=/dav/» из TXT (RFC 6764, 4).
  static String? _txtPath(List<DnsRecord>? txt) {
    for (final t in txt ?? const <DnsRecord>[]) {
      final m = RegExp(r'(?:^|\s)path=(\S+)').firstMatch(t.target);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Адрес начала DAV по [url] — без учётных данных: PROPFIND, переходы по
  /// перенаправлениям (только HTTPS и только в домене организации или на
  /// том же узле), ответ сервера DAV. [trusted] — узел, которому пароль и
  /// так доверен (сервер IMAP, запись SRV): там достаточно 401. null — не
  /// DAV.
  @visibleForTesting
  static Future<String?> davStart(http.Client c, String url,
      {required String domain, required bool trusted}) async {
    var u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return null;
    final firstHost = u.host;
    var redirected = false;
    for (var hop = 0; hop < 4; hop++) {
      final req = http.Request('PROPFIND', u!)
        ..followRedirects = false
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml; charset=utf-8'
        ..body = '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>';
      http.StreamedResponse r;
      try {
        r = await c.send(req).timeout(const Duration(seconds: 8));
      } catch (_) {
        return null;
      }
      final code = r.statusCode;
      unawaited(r.stream.drain<void>().catchError((_) {}));
      if (code >= 300 && code < 400) {
        final loc = r.headers['location'];
        if (loc == null) return null;
        final next = u.resolve(loc);
        final sameOrg = next.host == firstHost || sameOrgDomain(next.host, domain);
        if (next.scheme != 'https' || !sameOrg) return null;
        u = next;
        redirected = true;
        continue;
      }
      final dav = r.headers.containsKey('dav');
      if (code == 207 || (dav && (code == 401 || code == 200))) return u.toString();
      if (code == 401 && (trusted || redirected)) return u.toString();
      return null;
    }
    return null;
  }
}

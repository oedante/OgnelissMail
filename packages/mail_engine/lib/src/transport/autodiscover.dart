// lib/src/transport/autodiscover.dart
// Универсальный Exchange Autodiscover (без привязки к конкретной организации).
// Определяет EWS URL и/или EAS (ActiveSync) URL по адресу email.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class AutodiscoverResult {
  final String? ewsUrl;
  final String? easUrl;
  final List<String> log;
  const AutodiscoverResult({this.ewsUrl, this.easUrl, this.log = const []});
}

class Autodiscover {
  static const _outlookReq = 'http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006';
  static const _outlookResp = 'http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a';
  // Запрос MobileSync — в СВОЁМ пространстве имён. Раньше уходил в схеме
  // Outlook, и часть серверов отвечала ошибкой 600 (Invalid Request):
  // адрес ActiveSync так и не находился.
  static const _mobileReq = 'http://schemas.microsoft.com/exchange/autodiscover/mobilesync/requestschema/2006';
  static const _mobileResp = 'http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006';

  /// Пытается определить EWS и EAS URL по email.
  /// authHeader — заголовок Authorization (Basic ...), userAgent — UA.
  /// [httpClient] — корпоративный клиент приложения (доверенные внутренние
  /// центры сертификации, закрепление): с обычным клиентом Autodiscover
  /// внутреннего сервера падал на проверке сертификата.
  static Future<AutodiscoverResult> discover({
    required String email,
    required String authHeader,
    required String userAgent,
    Duration timeout = const Duration(seconds: 15),
    http.Client? httpClient,
  }) async {
    final log = <String>[];
    final domain = email.contains('@') ? email.split('@').last : email;
    if (domain.isEmpty) return const AutodiscoverResult(log: ['Autodiscover: пустой домен']);
    final client = httpClient ?? http.Client();
    final ownClient = httpClient == null;

    try {
      // Стандартные точки Autodiscover (MS-OXDISCO 3.1.5).
      final candidates = <String>[
        'https://autodiscover.$domain/Autodiscover/Autodiscover.xml',
        'https://$domain/Autodiscover/Autodiscover.xml',
      ];

      String? ewsUrl;
      String? easUrl;
      var currentEmail = email;

      Future<void> tryAll(List<String> urls) async {
        for (final start in urls) {
          var url = start;
          final seen = <String>{};
          for (var hop = 0; hop < 5 && seen.add('$url|$currentEmail'); hop++) {
            final r = await _tryPox(client,
                url: url, email: currentEmail, authHeader: authHeader, userAgent: userAgent,
                requestNs: _outlookReq, responseSchema: _outlookResp,
                extract: _extractEwsUrl, log: log, timeout: timeout);
            ewsUrl ??= r.value;
            final r2 = await _tryPox(client,
                url: url, email: currentEmail, authHeader: authHeader, userAgent: userAgent,
                requestNs: _mobileReq, responseSchema: _mobileResp,
                extract: _extractEasUrl, log: log, timeout: timeout);
            easUrl ??= r2.value;
            if (ewsUrl != null && easUrl != null) break;
            // Перенаправление на другой адрес почты (redirectAddr) —
            // повторяем с ним на том же сервере.
            final redirect = r.redirectAddr ?? r2.redirectAddr;
            if (redirect != null && redirect != currentEmail) {
              log.add('Autodiscover: перенаправление на адрес $redirect');
              currentEmail = redirect;
              continue;
            }
            // Перенаправление на другой адрес сервера: <Action>redirectUrl
            // в ответе или HTTP 301/302/307/308 на POST (аудит 07.10.2026,
            // E4). Только https и только в домене почты — см. [_sameDomain].
            final next = r.redirectUrl ?? r2.redirectUrl;
            if (next != null && next != url) {
              if (!_sameDomain(next, domain)) {
                log.add('Autodiscover: перенаправление на $next — другой домен, не следуем '
                    '(пароль не отправляется чужому серверу; адрес сервера можно указать вручную)');
                break;
              }
              log.add('Autodiscover: перенаправление на $next');
              url = next;
              continue;
            }
            break;
          }
          if (ewsUrl != null && easUrl != null) return;
        }
      }

      await tryAll(candidates);

      // Метод HTTP-перенаправления (MS-OXDISCO 3.1.5.2): GET по http://
      // autodiscover.<домен> отдаёт 302 на настоящий адрес. Так настроены
      // многие on-premise и хостинги Exchange.
      if (ewsUrl == null || easUrl == null) {
        final loc = await _httpRedirect(client, domain, log, timeout);
        if (loc != null) {
          // Ответ пришёл по http — его мог подменить кто угодно в сети
          // (открытый Wi-Fi). Пароль уходит только серверу в домене почты.
          if (_sameDomain(loc, domain)) {
            await tryAll([loc]);
          } else {
            log.add('Autodiscover: перенаправление на $loc — другой домен, не следуем '
                '(пароль не отправляется чужому серверу; адрес сервера можно указать вручную)');
          }
        }
      }

      log.add('Autodiscover: EWS=${ewsUrl ?? "—"}, EAS=${easUrl ?? "—"}');
      return AutodiscoverResult(ewsUrl: ewsUrl, easUrl: easUrl, log: log);
    } finally {
      if (ownClient) client.close();
    }
  }

  static Future<String?> _httpRedirect(
      http.Client client, String domain, List<String> log, Duration timeout) async {
    final url = 'http://autodiscover.$domain/Autodiscover/Autodiscover.xml';
    try {
      final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
      final resp = await client.send(req).timeout(timeout);
      await resp.stream.drain<void>();
      final loc = resp.headers['location'];
      if ((resp.statusCode == 301 || resp.statusCode == 302) &&
          loc != null &&
          loc.startsWith('https://')) {
        log.add('Autodiscover $url → перенаправление $loc');
        return loc;
      }
      log.add('Autodiscover $url → HTTP ${resp.statusCode}');
    } catch (e) {
      log.add('Autodiscover $url → $e');
    }
    return null;
  }

  /// Адрес https в домене почты (сам домен или его поддомен): только туда
  /// Autodiscover отправляет учётные данные при перенаправлении.
  static bool _sameDomain(String url, String domain) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return false;
    final h = u.host.toLowerCase();
    final d = domain.toLowerCase();
    return h == d || h.endsWith('.$d');
  }

  static Future<({String? value, String? redirectAddr, String? redirectUrl})> _tryPox(
    http.Client client, {
    required String url,
    required String email,
    required String authHeader,
    required String userAgent,
    required String requestNs,
    required String responseSchema,
    required String? Function(XmlDocument) extract,
    required List<String> log,
    required Duration timeout,
  }) async {
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<Autodiscover xmlns="$requestNs">'
        '<Request><EMailAddress>${_xmlEscape(email)}</EMailAddress>'
        '<AcceptableResponseSchema>$responseSchema</AcceptableResponseSchema>'
        '</Request></Autodiscover>';
    try {
      final resp = await client.post(Uri.parse(url), headers: {
        'Authorization': authHeader,
        'Content-Type': 'text/xml; charset=utf-8',
        'User-Agent': userAgent,
      }, body: body).timeout(timeout);
      if (resp.statusCode == 200) {
        final doc = XmlDocument.parse(resp.body);
        // <Action>redirectAddr</Action><RedirectAddr>…</RedirectAddr>
        // <Action>redirectUrl</Action><RedirectUrl>https://…</RedirectUrl>
        final action = doc.findAllElements('Action').firstOrNull?.innerText.trim();
        if (action == 'redirectAddr') {
          final addr = doc.findAllElements('RedirectAddr').firstOrNull?.innerText.trim();
          if (addr != null && addr.contains('@')) return (value: null, redirectAddr: addr, redirectUrl: null);
        }
        if (action == 'redirectUrl') {
          final next = doc.findAllElements('RedirectUrl').firstOrNull?.innerText.trim();
          if (next != null && next.startsWith('https://')) {
            return (value: null, redirectAddr: null, redirectUrl: next);
          }
        }
        final found = extract(doc);
        if (found != null) log.add('Autodiscover $url → найдено: $found');
        return (value: found, redirectAddr: null, redirectUrl: null);
      }
      // POST сетевой клиент сам не перенаправляет: 302 и подобные — здесь.
      const moved = {301, 302, 307, 308};
      final loc = resp.headers['location'];
      if (moved.contains(resp.statusCode) && loc != null && loc.isNotEmpty) {
        final next = Uri.parse(url).resolve(loc).toString();
        log.add('Autodiscover $url → HTTP ${resp.statusCode} на $next');
        if (next.startsWith('https://')) return (value: null, redirectAddr: null, redirectUrl: next);
        return (value: null, redirectAddr: null, redirectUrl: null);
      }
      log.add('Autodiscover $url → HTTP ${resp.statusCode}');
    } catch (e) {
      log.add('Autodiscover $url → $e');
    }
    return (value: null, redirectAddr: null, redirectUrl: null);
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String? _extractEwsUrl(XmlDocument doc) {
    // ТОЛЬКО EwsUrl. Раньше при его отсутствии возвращался ASUrl — но это
    // адрес ActiveSync (Microsoft-Server-ActiveSync), а не конечная точка
    // веб-служб: SOAP-запросы EWS уходили бы не туда и падали с 404/500.
    for (final p in doc.findAllElements('Protocol')) {
      final ews = p.findElements('EwsUrl').firstOrNull?.innerText;
      if (ews != null && ews.isNotEmpty) return ews;
    }
    // Иногда EwsUrl лежит вне Protocol.
    final direct = doc.findAllElements('EwsUrl').firstOrNull?.innerText;
    return (direct != null && direct.isNotEmpty) ? direct : null;
  }


  static String? _extractEasUrl(XmlDocument doc) {
    // MobileSync: <Server><Type>MobileSync</Type><Url>...</Url></Server>
    for (final s in doc.findAllElements('Server')) {
      final type = s.findElements('Type').firstOrNull?.innerText;
      final url = s.findElements('Url').firstOrNull?.innerText;
      if (type == 'MobileSync' && url != null && url.isNotEmpty) return url;
    }
    return doc.findAllElements('Url').firstOrNull?.innerText;
  }

  static String basicAuth(String user, String password) =>
      'Basic ${base64.encode(utf8.encode('$user:$password'))}';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

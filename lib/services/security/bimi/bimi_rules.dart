// lib/services/security/bimi/bimi_rules.dart
// Логотипы отправителей BIMI (1.9.x, просьба владельца 31.10.2026): когда
// письму можно доверить логотип и безопасен ли сам SVG.
//
// Логотип показывается, только если почтовый сервер пользователя написал в
// своём (верхнем) заголовке Authentication-Results «dmarc=pass» для домена из
// From. Заголовки ниже добавлены раньше по пути письма — их мог написать кто
// угодно, в том числе сам отправитель, поэтому они не учитываются. Политику
// DMARC домена (quarantine/reject) и запись BIMI проверяет сервер Ogneliss
// (server/oauth-proxy/bimi.js); SVG приложение проверяет ещё раз тем же
// списком разрешённого, что и сервер.

import 'package:xml/xml.dart';

/// Домен отправителя, если верхний заголовок Authentication-Results
/// подтверждает DMARC для домена из From; иначе null.
///
/// [authResults] — значение верхнего заголовка, как его хранит база (IMAP
/// берёт первый заголовок). ActiveSync склеивает одноимённые заголовки
/// через «; » — тогда учитывается только первый из склеенных.
///
/// [ownServers] — домены серверов ящиков пользователя ([ownMailServerDomains]):
/// заголовок учитывается, только если его поставил один из них (2.0.0, план
/// 08.11.2026, «Authentication-Results — только от своего сервера»). Сервер,
/// который сам заголовок не пишет (часто — Exchange в организации), оставлял
/// верхним чужой — его мог написать сервер отправителя, и подделка получала
/// логотип банка. null — без этой проверки (тесты правил разбора).
String? bimiDmarcDomain(String? authResults, String fromEmail, {Set<String>? ownServers}) {
  final domain = bimiFromDomain(fromEmail);
  if (domain == null) return null;
  final parts = trustedAuthResultParts(authResults, ownServers: ownServers);
  if (parts == null) return null;
  var pass = false;
  for (final p in parts) {
    final m = RegExp(r'^dmarc\s*=\s*([a-z]+)', caseSensitive: false).firstMatch(p);
    if (m == null) continue;
    if (m.group(1)!.toLowerCase() != 'pass') return null;
    // header.from — домен, который проверял сервер: должен совпасть с From.
    final hf = RegExp(r'header\.from\s*=\s*"?([^\s;"]+)', caseSensitive: false).firstMatch(p)?.group(1);
    if (hf != null && hf.toLowerCase().replaceAll(RegExp(r'\.$'), '') != domain) return null;
    pass = true;
  }
  return pass ? domain : null;
}

/// Проверки (resinfo) из верхнего заголовка без комментариев; null —
/// заголовка нет или он не похож на Authentication-Results (RFC 8601).
List<String>? trustedAuthResultParts(String? authResults, {Set<String>? ownServers}) {
  var a = (authResults ?? '').trim();
  if (a.isEmpty || a == 'none') return null;
  // Комментарии в скобках: «dmarc=pass (p=REJECT …)» — политика в
  // комментарии не доверяется, её проверяет сервер.
  for (var i = 0; i < 8 && a.contains('('); i++) {
    a = a.replaceAll(RegExp(r'\([^()]*\)'), ' ');
  }
  final parts = a.split(';').map((s) => s.trim()).toList();
  // Первая часть — authserv-id (имя сервера, без «=»). У запасного
  // Received-SPF и «spf=…» из EWS его нет — это не Authentication-Results.
  if (parts.first.isEmpty || parts.first.contains('=')) return null;
  if (ownServers != null && !isOwnAuthServ(parts.first, ownServers)) return null;
  final out = <String>[];
  for (final p in parts.skip(1)) {
    if (p.isEmpty) continue;
    if (!p.contains('=')) {
      if (p.toLowerCase() == 'none') continue;
      break; // начался следующий склеенный заголовок (его authserv-id)
    }
    out.add(p);
  }
  return out;
}

/// authserv-id (первая часть заголовка, «mx.google.com» или «mx.google.com 1»)
/// — сервер одного из ящиков пользователя: совпадает с доменом из
/// [ownServers] или оканчивается на «.домен».
bool isOwnAuthServ(String authServId, Set<String> ownServers) {
  final id = authServId.trim().split(RegExp(r'\s+')).first.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (id.isEmpty) return false;
  return ownServers.any((d) => id == d || id.endsWith('.$d'));
}

/// Домены серверов ящиков: домен адреса ящика и базовые домены его серверов
/// (IMAP, EWS, ActiveSync), у крупных почтовых служб — и домены, которыми
/// подписаны их заголовки (Gmail — google.com, Яндекс — yandex.net, iCloud —
/// apple.com, Outlook.com — outlook.com).
Set<String> ownMailServerDomains(Iterable<({String email, List<String?> hosts})> accounts) {
  final out = <String>{};
  for (final a in accounts) {
    final at = a.email.lastIndexOf('@');
    final mailDomain = at < 0 ? '' : a.email.substring(at + 1).trim().toLowerCase();
    final bases = <String>{
      if (mailDomain.isNotEmpty) mailDomain,
      for (final h in a.hosts)
        if (_hostOf(h) case final host? when host.contains('.')) _baseDomain(host),
    };
    out.addAll(bases);
    for (final b in bases) {
      out.addAll(_providerAliases[b] ?? const <String>[]);
    }
  }
  out.removeWhere((d) => !d.contains('.'));
  return out;
}

const _providerAliases = <String, List<String>>{
  'gmail.com': ['google.com'],
  'googlemail.com': ['google.com'],
  'yandex.ru': ['yandex.net'],
  'ya.ru': ['yandex.net', 'yandex.ru'],
  'yandex.com': ['yandex.net'],
  'icloud.com': ['apple.com'],
  'me.com': ['apple.com', 'icloud.com'],
  'mac.com': ['apple.com', 'icloud.com'],
  'hotmail.com': ['outlook.com'],
  'live.com': ['outlook.com'],
  'office365.com': ['outlook.com'],
  'bk.ru': ['mail.ru'],
  'inbox.ru': ['mail.ru'],
  'list.ru': ['mail.ru'],
};

/// Узел из адреса сервера: «https://mail.org.ru/EWS/Exchange.asmx» →
/// «mail.org.ru»; «imap.yandex.ru» — как есть.
String? _hostOf(String? s) {
  var v = (s ?? '').trim().toLowerCase();
  if (v.isEmpty) return null;
  final scheme = v.indexOf('://');
  if (scheme >= 0) v = v.substring(scheme + 3);
  v = v.split('/').first.split(':').first;
  return v.isEmpty ? null : v;
}

/// Базовый домен узла: последние две части, у «co.uk», «com.ru» и подобных —
/// три.
String _baseDomain(String host) {
  final l = host.split('.');
  if (l.length <= 2) return host;
  const second = {'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'msk', 'spb'};
  final n = second.contains(l[l.length - 2]) && l.last.length == 2 ? 3 : 2;
  return l.sublist(l.length - n).join('.');
}

/// Домен из адреса: только ASCII-домен (IDN — в punycode), иначе null.
String? bimiFromDomain(String email) {
  final at = email.lastIndexOf('@');
  if (at < 0) return null;
  final d = email.substring(at + 1).trim().toLowerCase().replaceAll(RegExp(r'[>\s]+$'), '').replaceAll(RegExp(r'\.$'), '');
  if (d.length > 253) return null;
  final labels = d.split('.');
  if (labels.length < 2) return null;
  final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  if (!labels.every(label.hasMatch)) return null;
  if (RegExp(r'^\d+$').hasMatch(labels.last)) return null;
  return d;
}

/// Проверка SVG перед отрисовкой: профиль SVG Tiny PS, тот же список
/// разрешённого, что у сервера. Любой элемент или атрибут вне списка —
/// отказ целиком (сервер присылает уже очищенный файл).
class BimiSvgFilter {
  BimiSvgFilter._();

  static const maxBytes = 32 * 1024;
  static const _maxDepth = 64;
  static const _maxElements = 4000;

  static const elements = {
    'svg', 'g', 'defs', 'title', 'desc', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
    'linearGradient', 'radialGradient', 'stop', 'use', 'text', 'tspan', 'solidColor',
  };
  static const attributes = {
    'xmlns', 'xmlns:xlink', 'version', 'baseProfile', 'viewBox', 'width', 'height', 'preserveAspectRatio',
    'id', 'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'fx', 'fy', 'd', 'points',
    'transform', 'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
    'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset',
    'opacity', 'color', 'display', 'visibility', 'offset', 'stop-color', 'stop-opacity', 'gradientUnits',
    'gradientTransform', 'spreadMethod', 'href', 'xlink:href', 'font-family', 'font-size', 'font-weight',
    'font-style', 'text-anchor', 'clip-rule', 'xml:space', 'solid-color', 'solid-opacity', 'vector-effect',
    'style',
  };

  static bool isSafe(String svg) {
    // Предел — в байтах UTF-8, как на сервере.
    if (svg.isEmpty || svg.length > maxBytes || _utf8Length(svg) > maxBytes) return false;
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(svg);
    } catch (_) {
      return false;
    }
    XmlElement? root;
    for (final n in doc.children) {
      if (n is XmlDeclaration || n is XmlComment) continue;
      if (n is XmlText && n.value.trim().isEmpty) continue;
      if (n is XmlElement && root == null) {
        root = n;
        continue;
      }
      return false; // DOCTYPE, инструкции, второй корень, текст вне корня
    }
    if (root == null || root.name.qualified != 'svg') return false;
    var count = 0;
    var drawable = false;
    bool walk(XmlElement e, int depth) {
      if (depth > _maxDepth || ++count > _maxElements) return false;
      final name = e.name.qualified;
      if (!elements.contains(name)) return false;
      if (name == 'svg' && depth > 0) return false;
      if (const {'path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line', 'text', 'use'}.contains(name)) {
        drawable = true;
      }
      for (final a in e.attributes) {
        final an = a.name.qualified;
        if (!attributes.contains(an) || !safeAttrValue(an, a.value)) return false;
      }
      for (final c in e.children) {
        if (c is XmlElement) {
          if (!walk(c, depth + 1)) return false;
        } else if (c is XmlText || c is XmlComment) {
          continue;
        } else {
          return false; // CDATA, инструкции обработки
        }
      }
      return true;
    }

    return walk(root, 0) && drawable;
  }

  /// Значение атрибута: ссылки только внутрь файла (#id, url(#id)), без
  /// схем (javascript:, data:), выражений CSS и обратных косых.
  static bool safeAttrValue(String name, String v) {
    if (v.contains('<') || v.contains(r'\')) return false;
    if (RegExp(r'javascript:|vbscript:|data:|expression\s*\(|@import|behavior\s*:|-moz-binding', caseSensitive: false)
        .hasMatch(v)) {
      return false;
    }
    for (final m in RegExp(r'url\s*\(([^)]*)\)?', caseSensitive: false).allMatches(v)) {
      if (!RegExp(r'''^url\s*\(\s*['"]?#[A-Za-z_][\w.:-]*['"]?\s*\)$''', caseSensitive: false).hasMatch(m.group(0)!)) {
        return false;
      }
    }
    if (name == 'href' || name == 'xlink:href') return RegExp(r'^#[A-Za-z_][\w.:-]*$').hasMatch(v);
    if (name == 'xmlns') return v == 'http://www.w3.org/2000/svg';
    if (name == 'xmlns:xlink') return v == 'http://www.w3.org/1999/xlink';
    return true;
  }

  static int _utf8Length(String s) {
    var n = 0;
    for (final r in s.runes) {
      n += r < 0x80 ? 1 : (r < 0x800 ? 2 : (r < 0x10000 ? 3 : 4));
    }
    return n;
  }
}

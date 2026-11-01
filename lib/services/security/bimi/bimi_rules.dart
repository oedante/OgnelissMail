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
String? bimiDmarcDomain(String? authResults, String fromEmail) {
  final domain = bimiFromDomain(fromEmail);
  if (domain == null) return null;
  final parts = trustedAuthResultParts(authResults);
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
List<String>? trustedAuthResultParts(String? authResults) {
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

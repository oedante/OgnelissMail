// lib/services/documents/text_doc_reader.dart
// Текстовые файлы .txt и Markdown (.md) в предпросмотре вложений (1.14.0,
// просьба владельца 05.11.2026: «можно добавить предпросмотр .txt и .md»).
//
// Раньше .txt и .md на Android и компьютере показывались сырым текстом
// моноширинным шрифтом и только в UTF-8 (файл в Windows-1251 — «кракозябры»),
// а на iPhone и iPad — «Просмотром» iOS, который Markdown не оформляет.
// Теперь:
//  · кодировка определяется по содержимому: метка BOM, UTF-16, UTF-8, а из
//    однобайтовых — Windows-1251, KOI8-R и DOS (866) по тому, в какой из них
//    получается связный русский текст; иначе Windows-1252;
//  · .txt — читаемым шрифтом с абзацами и ссылками; таблицы из пробелов и
//    псевдографика — моноширинным, чтобы не съехали столбцы;
//  · .md — оформленным документом (заголовки, списки, таблицы, код, цитаты)
//    по CommonMark и GitHub Flavored Markdown (пакет markdown, BSD-3-Clause).
// HTML дальше идёт тем же путём, что DOCX: санитайзер, окно письма без сети
// и JavaScript. Картинки из интернета не грузятся — вместо них ссылка.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;

import '../../core/utils/charset_handler.dart';
import 'csv_reader.dart';
import 'office_document.dart';

class TextDocReader {
  TextDocReader._();

  static const _plainExt = {'txt', 'text'};
  static const _mdExt = {'md', 'markdown', 'mdown', 'mkd', 'mkdn', 'mdwn'};

  /// Сколько байт файла показывается (дальше — «показано только начало»).
  static const maxBytes = 1024 * 1024;

  static const _timeout = Duration(seconds: 30);

  static bool isMarkdown(String fileName, {String? mimeType}) {
    if (_mdExt.contains(OfficeFormats.extOf(fileName))) return true;
    final mt = (mimeType ?? '').toLowerCase().split(';').first.trim();
    return OfficeFormats.extOf(fileName).isEmpty && (mt == 'text/markdown' || mt == 'text/x-markdown');
  }

  /// Файл показывается этим читателем (по расширению, Markdown — и по типу).
  static bool handles(String fileName, {String? mimeType}) =>
      _plainExt.contains(OfficeFormats.extOf(fileName)) || isMarkdown(fileName, mimeType: mimeType);

  /// Прочитать файл (начало до [maxBytes]) и разобрать в изоляте.
  static Future<OfficeTextDoc> readFile(String path, String fileName, {String? mimeType, String lang = 'en'}) async {
    final f = File(path);
    final len = await f.length();
    final truncated = len > maxBytes;
    final bytes = truncated
        ? Uint8List.fromList(await f.openRead(0, maxBytes).fold<List<int>>(<int>[], (a, b) => a..addAll(b)))
        : await f.readAsBytes();
    final markdown = isMarkdown(fileName, mimeType: mimeType);
    return Isolate.run(() => read(bytes, markdown: markdown, lang: lang, truncated: truncated)).timeout(_timeout);
  }

  /// Документ из байтов файла.
  static OfficeTextDoc read(Uint8List bytes, {required bool markdown, String lang = 'en', bool truncated = false}) {
    var text = decode(bytes, lang: lang, truncated: truncated);
    if (text.startsWith('﻿')) text = text.substring(1);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\u0000', '');
    if (text.trim().isEmpty) return OfficeTextDoc('', truncated: truncated);
    return OfficeTextDoc(markdown ? markdownHtml(text) : plainHtml(text), truncated: truncated);
  }

  // ─────────────────────────── кодировка ───────────────────────────

  /// Текст файла: метка BOM, UTF-16, UTF-8 — как у CSV; однобайтовый —
  /// русский в Windows-1251, KOI8-R или DOS 866, если в одной из них
  /// получается связный текст; иначе Windows-1252.
  static String decode(Uint8List b, {String lang = 'en', bool truncated = false}) {
    if (_unicode(b, truncated)) return CsvReader.decode(b, lang: lang, truncated: truncated);
    // Русские кодировки уже проверены по содержимому — язык приложения
    // больше не подсказка (немецкое «Grüße» при русском интерфейсе — 1252).
    return _bestCyrillic(b) ?? CsvReader.decode(b, truncated: truncated);
  }

  static bool _unicode(Uint8List b, bool truncated) {
    if ((b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) ||
        (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF)))) {
      return true;
    }
    if (b.length >= 4 && b[1] == 0 && b[3] == 0 && b[0] != 0) return true;
    var end = b.length;
    if (truncated) {
      var k = end - 1;
      var back = 0;
      while (k >= 0 && back < 3 && (b[k] & 0xC0) == 0x80) {
        k--;
        back++;
      }
      if (k >= 0 && b[k] >= 0xC0) end = k;
    }
    try {
      utf8.decode(Uint8List.sublistView(b, 0, end));
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Лучшая из русских однобайтовых кодировок или null — не русский текст.
  static String? _bestCyrillic(Uint8List b) {
    final sample = b.length > 64 * 1024 ? Uint8List.sublistView(b, 0, 64 * 1024) : b;
    var high = 0;
    for (final x in sample) {
      if (x >= 0x80) high++;
    }
    if (high == 0) return null;
    String? best;
    var bestScore = 0;
    var bestCp = '';
    for (final cp in const ['windows-1251', 'koi8-r', 'cp866']) {
      final s = _decodeCp(sample, cp);
      final score = cyrillicScore(s);
      if (score > bestScore) {
        bestScore = score;
        best = s;
        bestCp = cp;
      }
    }
    // Связного русского текста мало (несколько букв среди латиницы) — не
    // русский: «Grüße» в 1251 даёт «GrьЯe», а это не повод.
    if (best == null || bestScore < high) return null;
    return identical(sample, b) ? best : _decodeCp(b, bestCp);
  }

  static String _decodeCp(Uint8List b, String cp) =>
      cp == 'cp866' ? String.fromCharCodes([for (final x in b) x < 0x80 ? x : _cp866[x - 0x80]]) : CharsetHandler.decode(b, cp);

  /// Насколько [s] похож на русский текст: строчные буквы внутри слов —
  /// плюс; заглавная посреди слова, буква вплотную к латинице, служебные
  /// знаки и псевдографика из верхней половины таблицы — минус. В чужой
  /// кодировке русский текст превращается именно в такое.
  static int cyrillicScore(String s) {
    var score = 0;
    var prev = 0; // 0 — не буква, 1 — русская буква, 2 — латинская
    for (final r in s.runes) {
      final lower = (r >= 0x430 && r <= 0x44F) || r == 0x451;
      final upper = (r >= 0x410 && r <= 0x42F) || r == 0x401;
      final latin = (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
      if (lower || upper) {
        if (prev == 2) {
          score -= 3;
        } else if (upper) {
          score += prev == 1 ? -3 : 1;
        } else {
          score += 2;
        }
        prev = 1;
      } else if (latin) {
        if (prev == 1) score -= 3;
        prev = 2;
      } else {
        // Знаки, которые дают байты русских букв в чужой таблице: «‚„…†‡€‰‹›»,
        // «Ђ Ѓ Љ …», «ў Ј ¤ Ґ ¦ §», псевдографика DOS.
        if ((r >= 0x2010 && r <= 0x203A && r != 0x2014 && r != 0x2013 && r != 0x2026) ||
            (r >= 0x402 && r <= 0x40F) ||
            (r >= 0x452 && r <= 0x45F) ||
            (r >= 0x2500 && r <= 0x25A0) ||
            (r >= 0xA4 && r <= 0xA7) ||
            r == 0x20AC) {
          score -= 2;
        }
        prev = 0;
      }
    }
    return score;
  }

  /// DOS 866: 0x80–0xFF.
  static const _cp866 = [
    // 0x80–0xAF: А–Я, а–п
    0x410, 0x411, 0x412, 0x413, 0x414, 0x415, 0x416, 0x417, 0x418, 0x419, 0x41A, 0x41B, 0x41C, 0x41D, 0x41E, 0x41F, //
    0x420, 0x421, 0x422, 0x423, 0x424, 0x425, 0x426, 0x427, 0x428, 0x429, 0x42A, 0x42B, 0x42C, 0x42D, 0x42E, 0x42F,
    0x430, 0x431, 0x432, 0x433, 0x434, 0x435, 0x436, 0x437, 0x438, 0x439, 0x43A, 0x43B, 0x43C, 0x43D, 0x43E, 0x43F,
    // 0xB0–0xDF: псевдографика
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C,
    0x255B, 0x2510, 0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566,
    0x2560, 0x2550, 0x256C, 0x2567, 0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518,
    0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
    // 0xE0–0xEF: р–я
    0x440, 0x441, 0x442, 0x443, 0x444, 0x445, 0x446, 0x447, 0x448, 0x449, 0x44A, 0x44B, 0x44C, 0x44D, 0x44E, 0x44F,
    // 0xF0–0xFF
    0x401, 0x451, 0x404, 0x454, 0x407, 0x457, 0x40E, 0x45E, 0xB0, 0x2219, 0xB7, 0x221A, 0x2116, 0xA4, 0x25A0, 0xA0,
  ];

  // ─────────────────────────── простой текст ───────────────────────────

  /// Простой текст: абзацы по пустым строкам, переносы строк и отступы
  /// сохраняются, адреса http(s) — ссылками. Таблица из пробелов или
  /// псевдографика — моноширинным блоком.
  static String plainHtml(String text) {
    if (looksTabular(text)) return '<pre>${_linkify(_esc(text.trimRight()))}</pre>';
    final out = StringBuffer();
    for (final para in text.split(RegExp(r'\n[ \t]*\n'))) {
      final lines = para.split('\n');
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines.removeLast();
      }
      if (lines.isEmpty) continue;
      out.write('<p>');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) out.write('<br>');
        out.write(_indent(_linkify(_esc(lines[i].trimRight()))));
      }
      out.write('</p>');
    }
    return out.toString();
  }

  /// Столбцы выровнены пробелами или табуляцией, есть псевдографика —
  /// в пропорциональном шрифте такая разметка развалится.
  static bool looksTabular(String text) {
    var lines = 0;
    var aligned = 0;
    for (final l in text.split('\n').take(400)) {
      final t = l.trimRight();
      if (t.trim().isEmpty) continue;
      lines++;
      if (RegExp(r'[─-╿]').hasMatch(t) ||
          RegExp(r'^\s*[+|][-=+|]{3,}').hasMatch(t) ||
          RegExp(r'\S(\t| {3,})\S').hasMatch(t)) {
        aligned++;
      }
    }
    return lines > 0 && aligned * 5 >= lines && aligned >= 2;
  }

  static String _indent(String line) {
    var i = 0;
    final b = StringBuffer();
    while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
      b.write(line[i] == '\t' ? '&nbsp;&nbsp;&nbsp;&nbsp;' : '&nbsp;');
      i++;
    }
    return '$b${line.substring(i)}';
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// Адреса http(s) — ссылками (точка и скобка в конце — знаки предложения).
  static String _linkify(String escaped) => escaped.replaceAllMapped(_url, (m) {
        var u = m[0]!;
        var tail = '';
        while (u.isNotEmpty && '.,;:!?)]}\''.contains(u[u.length - 1])) {
          tail = u[u.length - 1] + tail;
          u = u.substring(0, u.length - 1);
        }
        if (u.endsWith('&amp')) {
          // «…&amp;» разрезали на «;» — вернуть.
          u = '$u;';
          tail = tail.startsWith(';') ? tail.substring(1) : tail;
        }
        return '<a href="$u">$u</a>$tail';
      });

  // ─────────────────────────── Markdown ───────────────────────────

  /// Markdown → HTML: CommonMark и расширения GitHub (таблицы, зачёркивание,
  /// списки задач, автоссылки, сноски). Флажки задач — знаками ☐ и ☑
  /// (санитайзер убирает поля ввода), картинки из интернета — ссылкой.
  static String markdownHtml(String text) {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: true);
    final nodes = doc.parse(text);
    _rewrite(nodes);
    return md.renderToHtml(nodes);
  }

  static void _rewrite(List<md.Node> nodes) {
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n is! md.Element) continue;
      if (n.tag == 'input' && n.attributes['type'] == 'checkbox') {
        nodes[i] = md.Text(n.attributes.containsKey('checked') ? '☑ ' : '☐ ');
        continue;
      }
      if (n.tag == 'img') {
        final src = (n.attributes['src'] ?? '').trim();
        final lower = src.toLowerCase();
        if (!lower.startsWith('data:image/')) {
          final alt = (n.attributes['alt'] ?? '').trim();
          final label = '🖼 ${alt.isEmpty ? src : alt}';
          nodes[i] = lower.startsWith('http://') || lower.startsWith('https://')
              ? (md.Element('a', [md.Text(_esc(label))])..attributes['href'] = src)
              : md.Text(_esc(label));
          continue;
        }
      }
      final kids = n.children;
      if (kids != null) _rewrite(kids);
    }
  }
}

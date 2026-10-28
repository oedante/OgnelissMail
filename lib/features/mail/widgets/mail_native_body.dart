// lib/features/mail/widgets/mail_native_body.dart
// Простые письма без WebView (1.5.9, этап 3 разбора задержки открытия).
//
// Большая часть рабочей почты — текст, ссылки, выделение, списки, цитаты
// и картинки подписи. Окно браузера для такого письма — самая дорогая часть
// открытия (создание окна, загрузка, вёрстка в отдельном процессе, замер
// высоты). Здесь такие письма рисуются виджетами Flutter — в том же кадре,
// что и шапка: без заглушки, замеров и ожидания.
//
// Как устроено:
//  1. [buildNativeMail] — в изоляте, по уже очищенному HTML (санитайзер и
//     блокировщик трекеров отработали раньше): один проход по DOM решает,
//     простое ли письмо, и строит список блоков (абзац, пункт списка,
//     цитата, линия) с фрагментами текста и их оформлением. Всё, что
//     виджетами не повторить точно (таблицы, внешние картинки, плавающие и
//     позиционированные блоки, фоновые картинки, VML, медиа), — null:
//     письмо показывается в WebView, как раньше.
//  2. [MailNativeBody] — Text.rich по блокам, выделение текста (SelectionArea),
//     ссылки — через тот же onLink (проверка домена), встроенные картинки —
//     из той же карты cid → data URI, что у WebView.
//
// Цвета письма в тёмной теме: цвет текста, который плохо читается на фоне
// страницы, заменяется цветом темы; выделенный маркером текст — чёрным или
// белым по яркости маркера. Блоки <style> письма не применяются (как у
// большинства мобильных клиентов для простых писем); письма, где без них
// не обойтись (скрытый текст классами, @media), уходят в WebView.
//
// Выключатель — «Настройки → Почта → Открытие писем → Простые письма без браузера».
// Кнопка «Как в браузере» в письме убрана в 1.5.10: по отзывам тестировщиков
// показ виджетами точнее и приятнее («в браузере — как рисунок»).
//
// Ссылки и адреса почты, написанные обычным текстом, — нажимаемые
// (core/utils/linkify.dart, 1.5.10).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/theme/mail_page_color.dart';
import '../../../core/utils/linkify.dart';
import '../../../core/utils/symbol_fonts.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/pinch_zoom.dart';
import 'span_table.dart';

// ───────────────────────── модель (передаётся из изолята) ─────────────────────────

/// Фрагмент текста с оформлением или встроенная картинка.
class NSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool mono;

  /// Цвет текста и маркера (ARGB) — как в письме.
  final int? color;
  final int? background;

  /// Размер относительно обычного текста письма (1 — обычный).
  final double size;
  final String? href;

  /// Картинка: `cid:…` (встроенная) или `data:` URI; ширина и высота — из
  /// разметки письма, если заданы.
  final String? image;
  final double? imageWidth;
  final double? imageHeight;

  const NSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.color,
    this.background,
    this.size = 1,
    this.href,
    this.image,
    this.imageWidth,
    this.imageHeight,
  });
}

enum NBlockKind { text, hr, table }

/// Ячейка простой таблицы: свои блоки, фон и доля ширины; объединение
/// строк и колонок (1.5.11) и видимые стороны рамки ([kBorderTop] …).
class NCell {
  final List<NBlock> blocks;
  final int? background;
  final double flex;
  final int rowSpan;
  final int colSpan;
  final int sides;

  /// 0 — сверху, 1 — по центру, 2 — снизу.
  final int valign;
  const NCell(this.blocks,
      {this.background, this.flex = 1, this.rowSpan = 1, this.colSpan = 1, this.sides = 0, this.valign = 0});
}

/// Блок письма: абзац (или пункт списка) либо горизонтальная линия.
class NBlock {
  final NBlockKind kind;
  final List<NSpan> spans;

  /// Уровень цитаты (blockquote) и списка.
  final int quote;
  final int list;

  /// Маркер пункта списка («•», «1.»), null — не пункт.
  final String? bullet;

  /// 0 — влево, 1 — по центру, 2 — вправо.
  final int align;

  /// Отступ после блока, в долях строки.
  final double after;
  final bool pre;

  /// Простая таблица (подпись в две колонки, небольшая таблица данных):
  /// строки ячеек; [borders] — видимые линии таблицы ([kBorderTop] …).
  final List<List<NCell>>? table;
  final int borders;
  bool get border => borders != 0;

  const NBlock({
    this.table,
    this.borders = 0,
    this.kind = NBlockKind.text,
    this.spans = const [],
    this.quote = 0,
    this.list = 0,
    this.bullet,
    this.align = 0,
    this.after = 0,
    this.pre = false,
  });

  bool get isBlank =>
      kind == NBlockKind.text &&
      spans.every((s) => s.image == null && s.text.replaceAll(' ', ' ').trim().isEmpty);
}

class NativeMail {
  final List<NBlock> blocks;
  const NativeMail(this.blocks);
}

// ───────────────────────── построение (в изоляте) ─────────────────────────

const _complexTags = {
  'svg', 'video', 'audio', 'iframe', 'object', 'embed', 'form', 'input', 'button', 'select',
  'textarea', 'canvas', 'map', 'math', 'picture', 'marquee', 'frameset', 'frame', 'applet',
};

/// Оформление, которое виджетами точно не повторить.
final _complexStyle = RegExp(
    r'position\s*:\s*(absolute|fixed)|float\s*:\s*(left|right)|display\s*:\s*(flex|grid|inline-block|table)'
    r'|background-image|background\s*:[^;]*url\(|transform\s*:|columns?\s*:|column-count'
    r'|(?<![-\w])(min-)?width\s*:\s*([6-9]\d\d|\d{4,})px',
    caseSensitive: false);

final _ws = RegExp(r'[ \t\r\n\f]+');

/// Простое письмо — блоки для показа виджетами; сложное — null (WebView).
/// [html] — уже очищенный HTML (санитайзер, блокировщик трекеров).
NativeMail? buildNativeMail(String html) => buildNativeMailWhy(html).mail;

/// То же при разрешённых картинках из интернета (1.5.11): картинки
/// http(s) — не повод уходить в браузер, приложение загрузит их само.
NativeMail? buildNativeMailRemote(String html) => buildNativeMailWhy(html, remoteImages: true).mail;

/// То же и причина, по которой письмо уходит в WebView (1.5.10) — для замера
/// открытия в журнале: «в браузере: объединённые ячейки», «…: картинка из
/// интернета». По ним видно, что ещё стоит научиться рисовать без браузера.
({NativeMail? mail, String? why}) buildNativeMailWhy(String html, {bool remoteImages = false}) {
  ({NativeMail? mail, String? why}) no(String why) => (mail: null, why: why);
  if (html.length > 400 * 1024) return no('больше 400 КБ');
  final doc = html_parser.parse(html);
  final body = doc.body;
  if (body == null) return no('нет тела');

  // <style> письма не применяются: если без них текст изменится (скрытые
  // классами блоки, адаптивная вёрстка) — в WebView.
  for (final st in doc.querySelectorAll('style')) {
    final t = st.text.toLowerCase();
    if (t.contains('@media')) return no('стили @media');
    if (RegExp(r'display\s*:\s*none').hasMatch(t)) return no('скрытые стилем блоки');
  }

  var count = 0;
  var tables = 0;
  for (final e in body.querySelectorAll('*')) {
    if (++count > 5000) return no('больше 5000 элементов');
    final tag = (e.localName ?? '').toLowerCase();
    if (_complexTags.contains(tag)) return no('<$tag>');
    // Таблица (1.5.9): до 6 колонок и 60 строк. Вложенность (1.5.10) — один
    // уровень: подпись Outlook «таблица в ячейке таблицы» рисуется
    // приложением; глубже, и больше восьми таблиц в письме — вёрстка
    // таблицами (рассылки), в WebView. Объединённые ячейки (1.5.11) —
    // можно: колонки считаются с учётом объединения.
    if (tag == 'table') {
      if (++tables > 8) return no('таблиц больше 8');
      var depth = 0;
      for (var p = e.parent; p != null; p = p.parent) {
        if (p.localName == 'table') depth++;
      }
      if (depth > 1) return no('таблица в таблице в таблице');
      final rows = _rowsOf(e);
      if (rows.isEmpty) return no('таблица без строк');
      if (rows.length > 60) return no('таблица: ${rows.length} строк');
      final cols = _gridColumns(rows);
      if (cols > 6) return no('таблица: $cols колонок');
    }
    // VML и прочие Office-элементы, кроме пустых абзацев Word (<o:p>).
    if (tag.contains(':') && tag != 'o:p') return no('<$tag>');
    if (e.attributes.containsKey('background')) return no('фоновая картинка');
    final st = e.attributes['style'] ?? '';
    if (st.isNotEmpty) {
      final m = _complexStyle.firstMatch(st);
      if (m != null) return no('стиль «${m.group(0)!.replaceAll(RegExp(r'\s+'), '')}»');
    }
    if (tag == 'img') {
      final src = (e.attributes['src'] ?? '').trim().toLowerCase();
      final web = remoteImages && (src.startsWith('https://') || src.startsWith('http://'));
      if (!src.startsWith('cid:') && !src.startsWith('data:image/') && !web) return no('картинка из интернета');
    }
    // Фон у блока (не у фрагмента текста): вёрстка карточками — в WebView.
    if (_blockTags.contains(tag) || tag == 'body') {
      final bg = _parseColor(e.attributes['bgcolor']) ?? _styleColor(st, 'background-color') ?? _styleColor(st, 'background');
      if (bg != null && !_isWhiteish(bg)) return no('фон у блока <$tag>');
    }
  }

  if (SymbolFonts.mayContain(html)) SymbolFonts.mapDom(body);

  final b = _Builder();
  b.walk(body, const _Ctx());
  b.flush();
  final blocks = b.blocks;
  // Пустые строки в начале и в конце (Outlook: <p>&nbsp;</p>) — как у WebView.
  while (blocks.isNotEmpty && blocks.first.isBlank) {
    blocks.removeAt(0);
  }
  while (blocks.isNotEmpty && blocks.last.isBlank) {
    blocks.removeLast();
  }
  if (blocks.isEmpty) return no('пустое');
  return (mail: NativeMail(blocks), why: null);
}

const kBorderTop = 1, kBorderRight = 2, kBorderBottom = 4, kBorderLeft = 8, kBorderInsideH = 16, kBorderInsideV = 32;

final _borderDecl = RegExp(r'^border(-top|-right|-bottom|-left|-style|-width|-color)?$');
final _borderLine = RegExp(r'\b(solid|dotted|dashed|double|groove|ridge|inset|outset)\b');
final _zeroWidth = RegExp(r'(^|\s)0(\.0+)?(pt|px|cm|mm|in|em)?(\s|$)');
final _invisibleColor = RegExp(r'\b(white|transparent)\b|#fff(fff)?\b|#fefefe\b|rgba?\(\s*255\s*,\s*255\s*,\s*255');

/// Видна ли линия с таким значением (`solid #D9D9D9 1.0pt`).
bool _lineVisible(String v) =>
    _borderLine.hasMatch(v) && !v.contains('none') && !v.contains('hidden') && !_zeroWidth.hasMatch(v) &&
    !_invisibleColor.hasMatch(v);

/// Видимые стороны рамки по стилю [st] (верх, право, низ, лево); [base] —
/// до стиля (атрибут border таблицы). Объявления — по порядку, как в CSS:
/// «border:none; border-right:solid …» — только правая. mso-border-* —
/// подсказки Word самому себе, браузер их не рисует.
List<bool> _borderSides(String st, List<bool> base) {
  final sides = List<bool>.of(base);
  if (!st.contains('border')) return sides;
  for (final d in st.split(';')) {
    final i = d.indexOf(':');
    if (i < 0) continue;
    final name = d.substring(0, i).trim();
    final v = d.substring(i + 1).trim();
    final m = _borderDecl.firstMatch(name);
    if (m == null) continue;
    switch (m.group(1)) {
      case null:
        sides.fillRange(0, 4, _lineVisible(v));
      case '-top':
        sides[0] = _lineVisible(v);
      case '-right':
        sides[1] = _lineVisible(v);
      case '-bottom':
        sides[2] = _lineVisible(v);
      case '-left':
        sides[3] = _lineVisible(v);
      case '-style':
        if (v.contains('none') || v.contains('hidden')) sides.fillRange(0, 4, false);
      case '-width':
        if (_zeroWidth.hasMatch(v)) sides.fillRange(0, 4, false);
      case '-color':
        if (_invisibleColor.hasMatch(v)) sides.fillRange(0, 4, false);
    }
  }
  return sides;
}

/// Число колонок сетки таблицы с учётом объединённых ячеек.
int _gridColumns(List<dom.Element> rows) {
  final busy = <int, Set<int>>{};
  var cols = 0;
  for (var r = 0; r < rows.length; r++) {
    var c = 0;
    for (final td in rows[r].children.where((x) => x.localName == 'td' || x.localName == 'th')) {
      while (busy[r]?.contains(c) ?? false) {
        c++;
      }
      final rs = (int.tryParse(td.attributes['rowspan'] ?? '1') ?? 1).clamp(1, 60);
      final cs = (int.tryParse(td.attributes['colspan'] ?? '1') ?? 1).clamp(1, 20);
      for (var i = 0; i < rs; i++) {
        for (var j = 0; j < cs; j++) {
          (busy[r + i] ??= <int>{}).add(c + j);
        }
      }
      c += cs;
      if (c > cols) cols = c;
    }
  }
  return cols;
}

/// Строки самой таблицы — без строк вложенных таблиц.
List<dom.Element> _rowsOf(dom.Element table) {
  final out = <dom.Element>[];
  for (final c in table.children) {
    final t = c.localName;
    if (t == 'tr') {
      out.add(c);
    } else if (t == 'thead' || t == 'tbody' || t == 'tfoot') {
      out.addAll(c.children.where((r) => r.localName == 'tr'));
    }
  }
  return out;
}

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'li', 'pre', 'center',
  'section', 'article', 'header', 'footer', 'address', 'dl', 'dt', 'dd', 'main', 'aside', 'nav', 'figure',
  'figcaption',
};

class _Ctx {
  final bool bold, italic, underline, strike, mono, pre;
  final int? color, background;
  final double size;
  final String? href;
  final int quote, list, align;
  const _Ctx({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.pre = false,
    this.color,
    this.background,
    this.size = 1,
    this.href,
    this.quote = 0,
    this.list = 0,
    this.align = 0,
  });

  _Ctx copy({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? mono,
    bool? pre,
    int? color,
    int? background,
    double? size,
    String? href,
    int? quote,
    int? list,
    int? align,
  }) =>
      _Ctx(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        mono: mono ?? this.mono,
        pre: pre ?? this.pre,
        color: color ?? this.color,
        background: background ?? this.background,
        size: size ?? this.size,
        href: href ?? this.href,
        quote: quote ?? this.quote,
        list: list ?? this.list,
        align: align ?? this.align,
      );
}

class _Builder {
  final List<NBlock> blocks = [];
  List<NSpan> _spans = [];
  _Ctx _blockCtx = const _Ctx();
  String? _bullet;
  double _after = 0;

  /// Последний добавленный символ — пробел (схлопывание пробелов HTML).
  bool _space = true;

  void _add(NSpan s) {
    _spans.add(s);
  }

  void flush() {
    final spans = _spans;
    // Хвостовой пробел абзаца.
    if (spans.isNotEmpty && spans.last.image == null && !_blockCtx.pre) {
      final last = spans.last;
      final t = last.text.replaceFirst(RegExp(r' +$'), '');
      spans[spans.length - 1] = _withText(last, t);
    }
    final blank = spans.every((s) => s.image == null && s.text.replaceAll(' ', ' ').trim().isEmpty);
    if (spans.isNotEmpty || _bullet != null) {
      // Подряд не больше двух пустых строк (Outlook ставит их пачками).
      final twoBlank = blank &&
          blocks.length >= 2 &&
          blocks[blocks.length - 1].isBlank &&
          blocks[blocks.length - 2].isBlank;
      if (!twoBlank) {
        blocks.add(NBlock(
          spans: blank && _bullet == null ? const [NSpan('')] : List.unmodifiable(spans),
          quote: _blockCtx.quote,
          list: _blockCtx.list,
          bullet: _bullet,
          align: _blockCtx.align,
          after: _after,
          pre: _blockCtx.pre,
        ));
      }
    }
    _spans = [];
    _bullet = null;
    _after = 0;
    _space = true;
  }

  void _startBlock(_Ctx c, {String? bullet, double after = 0}) {
    flush();
    _blockCtx = c;
    _bullet = bullet;
    _after = after;
  }

  void _hr(_Ctx c) {
    flush();
    blocks.add(NBlock(kind: NBlockKind.hr, quote: c.quote));
  }

  void _text(String raw, _Ctx c) {
    var t = raw;
    if (!c.pre) {
      t = t.replaceAll(_ws, ' ');
      if (_space && t.startsWith(' ')) t = t.substring(1);
      if (t.isEmpty) return;
      _space = t.endsWith(' ');
    }
    // Ссылки и адреса почты обычным текстом (1.5.10) — нажимаемые.
    final found = c.href == null ? Linkify.find(t) : const <LinkMatch>[];
    if (found.isEmpty) {
      _add(_span(t, c, c.href));
      return;
    }
    var at = 0;
    for (final m in found) {
      if (m.start > at) _add(_span(t.substring(at, m.start), c, null));
      _add(_span(t.substring(m.start, m.end), c, m.href));
      at = m.end;
    }
    if (at < t.length) _add(_span(t.substring(at), c, null));
  }

  static NSpan _span(String t, _Ctx c, String? href) => NSpan(t,
      bold: c.bold,
      italic: c.italic,
      underline: c.underline || href != null,
      strike: c.strike,
      mono: c.mono || c.pre,
      color: c.color,
      background: c.background,
      size: c.size,
      href: href);

  void walk(dom.Node node, _Ctx c) {
    for (final n in node.nodes) {
      if (n is dom.Text) {
        _text(n.text, c);
      } else if (n is dom.Element) {
        _element(n, c);
      }
    }
  }

  void _element(dom.Element e, _Ctx c) {
    final tag = (e.localName ?? '').toLowerCase();
    if (tag == 'style' || tag == 'script' || tag == 'head' || tag == 'title' || tag == 'meta') return;
    final st = (e.attributes['style'] ?? '').toLowerCase();
    if (e.attributes.containsKey('hidden') || RegExp(r'display\s*:\s*none').hasMatch(st)) return;

    var x = _inline(e, tag, st, c);

    switch (tag) {
      case 'br':
        _add(NSpan('\n',
            bold: x.bold, size: x.size, color: x.color, background: x.background, mono: x.mono || x.pre));
        _space = true;
        return;
      case 'img':
        final src = (e.attributes['src'] ?? '').trim();
        _add(NSpan('',
            image: src,
            imageWidth: _dim(e.attributes['width'], st, 'width'),
            imageHeight: _dim(e.attributes['height'], st, 'height')));
        _space = false;
        return;
      case 'hr':
        _hr(x);
        return;
    }

    if (tag == 'table') {
      _table(e, x);
      return;
    }

    if (!_blockTags.contains(tag)) {
      // Строчный элемент: оформление — детям.
      walk(e, x);
      return;
    }

    // ── Блок ──
    final align = _alignOf(e, st);
    if (align != null) x = x.copy(align: align);
    // Шапка цитаты Outlook («От: … Отправлено: …»): линия сверху.
    if (RegExp(r'border-top\s*:\s*solid').hasMatch(st)) _hr(x);

    switch (tag) {
      case 'blockquote':
        x = x.copy(quote: c.quote + 1);
        _startBlock(x);
        walk(e, x);
        flush();
        _blockCtx = c;
        return;
      case 'ul':
      case 'ol':
        final inner = x.copy(list: c.list + 1);
        flush();
        var i = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        for (final li in e.children) {
          if ((li.localName ?? '') != 'li') {
            _element(li, inner);
            continue;
          }
          final lst = (li.attributes['style'] ?? '').toLowerCase();
          if (RegExp(r'display\s*:\s*none').hasMatch(lst)) continue;
          _startBlock(inner, bullet: tag == 'ol' ? '$i.' : '•');
          walk(li, _inline(li, 'li', lst, inner));
          flush();
          i++;
        }
        _blockCtx = c;
        return;
      case 'pre':
        x = x.copy(pre: true, mono: true);
        _startBlock(x, after: 0.4);
        walk(e, x);
        flush();
        _blockCtx = c;
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final k = const {'h1': 1.6, 'h2': 1.4, 'h3': 1.2, 'h4': 1.1, 'h5': 1.0, 'h6': 0.9}[tag]!;
        x = x.copy(bold: true, size: (x.size == 1 ? k : x.size));
        _startBlock(x, after: 0.3);
        walk(e, x);
        flush();
        _blockCtx = c;
        return;
      case 'p':
        // Абзац Word (MsoNormal) — без отступа (как margin:0 в его стилях),
        // обычный — 0,4 строки (как в документе WebView).
        final mso = (e.attributes['class'] ?? '').toLowerCase().contains('mso');
        _startBlock(x, after: mso ? 0 : 0.4);
        walk(e, x);
        flush();
        _blockCtx = c;
        return;
      default:
        _startBlock(x);
        walk(e, x);
        flush();
        // Продолжение текста после блока — новый абзац с прежним оформлением.
        _blockCtx = c;
    }
  }

  /// Простая таблица: каждая ячейка — свои блоки (тот же разбор).
  void _table(dom.Element e, _Ctx c) {
    flush();
    final rows = <List<NCell>>[];
    // Рамки (1.5.10): как в браузере — по стилям ячеек. Атрибут border у
    // таблицы рисует рамки ячеек, только пока стиль ячейки их не отменил:
    // Word «Сетка таблицы» без границ — это border=1 и у каждой ячейки
    // «border:none» (таблица только для выравнивания; раньше рисовалась с
    // рамками). Белые и прозрачные линии, нулевая толщина, служебные
    // mso-border-* — не рамки. Стороны собираются в линии таблицы: левая
    // граница первой колонки — левый край, правая у внутренних — линия
    // между колонками и т. д.
    final attrBorder = (int.tryParse(e.attributes['border'] ?? '0') ?? 0) > 0;
    final tableSides = _borderSides((e.attributes['style'] ?? '').toLowerCase(), const [false, false, false, false]);
    final cellSides = <List<List<bool>>>[];
    for (final tr in _rowsOf(e)) {
      final cells = <NCell>[];
      final sidesRow = <List<bool>>[];
      for (final td in tr.children) {
        final tag = (td.localName ?? '').toLowerCase();
        if (tag != 'td' && tag != 'th') continue;
        final st = (td.attributes['style'] ?? '').toLowerCase();
        if (RegExp(r'display\s*:\s*none').hasMatch(st)) continue;
        final sd = _borderSides(st, List<bool>.filled(4, attrBorder));
        sidesRow.add(sd);
        final bg = _parseColor(td.attributes['bgcolor']) ?? _styleColor(st, 'background-color') ?? _styleColor(st, 'background');
        final w = _dim(td.attributes['width'], st, 'width');
        final sub = _Builder();
        var cx = _Ctx(quote: 0, align: _alignOf(td, st) ?? 0);
        if (tag == 'th') cx = cx.copy(bold: true);
        sub._blockCtx = cx;
        sub.walk(td, sub._inline(td, tag, st, cx));
        sub.flush();
        final cb = sub.blocks;
        while (cb.isNotEmpty && cb.first.isBlank) {
          cb.removeAt(0);
        }
        while (cb.isNotEmpty && cb.last.isBlank) {
          cb.removeLast();
        }
        final va = (td.attributes['valign'] ?? RegExp(r'vertical-align\s*:\s*(\w+)').firstMatch(st)?.group(1) ?? '')
            .toLowerCase();
        cells.add(NCell(cb,
            background: bg != null && !_isWhiteish(bg) ? bg : null,
            flex: (w != null && w > 0) ? w : 1,
            rowSpan: (int.tryParse(td.attributes['rowspan'] ?? '1') ?? 1).clamp(1, 60),
            colSpan: (int.tryParse(td.attributes['colspan'] ?? '1') ?? 1).clamp(1, 20),
            sides: (sd[0] ? kBorderTop : 0) | (sd[1] ? kBorderRight : 0) | (sd[2] ? kBorderBottom : 0) | (sd[3] ? kBorderLeft : 0),
            valign: va == 'middle' || va == 'center' ? 1 : (va == 'bottom' ? 2 : 0)));
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
        cellSides.add(sidesRow);
      }
    }
    if (rows.isEmpty) return;
    // Пустая таблица (разделитель из пустых ячеек) — не показывать.
    if (rows.every((r) => r.every((cell) => cell.blocks.isEmpty))) return;
    var borders = 0;
    if (tableSides[0]) borders |= kBorderTop;
    if (tableSides[1]) borders |= kBorderRight;
    if (tableSides[2]) borders |= kBorderBottom;
    if (tableSides[3]) borders |= kBorderLeft;
    for (var r = 0; r < cellSides.length; r++) {
      final row = cellSides[r];
      for (var k = 0; k < row.length; k++) {
        final sd = row[k];
        if (sd[0]) borders |= r == 0 ? kBorderTop : kBorderInsideH;
        if (sd[2]) borders |= r == cellSides.length - 1 ? kBorderBottom : kBorderInsideH;
        if (sd[3]) borders |= k == 0 ? kBorderLeft : kBorderInsideV;
        if (sd[1]) borders |= k == row.length - 1 ? kBorderRight : kBorderInsideV;
      }
    }
    blocks.add(NBlock(kind: NBlockKind.table, table: rows, borders: borders, quote: c.quote, after: 0.3));
    _blockCtx = c;
  }

  /// Оформление элемента: теги и атрибут style.
  _Ctx _inline(dom.Element e, String tag, String st, _Ctx c) {
    var x = c;
    switch (tag) {
      case 'b':
      case 'strong':
        x = x.copy(bold: true);
      case 'i':
      case 'em':
      case 'cite':
      case 'dfn':
        x = x.copy(italic: true);
      case 'u':
      case 'ins':
        x = x.copy(underline: true);
      case 's':
      case 'strike':
      case 'del':
        x = x.copy(strike: true);
      case 'code':
      case 'tt':
      case 'kbd':
      case 'samp':
        x = x.copy(mono: true);
      case 'small':
        x = x.copy(size: x.size * 0.85);
      case 'big':
        x = x.copy(size: x.size * 1.15);
      case 'a':
        final href = e.attributes['href']?.trim();
        if (href != null && href.isNotEmpty && !href.startsWith('#')) x = x.copy(href: href);
      case 'font':
        final fc = _parseColor(e.attributes['color']);
        if (fc != null) x = x.copy(color: fc);
        final fs = int.tryParse(e.attributes['size']?.trim() ?? '');
        if (fs != null) x = x.copy(size: const [0.7, 0.8, 1.0, 1.15, 1.45, 1.9, 2.6][(fs - 1).clamp(0, 6)]);
        final face = (e.attributes['face'] ?? '').toLowerCase();
        if (face.contains('courier') || face.contains('consolas') || face.contains('mono')) x = x.copy(mono: true);
    }
    if (st.isEmpty) return x;
    final col = _styleColor(st, 'color');
    if (col != null) x = x.copy(color: col);
    final bg = _styleColor(st, 'background-color') ?? _styleColor(st, 'background') ?? _styleColor(st, 'mso-highlight');
    if (bg != null && !_isWhiteish(bg) && !_blockTags.contains(tag)) x = x.copy(background: bg);
    final fw = RegExp(r'font-weight\s*:\s*(bold|bolder|[6-9]00)').hasMatch(st);
    if (fw) x = x.copy(bold: true);
    if (RegExp(r'font-weight\s*:\s*(normal|[1-4]00)').hasMatch(st)) {
      x = _Ctx(
          bold: false,
          italic: x.italic,
          underline: x.underline,
          strike: x.strike,
          mono: x.mono,
          pre: x.pre,
          color: x.color,
          background: x.background,
          size: x.size,
          href: x.href,
          quote: x.quote,
          list: x.list,
          align: x.align);
    }
    if (RegExp(r'font-style\s*:\s*italic').hasMatch(st)) x = x.copy(italic: true);
    if (RegExp(r'text-decoration[^;]*underline').hasMatch(st)) x = x.copy(underline: true);
    if (RegExp(r'text-decoration[^;]*line-through').hasMatch(st)) x = x.copy(strike: true);
    final fsz = RegExp(r'font-size\s*:\s*(\d+(?:\.\d+)?)\s*(pt|px|em|%)').firstMatch(st);
    if (fsz != null) {
      final v = double.parse(fsz.group(1)!);
      final rel = switch (fsz.group(2)) {
        'pt' => v * 4 / 3 / 14.67,
        'px' => v / 14.67,
        'em' => v,
        _ => v / 100,
      };
      // Обычный текст Outlook (11 pt) — обычный текст приложения.
      x = x.copy(size: (fsz.group(2) == 'em' || fsz.group(2) == '%' ? x.size * rel : rel).clamp(0.7, 2.2));
    }
    final ff = RegExp(r'font-family\s*:([^;]*)').firstMatch(st)?.group(1) ?? '';
    if (ff.contains('courier') || ff.contains('consolas') || ff.contains('monospace')) x = x.copy(mono: true);
    return x;
  }

  static NSpan _withText(NSpan s, String t) => NSpan(t,
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
      strike: s.strike,
      mono: s.mono,
      color: s.color,
      background: s.background,
      size: s.size,
      href: s.href);
}

int? _alignOf(dom.Element e, String st) {
  final a = (e.attributes['align'] ?? RegExp(r'text-align\s*:\s*(\w+)').firstMatch(st)?.group(1) ?? '')
      .toLowerCase();
  if ((e.localName ?? '') == 'center' || a == 'center') return 1;
  if (a == 'right') return 2;
  if (a == 'left' || a == 'justify') return 0;
  return null;
}

double? _dim(String? attr, String st, String prop) {
  final a = double.tryParse((attr ?? '').replaceAll('px', '').trim());
  if (a != null && a > 0) return a;
  final m = RegExp('(?<![-\\w])$prop\\s*:\\s*(\\d+(?:\\.\\d+)?)(px|pt)').firstMatch(st);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return m.group(2) == 'pt' ? v * 4 / 3 : v;
}

int? _styleColor(String st, String prop) {
  final m = RegExp('(?<![-\\w])$prop\\s*:\\s*([^;]+)').firstMatch(st);
  if (m == null) return null;
  // «background: #fff url(…)» и т. п. — первое слово.
  final v = m.group(1)!.trim();
  final first = v.startsWith('rgb') ? v.substring(0, (v.indexOf(')') + 1).clamp(0, v.length)) : v.split(' ').first;
  return _parseColor(first);
}

const _named = <String, int>{
  'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000, 'green': 0xFF008000, 'blue': 0xFF0000FF,
  'navy': 0xFF000080, 'maroon': 0xFF800000, 'purple': 0xFF800080, 'olive': 0xFF808000, 'teal': 0xFF008080,
  'gray': 0xFF808080, 'grey': 0xFF808080, 'silver': 0xFFC0C0C0, 'yellow': 0xFFFFFF00, 'orange': 0xFFFFA500,
  'lime': 0xFF00FF00, 'aqua': 0xFF00FFFF, 'fuchsia': 0xFFFF00FF, 'darkblue': 0xFF00008B, 'darkred': 0xFF8B0000,
  'darkgreen': 0xFF006400, 'cyan': 0xFF00FFFF, 'magenta': 0xFFFF00FF,
};

int? _parseColor(String? raw) {
  if (raw == null) return null;
  var v = raw.trim().toLowerCase().replaceAll('!important', '').trim();
  if (v.isEmpty || v == 'transparent' || v == 'inherit' || v == 'windowtext' || v == 'auto' || v == 'initial') {
    return null;
  }
  if (_named.containsKey(v)) return _named[v];
  if (v.startsWith('#')) {
    v = v.substring(1);
    if (v.length == 3) v = v.split('').map((ch) => '$ch$ch').join();
    if (v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : 0xFF000000 | n;
  }
  final m = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(v);
  if (m != null) {
    int ch(int i) => int.parse(m.group(i)!).clamp(0, 255);
    return 0xFF000000 | (ch(1) << 16) | (ch(2) << 8) | ch(3);
  }
  return null;
}

bool _isWhiteish(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return r > 240 && g > 240 && b > 240;
}

// ───────────────────────── показ ─────────────────────────

/// Простое письмо виджетами Flutter.
class MailNativeBody extends StatefulWidget {
  const MailNativeBody({
    super.key,
    required this.mail,
    required this.onLink,
    this.images = const {},
    this.textScale = 1,
    this.onShown,
  });

  final NativeMail mail;
  final void Function(String url, String? linkText) onLink;

  /// Встроенные картинки: Content-ID (нижний регистр, без «<>») → data URI.
  final Map<String, String> images;
  final double textScale;
  final VoidCallback? onShown;

  @override
  State<MailNativeBody> createState() => _MailNativeBodyState();
}

class _MailNativeBodyState extends State<MailNativeBody> {
  final List<TapGestureRecognizer> _taps = [];
  final Map<String, Uint8List?> _decoded = {};

  @override
  void initState() {
    super.initState();
    // Письмо видно в первом же кадре экрана.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown?.call();
    });
  }

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  /// Таблица с объединёнными ячейками: места ячеек в сетке — как у
  /// браузера (ячейка встаёт в первую свободную колонку строки), доли
  /// колонок — по ширинам ячеек без объединения колонок.
  Widget _spanTable(NBlock bl, ThemeData theme, Color? cellBg,
      List<Widget> Function(List<NBlock>, Color?) blocks) {
    final rows = bl.table!;
    final busy = <int, Set<int>>{};
    final placed = <({NCell cell, int row, int col})>[];
    var cols = 0;
    for (var r = 0; r < rows.length; r++) {
      var c = 0;
      for (final cell in rows[r]) {
        while (busy[r]?.contains(c) ?? false) {
          c++;
        }
        final rs = cell.rowSpan.clamp(1, rows.length - r);
        for (var i = 0; i < rs; i++) {
          for (var j = 0; j < cell.colSpan; j++) {
            (busy[r + i] ??= <int>{}).add(c + j);
          }
        }
        placed.add((cell: cell, row: r, col: c));
        c += cell.colSpan;
        if (c > cols) cols = c;
      }
    }
    final flex = List<double>.filled(cols, 0);
    for (final p in placed) {
      if (p.cell.colSpan == 1 && p.cell.flex > 1 && flex[p.col] == 0) flex[p.col] = p.cell.flex;
    }
    // Не у всех колонок ширина задана — поровну.
    final widths = flex.every((f) => f > 0) ? flex : List<double>.filled(cols, 1);
    final line = BorderSide(color: theme.dividerColor, width: 0.8);
    BorderSide side(int sides, int bit) => sides & bit != 0 ? line : BorderSide.none;
    return SpanTable(
      rows: rows.length,
      columnFlex: widths,
      children: [
        for (final p in placed)
          SpanCell(
            row: p.row,
            col: p.col,
            rowSpan: p.cell.rowSpan.clamp(1, rows.length - p.row),
            colSpan: p.cell.colSpan,
            child: Container(
              decoration: BoxDecoration(
                color: p.cell.background == null ? null : Color(p.cell.background!),
                border: p.cell.sides == 0
                    ? null
                    : Border(
                        top: side(p.cell.sides, kBorderTop),
                        right: side(p.cell.sides, kBorderRight),
                        bottom: side(p.cell.sides, kBorderBottom),
                        left: side(p.cell.sides, kBorderLeft),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              alignment: switch (p.cell.valign) {
                1 => Alignment.centerLeft,
                2 => Alignment.bottomLeft,
                _ => Alignment.topLeft,
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks(p.cell.blocks, p.cell.background == null ? cellBg : Color(p.cell.background!)),
              ),
            ),
          ),
      ],
    );
  }

  Uint8List? _bytes(String src) {
    var s = src;
    if (s.toLowerCase().startsWith('cid:')) {
      var cid = s.substring(4).trim();
      try {
        cid = Uri.decodeComponent(cid);
      } catch (_) {}
      if (cid.startsWith('<') && cid.endsWith('>')) cid = cid.substring(1, cid.length - 1);
      final data = widget.images[cid.toLowerCase()];
      if (data == null) return null;
      s = data;
    }
    return _decoded.putIfAbsent(s, () {
      final i = s.indexOf('base64,');
      if (!s.toLowerCase().startsWith('data:image/') || i < 0) return null;
      try {
        return base64Decode(s.substring(i + 7));
      } catch (_) {
        return null;
      }
    });
  }

  static double _lum(Color c) => c.computeLuminance();

  static double _contrast(Color a, Color b) {
    final la = _lum(a), lb = _lum(b);
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  // Готовое дерево письма: экран письма перестраивается часто (флажок,
  // плашки, шапка), а письмо от этого не меняется — повторно строить сотни
  // фрагментов текста незачем.
  Widget? _built;
  NativeMail? _bMail;
  Map<String, String>? _bImages;
  double? _bScale;
  ThemeData? _bTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Увеличение разведением пальцев (1.8.0): мелкие таблицы и картинки.
    return PinchZoom(
      resetLabel: AppLocalizations.of(context).tr('mailZoomReset'),
      child: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    final cached = _built;
    if (cached != null &&
        identical(_bMail, widget.mail) &&
        identical(_bImages, widget.images) &&
        _bScale == widget.textScale &&
        identical(_bTheme, theme)) {
      return cached;
    }
    _bMail = widget.mail;
    _bImages = widget.images;
    _bScale = widget.textScale;
    _bTheme = theme;
    return _built = _build(theme);
  }

  Widget _build(ThemeData theme) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    // Фон страницы письма — как у экрана письма.
    final page = mailPageColor(theme);
    final fg = theme.colorScheme.onSurface;
    final link = theme.colorScheme.primary;
    final base = TextStyle(fontSize: 14 * widget.textScale, height: 1.35, color: fg);

    Color? textColor(NSpan s, Color? cellBg) {
      if (s.background == null && cellBg != null) {
        // Текст в закрашенной ячейке — читаемый на её фоне.
        final own = s.color == null ? null : Color(s.color!);
        if (own != null && _contrast(own, cellBg) >= 3) return own;
        return cellBg.computeLuminance() > 0.45 ? Colors.black : Colors.white;
      }
      if (s.background != null) {
        return Color(s.background!).computeLuminance() > 0.45 ? Colors.black : Colors.white;
      }
      if (s.href != null && s.color == null) return link;
      if (s.color == null) return null;
      final c = Color(s.color!);
      // Цвет, который на фоне страницы не читается (чёрный в тёмной теме,
      // светло-серый в светлой), — цвет темы.
      return _contrast(c, page) < 3 ? (s.href != null ? link : null) : c;
    }

    InlineSpan span(NSpan s, Color? cellBg) {
      if (s.image != null) {
        final src = s.image!;
        // Картинка из интернета (разрешены — письмо собрано с ними, 1.5.11).
        if (src.startsWith('https://') || src.startsWith('http://')) {
          final w = s.imageWidth;
          final h = s.imageHeight;
          return WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w ?? double.infinity),
              child: Image.network(
                src,
                width: w,
                height: w == null ? h : null,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                // Пока грузится — место по размерам из письма, чтобы текст
                // не прыгал; не загрузилась — ничего (как пустой значок).
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : SizedBox(width: w ?? 1, height: (w != null && h != null) ? h : 1),
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            ),
          );
        }
        final b = _bytes(src);
        if (b == null) return const WidgetSpan(child: SizedBox.shrink());
        final w = s.imageWidth;
        return WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w ?? double.infinity),
            child: Image.memory(b,
                width: w, height: w == null ? s.imageHeight : null, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        );
      }
      TapGestureRecognizer? tap;
      final href = s.href;
      if (href != null) {
        tap = TapGestureRecognizer()..onTap = () => widget.onLink(href, s.text.trim());
        _taps.add(tap);
      }
      final deco = <TextDecoration>[
        if (s.underline) TextDecoration.underline,
        if (s.strike) TextDecoration.lineThrough,
      ];
      return TextSpan(
        text: s.text,
        recognizer: tap,
        style: TextStyle(
          fontWeight: s.bold ? FontWeight.w700 : null,
          fontStyle: s.italic ? FontStyle.italic : null,
          decoration: deco.isEmpty ? null : TextDecoration.combine(deco),
          fontFamily: s.mono ? 'monospace' : null,
          fontSize: s.size == 1 ? null : base.fontSize! * s.size,
          color: textColor(s, cellBg),
          backgroundColor: s.background == null ? null : Color(s.background!),
        ),
      );
    }

    final quoteLine = theme.colorScheme.outlineVariant;

    List<Widget> blocks(List<NBlock> list, Color? cellBg) {
    final children = <Widget>[];
    for (final bl in list) {
      Widget w;
      if (bl.kind == NBlockKind.hr) {
        w = Divider(height: 16, thickness: 1, color: theme.dividerColor);
      } else if (bl.kind == NBlockKind.table && bl.table!.any((r) => r.any((c) => c.rowSpan > 1 || c.colSpan > 1))) {
        // Объединённые ячейки (1.5.11) — своя раскладка, рамки — у ячеек.
        w = _spanTable(bl, theme, cellBg, blocks);
        final after = bl.after * base.fontSize! * 1.35;
        if (after > 0) w = Padding(padding: EdgeInsets.only(bottom: after), child: w);
      } else if (bl.kind == NBlockKind.table) {
        final rows = bl.table!;
        final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
        // Доли колонок — по ширинам первой строки, если заданы у всех ячеек.
        final first = rows.first;
        final widths = first.length == cols && first.every((c) => c.flex > 1)
            ? [for (final c in first) c.flex]
            : List<double>.filled(cols, 1);
        w = Table(
          border: bl.border
              ? () {
                  final line = BorderSide(color: theme.dividerColor, width: 0.8);
                  BorderSide side(int bit) => bl.borders & bit != 0 ? line : BorderSide.none;
                  return TableBorder(
                    top: side(kBorderTop),
                    right: side(kBorderRight),
                    bottom: side(kBorderBottom),
                    left: side(kBorderLeft),
                    horizontalInside: side(kBorderInsideH),
                    verticalInside: side(kBorderInsideV),
                  );
                }()
              : null,
          columnWidths: {for (var i = 0; i < cols; i++) i: FlexColumnWidth(widths[i])},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (final r in rows)
              TableRow(children: [
                for (var i = 0; i < cols; i++)
                  i < r.length
                      ? Container(
                          color: r[i].background == null ? null : Color(r[i].background!),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: blocks(r[i].blocks,
                                r[i].background == null ? cellBg : Color(r[i].background!)),
                          ),
                        )
                      : const SizedBox.shrink(),
              ]),
          ],
        );
        final after = bl.after * base.fontSize! * 1.35;
        if (after > 0) w = Padding(padding: EdgeInsets.only(bottom: after), child: w);
      } else {
        final text = Text.rich(
          TextSpan(children: [for (final s in bl.spans) span(s, cellBg)]),
          style: base,
          textScaler: TextScaler.noScaling,
          softWrap: true,
          textAlign: switch (bl.align) { 1 => TextAlign.center, 2 => TextAlign.right, _ => TextAlign.start },
        );
        w = bl.bullet == null
            ? text
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 22,
                  child: Text(bl.bullet!, style: base, textScaler: TextScaler.noScaling),
                ),
                Expanded(child: text),
              ]);
        final indent = (bl.list > 1 ? (bl.list - 1) * 18.0 : 0.0);
        final after = bl.after * base.fontSize! * 1.35;
        if (indent > 0 || after > 0) {
          w = Padding(padding: EdgeInsets.only(left: indent, bottom: after), child: w);
        }
      }
      for (var q = 0; q < bl.quote; q++) {
        w = Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: quoteLine, width: 3))),
          child: w,
        );
      }
      children.add(w);
    }
    return children;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: SelectionArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(widget.mail.blocks, null)),
      ),
    );
  }
}

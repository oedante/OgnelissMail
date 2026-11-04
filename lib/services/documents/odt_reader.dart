// lib/services/documents/odt_reader.dart
// Текстовый документ OpenDocument (ODT, OTT) → HTML для просмотра вложения
// (1.11.x, предпросмотр документов, план владельца 04.11.2026). Формат —
// OASIS OpenDocument 1.2/1.3 (ISO/IEC 26300): content.xml (текст и
// автоматические стили) и styles.xml (стили документа, стиль по
// умолчанию, нумерация заголовков, размер страницы).
//
// Что показывается: заголовки (text:h с уровнем структуры, номера по
// text:outline-style), оформление текста и абзацев с цепочками стилей
// (style:parent-style-name), списки с номерами и маркерами по стилю списка
// (уровни, «1.2.», продолжение нумерации), таблицы (объединение, заливка,
// рамки, вложенные), картинки (draw:image из Pictures/ и встроенные
// office:binary-data), надписи (draw:text-box) и текст фигур, ссылки
// (только http, https, mailto), сноски и концевые сноски — под чертой,
// разделы и оглавления (их готовый текст), поля — их текст.
// Не показываются: колонтитулы, примечания (office:annotation), удалённый
// при записи исправлений текст, формулы и диаграммы (объекты OLE),
// межстрочный интервал, позиции табуляции, колонки.

import 'dart:convert';
import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'doc_html.dart';
import 'doc_xml.dart';
import 'office_document.dart';
import 'office_package.dart';

class OdtReader {
  OdtReader._();

  static const _mimes = {
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.text-template',
    'application/vnd.oasis.opendocument.text-master',
    'application/vnd.oasis.opendocument.text-master-template',
    'application/vnd.oasis.opendocument.text-web',
  };

  /// Разобрать документ. Ошибки — только [OfficeDocException].
  static OfficeTextDoc read(OfficeZip zip) {
    try {
      if (zip.odfEncrypted) throw const OfficeDocException(OfficeDocError.encrypted, 'odf');
      final mime = zip.odfMimeType;
      // Таблица или презентация с расширением .odt — не текстовый документ.
      if (mime != null && !_mimes.contains(mime)) throw OfficeDocException(OfficeDocError.damaged, 'mimetype $mime');
      return _Odt(zip).run();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, '$e');
    }
  }
}

/// Свойства текста (style:text-properties); null — не задано.
class _TP {
  bool? b, i, u, s, smallCaps, hidden;
  String? transform;
  DocVert? vert;

  /// 0 — «авто» (цвет окна); у фона 0 — прозрачный.
  int? color, bg;
  double? size, pct;
  String? font;
  bool fontMono = false, fontSymbol = false;

  _TP over(_TP? o) {
    if (o == null) return this;
    final r = _TP()
      ..b = o.b ?? b
      ..i = o.i ?? i
      ..u = o.u ?? u
      ..s = o.s ?? s
      ..smallCaps = o.smallCaps ?? smallCaps
      ..hidden = o.hidden ?? hidden
      ..transform = o.transform ?? transform
      ..vert = o.vert ?? vert
      ..color = o.color ?? color
      ..bg = o.bg ?? bg
      ..font = o.font ?? font
      ..fontMono = o.font != null ? o.fontMono : fontMono
      ..fontSymbol = o.font != null ? o.fontSymbol : fontSymbol;
    // «120%» — от размера родителя.
    r.size = o.size ?? (o.pct != null && size != null ? size! * o.pct! / 100 : size);
    return r;
  }

  DocFont get docFont => DocFont(
    bold: b ?? false,
    italic: i ?? false,
    underline: u ?? false,
    strike: s ?? false,
    smallCaps: smallCaps ?? false,
    mono: fontMono,
    vert: vert ?? DocVert.none,
    color: (color ?? 0) == 0 ? null : color,
    background: (bg ?? 0) == 0 ? null : bg,
    size: size,
  );
}

/// Свойства абзаца (style:paragraph-properties).
class _PP {
  String? align;
  double? left, right, top, bottom, indent;
  int? bg;
  bool? rtl, contextual;
  bool breakBefore = false, breakAfter = false;
  DocLine? bTop, bRight, bBottom, bLeft;
  bool hasBorders = false;

  _PP over(_PP? o) {
    if (o == null) return this;
    final r = _PP()
      ..align = o.align ?? align
      ..left = o.left ?? left
      ..right = o.right ?? right
      ..top = o.top ?? top
      ..bottom = o.bottom ?? bottom
      ..indent = o.indent ?? indent
      ..bg = o.bg ?? bg
      ..rtl = o.rtl ?? rtl
      ..contextual = o.contextual ?? contextual
      // Разрыв страницы — свойство самого абзаца, не наследуется по смыслу,
      // но в стиле («Заголовок 1 с новой страницы») — тоже разрыв.
      ..breakBefore = o.breakBefore || breakBefore
      ..breakAfter = o.breakAfter || breakAfter;
    if (o.hasBorders) {
      r
        ..bTop = o.bTop
        ..bRight = o.bRight
        ..bBottom = o.bBottom
        ..bLeft = o.bLeft
        ..hasBorders = true;
    } else {
      r
        ..bTop = bTop
        ..bRight = bRight
        ..bBottom = bBottom
        ..bLeft = bLeft
        ..hasBorders = hasBorders;
    }
    return r;
  }
}

class _OStyle {
  final String name;
  final String family;
  final String? parent;
  final String? listStyle;
  final XmlElement el;
  const _OStyle(this.name, this.family, this.parent, this.listStyle, this.el);
}

/// Уровень стиля списка.
class _Level {
  bool bullet = false;
  String char = '•';
  String? font;
  String format = '1';
  String prefix = '';
  String suffix = '';
  int display = 1;
  int start = 1;
  bool sync = false;

  /// loext:num-list-format («%1%.%2%.») — точный вид номера у LibreOffice.
  String? listFormat;

  /// Отступы, pt: левый край текста и выступ первой строки (< 0).
  double? left, indent;
}

class _ListState {
  final counters = List<int?>.filled(10, null);
}

class _Ctx {
  final List<DocInline> inlines = [];
  final List<DocBlock> after = [];
  final List<String?> hrefs = [];
  bool space = true;
  bool lastTab = false;

  String? get href {
    for (var i = hrefs.length - 1; i >= 0; i--) {
      if (hrefs[i] != null) return hrefs[i];
    }
    return null;
  }

  int get produced => inlines.length + after.length;
}

class _Odt {
  _Odt(this.zip);

  final OfficeZip zip;
  final budget = DocBudget();
  final images = DocImages();

  final styles = <String, _OStyle>{};
  final defaults = <String, XmlElement>{};
  final listStyles = <String, Map<int, _Level>>{};
  Map<int, _Level> outline = const {};
  final fonts = <String, ({String family, bool mono, bool symbol})>{};

  /// Ширина текста страницы, pt (A4 с полями 2 см).
  double pageWidth = 481.9;

  final lists = <String, _ListState>{};
  _ListState? lastList;
  final outlineState = _ListState();

  final foot = <DocBlock>[];
  final end = <DocBlock>[];
  DocText? noteLead;
  int binaryTotal = 0;

  static const _structural = {
    'document-content',
    'body',
    'text',
    'automatic-styles',
    'styles',
    'font-face-decls',
    'table',
    'table-row',
    'table-rows',
    'table-header-rows',
    'table-row-group',
    'table-columns',
    'table-column-group',
    'table-cell',
    'covered-table-cell',
    'list',
    'list-item',
    'list-header',
    'section',
    'note',
    'note-body',
    'index-body',
    'table-of-content',
    'alphabetical-index',
    'illustration-index',
    'table-index',
    'object-index',
    'user-index',
    'bibliography',
    'frame',
    'text-box',
    'tracked-changes',
    'sequence-decls',
    'variable-decls',
    'user-field-decls',
    'scripts',
    'forms',
    'master-styles',
    'office-styles',
    'style',
    'list-style',
    'outline-style',
    'g',
  };

  OfficeTextDoc run() {
    final head = zip.readHead('content.xml', OfficeLimits.maxPartBytes);
    if (head == null) throw const OfficeDocException(OfficeDocError.damaged, 'no content.xml');
    final tree = DocXml.parse(
      OfficeZip.decodeText(head.bytes),
      blocks: const {'p', 'h', 'table-cell', 'table-row'},
      keepBlank: (p) => !_structural.contains(p),
      stopDepth: 3,
      cutInput: head.truncated,
    );
    final root = tree.root;
    final text = root.kid('body')?.kid('text');
    if (root.local != 'document-content' || text == null) {
      throw const OfficeDocException(OfficeDocError.damaged, 'not an OpenDocument text');
    }
    _loadStyles(root);

    final blocks = <DocBlock>[];
    _blocks(text, 0, blocks);
    final notes = [...foot, ...end];
    return DocHtml.render(blocks, notes: notes, images: images.map, truncated: budget.truncated || tree.cut);
  }

  // ───────────────────────── стили ─────────────────────────

  void _loadStyles(XmlElement content) {
    XmlElement? stylesRoot;
    try {
      final h = zip.readHead('styles.xml', 8 * 1024 * 1024);
      if (h != null) {
        stylesRoot = DocXml.parse(
          OfficeZip.decodeText(h.bytes),
          blocks: const {},
          keepBlank: (_) => false,
          stopDepth: 0,
          cutInput: h.truncated,
        ).root;
      }
    } on OfficeDocException catch (e) {
      // Испорченные стили — документ без оформления, но с текстом.
      if (e.kind != OfficeDocError.damaged) rethrow;
    }
    // Порядок: стили документа, потом автоматические стили content.xml —
    // они важнее при совпадении имён.
    if (stylesRoot != null) {
      _fonts(stylesRoot.kid('font-face-decls'));
      _styleSet(stylesRoot.kid('styles'), defaultsToo: true);
      _styleSet(stylesRoot.kid('automatic-styles'));
      _page(stylesRoot);
    }
    _fonts(content.kid('font-face-decls'));
    _styleSet(content.kid('automatic-styles'));
  }

  void _fonts(XmlElement? decls) {
    if (decls == null) return;
    for (final f in decls.kids('font-face')) {
      final name = f.attr('name');
      if (name == null) continue;
      final family = (f.attr('font-family') ?? name).replaceAll(RegExp('["\']'), '');
      final low = family.toLowerCase();
      fonts[name] = (
        family: family,
        mono:
            f.attr('font-pitch') == 'fixed' ||
            low.contains('courier') ||
            low.contains('mono') ||
            low.contains('consolas'),
        symbol: f.attr('font-charset') == 'x-symbol' || low.contains('symbol') || low.contains('wingdings'),
      );
    }
  }

  void _styleSet(XmlElement? set, {bool defaultsToo = false}) {
    if (set == null) return;
    for (final s in set.childElements) {
      switch (s.local) {
        case 'style':
          final name = s.attr('name');
          final family = s.attr('family');
          if (name == null || family == null) continue;
          styles['$family:$name'] = _OStyle(name, family, s.attr('parent-style-name'), s.attr('list-style-name'), s);
        case 'default-style':
          final family = s.attr('family');
          if (defaultsToo && family != null) defaults[family] = s;
        case 'list-style':
          final name = s.attr('name');
          if (name != null) listStyles[name] = _levels(s);
        case 'outline-style':
          outline = _levels(s);
      }
    }
  }

  void _page(XmlElement stylesRoot) {
    // Ширина текста — по первому макету страницы.
    final layout = stylesRoot.kid('automatic-styles')?.kids('page-layout').firstOrNull;
    final pp = layout?.kid('page-layout-properties');
    final w = _len(pp?.attr('page-width'));
    if (w == null) return;
    final l = _len(pp?.attr('margin-left')) ?? 56.7;
    final r = _len(pp?.attr('margin-right')) ?? 56.7;
    if (w - l - r > 72) pageWidth = w - l - r;
  }

  Map<int, _Level> _levels(XmlElement style) {
    final out = <int, _Level>{};
    for (final l in style.childElements) {
      final n = int.tryParse(l.attr('level') ?? '');
      if (n == null || n < 1 || n > 10) continue;
      final v = _Level();
      switch (l.local) {
        case 'list-level-style-bullet':
          v.bullet = true;
          v.char = l.attr('bullet-char') ?? '•';
          final tp = l.kid('text-properties');
          final fn = tp?.attr('font-name');
          v.font = fn == null ? tp?.attr('font-family') : (fonts[fn]?.family ?? fn);
        case 'list-level-style-image':
          v.bullet = true;
        case 'list-level-style-number':
        case 'outline-level-style':
          v.format = l.attr('num-format') ?? '';
          v.prefix = l.attr('num-prefix') ?? '';
          v.suffix = l.attr('num-suffix') ?? '';
          v.display = (int.tryParse(l.attr('display-levels') ?? '') ?? 1).clamp(1, 10);
          v.start = int.tryParse(l.attr('start-value') ?? '') ?? 1;
          v.sync = l.attr('num-letter-sync') == 'true';
          v.listFormat = l.attr('num-list-format');
        default:
          continue;
      }
      final props = l.kid('list-level-properties');
      final align = props?.kid('list-level-label-alignment');
      if (props?.attr('list-level-position-and-space-mode') == 'label-alignment' && align != null) {
        v.left = _len(align.attr('margin-left'));
        v.indent = _len(align.attr('text-indent'));
      } else if (props != null) {
        final before = _len(props.attr('space-before')) ?? 0;
        final width = _len(props.attr('min-label-width')) ?? 0;
        if (before != 0 || width != 0) {
          v.left = before + width;
          v.indent = -width;
        }
      }
      out[n] = v;
    }
    return out;
  }

  /// Цепочка стиля [name] семейства [family] от корня; первым — стиль по
  /// умолчанию семейства.
  List<XmlElement> _chain(String family, String? name) {
    final out = <XmlElement>[];
    final seen = <String>{};
    var cur = name;
    while (cur != null && seen.add(cur) && out.length < 32) {
      final s = styles['$family:$cur'];
      if (s == null) break;
      out.add(s.el);
      cur = s.parent;
    }
    final d = defaults[family];
    if (d != null) out.add(d);
    return out.reversed.toList();
  }

  final _tCache = <String, _TP>{};
  final _pCache = <String, _PP>{};

  _TP _text(String family, String? name) => _tCache['$family:$name'] ??= () {
    var t = _TP();
    for (final s in _chain(family, name)) {
      final tp = s.kid('text-properties');
      if (tp != null) t = t.over(_textProps(tp));
    }
    return t;
  }();

  _PP _para(String? name) => _pCache[name ?? ''] ??= () {
    var p = _PP();
    for (final s in _chain('paragraph', name)) {
      final pp = s.kid('paragraph-properties');
      if (pp != null) p = p.over(_paraProps(pp));
    }
    return p;
  }();

  /// Стиль списка абзаца по его стилю (style:list-style-name по цепочке).
  String? _paraListStyle(String? name) {
    final seen = <String>{};
    var cur = name;
    while (cur != null && seen.add(cur) && seen.length < 32) {
      final s = styles['paragraph:$cur'];
      if (s == null) return null;
      if (s.listStyle != null && s.listStyle!.isNotEmpty) return s.listStyle;
      cur = s.parent;
    }
    return null;
  }

  // ───────────────────────── свойства ─────────────────────────

  /// Длина ODF («1.25cm», «0.5in», «12pt», «10mm», «1pc», «16px») → pt.
  static double? _len(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^\s*(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*(cm|mm|in|inch|pt|pc|px)?\s*$').firstMatch(v);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!);
    if (n == null || n.isNaN || n.isInfinite) return null;
    return switch (m.group(2)) {
      'cm' => n * 72 / 2.54,
      'mm' => n * 72 / 25.4,
      'in' || 'inch' => n * 72,
      'pc' => n * 12,
      'px' => n * 0.75,
      _ => n,
    };
  }

  static int? _color(String? v) {
    if (v == null) return null;
    if (v == 'transparent' || v == 'none') return 0;
    return DocHtml.parseHex(v);
  }

  static DocLine? _border(String? v) {
    if (v == null) return null;
    final s = v.trim().toLowerCase();
    if (s.isEmpty || s == 'none' || s == 'hidden') return null;
    double? width;
    String style = 'solid';
    int? color;
    for (final part in s.split(RegExp(r'\s+'))) {
      final l = _len(part);
      if (l != null) {
        width = l;
      } else if (part.startsWith('#')) {
        color = DocHtml.parseHex(part);
      } else if (const {'solid', 'dotted', 'dashed', 'double', 'groove', 'ridge', 'inset', 'outset'}.contains(part)) {
        style = const {'dotted', 'dashed', 'double'}.contains(part) ? part : 'solid';
      } else if (part == 'none' || part == 'hidden') {
        return null;
      }
    }
    if (width != null && width <= 0) return null;
    return DocLine(width: width ?? 0.5, style: style, color: color);
  }

  _TP _textProps(XmlElement e) {
    final t = _TP();
    final w = e.attr('font-weight');
    if (w != null) t.b = w == 'bold' || (int.tryParse(w) ?? 0) >= 600;
    final st = e.attr('font-style');
    if (st != null) t.i = st == 'italic' || st == 'oblique';
    final ul = e.attr('text-underline-style');
    final ulType = e.attr('text-underline-type');
    if (ul != null || ulType != null) t.u = (ul ?? 'solid') != 'none' && ulType != 'none';
    final lt = e.attr('text-line-through-style');
    final ltType = e.attr('text-line-through-type');
    if (lt != null || ltType != null) t.s = (lt ?? 'solid') != 'none' && ltType != 'none';
    final fv = e.attr('font-variant');
    if (fv != null) t.smallCaps = fv == 'small-caps';
    final tt = e.attr('text-transform');
    if (tt != null) t.transform = tt;
    if (e.attr('display') == 'none') t.hidden = true;
    if (e.attr('use-window-font-color') == 'true') {
      t.color = 0;
    } else {
      final c = _color(e.attr('color', ns: 'xsl-fo'));
      if (c != null) t.color = c;
    }
    final bg = _color(e.attr('background-color'));
    if (bg != null) t.bg = bg;
    final fs = e.attr('font-size', ns: 'xsl-fo');
    if (fs != null) {
      if (fs.endsWith('%')) {
        t.pct = double.tryParse(fs.substring(0, fs.length - 1));
      } else {
        final pt = _len(fs);
        if (pt != null && pt >= 1 && pt <= 400) t.size = pt;
      }
    }
    final pos = e.attr('text-position');
    if (pos != null) {
      final first = pos.trim().split(RegExp(r'\s+')).first;
      final pct = double.tryParse(first.replaceAll('%', ''));
      t.vert = first == 'super' || (pct != null && pct > 0)
          ? DocVert.sup
          : (first == 'sub' || (pct != null && pct < 0) ? DocVert.sub : DocVert.none);
    }
    final fn = e.attr('font-name');
    final ff = e.attr('font-family', ns: 'xsl-fo');
    if (fn != null) {
      final f = fonts[fn];
      t.font = f?.family ?? fn;
      t.fontMono = f?.mono ?? _monoName(fn);
      t.fontSymbol = f?.symbol ?? false;
    } else if (ff != null) {
      t.font = ff.replaceAll(RegExp('["\']'), '');
      t.fontMono = _monoName(t.font!);
    }
    return t;
  }

  static bool _monoName(String n) {
    final l = n.toLowerCase();
    return l.contains('courier') || l.contains('consolas') || l.contains('mono');
  }

  _PP _paraProps(XmlElement e) {
    final p = _PP();
    p.align = switch (e.attr('text-align')) {
      'center' => 'center',
      'end' || 'right' => 'right',
      'justify' => 'justify',
      'start' || 'left' => '',
      _ => null,
    };
    final m = _len(e.attr('margin'));
    p.left = _len(e.attr('margin-left')) ?? m;
    p.right = _len(e.attr('margin-right')) ?? m;
    p.top = _len(e.attr('margin-top')) ?? m;
    p.bottom = _len(e.attr('margin-bottom')) ?? m;
    p.indent = _len(e.attr('text-indent'));
    p.bg = _color(e.attr('background-color'));
    final wm = e.attr('writing-mode');
    if (wm != null) p.rtl = wm.startsWith('rl');
    final cs = e.attr('contextual-spacing');
    if (cs != null) p.contextual = cs == 'true';
    p.breakBefore = e.attr('break-before') == 'page';
    p.breakAfter = e.attr('break-after') == 'page';
    final all = e.attr('border');
    final top = e.attr('border-top') ?? all;
    final right = e.attr('border-right') ?? all;
    final bottom = e.attr('border-bottom') ?? all;
    final left = e.attr('border-left') ?? all;
    if (top != null || right != null || bottom != null || left != null) {
      p
        ..hasBorders = true
        ..bTop = _border(top)
        ..bRight = _border(right)
        ..bBottom = _border(bottom)
        ..bLeft = _border(left);
    }
    return p;
  }

  // ───────────────────────── блоки ─────────────────────────

  void _blocks(XmlElement e, int depth, List<DocBlock> out) {
    if (depth > OfficeLimits.maxDepth) return;
    for (final k in e.childElements) {
      if (budget.full) return;
      _block(k, depth, out);
    }
  }

  /// Один блок: абзац, заголовок, список, таблица, раздел, оглавление,
  /// рамка или фигура, привязанная к странице.
  void _block(XmlElement k, int depth, List<DocBlock> out) {
    switch (k.local) {
      case 'p':
      case 'h':
        _paragraph(k, out, depth);
      case 'list':
        _list(k, out, depth + 1, null, 1);
      case 'numbered-paragraph':
        final number = k.kid('number')?.innerText.trim();
        for (final p in k.childElements.where((c) => c.local == 'p' || c.local == 'h')) {
          _paragraph(
            p,
            out,
            depth + 1,
            label: number == null || number.isEmpty ? null : DocText(number, DocFont.plain),
          );
        }
      case 'table':
        final t = _table(k, depth + 1);
        if (t != null) out.add(t);
      case 'section':
        if (k.attr('display') != 'none') _blocks(k, depth + 1, out);
      case 'table-of-content':
      case 'illustration-index':
      case 'table-index':
      case 'object-index':
      case 'user-index':
      case 'alphabetical-index':
      case 'bibliography':
        final body = k.kid('index-body');
        if (body != null) _blocks(body, depth + 1, out);
      case 'index-title':
        _blocks(k, depth + 1, out);
      default:
        if (!_isShape(k) || depth > OfficeLimits.maxDepth) return;
        // Рамка или фигура, привязанная к странице: картинка — отдельной
        // строкой, текст — абзацами.
        if (!budget.block()) return;
        final ctx = _Ctx();
        _shapeText(k, ctx, depth + 1);
        if (ctx.inlines.isNotEmpty) out.add(DocPara(const DocParaStyle(), ctx.inlines));
        out.addAll(ctx.after);
    }
  }

  /// Список: пункты — абзацы с номером или маркером и отступом уровня.
  void _list(XmlElement list, List<DocBlock> out, int depth, String? parentStyle, int level) {
    if (depth > OfficeLimits.maxDepth) return;
    final styleName = list.attr('style-name') ?? parentStyle;
    _ListState state;
    if (level == 1) {
      final cont = list.attr('continue-list');
      if (cont != null && lists.containsKey('id:$cont')) {
        state = lists['id:$cont']!;
      } else if (list.attr('continue-numbering') == 'true' && lastList != null) {
        state = lastList!;
      } else {
        state = _ListState();
      }
      lastList = state;
      final id = list.attr('id');
      if (id != null) lists['id:$id'] = state;
    } else {
      state = lastList ?? _ListState();
    }
    for (final item in list.childElements) {
      if (budget.full) return;
      final header = item.local == 'list-header';
      if (item.local != 'list-item' && !header) continue;
      var labeled = false;
      for (final c in item.childElements) {
        if (budget.full) return;
        switch (c.local) {
          case 'p':
          case 'h':
            final ls = styleName ?? _paraListStyle(c.attr('style-name'));
            final lv = _levelOf(ls, level);
            DocText? label;
            if (!labeled && !header && lv != null) {
              final start = int.tryParse(item.attr('start-value') ?? '');
              label = _number(lv, ls, level, state, start, _text('paragraph', c.attr('style-name')));
            }
            _paragraph(c, out, depth, label: label, indent: lv, keepLabelSpace: labeled || header);
            labeled = true;
          case 'list':
            _list(c, out, depth + 1, styleName, level + 1);
            labeled = true;
          default:
            _block(c, depth + 1, out);
        }
      }
    }
  }

  _Level? _levelOf(String? styleName, int level) {
    final levels = styleName == null ? null : listStyles[styleName];
    if (levels == null || levels.isEmpty) return null;
    for (var l = level.clamp(1, 10); l >= 1; l--) {
      if (levels[l] != null) return levels[l];
    }
    return null;
  }

  /// Номер или маркер пункта уровня [level] (счётчики [state]).
  DocText? _number(
    _Level lv,
    String? styleName,
    int level,
    _ListState state,
    int? start,
    _TP paraText, {
    Map<int, _Level>? levels,
  }) {
    final lvl = level.clamp(1, 10);
    final c = state.counters;
    final all = levels ?? (styleName == null ? const <int, _Level>{} : (listStyles[styleName] ?? const {}));
    c[lvl - 1] = start ?? (c[lvl - 1] == null ? lv.start : c[lvl - 1]! + 1);
    for (var d = lvl; d < c.length; d++) {
      c[d] = null;
    }
    final font = paraText.docFont;
    final f = DocFont(bold: font.bold, italic: font.italic, color: font.color, size: font.size);
    if (lv.bullet) return DocText(DocHtml.bullet(lv.char, lv.font), f);
    if (lv.format.isEmpty && lv.listFormat == null) return null;
    String num(int l) {
      final lvL = all[l] ?? lv;
      final n = c[l - 1] ?? lvL.start;
      return DocNumbers.format(n, _fmt(lvL.format), sync: lvL.sync);
    }

    final String text;
    if (lv.listFormat != null && lv.listFormat!.contains('%')) {
      text = lv.listFormat!.replaceAllMapped(RegExp(r'%(\d+)%'), (m) {
        final l = int.parse(m.group(1)!).clamp(1, lvl);
        return num(l);
      });
    } else {
      final from = math.max(1, lvl - lv.display + 1);
      text = '${lv.prefix}${[for (var l = from; l <= lvl; l++) num(l)].join('.')}${lv.suffix}';
    }
    return text.trim().isEmpty ? null : DocText(text, f);
  }

  static String _fmt(String f) => switch (f) {
    'a' => 'lowerLetter',
    'A' => 'upperLetter',
    'i' => 'lowerRoman',
    'I' => 'upperRoman',
    'а' => 'russianLower',
    'А' => 'russianUpper',
    '' => 'none',
    _ => 'decimal',
  };

  void _paragraph(
    XmlElement p,
    List<DocBlock> out,
    int depth, {
    DocText? label,
    _Level? indent,
    bool keepLabelSpace = false,
  }) {
    if (!budget.block()) return;
    final styleName = p.attr('style-name');
    final pp = _para(styleName);
    final tp = _text('paragraph', styleName);
    var heading = p.local == 'p' && _isTitle(styleName) ? 1 : 0;
    if (p.local == 'h') {
      heading = (int.tryParse(p.attr('outline-level') ?? '') ?? 1).clamp(1, 6);
      // Номер заголовка по нумерации структуры документа (text:outline-style).
      if (label == null && indent == null && p.attr('is-list-header') != 'true') {
        final lv = outline[heading];
        if (lv != null && (lv.format.isNotEmpty || lv.listFormat != null) && !lv.bullet) {
          label = _number(
            lv,
            null,
            heading,
            outlineState,
            int.tryParse(p.attr('start-value') ?? ''),
            tp,
            levels: outline,
          );
        }
      }
    }
    var left = pp.left ?? 0;
    var first = pp.indent ?? 0;
    if (indent != null && indent.left != null) {
      left = indent.left!;
      // Второй абзац пункта — без номера, но с отступом текста пункта.
      first = keepLabelSpace ? 0 : (indent.indent ?? 0);
    }
    var before = pp.top ?? 0;
    final after = pp.bottom ?? 0;
    // «Не добавлять интервал между абзацами одного стиля» (пункты списка —
    // каждый в своём text:list-item, поэтому по предыдущему абзацу вывода).
    final last = _last;
    if ((pp.contextual ?? false) &&
        last != null &&
        last.style == styleName &&
        identical(last.list, out) &&
        out.isNotEmpty &&
        identical(out.last, last.para)) {
      before = 0;
      out[out.length - 1] = DocPara(last.para.style.withSpacing(after: 0), last.para.inlines, label: last.para.label);
    }
    final style = DocParaStyle(
      heading: heading,
      align: (pp.align ?? '').isEmpty ? null : pp.align,
      before: before.clamp(0, 144).toDouble(),
      after: after.clamp(0, 144).toDouble(),
      left: left.clamp(-144, 1440).toDouble(),
      right: (pp.right ?? 0).clamp(-144, 1440).toDouble(),
      firstLine: first.clamp(-720, 720).toDouble(),
      background: (pp.bg ?? 0) == 0 ? null : pp.bg,
      borders: pp.hasBorders
          ? DocBorders(top: pp.bTop, right: pp.bRight, bottom: pp.bBottom, left: pp.bLeft)
          : DocBorders.none,
      rtl: pp.rtl ?? false,
      size: tp.size,
    );
    final ctx = _Ctx();
    final lead = noteLead;
    if (lead != null) {
      noteLead = null;
      ctx.inlines.add(lead);
    }
    _inline(p, ctx, tp, depth);
    // Номер сноски и её текст — через пробел (LibreOffice пишет его сам).
    if (lead != null && ctx.inlines.length > 1) {
      final next = ctx.inlines[1];
      if (next is! DocText || !next.text.startsWith(' ')) ctx.inlines.insert(1, DocText(' ', DocFont(size: tp.size)));
    }
    if (pp.breakBefore) out.add(const DocRule());
    final para = DocPara(style, ctx.inlines, label: label);
    out.add(para);
    _last = (list: out, para: para, style: styleName);
    out.addAll(ctx.after);
    if (pp.breakAfter) out.add(const DocRule());
  }

  /// Последний абзац вывода и его стиль — для contextual spacing.
  ({List<DocBlock> list, DocPara para, String? style})? _last;

  /// Стиль «Название» (Title) по цепочке — заголовок первого уровня, как у
  /// Word.
  bool _isTitle(String? name) {
    final seen = <String>{};
    var cur = name;
    while (cur != null && seen.add(cur) && seen.length < 32) {
      final s = styles['paragraph:$cur'];
      if (s == null) return false;
      if (s.name == 'Title' || (s.el.attr('display-name') ?? '').toLowerCase() == 'title') return true;
      cur = s.parent;
    }
    return false;
  }

  // ───────────────────────── текст абзаца ─────────────────────────

  void _inline(XmlElement e, _Ctx ctx, _TP tp, int depth, {XmlElement? only}) {
    if (depth > OfficeLimits.maxDepth) return;
    for (final n in e.children) {
      if (budget.full) return;
      if (only != null && n != only) continue;
      if (n is XmlText) {
        _textRun(n.value, ctx, tp, collapse: true);
        continue;
      }
      if (n is! XmlElement) continue;
      switch (n.local) {
        case 'span':
          final st = n.attr('style-name');
          _inline(n, ctx, st == null ? tp : tp.over(_text('text', st)), depth + 1);
        case 'a':
          ctx.hrefs.add(DocHtml.safeHref(n.attr('href')));
          final st = n.attr('style-name');
          _inline(n, ctx, st == null ? tp : tp.over(_text('text', st)), depth + 1);
          ctx.hrefs.removeLast();
        case 's':
          final c = (int.tryParse(n.attr('c') ?? '') ?? 1).clamp(1, 200);
          _textRun(' ' * c, ctx, tp, collapse: false);
        case 'tab':
          if (!ctx.lastTab) _textRun('\u2003\u2003', ctx, tp, collapse: false);
          ctx.lastTab = true;
        case 'line-break':
          ctx.inlines.add(const DocBreak());
          ctx.space = true;
        case 'note':
          _note(n, ctx, tp, depth);
        case 'frame':
          _frame(n, ctx, depth);
        case 'ruby':
          final base = n.kid('ruby-base');
          if (base != null) _inline(base, ctx, tp, depth + 1);
        // Не текст: примечания, исправления, закладки, метки указателей,
        // скрытый текст, элементы форм.
        case 'annotation':
        case 'annotation-end':
        case 'change':
        case 'change-start':
        case 'change-end':
        case 'bookmark':
        case 'bookmark-start':
        case 'bookmark-end':
        case 'reference-mark':
        case 'reference-mark-start':
        case 'reference-mark-end':
        case 'toc-mark':
        case 'toc-mark-start':
        case 'toc-mark-end':
        case 'alphabetical-index-mark':
        case 'alphabetical-index-mark-start':
        case 'alphabetical-index-mark-end':
        case 'user-index-mark':
        case 'user-index-mark-start':
        case 'user-index-mark-end':
        case 'soft-page-break':
        case 'hidden-text':
        case 'hidden-paragraph':
        case 'control':
        case 'tracked-changes':
          break;
        default:
          if (_isShape(n)) {
            _shapeText(n, ctx, depth);
          } else {
            // Поля (дата, номер страницы, автор, перекрёстные ссылки …) и
            // прочие строчные элементы — их текст.
            _inline(n, ctx, tp, depth + 1);
          }
      }
    }
  }

  static bool _isShape(XmlElement n) {
    final prefix = n.name.prefix;
    if (prefix == 'draw' || prefix == 'dr3d') return true;
    if (prefix == 'text' || prefix == 'table' || prefix == 'office') return false;
    return (n.name.namespaceUri ?? '').contains(':drawing:');
  }

  void _textRun(String raw, _Ctx ctx, _TP tp, {required bool collapse}) {
    if (raw.isEmpty || (tp.hidden ?? false)) return;
    var t = raw;
    if (collapse) {
      // Пробелы ODF схлопываются: несколько подряд — один, в начале абзаца —
      // ни одного (явные пробелы — text:s).
      t = t.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
      if (ctx.space && t.startsWith(' ')) t = t.substring(1);
      if (t.isEmpty) return;
      ctx.space = t.endsWith(' ');
    } else {
      ctx.space = false;
    }
    if (tp.fontSymbol || t.contains(RegExp('[\uF020-\uF0FF]'))) t = DocHtml.symbols(t, tp.font);
    switch (tp.transform) {
      case 'uppercase':
        t = t.toUpperCase();
      case 'lowercase':
        t = t.toLowerCase();
    }
    final fit = budget.text(t);
    if (fit.isEmpty) return;
    ctx.inlines.add(DocText(fit, tp.docFont, ctx.href));
    if (raw.trim().isNotEmpty) ctx.lastTab = false;
  }

  void _note(XmlElement n, _Ctx ctx, _TP tp, int depth) {
    final citation = n.kid('note-citation');
    final mark = (citation?.attr('label') ?? citation?.innerText ?? '').trim();
    final sup = tp.over(_TP()..vert = DocVert.sup);
    if (mark.isNotEmpty) {
      final fit = budget.text(mark);
      if (fit.isNotEmpty) ctx.inlines.add(DocText(fit, sup.docFont, null));
    }
    final body = n.kid('note-body');
    if (body == null || budget.full || depth > OfficeLimits.maxDepth - 4) return;
    final target = n.attr('note-class') == 'endnote' ? end : foot;
    final saved = noteLead;
    noteLead = mark.isEmpty ? null : DocText(mark, const DocFont(vert: DocVert.sup));
    _blocks(body, depth + 1, target);
    noteLead = saved;
  }

  // ───────────────────────── рамки, картинки, фигуры ─────────────────────────

  static double? _px(String? v) {
    final pt = _len(v);
    if (pt == null || pt <= 0) return null;
    return (pt * 4 / 3).clamp(1, 4000).toDouble();
  }

  void _frame(XmlElement f, _Ctx ctx, int depth) {
    final w = _px(f.attr('width', ns: 'svg-compatible'));
    final h = _px(f.attr('height', ns: 'svg-compatible'));
    final alt = (f.kid('desc')?.innerText ?? f.kid('title')?.innerText ?? '').trim();
    var shown = false;
    for (final k in f.childElements) {
      if (k.local == 'image' && !shown) {
        final key = _image(k);
        if (key == null) continue;
        if (!budget.block()) return;
        ctx.inlines.add(DocPicture(key, width: w, height: h, alt: alt, href: ctx.href));
        shown = true;
      } else if (k.local == 'text-box') {
        ctx.after.addAll(_sub(k, depth));
      }
    }
  }

  /// Картинка draw:image: часть пакета (Pictures/…) или office:binary-data.
  String? _image(XmlElement img) {
    final href = img.attr('href');
    if (href != null && href.isNotEmpty) {
      final low = href.toLowerCase();
      // Внешние картинки не загружаются никогда.
      if (low.contains('://') || low.startsWith('data:') || low.startsWith('/')) return null;
      final name = OfficeZip.normalize(href);
      return images.add(name, () => zip.image(name));
    }
    final bin = img.kid('binary-data');
    if (bin == null) return null;
    final data = bin.innerText.replaceAll(RegExp(r'\s+'), '');
    if (data.isEmpty || data.length > OfficeLimits.maxImageBytes * 4 ~/ 3 + 4) return null;
    return images.add('binary:${data.hashCode}:${data.length}', () {
      if (binaryTotal + data.length * 3 ~/ 4 > OfficeLimits.maxImagesTotal) return null;
      try {
        final bytes = base64Decode(data);
        final mime = OfficeImage.sniff(bytes);
        if (mime == null) return null;
        binaryTotal += bytes.length;
        return OfficeImage(mime, bytes);
      } on FormatException {
        return null;
      }
    });
  }

  /// Текст фигуры (draw:custom-shape, draw:rect …) — абзацами после абзаца.
  void _shapeText(XmlElement shape, _Ctx ctx, int depth) {
    if (shape.local == 'frame') {
      _frame(shape, ctx, depth);
      return;
    }
    if (shape.local == 'a') {
      ctx.hrefs.add(DocHtml.safeHref(shape.attr('href')));
      for (final k in shape.childElements) {
        if (_isShape(k)) _shapeText(k, ctx, depth + 1);
      }
      ctx.hrefs.removeLast();
      return;
    }
    ctx.after.addAll(_sub(shape, depth));
  }

  /// Блоки внутри рамки или фигуры (абзацы, списки, таблицы, вложенные
  /// фигуры).
  List<DocBlock> _sub(XmlElement e, int depth) {
    final out = <DocBlock>[];
    if (depth > OfficeLimits.maxDepth - 2) return out;
    _blocks(e, depth + 1, out);
    return out;
  }

  // ───────────────────────── таблицы ─────────────────────────

  Iterable<XmlElement> _rows(XmlElement e, [int depth = 0]) sync* {
    if (depth > 8) return;
    for (final k in e.childElements) {
      switch (k.local) {
        case 'table-row':
          yield k;
        case 'table-rows':
        case 'table-header-rows':
        case 'table-row-group':
          yield* _rows(k, depth + 1);
      }
    }
  }

  Iterable<XmlElement> _columns(XmlElement e, [int depth = 0]) sync* {
    if (depth > 8) return;
    for (final k in e.childElements) {
      switch (k.local) {
        case 'table-column':
          yield k;
        case 'table-columns':
        case 'table-header-columns':
        case 'table-column-group':
          yield* _columns(k, depth + 1);
      }
    }
  }

  static const _maxCols = 64;

  DocTable? _table(XmlElement t, int depth) {
    if (depth > OfficeLimits.maxDepth) return null;
    final tStyle = styles['table:${t.attr('style-name')}']?.el.kid('table-properties');

    final cols = <double>[];
    for (final c in _columns(t)) {
      final rep = (int.tryParse(c.attr('number-columns-repeated') ?? '') ?? 1).clamp(1, _maxCols);
      final cp = styles['table-column:${c.attr('style-name')}']?.el.kid('table-column-properties');
      final rel = cp?.attr('rel-column-width');
      final w = rel != null ? double.tryParse(rel.replaceAll('*', '')) : _len(cp?.attr('column-width'));
      for (var i = 0; i < rep && cols.length < _maxCols; i++) {
        cols.add(w ?? 0);
      }
      if (cols.length >= _maxCols) break;
    }
    final relWidths = cols.isNotEmpty && cols.every((w) => w > 0);

    final rows = <DocRow>[];
    var gridCount = cols.length;
    for (final r in _rows(t)) {
      if (budget.full) break;
      final rep = (int.tryParse(r.attr('number-rows-repeated') ?? '') ?? 1).clamp(1, 50);
      for (var k = 0; k < rep; k++) {
        if (!budget.block()) break;
        final cells = <DocCell>[];
        var col = 0;
        for (final c in r.childElements) {
          if (budget.full || col >= _maxCols) break;
          final crep = (int.tryParse(c.attr('number-columns-repeated') ?? '') ?? 1).clamp(1, _maxCols);
          if (c.local == 'covered-table-cell') {
            col += crep;
            continue;
          }
          if (c.local != 'table-cell') continue;
          for (var j = 0; j < crep && col < _maxCols; j++) {
            if (!budget.block()) break;
            final span = (int.tryParse(c.attr('number-columns-spanned') ?? '') ?? 1).clamp(1, _maxCols);
            final rspan = (int.tryParse(c.attr('number-rows-spanned') ?? '') ?? 1).clamp(1, 10000);
            final cp = styles['table-cell:${c.attr('style-name')}']?.el.kid('table-cell-properties');
            final blocks = <DocBlock>[];
            _blocks(c, depth + 1, blocks);
            cells.add(_cell(blocks, cp, span, rspan));
            // Колонка — каждая ячейка строки, и обычная, и закрытая
            // объединением (table:covered-table-cell идёт следом за
            // объединённой).
            col++;
          }
        }
        if (col > gridCount) gridCount = col;
        rows.add(DocRow(cells));
      }
    }
    if (rows.isEmpty) return null;

    double? pct;
    final relW = tStyle?.attr('rel-width');
    final absW = _len(tStyle?.attr('width'));
    if (relW != null && relW.endsWith('%')) {
      pct = double.tryParse(relW.substring(0, relW.length - 1));
    } else if (absW != null && absW > 0) {
      pct = depth > 1 ? 100 : absW / pageWidth * 100;
    }
    if (pct != null && pct > 90) pct = 100;
    final align = switch (tStyle?.attr('align')) {
      'center' => 'center',
      'right' => 'right',
      _ => null,
    };
    return DocTable(
      rows,
      columns: relWidths && cols.length >= gridCount ? cols : const [],
      widthPct: pct,
      align: align,
    );
  }

  DocCell _cell(List<DocBlock> blocks, XmlElement? cp, int span, int rspan) {
    if (cp == null) return DocCell(blocks, colSpan: span, rowSpan: rspan, padding: const [0, 2.8, 0, 2.8]);
    final all = cp.attr('border');
    final pad = _len(cp.attr('padding'));
    double p(String side) => (_len(cp.attr('padding-$side')) ?? pad ?? 2.8).clamp(0, 36).toDouble();
    final va = cp.attr('vertical-align');
    return DocCell(
      blocks,
      colSpan: span,
      rowSpan: rspan,
      background: (_color(cp.attr('background-color')) ?? 0) == 0 ? null : _color(cp.attr('background-color')),
      borders: DocBorders(
        top: _border(cp.attr('border-top') ?? all),
        right: _border(cp.attr('border-right') ?? all),
        bottom: _border(cp.attr('border-bottom') ?? all),
        left: _border(cp.attr('border-left') ?? all),
      ),
      valign: va == 'middle' ? 1 : (va == 'bottom' ? 2 : 0),
      padding: [p('top'), p('right'), p('bottom'), p('left')],
    );
  }
}

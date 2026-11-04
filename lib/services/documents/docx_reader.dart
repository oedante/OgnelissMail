// lib/services/documents/docx_reader.dart
// Документ Word (DOCX, DOCM, DOTX) → HTML для просмотра вложения (1.11.x,
// предпросмотр документов, план владельца 04.11.2026). Формат — ECMA-376
// (WordprocessingML); элементы и атрибуты — по локальным именам (OfficeXml),
// поэтому читаются и «переходный», и «строгий» варианты.
//
// Что показывается: заголовки (стили «heading N», «Title», уровень
// структуры), оформление текста и абзацев (с цепочками стилей basedOn),
// списки Word с настоящими номерами («1.2.», «а)», маркеры Symbol/Wingdings),
// таблицы (объединённые ячейки, заливка, рамки, вложенные таблицы),
// картинки (DrawingML и VML), ссылки (связью и полем HYPERLINK), сноски и
// концевые сноски — под чертой в конце, надписи — их абзацы на месте,
// исправления — принятыми (вставленное видно, удалённое — нет).
// Не показываются: колонтитулы, примечания, фигуры без текста, диаграммы,
// EMF/WMF, условное оформление стилей таблиц (полосы, цвет строки
// заголовка из стиля), межстрочный интервал и позиции табуляции (табуляция —
// пробелом), поля страницы, колонки.

import 'package:xml/xml.dart';

import 'doc_html.dart';
import 'doc_xml.dart';
import 'office_document.dart';
import 'office_package.dart';

class DocxReader {
  DocxReader._();

  /// Разобрать документ. Ошибки — только [OfficeDocException].
  static OfficeTextDoc read(OfficeZip zip) {
    try {
      return _Docx(zip).run();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      // FormatException, RangeError, StateError … из чужого файла — это
      // повреждённый документ, а не сбой приложения.
      throw OfficeDocException(OfficeDocError.damaged, '$e');
    }
  }
}

/// Свойства текста (w:rPr): null — не задано на этом уровне.
class _RPr {
  bool? b, i, u, strike, caps, smallCaps, vanish;
  DocVert? vert;

  /// 0 — «авто» (цвет приложения).
  int? color;

  /// Маркер (w:highlight) и заливка (w:shd); 0 — нет.
  int? highlight, shade;
  double? size;
  String? font;

  _RPr();

  _RPr over(_RPr? o) {
    if (o == null) return this;
    return _RPr()
      ..b = o.b ?? b
      ..i = o.i ?? i
      ..u = o.u ?? u
      ..strike = o.strike ?? strike
      ..caps = o.caps ?? caps
      ..smallCaps = o.smallCaps ?? smallCaps
      ..vanish = o.vanish ?? vanish
      ..vert = o.vert ?? vert
      ..color = o.color ?? color
      ..highlight = o.highlight ?? highlight
      ..shade = o.shade ?? shade
      ..size = o.size ?? size
      ..font = o.font ?? font;
  }

  bool get mono {
    final f = (font ?? '').toLowerCase();
    return f.contains('courier') || f.contains('consolas') || f.contains('lucida console') || f.contains('mono');
  }

  DocFont get docFont {
    final hl = highlight ?? 0;
    final sh = shade ?? 0;
    return DocFont(
      bold: b ?? false,
      italic: i ?? false,
      underline: u ?? false,
      strike: strike ?? false,
      smallCaps: (smallCaps ?? false) && !(caps ?? false),
      mono: mono,
      vert: vert ?? DocVert.none,
      color: (color ?? 0) == 0 ? null : color,
      background: hl != 0 ? hl : (sh != 0 ? sh : null),
      size: size,
    );
  }
}

/// Свойства абзаца (w:pPr).
class _PPr {
  String? style;
  String? jc;
  double? left, right, first, before, after;
  bool? contextual, bidi, pageBreakBefore;
  int? shade;
  int? outline;
  String? numId;
  int? ilvl;
  DocLine? bTop, bBottom, bLeft, bRight;
  bool hasBorders = false;

  /// Свойства знака абзаца (w:pPr/w:rPr): размер пустой строки, номер.
  _RPr? mark;

  /// Раздел кончается этим абзацем (w:pPr/w:sectPr), не «непрерывный».
  bool sectionBreak = false;

  _PPr over(_PPr? o) {
    if (o == null) return this;
    final r = _PPr()
      ..style = o.style ?? style
      ..jc = o.jc ?? jc
      ..left = o.left ?? left
      ..right = o.right ?? right
      ..first = o.first ?? first
      ..before = o.before ?? before
      ..after = o.after ?? after
      ..contextual = o.contextual ?? contextual
      ..bidi = o.bidi ?? bidi
      ..pageBreakBefore = o.pageBreakBefore ?? pageBreakBefore
      ..shade = o.shade ?? shade
      ..outline = o.outline ?? outline
      ..numId = o.numId ?? numId
      ..ilvl = o.ilvl ?? ilvl
      ..mark = mark == null ? o.mark : mark!.over(o.mark)
      ..sectionBreak = o.sectionBreak;
    if (o.hasBorders) {
      r
        ..bTop = o.bTop
        ..bBottom = o.bBottom
        ..bLeft = o.bLeft
        ..bRight = o.bRight
        ..hasBorders = true;
    } else {
      r
        ..bTop = bTop
        ..bBottom = bBottom
        ..bLeft = bLeft
        ..bRight = bRight
        ..hasBorders = hasBorders;
    }
    return r;
  }
}

/// Рамки таблицы: края и внутренние линии; null — не задано на этом
/// уровне, [_none] — задано «без линии».
class _TblBorders {
  final Map<String, DocLine?> sides = {};
  _TblBorders over(_TblBorders? o) {
    final r = _TblBorders()..sides.addAll(sides);
    if (o != null) r.sides.addAll(o.sides);
    return r;
  }

  DocLine? side(String name) => sides[name];
}

class _Style {
  final String id;
  final String type;
  final String name;
  final String? basedOn;
  final _PPr? pPr;
  final _RPr? rPr;
  final _TblBorders? tblBorders;
  final List<double>? cellMargins;
  const _Style(this.id, this.type, this.name, this.basedOn, this.pPr, this.rPr, this.tblBorders, this.cellMargins);
}

class _Lvl {
  int start = 1;
  String fmt = 'decimal';
  String text = '';
  String suff = 'tab';
  bool legal = false;
  _PPr? pPr;
  _RPr? rPr;
}

class _Num {
  final String abstractId;
  final Map<int, int> startOverride;
  final Map<int, _Lvl> lvlOverride;
  _Num(this.abstractId, this.startOverride, this.lvlOverride);
}

/// Поле Word (w:fldChar begin … separate … end): пока идёт инструкция,
/// текст не показывается; в результате поля HYPERLINK — ссылка.
class _Field {
  final StringBuffer instr = StringBuffer();
  bool result = false;
  String? href;
}

/// Состояние абзаца при обходе: строчные элементы, ссылки, надписи и
/// разрывы страницы, которые выводятся до или после абзаца.
class _ParaCtx {
  final List<DocInline> inlines = [];
  final List<DocBlock> after = [];
  final List<String?> hrefs = [];
  final _RPr base;
  bool breakBefore = false;
  bool breakAfter = false;
  bool lastTab = false;
  _ParaCtx(this.base);

  String? get href {
    for (var i = hrefs.length - 1; i >= 0; i--) {
      if (hrefs[i] != null) return hrefs[i];
    }
    return null;
  }

  bool get visible => inlines.any((i) => i is DocPicture || (i is DocText && i.text.trim().isNotEmpty));
  int get produced => inlines.length + after.length;
}

class _Docx {
  _Docx(this.zip);

  final OfficeZip zip;
  final budget = DocBudget();
  final images = DocImages();
  late final String part;
  Map<String, OfficeRel> rels = const {};

  final styles = <String, _Style>{};
  String? defaultPara;
  String? defaultChar;
  String? defaultTable;
  _RPr defaultsR = _RPr();
  _PPr defaultsP = _PPr();

  final abstracts = <String, Map<int, _Lvl>>{};
  final abstractLinks = <String, String>{};
  final nums = <String, _Num>{};
  final counters = <String, List<int?>>{};
  final numsSeen = <String>{};

  /// Ширина текста страницы, twips (A4 с полями Word по умолчанию).
  double pageWidth = 9355;

  List<_Field> fields = [];

  /// Сноски: id → номер (по порядку ссылок в тексте).
  final footIds = <String, int>{};
  final endIds = <String, int>{};
  String? noteMark;

  OfficeTextDoc run() {
    final main = zip.officeDocumentPart() ?? zip.find('word/document.xml');
    if (main == null) throw const OfficeDocException(OfficeDocError.damaged, 'no main document part');
    part = main;
    rels = zip.rels(part);
    _loadStyles();
    _loadNumbering();

    final head = zip.readHead(part, OfficeLimits.maxPartBytes);
    if (head == null) throw const OfficeDocException(OfficeDocError.damaged, 'main part');
    final tree = DocXml.parse(
      OfficeZip.decodeText(head.bytes),
      blocks: const {'p', 'tc', 'tr'},
      keepBlank: (p) => p == 't' || p == 'instrText',
      stopDepth: 2,
      cutInput: head.truncated,
    );
    final body = tree.root.kid('body');
    if (tree.root.local != 'document' || body == null) {
      throw const OfficeDocException(OfficeDocError.damaged, 'not a WordprocessingML document');
    }
    final sect = body.kids('sectPr').lastOrNull;
    if (sect != null) _pageSize(sect);

    final blocks = _blocks(body, 0);
    final notes = <DocBlock>[];
    if (!budget.full && (footIds.isNotEmpty || endIds.isNotEmpty)) {
      _notes('footnotes', 'footnote', footIds, notes);
      _notes('endnotes', 'endnote', endIds, notes);
    }
    return DocHtml.render(blocks, notes: notes, images: images.map, truncated: budget.truncated || tree.cut);
  }

  // ───────────────────────── стили и списки ─────────────────────────

  String? _relPart(String kind, String fallback) {
    for (final r in rels.values) {
      if (!r.external && r.isType(kind) && zip.has(r.target)) return zip.find(r.target);
    }
    return zip.find(fallback);
  }

  /// Вспомогательная часть (стили, списки, сноски): испорченная — без неё.
  XmlElement? _aux(String kind, String fallback) {
    final name = _relPart(kind, fallback);
    if (name == null) return null;
    try {
      return zip.readXml(name)?.rootElement;
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.damaged) return null;
      rethrow;
    }
  }

  void _loadStyles() {
    final root = _aux('styles', 'word/styles.xml');
    if (root == null) return;
    final dd = root.kid('docDefaults');
    final rd = dd?.kid('rPrDefault')?.kid('rPr');
    final pd = dd?.kid('pPrDefault')?.kid('pPr');
    if (rd != null) defaultsR = _rPr(rd);
    if (pd != null) defaultsP = _pPr(pd);
    for (final s in root.kids('style')) {
      final id = s.attr('styleId');
      if (id == null || id.isEmpty) continue;
      final type = s.attr('type') ?? 'paragraph';
      final tblPr = s.kid('tblPr');
      final st = _Style(
        id,
        type,
        (s.kid('name')?.attr('val') ?? id).toLowerCase(),
        s.kid('basedOn')?.attr('val'),
        s.kid('pPr') == null ? null : _pPr(s.kid('pPr')!),
        s.kid('rPr') == null ? null : _rPr(s.kid('rPr')!),
        tblPr?.kid('tblBorders') == null ? null : _tblBorders(tblPr!.kid('tblBorders')!),
        tblPr?.kid('tblCellMar') == null ? null : _margins(tblPr!.kid('tblCellMar')!),
      );
      styles.putIfAbsent(id, () => st);
      if (_on(s.attr('default'))) {
        if (type == 'paragraph') defaultPara ??= id;
        if (type == 'character') defaultChar ??= id;
        if (type == 'table') defaultTable ??= id;
      }
    }
  }

  /// Цепочка стиля [id] от корня до него самого (basedOn), без циклов.
  List<_Style> _chain(String? id) {
    final out = <_Style>[];
    final seen = <String>{};
    var cur = id;
    while (cur != null && seen.add(cur) && out.length < 32) {
      final s = styles[cur];
      if (s == null) break;
      out.add(s);
      cur = s.basedOn;
    }
    return out.reversed.toList();
  }

  final _pCache = <String, (_PPr, _RPr)>{};
  final _rCache = <String, _RPr>{};

  (_PPr, _RPr) _paraStyle(String? id) {
    final key = id ?? '';
    return _pCache[key] ??= () {
      var p = _PPr();
      var r = _RPr();
      for (final s in _chain(id ?? defaultPara)) {
        p = p.over(s.pPr);
        r = r.over(s.rPr);
      }
      return (p, r);
    }();
  }

  _RPr _charStyle(String? id) {
    final key = id ?? '';
    return _rCache[key] ??= () {
      var r = _RPr();
      for (final s in _chain(id ?? defaultChar)) {
        r = r.over(s.rPr);
      }
      return r;
    }();
  }

  /// Стиль таблицы: (рамки, поля ячеек, свойства абзацев и текста).
  ({_TblBorders borders, List<double>? margins, _PPr pPr, _RPr rPr}) _tableStyle(String? id) {
    var b = _TblBorders();
    List<double>? m;
    var p = _PPr();
    var r = _RPr();
    for (final s in _chain(id ?? defaultTable)) {
      b = b.over(s.tblBorders);
      m = s.cellMargins ?? m;
      p = p.over(s.pPr);
      r = r.over(s.rPr);
    }
    return (borders: b, margins: m, pPr: p, rPr: r);
  }

  /// Уровень заголовка по стилю абзаца: «heading N», «Title»; 0 — не он.
  int _headingOf(String? styleId) {
    for (final s in _chain(styleId ?? defaultPara).reversed) {
      final m = RegExp(r'^heading\s*(\d)$').firstMatch(s.name);
      if (m != null) return int.parse(m.group(1)!).clamp(1, 6);
      if (s.name == 'title') return 1;
    }
    return 0;
  }

  void _loadNumbering() {
    final root = _aux('numbering', 'word/numbering.xml');
    if (root == null) return;
    for (final a in root.kids('abstractNum')) {
      final id = a.attr('abstractNumId');
      if (id == null) continue;
      final lvls = <int, _Lvl>{};
      for (final l in a.kids('lvl')) {
        final i = int.tryParse(l.attr('ilvl') ?? '');
        if (i == null || i < 0 || i > 8) continue;
        lvls[i] = _lvl(l);
      }
      abstracts[id] = lvls;
      final link = a.kid('numStyleLink')?.attr('val');
      if (link != null) abstractLinks[id] = link;
    }
    for (final n in root.kids('num')) {
      final id = n.attr('numId');
      final abs = n.kid('abstractNumId')?.attr('val');
      if (id == null || abs == null) continue;
      final so = <int, int>{};
      final lo = <int, _Lvl>{};
      for (final o in n.kids('lvlOverride')) {
        final i = int.tryParse(o.attr('ilvl') ?? '');
        if (i == null || i < 0 || i > 8) continue;
        final s = int.tryParse(o.kid('startOverride')?.attr('val') ?? '');
        if (s != null) so[i] = s;
        final l = o.kid('lvl');
        if (l != null) lo[i] = _lvl(l);
      }
      nums[id] = _Num(abs, so, lo);
    }
  }

  _Lvl _lvl(XmlElement l) {
    final v = _Lvl()
      ..start = int.tryParse(l.kid('start')?.attr('val') ?? '') ?? 1
      ..fmt = l.kid('numFmt')?.attr('val') ?? 'decimal'
      ..text = l.kid('lvlText')?.attr('val') ?? ''
      ..suff = l.kid('suff')?.attr('val') ?? 'tab'
      ..legal = l.kid('isLgl') != null && _on(l.kid('isLgl')!.attr('val'));
    if (l.kid('pPr') != null) v.pPr = _pPr(l.kid('pPr')!);
    if (l.kid('rPr') != null) v.rPr = _rPr(l.kid('rPr')!);
    return v;
  }

  /// Определение списка [numId]: (ключ счётчиков, уровни, переопределения).
  ({String key, Map<int, _Lvl> lvls, _Num num})? _list(String? numId) {
    if (numId == null || numId == '0') return null;
    final n = nums[numId];
    if (n == null) return null;
    var abs = n.abstractId;
    // Список по стилю нумерации (numStyleLink): определение — у списка,
    // на который ссылается стиль.
    for (var hop = 0; hop < 4 && abstracts[abs]?.isEmpty != false && abstractLinks.containsKey(abs); hop++) {
      final st = styles[abstractLinks[abs]!];
      final linked = nums[st?.pPr?.numId ?? ''];
      if (linked == null) break;
      abs = linked.abstractId;
    }
    final lvls = abstracts[abs];
    if (lvls == null) return null;
    return (key: abs, lvls: lvls, num: n);
  }

  /// Номер пункта: текст метки и оформление уровня; null — не пункт.
  ({String text, _Lvl lvl})? _label(String? numId, int ilvl) {
    final l = _list(numId);
    if (l == null) return null;
    final lv = ilvl.clamp(0, 8);
    _Lvl? level(int i) => l.num.lvlOverride[i] ?? l.lvls[i];
    final cur = level(lv);
    if (cur == null) return null;
    final c = counters.putIfAbsent(l.key, () => List<int?>.filled(9, null));
    if (numsSeen.add(numId!) && l.num.startOverride.isNotEmpty) {
      // Первый пункт списка с «начать заново с N»: счётчики этого уровня
      // и глубже — сначала.
      for (final e in l.num.startOverride.entries) {
        c[e.key] = e.value - 1;
        for (var d = e.key + 1; d < 9; d++) {
          c[d] = null;
        }
      }
    }
    c[lv] = c[lv] == null ? cur.start : c[lv]! + 1;
    for (var d = lv + 1; d < 9; d++) {
      c[d] = null;
    }
    if (cur.fmt == 'bullet') return (text: DocHtml.bullet(cur.text, cur.rPr?.font), lvl: cur);
    if (cur.fmt == 'none') return (text: cur.text.replaceAll(RegExp(r'%\d'), ''), lvl: cur);
    final text = cur.text.replaceAllMapped(RegExp(r'%([1-9])'), (m) {
      final k = int.parse(m.group(1)!) - 1;
      final lk = level(k);
      final n = c[k] ?? lk?.start ?? 1;
      final fmt = cur.legal ? 'decimal' : (lk?.fmt ?? 'decimal');
      return DocNumbers.format(n, fmt);
    });
    return (text: text, lvl: cur);
  }

  // ───────────────────────── свойства ─────────────────────────

  static bool _on(String? v) {
    if (v == null) return true;
    final s = v.toLowerCase();
    return !(s == '0' || s == 'false' || s == 'off' || s == 'none');
  }

  /// Значение в twips: число или «2.5cm», «12pt», «1in» (строгий OOXML).
  static double? _twips(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*(mm|cm|in|pt|pc|pi)?\s*$').firstMatch(v);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    return switch (m.group(2)) {
      'mm' => n * 1440 / 25.4,
      'cm' => n * 1440 / 2.54,
      'in' => n * 1440,
      'pt' => n * 20,
      'pc' || 'pi' => n * 240,
      _ => n,
    };
  }

  static double? _pt(String? v) {
    final t = _twips(v);
    return t == null ? null : t / 20;
  }

  /// Цвет «RRGGBB»; «auto» — 0.
  static int? _color(String? v) {
    if (v == null) return null;
    if (v.toLowerCase() == 'auto') return 0;
    return DocHtml.parseHex(v);
  }

  _RPr _rPr(XmlElement e) {
    final r = _RPr();
    for (final k in e.childElements) {
      final val = k.attr('val');
      switch (k.local) {
        case 'b':
          r.b = _on(val);
        case 'i':
          r.i = _on(val);
        case 'u':
          r.u = val != null && val.toLowerCase() != 'none';
        case 'strike':
        case 'dstrike':
          r.strike = _on(val);
        case 'caps':
          r.caps = _on(val);
        case 'smallCaps':
          r.smallCaps = _on(val);
        case 'vanish':
          r.vanish = _on(val);
        case 'vertAlign':
          r.vert = switch (val) {
            'superscript' => DocVert.sup,
            'subscript' => DocVert.sub,
            _ => DocVert.none,
          };
        case 'color':
          r.color = _color(val);
        case 'sz':
          final hp = double.tryParse(val ?? '');
          // Половины пункта; разумные пределы — от 1 до 400 pt.
          if (hp != null && hp >= 2 && hp <= 800) r.size = hp / 2;
        case 'highlight':
          r.highlight = val == null || val == 'none' ? 0 : (DocHtml.highlight[val] ?? 0);
        case 'shd':
          final fill = _color(k.attr('fill'));
          r.shade = fill ?? 0;
        case 'rFonts':
          r.font = k.attr('ascii') ?? k.attr('hAnsi') ?? r.font;
      }
    }
    return r;
  }

  DocLine? _line(XmlElement? b) {
    if (b == null) return null;
    final v = (b.attr('val') ?? 'single').toLowerCase();
    if (v == 'nil' || v == 'none') return null;
    final sz = double.tryParse(b.attr('sz') ?? '') ?? 4;
    final c = _color(b.attr('color'));
    final style = switch (v) {
      'double' || 'triple' || 'thinthicksmallgap' || 'thickthinsmallgap' => 'double',
      'dotted' => 'dotted',
      'dashed' || 'dashsmallgap' || 'dotdash' || 'dotdotdash' || 'dashdotstroked' => 'dashed',
      _ => 'solid',
    };
    final w = v == 'thick' ? 1.5 : sz / 8;
    return DocLine(width: w, style: style, color: c == 0 ? null : c);
  }

  _TblBorders _tblBorders(XmlElement e) {
    final b = _TblBorders();
    for (final k in e.childElements) {
      final name = switch (k.local) {
        'start' => 'left',
        'end' => 'right',
        final n => n,
      };
      b.sides[name] = _line(k);
    }
    return b;
  }

  /// Поля ячеек (w:tblCellMar, w:tcMar), pt: сверху, справа, снизу, слева.
  List<double>? _margins(XmlElement e, [List<double>? base]) {
    final out = List<double>.of(base ?? const [0, 5.4, 0, 5.4]);
    var any = false;
    for (final k in e.childElements) {
      final w = _pt(k.attr('w'));
      if (w == null || w < 0) continue;
      final i = switch (k.local) {
        'top' => 0,
        'right' || 'end' => 1,
        'bottom' => 2,
        'left' || 'start' => 3,
        _ => -1,
      };
      if (i < 0) continue;
      out[i] = w.clamp(0, 36).toDouble();
      any = true;
    }
    return any ? out : base;
  }

  _PPr _pPr(XmlElement e) {
    final p = _PPr();
    for (final k in e.childElements) {
      switch (k.local) {
        case 'pStyle':
          p.style = k.attr('val');
        case 'jc':
          p.jc = k.attr('val');
        case 'ind':
          p.left = _pt(k.attr('left') ?? k.attr('start')) ?? p.left;
          p.right = _pt(k.attr('right') ?? k.attr('end')) ?? p.right;
          final hanging = _pt(k.attr('hanging'));
          final first = _pt(k.attr('firstLine'));
          if (hanging != null) {
            p.first = -hanging;
          } else if (first != null) {
            p.first = first;
          }
        case 'spacing':
          p.before = _pt(k.attr('before')) ?? p.before;
          p.after = _pt(k.attr('after')) ?? p.after;
          // «Авто» (абзацы из HTML) — 14 pt, как у Word.
          if (_on(k.attr('beforeAutospacing') ?? '0')) p.before = 14;
          if (_on(k.attr('afterAutospacing') ?? '0')) p.after = 14;
        case 'contextualSpacing':
          p.contextual = _on(k.attr('val'));
        case 'bidi':
          p.bidi = _on(k.attr('val'));
        case 'pageBreakBefore':
          p.pageBreakBefore = _on(k.attr('val'));
        case 'shd':
          p.shade = _color(k.attr('fill')) ?? 0;
        case 'outlineLvl':
          p.outline = int.tryParse(k.attr('val') ?? '');
        case 'numPr':
          p.numId = k.kid('numId')?.attr('val') ?? p.numId;
          p.ilvl = int.tryParse(k.kid('ilvl')?.attr('val') ?? '') ?? p.ilvl;
        case 'pBdr':
          p.hasBorders = true;
          p.bTop = _line(k.kid('top'));
          p.bBottom = _line(k.kid('bottom'));
          p.bLeft = _line(k.kid('left') ?? k.kid('start'));
          p.bRight = _line(k.kid('right') ?? k.kid('end'));
        case 'rPr':
          p.mark = _rPr(k);
        case 'sectPr':
          final type = k.kid('type')?.attr('val') ?? 'nextPage';
          p.sectionBreak = type != 'continuous';
      }
    }
    return p;
  }

  void _pageSize(XmlElement sect) {
    final w = _twips(sect.kid('pgSz')?.attr('w'));
    final mar = sect.kid('pgMar');
    final l = _twips(mar?.attr('left')) ?? 1701;
    final r = _twips(mar?.attr('right')) ?? 850;
    if (w != null && w - l - r > 1440) pageWidth = w - l - r;
  }

  // ───────────────────────── блоки ─────────────────────────

  /// Дочерние блоки [e]: абзацы, таблицы, элементы управления содержимым.
  List<DocBlock> _blocks(XmlElement e, int depth, {_TableStyle? table}) {
    final out = <DocBlock>[];
    _collect(e, depth, out, table);
    return out;
  }

  void _collect(XmlElement e, int depth, List<DocBlock> out, _TableStyle? table) {
    if (depth > OfficeLimits.maxDepth) return;
    final kids = e.childElements.toList();
    for (var i = 0; i < kids.length; i++) {
      if (budget.full) return;
      final k = kids[i];
      switch (k.local) {
        case 'p':
          _paragraph(k, out, depth, table, prev: _prevPara(kids, i), next: _nextPara(kids, i));
        case 'tbl':
          final t = _table(k, depth + 1);
          if (t != null) out.add(t);
        case 'sdt':
          final c = k.kid('sdtContent');
          if (c != null) _collect(c, depth + 1, out, table);
        case 'customXml':
        case 'ins':
        case 'moveTo':
          _collect(k, depth + 1, out, table);
        case 'AlternateContent':
          final before = out.length;
          final choice = k.kid('Choice');
          if (choice != null) _collect(choice, depth + 1, out, table);
          final fb = k.kid('Fallback');
          if (out.length == before && fb != null) _collect(fb, depth + 1, out, table);
      }
    }
  }

  /// Стиль соседнего абзаца — для «не добавлять интервал между абзацами
  /// одного стиля» (contextualSpacing).
  String? _styleOfPara(XmlElement p) => p.kid('pPr')?.kid('pStyle')?.attr('val') ?? defaultPara;

  String? _prevPara(List<XmlElement> kids, int i) =>
      i > 0 && kids[i - 1].local == 'p' ? _styleOfPara(kids[i - 1]) : null;
  String? _nextPara(List<XmlElement> kids, int i) =>
      i + 1 < kids.length && kids[i + 1].local == 'p' ? _styleOfPara(kids[i + 1]) : null;

  void _paragraph(XmlElement p, List<DocBlock> out, int depth, _TableStyle? table, {String? prev, String? next}) {
    if (!budget.block()) return;
    final direct = p.kid('pPr') == null ? _PPr() : _pPr(p.kid('pPr')!);
    final styleId = direct.style ?? defaultPara;
    final (sp, sr) = _paraStyle(styleId);
    var pp = defaultsP.over(table?.pPr).over(sp);
    final numId = direct.numId ?? sp.numId;
    final ilvl = direct.ilvl ?? sp.ilvl ?? 0;
    final label = _label(numId, ilvl);
    if (label != null) pp = pp.over(label.lvl.pPr);
    pp = pp.over(direct);
    final runBase = defaultsR.over(table?.rPr).over(sr);
    final markR = runBase.over(direct.mark);

    var heading = _headingOf(styleId);
    if (heading == 0 && pp.outline != null && pp.outline! >= 0 && pp.outline! < 6) heading = pp.outline! + 1;

    var before = pp.before ?? 0;
    var after = pp.after ?? 0;
    if (pp.contextual ?? false) {
      if (prev != null && prev == styleId) before = 0;
      if (next != null && next == styleId) after = 0;
    }
    final jc = switch (pp.jc) {
      'center' => 'center',
      'right' || 'end' => 'right',
      'both' || 'distribute' || 'mediumKashida' || 'highKashida' || 'lowKashida' || 'thaiDistribute' => 'justify',
      _ => null,
    };
    final style = DocParaStyle(
      heading: heading,
      align: jc,
      before: before.clamp(0, 144).toDouble(),
      after: after.clamp(0, 144).toDouble(),
      left: (pp.left ?? 0).clamp(-144, 1440).toDouble(),
      right: (pp.right ?? 0).clamp(-144, 1440).toDouble(),
      firstLine: (pp.first ?? 0).clamp(-720, 720).toDouble(),
      background: (pp.shade ?? 0) == 0 ? null : pp.shade,
      borders: pp.hasBorders
          ? DocBorders(top: pp.bTop, right: pp.bRight, bottom: pp.bBottom, left: pp.bLeft)
          : DocBorders.none,
      rtl: pp.bidi ?? false,
      size: markR.size,
    );

    final ctx = _ParaCtx(runBase);
    _inline(p, ctx, depth);

    DocText? labelText;
    if (label != null && label.text.isNotEmpty) {
      // Номер — оформлением знака абзаца и уровня списка (жирный номер у
      // жирного заголовка), без подчёркивания и зачёркивания текста.
      final lf = markR.over(label.lvl.rPr);
      var t = label.text;
      if (lf.caps ?? false) t = t.toUpperCase();
      final f = lf.docFont;
      final font = DocFont(bold: f.bold, italic: f.italic, color: f.color, size: f.size);
      if (label.lvl.suff == 'tab') {
        labelText = DocText(t, font);
      } else {
        ctx.inlines.insert(0, DocText(label.lvl.suff == 'space' ? '$t ' : t, font));
      }
    }

    if (ctx.breakBefore || (pp.pageBreakBefore ?? false)) out.add(const DocRule());
    final onlyBreak = (ctx.breakBefore || ctx.breakAfter) && !ctx.visible && labelText == null;
    if (!onlyBreak) out.add(DocPara(style, ctx.inlines, label: labelText));
    out.addAll(ctx.after);
    if (ctx.breakAfter || direct.sectionBreak) out.add(const DocRule());
  }

  // ───────────────────────── текст абзаца ─────────────────────────

  bool get _hidden => fields.any((f) => !f.result);

  String? _fieldHref() {
    for (var i = fields.length - 1; i >= 0; i--) {
      if (fields[i].href != null) return fields[i].href;
    }
    return null;
  }

  void _inline(XmlElement e, _ParaCtx ctx, int depth) {
    if (depth > OfficeLimits.maxDepth) return;
    for (final k in e.childElements) {
      if (budget.full) return;
      switch (k.local) {
        case 'r':
          _run(k, ctx, depth);
        case 'hyperlink':
          final id = k.attr('id', ns: 'relationships');
          final rel = id == null ? null : rels[id];
          ctx.hrefs.add(rel != null && rel.external ? DocHtml.safeHref(rel.target) : null);
          _inline(k, ctx, depth + 1);
          ctx.hrefs.removeLast();
        case 'fldSimple':
          final f = _Field()
            ..result = true
            ..href = DocHtml.fieldLink(k.attr('instr') ?? '');
          fields.add(f);
          _inline(k, ctx, depth + 1);
          fields.remove(f);
        case 'ins':
        case 'moveTo':
        case 'smartTag':
        case 'customXml':
        case 'dir':
        case 'bdo':
          _inline(k, ctx, depth + 1);
        case 'sdt':
          final c = k.kid('sdtContent');
          if (c != null) _inline(c, ctx, depth + 1);
        case 'AlternateContent':
          _alternate(k, ctx, depth);
        case 'oMath':
        case 'oMathPara':
          // Формула — её текст строкой (знаки m:t по порядку).
          if (_hidden) break;
          final t = StringBuffer();
          for (final d in k.descendantElements) {
            if (d.local == 't') t.write(d.innerText);
          }
          _text(t.toString(), ctx, ctx.base.over(_RPr()..i = true));
      }
    }
  }

  void _alternate(XmlElement k, _ParaCtx ctx, int depth) {
    final before = ctx.produced;
    final choice = k.kid('Choice');
    if (choice != null) _inline(choice, ctx, depth + 1);
    final fb = k.kid('Fallback');
    if (ctx.produced == before && fb != null) _inline(fb, ctx, depth + 1);
  }

  void _run(XmlElement r, _ParaCtx ctx, int depth) {
    final rprEl = r.kid('rPr');
    final direct = rprEl == null ? null : _rPr(rprEl);
    final rStyle = rprEl?.kid('rStyle')?.attr('val');
    final rp = ctx.base.over(_charStyle(rStyle)).over(direct);
    final hiddenRun = rp.vanish ?? false;
    for (final k in r.childElements) {
      if (budget.full) return;
      switch (k.local) {
        case 'fldChar':
          switch (k.attr('fldCharType')) {
            case 'begin':
              if (fields.length < OfficeLimits.maxDepth) fields.add(_Field());
            case 'separate':
              if (fields.isNotEmpty) {
                final f = fields.last;
                f.result = true;
                f.href = DocHtml.fieldLink(f.instr.toString());
              }
            case 'end':
              if (fields.isNotEmpty) fields.removeLast();
          }
          continue;
        case 'instrText':
          if (fields.isNotEmpty && !fields.last.result && fields.last.instr.length < 4096) {
            fields.last.instr.write(k.innerText);
          }
          continue;
      }
      if (_hidden || hiddenRun) continue;
      switch (k.local) {
        case 't':
          _text(k.innerText, ctx, rp);
        case 'tab':
        case 'ptab':
          _tab(ctx, rp);
        case 'br':
          final type = k.attr('type');
          if (type == 'page') {
            if (ctx.visible) {
              ctx.breakAfter = true;
            } else {
              ctx.breakBefore = true;
            }
          } else {
            ctx.inlines.add(const DocBreak());
            ctx.lastTab = false;
          }
        case 'cr':
          ctx.inlines.add(const DocBreak());
        case 'noBreakHyphen':
          _text('\u2011', ctx, rp);
        case 'softHyphen':
          _text('\u00AD', ctx, rp);
        case 'sym':
          final code = int.tryParse(k.attr('char') ?? '', radix: 16);
          if (code == null || code <= 0 || code > 0x10FFFF) break;
          final c = code >= 0xF000 && code <= 0xF0FF ? code - 0xF000 : code;
          _text(DocHtml.symbols(String.fromCharCode(c), k.attr('font')), ctx, rp.over(_RPr())..font = null);
        case 'footnoteReference':
        case 'endnoteReference':
          final id = k.attr('id');
          if (id == null || _on(k.attr('customMarkFollows') ?? '0')) break;
          final foot = k.local == 'footnoteReference';
          final map = foot ? footIds : endIds;
          final n = map[id] ??= map.length + 1;
          _text(foot ? '$n' : DocNumbers.roman(n).toLowerCase(), ctx, rp.over(_RPr()..vert = DocVert.sup));
        case 'footnoteRef':
        case 'endnoteRef':
          if (noteMark != null) _text(noteMark!, ctx, rp.over(_RPr()..vert = DocVert.sup));
        case 'drawing':
          _drawing(k, ctx, depth);
        case 'pict':
        case 'object':
          _vml(k, ctx, depth);
        case 'AlternateContent':
          final before = ctx.produced;
          final choice = k.kid('Choice');
          if (choice != null) _runContent(choice, ctx, rp, depth);
          final fb = k.kid('Fallback');
          if (ctx.produced == before && fb != null) _runContent(fb, ctx, rp, depth);
        case 'ruby':
          final base = k.kid('rubyBase');
          if (base != null) _inline(base, ctx, depth + 1);
      }
    }
  }

  /// Содержимое mc:Choice / mc:Fallback внутри фрагмента: картинки и надписи.
  void _runContent(XmlElement e, _ParaCtx ctx, _RPr rp, int depth) {
    for (final k in e.childElements) {
      switch (k.local) {
        case 'drawing':
          _drawing(k, ctx, depth);
        case 'pict':
        case 'object':
          _vml(k, ctx, depth);
        case 't':
          _text(k.innerText, ctx, rp);
      }
    }
  }

  void _text(String raw, _ParaCtx ctx, _RPr rp) {
    if (raw.isEmpty) return;
    var t = DocHtml.symbols(raw, rp.font);
    if (rp.caps ?? false) t = t.toUpperCase();
    final fit = budget.text(t);
    if (fit.isEmpty) return;
    ctx.inlines.add(DocText(fit, rp.docFont, ctx.href ?? _fieldHref()));
    ctx.lastTab = false;
  }

  /// Табуляция — пробелом шириной в две буквы; несколько подряд (так в
  /// Word выравнивают дату вправо) — одним промежутком, иначе на телефоне
  /// строка уезжала бы на следующую.
  void _tab(_ParaCtx ctx, _RPr rp) {
    if (ctx.lastTab) return;
    _text('\u2003\u2003', ctx, rp);
    ctx.lastTab = true;
  }

  // ───────────────────────── картинки и надписи ─────────────────────────

  String? _imageKey(String? relId) {
    if (relId == null) return null;
    final rel = rels[relId];
    if (rel == null || rel.external) return null;
    return images.add(rel.target, () => zip.image(rel.target));
  }

  static double? _emuPx(String? v) {
    final n = double.tryParse(v ?? '');
    if (n == null || n <= 0) return null;
    return (n / 9525).clamp(1, 4000).toDouble();
  }

  void _drawing(XmlElement d, _ParaCtx ctx, int depth) {
    for (final holder in d.childElements) {
      if (holder.local != 'inline' && holder.local != 'anchor') continue;
      final doc = holder.kid('docPr');
      if (doc != null && _on(doc.attr('hidden') ?? '0')) continue;
      final alt = doc?.attr('descr') ?? doc?.attr('title') ?? '';
      final ext = holder.kid('extent');
      final w = _emuPx(ext?.attr('cx'));
      final h = _emuPx(ext?.attr('cy'));
      final graphic = holder.kid('graphic')?.kid('graphicData');
      if (graphic == null) continue;
      final pics = <XmlElement>[];
      final boxes = <XmlElement>[];
      void find(XmlElement e, int dd) {
        if (dd > OfficeLimits.maxDepth) return;
        for (final k in e.childElements) {
          if (k.local == 'blip') {
            pics.add(k);
          } else if (k.local == 'txbxContent') {
            boxes.add(k);
          } else {
            find(k, dd + 1);
          }
        }
      }

      find(graphic, 0);
      for (final b in pics) {
        final key = _imageKey(b.attr('embed', ns: 'relationships'));
        if (key == null) continue;
        // В группе картинок у каждой свой размер (a:ext); одна — по wp:extent.
        double? pw = w, ph = h;
        if (pics.length > 1) {
          final xfrm = b.parentElement?.parentElement?.kid('spPr')?.kid('xfrm')?.kid('ext');
          pw = _emuPx(xfrm?.attr('cx')) ?? w;
          ph = _emuPx(xfrm?.attr('cy')) ?? h;
        }
        if (!budget.block()) return;
        ctx.inlines.add(DocPicture(key, width: pw, height: ph, alt: alt, href: ctx.href ?? _fieldHref()));
      }
      for (final box in boxes) {
        _textBox(box, ctx, depth);
      }
    }
  }

  void _vml(XmlElement v, _ParaCtx ctx, int depth) {
    void walk(XmlElement e, int dd, String style) {
      if (dd > OfficeLimits.maxDepth) return;
      for (final k in e.childElements) {
        final st = k.attr('style') ?? style;
        if (k.local == 'imagedata') {
          final key = _imageKey(k.attr('id', ns: 'relationships') ?? k.attr('relid'));
          if (key == null) continue;
          if (!budget.block()) return;
          ctx.inlines.add(
            DocPicture(key, width: _cssPx(st, 'width'), height: _cssPx(st, 'height'), alt: k.attr('title') ?? ''),
          );
        } else if (k.local == 'txbxContent') {
          _textBox(k, ctx, depth);
        } else {
          walk(k, dd + 1, st);
        }
      }
    }

    walk(v, 0, '');
  }

  /// Размер из стиля фигуры VML («width:120pt;height:3cm») в px.
  static double? _cssPx(String style, String prop) {
    final m = RegExp('(?:^|;)\\s*$prop\\s*:\\s*(-?\\d+(?:\\.\\d+)?)(pt|px|in|cm|mm)?').firstMatch(style);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    final px = switch (m.group(2)) {
      'pt' => n * 4 / 3,
      'in' => n * 96,
      'cm' => n * 96 / 2.54,
      'mm' => n * 96 / 25.4,
      _ => n,
    };
    return px <= 0 ? null : px.clamp(1, 4000).toDouble();
  }

  /// Надпись: её абзацы — сразу после абзаца, в котором она стоит.
  void _textBox(XmlElement box, _ParaCtx ctx, int depth) {
    final saved = fields;
    fields = [];
    try {
      ctx.after.addAll(_blocks(box, depth + 1));
    } finally {
      fields = saved;
    }
  }

  // ───────────────────────── таблицы ─────────────────────────

  DocTable? _table(XmlElement tbl, int depth) {
    if (depth > OfficeLimits.maxDepth) return null;
    final pr = tbl.kid('tblPr');
    final ts = _tableStyle(pr?.kid('tblStyle')?.attr('val'));
    final borders = ts.borders.over(pr?.kid('tblBorders') == null ? null : _tblBorders(pr!.kid('tblBorders')!));
    final margins = pr?.kid('tblCellMar') == null
        ? (ts.margins ?? const [0, 5.4, 0, 5.4])
        : (_margins(pr!.kid('tblCellMar')!, ts.margins) ?? const [0, 5.4, 0, 5.4]);
    final content = _TableStyle(ts.pPr, ts.rPr);

    final grid = <double>[];
    for (final g in tbl.kid('tblGrid')?.kids('gridCol') ?? const <XmlElement>[]) {
      if (grid.length >= 64) break;
      grid.add((_twips(g.attr('w')) ?? 0).clamp(0, 31680).toDouble());
    }

    final rows = <List<_CellB>>[];
    final open = <int, _CellB>{};
    var gridCount = grid.length;
    for (final tr in _flatten(tbl, 'tr')) {
      if (budget.full || !budget.block()) break;
      var col = int.tryParse(tr.kid('trPr')?.kid('gridBefore')?.attr('val') ?? '')?.clamp(0, 63) ?? 0;
      final row = <_CellB>[];
      if (col > 0) row.add(_CellB(const [], 0, col, margins)..empty = true);
      for (final tc in _flatten(tr, 'tc')) {
        if (budget.full) break;
        final tcPr = tc.kid('tcPr');
        final span = (int.tryParse(tcPr?.kid('gridSpan')?.attr('val') ?? '') ?? 1).clamp(1, 64);
        final vm = tcPr?.kid('vMerge');
        final vmVal = vm?.attr('val');
        final hm = tcPr?.kid('hMerge')?.attr('val');
        if (hm != null && hm != 'restart' && row.isNotEmpty) {
          // Старое горизонтальное объединение: ячейка — продолжение левой.
          row.last.span += span;
          col += span;
          continue;
        }
        if (vm != null && vmVal != 'restart' && open[col] != null) {
          final top = open[col]!;
          top.rowSpan++;
          col += span;
          continue;
        }
        if (!budget.block()) break;
        final cell =
            _CellB(
                _blocks(tc, depth + 1, table: content),
                col,
                span,
                tcPr?.kid('tcMar') == null ? margins : (_margins(tcPr!.kid('tcMar')!, margins) ?? margins),
              )
              ..row = rows.length
              ..fill = _color(tcPr?.kid('shd')?.attr('fill'))
              ..valign = switch (tcPr?.kid('vAlign')?.attr('val')) {
                'center' => 1,
                'bottom' => 2,
                _ => 0,
              }
              ..own = tcPr?.kid('tcBorders') == null ? null : _tblBorders(tcPr!.kid('tcBorders')!);
        for (var j = col; j < col + span; j++) {
          open.remove(j);
        }
        if (vm != null && vmVal == 'restart') open[col] = cell;
        row.add(cell);
        col += span;
      }
      if (col > gridCount) gridCount = col;
      rows.add(row);
    }
    if (rows.isEmpty) return null;

    final last = rows.length - 1;
    DocCell cellOf(_CellB c) {
      if (c.empty) return DocCell(const [], colSpan: c.span, padding: c.margins);
      DocLine? side(String own, String edge, String inside, bool atEdge) {
        final o = c.own?.sides;
        if (o != null && o.containsKey(own)) return o[own];
        return borders.side(atEdge ? edge : inside);
      }

      return DocCell(
        c.blocks,
        colSpan: c.span,
        rowSpan: c.rowSpan,
        background: (c.fill ?? 0) == 0 ? null : c.fill,
        valign: c.valign,
        padding: c.margins,
        borders: DocBorders(
          top: side('top', 'top', 'insideH', c.row == 0),
          bottom: side('bottom', 'bottom', 'insideH', c.row + c.rowSpan - 1 >= last),
          left: side('left', 'left', 'insideV', c.col == 0),
          right: side('right', 'right', 'insideV', c.col + c.span >= gridCount),
        ),
      );
    }

    final gridSum = grid.fold<double>(0, (a, b) => a + b);
    double? widthPct;
    final tblW = pr?.kid('tblW');
    final wType = tblW?.attr('type');
    final wVal = tblW?.attr('w') ?? '';
    if (wType == 'pct') {
      widthPct = wVal.endsWith('%')
          ? double.tryParse(wVal.substring(0, wVal.length - 1))
          : (double.tryParse(wVal) ?? 0) / 50;
    } else if (wType == 'dxa' && (_twips(wVal) ?? 0) > 0) {
      widthPct = _twips(wVal)! / pageWidth * 100;
    } else if (gridSum > 0) {
      widthPct = gridSum / pageWidth * 100;
    }
    // Вложенная таблица — по ширине ячейки; почти во всю страницу — во
    // всю ширину окна.
    if (depth > 1 && wType != 'pct') widthPct = 100;
    if (widthPct != null && (widthPct <= 0 || widthPct.isNaN)) widthPct = null;
    if (widthPct != null && widthPct > 90) widthPct = 100;

    return DocTable(
      [
        for (final r in rows) DocRow([for (final c in r) cellOf(c)]),
      ],
      columns: grid.length >= gridCount ? grid : const [],
      widthPct: widthPct,
      align: switch (pr?.kid('jc')?.attr('val')) {
        'center' => 'center',
        'right' || 'end' => 'right',
        _ => null,
      },
    );
  }

  /// Строки (ячейки) таблицы, в том числе внутри элементов управления
  /// содержимым и пользовательского XML.
  Iterable<XmlElement> _flatten(XmlElement e, String local, [int depth = 0]) sync* {
    if (depth > 8) return;
    for (final k in e.childElements) {
      if (k.local == local) {
        yield k;
      } else if (k.local == 'sdt') {
        final c = k.kid('sdtContent');
        if (c != null) yield* _flatten(c, local, depth + 1);
      } else if (k.local == 'customXml' || k.local == 'ins' || k.local == 'moveTo') {
        yield* _flatten(k, local, depth + 1);
      }
    }
  }

  // ───────────────────────── сноски ─────────────────────────

  void _notes(String kind, String tag, Map<String, int> ids, List<DocBlock> out) {
    if (ids.isEmpty || budget.full) return;
    final root = _aux(kind, 'word/$kind.xml');
    if (root == null) return;
    final byId = <String, XmlElement>{};
    for (final n in root.kids(tag)) {
      final id = n.attr('id');
      final type = n.attr('type');
      if (id == null || (type != null && type != 'normal')) continue;
      byId[id] = n;
    }
    final order = ids.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    for (final e in order) {
      final n = byId[e.key];
      if (n == null || budget.full) continue;
      noteMark = tag == 'footnote' ? '${e.value}' : DocNumbers.roman(e.value).toLowerCase();
      fields = [];
      out.addAll(_blocks(n, 1));
    }
    noteMark = null;
  }
}

/// Оформление абзацев таблицы из её стиля.
class _TableStyle {
  final _PPr pPr;
  final _RPr rPr;
  const _TableStyle(this.pPr, this.rPr);
}

class _CellB {
  _CellB(this.blocks, this.col, this.span, this.margins);
  final List<DocBlock> blocks;
  final int col;
  int span;
  final List<double> margins;
  int row = 0;
  int rowSpan = 1;
  int? fill;
  int valign = 0;
  _TblBorders? own;
  bool empty = false;
}

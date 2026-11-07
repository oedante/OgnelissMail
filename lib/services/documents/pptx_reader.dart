// lib/services/documents/pptx_reader.dart
// PPTX (PowerPoint 2007+, ECMA-376 PresentationML + DrawingML) → слайды
// [OfficeSlidesDoc] (1.11.x, предпросмотр документов, план владельца
// 04.11.2026).
//
// Как PowerPoint собирает слайд и что из этого здесь повторено:
//  · presentation.xml — размер (sldSz, EMU: 12 700 в пункте) и порядок
//    слайдов (sldIdLst); скрытые (show="0") не показываются;
//  · слайд → макет → образец → тема (по связям _rels). Заполнитель (p:ph)
//    без своей рамки берёт её у заполнителя макета (по idx, потом по типу),
//    а тот — у образца;
//  · оформление текста наследуется: фрагмент ← абзац ← список стилей
//    фигуры ← заполнитель макета ← заполнитель образца ← стили образца
//    (titleStyle / bodyStyle / otherStyle) ← defaultTextStyle презентации;
//  · цвета — srgbClr, schemeClr (через clrMap образца: tx1 → dk1 …), sysClr,
//    prstClr и поправки lumMod/lumOff/tint/shade/alpha;
//  · фигуры образца и макета (не заполнители) рисуются под фигурами слайда.
// Диаграммы (графики) не рисуются — на их месте плашка; SmartArt — по
// сохранённому рисунку (ppt/diagrams/drawing*.xml), если он есть. Заметки
// докладчика (1.15.1) — текст заполнителя body страницы заметок (связь
// notesSlide слайда). Анимация и переходы не читаются.
//
// Всё в файле — чужое: части читаются только через OfficeZip (пределы
// распакованного), вложенность групп — не глубже OfficeLimits.maxDepth,
// счётчики и размеры из файла не превращаются в выделение памяти. Испорченный
// слайд, макет, тема или картинка пропускаются — остальное показывается.

import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'doc_slides.dart';
import 'office_package.dart';

class PptxReader {
  PptxReader._();

  /// Абзацев в одной надписи или ячейке — не больше (дальше — [OfficeSlidesDoc.truncated]).
  static const maxParagraphs = 400;

  /// Знаков в одном фрагменте текста.
  static const maxRunChars = 8000;

  /// Строк и столбцов таблицы.
  static const maxTableRows = 200;
  static const maxTableCols = 60;

  /// Разобрать презентацию. Ошибка — только [OfficeDocException].
  static OfficeSlidesDoc read(OfficeZip zip) {
    try {
      return _Pptx(zip).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      // XmlException, FormatException, RangeError, StateError… — файл испорчен.
      throw OfficeDocException(OfficeDocError.damaged, '$e');
    }
  }
}

const _emuPerPt = 12700.0;

double _pt(num emu) => emu / _emuPerPt;

int? _int(String? s) => s == null ? null : int.tryParse(s.trim());

double? _num(String? s) => s == null ? null : double.tryParse(s.trim());

bool? _bool(String? s) {
  if (s == null) return null;
  final v = s.trim().toLowerCase();
  if (v == '1' || v == 'true' || v == 'on') return true;
  if (v == '0' || v == 'false' || v == 'off') return false;
  return null;
}

/// Тема: цвета, шрифты, заготовки заливок и линий (для p:style и bgRef).
class _Theme {
  final Map<String, int> colors;
  final String major, minor;
  final List<XmlElement> fills, lines, bgFills;
  const _Theme(this.colors, this.major, this.minor, this.fills, this.lines, this.bgFills);

  /// Тема Office 2007 — если своей нет или она испорчена.
  static const fallback = _Theme(
    {
      'dk1': 0xFF000000,
      'lt1': 0xFFFFFFFF,
      'dk2': 0xFF1F497D,
      'lt2': 0xFFEEECE1,
      'accent1': 0xFF4F81BD,
      'accent2': 0xFFC0504D,
      'accent3': 0xFF9BBB59,
      'accent4': 0xFF8064A2,
      'accent5': 0xFF4BACC6,
      'accent6': 0xFFF79646,
      'hlink': 0xFF0000FF,
      'folHlink': 0xFF800080,
    },
    'Calibri',
    'Calibri',
    [],
    [],
    [],
  );
}

/// Часть (слайд, макет, образец, рисунок SmartArt) и её связи: картинки и
/// ссылки фигуры ищутся в связях той части, где фигура записана.
class _Src {
  final String part;
  final Map<String, OfficeRel> rels;

  /// Образец или макет: их заполнители не рисуются.
  final bool template;
  const _Src(this.part, this.rels, {this.template = false});
}

class _Master {
  final _Src src;
  final XmlElement root;
  final _Theme theme;
  final Map<String, String> clrMap;
  final List<XmlElement> phs;
  const _Master(this.src, this.root, this.theme, this.clrMap, this.phs);

  XmlElement? txStyle(String name) => root.kid('txStyles')?.kid(name);
}

class _Layout {
  final _Src src;
  final XmlElement root;
  final _Master? master;
  final List<XmlElement> phs;
  const _Layout(this.src, this.root, this.master, this.phs);
}

/// Аффинное преобразование: координаты части (EMU) → пункты слайда.
class _Xf {
  final double a, b, c, d, e, f;
  const _Xf(this.a, this.b, this.c, this.d, this.e, this.f);

  static const root = _Xf(1 / _emuPerPt, 0, 0, 1 / _emuPerPt, 0, 0);

  double x(double px, double py) => a * px + c * py + e;
  double y(double px, double py) => b * px + d * py + f;

  /// Сначала [inner], потом это.
  _Xf after(_Xf inner) => _Xf(
    a * inner.a + c * inner.b,
    b * inner.a + d * inner.b,
    a * inner.c + c * inner.d,
    b * inner.c + d * inner.d,
    a * inner.e + c * inner.f + e,
    b * inner.e + d * inner.f + f,
  );
}

/// Рамка a:xfrm в EMU.
class _Box {
  final double x, y, w, h, rot;
  final bool flipH, flipV;
  const _Box(this.x, this.y, this.w, this.h, {this.rot = 0, this.flipH = false, this.flipV = false});

  static _Box? of(XmlElement? xfrm) {
    if (xfrm == null) return null;
    final off = xfrm.kid('off');
    final ext = xfrm.kid('ext');
    if (off == null || ext == null) return null;
    double v(XmlElement e, String n) => (_num(e.attr(n)) ?? 0).clamp(-2e10, 2e10).toDouble();
    return _Box(
      v(off, 'x'),
      v(off, 'y'),
      v(ext, 'cx').abs(),
      v(ext, 'cy').abs(),
      rot: ((_num(xfrm.attr('rot')) ?? 0) / 60000) % 360,
      flipH: _bool(xfrm.attr('flipH')) ?? false,
      flipV: _bool(xfrm.attr('flipV')) ?? false,
    );
  }
}

/// Источники оформления текста одной фигуры по порядку наследования.
class _TextStyles {
  /// Списки стилей (a:lstStyle, p:titleStyle …): фигура, заполнитель макета,
  /// заполнитель образца, стиль образца, стиль презентации.
  final List<XmlElement?> before;
  final List<XmlElement?> after;

  /// Цвет и шрифт из p:style/a:fontRef — между своими стилями фигуры и
  /// унаследованными (так PowerPoint делает белый текст на фигурах темы).
  final XmlElement? fontRef;

  const _TextStyles(this.before, this.after, this.fontRef);
}

class _Pptx {
  _Pptx(this.zip);

  final OfficeZip zip;
  bool _truncated = false;
  final Map<String, XmlDocument?> _xml = {};
  final Map<String, OfficeImage?> _images = {};
  final Map<String, _Master?> _masters = {};
  final Map<String, _Layout?> _layouts = {};
  final Map<String, _Theme> _themes = {};
  final Map<String, List<DocShape>> _templateShapes = {};
  XmlElement? _defaultStyle;
  XmlElement? _tableStyles;

  OfficeSlidesDoc read() {
    final presPart = zip.officeDocumentPart() ?? (zip.has('ppt/presentation.xml') ? 'ppt/presentation.xml' : null);
    if (presPart == null) throw const OfficeDocException(OfficeDocError.damaged, 'no presentation');
    final pres = zip.readXml(presPart)?.rootElement;
    if (pres == null || pres.local != 'presentation') {
      throw const OfficeDocException(OfficeDocError.damaged, 'presentation.xml');
    }
    final sz = pres.kid('sldSz');
    var w = _pt(_num(sz?.attr('cx')) ?? 9144000);
    var h = _pt(_num(sz?.attr('cy')) ?? 6858000);
    // Неправдоподобный размер — 4:3 по умолчанию (иначе слайд в точку или
    // в километр).
    if (!(w >= 36 && w <= 20000) || !(h >= 36 && h <= 20000)) {
      w = 720;
      h = 540;
    }
    _defaultStyle = pres.kid('defaultTextStyle');
    final presRels = zip.rels(presPart);
    for (final r in presRels.values) {
      if (!r.external && r.isType('tableStyles')) {
        _tableStyles = _doc(r.target)?.rootElement;
      }
    }

    final slides = <DocSlide>[];
    for (final id in pres.kid('sldIdLst')?.kids('sldId') ?? const <XmlElement>[]) {
      final rel = presRels[id.attr('id', ns: 'relationships') ?? ''];
      if (rel == null || rel.external) continue;
      if (slides.length >= OfficeSlidesDoc.maxSlides) {
        _truncated = true;
        break;
      }
      try {
        final s = _slide(rel.target);
        if (s != null) slides.add(s);
      } on OfficeDocException catch (e) {
        // Испорченный слайд — без него; слишком большой — без него, но с
        // пометкой «показано не всё».
        if (e.kind == OfficeDocError.tooLarge) _truncated = true;
        if (e.kind == OfficeDocError.encrypted || e.kind == OfficeDocError.unsupported) rethrow;
      } catch (_) {
        // Слайд, который не разобрался (неожиданное содержимое), — без него.
      }
    }
    return OfficeSlidesDoc(width: w, height: h, slides: slides, truncated: _truncated);
  }

  /// Часть как XML, один раз; испорченная или отсутствующая — null.
  XmlDocument? _doc(String part) {
    if (_xml.containsKey(part)) return _xml[part];
    XmlDocument? d;
    try {
      d = zip.readXml(part);
    } on OfficeDocException catch (e) {
      if (e.kind != OfficeDocError.damaged) rethrow;
    }
    return _xml[part] = d;
  }

  OfficeImage? _image(String part) => _images.putIfAbsent(part, () => zip.image(part));

  // ───────────────────────── образец, макет, тема ─────────────────────────

  _Theme _theme(String part) => _themes.putIfAbsent(part, () {
    final root = _doc(part)?.rootElement;
    final el = root?.kid('themeElements');
    if (el == null) return _Theme.fallback;
    final colors = Map<String, int>.of(_Theme.fallback.colors);
    for (final c in el.kid('clrScheme')?.childElements ?? const <XmlElement>[]) {
      final v = _baseColor(c.childElements.firstOrNull, const {}, null);
      if (v != null) colors[c.local] = v;
    }
    String font(String kind) =>
        el.kid('fontScheme')?.kid(kind)?.kid('latin')?.attr('typeface') ?? _Theme.fallback.minor;
    final fmt = el.kid('fmtScheme');
    List<XmlElement> list(String n) => fmt?.kid(n)?.childElements.toList() ?? const [];
    return _Theme(
      colors,
      font('majorFont'),
      font('minorFont'),
      list('fillStyleLst'),
      list('lnStyleLst'),
      list('bgFillStyleLst'),
    );
  });

  static List<XmlElement> _placeholders(XmlElement root) => [
    for (final e in root.kid('cSld')?.kid('spTree')?.childElements ?? const <XmlElement>[])
      if (_ph(e) != null) e,
  ];

  static XmlElement? _ph(XmlElement shape) {
    for (final nv in shape.childElements) {
      if (nv.local.startsWith('nv')) return nv.kid('nvPr')?.kid('ph');
    }
    return null;
  }

  _Master? _master(String part) {
    if (_masters.containsKey(part)) return _masters[part];
    final root = _doc(part)?.rootElement;
    if (root == null) return _masters[part] = null;
    final rels = zip.rels(part);
    var theme = _Theme.fallback;
    for (final r in rels.values) {
      if (!r.external && r.isType('theme')) theme = _theme(r.target);
    }
    final clrMap = <String, String>{
      for (final a in root.kid('clrMap')?.attributes ?? const <XmlAttribute>[]) a.name.local: a.value,
    };
    return _masters[part] = _Master(_Src(part, rels, template: true), root, theme, clrMap, _placeholders(root));
  }

  _Layout? _layout(String part) {
    if (_layouts.containsKey(part)) return _layouts[part];
    final root = _doc(part)?.rootElement;
    if (root == null) return _layouts[part] = null;
    final rels = zip.rels(part);
    _Master? master;
    for (final r in rels.values) {
      if (!r.external && r.isType('slideMaster')) master = _master(r.target);
    }
    return _layouts[part] = _Layout(_Src(part, rels, template: true), root, master, _placeholders(root));
  }

  // ───────────────────────────────── слайд ─────────────────────────────────

  DocSlide? _slide(String part) {
    final doc = zip.readXml(part);
    final root = doc?.rootElement;
    if (root == null || root.local != 'sld') return null;
    if (_bool(root.attr('show')) == false) return null;
    final rels = zip.rels(part);
    _Layout? layout;
    var notes = '';
    for (final r in rels.values) {
      if (r.external) continue;
      if (r.isType('slideLayout')) layout = _layout(r.target);
      if (r.isType('notesSlide')) notes = _notes(r.target);
    }
    final master = layout?.master;
    final theme = master?.theme ?? _Theme.fallback;
    // Своя таблица цветов слайда (clrMapOvr) — редко, но бывает.
    var clrMap = master?.clrMap ?? const <String, String>{};
    final over =
        root.kid('clrMapOvr')?.kid('overrideClrMapping') ?? layout?.root.kid('clrMapOvr')?.kid('overrideClrMapping');
    if (over != null) clrMap = {for (final a in over.attributes) a.name.local: a.value};
    final ctx = _Ctx(this, theme, clrMap, master, layout);
    final src = _Src(part, rels);

    // Фон: слайд, иначе макет, иначе образец.
    DocFill? bg;
    for (final (el, s) in [
      (root, src),
      if (layout != null) (layout.root, layout.src),
      if (master != null) (master.root, master.src),
    ]) {
      final b = el.kid('cSld')?.kid('bg');
      if (b == null) continue;
      bg = ctx.background(b, s);
      break;
    }

    final shapes = <DocShape>[];
    // Фигуры образца и макета — под фигурами слайда, если их не скрыли.
    final showMaster = _bool(root.attr('showMasterSp')) ?? true;
    if (showMaster && layout != null) {
      final key = '${layout.src.part}|${over == null ? '' : over.toXmlString()}';
      final cached = _templateShapes[key];
      if (cached != null) {
        shapes.addAll(cached);
      } else {
        final t = <DocShape>[];
        if (master != null && (_bool(layout.root.attr('showMasterSp')) ?? true)) {
          ctx.tree(master.root.kid('cSld')?.kid('spTree'), master.src, _Xf.root, t, 0);
        }
        ctx.tree(layout.root.kid('cSld')?.kid('spTree'), layout.src, _Xf.root, t, 0);
        _templateShapes[key] = t;
        shapes.addAll(t);
      }
    }
    ctx.tree(root.kid('cSld')?.kid('spTree'), src, _Xf.root, shapes, 0);
    if (shapes.length > OfficeSlidesDoc.maxShapes) {
      shapes.removeRange(OfficeSlidesDoc.maxShapes, shapes.length);
      _truncated = true;
    }
    return DocSlide(background: bg, shapes: shapes, notes: notes);
  }

  /// Текст заметок докладчика: заполнитель body страницы заметок.
  String _notes(String part) {
    final XmlElement? root;
    try {
      root = zip.readXml(part)?.rootElement;
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.tooLarge) _truncated = true;
      return '';
    }
    final tree = root?.kid('cSld')?.kid('spTree');
    if (tree == null) return '';
    final out = StringBuffer();
    void walk(XmlElement g, int depth) {
      if (depth > OfficeLimits.maxDepth) return;
      for (final e in g.childElements) {
        if (out.length > DocSlide.maxNotes) return;
        if (e.local == 'grpSp') {
          walk(e, depth + 1);
        } else if (e.local == 'sp' && e.kid('nvSpPr')?.kid('nvPr')?.kid('ph')?.attr('type') == 'body') {
          for (final p in e.kid('txBody')?.kids('p') ?? const <XmlElement>[]) {
            if (out.isNotEmpty) out.write('\n');
            for (final r in p.childElements) {
              if (r.local == 'br') {
                out.write('\n');
              } else if (r.local == 'r' || r.local == 'fld') {
                out.write(r.kid('t')?.innerText ?? '');
              }
            }
          }
        }
      }
    }

    walk(tree, 0);
    return DocSlide.cleanNotes(out.toString());
  }
}

/// Разбор одного слайда: тема, таблица цветов, макет и образец.
class _Ctx {
  _Ctx(this.r, this.theme, this.clrMap, this.master, this.layout);

  final _Pptx r;
  final _Theme theme;
  final Map<String, String> clrMap;
  final _Master? master;
  final _Layout? layout;

  // ─────────────────────────────── цвета ───────────────────────────────

  /// Цвет из элемента-держателя (solidFill, a:fontRef, buClr …): первый
  /// дочерний элемент цвета; [ph] — цвет вместо phClr (заготовки темы).
  int? color(XmlElement? holder, {int? ph}) {
    if (holder == null) return null;
    for (final c in holder.childElements) {
      final v = _baseColor(c, clrMap, theme, ph: ph);
      if (v != null) return v;
    }
    return null;
  }

  /// Цвет темы по имени схемы (tx1, hlink …) через таблицу цветов.
  int? scheme(String name) =>
      _baseColor(XmlElement(XmlName('schemeClr'), [XmlAttribute(XmlName('val'), name)]), clrMap, theme);

  // ─────────────────────────────── заливки ───────────────────────────────

  /// Заливка из элемента со свойствами (spPr, bgPr, tcPr, заготовка темы):
  /// set — заливка задана (noFill — задана и пустая).
  ({bool set, DocFill? fill}) fill(XmlElement? props, _Src src, {int? ph}) {
    if (props == null) return (set: false, fill: null);
    for (final e in props.childElements) {
      switch (e.local) {
        case 'noFill':
          return (set: true, fill: null);
        case 'solidFill':
          final c = color(e, ph: ph);
          return (set: true, fill: c == null ? null : DocFill.solid(c));
        case 'gradFill':
          return (set: true, fill: _gradient(e, ph));
        case 'pattFill':
          // Узор — цветом переднего плана, смешанным с фоном пополам.
          final fg = color(e.kid('fgClr'), ph: ph) ?? 0xFF000000;
          final bg = color(e.kid('bgClr'), ph: ph) ?? 0xFFFFFFFF;
          return (set: true, fill: DocFill.solid(_mix(fg, bg, 0.5)));
        case 'blipFill':
          final img = _blip(e, src);
          if (img == null) return (set: true, fill: null);
          final tile = e.kid('tile');
          return (
            set: true,
            fill: DocFill.picture(
              img,
              tile: tile != null,
              tileScale: tile == null ? 1 : ((_num(tile.attr('sx')) ?? 100000) / 100000).abs(),
            ),
          );
        case 'grpFill':
          return (set: true, fill: null);
      }
    }
    return (set: false, fill: null);
  }

  DocFill? _gradient(XmlElement g, int? ph) {
    final stops = <(double, int)>[];
    for (final gs in g.kid('gsLst')?.kids('gs') ?? const <XmlElement>[]) {
      final c = color(gs, ph: ph);
      if (c == null) continue;
      stops.add((((_num(gs.attr('pos')) ?? 0) / 100000).clamp(0.0, 1.0), c));
      if (stops.length >= 16) break;
    }
    if (stops.isEmpty) return null;
    if (stops.length == 1) return DocFill.solid(stops.first.$2);
    stops.sort((a, b) => a.$1.compareTo(b.$1));
    final lin = g.kid('lin');
    final path = g.kid('path');
    return DocFill.gradient(
      [for (final s in stops) s.$2],
      [for (final s in stops) s.$1],
      gradientAngle: (_num(lin?.attr('ang')) ?? 0) / 60000,
      radial: path != null,
    );
  }

  OfficeImage? _blip(XmlElement blipFill, _Src src) {
    final id = blipFill.kid('blip')?.attr('embed', ns: 'relationships');
    final rel = src.rels[id ?? ''];
    if (rel == null || rel.external) return null;
    return r._image(rel.target);
  }

  DocFill? background(XmlElement bg, _Src src) {
    final pr = bg.kid('bgPr');
    if (pr != null) return fill(pr, src).fill;
    final ref = bg.kid('bgRef');
    if (ref != null) return _styleFill(_int(ref.attr('idx')) ?? 0, color(ref), src);
    return null;
  }

  /// Заливка по номеру из темы: 1…999 — fillStyleLst, 1001… — bgFillStyleLst.
  DocFill? _styleFill(int idx, int? ph, _Src src) {
    XmlElement? e;
    if (idx >= 1001 && idx - 1001 < theme.bgFills.length) e = theme.bgFills[idx - 1001];
    if (idx >= 1 && idx <= 999 && idx - 1 < theme.fills.length) e = theme.fills[idx - 1];
    if (e == null) return idx == 0 || ph == null ? null : DocFill.solid(ph);
    final holder = XmlElement(XmlName('x'), const [], [e.copy()]);
    // Картинки заготовок темы — в связях темы; их почти не бывает, без них.
    return fill(holder, src, ph: ph).fill;
  }

  /// Линия из a:ln; [ref] — p:style/a:lnRef, если своей заливки линии нет.
  ({bool set, DocLine? line}) line(XmlElement? ln, XmlElement? ref, {bool arrows = false}) {
    XmlElement? styleLn;
    int? refColor;
    if (ref != null) {
      final idx = _int(ref.attr('idx')) ?? 0;
      refColor = color(ref);
      if (idx >= 1 && idx - 1 < theme.lines.length) styleLn = theme.lines[idx - 1];
      if (idx == 0 && ln == null) return (set: true, line: null);
    }
    if (ln == null && styleLn == null) return (set: false, line: null);
    int? c;
    var set = false;
    var none = false;
    for (final src in [ln, styleLn]) {
      if (src == null || set) continue;
      for (final e in src.childElements) {
        if (e.local == 'noFill') {
          none = true;
          set = true;
        } else if (e.local == 'solidFill') {
          c = color(e, ph: refColor);
          set = true;
        } else if (e.local == 'gradFill') {
          c = _gradient(e, refColor)?.flatColor;
          set = true;
        } else if (e.local == 'pattFill') {
          c = color(e.kid('fgClr'), ph: refColor);
          set = true;
        }
        if (set) break;
      }
    }
    if (!set) return (set: false, line: null);
    if (none || c == null) return (set: true, line: null);
    final w = _num(ln?.attr('w')) ?? _num(styleLn?.attr('w')) ?? 9525;
    final dashVal = (ln?.kid('prstDash') ?? styleLn?.kid('prstDash'))?.attr('val') ?? 'solid';
    final dash = switch (dashVal) {
      'solid' => DocDash.solid,
      'dot' || 'sysDot' => DocDash.dot,
      'dashDot' || 'lgDashDot' || 'lgDashDotDot' || 'sysDashDot' || 'sysDashDotDot' => DocDash.dashDot,
      _ => DocDash.dash,
    };
    bool arrow(String n) {
      final t = (ln?.kid(n) ?? styleLn?.kid(n))?.attr('type');
      return t != null && t != 'none';
    }

    return (
      set: true,
      line: DocLine(c, _pt(w).clamp(0.0, 200.0), dash: dash, headArrow: arrow('headEnd'), tailArrow: arrow('tailEnd')),
    );
  }

  // ─────────────────────────────── фигуры ───────────────────────────────

  /// Фигуры дерева (spTree, grpSp, mc:Choice …) — в [out].
  void tree(XmlElement? parent, _Src src, _Xf xf, List<DocShape> out, int depth) {
    if (parent == null) return;
    if (depth > OfficeLimits.maxDepth) {
      r._truncated = true;
      return;
    }
    for (final e in parent.childElements) {
      if (out.length > OfficeSlidesDoc.maxShapes) {
        r._truncated = true;
        return;
      }
      try {
        switch (e.local) {
          case 'sp':
            _sp(e, src, xf, out);
          case 'cxnSp':
            _sp(e, src, xf, out, connector: true);
          case 'pic':
            _pic(e, src, xf, out);
          case 'graphicFrame':
            _frame(e, src, xf, out, depth);
          case 'grpSp':
            _group(e, src, xf, out, depth);
          case 'AlternateContent':
            // Новое содержимое (mc:Choice) или запасное (mc:Fallback): одно из
            // двух. Запасное — когда в нём картинка (уравнения, значки SVG).
            final choice = e.kid('Choice');
            final fallback = e.kid('Fallback');
            final usable = fallback != null && fallback.descendant('pic') != null ? fallback : (choice ?? fallback);
            tree(usable, src, xf, out, depth + 1);
        }
      } on OfficeDocException catch (ex) {
        if (ex.kind != OfficeDocError.damaged) rethrow;
      } catch (_) {
        // Испорченная фигура — без неё, остальной слайд показывается.
      }
    }
  }

  bool _hidden(XmlElement shape) {
    for (final nv in shape.childElements) {
      if (nv.local.startsWith('nv')) {
        for (final c in nv.childElements) {
          if (c.local == 'cNvPr') return _bool(c.attr('hidden')) ?? false;
        }
      }
    }
    return false;
  }

  /// Заполнители макета и образца, от которых наследует фигура слайда.
  (XmlElement?, XmlElement?) _inherited(XmlElement ph) {
    final l = _find(layout?.phs, ph);
    final m = _find(master?.phs, l != null ? (_Pptx._ph(l) ?? ph) : ph, master: true);
    return (l, m);
  }

  static String _normType(String t) => switch (t) {
    'ctrTitle' => 'title',
    'subTitle' || 'obj' || 'body' => 'body',
    _ => t,
  };

  /// Заполнитель из [list]: по idx, потом по типу (у образца — только по типу).
  XmlElement? _find(List<XmlElement>? list, XmlElement ph, {bool master = false}) {
    if (list == null || list.isEmpty) return null;
    final type = ph.attr('type') ?? 'obj';
    final idx = ph.attr('idx');
    if (!master && idx != null) {
      for (final s in list) {
        if (_Pptx._ph(s)?.attr('idx') == idx) return s;
      }
    }
    for (final s in list) {
      if ((_Pptx._ph(s)?.attr('type') ?? 'obj') == type) return s;
    }
    final norm = _normType(type);
    for (final s in list) {
      if (_normType(_Pptx._ph(s)?.attr('type') ?? 'obj') == norm) return s;
    }
    return null;
  }

  /// Готовая фигура в координатах слайда.
  DocShape? _place(
    _Xf xf,
    _Box b, {
    DocGeom geom = DocGeom.rect,
    double? adjust,
    DocPath? path,
    DocFill? fill,
    DocLine? line,
    DocPicture? picture,
    DocTextBody? text,
    DocTable? table,
    DocEmbed? embed,
  }) {
    final cx = b.x + b.w / 2;
    final cy = b.y + b.h / 2;
    final rad = b.rot * math.pi / 180;
    final cosR = math.cos(rad), sinR = math.sin(rad);
    final sh = b.flipH ? -1.0 : 1.0, sv = b.flipV ? -1.0 : 1.0;
    // Оси фигуры после поворота и отражения, затем — преобразование группы.
    final ux0 = sh * cosR, uy0 = sh * sinR;
    final vx0 = -sv * sinR, vy0 = sv * cosR;
    final ux = xf.a * ux0 + xf.c * uy0, uy = xf.b * ux0 + xf.d * uy0;
    final vx = xf.a * vx0 + xf.c * vy0, vy = xf.b * vx0 + xf.d * vy0;
    final lu = math.sqrt(ux * ux + uy * uy), lv = math.sqrt(vx * vx + vy * vy);
    final w = b.w * lu, h = b.h * lv;
    final det = ux * vy - uy * vx;
    final flip = det < 0;
    var angle = (flip ? math.atan2(-uy, -ux) : math.atan2(uy, ux)) * 180 / math.pi;
    if (angle.abs() < 1e-6) angle = 0;
    final px = xf.x(cx, cy), py = xf.y(cx, cy);
    if (!px.isFinite || !py.isFinite || !w.isFinite || !h.isFinite) return null;
    return DocShape(
      x: px - w / 2,
      y: py - h / 2,
      w: w,
      h: h,
      rotation: angle,
      flipH: flip,
      geom: geom,
      adjust: adjust,
      path: path,
      fill: fill,
      line: line,
      picture: picture,
      text: text,
      table: table,
      embed: embed,
    );
  }

  void _sp(XmlElement sp, _Src src, _Xf xf, List<DocShape> out, {bool connector = false}) {
    if (_hidden(sp)) return;
    final ph = _Pptx._ph(sp);
    if (ph != null && src.template) return;
    XmlElement? lph, mph;
    if (ph != null) (lph, mph) = _inherited(ph);
    final spPr = sp.kid('spPr');
    final lPr = lph?.kid('spPr'), mPr = mph?.kid('spPr');
    final box = _Box.of(spPr?.kid('xfrm')) ?? _Box.of(lPr?.kid('xfrm')) ?? _Box.of(mPr?.kid('xfrm'));
    if (box == null) return;
    final style = sp.kid('style');

    // Форма: своя, иначе — заполнителя.
    final geomEl = [
      spPr,
      lPr,
      mPr,
    ].firstWhere((p) => p?.kid('prstGeom') != null || p?.kid('custGeom') != null, orElse: () => null);
    final (geom, adjust, path) = _geometry(geomEl, box, connector: connector);

    // Заливка: своя → заполнителя → p:style.
    DocFill? fill;
    var fillSet = false;
    for (final p in [spPr, lPr, mPr]) {
      final f = this.fill(p, src);
      if (f.set) {
        fill = f.fill;
        fillSet = true;
        break;
      }
    }
    if (!fillSet && style != null && geom != DocGeom.line && !connector) {
      final ref = style.kid('fillRef');
      fill = _styleFill(_int(ref?.attr('idx')) ?? 0, color(ref), src);
    }
    if (path != null && !path.filled) fill = null;

    // Линия: своя → заполнителя → p:style.
    DocLine? line;
    var lineSet = false;
    for (final p in [spPr, lPr, mPr]) {
      final ln = p?.kid('ln');
      if (ln == null) continue;
      final l = this.line(ln, p == spPr ? style?.kid('lnRef') : null);
      if (l.set) {
        line = l.line;
        lineSet = true;
        break;
      }
    }
    if (!lineSet && style != null) line = this.line(null, style.kid('lnRef')).line;

    DocTextBody? text;
    final tx = sp.kid('txBody');
    if (tx != null) {
      final type = ph?.attr('type') ?? (ph != null ? 'obj' : null);
      final master = this.master;
      XmlElement? txStyle;
      if (type == null) {
        txStyle = master?.txStyle('otherStyle');
      } else if (type == 'title' || type == 'ctrTitle') {
        txStyle = master?.txStyle('titleStyle');
      } else if (type == 'dt' || type == 'ftr' || type == 'sldNum' || type == 'hdr') {
        txStyle = master?.txStyle('otherStyle');
      } else {
        txStyle = master?.txStyle('bodyStyle');
      }
      final styles = _TextStyles(
        [tx.kid('lstStyle')],
        [lph?.kid('txBody')?.kid('lstStyle'), mph?.kid('txBody')?.kid('lstStyle'), txStyle, r._defaultStyle],
        style?.kid('fontRef'),
      );
      text = _text(
        tx,
        styles,
        src,
        inheritedBody: [lph?.kid('txBody')?.kid('bodyPr'), mph?.kid('txBody')?.kid('bodyPr')],
      );
      // Пустой заполнитель на слайде — подсказка редактора, не текст.
      if (text != null && text.isEmpty) text = null;
    }
    if (fill == null && line == null && text == null) return;
    final s = _place(xf, box, geom: geom, adjust: adjust, path: path, fill: fill, line: line, text: text);
    if (s != null) out.add(s);
  }

  void _pic(XmlElement pic, _Src src, _Xf xf, List<DocShape> out) {
    if (_hidden(pic)) return;
    final ph = _Pptx._ph(pic);
    if (ph != null && src.template) return;
    XmlElement? lph, mph;
    if (ph != null) (lph, mph) = _inherited(ph);
    final spPr = pic.kid('spPr');
    final box =
        _Box.of(spPr?.kid('xfrm')) ?? _Box.of(lph?.kid('spPr')?.kid('xfrm')) ?? _Box.of(mph?.kid('spPr')?.kid('xfrm'));
    if (box == null) return;
    final blipFill = pic.kid('blipFill');
    final img = blipFill == null ? null : _blip(blipFill, src);
    DocPicture? picture;
    if (img != null) {
      final rect = blipFill!.kid('srcRect');
      double crop(String n) => ((_num(rect?.attr(n)) ?? 0) / 100000).clamp(-10.0, 0.99);
      picture = DocPicture(img, cropLeft: crop('l'), cropTop: crop('t'), cropRight: crop('r'), cropBottom: crop('b'));
    }
    final (geom, adjust, path) = _geometry(spPr, box);
    final line = this.line(spPr?.kid('ln'), pic.kid('style')?.kid('lnRef')).line;
    final s = picture == null
        // Картинка, которую не нарисовать (EMF, WMF, TIFF, слишком большая): серая
        // плашка, а не пустое место — видно, что там что-то есть.
        ? _place(xf, box, embed: DocEmbed.object, line: line)
        : _place(xf, box, geom: geom, adjust: adjust, path: path, picture: picture, line: line);
    if (s != null) out.add(s);
  }

  void _group(XmlElement g, _Src src, _Xf xf, List<DocShape> out, int depth) {
    if (_hidden(g)) return;
    final x = g.kid('grpSpPr')?.kid('xfrm');
    var inner = xf;
    final box = _Box.of(x);
    if (box != null) {
      final chOff = x!.kid('chOff'), chExt = x.kid('chExt');
      final chx = _num(chOff?.attr('x')) ?? box.x, chy = _num(chOff?.attr('y')) ?? box.y;
      final chw = _num(chExt?.attr('cx')) ?? box.w, chh = _num(chExt?.attr('cy')) ?? box.h;
      final sx = chw > 0 ? box.w / chw : 1.0, sy = chh > 0 ? box.h / chh : 1.0;
      final scale = _Xf(sx, 0, 0, sy, box.x - chx * sx, box.y - chy * sy);
      // Поворот и отражение группы — вокруг её центра.
      final cx = box.x + box.w / 2, cy = box.y + box.h / 2;
      final rad = box.rot * math.pi / 180;
      final cosR = math.cos(rad), sinR = math.sin(rad);
      final fh = box.flipH ? -1.0 : 1.0, fv = box.flipV ? -1.0 : 1.0;
      final a = cosR * fh, b = sinR * fh, c = -sinR * fv, d = cosR * fv;
      final rot = _Xf(a, b, c, d, cx - a * cx - c * cy, cy - b * cx - d * cy);
      inner = xf.after(rot).after(scale);
    }
    tree(g, src, inner, out, depth + 1);
  }

  void _frame(XmlElement f, _Src src, _Xf xf, List<DocShape> out, int depth) {
    if (_hidden(f)) return;
    if (_Pptx._ph(f) != null && src.template) return;
    final box = _Box.of(f.kid('xfrm'));
    if (box == null) return;
    final data = f.kid('graphic')?.kid('graphicData');
    final uri = data?.attr('uri') ?? '';
    if (data == null) return;
    if (uri.endsWith('/table')) {
      final tbl = data.kid('tbl');
      final t = tbl == null ? null : _table(tbl, src);
      if (t != null) {
        final s = _place(xf, box, table: t);
        if (s != null) out.add(s);
      }
      return;
    }
    if (uri.endsWith('/diagram')) {
      // SmartArt: сохранённый рисунок (drawing*.xml) — координаты от рамки.
      if (_diagram(data, src, xf, box, out, depth)) return;
      final s = _place(xf, box, embed: DocEmbed.diagram);
      if (s != null) out.add(s);
      return;
    }
    if (uri.endsWith('/chart') || uri.contains('chartex')) {
      final s = _place(xf, box, embed: DocEmbed.chart);
      if (s != null) out.add(s);
      return;
    }
    // Объект OLE (лист Excel, формула…): его картинка-заменитель, если она
    // рисуется (обычно EMF — тогда плашка).
    final pic = data.descendant('pic');
    final blip = pic?.kid('blipFill');
    final img = blip == null ? null : _blip(blip, src);
    final s = img != null ? _place(xf, box, picture: DocPicture(img)) : _place(xf, box, embed: DocEmbed.object);
    if (s != null) out.add(s);
  }

  bool _diagram(XmlElement data, _Src src, _Xf xf, _Box box, List<DocShape> out, int depth) {
    final relIds = data.kid('relIds');
    String? drawing;
    final dm = src.rels[relIds?.attr('dm', ns: 'relationships') ?? ''];
    if (dm != null && !dm.external) {
      final ext = r._doc(dm.target)?.rootElement.descendant('dataModelExt');
      final id = ext?.attr('relId');
      final rel = src.rels[id ?? ''];
      if (rel != null && !rel.external) drawing = rel.target;
    }
    drawing ??= src.rels.values
        .where((r) => !r.external && r.isType('diagramDrawing'))
        .map((r) => r.target)
        .firstOrNull;
    if (drawing == null) return false;
    final tree = r._doc(drawing)?.rootElement.kid('spTree');
    if (tree == null) return false;
    // Координаты рисунка — от левого верхнего угла рамки SmartArt.
    final shift = _Xf(1, 0, 0, 1, box.x, box.y);
    final before = out.length;
    this.tree(tree, _Src(drawing, r.zip.rels(drawing)), xf.after(shift), out, depth + 1);
    return out.length > before;
  }

  // ─────────────────────────────── формы ───────────────────────────────

  /// Форма из spPr: заготовка (prstGeom) или свой контур (custGeom).
  (DocGeom, double?, DocPath?) _geometry(XmlElement? spPr, _Box box, {bool connector = false}) {
    final prst = spPr?.kid('prstGeom');
    if (prst != null) {
      final name = prst.attr('prst') ?? 'rect';
      double? adj(String n, double def) {
        for (final gd in prst.kid('avLst')?.kids('gd') ?? const <XmlElement>[]) {
          if (gd.attr('name') != n) continue;
          final f = (gd.attr('fmla') ?? '').trim();
          if (f.startsWith('val ')) return (_num(f.substring(4)) ?? def) / 100000;
        }
        return def / 100000;
      }

      if (name.startsWith('bentConnector') || name.startsWith('curvedConnector')) {
        final a = adj('adj1', 50000)!;
        final curved = name.startsWith('curved');
        if (name.endsWith('2')) {
          return (
            DocGeom.path,
            null,
            const DocPath([DocPathOp.move, DocPathOp.line, DocPathOp.line], [0, 0, 1, 0, 1, 1], filled: false),
          );
        }
        return (
          DocGeom.path,
          null,
          curved
              ? DocPath([DocPathOp.move, DocPathOp.cubic], [0, 0, a, 0, a, 1, 1, 1], filled: false)
              : DocPath(
                  [DocPathOp.move, DocPathOp.line, DocPathOp.line, DocPathOp.line],
                  [0, 0, a, 0, a, 1, 1, 1],
                  filled: false,
                ),
        );
      }
      final g = docPresetGeometry[name] ?? (connector ? DocGeom.line : DocGeom.rect);
      final adjust = switch (g) {
        DocGeom.roundRect => name == 'flowChartAlternateProcess' ? 1 / 6 : adj('adj', 16667),
        DocGeom.triangle => adj('adj', 50000),
        DocGeom.parallelogram || DocGeom.trapezoid || DocGeom.hexagon || DocGeom.plus => adj('adj', 25000),
        DocGeom.octagon => adj('adj', 29289),
        DocGeom.homePlate || DocGeom.chevron => adj('adj', 50000),
        DocGeom.rightArrow ||
        DocGeom.leftArrow ||
        DocGeom.upArrow ||
        DocGeom.downArrow ||
        DocGeom.leftRightArrow => adj('adj2', 50000),
        _ => null,
      };
      return (g, adjust, null);
    }
    final cust = spPr?.kid('custGeom');
    if (cust != null) {
      final p = _custPath(cust, box);
      if (p != null && !p.isEmpty) return (DocGeom.path, null, p);
    }
    return (connector ? DocGeom.line : DocGeom.rect, null, null);
  }

  /// Свой контур a:custGeom → доли рамки. Точки — числа (формулы в точках
  /// не вычисляются: такой контур рисуется прямоугольником).
  DocPath? _custPath(XmlElement cust, _Box box) {
    final guides = <String, double>{};
    for (final gd in cust.kid('gdLst')?.kids('gd') ?? const <XmlElement>[]) {
      final f = (gd.attr('fmla') ?? '').trim();
      final name = gd.attr('name');
      if (name != null && f.startsWith('val ')) {
        final v = _num(f.substring(4));
        if (v != null) guides[name] = v;
      }
    }
    double? val(String? s) => s == null ? null : (_num(s) ?? guides[s]);
    final ops = <DocPathOp>[];
    final pts = <double>[];
    var filled = true;
    var count = 0;
    for (final path in cust.kid('pathLst')?.kids('path') ?? const <XmlElement>[]) {
      final pw = _num(path.attr('w')) ?? box.w;
      final phh = _num(path.attr('h')) ?? box.h;
      final sx = pw > 0 ? 1 / pw : 0.0, sy = phh > 0 ? 1 / phh : 0.0;
      if (path.attr('fill') == 'none') filled = false;
      var curX = 0.0, curY = 0.0;
      for (final c in path.childElements) {
        if (++count > 5000) {
          r._truncated = true;
          break;
        }
        final ptsEl = c.kids('pt').toList();
        List<double>? xy(int i) {
          if (i >= ptsEl.length) return null;
          final x = val(ptsEl[i].attr('x')), y = val(ptsEl[i].attr('y'));
          return x == null || y == null ? null : [x, y];
        }

        switch (c.local) {
          case 'moveTo' || 'lnTo':
            final p = xy(0);
            if (p == null) return null;
            ops.add(c.local == 'moveTo' ? DocPathOp.move : DocPathOp.line);
            pts.addAll([p[0] * sx, p[1] * sy]);
            (curX, curY) = (p[0], p[1]);
          case 'cubicBezTo':
            final a = xy(0), b = xy(1), e = xy(2);
            if (a == null || b == null || e == null) return null;
            ops.add(DocPathOp.cubic);
            pts.addAll([a[0] * sx, a[1] * sy, b[0] * sx, b[1] * sy, e[0] * sx, e[1] * sy]);
            (curX, curY) = (e[0], e[1]);
          case 'quadBezTo':
            final a = xy(0), e = xy(1);
            if (a == null || e == null) return null;
            final c1x = curX + 2 / 3 * (a[0] - curX), c1y = curY + 2 / 3 * (a[1] - curY);
            final c2x = e[0] + 2 / 3 * (a[0] - e[0]), c2y = e[1] + 2 / 3 * (a[1] - e[1]);
            ops.add(DocPathOp.cubic);
            pts.addAll([c1x * sx, c1y * sy, c2x * sx, c2y * sy, e[0] * sx, e[1] * sy]);
            (curX, curY) = (e[0], e[1]);
          case 'arcTo':
            final wr = val(c.attr('wR')), hr = val(c.attr('hR'));
            final st = val(c.attr('stAng')), sw = val(c.attr('swAng'));
            if (wr == null || hr == null || st == null || sw == null) return null;
            (curX, curY) = _arc(curX, curY, wr, hr, st / 60000, sw / 60000, ops, pts, sx, sy);
          case 'close':
            ops.add(DocPathOp.close);
        }
      }
    }
    if (ops.isEmpty) return null;
    return DocPath(ops, pts, filled: filled);
  }

  /// Дуга arcTo — кривыми Безье (не больше 90° на кривую).
  static (double, double) _arc(
    double x0,
    double y0,
    double wr,
    double hr,
    double stDeg,
    double swDeg,
    List<DocPathOp> ops,
    List<double> pts,
    double sx,
    double sy,
  ) {
    if (wr <= 0 || hr <= 0 || swDeg == 0) return (x0, y0);
    // Угол в DrawingML — «видимый»; параметр эллипса — через atan2.
    double param(double deg) {
      final a = deg * math.pi / 180;
      return math.atan2(wr * math.sin(a), hr * math.cos(a));
    }

    final t0 = param(stDeg);
    var t1 = param(stDeg + swDeg);
    // Направление и полнота обхода — по swAng.
    final sweep = swDeg * math.pi / 180;
    var dt = t1 - t0;
    if (sweep > 0 && dt <= 0) dt += 2 * math.pi;
    if (sweep < 0 && dt >= 0) dt -= 2 * math.pi;
    if (sweep.abs() >= 2 * math.pi - 1e-6) dt = sweep;
    t1 = t0 + dt;
    final cx = x0 - wr * math.cos(t0), cy = y0 - hr * math.sin(t0);
    final n = math.max(1, (dt.abs() / (math.pi / 2)).ceil());
    final step = dt / n;
    var a = t0;
    for (var i = 0; i < n; i++) {
      final b = a + step;
      final k = 4 / 3 * math.tan((b - a) / 4);
      final p1x = cx + wr * (math.cos(a) - k * math.sin(a)), p1y = cy + hr * (math.sin(a) + k * math.cos(a));
      final p2x = cx + wr * (math.cos(b) + k * math.sin(b)), p2y = cy + hr * (math.sin(b) - k * math.cos(b));
      final ex = cx + wr * math.cos(b), ey = cy + hr * math.sin(b);
      ops.add(DocPathOp.cubic);
      pts.addAll([p1x * sx, p1y * sy, p2x * sx, p2y * sy, ex * sx, ey * sy]);
      a = b;
    }
    return (cx + wr * math.cos(t1), cy + hr * math.sin(t1));
  }

  // ─────────────────────────────── текст ───────────────────────────────

  DocTextBody? _text(
    XmlElement txBody,
    _TextStyles st,
    _Src src, {
    List<XmlElement?> inheritedBody = const [],
    XmlElement? cellPr,
    XmlElement? tableText,
  }) {
    final bodies = [txBody.kid('bodyPr'), ...inheritedBody];
    String? battr(String n) {
      for (final b in bodies) {
        final v = b?.attr(n);
        if (v != null) return v;
      }
      return null;
    }

    XmlElement? autofit;
    for (final b in bodies) {
      autofit = b?.childElements.where((e) => e.local.endsWith('utofit') || e.local == 'spAutoFit').firstOrNull;
      if (autofit != null) break;
    }
    double ins(String n, String cellN, double def) {
      final v = _num(cellPr?.attr(cellN)) ?? _num(battr(n));
      return v == null ? def : _pt(v).clamp(0.0, 500.0);
    }

    final anchorS = cellPr?.attr('anchor') ?? battr('anchor') ?? 't';
    final anchor = switch (anchorS) {
      'ctr' => DocAnchor.middle,
      'b' => DocAnchor.bottom,
      _ => DocAnchor.top,
    };
    final fontScale = autofit?.local == 'normAutofit' ? (_num(autofit!.attr('fontScale')) ?? 100000) / 100000 : 1.0;
    final reduction = autofit?.local == 'normAutofit' ? (_num(autofit!.attr('lnSpcReduction')) ?? 0) / 100000 : 0.0;
    final paragraphs = <DocParagraph>[];
    final counters = List<int>.filled(9, 0);
    final counterKind = List<String?>.filled(9, null);
    for (final p in txBody.kids('p')) {
      if (paragraphs.length >= PptxReader.maxParagraphs) {
        r._truncated = true;
        break;
      }
      paragraphs.add(_paragraph(p, st, src, counters, counterKind, tableText));
    }
    return DocTextBody(
      insetLeft: ins('lIns', 'marL', 7.2),
      insetTop: ins('tIns', 'marT', 3.6),
      insetRight: ins('rIns', 'marR', 7.2),
      insetBottom: ins('bIns', 'marB', 3.6),
      anchor: anchor,
      wrap: battr('wrap') != 'none',
      fontScale: fontScale.clamp(0.05, 1.0),
      lineReduction: reduction.clamp(0.0, 0.9),
      // Автоподбор без сохранённого множителя: показ уменьшит сам.
      shrink: autofit?.local == 'normAutofit' && autofit!.attr('fontScale') == null,
      paragraphs: paragraphs,
    );
  }

  DocParagraph _paragraph(
    XmlElement p,
    _TextStyles st,
    _Src src,
    List<int> counters,
    List<String?> counterKind,
    XmlElement? tableText,
  ) {
    final pPr = p.kid('pPr');
    final level = (_int(pPr?.attr('lvl')) ?? 0).clamp(0, 8);
    XmlElement? lvl(XmlElement? list) {
      if (list == null) return null;
      return list.kid('lvl${level + 1}pPr');
    }

    // Свойства абзаца по цепочке наследования.
    final chain = <XmlElement?>[
      pPr,
      for (final l in st.before) lvl(l),
      for (final l in st.after) lvl(l),
      st.after.lastOrNull?.kid('defPPr'),
    ].whereType<XmlElement>().toList();
    String? a(String n) {
      for (final e in chain) {
        final v = e.attr(n);
        if (v != null) return v;
      }
      return null;
    }

    XmlElement? k(bool Function(XmlElement) test) {
      for (final e in chain) {
        for (final c in e.childElements) {
          if (test(c)) return c;
        }
      }
      return null;
    }

    // Оформление фрагментов: своё → абзаца → стили фигуры → fontRef → унаследованные.
    final fontRef = st.fontRef;
    XmlElement? refRPr;
    if (fontRef != null || tableText != null) {
      final kids = <XmlElement>[];
      final fr = fontRef?.attr('idx');
      if (tableText != null) {
        for (final c in tableText.childElements) {
          kids.add(c.copy());
        }
      }
      final refColor = fontRef?.childElements.firstOrNull;
      if (refColor != null && !kids.any((e) => e.local == 'solidFill')) {
        kids.add(XmlElement(XmlName('solidFill'), const [], [refColor.copy()]));
      }
      if (fr == 'major' || fr == 'minor') {
        kids.add(
          XmlElement(XmlName('latin'), [XmlAttribute(XmlName('typeface'), fr == 'major' ? '+mj-lt' : '+mn-lt')]),
        );
      }
      refRPr = XmlElement(XmlName('defRPr'), [
        for (final at in tableText?.attributes ?? const <XmlAttribute>[])
          XmlAttribute(XmlName(at.name.local), at.value),
      ], kids);
    }
    final runChain = <XmlElement?>[
      pPr?.kid('defRPr'),
      for (final l in st.before) lvl(l)?.kid('defRPr'),
      refRPr,
      for (final l in st.after) lvl(l)?.kid('defRPr'),
      st.after.lastOrNull?.kid('defPPr')?.kid('defRPr'),
    ].whereType<XmlElement>().toList();

    final runs = <DocRun>[];
    for (final c in p.childElements) {
      switch (c.local) {
        case 'r' || 'fld':
          var t = c.kid('t')?.innerText ?? '';
          if (t.length > PptxReader.maxRunChars) {
            t = t.substring(0, PptxReader.maxRunChars);
            r._truncated = true;
          }
          runs.add(_run(t, c.kid('rPr'), runChain, src));
        case 'br':
          runs.add(_run('\n', c.kid('rPr'), runChain, src));
      }
    }
    final endSize = _size([p.kid('endParaRPr'), ...runChain]) ?? 18;
    final firstSize = runs.isEmpty ? endSize : runs.first.size;

    // Маркер.
    DocBullet? bullet;
    final bu = k((e) => const {'buNone', 'buChar', 'buAutoNum', 'buBlip'}.contains(e.local));
    final hasText = runs.any((r) => r.text.trim().isNotEmpty);
    if (bu != null && bu.local != 'buNone' && hasText) {
      final fontEl = k((e) => e.local == 'buFont' || e.local == 'buFontTx');
      var font = fontEl?.local == 'buFont' ? fontEl?.attr('typeface') : null;
      if (font != null && font.startsWith('+')) font = _font(font);
      final clrEl = k((e) => e.local == 'buClr' || e.local == 'buClrTx');
      final szEl = k((e) => e.local == 'buSzPct' || e.local == 'buSzPts' || e.local == 'buSzTx');
      var scale = 1.0;
      if (szEl?.local == 'buSzPct') scale = ((_num(szEl!.attr('val')) ?? 100000) / 100000).clamp(0.25, 4.0);
      if (szEl?.local == 'buSzPts' && firstSize > 0) {
        scale = (((_num(szEl!.attr('val')) ?? 0) / 100) / firstSize).clamp(0.25, 4.0);
      }
      String text;
      if (bu.local == 'buAutoNum') {
        final kind = bu.attr('type') ?? 'arabicPeriod';
        final start = (_int(bu.attr('startAt')) ?? 1).clamp(1, 32767);
        if (counterKind[level] != kind) {
          counterKind[level] = kind;
          counters[level] = start;
        } else {
          counters[level]++;
        }
        text = _autoNumber(kind, counters[level]);
        font = null;
      } else if (bu.local == 'buBlip') {
        text = '•';
      } else {
        text = _bulletChar(bu.attr('char') ?? '•', font);
        if (_symbolFont(font)) font = null;
      }
      bullet = DocBullet(text, color: clrEl?.local == 'buClr' ? color(clrEl) : null, sizeScale: scale, font: font);
    }
    if (bu?.local != 'buAutoNum') {
      counterKind[level] = null;
    }
    // Абзац уровнем выше заканчивает нумерацию вложенных.
    for (var i = level + 1; i < 9; i++) {
      counterKind[i] = null;
    }

    double spacing(String n) {
      final e = k((e) => e.local == n);
      final pts = e?.kid('spcPts');
      if (pts != null) return ((_num(pts.attr('val')) ?? 0) / 100).clamp(0.0, 1000.0);
      final pct = e?.kid('spcPct');
      if (pct != null) return ((_num(pct.attr('val')) ?? 0) / 100000 * firstSize * 1.2).clamp(0.0, 1000.0);
      return 0;
    }

    final ln = k((e) => e.local == 'lnSpc');
    var lineSpacing = 1.0;
    double? lineExact;
    if (ln?.kid('spcPct') != null) {
      lineSpacing = ((_num(ln!.kid('spcPct')!.attr('val')) ?? 100000) / 100000).clamp(0.1, 10.0);
    } else if (ln?.kid('spcPts') != null) {
      lineExact = ((_num(ln!.kid('spcPts')!.attr('val')) ?? 1200) / 100).clamp(1.0, 1000.0);
    }
    final align = switch (a('algn')) {
      'ctr' => DocAlign.center,
      'r' => DocAlign.right,
      'just' || 'dist' || 'justLow' || 'thaiDist' => DocAlign.justify,
      _ => DocAlign.left,
    };
    return DocParagraph(
      align: align,
      level: level,
      marginLeft: _pt(_num(a('marL')) ?? 0).clamp(0.0, 2000.0),
      indent: _pt(_num(a('indent')) ?? 0).clamp(-2000.0, 2000.0),
      bullet: bullet,
      spaceBefore: spacing('spcBef'),
      spaceAfter: spacing('spcAft'),
      lineSpacing: lineSpacing,
      lineExact: lineExact,
      endSize: endSize,
      runs: runs,
    );
  }

  static double? _size(List<XmlElement?> chain) {
    for (final e in chain) {
      final v = _num(e?.attr('sz'));
      if (v != null) return (v / 100).clamp(1.0, 400.0);
    }
    return null;
  }

  String? _font(String? typeface) {
    if (typeface == null || typeface.isEmpty) return null;
    if (typeface.startsWith('+mj')) return theme.major;
    if (typeface.startsWith('+mn')) return theme.minor;
    return typeface;
  }

  DocRun _run(String text, XmlElement? rPr, List<XmlElement> inherited, _Src src) {
    final chain = [rPr, ...inherited].whereType<XmlElement>();
    String? a(String n) {
      for (final e in chain) {
        final v = e.attr(n);
        if (v != null) return v;
      }
      return null;
    }

    int? textColor;
    var colorSet = false;
    for (final e in chain) {
      for (final c in e.childElements) {
        if (c.local == 'solidFill') {
          textColor = color(c);
        } else if (c.local == 'gradFill') {
          textColor = _gradient(c, null)?.flatColor;
        } else if (c.local == 'noFill') {
          textColor = 0x00000000;
        } else {
          continue;
        }
        colorSet = true;
        break;
      }
      if (colorSet) break;
    }
    String? font;
    for (final e in chain) {
      final t = e.kid('latin')?.attr('typeface') ?? e.kid('cs')?.attr('typeface');
      if (t != null && t.isNotEmpty) {
        font = _font(t);
        break;
      }
    }
    font ??= theme.minor;
    String? href;
    final click = rPr?.kid('hlinkClick');
    if (click != null) {
      final rel = src.rels[click.attr('id', ns: 'relationships') ?? ''];
      if (rel != null && rel.external) href = docSafeHref(rel.target);
    }
    // Ссылка — цветом ссылки темы и подчёркнутая, как в PowerPoint.
    var underline = (a('u') ?? 'none') != 'none';
    if (href != null) {
      final own = rPr?.kid('solidFill');
      textColor = own != null ? color(own) : scheme('hlink');
      underline = true;
    }
    if (a('cap') == 'all') text = text.toUpperCase();
    final strike = a('strike');
    return DocRun(
      text,
      size: _size([rPr, ...inherited]) ?? 18,
      color: textColor ?? scheme('tx1') ?? 0xFF000000,
      bold: _bool(a('b')) ?? false,
      italic: _bool(a('i')) ?? false,
      underline: underline,
      strike: strike != null && strike != 'noStrike',
      baseline: ((_num(a('baseline')) ?? 0) / 1000).clamp(-100.0, 100.0),
      font: font,
      highlight: color(rPr?.kid('highlight')),
      href: href,
    );
  }

  static String _autoNumber(String kind, int n) {
    String body;
    if (kind.startsWith('alphaLc')) {
      body = _alpha(n);
    } else if (kind.startsWith('alphaUc')) {
      body = _alpha(n).toUpperCase();
    } else if (kind.startsWith('romanLc')) {
      body = _roman(n).toLowerCase();
    } else if (kind.startsWith('romanUc')) {
      body = _roman(n);
    } else {
      body = '$n';
    }
    if (kind.endsWith('ParenBoth')) return '($body)';
    if (kind.endsWith('ParenR')) return '$body)';
    if (kind.endsWith('Plain')) return body;
    if (kind.endsWith('Minus')) return '- $body -';
    return '$body.';
  }

  static String _alpha(int n) {
    final out = StringBuffer();
    var v = n;
    while (v > 0 && out.length < 8) {
      v--;
      out.write(String.fromCharCode(0x61 + v % 26));
      v ~/= 26;
    }
    return out.toString().split('').reversed.join();
  }

  static String _roman(int n) {
    if (n <= 0 || n >= 4000) return '$n';
    const v = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const s = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    final out = StringBuffer();
    var x = n;
    for (var i = 0; i < v.length; i++) {
      while (x >= v[i]) {
        out.write(s[i]);
        x -= v[i];
      }
    }
    return out.toString();
  }

  static bool _symbolFont(String? f) {
    final n = (f ?? '').toLowerCase();
    return n.startsWith('wingdings') || n == 'symbol' || n.startsWith('webdings') || n == 'monotype sorts';
  }

  /// Знак маркера шрифтов Wingdings и Symbol — знаком Юникода: у телефона
  /// этих шрифтов нет, и «§» вместо квадратика сбивает с толку.
  static String _bulletChar(String ch, String? font) {
    if (ch.isEmpty) return '•';
    if (!_symbolFont(font)) return ch;
    var code = ch.runes.first;
    // Знаки шрифтов-символов часто записаны в области U+F0xx.
    if (code >= 0xF000 && code <= 0xF0FF) code -= 0xF000;
    final symbol = (font ?? '').toLowerCase() == 'symbol';
    if (symbol) return code == 0xB7 ? '•' : (code == 0xAE ? '→' : '•');
    return switch (code) {
      0x6C => '●',
      0x6E => '■',
      0x6F => '□',
      0x71 => '❑',
      0x75 => '◆',
      0x76 => '❖',
      0x77 => '⬥',
      0xA7 => '▪',
      0x9F => '•',
      0xA8 => '◻',
      0xD8 => '➢',
      0xE0 || 0xE8 => '➔',
      0xF0 => '⇨',
      0xFC => '✔',
      0xFB => '✘',
      _ => '•',
    };
  }

  // ─────────────────────────────── таблицы ───────────────────────────────

  DocTable? _table(XmlElement tbl, _Src src) {
    final cols = <double>[];
    for (final gc in tbl.kid('tblGrid')?.kids('gridCol') ?? const <XmlElement>[]) {
      if (cols.length >= PptxReader.maxTableCols) {
        r._truncated = true;
        break;
      }
      cols.add(_pt(_num(gc.attr('w')) ?? 0).clamp(0.0, 20000.0));
    }
    if (cols.isEmpty) return null;
    final tblPr = tbl.kid('tblPr');
    final style = _tableStyle(tblPr?.kid('tableStyleId')?.innerText.trim());
    bool flag(String n) => _bool(tblPr?.attr(n)) ?? false;
    final firstRow = flag('firstRow'), lastRow = flag('lastRow');
    final firstCol = flag('firstCol'), lastCol = flag('lastCol');
    final bandRow = flag('bandRow'), bandCol = flag('bandCol');

    final rowEls = tbl.kids('tr').take(PptxReader.maxTableRows + 1).toList();
    if (rowEls.length > PptxReader.maxTableRows) {
      rowEls.removeLast();
      r._truncated = true;
    }
    final rows = <double>[for (final tr in rowEls) _pt(_num(tr.attr('h')) ?? 0).clamp(0.0, 20000.0)];
    final cells = <DocCell>[];
    final nRows = rows.length, nCols = cols.length;
    for (var ri = 0; ri < nRows; ri++) {
      var ci = 0;
      for (final tc in rowEls[ri].kids('tc')) {
        if (ci >= nCols) break;
        final col = ci++;
        if ((_bool(tc.attr('hMerge')) ?? false) || (_bool(tc.attr('vMerge')) ?? false)) continue;
        final colSpan = (_int(tc.attr('gridSpan')) ?? 1).clamp(1, nCols - col);
        final rowSpan = (_int(tc.attr('rowSpan')) ?? 1).clamp(1, nRows - ri);
        // Части стиля таблицы, которые относятся к ячейке, — от общей к частной.
        final parts = <XmlElement?>[
          style?.kid('wholeTbl'),
          if (bandCol && !(firstCol && col == 0))
            style?.kid(((col - (firstCol ? 1 : 0)) % 2 == 0) ? 'band1V' : 'band2V'),
          if (bandRow && !(firstRow && ri == 0) && !(lastRow && ri == nRows - 1))
            style?.kid(((ri - (firstRow ? 1 : 0)) % 2 == 0) ? 'band1H' : 'band2H'),
          if (firstCol && col == 0) style?.kid('firstCol'),
          if (lastCol && col + colSpan == nCols) style?.kid('lastCol'),
          if (lastRow && ri + rowSpan == nRows) style?.kid('lastRow'),
          if (firstRow && ri == 0) style?.kid('firstRow'),
        ].whereType<XmlElement>().toList();
        final tcPr = tc.kid('tcPr');
        // Заливка: своя, иначе — стиля.
        var fill = this.fill(tcPr, src);
        if (!fill.set) {
          for (final p in parts.reversed) {
            final f = this.fill(p.kid('tcStyle')?.kid('fill'), src);
            if (f.set) {
              fill = f;
              break;
            }
          }
        }
        DocLine? border(String own, String side, String inner, bool outer) {
          final l = line(tcPr?.kid(own), null);
          if (l.set) return l.line;
          for (final p in parts.reversed) {
            final bdr = p.kid('tcStyle')?.kid('tcBdr');
            final e = bdr?.kid(outer ? side : inner) ?? (outer ? null : bdr?.kid(side));
            if (e == null) continue;
            final ln = e.kid('ln');
            if (ln != null) {
              final v = line(ln, null);
              if (v.set) return v.line;
            }
            final ref = e.kid('lnRef');
            if (ref != null) return line(null, ref).line;
          }
          return null;
        }

        // Оформление текста стиля: жирный и цвет из tcTxStyle.
        XmlElement? txt;
        for (final p in parts.reversed) {
          final s = p.kid('tcTxStyle');
          if (s == null) continue;
          txt ??= XmlElement(XmlName('defRPr'));
          if (txt.getAttribute('b') == null && s.attr('b') != null) {
            txt.setAttribute('b', s.attr('b') == 'on' ? '1' : '0');
          }
          if (txt.getAttribute('i') == null && s.attr('i') != null) {
            txt.setAttribute('i', s.attr('i') == 'on' ? '1' : '0');
          }
          final c = color(s, ph: null) ?? color(s.kid('fontRef'));
          if (c != null && txt.childElements.isEmpty) {
            txt.children.add(
              XmlElement(XmlName('solidFill'), const [], [
                XmlElement(XmlName('srgbClr'), [XmlAttribute(XmlName('val'), _hex(c))]),
              ]),
            );
          }
        }
        final tx = tc.kid('txBody');
        final text = tx == null
            ? null
            : _text(
                tx,
                _TextStyles([tx.kid('lstStyle')], [master?.txStyle('otherStyle'), r._defaultStyle], null),
                src,
                cellPr: tcPr ?? XmlElement(XmlName('tcPr')),
                tableText: txt,
              );
        cells.add(
          DocCell(
            row: ri,
            col: col,
            rowSpan: rowSpan,
            colSpan: colSpan,
            fill: fill.fill,
            left: border('lnL', 'left', 'insideV', col == 0),
            right: border('lnR', 'right', 'insideV', col + colSpan == nCols),
            top: border('lnT', 'top', 'insideH', ri == 0),
            bottom: border('lnB', 'bottom', 'insideH', ri + rowSpan == nRows),
            text: text == null || text.isEmpty ? null : text,
          ),
        );
        ci = col + 1;
      }
    }
    return DocTable(columns: cols, rows: rows, cells: cells);
  }

  static String _hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// Стиль таблицы: из ppt/tableStyles.xml, иначе — встроенный (самые
  /// частые «Средний стиль 2 — акцент N» и «Без стиля»), иначе — простая
  /// сетка: остальные встроенные стили PowerPoint в файл не записывает.
  XmlElement? _tableStyle(String? id) {
    // Без стиля — как в PowerPoint: ни заливок, ни сетки (кроме своих у ячеек).
    if (id == null || id.isEmpty) return null;
    for (final s in r._tableStyles?.kids('tblStyle') ?? const <XmlElement>[]) {
      if (s.attr('styleId') == id) return s;
    }
    return _builtinStyle(id);
  }

  static final Map<String, XmlElement?> _builtin = {};

  static XmlElement? _builtinStyle(String id) => _builtin.putIfAbsent(id, () {
    const medium2 = {
      '{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}': 'accent1',
      '{21E4AEA4-8DFA-4A89-87EB-49C32662AFE8}': 'accent2',
      '{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}': 'accent3',
      '{00A15C55-8517-42AA-B614-E9B94910E393}': 'accent4',
      '{7DF18680-E054-41AD-8BC1-D1AEF772440D}': 'accent5',
      '{93296810-A885-4BE3-A3E7-6D5BEEA58F35}': 'accent6',
      '{073A0DAA-6AF3-43AB-8588-CEC1D06C72B9}': 'dk1',
    };
    final accent = medium2[id];
    String xml;
    const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
    String ln(String w, String c) => '<a:ln w="$w"><a:solidFill><a:schemeClr val="$c"/></a:solidFill></a:ln>';
    if (accent != null) {
      final white = ln('12700', 'lt1');
      xml =
          '<a:tblStyle $ns>'
          '<a:wholeTbl><a:tcTxStyle><a:schemeClr val="dk1"/></a:tcTxStyle><a:tcStyle><a:tcBdr>'
          '<a:left>$white</a:left><a:right>$white</a:right><a:top>$white</a:top><a:bottom>$white</a:bottom>'
          '<a:insideH>$white</a:insideH><a:insideV>$white</a:insideV></a:tcBdr>'
          '<a:fill><a:solidFill><a:schemeClr val="$accent"><a:tint val="20000"/></a:schemeClr></a:solidFill></a:fill>'
          '</a:tcStyle></a:wholeTbl>'
          '<a:band1H><a:tcStyle><a:fill><a:solidFill><a:schemeClr val="$accent"><a:tint val="40000"/></a:schemeClr>'
          '</a:solidFill></a:fill></a:tcStyle></a:band1H>'
          '<a:band1V><a:tcStyle><a:fill><a:solidFill><a:schemeClr val="$accent"><a:tint val="40000"/></a:schemeClr>'
          '</a:solidFill></a:fill></a:tcStyle></a:band1V>'
          '<a:lastCol><a:tcTxStyle b="on"><a:schemeClr val="lt1"/></a:tcTxStyle><a:tcStyle><a:fill><a:solidFill>'
          '<a:schemeClr val="$accent"/></a:solidFill></a:fill></a:tcStyle></a:lastCol>'
          '<a:firstCol><a:tcTxStyle b="on"><a:schemeClr val="lt1"/></a:tcTxStyle><a:tcStyle><a:fill><a:solidFill>'
          '<a:schemeClr val="$accent"/></a:solidFill></a:fill></a:tcStyle></a:firstCol>'
          '<a:lastRow><a:tcTxStyle b="on"><a:schemeClr val="lt1"/></a:tcTxStyle><a:tcStyle><a:tcBdr><a:top>'
          '${ln('38100', 'lt1')}</a:top></a:tcBdr><a:fill><a:solidFill><a:schemeClr val="$accent"/></a:solidFill>'
          '</a:fill></a:tcStyle></a:lastRow>'
          '<a:firstRow><a:tcTxStyle b="on"><a:schemeClr val="lt1"/></a:tcTxStyle><a:tcStyle><a:tcBdr><a:bottom>'
          '${ln('38100', 'lt1')}</a:bottom></a:tcBdr><a:fill><a:solidFill><a:schemeClr val="$accent"/></a:solidFill>'
          '</a:fill></a:tcStyle></a:firstRow></a:tblStyle>';
    } else if (id == '{2D5ABB26-0587-4C30-8999-92F81FD0307C}') {
      // «Без стиля, без сетки».
      xml = '<a:tblStyle $ns><a:wholeTbl><a:tcTxStyle><a:schemeClr val="tx1"/></a:tcTxStyle></a:wholeTbl></a:tblStyle>';
    } else {
      // «Без стиля, сетка» и неизвестные стили: тонкая сетка цветом текста.
      final grid = ln('12700', 'tx1');
      xml =
          '<a:tblStyle $ns><a:wholeTbl><a:tcTxStyle><a:schemeClr val="tx1"/></a:tcTxStyle><a:tcStyle><a:tcBdr>'
          '<a:left>$grid</a:left><a:right>$grid</a:right><a:top>$grid</a:top><a:bottom>$grid</a:bottom>'
          '<a:insideH>$grid</a:insideH><a:insideV>$grid</a:insideV></a:tcBdr></a:tcStyle></a:wholeTbl>'
          '<a:firstRow><a:tcTxStyle b="on"/></a:firstRow></a:tblStyle>';
    }
    return XmlDocument.parse(xml).rootElement;
  });
}

// ─────────────────────────────── цвета ───────────────────────────────

const _preset = {
  'black': 0x000000,
  'white': 0xFFFFFF,
  'red': 0xFF0000,
  'green': 0x008000,
  'blue': 0x0000FF,
  'yellow': 0xFFFF00,
  'cyan': 0x00FFFF,
  'aqua': 0x00FFFF,
  'magenta': 0xFF00FF,
  'fuchsia': 0xFF00FF,
  'gray': 0x808080,
  'grey': 0x808080,
  'darkGray': 0xA9A9A9,
  'dkGray': 0xA9A9A9,
  'lightGray': 0xD3D3D3,
  'ltGray': 0xD3D3D3,
  'silver': 0xC0C0C0,
  'orange': 0xFFA500,
  'purple': 0x800080,
  'navy': 0x000080,
  'maroon': 0x800000,
  'olive': 0x808000,
  'teal': 0x008080,
  'lime': 0x00FF00,
  'brown': 0xA52A2A,
  'pink': 0xFFC0CB,
  'gold': 0xFFD700,
  'darkBlue': 0x00008B,
  'dkBlue': 0x00008B,
  'darkRed': 0x8B0000,
  'dkRed': 0x8B0000,
  'darkGreen': 0x006400,
  'dkGreen': 0x006400,
  'lightBlue': 0xADD8E6,
  'ltBlue': 0xADD8E6,
  'indigo': 0x4B0082,
  'violet': 0xEE82EE,
  'tan': 0xD2B48C,
  'coral': 0xFF7F50,
  'salmon': 0xFA8072,
};

/// Цвет элемента цвета DrawingML с поправками; null — не цвет.
int? _baseColor(XmlElement? e, Map<String, String> clrMap, _Theme? theme, {int? ph}) {
  if (e == null) return null;
  int? rgb;
  switch (e.local) {
    case 'srgbClr':
      rgb = _hexColor(e.attr('val'));
    case 'scrgbClr':
      double lin(String n) => ((_num(e.attr(n)) ?? 0) / 100000).clamp(0.0, 1.0);
      rgb =
          (_toByte(_fromLinear(lin('r'))) << 16) |
          (_toByte(_fromLinear(lin('g'))) << 8) |
          _toByte(_fromLinear(lin('b')));
    case 'hslClr':
      final hsl = _hslToRgb(
        ((_num(e.attr('hue')) ?? 0) / 60000) / 360,
        ((_num(e.attr('sat')) ?? 0) / 100000),
        ((_num(e.attr('lum')) ?? 0) / 100000),
      );
      rgb = (_toByte(hsl.$1) << 16) | (_toByte(hsl.$2) << 8) | _toByte(hsl.$3);
    case 'sysClr':
      rgb =
          _hexColor(e.attr('lastClr')) ??
          switch (e.attr('val')) {
            'window' || 'highlightText' || 'btnHighlight' => 0xFFFFFF,
            _ => 0x000000,
          };
    case 'prstClr':
      rgb = _preset[e.attr('val')];
    case 'schemeClr':
      final v = e.attr('val') ?? '';
      if (v == 'phClr') {
        if (ph == null) return null;
        rgb = ph & 0xFFFFFF;
        final base = _mods(e, rgb, ((ph >> 24) & 0xFF) / 255);
        return base;
      }
      final mapped =
          clrMap[v] ??
          switch (v) {
            'bg1' => 'lt1',
            'tx1' => 'dk1',
            'bg2' => 'lt2',
            'tx2' => 'dk2',
            _ => v,
          };
      final c = (theme ?? _Theme.fallback).colors[mapped] ?? _Theme.fallback.colors[mapped];
      if (c == null) return null;
      rgb = c & 0xFFFFFF;
    default:
      return null;
  }
  if (rgb == null) return null;
  return _mods(e, rgb, 1);
}

int? _hexColor(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.length != 6) return null;
  return int.tryParse(t, radix: 16);
}

int _toByte(double v) => (v.clamp(0.0, 1.0) * 255).round();

double _toLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _fromLinear(double c) => c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

(double, double, double) _rgbToHsl(double r, double g, double b) {
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  if (mx == mn) return (0, 0, l);
  final d = mx - mn;
  final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h / 6, s, l);
}

(double, double, double) _hslToRgb(double h, double s, double l) {
  if (s <= 0) return (l, l, l);
  double hue(double p, double q, double t) {
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  return (hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3));
}

/// Поправки цвета (дочерние элементы цвета) по порядку записи.
int _mods(XmlElement e, int rgb, double alpha0) {
  var r = ((rgb >> 16) & 0xFF) / 255, g = ((rgb >> 8) & 0xFF) / 255, b = (rgb & 0xFF) / 255;
  var alpha = alpha0;
  for (final m in e.childElements) {
    final v = (_num(m.attr('val')) ?? 0) / 100000;
    switch (m.local) {
      case 'alpha':
        alpha = v;
      case 'alphaMod':
        alpha *= v;
      case 'alphaOff':
        alpha += v;
      case 'tint':
        // Светлее: в линейном RGB — смесь с белым.
        r = _fromLinear(1 - (1 - _toLinear(r)) * v);
        g = _fromLinear(1 - (1 - _toLinear(g)) * v);
        b = _fromLinear(1 - (1 - _toLinear(b)) * v);
      case 'shade':
        r = _fromLinear(_toLinear(r) * v);
        g = _fromLinear(_toLinear(g) * v);
        b = _fromLinear(_toLinear(b) * v);
      case 'lumMod' || 'lumOff' || 'satMod' || 'satOff' || 'hueMod' || 'hueOff' || 'hue' || 'sat' || 'lum':
        var (h, s, l) = _rgbToHsl(r, g, b);
        switch (m.local) {
          case 'lumMod':
            l *= v;
          case 'lumOff':
            l += v;
          case 'satMod':
            s *= v;
          case 'satOff':
            s += v;
          case 'hueMod':
            h *= v;
          case 'hueOff':
            h += (_num(m.attr('val')) ?? 0) / 60000 / 360;
          case 'hue':
            h = (_num(m.attr('val')) ?? 0) / 60000 / 360;
          case 'sat':
            s = v;
          case 'lum':
            l = v;
        }
        (r, g, b) = _hslToRgb(h % 1, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0));
      case 'comp':
        final (h, s, l) = _rgbToHsl(r, g, b);
        (r, g, b) = _hslToRgb((h + 0.5) % 1, s, l);
      case 'inv':
        (r, g, b) = (1 - r, 1 - g, 1 - b);
      case 'gray':
        final y = 0.299 * r + 0.587 * g + 0.114 * b;
        (r, g, b) = (y, y, y);
    }
    r = r.clamp(0.0, 1.0);
    g = g.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);
  }
  final a = _toByte(alpha.clamp(0.0, 1.0));
  return (a << 24) | (_toByte(r) << 16) | (_toByte(g) << 8) | _toByte(b);
}

int _mix(int a, int b, double t) {
  int ch(int s) => (((a >> s) & 0xFF) * (1 - t) + ((b >> s) & 0xFF) * t).round();
  return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

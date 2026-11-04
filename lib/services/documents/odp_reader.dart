// lib/services/documents/odp_reader.dart
// ODP (OpenDocument Presentation, OASIS ODF 1.2/1.3, ISO/IEC 26300) →
// слайды [OfficeSlidesDoc] (1.11.x, предпросмотр документов, план владельца
// 04.11.2026).
//
// Как устроен файл и что отсюда читается:
//  · content.xml — office:presentation/draw:page: слайды по порядку;
//    скрытые (presentation:visibility="hidden" — у слайда или в стиле
//    страницы) не показываются;
//  · styles.xml — общие стили (оформление по умолчанию, стили заполнителей
//    «Заголовок», «Структура 1…9»), образцы слайдов (style:master-page: их
//    фигуры — не заполнители — рисуются под слайдом, фон, размер страницы);
//  · стили — цепочкой style:parent-style-name; размер шрифта в процентах —
//    от унаследованного;
//  · фигуры: draw:frame (надпись, картинка, таблица, объект — диаграмма
//    рисуется плашкой), draw:custom-shape (форма — по draw:type), draw:rect,
//    draw:ellipse, draw:line, draw:polygon, draw:path, draw:g; поворот —
//    draw:transform.
// Анимация, заметки и формулы своих форм (draw:equation) не читаются.
//
// Файл — чужой: части — только через OfficeZip (пределы распакованного),
// повторы (table:number-columns-repeated) и вложенность ограничены, внешние
// картинки не загружаются, ссылки — только http, https, mailto.

import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'doc_slides.dart';
import 'office_package.dart';

class OdpReader {
  OdpReader._();

  /// Абзацев в одной надписи или ячейке.
  static const maxParagraphs = 400;

  /// Строк и столбцов таблицы, повторов одной строки или столбца.
  static const maxTableRows = 200;
  static const maxTableCols = 60;

  /// Разобрать презентацию. Ошибка — только [OfficeDocException].
  static OfficeSlidesDoc read(OfficeZip zip) {
    try {
      final mime = zip.odfMimeType;
      if (mime != 'application/vnd.oasis.opendocument.presentation' &&
          mime != 'application/vnd.oasis.opendocument.presentation-template') {
        throw OfficeDocException(OfficeDocError.damaged, 'mimetype $mime');
      }
      if (zip.odfEncrypted) throw const OfficeDocException(OfficeDocError.encrypted, 'odf');
      return _Odp(zip).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, '$e');
    }
  }
}

/// Длина ODF («1.27cm», «12pt», «10mm», «1in», «2pc», «96px») → пункты;
/// null — не длина (проценты, пусто).
double? _len(String? s) {
  if (s == null) return null;
  final t = s.trim();
  final m = RegExp(r'^(-?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\s*(cm|mm|in|pt|pc|px|inch)?$').firstMatch(t);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!);
  if (v == null || !v.isFinite) return null;
  final pt = switch (m.group(2)) {
    'cm' => v * 72 / 2.54,
    'mm' => v * 72 / 25.4,
    'in' || 'inch' => v * 72,
    'pc' => v * 12,
    'px' => v * 0.75,
    _ => v,
  };
  return pt.clamp(-1e6, 1e6).toDouble();
}

double? _pct(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (!t.endsWith('%')) return null;
  return double.tryParse(t.substring(0, t.length - 1));
}

int? _rgb(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.length != 7 || !t.startsWith('#')) return null;
  final v = int.tryParse(t.substring(1), radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

/// Где искать стиль: автоматические стили content.xml (слайды) или
/// styles.xml (образцы); общие (office:styles) — для обоих.
enum _Scope { content, master }

class _Styles {
  final Map<String, XmlElement> common = {};
  final Map<String, XmlElement> masterAuto = {};
  final Map<String, XmlElement> contentAuto = {};
  final Map<String, XmlElement> defaults = {};

  /// draw:gradient, draw:fill-image, draw:hatch — по имени.
  final Map<String, XmlElement> drawing = {};
  final Map<String, String> fontFaces = {};
  final Map<String, Map<String, String>> _cache = {};

  static String _key(String family, String name) => '$family|$name';

  void addAll(XmlElement? container, Map<String, XmlElement> into) {
    for (final e in container?.childElements ?? const <XmlElement>[]) {
      final name = e.attr('name');
      switch (e.local) {
        case 'style':
          if (name != null) into[_key(e.attr('family') ?? '', name)] = e;
        case 'list-style':
          if (name != null) into[_key('list', name)] = e;
        case 'default-style':
          defaults[e.attr('family') ?? ''] = e;
        case 'gradient' || 'fill-image' || 'hatch':
          if (name != null) drawing['${e.local}|$name'] = e;
        case 'page-layout':
          if (name != null) into[_key('page-layout', name)] = e;
      }
    }
  }

  XmlElement? find(String family, String? name, _Scope scope) {
    if (name == null || name.isEmpty) return null;
    final k = _key(family, name);
    return (scope == _Scope.content ? contentAuto[k] : masterAuto[k]) ?? common[k];
  }

  /// Свойства [kind] («graphic-properties», «text-properties» …) стиля со
  /// всеми родителями; [withDefault] — снизу ещё стиль по умолчанию семейства.
  Map<String, String> props(String family, String? name, String kind, _Scope scope, {bool withDefault = false}) {
    final key = '${scope.name}|$family|$name|$kind|$withDefault';
    final cached = _cache[key];
    if (cached != null) return cached;
    final chain = <XmlElement>[];
    var s = find(family, name, scope);
    final seen = <XmlElement>{};
    while (s != null && seen.add(s) && chain.length < OfficeLimits.maxDepth) {
      chain.add(s);
      s = find(family, s.attr('parent-style-name'), scope);
    }
    final out = <String, String>{};
    if (withDefault) mergeInto(out, defaults[family], kind);
    for (final st in chain.reversed) {
      mergeInto(out, st, kind);
    }
    return _cache[key] = out;
  }

  /// Свойства [kind] элемента [style] — поверх [out]; размер шрифта в
  /// процентах — от того, что уже в [out].
  static void mergeInto(Map<String, String> out, XmlElement? style, String kind) {
    if (style == null) return;
    for (final p in style.childElements) {
      if (p.local != kind) continue;
      for (final a in p.attributes) {
        final n = a.name.local;
        if (n == 'font-size') {
          final pct = _pct(a.value);
          if (pct != null) {
            final base = _len(out['font-size']) ?? 18;
            out[n] = '${base * pct / 100}pt';
            continue;
          }
        }
        // Атрибуты разных пространств имён с одним локальным именем: fo:color
        // и loext:color и т. п. — первым считается fo/svg/draw/style.
        final ns = a.name.namespaceUri ?? '';
        if (out.containsKey(n) && (ns.contains('libreoffice') || ns.contains('loext'))) continue;
        out[n] = a.value;
      }
    }
  }

  /// Имя шрифта: fo:font-family или объявление style:font-face.
  String? font(Map<String, String> tp) {
    var f = tp['font-family'];
    final name = tp['font-name'];
    if (name != null) f = fontFaces[name] ?? f ?? name;
    if (f == null) return null;
    f = f.split(',').first.trim();
    if (f.length >= 2 && (f.startsWith("'") || f.startsWith('"'))) f = f.substring(1, f.length - 1);
    return f.isEmpty ? null : f;
  }
}

/// Источники оформления текста фигуры: от общего к частному (стиль
/// фигуры, стиль заполнителя, draw:text-style-name).
class _TextBase {
  final XmlElement shape;
  final Map<String, String> para;
  final Map<String, String> text;

  /// Стиль заполнителя «…-outline1»: абзацы уровня N берут «…-outlineN».
  final String? outlinePrefix;
  final XmlElement? listStyle;

  /// Оформление уровней структуры 2…9 — по мере надобности.
  final Map<int, _TextBase> levels = {};
  _TextBase(this.shape, this.para, this.text, this.outlinePrefix, this.listStyle);
}

class _Odp {
  _Odp(this.zip);

  final OfficeZip zip;
  final _Styles st = _Styles();
  bool _truncated = false;
  final Map<String, OfficeImage?> _images = {};
  final Map<String, XmlElement> _masters = {};
  final Map<String, List<DocShape>> _masterShapes = {};

  OfficeSlidesDoc read() {
    XmlDocument? styles;
    try {
      styles = zip.readXml('styles.xml');
    } on OfficeDocException catch (e) {
      // Испорченные стили — слайды без оформления образца, но со своим.
      if (e.kind != OfficeDocError.damaged) rethrow;
    }
    final content = zip.readXml('content.xml');
    final croot = content?.rootElement;
    if (croot == null) throw const OfficeDocException(OfficeDocError.damaged, 'no content.xml');
    final sroot = styles?.rootElement;
    for (final root in [sroot, croot]) {
      for (final f in root?.kid('font-face-decls')?.kids('font-face') ?? const <XmlElement>[]) {
        final name = f.attr('name');
        final family = f.attr('font-family');
        if (name != null && family != null) st.fontFaces[name] = family;
      }
    }
    st.addAll(sroot?.kid('styles'), st.common);
    st.addAll(sroot?.kid('automatic-styles'), st.masterAuto);
    st.addAll(croot.kid('automatic-styles'), st.contentAuto);
    for (final m in sroot?.kid('master-styles')?.kids('master-page') ?? const <XmlElement>[]) {
      final name = m.attr('name');
      if (name != null) _masters[name] = m;
    }

    final pres = croot.kid('body')?.kid('presentation');
    if (pres == null) throw const OfficeDocException(OfficeDocError.damaged, 'no office:presentation');
    final pages = pres.kids('page').toList();

    // Размер слайда — из макета страницы образца первого слайда.
    double w = 0, h = 0;
    for (final p in pages.take(1)) {
      final m = _masters[p.attr('master-page-name') ?? ''] ?? _masters.values.firstOrNull;
      final layout = st.find('page-layout', m?.attr('page-layout-name'), _Scope.master);
      final lp = layout?.kid('page-layout-properties');
      w = _len(lp?.attr('page-width')) ?? 0;
      h = _len(lp?.attr('page-height')) ?? 0;
    }
    if (!(w >= 36 && w <= 20000) || !(h >= 36 && h <= 20000)) {
      w = 720;
      h = 540;
    }

    final slides = <DocSlide>[];
    for (final page in pages) {
      final pageProps = st.props('drawing-page', page.attr('style-name'), 'drawing-page-properties', _Scope.content);
      if (page.attr('visibility') == 'hidden' || pageProps['visibility'] == 'hidden') continue;
      if (slides.length >= OfficeSlidesDoc.maxSlides) {
        _truncated = true;
        break;
      }
      try {
        slides.add(_slide(page, pageProps));
      } on OfficeDocException catch (e) {
        if (e.kind == OfficeDocError.tooLarge) _truncated = true;
        if (e.kind == OfficeDocError.encrypted || e.kind == OfficeDocError.unsupported) rethrow;
      } catch (_) {
        // Слайд, который не разобрался, — без него.
      }
    }
    return OfficeSlidesDoc(width: w, height: h, slides: slides, truncated: _truncated);
  }

  OfficeImage? _image(String? href) {
    if (href == null) return null;
    final h = href.trim();
    // Внешние картинки (http:, file:) не загружаются.
    if (h.isEmpty || h.contains(':')) return null;
    final name = OfficeZip.normalize(h);
    return _images.putIfAbsent(name, () => zip.image(name));
  }

  DocSlide _slide(XmlElement page, Map<String, String> pageProps) {
    final master = _masters[page.attr('master-page-name') ?? ''];
    final masterProps = st.props('drawing-page', master?.attr('style-name'), 'drawing-page-properties', _Scope.master);
    // Фон: свой у слайда, иначе — образца; без фона — белый.
    var bg = _fill(pageProps, _Scope.content);
    if (bg == null && pageProps['background-visible'] != 'false') bg = _fill(masterProps, _Scope.master);
    final bgColor = bg?.flatColor ?? 0xFFFFFFFF;
    final shapes = <DocShape>[];
    if (master != null && pageProps['background-objects-visible'] != 'false') {
      final key = '${master.attr('name')}|$bgColor';
      shapes.addAll(
        _masterShapes.putIfAbsent(key, () {
          final out = <DocShape>[];
          _Shapes(this, _Scope.master, bgColor).tree(master, out, 0, master: true);
          return out;
        }),
      );
    }
    _Shapes(this, _Scope.content, bgColor).tree(page, shapes, 0);
    if (shapes.length > OfficeSlidesDoc.maxShapes) {
      shapes.removeRange(OfficeSlidesDoc.maxShapes, shapes.length);
      _truncated = true;
    }
    return DocSlide(background: bg, shapes: shapes);
  }

  /// Заливка из свойств (graphic-properties, drawing-page-properties).
  DocFill? _fill(Map<String, String> p, _Scope scope) {
    final kind = p['fill'];
    final opacity = (_pct(p['opacity']) ?? 100).clamp(0.0, 100.0) / 100;
    int alpha(int c) => (((c >> 24) & 0xFF) * opacity).round() << 24 | (c & 0xFFFFFF);
    switch (kind) {
      case 'solid':
        final c = _rgb(p['fill-color']);
        return c == null ? null : DocFill.solid(alpha(c));
      case 'gradient':
        final g = st.drawing['gradient|${p['fill-gradient-name']}'];
        if (g == null) {
          final c = _rgb(p['fill-color']);
          return c == null ? null : DocFill.solid(alpha(c));
        }
        final start = alpha(_rgb(g.attr('start-color')) ?? 0xFF000000);
        final end = alpha(_rgb(g.attr('end-color')) ?? 0xFFFFFFFF);
        final style = g.attr('style') ?? 'linear';
        // Угол ODF — против часовой стрелки от «сверху вниз», в десятых
        // долях градуса («300») или с единицей («30deg»).
        final raw = (g.attr('angle') ?? '0').trim();
        double angle;
        if (raw.endsWith('deg')) {
          angle = double.tryParse(raw.substring(0, raw.length - 3)) ?? 0;
        } else if (raw.endsWith('rad')) {
          angle = (double.tryParse(raw.substring(0, raw.length - 3)) ?? 0) * 180 / math.pi;
        } else {
          angle = (double.tryParse(raw) ?? 0) / 10;
        }
        switch (style) {
          case 'axial':
            return DocFill.gradient([end, start, end], const [0, 0.5, 1], gradientAngle: 90 - angle);
          case 'radial' || 'ellipsoid' || 'square' || 'rectangular':
            return DocFill.gradient([end, start], const [0, 1], radial: true);
          default:
            return DocFill.gradient([start, end], const [0, 1], gradientAngle: 90 - angle);
        }
      case 'bitmap':
        final f = st.drawing['fill-image|${p['fill-image-name']}'];
        final img = _image(f?.attr('href'));
        if (img == null) return null;
        return DocFill.picture(img, tile: (p['repeat'] ?? 'repeat') == 'repeat');
      case 'hatch':
        final c = _rgb(p['fill-color']);
        return (p['fill-hatch-solid'] == 'true' && c != null) ? DocFill.solid(alpha(c)) : null;
    }
    return null;
  }
}

/// Фигуры одной страницы (слайда или образца).
class _Shapes {
  _Shapes(this.o, this.scope, this.bgColor);

  final _Odp o;
  final _Scope scope;

  /// Цвет фона — для «автоматического» цвета текста (чёрный на светлом,
  /// белый на тёмном, как в Impress).
  final int bgColor;
  _Styles get st => o.st;

  void tree(XmlElement parent, List<DocShape> out, int depth, {bool master = false}) {
    if (depth > OfficeLimits.maxDepth) {
      o._truncated = true;
      return;
    }
    for (final e in parent.childElements) {
      if (out.length > OfficeSlidesDoc.maxShapes) {
        o._truncated = true;
        return;
      }
      // Заполнители образца («Заголовок», «Структура», колонтитулы) не
      // рисуются: это места для текста слайдов.
      if (master && e.attr('class') != null) continue;
      try {
        switch (e.local) {
          case 'g' || 'a':
            tree(e, out, depth + 1, master: master);
          case 'frame':
            _frame(e, out);
          case 'custom-shape' || 'rect' || 'ellipse' || 'circle' || 'caption' || 'polygon' || 'polyline' || 'path':
            _shape(e, out);
          case 'line' || 'connector':
            _line(e, out);
        }
      } on OfficeDocException catch (ex) {
        if (ex.kind != OfficeDocError.damaged) rethrow;
      } catch (_) {
        // Испорченная фигура — без неё.
      }
    }
  }

  /// Свойства фигуры: стиль draw:style-name (графический) поверх стиля
  /// заполнителя presentation:style-name.
  Map<String, String> _graphic(XmlElement e) {
    final out = <String, String>{};
    out.addAll(st.props('graphic', null, 'graphic-properties', scope, withDefault: true));
    out.addAll(st.props('presentation', e.attr('style-name', ns: 'presentation'), 'graphic-properties', scope));
    out.addAll(st.props('graphic', e.attr('style-name', ns: 'drawing'), 'graphic-properties', scope));
    return out;
  }

  /// Рамка фигуры: svg:x/y/width/height и draw:transform.
  ({double x, double y, double w, double h, double rot, bool flipH})? _box(XmlElement e) {
    final w = (_len(e.attr('width')) ?? 0).abs();
    final h = (_len(e.attr('height')) ?? 0).abs();
    var x = _len(e.attr('x')) ?? 0;
    var y = _len(e.attr('y')) ?? 0;
    final t = e.attr('transform');
    if (t == null || t.trim().isEmpty) return (x: x, y: y, w: w, h: h, rot: 0, flipH: false);
    final m = _transform(t);
    if (m == null) return (x: x, y: y, w: w, h: h, rot: 0, flipH: false);
    // Центр рамки — через преобразование; оси — по его линейной части.
    final cx = x + w / 2, cy = y + h / 2;
    final px = m[0] * cx + m[2] * cy + m[4], py = m[1] * cx + m[3] * cy + m[5];
    final lu = math.sqrt(m[0] * m[0] + m[1] * m[1]), lv = math.sqrt(m[2] * m[2] + m[3] * m[3]);
    final det = m[0] * m[3] - m[1] * m[2];
    final flip = det < 0;
    final rot = (flip ? math.atan2(-m[1], -m[0]) : math.atan2(m[1], m[0])) * 180 / math.pi;
    final nw = w * lu, nh = h * lv;
    if (!px.isFinite || !py.isFinite || !nw.isFinite || !nh.isFinite) return null;
    x = px - nw / 2;
    y = py - nh / 2;
    return (x: x, y: y, w: nw, h: nh, rot: rot.abs() < 1e-6 ? 0 : rot, flipH: flip);
  }

  /// draw:transform → матрица [a b c d e f] (x' = a·x + c·y + e …): функции
  /// применяются к точке по порядку записи, углы — в радианах, против
  /// часовой стрелки на экране.
  static List<double>? _transform(String s) {
    var m = <double>[1, 0, 0, 1, 0, 0];
    List<double> mul(List<double> l, List<double> r) => [
      l[0] * r[0] + l[2] * r[1],
      l[1] * r[0] + l[3] * r[1],
      l[0] * r[2] + l[2] * r[3],
      l[1] * r[2] + l[3] * r[3],
      l[0] * r[4] + l[2] * r[5] + l[4],
      l[1] * r[4] + l[3] * r[5] + l[5],
    ];
    var count = 0;
    for (final f in RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)').allMatches(s)) {
      if (++count > 32) break;
      final args = f.group(2)!.trim().split(RegExp(r'[\s,]+')).where((a) => a.isNotEmpty).toList();
      double arg(int i) => i < args.length ? (_len(args[i]) ?? double.tryParse(args[i]) ?? 0) : 0;
      List<double>? step;
      switch (f.group(1)) {
        case 'rotate':
          final a = arg(0);
          step = [math.cos(a), -math.sin(a), math.sin(a), math.cos(a), 0, 0];
        case 'translate':
          step = [1, 0, 0, 1, arg(0), args.length > 1 ? arg(1) : 0];
        case 'scale':
          final sx = arg(0);
          step = [sx, 0, 0, args.length > 1 ? arg(1) : sx, 0, 0];
        case 'skewX':
          step = [1, 0, math.tan(arg(0)), 1, 0, 0];
        case 'skewY':
          step = [1, math.tan(arg(0)), 0, 1, 0, 0];
        case 'matrix':
          if (args.length == 6) step = [arg(0), arg(1), arg(2), arg(3), arg(4), arg(5)];
      }
      if (step != null) m = mul(step, m);
    }
    return m.every((v) => v.isFinite) ? m : null;
  }

  DocLine? _stroke(Map<String, String> g) {
    final kind = g['stroke'];
    if (kind == null || kind == 'none') return null;
    final c = _rgb(g['stroke-color']) ?? 0xFF000000;
    final op = (_pct(g['stroke-opacity']) ?? 100).clamp(0.0, 100.0) / 100;
    final color = ((0xFF * op).round() << 24) | (c & 0xFFFFFF);
    final w = (_len(g['stroke-width']) ?? 0).clamp(0.0, 200.0);
    bool marker(String n) => (g[n] ?? '').trim().isNotEmpty;
    return DocLine(
      color,
      w,
      dash: kind == 'dash' ? DocDash.dash : DocDash.solid,
      headArrow: marker('marker-start'),
      tailArrow: marker('marker-end'),
    );
  }

  void _frame(XmlElement e, List<DocShape> out) {
    // Пустой заполнитель («Щёлкните, чтобы добавить текст») не показывается.
    if (e.attr('placeholder') == 'true') return;
    final b = _box(e);
    if (b == null) return;
    final g = _graphic(e);
    var fill = o._fill(g, scope);
    var line = _stroke(g);
    DocTextBody? text;
    DocPicture? picture;
    DocTable? table;
    DocEmbed? embed;
    final tbl = e.kid('table');
    final box = e.kid('text-box');
    final image = e.kids('image').map((i) => o._image(i.attr('href'))).whereType<OfficeImage>().firstOrNull;
    final object = e.kid('object') ?? e.kid('object-ole');
    if (tbl != null) {
      table = _table(tbl, e);
      // Рамка таблицы в Impress не рисуется — только ячейки.
      fill = null;
      line = null;
    } else if (box != null) {
      final growW = g['auto-grow-width'] == 'true';
      text = _textBody(box, e, g, fill?.flatColor, wrap: !growW);
    } else if (object != null) {
      // Объект (диаграмма, формула): его картинка-заменитель — если её можно
      // нарисовать (обычно это SVM/WMF — тогда плашка).
      if (image != null) {
        picture = DocPicture(image);
      } else {
        embed = _isChart(object.attr('href')) ? DocEmbed.chart : DocEmbed.object;
      }
    } else if (e.kid('plugin') != null) {
      if (image != null) {
        picture = DocPicture(image);
      } else {
        embed = DocEmbed.media;
      }
    } else if (e.kid('image') != null) {
      if (image != null) {
        picture = DocPicture(image);
      } else {
        embed = DocEmbed.object;
      }
    }
    if (text != null && text.isEmpty) text = null;
    if (fill == null && line == null && text == null && picture == null && table == null && embed == null) return;
    out.add(
      DocShape(
        x: b.x,
        y: b.y,
        w: b.w,
        h: b.h,
        rotation: b.rot,
        flipH: b.flipH,
        fill: picture == null ? fill : null,
        line: line,
        text: text,
        picture: picture,
        table: table,
        embed: embed,
      ),
    );
  }

  bool _isChart(String? href) {
    if (href == null || href.contains(':')) return false;
    final dir = OfficeZip.normalize(href);
    final head = o.zip.readHead('$dir/content.xml', 4096);
    if (head == null) return false;
    return OfficeZip.decodeText(head.bytes).contains('office:chart');
  }

  static const _types = {
    'rectangle': DocGeom.rect,
    'flowchart-process': DocGeom.rect,
    'round-rectangle': DocGeom.roundRect,
    'flowchart-alternate-process': DocGeom.roundRect,
    'round-rectangular-callout': DocGeom.roundRect,
    'ellipse': DocGeom.ellipse,
    'circle': DocGeom.ellipse,
    'flowchart-connector': DocGeom.ellipse,
    'round-callout': DocGeom.ellipse,
    'isosceles-triangle': DocGeom.triangle,
    'right-triangle': DocGeom.rtTriangle,
    'diamond': DocGeom.diamond,
    'flowchart-decision': DocGeom.diamond,
    'parallelogram': DocGeom.parallelogram,
    'flowchart-data': DocGeom.parallelogram,
    'trapezoid': DocGeom.trapezoid,
    'pentagon': DocGeom.pentagon,
    'hexagon': DocGeom.hexagon,
    'octagon': DocGeom.octagon,
    'pentagon-right': DocGeom.homePlate,
    'chevron': DocGeom.chevron,
    'right-arrow': DocGeom.rightArrow,
    'left-arrow': DocGeom.leftArrow,
    'up-arrow': DocGeom.upArrow,
    'down-arrow': DocGeom.downArrow,
    'left-right-arrow': DocGeom.leftRightArrow,
    'cross': DocGeom.plus,
    'star5': DocGeom.star5,
  };

  void _shape(XmlElement e, List<DocShape> out) {
    final b = _box(e);
    if (b == null) return;
    final g = _graphic(e);
    var geom = DocGeom.rect;
    double? adjust;
    DocPath? path;
    var flipH = b.flipH, flipV = false;
    switch (e.local) {
      case 'ellipse' || 'circle':
        geom = DocGeom.ellipse;
      case 'rect':
        final r = _len(e.attr('corner-radius')) ?? 0;
        if (r > 0) {
          geom = DocGeom.roundRect;
          final m = math.min(b.w, b.h);
          adjust = m > 0 ? (r / m).clamp(0.0, 0.5) : 0;
        }
      case 'polygon' || 'polyline':
        path = _points(e.attr('points'), e.attr('viewBox'), filled: e.local == 'polygon');
        if (path != null) geom = DocGeom.path;
      case 'path':
        path = _svgPath(e.attr('d'), e.attr('viewBox'));
        if (path != null) geom = DocGeom.path;
      case 'custom-shape':
        final eg = e.kid('enhanced-geometry');
        final type = eg?.attr('type') ?? 'rectangle';
        final mods = (eg?.attr('modifiers') ?? '').trim().split(RegExp(r'\s+'));
        final mod0 = mods.isEmpty ? null : double.tryParse(mods.first);
        flipH ^= eg?.attr('mirror-horizontal') == 'true';
        flipV = eg?.attr('mirror-vertical') == 'true';
        final preset = type.startsWith('ooxml-') ? docPresetGeometry[type.substring(6)] : null;
        if (preset != null) {
          geom = preset;
          if (mod0 != null && (geom == DocGeom.roundRect || geom == DocGeom.homePlate || geom == DocGeom.chevron)) {
            adjust = (mod0 / 100000).clamp(0.0, 1.0);
          }
        } else if (_types.containsKey(type)) {
          geom = _types[type]!;
          // Параметры форм Impress — в единицах 21600 от меньшей стороны.
          if (geom == DocGeom.roundRect) adjust = ((mod0 ?? 3600) / 21600).clamp(0.0, 0.5);
        } else {
          // Свой контур (полилиния из PowerPoint — «ooxml-non-primitive»):
          // числа без формул; область координат — svg:viewBox, а если он
          // пустой — drawooo:sub-view-size.
          path = _enhancedPath(eg?.attr('enhanced-path'), eg?.attr('viewBox'), eg?.attr('sub-view-size'));
          if (path != null) geom = DocGeom.path;
        }
    }
    final fill = (path != null && !path.filled) ? null : o._fill(g, scope);
    final line = _stroke(g);
    final text = _textBody(e, e, g, fill?.flatColor, wrap: g['wrap-option'] != 'no-wrap');
    final body = text == null || text.isEmpty ? null : text;
    if (fill == null && line == null && body == null) return;
    out.add(
      DocShape(
        x: b.x,
        y: b.y,
        w: b.w,
        h: b.h,
        rotation: b.rot,
        flipH: flipH,
        flipV: flipV,
        geom: geom,
        adjust: adjust,
        path: path,
        fill: fill,
        line: line,
        text: body,
      ),
    );
  }

  void _line(XmlElement e, List<DocShape> out) {
    final x1 = _len(e.attr('x1')) ?? 0, y1 = _len(e.attr('y1')) ?? 0;
    final x2 = _len(e.attr('x2')) ?? 0, y2 = _len(e.attr('y2')) ?? 0;
    final line = _stroke(_graphic(e));
    if (line == null) return;
    out.add(
      DocShape(
        x: math.min(x1, x2),
        y: math.min(y1, y2),
        w: (x2 - x1).abs(),
        h: (y2 - y1).abs(),
        flipH: x2 < x1,
        flipV: y2 < y1,
        geom: DocGeom.line,
        line: line,
      ),
    );
  }

  /// svg:viewBox «x y w h».
  static List<double>? _viewBox(String? vb) {
    final v = (vb ?? '').trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
    if (v.length != 4 || v.any((x) => x == null)) return null;
    final w = v[2]!, h = v[3]!;
    return [v[0]!, v[1]!, w == 0 ? 1 : w, h == 0 ? 1 : h];
  }

  DocPath? _points(String? points, String? viewBox, {required bool filled}) {
    final vb = _viewBox(viewBox);
    if (vb == null || points == null) return null;
    final nums = points.trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
    final ops = <DocPathOp>[];
    final pts = <double>[];
    for (var i = 0; i + 1 < nums.length && ops.length < 5000; i += 2) {
      final x = nums[i], y = nums[i + 1];
      if (x == null || y == null) return null;
      ops.add(ops.isEmpty ? DocPathOp.move : DocPathOp.line);
      pts.addAll([(x - vb[0]) / vb[2], (y - vb[1]) / vb[3]]);
    }
    if (ops.length < 2) return null;
    if (filled) ops.add(DocPathOp.close);
    return DocPath(ops, pts, filled: filled);
  }

  /// svg:d (SVG: M L H V C S Q T Z, большие — абсолютные, малые —
  /// относительные; дуга A — отрезком до её конца).
  DocPath? _svgPath(String? d, String? viewBox) {
    final vb = _viewBox(viewBox);
    if (vb == null || d == null) return null;
    final tokens = RegExp(
      r'[MmLlHhVvCcSsQqTtAaZz]|-?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?',
    ).allMatches(d).map((m) => m[0]!).toList();
    final ops = <DocPathOp>[];
    final pts = <double>[];
    var i = 0;
    var cmd = 'M';
    var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
    double? lastC2x, lastC2y;
    double nx(double x) => (x - vb[0]) / vb[2];
    double ny(double y) => (y - vb[1]) / vb[3];
    bool isNum(int k) => k < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[k]);
    double take() => double.parse(tokens[i++]);
    var filled = false;
    while (i < tokens.length && ops.length < 5000) {
      if (!isNum(i)) cmd = tokens[i++];
      final rel = cmd == cmd.toLowerCase();
      final c = cmd.toUpperCase();
      double ox() => rel ? cx : 0;
      double oy() => rel ? cy : 0;
      switch (c) {
        case 'M' || 'L':
          if (!isNum(i) || !isNum(i + 1)) return ops.isEmpty ? null : DocPath(ops, pts, filled: filled);
          final x = take() + ox(), y = take() + oy();
          ops.add(c == 'M' ? DocPathOp.move : DocPathOp.line);
          pts.addAll([nx(x), ny(y)]);
          (cx, cy) = (x, y);
          if (c == 'M') {
            (sx, sy) = (x, y);
            cmd = rel ? 'l' : 'L';
          }
          lastC2x = null;
        case 'H' || 'V':
          if (!isNum(i)) return null;
          final v = take();
          if (c == 'H') {
            cx = v + ox();
          } else {
            cy = v + oy();
          }
          ops.add(DocPathOp.line);
          pts.addAll([nx(cx), ny(cy)]);
          lastC2x = null;
        case 'C' || 'S' || 'Q' || 'T':
          final n = switch (c) {
            'C' => 6,
            'S' || 'Q' => 4,
            _ => 2,
          };
          for (var k = 0; k < n; k++) {
            if (!isNum(i + k)) return null;
          }
          double c1x, c1y, c2x, c2y, ex, ey;
          if (c == 'C') {
            c1x = take() + ox();
            c1y = take() + oy();
            c2x = take() + ox();
            c2y = take() + oy();
            ex = take() + ox();
            ey = take() + oy();
          } else if (c == 'S') {
            c1x = lastC2x == null ? cx : 2 * cx - lastC2x;
            c1y = lastC2y == null ? cy : 2 * cy - lastC2y;
            c2x = take() + ox();
            c2y = take() + oy();
            ex = take() + ox();
            ey = take() + oy();
          } else {
            double qx, qy;
            if (c == 'Q') {
              qx = take() + ox();
              qy = take() + oy();
            } else {
              qx = cx;
              qy = cy;
            }
            ex = take() + ox();
            ey = take() + oy();
            c1x = cx + 2 / 3 * (qx - cx);
            c1y = cy + 2 / 3 * (qy - cy);
            c2x = ex + 2 / 3 * (qx - ex);
            c2y = ey + 2 / 3 * (qy - ey);
          }
          ops.add(DocPathOp.cubic);
          pts.addAll([nx(c1x), ny(c1y), nx(c2x), ny(c2y), nx(ex), ny(ey)]);
          (cx, cy) = (ex, ey);
          (lastC2x, lastC2y) = (c2x, c2y);
        case 'A':
          for (var k = 0; k < 7; k++) {
            if (!isNum(i + k)) return null;
          }
          i += 5;
          cx = take() + ox();
          cy = take() + oy();
          ops.add(DocPathOp.line);
          pts.addAll([nx(cx), ny(cy)]);
          lastC2x = null;
        case 'Z':
          ops.add(DocPathOp.close);
          filled = true;
          (cx, cy) = (sx, sy);
          lastC2x = null;
        default:
          return null;
      }
    }
    if (ops.isEmpty) return null;
    return DocPath(ops, pts, filled: filled);
  }

  /// draw:enhanced-path без формул (только числа): M L C Z N F S, Q.
  DocPath? _enhancedPath(String? d, String? viewBox, String? subView) {
    if (d == null || d.contains('?') || d.contains(r'$')) return null;
    var box = _viewBox(viewBox);
    if (box == null || box[2] <= 1 || box[3] <= 1) box = _viewBox('0 0 ${subView ?? ''}');
    if (box == null || box[2] <= 1 || box[3] <= 1) return null;
    final vb = box;
    final tokens = d.trim().split(RegExp(r'[\s,]+'));
    final ops = <DocPathOp>[];
    final pts = <double>[];
    var i = 0;
    var cmd = 'M';
    var filled = true;
    double nx(double x) => (x - vb[0]) / vb[2];
    double ny(double y) => (y - vb[1]) / vb[3];
    while (i < tokens.length && ops.length < 5000) {
      final t = tokens[i];
      if (double.tryParse(t) == null) {
        cmd = t;
        i++;
        if (cmd == 'Z') ops.add(DocPathOp.close);
        if (cmd == 'F') filled = false;
        if (cmd == 'Z' || cmd == 'N' || cmd == 'F' || cmd == 'S') continue;
        if (!const {'M', 'L', 'C', 'Q'}.contains(cmd)) return null;
        continue;
      }
      final n = switch (cmd) {
        'C' => 6,
        'Q' => 4,
        _ => 2,
      };
      if (i + n > tokens.length) break;
      final v = [for (var k = 0; k < n; k++) double.tryParse(tokens[i + k])];
      if (v.any((x) => x == null)) return null;
      i += n;
      if (cmd == 'C') {
        ops.add(DocPathOp.cubic);
        pts.addAll([nx(v[0]!), ny(v[1]!), nx(v[2]!), ny(v[3]!), nx(v[4]!), ny(v[5]!)]);
      } else if (cmd == 'Q') {
        // Квадратичная — отрезком до конца: в формах Impress без формул редкость.
        ops.add(DocPathOp.line);
        pts.addAll([nx(v[2]!), ny(v[3]!)]);
      } else {
        ops.add(cmd == 'M' ? DocPathOp.move : DocPathOp.line);
        pts.addAll([nx(v[0]!), ny(v[1]!)]);
        if (cmd == 'M') cmd = 'L';
      }
    }
    if (ops.isEmpty) return null;
    return DocPath(ops, pts, filled: filled);
  }

  // ─────────────────────────────── текст ───────────────────────────────

  /// Оформление текста фигуры: стиль по умолчанию → заполнитель (для уровня
  /// [level] структуры — «…-outlineN») → графический стиль →
  /// draw:text-style-name.
  _TextBase _base(XmlElement shape, {int level = 1, String? outlinePrefix}) {
    final para = <String, String>{};
    final text = <String, String>{};
    final presName = outlinePrefix != null && level > 1
        ? '$outlinePrefix$level'
        : shape.attr('style-name', ns: 'presentation');
    final drawName = shape.attr('style-name', ns: 'drawing');
    String? outline;
    XmlElement? list;
    // Стиль по умолчанию → заполнитель → графический стиль → draw:text-style-name.
    _Styles.mergeInto(text, st.defaults['graphic'], 'text-properties');
    _Styles.mergeInto(para, st.defaults['graphic'], 'paragraph-properties');
    for (final (family, name) in [('presentation', presName), ('graphic', drawName)]) {
      para.addAll(st.props(family, name, 'paragraph-properties', scope));
      _mergeText(text, st.props(family, name, 'text-properties', scope));
      // Список стиля фигуры: text:list-style внутри graphic-properties или
      // style:list-style-name.
      var s = st.find(family, name, scope);
      var guard = 0;
      while (s != null && guard++ < OfficeLimits.maxDepth) {
        final sn = s.attr('name') ?? '';
        if (family == 'presentation' && sn.endsWith('-outline1')) outline = sn.substring(0, sn.length - 1);
        list ??= s.kid('graphic-properties')?.kid('list-style') ?? st.find('list', s.attr('list-style-name'), scope);
        s = st.find(family, s.attr('parent-style-name'), scope);
      }
    }
    final ts = shape.attr('text-style-name');
    if (ts != null) {
      para.addAll(st.props('paragraph', ts, 'paragraph-properties', scope));
      _mergeText(text, st.props('paragraph', ts, 'text-properties', scope));
    }
    return _TextBase(shape, para, text, outlinePrefix ?? outline, list);
  }

  /// Размер шрифта в процентах — от текущего; остальное — поверх.
  static void _mergeText(Map<String, String> into, Map<String, String> from) {
    from.forEach((k, v) {
      if (k == 'font-size') {
        final pct = _pct(v);
        if (pct != null) {
          into[k] = '${(_len(into[k]) ?? 18) * pct / 100}pt';
          return;
        }
      }
      into[k] = v;
    });
  }

  DocTextBody? _textBody(
    XmlElement container,
    XmlElement shape,
    Map<String, String> g,
    int? fillColor, {
    required bool wrap,
  }) {
    final base = _base(shape);
    final paragraphs = <DocParagraph>[];
    // Цвет «автоматического» текста — по заливке фигуры, иначе по фону слайда.
    final under = fillColor != null && (fillColor >> 24) > 0x80 ? fillColor : bgColor;
    final auto = _dark(under) ? 0xFFFFFFFF : 0xFF000000;
    _blocks(container, base, paragraphs, auto, 0, null, 0);
    final anchor = switch (g['textarea-vertical-align']) {
      'middle' => DocAnchor.middle,
      'bottom' => DocAnchor.bottom,
      _ => DocAnchor.top,
    };
    double pad(String n) =>
        (_len(g['padding-$n']) ?? _len(g['padding']) ?? (n == 'left' || n == 'right' ? 7.2 : 3.6)).clamp(0.0, 500.0);
    return DocTextBody(
      insetLeft: pad('left'),
      insetTop: pad('top'),
      insetRight: pad('right'),
      insetBottom: pad('bottom'),
      anchor: anchor,
      wrap: wrap,
      shrink: g['shrink-to-fit'] == 'true' || g['fit-to-size'] == 'shrink-to-fit',
      paragraphs: paragraphs,
    );
  }

  static bool _dark(int c) {
    final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
    return 0.299 * r + 0.587 * g + 0.114 * b < 128;
  }

  /// Абзацы и списки контейнера (text-box, ячейка, фигура) по порядку.
  void _blocks(
    XmlElement parent,
    _TextBase base,
    List<DocParagraph> out,
    int auto,
    int level,
    XmlElement? list,
    int depth,
  ) {
    if (depth > OfficeLimits.maxDepth) return;
    for (final e in parent.childElements) {
      if (out.length >= OdpReader.maxParagraphs) {
        o._truncated = true;
        return;
      }
      switch (e.local) {
        case 'p' || 'h':
          out.add(_paragraph(e, base, auto, 0, null, null));
        case 'list':
          _list(
            e,
            base,
            out,
            auto,
            level + 1,
            st.find('list', e.attr('style-name'), scope) ?? list ?? base.listStyle,
            depth + 1,
          );
      }
    }
  }

  void _list(XmlElement l, _TextBase base, List<DocParagraph> out, int auto, int level, XmlElement? style, int depth) {
    if (depth > OfficeLimits.maxDepth) return;
    var n = 0;
    for (final item in l.childElements) {
      final header = item.local == 'list-header';
      if (item.local != 'list-item' && !header) continue;
      if (!header) n++;
      for (final e in item.childElements) {
        if (out.length >= OdpReader.maxParagraphs) {
          o._truncated = true;
          return;
        }
        switch (e.local) {
          case 'p' || 'h':
            out.add(_paragraph(e, base, auto, level, header ? null : style, n));
          case 'list':
            _list(e, base, out, auto, level + 1, st.find('list', e.attr('style-name'), scope) ?? style, depth + 1);
        }
      }
    }
  }

  DocParagraph _paragraph(XmlElement p, _TextBase base, int auto, int level, XmlElement? listStyle, int? number) {
    // Уровень N структуры — свой стиль «…-outlineN» (размер, отступы).
    final prefix = base.outlinePrefix;
    final lb = prefix != null && level > 1
        ? base.levels.putIfAbsent(level, () => _base(base.shape, level: level.clamp(1, 9), outlinePrefix: prefix))
        : base;
    var para = Map<String, String>.of(lb.para);
    var text = Map<String, String>.of(lb.text);
    final ps = p.attr('style-name');
    if (ps != null) {
      para = {...para, ...st.props('paragraph', ps, 'paragraph-properties', scope)};
      final t = Map<String, String>.of(text);
      _mergeText(t, st.props('paragraph', ps, 'text-properties', scope));
      text = t;
    }
    final runs = <DocRun>[];
    _inline(p, text, runs, auto, null, 0, true);
    final paraSize = _len(text['font-size']) ?? 18;

    // Маркер и отступы списка.
    DocBullet? bullet;
    var marginLeft = _len(para['margin-left']) ?? 0;
    var indent = _len(para['text-indent']) ?? 0;
    final lvl = listStyle?.childElements.where((e) => e.attr('level') == '${level.clamp(1, 10)}').firstOrNull;
    if (lvl != null) {
      final lp = lvl.kid('list-level-properties');
      final align = lp?.kid('list-level-label-alignment');
      if (align != null) {
        marginLeft += _len(align.attr('margin-left')) ?? 0;
        indent = _len(align.attr('text-indent')) ?? indent;
      } else {
        final before = _len(lp?.attr('space-before')) ?? 0;
        final label = _len(lp?.attr('min-label-width')) ?? 0;
        marginLeft += before + label;
        indent = -label;
      }
      final tp = <String, String>{};
      _Styles.mergeInto(tp, lvl, 'text-properties');
      final scale = ((_pct(tp['font-size']) ?? 100) / 100).clamp(0.25, 4.0);
      final color = tp['use-window-font-color'] == 'true' ? null : _rgb(tp['color']);
      final font = st.font(tp);
      String? label;
      if (lvl.local == 'list-level-style-bullet') {
        final ch = lvl.attr('bullet-char') ?? '';
        label = ch.isEmpty ? null : ch;
      } else if (lvl.local == 'list-level-style-number') {
        final fmt = lvl.attr('num-format') ?? '';
        if (fmt.isNotEmpty) {
          final start = int.tryParse(lvl.attr('start-value') ?? '') ?? 1;
          label =
              '${lvl.attr('num-prefix') ?? ''}${_number(fmt, start + (number ?? 1) - 1)}${lvl.attr('num-suffix') ?? ''}';
        }
      } else if (lvl.local == 'list-level-style-image') {
        label = '•';
      }
      final hasText = runs.any((r) => r.text.trim().isNotEmpty);
      if (label != null && hasText) {
        bullet = DocBullet(
          label,
          color: color,
          sizeScale: scale,
          font: font == 'OpenSymbol' || font == 'StarSymbol' ? null : font,
        );
      }
    }
    final align = switch (para['text-align']) {
      'center' => DocAlign.center,
      'end' || 'right' => DocAlign.right,
      'justify' => DocAlign.justify,
      _ => DocAlign.left,
    };
    var lineSpacing = 1.0;
    double? lineExact;
    final lh = para['line-height'];
    if (lh != null && lh != 'normal') {
      final pct = _pct(lh);
      if (pct != null) {
        lineSpacing = (pct / 100).clamp(0.1, 10.0);
      } else {
        lineExact = _len(lh)?.clamp(1.0, 1000.0);
      }
    }
    return DocParagraph(
      align: align,
      level: math.max(0, level - 1),
      marginLeft: marginLeft.clamp(0.0, 2000.0),
      indent: indent.clamp(-2000.0, 2000.0),
      bullet: bullet,
      spaceBefore: (_len(para['margin-top']) ?? 0).clamp(0.0, 1000.0),
      spaceAfter: (_len(para['margin-bottom']) ?? 0).clamp(0.0, 1000.0),
      lineSpacing: lineSpacing,
      lineExact: lineExact,
      endSize: paraSize.clamp(1.0, 400.0),
      runs: runs,
    );
  }

  static String _number(String fmt, int n) {
    switch (fmt) {
      case 'a' || 'A':
        final out = StringBuffer();
        var v = n;
        while (v > 0 && out.length < 8) {
          v--;
          out.write(String.fromCharCode((fmt == 'a' ? 0x61 : 0x41) + v % 26));
          v ~/= 26;
        }
        return out.toString().split('').reversed.join();
      case 'i' || 'I':
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
        return fmt == 'i' ? out.toString().toLowerCase() : out.toString();
      default:
        return '$n';
    }
  }

  /// Текст абзаца: span (вложенные), a, s, tab, line-break, поля.
  void _inline(
    XmlElement el,
    Map<String, String> tp,
    List<DocRun> runs,
    int auto,
    String? href,
    int depth,
    bool first,
  ) {
    if (depth > OfficeLimits.maxDepth) return;
    var atStart = first;
    for (final n in el.children) {
      if (n is XmlText || n is XmlCDATA) {
        // Пробелы ODF: подряд — как один (как в HTML), в начале абзаца — нет.
        var t = (n.value ?? '').replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
        if (atStart) t = t.trimLeft();
        if (t.isEmpty) continue;
        _addRun(runs, t, tp, auto, href);
        atStart = false;
        continue;
      }
      if (n is! XmlElement) continue;
      switch (n.local) {
        case 'span':
          final t = Map<String, String>.of(tp);
          _mergeText(t, st.props('text', n.attr('style-name'), 'text-properties', scope));
          final before = runs.length;
          _inline(n, t, runs, auto, href, depth + 1, atStart);
          if (runs.length > before) atStart = false;
        case 'a':
          final before = runs.length;
          _inline(n, tp, runs, auto, docSafeHref(n.attr('href')), depth + 1, atStart);
          if (runs.length > before) atStart = false;
        case 's':
          final c = (int.tryParse(n.attr('c') ?? '1') ?? 1).clamp(1, 200);
          _addRun(runs, ' ' * c, tp, auto, href);
          atStart = false;
        case 'tab':
          _addRun(runs, '\t', tp, auto, href);
          atStart = false;
        case 'line-break':
          _addRun(runs, '\n', tp, auto, href);
          atStart = true;
        case 'soft-page-break' ||
            'bookmark' ||
            'bookmark-start' ||
            'bookmark-end' ||
            'annotation' ||
            'annotation-end' ||
            'note':
          break;
        default:
          // Поля (номер слайда, дата, автор) — их сохранённый текст.
          final before = runs.length;
          _inline(n, tp, runs, auto, href, depth + 1, atStart);
          if (runs.length > before) atStart = false;
      }
    }
  }

  void _addRun(List<DocRun> runs, String text, Map<String, String> tp, int auto, String? href) {
    if (runs.length >= 2000) {
      o._truncated = true;
      return;
    }
    final weight = tp['font-weight'] ?? 'normal';
    final bold = weight == 'bold' || (int.tryParse(weight) ?? 400) >= 600;
    final pos = (tp['text-position'] ?? '').trim();
    var baseline = 0.0;
    if (pos.startsWith('super')) {
      baseline = 33;
    } else if (pos.startsWith('sub')) {
      baseline = -33;
    } else if (pos.isNotEmpty) {
      baseline = (_pct(pos.split(RegExp(r'\s+')).first) ?? 0).clamp(-100.0, 100.0);
    }
    var t = text;
    if (tp['text-transform'] == 'uppercase') t = t.toUpperCase();
    if (tp['text-transform'] == 'lowercase') t = t.toLowerCase();
    var color = tp['use-window-font-color'] == 'true' && !tp.containsKey('color') ? auto : (_rgb(tp['color']) ?? auto);
    final under = (tp['text-underline-style'] ?? 'none') != 'none' || href != null;
    if (href != null && !tp.containsKey('color')) color = 0xFF0563C1;
    runs.add(
      DocRun(
        t,
        size: (_len(tp['font-size']) ?? 18).clamp(1.0, 400.0),
        color: color,
        bold: bold,
        italic: tp['font-style'] == 'italic' || tp['font-style'] == 'oblique',
        underline: under,
        strike: (tp['text-line-through-style'] ?? 'none') != 'none',
        baseline: baseline,
        font: st.font(tp),
        highlight: tp['background-color'] == null || tp['background-color'] == 'transparent'
            ? null
            : _rgb(tp['background-color']),
        href: href,
      ),
    );
  }

  // ─────────────────────────────── таблицы ───────────────────────────────

  DocTable? _table(XmlElement t, XmlElement frame) {
    final cols = <double>[];
    final colCellStyle = <String?>[];
    void addCol(XmlElement c) {
      final rep = (int.tryParse(c.attr('number-columns-repeated') ?? '1') ?? 1).clamp(1, OdpReader.maxTableCols);
      final w = _len(st.props('table-column', c.attr('style-name'), 'table-column-properties', scope)['column-width']);
      for (var i = 0; i < rep && cols.length < OdpReader.maxTableCols; i++) {
        cols.add((w ?? 0).clamp(0.0, 20000.0));
        colCellStyle.add(c.attr('default-cell-style-name'));
      }
    }

    final rowEls = <XmlElement>[];
    void walk(XmlElement p, int depth) {
      if (depth > 4) return;
      for (final c in p.childElements) {
        switch (c.local) {
          case 'table-column':
            addCol(c);
          case 'table-columns' || 'table-header-columns' || 'table-column-group':
            walk(c, depth + 1);
          case 'table-row':
            final rep = (int.tryParse(c.attr('number-rows-repeated') ?? '1') ?? 1).clamp(1, OdpReader.maxTableRows);
            for (var i = 0; i < rep && rowEls.length <= OdpReader.maxTableRows; i++) {
              rowEls.add(c);
            }
          case 'table-rows' || 'table-header-rows' || 'table-row-group':
            walk(c, depth + 1);
        }
      }
    }

    walk(t, 0);
    if (rowEls.length > OdpReader.maxTableRows) {
      rowEls.removeRange(OdpReader.maxTableRows, rowEls.length);
      o._truncated = true;
    }
    if (rowEls.isEmpty) return null;
    // Столбцы без ширины — поровну по ширине рамки.
    final frameW = (_len(frame.attr('width')) ?? 0).abs();
    var nCols = cols.length;
    if (nCols == 0) {
      for (final r in rowEls) {
        var n = 0;
        for (final c in r.childElements) {
          if (c.local == 'table-cell' || c.local == 'covered-table-cell') {
            n += (int.tryParse(c.attr('number-columns-repeated') ?? '1') ?? 1).clamp(1, OdpReader.maxTableCols);
          }
        }
        nCols = math.max(nCols, math.min(n, OdpReader.maxTableCols));
      }
      if (nCols == 0) return null;
      cols.addAll(List.filled(nCols, frameW / nCols));
      colCellStyle.addAll(List.filled(nCols, null));
    }
    if (cols.every((w) => w == 0)) {
      for (var i = 0; i < cols.length; i++) {
        cols[i] = frameW / cols.length;
      }
    }
    final frameH = (_len(frame.attr('height')) ?? 0).abs();
    final rows = <double>[];
    for (final r in rowEls) {
      final rp = st.props('table-row', r.attr('style-name'), 'table-row-properties', scope);
      rows.add((_len(rp['row-height']) ?? _len(rp['min-row-height']) ?? frameH / rowEls.length).clamp(0.0, 20000.0));
    }
    final base = _base(frame);
    final cells = <DocCell>[];
    for (var ri = 0; ri < rowEls.length; ri++) {
      final row = rowEls[ri];
      var ci = 0;
      for (final c in row.childElements) {
        if (c.local != 'table-cell' && c.local != 'covered-table-cell') continue;
        final rep = (int.tryParse(c.attr('number-columns-repeated') ?? '1') ?? 1).clamp(1, OdpReader.maxTableCols);
        for (var k = 0; k < rep && ci < cols.length; k++) {
          final col = ci++;
          if (c.local == 'covered-table-cell') continue;
          final colSpan = (int.tryParse(c.attr('number-columns-spanned') ?? '1') ?? 1).clamp(1, cols.length - col);
          final rowSpan = (int.tryParse(c.attr('number-rows-spanned') ?? '1') ?? 1).clamp(1, rowEls.length - ri);
          final styleName = c.attr('style-name') ?? row.attr('default-cell-style-name') ?? colCellStyle[col];
          final p = <String, String>{};
          for (final kind in ['graphic-properties', 'paragraph-properties', 'table-cell-properties']) {
            p.addAll(st.props('table-cell', styleName, kind, scope));
          }
          DocFill? fill = o._fill(p, scope);
          final bgc = p['background-color'];
          if (fill == null && bgc != null && bgc != 'transparent') {
            final v = _rgb(bgc);
            if (v != null) fill = DocFill.solid(v);
          }
          DocLine? border(String side) => _border(p['border-$side'] ?? p['border']);
          final anchor = switch (p['textarea-vertical-align'] ?? p['vertical-align']) {
            'middle' => DocAnchor.middle,
            'bottom' => DocAnchor.bottom,
            _ => DocAnchor.top,
          };
          double pad(String n) =>
              (_len(p['padding-$n']) ?? _len(p['padding']) ?? (n == 'left' || n == 'right' ? 7.2 : 3.6)).clamp(
                0.0,
                200.0,
              );
          final paragraphs = <DocParagraph>[];
          final under = fill?.flatColor ?? bgColor;
          _blocks(c, base, paragraphs, _dark(under) ? 0xFFFFFFFF : 0xFF000000, 0, null, 0);
          final text = DocTextBody(
            insetLeft: pad('left'),
            insetTop: pad('top'),
            insetRight: pad('right'),
            insetBottom: pad('bottom'),
            anchor: anchor,
            paragraphs: paragraphs,
          );
          cells.add(
            DocCell(
              row: ri,
              col: col,
              rowSpan: rowSpan,
              colSpan: colSpan,
              fill: fill,
              left: border('left'),
              right: border('right'),
              top: border('top'),
              bottom: border('bottom'),
              text: text.isEmpty ? null : text,
            ),
          );
        }
      }
    }
    return DocTable(columns: cols, rows: rows, cells: cells);
  }

  /// fo:border «0.5pt solid #000000».
  static DocLine? _border(String? s) {
    if (s == null) return null;
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.contains('none') || parts.contains('hidden')) return null;
    double? w;
    int? c;
    var dash = DocDash.solid;
    for (final p in parts) {
      w ??= _len(p);
      c ??= _rgb(p);
      if (p == 'dashed') dash = DocDash.dash;
      if (p == 'dotted') dash = DocDash.dot;
    }
    if ((w ?? 1) <= 0) return null;
    return DocLine(c ?? 0xFF000000, (w ?? 0.75).clamp(0.0, 50.0), dash: dash);
  }
}

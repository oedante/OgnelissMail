// lib/services/documents/xlsx_reader.dart
// Книга Excel (XLSX, XLSM, шаблоны) → листы для показа сеткой (1.11.x,
// предпросмотр документов, план владельца 04.11.2026). По ECMA-376
// (SpreadsheetML): переходный и «строгий» варианты читаются одинаково —
// элементы и атрибуты по локальным именам.
//
// Что читается:
//  · workbook.xml — листы (скрытые пропускаются), система дат 1904,
//    открытый лист; связи книги — части листов, стилей, строк, темы;
//  · sharedStrings.xml — общие строки (бывает в десятки мегабайт — событиями;
//    фонетика rPh пропускается, «_x000D_» раскодируется);
//  · styles.xml — форматы чисел, шрифты, заливки, рамки, выравнивание;
//    цвета — RGB, из темы (с оттенком tint) и из палитры по номеру;
//  · лист — событиями по началу части: ширины столбцов, высоты и скрытые
//    строки, закрепление (pane frozen), линии сетки, ячейки, объединения.
// Формулы не вычисляются: показывается сохранённое в файле значение (как в
// «Защищённом просмотре» Excel). Диаграммы, картинки, примечания, условное
// форматирование — не показываются.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'doc_sheets.dart';
import 'office_package.dart';
import 'sheet_format.dart';

class XlsxReader {
  XlsxReader._();

  /// Разобрать книгу. Ошибки — только [OfficeDocException]: повреждённая
  /// книга — [OfficeDocError.damaged]; испорченный лист или стили — без них.
  static OfficeSheetsDoc read(OfficeZip zip, {String lang = 'en'}) {
    try {
      return _Xlsx(zip, SheetLocale.of(lang)).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, 'xlsx: $e');
    }
  }

  /// Ширина столбца Excel (в «знаках» шрифта по умолчанию, с полями) →
  /// точки: ECMA-376 18.3.1.13 при ширине цифры 7 точек (Calibri 11).
  static double colWidthPx(double width) => (width * 7 + 0.49).floorToDouble();
}

class _Font {
  final bool b, i, u, s;
  final double? px;
  final int? color;
  const _Font(this.b, this.i, this.u, this.s, this.px, this.color);
}

class _Borders {
  final DocBorder? l, t, r, b;
  const _Borders(this.l, this.t, this.r, this.b);
}

class _Xf {
  final int numFmt, font, fill, border;
  final DocHAlign h;
  final DocVAlign v;
  final bool wrap;
  final double indent;
  const _Xf(this.numFmt, this.font, this.fill, this.border, this.h, this.v, this.wrap, this.indent);
}

class _Xlsx {
  _Xlsx(this.zip, this.loc);

  final OfficeZip zip;
  final SheetLocale loc;
  final book = DocBookBuilder();
  bool date1904 = false;

  List<String> sst = const [];
  bool sstTruncated = false;

  // Стили.
  final Map<int, String> numFmts = {};
  List<_Font> fonts = const [];
  List<int?> fills = const [];
  List<_Borders> borders = const [];
  List<_Xf> xfs = const [];
  List<int> themeColors = _defaultTheme;
  List<int> palette = excelPalette;
  final Map<int, int> _xfStyle = {};
  final Map<int, SheetNumberFormat> _xfFormat = {};

  /// Цвета темы Office 2013+ в порядке номеров SpreadsheetML: lt1, dk1,
  /// lt2, dk2, accent1–6, hlink, folHlink (первые две пары переставлены
  /// относительно clrScheme — так в спецификации).
  static const _defaultTheme = [
    0xFFFFFFFF, 0xFF000000, 0xFFE7E6E6, 0xFF44546A, 0xFF4472C4, 0xFFED7D31, //
    0xFFA5A5A5, 0xFFFFC000, 0xFF5B9BD5, 0xFF70AD47, 0xFF0563C1, 0xFF954F72,
  ];

  OfficeSheetsDoc read() {
    final wbPart = zip.officeDocumentPart() ?? zip.find('xl/workbook.xml');
    if (wbPart == null) throw const OfficeDocException(OfficeDocError.damaged, 'no workbook');
    final XmlDocument? wb;
    try {
      wb = _smallXml(wbPart, required: true);
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.tooLarge) throw const OfficeDocException(OfficeDocError.damaged, 'workbook');
      rethrow;
    }
    if (wb == null) throw const OfficeDocException(OfficeDocError.damaged, 'workbook');
    final root = wb.rootElement;
    final pr = root.kid('workbookPr');
    date1904 = _true(pr?.attr('date1904'));
    final activeTab = int.tryParse(root.kid('bookViews')?.kid('workbookView')?.attr('activeTab') ?? '') ?? 0;
    final rels = zip.rels(wbPart);
    String? part(String type, String fallback) {
      for (final r in rels.values) {
        if (!r.external && r.isType(type) && zip.has(r.target)) return zip.find(r.target);
      }
      return zip.find(fallback);
    }

    _readTheme(part('theme', 'xl/theme/theme1.xml'));
    _readStyles(part('styles', 'xl/styles.xml'));
    _readSst(part('sharedStrings', 'xl/sharedStrings.xml'));

    final entries = <({String name, String part, int index})>[];
    var index = 0;
    for (final s in root.kid('sheets')?.kids('sheet') ?? const <XmlElement>[]) {
      final i = index++;
      final state = (s.attr('state') ?? '').toLowerCase();
      if (state == 'hidden' || state == 'veryhidden') continue;
      final rel = rels[s.attr('id', ns: 'relationships') ?? ''];
      if (rel == null || rel.external || !rel.isType('worksheet')) continue;
      final p = zip.find(rel.target);
      if (p == null) continue;
      final name = (s.attr('name') ?? '').trim();
      entries.add((name: name.isEmpty ? 'Sheet${i + 1}' : name, part: p, index: i));
      if (entries.length >= SheetLimits.maxSheets) {
        book.truncated = true;
        break;
      }
    }
    final sheets = <DocSheet>[];
    var active = 0;
    var damaged = 0;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      try {
        sheets.add(_readSheet(e.name, e.part, book.budgetFor(i, entries.length)));
        if (e.index == activeTab) active = sheets.length - 1;
      } on OfficeDocException catch (err) {
        // Испорченный лист — без него; предел всего документа — ошибка.
        if (err.kind == OfficeDocError.tooLarge || err.kind == OfficeDocError.encrypted) rethrow;
        damaged++;
      } on XmlException {
        damaged++;
      }
    }
    if (sheets.isEmpty && damaged > 0) throw const OfficeDocException(OfficeDocError.damaged, 'sheets');
    return OfficeSheetsDoc(
      sheets: sheets,
      styles: List.unmodifiable(book.styles),
      activeSheet: active,
      truncated: book.truncated || damaged > 0,
    );
  }

  static bool _true(String? v) => v == '1' || v == 'true' || v == 'on';

  /// Небольшая служебная часть деревом; больше предела или испорчена — null
  /// ([required] — ошибка испорченной части передаётся выше).
  XmlDocument? _smallXml(String? name, {bool required = false}) {
    if (name == null) return null;
    try {
      final b = zip.read(name, max: SheetLimits.maxSmallXmlBytes);
      if (b == null) return null;
      return XmlDocument.parse(OfficeZip.decodeText(b));
    } on XmlException {
      if (required) throw OfficeDocException(OfficeDocError.damaged, name);
      return null;
    } on OfficeDocException catch (e) {
      if (required || e.kind != OfficeDocError.tooLarge) rethrow;
      return null;
    }
  }

  // ── Тема и цвета ──

  void _readTheme(String? name) {
    final XmlDocument? doc;
    try {
      doc = _smallXml(name);
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.damaged) return;
      rethrow;
    }
    final scheme = doc?.rootElement.descendant('clrScheme');
    if (scheme == null) return;
    int? c(String local) {
      final el = scheme.kid(local);
      if (el == null) return null;
      for (final x in el.childElements) {
        final v = x.local == 'sysClr' ? x.attr('lastClr') : (x.local == 'srgbClr' ? x.attr('val') : null);
        final n = v == null ? null : int.tryParse(v, radix: 16);
        if (n != null) return 0xFF000000 | n;
      }
      return null;
    }

    const order = [
      'lt1', 'dk1', 'lt2', 'dk2', 'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6', //
      'hlink', 'folHlink',
    ];
    themeColors = [for (var i = 0; i < order.length; i++) c(order[i]) ?? _defaultTheme[i]];
  }

  /// Цвет элемента CT_Color; null — «авто» (цвет темы приложения).
  int? _color(XmlElement? el, {bool text = false}) {
    if (el == null || _true(el.attr('auto'))) return null;
    int? c;
    final rgb = el.attr('rgb');
    final theme = int.tryParse(el.attr('theme') ?? '');
    final indexed = int.tryParse(el.attr('indexed') ?? '');
    final tint = double.tryParse(el.attr('tint') ?? '') ?? 0;
    if (rgb != null) {
      final h = rgb.length > 6 ? rgb.substring(rgb.length - 6) : rgb;
      final n = int.tryParse(h, radix: 16);
      if (n != null) c = 0xFF000000 | n;
    } else if (theme != null) {
      // Тёмный текст темы (dk1) у шрифта — это и есть «авто»: в тёмной теме
      // приложения он должен стать светлым.
      if (text && theme == 1 && tint == 0) return null;
      if (theme >= 0 && theme < themeColors.length) c = themeColors[theme];
    } else if (indexed != null) {
      if (indexed >= 0 && indexed < palette.length && indexed < 64) c = palette[indexed];
    }
    if (c == null) return null;
    return tint == 0 ? c : _tint(c, tint);
  }

  /// Оттенок цвета темы: светлее (tint > 0) или темнее (< 0) по яркости HSL.
  static int _tint(int argb, double tint) {
    final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    var h = 0.0, s = 0.0;
    var l = (mx + mn) / 2;
    final d = mx - mn;
    if (d > 0) {
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      if (mx == r) {
        h = (g - b) / d + (g < b ? 6 : 0);
      } else if (mx == g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      h /= 6;
    }
    l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
    l = l.clamp(0.0, 1.0);
    double hue(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    double rr, gg, bb;
    if (s == 0) {
      rr = gg = bb = l;
    } else {
      final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final p = 2 * l - q;
      rr = hue(p, q, h + 1 / 3);
      gg = hue(p, q, h);
      bb = hue(p, q, h - 1 / 3);
    }
    int ch(double v) => (v * 255).round().clamp(0, 255);
    return 0xFF000000 | (ch(rr) << 16) | (ch(gg) << 8) | ch(bb);
  }

  static int _mix(int fg, int bg, double k) {
    int ch(int shift) => (((fg >> shift) & 0xFF) * k + ((bg >> shift) & 0xFF) * (1 - k)).round().clamp(0, 255);
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  // ── Стили ──

  void _readStyles(String? name) {
    final XmlDocument? doc;
    try {
      doc = _smallXml(name);
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.damaged) return;
      rethrow;
    }
    if (doc == null) return;
    final root = doc.rootElement;
    // Своя палитра (indexedColors) — до шрифтов и заливок.
    final custom = root.kid('colors')?.kid('indexedColors')?.kids('rgbColor').toList();
    if (custom != null && custom.isNotEmpty) {
      int rgb(String s) => (int.tryParse(s.length > 6 ? s.substring(s.length - 6) : s, radix: 16) ?? 0) | 0xFF000000;
      palette = [for (var i = 0; i < 64; i++) i < custom.length ? rgb(custom[i].attr('rgb') ?? '') : excelPalette[i]];
    }
    for (final f in root.kid('numFmts')?.kids('numFmt') ?? const <XmlElement>[]) {
      final id = int.tryParse(f.attr('numFmtId') ?? '');
      final code = f.attr('formatCode');
      if (id != null && code != null && numFmts.length < 2000) numFmts[id] = code;
    }
    bool flag(XmlElement? e) => e != null && !const ['0', 'false', 'none'].contains(e.attr('val'));
    // Шрифт без размера (так пишут некоторые программы) — размера обычного
    // шрифта книги (первый в списке).
    double? defaultPx;
    fonts = [
      for (final f in (root.kid('fonts')?.kids('font') ?? const <XmlElement>[]).take(SheetLimits.maxStyles))
        _Font(
          flag(f.kid('b')),
          flag(f.kid('i')),
          f.kid('u') != null && (f.kid('u')!.attr('val') ?? 'single') != 'none',
          flag(f.kid('strike')),
          () {
            final sz = double.tryParse(f.kid('sz')?.attr('val') ?? '');
            final name = f.kid('name')?.attr('val') ?? '';
            final px = sz == null || sz <= 0 || sz > 409 ? null : SheetFonts.px(sz, name);
            defaultPx ??= px ?? SheetFonts.px(11, name.isEmpty ? 'Calibri' : name);
            return px ?? defaultPx;
          }(),
          _color(f.kid('color'), text: true),
        ),
    ];
    fills = [
      for (final f in (root.kid('fills')?.kids('fill') ?? const <XmlElement>[]).take(SheetLimits.maxStyles)) _fill(f),
    ];
    borders = [
      for (final b in (root.kid('borders')?.kids('border') ?? const <XmlElement>[]).take(SheetLimits.maxStyles))
        _Borders(
          _side(b.kid('left') ?? b.kid('start')),
          _side(b.kid('top')),
          _side(b.kid('right') ?? b.kid('end')),
          _side(b.kid('bottom')),
        ),
    ];
    xfs = [
      for (final x in (root.kid('cellXfs')?.kids('xf') ?? const <XmlElement>[]).take(SheetLimits.maxStyles * 4))
        () {
          final a = x.kid('alignment');
          final h = switch (a?.attr('horizontal')) {
            'left' => DocHAlign.left,
            'center' || 'centerContinuous' => DocHAlign.center,
            'right' => DocHAlign.right,
            'justify' || 'distributed' => DocHAlign.justify,
            _ => DocHAlign.general,
          };
          final v = switch (a?.attr('vertical')) {
            'top' || 'justify' || 'distributed' => DocVAlign.top,
            'center' => DocVAlign.center,
            _ => DocVAlign.bottom,
          };
          final indent = (int.tryParse(a?.attr('indent') ?? '') ?? 0).clamp(0, 250);
          return _Xf(
            int.tryParse(x.attr('numFmtId') ?? '') ?? 0,
            int.tryParse(x.attr('fontId') ?? '') ?? 0,
            int.tryParse(x.attr('fillId') ?? '') ?? 0,
            int.tryParse(x.attr('borderId') ?? '') ?? 0,
            h,
            v,
            _true(a?.attr('wrapText')),
            indent * 9.0,
          );
        }(),
    ];
  }

  int? _fill(XmlElement f) {
    final p = f.kid('patternFill');
    if (p != null) {
      final type = p.attr('patternType') ?? (p.kid('fgColor') != null ? 'solid' : 'none');
      if (type == 'none') return null;
      final fg = _color(p.kid('fgColor')) ?? 0xFF000000;
      if (type == 'solid') return fg;
      final bg = _color(p.kid('bgColor')) ?? 0xFFFFFFFF;
      // Узор (штриховка) — средним цветом по плотности узора.
      final k = switch (type) {
        'darkGray' => 0.75,
        'mediumGray' => 0.5,
        'lightGray' => 0.25,
        'gray125' => 0.125,
        'gray0625' => 0.0625,
        _ => 0.5,
      };
      return _mix(fg, bg, k);
    }
    final g = f.kid('gradientFill');
    if (g != null) {
      final stops = g.kids('stop').map((s) => _color(s.kid('color'))).whereType<int>().toList();
      if (stops.isEmpty) return null;
      return stops.length == 1 ? stops.first : _mix(stops.first, stops.last, 0.5);
    }
    return null;
  }

  DocBorder? _side(XmlElement? e) {
    final style = e?.attr('style');
    if (e == null || style == null || style == 'none') return null;
    final w = switch (style) {
      'medium' || 'mediumDashed' || 'mediumDashDot' || 'mediumDashDotDot' || 'slantDashDot' => 2.0,
      'thick' || 'double' => 3.0,
      _ => 1.0,
    };
    return DocBorder(color: _color(e.kid('color'), text: true), width: w);
  }

  /// Номер оформления в книге для xf [s] ячейки.
  int _style(int s) {
    final hit = _xfStyle[s];
    if (hit != null) return hit;
    if (s < 0 || s >= xfs.length) return _xfStyle[s] = 0;
    final x = xfs[s];
    final f = x.font >= 0 && x.font < fonts.length ? fonts[x.font] : null;
    final b = x.border >= 0 && x.border < borders.length ? borders[x.border] : null;
    final style = DocCellStyle(
      bold: f?.b ?? false,
      italic: f?.i ?? false,
      underline: f?.u ?? false,
      strike: f?.s ?? false,
      fontSize: f?.px,
      color: f?.color,
      fill: x.fill >= 0 && x.fill < fills.length ? fills[x.fill] : null,
      hAlign: x.h,
      vAlign: x.v,
      wrap: x.wrap,
      indent: x.indent,
      left: b?.l,
      top: b?.t,
      right: b?.r,
      bottom: b?.b,
    );
    return _xfStyle[s] = book.style(style);
  }

  SheetNumberFormat _format(int s) {
    final hit = _xfFormat[s];
    if (hit != null) return hit;
    final id = s >= 0 && s < xfs.length ? xfs[s].numFmt : 0;
    final code = numFmts[id] ?? SheetNumberFormat.builtin(id, loc) ?? 'General';
    return _xfFormat[s] = SheetNumberFormat(code);
  }

  // ── Общие строки ──

  void _readSst(String? name) {
    if (name == null) return;
    final head = zip.readHead(name, SheetLimits.maxSheetXmlBytes);
    if (head == null) return;
    sstTruncated = head.truncated;
    final out = <String>[];
    final buf = StringBuffer();
    var inSi = false;
    var inT = false;
    var rph = 0;
    const maxStrings = 1000000;
    try {
      SheetXml.forEach(head.bytes, (e) {
        if (e is XmlStartElementEvent) {
          final n = SheetXml.local(e.name);
          if (n == 'si') {
            buf.clear();
            if (e.isSelfClosing) {
              out.add('');
            } else {
              inSi = true;
            }
          } else if (n == 'rPh') {
            if (!e.isSelfClosing) rph++;
          } else if (n == 't' && inSi && rph == 0 && !e.isSelfClosing) {
            inT = true;
          }
        } else if (e is XmlEndElementEvent) {
          final n = SheetXml.local(e.name);
          if (n == 't') {
            inT = false;
          } else if (n == 'rPh') {
            if (rph > 0) rph--;
          } else if (n == 'si') {
            inSi = false;
            out.add(_unescape(buf.toString()));
            if (out.length >= maxStrings) {
              sstTruncated = true;
              return false;
            }
          }
        } else if (inT && buf.length < SheetLimits.maxCellText) {
          if (e is XmlTextEvent) buf.write(e.value);
          if (e is XmlCDATAEvent) buf.write(e.value);
        }
        return true;
      });
    } on XmlException {
      // Испорченный конец — что успели прочитать.
      sstTruncated = true;
    }
    sst = out;
  }

  static final _xEscape = RegExp(r'_x([0-9A-Fa-f]{4})_');

  /// «_x000D_» (так OOXML пишет управляющие знаки) → знак; переводы строк — «\n».
  static String _unescape(String s) {
    var out = s;
    if (out.contains('_x')) {
      out = out.replaceAllMapped(_xEscape, (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    }
    if (out.contains('\r')) out = out.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return out;
  }

  // ── Лист ──

  DocSheet _readSheet(String name, String part, int budget) {
    final head = zip.readHead(part, SheetLimits.maxSheetXmlBytes);
    final sb = DocSheetBuilder(book, name, budget: budget);
    if (head == null) return sb.build();
    if (head.truncated) sb.truncated = true;
    var defaultRowPx = 20.0;
    var zeroHeight = false;
    var firstView = true;
    var inData = false;
    var row = -1;
    var col = -1;
    // Текущая ячейка.
    var inCell = false;
    var cellRow = 0;
    var cellCol = 0;
    String? cellType;
    var cellXf = 0;
    final v = StringBuffer();
    final inl = StringBuffer();
    var inV = false;
    var inIs = false;
    var inT = false;
    var rph = 0;
    var hasV = false;
    var stopped = false;

    void finishCell() {
      final style = _style(cellXf);
      final raw = v.toString();
      String text;
      var kind = DocCellKind.text;
      var st = style;
      switch (cellType) {
        case 's':
          final i = int.tryParse(raw.trim());
          if (i != null && i >= 0 && i < sst.length) {
            text = sst[i];
          } else {
            text = '';
            if (sstTruncated && i != null) sb.truncated = true;
          }
        case 'str':
          text = _unescape(raw);
        case 'inlineStr':
          text = _unescape(inl.toString());
        case 'b':
          text = raw.trim() == '1' || raw.trim() == 'true' ? loc.trueText : loc.falseText;
          kind = DocCellKind.boolean;
        case 'e':
          text = raw.trim();
          kind = DocCellKind.error;
        case 'd':
          final d = DateTime.tryParse(raw.trim());
          if (d == null) {
            text = raw.trim();
          } else {
            final fmt = _format(cellXf);
            final serial = ExcelDate.serial(d, date1904: date1904);
            text = (fmt.isDate ? fmt : SheetNumberFormat(loc.shortDate)).format(serial, loc, date1904: date1904).text;
            kind = DocCellKind.number;
          }
        default:
          final t = raw.trim();
          if (t.isEmpty) {
            text = '';
          } else {
            final n = double.tryParse(t);
            if (n == null) {
              text = t;
            } else {
              final fmt = _format(cellXf);
              final r = identical(fmt, SheetNumberFormat.general) || fmt.code == 'General'
                  ? SheetFormatted(SheetNumberFormat.generalText(n, loc))
                  : fmt.format(n, loc, date1904: date1904);
              text = r.text;
              if (r.color != null) st = book.withColor(style, r.color!);
              kind = DocCellKind.number;
            }
          }
      }
      if (kind == DocCellKind.text && text.isNotEmpty) {
        final fmt = _format(cellXf);
        if (fmt.code != 'General') text = fmt.formatText(text) ?? text;
      }
      if (cellRow >= SheetLimits.maxRows) {
        if (text.isNotEmpty) {
          sb.truncated = true;
          stopped = true;
        }
        return;
      }
      if (!sb.add(cellRow, cellCol, text, style: st, kind: kind)) stopped = true;
    }

    var stopAt = 0;
    try {
      stopAt = SheetXml.forEach(head.bytes, (e) {
        if (e is XmlStartElementEvent) {
          final n = SheetXml.local(e.name);
          if (inCell) {
            switch (n) {
              case 'v':
                if (!e.isSelfClosing) inV = true;
                hasV = true;
              case 'is':
                if (!e.isSelfClosing) inIs = true;
                hasV = true;
              case 'rPh':
                if (!e.isSelfClosing) rph++;
              case 't':
                if (inIs && rph == 0 && !e.isSelfClosing) inT = true;
            }
            return true;
          }
          switch (n) {
            case 'c':
              if (!inData) return true;
              final ref = SheetXml.attr(e, 'r');
              final c = ref == null ? null : SheetRef.colOf(ref);
              col = c ?? col + 1;
              cellRow = row < 0 ? 0 : row;
              cellCol = col;
              cellType = SheetXml.attr(e, 't');
              cellXf = int.tryParse(SheetXml.attr(e, 's') ?? '') ?? 0;
              v.clear();
              inl.clear();
              hasV = false;
              if (e.isSelfClosing) {
                finishCell();
              } else {
                inCell = true;
              }
            case 'row':
              if (!inData) return true;
              final r = int.tryParse(SheetXml.attr(e, 'r') ?? '');
              row = r != null && r > 0 ? r - 1 : row + 1;
              col = -1;
              if (row >= SheetLimits.maxRows) return true;
              final hidden = _true(SheetXml.attr(e, 'hidden'));
              final ht = double.tryParse(SheetXml.attr(e, 'ht') ?? '');
              if (hidden) {
                sb.rowHeight(row, 0);
              } else if (ht != null && ht >= 0) {
                sb.rowHeight(row, ht * 96 / 72);
              } else if (zeroHeight) {
                sb.rowHeight(row, defaultRowPx);
              }
            case 'sheetData':
              if (!e.isSelfClosing) inData = true;
            case 'col':
              final min = int.tryParse(SheetXml.attr(e, 'min') ?? '') ?? 0;
              final max = int.tryParse(SheetXml.attr(e, 'max') ?? '') ?? min;
              final hidden = _true(SheetXml.attr(e, 'hidden'));
              final w = double.tryParse(SheetXml.attr(e, 'width') ?? '');
              if (min >= 1 && (hidden || w != null)) {
                final px = hidden ? 0.0 : XlsxReader.colWidthPx(w!);
                for (var c = min - 1; c < math.min(max, SheetLimits.maxCols); c++) {
                  sb.colWidth(c, px);
                }
              }
            case 'sheetFormatPr':
              final dh = double.tryParse(SheetXml.attr(e, 'defaultRowHeight') ?? '');
              if (dh != null && dh > 0) defaultRowPx = dh * 96 / 72;
              zeroHeight = _true(SheetXml.attr(e, 'zeroHeight'));
              sb.defaultRowHeight = zeroHeight ? 0 : defaultRowPx;
              final dw = double.tryParse(SheetXml.attr(e, 'defaultColWidth') ?? '');
              final bw = double.tryParse(SheetXml.attr(e, 'baseColWidth') ?? '');
              if (dw != null && dw > 0) {
                sb.defaultColWidth = XlsxReader.colWidthPx(dw);
              } else if (bw != null && bw > 0) {
                sb.defaultColWidth = ((bw + 0.43) * 7 + 5).roundToDouble();
              }
            case 'sheetView':
              if (!firstView) return true;
              sb.showGrid = !const ['0', 'false'].contains(SheetXml.attr(e, 'showGridLines'));
              if (e.isSelfClosing) firstView = false;
            case 'pane':
              if (!firstView) return true;
              final state = SheetXml.attr(e, 'state') ?? '';
              if (state.startsWith('frozen')) {
                sb.frozenCols = (double.tryParse(SheetXml.attr(e, 'xSplit') ?? '') ?? 0).floor().clamp(
                  0,
                  SheetLimits.maxCols,
                );
                sb.frozenRows = (double.tryParse(SheetXml.attr(e, 'ySplit') ?? '') ?? 0).floor().clamp(
                  0,
                  SheetLimits.maxRows,
                );
              }
            case 'mergeCell':
              final m = SheetRef.range(SheetXml.attr(e, 'ref') ?? '');
              if (m != null) sb.merge(m);
          }
          return true;
        }
        if (e is XmlEndElementEvent) {
          final n = SheetXml.local(e.name);
          if (inCell) {
            switch (n) {
              case 'v':
                inV = false;
              case 't':
                inT = false;
              case 'rPh':
                if (rph > 0) rph--;
              case 'is':
                inIs = false;
              case 'c':
                inCell = false;
                inV = inIs = inT = false;
                rph = 0;
                if (hasV || cellXf > 0) finishCell();
                if (stopped) return false;
            }
            return true;
          }
          if (n == 'sheetData') inData = false;
          if (n == 'sheetView') firstView = false;
          return true;
        }
        if (inV) {
          if (e is XmlTextEvent && v.length < SheetLimits.maxCellText) v.write(e.value);
        } else if (inT) {
          if (inl.length < SheetLimits.maxCellText) {
            if (e is XmlTextEvent) inl.write(e.value);
            if (e is XmlCDATAEvent) inl.write(e.value);
          }
        }
        return true;
      });
    } on XmlException {
      // Испорченный конец листа — показываем прочитанное; испорчен весь —
      // лист пропускается.
      if (sb.cellCount == 0) rethrow;
      sb.truncated = true;
    }
    // Остановились на пределе строк или ячеек — объединения (они после
    // данных листа) ищем в оставшихся байтах без разбора.
    if (stopped) _scanMerges(head.bytes, stopAt, sb);
    return sb.build();
  }

  static final _mergeRef = RegExp(r'''ref\s*=\s*["']([A-Za-z$]+[0-9$]+:[A-Za-z$]+[0-9$]+)["']''');

  void _scanMerges(Uint8List bytes, int from, DocSheetBuilder sb) {
    final pattern = ascii.encode('mergeCells');
    var at = -1;
    outer:
    for (var i = math.max(0, from); i + pattern.length <= bytes.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      at = i;
      break;
    }
    if (at < 0) return;
    final end = math.min(bytes.length, at + 2 * 1024 * 1024);
    final text = latin1.decode(Uint8List.sublistView(bytes, at, end));
    for (final m in _mergeRef.allMatches(text)) {
      final r = SheetRef.range(m.group(1)!);
      if (r != null) sb.merge(r);
    }
  }
}

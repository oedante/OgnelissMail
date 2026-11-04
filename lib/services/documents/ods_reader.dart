// lib/services/documents/ods_reader.dart
// Таблица OpenDocument (ODS, шаблон OTS — LibreOffice, «Мой Офис», Р7)
// → листы для показа сеткой (1.11.x, предпросмотр документов, план
// владельца 04.11.2026). По OASIS OpenDocument 1.2–1.3 (ISO/IEC 26300).
//
// В отличие от XLSX, в ячейке ODS уже лежит готовый текст (text:p) — так,
// как его показала программа при сохранении: «1 234,50 ₽», «05.11.2026».
// Его и показываем; значение (office:value) — только когда текста нет
// (файлы из скриптов и выгрузок).
//
// Главная ловушка формата — повторы: LibreOffice пишет «пустую строку × 1 048 553»
// и «пустую ячейку × 1024» до конца листа. Повторы не разворачиваются: пустые
// строки — счётчиком, одинаковые строки с данными — одним общим списком
// ячеек, а строки только с оформлением (заливка, рамка) — лишь если ниже
// есть данные. Всё — в пределах [SheetLimits].
//
// content.xml (все листы и автоматические стили) — событиями по началу
// части; styles.xml (общие стили) и settings.xml (закрепление, сетка,
// открытый лист) — деревом, они маленькие.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'doc_sheets.dart';
import 'office_package.dart';
import 'sheet_format.dart';

class OdsReader {
  OdsReader._();

  static const _mimes = {
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.oasis.opendocument.spreadsheet-template',
  };

  /// Разобрать таблицу. Ошибки — только [OfficeDocException]: с паролем —
  /// [OfficeDocError.encrypted], не таблица или испорчена — [OfficeDocError.damaged].
  static OfficeSheetsDoc read(OfficeZip zip, {String lang = 'en'}) {
    try {
      final mime = zip.odfMimeType;
      if (mime != null && !_mimes.contains(mime)) {
        throw OfficeDocException(OfficeDocError.damaged, 'mimetype $mime');
      }
      if (zip.odfEncrypted) throw const OfficeDocException(OfficeDocError.encrypted, 'odf');
      return _Ods(zip, SheetLocale.of(lang)).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, 'ods: $e');
    }
  }

  /// Длина ODF («2.258cm», «0.889in», «64pt», «12mm») → точки (96 на дюйм).
  static double? lengthPx(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(-?[0-9]*\.?[0-9]+)\s*(cm|mm|in|inch|pt|pc|px)?\s*$').firstMatch(s);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    return switch (m.group(2)) {
      'cm' => v * 96 / 2.54,
      'mm' => v * 96 / 25.4,
      'in' || 'inch' => v * 96,
      'pt' => v * 96 / 72,
      'pc' => v * 16,
      _ => v,
    };
  }
}

/// Стиль ODS (автоматический или общий) — свойства, которые нужны сетке.
class _OStyle {
  _OStyle(this.name, this.family, this.parent);
  final String name;
  final String family;
  final String? parent;
  int? fill;
  bool fillSet = false;
  bool? bold, italic, underline, strike;
  double? fontPx;
  int? color;
  DocHAlign? h;
  DocVAlign? v;
  bool? wrap;
  double? indent;
  DocBorder? l, t, r, b;
  bool lSet = false, tSet = false, rSet = false, bSet = false;
  double? width;
  double? height;
  bool? display;

  void cell(XmlStartElementEvent e) {
    for (final a in e.attributes) {
      final n = SheetXml.local(a.name);
      final val = a.value;
      switch (n) {
        case 'background-color':
          fillSet = true;
          fill = _Ods.color(val);
        case 'wrap-option':
          wrap = val == 'wrap';
        case 'vertical-align':
          v = switch (val) {
            'top' => DocVAlign.top,
            'middle' => DocVAlign.center,
            'bottom' => DocVAlign.bottom,
            _ => null,
          };
        case 'border':
          final x = _Ods.border(val);
          l = t = r = b = x;
          lSet = tSet = rSet = bSet = true;
        case 'border-left':
          l = _Ods.border(val);
          lSet = true;
        case 'border-top':
          t = _Ods.border(val);
          tSet = true;
        case 'border-right':
          r = _Ods.border(val);
          rSet = true;
        case 'border-bottom':
          b = _Ods.border(val);
          bSet = true;
      }
    }
  }

  void text(XmlStartElementEvent e) {
    for (final a in e.attributes) {
      final n = SheetXml.local(a.name);
      final val = a.value;
      // Свойства для азиатского и сложного письма (…-asian, …-complex) —
      // те же имена с приставкой: не путаем.
      if (a.name.startsWith('style:') && n.endsWith('-asian')) continue;
      switch (n) {
        case 'font-weight':
          bold = val == 'bold' || (int.tryParse(val) ?? 400) >= 600;
        case 'font-style':
          italic = val == 'italic' || val == 'oblique';
        case 'text-underline-style':
          underline = val != 'none';
        case 'text-line-through-style':
          strike = val != 'none';
        case 'font-size':
          final px = OdsReader.lengthPx(val);
          if (px != null && px > 0 && px < 600) fontPx = px;
        case 'color':
          color = _Ods.color(val);
      }
    }
  }

  void paragraph(XmlStartElementEvent e) {
    String? align;
    String? source;
    for (final a in e.attributes) {
      final n = SheetXml.local(a.name);
      if (n == 'text-align') align = a.value;
      if (n == 'text-align-source') source = a.value;
      if (n == 'margin-left') indent = OdsReader.lengthPx(a.value);
    }
    if (source == 'value-type') {
      h = DocHAlign.general;
    } else if (align != null) {
      h = switch (align) {
        'start' || 'left' => DocHAlign.left,
        'end' || 'right' => DocHAlign.right,
        'center' => DocHAlign.center,
        'justify' => DocHAlign.justify,
        _ => DocHAlign.general,
      };
    }
  }

  void props(XmlStartElementEvent e) {
    switch (SheetXml.local(e.name)) {
      case 'table-cell-properties':
        cell(e);
      case 'text-properties':
        text(e);
      case 'paragraph-properties':
        paragraph(e);
      case 'table-column-properties':
        width = OdsReader.lengthPx(SheetXml.attr(e, 'column-width'));
      case 'table-row-properties':
        height = OdsReader.lengthPx(SheetXml.attr(e, 'row-height'));
      case 'table-properties':
        final d = SheetXml.attr(e, 'display');
        if (d != null) display = d != 'false';
    }
  }
}

/// Отрезок ячеек строки: [count] одинаковых ячеек с [col].
class _Seg {
  final int col;
  final int count;
  final String text;
  final int style;
  final DocCellKind kind;
  final int spanCols;
  final int spanRows;
  const _Seg(this.col, this.count, this.text, this.style, this.kind, this.spanCols, this.spanRows);
}

class _Ods {
  _Ods(this.zip, this.loc);

  final OfficeZip zip;
  final SheetLocale loc;
  final book = DocBookBuilder();
  final Map<String, _OStyle> _styles = {};
  _OStyle? _default;
  final Map<String, int> _cellStyleIds = {};

  // Из settings.xml.
  final Map<String, ({int rows, int cols})> _frozen = {};
  bool _showGrid = true;
  String? _activeTable;

  static int? color(String v) {
    final s = v.trim();
    if (!s.startsWith('#') || s.length != 7) return null;
    final n = int.tryParse(s.substring(1), radix: 16);
    return n == null ? null : 0xFF000000 | n;
  }

  /// «0.06pt solid #000000» → линия; «none» — нет.
  static DocBorder? border(String v) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty || s == 'none' || s.startsWith('hidden')) return null;
    int? c;
    double? w;
    var dbl = false;
    for (final part in s.split(RegExp(r'\s+'))) {
      if (part.startsWith('#')) {
        c = color(part);
      } else if (part == 'double' || part.startsWith('double-')) {
        dbl = true;
      } else if (part == 'none') {
        return null;
      } else {
        w ??= OdsReader.lengthPx(part);
      }
    }
    final px = w ?? 1;
    return DocBorder(color: c, width: dbl ? 3 : (px <= 1.1 ? 1 : (px <= 2.5 ? 2 : 3)));
  }

  OfficeSheetsDoc read() {
    _readCommonStyles();
    _readSettings();
    final head = zip.readHead('content.xml', OfficeLimits.maxPartBytes);
    if (head == null) throw const OfficeDocException(OfficeDocError.damaged, 'no content.xml');
    return _readContent(head.bytes, head.truncated);
  }

  void _readCommonStyles() {
    XmlDocument? doc;
    try {
      final b = zip.read('styles.xml', max: SheetLimits.maxSmallXmlBytes);
      if (b != null) doc = XmlDocument.parse(OfficeZip.decodeText(b));
    } on XmlException {
      return;
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.tooLarge || e.kind == OfficeDocError.damaged) return;
      rethrow;
    }
    final styles = doc?.rootElement.kid('styles');
    if (styles == null) return;
    for (final el in styles.childElements.take(SheetLimits.maxStyles)) {
      if (el.local != 'style' && el.local != 'default-style') continue;
      final family = el.attr('family') ?? '';
      if (family != 'table-cell') continue;
      final st = _OStyle(el.attr('name') ?? '', family, el.attr('parent-style-name'));
      for (final p in el.childElements) {
        st.props(_eventOf(p));
      }
      if (el.local == 'default-style') {
        _default = st;
      } else {
        _styles['$family:${st.name}'] = st;
      }
    }
  }

  /// Элемент дерева как событие — чтобы общие стили читались тем же кодом,
  /// что и автоматические из потока событий.
  static XmlStartElementEvent _eventOf(XmlElement e) => XmlStartElementEvent(e.name.qualified, [
    for (final a in e.attributes) XmlEventAttribute(a.name.qualified, a.value, XmlAttributeType.DOUBLE_QUOTE),
  ], true);

  void _readSettings() {
    XmlDocument? doc;
    try {
      final b = zip.read('settings.xml', max: SheetLimits.maxSmallXmlBytes);
      if (b != null) doc = XmlDocument.parse(OfficeZip.decodeText(b));
    } on XmlException {
      return;
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.tooLarge || e.kind == OfficeDocError.damaged) return;
      rethrow;
    }
    if (doc == null) return;
    Map<String, String> items(XmlElement entry) => {
      for (final i in entry.childElements)
        if (i.local == 'config-item') i.attr('name') ?? '': i.innerText.trim(),
    };
    void walk(XmlElement el, int depth) {
      if (depth > 12) return;
      for (final c in el.childElements) {
        if (c.local == 'config-item-map-named' && c.attr('name') == 'Tables') {
          for (final entry in c.childElements) {
            final name = entry.attr('name');
            if (name == null) continue;
            final it = items(entry);
            final cols = it['HorizontalSplitMode'] == '2' ? int.tryParse(it['HorizontalSplitPosition'] ?? '') ?? 0 : 0;
            final rows = it['VerticalSplitMode'] == '2' ? int.tryParse(it['VerticalSplitPosition'] ?? '') ?? 0 : 0;
            if (rows > 0 || cols > 0) _frozen[name] = (rows: rows, cols: cols);
          }
          continue;
        }
        if (c.local == 'config-item-map-entry' && el.local == 'config-item-map-indexed' && el.attr('name') == 'Views') {
          final it = items(c);
          if (it['ShowGrid'] == 'false') _showGrid = false;
          _activeTable ??= it['ActiveTable'];
        }
        walk(c, depth + 1);
      }
    }

    walk(doc.rootElement, 0);
  }

  // ── Оформление ячейки ──

  _OStyle? _find(String family, String? name) => name == null ? null : _styles['$family:$name'];

  int _cellStyle(String? name) {
    final key = name ?? '';
    final hit = _cellStyleIds[key];
    if (hit != null) return hit;
    // Цепочка «стиль → родитель → … → стиль по умолчанию»: ближний важнее.
    final chain = <_OStyle>[];
    var cur = _find('table-cell', name) ?? _find('table-cell', 'Default');
    while (cur != null && chain.length < 16) {
      chain.add(cur);
      cur = cur.parent == null ? null : _find('table-cell', cur.parent);
    }
    if (_default != null) chain.add(_default!);
    T? pick<T>(T? Function(_OStyle s) f) {
      for (final s in chain) {
        final v = f(s);
        if (v != null) return v;
      }
      return null;
    }

    int? fill;
    for (final s in chain) {
      if (s.fillSet) {
        fill = s.fill;
        break;
      }
    }
    DocBorder? side(bool Function(_OStyle s) isSet, DocBorder? Function(_OStyle s) get) {
      for (final s in chain) {
        if (isSet(s)) return get(s);
      }
      return null;
    }

    final style = DocCellStyle(
      bold: pick((s) => s.bold) ?? false,
      italic: pick((s) => s.italic) ?? false,
      underline: pick((s) => s.underline) ?? false,
      strike: pick((s) => s.strike) ?? false,
      fontSize: pick((s) => s.fontPx),
      color: pick((s) => s.color),
      fill: fill,
      hAlign: pick((s) => s.h) ?? DocHAlign.general,
      vAlign: pick((s) => s.v) ?? DocVAlign.bottom,
      wrap: pick((s) => s.wrap) ?? false,
      indent: pick((s) => s.indent) ?? 0,
      left: side((s) => s.lSet, (s) => s.l),
      top: side((s) => s.tSet, (s) => s.t),
      right: side((s) => s.rSet, (s) => s.r),
      bottom: side((s) => s.bSet, (s) => s.b),
    );
    return _cellStyleIds[key] = book.style(style);
  }

  // ── content.xml ──

  static int _countTables(Uint8List b) {
    final p = ascii.encode('<table:table ');
    var n = 0;
    outer:
    for (var i = 0; i + p.length <= b.length; i++) {
      if (b[i] != 0x3C) continue;
      for (var j = 1; j < p.length; j++) {
        if (b[i + j] != p[j]) continue outer;
      }
      n++;
    }
    return math.max(1, n);
  }

  OfficeSheetsDoc _readContent(Uint8List bytes, bool headTruncated) {
    final tableCount = _countTables(bytes);
    final sheets = <DocSheet>[];
    var active = 0;
    var tableIndex = 0;

    // Разбор стилей content.xml (автоматические).
    _OStyle? defining;
    var inBody = false;

    // Лист.
    DocSheetBuilder? sb;
    var skipTable = false;
    var tableDepth = 0;
    var colCursor = 0;
    final colDefault = <int, String>{};
    var rowCursor = 0;
    var tableStopped = false;

    // Строка.
    var inRow = false;
    var rowRep = 1;
    double? rowHeight;
    var rowHidden = false;
    String? rowDefault;
    final segs = <_Seg>[];
    // Строки без данных: ждут, не будет ли ниже данных.
    final pending = <({int row, int rep, List<_Seg> segs, double? height, bool hidden})>[];

    // Ячейка.
    var inCell = false;
    var covered = false;
    var cellRep = 1;
    var spanC = 1;
    var spanR = 1;
    String? cellStyleName;
    String? valueType;
    var isError = false;
    String? value;
    String? dateValue;
    String? timeValue;
    String? boolValue;
    String? stringValue;
    final text = StringBuffer();
    var paras = 0;
    var skipDepth = 0;

    void setHeight(int r, double? h, bool hidden) {
      if (sb == null || r >= SheetLimits.maxRows) return;
      if (hidden) {
        sb!.rowHeight(r, 0);
      } else if (h != null) {
        sb!.rowHeight(r, h);
      }
    }

    List<DocCell> materialize(int row, List<_Seg> list, int rep) {
      final cells = <DocCell>[];
      for (final s in list) {
        for (var k = 0; k < s.count; k++) {
          final c = s.col + k;
          if (c >= SheetLimits.maxCols) {
            if (s.text.isNotEmpty) sb!.truncated = true;
            break;
          }
          cells.add(DocCell(c, s.text, style: s.style, kind: s.kind));
          if (s.spanCols > 1 || s.spanRows > 1) {
            for (var j = 0; j < math.min(rep, 64); j++) {
              sb!.merge(DocMerge(row + j, c, row + j + s.spanRows - 1, c + s.spanCols - 1));
            }
          }
        }
      }
      return cells;
    }

    bool place(int row, int rep, List<_Seg> list, double? height, bool hidden) {
      final n = math.min(rep, SheetLimits.maxRows - row);
      if (n <= 0) return false;
      final cells = materialize(row, list, n);
      for (var k = 0; k < n; k++) {
        setHeight(row + k, height, hidden);
        if (!sb!.addRow(row + k, cells)) return false;
      }
      return true;
    }

    void finishRow() {
      inRow = false;
      final s = sb;
      if (s == null || tableStopped) {
        rowCursor += rowRep;
        return;
      }
      final hasText = segs.any((x) => x.text.isNotEmpty);
      if (rowCursor >= SheetLimits.maxRows) {
        if (hasText) {
          s.truncated = true;
          tableStopped = true;
        }
      } else if (hasText) {
        for (final p in pending) {
          if (!place(p.row, p.rep, p.segs, p.height, p.hidden) && s.full) break;
        }
        pending.clear();
        if (!place(rowCursor, rowRep, List.of(segs), rowHeight, rowHidden)) {
          if (s.full || rowCursor + rowRep > SheetLimits.maxRows) {
            s.truncated = true;
            tableStopped = true;
          }
        } else if (rowCursor + rowRep > SheetLimits.maxRows) {
          s.truncated = true;
          tableStopped = true;
        }
      } else if (rowCursor < SheetLimits.maxRows) {
        // Пустая или только с оформлением: высота — сразу (ниже могут быть
        // данные), ячейки — позже, если данные будут.
        final n = math.min(rowRep, SheetLimits.maxRows - rowCursor);
        if (segs.isNotEmpty && pending.length < 4096) {
          pending.add((row: rowCursor, rep: n, segs: List.of(segs), height: rowHeight, hidden: rowHidden));
        } else if (rowHeight != null || rowHidden) {
          if (n <= 64) {
            for (var k = 0; k < n; k++) {
              setHeight(rowCursor + k, rowHeight, rowHidden);
            }
          } else {
            pending.add((row: rowCursor, rep: n, segs: const [], height: rowHeight, hidden: rowHidden));
          }
        }
      }
      rowCursor += rowRep;
      segs.clear();
    }

    void finishCell() {
      inCell = false;
      final start = colCursor;
      colCursor += cellRep;
      if (covered || sb == null || tableStopped || start >= SheetLimits.maxCols) {
        if (!covered && start >= SheetLimits.maxCols && text.isNotEmpty) sb?.truncated = true;
        return;
      }
      var t = text.toString();
      var kind = DocCellKind.text;
      final vt = valueType;
      if (isError) {
        kind = DocCellKind.error;
      } else if (vt == 'float' || vt == 'percentage' || vt == 'currency' || vt == 'date' || vt == 'time') {
        kind = DocCellKind.number;
      } else if (vt == 'boolean') {
        kind = DocCellKind.boolean;
      }
      if (t.isEmpty) t = _fallback(vt, value, dateValue, timeValue, boolValue, stringValue);
      final style = _cellStyle(cellStyleName ?? rowDefault ?? colDefault[start]);
      if (t.isEmpty && !book.styles[style].visible) return;
      if (t.length > SheetLimits.maxCellText) t = t.substring(0, SheetLimits.maxCellText);
      segs.add(_Seg(start, math.min(cellRep, SheetLimits.maxCols - start), t, style, kind, spanC, spanR));
    }

    void finishTable() {
      final s = sb;
      if (s != null) {
        // Строки с оформлением после последних данных — не показываем, но
        // высоты строк между данными уже стоят.
        for (final p in pending) {
          if (p.segs.isEmpty && p.row < SheetLimits.maxRows) {
            for (var k = 0; k < math.min(p.rep, 64); k++) {
              setHeight(p.row + k, p.height, p.hidden);
            }
          }
        }
        if (headTruncated) s.truncated = true;
        sheets.add(s.build());
        if (s.name == _activeTable) active = sheets.length - 1;
      }
      pending.clear();
      sb = null;
    }

    try {
      SheetXml.forEach(bytes, (e) {
        if (e is XmlStartElementEvent) {
          final n = SheetXml.local(e.name);
          if (skipDepth > 0) {
            if (!e.isSelfClosing) skipDepth++;
            return true;
          }
          if (inCell) {
            switch (n) {
              case 'p':
              case 'h':
                if (paras++ > 0) text.write('\n');
              case 's':
                final c = (int.tryParse(SheetXml.attr(e, 'c') ?? '') ?? 1).clamp(1, 256);
                if (text.length < SheetLimits.maxCellText) text.write(' ' * c);
              case 'tab':
                text.write('\t');
              case 'line-break':
                text.write('\n');
              case 'annotation':
              case 'frame':
              case 'note':
              case 'custom-shape':
              case 'rect':
              case 'g':
              case 'ruby-text':
                if (!e.isSelfClosing) skipDepth = 1;
            }
            return true;
          }
          if (!inBody) {
            switch (n) {
              case 'body':
                inBody = true;
              case 'style':
                final family = SheetXml.attr(e, 'family') ?? '';
                final st = _OStyle(SheetXml.attr(e, 'name') ?? '', family, SheetXml.attr(e, 'parent-style-name'));
                if (_styles.length < SheetLimits.maxStyles * 2) _styles['$family:${st.name}'] = st;
                defining = e.isSelfClosing ? null : st;
              default:
                defining?.props(e);
            }
            return true;
          }
          switch (n) {
            case 'table':
              if (sb != null || skipTable) {
                // Таблица внутри таблицы (в надписи) — пропускаем.
                if (!e.isSelfClosing) tableDepth++;
                return true;
              }
              final ts = _find('table', SheetXml.attr(e, 'style-name'));
              final name = SheetXml.attr(e, 'name') ?? 'Sheet${tableIndex + 1}';
              final i = tableIndex++;
              colCursor = 0;
              rowCursor = 0;
              colDefault.clear();
              tableStopped = false;
              tableDepth = 1;
              if (ts?.display == false || sheets.length >= SheetLimits.maxSheets) {
                skipTable = true;
                if (sheets.length >= SheetLimits.maxSheets) book.truncated = true;
              } else {
                sb = DocSheetBuilder(
                  book,
                  name,
                  defaultColWidth: 85,
                  defaultRowHeight: 17,
                  budget: book.budgetFor(i, tableCount),
                );
                final fr = _frozen[name];
                if (fr != null) {
                  sb!.frozenRows = fr.rows;
                  sb!.frozenCols = fr.cols;
                }
                sb!.showGrid = _showGrid;
              }
              if (e.isSelfClosing) {
                skipTable = false;
                finishTable();
              }
            case 'table-column':
              if (sb == null || tableDepth != 1) return true;
              final rep = int.tryParse(SheetXml.attr(e, 'number-columns-repeated') ?? '') ?? 1;
              final cs = _find('table-column', SheetXml.attr(e, 'style-name'));
              final hidden = (SheetXml.attr(e, 'visibility') ?? 'visible') != 'visible';
              final def = SheetXml.attr(e, 'default-cell-style-name');
              for (var k = 0; k < rep && colCursor + k < SheetLimits.maxCols; k++) {
                final c = colCursor + k;
                if (hidden) {
                  sb!.colWidth(c, 0);
                } else if (cs?.width != null) {
                  sb!.colWidth(c, cs!.width!.roundToDouble());
                }
                if (def != null && def != 'Default') colDefault[c] = def;
              }
              colCursor += math.max(1, rep);
            case 'table-row':
              if (sb == null || tableDepth != 1) return true;
              if (colCursor > 0 && !inRow && rowCursor == 0 && segs.isEmpty) colCursor = 0;
              inRow = true;
              colCursor = 0;
              rowRep = math.max(1, int.tryParse(SheetXml.attr(e, 'number-rows-repeated') ?? '') ?? 1);
              rowHeight = _find('table-row', SheetXml.attr(e, 'style-name'))?.height;
              rowHidden = (SheetXml.attr(e, 'visibility') ?? 'visible') != 'visible';
              rowDefault = SheetXml.attr(e, 'default-cell-style-name');
              if (rowDefault == 'Default') rowDefault = null;
              segs.clear();
              if (e.isSelfClosing) finishRow();
            case 'table-cell':
            case 'covered-table-cell':
              if (sb == null || !inRow || tableDepth != 1) return true;
              covered = n == 'covered-table-cell';
              cellRep = math.max(1, int.tryParse(SheetXml.attr(e, 'number-columns-repeated') ?? '') ?? 1);
              spanC = (int.tryParse(SheetXml.attr(e, 'number-columns-spanned') ?? '') ?? 1).clamp(
                1,
                SheetLimits.maxCols,
              );
              spanR = (int.tryParse(SheetXml.attr(e, 'number-rows-spanned') ?? '') ?? 1).clamp(1, SheetLimits.maxRows);
              cellStyleName = SheetXml.attr(e, 'style-name');
              valueType = null;
              isError = false;
              value = dateValue = timeValue = boolValue = stringValue = null;
              for (final a in e.attributes) {
                switch (SheetXml.local(a.name)) {
                  case 'value-type':
                    if (a.name.startsWith('calcext:')) {
                      if (a.value == 'error') isError = true;
                    } else {
                      valueType = a.value;
                    }
                  case 'value':
                    value = a.value;
                  case 'date-value':
                    dateValue = a.value;
                  case 'time-value':
                    timeValue = a.value;
                  case 'boolean-value':
                    boolValue = a.value;
                  case 'string-value':
                    stringValue = a.value;
                }
              }
              text.clear();
              paras = 0;
              if (e.isSelfClosing) {
                finishCell();
              } else {
                inCell = true;
              }
          }
          return true;
        }
        if (e is XmlEndElementEvent) {
          final n = SheetXml.local(e.name);
          if (skipDepth > 0) {
            skipDepth--;
            return true;
          }
          if (inCell) {
            if (n == 'table-cell' || n == 'covered-table-cell') finishCell();
            return true;
          }
          if (!inBody) {
            if (n == 'style') defining = null;
            return true;
          }
          switch (n) {
            case 'table':
              if (tableDepth > 1) {
                tableDepth--;
                return true;
              }
              tableDepth = 0;
              if (skipTable) {
                skipTable = false;
              } else {
                finishTable();
              }
              if (book.full) return false;
            case 'table-row':
              if (inRow && tableDepth == 1) finishRow();
          }
          return true;
        }
        if (inCell && skipDepth == 0 && text.length < SheetLimits.maxCellText) {
          if (e is XmlTextEvent) {
            // Переводы строк и отступы разметки внутри text:p — не текст
            // ячейки (пробелы ODF задаёт text:s).
            text.write(e.value.replaceAll(RegExp(r'[\r\n\t]+'), ''));
          } else if (e is XmlCDATAEvent) {
            text.write(e.value);
          }
        }
        return true;
      });
    } on XmlException {
      // Испорченный конец content.xml — показываем прочитанное.
      if (sb != null) {
        sb!.truncated = true;
        finishTable();
      }
      if (sheets.isEmpty) rethrow;
      book.truncated = true;
    }
    if (sb != null) {
      // content.xml оборван посередине листа.
      sb!.truncated = true;
      finishTable();
    }
    if (sheets.isEmpty && tableIndex == 0 && !headTruncated) {
      // Не таблица (нет office:spreadsheet) — или пустая книга.
      final hasSheet = _contains(bytes, 'spreadsheet');
      if (!hasSheet) throw const OfficeDocException(OfficeDocError.damaged, 'not a spreadsheet');
    }
    return OfficeSheetsDoc(
      sheets: sheets,
      styles: List.unmodifiable(book.styles),
      activeSheet: active,
      truncated: book.truncated || headTruncated,
    );
  }

  static bool _contains(Uint8List b, String s) {
    final p = ascii.encode(s);
    outer:
    for (var i = 0; i + p.length <= b.length && i < 64 * 1024; i++) {
      for (var j = 0; j < p.length; j++) {
        if (b[i + j] != p[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// Текст ячейки без text:p — по значению (файлы из выгрузок и скриптов).
  String _fallback(String? type, String? value, String? date, String? time, String? boolean, String? string) {
    switch (type) {
      case 'float':
      case 'currency':
        final v = double.tryParse(value ?? '');
        return v == null ? '' : SheetNumberFormat.generalText(v, loc);
      case 'percentage':
        final v = double.tryParse(value ?? '');
        return v == null ? '' : '${SheetNumberFormat.generalText(v * 100, loc)}%';
      case 'date':
        final d = DateTime.tryParse(date ?? '');
        if (d == null) return date ?? '';
        final serial = ExcelDate.serial(d);
        final withTime = (date ?? '').contains('T') && (d.hour != 0 || d.minute != 0 || d.second != 0);
        return SheetNumberFormat(withTime ? '${loc.shortDate} h:mm' : loc.shortDate).format(serial, loc).text;
      case 'time':
        final m = RegExp(r'^-?P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?$').firstMatch(time ?? '');
        if (m == null) return time ?? '';
        final h = (int.tryParse(m.group(1) ?? '') ?? 0) * 24 + (int.tryParse(m.group(2) ?? '') ?? 0);
        final mi = int.tryParse(m.group(3) ?? '') ?? 0;
        final s = (double.tryParse(m.group(4) ?? '') ?? 0).round();
        return '$h:${mi.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      case 'boolean':
        return boolean == 'true' ? loc.trueText : (boolean == 'false' ? loc.falseText : '');
      case 'string':
        return string ?? '';
    }
    return '';
  }
}

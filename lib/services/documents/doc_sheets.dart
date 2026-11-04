// lib/services/documents/doc_sheets.dart
// Таблица из вложения — XLSX, ODS, CSV — для показа сеткой (1.11.x,
// предпросмотр документов, план владельца 04.11.2026).
//
// Модель общая для трёх форматов: листы с разреженными строками ячеек, у
// ячейки — уже готовый текст (число отформатировано так, как его показывает
// Excel: «1 234,56», «05.11.2026», «13%») и номер оформления в общем списке
// [OfficeSheetsDoc.styles]. Размеры — в логических точках при масштабе 100 %,
// цвета — int 0xAARRGGBB: модель собирается в фоновом изоляте и переходит в
// изолят интерфейса как обычные данные (без dart:ui).
//
// Скрытые листы в модель не попадают; скрытые строки и столбцы остаются с
// высотой и шириной 0 — так у видимых сохраняются настоящие номера («1, 2,
// 4», как в Excel) и объединения ячеек не сдвигаются.
//
// Пределы ([SheetLimits]) — на то, что действительно прочитано: объявленным в
// файле размерам («A1:XFD1048576», «повторить 1 048 576 строк») не верим и по
// ним ничего не выделяем.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart' show XmlParserException;
import 'package:xml/xml_events.dart';

import 'office_document.dart';

/// Пределы таблицы для показа. Больше — «показано начало»
/// ([DocSheet.truncated]), экран предлагает открыть файл в другом приложении.
class SheetLimits {
  SheetLimits._();

  /// Строк на лист: сетка листается плавно и на 10 000 строк, но читать и
  /// держать в памяти больше для предпросмотра незачем.
  static const maxRows = 10000;

  /// Столбцов на лист (A…IV, как в Excel 2003).
  static const maxCols = 256;

  /// Непустых ячеек во всём документе: ~300 000 ячеек — порядка 20–40 МБ в
  /// памяти телефона вместе с текстом.
  static const maxCells = 300000;

  /// Листов в документе.
  static const maxSheets = 256;

  /// Объединённых диапазонов на лист.
  static const maxMerges = 10000;

  /// Разных оформлений ячеек в документе (у Excel их до 64 000).
  static const maxStyles = 8000;

  /// Знаков в одной ячейке (у Excel — тоже 32 767).
  static const maxCellText = 32767;

  /// Начало XML одного листа (XLSX) и content.xml (ODS): дальше — «показано
  /// начало». 10 000 строк по 26 столбцов — около 10 МБ XML.
  static const maxSheetXmlBytes = 24 * 1024 * 1024;

  /// Начало файла CSV.
  static const maxCsvBytes = 8 * 1024 * 1024;

  /// Небольшие служебные части (стили, тема, настройки вида): больше — без
  /// них, но с данными (дерево XML занимает в памяти в разы больше текста).
  static const maxSmallXmlBytes = 4 * 1024 * 1024;

  /// Листов, которым при большом первом листе всё равно достаётся немного
  /// ячеек (по столько): итоги на втором листе не должны пропасть из-за
  /// выгрузки на первом.
  static const reservePerSheet = 1000;
}

/// Выравнивание по горизонтали. [general] — как в Excel по умолчанию: текст
/// влево, числа и даты вправо, логические значения и ошибки по центру.
enum DocHAlign { general, left, center, right, justify }

/// Выравнивание по вертикали (по умолчанию в Excel и LibreOffice — вниз).
enum DocVAlign { top, center, bottom }

/// Что в ячейке: от этого — выравнивание по умолчанию и «###» для числа, не
/// влезающего в ширину столбца.
enum DocCellKind { text, number, boolean, error }

/// Линия рамки ячейки.
class DocBorder {
  /// Цвет 0xAARRGGBB; null — «авто» (цвет текста темы).
  final int? color;

  /// Толщина в точках: 1 — тонкая, 2 — средняя, 3 — толстая или двойная.
  final double width;

  const DocBorder({this.color, this.width = 1});

  @override
  bool operator ==(Object other) => other is DocBorder && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// Оформление ячейки. Один и тот же объект — у многих ячеек: в модели
/// хранится номер в [OfficeSheetsDoc.styles].
class DocCellStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// Размер шрифта в логических точках; null — обычный размер сетки.
  final double? fontSize;

  /// Цвет текста; null — автоматический (цвет темы или контрастный к заливке).
  final int? color;

  /// Заливка; null — фон сетки (цвет поверхности темы).
  final int? fill;
  final DocHAlign hAlign;
  final DocVAlign vAlign;

  /// Перенос по словам внутри ячейки.
  final bool wrap;

  /// Отступ текста от края в точках.
  final double indent;
  final DocBorder? left;
  final DocBorder? top;
  final DocBorder? right;
  final DocBorder? bottom;

  const DocCellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSize,
    this.color,
    this.fill,
    this.hAlign = DocHAlign.general,
    this.vAlign = DocVAlign.bottom,
    this.wrap = false,
    this.indent = 0,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  static const plain = DocCellStyle();

  /// Пустую ячейку с таким оформлением видно (заливка или рамка) — её стоит
  /// хранить.
  bool get visible => fill != null || left != null || top != null || right != null || bottom != null;

  bool get hasBorders => left != null || top != null || right != null || bottom != null;

  DocCellStyle withColor(int? c) => DocCellStyle(
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    fontSize: fontSize,
    color: c,
    fill: fill,
    hAlign: hAlign,
    vAlign: vAlign,
    wrap: wrap,
    indent: indent,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );

  @override
  bool operator ==(Object other) =>
      other is DocCellStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.fill == fill &&
      other.hAlign == hAlign &&
      other.vAlign == vAlign &&
      other.wrap == wrap &&
      other.indent == indent &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    strike,
    fontSize,
    color,
    fill,
    hAlign,
    vAlign,
    wrap,
    indent,
    left,
    top,
    right,
    bottom,
  );
}

/// Ячейка: столбец (с 0), готовый к показу текст, номер оформления, вид.
class DocCell {
  final int col;
  final String text;
  final int style;
  final DocCellKind kind;
  const DocCell(this.col, this.text, {this.style = 0, this.kind = DocCellKind.text});
}

/// Объединённые ячейки: от [row]/[col] до [lastRow]/[lastCol] включительно.
/// Текст и оформление — у первой ячейки.
class DocMerge {
  final int row;
  final int col;
  final int lastRow;
  final int lastCol;
  const DocMerge(this.row, this.col, this.lastRow, this.lastCol);

  bool contains(int r, int c) => r >= row && r <= lastRow && c >= col && c <= lastCol;
}

/// Лист таблицы.
class DocSheet {
  final String name;

  /// Сколько строк и столбцов показывается (до последней непустой ячейки, не
  /// больше [SheetLimits]).
  final int rowCount;
  final int colCount;

  /// [rowCount] строк; в строке — ячейки по возрастанию столбца (пустая
  /// строка — пустой список; у одинаковых повторённых строк ODS — один и тот
  /// же список).
  final List<List<DocCell>> rows;

  /// Ширины столбцов и высоты строк в точках; скрытые — 0.
  final Float64List colWidths;
  final Float64List rowHeights;

  /// Размеры столбцов и строк за пределами данных (сетка дорисовывается до
  /// края экрана, как в Excel).
  final double defaultColWidth;
  final double defaultRowHeight;
  final List<DocMerge> merges;

  /// Закреплённые строки и столбцы из файла.
  final int frozenRows;
  final int frozenCols;

  /// Линии сетки (в Excel их отключают у бланков и счетов).
  final bool showGrid;

  /// Показана только часть листа.
  final bool truncated;

  /// На листе есть хоть одна ячейка с текстом.
  final bool hasContent;

  const DocSheet({
    required this.name,
    required this.rowCount,
    required this.colCount,
    required this.rows,
    required this.colWidths,
    required this.rowHeights,
    this.defaultColWidth = 64,
    this.defaultRowHeight = 20,
    this.merges = const [],
    this.frozenRows = 0,
    this.frozenCols = 0,
    this.showGrid = true,
    this.truncated = false,
    this.hasContent = false,
  });

  bool get isEmpty => !hasContent;

  /// Ячейка в строке [row] и столбце [col]; null — пустая.
  DocCell? cell(int row, int col) {
    if (row < 0 || row >= rows.length) return null;
    final r = rows[row];
    final i = lowerBound(r, col);
    return i < r.length && r[i].col == col ? r[i] : null;
  }

  /// Первая ячейка строки со столбцом не меньше [col] (двоичный поиск).
  static int lowerBound(List<DocCell> row, int col) {
    var lo = 0;
    var hi = row.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (row[mid].col < col) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Разобранная таблица.
class OfficeSheetsDoc extends OfficeDoc {
  /// Видимые листы в порядке книги.
  final List<DocSheet> sheets;

  /// Оформления ячеек; [DocCell.style] — номер здесь, 0 — обычное.
  final List<DocCellStyle> styles;

  /// Лист, открытый в файле последним (с него начинается показ).
  final int activeSheet;
  final bool _truncated;

  const OfficeSheetsDoc({
    required this.sheets,
    this.styles = const [DocCellStyle.plain],
    this.activeSheet = 0,
    bool truncated = false,
  }) : _truncated = truncated;

  @override
  bool get truncated => _truncated || sheets.any((s) => s.truncated);

  DocCellStyle styleOf(DocCell c) => c.style >= 0 && c.style < styles.length ? styles[c.style] : DocCellStyle.plain;
}

/// Адреса ячеек: «B12» ↔ строка и столбец (с 0).
class SheetRef {
  SheetRef._();

  /// Буквы столбца: 0 → «A», 25 → «Z», 26 → «AA».
  static String colName(int col) {
    var n = col + 1;
    final out = <int>[];
    while (n > 0) {
      final m = (n - 1) % 26;
      out.add(0x41 + m);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(out.reversed);
  }

  /// «B12» (и «$B$12») → (row: 11, col: 1); null — не адрес ячейки.
  static ({int row, int col})? parse(String ref) {
    var i = 0;
    final s = ref.trim();
    var col = 0;
    var letters = 0;
    if (i < s.length && s.codeUnitAt(i) == 0x24) i++;
    while (i < s.length) {
      var ch = s.codeUnitAt(i);
      if (ch >= 0x61 && ch <= 0x7A) ch -= 0x20;
      if (ch < 0x41 || ch > 0x5A) break;
      col = col * 26 + (ch - 0x40);
      if (++letters > 4) return null;
      i++;
    }
    if (i < s.length && s.codeUnitAt(i) == 0x24) i++;
    var row = 0;
    var digits = 0;
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch < 0x30 || ch > 0x39) return null;
      row = row * 10 + (ch - 0x30);
      if (++digits > 8) return null;
      i++;
    }
    if (letters == 0 || digits == 0 || row == 0) return null;
    return (row: row - 1, col: col - 1);
  }

  /// Только буквы столбца в начале адреса: «C7» → 2; null — нет букв.
  static int? colOf(String ref) {
    var col = 0;
    var letters = 0;
    for (var i = 0; i < ref.length; i++) {
      var ch = ref.codeUnitAt(i);
      if (ch == 0x24) continue;
      if (ch >= 0x61 && ch <= 0x7A) ch -= 0x20;
      if (ch < 0x41 || ch > 0x5A) break;
      col = col * 26 + (ch - 0x40);
      if (++letters > 4) return null;
    }
    return letters == 0 ? null : col - 1;
  }

  /// «A1:C3» → объединение; одиночная ячейка и ошибки — null.
  static DocMerge? range(String ref) {
    final colon = ref.indexOf(':');
    if (colon < 0) return null;
    final a = parse(ref.substring(0, colon));
    final b = parse(ref.substring(colon + 1));
    if (a == null || b == null) return null;
    final m = DocMerge(math.min(a.row, b.row), math.min(a.col, b.col), math.max(a.row, b.row), math.max(a.col, b.col));
    if (m.row == m.lastRow && m.col == m.lastCol) return null;
    return m;
  }
}

/// Сборка документа: общий список оформлений и счёт ячеек на все листы.
class DocBookBuilder {
  final List<DocCellStyle> styles = [DocCellStyle.plain];
  final Map<DocCellStyle, int> _ids = {DocCellStyle.plain: 0};
  final Map<int, int> _colored = {};

  /// Ячеек во всём документе.
  int cells = 0;

  /// Что-то не поместилось в пределы (не привязано к листу).
  bool truncated = false;

  /// Номер оформления [s] (одинаковые — один номер). Больше
  /// [SheetLimits.maxStyles] разных — обычное оформление.
  int style(DocCellStyle s) {
    final id = _ids[s];
    if (id != null) return id;
    if (styles.length >= SheetLimits.maxStyles) return 0;
    styles.add(s);
    return _ids[s] = styles.length - 1;
  }

  /// Оформление [base] с цветом текста [color] (цвет из формата числа:
  /// «[Red]» у отрицательных).
  int withColor(int base, int color) {
    final key = base * 0x10000000 + (color & 0xFFFFFFF);
    final hit = _colored[key];
    if (hit != null) return hit;
    final s = base >= 0 && base < styles.length ? styles[base] : DocCellStyle.plain;
    return _colored[key] = style(s.withColor(color));
  }

  bool get full => cells >= SheetLimits.maxCells;

  /// Ячеек, которые ещё можно отдать листу [index] из [count]: остальным
  /// листам остаётся по [SheetLimits.reservePerSheet].
  int budgetFor(int index, int count) {
    final int left = math.max(0, SheetLimits.maxCells - cells);
    final int reserve = SheetLimits.reservePerSheet * math.max(0, count - index - 1);
    return math.max(math.min(left, SheetLimits.reservePerSheet), left - reserve);
  }
}

/// Сборка одного листа. Ячейки добавляются строка за строкой; всё, что за
/// пределами [SheetLimits], отбрасывается с пометкой [truncated].
class DocSheetBuilder {
  DocSheetBuilder(this.book, this.name, {this.defaultColWidth = 64, this.defaultRowHeight = 20, int? budget})
    : _budget = budget ?? SheetLimits.maxCells;

  final DocBookBuilder book;
  final String name;
  double defaultColWidth;
  double defaultRowHeight;
  int frozenRows = 0;
  int frozenCols = 0;
  bool showGrid = true;
  bool truncated = false;

  final int _budget;
  int _cells = 0;
  final List<List<DocCell>?> _rows = [];
  final Set<int> _unsorted = {};
  final Map<int, double> _colWidths = {};
  final Map<int, double> _rowHeights = {};
  final List<DocMerge> _merges = [];

  // Последние строка и столбец с текстом и с видимым оформлением.
  int _textRow = -1;
  int _textCol = -1;
  int _styledRow = -1;
  int _styledCol = -1;
  bool _hasContent = false;

  /// Лист больше нечего добавлять: ячейки документа или листа кончились.
  bool get full => _cells >= _budget || book.full;

  int get cellCount => _cells;

  /// Добавить ячейку. false — места больше нет (читать лист дальше незачем).
  bool add(int row, int col, String text, {int style = 0, DocCellKind kind = DocCellKind.text}) {
    if (row < 0 || col < 0) return true;
    if (text.isEmpty && !_styleVisible(style)) return true;
    if (row >= SheetLimits.maxRows || col >= SheetLimits.maxCols) {
      if (text.isNotEmpty) truncated = true;
      return row < SheetLimits.maxRows;
    }
    if (full) {
      truncated = true;
      return false;
    }
    if (text.length > SheetLimits.maxCellText) text = text.substring(0, SheetLimits.maxCellText);
    while (_rows.length <= row) {
      _rows.add(null);
    }
    final list = _rows[row] ??= <DocCell>[];
    if (list.isNotEmpty && list.last.col >= col) _unsorted.add(row);
    list.add(DocCell(col, text, style: style, kind: kind));
    _cells++;
    book.cells++;
    if (text.isNotEmpty) {
      _hasContent = true;
      if (row > _textRow) _textRow = row;
      if (col > _textCol) _textCol = col;
    } else {
      if (row > _styledRow) _styledRow = row;
      if (col > _styledCol) _styledCol = col;
    }
    return true;
  }

  /// Строка целиком (ячейки по возрастанию столбца, все < [SheetLimits.maxCols]);
  /// одинаковые строки ODS («повторить 50 раз») делят один список.
  bool addRow(int row, List<DocCell> cells) {
    if (cells.isEmpty) return true;
    if (row >= SheetLimits.maxRows) {
      if (cells.any((c) => c.text.isNotEmpty)) truncated = true;
      return false;
    }
    if (full || _cells + cells.length > _budget || book.cells + cells.length > SheetLimits.maxCells) {
      truncated = true;
      return false;
    }
    while (_rows.length <= row) {
      _rows.add(null);
    }
    if (_rows[row] != null) {
      for (final c in cells) {
        if (!add(row, c.col, c.text, style: c.style, kind: c.kind)) return false;
      }
      return true;
    }
    _rows[row] = cells;
    _cells += cells.length;
    book.cells += cells.length;
    for (final c in cells) {
      if (c.text.isNotEmpty) {
        _hasContent = true;
        if (row > _textRow) _textRow = row;
        if (c.col > _textCol) _textCol = c.col;
      } else {
        if (row > _styledRow) _styledRow = row;
        if (c.col > _styledCol) _styledCol = c.col;
      }
    }
    return true;
  }

  bool _styleVisible(int style) => style > 0 && style < book.styles.length && book.styles[style].visible;

  void colWidth(int col, double px) {
    if (col >= 0 && col < SheetLimits.maxCols) _colWidths[col] = px.isFinite ? px.clamp(0.0, 2000.0) : defaultColWidth;
  }

  void rowHeight(int row, double px) {
    if (row >= 0 && row < SheetLimits.maxRows) {
      _rowHeights[row] = px.isFinite ? px.clamp(0.0, 1000.0) : defaultRowHeight;
    }
  }

  bool hasRowHeight(int row) => _rowHeights.containsKey(row);

  void merge(DocMerge m) {
    if (_merges.length >= SheetLimits.maxMerges) {
      truncated = true;
      return;
    }
    if (m.row >= SheetLimits.maxRows || m.col >= SheetLimits.maxCols) return;
    _merges.add(
      DocMerge(
        m.row,
        m.col,
        math.min(m.lastRow, SheetLimits.maxRows - 1),
        math.min(m.lastCol, SheetLimits.maxCols - 1),
      ),
    );
  }

  /// Строки без высоты из файла, где есть перенос или несколько строк
  /// текста, — с высотой по тексту (Excel подбирает её сам; в CSV и файлах
  /// из программ её нет). Ширина буквы — примерно 0,55 размера шрифта.
  void _autoHeights(List<List<DocCell>> rows, Float64List widths, Float64List heights) {
    for (var r = 0; r < rows.length; r++) {
      if (_rowHeights.containsKey(r) || heights[r] == 0) continue;
      var need = 0.0;
      for (final c in rows[r]) {
        if (c.text.isEmpty) continue;
        final st = c.style < book.styles.length ? book.styles[c.style] : DocCellStyle.plain;
        final multi = c.text.contains('\n');
        if (!st.wrap && !multi) continue;
        final font = st.fontSize ?? 13;
        final lineH = font * 1.25;
        final w = c.col < widths.length ? widths[c.col] : defaultColWidth;
        final perLine = math.max(1, ((w - 6) / (font * 0.55)).floor());
        var lines = 0;
        for (final part in c.text.split('\n')) {
          lines += st.wrap ? math.max(1, (part.length / perLine).ceil()) : 1;
          if (lines > 40) break;
        }
        need = math.max(need, lines * lineH + 4);
      }
      if (need > heights[r]) heights[r] = math.min(need, 545);
    }
  }

  DocSheet build() {
    // Пустые ячейки с заливкой или рамкой — только рядом с данными: у
    // LibreOffice строка с цветом бывает «до столбца AMJ».
    var lastRow = _textRow;
    var lastCol = _textCol;
    for (final m in _merges) {
      if (m.row <= _textRow || cell(m.row, m.col)?.text.isNotEmpty == true) {
        lastRow = math.max(lastRow, m.lastRow);
        lastCol = math.max(lastCol, m.lastCol);
      }
    }
    lastRow = math.max(lastRow, math.min(_styledRow, lastRow + 2));
    lastCol = math.max(lastCol, math.min(_styledCol, lastCol + 2));
    final rowCount = math.min(lastRow + 1, SheetLimits.maxRows);
    final colCount = math.min(lastCol + 1, SheetLimits.maxCols);
    final rows = List<List<DocCell>>.filled(rowCount, const <DocCell>[]);
    for (var r = 0; r < rowCount && r < _rows.length; r++) {
      var list = _rows[r];
      if (list == null) continue;
      if (_unsorted.contains(r)) {
        // Ячейки не по порядку (так пишут некоторые программы) — по
        // столбцу; у повторённой ячейки остаётся последняя.
        final byCol = <int, DocCell>{for (final c in list) c.col: c};
        list = byCol.values.toList()..sort((a, b) => a.col.compareTo(b.col));
      }
      if (list.isNotEmpty && list.last.col >= colCount) list = list.where((c) => c.col < colCount).toList();
      rows[r] = list;
    }
    final widths = Float64List(colCount);
    for (var c = 0; c < colCount; c++) {
      widths[c] = _colWidths[c] ?? defaultColWidth;
    }
    final heights = Float64List(rowCount);
    for (var r = 0; r < rowCount; r++) {
      heights[r] = _rowHeights[r] ?? defaultRowHeight;
    }
    _autoHeights(rows, widths, heights);
    final merges = [
      for (final m in _merges)
        if (m.row < rowCount && m.col < colCount)
          DocMerge(m.row, m.col, math.min(m.lastRow, rowCount - 1), math.min(m.lastCol, colCount - 1)),
    ];
    return DocSheet(
      name: name,
      rowCount: rowCount,
      colCount: colCount,
      rows: rows,
      colWidths: widths,
      rowHeights: heights,
      defaultColWidth: defaultColWidth,
      defaultRowHeight: defaultRowHeight == 0 ? 20 : defaultRowHeight,
      merges: merges,
      frozenRows: frozenRows.clamp(0, rowCount),
      frozenCols: frozenCols.clamp(0, colCount),
      showGrid: showGrid,
      truncated: truncated,
      hasContent: _hasContent,
    );
  }

  DocCell? cell(int row, int col) {
    if (row < 0 || row >= _rows.length) return null;
    final list = _rows[row];
    if (list == null) return null;
    for (final c in list) {
      if (c.col == col) return c;
    }
    return null;
  }
}

/// Разбор большой части XML событиями, кусками: в памяти — байты части и
/// текущий кусок текста, а не вся строка и не дерево. Кусок обрывается
/// перед «<», поэтому текст между тегами всегда целый (и сущности «&amp;»
/// не разрываются); тег, оборванный внутри (CDATA, комментарий), переходит
/// в следующий кусок.
class SheetXml {
  SheetXml._();

  static const chunkBytes = 64 * 1024;

  /// Обойти события [bytes]; [onEvent] вернул false — остановиться.
  /// Возвращает смещение в байтах, до которого дочитано (для поиска после
  /// остановки). Испорченный XML — [XmlException].
  static int forEach(Uint8List bytes, bool Function(XmlEvent e) onEvent) {
    var pos = 0;
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) pos = 3;
    if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      // UTF-16 (редко, так пишут отдельные программы) — целиком.
      for (final e in parseEvents(_utf16(bytes))) {
        if (!onEvent(e)) break;
      }
      return bytes.length;
    }
    var carry = '';
    while (pos < bytes.length) {
      var end = math.min(pos + chunkBytes, bytes.length);
      if (end < bytes.length) {
        final lt = bytes.indexOf(0x3C, end);
        end = lt < 0 ? bytes.length : lt;
      }
      final text = carry + utf8.decode(Uint8List.sublistView(bytes, pos, end), allowMalformed: true);
      final chunkStart = pos;
      pos = end;
      var stop = 0;
      try {
        for (final e in parseEvents(text, withLocation: true)) {
          stop = e.stop ?? stop;
          if (!onEvent(e)) return chunkStart;
        }
        carry = '';
      } on XmlParserException {
        // Тег не закончился в этом куске — дочитать со следующим; если
        // «хвост» растёт без конца, XML испорчен.
        if (pos >= bytes.length || text.length - stop > 1024 * 1024) rethrow;
        carry = text.substring(stop);
      }
    }
    return bytes.length;
  }

  static String _utf16(Uint8List b) {
    final le = b[0] == 0xFF;
    final units = Uint16List((b.length - 2) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      final j = 2 + i * 2;
      units[i] = le ? b[j] | (b[j + 1] << 8) : (b[j] << 8) | b[j + 1];
    }
    return String.fromCharCodes(units);
  }

  /// Атрибут события по локальному имени (r, t, s; table:style-name → «style-name»).
  static String? attr(XmlStartElementEvent e, String local) {
    for (final a in e.attributes) {
      final n = a.name;
      final colon = n.indexOf(':');
      if (colon < 0 ? n == local : (n.length - colon - 1 == local.length && n.endsWith(local))) return a.value;
    }
    return null;
  }

  /// Локальное имя элемента (без префикса x:, table:).
  static String local(String qualified) {
    final colon = qualified.indexOf(':');
    return colon < 0 ? qualified : qualified.substring(colon + 1);
  }
}

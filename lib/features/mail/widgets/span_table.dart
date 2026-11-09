// lib/features/mail/widgets/span_table.dart
// Таблица с объединёнными ячейками (rowspan, colspan) для писем без
// браузера (1.5.11). Table из Flutter объединять ячейки не умеет — из-за
// этого отчёты 1С, таблицы из Excel и шапки «Плановый год вовлечения» над
// тремя колонками уходили в окно браузера.
//
// С 2.2.0 — все таблицы писем без браузера, и простые (раньше — Table
// из Flutter: колонки строго по долям из письма, и подпись Outlook шириной
// 1914 точек с колонками 300 и 1614 сжимала левую колонку до букв,
// замечание владельца 08.11.2026).
//
// Раскладка — как у браузера в упрощённом виде:
//  1. ширины колонок — доли (из ширин ячеек без объединения) от ширины
//     таблицы, но колонка не уже своего содержимого — самого длинного
//     слова, картинки ([fitColumnWidths]); ячейка получает сумму ширин
//     своих колонок;
//  2. высота строки — по самой высокой ячейке без объединения строк;
//     ячейка, объединяющая строки, если не помещается, добавляет высоту
//     последней из своих строк;
//  3. ячейка растягивается на всю свою высоту (фон и рамка — сплошные).

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Место ячейки в сетке.
class SpanCellParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0;
  int col = 0;
  int rowSpan = 1;
  int colSpan = 1;
}

/// Ячейка [SpanTable]: строка и колонка сетки (с учётом объединений) и
/// сколько строк и колонок она занимает.
class SpanCell extends ParentDataWidget<SpanCellParentData> {
  const SpanCell({
    super.key,
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
    required super.child,
  });

  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  @override
  void applyParentData(RenderObject renderObject) {
    final d = renderObject.parentData! as SpanCellParentData;
    if (d.row == row && d.col == col && d.rowSpan == rowSpan && d.colSpan == colSpan) return;
    d
      ..row = row
      ..col = col
      ..rowSpan = rowSpan
      ..colSpan = colSpan;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => SpanTable;
}

class SpanTable extends MultiChildRenderObjectWidget {
  const SpanTable({super.key, required this.rows, required this.columnFlex, required super.children});

  final int rows;

  /// Доли ширины колонок (длина — число колонок).
  final List<double> columnFlex;

  @override
  RenderSpanTable createRenderObject(BuildContext context) =>
      RenderSpanTable(rows: rows, columnFlex: columnFlex);

  @override
  void updateRenderObject(BuildContext context, RenderSpanTable renderObject) {
    renderObject
      ..rows = rows
      ..columnFlex = columnFlex;
  }
}

/// Ширины колонок таблицы шириной [width]: доли [flex] (ширины из письма;
/// все одинаковые — поровну), но колонка не уже [mins] — своего самого
/// длинного слова или картинки, как в браузере. Колонке, которой доли
/// мало, — её минимум, остальные делят оставшееся по долям.
///
/// Не хватает и на минимумы (адрес почты или ссылка без пробелов длиннее
/// половины экрана) — колонки получают желаемое (минимум или долю, что
/// больше), но не больше общего предела: узкие — сколько просят, широкие
/// — поровну остаток. Так разрываются только самые длинные слова, а
/// короткие в узких колонках — нет.
List<double> fitColumnWidths(List<double> flex, List<double> mins, double width) {
  final n = flex.length;
  if (n == 0) return const [];
  double minAt(int i) => i < mins.length && mins[i].isFinite && mins[i] > 0 ? mins[i] : 0;
  final f = [for (final v in flex) v.isFinite && v > 0 ? v : 0.0];
  final fSum = f.fold<double>(0, (a, b) => a + b);
  final share = [for (final v in f) fSum <= 0 ? width / n : width * v / fSum];
  var sumMin = 0.0;
  for (var i = 0; i < n; i++) {
    sumMin += minAt(i);
  }
  if (sumMin > width) {
    final want = [for (var i = 0; i < n; i++) math.max(minAt(i), share[i])];
    final sorted = [...want]..sort();
    var rest = width;
    var left = n;
    var cap = width / n;
    for (final w in sorted) {
      if (w > rest / left) {
        cap = rest / left;
        break;
      }
      rest -= w;
      left--;
      cap = left == 0 ? w : rest / left;
    }
    return [for (final w in want) math.min(w, cap)];
  }
  // Колонки, которым доли мало, — по содержимому; остальные делят
  // оставшееся по долям (пока кто-то из них не окажется уже минимума).
  final fixed = List<bool>.filled(n, false);
  while (true) {
    var rest = width;
    var free = 0;
    var freeFlex = 0.0;
    for (var i = 0; i < n; i++) {
      if (fixed[i]) {
        rest -= minAt(i);
      } else {
        free++;
        freeFlex += f[i];
      }
    }
    double part(int i) => freeFlex <= 0 ? rest / free : rest * f[i] / freeFlex;
    var changed = false;
    for (var i = 0; i < n; i++) {
      if (!fixed[i] && part(i) < minAt(i)) {
        fixed[i] = true;
        changed = true;
      }
    }
    if (!changed || free == 0) {
      return [for (var i = 0; i < n; i++) fixed[i] ? minAt(i) : part(i)];
    }
  }
}

class RenderSpanTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, SpanCellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, SpanCellParentData> {
  RenderSpanTable({required int rows, required List<double> columnFlex})
      : _rows = rows,
        _columnFlex = columnFlex;

  int _rows;
  int get rows => _rows;
  set rows(int v) {
    if (v == _rows) return;
    _rows = v;
    markNeedsLayout();
  }

  List<double> _columnFlex;
  List<double> get columnFlex => _columnFlex;
  set columnFlex(List<double> v) {
    if (listEquals(v, _columnFlex)) return;
    _columnFlex = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! SpanCellParentData) child.parentData = SpanCellParentData();
  }

  List<double> get _flex => _columnFlex.isEmpty ? const [1.0] : _columnFlex;

  /// Самое узкое, во что колонка помещается без разрыва слов: самое
  /// длинное слово ячеек, картинка, вложенная таблица (с отступами
  /// ячейки). Объединённая ячейка шире своих колонок — разница поровну.
  List<double> _columnMins() {
    final n = _flex.length;
    final mins = List<double>.filled(n, 0);
    final spanned = <(SpanCellParentData, double)>[];
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as SpanCellParentData;
      if (d.col < n) {
        final m = child.getMinIntrinsicWidth(double.infinity);
        if (d.colSpan <= 1) {
          mins[d.col] = math.max(mins[d.col], m);
        } else {
          spanned.add((d, m));
        }
      }
      child = d.nextSibling;
    }
    for (final (d, m) in spanned) {
      final end = math.min(n, d.col + d.colSpan);
      final have = _span(mins, d.col, end - d.col);
      if (m > have) {
        final add = (m - have) / (end - d.col);
        for (var i = d.col; i < end; i++) {
          mins[i] += add;
        }
      }
    }
    return mins;
  }

  List<double> _colWidths(double width) => fitColumnWidths(_flex, _columnMins(), width);

  // Вложенная таблица (подпись Outlook — таблица в ячейке таблицы):
  // внешняя узнаёт, уже чего её колонку не сжать.
  @override
  double computeMinIntrinsicWidth(double height) => _columnMins().fold<double>(0, (a, b) => a + b);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final n = _flex.length;
    final maxes = List<double>.filled(n, 0);
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as SpanCellParentData;
      if (d.col < n) {
        final m = child.getMaxIntrinsicWidth(double.infinity) / math.max(1, d.colSpan);
        for (var i = d.col; i < math.min(n, d.col + d.colSpan); i++) {
          maxes[i] = math.max(maxes[i], m);
        }
      }
      child = d.nextSibling;
    }
    return maxes.fold<double>(0, (a, b) => a + b);
  }

  double _span(List<double> list, int from, int count) {
    var s = 0.0;
    for (var i = from; i < from + count && i < list.length; i++) {
      s += list[i];
    }
    return s;
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
    final colW = _colWidths(width);
    final colX = <double>[0];
    for (final w in colW) {
      colX.add(colX.last + w);
    }
    final rowH = List<double>.filled(math.max(1, _rows), 0);

    // 1. Высоты ячеек при их ширине.
    final heights = <RenderBox, double>{};
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as SpanCellParentData;
      final w = _span(colW, d.col, d.colSpan);
      child.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
      heights[child] = child.size.height;
      if (d.rowSpan == 1 && d.row < rowH.length) rowH[d.row] = math.max(rowH[d.row], child.size.height);
      child = d.nextSibling;
    }
    // 2. Объединённые строки: не хватает высоты — добавить последней строке.
    child = firstChild;
    while (child != null) {
      final d = child.parentData! as SpanCellParentData;
      if (d.rowSpan > 1 && d.row < rowH.length) {
        final last = math.min(rowH.length - 1, d.row + d.rowSpan - 1);
        final have = _span(rowH, d.row, last - d.row + 1);
        final need = heights[child]! - have;
        if (need > 0) rowH[last] += need;
      }
      child = d.nextSibling;
    }
    final rowY = <double>[0];
    for (final h in rowH) {
      rowY.add(rowY.last + h);
    }
    // 3. Каждая ячейка — на всю свою высоту.
    child = firstChild;
    while (child != null) {
      final d = child.parentData! as SpanCellParentData;
      final w = _span(colW, d.col, d.colSpan);
      final r = math.min(d.row, rowH.length - 1);
      final h = _span(rowH, r, math.min(d.rowSpan, rowH.length - r));
      child.layout(BoxConstraints.tightFor(width: w, height: h));
      d.offset = Offset(colX[math.min(d.col, colX.length - 1)], rowY[r]);
      child = d.nextSibling;
    }
    size = constraints.constrain(Size(width, rowY.last));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

// lib/features/mail/widgets/span_table.dart
// Таблица с объединёнными ячейками (rowspan, colspan) для писем без
// браузера (1.5.11). Table из Flutter объединять ячейки не умеет — из-за
// этого отчёты 1С, таблицы из Excel и шапки «Плановый год вовлечения» над
// тремя колонками уходили в окно браузера.
//
// Раскладка — как у браузера в упрощённом виде:
//  1. ширины колонок — доли (из ширин ячеек без объединения) от ширины
//     таблицы; ячейка получает сумму ширин своих колонок;
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

  List<double> _colWidths(double width) {
    final n = math.max(1, _columnFlex.length);
    final flex = _columnFlex.isEmpty ? List<double>.filled(n, 1) : _columnFlex;
    final sum = flex.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
    return [for (final f in flex) sum <= 0 ? width / n : width * (f > 0 ? f : 0) / sum];
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

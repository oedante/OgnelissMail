// lib/widgets/common/gap_below.dart
// Отступ снизу — только если над ним что-то есть (1.7.2, замечание
// 20.10.2026: под строками вверху ленты — «Автоответ включён», «Ожидают
// отправки»… — не было пустого места, и письма при прокрутке уходили под
// нижний край строки вплотную). Нет ни одной строки — отступа тоже нет,
// лента начинается сразу под шапкой, как раньше.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class GapBelowIfNotEmpty extends SingleChildRenderObjectWidget {
  final double gap;
  const GapBelowIfNotEmpty({super.key, required this.gap, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGapBelow(gap);

  @override
  void updateRenderObject(BuildContext context, RenderGapBelow renderObject) {
    renderObject.gap = gap;
  }
}

class RenderGapBelow extends RenderProxyBox {
  RenderGapBelow(this._gap);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    final maxH = constraints.maxHeight.isFinite
        ? (constraints.maxHeight - _gap).clamp(0.0, double.infinity)
        : double.infinity;
    c.layout(constraints.copyWith(minHeight: 0, maxHeight: maxH), parentUsesSize: true);
    final h = c.size.height;
    size = constraints.constrain(Size(c.size.width, h > 0 ? h + _gap : 0));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final h = super.computeMinIntrinsicHeight(width);
    return h > 0 ? h + _gap : 0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final h = super.computeMaxIntrinsicHeight(width);
    return h > 0 ? h + _gap : 0;
  }
}

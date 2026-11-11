// lib/widgets/common/paging_slop.dart
//
// Листание страниц (писем ленты, писем беседы) — только намеренным жестом
// вбок (2.3.2, замечание владельца 11.11.2026: «свайп очень лёгкий — едва
// коснулся, уже письмо поехало»).
//
// На Android порог начала жеста — системный, около 8 точек, и одинаковый
// для прокрутки письма вниз и для листания вбок: палец, который при
// прокрутке чуть ушёл в сторону, начинал листание. У системного ViewPager
// (Gmail) порог листания вдвое больше порога прокрутки, и вбок нужно
// провести заметно дальше, чем вниз. Здесь — так же: порог листания в
// [factor] раза больше системного, но не меньше [minSlop] точек; жест, у
// которого сдвиг вниз набрал системный порог раньше, достаётся прокрутке.
// Порог должен оставаться меньше 36 точек: с него жест забирает окно
// письма (распознаватель масштаба), и листание над текстом перестало бы
// работать.
//
// [PagingSlop] оборачивает PageView; страницы внутри — [PagingSlop.page],
// чтобы у их собственной прокрутки порог остался системным.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class PagingSlop extends StatelessWidget {
  const PagingSlop({super.key, required this.child});

  /// PageView (или другая прокрутка страниц).
  final Widget child;

  static const factor = 2.5;
  static const minSlop = 20.0;
  static const maxSlop = 30.0;

  /// Порог листания для системного порога [system] (null — стандартный).
  static double slopFor(double? system) =>
      math.min(maxSlop, math.max(minSlop, (system ?? kTouchSlop) * factor));

  /// Страница внутри [PagingSlop]: её жестам — прежний, системный порог.
  static Widget page(BuildContext context, Widget child) {
    final base = context.getInheritedWidgetOfExactType<_BaseGestures>()?.settings;
    if (base == null) return child;
    return MediaQuery(data: MediaQuery.of(context).copyWith(gestureSettings: base), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final base = mq.gestureSettings;
    return _BaseGestures(
      settings: base,
      child: MediaQuery(
        data: mq.copyWith(gestureSettings: DeviceGestureSettings(touchSlop: slopFor(base.touchSlop))),
        child: child,
      ),
    );
  }
}

class _BaseGestures extends InheritedWidget {
  const _BaseGestures({required this.settings, required super.child});

  final DeviceGestureSettings settings;

  @override
  bool updateShouldNotify(_BaseGestures oldWidget) => settings != oldWidget.settings;
}

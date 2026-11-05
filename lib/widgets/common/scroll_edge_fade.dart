// lib/widgets/common/scroll_edge_fade.dart
// Тень у края прокручиваемого списка: «сверху/снизу есть ещё».
//
// Замечание 10.10.2026: в меню, панелях и настройках не видно, что список
// можно прокрутить — последние пункты просто обрезаны краем. Теперь у края,
// за которым есть содержимое, появляется мягкая тень (8 dp).
//
// Подключается ко ВСЕМ вертикальным спискам приложения через ScrollBehavior
// (main.dart, _AppScrollBehavior.buildScrollbar) — правило одно на всё
// приложение, отдельные экраны трогать не нужно. Горизонтальные ленты,
// поля ввода (у них полосы прокрутки выключены) и маленькие области (ниже
// 120 dp — колёса выбора, строки) не затрагиваются.
//
// [axis] — горизонтальная лента (1.12.x, строка сведений письма, просьба
// владельца 04.11.2026): тень у левого и правого края. Её экран
// оборачивает сам — общее правило ScrollBehavior только для вертикальных.

import 'package:flutter/material.dart';

class ScrollEdgeFade extends StatefulWidget {
  final Widget child;
  final double size;
  final Axis axis;

  const ScrollEdgeFade({super.key, required this.child, this.size = 8, this.axis = Axis.vertical});

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _top = false;
  bool _bottom = false;

  bool _update(ScrollMetrics m, int depth) {
    if (depth != 0 || m.axis != widget.axis) return false;
    var before = m.extentBefore > 1;
    var after = m.extentAfter > 1;
    if (m.viewportDimension < 120) {
      before = false;
      after = false;
    }
    // Перевёрнутый список (reverse: true, письмо справа налево): «до» —
    // внизу (справа).
    if (m.axisDirection == AxisDirection.up || m.axisDirection == AxisDirection.left) {
      final t = before;
      before = after;
      after = t;
    }
    if (before != _top || after != _bottom) {
      if (mounted) {
        setState(() {
          _top = before;
          _bottom = after;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final shade = theme.colorScheme.shadow.withValues(alpha: dark ? 0.32 : 0.10);
    final vertical = widget.axis == Axis.vertical;
    Widget edge(bool visible, Alignment from) => IgnorePointer(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              height: vertical ? widget.size : null,
              width: vertical ? null : widget.size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: from,
                  end: Alignment(-from.x, -from.y),
                  colors: [shade, shade.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _update(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _update(n.metrics, n.depth),
        child: Stack(
          // Списку — те же ограничения, что без обёртки.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (vertical) ...[
              Positioned(top: 0, left: 0, right: 0, child: edge(_top, Alignment.topCenter)),
              Positioned(bottom: 0, left: 0, right: 0, child: edge(_bottom, Alignment.bottomCenter)),
            ] else ...[
              // Слева направо: «до» — у левого края, «после» — у правого.
              Positioned(top: 0, bottom: 0, left: 0, child: edge(_top, Alignment.centerLeft)),
              Positioned(top: 0, bottom: 0, right: 0, child: edge(_bottom, Alignment.centerRight)),
            ],
          ],
        ),
      ),
    );
  }
}

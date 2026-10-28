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

import 'package:flutter/material.dart';

class ScrollEdgeFade extends StatefulWidget {
  final Widget child;
  final double size;

  const ScrollEdgeFade({super.key, required this.child, this.size = 8});

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _top = false;
  bool _bottom = false;

  bool _update(ScrollMetrics m, int depth) {
    if (depth != 0 || m.axis != Axis.vertical) return false;
    var before = m.extentBefore > 1;
    var after = m.extentAfter > 1;
    if (m.viewportDimension < 120) {
      before = false;
      after = false;
    }
    // Перевёрнутый список (reverse: true): «до» — внизу экрана.
    if (m.axisDirection == AxisDirection.up) {
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
    Widget edge(bool visible, Alignment from) => IgnorePointer(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              height: widget.size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: from,
                  end: from == Alignment.topCenter ? Alignment.bottomCenter : Alignment.topCenter,
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
            Positioned(top: 0, left: 0, right: 0, child: edge(_top, Alignment.topCenter)),
            Positioned(bottom: 0, left: 0, right: 0, child: edge(_bottom, Alignment.bottomCenter)),
          ],
        ),
      ),
    );
  }
}

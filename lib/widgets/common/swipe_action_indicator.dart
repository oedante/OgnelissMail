// lib/widgets/common/swipe_action_indicator.dart
// «Живой» значок действия свайпа (1.6.21, замечание владельца 17.10.2026:
// значок появлялся, только когда строку протянули далеко, — до этого было
// непонятно, что произойдёт).
//
// Что делает:
//  · значок стоит у края, с которого выезжает панель, — виден с первых
//    миллиметров свайпа (раньше — по центру панели, и при коротком свайпе
//    его не было видно);
//  · по мере свайпа значок проявляется и растёт, у края панели — лёгкий
//    градиент; подписи на экране нет (1.6.25: появляясь, она сдвигала значок);
//  · дальше, до порога полного свайпа (действие сработает, если отпустить),
//    значок плавно дорастает и градиент густеет — по положению пальца, без
//    скачков (1.6.25). Без вибрации (1.6.22, решение владельца: при разборе
//    почты серией свайпов она утомляет).
//
//  · 1.10.3 (просьба владельца 02.11.2026: «анимации свайпам, не сильно
//    отвлекающие, в бизнес-стиле»): у порога значок плавно становится
//    залитым, за ним проступает мягкий круг цвета действия — видно, что
//    действие сработает, если отпустить. У панели из двух кнопок (порога
//    нет) — то же, когда панель открыта целиком. Всё по положению пальца,
//    без пружин, вспышек и вибрации.
//
// Нагрузка: перерисовывается только этот маленький виджет и только пока
// строку тянут (подписка на анимацию свайпа). Выключается настройкой
// «Живой свайп» и «Уменьшить движение» — тогда значок просто стоит у края.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/theme/tokens.dart';

class SwipeActionIndicator extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;

  /// Панель выезжает слева (свайп вправо). false — справа.
  final bool fromStart;

  /// У края (одно действие на стороне) или по центру своей кнопки (два).
  final bool atEdge;

  /// Доля ширины строки, которую занимает панель (ActionPane.extentRatio).
  final double extentRatio;

  /// Порог полного свайпа (доля ширины строки); null — автосрабатывания нет.
  final double? armAt;

  /// Анимация включена (настройка «Живой свайп» и нет «Уменьшить движение»).
  final bool animated;

  const SwipeActionIndicator({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.fromStart,
    required this.atEdge,
    required this.extentRatio,
    this.armAt,
    this.animated = true,
  });

  @override
  State<SwipeActionIndicator> createState() => _SwipeActionIndicatorState();
}

class _SwipeActionIndicatorState extends State<SwipeActionIndicator> {
  SlidableController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = Slidable.of(context);
  }

  Alignment get _edge => widget.atEdge
      ? (widget.fromStart ? Alignment.centerLeft : Alignment.centerRight)
      : Alignment.center;

  Widget _icon(double alpha, {double fill = 0}) =>
      Icon(widget.icon, size: 28, fill: fill, color: widget.color.withValues(alpha: alpha));

  /// Место под круг за значком: значок в центре квадрата [_haloBox], поэтому
  /// отступ от края у анимированного значка меньше на (_haloBox − 28) / 2 —
  /// значок стоит там же, где и без анимации.
  static const _haloBox = 48.0;

  /// Круг за значком у порога (1.10.3): 0 — нет, 1 — виден полностью.
  /// Размер виджета постоянный — значок не сдвигается, когда круг растёт.
  Widget _halo(double t, Widget icon) => SizedBox.square(
        dimension: _haloBox,
        child: Stack(alignment: Alignment.center, children: [
          if (t > 0)
            Transform.scale(
              scale: 0.7 + 0.3 * t,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.14 * t)),
                child: const SizedBox.square(dimension: _haloBox),
              ),
            ),
          icon,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(horizontal: widget.atEdge ? Space.xl - 4 : Space.xs);
    final c = _controller;
    // Подпись действия — только для озвучивания: на экране её нет (1.6.25,
    // появляясь, она сдвигала значок вверх).
    if (c == null || !widget.animated) {
      // Без анимации: значок у края — виден сразу, без эффектов.
      return Semantics(
        label: widget.label,
        child: SizedBox.expand(
          child: Align(alignment: _edge, child: Padding(padding: padding, child: _icon(1))),
        ),
      );
    }
    final arm = widget.armAt;
    return Semantics(
      label: widget.label,
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: c.animation,
            builder: (context, _) {
              final v = c.animation.value; // доля ширины строки
              final p = (v / widget.extentRatio).clamp(0.0, 1.0);
              final eased = Curves.easeOutCubic.transform(p);
              // Подход к порогу — плавно, по положению пальца, а не скачком:
              // от края панели до порога значок дорастает до 1,15, градиент
              // густеет (1.6.25; раньше у порога было резкое увеличение).
              var armT = 0.0;
              if (arm != null && arm > widget.extentRatio) {
                armT = Curves.easeInOut
                    .transform(((v - widget.extentRatio) / (arm - widget.extentRatio)).clamp(0.0, 1.0));
              }
              // Две кнопки (порога нет): «готово» — когда панель открыта
              // почти целиком.
              final ready = arm != null ? armT : Curves.easeInOut.transform(((p - 0.85) / 0.15).clamp(0.0, 1.0));
              final iconAlpha = 0.45 + 0.55 * eased;
              final scale = 0.8 + 0.2 * eased + 0.08 * ready;
              final glow = 0.12 * eased + 0.10 * armT;
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: widget.fromStart ? Alignment.centerLeft : Alignment.centerRight,
                    end: widget.fromStart ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [widget.color.withValues(alpha: glow), widget.color.withValues(alpha: 0)],
                  ),
                ),
                child: Align(
                  alignment: _edge,
                  child: Padding(
                    padding: widget.atEdge
                        ? const EdgeInsets.symmetric(horizontal: Space.xl - 4 - (_haloBox - 28) / 2)
                        : EdgeInsets.zero,
                    child: Transform.scale(scale: scale, child: _halo(ready, _icon(iconAlpha, fill: ready))),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

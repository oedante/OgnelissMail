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
//
//  · 2.2.0 (решение владельца 09.11.2026 «что предлагаю дальше по свайпам —
//    делаем»): одно правило для всех свайпов — протянул до порога и отпустил.
//    За краем панели рядом со значком проступает подпись — что сработает.
//    Два действия на стороне — по расстоянию: короткий свайп — первое,
//    длинный ([SwipeStep.at]) — второе; значок, подпись и цвет меняются,
//    пока тянешь. Подпись — справа от значка (слева у правой панели):
//    значок на месте, как и раньше.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/theme/tokens.dart';

/// Второе действие стороны: срабатывает, если отпустить дальше [at].
class SwipeStep {
  final IconData icon;
  final String label;

  /// Цвет значка и подписи.
  final Color color;

  /// Заливка панели.
  final Color background;

  /// Доля ширины строки, с которой выбрано это действие.
  final double at;
  const SwipeStep({required this.icon, required this.label, required this.color, required this.background, required this.at});
}

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

  /// Второе действие (длинный свайп) — или null.
  final SwipeStep? second;

  /// Заливка панели первого действия: у края она — на всё открывшееся место,
  /// а не только на ширину панели (иначе за ней — пустой зазор).
  final Color? background;

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
    this.second,
    this.background,
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

  Widget _icon(double alpha, {double fill = 0, IconData? icon, Color? color}) =>
      Icon(icon ?? widget.icon, size: 28, fill: fill, color: (color ?? widget.color).withValues(alpha: alpha));

  /// Подпись рядом со значком: значок у края, подпись — дальше от края.
  Widget _withLabel(Widget icon, String label, Color color, double opacity) {
    if (opacity <= 0 || label.isEmpty || !widget.atEdge) return icon;
    final text = Flexible(
      child: Opacity(
        opacity: opacity,
        child: Text(
          label,
          key: const ValueKey('swipe_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: widget.fromStart ? [icon, const SizedBox(width: Space.xs), text] : [text, const SizedBox(width: Space.xs), icon],
    );
  }

  /// Место под круг за значком: значок в центре квадрата [_haloBox], поэтому
  /// отступ от края у анимированного значка меньше на (_haloBox − 28) / 2 —
  /// значок стоит там же, где и без анимации.
  static const _haloBox = 48.0;

  /// Круг за значком у порога (1.10.3): 0 — нет, 1 — виден полностью.
  /// Размер виджета постоянный — значок не сдвигается, когда круг растёт.
  Widget _halo(double t, Widget icon, {Color? haloColor}) => SizedBox.square(
        dimension: _haloBox,
        child: Stack(alignment: Alignment.center, children: [
          if (t > 0)
            Transform.scale(
              scale: 0.7 + 0.3 * t,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: (haloColor ?? widget.color).withValues(alpha: 0.14 * t)),
                child: const SizedBox.square(dimension: _haloBox),
              ),
            ),
          icon,
        ]),
      );

  /// У края — слой во всю ширину строки от края: панель библиотеки узкая
  /// (extentRatio), а строку тянут дальше. Видна только открытая часть —
  /// её обрезает сама Slidable. Посередине (две кнопки) — как раньше.
  Widget _wide(BuildContext context, {required Widget child}) {
    if (!widget.atEdge) return SizedBox.expand(child: child);
    final w = MediaQuery.maybeSizeOf(context)?.width ?? 0;
    return LayoutBuilder(builder: (context, c) {
      final wide = w > c.maxWidth ? w : c.maxWidth;
      return OverflowBox(
        alignment: widget.fromStart ? Alignment.centerLeft : Alignment.centerRight,
        minWidth: wide,
        maxWidth: wide,
        minHeight: c.maxHeight,
        maxHeight: c.maxHeight,
        child: child,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(horizontal: widget.atEdge ? Space.xl - 4 : Space.xs);
    final c = _controller;
    // Подпись на экране — рядом со значком за краем панели (2.2.0); значок
    // при этом не сдвигается (1.6.25: подпись под значком сдвигала его).
    if (c == null) {
      // Без контроллера (вне Slidable): значок у края.
      return Semantics(
        label: widget.label,
        child: SizedBox.expand(
          child: Align(alignment: _edge, child: Padding(padding: padding, child: _icon(1))),
        ),
      );
    }
    final arm = widget.armAt;
    final second = widget.second;
    return Semantics(
      label: widget.label,
      child: RepaintBoundary(
        child: _wide(
          context,
          child: AnimatedBuilder(
            animation: c.animation,
            builder: (context, _) {
              final v = c.animation.value; // доля ширины строки
              final p = (v / widget.extentRatio).clamp(0.0, 1.0);
              // Длинный свайп — второе действие: другой значок, подпись, цвет.
              final two = second != null && v >= second.at;
              final icon = two ? second.icon : widget.icon;
              final color = two ? second.color : widget.color;
              final label = two ? second.label : widget.label;
              // Подпись — за краем панели (там, где строку можно отпустить
              // с действием), полностью — на полпути к порогу.
              var labelT = 0.0;
              if (arm != null && arm > widget.extentRatio) {
                labelT = ((v - widget.extentRatio) / ((arm - widget.extentRatio) / 2)).clamp(0.0, 1.0);
              }
              if (!widget.animated) {
                // Без анимации: значок и подпись без роста и свечения.
                return DecoratedBox(
                  decoration: BoxDecoration(color: two ? second.background : widget.background),
                  child: Align(
                    alignment: _edge,
                    child: Padding(
                      padding: padding,
                      child: _withLabel(_icon(1, icon: icon, color: color, fill: v >= (arm ?? 2) ? 1 : 0), label,
                          color, labelT > 0 ? 1 : 0),
                    ),
                  ),
                );
              }
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
                  color: two ? second.background : widget.background,
                  gradient: two
                      ? null
                      : LinearGradient(
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
                    child: _withLabel(
                        Transform.scale(
                            scale: scale,
                            child: _halo(ready, _icon(iconAlpha, fill: ready, icon: icon, color: color),
                                haloColor: color)),
                        label,
                        color,
                        labelT),
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

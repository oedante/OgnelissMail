// lib/features/my_day/flip_clock.dart
// Перелистывающиеся часы в «Моём дне» (1.15.1, просьба владельца 07.11.2026:
// «в мой день добавить переворачивающиеся часы (флип-клок)»).
//
// Каждая цифра — карточка из двух половин. Цифра сменилась: верхняя половина
// прежней цифры падает вниз (поворот вокруг середины), открывая верх новой,
// затем снизу ложится нижняя половина новой. Только меняющиеся цифры —
// минуты чаще всего одна. Время часы берут сами и меняют ровно в начале
// минуты (экран «Моего дня» перестраивается раз в полминуты). «Уменьшить
// движение» (настройка или система) — без анимации.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FlipClock extends StatefulWidget {
  /// Высота цифры (карточки).
  final double height;

  /// Без анимации (настройка «Уменьшить движение»).
  final bool reduceMotion;

  /// Часы для тестов; null — текущее время.
  final DateTime Function()? clock;

  const FlipClock({super.key, this.height = 44, this.reduceMotion = false, this.clock});

  @override
  State<FlipClock> createState() => _FlipClockState();
}

class _FlipClockState extends State<FlipClock> {
  Timer? _timer;
  late DateTime _now;

  DateTime _read() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _read();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final n = _read();
    // До начала следующей минуты (и чуть после — не раньше смены).
    final next = DateTime(n.year, n.month, n.day, n.hour, n.minute + 1);
    _timer = Timer(next.difference(n) + const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() => _now = _read());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = DateFormat('HH:mm').format(_now);
    final still = widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final h = widget.height;
    Widget digit(int i) => _FlipDigit(value: text[i], height: h, animate: !still);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        digit(0),
        SizedBox(width: h * 0.06),
        digit(1),
        _Colon(height: h),
        digit(3),
        SizedBox(width: h * 0.06),
        digit(4),
      ]),
    );
  }
}

class _Colon extends StatelessWidget {
  final double height;
  const _Colon({required this.height});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final dot = height * 0.09;
    Widget d() => Container(width: dot, height: dot, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    return SizedBox(
      width: height * 0.32,
      height: height,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [d(), SizedBox(height: height * 0.18), d()]),
    );
  }
}

/// Одна цифра: смена — перелистыванием.
class _FlipDigit extends StatefulWidget {
  final String value;
  final double height;
  final bool animate;
  const _FlipDigit({required this.value, required this.height, required this.animate});

  @override
  State<_FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<_FlipDigit> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late String _prev = widget.value;

  @override
  void didUpdateWidget(_FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    _prev = old.value;
    if (widget.animate) {
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final w = h * 0.68;
    return SizedBox(
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          final next = widget.value;
          final flipping = _c.isAnimating;
          if (!flipping) return _Card(digit: next, height: h, width: w);
          // Первая половина: верх прежней цифры падает (0 → −90°);
          // вторая: низ новой ложится (90° → 0).
          final first = t < 0.5;
          final angle = first ? -t * math.pi : (1 - t) * math.pi;
          return Stack(children: [
            // Неподвижно: сверху — новая, снизу — прежняя (пока не закрыта).
            _Half(top: true, child: _Card(digit: next, height: h, width: w)),
            _Half(top: false, child: _Card(digit: first ? _prev : next, height: h, width: w)),
            if (first)
              _Half(
                top: true,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.004)
                    ..rotateX(angle),
                  child: _Card(digit: _prev, height: h, width: w),
                ),
              )
            else
              _Half(
                top: false,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.004)
                    ..rotateX(angle),
                  child: _Card(digit: next, height: h, width: w),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Половина карточки: верх или низ (вторая половина обрезана).
class _Half extends StatelessWidget {
  final bool top;
  final Widget child;
  const _Half({required this.top, required this.child});

  @override
  Widget build(BuildContext context) {
    final a = top ? Alignment.topCenter : Alignment.bottomCenter;
    return Align(
      alignment: a,
      child: ClipRect(child: Align(alignment: a, heightFactor: 0.5, child: child)),
    );
  }
}

/// Карточка цифры: фон, цифра, полоска посередине.
class _Card extends StatelessWidget {
  final String digit;
  final double height, width;
  const _Card({required this.digit, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Светлая тема: белая карточка на подкрашенном фоне «Сейчас» (серая
    // сливалась с ним), полоска — линией контура; тёмная — наоборот.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? scheme.surface.withValues(alpha: 0.9) : scheme.outlineVariant;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? scheme.surfaceContainerHighest : scheme.surface,
        borderRadius: BorderRadius.circular(height * 0.14),
        border: dark ? null : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.5),
      ),
      alignment: Alignment.center,
      child: Stack(alignment: Alignment.center, children: [
        Text(
          digit,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: height * 0.72,
            height: 1,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: height / 2 - 0.5,
          child: Container(height: 1, color: line),
        ),
      ]),
    );
  }
}

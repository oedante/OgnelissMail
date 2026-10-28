// lib/widgets/common/animated_appearance.dart
// Тонкие, быстрые анимации появления. Без внешних зависимостей и без явных
// контроллеров (TweenAnimationBuilder проигрывает один раз при монтировании).

import 'package:flutter/material.dart';

/// Декоративные анимации интерфейса (появление, смена содержимого, Hero).
/// Задаётся настройкой «Анимации интерфейса» (Доступность → Движение) с
/// учётом «Уменьшить движение» и системной «Убрать анимацию» — см. main.dart.
/// По умолчанию выключены: 07.10.2026 на тестовых устройствах выглядели
/// рваными (рывки давал WebView письма в режиме гибридной композиции).
bool uiAnimations = false;

/// Плавное появление: затухание + лёгкий сдвиг снизу. Тонко и быстро — подходит
/// для элементов списка, карточек, секций. Проигрывается один раз при появлении.
class AnimatedAppearance extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double offsetY;
  final Curve curve;
  /// false — показать сразу, без анимации (строка, уже виденная раньше).
  /// Тип виджета при этом не меняется, поэтому начатая анимация не
  /// обрывается при перестроении.
  final bool play;

  const AnimatedAppearance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
    this.offsetY = 10,
    this.curve = Curves.easeOut,
    this.play = true,
  });

  @override
  Widget build(BuildContext context) {
    // Анимации появления отключены (замечание 07.10.2026).
    if (!uiAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: play ? 0.0 : 1.0, end: 1.0),
      duration: duration,
      curve: curve,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * offsetY), child: child),
      ),
    );
  }
}

/// Плавная смена содержимого (fade + лёгкий сдвиг). Оборачивает область, где
/// контент меняется (разделы, результаты поиска). Меняйте key у child, чтобы
/// запустить переход.
class AnimatedContentSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const AnimatedContentSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: uiAnimations ? duration : Duration.zero,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      // Не накладываем уходящий и приходящий друг на друга — чище для целых экранов.
      layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
      child: child,
    );
  }
}

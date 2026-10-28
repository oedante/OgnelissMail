// lib/widgets/common/haptic_wrapper.dart
// Утилита тактильной отдачи (Haptic Feedback).
// Обёртки для действий: свайп, нажатие, долгое нажатие, успех, ошибка.
// Учитывает настройку "Уменьшить движение" из доступности.

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Централизованный haptic feedback
class HapticHelper {
  HapticHelper._();

  /// Лёгкая вибрация (выбор элемента, переключение)
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Средняя вибрация (свайп, действие)
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Тяжёлая вибрация (удаление, важное действие)
  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  /// Вибрация при выборе (toggle, checkbox)
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Успех (отправка, сохранение)
  static Future<void> success() async {
    unawaited(HapticFeedback.mediumImpact());
    await Future.delayed(const Duration(milliseconds: 100));
    unawaited(HapticFeedback.lightImpact());
  }

  /// Ошибка (двойная вибрация)
  static Future<void> error() async {
    unawaited(HapticFeedback.heavyImpact());
    await Future.delayed(const Duration(milliseconds: 80));
    unawaited(HapticFeedback.heavyImpact());
  }

  /// Вибрация при pull-to-refresh (когда достигнут порог)
  static void refresh() {
    HapticFeedback.mediumImpact();
  }
}

/// Обёртка виджета с haptic на tap
class HapticTap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const HapticTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap != null
          ? () {
              HapticHelper.light();
              onTap!();
            }
          : null,
      onLongPress: onLongPress != null
          ? () {
              HapticHelper.medium();
              onLongPress!();
            }
          : null,
      child: child,
    );
  }
}

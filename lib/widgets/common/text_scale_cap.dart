// lib/widgets/common/text_scale_cap.dart
// Ограничение масштаба шрифта в плотных местах интерфейса.
//
// Отзывы тестировщиков (07.10.2026): при крупном системном шрифте кнопки и
// подписи наезжают друг на друга. Текст основного содержимого (письма,
// списки, настройки) масштабируется полностью, а «хром» с фиксированной
// геометрией — панели вкладок и действий, заголовки, сетка календаря, чипы —
// растёт не больше заданного предела. Так делают системные приложения
// Android: подписи панели навигации там тоже не растут бесконечно.

import 'package:flutter/widgets.dart';

/// Пределы масштаба для разных зон интерфейса.
abstract final class TextScaleLimits {
  /// Предел для всего приложения. Выше — вёрстка большинства экранов
  /// разваливается; для очень слабого зрения есть системная экранная лупа.
  static const double app = 1.6;

  /// Панели вкладок и действий, заголовки AppBar.
  static const double chrome = 1.25;

  /// Ячейки с фиксированным размером: сетка календаря, плитки событий.
  static const double grid = 1.15;

  /// Чипы, строки фильтров, компактные кнопки.
  static const double compact = 1.35;
}

/// Ограничивает масштаб шрифта для [child] значением [max].
class TextScaleCap extends StatelessWidget {
  final double max;
  final Widget child;

  const TextScaleCap({super.key, this.max = TextScaleLimits.chrome, required this.child});

  const TextScaleCap.grid({super.key, required this.child}) : max = TextScaleLimits.grid;

  const TextScaleCap.compact({super.key, required this.child}) : max = TextScaleLimits.compact;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);
}

/// AppBar и другие PreferredSizeWidget с ограниченным масштабом шрифта.
class TextScaleCapBar extends StatelessWidget implements PreferredSizeWidget {
  final PreferredSizeWidget child;
  final double max;

  const TextScaleCapBar({super.key, required this.child, this.max = TextScaleLimits.chrome});

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);
}

extension TextScaleContext on BuildContext {
  /// Текущий множитель шрифта (1.0 — обычный).
  double get textScale => MediaQuery.textScalerOf(this).scale(1);

  /// Крупный шрифт: плотные строки стоит перестраивать в столбец.
  bool get isLargeText => textScale >= 1.3;
}

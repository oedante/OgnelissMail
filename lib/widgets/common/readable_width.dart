// lib/widgets/common/readable_width.dart
// Ограничение ширины контента для читаемости на широких экранах.
//
// На десктопе (1920+) текст, растянутый на всю ширину, читается плохо: глаз
// теряет начало следующей строки. Оптимальная длина строки — 60–90 символов,
// это примерно 700–900 логических пикселей. На телефоне и планшете виджет
// ничего не меняет (контент и так уже́ лимита).

import 'package:flutter/material.dart';

class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = 860,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// Максимальная ширина контента. 860 — комфортная длина строки для текста
  /// письма; для форм можно задавать меньше (например, 640).
  final double maxWidth;

  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

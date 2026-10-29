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
    this.fill = false,
  });

  final Widget child;

  /// Максимальная ширина контента. 860 — комфортная длина строки для текста
  /// письма; для форм можно задавать меньше (например, 640).
  final double maxWidth;

  final AlignmentGeometry alignment;

  /// Колонка во всю [maxWidth] (на узком экране — во всю ширину), а не по
  /// самому широкому содержимому (1.8.13): у короткого письма колонка текста
  /// была уже колонки шапки и стояла по центру — текст начинался правее темы
  /// и адресатов.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: fill ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

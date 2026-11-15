// lib/widgets/common/readable_width.dart
// Ограничение ширины контента для читаемости на широких экранах.
//
// На десктопе (1920+) текст, растянутый на всю ширину, читается плохо: глаз
// теряет начало следующей строки. Оптимальная длина строки — 60–90 символов,
// это примерно 700–900 логических пикселей. На телефоне и планшете виджет
// ничего не меняет (контент и так уже́ лимита).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = 860,
    this.alignment = Alignment.topCenter,
    this.fill = false,
    this.heightFactor,
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

  /// Высота по содержимому ([Align.heightFactor]). Без неё [Align] в месте с
  /// ограниченной высотой занимает её всю: панель кнопок письма
  /// (bottomNavigationBar) растягивалась на весь экран — кнопки вставали
  /// наверх, под строку состояния, а белая панель закрывала письмо
  /// (1.10.1, замечание владельца 02.11.2026: при выключенной строке
  /// «Ответить…»).
  final double? heightFactor;

  /// Письмо на компьютере — во всю ширину окна или области чтения, как в
  /// Outlook (2.5.4, замечание владельца 15.11.2026: «не надо ограничивать
  /// письмо по ширине»). Телефон и планшет — колонкой [maxWidth].
  static double mailWidth({double tablet = 860}) =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ? double.infinity : tablet;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      heightFactor: heightFactor,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: fill ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

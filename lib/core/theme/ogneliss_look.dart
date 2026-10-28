// lib/core/theme/ogneliss_look.dart
// «Воздушный» вид (1.8.0, как Ogneliss Dialer 1.7.0; просьба владельца
// 26.10.2026): разделы — синие подписи без серых полос, между строками нет
// линий, фото и кружки с буквой — без кольца и светлее, карточки — без
// рамки, нижние панели плоские, с тонкой линией сверху.
//
// Высококонтрастная тема — как была: полосы, линии, кольца и рамки там
// нужнее ([outlined]). В AMOLED и «Чтении» у карточек остаётся рамка
// ([cardBorder]): на чёрном и на «бумаге» без неё карточку не видно.
//
// Виджеты узнают вид через OgnelissLook.of(context) — правок в каждом месте
// использования полос, групп и фото не нужно.

import 'package:flutter/material.dart';

@immutable
class OgnelissLook extends ThemeExtension<OgnelissLook> {
  /// Границы рисуются явно: полосы разделов, линии между строками, кольца
  /// у фото, тени панелей — высококонтрастная тема.
  final bool outlined;

  /// Рамка у карточек и групп строк: высокий контраст, AMOLED, «Чтение».
  final bool cardBorder;

  const OgnelissLook({this.outlined = false, this.cardBorder = false});

  /// Вид по умолчанию — «воздушный».
  static const airy = OgnelissLook();

  static OgnelissLook of(BuildContext context) => Theme.of(context).extension<OgnelissLook>() ?? airy;

  @override
  OgnelissLook copyWith({bool? outlined, bool? cardBorder}) =>
      OgnelissLook(outlined: outlined ?? this.outlined, cardBorder: cardBorder ?? this.cardBorder);

  @override
  OgnelissLook lerp(covariant OgnelissLook? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Линия между строками списка — только в высококонтрастной теме (1.8.0,
/// «воздушный» вид, как Ogneliss Dialer: строки разделяют поля, а не линии).
class RowDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final Color? color;
  const RowDivider({super.key, this.indent = 0, this.endIndent = 0, this.color});

  @override
  Widget build(BuildContext context) => OgnelissLook.of(context).outlined
      ? Divider(height: 1, thickness: 1, indent: indent, endIndent: endIndent, color: color)
      : const SizedBox.shrink();
}

// lib/widgets/ui/banner_button.dart
// Кнопка в плашке письма: «Снять с контроля», «Изменить», «Отписаться»,
// «Не спам», «В календарь» (1.7.2, замечание 22.10.2026: «кнопки прикреплены
// к нижней границе, а не по середине»).
//
// У TextButton по теме приложения высота 44 и запас касания до 48: плашка
// без своих отступов подстраивалась под кнопку, кнопка упиралась в края
// плашки, а у двухстрочной плашки надпись кнопки оказывалась у нижнего края.
// Здесь кнопка — 36 без запаса касания, плашка — с равными отступами сверху и
// снизу ([bannerPadding]) и строкой по центру.

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Отступы плашки с кнопкой справа: одинаковые сверху и снизу.
const bannerPadding = EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs);

/// Наименьшая высота плашки: кнопка 36 + отступы.
const bannerMinHeight = 44.0;

class BannerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  const BannerButton({super.key, required this.label, required this.onPressed, this.icon, this.color});

  static ButtonStyle style({Color? color}) => TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(48, 36),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      );

  @override
  Widget build(BuildContext context) {
    final i = icon;
    if (i == null) {
      return TextButton(style: style(color: color), onPressed: onPressed, child: Text(label));
    }
    return TextButton.icon(
      style: style(color: color),
      onPressed: onPressed,
      icon: Icon(i, size: 18),
      label: Text(label),
    );
  }
}

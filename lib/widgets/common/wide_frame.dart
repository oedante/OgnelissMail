// lib/widgets/common/wide_frame.dart
// Экран-форма на широком окне (планшет в альбомной ориентации, раскрытый
// складной телефон, Android 16 на больших экранах — там запрет поворота
// игнорируется, П2 #9 плана, 10.10.2026): настройки, письмо в редакторе,
// встреча, заметка растягивались на 1200+ dp — строки настроек в одну линию
// через весь экран, переключатель в метре от названия.
//
// Начиная с ширины окна [Breakpoints.tablet] (840 dp) экран стоит колонкой
// [maxWidth] по центру, по бокам — фон приложения и тонкие линии. Уже —
// ничего не меняется (телефон, планшет в портрете, разделённый экран).

import 'package:flutter/material.dart';

import 'adaptive_layout.dart' show Breakpoints;

class WideFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// Формы и настройки — 720 dp; редактор письма, встреча — шире (840).
  const WideFrame({super.key, required this.child, this.maxWidth = 720});

  /// Для редактора письма и встречи: длинные строки текста.
  const WideFrame.wide({super.key, required this.child}) : maxWidth = 840;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < Breakpoints.tablet || width <= maxWidth + 48) return child;
    final theme = Theme.of(context);
    final edge = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6));
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(left: edge, right: edge)),
          child: SizedBox(
            width: maxWidth,
            // Экран внутри считает своей ширину колонки: шторки, подсказки и
            // расчёты по MediaQuery — под неё, а не под всё окно.
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(maxWidth, MediaQuery.sizeOf(context).height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

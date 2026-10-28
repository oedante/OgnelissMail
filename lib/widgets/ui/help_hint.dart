// lib/widgets/ui/help_hint.dart
// «?» — пояснение по нажатию вместо длинного текста на экране.
//
// Длинные абзацы на входе в экран и под настройками отвлекали и отодвигали
// сами настройки вниз (замечание 10.10.2026). Теперь на экране — короткая
// строка, а «как это работает» открывается по значку «?» в шторке.

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/app_sheet.dart';

/// Открыть пояснение в нижней шторке.
Future<void> showHelpSheet(BuildContext context, {String? title, required String text}) {
  return showAppSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null && title.isNotEmpty) ...[
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.m),
              ],
              Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
              const SizedBox(height: Space.l),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(AppLocalizations.of(ctx).tr('close')),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Значок «?» — открывает пояснение. [compact] — маленький, рядом с
/// названием настройки; иначе обычная кнопка (для AppBar).
class HelpButton extends StatelessWidget {
  final String text;
  final String? title;
  final bool compact;
  const HelpButton({super.key, required this.text, this.title, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = compact ? AppColors.mutedText(context) : null;
    return IconButton(
      tooltip: l10n.tr('helpWhat'),
      icon: Icon(AppIcons.help, color: color),
      iconSize: compact ? 18 : null,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact ? const BoxConstraints.tightFor(width: 32, height: 32) : null,
      onPressed: () => showHelpSheet(context, title: title, text: text),
    );
  }
}

/// Название настройки со значком «?» после него.
class TitleWithHelp extends StatelessWidget {
  final String title;
  final String? hint;
  final TextStyle? style;
  const TitleWithHelp(this.title, {super.key, this.hint, this.style});

  @override
  Widget build(BuildContext context) {
    final t = Text(title, style: style);
    if (hint == null || hint!.isEmpty) return t;
    return Row(
      children: [
        Flexible(child: t),
        HelpButton(text: hint!, title: title, compact: true),
      ],
    );
  }
}

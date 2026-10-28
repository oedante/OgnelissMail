// lib/widgets/ui/empty_state.dart
// Пустой экран — один вид во всех разделах (Ф0, docs/plan/UI_REDESIGN.md):
// крупный приглушённый значок, заголовок, пояснение и, если есть, одно
// действие. Раньше у почты, задач, заметок, контактов и правил были свои
// размеры значков (72–80), цвета (disabledColor, hintColor, alpha 0.15–0.5)
// и отступы, а у контактов — просто строка текста.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';

import '../../core/theme/tokens.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  /// Дополнительная строка (например, почему папка пуста).
  final String? note;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  /// Внутри RefreshIndicator: прокручиваемый, чтобы работало «потянуть вниз».
  final bool scrollable;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.note,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.scrollable = false,
  });

  static const _iconSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _iconSize, color: muted.withValues(alpha: 0.35)),
          const SizedBox(height: Space.l),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface)),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ],
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Text(note!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: Space.xl),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? AppIcons.add),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
    if (!scrollable) return Center(child: content);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

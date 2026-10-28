// lib/widgets/ui/action_sheet.dart
// Общая шторка действий: заголовок с объектом (значок, имя, подпись) и
// список действий одной высоты. Раньше каждая шторка собиралась вручную —
// разные отступы, размеры значков и цвет «опасных» пунктов.
//
// Открывается через showAppSheet — с учётом системных отступов на Android
// (edge-to-edge) и «дом»-индикатора на iPhone.

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/app_theme.dart';
import '../common/app_sheet.dart';

class ActionSheetItem<T> {
  final IconData icon;
  final String label;
  final String? subtitle;
  final T value;
  final bool destructive;
  final bool enabled;

  const ActionSheetItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
  });
}

/// Показать шторку действий. Возвращает value выбранного пункта или null.
/// [footer] — виджет под пунктами; шторку он не закрывает.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  Widget? leading,
  required List<ActionSheetItem<T>> items,
  Widget? footer,
}) {
  return showAppSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ActionSheet<T>(title: title, subtitle: subtitle, leading: leading, items: items, footer: footer),
  );
}

class _ActionSheet<T> extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<ActionSheetItem<T>> items;
  /// Под пунктами, через разделитель (например, выбор темы в «Ещё»).
  final Widget? footer;

  const _ActionSheet({this.title, this.subtitle, this.leading, required this.items, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.m),
                child: Row(children: [
                  if (leading != null) ...[
                    SizedBox(width: Sizes.avatar, height: Sizes.avatar, child: Center(child: leading)),
                    const SizedBox(width: Space.m),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        if ((subtitle ?? '').isNotEmpty)
                          Text(subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.mutedText(context))),
                      ],
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
            ],
            for (final it in items)
              ListTile(
                minTileHeight: Sizes.tapTarget + Space.xs,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                enabled: it.enabled,
                leading: Icon(it.icon, color: it.destructive ? error : null),
                title: Text(it.label, style: it.destructive ? TextStyle(color: error) : null),
                subtitle: it.subtitle == null ? null : Text(it.subtitle!),
                onTap: () => Navigator.of(context).pop(it.value),
              ),
            if (footer != null) ...[
              const Divider(height: Space.l),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

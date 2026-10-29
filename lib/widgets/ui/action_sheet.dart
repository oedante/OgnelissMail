// lib/widgets/ui/action_sheet.dart
// Общая шторка действий: заголовок с объектом (значок, имя, подпись) и
// список действий одной высоты. Раньше каждая шторка собиралась вручную —
// разные отступы, размеры значков и цвет «опасных» пунктов.
//
// 1.8.8 (замечание владельца 29.10.2026: «всплывающие панели — как карточка
// по долгому нажатию на письмо или контакт»): не шторка снизу, а карточка
// на размытом фоне — та же, что у меню «⋮» (showAnchoredMenu): по центру
// экрана или у кнопки [anchor], шапка с объектом, строки со значками,
// необратимые действия — цветом ошибки.

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/app_theme.dart';
import '../common/peek_card.dart';

export '../common/peek_card.dart' show AppMenuEntry;

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

/// Показать действия карточкой. Возвращает value выбранного пункта или null.
/// [footer] — пояснение под пунктами. [anchor] — кнопка, у которой открыть
/// (null — по центру экрана).
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  Widget? leading,
  required List<ActionSheetItem<T>> items,
  Widget? footer,
  Rect? anchor,
  Widget? headerTrailing,
}) {
  return showAnchoredMenu<T>(
    context,
    anchor: anchor,
    header: title == null
        ? null
        : _ActionHeader(title: title, subtitle: subtitle, leading: leading, trailing: headerTrailing),
    footer: footer,
    entries: [
      for (final it in items)
        AppMenuEntry<T>(
          value: it.value,
          label: it.label,
          icon: it.icon,
          subtitle: it.subtitle,
          destructive: it.destructive,
          enabled: it.enabled,
        ),
    ],
  );
}

/// Шапка карточки: значок объекта, имя и подпись — как у карточки письма.
class _ActionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Справа в шапке — например, «?» с пояснением (HelpButton).
  final Widget? trailing;

  const _ActionHeader({required this.title, this.subtitle, this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
      child: Row(children: [
        if (leading != null) ...[
          SizedBox(width: Sizes.avatar, height: Sizes.avatar, child: Center(child: leading)),
          const SizedBox(width: Space.m),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              if ((subtitle ?? '').isNotEmpty)
                Text(subtitle!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Выбор значения карточкой по центру экрана (1.8.8) — вместо шторки со
/// списком: выбранное — с галочкой, [title] — что выбирается.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<AppMenuEntry<T>> entries,
  T? selected,
  Widget? footer,
  Rect? anchor,
  Widget? headerTrailing,
}) =>
    showAnchoredMenu<T>(
      context,
      anchor: anchor,
      selected: selected,
      header: title == null ? null : _ActionHeader(title: title, subtitle: subtitle, trailing: headerTrailing),
      footer: footer,
      entries: entries,
    );

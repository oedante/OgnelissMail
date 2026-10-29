// lib/widgets/ui/app_menu_button.dart
// Кнопка с меню — замена PopupMenuButton (1.8.6): меню в стиле карточки по
// удержанию письма (размытый фон, карточка, строки как у кнопки «Написать»),
// а не стандартное меню Material. Вид меню — showAnchoredMenu в
// lib/widgets/common/peek_card.dart.
//
// По умолчанию — кнопка «⋮»; [child] — своя кнопка (поле выбора значения,
// подпись со стрелкой). [initialValue] — текущее значение: в меню оно с
// галочкой.

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../common/peek_card.dart';

export '../common/peek_card.dart' show AppMenuEntry, showAnchoredMenu;

class AppMenuButton<T> extends StatelessWidget {
  final List<AppMenuEntry<T>> Function(BuildContext context) itemBuilder;
  final ValueChanged<T>? onSelected;
  final Widget? icon;
  final double? iconSize;
  final String? tooltip;
  final T? initialValue;
  final bool enabled;

  /// Своя кнопка вместо значка: нажатие на неё открывает меню.
  final Widget? child;

  const AppMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.icon,
    this.iconSize,
    this.tooltip,
    this.initialValue,
    this.enabled = true,
    this.child,
  });

  Future<void> _open(BuildContext context) async {
    final entries = itemBuilder(context);
    if (entries.isEmpty) return;
    // Кнопки нет на экране — меню по центру.
    final v = await showAnchoredMenu<T>(context, anchor: peekAnchorOf(context), entries: entries, selected: initialValue);
    if (v != null) onSelected?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final tip = tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    if (child != null) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: enabled ? () => _open(context) : null,
          borderRadius: Radii.chipAll,
          child: child,
        ),
      );
    }
    return IconButton(
      icon: icon ?? const Icon(AppIcons.more_vert),
      iconSize: iconSize,
      tooltip: tip,
      onPressed: enabled ? () => _open(context) : null,
    );
  }
}

/// Поле выбора значения (1.8.8) — замена DropdownButtonFormField и
/// DropdownButton: их список Material выглядел чужим рядом с меню «⋮» и
/// карточкой по удержанию. Нажатие — та же карточка-меню у поля, выбранное
/// значение — с галочкой.
///
/// [decoration] — поле формы (подпись, значок, рамка темы); null — строка
/// без рамки (как DropdownButton без подчёркивания). [selectedBuilder] — свой
/// вид выбранного значения в поле (например, имя ящика цветом).
class AppSelectField<T> extends StatelessWidget {
  final T? value;
  final List<AppMenuEntry<T>> entries;

  /// null — поле недоступно.
  final ValueChanged<T>? onChanged;
  final InputDecoration? decoration;
  final Widget Function(BuildContext context, AppMenuEntry<T>? selected)? selectedBuilder;

  /// По ширине значения (справа в строке настроек), а не на всю ширину.
  final bool compact;

  const AppSelectField({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.decoration,
    this.selectedBuilder,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final sel = entries.where((e) => !e.isDivider && e.value == value).firstOrNull;
    final shown = selectedBuilder?.call(context, sel) ??
        Text(
          sel?.label ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(color: enabled ? null : theme.disabledColor),
        );
    final row = Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
      if (decoration == null && sel?.icon != null) ...[
        Icon(sel!.icon, size: Sizes.iconRow, color: sel.iconColor ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: Space.s),
      ],
      if (compact) Flexible(child: shown) else Expanded(child: shown),
      Icon(AppIcons.arrow_drop_down, color: enabled ? theme.colorScheme.onSurfaceVariant : theme.disabledColor),
    ]);
    final d = decoration;
    final field = d == null
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.tapTarget),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.xs), child: row),
          )
        : InputDecorator(decoration: d.copyWith(enabled: enabled), isEmpty: sel == null, child: row);
    return AppMenuButton<T>(
      tooltip: d?.labelText ?? sel?.label ?? MaterialLocalizations.of(context).showMenuTooltip,
      initialValue: value,
      enabled: enabled,
      itemBuilder: (_) => entries,
      onSelected: onChanged,
      child: field,
    );
  }
}

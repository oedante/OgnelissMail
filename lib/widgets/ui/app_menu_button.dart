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
    final anchor = peekAnchorOf(context) ??
        Rect.fromCenter(center: MediaQuery.sizeOf(context).center(Offset.zero), width: 0, height: 0);
    final v = await showAnchoredMenu<T>(context, anchor: anchor, entries: entries, selected: initialValue);
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

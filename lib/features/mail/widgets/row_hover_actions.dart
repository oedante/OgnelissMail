// lib/features/mail/widgets/row_hover_actions.dart
//
// Быстрые кнопки строки письма при наведении мыши (1.10.5, по образцу
// Outlook, планшет и компьютер): удалить, в архив, прочитано, флажок —
// поверх правого края строки, на месте даты. На сенсорном экране наведения
// нет — строка как прежде (действия — свайпом и удержанием).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';

class RowHoverAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;
  const RowHoverAction(this.icon, this.tooltip, this.onTap, {this.selected = false, this.color});
}

class RowHoverActions extends StatefulWidget {
  final Widget child;
  final List<RowHoverAction> actions;

  /// Выключено (режим выбора писем) — только строка.
  final bool enabled;

  const RowHoverActions({super.key, required this.child, required this.actions, this.enabled = true});

  @override
  State<RowHoverActions> createState() => _RowHoverActionsState();
}

class _RowHoverActionsState extends State<RowHoverActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(children: [
        widget.child,
        if (_hover)
          Positioned(
            top: Space.xs,
            right: Space.s,
            child: Material(
              color: scheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: Radii.chipAll,
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final a in widget.actions)
                  IconButton(
                    tooltip: a.tooltip,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(a.icon, fill: a.selected ? 1 : 0, color: a.color ?? scheme.onSurfaceVariant),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      a.onTap();
                    },
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

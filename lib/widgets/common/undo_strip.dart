// lib/widgets/common/undo_strip.dart
// «Письмо удалено · Вернуть» (1.6.49+95, как «Чат удалён · Отмена» в
// Telegram): пока удаление или перенос ждут выполнения (7 секунд), их можно
// отменить. Раньше «Отменить» была в плашке, а плашки в приложении скрыты —
// вернуть письмо было нельзя.
//
// С 1.7.2+106 строка — поверх ленты внизу, над нижней панелью (замечание
// владельца 24.10.2026: строка вставлялась над лентой, и при её появлении и
// исчезновении вся лента вздрагивала). Под большим пальцем, как в Telegram и
// Nine; ленту не сдвигает.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'undo_manager.dart';

/// Подложка строки поверх ленты: непрозрачная (письма под ней не
/// просвечивают), спокойного оттенка акцента, с лёгкой тенью.
class FloatingStripSurface extends StatelessWidget {
  final Widget child;
  const FloatingStripSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Material(
        color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.10), scheme.surfaceContainerHigh),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: Radii.chipAll,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.only(left: Space.m), child: child),
      ),
    );
  }
}

/// Появление и исчезновение строки поверх ленты: снизу вверх с
/// проявлением; при «уменьшении движения» — сразу.
class FloatingStripSwitcher extends StatelessWidget {
  final Widget? child;
  const FloatingStripSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child ?? const SizedBox(key: ValueKey('none'), width: double.infinity),
    );
  }
}

class UndoStrip extends StatefulWidget {
  const UndoStrip({super.key});

  @override
  State<UndoStrip> createState() => _UndoStripState();
}

class _UndoStripState extends State<UndoStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    EmailUndoManager.pending.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    EmailUndoManager.pending.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    final on = EmailUndoManager.pending.value != null;
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final action = EmailUndoManager.pending.value;
    return FloatingStripSwitcher(
      child: action == null ? null : KeyedSubtree(key: const ValueKey('undo'), child: _bar(context, action)),
    );
  }

  Widget _bar(BuildContext context, UndoableAction action) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final end = EmailUndoManager.deadline;
    final total = const Duration(seconds: 7).inMilliseconds;
    final leftMs = end == null ? 0 : end.difference(DateTime.now()).inMilliseconds.clamp(0, total).toInt();
    final secs = (leftMs / 1000).ceil();
    return FloatingStripSurface(
      child: Row(children: [
        // Отсчёт — кольцом с секундами, как в Telegram.
        SizedBox.square(
          dimension: Sizes.icon,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: total == 0 ? 0 : leftMs / total,
              strokeWidth: 2,
              color: scheme.primary,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
            ),
            Text('$secs', style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
          ]),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Text(action.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
        ),
        TextButton.icon(
          onPressed: () {
            if (EmailUndoManager.undoPending()) unawaited(HapticFeedback.selectionClick());
          },
          icon: const Icon(AppIcons.undo, size: Sizes.iconInline),
          label: Text(l10n.tr('undoReturn')),
        ),
      ]),
    );
  }
}

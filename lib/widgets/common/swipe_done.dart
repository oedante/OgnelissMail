// lib/widgets/common/swipe_done.dart
//
// «Сделано» после свайпа (2.2.0, замечание владельца 09.11.2026: «в беседах
// свайп "На контроль" никак не отображается… свайпам не хватает понимания,
// что что-то сделано»). Строка возвращается на место, а поверх неё на
// секунду — плашка цвета действия с результатом: «На контроле», «Снято с
// контроля», «Прочитано», «Флажок снят»… Экранный диктор слышит то же.
//
// Только для действий, после которых письмо остаётся на месте (прочитано,
// флажок, контроль): архив, удаление и спам убирают строку и показывают
// «Вернуть». Плашка не принимает касаний и не сдвигает строку; «Уменьшить
// движение» — без анимации появления.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/email_model.dart';
import '../../features/settings/providers/settings_provider.dart' show SwipeAction;
import '../../l10n/app_localizations.dart';

/// Событие «сделано» для строки [id].
class SwipeDoneEvent {
  final String id;
  final IconData icon;
  final String label;

  /// Цвет действия (константа AppColors, как у панели свайпа).
  final Color color;

  /// Плашка у края, с которого тянули (true — слева).
  final bool fromStart;
  const SwipeDoneEvent(this.id, {required this.icon, required this.label, required this.color, this.fromStart = true});
}

class SwipeDone {
  SwipeDone._();

  /// Последнее событие; строки слушают и показывают своё.
  static final events = ValueNotifier<SwipeDoneEvent?>(null);

  /// Сколько держится плашка.
  static const hold = Duration(milliseconds: 1100);

  /// Показать результат на строке [SwipeDoneEvent.id] и сказать его диктору.
  static void show(BuildContext context, SwipeDoneEvent e) {
    events.value = e;
    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    unawaited(SemanticsService.sendAnnouncement(View.of(context), e.label, dir));
  }
}

/// Плашка «сделано» для свайпа [a] над письмом [e] — состояние ПОСЛЕ
/// действия. [read] — строка сейчас прочитана (у свёрнутой беседы — вся),
/// [control] — её отметка «На контроле» до действия. Для действий, которые
/// убирают письмо или открывают окно, — ничего.
void showSwipeDone(BuildContext context, SwipeAction a, EmailModel e, AppLocalizations l10n,
    {required String id, bool? read, int? control, bool fromStart = true}) {
  final SwipeDoneEvent? ev = switch (a) {
    SwipeAction.markRead => (read ?? e.isRead)
        ? SwipeDoneEvent(id,
            icon: AppIcons.mark_email_unread, label: l10n.tr('swipeDoneUnread'), color: AppColors.infoBlue, fromStart: fromStart)
        : SwipeDoneEvent(id,
            icon: AppIcons.mark_email_read, label: l10n.tr('swipeDoneRead'), color: AppColors.infoBlue, fromStart: fromStart),
    SwipeAction.flag => SwipeDoneEvent(id,
        icon: AppIcons.flag,
        label: l10n.tr(e.isFlagged ? 'swipeDoneUnflag' : 'swipeDoneFlag'),
        color: AppColors.warningYellow,
        fromStart: fromStart),
    SwipeAction.control => SwipeDoneEvent(id,
        icon: (control ?? e.controlState) != 0 ? AppIcons.bookmark_remove : AppIcons.bookmark_added,
        label: l10n.tr((control ?? e.controlState) != 0 ? 'swipeDoneControlOff' : 'swipeDoneControl'),
        color: AppColors.successGreen,
        fromStart: fromStart),
    _ => null,
  };
  if (ev != null) SwipeDone.show(context, ev);
}

/// Строка списка с плашкой «сделано» поверх.
class SwipeDoneOverlay extends StatefulWidget {
  /// Тот же id, что в [SwipeDoneEvent.id].
  final String id;
  final Widget child;
  final BorderRadius? borderRadius;
  const SwipeDoneOverlay({super.key, required this.id, required this.child, this.borderRadius});

  @override
  State<SwipeDoneOverlay> createState() => _SwipeDoneOverlayState();
}

class _SwipeDoneOverlayState extends State<SwipeDoneOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );
  SwipeDoneEvent? _event;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    SwipeDone.events.addListener(_onEvent);
  }

  void _onEvent() {
    final e = SwipeDone.events.value;
    if (e == null || e.id != widget.id || !mounted) return;
    _timer?.cancel();
    setState(() => _event = e);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.value = 1;
    } else {
      unawaited(_c.forward(from: _c.value));
    }
    _timer = Timer(SwipeDone.hold, () {
      if (!mounted) return;
      if (reduce) {
        _c.value = 0;
        setState(() => _event = null);
      } else {
        unawaited(_c.reverse().then((_) {
          if (mounted) setState(() => _event = null);
        }));
      }
    });
  }

  @override
  void dispose() {
    SwipeDone.events.removeListener(_onEvent);
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    if (e == null) return widget.child;
    final (bg, fg) = SwipeTone.of(context, e.color);
    final theme = Theme.of(context);
    return Stack(children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: FadeTransition(
            opacity: _c,
            child: DecoratedBox(
              key: const ValueKey('swipe_done'),
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                gradient: LinearGradient(
                  begin: e.fromStart ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  end: e.fromStart ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  colors: [bg, bg.withValues(alpha: 0.92), bg.withValues(alpha: 0)],
                  stops: const [0, 0.55, 1],
                ),
              ),
              child: Align(
                alignment: e.fromStart ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppIcons.check_circle, size: Sizes.iconInline + 4, fill: 1, color: fg),
                    const SizedBox(width: Space.s),
                    Icon(e.icon, size: Sizes.iconInline + 2, color: fg),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        e.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

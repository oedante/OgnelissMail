// lib/widgets/common/swipe_preview.dart
// Gesture preview — иконка и цвет появляются при свайпе,
// показывая какое действие будет выполнено до отпускания.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';

/// Виджет-индикатор действия свайпа
class SwipeActionPreview extends StatelessWidget {
  final SwipeAction action;
  final Alignment alignment;

  const SwipeActionPreview({
    super.key,
    required this.action,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final config = _actionConfig(action, AppLocalizations.of(context));
    final (bg, fg) = SwipeTone.of(context, config.color);

    return Container(
      color: bg,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(config.icon, color: fg, size: 28),
          const SizedBox(height: Space.xs),
          Text(
            config.label,
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  _SwipeConfig _actionConfig(SwipeAction action, AppLocalizations l10n) {
    switch (action) {
      case SwipeAction.markRead:
        return _SwipeConfig(AppIcons.mark_email_read, l10n.tr('readFlag'), AppColors.infoBlue);
      case SwipeAction.flag:
        return _SwipeConfig(AppIcons.flag, l10n.tr('flag'), AppColors.warningYellow);
      case SwipeAction.archive:
        return _SwipeConfig(AppIcons.archive, l10n.tr('ntfArchive'), AppColors.primaryBlue);
      case SwipeAction.delete:
        return _SwipeConfig(AppIcons.delete, l10n.tr('deleteLbl'), AppColors.errorRed);
      case SwipeAction.moveToJunk:
        return _SwipeConfig(AppIcons.report, l10n.tr('spam'), AppColors.accentOrange);
      case SwipeAction.moveTo:
        return _SwipeConfig(AppIcons.drive_file_move, l10n.tr('move'), AppColors.primaryBlue);
      case SwipeAction.snooze:
        return _SwipeConfig(AppIcons.watch_later, l10n.tr('later'), AppColors.accentOrange);
      case SwipeAction.reply:
        return _SwipeConfig(AppIcons.reply, l10n.tr('replyLbl'), AppColors.primaryBlue);
      case SwipeAction.forward:
        return _SwipeConfig(AppIcons.forward, l10n.tr('forwardLbl'), AppColors.primaryBlue);
      case SwipeAction.createTask:
        return _SwipeConfig(AppIcons.add_task, l10n.tr('swipePrevTask'), AppColors.successGreen);
      case SwipeAction.findBySender:
        return _SwipeConfig(AppIcons.person_search, l10n.tr('swipePrevSender'), AppColors.primaryBlue);
      case SwipeAction.control:
        return _SwipeConfig(AppIcons.task_alt, l10n.tr('controlSet'), AppColors.successGreen);
      case SwipeAction.none:
        return const _SwipeConfig(AppIcons.more_horiz, '', AppColors.tagGeneral);
    }
  }
}

class _SwipeConfig {
  final IconData icon;
  final String label;
  final Color color;
  const _SwipeConfig(this.icon, this.label, this.color);
}

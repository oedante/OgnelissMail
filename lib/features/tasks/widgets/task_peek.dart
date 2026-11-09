// lib/features/tasks/widgets/task_peek.dart
// Карточка задачи по удержанию — одна для «Задач» и «Моего дня» (доска и
// шкала). Решение владельца 09.11.2026: долгое нажатие на задачу, как на
// письмо и контакт, — «Сегодня», «Завтра», «На следующей неделе», «Без
// срока», «Выполнено», «Удалить» и «Выбрать дату…»; своё время — в самой
// задаче («Изменить»).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart' show mailOpenPath;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/task_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../calendar/calendar_data.dart' show capitalize;
import '../../../services/tasks/task_actions_service.dart';
import '../../../widgets/common/peek_card.dart';
import '../../../widgets/ui/wheel_pickers.dart';

/// Показать карточку задачи [t]. [onToggleDone] и [onDelete] — экран сам
/// показывает «Отменить» и прячет строку; перенос срока — здесь.
Future<void> showTaskPeek(
  BuildContext context,
  WidgetRef ref,
  TaskModel t, {
  required Rect? anchor,
  required VoidCallback onEdit,
  required VoidCallback onToggleDone,
  required VoidCallback onDelete,
}) {
  unawaited(HapticFeedback.mediumImpact());
  final l10n = AppLocalizations.of(context);
  final actions = ref.read(taskActionsProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  void due(DateTime? d) {
    unawaited(HapticFeedback.selectionClick());
    unawaited(actions.reschedule(t.accountId, t.id, d));
  }

  Future<void> pick() async {
    final cur = t.dueDate?.toLocal();
    final d = await showWheelDatePicker(context,
        initial: cur == null || cur.isBefore(today) ? today : cur, first: today, title: l10n.tr('taskPickDate'));
    if (d != null) due(d);
  }

  final done = PeekAction(
    icon: t.isDone ? AppIcons.undo : AppIcons.check,
    label: l10n.tr(t.isDone ? 'taskReopen' : 'taskDone'),
    onTap: onToggleDone,
  );
  final star = PeekAction(
    icon: AppIcons.star,
    filled: t.isFlagged,
    color: t.isFlagged ? AppColors.brandAmber : null,
    label: l10n.tr('important'),
    onTap: () => unawaited(actions.toggleImportant(t.accountId, t.id)),
  );
  final edit = PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: onEdit);
  final todayA = PeekAction(icon: AppIcons.today, label: l10n.tr('today'), onTap: () => due(today));
  final tomorrowA =
      PeekAction(icon: AppIcons.event, label: l10n.tr('tomorrow'), onTap: () => due(today.add(const Duration(days: 1))));
  final linked = t.linkedEmailId;
  return showPeekCard(
    context,
    anchor: anchor,
    onOpen: onEdit,
    card: TaskPeekCard(task: t, l10n: l10n),
    moreLabel: l10n.tr('peekMore'),
    actions: [
      done,
      if (!t.isDone) todayA,
      if (!t.isDone) tomorrowA,
      edit,
    ],
    more: [
      PeekGroup(title: l10n.tr('peekGroupTask'), items: [done, star, edit]),
      if (!t.isDone)
        PeekGroup(title: l10n.tr('peekGroupDue'), items: [
          todayA,
          tomorrowA,
          PeekAction(
              icon: AppIcons.date_range, label: l10n.tr('laterNextWeek'), onTap: () => due(TaskReschedule.nextWeek(now))),
          PeekAction(icon: AppIcons.calendar_month, label: l10n.tr('taskPickDate'), onTap: () => unawaited(pick())),
          if (t.dueDate != null || t.reminderAt != null)
            PeekAction(icon: AppIcons.event_busy, label: l10n.tr('noDueDate'), onTap: () => due(null)),
        ]),
      if (linked != null)
        PeekGroup(title: l10n.tr('peekGroupMail'), items: [
          PeekAction(
            icon: AppIcons.mail,
            label: l10n.tr('openEmail'),
            onTap: () => context.push(mailOpenPath(context, linked, accountId: t.accountId)),
          ),
        ]),
      PeekGroup(items: [
        PeekAction(
          icon: AppIcons.delete,
          label: l10n.delete,
          color: AppColors.errorText(context),
          onTap: onDelete,
        ),
      ]),
    ],
  );
}

/// Содержимое карточки: срок, напоминание, письмо, описание, подзадачи.
class TaskPeekCard extends StatelessWidget {
  final TaskModel task;
  final AppLocalizations l10n;
  const TaskPeekCard({super.key, required this.task, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final t = task;
    final fmt = DateFormat('EEE, d MMM', l10n.localeCode);
    String when(DateTime d) {
      final l = d.toLocal();
      final time = (l.hour != 0 || l.minute != 0) ? ', ${DateFormat('HH:mm').format(l)}' : '';
      return '${capitalize(fmt.format(l))}$time';
    }

    Widget line(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(children: [
            Icon(icon, size: 16, color: color ?? muted),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color ?? muted)),
            ),
          ]),
        );
    final desc = (t.description ?? '').trim();
    final overdue = !t.isDone && t.dueDate != null && t.dueDate!.toLocal().isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(t.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              decoration: t.isDone ? TextDecoration.lineThrough : null,
              color: t.isDone ? muted : null,
            )),
        if (t.dueDate != null)
          line(AppIcons.event, when(t.dueDate!), color: overdue ? AppColors.errorText(context) : null),
        if (t.reminderAt != null && !t.isDone) line(AppIcons.notifications, when(t.reminderAt!)),
        if ((t.linkedEmailSubject ?? '').trim().isNotEmpty) line(AppIcons.mail, t.linkedEmailSubject!.trim()),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text(desc, maxLines: 5, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
        ],
        if (t.subtasks.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          for (final st in t.subtasks.take(5))
            line(st.done ? AppIcons.check_box : AppIcons.check_box_outline_blank, st.title),
          if (t.subtasks.length > 5)
            line(AppIcons.more_horiz, '${t.subtasks.where((s) => s.done).length}/${t.subtasks.length}'),
        ],
      ]),
    );
  }
}

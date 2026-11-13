// lib/features/assignments/assignment_widgets.dart
// Общие детали поручений: метка статуса, портрет другой стороны, карточка
// по удержанию с быстрыми действиями (решение владельца 09.11.2026: «и в
// поручениях должны срабатывать долгие нажатия с быстрыми функциями»).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_router.dart' show mailOpenPath;
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/tasks/task_actions_service.dart' show TaskReschedule;
import '../../widgets/common/hero_email_transition.dart';
import '../../widgets/common/peek_card.dart';
import '../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../../widgets/ui/wheel_pickers.dart';
import '../../core/utils/text_safe.dart' show initialOf;
import 'assignment_edit.dart';

/// Подпись статуса.
String assignmentStatusLabel(int status, AppLocalizations l10n) => l10n.tr(switch (status) {
      AssignmentStatus.inProgress => 'assignStInProgress',
      AssignmentStatus.review => 'assignStReview',
      AssignmentStatus.done => 'assignStDone',
      AssignmentStatus.cancelled => 'assignStCancelled',
      _ => 'assignStNew',
    });

Color assignmentStatusColor(int status, BuildContext context) => switch (status) {
      AssignmentStatus.inProgress => Theme.of(context).colorScheme.primary,
      AssignmentStatus.review => AppColors.warningText(context),
      AssignmentStatus.done => AppColors.successText(context),
      AssignmentStatus.cancelled => AppColors.mutedText(context),
      _ => AppColors.infoText(context),
    };

/// Метка статуса цветной плашкой.
class AssignmentStatusPill extends StatelessWidget {
  final int status;
  const AssignmentStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = assignmentStatusColor(status, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Text(assignmentStatusLabel(status, AppLocalizations.of(context)),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/// Портрет другой стороны поручения (фото из контактов или буква).
class AssignmentAvatar extends StatelessWidget {
  final AssignmentView v;
  final double radius;
  const AssignmentAvatar(this.v, {super.key, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    // Проект — значок плана, а не буква человека.
    if (v.isProject) {
      final scheme = Theme.of(context).colorScheme;
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        child: Icon(AppIcons.account_tree, size: radius, color: scheme.onPrimaryContainer),
      );
    }
    final email = v.otherEmail ?? '';
    final name = v.otherName;
    return HeroEmailAvatar(
      emailId: 'asg${v.id}',
      initial: initialOf(name),
      color: HeroEmailAvatar.colorForEmail(email),
      radius: radius,
      hero: false,
      email: email,
    );
  }
}

/// Карточка поручения по удержанию: быстрые действия по роли и статусу.
Future<void> showAssignmentPeek(BuildContext context, WidgetRef ref, AssignmentView v, {Rect? anchor}) {
  unawaited(HapticFeedback.mediumImpact());
  final l10n = AppLocalizations.of(context);
  final svc = ref.read(assignmentServiceProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Перенос на другой день сохраняет время срока (13.11.2026).
  void due(DateTime? d) => assignmentFire(svc.reschedule(v, d == null ? null : assignmentDueOn(d, v.due)));
  Future<void> pick() async {
    final cur = v.due;
    final d = await showWheelDatePicker(context,
        initial: cur == null || cur.isBefore(today) ? today : cur, first: today, title: l10n.tr('taskPickDate'));
    if (d != null) due(d);
  }

  Future<void> pickTime() async {
    final cur = v.due ?? today;
    final t = await showWheelTimePicker(context,
        initial: dueHasTime(cur) ? TimeOfDay(hour: cur.hour, minute: cur.minute) : const TimeOfDay(hour: 18, minute: 0),
        title: l10n.tr('time'),
        minuteInterval: 5);
    if (t != null) assignmentFire(svc.reschedule(v, DateTime(cur.year, cur.month, cur.day, t.hour, t.minute)));
  }

  final s = v.status;
  final actions = <PeekAction>[
    if (v.outgoing && s == AssignmentStatus.review)
      PeekAction(
          icon: AppIcons.check,
          label: l10n.tr('assignAccept'),
          onTap: () => assignmentFire(svc.setStatus(v, AssignmentStatus.done))),
    if (v.outgoing && s == AssignmentStatus.review)
      PeekAction(
          icon: AppIcons.undo,
          label: l10n.tr('assignReturn'),
          onTap: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress))),
    if (v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress))
      PeekAction(icon: AppIcons.notifications, label: l10n.tr('assignRemind'), onTap: () => assignmentFire(svc.remind(v))),
    if (!v.outgoing && s == AssignmentStatus.open)
      PeekAction(
          icon: AppIcons.play_arrow,
          label: l10n.tr('assignTake'),
          onTap: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress))),
    if (!v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress))
      PeekAction(
          icon: AppIcons.task_alt,
          label: l10n.tr('assignDoneAction'),
          onTap: () => assignmentFire(svc.setStatus(v, AssignmentStatus.review))),
    PeekAction(icon: AppIcons.chevron_right, label: l10n.tr('assignOpen'), onTap: () => context.push('/assignments/${v.id}')),
  ];
  final src = v.row.sourceEmailId;
  return showPeekCard(
    context,
    anchor: anchor,
    onOpen: () => context.push('/assignments/${v.id}'),
    card: _AssignmentPeekCard(v: v),
    moreLabel: l10n.tr('peekMore'),
    actions: actions.take(4).toList(),
    more: [
      PeekGroup(title: l10n.tr('assignTitle'), items: actions),
      if (v.active)
        PeekGroup(title: l10n.tr('peekGroupDue'), items: [
          PeekAction(icon: AppIcons.today, label: l10n.tr('today'), onTap: () => due(today)),
          PeekAction(icon: AppIcons.event, label: l10n.tr('tomorrow'), onTap: () => due(today.add(const Duration(days: 1)))),
          PeekAction(
              icon: AppIcons.date_range, label: l10n.tr('laterNextWeek'), onTap: () => due(TaskReschedule.nextWeek(now))),
          PeekAction(icon: AppIcons.calendar_month, label: l10n.tr('taskPickDate'), onTap: () => unawaited(pick())),
          PeekAction(icon: AppIcons.schedule, label: l10n.tr('time'), onTap: () => unawaited(pickTime())),
          if (v.due != null) PeekAction(icon: AppIcons.event_busy, label: l10n.tr('noDueDate'), onTap: () => due(null)),
        ]),
      // Изменить и права постановщика (13.11.2026): у этапа права — в
      // проекте.
      if (v.outgoing && v.active && !v.isProject)
        PeekGroup(items: [
          PeekAction(
              icon: AppIcons.edit,
              label: l10n.tr('edit'),
              onTap: () => unawaited(editAssignment(context, ref, v))),
          if (v.parentId == null || !_isStage(ref, v))
            PeekAction(
                icon: AppIcons.manage_accounts,
                label: l10n.tr('assignRights'),
                onTap: () => unawaited(showRightsSheet(context, ref, v))),
        ]),
      if (src != null)
        PeekGroup(title: l10n.tr('peekGroupMail'), items: [
          PeekAction(
            icon: AppIcons.mail,
            label: l10n.tr('openEmail'),
            onTap: () => context.push(mailOpenPath(context, src, accountId: v.row.accountId)),
          ),
        ]),
      PeekGroup(items: [
        if (v.outgoing && v.active)
          PeekAction(
            icon: AppIcons.close,
            label: l10n.tr('assignCancel'),
            color: AppColors.errorText(context),
            onTap: () => unawaited(() async {
              final ok = await confirmDestructive(context,
                  title: l10n.tr('assignCancel'), message: l10n.tr('assignCancelConfirm'));
              if (ok) assignmentFire(svc.setStatus(v, AssignmentStatus.cancelled));
            }()),
          ),
        PeekAction(
          icon: AppIcons.delete,
          label: l10n.tr('assignDeleteLocal'),
          color: AppColors.errorText(context),
          onTap: () => assignmentFire(svc.delete(v)),
        ),
      ]),
    ],
  );
}

/// Этап проекта (права постановщика — у проекта, не у этапа).
bool _isStage(WidgetRef ref, AssignmentView v) {
  final id = v.parentId;
  if (id == null) return false;
  final all = ref.read(assignmentsProvider).value ?? const <AssignmentView>[];
  return all.where((x) => x.id == id).firstOrNull?.isProject ?? false;
}

class _AssignmentPeekCard extends StatelessWidget {
  final AssignmentView v;
  const _AssignmentPeekCard({required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.mutedText(context);
    final overdue = v.overdue(DateTime.now());
    final desc = (v.row.description ?? '').trim();
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          AssignmentAvatar(v, radius: 16),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              '${l10n.tr(v.outgoing ? 'assignTo' : 'assignFrom')} ${v.otherName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          AssignmentStatusPill(v.status),
        ]),
        const SizedBox(height: Space.s),
        Text(v.row.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
        if (v.due != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Row(children: [
              Icon(AppIcons.schedule, size: 16, color: overdue ? AppColors.errorText(context) : muted),
              const SizedBox(width: Space.xs),
              Text(assignmentDueText(v.due!, l10n),
                  style: theme.textTheme.bodySmall?.copyWith(color: overdue ? AppColors.errorText(context) : muted)),
            ]),
          ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text(desc, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
        ],
      ]),
    );
  }
}

/// Подзадача в карточке родительского поручения: статус, исполнитель, срок;
/// нажатие — карточка подзадачи, удержание — быстрые действия.
class AssignmentSubtaskRow extends ConsumerWidget {
  final AssignmentView v;
  const AssignmentSubtaskRow({super.key, required this.v});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.mutedText(context);
    final overdue = v.overdue(DateTime.now());
    final done = v.status == AssignmentStatus.done;
    return InkWell(
      onTap: () => context.push('/assignments/${v.id}'),
      onLongPress: () => unawaited(showAssignmentPeek(context, ref, v)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
        child: Row(children: [
          Icon(done ? AppIcons.check_circle : AppIcons.radio_button_unchecked,
              size: 20, color: done ? AppColors.successText(context) : assignmentStatusColor(v.status, context)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: v.active ? null : muted,
                    decoration: v.status == AssignmentStatus.cancelled ? TextDecoration.lineThrough : null,
                  )),
              Text(
                [
                  v.otherName,
                  if (v.due != null) assignmentDueText(v.due!, l10n),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: overdue ? AppColors.errorText(context) : muted),
              ),
            ]),
          ),
          const SizedBox(width: Space.s),
          AssignmentStatusPill(v.status),
        ]),
      ),
    );
  }
}

/// Раскрытая плашка поручения над письмом: срок и действия по роли.
class AssignmentMailCard extends ConsumerWidget {
  final AssignmentView v;
  const AssignmentMailCard({super.key, required this.v});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final svc = ref.read(assignmentServiceProvider);
    final s = v.status;
    final src = v.row.sourceEmailId;
    return Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(v.row.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (v.due != null)
          Text('${l10n.tr('assignDueTitle')}: ${assignmentDueText(v.due!, l10n)}',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          if (!v.outgoing && s == AssignmentStatus.open)
            FilledButton.icon(
                onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress)),
                icon: const Icon(AppIcons.play_arrow, size: 18),
                label: Text(l10n.tr('assignTake'))),
          if (!v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress))
            OutlinedButton.icon(
                onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.review)),
                icon: const Icon(AppIcons.check, size: 18),
                label: Text(l10n.tr('assignDoneAction'))),
          if (!v.outgoing && v.active && src != null)
            OutlinedButton.icon(
                onPressed: () => context.push(Uri(path: '/compose', queryParameters: {
                      'replyToId': src,
                      'accountId': v.row.accountId,
                    }).toString()),
                icon: const Icon(AppIcons.help, size: 18),
                label: Text(l10n.tr('assignQuestion'))),
          if (v.outgoing && s == AssignmentStatus.review) ...[
            FilledButton(
                onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.done)),
                child: Text(l10n.tr('assignAccept'))),
            OutlinedButton(
                onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress)),
                child: Text(l10n.tr('assignReturn'))),
          ],
          TextButton(onPressed: () => context.push('/assignments/${v.id}'), child: Text(l10n.tr('assignOpen'))),
        ]),
        if (!v.outgoing && v.active) ...[
          const SizedBox(height: Space.xs),
          Text(l10n.tr('assignReplyHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
        ],
      ]),
    );
  }
}

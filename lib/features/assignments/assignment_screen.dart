// lib/features/assignments/assignment_screen.dart
// Карточка поручения (макет — docs/design/MOCKUPS_MY_DAY_TASKS.md):
// заголовок, ход статусов «Новое → В работе → На проверке → Выполнено»,
// исполнитель или поручивший, срок, письмо-основание, пояснение и история —
// что и когда сделано, в том числе по ответам. Внизу — действия по роли:
// поручивший принимает работу, возвращает на доработку, напоминает;
// исполнитель берёт в работу, сдаёт («Готово»), задаёт вопрос (ответ на
// письмо поручения).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart' show mailOpenPath;
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/database/app_database.dart' show AssignmentEvent;
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../../widgets/ui/action_sheet.dart';
import 'assignment_widgets.dart';

class AssignmentScreen extends ConsumerWidget {
  final String id;
  const AssignmentScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final list = ref.watch(assignmentsProvider).value;
    final v = list?.where((x) => x.id == id).firstOrNull;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tr('assignTitle'))),
        body: list == null ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
      );
    }
    final events = ref.watch(assignmentEventsProvider(id)).value ?? const <AssignmentEvent>[];
    final svc = ref.read(assignmentServiceProvider);
    final overdue = v.overdue(DateTime.now());
    final src = v.row.sourceEmailId;
    final desc = (v.row.description ?? '').trim();

    Widget info(IconData icon, String label, Widget value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            child: Row(children: [
              Icon(icon, size: 20, color: muted),
              const SizedBox(width: Space.m),
              SizedBox(
                  width: 112, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: muted))),
              Expanded(child: value),
              if (onTap != null) Icon(AppIcons.chevron_right, color: muted),
            ]),
          ),
        );

    final s = v.status;
    final buttons = <Widget>[
      if (v.outgoing && s == AssignmentStatus.review) ...[
        Expanded(
          child: FilledButton.tonal(
              onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress)),
              child: Text(l10n.tr('assignReturn'))),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: FilledButton(
              onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.done)), child: Text(l10n.tr('assignAccept'))),
        ),
      ],
      if (v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress))
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => assignmentFire(svc.remind(v)),
              icon: const Icon(AppIcons.notifications, size: 18),
              label: Text(l10n.tr('assignRemind'))),
        ),
      if (!v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress)) ...[
        if (src != null) ...[
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => context.push(Uri(path: '/compose', queryParameters: {
                      'replyToId': src,
                      'accountId': v.row.accountId,
                    }).toString()),
                icon: const Icon(AppIcons.help, size: 18),
                label: Text(l10n.tr('assignQuestion'))),
          ),
          const SizedBox(width: Space.s),
        ],
        Expanded(
          child: s == AssignmentStatus.open
              ? FilledButton.icon(
                  onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.inProgress)),
                  icon: const Icon(AppIcons.play_arrow, size: 18),
                  label: Text(l10n.tr('assignTake')))
              : FilledButton.icon(
                  onPressed: () => assignmentFire(svc.setStatus(v, AssignmentStatus.review)),
                  icon: const Icon(AppIcons.check, size: 18),
                  label: Text(l10n.tr('assignDoneAction'))),
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('assignTitle')),
        actions: [
          Builder(
            builder: (bctx) => IconButton(
              tooltip: l10n.tr('more'),
              icon: const Icon(AppIcons.more_vert),
              onPressed: () => unawaited(showAssignmentPeek(context, ref, v, anchor: peekAnchorOf(bctx))),
            ),
          ),
        ],
      ),
      bottomNavigationBar: buttons.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                child: Row(children: buttons),
              ),
            ),
      body: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
          child: Text(v.row.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                decoration: s == AssignmentStatus.cancelled ? TextDecoration.lineThrough : null,
              )),
        ),
        if (s == AssignmentStatus.cancelled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Align(alignment: Alignment.centerLeft, child: AssignmentStatusPill(s)),
          )
        else
          // Поручивший может отметить шаг сам: ответ исполнителя не
          // распознан (2.2.1).
          _Stepper(status: s, onPick: v.outgoing ? (st) => _pickStatus(context, v, st) : null),
        const SizedBox(height: Space.m),
        info(
          v.outgoing ? AppIcons.person : AppIcons.assignment_ind,
          l10n.tr(v.outgoing ? 'assignAssignee' : 'assignOwner'),
          Row(children: [
            AssignmentAvatar(v, radius: 12),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(v.otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        info(
          AppIcons.event,
          l10n.tr('assignDueTitle'),
          Text(
            v.due == null ? l10n.tr('noDueDate') : DateFormat('EEEE, d MMMM', l10n.localeCode).format(v.due!),
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500, color: overdue ? AppColors.errorText(context) : null),
          ),
          onTap: v.active ? () => unawaited(showAssignmentPeek(context, ref, v)) : null,
        ),
        if (src != null)
          info(
            AppIcons.mail,
            l10n.tr('assignSourceMail'),
            Text(l10n.tr('openEmail'),
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.linkText(context))),
            onTap: () => context.push(mailOpenPath(context, src, accountId: v.row.accountId)),
          ),
        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Text(desc, style: theme.textTheme.bodyLarge),
          ),
        const Divider(height: Space.xl),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
          child: Text(l10n.tr('assignHistory'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        for (final e in events) _EventRow(e: e, v: v),
      ]),
    );
  }
}

/// Шаг на шкале статусов нажат поручившим: «Выполнено» — принять работу
/// (исполнитель получит письмо, как кнопкой «Принять»), остальное — отметка
/// только у себя.
Future<void> _pickStatus(BuildContext context, AssignmentView v, int status) async {
  final l10n = AppLocalizations.of(context);
  final svc = ProviderScope.containerOf(context).read(assignmentServiceProvider);
  final done = status == AssignmentStatus.done;
  final ok = await showActionSheet<bool>(context, title: assignmentStatusLabel(status, l10n), items: [
    ActionSheetItem(
      icon: done ? AppIcons.check : AppIcons.edit,
      label: done ? l10n.tr('assignAccept') : l10n.tr('assignMarkAs').replaceAll('{status}', assignmentStatusLabel(status, l10n)),
      subtitle: done ? null : l10n.tr('assignMarkLocalHint'),
      value: true,
    ),
  ]);
  if (ok != true) return;
  assignmentFire(done ? svc.setStatus(v, status) : svc.markLocally(v, status));
}

class _Stepper extends StatelessWidget {
  final int status;

  /// Нажатие на другой шаг (поручивший, 2.2.1); null — шкала только для вида.
  final void Function(int status)? onPick;
  const _Stepper({required this.status, this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final p = theme.colorScheme.primary;
    final line = theme.colorScheme.outlineVariant;
    const steps = [AssignmentStatus.open, AssignmentStatus.inProgress, AssignmentStatus.review, AssignmentStatus.done];
    final cur = steps.indexOf(status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      child: Row(children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: _tappable(
              context,
              steps[i],
              Column(children: [
              Row(children: [
                Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= cur ? p : line))),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: i < cur || (i == cur && status == AssignmentStatus.done) ? p : (i == cur ? p.withValues(alpha: 0.15) : null),
                    border: Border.all(color: i <= cur ? p : line, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: i < cur || (i == cur && status == AssignmentStatus.done)
                      ? Icon(AppIcons.check, size: 14, color: theme.colorScheme.onPrimary)
                      : null,
                ),
                Expanded(
                    child: Container(height: 2, color: i == steps.length - 1 ? Colors.transparent : (i < cur ? p : line))),
              ]),
              const SizedBox(height: 6),
              Text(assignmentStatusLabel(steps[i], l10n),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: i == cur ? FontWeight.w700 : null,
                    color: i == cur ? p : AppColors.mutedText(context),
                  )),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _tappable(BuildContext context, int step, Widget child) {
    final pick = onPick;
    if (pick == null || step == status) return child;
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('assign_step_$step'),
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: () => pick(step),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final AssignmentEvent e;
  final AssignmentView v;
  const _EventRow({required this.e, required this.v});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.mutedText(context);
    Map<String, dynamic> p = const {};
    try {
      final j = jsonDecode(e.payloadJson);
      if (j is Map<String, dynamic>) p = j;
    } catch (_) {}
    final mine = e.direction == 0;
    final who = mine
        ? l10n.tr('assignMe')
        : (e.authorEmail == v.assignee?.email
            ? (v.assignee?.displayName ?? e.authorEmail)
            : (v.owner?.displayName ?? e.authorEmail));
    final status = p['status'] is int ? p['status'] as int : null;
    final text = (p['text'] as String? ?? '').trim();
    final (IconData icon, String line) = switch (e.type) {
      'created' => (
          AppIcons.send,
          l10n.tr(v.outgoing ? 'assignEvCreated' : 'assignEvReceived').replaceAll('{name}', v.otherName)
        ),
      'reminder' => (AppIcons.notifications, '${l10n.tr('assignEvReminder')}${text.isEmpty ? '' : ' — $text'}'),
      'due' => (AppIcons.event, text),
      'status' => (
          AppIcons.history,
          '$who: ${assignmentStatusLabel(status ?? v.status, l10n)}${text.isEmpty ? '' : ' — «$text»'}'
        ),
      _ => (
          AppIcons.reply,
          [
            '$who${text.isEmpty ? '' : ': «${text.length > 160 ? '${text.substring(0, 160)}…' : text}»'}',
            if (status != null) '· ${assignmentStatusLabel(status, l10n)}',
          ].join(' ')
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 6, Space.l, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: status != null ? assignmentStatusColor(status, context) : muted),
        const SizedBox(width: Space.m),
        SizedBox(
          width: 96,
          child: Text(DateFormat('d MMM, HH:mm', l10n.localeCode).format(e.createdAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
        Expanded(child: Text(line, style: theme.textTheme.bodySmall)),
      ]),
    );
  }
}

// lib/features/assignments/assignment_screen.dart
// Карточка поручения (макет — docs/design/MOCKUPS_MY_DAY_TASKS.md):
// заголовок, ход статусов «Новое → В работе → На проверке → Выполнено»,
// исполнитель или поручивший, срок, письмо-основание, пояснение и история —
// что и когда сделано, в том числе по ответам. Внизу — действия по роли:
// поручивший принимает работу, возвращает на доработку, напоминает;
// исполнитель берёт в работу, сдаёт («Готово»), задаёт вопрос (ответ на
// письмо поручения). Связь «родитель — подзадача» (12.11.2026): у подзадачи —
// строка «Часть поручения», у родителя — список подзадач с их статусами и
// «Добавить подзадачу».

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart' show mailOpenPath;
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/platform/file_opener.dart';
import '../../data/database/app_database.dart' show AssignmentEvent, AssignmentParticipant;
import '../../data/models/email_model.dart';
import '../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../mail/providers/mail_providers.dart' show accountsProvider;
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/assignments/assignment_store.dart' show AssignmentTree, AssignmentFile;
import '../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../../widgets/common/readable_width.dart';
import '../../widgets/ui/action_sheet.dart';
import 'assign_sheet.dart';
import 'project_editor.dart' show pickAssignmentFiles;
import 'project_screen.dart';
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
    // Проект с этапами — свой экран (этапы, план, файлы, история).
    if (v.isProject) return ProjectScreen(project: v, all: list!);
    final events = ref.watch(assignmentEventsProvider(id)).value ?? const <AssignmentEvent>[];
    final svc = ref.read(assignmentServiceProvider);
    final afterStage = v.row.afterId == null ? null : list!.where((x) => x.id == v.row.afterId).firstOrNull;
    final checklist = v.checklist;
    final files = v.files;
    // Кто что может: исполнитель — «Взять», «Готово», «Передать»;
    // соисполнитель — «Сообщить о ходе работ»; принимает работу
    // контролирующий, а без него — постановщик.
    final canWork = v.iExecute || v.iCoExecute || (!v.outgoing && v.myRoles.isEmpty);
    final canCheck = canWork || v.outgoing;
    final canAddFiles = v.active && (canWork || v.outgoing || v.iControl);
    final overdue = v.overdue(DateTime.now());
    final src = v.row.sourceEmailId;
    final desc = (v.row.description ?? '').trim();
    final parent = list!.parentOf(v);
    final subtasks = list.childrenOf(v.id);
    final subDone = subtasks.where((x) => x.status == AssignmentStatus.done).length;

    Widget info(IconData icon, String label, Widget value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            child: Row(children: [
              Icon(icon, size: 20, color: muted),
              const SizedBox(width: Space.m),
              SizedBox(
                  width: 136,
                  child: Text(label,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted))),
              Expanded(child: value),
              if (onTap != null) Icon(AppIcons.chevron_right, color: muted),
            ]),
          ),
        );

    final s = v.status;
    final main = v.iExecute || (!v.outgoing && v.myRoles.isEmpty);
    final buttons = <Widget>[
      if (v.iAccept && s == AssignmentStatus.review) ...[
        Expanded(
          child: FilledButton.tonal(
              key: const ValueKey('assign_return'),
              onPressed: () => unawaited(_reply(context, v, AssignmentStatus.inProgress)),
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
      if (main && !v.outgoing && (s == AssignmentStatus.open || s == AssignmentStatus.inProgress)) ...[
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
                  key: const ValueKey('assign_done'),
                  onPressed: () => unawaited(_reply(context, v, AssignmentStatus.review)),
                  icon: const Icon(AppIcons.check, size: 18),
                  label: Text(l10n.tr('assignDoneAction'))),
        ),
      ],
      // Соисполнитель: «Готово» отправляет основной исполнитель (решение
      // владельца 12.11.2026) — здесь ход работ.
      if (v.iCoExecute && !v.outgoing && AssignmentStatus.isActive(s))
        Expanded(
          child: FilledButton.tonalIcon(
              onPressed: () => unawaited(_report(context, v)),
              icon: const Icon(AppIcons.analytics, size: 18),
              label: Text(l10n.tr('projReport'))),
        ),
    ];

    String person(AssignmentParticipant? p, String fallback) {
      final n = (p?.displayName ?? '').trim();
      return n.isNotEmpty ? n : (p?.email ?? fallback);
    }

    final fmtDate = DateFormat('EEE, d MMM', l10n.localeCode);
    // Ящик поручения (просьба владельца 12.11.2026): с какого отправлено
    // или на какой пришло.
    final account = ref.watch(accountsProvider).where((a) => a.id == v.row.accountId).firstOrNull;
    final roles = <Widget>[
      info(AppIcons.assignment_ind, l10n.tr('projRoleOwner'),
          Text(v.outgoing ? l10n.tr('assignMe') : person(v.owner, v.row.ownerEmail),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
      if (v.assignee != null)
        info(
          AppIcons.person,
          l10n.tr('projExecutor'),
          Row(children: [
            AssignmentAvatar(v, radius: 12),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(v.iExecute ? l10n.tr('assignMe') : person(v.assignee, ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      if (v.coExecutors.isNotEmpty)
        info(AppIcons.group, l10n.tr('projCo'),
            Text(v.coExecutors.map((p) => person(p, '')).join(', '), style: theme.textTheme.bodyMedium)),
      if (v.controller != null)
        info(AppIcons.verified_user, l10n.tr('projController'),
            Text(v.iControl ? l10n.tr('assignMe') : person(v.controller, ''), style: theme.textTheme.bodyMedium)),
      if (v.observers.isNotEmpty)
        info(AppIcons.visibility, l10n.tr('projObservers'),
            Text(v.observers.map((p) => person(p, '')).join(', '), style: theme.textTheme.bodyMedium)),
      if (account != null) assignmentMailboxRow(context, account, outgoing: v.outgoing, info: info),
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
              child: ReadableWidth(
                maxWidth: assignmentColumnWidth,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                  child: Row(children: buttons),
                ),
              ),
            ),
      // Планшет и компьютер: колонка читаемой ширины, а не во весь экран.
      body: ReadableWidth(
          maxWidth: assignmentColumnWidth,
          fill: true,
          child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
          child: Text.rich(
              TextSpan(children: [
                if (v.important)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: Space.xs),
                      child: Icon(AppIcons.priority_high, color: AppColors.errorText(context)),
                    ),
                  ),
                TextSpan(text: v.row.title),
              ]),
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
        ...roles,
        info(
          AppIcons.event,
          l10n.tr('assignDueTitle'),
          Text(
            v.start != null
                ? '${fmtDate.format(v.start!)} — ${v.due == null ? l10n.tr('noDueDate') : fmtDate.format(v.due!)}'
                : (v.due == null ? l10n.tr('noDueDate') : DateFormat('EEEE, d MMMM', l10n.localeCode).format(v.due!)),
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500, color: overdue ? AppColors.errorText(context) : null),
          ),
          onTap: v.active ? () => unawaited(showAssignmentPeek(context, ref, v)) : null,
        ),
        if (v.row.afterId != null)
          info(
            AppIcons.schedule,
            l10n.tr('projOrder'),
            Text(
              [
                l10n.tr('projAfter').replaceAll('{title}', afterStage?.row.title ?? '…'),
                if (v.waiting) l10n.tr('projWaiting'),
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: v.waiting ? AppColors.mutedText(context) : null),
            ),
            onTap: afterStage == null ? null : () => context.push('/assignments/${afterStage.id}'),
          ),
        if (parent != null)
          info(
            AppIcons.account_tree,
            l10n.tr('assignParent'),
            Text(parent.row.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            onTap: () => context.push('/assignments/${parent.id}'),
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
        // Результат (как в Битрикс24): последний ответ «Готово» — текст и файлы.
        if (s == AssignmentStatus.review || s == AssignmentStatus.done) AssignmentResult(v: v, events: events),
        if (checklist.isNotEmpty) ChecklistSection(v: v, editable: canCheck && v.active),
        if (files.isNotEmpty) FilesSection(v: v, files: files, canAdd: canAddFiles),
        // Пустые чек-лист и файлы — кнопками, без пустых разделов.
        if (v.active && ((checklist.isEmpty && canCheck) || (files.isEmpty && canAddFiles)))
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.l, 0),
            child: Wrap(spacing: Space.xs, children: [
              if (checklist.isEmpty && canCheck)
                TextButton.icon(
                  key: const ValueKey('assign_add_check'),
                  onPressed: () async {
                    final t = await _askNote(context, l10n.tr('projChecklist'), l10n.tr('projAddCheck'),
                        ok: l10n.tr('add'));
                    if ((t ?? '').trim().isNotEmpty) assignmentFire(svc.addCheck(v, t!));
                  },
                  icon: const Icon(AppIcons.checklist, size: 18),
                  label: Text(l10n.tr('projChecklist')),
                ),
              if (files.isEmpty && canAddFiles)
                TextButton.icon(
                  key: const ValueKey('assign_add_files'),
                  onPressed: () => unawaited(addAssignmentFiles(ref, v)),
                  icon: const Icon(AppIcons.attach_file, size: 18),
                  label: Text(l10n.tr('projAddFiles')),
                ),
            ]),
          ),
        if (main && !v.outgoing && v.active)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
              OutlinedButton.icon(
                key: const ValueKey('assign_delegate'),
                onPressed: () => unawaited(_delegate(context, ref, v)),
                icon: const Icon(AppIcons.forward, size: 18),
                label: Text(l10n.tr('projDelegate')),
              ),
              if (checklist.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => unawaited(_report(context, v)),
                  icon: const Icon(AppIcons.analytics, size: 18),
                  label: Text(l10n.tr('projReport')),
                ),
            ]),
          ),
        if (subtasks.isNotEmpty || v.active) ...[
          const Divider(height: Space.xl),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.s, Space.xs),
            child: Row(children: [
              Expanded(
                child: Text(
                  subtasks.isEmpty
                      ? l10n.tr('subtasks')
                      : '${l10n.tr('subtasks')} · $subDone/${subtasks.length}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (v.active)
                TextButton.icon(
                  key: const ValueKey('assign_add_subtask'),
                  onPressed: () => unawaited(showAssignSheet(context, parent: v)),
                  icon: const Icon(AppIcons.add, size: 18),
                  label: Text(l10n.tr('add')),
                ),
            ]),
          ),
          for (final c in subtasks) AssignmentSubtaskRow(v: c),
        ],
        const Divider(height: Space.xl),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
          child: Text(l10n.tr('assignHistory'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        for (final e in events) _EventRow(e: e, v: v),
      ])),
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
      'delegated' => (
          AppIcons.person_add,
          l10n.tr('projEvDelegated').replaceAll('{name}', '${p['name'] ?? p['to'] ?? ''}')
        ),
      'progress' => (AppIcons.history, '$who: $text'),
      'files' => (AppIcons.attach_file, '$who: $text'),
      'go' => (AppIcons.play_arrow, l10n.tr('projEvGo')),
      'sent' => (AppIcons.send, l10n.tr('projEvSent')),
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


/// «Передать для исполнения»: выбранный человек — соисполнитель, я остаюсь
/// исполнителем.
Future<void> _delegate(BuildContext context, WidgetRef ref, AssignmentView v) async {
  final account = ref.read(accountsProvider).where((a) => a.id == v.row.accountId).firstOrNull;
  final picked = await showPeoplePicker(context,
      account: account, exclude: {for (final p in v.people) p.email.toLowerCase()});
  if (picked.isEmpty || !context.mounted) return;
  final c = picked.first;
  final l10n = AppLocalizations.of(context);
  final note = await _askNote(context, l10n.tr('projDelegate'), l10n.tr('projDelegateHint').replaceAll('{name}', c.displayName.trim().isEmpty ? c.email : c.displayName));
  if (note == null) return;
  assignmentFire(ref
      .read(assignmentServiceProvider)
      .delegate(v, EmailAddress(email: c.email, displayName: c.displayName.trim().isEmpty ? null : c.displayName), note: note));
}

/// «Сообщить о ходе работ»: чек-лист и комментарий постановщику.
Future<void> _report(BuildContext context, AssignmentView v) async {
  final l10n = AppLocalizations.of(context);
  final svc = ProviderScope.containerOf(context).read(assignmentServiceProvider);
  final r = await showAssignmentReply(context, title: l10n.tr('projReport'), hint: l10n.tr('projReportHint'));
  if (r == null) return;
  assignmentFire(svc.reportProgress(v, note: r.text, files: r.files));
}

/// «Готово» с результатом и файлами; «Вернуть на доработку» — с причиной.
Future<void> _reply(BuildContext context, AssignmentView v, int status) async {
  final l10n = AppLocalizations.of(context);
  final svc = ProviderScope.containerOf(context).read(assignmentServiceProvider);
  final returning = status == AssignmentStatus.inProgress;
  final r = await showAssignmentReply(context,
      title: l10n.tr(returning ? 'assignReturn' : 'assignDoneAction'),
      hint: l10n.tr(returning ? 'assignReturnHint' : 'assignResultHint'),
      requireText: returning);
  if (r == null) return;
  assignmentFire(svc.setStatus(v, status, note: r.text, files: r.files));
}

/// Ответ по поручению: текст и файлы (как комментарий с вложениями в Jira
/// и Битрикс24). null — передумали.
Future<({String text, List<AssignmentFile> files})?> showAssignmentReply(
  BuildContext context, {
  required String title,
  required String hint,
  bool requireText = false,
}) =>
    showDialog<({String text, List<AssignmentFile> files})>(
      context: context,
      builder: (_) => _ReplyDialog(title: title, hint: hint, requireText: requireText),
    );

class _ReplyDialog extends StatefulWidget {
  final String title;
  final String hint;
  final bool requireText;
  const _ReplyDialog({required this.title, required this.hint, required this.requireText});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final _ctrl = TextEditingController();
  final List<AssignmentFile> _files = [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ok = !widget.requireText || _ctrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const ValueKey('assign_reply_text'),
            controller: _ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: widget.hint, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            for (final f in _files)
              InputChip(
                avatar: const Icon(AppIcons.attach_file, size: 16),
                label: Text(f.name, overflow: TextOverflow.ellipsis),
                onDeleted: () => setState(() => _files.remove(f)),
              ),
            ActionChip(
              key: const ValueKey('assign_reply_files'),
              avatar: const Icon(AppIcons.attach_file, size: 18),
              label: Text(l10n.tr('projAddFiles')),
              onPressed: () async {
                List<AssignmentFile> picked = const [];
                try {
                  picked = await pickAssignmentFiles();
                } catch (_) {}
                if (picked.isNotEmpty && mounted) setState(() => _files.addAll(picked));
              },
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          key: const ValueKey('assign_reply_send'),
          onPressed: ok ? () => Navigator.pop(context, (text: _ctrl.text.trim(), files: List.of(_files))) : null,
          child: Text(l10n.tr('send')),
        ),
      ],
    );
  }
}

/// Результат: последний ответ «Готово» (текст без слова «Готово», файлы).
class AssignmentResult extends StatelessWidget {
  final AssignmentView v;
  final List<AssignmentEvent> events;
  const AssignmentResult({super.key, required this.v, required this.events});

  static Map<String, dynamic> _payload(AssignmentEvent e) {
    try {
      final j = jsonDecode(e.payloadJson);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    return const {};
  }

  /// Последнее событие «на проверке» (своё или из письма исполнителя).
  static AssignmentEvent? resultOf(List<AssignmentEvent> events) {
    AssignmentEvent? best;
    for (final e in events) {
      if (e.type != 'status' && e.type != 'message') continue;
      if (_payload(e)['status'] != AssignmentStatus.review) continue;
      if (best == null || e.createdAt.isAfter(best.createdAt)) best = e;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final e = resultOf(events);
    if (e == null) return const SizedBox.shrink();
    final p = _payload(e);
    var text = (p['text'] as String? ?? '').trim();
    final stock = l10n.tr('assignReplyDone');
    if (text == stock) text = '';
    if (text.startsWith('$stock\n')) text = text.substring(stock.length + 1).trim();
    final names = [for (final n in (p['files'] as List? ?? const [])) '$n'];
    final files = [for (final n in names) v.files.where((f) => f.name == n).firstOrNull ?? AssignmentFile(name: n)];
    String who = e.authorEmail;
    if (e.direction == 0) {
      who = l10n.tr('assignMe');
    } else {
      for (final p in [...v.people, if (v.assignee != null) v.assignee!, if (v.owner != null) v.owner!]) {
        if (p.email.toLowerCase() == e.authorEmail.toLowerCase() && (p.displayName ?? '').trim().isNotEmpty) {
          who = p.displayName!.trim();
          break;
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: Space.xl),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
        child: Row(children: [
          Icon(AppIcons.task_alt, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: Space.s),
          Text(l10n.tr('assignResult'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text('$who · ${DateFormat('d MMM, HH:mm', l10n.localeCode).format(e.createdAt.toLocal())}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ]),
      ),
      if (text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      if (files.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            for (final f in files)
              ActionChip(
                avatar: const Icon(AppIcons.attach_file, size: 16),
                label: Text(f.name, overflow: TextOverflow.ellipsis),
                onPressed: () => unawaited(openAssignmentFile(context, v, f)),
              ),
          ]),
        ),
      if (text.isEmpty && files.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
          child: Text(l10n.tr('assignResultEmpty'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
    ]);
  }
}

/// Комментарий к действию; null — передумали.
Future<String?> _askNote(BuildContext context, String title, String hint, {String? ok}) async {
  final l10n = AppLocalizations.of(context);
  final ctrl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(ok ?? l10n.tr('send'))),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}

/// Чек-лист этапа: отметки — у себя (постановщик узнаёт из «Сообщить о
/// ходе работ», «Принято», «Готово»), новый пункт — внизу.
class ChecklistSection extends ConsumerStatefulWidget {
  final AssignmentView v;
  final bool editable;
  const ChecklistSection({super.key, required this.v, required this.editable});

  @override
  ConsumerState<ChecklistSection> createState() => _ChecklistSectionState();
}

class _ChecklistSectionState extends ConsumerState<ChecklistSection> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = widget.v.checklist;
    final done = items.where((i) => i.done).length;
    final svc = ref.read(assignmentServiceProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: Space.xl),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
        child: Text(items.isEmpty ? l10n.tr('projChecklist') : '${l10n.tr('projChecklist')} · $done/${items.length}',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: LinearProgressIndicator(value: done / items.length, minHeight: 4, borderRadius: BorderRadius.circular(2)),
        ),
      for (var i = 0; i < items.length; i++)
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: items[i].done,
          onChanged: widget.editable ? (_) => assignmentFire(svc.toggleCheck(widget.v, i)) : null,
          title: Text(items[i].text,
              style: items[i].done
                  ? theme.textTheme.bodyMedium?.copyWith(
                      decoration: TextDecoration.lineThrough, color: AppColors.mutedText(context))
                  : theme.textTheme.bodyMedium),
        ),
      if (widget.editable)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 0),
          child: TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
                hintText: l10n.tr('projAddCheck'), prefixIcon: const Icon(AppIcons.add), isDense: true),
            onSubmitted: (t) {
              if (t.trim().isEmpty) return;
              assignmentFire(svc.addCheck(widget.v, t));
              _ctrl.clear();
            },
          ),
        ),
    ]);
  }
}

/// Файлы поручения: свои открываются, из письма — открывают письмо.
class FilesSection extends ConsumerWidget {
  final AssignmentView v;
  final List<AssignmentFile> files;
  final bool canAdd;
  final String? title;
  final bool divider;
  const FilesSection(
      {super.key, required this.v, required this.files, required this.canAdd, this.title, this.divider = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (files.isEmpty && !canAdd) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (divider) const Divider(height: Space.xl),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.s, Space.xs),
        child: Row(children: [
          Expanded(
            child: Text(files.isEmpty ? (title ?? l10n.tr('projTabFiles')) : '${title ?? l10n.tr('projTabFiles')} · ${files.length}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (canAdd)
            TextButton.icon(
              onPressed: () => unawaited(addAssignmentFiles(ref, v)),
              icon: const Icon(AppIcons.attach_file, size: 18),
              label: Text(l10n.tr('projAddFiles')),
            ),
        ]),
      ),
      for (final f in files)
        ListTile(
          dense: true,
          leading: const Icon(AppIcons.attach_file),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: f.size > 0 ? Text(_fileSize(f.size)) : null,
          onTap: () => unawaited(openAssignmentFile(context, v, f)),
        ),
    ]);
  }
}

/// Открыть файл поручения: свой — приложением, из письма — само письмо.
Future<void> openAssignmentFile(BuildContext context, AssignmentView v, AssignmentFile f) async {
  final path = f.path;
  if (path != null && File(path).existsSync()) {
    await FileOpener.open(path, name: f.name);
  } else if (f.mailId != null && context.mounted) {
    unawaited(context.push(mailOpenPath(context, f.mailId!, accountId: v.row.accountId)));
  }
}

/// Выбрать файлы и добавить к поручению (письмо другой стороне).
Future<void> addAssignmentFiles(WidgetRef ref, AssignmentView v) async {
  List<AssignmentFile> picked = const [];
  try {
    picked = await pickAssignmentFiles();
  } catch (_) {}
  if (picked.isEmpty) return;
  assignmentFire(ref.read(assignmentServiceProvider).addFiles(v, picked));
}

String _fileSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

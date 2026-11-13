// lib/features/assignments/project_screen.dart
// Проект с этапами (просьба владельца 12.11.2026): прогресс, этапы с
// исполнителями и сроками, план — диаграмма Ганта, файлы проекта, история.
// Постановщик: добавить этап, сдвинуть следующие этапы после опоздания,
// сохранить проект шаблоном. Участник без своих этапов видит план из
// письма проекта.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/database/app_database.dart' show AssignmentEvent;
import '../../data/models/email_model.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/assignments/assignment_store.dart'
    show PlanStage, mergePlan, projectProgress, shiftSuccessors, AssignmentTree;
import 'assignment_edit.dart' show showRightsSheet;
import 'assignment_screen.dart' show FilesSection;
import 'assignment_widgets.dart';
import 'gantt_chart.dart';
import 'project_editor.dart';

class ProjectScreen extends ConsumerWidget {
  final AssignmentView project;
  final List<AssignmentView> all;
  const ProjectScreen({super.key, required this.project, required this.all});

  List<AssignmentView> _stages() {
    final list = all.childrenOf(project.id)
      ..sort((a, b) {
        final o = a.row.stageOrder.compareTo(b.row.stageOrder);
        return o != 0 ? o : a.row.createdAt.compareTo(b.row.createdAt);
      });
    return list;
  }

  /// План. У постановщика — его этапы со статусами. У участника — план из
  /// письма проекта, где свои этапы — с текущим статусом.
  List<PlanStage> _plan(List<AssignmentView> stages) => mergePlan(
        own: planOf(stages),
        fromMail: project.outgoing ? const [] : PlanStage.decode(project.row.planJson),
      );

  /// Номер этапа [id] в плане (с 1).
  static int? _no(List<PlanStage> plan, String? id) {
    if (id == null) return null;
    final i = plan.indexWhere((p) => p.id == id);
    return i < 0 ? null : i + 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final stages = _stages();
    final plan = _plan(stages);
    final now = DateTime.now();
    final progress = projectProgress(plan.where((p) => p.status != null).toList());
    final doneN = stages.where((s) => s.status == AssignmentStatus.done).length;
    final late = project.outgoing ? shiftSuccessors(plan, now) : const <String, ({DateTime start, DateTime due})>{};
    final fmt = DateFormat('d MMM', l10n.localeCode);
    final svc = ref.read(assignmentServiceProvider);
    final dates = [
      if (project.start != null) fmt.format(project.start!),
      if (project.due != null) fmt.format(project.due!),
    ].join(' — ');

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(project.row.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Space.xs),
        Text(
          [
            if (!project.iOwn)
              '${l10n.tr('projRoleOwner')}: ${(project.owner?.displayName ?? '').trim().isNotEmpty ? project.owner!.displayName!.trim() : project.row.ownerEmail}',
            if (project.iDeputy) l10n.tr('projYouDeputy'),
            if (dates.isNotEmpty) dates,
            if (stages.isNotEmpty)
              l10n.tr('projStagesCount').replaceAll('{done}', '$doneN').replaceAll('{total}', '${stages.length}'),
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        if (stages.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(
              child: LinearProgressIndicator(
                  value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: Space.s),
            Text(l10n.tr('projProgress').replaceAll('{p}', '${(progress * 100).round()}'),
                style: theme.textTheme.labelLarge),
          ]),
        ],
        if (late.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Material(
              color: AppColors.errorText(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.chip),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
                child: Row(children: [
                  Icon(AppIcons.schedule, size: 18, color: AppColors.errorText(context)),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(l10n.tr('projLate'), style: theme.textTheme.bodySmall)),
                  TextButton(
                    key: const ValueKey('proj_shift'),
                    onPressed: () => assignmentFire(svc.shiftLate(project.id)),
                    child: Text(l10n.tr('projShift')),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );

    final stagesTab = ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
      if ((project.row.description ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
          child: Text(project.row.description!.trim(), style: theme.textTheme.bodyLarge),
        ),
      // По плану: свои этапы — карточками, этапы других участников — строкой.
      for (var i = 0; i < plan.length; i++)
        if (stages.where((s) => s.id == plan[i].id).firstOrNull case final v?)
          _StageRow(index: i, v: v, afterNo: _no(plan, v.row.afterId))
        else
          // Этап другого участника — из плана в письме проекта: кто, когда,
          // после какого этапа и статус (13.11.2026).
          ListTile(
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(plan[i].title),
            trailing: plan[i].status == null ? null : AssignmentStatusPill(plan[i].status!),
            subtitle: Text([
              if ((plan[i].assigneeName ?? '').trim().isNotEmpty)
                plan[i].assigneeName!.trim()
              else if (plan[i].assignee != null)
                plan[i].assignee!,
              [if (plan[i].start != null) fmt.format(plan[i].start!), if (plan[i].due != null) fmt.format(plan[i].due!)]
                  .join(' — '),
              if (_no(plan, plan[i].after) case final n?) l10n.tr('projAfter').replaceAll('{title}', '$n'),
            ].where((x) => x.isNotEmpty).join(' · ')),
          ),
      if (!project.outgoing && !project.planShared)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Text(l10n.tr('projOwnOnlyHint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
      if (project.outgoing && project.active)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: OutlinedButton.icon(
            key: const ValueKey('proj_card_add_stage'),
            onPressed: () => unawaited(_addStage(context, ref, stages)),
            icon: const Icon(AppIcons.add, size: 18),
            label: Text(l10n.tr('projAddStage')),
          ),
        ),
    ]);

    final planTab = ListView(padding: const EdgeInsets.only(top: Space.m, bottom: Space.xl), children: [
      if (plan.isEmpty)
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Text(l10n.tr('projNeedStage'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        )
      else
        GanttChart(
          stages: plan,
          today: now,
          onTap: (id) {
            if (stages.any((s) => s.id == id)) unawaited(context.push('/assignments/$id'));
          },
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
        child: Text(l10n.tr('projPlanHint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ),
    ]);

    final filesTab = ListView(children: [
      FilesSection(v: project, files: project.files, canAdd: project.outgoing && project.active, title: l10n.tr('projFiles')),
      for (final s in stages)
        if (s.files.isNotEmpty) FilesSection(v: s, files: s.files, canAdd: false, title: s.row.title),
    ]);

    final historyTab = _History(project: project, stages: stages);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tr('projTitle')),
          actions: [
            if (project.outgoing)
              PopupMenuButton<String>(
                key: const ValueKey('proj_menu'),
                tooltip: l10n.tr('more'),
                onSelected: (v) {
                  if (v == 'edit') unawaited(showProjectEdit(context, project, stages));
                  if (v == 'rights') unawaited(showRightsSheet(context, ref, project));
                  if (v == 'template') unawaited(_saveTemplate(context, ref));
                  if (v == 'cancel') assignmentFire(_cancelAll(ref, stages));
                },
                itemBuilder: (_) => [
                  if (project.active) PopupMenuItem(value: 'edit', child: Text(l10n.tr('projEdit'))),
                  if (project.active) PopupMenuItem(value: 'rights', child: Text(l10n.tr('assignRights'))),
                  PopupMenuItem(value: 'template', child: Text(l10n.tr('projSaveTemplate'))),
                  if (project.active) PopupMenuItem(value: 'cancel', child: Text(l10n.tr('projCancel'))),
                ],
              ),
          ],
        ),
        body: Column(children: [
          header,
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: l10n.tr('projStages')),
            Tab(text: l10n.tr('projPlan')),
            Tab(text: l10n.tr('projTabFiles')),
            Tab(text: l10n.tr('assignHistory')),
          ]),
          Expanded(child: TabBarView(children: [stagesTab, planTab, filesTab, historyTab])),
        ]),
      ),
    );
  }

  Future<void> _addStage(BuildContext context, WidgetRef ref, List<AssignmentView> stages) async {
    EmailAddress addr(String email, String? name) => EmailAddress(email: email, displayName: name);
    final draft = ProjectDraft(
      title: project.row.title,
      start: project.start,
      stages: [
        for (final s in stages)
          StageDraft(
            title: s.row.title,
            executor: addr(s.assignee?.email ?? '', s.assignee?.displayName),
            start: s.start,
            due: s.due,
          ),
      ],
    );
    final st = await showStageEditor(context, ref, project: draft);
    if (st == null) return;
    final afterId = st.after == null || st.after! >= stages.length ? null : stages[st.after!].id;
    assignmentFire(ref.read(assignmentServiceProvider).addStage(project, st, afterId: afterId).then((_) {}));
  }

  Future<void> _saveTemplate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: project.row.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('projSaveTemplate')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: l10n.tr('projTemplateName'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    assignmentFire(ref.read(assignmentServiceProvider).saveProjectAsTemplate(project, name));
  }

  /// Снять проект: снять все действующие этапы (письма их исполнителям) и
  /// сам проект.
  Future<void> _cancelAll(WidgetRef ref, List<AssignmentView> stages) async {
    final svc = ref.read(assignmentServiceProvider);
    for (final s in stages) {
      if (s.active) await svc.setStatus(s, AssignmentStatus.cancelled);
    }
    await svc.markLocally(project, AssignmentStatus.cancelled);
  }
}

class _StageRow extends StatelessWidget {
  final int index;
  final AssignmentView v;

  /// Номер этапа, после которого начинать.
  final int? afterNo;
  const _StageRow({required this.index, required this.v, this.afterNo});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('d MMM', l10n.localeCode);
    final overdue = v.overdue(DateTime.now());
    final who = [
      (v.assignee?.displayName ?? '').trim().isNotEmpty ? v.assignee!.displayName! : (v.assignee?.email ?? ''),
      if (v.coExecutors.isNotEmpty) '+${v.coExecutors.length}',
    ].join(' ');
    final dates = [if (v.start != null) fmt.format(v.start!), if (v.due != null) fmt.format(v.due!)].join(' — ');
    final checklist = v.checklist;
    return InkWell(
      onTap: () => context.push('/assignments/${v.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 14, child: Text('${index + 1}', style: theme.textTheme.labelMedium)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(v.row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: Space.s),
                AssignmentStatusPill(v.status),
              ]),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: [
                    if (who.isNotEmpty) who,
                    if (dates.isNotEmpty) dates,
                    if (afterNo != null) l10n.tr('projAfter').replaceAll('{title}', '$afterNo'),
                    if (v.waiting) l10n.tr('projWaiting'),
                  ].join(' · ')),
                  // Чек-лист и файлы — значками (не символами шрифта).
                  if (checklist.isNotEmpty) ...[
                    const TextSpan(text: '  '),
                    WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(AppIcons.checklist, size: 14, color: muted)),
                    TextSpan(text: ' ${checklist.where((c) => c.done).length}/${checklist.length}'),
                  ],
                  if (v.files.isNotEmpty) ...[
                    const TextSpan(text: '  '),
                    WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(AppIcons.attach_file, size: 14, color: muted)),
                    TextSpan(text: ' ${v.files.length}'),
                  ],
                ]),
                style: theme.textTheme.bodySmall?.copyWith(color: overdue ? AppColors.errorText(context) : muted),
              ),
              const SizedBox(height: Space.xs),
              LinearProgressIndicator(
                  value: v.progress, minHeight: 3, borderRadius: BorderRadius.circular(2)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// История проекта и его этапов — по времени.
class _History extends ConsumerWidget {
  final AssignmentView project;
  final List<AssignmentView> stages;
  const _History({required this.project, required this.stages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final items = <(AssignmentEvent, AssignmentView)>[
      for (final e in ref.watch(assignmentEventsProvider(project.id)).value ?? const <AssignmentEvent>[]) (e, project),
      for (final s in stages)
        for (final e in ref.watch(assignmentEventsProvider(s.id)).value ?? const <AssignmentEvent>[]) (e, s),
    ]..sort((a, b) => b.$1.createdAt.compareTo(a.$1.createdAt));
    return ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
      for (final (e, v) in items)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 6, Space.l, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 96,
              child: Text(DateFormat('d MMM, HH:mm', l10n.localeCode).format(e.createdAt.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
            Expanded(
              child: Text(
                '${v.row.title} — ${_eventText(e, v, l10n)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ]),
        ),
    ]);
  }

  String _eventText(AssignmentEvent e, AssignmentView v, AppLocalizations l10n) {
    Map<String, dynamic> p = const {};
    try {
      final j = jsonDecode(e.payloadJson);
      if (j is Map<String, dynamic>) p = j;
    } catch (_) {}
    final text = (p['text'] as String? ?? '').trim();
    final status = p['status'] is int ? p['status'] as int : null;
    final who = e.direction == 0 ? l10n.tr('assignMe') : e.authorEmail;
    return switch (e.type) {
      'created' => v.isProject
          ? l10n.tr('projEvCreated')
          : l10n.tr(v.outgoing ? 'assignEvCreated' : 'assignEvReceived').replaceAll('{name}', v.otherName),
      'sent' => l10n.tr('projEvSent'),
      'delegated' => l10n.tr('projEvDelegated').replaceAll('{name}', '${p['name'] ?? p['to'] ?? ''}'),
      'go' => l10n.tr('projEvGo'),
      'progress' => '$who: $text',
      'files' => '$who: $text',
      'edited' || 'removed' || 'rights' => '$who: ${text.replaceAll('\n', ' · ')}',
      'plan' => l10n.tr('projEvPlan'),
      _ => [
          '$who${text.isEmpty ? '' : ': «${text.length > 120 ? '${text.substring(0, 120)}…' : text}»'}',
          if (status != null) '· ${assignmentStatusLabel(status, l10n)}',
        ].join(' '),
    };
  }
}

// lib/features/assignments/assignments_summary_screen.dart
// «Сводка» по поручениям (просьба владельца 12.11.2026: сводные данные и
// визуальные отчёты по нескольким поручениям сразу). Как панель Jira и
// «Эффективность» Битрикс24: показатели, статусы, по людям, по неделям,
// проекты на одной диаграмме; отчёт — файлом в письме.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_report.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/assignments/assignment_stats.dart';
import '../../services/assignments/assignment_store.dart' show AssignmentTree, PlanStage, projectProgress, projectStatus;
import '../mail/providers/mail_providers.dart' show accountsProvider;
import 'assignment_charts.dart';
import 'assignment_widgets.dart' show AssignmentMailboxChip;
import 'gantt_chart.dart';

enum SummaryScope { mine, toMe, all }

/// Открыть «Сводку».
Future<void> showAssignmentsSummary(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AssignmentsSummaryScreen()));

/// Отчёт файлом HTML во вложении нового письма (текст — кратко).
Future<void> sendAssignmentReport(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<AssignmentView> items,
  required AssignmentStats stats,
  String? accountId,
}) async {
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final now = DateTime.now();
  final html = assignmentReportHtml(l10n: l10n, title: title, subtitle: subtitle, stats: stats, items: items, now: now);
  final dir = Directory('${(await getTemporaryDirectory()).path}/assignment_reports');
  await dir.create(recursive: true);
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe ${DateFormat('yyyy-MM-dd').format(now)}.html');
  await file.writeAsString(html);
  unawaited(router.push(Uri(path: '/compose', queryParameters: {
    'subject': '$title — ${DateFormat('d MMM yyyy', l10n.localeCode).format(now)}',
    'body': assignmentReportText(l10n: l10n, title: title, stats: stats),
    'attachments': file.path,
    if (accountId != null) 'accountId': accountId,
  }).toString()));
}

class AssignmentsSummaryScreen extends ConsumerStatefulWidget {
  const AssignmentsSummaryScreen({super.key});

  @override
  ConsumerState<AssignmentsSummaryScreen> createState() => _AssignmentsSummaryScreenState();
}

class _AssignmentsSummaryScreenState extends ConsumerState<AssignmentsSummaryScreen> {
  SummaryScope _scope = SummaryScope.mine;
  int _period = 30;
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final accounts = ref.watch(accountsProvider);
    if (_accountId != null && !accounts.any((a) => a.id == _accountId)) _accountId = null;
    final everything = ref.watch(assignmentsProvider).value ?? const <AssignmentView>[];
    final items = [
      for (final v in everything)
        if ((_accountId == null || v.row.accountId == _accountId) &&
            switch (_scope) {
              SummaryScope.mine => v.outgoing,
              SummaryScope.toMe => !v.outgoing,
              SummaryScope.all => true,
            })
          v,
    ];
    final now = DateTime.now();
    final stats = AssignmentStats.of(items, now, periodDays: _period);
    final projects = [for (final v in items) if (v.isProject && v.active) v];
    final periodText = l10n.tr('assignStatsPeriod').replaceAll('{n}', '$_period');
    final scopeText = l10n.tr(switch (_scope) {
      SummaryScope.mine => 'assignTabMine',
      SummaryScope.toMe => 'assignTabToMe',
      SummaryScope.all => 'all',
    });
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('assignSummary')),
        actions: [
          IconButton(
            key: const ValueKey('assign_send_report'),
            tooltip: l10n.tr('assignSendReport'),
            icon: const Icon(AppIcons.send),
            onPressed: () => unawaited(sendAssignmentReport(
              context,
              title: l10n.tr('assignReportTitle'),
              subtitle: [scopeText, periodText, if (account != null) account.email].join(' · '),
              items: items,
              stats: stats,
              accountId: _accountId,
            )),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
        // Фильтры — над графиками: кто, период, ящик.
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Wrap(spacing: Space.xs, runSpacing: Space.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<SummaryScope>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: SummaryScope.mine, label: Text(l10n.tr('assignTabMine'))),
                ButtonSegment(value: SummaryScope.toMe, label: Text(l10n.tr('assignTabToMe'))),
                ButtonSegment(value: SummaryScope.all, label: Text(l10n.tr('all'))),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            for (final d in const [30, 90, 365])
              ChoiceChip(
                label: Text(l10n.tr('assignStatsPeriod').replaceAll('{n}', '$d')),
                selected: _period == d,
                onSelected: (_) => setState(() => _period = d),
              ),
            if (accounts.length > 1)
              AssignmentMailboxChip(
                accounts: accounts,
                selected: _accountId,
                onChanged: (id) => setState(() => _accountId = id),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
          child: StatGrid(tiles: [
            StatTile(label: l10n.tr('assignStatsInWork'), value: '${stats.active}'),
            StatTile(
                label: l10n.tr('overdue'),
                value: '${stats.overdue}',
                accent: stats.overdue > 0 ? AppColors.errorText(context) : null),
            StatTile(label: l10n.tr('assignStReview'), value: '${stats.review}'),
            StatTile(label: l10n.tr('assignStatsDonePeriod'), value: '${stats.done}', note: periodText),
            StatTile(
                label: l10n.tr('assignStatsOnTime'),
                value: stats.onTimeShare == null ? '—' : percentText(stats.onTimeShare!),
                note: stats.done == 0 ? null : '${stats.onTime} / ${stats.done}'),
            StatTile(
                label: l10n.tr('assignStatsAvgDays'),
                value: stats.avgDays == null ? '—' : stats.avgDays!.toStringAsFixed(1)),
          ]),
        ),
        ChartCard(
          title: l10n.tr('assignStatsStatuses'),
          subtitle: l10n.tr('assignStatsStatusesHint').replaceAll('{period}', periodText),
          child: StatusSplitBar(counts: stats.byStatus),
        ),
        ChartCard(
          title: l10n.tr(switch (_scope) {
            SummaryScope.mine => 'assignStatsExecutors',
            SummaryScope.toMe => 'assignStatsOwners',
            SummaryScope.all => 'assignStatsPeople',
          }),
          child: PeopleBars(people: stats.people),
        ),
        ChartCard(
          title: l10n.tr('assignStatsWeeks'),
          subtitle: l10n.tr('assignStatsWeeksHint'),
          child: WeeklyColumns(weeks: stats.weeks),
        ),
        if (projects.isNotEmpty)
          ChartCard(
            title: l10n.tr('assignStatsProjects'),
            child: GanttChart(
              stages: [
                for (var i = 0; i < projects.length; i++)
                  () {
                    final p = projects[i];
                    final stages = everything.childrenOf(p.id);
                    final plan = planOf(stages);
                    return PlanStage(
                      id: p.id,
                      title: p.row.title,
                      start: p.start ?? p.row.createdAt.toLocal(),
                      due: p.due,
                      order: i,
                      status: projectStatus(p.status, [for (final s in stages) s.status]),
                      progress: projectProgress(plan),
                    );
                  }(),
              ],
              today: now,
              onTap: (id) => unawaited(context.push('/assignments/$id')),
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(l10n.tr('assignStatsNone'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Text(l10n.tr('assignStatsNote'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ),
      ]),
    );
  }
}

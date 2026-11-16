// lib/features/assignments/assignments_summary_screen.dart
// «Сводка» по поручениям. Решение владельца 16.11.2026: «много отчётов,
// графиков и таблиц не нужно — нужно понимать общий ход работы (диаграмма
// Ганта), кто исполнители и на каком этапе; акцентировать пользователю его
// роль и сроки». Поэтому главное — диаграмма «Ход работ»: поручения и
// проекты (этапы — внутри проекта), исполнитель и стадия второй строкой,
// моя роль — цветом строки (исполняю, контролирую, поручил, наблюдаю),
// срок — у конца полосы. Сверху — фильтр по роли и ящику и одна строка
// счётчиков; отчёт — файлом в письме.

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
import '../../widgets/common/readable_width.dart';
import 'assignment_widgets.dart';
import 'gantt_chart.dart';


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

/// Фильтр сводки по моей роли.
enum SummaryRole { all, execute, control, own, observe }

class AssignmentsSummaryScreen extends ConsumerStatefulWidget {
  const AssignmentsSummaryScreen({super.key});

  @override
  ConsumerState<AssignmentsSummaryScreen> createState() => _AssignmentsSummaryScreenState();
}

class _AssignmentsSummaryScreenState extends ConsumerState<AssignmentsSummaryScreen> {
  SummaryRole _role = SummaryRole.all;
  String? _accountId;

  /// Все строки (по умолчанию — первые 15 поручений и проектов).
  bool _showAll = false;
  static const _limit = 15;

  static bool _matches(AssignmentView v, SummaryRole r) => switch (r) {
        SummaryRole.all => true,
        SummaryRole.execute => myAssignmentRole(v) == MyAssignmentRole.execute,
        SummaryRole.control => myAssignmentRole(v) == MyAssignmentRole.control,
        SummaryRole.own => myAssignmentRole(v) == MyAssignmentRole.own,
        SummaryRole.observe => myAssignmentRole(v) == MyAssignmentRole.observe,
      };

  /// Строки «Хода работ»: действующие поручения со сроком и проекты, за
  /// проектом — его этапы; просроченные — первыми, дальше по сроку.
  ({List<(AssignmentView, int)> rows, int hidden, int noDue}) _rows(
      List<AssignmentView> items, List<AssignmentView> everything, DateTime now) {
    final projects = {for (final v in items) if (v.isProject && v.active) v.id};
    final top = <AssignmentView>[];
    var noDue = 0;
    for (final v in items) {
      if (!v.active || projects.contains(v.parentId)) continue;
      if (!_matches(v, _role) && !v.isProject) continue;
      if (v.isProject) {
        final stages = everything.childrenOf(v.id).where((s) => s.active).toList();
        // Проект — если в нём есть этапы под фильтр (или фильтра нет).
        if (_role != SummaryRole.all && !_matches(v, _role) && !stages.any((s) => _matches(s, _role))) continue;
        if (v.due == null && stages.every((s) => s.due == null)) continue;
      } else if (v.due == null) {
        noDue++;
        continue;
      }
      top.add(v);
    }
    DateTime dueOf(AssignmentView v) => v.due ?? DateTime(9999);
    top.sort((a, b) {
      final la = a.overdue(now), lb = b.overdue(now);
      if (la != lb) return la ? -1 : 1;
      return dueOf(a).compareTo(dueOf(b));
    });
    final shown = _showAll || top.length <= _limit ? top : top.take(_limit).toList();
    final rows = <(AssignmentView, int)>[];
    for (final v in shown) {
      rows.add((v, 0));
      if (v.isProject) {
        final stages = everything.childrenOf(v.id).where((s) => s.active && (s.start != null || s.due != null)).toList()
          ..sort((a, b) {
            final o = a.row.stageOrder.compareTo(b.row.stageOrder);
            return o != 0 ? o : a.row.createdAt.compareTo(b.row.createdAt);
          });
        for (final s in stages) {
          rows.add((s, 1));
        }
      }
    }
    return (rows: rows, hidden: top.length - shown.length, noDue: noDue);
  }

  /// Строка диаграммы: название; второй строкой — моя роль, исполнитель
  /// (если это не я) и стадия.
  PlanStage _planRow(AssignmentView v, int order, List<AssignmentView> all, AppLocalizations l10n) {
    final roleKey = myAssignmentRoleKey(v);
    final role = roleKey == null ? null : l10n.tr(roleKey);
    if (v.isProject) {
      final stages = all.childrenOf(v.id);
      final done = stages.where((s) => s.status == AssignmentStatus.done).length;
      return PlanStage(
        id: v.id,
        title: v.row.title,
        start: v.start ?? v.row.createdAt.toLocal(),
        due: v.due,
        order: order,
        status: projectStatus(v.status, [for (final s in stages) s.status]),
        progress: projectProgress(planOf(stages)),
        assignee: [
          ?role,
          l10n.tr('assignProjectSubject'),
          if (stages.isNotEmpty)
            l10n.tr('projStagesCount').replaceAll('{done}', '$done').replaceAll('{total}', '${stages.length}'),
        ].join(' · '),
      );
    }
    final me = myAssignmentRole(v) == MyAssignmentRole.execute && !v.iCoExecute;
    final executor = (v.assignee?.displayName ?? '').trim().isNotEmpty ? v.assignee!.displayName!.trim() : v.assignee?.email;
    return PlanStage(
      id: v.id,
      title: v.important ? '! ${v.row.title}' : v.row.title,
      start: v.start ?? v.row.createdAt.toLocal(),
      due: v.due,
      order: order,
      status: v.status,
      progress: v.progress,
      assignee: [
        ?role,
        if (!me && executor != null) executor,
        assignmentStatusLabel(v.status, l10n),
      ].join(' · '),
    );
  }

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
        if (_accountId == null || v.row.accountId == _accountId) v,
    ];
    final now = DateTime.now();
    final active = [for (final v in items) if (v.active && !v.isProject) v];
    int count(SummaryRole r) => active.where((v) => _matches(v, r)).length;
    final mine = [for (final v in active) if (_matches(v, _role)) v];
    final late = mine.where((v) => v.overdue(now)).length;
    final review = mine.where((v) => v.status == AssignmentStatus.review).length;
    final week = mine.where((v) {
      final d = v.due;
      return d != null && !v.overdue(now) && d.isBefore(DateTime(now.year, now.month, now.day + 8));
    }).length;
    final r = _rows(items, everything, now);
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final styles = {
      for (final (v, level) in r.rows)
        v.id: GanttRowStyle(accent: myAssignmentRoleColor(myAssignmentRole(v)), indent: level),
    };

    Widget roleChip(SummaryRole role, String label, MyAssignmentRole? color) {
      final c = color == null ? null : myAssignmentRoleColor(color);
      final n = role == SummaryRole.all ? active.length : count(role);
      return ChoiceChip(
        key: ValueKey('summary_role_${role.name}'),
        avatar: c == null ? null : CircleAvatar(radius: 5, backgroundColor: c),
        label: Text('$label · $n'),
        selected: _role == role,
        showCheckmark: false,
        onSelected: (_) => setState(() {
          _role = role;
          _showAll = false;
        }),
      );
    }

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
              subtitle: [if (account != null) account.email].join(' · '),
              items: items,
              stats: AssignmentStats.of(items, now),
              accountId: _accountId,
            )),
          ),
        ],
      ),
      body: ReadableWidth(
          maxWidth: 1280,
          fill: true,
          child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
            // Моя роль — фильтром; цвет чипа = цвет строки на диаграмме.
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
                roleChip(SummaryRole.all, l10n.tr('all'), null),
                roleChip(SummaryRole.execute, l10n.tr('assignRoleMeExecute'), MyAssignmentRole.execute),
                roleChip(SummaryRole.control, l10n.tr('filterControl'), MyAssignmentRole.control),
                roleChip(SummaryRole.own, l10n.tr('assignRoleMeOwn'), MyAssignmentRole.own),
                if (count(SummaryRole.observe) > 0)
                  roleChip(SummaryRole.observe, l10n.tr('filterObserve'), MyAssignmentRole.observe),
                if (accounts.length > 1)
                  AssignmentMailboxChip(
                    accounts: accounts,
                    selected: _accountId,
                    onChanged: (id) => setState(() => _accountId = id),
                  ),
              ]),
            ),
            // Одна строка вместо плиток: что горит.
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: l10n.tr('overdue'),
                      style: TextStyle(color: late > 0 ? AppColors.errorText(context) : null)),
                  TextSpan(
                      text: ' $late',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: late > 0 ? AppColors.errorText(context) : null)),
                  TextSpan(text: '  ·  ${l10n.tr('assignStReview')} '),
                  TextSpan(text: '$review', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '  ·  ${l10n.tr('assignStatsWeek')} '),
                  TextSpan(text: '$week', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (r.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Text(l10n.tr('assignStatsNone'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
                child: Text(l10n.tr('assignStatsProgress'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              GanttChart(
                key: ValueKey('summary_gantt_${_role.name}_${_accountId}_$_showAll'),
                stages: [for (var i = 0; i < r.rows.length; i++) _planRow(r.rows[i].$1, i, everything, l10n)],
                today: now,
                numbered: false,
                showAssignee: true,
                focusToday: true,
                styles: styles,
                dueLabels: true,
                onTap: (id) => unawaited(context.push('/assignments/$id')),
              ),
            ],
            if (r.hidden > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('summary_show_all'),
                    onPressed: () => setState(() => _showAll = true),
                    child: Text(l10n.tr('assignStatsShowAll').replaceAll('{n}', '${r.hidden}')),
                  ),
                ),
              ),
            if (r.noDue > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
                child: Text(l10n.tr('assignStatsNoDue').replaceAll('{n}', '${r.noDue}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Text(l10n.tr('assignStatsProgressHint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
          ])),
    );
  }
}

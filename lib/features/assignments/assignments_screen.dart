// lib/features/assignments/assignments_screen.dart
// «Поручения» — отдельный раздел меню (решение владельца 09.11.2026):
// «Я поручил» и «Мне поручили», фильтры, группы по сроку — просрочено
// (красным), на проверке, сегодня, на этой неделе, позже, без срока;
// выполненные и снятые — свёрнуто внизу. Нажатие — карточка поручения,
// долгое нажатие — быстрые действия (assignment_widgets.dart), кнопка —
// новое поручение. Проекты с этапами (12.11.2026): строка проекта — с
// прогрессом, этапы своего проекта — внутри него; фильтры «Контролирую» и
// «Наблюдаю» — по ролям в чужих поручениях.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/navigation/app_bottom_bar.dart' show AppBottomBar;
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../widgets/common/account_avatar.dart' show AccountAvatar;
import '../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../mail/providers/mail_providers.dart' show accountsProvider;
import '../../widgets/ui/empty_state.dart';
import '../../services/assignments/assignment_store.dart' show AssignmentTree, projectStatus;
import 'assign_sheet.dart';
import 'assignment_widgets.dart';
import 'assignments_summary_screen.dart' show showAssignmentsSummary;
import 'project_editor.dart' show showProjectEditor;

enum _Filter { all, overdue, review, control, help, observe }

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  /// С этой ширины области — две колонки вместо вкладок.
  static const _twoColumnsMin = 720.0;

  _Filter _filter = _Filter.all;
  bool _showDone = false;
  List<AssignmentView> _all = const [];

  /// Ящик (несколько ящиков): null — все.
  String? _accountId;

  Widget _summary(AppLocalizations l10n) => IconButton(
        key: const ValueKey('assign_summary'),
        tooltip: l10n.tr('assignSummary'),
        icon: const Icon(AppIcons.analytics),
        onPressed: () => unawaited(showAssignmentsSummary(context)),
      );

  Widget _newProject(AppLocalizations l10n) => IconButton(
        key: const ValueKey('assign_new_project'),
        tooltip: l10n.tr('projNew'),
        icon: const Icon(AppIcons.account_tree),
        onPressed: () => unawaited(showProjectEditor(context)),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider);
    if (_accountId != null && !accounts.any((a) => a.id == _accountId)) _accountId = null;
    final everything = ref.watch(assignmentsProvider).value ?? const <AssignmentView>[];
    final all = _accountId == null ? everything : [for (final v in everything) if (v.row.accountId == _accountId) v];
    _all = all;
    // Этапы своего проекта — внутри проекта, не отдельными строками.
    final myProjects = {for (final v in all) if (v.outgoing && v.isProject) v.id};
    final mine = [for (final v in all) if (v.outgoing && !myProjects.contains(v.parentId)) v];
    final toMe = [for (final v in all) if (!v.outgoing) v];
    int active(List<AssignmentView> l) => l.where((v) => v.active).length;
    final fab = AppBottomBar.inUse(context)
        ? null
        : FloatingActionButton.extended(
            heroTag: 'fab_assign',
            onPressed: () => unawaited(showAssignSheet(context)),
            icon: const Icon(AppIcons.add),
            label: Text(l10n.tr('assignNew')),
          );
    // Широкое окно (компьютер, планшет; просьба владельца 12.11.2026):
    // «Я поручил» и «Мне поручили» рядом, а не вкладками.
    return LayoutBuilder(builder: (context, box) => box.maxWidth >= _twoColumnsMin
        ? _wide(context, l10n, mine, toMe, active(mine), active(toMe), fab)
        : _tabs(context, l10n, mine, toMe, active(mine), active(toMe), fab));
  }

  Widget _wide(BuildContext context, AppLocalizations l10n, List<AssignmentView> mine, List<AssignmentView> toMe,
      int nMine, int nToMe, Widget? fab) {
    final theme = Theme.of(context);
    Widget column(String title, int n, List<AssignmentView> items) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Text('$title · $n', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: _list(context, items, l10n)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('assignments')), actions: [_summary(l10n), _newProject(l10n)]),
      floatingActionButton: fab,
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        column(l10n.tr('assignTabMine'), nMine, mine),
        const VerticalDivider(width: 1),
        column(l10n.tr('assignTabToMe'), nToMe, toMe),
      ]),
    );
  }

  Widget _tabs(BuildContext context, AppLocalizations l10n, List<AssignmentView> mine, List<AssignmentView> toMe,
      int nMine, int nToMe, Widget? fab) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tr('assignments')),
          actions: [_summary(l10n), _newProject(l10n)],
          bottom: TabBar(tabs: [
            Tab(text: '${l10n.tr('assignTabMine')} · $nMine'),
            Tab(text: '${l10n.tr('assignTabToMe')} · $nToMe'),
          ]),
        ),
        // На телефоне «Поручить» — в центре нижней панели (2.2.0).
        floatingActionButton: fab,
        body: TabBarView(children: [_list(context, mine, l10n), _list(context, toMe, l10n)]),
      ),
    );
  }

  Widget _list(BuildContext context, List<AssignmentView> items, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(Duration(days: 8 - today.weekday));
    final activeItems = [for (final v in items) if (v.active) v];
    final closed = [for (final v in items) if (!v.active) v];
    // Проект — просрочен, если опаздывает хоть один его этап (этапы своего
    // проекта в списке не показываются отдельно).
    bool late(AssignmentView v) =>
        v.overdue(now) || (v.isProject && _all.childrenOf(v.id).any((s) => s.active && s.overdue(now)));
    final overdueN = activeItems.where(late).length;
    final reviewN = activeItems.where((v) => v.status == AssignmentStatus.review).length;
    final controlN = activeItems.where((v) => v.iControl).length;
    final observeN = activeItems.where((v) => v.iObserve).length;
    final helpN = activeItems.where((v) => v.iCoExecute).length;
    var shown = activeItems;
    if (_filter == _Filter.overdue) shown = [for (final v in shown) if (late(v)) v];
    if (_filter == _Filter.review) shown = [for (final v in shown) if (v.status == AssignmentStatus.review) v];
    if (_filter == _Filter.control) shown = [for (final v in shown) if (v.iControl) v];
    if (_filter == _Filter.observe) shown = [for (final v in shown) if (v.iObserve) v];
    if (_filter == _Filter.help) shown = [for (final v in shown) if (v.iCoExecute) v];
    shown = [...shown]..sort((a, b) {
        // Важные — первыми в своей группе.
        if (a.important != b.important) return a.important ? -1 : 1;
        final da = a.due, db = b.due;
        if (da == null && db == null) return b.row.createdAt.compareTo(a.row.createdAt);
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    final groups = <(String, Color?, List<AssignmentView>)>[
      (l10n.tr('overdue'), AppColors.errorText(context), [for (final v in shown) if (late(v)) v]),
      (
        l10n.tr('assignStReview'),
        null,
        [for (final v in shown) if (!late(v) && v.status == AssignmentStatus.review) v]
      ),
    ];
    bool rest(AssignmentView v) => !late(v) && v.status != AssignmentStatus.review;
    DateTime? day(AssignmentView v) => v.due == null ? null : DateTime(v.due!.year, v.due!.month, v.due!.day);
    groups.addAll([
      (l10n.tr('today'), null, [for (final v in shown) if (rest(v) && day(v) == today) v]),
      (
        l10n.tr('thisWeek'),
        null,
        [for (final v in shown) if (rest(v) && day(v) != null && day(v)!.isAfter(today) && day(v)!.isBefore(weekEnd)) v]
      ),
      (l10n.tr('later'), null, [for (final v in shown) if (rest(v) && day(v) != null && !day(v)!.isBefore(weekEnd)) v]),
      (l10n.tr('noDueDate'), null, [for (final v in shown) if (rest(v) && day(v) == null) v]),
    ]);

    final children = <Widget>[
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          children: [
            if (ref.watch(accountsProvider).length > 1) ...[
              AssignmentMailboxChip(
                accounts: ref.watch(accountsProvider),
                selected: _accountId,
                onChanged: (id) => setState(() => _accountId = id),
              ),
              const SizedBox(width: Space.xs),
            ],
            FilterChip(
                label: Text(l10n.tr('all')),
                selected: _filter == _Filter.all,
                onSelected: (_) => setState(() => _filter = _Filter.all)),
            const SizedBox(width: Space.xs),
            FilterChip(
                label: Text('${l10n.tr('overdue')} · $overdueN'),
                selected: _filter == _Filter.overdue,
                onSelected: (_) => setState(() => _filter = _filter == _Filter.overdue ? _Filter.all : _Filter.overdue)),
            const SizedBox(width: Space.xs),
            FilterChip(
                label: Text('${l10n.tr('assignStReview')} · $reviewN'),
                selected: _filter == _Filter.review,
                onSelected: (_) => setState(() => _filter = _filter == _Filter.review ? _Filter.all : _Filter.review)),
            // По ролям — только когда такие есть в этом списке.
            for (final (f, key, n) in [
              (_Filter.control, 'filterControl', controlN),
              (_Filter.help, 'filterHelp', helpN),
              (_Filter.observe, 'filterObserve', observeN),
            ])
              if (n > 0 || _filter == f) ...[
                const SizedBox(width: Space.xs),
                FilterChip(
                    label: Text('${l10n.tr(key)} · $n'),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = _filter == f ? _Filter.all : f)),
              ],
          ],
        ),
      ),
    ];
    for (final (title, color, list) in groups) {
      if (list.isEmpty) continue;
      children
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: color ?? AppColors.mutedText(context), fontWeight: FontWeight.w700)),
        ))
        ..addAll([for (final v in list) _AssignmentRow(v: v, all: _all)]);
    }
    if (closed.isNotEmpty) {
      children.add(ListTile(
        leading: Icon(_showDone ? AppIcons.expand_less : AppIcons.expand_more, color: AppColors.mutedText(context)),
        title: Text('${l10n.tr('assignClosed')} · ${closed.length}',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
        onTap: () => setState(() => _showDone = !_showDone),
      ));
      if (_showDone) children.addAll([for (final v in closed) _AssignmentRow(v: v, all: _all)]);
    }
    if (activeItems.isEmpty && closed.isEmpty) {
      return ListView(children: [
        const SizedBox(height: Space.xxl),
        EmptyState(icon: AppIcons.assignment_ind, title: l10n.tr('assignEmpty'), message: l10n.tr('assignEmptyHint')),
      ]);
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
  }
}

class _AssignmentRow extends ConsumerWidget {
  final AssignmentView v;

  /// Все поручения — этапы проекта для прогресса.
  final List<AssignmentView> all;
  const _AssignmentRow({required this.v, required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.mutedText(context);
    final now = DateTime.now();
    // Проект: «2 из 5 этапов» и полоса прогресса (у постановщика).
    final stages = v.isProject ? all.childrenOf(v.id) : const <AssignmentView>[];
    final overdue = v.overdue(now) || stages.any((s) => s.active && s.overdue(now));
    final dueColor = overdue ? AppColors.errorText(context) : muted;
    final live = [for (final s in stages) if (s.status != AssignmentStatus.cancelled) s];
    final doneN = live.where((s) => s.status == AssignmentStatus.done).length;
    final progress = live.isEmpty ? 0.0 : live.fold<double>(0, (a, s) => a + s.progress) / live.length;
    // Своя роль в чужом поручении — если не исполнитель.
    final role = v.outgoing || v.iExecute
        ? null
        : v.iControl
            ? l10n.tr('filterControl')
            : v.iCoExecute
                ? l10n.tr('filterHelp')
                : v.iObserve
                    ? l10n.tr('filterObserve')
                    : null;
    return InkWell(
      onTap: () => context.push('/assignments/${v.id}'),
      onLongPress: () => unawaited(showAssignmentPeek(context, ref, v, anchor: peekAnchorOf(context))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Несколько ящиков — значок ящика у портрета (как в уведомлениях).
          Builder(builder: (context) {
            final accounts = ref.watch(accountsProvider);
            final account = accounts.length > 1 ? accounts.where((a) => a.id == v.row.accountId).firstOrNull : null;
            if (account == null) return AssignmentAvatar(v);
            return Stack(clipBehavior: Clip.none, children: [
              AssignmentAvatar(v),
              Positioned(right: -4, bottom: -4, child: AccountAvatar(account: account, radius: 7)),
            ]);
          }),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                  TextSpan(children: [
                    if (v.important)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(AppIcons.priority_high, size: 18, color: AppColors.errorText(context)),
                      ),
                    TextSpan(text: v.row.title),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: v.active ? null : muted,
                    decoration: v.status == AssignmentStatus.cancelled ? TextDecoration.lineThrough : null,
                  )),
              const SizedBox(height: 2),
              Row(children: [
                // Подзадача другого поручения или проект (12.11.2026).
                if (v.parentId != null || v.isProject) ...[
                  Icon(AppIcons.account_tree, size: 13, color: v.isProject ? theme.colorScheme.primary : muted),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                      [
                        if (v.isProject && live.isNotEmpty)
                          l10n
                              .tr('projStagesCount')
                              .replaceAll('{done}', '$doneN')
                              .replaceAll('{total}', '${live.length}')
                        else if (!(v.outgoing && v.isProject))
                          v.otherName,
                        if (role != null) role,
                        if (v.waiting) l10n.tr('projWaiting'),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
                if (v.due != null) ...[
                  Text(' · ', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  Icon(AppIcons.schedule, size: 13, color: dueColor),
                  const SizedBox(width: 2),
                  Text(assignmentDueText(v.due!, l10n),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: dueColor, fontWeight: overdue ? FontWeight.w700 : null)),
                ],
              ]),
              if (v.isProject && live.isNotEmpty && v.active)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: LinearProgressIndicator(value: progress, minHeight: 3, borderRadius: BorderRadius.circular(2)),
                ),
            ]),
          ),
          const SizedBox(width: Space.s),
          AssignmentStatusPill(v.isProject ? projectStatus(v.status, [for (final s in stages) s.status]) : v.status),
        ]),
      ),
    );
  }
}

// lib/features/tasks/screens/tasks_screen.dart
// Задачи и напоминания (переработано 07.10.2026 по образцу Microsoft To Do и
// Google Tasks):
//  · умные списки: «Мой день», «Запланировано», «Важное», «Все», «Письма»
//    (письма с «Напомнить» и «нет ответа»), «Выполнено»;
//  · круглая отметка «выполнено», звезда «важное», свайп вправо — выполнить,
//    влево — удалить (с «Отменить»);
//  · у задачи отдельно срок и напоминание, повтор, подзадачи — в карточке
//    задачи (нажатие), а не в меню по долгому нажатию;
//  · быстрое добавление одной строкой: «Позвонить завтра в 15:00 !»;
//  · список обновляется сам (поток из базы) — синхронизация, кнопка
//    «Выполнено» в уведомлении и календарь видны сразу.

import '../../../widgets/ui/section_band.dart';
import 'dart:async';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../widgets/navigation/panel_requests.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/empty_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart' show pushMailDetail;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ogneliss_look.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/task_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/sync_service.dart';
import '../../../services/mail/email_actions_service.dart' show emailActionsProvider;
import '../../../services/tasks/task_actions_service.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../../widgets/common/peek_card.dart';
import '../../../widgets/common/quick_long_press.dart';
import '../../calendar/calendar_data.dart' show calendarScopeProvider, accountColorsProvider, capitalize;
import '../../mail/providers/mail_providers.dart';
import '../../settings/providers/module_settings_provider.dart';
import '../task_quick_parser.dart';
import '../widgets/task_editor_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/adaptive_layout.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;
import '../../../widgets/ui/app_menu_button.dart';

/// Умные списки.
enum TaskList { myDay, planned, important, all, mail, completed }

/// Задачи ящиков текущей области (как у почты и календаря) — поток.
final tasksStreamProvider = StreamProvider.autoDispose<List<TaskModel>>((ref) {
  final db = ref.watch(databaseProvider);
  final ids = [for (final a in ref.watch(calendarScopeProvider)) a.id];
  ref.watch(tasksRevisionProvider);
  if (ids.isEmpty) return Stream.value(const <TaskModel>[]);
  return (db.select(db.tasks)..where((t) => t.accountId.isIn(ids)))
      .watch()
      .map((rows) => rows.map(taskFromRow).toList());
});

/// Письма с напоминанием («Напомнить») или контролем ответа.
final mailRemindersProvider = StreamProvider.autoDispose<List<Email>>((ref) {
  final db = ref.watch(databaseProvider);
  final ids = [for (final a in ref.watch(calendarScopeProvider)) a.id];
  if (ids.isEmpty) return Stream.value(const <Email>[]);
  return (db.select(db.emails)
        ..where((e) => e.accountId.isIn(ids))
        ..where((e) => e.remindAt.isNotNull() | e.followUpAt.isNotNull())
        ..limit(200))
      .watch();
});

/// «Задача удалена — Отменить» (1.8.0: строкой вверху экрана вместо чёрной
/// плашки внизу, которая мешала — замечание 07.10.2026). «Выполнена» строкой
/// не сообщается: отметка видна в списке и снимается повторным нажатием.
bool taskUndoBars = true;

class TasksScreen extends ConsumerStatefulWidget {
  /// Открыть карточку задачи (из уведомления или календаря).
  final String? openTaskId;
  final String? openAccountId;
  /// Сразу открыть новое напоминание (быстрое действие на значке).
  final bool openNew;
  const TasksScreen({super.key, this.openTaskId, this.openAccountId, this.openNew = false});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  /// Карточка задачи в правой панели (планшет, iPad, широкое окно).
  ({TaskModel? task, ParsedTask? draft, String? accountId, int gen})? _pane;
  int _paneGen = 0;
  /// Ширина области содержимого при последней сборке (без боковой
  /// навигации): по ней решается, поместится ли панель справа.
  double _bodyWidth = 0;

  /// Открыть карточку: на широком экране — справа от списка, на телефоне —
  /// снизу листом (как раньше).
  void _openEditor({TaskModel? task, ParsedTask? draft, String? accountId}) {
    if (_bodyWidth >= Breakpoints.tablet) {
      setState(() => _pane = (task: task, draft: draft, accountId: accountId, gen: ++_paneGen));
      return;
    }
    showTaskEditor(context, task: task, draft: draft, accountId: accountId);
  }

  static const _kList = 'tasks_last_list';

  late TaskList _list;
  bool _searchActive = false;
  String _search = '';
  final _searchCtrl = TextEditingController();
  /// Смахнутые строки — скрыты до прихода обновления из базы.
  final Set<String> _hidden = {};
  String? _pendingOpen;
  String? _pendingOpenAccount;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(sharedPrefsProvider).getInt(_kList);
    if (saved != null && saved >= 0 && saved < TaskList.values.length) {
      _list = TaskList.values[saved];
    } else {
      _list = switch (ref.read(moduleSettingsProvider).taskView) {
        TaskDefaultView.today => TaskList.myDay,
        TaskDefaultView.upcoming => TaskList.planned,
        TaskDefaultView.all => TaskList.all,
      };
    }
    // Список «Сегодня» убран (08.10.2026): задачи объединены с календарём, день
    // смотрят в режиме «День» календаря. Сохранённый выбор — на «Запланировано»
    // (там тоже есть «Просрочено» и «Сегодня»).
    if (_list == TaskList.myDay) _list = TaskList.planned;
    _pendingOpen = widget.openTaskId;
    _pendingOpenAccount = widget.openAccountId;
    if (widget.openNew) _openNewSoon();
  }

  void _openNewSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final acc = widget.openAccountId;
      _openEditor(accountId: (acc != null && acc.isNotEmpty) ? acc : _defaultAccount());
    });
  }

  @override
  void didUpdateWidget(covariant TasksScreen old) {
    super.didUpdateWidget(old);
    // Экран уже открыт, а пришло быстрое действие — новое напоминание.
    if (widget.openNew && !old.openNew) _openNewSoon();
    if (widget.openTaskId != null && widget.openTaskId != old.openTaskId) {
      _pendingOpen = widget.openTaskId;
      _pendingOpenAccount = widget.openAccountId;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setList(TaskList l) {
    HapticFeedback.selectionClick();
    setState(() => _list = l);
    ref.read(sharedPrefsProvider).setInt(_kList, l.index);
  }

  String _key(TaskModel t) => '${t.accountId}|${t.id}';

  @override
  Widget build(BuildContext context) {
    // «Новая задача» из центра нижней панели.
    ref.listen<int>(tasksAddRequestProvider, (_, __) => _openEditor(accountId: null));
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(tasksStreamProvider);
    final mail = ref.watch(mailRemindersProvider).value ?? const <Email>[];
    final mod = ref.watch(moduleSettingsProvider);

    final all = (async.value ?? const <TaskModel>[])
        .where((t) => !_hidden.contains(_key(t)))
        .where((t) => _search.isEmpty ||
            t.title.toLowerCase().contains(_search) ||
            (t.description ?? '').toLowerCase().contains(_search) ||
            t.tags.any((g) => g.toLowerCase().contains(_search)))
        .toList();

    // Открыть задачу, когда список загружен.
    if (_pendingOpen != null && async.hasValue) {
      final id = _pendingOpen!;
      final acc = _pendingOpenAccount;
      _pendingOpen = null;
      final t = (async.value ?? const <TaskModel>[])
          .where((x) => x.id == id && (acc == null || acc.isEmpty || x.accountId == acc))
          .firstOrNull;
      if (t != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openEditor(task: t);
        });
      }
    }

    final counts = _counts(all, mail);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: _searchActive
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(hintText: l10n.tr('search'), border: InputBorder.none, filled: false),
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              )
            : Text(l10n.tasksLabel),
        actions: [
          if (_searchActive)
            IconButton(
              tooltip: l10n.tr('close'),
              icon: const Icon(AppIcons.close),
              onPressed: () => setState(() {
                _searchActive = false;
                _search = '';
                _searchCtrl.clear();
              }),
            )
          else
            IconButton(
              icon: const Icon(AppIcons.search),
              tooltip: l10n.tr('search'),
              onPressed: () => setState(() => _searchActive = true),
            ),
          AppMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'clear_done':
                  await _clearCompleted(l10n, all);
                  break;
                case 'settings':
                  if (mounted) unawaited(context.push('/settings/tasks'));
                  break;
              }
            },
            itemBuilder: (_) => [
              AppMenuEntry(value: 'clear_done', icon: AppIcons.delete_sweep, label: l10n.tr('clearCompleted')),
              AppMenuEntry(value: 'settings', icon: AppIcons.settings, label: l10n.tr('settings')),
            ],
          ),
        ],
      )),
      body: LayoutBuilder(builder: (context, c) {
        _bodyWidth = c.maxWidth;
        final list = _mainColumn(l10n, theme, counts, async, all, mail, mod);
        final pane = _pane;
        if (pane == null || c.maxWidth < Breakpoints.tablet) return list;
        return Row(children: [
          Expanded(child: list),
          VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
          SizedBox(
            width: (c.maxWidth * 0.42).clamp(340.0, 480.0),
            child: Column(children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => setState(() => _pane = null),
                ),
              ),
              Expanded(
                child: TaskEditor(
                  key: ValueKey('pane_${pane.gen}'),
                  task: pane.task,
                  draft: pane.draft,
                  accountId: pane.accountId,
                  onDone: () => setState(() => _pane = null),
                ),
              ),
            ]),
          ),
        ]);
      }),
      bottomNavigationBar: _QuickAddBar(
        list: _list,
        onOpenEditor: (draft) => _openEditor(draft: draft, accountId: _defaultAccount()),
        onAdd: _quickAdd,
      ),
    );
  }

  Widget _mainColumn(AppLocalizations l10n, ThemeData theme, Map<TaskList, int> counts, AsyncValue<List<TaskModel>> async,
      List<TaskModel> all, List<Email> mail, ModuleSettings mod) {
    return Column(
        children: [
          _listChips(l10n, counts),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (_) => RefreshIndicator(
                onRefresh: () async {
                  unawaited(HapticFeedback.mediumImpact());
                  await ref.read(syncServiceProvider).syncAll();
                },
                child: _list == TaskList.mail
                    ? _mailList(l10n, theme, mail)
                    : _taskList(l10n, theme, all, mod),
              ),
            ),
          ),
        ],
      );
  }

  String? _defaultAccount() => ref.read(activeAccountProvider)?.id ?? ref.read(calendarScopeProvider).firstOrNull?.id;

  // ── Счётчики и вкладки ──
  Map<TaskList, int> _counts(List<TaskModel> all, List<Email> mail) {
    final now = DateTime.now();
    final active = all.where((t) => !t.isDone).toList();
    return {
      TaskList.myDay: active.where((t) => _inMyDay(t, now)).length,
      TaskList.planned: active.where((t) => t.dueDate != null || t.reminderAt != null).length,
      TaskList.important: active.where((t) => t.isFlagged).length,
      TaskList.all: active.length,
      TaskList.mail: mail.length,
      TaskList.completed: all.where((t) => t.isDone).length,
    };
  }

  static bool _inMyDay(TaskModel t, DateTime now) {
    final end = DateTime(now.year, now.month, now.day + 1);
    final due = t.dueDate?.toLocal();
    final rem = t.reminderAt?.toLocal();
    return (due != null && due.isBefore(end)) || (rem != null && rem.isBefore(end));
  }

  Widget _listChips(AppLocalizations l10n, Map<TaskList, int> counts) {
    final items = <(TaskList, IconData, String)>[
      (TaskList.planned, AppIcons.event_note, l10n.tr('planned')),
      (TaskList.important, AppIcons.star, l10n.tr('important')),
      (TaskList.all, AppIcons.all_inbox, l10n.tr('allTasks')),
      (TaskList.mail, AppIcons.mark_email_unread, l10n.tr('mailReminders')),
      (TaskList.completed, AppIcons.task_alt, l10n.tr('completed')),
    ];
    // Высота ряда растёт вместе с (ограниченным) шрифтом чипов — иначе
    // при крупном шрифте чипы обрезались снизу.
    return TextScaleCap.compact(child: Builder(builder: (context) => SizedBox(
      height: 36 + 16 * context.textScale,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Space.s),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                avatar: Icon(it.$2, size: 18),
                label: Text((counts[it.$1] ?? 0) > 0 ? '${it.$3} ${counts[it.$1]}' : it.$3),
                selected: _list == it.$1,
                showCheckmark: false,
                onSelected: (_) => _setList(it.$1),
              ),
            ),
        ],
      ),
    )));
  }

  // ── Список задач ──
  Widget _taskList(AppLocalizations l10n, ThemeData theme, List<TaskModel> all, ModuleSettings mod) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekEnd = today.add(const Duration(days: 7));

    DateTime? when(TaskModel t) => t.dueDate?.toLocal() ?? t.reminderAt?.toLocal();
    int byWhen(TaskModel a, TaskModel b) {
      final wa = when(a), wb = when(b);
      if (wa == null && wb == null) {
        if (a.isFlagged != b.isFlagged) return a.isFlagged ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      }
      if (wa == null) return 1;
      if (wb == null) return -1;
      return wa.compareTo(wb);
    }

    bool overdue(TaskModel t) {
      final d = t.dueDate?.toLocal();
      if (d == null) return false;
      final dateOnly = d.hour == 0 && d.minute == 0;
      return dateOnly ? d.isBefore(today) : d.isBefore(now);
    }

    final active = all.where((t) => !t.isDone).toList()..sort(byWhen);
    final sections = <(String, List<TaskModel>, Color?)>[];

    switch (_list) {
      case TaskList.myDay:
        final od = active.where(overdue).toList();
        final td = active.where((t) => !overdue(t) && _inMyDay(t, now)).toList();
        sections.add((l10n.tr('overdue'), od, AppColors.errorRed));
        sections.add((l10n.tr('today'), td, null));
        break;
      case TaskList.planned:
        final planned = active.where((t) => when(t) != null).toList();
        final od = planned.where(overdue).toList();
        final rest = planned.where((t) => !overdue(t)).toList();
        bool inDay(TaskModel t, DateTime a, DateTime b) {
          final w = when(t)!;
          return !w.isBefore(a) && w.isBefore(b);
        }
        sections.add((l10n.tr('overdue'), od, AppColors.errorRed));
        sections.add((l10n.tr('today'), rest.where((t) => when(t)!.isBefore(tomorrow)).toList(), null));
        sections.add((l10n.tr('tomorrow'), rest.where((t) => inDay(t, tomorrow, tomorrow.add(const Duration(days: 1)))).toList(), null));
        sections.add((l10n.tr('thisWeek'), rest.where((t) => inDay(t, tomorrow.add(const Duration(days: 1)), weekEnd)).toList(), null));
        sections.add((l10n.tr('later'), rest.where((t) => !when(t)!.isBefore(weekEnd)).toList(), null));
        break;
      case TaskList.important:
        sections.add(('', active.where((t) => t.isFlagged).toList(), null));
        break;
      case TaskList.all:
        sections.add((l10n.tr('withDate'), active.where((t) => when(t) != null).toList(), null));
        sections.add((l10n.tr('noDueDate'), active.where((t) => when(t) == null).toList(), null));
        break;
      case TaskList.completed:
        final done = all.where((t) => t.isDone).toList()
          ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
        sections.add(('', done, null));
        break;
      case TaskList.mail:
        break;
    }

    final nonEmpty = sections.where((s) => s.$2.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return _empty(l10n, theme);

    final colors = ref.watch(accountColorsProvider);
    final multi = ref.watch(calendarScopeProvider).length > 1;
    final children = <Widget>[];
    for (final s in nonEmpty) {
      if (s.$1.isNotEmpty) {
        // Раздел — полосой, как в боковом меню (10.10.2026).
        children.add(SectionBand(title: s.$1, count: s.$2.length, color: s.$3));
      }
      for (final t in s.$2) {
        children.add(_TaskTile(
          key: ValueKey(_key(t)),
          task: t,
          l10n: l10n,
          accountColor: multi ? colors[t.accountId] : null,
          isShared: _isShared(t.accountId),
          onToggle: () => _toggle(t),
          onStar: () => ref.read(taskActionsProvider).toggleImportant(t.accountId, t.id),
          onTap: () => _openEditor(task: t),
          onDelete: () => _delete(t, l10n),
          onLongPress: (tileCtx) => _peek(tileCtx, t, l10n),
        ));
      }
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: children,
    );
  }

  /// Карточка задачи по удержанию (1.7.0, как у писем, встреч, контактов и
  /// заметок): описание и подзадачи, кнопки — выполнено, важная, изменить,
  /// срок «Сегодня»; «Ещё» — по группам: задача, срок, письмо, удалить.
  void _peek(BuildContext tileCtx, TaskModel t, AppLocalizations l10n) {
    unawaited(HapticFeedback.mediumImpact());
    final actions = ref.read(taskActionsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    void due(DateTime? d) {
      unawaited(HapticFeedback.selectionClick());
      unawaited(actions.update(t.accountId, t.id, TasksCompanion(dueDate: Value(d))));
    }

    final done = PeekAction(
      icon: t.isDone ? AppIcons.undo : AppIcons.check,
      label: l10n.tr(t.isDone ? 'taskReopen' : 'taskDone'),
      onTap: () => unawaited(_toggle(t)),
    );
    final star = PeekAction(
      icon: AppIcons.star,
      filled: t.isFlagged,
      color: t.isFlagged ? AppColors.brandAmber : null,
      label: l10n.tr('important'),
      onTap: () => unawaited(actions.toggleImportant(t.accountId, t.id)),
    );
    final edit = PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: () => _openEditor(task: t));
    final linked = t.linkedEmailId;
    unawaited(showPeekCard(
      context,
      anchor: peekAnchorOf(tileCtx),
      onOpen: () => _openEditor(task: t),
      card: _TaskPeekCard(task: t, l10n: l10n),
      moreLabel: l10n.tr('peekMore'),
      actions: [
        done,
        star,
        edit,
        if (!t.isDone) PeekAction(icon: AppIcons.today, label: l10n.tr('today'), onTap: () => due(today)),
      ],
      more: [
        PeekGroup(title: l10n.tr('peekGroupTask'), items: [done, star, edit]),
        if (!t.isDone)
          PeekGroup(title: l10n.tr('peekGroupDue'), items: [
            PeekAction(icon: AppIcons.today, label: l10n.tr('today'), onTap: () => due(today)),
            PeekAction(icon: AppIcons.event, label: l10n.tr('tomorrow'), onTap: () => due(today.add(const Duration(days: 1)))),
            PeekAction(
                icon: AppIcons.date_range, label: l10n.tr('inAWeek'), onTap: () => due(today.add(const Duration(days: 7)))),
            if (t.dueDate != null)
              PeekAction(icon: AppIcons.event_busy, label: l10n.tr('noDueDate'), onTap: () => due(null)),
          ]),
        if (linked != null)
          PeekGroup(title: l10n.tr('peekGroupMail'), items: [
            PeekAction(
              icon: AppIcons.mail,
              label: l10n.tr('openEmail'),
              onTap: () => pushMailDetail(GoRouter.of(context), linked, accountId: t.accountId),
            ),
          ]),
        PeekGroup(items: [
          PeekAction(
            icon: AppIcons.delete,
            label: l10n.delete,
            color: AppColors.errorText(context),
            onTap: () => unawaited(_delete(t, l10n)),
          ),
        ]),
      ],
    ));
  }

  bool _isShared(String accountId) =>
      ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull?.isSharedMailbox ?? false;

  Future<void> _toggle(TaskModel t) async {
    unawaited(HapticFeedback.lightImpact());
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(taskActionsProvider);
    final done = !t.isDone;
    await actions.setDone(t.accountId, t.id, done);
    // Повторяющаяся задача: выполненная тут же появляется со следующим
    // сроком — объяснить, что произошло.
    if (done && t.isRepeating) showInlineNotice(l10n.tr('taskNextOccurrence'));
  }

  Future<void> _delete(TaskModel t, AppLocalizations l10n) async {
    final actions = ref.read(taskActionsProvider);
    setState(() => _hidden.add(_key(t)));
    final row = await actions.delete(t.accountId, t.id);
    if (!mounted) return;
    setState(() => _hidden.remove(_key(t)));
    if (row == null || !taskUndoBars) return;
    showInlineNotice(l10n.tr('taskDeleted'), actionLabel: l10n.tr('undo'), onAction: () => actions.restore(row));
  }

  Future<void> _clearCompleted(AppLocalizations l10n, List<TaskModel> all) async {
    final done = all.where((t) => t.isDone).toList();
    if (done.isEmpty) return;
    final ok = await confirmDestructive(context,
        title: l10n.tr('clearCompleted'),
        message: l10n.tr('clearCompletedConfirm').replaceAll('{n}', '${done.length}'));
    if (!ok) return;
    final actions = ref.read(taskActionsProvider);
    for (final t in done) {
      await actions.delete(t.accountId, t.id);
    }
  }

  Future<void> _quickAdd(String text) async {
    final p = TaskQuickParser.parse(text);
    final accountId = _defaultAccount();
    if (accountId == null || p.title.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    // В «Мой день» без даты — срок сегодня; в «Важном» — важная.
    final due = p.due ?? (_list == TaskList.myDay ? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day) : null);
    await ref.read(taskActionsProvider).create(
          accountId: accountId,
          title: p.title,
          dueDate: due,
          reminderAt: p.reminder,
          repeat: p.repeat,
          important: p.important || _list == TaskList.important,
        );
  }

  Widget _empty(AppLocalizations l10n, ThemeData theme) {
    final (icon, text) = switch (_list) {
      TaskList.myDay => (AppIcons.myDay, l10n.tr('myDayEmpty')),
      TaskList.planned => (AppIcons.event_note, l10n.tr('plannedEmpty')),
      TaskList.important => (AppIcons.star, l10n.tr('importantEmpty')),
      TaskList.completed => (AppIcons.task_alt, l10n.tr('completedEmpty')),
      TaskList.mail => (AppIcons.mark_email_unread, l10n.tr('mailRemindersEmpty')),
      TaskList.all => (AppIcons.check_box, l10n.tr('noTasks')),
    };
    return EmptyState(icon: icon, title: text, scrollable: true);
  }

  // ── Письма с напоминанием ──
  Widget _mailList(AppLocalizations l10n, ThemeData theme, List<Email> mail) {
    if (mail.isEmpty) return _empty(l10n, theme);
    final locale = l10n.localeCode;
    DateTime at(Email e) => (e.remindAt ?? e.followUpAt)!.toLocal();
    final sorted = [...mail]..sort((a, b) => at(a).compareTo(at(b)));
    final now = DateTime.now();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final e = sorted[i];
        final w = at(e);
        final followUp = e.remindAt == null;
        final due = w.isBefore(now);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: (due ? AppColors.errorRed : theme.colorScheme.primary).withValues(alpha: 0.12),
            child: Icon(followUp ? AppIcons.reply : AppIcons.alarm,
                color: due ? AppColors.errorRed : theme.colorScheme.primary, size: 20),
          ),
          title: Text(e.subject.isEmpty ? l10n.tr('noSubject') : e.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${followUp ? l10n.tr('followUpNoReply') : l10n.tr('remindMe')} · '
            '${capitalize(DateFormat('EEE, d MMM, HH:mm', locale).format(w))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: due ? AppColors.errorTextOn(theme) : null),
          ),
          trailing: IconButton(
            tooltip: l10n.tr('removeReminder'),
            icon: const Icon(AppIcons.alarm_off),
            onPressed: () async {
              final db = ref.read(databaseProvider);
              // «Позже» снимается вместе с напоминанием (и уведомление тоже).
              if (e.remindAt != null) {
                await ref.read(emailActionsProvider).setLater(e.id, e.accountId, on: false);
              }
              await (db.update(db.emails)..where((x) => x.id.equals(e.id) & x.accountId.equals(e.accountId)))
                  .write(const EmailsCompanion(remindAt: Value(null), followUpAt: Value(null)));
            },
          ),
          onTap: () => pushMailDetail(GoRouter.of(context), e.id, accountId: e.accountId),
        );
      },
    );
  }
}

/// Строка задачи.
class _TaskTile extends StatelessWidget {
  final TaskModel task;
  final AppLocalizations l10n;
  final Color? accountColor;
  final bool isShared;
  final VoidCallback onToggle;
  final VoidCallback onStar;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Удержание — карточка задачи (1.7.0); получает context строки.
  final void Function(BuildContext tileContext)? onLongPress;

  const _TaskTile({
    super.key,
    required this.task,
    required this.l10n,
    required this.onToggle,
    required this.onStar,
    required this.onTap,
    required this.onDelete,
    this.onLongPress,
    this.accountColor,
    this.isShared = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = task;
    final scheme = theme.colorScheme;
    final meta = _meta(theme);

    return Dismissible(
      key: ValueKey('dismiss_${t.accountId}|${t.id}'),
      // Спокойные тональные цвета, как у свайпов в почте.
      background: Container(
        color: SwipeTone.of(context, AppColors.successGreen).$1,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Space.xl),
        child: Icon(t.isDone ? AppIcons.undo : AppIcons.check,
            color: SwipeTone.of(context, AppColors.successGreen).$2),
      ),
      secondaryBackground: Container(
        color: SwipeTone.of(context, AppColors.errorRed).$1,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        child: Icon(AppIcons.delete, color: SwipeTone.of(context, AppColors.errorRed).$2),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onToggle();
          return false; // строку обновит поток из базы
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      child: SharedMailboxStripe(
        isShared: isShared,
        child: QuickLongPress(
          onLongPress: onLongPress == null ? null : () => onLongPress!(context),
          pressEffect: true,
          child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: Space.m),
                  child: TaskRoundCheck(value: t.isDone, onChanged: onToggle, color: scheme.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: t.isDone ? TextDecoration.lineThrough : null,
                          color: t.isDone ? theme.hintColor : null,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: meta,
                          ),
                        ),
                    ],
                  ),
                ),
                if (accountColor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 9, left: 6),
                    child: CircleAvatar(radius: 4, backgroundColor: accountColor),
                  ),
                IconButton(
                  tooltip: l10n.tr('important'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.star, fill: t.isFlagged ? 1 : 0,
                      color: t.isFlagged ? AppColors.brandAmber : theme.hintColor),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onStar();
                  },
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  List<Widget> _meta(ThemeData theme) {
    final t = task;
    final out = <Widget>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final locale = l10n.localeCode;
    final small = theme.textTheme.bodySmall;

    Widget item(IconData icon, String text, {Color? color}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color ?? theme.hintColor),
            const SizedBox(width: 3),
            Text(text, style: small?.copyWith(color: color ?? theme.hintColor)),
          ],
        );

    String rel(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      final hasTime = d.hour != 0 || d.minute != 0;
      final tm = hasTime ? ' ${DateFormat('HH:mm').format(d)}' : '';
      if (day == today) return '${l10n.tr('today')}$tm';
      if (day == today.add(const Duration(days: 1))) return '${l10n.tr('tomorrow')}$tm';
      if (day == today.subtract(const Duration(days: 1))) return '${l10n.tr('yesterday')}$tm';
      final diff = day.difference(today).inDays;
      if (diff > 0 && diff < 7) return '${capitalize(DateFormat('EEE', locale).format(d))}$tm';
      return '${DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yyyy', locale).format(d)}$tm';
    }

    final due = t.dueDate?.toLocal();
    if (due != null) {
      final dateOnly = due.hour == 0 && due.minute == 0;
      final od = !t.isDone && (dateOnly ? due.isBefore(today) : due.isBefore(now));
      final isToday = DateTime(due.year, due.month, due.day) == today;
      out.add(item(AppIcons.event, rel(due),
          color: od ? AppColors.errorRed : (isToday && !t.isDone ? theme.colorScheme.primary : null)));
    }
    final rem = t.reminderAt?.toLocal();
    if (rem != null && !t.isDone) {
      out.add(item(AppIcons.notifications, DateFormat('HH:mm').format(rem) == '00:00' ? rel(rem) : rel(rem),
          color: rem.isBefore(now) ? theme.hintColor : null));
    }
    if (t.isRepeating) out.add(Icon(AppIcons.repeat, size: 14, color: theme.hintColor));
    if (t.subtasks.isNotEmpty) {
      out.add(item(AppIcons.checklist, '${t.subtasks.where((s) => s.done).length}/${t.subtasks.length}'));
    }
    if ((t.description ?? '').trim().isNotEmpty) out.add(Icon(AppIcons.notes, size: 14, color: theme.hintColor));
    if (t.linkedEmailId != null) out.add(Icon(AppIcons.mail, size: 14, color: theme.hintColor));
    if (t.priority == TaskPriority.high || t.priority == TaskPriority.urgent) {
      out.add(const Icon(AppIcons.priority_high, size: 14, color: AppColors.errorRed));
    }
    for (final tag in t.tags.take(3)) {
      out.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.getTagColor(tag).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(tag, style: TextStyle(fontSize: 10.5, color: AppTheme.getTagColor(tag))),
      ));
    }
    return out;
  }
}

/// Содержимое карточки задачи по удержанию: название, срок и напоминание,
/// описание, подзадачи (до пяти), письмо, из которого задача.
class _TaskPeekCard extends StatelessWidget {
  final TaskModel task;
  final AppLocalizations l10n;
  const _TaskPeekCard({required this.task, required this.l10n});

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

/// Строка быстрого добавления: разбор на лету («завтра в 15:00» → чипы
/// срока и напоминания), Enter — добавить, ⋯ — открыть полную карточку.
class _QuickAddBar extends StatefulWidget {
  final TaskList list;
  final Future<void> Function(String text) onAdd;
  final void Function(ParsedTask draft) onOpenEditor;
  const _QuickAddBar({required this.list, required this.onAdd, required this.onOpenEditor});

  @override
  State<_QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<_QuickAddBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  ParsedTask? _parsed;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    _ctrl.clear();
    setState(() => _parsed = null);
    await widget.onAdd(v);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = l10n.localeCode;
    final p = _parsed;
    String fmt(DateTime d) => (d.hour == 0 && d.minute == 0)
        ? DateFormat('EEE, d MMM', locale).format(d)
        : DateFormat('EEE, d MMM, HH:mm', locale).format(d);

    // Плоская строка с тонкой линией сверху, цвета страницы — как нижние
    // панели «воздушного» вида (замечание владельца 27.10.2026: «окно задач
    // тоже нужно к общему UI привести»); в высоком контрасте — с тенью.
    final outlined = OgnelissLook.of(context).outlined;
    return Material(
      elevation: outlined ? 3 : 0,
      color: outlined ? theme.colorScheme.surfaceContainer : theme.scaffoldBackgroundColor,
      shape: outlined ? null : Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(left: Space.s, right: Space.s, top: 6, bottom: 6 + MediaQuery.of(context).viewInsets.bottom * 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p != null && p.hasExtras)
                Padding(
                  padding: const EdgeInsets.only(left: 44, bottom: Space.xs),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (p.due != null)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(AppIcons.event, size: 16),
                          label: Text(fmt(p.due!)),
                        ),
                      if (p.reminder != null && p.reminder != p.due)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(AppIcons.notifications, size: 16),
                          label: Text(fmt(p.reminder!)),
                        ),
                      if (p.important)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(AppIcons.star, size: 16, fill: 1, color: AppColors.brandAmber),
                          label: Text('!'),
                        ),
                      if (p.repeat != TaskRepeat.none)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Icon(AppIcons.repeat, size: 16),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.tr('taskDetails'),
                    icon: const Icon(AppIcons.add_task),
                    onPressed: () {
                      final draft = _ctrl.text.trim().isEmpty
                          ? const ParsedTask(title: '')
                          : TaskQuickParser.parse(_ctrl.text);
                      _ctrl.clear();
                      setState(() => _parsed = null);
                      widget.onOpenEditor(draft);
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: l10n.tr('quickAddHint'),
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _parsed = v.trim().isEmpty ? null : TaskQuickParser.parse(v)),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: l10n.tr('add'),
                    onPressed: _submit,
                    icon: const Icon(AppIcons.arrow_upward),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

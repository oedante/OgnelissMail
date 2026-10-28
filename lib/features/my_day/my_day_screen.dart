// lib/features/my_day/my_day_screen.dart
// «Мой день» (отключаемый раздел) — сводка на сегодня одним взглядом
// (09.10.2026, по замечанию владельца: не ссылки, а что предстоит):
//   · «Сейчас»: текущее время, идущая встреча, следующая — через сколько,
//     итог дня (встречи впереди, задачи, письма в работе, непрочитанные);
//   · расписание: встречи, задачи и напоминания по времени — «Весь день»,
//     «Утро», «День», «Вечер». Прошедшее не показывается: экран следит за
//     временем и раз в полминуты убирает закончившееся. Невыполненные
//     задачи с прошедшим сроком — отдельной группой сверху;
//   · письма в работе: «На контроле», «Позже» (вернувшиеся и сегодняшние),
//     приглашения без ответа;
//   · от VIP: непрочитанные и сегодняшние письма VIP-отправителей;
//   · «Продолжить»: недописанные черновики и вчерашние открытые письма
//     без ответа — убрано 10.10.2026 (не помогало), вместо него «Отложенные»;
//   · непрочитанные во «Входящих» — одной строкой со счётчиком.
// Мини-секретарь (10.10.2026): под «Сейчас» — итог дня плитками (встречи и
// их время, ближайшее свободное окно в рабочих часах, задачи «N из M»,
// почта за сегодня); пересечения встреч помечены; перед встречей — «К
// встрече: N писем»; вечером — с чего начнётся завтра. «Исполнено» из «На
// контроле» — одной строкой с «Снять отметки». Расчёты — day_stats.dart.
// Только данные из телефона, без запросов к серверу.
// Второй вид — доска (канбан, my_day_board.dart): «Предстоит», «В работе»,
// «Готово»; переключатель в заголовке, выбор запоминается.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/calendar/pending_invites.dart' show loadPendingInvites;
import '../../core/navigation/app_router.dart' show eventDetailsPath, mailDetailPath;
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart' show EmailMeeting;
import '../../data/models/folder_model.dart' show FolderType;
import '../../data/models/task_model.dart' show taskFromRow, TaskStatus;
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/home_widget_service.dart';
import '../../services/calendar/meeting_prep.dart' show meetingPrepProvider;
import '../../services/sync/sync_schedule.dart';
import '../../services/mail/control_service.dart';
import '../../services/mail/own_addresses.dart';
import '../../services/mail/focus_mode_service.dart';
import '../../services/mail/later_service.dart';
import '../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../mail/widgets/later_sheet.dart' show laterWhenLabel;
import '../../services/tasks/task_actions_service.dart' show tasksRevisionProvider, taskActionsProvider;
import '../../widgets/common/adaptive_layout.dart' show Breakpoints;
import '../../widgets/common/text_scale_cap.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/settings_group.dart';
import '../../widgets/ui/section_band.dart';
import '../calendar/calendar_data.dart';
import '../mail/providers/mail_providers.dart';
import '../mail/widgets/control_sheet.dart' show controlDeadlineLabel;
import '../settings/providers/settings_provider.dart';
import '../tasks/widgets/task_editor_sheet.dart' show showTaskEditor;

import 'day_stats.dart';
import '../../core/theme/ogneliss_look.dart';

part 'my_day_board.dart';

class _MyDayData {
  final List<CalendarEvent> events;
  final List<Task> tasks;
  /// Доска: задачи «в работе» (любой срок) и выполненные сегодня.
  final List<Task> inProgress;
  final List<Task> doneToday;
  final List<Email> control;
  final List<Email> invites;
  /// «Позже»: вернувшиеся и со сроком сегодня; [laterTotal] — всего отложено.
  final List<Email> later;
  final int laterTotal;
  final List<Email> vip;
  final int unreadTotal;
  /// «Отложенные» (10.10.2026, вместо «Продолжить»): письма «Позже», которые
  /// ещё не вернулись, и отложенная отправка — ближайшие по времени.
  final List<_Deferred> deferred;
  /// Завтрашние встречи (для вечернего «Завтра первая встреча в …»).
  final List<CalendarEvent> tomorrow;
  /// Почта за сегодня: пришло во «Входящие» и отправлено.
  final int receivedToday;
  final int sentToday;
  const _MyDayData({
    this.events = const [],
    this.tasks = const [],
    this.inProgress = const [],
    this.doneToday = const [],
    this.control = const [],
    this.invites = const [],
    this.later = const [],
    this.laterTotal = 0,
    this.vip = const [],
    this.unreadTotal = 0,
    this.deferred = const [],
    this.tomorrow = const [],
    this.receivedToday = 0,
    this.sentToday = 0,
  });

}

/// Отложенное: письмо «Позже» (вернётся во «Входящие») или письмо с
/// отложенной отправкой (уйдёт само).
class _Deferred {
  final DateTime at;
  final String subject;
  final String who;
  final Email? mail; // «Позже»
  final int? queueId; // отложенная отправка (строка очереди)
  const _Deferred({required this.at, required this.subject, required this.who, this.mail, this.queueId});
  bool get outgoing => queueId != null;
}

/// Любое изменение писем (прочитано, перемещено, новое) — пересчёт «Моего
/// дня» не чаще раза в секунду. Раньше прочитанное письмо оставалось в
/// списке до перезахода на экран.
final _myDayMailTickProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  var n = 0;
  Timer? t;
  final c = StreamController<int>();
  final sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.emails, db.tasks, db.calendarEvents])).listen((_) {
    t?.cancel();
    t = Timer(const Duration(seconds: 1), () => c.add(++n));
  });
  ref.onDispose(() {
    t?.cancel();
    sub.cancel();
    c.close();
  });
  return c.stream;
});

final _myDayProvider = FutureProvider.autoDispose<_MyDayData>((ref) async {
  ref.watch(_myDayMailTickProvider);
  ref.watch(controlRevisionProvider);
  ref.watch(laterRevisionProvider);
  ref.watch(tasksRevisionProvider);
  final db = ref.watch(databaseProvider);
  final ids = [for (final a in ref.watch(accountsProvider)) a.id];
  final showControl = ref.watch(settingsProvider.select((s) => s.mailControl));
  final vipList = [for (final v in ref.watch(focusModeProvider.select((s) => s.vipEmails))) v.toLowerCase()];
  if (ids.isEmpty) return const _MyDayData();
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));

  final events = await (db.select(db.calendarEvents)
        ..where((e) => e.accountId.isIn(ids))
        ..where((e) => e.isCancelled.equals(false))
        ..where((e) => e.startTime.isSmallerThanValue(end))
        ..where((e) => e.endTime.isBiggerThanValue(start))
        ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
      .get();

  // Задачи со сроком или напоминанием до конца дня, невыполненные.
  final tasks = await (db.select(db.tasks)
        ..where((t) => t.accountId.isIn(ids))
        ..where((t) =>
            (t.dueDate.isNotNull() & t.dueDate.isSmallerThanValue(end)) |
            (t.reminderAt.isNotNull() & t.reminderAt.isSmallerThanValue(end)))
        ..where((t) => t.status.isNotIn(const [2, 3]))
        ..limit(100))
      .get();

  // Для доски: «в работе» с любым сроком и выполненные сегодня.
  final inProgress = await (db.select(db.tasks)
        ..where((t) => t.accountId.isIn(ids))
        ..where((t) => t.status.equals(TaskStatus.inProgress.index))
        ..limit(50))
      .get();
  final doneToday = await (db.select(db.tasks)
        ..where((t) => t.accountId.isIn(ids))
        ..where((t) => t.status.equals(TaskStatus.completed.index))
        ..where((t) => t.completedAt.isBiggerOrEqualValue(start))
        ..orderBy([(t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc)])
        ..limit(50))
      .get();

  // Сначала те, что ещё ждут, затем «Исполнено» (их снимает пользователь).
  final controlled = showControl ? await db.controlledEmails(accountIds: ids) : const <Email>[];
  final control = [
    ...controlled.where((m) => m.controlState != ControlState.done),
    ...controlled.where((m) => m.controlState == ControlState.done),
  ];

  // «Посмотреть позже»: вернувшиеся и те, что вернутся сегодня.
  final allLater = await db.laterEmails(accountIds: ids);
  final later = [
    for (final m in allLater)
      if (m.laterState == LaterState.returned || (m.remindAt != null && m.remindAt!.isBefore(end))) m,
  ];

  final inboxIds = await (db.selectOnly(db.folders)
        ..addColumns([db.folders.id])
        ..where(db.folders.accountId.isIn(ids) & db.folders.type.equals(FolderType.inbox.index)))
      .map((r) => r.read(db.folders.id)!)
      .get();

  // Приглашения без ответа — на любой день, не только сегодня (общий
  // запрос с календарём, 1.6.33).
  final invites = await loadPendingInvites(db, ids, now: now);

  // От VIP: только непрочитанные во «Входящих». Прочитанное письмо уходит из
  // списка (раньше оставались и прочитанные сегодняшние, 10.10.2026).
  final vip = inboxIds.isEmpty || vipList.isEmpty
      ? const <Email>[]
      : await (db.select(db.emails)
            ..where((e) => e.accountId.isIn(ids))
            ..where((e) => e.folderId.isIn(inboxIds))
            ..where((e) => e.fromEmail.lower().isIn(vipList))
            ..where((e) => e.isRead.equals(false))
            ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
            ..limit(5))
          .get();

  // Непрочитанные во «Входящих» — только число (сами письма — в ленте).
  var unreadTotal = 0;
  if (inboxIds.isNotEmpty) {
    unreadTotal = await (db.selectOnly(db.emails)
          ..addColumns([db.emails.id.count()])
          ..where(db.emails.accountId.isIn(ids) & db.emails.folderId.isIn(inboxIds) & db.emails.isRead.equals(false)))
        .map((r) => r.read(db.emails.id.count()) ?? 0)
        .getSingle();
  }

  // «Отложенные»: письма «Позже», которые ещё вернутся, и отложенная
  // отправка — пять ближайших по времени (заменили «Продолжить», 10.10.2026).
  final deferred = <_Deferred>[
    for (final m in allLater)
      if (m.laterState == LaterState.waiting && m.remindAt != null && m.remindAt!.isAfter(now))
        _Deferred(
          at: m.remindAt!.toLocal(),
          subject: m.subject,
          who: (m.fromName ?? '').trim().isNotEmpty ? m.fromName!.trim() : m.fromEmail,
          mail: m,
        ),
  ];
  final scheduled = await (db.select(db.syncQueue)
        ..where((q) => q.accountId.isIn(ids) & q.operationType.equals('send_email') & q.targetId.like('scheduled_%'))
        ..limit(20))
      .get();
  for (final q in scheduled) {
    try {
      final p = jsonDecode(q.payloadJson) as Map<String, dynamic>;
      final at = DateTime.tryParse(p['scheduledAt'] as String? ?? '');
      if (at == null) continue;
      final to = (p['to'] as List? ?? const []).whereType<Map>().toList();
      final first = to.isEmpty ? '' : ((to.first['displayName'] as String?)?.trim().isNotEmpty == true
          ? to.first['displayName'] as String
          : (to.first['email'] as String? ?? ''));
      deferred.add(_Deferred(
        at: at.toLocal(),
        subject: p['subject'] as String? ?? '',
        who: to.length > 1 ? '$first +${to.length - 1}' : first,
        queueId: q.id,
      ));
    } catch (_) {}
  }
  deferred.sort((x, y) => x.at.compareTo(y.at));

  // Завтра: встречи (вечером «Моего дня» — с чего начнётся завтра).
  final tomorrow = await (db.select(db.calendarEvents)
        ..where((e) => e.accountId.isIn(ids))
        ..where((e) => e.isCancelled.equals(false))
        ..where((e) => e.startTime.isBiggerOrEqualValue(end))
        ..where((e) => e.startTime.isSmallerThanValue(end.add(const Duration(days: 1))))
        ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
        ..limit(30))
      .get();

  // Почта за сегодня: пришло во «Входящие», отправлено (по папкам «Отправленные»).
  Future<int> countSince(List<String> folders) async => folders.isEmpty
      ? 0
      : await (db.selectOnly(db.emails)
            ..addColumns([db.emails.id.count()])
            ..where(db.emails.accountId.isIn(ids) &
                db.emails.folderId.isIn(folders) &
                db.emails.receivedAt.isBiggerOrEqualValue(start)))
          .map((r) => r.read(db.emails.id.count()) ?? 0)
          .getSingle();
  final sentIds = await (db.selectOnly(db.folders)
        ..addColumns([db.folders.id])
        ..where(db.folders.accountId.isIn(ids) & db.folders.type.equals(FolderType.sent.index)))
      .map((r) => r.read(db.folders.id)!)
      .get();
  final receivedToday = await countSince(inboxIds);
  final sentToday = await countSince(sentIds);

  return _MyDayData(
    tomorrow: tomorrow,
    receivedToday: receivedToday,
    sentToday: sentToday,
    deferred: deferred,
    events: events,
    tasks: tasks,
    inProgress: inProgress,
    doneToday: doneToday,
    control: control,
    invites: invites,
    later: later,
    laterTotal: allLater.length,
    vip: vip,
    unreadTotal: unreadTotal,
  );
});

/// Пункт расписания: встреча, задача или письмо, которое вернётся («Позже»).
class _Slot {
  final DateTime? at; // null — «весь день» / без времени
  final DateTime? until;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool live;
  final VoidCallback onTap;
  final Widget? trailing;
  /// Встреча (для «К встрече» в карточке «Сейчас»).
  final CalendarEvent? event;
  /// «Пересекается: …» — встреча накладывается на другую.
  final String? conflict;
  const _Slot({
    required this.at,
    this.until,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    this.live = false,
    required this.onTap,
    this.trailing,
    this.event,
    this.conflict,
  });
}

class MyDayScreen extends ConsumerStatefulWidget {
  const MyDayScreen({super.key});

  @override
  ConsumerState<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends ConsumerState<MyDayScreen> {
  Timer? _tick;
  int _ticks = 0;

  /// Вид «доска» (канбан) — запоминается.
  late bool _board = ref.read(sharedPrefsProvider).getBool('myday_board') ?? false;

  /// Доска на телефоне: панели, раскрытые целиком («Показать все»).
  final Set<_Col> _boardExpanded = {};
  void _toggleBoardExpanded(_Col c) =>
      setState(() => _boardExpanded.contains(c) ? _boardExpanded.remove(c) : _boardExpanded.add(c));

  void _setBoard(bool v) {
    setState(() => _board = v);
    final container = ProviderScope.containerOf(context, listen: false);
    unawaited(() async {
      await ref.read(sharedPrefsProvider).setBool('myday_board', v);
      // Виджет «Мой день» показывает тот же вид — доску или список.
      await HomeWidgetService.updateFromContainer(container, force: true);
    }());
  }


  /// Доска: переносы задач, ещё не дошедшие до базы (ключ карточки → колонка),
  /// и карточка, которую сейчас тянут.
  final Map<String, _Col> _boardMoves = {};
  String? _boardDragging;
  void _markBoardMove(String key, _Col to) => setState(() => _boardMoves[key] = to);
  void _setBoardDragging(String? key) {
    if (_boardDragging != key && mounted) setState(() => _boardDragging = key);
  }

  /// Список: задачи, отмеченные выполненными, — скрыты сразу, не дожидаясь
  /// перечитывания базы (экран больше не «дёргается»).
  final Set<String> _doneLocal = {};

  @override
  void initState() {
    super.initState();
    // Экран следит за временем: раз в 30 с — «сейчас», закончившиеся встречи
    // уходят; раз в 2 мин — перечитать данные (новые письма, синхронизация).
    // Изменения базы (письма, задачи, встречи) экран и так получает через
    // _myDayMailTickProvider; полное перечитывание по таймеру — только для
    // смены суток и подобного, раз в 10 минут (было раз в 2 минуты). Свёрнутое
    // приложение экран не перестраивает (аудит 11.10.2026).
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      _ticks++;
      if (_ticks % 20 == 0) ref.invalidate(_myDayProvider);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final data = ref.watch(_myDayProvider);
    final now = DateTime.now();
    final title = DateFormat('EEEE, d MMMM', l10n.localeCode).format(now);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('myDay')),
            Text(capitalize(title), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.tr(_board ? 'myDayViewList' : 'myDayViewBoard'),
            icon: Icon(_board ? AppIcons.view_agenda : AppIcons.view_column),
            onPressed: () => _setBoard(!_board),
          ),
        ],
      )),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_myDayProvider),
        // На доске списки — внутри листаемых вбок колонок: обновление
        // жестом вниз из любой колонки.
        notificationPredicate: _board
            ? (n) => n.metrics.axis == Axis.vertical
            : defaultScrollNotificationPredicate,
        // Перечитывание (новая задача, отметка «выполнено», синхронизация)
        // идёт под старыми данными: раньше на это время экран сменялся
        // кругом загрузки и «дёргался», прокрутка сбрасывалась.
        child: data.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          // Ошибка чтения базы — без всплывающих окон, просто пустой экран.
          error: (e, _) => ListView(children: const [SizedBox(height: Space.xxl)]),
          data: (d) => _board ? _boardBody(context, d, now, l10n) : _body(context, d, now, l10n),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final slots = _slots(context, d, now, l10n);
    final overdue = _overdueTasks(context, d, now, l10n);
    final work = _workItems(context, d, l10n);
    final nothing = slots.isEmpty && overdue.isEmpty && work.isEmpty && d.vip.isEmpty && d.unreadTotal == 0 &&
        d.deferred.isEmpty;
    if (nothing) {
      return EmptyState(
        icon: AppIcons.wb_sunny,
        title: l10n.tr('myDayClear'),
        message: l10n.tr('myDayEmptyHint'),
        scrollable: true,
      );
    }
    // Расписание по частям дня.
    final allDay = [for (final s in slots) if (s.at == null) s];
    final timed = [for (final s in slots) if (s.at != null) s]..sort((a, b) => a.at!.compareTo(b.at!));
    List<_Slot> part(int fromH, int toH) =>
        [for (final s in timed) if (s.at!.hour >= fromH && s.at!.hour < toH) s];
    final morning = part(0, 12), day = part(12, 17), evening = part(17, 24);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
      children: [
        _nowCard(context, d, timed, now, l10n),
        _statsGrid(context, d, now, l10n),
        if (overdue.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayOverdue')),
          SettingsGroup(children: overdue),
        ],
        if (allDay.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayAllDay')),
          SettingsGroup(children: [for (final s in allDay) _slotTile(context, s, l10n)]),
        ],
        if (morning.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayMorning')),
          SettingsGroup(children: [for (final s in morning) _slotTile(context, s, l10n)]),
        ],
        if (day.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayAfternoon')),
          SettingsGroup(children: [for (final s in day) _slotTile(context, s, l10n)]),
        ],
        if (evening.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayEvening')),
          SettingsGroup(children: [for (final s in evening) _slotTile(context, s, l10n)]),
        ],
        if (work.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayInWork')),
          SettingsGroup(children: work),
        ],
        if (d.deferred.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayDeferred'), help: l10n.tr('myDayDeferredHelp')),
          SettingsGroup(children: [
            for (final x in d.deferred.take(5)) _deferredTile(context, x, l10n),
            if (d.laterTotal > 0)
              ListTile(
                leading: const Icon(AppIcons.watch_later),
                title: Text(l10n.tr('laterAll').replaceAll('{n}', '${d.laterTotal}')),
                trailing: const Icon(AppIcons.chevron_right),
                onTap: () => _openMailFilter(MailFilter.later),
              ),
          ]),
        ],
        if (d.vip.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('myDayVip')),
          SettingsGroup(children: [for (final m in d.vip) _mailTile(context, m, l10n, vip: true)]),
        ],
        // Непрочитанные — одной строкой: «Мой день» не дублирует ленту писем
        // (раньше здесь были ещё пять последних писем).
        if (d.unreadTotal > 0) ...[
          const SizedBox(height: Space.m),
          SettingsGroup(children: [
            ListTile(
              leading: const Icon(AppIcons.mark_email_unread),
              title: Text(l10n.tr('myDayUnreadAll').replaceAll('{n}', '${d.unreadTotal}')),
              trailing: const Icon(AppIcons.chevron_right),
              onTap: () => _openMailFilter(MailFilter.unread),
            ),
          ]),
        ],
      ],
    );
  }

  // ── «Сейчас» ──

  Widget _nowCard(BuildContext context, _MyDayData d, List<_Slot> timed, DateTime now, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final t = DateFormat('HH:mm');
    final live = timed.where((s) => s.live).toList();
    final next = timed.where((s) => s.at!.isAfter(now)).firstOrNull;
    final inWork = d.control.where((m) => m.controlState != ControlState.done).length + d.later.length;
    // Одна фраза-итог под часами: что ещё осталось сделать сегодня.
    final remainingTasks = d.tasks.length;
    final counts = [
      if (remainingTasks > 0) l10n.plural('digestTasksN', remainingTasks),
      if (inWork > 0) l10n.tr('myDayInWorkCount').replaceAll('{n}', '$inWork'),
    ];
    // «К встрече»: ближайшая (или идущая) встреча в пределах двух часов.
    final soon = [...live, if (next != null) next]
        .where((x) => x.event != null && x.at!.difference(now) <= const Duration(hours: 2))
        .firstOrNull;
    final prepCount = soon == null ? 0 : (ref.watch(meetingPrepProvider(soon.event!)).value?.mails.length ?? 0);
    // Вечером или когда встреч больше нет — с чего начнётся завтра.
    final tomorrowTimed = [for (final e in d.tomorrow) if (!e.isAllDay && e.showAs != 0) e];
    final showTomorrow = now.hour >= 16 || (next == null && live.isEmpty);
    return Container(
      margin: const EdgeInsets.only(top: Space.s, bottom: Space.xs),
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: Radii.cardAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t.format(now), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              counts.isNotEmpty
                  ? counts.join(' · ')
                  : (next == null && live.isEmpty ? l10n.tr('myDayNothingAhead') : ''),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context)),
            ),
          ),
        ]),
        const SizedBox(height: Space.s),
        for (final s in live)
          _nowLine(context, AppIcons.play_circle, AppColors.successText(context),
              '${l10n.tr('myDayNowLabel')}: ${s.title}',
              s.until == null ? null : l10n.tr('myDayUntil').replaceAll('{time}', t.format(s.until!))),
        if (next != null)
          _nowLine(context, AppIcons.schedule, theme.colorScheme.primary,
              '${t.format(next.at!)} — ${next.title}', l10n.tr('myDayIn').replaceAll('{d}', _left(next.at!.difference(now), l10n)))
        else if (live.isEmpty)
          _nowLine(context, AppIcons.event_available, AppColors.mutedText(context), l10n.tr('myDayNoMore'), null),
        if (soon != null && prepCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: Icon(AppIcons.groups, size: 16, color: theme.colorScheme.primary),
                label: Text(l10n.tr('myDayPrepChip').replaceAll('{n}', '$prepCount')),
                onPressed: () => context.push(eventDetailsPath(soon.event!.id, accountId: soon.event!.accountId)),
              ),
            ),
          ),
        if (showTomorrow)
          _nowLine(
            context,
            AppIcons.event_upcoming,
            AppColors.mutedText(context),
            tomorrowTimed.isEmpty
                ? l10n.tr('myDayTomorrowFree')
                : l10n
                    .tr('myDayTomorrowFirst')
                    .replaceAll('{time}', t.format(tomorrowTimed.first.startTime.toLocal()))
                    .replaceAll('{title}',
                        tomorrowTimed.first.title.trim().isEmpty ? l10n.tr('noSubject') : tomorrowTimed.first.title.trim()),
            tomorrowTimed.length > 1 ? l10n.plural('digestEventsN', tomorrowTimed.length) : null,
          ),
      ]),
    );
  }

  // ── Итог дня: встречи, свободное окно, задачи, почта ──

  Widget _statsGrid(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final t = DateFormat('HH:mm');
    final today = DateTime(now.year, now.month, now.day);
    final meetings = [
      for (final e in d.events)
        if (!e.isAllDay)
          DayMeeting(id: e.id, title: e.title, start: e.startTime.toLocal(), end: e.endTime.toLocal(), free: e.showAs == 0),
    ];
    final busy = DayStats.busy(meetings, dayStart: today, dayEnd: today.add(const Duration(days: 1)));
    final busyCount = meetings.where((m) => !m.free).length;
    final left = meetings.where((m) => !m.free && m.end.isAfter(now)).length;
    final work = DayStats.workHours(now, SyncSchedule.startMinutes, SyncSchedule.endMinutes);
    final from = now.isAfter(work.start) ? now : work.start;
    final free = DayStats.nextFree(busy, from: from, until: work.end);
    // Задачи на сегодня: выполнено сегодня из (выполнено + осталось).
    final done = d.doneToday.length;
    final total = done + d.tasks.length;

    final tiles = [
      _StatTile(
        icon: AppIcons.event,
        label: l10n.tr('dayStatMeetings'),
        value: busyCount == 0 ? l10n.tr('dayStatNoMeetings') : '$busyCount · ${_left(DayStats.meetingTime(busy), l10n)}',
        sub: busyCount == 0 ? null : l10n.tr('dayStatMeetingsLeft').replaceAll('{n}', '$left'),
        onTap: () => context.go('/calendar'),
      ),
      _StatTile(
        icon: AppIcons.event_available,
        label: l10n.tr('dayStatFree'),
        value: !now.isBefore(work.end)
            ? l10n.tr('dayStatWorkOver')
            : (free == null ? l10n.tr('dayStatFreeNone') : '${t.format(free.start)}–${t.format(free.end)}'),
        sub: !now.isBefore(work.end) || free == null
            ? l10n.tr('dayStatWorkHours').replaceAll('{range}', '${t.format(work.start)}–${t.format(work.end)}')
            : l10n.tr('dayStatFreeNext'),
        onTap: () => context.go('/calendar'),
      ),
      _StatTile(
        icon: AppIcons.task_alt,
        label: l10n.tr('dayStatTasks'),
        value: total == 0
            ? l10n.tr('dayStatNoTasks')
            : l10n.tr('dayStatTasksValue').replaceAll('{done}', '$done').replaceAll('{total}', '$total'),
        progress: total == 0 ? null : done / total,
        onTap: () => context.go('/tasks'),
      ),
      _StatTile(
        icon: AppIcons.mail,
        label: l10n.tr('dayStatMail'),
        value: l10n.tr('dayStatMailValue').replaceAll('{n}', '${d.receivedToday}'),
        sub: l10n
            .tr('dayStatMailSub')
            .replaceAll('{s}', '${d.sentToday}')
            .replaceAll('{u}', '${d.unreadTotal}'),
        onTap: () => _openMailFilter(d.unreadTotal > 0 ? MailFilter.unread : MailFilter.none),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Space.s),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: Space.s),
              Expanded(child: tiles[i + 1]),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _nowLine(BuildContext context, IconData icon, Color color, String text, String? tail) => Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Row(children: [
          Icon(icon, size: Sizes.iconInline, color: color),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (tail != null) ...[
            const SizedBox(width: Space.s),
            Text(tail, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ],
        ]),
      );

  static String _left(Duration d, AppLocalizations l10n) {
    final m = d.inMinutes.clamp(0, 24 * 60);
    if (m < 60) return l10n.tr('myDayMinutes').replaceAll('{m}', '$m');
    return l10n.tr('myDayHours').replaceAll('{h}', '${m ~/ 60}').replaceAll('{m}', '${m % 60}');
  }

  // ── Расписание ──

  List<_Slot> _slots(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    final out = <_Slot>[];
    // Пересечения встреч сегодня (обе «занят») — секретарь предупредил бы.
    final clashes = DayStats.conflicts([
      for (final e in d.events)
        if (!e.isAllDay) DayMeeting(id: e.id, title: e.title, start: e.startTime.toLocal(), end: e.endTime.toLocal(), free: e.showAs == 0),
    ]);
    for (final e in d.events) {
      final s = e.startTime.toLocal(), en = e.endTime.toLocal();
      if (!e.isAllDay && !en.isAfter(now)) continue; // прошло — не показываем
      final color = e.colorValue != null ? Color(e.colorValue!) : scheme.primary;
      out.add(_Slot(
        at: e.isAllDay ? null : (s.isBefore(today) ? today : s),
        until: e.isAllDay ? null : en,
        title: e.title.trim().isEmpty ? l10n.tr('noSubject') : e.title,
        subtitle: [
          if (!e.isAllDay) '${DateFormat('HH:mm').format(s)}–${DateFormat('HH:mm').format(en)}',
          if ((e.location ?? '').trim().isNotEmpty) e.location!.trim(),
        ].join(' · '),
        icon: (e.onlineMeetingUrl ?? '').isNotEmpty ? AppIcons.videocam : AppIcons.event,
        color: color,
        live: !e.isAllDay && !s.isAfter(now) && en.isAfter(now),
        onTap: () => context.push(eventDetailsPath(e.id, accountId: e.accountId)),
        event: e,
        conflict: clashes[e.id] == null
            ? null
            : l10n.tr('myDayConflict').replaceAll('{names}', clashes[e.id]!.map((t) => t.trim().isEmpty ? l10n.tr('noSubject') : t).join(', ')),
      ));
    }
    // Задачи на сегодня: со временем — по времени, без времени — «весь день».
    // Прошедшие и невыполненные — в группе «Не выполнено» (_overdueTasks).
    for (final t in d.tasks) {
      if (_doneLocal.contains('${t.accountId}|${t.id}')) continue; // только что выполнена
      final when = _taskTime(t);
      if (when == null) continue;
      final hasTime = when.hour != 0 || when.minute != 0;
      final day = DateTime(when.year, when.month, when.day);
      if (day.isBefore(today) || (hasTime && when.isBefore(now))) continue;
      out.add(_Slot(
        at: hasTime ? when : null,
        title: t.title,
        subtitle: l10n.tr('myDayTask'),
        icon: AppIcons.task_alt,
        color: scheme.primary,
        onTap: () => showTaskEditor(context, task: taskFromRow(t), accountId: t.accountId),
        trailing: _doneButton(t, l10n),
      ));
    }
    // «Позже», которые вернутся сегодня, — напоминание в расписании.
    for (final m in d.later) {
      final at = m.remindAt?.toLocal();
      if (m.laterState != LaterState.waiting || at == null || !at.isAfter(now)) continue;
      out.add(_Slot(
        at: at,
        title: _subjectOf(m, l10n),
        subtitle: '${l10n.tr('myDayLaterReturns')} · ${m.fromName ?? m.fromEmail}',
        icon: AppIcons.watch_later,
        color: const Color(0xFF7B61B8),
        onTap: () => context.push(mailDetailPath(m.id, accountId: m.accountId)),
      ));
    }
    return out;
  }

  static DateTime? _taskTime(Task t) => (t.reminderAt ?? t.dueDate)?.toLocal();

  List<Widget> _overdueTasks(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final today = DateTime(now.year, now.month, now.day);
    final list = <Task>[];
    for (final t in d.tasks) {
      if (_doneLocal.contains('${t.accountId}|${t.id}')) continue; // только что выполнена
      final when = _taskTime(t);
      if (when == null) continue;
      final hasTime = when.hour != 0 || when.minute != 0;
      final day = DateTime(when.year, when.month, when.day);
      if (day.isBefore(today) || (hasTime && when.isBefore(now))) list.add(t);
    }
    list.sort((a, b) => _taskTime(a)!.compareTo(_taskTime(b)!));
    return [
      // Просроченные не прячутся (замечание 09.10.2026): все, до 30.
      for (final t in list.take(30))
        ListTile(
          leading: Icon(AppIcons.task_alt, color: AppColors.errorText(context)),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_whenShort(_taskTime(t)!, now, l10n),
              style: TextStyle(color: AppColors.errorText(context))),
          trailing: _doneButton(t, l10n),
          onTap: () => showTaskEditor(context, task: taskFromRow(t), accountId: t.accountId),
        ),
    ];
  }

  static String _whenShort(DateTime at, DateTime now, AppLocalizations l10n) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final hasTime = at.hour != 0 || at.minute != 0;
    final time = hasTime ? DateFormat('HH:mm').format(at) : '';
    if (day == today) return '${l10n.tr('today')}${time.isEmpty ? '' : ', $time'}';
    return '${DateFormat('d MMM', l10n.localeCode).format(at)}${time.isEmpty ? '' : ', $time'}';
  }

  Widget _doneButton(Task t, AppLocalizations l10n) => IconButton(
        tooltip: l10n.tr('ntfTaskDone'),
        icon: const Icon(AppIcons.radio_button_unchecked),
        onPressed: () async {
          unawaited(HapticFeedback.selectionClick());
          setState(() => _doneLocal.add('${t.accountId}|${t.id}'));
          await ref.read(taskActionsProvider).setDone(t.accountId, t.id, true);
          if (mounted) ref.invalidate(_myDayProvider);
        },
      );

  Widget _slotTile(BuildContext context, _Slot s, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    return ListTile(
      onTap: s.onTap,
      leading: SizedBox(
        width: 52,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(s.at == null ? '—' : DateFormat('HH:mm').format(s.at!),
              style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600, color: s.live ? AppColors.successText(context) : null)),
          if (s.live)
            Text(l10n.tr('myDayNow'), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.successText(context))),
        ]),
      ),
      title: Row(children: [
        Icon(s.icon, size: Sizes.iconInline, color: s.color),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: s.live ? const TextStyle(fontWeight: FontWeight.w600) : null),
        ),
      ]),
      subtitle: (s.subtitle ?? '').isEmpty && s.conflict == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: Sizes.iconInline + Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((s.subtitle ?? '').isNotEmpty)
                  Text(s.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
                if (s.conflict != null)
                  Row(children: [
                    Icon(AppIcons.warning, size: 14, color: AppColors.warningText(context)),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(s.conflict!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.warningText(context))),
                    ),
                  ]),
              ]),
            ),
      trailing: s.trailing,
      tileColor: s.live ? AppColors.successGreen.withValues(alpha: 0.06) : null,
    );
  }

  // ── Письма в работе ──

  List<Widget> _workItems(BuildContext context, _MyDayData d, AppLocalizations l10n) => [
        for (final m in d.later)
          if (m.laterState == LaterState.returned) _laterTile(context, m, l10n),
        for (final m in d.control)
          if (m.controlState != ControlState.done) _controlTile(context, m, l10n),
        // «Исполнено» — одной строкой с кнопкой «Снять отметки», а не списком.
        if (d.control.any((m) => m.controlState == ControlState.done)) _controlDoneTile(context, d, l10n),
        for (final m in d.invites) _inviteTile(context, m, l10n),
      ];

  void _openMailFilter(MailFilter f) {
    ref.read(mailFilterProvider.notifier).state = f;
    ref.read(unifiedModeProvider.notifier).state = true;
    ref.read(selectedFolderIdProvider.notifier).state = null;
    context.go('/mail');
  }

  Widget _controlTile(BuildContext context, Email m, AppLocalizations l10n) {
    final done = m.controlState == ControlState.done;
    final label = l10n.tr(done
        ? 'controlDone'
        : (m.controlState == ControlState.awaitingReply ? 'controlAwaiting' : 'controlMustReply'));
    final model = emailModelFromRow(m);
    final who = m.controlState == ControlState.awaitingReply
        ? model.to.map((a) => a.label).take(2).join(', ')
        : (m.fromName ?? m.fromEmail);
    final acc = ref.read(accountsProvider).where((a) => a.id == m.accountId).firstOrNull;
    final me = acc == null ? '' : OwnAddresses.of(acc).join(',');
    final pr = ControlService.progress(
        state: m.controlState, to: ControlService.toRecipients(m.toRecipients, me), replied: m.controlReplied);
    final extra = [
      if (pr != null) l10n.tr('controlRepliedOf').replaceAll('{n}', '${pr.replied}').replaceAll('{total}', '${pr.total}'),
      if (!done && m.followUpAt != null)
        l10n.tr('controlUntil').replaceAll('{when}', controlDeadlineLabel(m.followUpAt!.toLocal(), l10n)),
    ];
    final overdue = !done && m.followUpAt != null && m.followUpAt!.isBefore(DateTime.now());
    return ListTile(
      leading: Icon(done ? AppIcons.bookmark_added : AppIcons.bookmark,
          fill: 1,
          color: done
              ? AppColors.successText(context)
              : (m.controlState == ControlState.mustReply ? AppColors.accentOrange : Theme.of(context).colorScheme.primary)),
      title: Text(_subjectOf(m, l10n),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([label, ...extra, who].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: overdue ? TextStyle(color: AppColors.errorText(context)) : null),
      trailing: done
          ? IconButton(
              tooltip: l10n.tr('controlClear'),
              icon: const Icon(AppIcons.close),
              onPressed: () async {
                await ref.read(databaseProvider).setControlState(m.id, m.accountId, ControlState.none);
                ref.read(emailsProvider.notifier).applyLocalFlags(m.id, controlState: ControlState.none);
                ref.read(controlRevisionProvider.notifier).state++;
              },
            )
          : null,
      onTap: () => context.push(mailDetailPath(m.id, accountId: m.accountId)),
    );
  }

  Widget _controlDoneTile(BuildContext context, _MyDayData d, AppLocalizations l10n) {
    final done = [for (final m in d.control) if (m.controlState == ControlState.done) m];
    return ListTile(
      leading: Icon(AppIcons.bookmark_added, fill: 1, color: AppColors.successText(context)),
      title: Text(l10n.tr('myDayControlDoneN').replaceAll('{n}', '${done.length}')),
      subtitle: Text(done.map((m) => _subjectOf(m, l10n)).take(2).join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: () async {
          final db = ref.read(databaseProvider);
          for (final m in done) {
            await db.setControlState(m.id, m.accountId, ControlState.none);
            ref.read(emailsProvider.notifier).applyLocalFlags(m.id, controlState: ControlState.none);
          }
          ref.read(controlRevisionProvider.notifier).state++;
        },
        child: Text(l10n.tr('controlClearAll')),
      ),
      onTap: () => _openMailFilter(MailFilter.control),
    );
  }

  Widget _inviteTile(BuildContext context, Email m, AppLocalizations l10n) {
    final meet = EmailMeeting.parse(m.meetingJson);
    final start = meet?.start;
    final when = start == null
        ? null
        : (meet!.allDay
            ? DateFormat('EEE, d MMM', l10n.localeCode).format(start)
            : DateFormat('EEE, d MMM, HH:mm', l10n.localeCode).format(start));
    return ListTile(
      leading: Icon(AppIcons.event_available, color: Theme.of(context).colorScheme.primary),
      title: Text(_subjectOf(m, l10n),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([l10n.tr('myDayInvite'), if (when != null) when, m.fromName ?? m.fromEmail].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => context.push(mailDetailPath(m.id, accountId: m.accountId)),
    );
  }

  Widget _laterTile(BuildContext context, Email m, AppLocalizations l10n) => ListTile(
        leading: Icon(AppIcons.watch_later, fill: 1, color: AppColors.accentOrangeText(context)),
        title: Text(_subjectOf(m, l10n),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${l10n.tr('laterReturned')} · ${m.fromName ?? m.fromEmail}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => context.push(mailDetailPath(m.id, accountId: m.accountId)),
      );

  /// Тема письма.
  String _subjectOf(Email m, AppLocalizations l10n) {
    return m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject.trim();
  }

  /// Отложенное: «Позже» — вернётся во «Входящие» (нажатие — письмо);
  /// отложенная отправка — уйдёт сама (кнопка — отменить отправку).
  Widget _deferredTile(BuildContext context, _Deferred x, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final when = laterWhenLabel(x.at, l10n);
    return ListTile(
      leading: Icon(x.outgoing ? AppIcons.schedule_send : AppIcons.watch_later,
          color: x.outgoing ? theme.colorScheme.primary : AppColors.accentOrange),
      title: Text(x.subject.trim().isEmpty ? l10n.tr('noSubject') : x.subject.trim(),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [
            l10n.tr(x.outgoing ? 'myDayDeferredSends' : 'myDayDeferredReturns').replaceAll('{when}', when),
            if (x.who.isNotEmpty) x.outgoing ? '${l10n.tr('to')}: ${x.who}' : x.who,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: x.outgoing
          ? IconButton(
              tooltip: l10n.tr('myDayDeferredCancel'),
              icon: const Icon(AppIcons.close),
              onPressed: () => _cancelScheduled(x, l10n),
            )
          : Text(when, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.mutedText(context))),
      onTap: x.mail == null ? null : () => context.push(mailDetailPath(x.mail!.id, accountId: x.mail!.accountId)),
    );
  }

  /// Отменить отложенную отправку: строка очереди удаляется (письмо не уйдёт).
  Future<void> _cancelScheduled(_Deferred x, AppLocalizations l10n) async {
    final ok = await confirmDestructive(context,
        title: l10n.tr('myDayDeferredCancelQ'),
        message: x.subject.trim().isEmpty ? l10n.tr('noSubject') : x.subject.trim(),
        action: l10n.tr('myDayDeferredCancel'));
    if (!ok || !mounted) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.syncQueue)..where((q) => q.id.equals(x.queueId!))).go();
    if (mounted) ref.invalidate(_myDayProvider);
  }

  Widget _mailTile(BuildContext context, Email m, AppLocalizations l10n, {bool vip = false}) {
    final theme = Theme.of(context);
    final at = m.receivedAt.toLocal();
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return ListTile(
      leading: Icon(vip ? AppIcons.star : AppIcons.mail,
          fill: vip ? 1 : 0, color: vip ? AppColors.brandAmber : theme.colorScheme.primary),
      title: Text(m.fromName?.trim().isNotEmpty == true ? m.fromName! : m.fromEmail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: m.isRead ? null : const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(_subjectOf(m, l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(sameDay ? DateFormat('HH:mm').format(at) : DateFormat('d MMM', l10n.localeCode).format(at),
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.mutedText(context))),
      onTap: () => context.push(mailDetailPath(m.id, accountId: m.accountId)),
    );
  }
}

/// Плитка «итога дня»: значок и подпись, значение, пояснение или полоска.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final double? progress;
  final VoidCallback onTap;

  const _StatTile({required this.icon, required this.label, required this.value, this.sub, this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    return Material(
      color: AppColors.cardFill(context),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: AppColors.cardSide(context, alpha: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(icon, size: Sizes.iconInline, color: theme.colorScheme.primary),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
              ),
            ]),
            const SizedBox(height: Space.xs),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (progress != null) ...[
              const SizedBox(height: Space.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress, minHeight: 4),
              ),
            ] else if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ]),
        ),
      ),
    );
  }
}

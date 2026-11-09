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
// Виды (решение владельца 09.11.2026): доска (канбан, my_day_board.dart) —
// по умолчанию, и шкала дня (my_day_timeline.dart); переключатель в
// заголовке, выбор запоминается. Прежний список убран.

import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/calendar/pending_invites.dart' show loadPendingInvites;
import '../../core/navigation/app_router.dart' show eventDetailsPath, mailOpenPath;
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart' show EmailMeeting;
import '../../data/models/task_model.dart' show taskFromRow, TaskStatus;
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/calendar/meeting_prep.dart' show meetingPrepProvider;
import '../../services/sync/sync_schedule.dart';
import '../../services/mail/control_service.dart';
import '../../services/mail/later_service.dart';
import '../../services/tasks/task_actions_service.dart' show tasksRevisionProvider, taskActionsProvider;
import '../../widgets/common/adaptive_layout.dart' show Breakpoints;
import '../../widgets/common/text_scale_cap.dart';
import '../../widgets/ui/section_band.dart';
import '../../widgets/ui/app_menu_button.dart';
import '../calendar/calendar_data.dart';
import '../mail/providers/mail_providers.dart';
import '../mail/widgets/control_sheet.dart' show controlDeadlineLabel;
import '../settings/providers/settings_provider.dart';
import '../tasks/widgets/task_editor_sheet.dart' show showTaskEditor;
import '../tasks/widgets/task_peek.dart' show showTaskPeek;
import '../../services/tasks/task_blocks.dart';
import '../../services/assignments/assignment_service.dart';
import '../assignments/assignment_widgets.dart';
import '../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../../widgets/common/inline_notice.dart' show showInlineNotice;

import 'day_stats.dart';
import 'flip_clock.dart';
import 'weather_view.dart';
import '../../services/weather/weather_service.dart' show weatherProvider;
import '../../core/theme/ogneliss_look.dart';

part 'my_day_board.dart';
part 'my_day_timeline.dart';

class _MyDayData {
  final List<CalendarEvent> events;
  final List<Task> tasks;
  /// Доска: задачи «в работе» (любой срок) и выполненные сегодня.
  final List<Task> inProgress;
  final List<Task> doneToday;
  final List<Email> control;
  final List<Email> invites;
  /// «Позже»: вернувшиеся и со сроком сегодня.
  final List<Email> later;
  /// Завтрашние встречи (для вечернего «Завтра первая встреча в …»).
  final List<CalendarEvent> tomorrow;
  const _MyDayData({
    this.events = const [],
    this.tasks = const [],
    this.inProgress = const [],
    this.doneToday = const [],
    this.control = const [],
    this.invites = const [],
    this.later = const [],
    this.tomorrow = const [],
  });

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

  // Приглашения без ответа — на любой день, не только сегодня (общий
  // запрос с календарём, 1.6.33).
  final invites = await loadPendingInvites(db, ids, now: now);

  // Завтра: встречи (вечером «Моего дня» — с чего начнётся завтра).
  final tomorrow = await (db.select(db.calendarEvents)
        ..where((e) => e.accountId.isIn(ids))
        ..where((e) => e.isCancelled.equals(false))
        ..where((e) => e.startTime.isBiggerOrEqualValue(end))
        ..where((e) => e.startTime.isSmallerThanValue(end.add(const Duration(days: 1))))
        ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
        ..limit(30))
      .get();

  return _MyDayData(
    tomorrow: tomorrow,
    events: events,
    tasks: tasks,
    inProgress: inProgress,
    doneToday: doneToday,
    control: control,
    invites: invites,
    later: later,
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

  /// Вид: доска (по умолчанию) или шкала — запоминается.
  static const _viewKey = 'myday_view';
  late bool _timeline = ref.read(sharedPrefsProvider).getString(_viewKey) == 'timeline';

  /// Шкала: прокрутка (первый показ — к «сейчас»), куда встанет задача.
  final ScrollController _tlScroll = ScrollController();
  bool _tlScrolled = false;
  final GlobalKey _tlKey = GlobalKey();
  final GlobalKey _tlViewKey = GlobalKey();
  double? _tlHover;
  void _setTlHover(double? h) {
    if (_tlHover != h && mounted) setState(() => _tlHover = h);
  }

  /// Доска на телефоне: панели, раскрытые целиком («Показать все»).
  final Set<_Col> _boardExpanded = {};
  void _toggleBoardExpanded(_Col c) =>
      setState(() => _boardExpanded.contains(c) ? _boardExpanded.remove(c) : _boardExpanded.add(c));

  void _setTimeline(bool v) {
    setState(() {
      _timeline = v;
      _tlScrolled = false;
    });
    unawaited(ref.read(sharedPrefsProvider).setString(_viewKey, v ? 'timeline' : 'board'));
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
      if (_ticks % 20 == 0) {
        ref.invalidate(_myDayProvider);
        // Погода — из кэша до срока ответа сервиса, потом с сервера.
        ref.invalidate(weatherProvider);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tlScroll.dispose();
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
          // Погода (1.15.1): включить — выбор города; включена — прогноз.
          if (weatherAllowed(ref))
            IconButton(
              tooltip: l10n.tr('weather'),
              icon: const Icon(AppIcons.partly_cloudy_day),
              onPressed: () => unawaited(showWeatherSheet(context)),
            ),
          IconButton(
            tooltip: l10n.tr(_timeline ? 'myDayViewBoard' : 'myDayViewTimeline'),
            icon: Icon(_timeline ? AppIcons.view_column : AppIcons.view_timeline),
            onPressed: () => _setTimeline(!_timeline),
          ),
        ],
      )),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_myDayProvider),
        // На доске списки — внутри листаемых вбок колонок: обновление
        // жестом вниз из любой колонки.
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        // Перечитывание (новая задача, отметка «выполнено», синхронизация)
        // идёт под старыми данными: раньше на это время экран сменялся
        // кругом загрузки и «дёргался», прокрутка сбрасывалась.
        child: data.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          // Ошибка чтения базы — без всплывающих окон, просто пустой экран.
          error: (e, _) => ListView(children: const [SizedBox(height: Space.xxl)]),
          data: (d) => _timeline ? _timelineBody(context, d, now, l10n) : _boardBody(context, d, now, l10n),
        ),
      ),
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
        // Часы — перелистывающиеся (1.15.1), справа — погода, если включена.
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          FlipClock(height: 40, reduceMotion: ref.watch(settingsProvider).reduceMotion),
          const Spacer(),
          const WeatherChip(),
        ]),
        if (counts.isNotEmpty || (next == null && live.isEmpty)) ...[
          const SizedBox(height: Space.s),
          Text(
            counts.isNotEmpty ? counts.join(' · ') : l10n.tr('myDayNothingAhead'),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context)),
          ),
        ],
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
    // Ровно часы — без «0 мин».
    if (m % 60 == 0) return l10n.tr('durHours').replaceAll('{h}', '${m ~/ 60}');
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
        onTap: () => context.push(mailOpenPath(context, m.id, accountId: m.accountId)),
      ));
    }
    return out;
  }

  static DateTime? _taskTime(Task t) => (t.reminderAt ?? t.dueDate)?.toLocal();


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


  /// Тема письма.
  String _subjectOf(Email m, AppLocalizations l10n) {
    return m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject.trim();
  }


}


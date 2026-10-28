// lib/features/calendar/screens/calendar_screen.dart
// Календарь (переработан 07.10.2026 по образцу Google Календаря и Outlook):
//  · виды «Расписание», «День», «3 дня», «Неделя», «Месяц»; выбранный вид
//    запоминается;
//  · день/неделя — сетка времени с блоками встреч, линией «сейчас»,
//    полосой «весь день»; нажатие на пустое время — новая встреча;
//  · листание периодов жестом влево/вправо;
//  · месяц — названия встреч в ячейках и расписание выбранного дня ниже;
//  · встреча открывается целиком (участники, «Подключиться», напоминание);
//  · фильтр «Календари»: ящики со своими цветами и слои (задачи, письма);
//  · поиск по всем событиям в базе, а не только по загруженному окну.
// Данные — поток из базы за видимый период (calendar_data.dart).

import '../../../widgets/ui/wheel_pickers.dart';
import 'dart:async';
import 'dart:io' show Platform;
import '../../../core/theme/app_icons.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../../widgets/navigation/app_bottom_bar.dart';
import '../../../services/mail/dav/dav_pim_service.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider, emailModelFromRow;
import '../../mail/widgets/mail_peek_card.dart' show showMailPeek, PeekAction;
import '../../mail/widgets/peek_helpers.dart' show peekCanRespondInvite, peekInviteActions;
import '../../../widgets/common/peek_card.dart' show peekAnchorAtFinger;
import '../widgets/event_peek.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart' show eventDetailsPath, mailDetailPath, tasksPath;
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../data/models/task_model.dart' show taskFromRow;
import '../../../services/tasks/task_actions_service.dart' show taskActionsProvider;
import '../../tasks/widgets/task_editor_sheet.dart' show showTaskEditor;
import '../../tasks/task_quick_parser.dart' show ParsedTask;
import '../../settings/providers/module_settings_provider.dart';
import '../../../widgets/navigation/panel_requests.dart' show calendarDayRequestProvider;
import '../../../data/models/email_model.dart' show EmailMeeting;
import '../../../services/calendar/pending_invites.dart' show pendingInvitesProvider;
import '../calendar_data.dart';
import '../widgets/agenda_view.dart';
import '../widgets/event_tile.dart';
import '../widgets/month_grid_view.dart';
import '../widgets/time_grid_view.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/calendar_day_icon.dart';
import '../../../widgets/common/adaptive_layout.dart';
import 'event_details_screen.dart';
import '../../../core/permissions/app_permissions.dart';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;

export '../calendar_data.dart' show calendarEventsProvider, calendarLayersProvider, CalendarLayers;

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _base = 10000;

  CalendarDefaultView? _view; // null → из настроек
  /// Опорная дата текущей страницы (день, первый день недели, месяц).
  DateTime _anchor = CalendarViewUtils.dayOf(DateTime.now());
  /// Дата, от которой отсчитываются страницы PageView (страница _base).
  DateTime _origin = CalendarViewUtils.dayOf(DateTime.now());
  DateTime? _selectedDay = CalendarViewUtils.dayOf(DateTime.now());
  /// Встреча в правой панели (планшет, iPad, широкое окно): (id, аккаунт).
  (String, String)? _pane;
  /// Ширина области содержимого при последней сборке (без боковой
  /// навигации): по ней решается, поместится ли панель справа.
  double _bodyWidth = 0;
  int _pagerGeneration = 0;
  PageController _pager = PageController(initialPage: _base);

  /// Вертикальная прокрутка сетки времени, общая для страниц: с утра.
  // Меньше нуля — сетка сама откроется на часе до текущего (шкала времени
  // по периодам, 1.5.11: высота часа зависит от дней и экрана).
  final _gridScroll = ValueNotifier<double>(-1);

  // «Расписание»: период ленты.
  late DateTime _agendaFrom = CalendarViewUtils.dayOf(DateTime.now());
  late DateTime _agendaTo = _agendaFrom.add(const Duration(days: 60));

  @override
  void initState() {
    super.initState();
    // Опорная дата первой страницы по виду: у недели — её первый день.
    _anchor = _pageStart(_currentView, _base);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeDayRequest();
      _askExactAlarmsOnce();
    });
  }

  /// «Мой день» → «Календарь на сегодня»: день в режиме «День».
  void _consumeDayRequest() {
    if (!mounted) return;
    final day = ref.read(calendarDayRequestProvider);
    if (day == null) return;
    ref.read(calendarDayRequestProvider.notifier).state = null;
    _jumpTo(day, view: CalendarDefaultView.day);
  }

  /// Точные будильники (Android 12+): без них напоминание о встрече
  /// приходит с опозданием до 15 минут. Разрешение «особое» и по умолчанию
  /// не выдано; раньше его можно было дать только на экране «Разрешения».
  /// Спрашиваем один раз — при первом открытии календаря.
  Future<void> _askExactAlarmsOnce() async {
    if (kIsWeb || !Platform.isAndroid) return;
    const key = 'perm_exact_asked_calendar_v1';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return;
    if (await AppPermissions.state(AppPermission.exactAlarms) != AppPermissionState.denied) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    final ok = await AppPermissions.ensure(context, AppPermission.exactAlarms);
    // Уже запланированные напоминания стоят «неточно» — перевыставляем.
    if (ok || await AppPermissions.state(AppPermission.exactAlarms) == AppPermissionState.granted) {
      await ref.read(reminderSchedulerProvider).rescheduleAll();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  CalendarDefaultView get _currentView => _view ?? ref.read(moduleSettingsProvider).calendarView;

  int get _weekStartDay => ref.read(moduleSettingsProvider).weekStartDay;

  /// Дней на странице сетки.
  int _daysOf(CalendarDefaultView v) => switch (v) {
        CalendarDefaultView.day => 1,
        CalendarDefaultView.threeDay => 3,
        CalendarDefaultView.week => 7,
        _ => 0,
      };

  /// Начало страницы с номером [page] для вида [v].
  DateTime _pageStart(CalendarDefaultView v, int page) {
    final k = page - _base;
    switch (v) {
      case CalendarDefaultView.day:
        return DateTime(_origin.year, _origin.month, _origin.day + k);
      case CalendarDefaultView.threeDay:
        return DateTime(_origin.year, _origin.month, _origin.day + 3 * k);
      case CalendarDefaultView.week:
        final ws = CalendarViewUtils.weekStart(_origin, _weekStartDay);
        return DateTime(ws.year, ws.month, ws.day + 7 * k);
      case CalendarDefaultView.month:
        return DateTime(_origin.year, _origin.month + k, 1);
      case CalendarDefaultView.agenda:
        return _origin;
    }
  }

  /// Перейти к дате (и/или виду): страницы пересчитываются от неё.
  void _jumpTo(DateTime date, {CalendarDefaultView? view}) {
    final d = CalendarViewUtils.dayOf(date);
    setState(() {
      if (view != null) _view = view;
      _origin = d;
      _selectedDay = d;
      final v = _currentView;
      _anchor = v == CalendarDefaultView.week
          ? CalendarViewUtils.weekStart(d, _weekStartDay)
          : v == CalendarDefaultView.month
              ? DateTime(d.year, d.month, 1)
              : d;
      if (v == CalendarDefaultView.agenda) {
        _agendaFrom = d;
        _agendaTo = d.add(const Duration(days: 60));
      }
      // Старый контроллер ещё привязан к PageView до перестройки — освобождаем
      // его после кадра.
      final old = _pager;
      _pager = PageController(initialPage: _base);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _pagerGeneration++;
    });
  }

  void _setView(CalendarDefaultView v) {
    HapticFeedback.selectionClick();
    // Выбор запоминается: в следующий раз календарь откроется так же.
    ref.read(moduleSettingsProvider.notifier).setCalendarView(v);
    final keep = _selectedDay ?? _anchor;
    _jumpTo(keep, view: v);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DateTime?>(calendarDayRequestProvider, (_, next) {
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => _consumeDayRequest());
    });
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Пересборка при смене настроек (начало недели, номера недель).
    final mod = ref.watch(moduleSettingsProvider);
    final view = _view ?? mod.calendarView;
    final ru = l10n.isRussian;
    final now = ref.watch(nowTickerProvider).value ?? DateTime.now();

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        titleSpacing: 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pickDate(l10n),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _title(view, l10n),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(AppIcons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.tr('today'),
            onPressed: () => _jumpTo(DateTime.now()),
            // Число дня — тем же значком, что вкладка внизу (CalendarDayIcon).
            icon: CalendarDayIcon(day: now.day),
          ),
          IconButton(
            icon: const Icon(AppIcons.search),
            tooltip: l10n.tr('search'),
            onPressed: () => _openSearch(l10n),
          ),
          PopupMenuButton<CalendarDefaultView>(
            tooltip: l10n.tr('defaultView'),
            icon: Icon(_viewIcon(view)),
            initialValue: view,
            onSelected: _setView,
            itemBuilder: (_) => [
              for (final v in const [
                CalendarDefaultView.agenda,
                CalendarDefaultView.day,
                CalendarDefaultView.threeDay,
                CalendarDefaultView.week,
                CalendarDefaultView.month,
              ])
                PopupMenuItem(
                  value: v,
                  child: Row(children: [
                    Icon(_viewIcon(v), size: 20),
                    const SizedBox(width: Space.m),
                    Text(_viewLabel(v, l10n)),
                  ]),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(AppIcons.tune),
            tooltip: l10n.tr('calendarLayers'),
            onPressed: () => _showCalendars(l10n),
          ),
        ],
      )),
      // Сетка дня/недели/месяца — ячейки фиксированного размера: при крупном
      // системном шрифте подписи в них растут умеренно (повестка — полностью).
      body: LayoutBuilder(builder: (context, c) {
        _bodyWidth = c.maxWidth;
        final inner = view == CalendarDefaultView.agenda
            ? _body(view, mod, ru, now, l10n)
            : TextScaleCap.grid(child: _body(view, mod, ru, now, l10n));
        // Хаб: строка ящиков над сеткой — нажатие включает и выключает
        // календарь ящика, долгое нажатие — «только этот».
        final grid = Column(children: [
          _AccountChips(l10n: l10n),
          // Приглашения без ответа — на любой день (1.6.33).
          _PendingInvitesBar(l10n: l10n),
          Expanded(child: inner),
        ]);
        final pane = _pane;
        if (pane == null || c.maxWidth < Breakpoints.tablet) return grid;
        return Row(children: [
          Expanded(child: grid),
          VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
          SizedBox(
            width: (c.maxWidth * 0.4).clamp(340.0, 460.0),
            child: EventDetailsScreen(
              key: ValueKey(pane),
              eventId: pane.$1,
              accountId: pane.$2,
              onClose: () => setState(() => _pane = null),
            ),
          ),
        ]);
      }),
      // На телефоне «Создать встречу» — в центре нижней панели.
      floatingActionButton: AppBottomBar.inUse(context) ? null : FloatingActionButton(
        heroTag: 'fab_calendar_add',
        tooltip: l10n.tr('createMeeting'),
        onPressed: () => _createAt(null),
        child: const Icon(AppIcons.add),
      ),
    );
  }

  Widget _body(CalendarDefaultView view, ModuleSettings mod, bool ru, DateTime now, AppLocalizations l10n) {
    switch (view) {
      case CalendarDefaultView.agenda:
        return _agenda(ru, now);
      case CalendarDefaultView.month:
        return _month(mod, ru, now, l10n);
      case CalendarDefaultView.day:
      case CalendarDefaultView.threeDay:
      case CalendarDefaultView.week:
        final days = _daysOf(view);
        return PageView.builder(
          key: ValueKey('grid_${view.name}_$_pagerGeneration'),
          controller: _pager,
          onPageChanged: (p) => setState(() {
            _anchor = _pageStart(view, p);
            _selectedDay = _anchor;
          }),
          itemBuilder: (context, page) {
            final start = _pageStart(view, page);
            final range = (from: start, to: start.add(Duration(days: days)));
            return Consumer(builder: (context, ref, _) {
              final events = ref.watch(calendarEventsProvider(range)).value ?? const <CalendarEvent>[];
              return TimeGridView(
                  start: start,
                  days: days,
                  events: events,
                  accountColors: ref.watch(accountColorsProvider),
                  isRussian: ru,
                  now: now,
                  scrollOffset: _gridScroll,
                  onEventTap: _open,
                  onEventLongPress: _quickActions,
                  onSlotTap: (t) => _createAt(t),
                  onDayHeaderTap: days == 1 ? null : (d) => _jumpTo(d, view: CalendarDefaultView.day),
              );
            });
          },
        );
    }
  }

  // ── Расписание ──
  Widget _agenda(bool ru, DateTime now) {
    final range = (from: _agendaFrom, to: _agendaTo);
    final async = ref.watch(calendarEventsProvider(range));
    final events = async.value;
    if (events == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _refresh,
      child: AgendaView(
        from: _agendaFrom,
        to: _agendaTo,
        events: events,
        accountColors: ref.watch(accountColorsProvider),
        isRussian: ru,
        now: now,
        onEventTap: _open,
        onEventLongPress: _quickActions,
        onLoadEarlier: () => setState(() => _agendaFrom = _agendaFrom.subtract(const Duration(days: 30))),
        onLoadMore: () => setState(() => _agendaTo = _agendaTo.add(const Duration(days: 60))),
        onEmptyDayTap: (d) => _jumpTo(d, view: CalendarDefaultView.day),
      ),
    );
  }

  // ── Месяц ──
  Widget _month(ModuleSettings mod, bool ru, DateTime now, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          flex: 11,
          child: PageView.builder(
            key: ValueKey('month_$_pagerGeneration'),
            controller: _pager,
            onPageChanged: (p) => setState(() {
              _anchor = _pageStart(CalendarDefaultView.month, p);
              // Выбранный день — сегодня, если он в этом месяце, иначе 1-е.
              _selectedDay = (now.year == _anchor.year && now.month == _anchor.month)
                  ? CalendarViewUtils.dayOf(now)
                  : _anchor;
            }),
            itemBuilder: (context, page) {
              final month = _pageStart(CalendarDefaultView.month, page);
              final gs = MonthGridView.gridStart(month, mod.weekStartDay);
              final range = (from: gs, to: gs.add(const Duration(days: 42)));
              return Consumer(builder: (context, ref, _) {
                final events = ref.watch(calendarEventsProvider(range)).value ?? const <CalendarEvent>[];
                return MonthGridView(
                  month: month,
                  events: events,
                  weekStartDay: mod.weekStartDay,
                  showWeekNumbers: mod.showWeekNumbers,
                  isRussian: ru,
                  selectedDay: _selectedDay,
                  now: now,
                  accountColors: ref.watch(accountColorsProvider),
                  onDaySelected: (d) {
                    HapticFeedback.selectionClick();
                    if (_selectedDay != null && CalendarViewUtils.sameDay(d, _selectedDay!)) {
                      // Второе нажатие на выбранный день — его сетка времени.
                      _jumpTo(d, view: CalendarDefaultView.day);
                      return;
                    }
                    setState(() => _selectedDay = d);
                  },
                );
              });
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(flex: 8, child: _selectedDayList(ru, now, l10n)),
      ],
    );
  }

  Widget _selectedDayList(bool ru, DateTime now, AppLocalizations l10n) {
    final day = _selectedDay ?? _anchor;
    final theme = Theme.of(context);
    final range = (from: day, to: day.add(const Duration(days: 1)));
    final events = CalendarViewUtils.eventsForDay(
        ref.watch(calendarEventsProvider(range)).value ?? const <CalendarEvent>[], day);
    final colors = ref.watch(accountColorsProvider);
    final locale = l10n.localeCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 96),
      children: [
        // День — полосой, как разделы в остальном приложении.
        SettingsSectionTitle(
          DateFormat('EEEE, d MMMM', locale).format(day),
          trailing: TextButton.icon(
            onPressed: () => _createAt(DateTime(day.year, day.month, day.day, 9), dayOnly: true),
            icon: const Icon(AppIcons.add, size: Sizes.iconInline),
            label: Text(l10n.tr('add')),
          ),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(l10n.tr('noEventsThisDay'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
            ),
          ),
        for (final e in events)
          EventTile(
            event: e,
            day: day,
            color: eventColor(e, colors),
            isRussian: ru,
            now: now,
            onTap: () => _open(e),
            onLongPress: () => _quickActions(e),
          ),
      ],
    );
  }

  // ── Заголовок и подписи ──
  String _title(CalendarDefaultView view, AppLocalizations l10n) {
    final locale = l10n.localeCode;
    final now = DateTime.now();
    switch (view) {
      case CalendarDefaultView.agenda:
        return l10n.tr('viewAgenda');
      case CalendarDefaultView.day:
        final fmt = _anchor.year == now.year ? 'd MMMM' : 'd MMMM yyyy';
        return DateFormat(fmt, locale).format(_anchor);
      case CalendarDefaultView.threeDay:
      case CalendarDefaultView.week:
        final end = _anchor.add(Duration(days: _daysOf(view) - 1));
        if (end.month == _anchor.month) {
          return capitalize(DateFormat('LLLL yyyy', locale).format(_anchor));
        }
        return '${capitalize(DateFormat('LLL', locale).format(_anchor))} – ${DateFormat('LLL yyyy', locale).format(end)}';
      case CalendarDefaultView.month:
        return capitalize(DateFormat('LLLL yyyy', locale).format(_anchor));
    }
  }

  IconData _viewIcon(CalendarDefaultView v) => switch (v) {
        CalendarDefaultView.agenda => AppIcons.view_agenda,
        CalendarDefaultView.day => AppIcons.view_day,
        CalendarDefaultView.threeDay => AppIcons.view_column,
        CalendarDefaultView.week => AppIcons.view_week,
        CalendarDefaultView.month => AppIcons.calendar_view_month,
      };

  String _viewLabel(CalendarDefaultView v, AppLocalizations l10n) => switch (v) {
        CalendarDefaultView.agenda => l10n.tr('viewAgenda'),
        CalendarDefaultView.day => l10n.tr('viewDay'),
        CalendarDefaultView.threeDay => l10n.tr('view3Days'),
        CalendarDefaultView.week => l10n.tr('viewWeek'),
        CalendarDefaultView.month => l10n.tr('viewMonth'),
      };

  // ── Действия ──
  Future<void> _refresh() async {
    unawaited(HapticFeedback.mediumImpact());
    // Ручное обновление — календари CalDAV выгружаются целиком, даже если
    // метка изменений на сервере та же.
    for (final a in ref.read(accountsProvider)) {
      await DavPimService.invalidateTags(a.id);
    }
    await ref.read(syncServiceProvider).syncAll();
  }

  Future<void> _pickDate(AppLocalizations l10n) async {
    final picked = await showWheelDatePicker(context,
        initial: _selectedDay ?? _anchor, first: DateTime(2000), last: DateTime(2100));
    if (picked != null && mounted) _jumpTo(picked);
  }

  /// Создать в календаре: встречу или задачу (замечание 10.10.2026 —
  /// из календаря создавалась только встреча). Время ячейки — начало встречи
  /// или срок задачи.
  Future<void> _createAt(DateTime? start, {bool dayOnly = false}) async {
    final l10n = AppLocalizations.of(context);
    final kind = await showActionSheet<String>(context, items: [
      ActionSheetItem(icon: AppIcons.event, label: l10n.tr('createMeeting'), value: 'event'),
      ActionSheetItem(
          icon: AppIcons.add_task, label: l10n.tr('newTask'), subtitle: l10n.tr('newTaskHint'), value: 'task'),
    ]);
    if (kind == null || !mounted) return;
    if (kind == 'task') {
      final now = DateTime.now();
      final day = start ?? _selectedDay ?? now;
      // Ячейка времени — срок со временем; кнопка дня — срок на день.
      final due = start != null && !dayOnly ? start : DateTime(day.year, day.month, day.day);
      unawaited(showTaskEditor(context, draft: ParsedTask(title: '', due: due)));
      return;
    }
    if (start == null) {
      unawaited(context.push('/create-event'));
      return;
    }
    unawaited(context.push('/create-event', extra: {
      'start': start,
      'end': start.add(Duration(minutes: _defaultDuration)),
    }));
  }

  /// Длительность новой встречи по умолчанию — 30 минут, как в Outlook (1.6.8).
  int get _defaultDuration => 30;

  /// Нажатие на событие: встреча — целиком; задача — в «Напоминаниях»;
  /// письмо с напоминанием — само письмо.
  void _open(CalendarEvent e) {
    HapticFeedback.selectionClick();
    if (isTaskItem(e)) {
      // Задача открывается здесь же, карточкой поверх календаря: календарь и
      // задачи — один план дня (раньше — переход в раздел «Задачи»).
      unawaited(_openTask(e));
      return;
    }
    if (isMailItem(e)) {
      context.push(mailDetailPath(e.id.substring(mailPrefix.length), accountId: e.accountId));
      return;
    }
    // Приглашение без ответа — письмо с «Принять / Под вопросом / Отклонить».
    if (isInviteItem(e)) {
      context.push(mailDetailPath(e.id.substring(invitePrefix.length), accountId: e.accountId));
      return;
    }
    // Широкий экран: встреча открывается справа, календарь остаётся виден.
    if (_bodyWidth >= Breakpoints.tablet) {
      setState(() => _pane = (e.id, e.accountId));
      return;
    }
    context.push(eventDetailsPath(e.id, accountId: e.accountId));
  }

  /// Долгое нажатие: быстрые действия без открытия встречи.
  /// 1.6.47: карточка встречи «как в Telegram» (кнопки под ней, «Ещё» —
  /// все действия по группам здесь же, 1.6.49+95); приглашение без ответа —
  /// карточка письма с «Принять / Под вопросом / Отклонить».
  Future<void> _quickActions(CalendarEvent e) async {
    if (isTaskItem(e)) {
      await _taskActions(e);
      return;
    }
    if (isInviteItem(e)) {
      await _invitePeek(e);
      return;
    }
    if (!isRealEvent(e)) {
      _open(e);
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    await showEventPeek(
      context,
      ref,
      e,
      color: eventColor(e, ref.read(accountColorsProvider)),
      onOpen: () => _open(e),
      onDuplicate: () => _duplicate(e),
    );
  }

  /// Приглашение без ответа (письмо) — карточка письма с ответом.
  Future<void> _invitePeek(CalendarEvent e) async {
    final l10n = AppLocalizations.of(context);
    final row = await ref.read(databaseProvider).getEmailById(e.id.substring(invitePrefix.length), accountId: e.accountId);
    if (!mounted) return;
    if (row == null) {
      _open(e);
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    final email = emailModelFromRow(row);
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    await showMailPeek(
      context,
      email: email,
      anchor: peekAnchorAtFinger(context),
      previewLines: 2,
      onOpen: () => _open(e),
      actions: [
        if (account != null && peekCanRespondInvite(account, email))
          ...peekInviteActions(context, ref, account, email, l10n),
        PeekAction(icon: AppIcons.mail, label: l10n.tr('ntfOpen'), onTap: () => _open(e)),
      ],
    );
  }

  void _duplicate(CalendarEvent e) => context.push('/create-event', extra: {'duplicate': e});

  Future<void> _openTask(CalendarEvent e) async {
    final id = e.id.substring(taskPrefix.length);
    final db = ref.read(databaseProvider);
    final row = await (db.select(db.tasks)
          ..where((t) => t.id.equals(id) & t.accountId.equals(e.accountId)))
        .getSingleOrNull();
    if (!mounted) return;
    if (row == null) {
      context.go(tasksPath(openTaskId: id, accountId: e.accountId));
      return;
    }
    await showTaskEditor(context, task: taskFromRow(row), accountId: row.accountId);
  }

  /// Долгое нажатие на задачу: выполнено, открыть, удалить.
  Future<void> _taskActions(CalendarEvent e) async {
    final l10n = AppLocalizations.of(context);
    final id = e.id.substring(taskPrefix.length);
    final a = await showActionSheet<String>(
      context,
      title: e.title,
      leading: const Icon(AppIcons.task_alt),
      items: [
        ActionSheetItem(icon: AppIcons.check_circle, label: l10n.tr('taskMarkDone'), value: 'done'),
        ActionSheetItem(icon: AppIcons.open_in_full, label: l10n.tr('ntfOpen'), value: 'open'),
        ActionSheetItem(icon: AppIcons.delete, label: l10n.delete, value: 'delete', destructive: true),
      ],
    );
    if (a == null || !mounted) return;
    final actions = ref.read(taskActionsProvider);
    switch (a) {
      case 'done':
        await actions.setDone(e.accountId, id, true);
      case 'open':
        await _openTask(e);
      case 'delete':
        await actions.delete(e.accountId, id);
    }
  }

  /// «Календари»: ящики (галочка — показывать) и слои.
  void _showCalendars(AppLocalizations l10n) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final scope = ref.watch(calendarScopeProvider);
          final hidden = ref.watch(calendarHiddenAccountsProvider);
          final layers = ref.watch(calendarLayersProvider);
          final layersN = ref.read(calendarLayersProvider.notifier);
          final theme = Theme.of(ctx);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, Space.s, Space.s, 0),
                    child: Row(children: [
                      Expanded(child: Text(l10n.tr('calendarsTitle'), style: theme.textTheme.titleMedium)),
                      if (hidden.isNotEmpty)
                        TextButton(
                          onPressed: () => ref.read(calendarHiddenAccountsProvider.notifier).setHidden(const {}),
                          child: Text(l10n.tr('calShowAll')),
                        ),
                    ]),
                  ),
                  SwitchListTile(
                    value: ref.watch(calendarHubProvider),
                    onChanged: (v) => ref.read(calendarHubProvider.notifier).set(v),
                    secondary: const Icon(AppIcons.calendar_month),
                    title: Text(l10n.tr('calHubAll')),
                    subtitle: Text(l10n.tr('calHubAllDesc')),
                  ),
                  for (final a in scope)
                    CheckboxListTile(
                      value: !hidden.contains(a.id),
                      onChanged: (_) => ref.read(calendarHiddenAccountsProvider.notifier).toggle(a.id),
                      activeColor: Color(a.colorValue),
                      secondary: CircleAvatar(radius: 7, backgroundColor: Color(a.colorValue)),
                      title: Text(a.displayName.isNotEmpty ? a.displayName : a.email),
                      subtitle: a.displayName.isNotEmpty ? Text(a.email) : null,
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, Space.s, 20, Space.xs),
                    child: Text(l10n.tr('calendarLayers'), style: theme.textTheme.titleMedium),
                  ),
                  CheckboxListTile(
                    value: layers.showTasks,
                    onChanged: (v) => layersN.set(layers.copyWith(showTasks: v ?? false)),
                    secondary: const Icon(AppIcons.check_circle),
                    title: Text(l10n.tr('layerTasks')),
                  ),
                  CheckboxListTile(
                    value: layers.showFlaggedMail,
                    onChanged: (v) => layersN.set(layers.copyWith(showFlaggedMail: v ?? false)),
                    secondary: const Icon(AppIcons.flag),
                    title: Text(l10n.tr('layerFlaggedMail')),
                    subtitle: Text(l10n.tr('layerFlaggedMailHint')),
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.settings),
                    title: Text(l10n.tr('calendarSettings')),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/settings/calendar');
                    },
                  ),
                  const SizedBox(height: Space.s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Поиск по всем событиям в базе (видимых ящиков), не только по окну.
  Future<void> _openSearch(AppLocalizations l10n) async {
    final picked = await showSearch<CalendarEvent?>(
      context: context,
      delegate: _EventSearchDelegate(
        db: ref.read(databaseProvider),
        accountIds: ref.read(calendarVisibleAccountIdsProvider),
        l10n: l10n,
      ),
    );
    if (picked != null && mounted) _open(picked);
  }
}

class _EventSearchDelegate extends SearchDelegate<CalendarEvent?> {
  _EventSearchDelegate({required this.db, required this.accountIds, required this.l10n});

  final AppDatabase db;
  final List<String> accountIds;
  final AppLocalizations l10n;

  Future<List<CalendarEvent>> _search(String q) {
    final like = '%${q.toLowerCase()}%';
    return (db.select(db.calendarEvents)
          ..where((e) => e.accountId.isIn(accountIds))
          ..where((e) =>
              e.title.lower().like(like) |
              e.location.lower().like(like) |
              e.description.lower().like(like) |
              e.attendeesJson.lower().like(like))
          ..orderBy([(e) => OrderingTerm(expression: e.startTime, mode: OrderingMode.desc)])
          ..limit(100))
        .get();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty) IconButton(tooltip: MaterialLocalizations.of(context).deleteButtonTooltip, icon: const Icon(AppIcons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: const Icon(AppIcons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.trim();
    if (q.length < 2) {
      return Center(child: Text(l10n.tr('calendarSearchHint')));
    }
    final locale = l10n.localeCode;
    final now = DateTime.now();
    return FutureBuilder<List<CalendarEvent>>(
      future: _search(q),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final results = snap.data!;
        if (results.isEmpty) return Center(child: Text(l10n.tr('recipientSearchNone')));
        // Сначала будущие (ближайшие сверху), затем прошедшие.
        final future = results.where((e) => e.endTime.isAfter(now)).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        final past = results.where((e) => !e.endTime.isAfter(now)).toList();
        final all = [...future, ...past];
        return ListView.builder(
          itemCount: all.length,
          itemBuilder: (ctx, i) {
            final e = all[i];
            final dateStr = e.isAllDay
                ? DateFormat('d MMM yyyy', locale).format(e.startTime.toLocal())
                : DateFormat('d MMM yyyy, HH:mm', locale).format(e.startTime.toLocal());
            return ListTile(
              leading: Icon(e.endTime.isAfter(now) ? AppIcons.event : AppIcons.event_available,
                  color: e.endTime.isAfter(now) ? null : Theme.of(ctx).hintColor),
              title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                (e.location ?? '').isEmpty ? dateStr : '$dateStr · ${e.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => close(context, e),
            );
          },
        );
      },
    );
  }
}

/// Строка ящиков календаря («хаб»): цветная метка — календарь ящика виден,
/// серая — выключен. Нажатие — включить/выключить, долгое — только этот.
/// Один ящик — строки нет.
class _AccountChips extends ConsumerWidget {
  final AppLocalizations l10n;
  const _AccountChips({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(calendarScopeProvider);
    if (scope.length < 2) return const SizedBox.shrink();
    final hidden = ref.watch(calendarHiddenAccountsProvider);
    final n = ref.read(calendarHiddenAccountsProvider.notifier);
    final theme = Theme.of(context);
    final allOff = scope.every((a) => hidden.contains(a.id));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
            children: [
              for (final a in scope)
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  // Без подсказки (tooltip): её долгое нажатие перехватывало
                  // «только этот».
                  child: GestureDetector(
                    onLongPress: () => n.setHidden({for (final o in scope) if (o.id != a.id) o.id}),
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      selected: !hidden.contains(a.id),
                      onSelected: (_) => n.toggle(a.id),
                      avatar: CircleAvatar(
                        radius: 6,
                        backgroundColor: hidden.contains(a.id)
                            ? theme.colorScheme.outlineVariant
                            : Color(a.colorValue),
                      ),
                      label: Text(
                        a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email.split('@').first,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (allOff)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
            child: Text(l10n.tr('calNoneVisible'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// «Ждут ответа: N» — приглашения на встречи без ответа (1.6.33, просьба
/// 18.10.2026: «даже если они не на сегодня»). Полоса над сеткой; одно
/// приглашение — нажатие открывает письмо с кнопками «Принять / Под вопросом
/// / Отклонить», несколько — список. Нет приглашений — полосы нет.
class _PendingInvitesBar extends ConsumerWidget {
  final AppLocalizations l10n;
  const _PendingInvitesBar({required this.l10n});

  static String _when(Email m, String locale, AppLocalizations l10n) {
    final meet = EmailMeeting.parse(m.meetingJson);
    final s = meet?.start;
    if (s == null) return '';
    final now = DateTime.now();
    final day = DateFormat(s.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy', locale).format(s);
    if (meet!.allDay) return '$day · ${l10n.tr('allDay')}';
    final e = meet.end;
    final t = DateFormat.Hm(locale);
    return e == null ? '$day, ${t.format(s)}' : '$day, ${t.format(s)}–${t.format(e)}';
  }

  static String _subject(Email m, AppLocalizations l10n) =>
      m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject.trim();

  static String _who(Email m) {
    final n = (m.fromName ?? '').trim();
    return n.isNotEmpty ? n : m.fromEmail;
  }

  void _openMail(BuildContext context, Email m) =>
      context.push(mailDetailPath(m.id, accountId: m.accountId));

  Future<void> _showAll(BuildContext context, List<Email> list) async {
    final locale = l10n.localeCode;
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Space.l),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Text(l10n.tr('invitesPendingTitle'), style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final m in list)
              ListTile(
                leading: const Icon(AppIcons.event_available),
                title: Text(_subject(m, l10n), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([_when(m, locale, l10n), _who(m)].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(AppIcons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openMail(context, m);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingInvitesProvider).value ?? const <Email>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = list.first;
    final title = list.length == 1
        ? _subject(first, l10n)
        : l10n.tr('invitesPendingN').replaceAll('{n}', '${list.length}');
    final sub = list.length == 1
        ? [l10n.tr('invitePendingOne'), _when(first, l10n.localeCode, l10n)].where((x) => x.isNotEmpty).join(' · ')
        : '${l10n.tr('invitesPendingNext')}: ${_subject(first, l10n)} · ${_when(first, l10n.localeCode, l10n)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xs),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => list.length == 1 ? _openMail(context, first) : _showAll(context, list),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(children: [
              Icon(AppIcons.event_available, color: scheme.primary),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ),
              Icon(AppIcons.chevron_right, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

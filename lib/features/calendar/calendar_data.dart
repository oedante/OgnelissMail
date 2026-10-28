// lib/features/calendar/calendar_data.dart
// Данные календаря: события за любой видимый период (а не фиксированные
// ±45 дней, как раньше — в следующем квартале календарь был пуст), слои
// (задачи со сроком, письма с напоминанием), скрытые ящики, цвета.
//
// События берутся из базы потоком (drift watch): синхронизация добавила
// встречу — она появляется на экране без «потянуть для обновления».

import 'dart:convert';
import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../services/home_widget_service.dart';
import '../../services/tasks/task_actions_service.dart';
import '../mail/providers/mail_providers.dart';
import '../../data/models/email_model.dart' show EmailMeeting;
import '../../services/calendar/pending_invites.dart' show pendingInvitesProvider;
import '../settings/providers/account_groups_provider.dart';

/// Период выборки: [from, to) в локальном времени.
typedef CalRange = ({DateTime from, DateTime to});

/// Какие слои показывать в календаре (сохраняется между запусками).
class CalendarLayers {
  final bool showTasks;
  final bool showFlaggedMail;
  const CalendarLayers({this.showTasks = true, this.showFlaggedMail = true});

  CalendarLayers copyWith({bool? showTasks, bool? showFlaggedMail}) =>
      CalendarLayers(
        showTasks: showTasks ?? this.showTasks,
        showFlaggedMail: showFlaggedMail ?? this.showFlaggedMail,
      );
}

class _LayersNotifier extends StateNotifier<CalendarLayers> {
  final Ref _ref;
  _LayersNotifier(Ref ref)
      : _ref = ref,
        super(CalendarLayers(
          showTasks: ref.read(sharedPrefsProvider).getBool('cal_layer_tasks') ?? true,
          showFlaggedMail: ref.read(sharedPrefsProvider).getBool('cal_layer_mail') ?? true,
        ));

  void set(CalendarLayers v) {
    state = v;
    final p = _ref.read(sharedPrefsProvider);
    p.setBool('cal_layer_tasks', v.showTasks);
    p.setBool('cal_layer_mail', v.showFlaggedMail);
  }
}

final calendarLayersProvider =
    StateNotifierProvider<_LayersNotifier, CalendarLayers>((ref) => _LayersNotifier(ref));

/// Ящики, скрытые в календаре (галочки в «Календари»).
class _HiddenNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  _HiddenNotifier(Ref ref)
      : _ref = ref,
        super({...?ref.read(sharedPrefsProvider).getStringList('cal_hidden_accounts')});

  void toggle(String accountId) {
    final next = {...state};
    if (!next.remove(accountId)) next.add(accountId);
    state = next;
    _ref.read(sharedPrefsProvider).setStringList('cal_hidden_accounts', next.toList());
    // Виджет «Календарь» показывает те же ящики.
    unawaited(HomeWidgetService.updateFrom(_ref, force: true));
  }

  /// Скрыть ровно эти ящики (пусто — показать все).
  void setHidden(Set<String> ids) {
    state = {...ids};
    _ref.read(sharedPrefsProvider).setStringList('cal_hidden_accounts', state.toList());
    unawaited(HomeWidgetService.updateFrom(_ref, force: true));
  }
}

/// «Хаб» календаря: все ящики сразу, включение и выключение галочками —
/// независимо от ящика, выбранного в почте. Выключен — календарь следует
/// области почты, как раньше. По умолчанию включён.
class _HubNotifier extends StateNotifier<bool> {
  final Ref _ref;
  _HubNotifier(Ref ref)
      : _ref = ref,
        super(ref.read(sharedPrefsProvider).getBool('cal_hub') ?? true);

  void set(bool v) {
    state = v;
    _ref.read(sharedPrefsProvider).setBool('cal_hub', v);
  }
}

final calendarHubProvider = StateNotifierProvider<_HubNotifier, bool>((ref) => _HubNotifier(ref));

final calendarHiddenAccountsProvider =
    StateNotifierProvider<_HiddenNotifier, Set<String>>((ref) => _HiddenNotifier(ref));

/// Ящики, чей календарь показывается. «Хаб» — все активные (в порядке из
/// настроек), лишние выключаются галочками. Без хаба — область почты:
/// «Все ящики» — все активные; группа — её ящики; иначе — текущий.
final calendarScopeProvider = Provider<List<AccountModel>>((ref) {
  final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
  if (ref.watch(calendarHubProvider)) return accounts;
  final active = ref.watch(activeAccountProvider);
  final group = ref.watch(activeGroupAccountIdsProvider);
  final all = ref.watch(allAccountsModeProvider);
  if (all) return accounts;
  if (group.isNotEmpty) return accounts.where((a) => group.contains(a.id)).toList();
  return active == null ? const [] : [active];
});

/// Ящики области, которые не скрыты.
final calendarVisibleAccountIdsProvider = Provider<List<String>>((ref) {
  final hidden = ref.watch(calendarHiddenAccountsProvider);
  return [for (final a in ref.watch(calendarScopeProvider)) if (!hidden.contains(a.id)) a.id];
});

/// События за период (с запасом в сутки по краям — многодневные события и
/// разница UTC/местного времени). Поток: обновляется при изменениях в базе.
final calendarEventsProvider =
    StreamProvider.autoDispose.family<List<CalendarEvent>, CalRange>((ref, range) {
  final db = ref.watch(databaseProvider);
  final ids = ref.watch(calendarVisibleAccountIdsProvider);
  final layers = ref.watch(calendarLayersProvider);
  // Правки задач (выполнено, срок) — пересчёт слоя задач.
  ref.watch(tasksRevisionProvider);
  // Приглашения без ответа (1.6.34): встреча видна в календаре, даже если
  // сервер ещё не положил её туда (или положил, а синхронизация не дошла).
  final invites = ref.watch(pendingInvitesProvider).value ?? const <Email>[];
  if (ids.isEmpty) return Stream.value(const <CalendarEvent>[]);

  final from = range.from.subtract(const Duration(days: 1));
  final to = range.to.add(const Duration(days: 1));
  // Многодневные события, начавшиеся раньше периода, — до 60 дней назад.
  final lookback = from.subtract(const Duration(days: 60));

  final query = db.select(db.calendarEvents)
    ..where((e) => e.accountId.isIn(ids))
    ..where((e) => e.startTime.isSmallerThanValue(to))
    ..where((e) => e.startTime.isBiggerOrEqualValue(lookback))
    ..where((e) => e.endTime.isBiggerThanValue(from))
    ..where((e) => e.isCancelled.equals(false))
    ..orderBy([(e) => OrderingTerm(expression: e.startTime)]);

  return query.watch().asyncMap((events) async {
    final extra = <CalendarEvent>[];
    if (layers.showTasks) {
      final tasks = await (db.select(db.tasks)
            ..where((t) => t.accountId.isIn(ids))
            ..where((t) => t.dueDate.isNotNull())
            ..where((t) => t.dueDate.isBiggerOrEqualValue(from))
            ..where((t) => t.dueDate.isSmallerThanValue(to))
            ..where((t) => t.status.isNotIn([2, 3])))
          .get();
      for (final t in tasks) {
        final due = t.dueDate!.toLocal();
        final dateOnly = due.hour == 0 && due.minute == 0;
        extra.add(CalendarEvent(
          id: '$taskPrefix${t.id}',
          accountId: t.accountId,
          title: t.title,
          startTime: due,
          endTime: dateOnly ? due.add(const Duration(days: 1)) : due.add(const Duration(minutes: 30)),
          createdAt: t.createdAt,
          isAllDay: dateOnly,
          recurrence: 0,
          priority: t.priority,
          showAs: 0,
          isPrivate: false,
          isCancelled: false,
          isLocallyModified: false,
        ));
      }
    }
    if (layers.showFlaggedMail) {
      final mails = await (db.select(db.emails)
            ..where((e) => e.accountId.isIn(ids))
            ..where((e) => e.followUpAt.isNotNull())
            ..where((e) => e.followUpAt.isBiggerOrEqualValue(from))
            ..where((e) => e.followUpAt.isSmallerThanValue(to))
            ..limit(200))
          .get();
      for (final m in mails) {
        extra.add(CalendarEvent(
          id: '$mailPrefix${m.id}',
          accountId: m.accountId,
          title: m.subject.isEmpty ? '—' : m.subject,
          startTime: m.followUpAt!,
          endTime: m.followUpAt!.add(const Duration(minutes: 15)),
          createdAt: m.receivedAt,
          isAllDay: false,
          recurrence: 0,
          priority: 1,
          showAs: 0,
          isPrivate: false,
          isCancelled: false,
          isLocallyModified: false,
        ));
      }
    }
    for (final m in invites) {
      if (!ids.contains(m.accountId)) continue;
      final meet = EmailMeeting.parse(m.meetingJson);
      final st = meet?.start;
      if (meet == null || st == null) continue;
      final en = meet.end ?? st.add(const Duration(minutes: 30));
      if (!st.isBefore(to) || !en.isAfter(from)) continue;
      // Сервер уже положил встречу в календарь — второй раз не показываем.
      final subj = m.subject.trim().toLowerCase();
      final dup = events.any((e) =>
          e.accountId == m.accountId &&
          e.startTime.toLocal().difference(st).inMinutes.abs() <= 1 &&
          (subj.isEmpty || subj.endsWith(e.title.trim().toLowerCase())));
      if (dup) continue;
      extra.add(CalendarEvent(
        id: '$invitePrefix${m.id}',
        accountId: m.accountId,
        title: m.subject.trim().isEmpty ? '—' : m.subject.trim(),
        location: meet.location,
        organizerEmail: m.fromEmail,
        startTime: st,
        endTime: en,
        createdAt: m.receivedAt,
        isAllDay: meet.allDay,
        recurrence: 0,
        priority: 1,
        showAs: 1,
        isPrivate: false,
        isCancelled: false,
        isLocallyModified: false,
      ));
    }
    if (extra.isEmpty) return events;
    return [...events, ...extra]..sort((a, b) => a.startTime.compareTo(b.startTime));
  });
});

/// Псевдо-события слоёв.
const taskPrefix = 'task_';
const mailPrefix = 'mail_';
/// Приглашение без ответа (письмо), 1.6.34.
const invitePrefix = 'invite_';

bool isTaskItem(CalendarEvent e) => e.id.startsWith(taskPrefix);
bool isMailItem(CalendarEvent e) => e.id.startsWith(mailPrefix);
bool isInviteItem(CalendarEvent e) => e.id.startsWith(invitePrefix);
bool isRealEvent(CalendarEvent e) => !isTaskItem(e) && !isMailItem(e) && !isInviteItem(e);

/// Цвета ящиков по id (для полос событий).
final accountColorsProvider = Provider<Map<String, Color>>((ref) => {
      for (final a in ref.watch(accountsProvider)) a.id: Color(a.colorValue),
    });

/// Цвет события: свой (категория/выбор при создании), иначе цвет ящика.
Color eventColor(CalendarEvent e, Map<String, Color> accountColors) {
  if (isTaskItem(e)) return AppColors.successGreen;
  if (isMailItem(e)) return AppColors.accentOrange;
  if (e.colorValue != null && e.colorValue != 0) return Color(e.colorValue!);
  return accountColors[e.accountId] ?? AppColors.primaryBlue;
}

/// Первая буква заглавная («октябрь 2026» → «Октябрь 2026»).
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Текст поверх цвета: белый или чёрный по яркости.
Color onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black87;

class CalendarViewUtils {
  CalendarViewUtils._();

  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// События, пересекающиеся с днём (конец не включается). Многодневные и
  /// «на весь день» на несколько дней видны во все свои дни.
  static List<CalendarEvent> eventsForDay(List<CalendarEvent> events, DateTime day) {
    final d = dayOf(day);
    final next = DateTime(day.year, day.month, day.day + 1);
    return events.where((e) {
      final s = e.startTime.toLocal();
      final en = e.endTime.toLocal();
      if (!en.isAfter(s)) return !s.isBefore(d) && s.isBefore(next);
      return s.isBefore(next) && en.isAfter(d);
    }).toList()
      ..sort((a, b) {
        if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
        return a.startTime.compareTo(b.startTime);
      });
  }

  static int eventCountForDay(List<CalendarEvent> events, DateTime day) =>
      eventsForDay(events, day).length;

  /// Начало недели, в которую входит [d] (weekStartDay: 1 = пн, 7 = вс).
  static DateTime weekStart(DateTime d, int weekStartDay) {
    var diff = (d.weekday - weekStartDay) % 7;
    if (diff < 0) diff += 7;
    return DateTime(d.year, d.month, d.day - diff);
  }

  /// Номер недели по ISO 8601.
  static int isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstWeekStart = firstThursday.subtract(Duration(days: firstThursday.weekday - 1));
    return 1 + DateTime(thursday.year, thursday.month, thursday.day)
            .difference(firstWeekStart)
            .inDays ~/
        7;
  }

  /// «1 ч 30 мин» / «45 мин» / «2 дн.».
  static String durationLabel(Duration d, AppLocalizations l10n) {
    if (d.inMinutes >= 1440 && d.inMinutes % 1440 == 0) {
      return l10n.tr('durDays').replaceAll('{n}', '${d.inDays}');
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return l10n.tr('durMinutes').replaceAll('{m}', '$m');
    if (m == 0) return l10n.tr('durHours').replaceAll('{h}', '$h');
    return l10n.tr('durHoursMinutes').replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  }
}

/// Раскладка пересекающихся событий дня по колонкам (как у Google Календаря):
/// для каждого события — номер колонки и число колонок в его группе.
class TimedLayout {
  final CalendarEvent event;
  final DateTime start; // обрезано по дню
  final DateTime end;
  int column = 0;
  int columns = 1;
  TimedLayout(this.event, this.start, this.end);

  static List<TimedLayout> layoutDay(List<CalendarEvent> events, DateTime day) {
    final d0 = CalendarViewUtils.dayOf(day);
    final d1 = DateTime(day.year, day.month, day.day + 1);
    final items = <TimedLayout>[];
    for (final e in events) {
      if (e.isAllDay) continue;
      var s = e.startTime.toLocal();
      var en = e.endTime.toLocal();
      if (!en.isAfter(s)) en = s.add(const Duration(minutes: 30));
      if (!s.isBefore(d1) || !en.isAfter(d0)) continue;
      // Многодневное событие без «весь день» — в этот день целиком; такие
      // идут в полосу «весь день», а не на сетку.
      if (s.isBefore(d0) && !en.isBefore(d1)) continue;
      if (s.isBefore(d0)) s = d0;
      if (en.isAfter(d1)) en = d1;
      // Короткие события растягиваем до 15 минут — иначе их не нажать.
      if (en.difference(s).inMinutes < 15) en = s.add(const Duration(minutes: 15));
      items.add(TimedLayout(e, s, en));
    }
    items.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });
    // Группы пересекающихся событий; внутри — жадная раскладка по колонкам.
    var group = <TimedLayout>[];
    var groupEnd = DateTime(0);
    void flush() {
      if (group.isEmpty) return;
      final colEnds = <DateTime>[];
      for (final it in group) {
        var placed = false;
        for (var c = 0; c < colEnds.length; c++) {
          if (!it.start.isBefore(colEnds[c])) {
            it.column = c;
            colEnds[c] = it.end;
            placed = true;
            break;
          }
        }
        if (!placed) {
          it.column = colEnds.length;
          colEnds.add(it.end);
        }
      }
      for (final it in group) {
        it.columns = colEnds.length;
      }
      group = [];
    }

    for (final it in items) {
      if (group.isNotEmpty && !it.start.isBefore(groupEnd)) flush();
      group.add(it);
      if (it.end.isAfter(groupEnd)) groupEnd = it.end;
    }
    flush();
    return items;
  }

  /// События в полосе «весь день» для дня: «весь день» и многодневные.
  static List<CalendarEvent> allDayFor(List<CalendarEvent> events, DateTime day) {
    final d0 = CalendarViewUtils.dayOf(day);
    final d1 = DateTime(day.year, day.month, day.day + 1);
    return events.where((e) {
      final s = e.startTime.toLocal();
      final en = e.endTime.toLocal();
      if (!s.isBefore(d1) || !en.isAfter(d0)) return false;
      if (e.isAllDay) return true;
      return s.isBefore(d0) && !en.isBefore(d1);
    }).toList();
  }
}

/// Приглашение «нужно ответить»? Для отображения отметки в карточке.
/// (Ответ хранится в письме-приглашении; в событии — только участники.)
bool hasAttendees(CalendarEvent e) => (e.attendeesJson ?? '').length > 4;

/// Кто проводит встречу и сколько участников — для карточки в списке, чтобы
/// не открывать каждую встречу (замечание 07.10.2026). [organizer] — имя из
/// встречи или, если его нет, логин; [organizerEmail] — для поиска полного
/// ФИО (1.6.4: вместо «rizel.halilova»).
({String? organizer, String? organizerName, String? organizerEmail, int count}) attendeeSummary(CalendarEvent e) {
  var count = 0;
  String? organizer;
  final org = (e.organizerEmail ?? '').trim().toLowerCase();
  try {
    final raw = e.attendeesJson;
    if (raw != null && raw.length > 4) {
      for (final a in (jsonDecode(raw) as List).whereType<Map>()) {
        final email = (a['email'] ?? '').toString().trim().toLowerCase();
        if (email.isEmpty) continue;
        if (email == org) {
          final n = (a['displayName'] ?? a['name'])?.toString().trim();
          if (n != null && n.isNotEmpty) organizer = n;
          continue;
        }
        count++;
      }
    }
  } catch (_) {}
  final given = organizer;
  if (organizer == null && org.isNotEmpty) organizer = org.split('@').first;
  return (organizer: organizer, organizerName: given, organizerEmail: org.isEmpty ? null : org, count: count);
}

/// Таймер «текущее время» для красной линии: тикает раз в минуту.
final nowTickerProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final c = StreamController<DateTime>();
  c.add(DateTime.now());
  final t = Timer.periodic(const Duration(minutes: 1), (_) => c.add(DateTime.now()));
  ref.onDispose(() {
    t.cancel();
    c.close();
  });
  return c.stream;
});

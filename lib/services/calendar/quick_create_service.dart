// lib/services/calendar/quick_create_service.dart
// Встреча или задача из виджета «Календарь» — без входа в приложение.
//
// Кнопка «+» виджета открывает маленькое окно Android (QuickCreateActivity):
// встреча или задача, название, дата и время, ящик. Окно складывает запрос
// в очередь (SharedPreferences, ключ widget_create_queue) и будит Dart:
//  · движок приложения работает (почта приходит в фоне) — вызов «create»
//    канала ogneliss/widget, встреча создаётся сразу;
//  · движка нет — окно запускает его, очередь разбирается при запуске.
// Очередь разбирается и при открытии приложения, и в фоновой синхронизации:
// запрос не теряется, даже если в момент создания не было сети. Встреча
// создаётся тем же путём, что в приложении (сервер Exchange/CalDAV, иначе
// локально), задача — через TaskActionsService.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart' show AccountModel;
import '../../data/models/calendar_event_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider;
import '../home_widget_service.dart';
import '../mail/engine/mail_engine_service.dart';
import '../notifications/reminder_scheduler_service.dart';
import '../tasks/task_actions_service.dart' show taskActionsProvider;

final quickCreateProvider = Provider<QuickCreateService>((ref) => QuickCreateService(ref));

class QuickCreateService {
  final Ref _ref;
  QuickCreateService(this._ref);

  static const queueKey = 'widget_create_queue';
  static bool _busy = false;

  /// Разобрать очередь. Неудавшиеся запросы (нет сети и т. п.) остаются в
  /// очереди до следующего раза.
  Future<int> drain() async {
    if (_busy) return 0;
    _busy = true;
    var done = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Очередь пишет код Android в обход кэша плагина — перечитать.
      await prefs.reload();
      final raw = prefs.getString(queueKey);
      if (raw == null || raw.isEmpty) return 0;
      await prefs.remove(queueKey);
      final List<dynamic> items;
      try {
        items = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return 0;
      }
      final failed = <Object?>[];
      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, Object?>.from(it);
        try {
          final ok = m['t'] == 'task' ? await _task(m) : await _event(m);
          if (ok) {
            done++;
          } else {
            failed.add(m);
          }
        } catch (e) {
          AppLogger.warning('Создание из виджета: $e');
          final tries = ((m['tries'] as num?)?.toInt() ?? 0) + 1;
          if (tries < 20) failed.add({...m, 'tries': tries});
        }
      }
      if (failed.isNotEmpty) {
        // Новые запросы, пришедшие за время разбора, не затираем.
        await prefs.reload();
        final fresh = prefs.getString(queueKey);
        final merged = [...failed, if (fresh != null && fresh.isNotEmpty) ...(jsonDecode(fresh) as List<dynamic>)];
        await prefs.setString(queueKey, jsonEncode(merged));
      }
      if (done > 0) {
        AppLogger.info('Создано из виджета: $done');
        try {
          await _ref.read(reminderSchedulerProvider).rescheduleAll();
        } catch (_) {}
        await HomeWidgetService.updateFrom(_ref, force: true);
      }
    } catch (e) {
      AppLogger.warning('Очередь виджета: $e');
    } finally {
      _busy = false;
    }
    return done;
  }

  AccountModel? _account(String? id, {bool calendar = false}) {
    final all = _ref.read(accountsProvider).where((a) => a.isActive).toList();
    if (all.isEmpty) return null;
    final byId = all.where((a) => a.id == id).firstOrNull;
    if (byId != null) return byId;
    final active = _ref.read(activeAccountProvider);
    if (!calendar) return active ?? all.first;
    final engine = _ref.read(mailEngineServiceProvider);
    if (active != null && engine.canWriteCalendar(active)) return active;
    return all.where(engine.canWriteCalendar).firstOrNull ?? active ?? all.first;
  }

  static DateTime? ms(Object? v) =>
      v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  Future<bool> _task(Map<String, Object?> m) async {
    final title = (m['title'] as String? ?? '').trim();
    if (title.isEmpty) return true; // пустое не создаём, но и не держим в очереди
    final account = _account(m['acc'] as String?);
    if (account == null) return false;
    await _ref.read(taskActionsProvider).create(
          accountId: account.id,
          title: title,
          dueDate: ms(m['due']),
          reminderAt: ms(m['rem']),
        );
    return true;
  }

  /// Начало и конец встречи из окна виджета. Весь день — от полуночи
  /// первого дня до полуночи после последнего (как хранит Exchange); конец
  /// не позже начала — час (или сутки для «весь день»).
  static ({DateTime start, DateTime end}) eventTimes(DateTime st, DateTime? en, bool allDay) {
    if (allDay) {
      final start = DateTime(st.year, st.month, st.day);
      // Окно виджета передаёт конец как полночь следующего дня — это
      // исключающая граница, последний день — накануне.
      final last = en == null || !en.isAfter(st) ? start : en.subtract(const Duration(milliseconds: 1));
      final end = DateTime(last.year, last.month, last.day).add(const Duration(days: 1));
      return (start: start, end: end.isAfter(start) ? end : start.add(const Duration(days: 1)));
    }
    final end = en == null || !en.isAfter(st) ? st.add(const Duration(hours: 1)) : en;
    return (start: st, end: end);
  }

  Future<bool> _event(Map<String, Object?> m) async {
    final title = (m['title'] as String? ?? '').trim();
    final st = ms(m['st']);
    final en = ms(m['en']);
    if (title.isEmpty || st == null) return true;
    final allDay = m['a'] == true;
    final account = _account(m['acc'] as String?, calendar: true);
    if (account == null) return false;
    final times = eventTimes(st, en, allDay);
    final event = CalendarEventModel(
      id: const Uuid().v4(),
      accountId: account.id,
      title: title,
      startTime: times.start,
      endTime: times.end,
      isAllDay: allDay,
      organizerEmail: account.email,
      reminders: const [EventReminder(minutesBefore: 15)],
      createdAt: DateTime.now(),
    );
    final engine = _ref.read(mailEngineServiceProvider);
    var localId = event.id;
    if (engine.canWriteCalendar(account)) {
      final r = await engine.createEvent(account, event);
      if (r.created && r.id == null) return true; // придёт синхронизацией
      if (r.id != null) localId = r.id!;
      if (!r.created) {
        AppLogger.warning('Встреча из виджета: сервер не принял — сохранена на телефоне');
      }
    }
    final db = _ref.read(databaseProvider);
    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            id: localId,
            accountId: event.accountId,
            title: event.title,
            startTime: event.startTime,
            endTime: event.endTime,
            isAllDay: Value(event.isAllDay),
            organizerEmail: Value(event.organizerEmail),
            remindersJson: Value(jsonEncode([
              for (final r in event.reminders) {'minutesBefore': r.minutesBefore}
            ])),
            createdAt: event.createdAt,
          ),
          mode: InsertMode.insertOrReplace,
        );
    return true;
  }
}

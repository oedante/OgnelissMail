// lib/services/notifications/reminder_scheduler_service.dart
// Планировщик напоминаний: встречи календаря и задачи. ЕДИНСТВЕННЫЙ источник
// напоминаний (07.10.2026): прежние ежеминутные таймеры MeetingReminderService
// и TaskReminderService дублировали эти уведомления (встреча напоминала о себе
// за 60/30/15/5/0 минут независимо от своей настройки, тексты — только
// по-русски) и работали лишь при живом процессе.
//
// Локальные уведомления планируются в ОС заранее (AlarmManager), поэтому их
// перевыставляют при каждом изменении данных — старте приложения, после
// синхронизации, после правки события или задачи. Сработают и офлайн, и при
// выгруженном приложении.

import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../l10n/app_localizations.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import 'notification_service.dart';

class ReminderSchedulerService {
  final AppDatabase _db;
  final NotificationService _notifications;

  ReminderSchedulerService(this._db, this._notifications);

  /// Язык текстов уведомлений. BuildContext и Ref здесь нет (сервис работает
  /// и из фоновой синхронизации), поэтому язык читается из настроек
  /// (s_locale), иначе — системный (ru/en/de/fr), иначе английский.
  static Future<AppLocalizations> _l10n() async {
    final supported = AppLocalizations.supportedCodes;
    String? lang;
    try {
      lang = (await SharedPreferences.getInstance()).getString('s_locale');
    } catch (_) {}
    if (lang == null || !supported.contains(lang)) {
      final sys = PlatformDispatcher.instance.locale.languageCode;
      lang = supported.contains(sys) ? sys : 'en';
    }
    // Строки языка — из файла assets/l10n (1.7.3): загрузить до чтения.
    return AppLocalizations.load(lang);
  }

  /// На сколько вперёд планируем. Дальше — перепланируем при следующем запуске
  /// или синхронизации: ОС ограничивает число отложенных уведомлений (на iOS — 64).
  static const _horizon = Duration(days: 14);

  /// Ключи настроек модуля (module_settings_provider.dart, _MK).
  static const _kDefaultReminder = 'mod_default_reminder';
  static const _kEventFallback = 'mod_event_fallback_reminder';
  static const _kEventAlarmClock = 'mod_event_alarm_clock';
  static const _kTaskReminderDefault = 'mod_task_reminder';
  static const _kTaskDueHour = 'mod_task_due_hour';

  static int eventNotificationId(String accountId, String eventId, int minutesBefore) =>
      NotificationService.stableId('ev|$accountId|$eventId|$minutesBefore');

  static int taskNotificationId(String accountId, String taskId) =>
      NotificationService.stableId('task|$accountId|$taskId');

  static int snoozeNotificationId(String kind, String accountId, String id) =>
      NotificationService.stableId('snooze|$kind|$accountId|$id');

  /// Подписи выставленных уведомлений (id → время, текст, параметры).
  /// После синхронизации перевыставляются только новые и изменившиеся:
  /// раньше каждые несколько минут (после каждой синхронизации) все
  /// напоминания снимались и ставились в ОС заново — десятки вызовов
  /// AlarmManager без всякой причины (журнал 11.10.2026: 136 раз за день).
  static const _kSig = 'reminder_scheduled_sig';
  Map<String, String> _oldSig = const {};
  final Map<String, String> _newSig = {};
  bool _force = false;

  /// Уведомление [id] уже выставлено ровно таким — повторять не нужно.
  bool _unchanged(int id, String sig) {
    _newSig['$id'] = sig;
    return !_force && _oldSig['$id'] == sig;
  }

  Future<void>? _running;
  bool _again = false;
  bool _againForce = false;

  /// Перевыставить напоминания на горизонт планирования. [force] — все
  /// заново (запуск приложения, смена настроек): после «Остановить» в
  /// настройках телефона ОС забывает отложенные уведомления.
  Future<void> rescheduleAll({bool force = false}) async {
    // Вызовы во время прохода (синхронизация нескольких ящиков подряд)
    // склеиваются в один следующий проход.
    if (_running != null) {
      _again = true;
      _againForce = _againForce || force;
      return _running;
    }
    final f = _rescheduleOnce(force);
    _running = f;
    try {
      await f;
    } finally {
      _running = null;
    }
    if (_again) {
      final fr = _againForce;
      _again = false;
      _againForce = false;
      await rescheduleAll(force: fr);
    }
  }

  Future<void> _rescheduleOnce(bool force) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Фоновая синхронизация идёт в своём изоляте — подписи могли измениться там.
      try {
        await prefs.reload();
      } catch (_) {}
      // Телефон перезагружали (1.6.12): запланированные уведомления система
      // сбросила, а подписи в настройках остались — без полного прохода
      // перевыставились бы только новые и изменённые. Приёмника загрузки
      // больше нет (требование Google Play к Android 15), поэтому перезагрузку
      // узнаём по времени работы системы.
      var full = force;
      if (await _rebootedSinceLastRun(prefs) && !full) {
        AppLogger.info('Напоминания: телефон перезагружали — перевыставляю все');
        full = true;
      }
      _force = full;
      _newSig.clear();
      try {
        _oldSig = Map<String, String>.from(jsonDecode(prefs.getString(_kSig) ?? '{}') as Map);
      } catch (_) {
        _oldSig = const {};
      }
      final ids = <int>{};
      await _scheduleEvents(ids, prefs);
      await _scheduleTasks(ids, prefs);
      await _scheduleDigest(ids, prefs);
      // Напоминания встреч и задач, которых больше нет (удалены, отменены,
      // перенесены, выполнены), снимаются: раньше уведомление об удалённой
      // встрече всё равно приходило.
      const key = 'reminder_scheduled_ids';
      final old = (prefs.getStringList(key) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>();
      for (final id in old) {
        if (!ids.contains(id)) await _notifications.cancelScheduled(id);
      }
      await prefs.setStringList(key, [for (final i in ids) '$i']);
      await prefs.setString(_kSig, jsonEncode(_newSig));
    } catch (e, st) {
      AppLogger.error('Планировщик напоминаний: ошибка', e, st);
    }
  }

  /// Время загрузки системы (с точностью до минуты) изменилось с прошлого
  /// раза. Android: /proc/uptime; на других системах — false.
  static Future<bool> _rebootedSinceLastRun(SharedPreferences prefs) async {
    if (!Platform.isAndroid) return false;
    try {
      final up = double.parse((await File('/proc/uptime').readAsString()).split(' ').first);
      final boot = DateTime.now().millisecondsSinceEpoch ~/ 1000 - up.round();
      const k = 'reminders_boot_epoch';
      final prev = prefs.getInt(k);
      await prefs.setInt(k, boot);
      return prev != null && (boot - prev).abs() > 120;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────── Встречи ───────────────────────────

  /// Минуты «за сколько до» для события: свои из remindersJson, иначе —
  /// напоминание по умолчанию из настроек календаря (если включено). События
  /// «на весь день» без своего напоминания не напоминают: у Outlook это
  /// «за 18 часов» — в 6 утра накануне, такое будит, а не помогает.
  static List<int> remindersFor(CalendarEvent e, SharedPreferences prefs) {
    final own = remindersOf(e.remindersJson);
    if (own != null) return own;
    if (e.isAllDay) return const [];
    if (!(prefs.getBool(_kEventFallback) ?? true)) return const [];
    final def = prefs.getInt(_kDefaultReminder) ?? 15;
    // 0 в настройках — «Нет» (calendar_settings_screen).
    return def <= 0 ? const [] : [def];
  }

  Future<void> _scheduleEvents(Set<int> ids, SharedPreferences prefs) async {
    final now = DateTime.now();
    final until = now.add(_horizon);

    final events = await (_db.select(_db.calendarEvents)
          // С запасом назад: напоминание «за сутки» о встрече через 2 часа
          // уже прошло, а о встрече через 25 часов — нет.
          ..where((e) => e.startTime.isBiggerThanValue(now))
          ..where((e) => e.startTime.isSmallerThanValue(until))
          ..where((e) => e.isCancelled.equals(false)))
        .get();

    final l10n = await _l10n();
    var count = 0;
    for (final e in events) {
      // Свободное время (showAs = 0) — например, чужие дни рождения — не напоминаем.
      if (e.showAs == 0 && remindersOf(e.remindersJson) == null) continue;
      for (final minutes in remindersFor(e, prefs)) {
        final when = e.startTime.subtract(Duration(minutes: minutes));
        if (when.isBefore(now)) continue; // момент уже прошёл
        final nid = eventNotificationId(e.accountId, e.id, minutes);
        ids.add(nid);
        final title = e.title.isEmpty ? l10n.tr('noSubject') : e.title;
        final body = eventBody(e, minutes, l10n);
        final canJoin = (e.onlineMeetingUrl ?? '').isNotEmpty;
        final alarmClock = prefs.getBool(_kEventAlarmClock) ?? true;
        final payload = jsonEncode({
          'type': 'event',
          'id': e.id,
          'accountId': e.accountId,
          'nid': nid,
          if (canJoin) 'url': e.onlineMeetingUrl,
        });
        if (_unchanged(nid, '${when.millisecondsSinceEpoch}|$title|$body|$canJoin|$alarmClock|$payload')) continue;
        await _notifications.scheduleEventReminder(
          id: nid,
          title: title,
          body: body,
          when: when,
          canJoin: canJoin,
          alarmClock: alarmClock,
          payload: payload,
        );
        count++;
      }
    }
    if (count > 0) AppLogger.info('Запланировано напоминаний о встречах: $count (новые и изменённые)');
  }

  /// Минуты «за сколько до» из remindersJson. Формат: [{"minutesBefore": 15}].
  /// null — напоминание не задано (тогда действует умолчание); пустой список —
  /// явно «без напоминания».
  static List<int>? remindersOf(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((m) => ((m as Map<String, dynamic>)['minutesBefore'] as num?)?.toInt())
          .whereType<int>()
          .where((m) => m >= 0)
          .toList();
    } catch (_) {
      return null;
    }
  }

  static String eventBody(CalendarEvent e, int minutes, AppLocalizations l10n) {
    final s = e.startTime.toLocal();
    final at = e.isAllDay
        ? l10n.tr('reminderAllDay')
        : '${s.hour.toString().padLeft(2, '0')}:'
            '${s.minute.toString().padLeft(2, '0')}';
    final where = (e.location != null && e.location!.isNotEmpty)
        ? ' · ${e.location}'
        : '';
    if (minutes == 0) {
      return '${l10n.tr('reminderStartsNow').replaceAll('{at}', at)}$where';
    }
    if (minutes < 60) {
      return '${l10n.tr('reminderInMinutes').replaceAll('{n}', '$minutes').replaceAll('{at}', at)}$where';
    }
    if (minutes % 1440 == 0) {
      return '${l10n.tr('reminderInDays').replaceAll('{n}', '${minutes ~/ 1440}').replaceAll('{at}', at)}$where';
    }
    final h = minutes ~/ 60;
    return '${l10n.tr('reminderInHours').replaceAll('{n}', '$h').replaceAll('{at}', at)}$where';
  }

  // ─────────────────────────── Задачи ───────────────────────────

  /// Момент напоминания задачи: своё напоминание, иначе (если в настройках
  /// включено «Напоминать в срок») — срок; срок без времени — в
  /// mod_task_due_hour (9:00) того дня.
  static DateTime? taskReminderTime(Task t, SharedPreferences prefs) {
    if (t.reminderAt != null) return t.reminderAt!.toLocal();
    final due = t.dueDate?.toLocal();
    if (due == null || !(prefs.getBool(_kTaskReminderDefault) ?? false)) return null;
    if (due.hour == 0 && due.minute == 0) {
      return DateTime(due.year, due.month, due.day, prefs.getInt(_kTaskDueHour) ?? 9);
    }
    return due;
  }

  Future<void> _scheduleTasks(Set<int> ids, SharedPreferences prefs) async {
    final now = DateTime.now();
    final until = now.add(_horizon);

    final tasks = await (_db.select(_db.tasks)
          // 2 = completed, 3 = cancelled (TaskStatus)
          ..where((t) => t.status.isNotIn([2, 3]))
          ..where((t) => t.reminderAt.isNotNull() | t.dueDate.isNotNull()))
        .get();

    final l10n = await _l10n();
    var count = 0;
    for (final t in tasks) {
      final when = taskReminderTime(t, prefs);
      if (when == null || when.isBefore(now) || when.isAfter(until)) continue;
      final nid = taskNotificationId(t.accountId, t.id);
      ids.add(nid);
      final body = taskBody(t, l10n);
      if (_unchanged(nid, '${when.millisecondsSinceEpoch}|${t.title}|$body')) continue;
      await _notifications.scheduleTaskReminder(
        id: nid,
        title: t.title,
        body: body,
        when: when,
        payload: jsonEncode({'type': 'task', 'id': t.id, 'accountId': t.accountId, 'nid': nid}),
      );
      count++;
    }
    if (count > 0) AppLogger.info('Запланировано напоминаний о задачах: $count (новые и изменённые)');
  }

  // ───────────────────────── Утренняя сводка ─────────────────────────

  /// Ключи настроек (AppSettings, settings_provider.dart).
  static const _kDigest = 's_morning_digest';
  static const _kDigestMinutes = 's_morning_digest_min';

  static int digestNotificationId(DateTime day) =>
      NotificationService.stableId('digest|${day.year}-${day.month}-${day.day}');

  /// Сводка на сегодня и два следующих дня — каждая со своими числами. Если
  /// перепланирования не будет (телефон не синхронизировался), завтрашняя
  /// всё равно придёт. Пустой день — без уведомления.
  static String? _lastDigestLog;

  Future<void> _scheduleDigest(Set<int> ids, SharedPreferences prefs) async {
    if (!(prefs.getBool(_kDigest) ?? false)) return;
    final minutes = prefs.getInt(_kDigestMinutes) ?? 8 * 60;
    final now = DateTime.now();
    final l10n = await _l10n();
    final control = (prefs.getBool('s_mail_control') ?? true)
        ? (await _db.controlledEmails(activeOnly: true)).length
        : 0;
    var logged = false;
    for (var off = 0; off < 3; off++) {
      final day = DateTime(now.year, now.month, now.day + off);
      final at = day.add(Duration(minutes: minutes));
      if (!at.isAfter(now)) continue;
      final end = day.add(const Duration(days: 1));
      final events = await (_db.selectOnly(_db.calendarEvents)
            ..addColumns([_db.calendarEvents.id.count()])
            ..where(_db.calendarEvents.isCancelled.equals(false) &
                _db.calendarEvents.startTime.isSmallerThanValue(end) &
                _db.calendarEvents.endTime.isBiggerThanValue(day)))
          .map((r) => r.read(_db.calendarEvents.id.count()) ?? 0)
          .getSingle();
      // Задачи со сроком в этот день и просроченные к нему.
      final tasks = await (_db.selectOnly(_db.tasks)
            ..addColumns([_db.tasks.id.count()])
            ..where(_db.tasks.status.isNotIn(const [2, 3]) &
                _db.tasks.dueDate.isNotNull() &
                _db.tasks.dueDate.isSmallerThanValue(end)))
          .map((r) => r.read(_db.tasks.id.count()) ?? 0)
          .getSingle();
      // «Посмотреть позже», которые вернутся в этот день.
      final later = await (_db.selectOnly(_db.emails)
            ..addColumns([_db.emails.id.count()])
            ..where(_db.emails.laterState.equals(1) &
                _db.emails.remindAt.isBiggerOrEqualValue(day) &
                _db.emails.remindAt.isSmallerThanValue(end)))
          .map((r) => r.read(_db.emails.id.count()) ?? 0)
          .getSingle();
      final body = digestBody(l10n, events: events, tasks: tasks, control: control, later: later);
      if (body == null) continue;
      final nid = digestNotificationId(day);
      ids.add(nid);
      if (_unchanged(nid, '${at.millisecondsSinceEpoch}|$body')) continue;
      await _notifications.scheduleDigest(
        id: nid,
        title: l10n.tr('digestTitle'),
        body: body,
        when: at,
        payload: jsonEncode({'type': 'myday'}),
      );
      // В журнал — ближайшая сводка, только при изменении (перепланирование
      // идёт после каждой синхронизации).
      final line = '${at.day}.${at.month} ${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')} — $body';
      if (!logged) {
        logged = true;
        if (_lastDigestLog != line) {
          _lastDigestLog = line;
          AppLogger.info('Утренняя сводка запланирована: $line');
        }
      }
    }
  }

  /// «3 встречи · 2 задачи · 4 письма на контроле»; null — день пустой.
  static String? digestBody(AppLocalizations l10n,
      {required int events, required int tasks, required int control, int later = 0}) {
    final parts = [
      if (events > 0) l10n.plural('digestEventsN', events),
      if (tasks > 0) l10n.plural('digestTasksN', tasks),
      if (control > 0) l10n.plural('digestControlN', control),
      if (later > 0) l10n.plural('digestLaterN', later),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String taskBody(Task t, AppLocalizations l10n) {
    final due = t.dueDate?.toLocal();
    if (due == null) return l10n.tr('reminderTaskNoDue');
    final d = '${due.day.toString().padLeft(2, '0')}.'
        '${due.month.toString().padLeft(2, '0')}';
    final hasTime = due.hour != 0 || due.minute != 0;
    final tm = hasTime
        ? ' ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}'
        : '';
    return l10n.tr('reminderTaskDueBody').replaceAll('{when}', '$d$tm');
  }

  // ───────────────────────── Отложить ─────────────────────────

  /// «Отложить» из уведомления: показать то же напоминание снова через
  /// [delay]. Данные не меняются — переносится только уведомление.
  Future<void> snooze({
    required String kind, // 'event' | 'task'
    required String accountId,
    required String id,
    required Duration delay,
  }) async {
    final l10n = await _l10n();
    final when = DateTime.now().add(delay);
    final nid = snoozeNotificationId(kind, accountId, id);
    if (kind == 'event') {
      final e = await (_db.select(_db.calendarEvents)
            ..where((x) => x.id.equals(id) & x.accountId.equals(accountId)))
          .getSingleOrNull();
      if (e == null) return;
      final left = e.startTime.difference(when).inMinutes;
      await _notifications.scheduleEventReminder(
        id: nid,
        title: e.title,
        body: eventBody(e, left < 0 ? 0 : left, l10n),
        when: when,
        canJoin: (e.onlineMeetingUrl ?? '').isNotEmpty,
        payload: jsonEncode({
          'type': 'event', 'id': e.id, 'accountId': e.accountId, 'nid': nid,
          if ((e.onlineMeetingUrl ?? '').isNotEmpty) 'url': e.onlineMeetingUrl,
        }),
      );
    } else {
      final t = await (_db.select(_db.tasks)
            ..where((x) => x.id.equals(id) & x.accountId.equals(accountId)))
          .getSingleOrNull();
      if (t == null) return;
      await _notifications.scheduleTaskReminder(
        id: nid,
        title: t.title,
        body: taskBody(t, l10n),
        when: when,
        payload: jsonEncode({'type': 'task', 'id': t.id, 'accountId': t.accountId, 'nid': nid}),
      );
    }
  }

  // ───────────────────────── Точечная отмена ─────────────────────

  /// Снять напоминания события (при удалении/отмене).
  Future<void> cancelEvent(String accountId, String eventId, String? remindersJson) async {
    final prefs = await SharedPreferences.getInstance();
    final mins = {...?remindersOf(remindersJson), prefs.getInt(_kDefaultReminder) ?? 15};
    final ids = [for (final m in mins) eventNotificationId(accountId, eventId, m)];
    for (final id in ids) {
      await _notifications.cancelScheduled(id);
    }
    await _notifications.cancelScheduled(snoozeNotificationId('event', accountId, eventId));
    await _forgetSig(prefs, ids);
  }

  /// Снять напоминание задачи (при выполнении/удалении).
  Future<void> cancelTask(String accountId, String taskId) async {
    final id = taskNotificationId(accountId, taskId);
    await _notifications.cancelScheduled(id);
    await _notifications.cancelScheduled(snoozeNotificationId('task', accountId, taskId));
    await _forgetSig(await SharedPreferences.getInstance(), [id]);
  }

  /// Снятое вручную уведомление больше не «выставлено»: если задачу снова
  /// откроют с тем же сроком, следующий проход поставит его заново.
  Future<void> _forgetSig(SharedPreferences prefs, List<int> ids) async {
    try {
      final m = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kSig) ?? '{}') as Map);
      var changed = false;
      for (final id in ids) {
        changed = m.remove('$id') != null || changed;
      }
      if (changed) await prefs.setString(_kSig, jsonEncode(m));
    } catch (_) {}
  }
}

final reminderSchedulerProvider = Provider<ReminderSchedulerService>((ref) {
  return ReminderSchedulerService(
    ref.watch(databaseProvider),
    ref.watch(notificationServiceProvider),
  );
});

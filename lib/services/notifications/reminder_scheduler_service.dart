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
import '../assignments/assignment_codec.dart' show AssignmentStatus;
import '../assignments/assignment_store.dart';
import '../mail/own_addresses.dart';
import 'messenger_notifications.dart';
import 'notification_service.dart';
import 'notification_text.dart';

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
  static const kAssignReminder = 'mod_assign_reminder';

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
      _boxes = await _mailboxes();
      await _scheduleEvents(ids, prefs);
      await _scheduleTasks(ids, prefs);
      await _scheduleAssignments(ids, prefs);
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

  // ──────────────────────────── Ящики ────────────────────────────

  /// Ящик напоминания (12.11.2026, план 2026-11: «ящик в напоминаниях о
  /// встречах и задачах — сейчас он есть только в уведомлениях о письмах»):
  /// короткая подпись и значок — как у уведомлений о письмах, только когда
  /// подключено больше одного ящика (или ящик общий).
  Map<String, ({String label, Uint8List? icon})> _boxes = const {};

  Future<Map<String, ({String label, Uint8List? icon})>> _mailboxes() async {
    try {
      final rows = await (_db.select(_db.accounts)..where((a) => a.isActive.equals(true))).get();
      final emails = [for (final a in rows) a.email];
      final out = <String, ({String label, Uint8List? icon})>{};
      for (final a in rows) {
        final shared = (a.sharedMailboxEmail ?? '').trim().isNotEmpty;
        if (rows.length < 2 && !shared) continue;
        out[a.id] = (
          label: NotificationText.shortMailbox(a.email, emails),
          icon: await MessengerNotify.mailboxIcon(
              accountId: a.id, name: a.displayName, email: a.email, color: a.colorValue, photo: a.avatarUrl),
        );
      }
      return out;
    } catch (e) {
      AppLogger.debug('Напоминания: ящики — $e');
      return const {};
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

    // С начала суток (1.8.13): событие на весь день уже «началось» в
    // полночь, а его утреннее напоминание ещё впереди.
    final dayStart = DateTime(now.year, now.month, now.day);
    final events = await (_db.select(_db.calendarEvents)
          // С запасом назад: напоминание «за сутки» о встрече через 2 часа
          // уже прошло, а о встрече через 25 часов — нет.
          ..where((e) => e.startTime.isBiggerOrEqualValue(dayStart))
          ..where((e) => e.startTime.isSmallerThanValue(until))
          ..where((e) => e.isCancelled.equals(false)))
        .get();

    final l10n = await _l10n();
    var count = 0;
    for (final e in events) {
      // Свободное время (showAs = 0) — например, чужие дни рождения — не напоминаем.
      if (e.showAs == 0 && remindersOf(e.remindersJson) == null) continue;
      for (final minutes in remindersFor(e, prefs)) {
        final when = reminderTime(e, minutes, prefs);
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
        final box = _boxes[e.accountId];
        if (_unchanged(nid, '${when.millisecondsSinceEpoch}|$title|$body|$canJoin|$alarmClock|$payload|${box?.label}')) {
          continue;
        }
        await _notifications.scheduleEventReminder(
          id: nid,
          title: title,
          body: body,
          when: when,
          canJoin: canJoin,
          alarmClock: alarmClock,
          payload: payload,
          mailbox: box?.label,
          mailboxIcon: box?.icon,
        );
        count++;
      }
    }
    if (count > 0) AppLogger.info('Запланировано напоминаний о встречах: $count (новые и изменённые)');
  }

  /// Когда звучит напоминание «за [minutes] минут». У события на весь день
  /// «в момент начала» — утро этого дня (час из «Напоминать о сроке»,
  /// 9:00), а не полночь (1.8.13): iCloud хранит «в день события в 9:00» как
  /// напоминание после начала, оно читалось как «в момент начала» и звенело
  /// в 00:00.
  static DateTime reminderTime(CalendarEvent e, int minutes, SharedPreferences prefs) {
    if (e.isAllDay && minutes == 0) {
      final s = e.startTime.toLocal();
      return DateTime(s.year, s.month, s.day, prefs.getInt(_kTaskDueHour) ?? 9);
    }
    return e.startTime.subtract(Duration(minutes: minutes));
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
      // Весь день — утреннее напоминание в тот же день (см. reminderTime).
      if (e.isAllDay) return '${l10n.tr('reminderToday').replaceAll('{at}', at)}$where';
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
      final box = _boxes[t.accountId];
      if (_unchanged(nid, '${when.millisecondsSinceEpoch}|${t.title}|$body|${box?.label}')) continue;
      await _notifications.scheduleTaskReminder(
        id: nid,
        title: t.title,
        body: body,
        when: when,
        payload: jsonEncode({'type': 'task', 'id': t.id, 'accountId': t.accountId, 'nid': nid}),
        mailbox: box?.label,
        mailboxIcon: box?.icon,
      );
      count++;
    }
    if (count > 0) AppLogger.info('Запланировано напоминаний о задачах: $count (новые и изменённые)');
  }

  // ─────────────────────────── Поручения ───────────────────────────

  static int assignmentNotificationId(String id, String kind) =>
      NotificationService.stableId('assign|$id|$kind');

  /// Напоминания о сроках поручений [list] (просьба владельца 13.11.2026):
  /// исполнителю и соисполнителю — накануне срока и в день срока, в час
  /// [dueHour]; поручившему и контролирующему — утром после срока, если
  /// работа не сдана. Без напоминаний: общая строка проекта (напоминают
  /// его этапы), выполненные, снятые, сданные на проверку, этапы, ждущие
  /// предыдущего этапа, и наблюдателю. Только будущее, в пределах [until].
  static List<({AssignmentView v, String kind, DateTime when})> assignmentReminders(
    List<AssignmentView> list,
    DateTime now, {
    int dueHour = 9,
    DateTime? until,
  }) {
    final out = <({AssignmentView v, String kind, DateTime when})>[];
    final end = until ?? now.add(_horizon);
    void add(AssignmentView v, String kind, DateTime when) {
      if (when.isAfter(now) && !when.isAfter(end)) out.add((v: v, kind: kind, when: when));
    }

    for (final v in list) {
      final due = v.due;
      if (due == null || v.isProject) continue;
      if (v.status != AssignmentStatus.open && v.status != AssignmentStatus.inProgress) continue;
      final day = DateTime(due.year, due.month, due.day);
      // Срок со временем (13.11.2026): исполнителю — ещё за час до срока,
      // постановщику — через полчаса после срока.
      final timed = dueHasTime(due);
      if (v.iExecute || v.iCoExecute) {
        if (v.waiting) continue;
        add(v, 'tomorrow', DateTime(day.year, day.month, day.day - 1, dueHour));
        if (!timed || due.hour > dueHour + 1) add(v, 'today', DateTime(day.year, day.month, day.day, dueHour));
        if (timed) add(v, 'soon', due.subtract(const Duration(hours: 1)));
      } else if (v.outgoing || v.iControl) {
        add(v, 'late', timed ? due.add(const Duration(minutes: 30)) : DateTime(day.year, day.month, day.day + 1, dueHour));
      }
    }
    return out;
  }

  /// Текст напоминания о поручении: «Поручение: срок завтра, 14.11 · Проект».
  static String assignmentBody(AssignmentView v, String kind, AppLocalizations l10n, {String? projectTitle}) {
    final d = v.due;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = d != null && dueHasTime(d) ? ' ${two(d.hour)}:${two(d.minute)}' : '';
    final due = d == null ? '' : '${two(d.day)}.${two(d.month)}$time';
    final text = switch (kind) {
      'tomorrow' => l10n.tr('assignRemTomorrow').replaceAll('{due}', due),
      'today' => '${l10n.tr('assignRemToday')}${time.isEmpty ? '' : ',$time'}',
      'soon' => '${l10n.tr('assignRemToday')},$time',
      _ => l10n.tr('assignRemLate').replaceAll('{due}', due).replaceAll('{name}', v.otherName),
    };
    final p = (projectTitle ?? '').trim();
    return p.isEmpty ? text : '$text · $p';
  }

  /// Мои адреса по ящикам — для ролей в поручениях (без Riverpod: и из
  /// фоновой синхронизации).
  Future<Map<String, Set<String>>> _myAddresses() async {
    final rows = await (_db.select(_db.accounts)..where((a) => a.isActive.equals(true))).get();
    return {
      for (final a in rows)
        a.id: {
          a.email.trim().toLowerCase(),
          if ((a.sharedMailboxEmail ?? '').trim().isNotEmpty) a.sharedMailboxEmail!.trim().toLowerCase(),
          ...OwnAddresses.extraFor(a.id),
          ...OwnAddresses.sameMailbox(a.email),
        }..removeWhere((e) => !e.contains('@')),
    };
  }

  Future<void> _scheduleAssignments(Set<int> ids, SharedPreferences prefs) async {
    if (!(prefs.getBool(kAssignReminder) ?? true)) return;
    final mine = await _myAddresses();
    if (mine.isEmpty) return;
    final list = await AssignmentStore.all(_db, mine);
    if (list.isEmpty) return;
    final plan = assignmentReminders(list, DateTime.now(), dueHour: prefs.getInt(_kTaskDueHour) ?? 9);
    if (plan.isEmpty) return;
    final l10n = await _l10n();
    final titles = {for (final v in list) v.id: v.row.title};
    var count = 0;
    for (final r in plan) {
      final v = r.v;
      final nid = assignmentNotificationId(v.id, r.kind);
      ids.add(nid);
      final body = assignmentBody(v, r.kind, l10n, projectTitle: v.parentId == null ? null : titles[v.parentId]);
      final box = _boxes[v.row.accountId];
      final payload = jsonEncode({
        'type': 'assignment',
        'id': v.id,
        'accountId': v.row.accountId,
        'nid': nid,
        't': v.row.title,
        'b': body,
      });
      if (_unchanged(nid, '${r.when.millisecondsSinceEpoch}|$payload|${box?.label}')) continue;
      await _notifications.scheduleAssignmentReminder(
        id: nid,
        title: v.row.title,
        body: body,
        when: r.when,
        payload: payload,
        mailbox: box?.label,
        mailboxIcon: box?.icon,
      );
      count++;
    }
    if (count > 0) AppLogger.info('Запланировано напоминаний о поручениях: $count (новые и изменённые)');
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
    required String kind, // 'event' | 'task' | 'assignment'
    required String accountId,
    required String id,
    required Duration delay,
    /// Поручение: заголовок и текст прежнего уведомления.
    ({String? title, String? body})? text,
  }) async {
    final l10n = await _l10n();
    final when = DateTime.now().add(delay);
    final nid = snoozeNotificationId(kind, accountId, id);
    final boxes = await _mailboxes();
    if (kind == 'assignment') {
      final a = await AssignmentStore.byId(_db, id);
      if (a == null || !AssignmentStatus.isActive(a.status)) return;
      final body = text?.body ?? '';
      await _notifications.scheduleAssignmentReminder(
        id: nid,
        title: text?.title ?? a.title,
        body: body,
        when: when,
        payload: jsonEncode({
          'type': 'assignment', 'id': id, 'accountId': a.accountId, 'nid': nid,
          't': text?.title ?? a.title, 'b': body,
        }),
        mailbox: boxes[a.accountId]?.label,
        mailboxIcon: boxes[a.accountId]?.icon,
      );
    } else if (kind == 'event') {
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
        mailbox: boxes[accountId]?.label,
        mailboxIcon: boxes[accountId]?.icon,
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
        mailbox: boxes[accountId]?.label,
        mailboxIcon: boxes[accountId]?.icon,
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

// lib/services/home_widget_service.dart
// Виджеты рабочего стола («Мой день», «Почта», «Календарь», «Заметки»):
// данные готовит приложение, рисует система — Android (HomeWidgets.kt,
// RemoteViews), iPhone (ios/OgnelissWidgets, WidgetKit; данные — через
// App Group, см. WidgetBridgePlugin.swift).
//
// Приложение после синхронизации (и при открытии/сворачивании) пишет в
// SharedPreferences ключ widget_myday — JSON с уже переведёнными строками:
// дата, ближайшие встречи и задачи на сегодня (со временем окончания),
// число непрочитанных и писем «в работе». Виджет сам скрывает прошедшее по
// времени окончания, поэтому между обновлениями он не устаревает.
// Обновить виджет сразу — канал ogneliss/widget («refresh»); в фоновом
// процессе WorkManager канала нет — тогда виджет перечитает данные при
// плановом обновлении системы (раз в 30 минут).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../data/database/app_database.dart';
import '../data/models/account_model.dart' show AccountModel;
import '../data/models/folder_model.dart' show FolderType;
import '../data/providers/database_provider.dart';
import '../features/settings/providers/widget_prefs.dart' show WidgetThemeNotifier, widgetThemeProvider;
import '../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../features/settings/providers/settings_provider.dart';
import 'security/pin_lock_service.dart' show pinLockProvider;
import '../l10n/app_localizations.dart';
import 'mail/control_service.dart' show ControlState;
import 'calendar/meeting_link_service.dart';
import 'sync/mail_freshness.dart';
import 'sync/sync_schedule.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const prefKey = 'widget_myday';
  static const mailKey = 'widget_mail';
  static const calendarKey = 'widget_calendar';
  static const notesKey = 'widget_notes';
  static const _channel = MethodChannel('ogneliss/widget');
  static String? _lastJson;
  static DateTime? _lastAt;

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  /// Обновить данные виджета из Riverpod (синхронизация).
  static Future<void> updateFrom(Ref ref, {bool force = false}) async {
    if (!_supported) return;
    try {
      await _updateFromState(ref.read(settingsProvider), ref.read(databaseProvider), ref.read(accountsProvider),
          ref.read(pinLockProvider).isPinSet, force);
    } catch (e) {
      AppLogger.debug('Виджет: $e');
    }
  }

  /// То же из ProviderContainer (запуск, сворачивание приложения).
  static Future<void> updateFromContainer(ProviderContainer c, {bool force = false}) async {
    if (!_supported) return;
    try {
      await _updateFromState(c.read(settingsProvider), c.read(databaseProvider), c.read(accountsProvider),
          c.read(pinLockProvider).isPinSet, force);
    } catch (e) {
      AppLogger.debug('Виджет: $e');
    }
  }

  static Future<void> _updateFromState(
      AppSettings settings, AppDatabase db, List<AccountModel> all, bool pinSet, bool force) {
    // Выключенные ящики в виджетах не показываем — как и в приложении.
    final accounts = [for (final a in all) if (a.isActive) a];
    return update(
      db,
      [for (final a in accounts) a.id],
      AppLocalizations(settings.locale),
      showControl: settings.mailControl,
      // С PIN-кодом на рабочем столе — только время и счётчики: темы писем
      // и названия встреч видны без разблокировки.
      private: pinSet,
      colors: {for (final a in accounts) a.id: a.colorValue},
      labels: {
        for (final a in accounts)
          a.id: a.displayName.trim().isNotEmpty && a.displayName.trim().toLowerCase() != a.email.toLowerCase()
              ? a.displayName.trim()
              : a.email.split('@').first,
      },
      force: force,
      activeAccountId: settings.activeAccountId,
      // «Обновлено в …» в виджете «Почта» (1.6.48): после скольких минут
      // без обновления ящик «давний». Ящики «вручную» не в счёт; общая
      // проверка «Никогда» — давних нет.
      staleMin: settings.syncIntervalMinutes < 0
          ? const {}
          : {
              for (final a in accounts)
                if (MailFreshness.expectedMinutes(a, DateTime.now()) case final m?)
                  a.id: widgetStaleMinutes(a, m),
            },
    );
  }

  /// Виджет перерисовывается редко (данные — после синхронизации, иначе —
  /// раз в 30 минут), поэтому порог мягче, чем в шапке ленты: не меньше
  /// часа (ночью Android откладывает фоновые задачи), у push — его резервная
  /// проверка раз в 30 минут.
  static int widgetStaleMinutes(AccountModel a, int everyMin) {
    final every = SyncSchedule.pushNow(a) ? 30 : everyMin;
    return math.max(every * 2 + 5, 60);
  }

  static Future<void> update(AppDatabase db, List<String> ids, AppLocalizations l10n,
      {bool showControl = true,
      bool private = false,
      Map<String, String> labels = const {},
      Map<String, int> colors = const {},
      bool force = false,
      String? activeAccountId,
      Map<String, int> staleMin = const {}}) async {
    if (!_supported) return;
    // Не чаще раза в 20 секунд: синхронизации идут пачками по ящикам.
    final now = DateTime.now();
    if (!force && _lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 20)) return;
    _lastAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Доска включена в «Моём дне» — виджет тоже показывает колонки.
      final board = prefs.getBool('myday_board') ?? false;
      final json = jsonEncode(await _build(db, ids, l10n, showControl, now, private, board: board));
      final mail = jsonEncode(await _buildMail(db, ids, l10n, now, private, labels, colors, staleMin));
      // Календарь — те ящики, что включены в «хабе» календаря в приложении.
      final hidden = {...?prefs.getStringList('cal_hidden_accounts')};
      final calIds = [for (final id in ids) if (!hidden.contains(id)) id];
      final cal = jsonEncode(await _buildCalendar(db, calIds, l10n, now, private, colors, labels, ids, activeAccountId));
      final notes = jsonEncode(await _buildNotes(db, l10n, private));
      if (json + mail + cal + notes == _lastJson && !force) return;
      _lastJson = json + mail + cal + notes;
      await prefs.setString(notesKey, notes);
      await prefs.setString(prefKey, json);
      await prefs.setString(mailKey, mail);
      await prefs.setString(calendarKey, cal);
      // iPhone: расширение виджетов читает общий контейнер App Group, а не
      // настройки приложения — те же JSON передаются туда.
      if (_ios) {
        try {
          for (final e in {prefKey: json, mailKey: mail, calendarKey: cal, notesKey: notes}.entries) {
            await _channel.invokeMethod<void>('save', {'key': e.key, 'json': e.value});
          }
        } on MissingPluginException {
          // Канал не зарегистрирован (старый движок) — виджеты без данных.
        }
      }
      try {
        await _channel.invokeMethod<void>('refresh');
      } on MissingPluginException {
        // Фоновый процесс: виджет обновится по расписанию системы.
      }
    } catch (e) {
      AppLogger.debug('Виджет «Мой день»: $e');
    }
  }

  static Future<Map<String, Object?>> _build(
      AppDatabase db, List<String> ids, AppLocalizations l10n, bool showControl, DateTime now, bool private,
      {bool board = false}) async {
    final lang = l10n.locale.languageCode;
    String date;
    try {
      date = DateFormat('EEE, d MMM', lang).format(now);
    } catch (_) {
      date = '${now.day}.${now.month.toString().padLeft(2, '0')}';
    }
    final hm = DateFormat('HH:mm');
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final items = <Map<String, Object?>>[];
    final inWork = <Map<String, Object?>>[];
    final done = <Map<String, Object?>>[];
    var unread = 0;
    var work = 0;

    if (ids.isNotEmpty) {
      final events = await (db.select(db.calendarEvents)
            ..where((e) => e.accountId.isIn(ids))
            ..where((e) => e.isCancelled.equals(false))
            ..where((e) => e.startTime.isSmallerThanValue(end))
            ..where((e) => e.endTime.isBiggerThanValue(now))
            ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
            ..limit(20))
          .get();
      for (final e in events) {
        items.add({
          't': e.isAllDay ? l10n.tr('myDayAllDay') : hm.format(e.startTime),
          's': private ? l10n.tr('widgetMeeting') : (e.title.trim().isEmpty ? '—' : e.title.trim()),
          'at': e.isAllDay ? start.millisecondsSinceEpoch : e.startTime.millisecondsSinceEpoch,
          'end': (e.isAllDay ? end : e.endTime).millisecondsSinceEpoch,
          'k': 'e',
        });
      }
      // Задачи на сегодня со временем (срок или напоминание), невыполненные.
      final tasks = await (db.select(db.tasks)
            ..where((t) => t.accountId.isIn(ids))
            ..where((t) => t.status.isNotIn(const [2, 3]))
            ..where((t) =>
                (t.reminderAt.isNotNull() & t.reminderAt.isBiggerOrEqualValue(start) & t.reminderAt.isSmallerThanValue(end)) |
                (t.dueDate.isNotNull() & t.dueDate.isBiggerOrEqualValue(start) & t.dueDate.isSmallerThanValue(end)))
            ..limit(20))
          .get();
      for (final t in tasks) {
        final at = t.reminderAt ?? t.dueDate!;
        final hasTime = at.hour != 0 || at.minute != 0;
        items.add({
          't': hasTime ? hm.format(at) : '✓',
          's': private ? l10n.tr('myDayTask') : t.title.trim(),
          'at': at.millisecondsSinceEpoch,
          // Задача без времени — до конца дня; со временем — час после.
          'end': (hasTime ? at.add(const Duration(hours: 1)) : end).millisecondsSinceEpoch,
          'k': 't',
          // «В работе» — на доске в своей колонке, не в «Предстоит».
          if (t.status == 1) 'ip': true,
        });
      }
      items.sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));

      if (board) {
        // Колонки доски — как на экране «Мой день»: в работе — задачи «в
        // работе»; готово — выполненные сегодня и прошедшие сегодня встречи.
        String title(String s, String fallback) => private ? fallback : (s.trim().isEmpty ? '—' : s.trim());
        for (final t in await (db.select(db.tasks)
              ..where((t) => t.accountId.isIn(ids))
              ..where((t) => t.status.equals(1))
              ..limit(20))
            .get()) {
          inWork.add({'s': title(t.title, l10n.tr('myDayTask'))});
        }
        for (final t in await (db.select(db.tasks)
              ..where((t) => t.accountId.isIn(ids))
              ..where((t) => t.status.equals(2))
              ..where((t) => t.completedAt.isBiggerOrEqualValue(start))
              ..orderBy([(t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc)])
              ..limit(20))
            .get()) {
          done.add({'s': '✓ ${title(t.title, l10n.tr('myDayTask'))}'});
        }
        for (final e in await (db.select(db.calendarEvents)
              ..where((e) => e.accountId.isIn(ids))
              ..where((e) => e.isCancelled.equals(false))
              ..where((e) => e.isAllDay.equals(false))
              ..where((e) => e.startTime.isBiggerOrEqualValue(start))
              ..where((e) => e.endTime.isSmallerOrEqualValue(now))
              ..orderBy([(e) => OrderingTerm(expression: e.startTime, mode: OrderingMode.desc)])
              ..limit(20))
            .get()) {
          done.add({'s': '${hm.format(e.startTime)} ${title(e.title, l10n.tr('widgetMeeting'))}'});
        }
      }

      final inboxIds = await (db.selectOnly(db.folders)
            ..addColumns([db.folders.id])
            ..where(db.folders.accountId.isIn(ids) & db.folders.type.equals(FolderType.inbox.index)))
          .map((r) => r.read(db.folders.id)!)
          .get();
      if (inboxIds.isNotEmpty) {
        unread = await (db.selectOnly(db.emails)
              ..addColumns([db.emails.id.count()])
              ..where(db.emails.accountId.isIn(ids) &
                  db.emails.folderId.isIn(inboxIds) &
                  db.emails.isRead.equals(false)))
            .map((r) => r.read(db.emails.id.count()) ?? 0)
            .getSingle();
      }
      if (showControl) {
        work = (await db.controlledEmails(accountIds: ids))
            .where((m) => ControlState.isActive(m.controlState))
            .length;
      }
    }

    return {
      'lang': lang,
      'title': l10n.tr('myDay'),
      'date': date,
      'empty': l10n.tr('myDayNoMore'),
      'compose': l10n.tr('shortcutCompose'),
      'unread': unread > 0 ? l10n.tr('myDayUnreadCount').replaceAll('{n}', '$unread') : '',
      'work': work > 0 ? l10n.tr('myDayInWorkCount').replaceAll('{n}', '$work') : '',
      'items': items.take(12).toList(),
      'more': l10n.tr('widgetMore'),
      if (board) ...{
        'board': true,
        'cols': [
          {
            'title': l10n.tr('boardUpcoming'),
            'items': [
              for (final i in items.take(20))
                if (i['ip'] != true) {'s': '${i['t']} ${i['s']}', 'end': i['end']},
            ],
          },
          {'title': l10n.tr('boardInWork'), 'items': inWork},
          {'title': l10n.tr('boardDone'), 'items': done},
        ],
      },
      'updated': now.millisecondsSinceEpoch,
    };
  }

  /// Виджет «Почта»: непрочитанные во «Входящих» по ящикам и четыре
  /// последних непрочитанных письма (нажатие — письмо).
  static Future<Map<String, Object?>> _buildMail(AppDatabase db, List<String> ids, AppLocalizations l10n,
      DateTime now, bool private, Map<String, String> labels,
      [Map<String, int> colors = const {}, Map<String, int> staleMin = const {}]) async {
    final rows = <Map<String, Object?>>[];
    final perAccount = <String, int>{};
    var total = 0;
    if (ids.isNotEmpty) {
      final inboxes = await (db.select(db.folders)
            ..where((f) => f.accountId.isIn(ids) & f.type.equals(FolderType.inbox.index)))
          .get();
      final inboxIds = [for (final f in inboxes) f.id];
      if (inboxIds.isNotEmpty) {
        final cnt = db.emails.id.count();
        final counts = await (db.selectOnly(db.emails)
              ..addColumns([db.emails.accountId, cnt])
              ..where(db.emails.accountId.isIn(ids) &
                  db.emails.folderId.isIn(inboxIds) &
                  db.emails.isRead.equals(false))
              ..groupBy([db.emails.accountId]))
            .get();
        for (final r in counts) {
          final n = r.read(cnt) ?? 0;
          perAccount[r.read(db.emails.accountId)!] = n;
          total += n;
        }
        final latest = await (db.select(db.emails)
              ..where((e) => e.accountId.isIn(ids))
              ..where((e) => e.folderId.isIn(inboxIds))
              ..where((e) => e.isRead.equals(false))
              ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
              // Android показывает столько, сколько помещается по высоте
              // виджета (до 10), iPhone — первые строки.
              ..limit(10))
            .get();
        final today = DateTime(now.year, now.month, now.day);
        for (final m in latest) {
          final at = m.receivedAt;
          final name = (m.fromName ?? '').trim().isNotEmpty ? m.fromName!.trim() : m.fromEmail;
          rows.add({
            'f': private ? (labels[m.accountId] ?? '') : name,
            's': private ? '' : (m.subject.trim().isEmpty ? '—' : m.subject.trim()),
            't': at.isBefore(today) ? DateFormat('dd.MM').format(at) : DateFormat('HH:mm').format(at),
            // Цвет ящика — метка слева от письма (несколько ящиков).
            if (ids.length > 1 && colors[m.accountId] != null) 'c': colors[m.accountId],
            'open': Uri(path: 'email', queryParameters: {'id': m.id, 'acc': m.accountId}).toString(),
          });
        }
      }
    }
    // Когда почта обновлялась (1.6.48): по самому давнему ящику с
    // автоматической проверкой; «давно» виджет считает сам при показе
    // (staleAt — когда первый из ящиков станет давним).
    int? upd;
    int? staleAt;
    if (ids.isNotEmpty) {
      final accRows = await (db.select(db.accounts)..where((a) => a.id.isIn(ids))).get();
      final auto = [for (final r in accRows) if (staleMin.containsKey(r.id)) r];
      for (final r in auto.isNotEmpty ? auto : accRows) {
        final at = r.lastSyncAt;
        if (at == null) continue;
        final ms = at.millisecondsSinceEpoch;
        if (upd == null || ms < upd) upd = ms;
        final lim = staleMin[r.id];
        if (lim != null) {
          final s = ms + lim * 60000;
          if (staleAt == null || s < staleAt) staleAt = s;
        }
      }
    }
    return {
      'title': l10n.tr('mail'),
      'lang': l10n.locale.languageCode,
      if (upd != null) 'upd': upd,
      if (staleAt != null) 'staleAt': staleAt,
      'updAt': l10n.tr('mailUpdatedAt'),
      'updOn': l10n.tr('mailUpdatedOn'),
      'updStale': l10n.tr('mailNotUpdatedSince'),
      'count': total > 0 ? '$total' : '',
      'empty': l10n.tr('widgetNoUnread'),
      'compose': l10n.tr('shortcutCompose'),
      // Счётчики ящиков — в порядке из настроек.
      'accounts': [
        for (final id in ids)
          if ((perAccount[id] ?? 0) > 0) '${labels[id] ?? ''} ${perAccount[id]}',
      ].join(' · '),
      'items': rows,
    };
  }

  /// Виджет «Календарь»: встречи всех включённых ящиков на 14 дней вперёд,
  /// с цветом ящика. Подписи дней («Сегодня», «Завтра», дата) виджет
  /// считает сам по началу дня — после полуночи они не устаревают.
  static Future<Map<String, Object?>> _buildCalendar(AppDatabase db, List<String> ids, AppLocalizations l10n,
      DateTime now, bool private, Map<String, int> colors,
      [Map<String, String> labels = const {}, List<String> allIds = const [], String? activeAccountId]) async {
    final hm = DateFormat('HH:mm');
    final today = DateTime(now.year, now.month, now.day);
    final until = today.add(const Duration(days: 14));
    final items = <Map<String, Object?>>[];
    if (ids.isNotEmpty) {
      final events = await (db.select(db.calendarEvents)
            ..where((e) => e.accountId.isIn(ids))
            ..where((e) => e.isCancelled.equals(false))
            ..where((e) => e.startTime.isSmallerThanValue(until))
            ..where((e) => e.endTime.isBiggerThanValue(now))
            ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
            ..limit(40))
          .get();
      for (final e in events) {
        final st = e.startTime.toLocal();
        final en = e.endTime.toLocal();
        // Многодневное, начавшееся раньше, — показываем на сегодня.
        final s0 = st.isBefore(today) ? today : st;
        final day = DateTime(s0.year, s0.month, s0.day);
        // Онлайн-встреча — кнопка «Подключиться» в виджете (ссылка не
        // передаётся при PIN-коде: она открывает встречу без разблокировки).
        final link = (e.onlineMeetingUrl ?? '').isNotEmpty
            ? MeetingLink(MeetingLinkService.platformOf(e.onlineMeetingUrl!) ?? '', e.onlineMeetingUrl!)
            : MeetingLinkService.find(location: e.location, description: e.description);
        items.add({
          'day': day.millisecondsSinceEpoch,
          'st': st.millisecondsSinceEpoch,
          if (link != null && !private) 'join': link.url,
          't': e.isAllDay || st.isBefore(today) ? l10n.tr('myDayAllDay') : hm.format(st),
          's': private ? l10n.tr('widgetMeeting') : (e.title.trim().isEmpty ? '—' : e.title.trim()),
          'end': en.millisecondsSinceEpoch,
          'c': colors[e.accountId] ?? 0xFF5C7CFA,
          'open': Uri(path: 'calevent', queryParameters: {'id': e.id, 'acc': e.accountId}).toString(),
        });
      }
    }
    // Android: три вида (день, неделя, месяц) с листанием — встречи с начала
    // прошлого месяца до конца позапрошлого вперёд, включая прошедшие
    // (точки в сетке месяца). Время подписывает сам виджет.
    final events = <Map<String, Object?>>[];
    if (ids.isNotEmpty) {
      final from = DateTime(now.year, now.month - 1, 1);
      final to = DateTime(now.year, now.month + 3, 1);
      final rows = await (db.select(db.calendarEvents)
            ..where((e) => e.accountId.isIn(ids))
            ..where((e) => e.isCancelled.equals(false))
            ..where((e) => e.startTime.isSmallerThanValue(to))
            ..where((e) => e.endTime.isBiggerThanValue(from))
            ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
            ..limit(600))
          .get();
      for (final e in rows) {
        final st = e.startTime.toLocal();
        var en = e.endTime.toLocal();
        if (!en.isAfter(st)) en = st.add(Duration(minutes: e.isAllDay ? 24 * 60 : 30));
        final link = private
            ? null
            : (e.onlineMeetingUrl ?? '').isNotEmpty
                ? e.onlineMeetingUrl
                : MeetingLinkService.find(location: e.location, description: e.description)?.url;
        events.add({
          'st': st.millisecondsSinceEpoch,
          'en': en.millisecondsSinceEpoch,
          if (e.isAllDay) 'a': 1,
          's': private ? l10n.tr('widgetMeeting') : (e.title.trim().isEmpty ? '—' : e.title.trim()),
          if (!private && (e.location ?? '').trim().isNotEmpty) 'l': e.location!.trim(),
          'c': colors[e.accountId] ?? 0xFF5C7CFA,
          'o': Uri(path: 'calevent', queryParameters: {'id': e.id, 'acc': e.accountId}).toString(),
          if (link != null && link.isNotEmpty) 'j': link,
        });
      }
    }
    return {
      'lang': l10n.locale.languageCode,
      'private': private,
      'events': events,
      'tabs': [l10n.tr('viewDay'), l10n.tr('viewWeek'), l10n.tr('viewMonth')],
      // Окно «Создать» виджета: ящики (порядок из настроек; первым —
      // активный) и подписи на языке приложения.
      'defaultAccount': activeAccountId ?? '',
      'accounts': [
        for (final id in allIds) {'id': id, 'label': labels[id] ?? '', 'c': colors[id] ?? 0xFF5C7CFA},
      ],
      'qc': {
        'title': l10n.tr('calendarCreate'),
        'event': l10n.tr('qcMeeting'),
        'task': l10n.tr('qcTask'),
        'name': l10n.tr('qcName'),
        'allDay': l10n.tr('myDayAllDay'),
        'remind': l10n.tr('qcRemind'),
        'noDate': l10n.tr('qcNoDate'),
        'account': l10n.tr('qcAccount'),
        'cancel': l10n.tr('cancel'),
        'create': l10n.tr('create'),
        'empty': l10n.tr('qcNameEmpty'),
        'done': l10n.tr('qcCreated'),
      },
      'allDay': l10n.tr('myDayAllDay'),
      'free': l10n.tr('widgetDayFree'),
      'freeWeek': l10n.tr('widgetWeekFree'),
      'more': l10n.tr('widgetMore'),
      'title': l10n.tr('calendar'),
      'today': l10n.tr('today'),
      'tomorrow': l10n.tr('tomorrow'),
      'empty': l10n.tr('widgetNoEvents'),
      'add': l10n.tr('calendarCreate'),
      'joinLabel': l10n.tr('joinMeeting'),
      'items': items,
    };
  }

  /// Виджет «Заметки»: пять последних заметок (заголовок и первая строка
  /// текста), «+» — новая заметка. С PIN-кодом — только число заметок.
  static Future<Map<String, Object?>> _buildNotes(AppDatabase db, AppLocalizations l10n, bool private) async {
    final rows = await (db.select(db.notes)
          ..where((n) => n.isDeleted.equals(false))
          ..orderBy([(n) => OrderingTerm(expression: n.modifiedAt, mode: OrderingMode.desc)])
          ..limit(8))
        .get();
    final total = await (db.selectOnly(db.notes)
          ..addColumns([db.notes.id.count()])
          ..where(db.notes.isDeleted.equals(false)))
        .map((r) => r.read(db.notes.id.count()) ?? 0)
        .getSingle();
    String plain(String s) => s
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'[#*_>`\[\]]'), '')
        .trim();
    final items = <Map<String, Object?>>[];
    if (!private) {
      for (final n in rows) {
        final lines = plain(n.body).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        final title = n.title.trim().isNotEmpty ? n.title.trim() : (lines.isNotEmpty ? lines.removeAt(0) : '—');
        items.add({
          's': title,
          'p': lines.isNotEmpty ? lines.first : '',
          'open': Uri(path: 'note', queryParameters: {'id': n.id}).toString(),
        });
      }
    }
    return {
      'title': l10n.tr('notes'),
      'count': total > 0 ? '$total' : '',
      'empty': private ? l10n.tr('widgetNotesLocked') : l10n.tr('widgetNoNotes'),
      'add': l10n.tr('newNote'),
      'items': items,
    };
  }

  /// Запуск: нажатия на виджет, первое заполнение и обновление при
  /// сворачивании приложения (на рабочем столе виджет сразу свежий).
  static AppLifecycleListener? _life;

  /// Разбор очереди «Создать» из виджета (подключается в main).
  static Future<void> Function()? onCreate;
  static StreamSubscription<Set<TableUpdate>>? _notesSub;
  static Future<void> init(ProviderContainer container, Future<void> Function(String type) open) async {
    if (!_supported) return;
    _life ??= AppLifecycleListener(
      onHide: () => updateFromContainer(container, force: true),
      onResume: () => updateFromContainer(container),
    );
    await listenOpens(open);
    // Заметку сохранили или удалили — виджет «Заметки» обновляется через
    // пару секунд (без ожидания синхронизации).
    Timer? debounce;
    _notesSub ??= container
        .read(databaseProvider)
        .tableUpdates(const TableUpdateQuery.onTableName('notes'))
        .listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(seconds: 2), () => updateFromContainer(container, force: true));
    });
    // Аккаунты грузятся асинхронно — первое заполнение чуть позже.
    Future<void>.delayed(const Duration(seconds: 5), () => updateFromContainer(container, force: true));
    // Тема виджетов iPhone — в общий контейнер (после переустановки его нет).
    unawaited(WidgetThemeNotifier.pushToIos(container.read(widgetThemeProvider)));
  }

  /// Нажатие на виджет: какой экран открыть («myday», «compose»). Холодный
  /// запуск — значение забирается при старте; приложение уже открыто —
  /// приходит вызов «open».
  static Future<void> listenOpens(Future<void> Function(String type) open) async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final t = await _take();
        if (t != null) await open(t);
      } else if (call.method == 'create') {
        // Окно виджета «Создать» положило встречу или задачу в очередь.
        await onCreate?.call();
      }
      return null;
    });
    final t = await _take();
    if (t != null) await open(t);
  }

  static Future<String?> _take() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } catch (_) {
      return null;
    }
  }
}

// lib/services/mail/dav/dav_pim_service.dart
// Календарь (CalDAV) и контакты (CardDAV) для почты, где PIM не приходит по
// IMAP: Google, Яндекс, Mail.ru, Yahoo.
//
// Как входим (заголовок готовит DavCredentials):
//   Google — OAuth-токен «Bearer», scope calendar + carddav;
//   Яндекс — OAuth-токен «OAuth», права calendar:all + addressbook:all;
//            без OAuth — пароль приложения;
//   Mail.ru — только пароль внешнего приложения (OAuth календарь не даёт),
//             контакты Mail.ru по CardDAV не отдаёт;
//   Yahoo  — пароль приложения.
// Отказ сервера (401/403) — нормальный исход: пустой список и пауза 6 часов.

import 'dart:convert';
import 'dart:math' show Random;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/account_model.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/task_model.dart';
import '../../../core/logging/app_logger.dart';
import '../../calendar/eas_recurrence.dart';
import 'dav_client.dart';
import 'ical_parser.dart';
import 'vcard_parser.dart';

class DavPimService {
  /// Откуда начинать обнаружение и куда идти, если сервер не отдал список
  /// коллекций. У Google корень `/caldav/v2` и `/carddav/v1` — не ресурсы:
  /// начинать нужно с principal пользователя. Остальные серверы отвечают на
  /// current-user-principal от корня.
  static ({String start, List<String> fallback})? _calendarEndpoints(String provider, String email) {
    final e = Uri.encodeComponent(email);
    switch (provider) {
      case 'google':
        return (
          start: 'https://apidata.googleusercontent.com/caldav/v2/$e/user',
          fallback: ['https://apidata.googleusercontent.com/caldav/v2/$e/events/'],
        );
      case 'yandex':
        return (start: 'https://caldav.yandex.ru/', fallback: const []);
      case 'mailru':
        return (start: 'https://calendar.mail.ru/', fallback: const []);
      case 'yahoo':
        return (start: 'https://caldav.calendar.yahoo.com/', fallback: const []);
      // iCloud (1.6.12): principal с корня, пароль приложения Apple.
      case 'icloud':
        return (start: 'https://caldav.icloud.com/', fallback: const []);
    }
    return null;
  }

  static ({String start, List<String> fallback})? _contactsEndpoints(String provider, String email) {
    final e = Uri.encodeComponent(email);
    switch (provider) {
      case 'google':
        return (
          start: 'https://www.googleapis.com/carddav/v1/principals/$e',
          fallback: ['https://www.googleapis.com/carddav/v1/principals/$e/lists/default/'],
        );
      case 'yandex':
        return (start: 'https://carddav.yandex.ru/', fallback: const []);
      case 'yahoo':
        return (start: 'https://carddav.address.yahoo.com/', fallback: const []);
      case 'icloud':
        return (start: 'https://contacts.icloud.com/', fallback: const []);
      // mail.ru: CardDAV нет.
    }
    return null;
  }

  static const _yandexDomains = {
    'yandex.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua', 'ya.ru', 'narod.ru',
  };
  static const _icloudDomains = {'icloud.com', 'me.com', 'mac.com'};
  static const _mailruDomains = {
    'mail.ru', 'inbox.ru', 'list.ru', 'bk.ru', 'internet.ru', 'mail.ua', 'xmail.ru',
  };

  /// Провайдер — по типу аккаунта, а для IMAP — по домену. Яндекс 360 и
  /// Google Workspace на своих доменах узнаются только по типу аккаунта.
  static String? providerOf(AccountModel account) {
    switch (account.type) {
      case AccountType.google:
        return 'google';
      case AccountType.yandex:
        return 'yandex';
      case AccountType.mailru:
        return 'mailru';
      case AccountType.yahoo:
        return 'yahoo';
      case AccountType.imap:
        break;
      default:
        return null; // Exchange/EAS — PIM приходит по своему протоколу
    }
    final d = account.email.split('@').last.toLowerCase();
    if (_yandexDomains.contains(d)) return 'yandex';
    if (_mailruDomains.contains(d)) return 'mailru';
    if (d == 'gmail.com' || d == 'googlemail.com') return 'google';
    if (d.startsWith('yahoo.') || d == 'ymail.com') return 'yahoo';
    if (_icloudDomains.contains(d) || (account.imapServer ?? '').toLowerCase() == 'imap.mail.me.com') {
      return 'icloud';
    }
    return null;
  }

  /// Есть ли у провайдера контакты по CardDAV.
  static bool hasContacts(String provider) => provider != 'mailru';

  /// Нужен ли пароль приложения для календаря и контактов (1.7.2+110 —
  /// пункт «Календарь и контакты» в настройках ящика показывается только
  /// тогда; раньше он был у всех ящиков с текстом про Яндекс):
  ///  · Яндекс по паролю — да: пароль почты к CalDAV и CardDAV не подходит,
  ///    нужны пароли приложений «Календарь» и «Контакты»; через Яндекс ID —
  ///    нет, подходит токен;
  ///  · Mail.ru и Yahoo через вход в аккаунт — да (токен к DAV не подходит);
  ///    по паролю приложения — нет, подходит тот же пароль;
  ///  · Google, iCloud и остальные — нет.
  static bool needsAppPassword(AccountModel account) => switch (providerOf(account)) {
        'yandex' => !account.isOAuth,
        'mailru' || 'yahoo' => account.isOAuth,
        _ => false,
      };

  /// Сбросить паузу после отказа — например, пользователь ввёл пароль.
  static void clearPause(String accountId) {
    _deniedUntil.remove('$accountId:cal');
    _deniedUntil.remove('$accountId:card');
  }

  /// Отказ сервера (нет scope календаря/контактов у токена) не меняется от
  /// синхронизации к синхронизации: после него не повторяем запросы 6 часов,
  /// иначе каждые несколько минут в журнал шли по 8 предупреждений.
  static final Map<String, DateTime> _deniedUntil = {};
  static const _deniedPause = Duration(hours: 6);

  static bool _paused(String key) {
    final until = _deniedUntil[key];
    return until != null && DateTime.now().isBefore(until);
  }

  static void _noteResult(String key, DavClient client, bool empty) {
    if (client.denied && empty) {
      _deniedUntil[key] = DateTime.now().add(_deniedPause);
    } else {
      _deniedUntil.remove(key);
    }
  }

  /// Поддерживается ли DAV-PIM для аккаунта.
  static bool isSupported(AccountModel account) => providerOf(account) != null;

  // ── Календарь ──

  /// Период выборки: три месяца назад, год вперёд. Без него серверы отдавали
  /// весь архив, а повторяющиеся события не разворачивались совсем.
  static ({DateTime from, DateTime to}) window() {
    final now = DateTime.now();
    return (
      from: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 90)),
      to: DateTime(now.year, now.month, now.day).add(const Duration(days: 366)),
    );
  }

  /// Календари аккаунта (кэш на время работы процесса — обнаружение стоит
  /// трёх запросов).
  static final Map<String, List<DavCalendar>> _calendars = {};

  /// Когда список календарей/адресных книг обнаруживался (ключ «id:cal» /
  /// «id:card»). Обнаружение — три запроса; раньше оно шло на каждой
  /// синхронизации (раз в 15 минут), хотя календари добавляют редко.
  /// Теперь — раз в 6 часов и по «обновить» ([invalidateTags]).
  static final Map<String, DateTime> _discoveredAt = {};
  static const _discoverEvery = Duration(hours: 6);

  static bool _discoveryStale(String key) {
    final at = _discoveredAt[key];
    return at == null || DateTime.now().difference(at) >= _discoverEvery;
  }

  Future<List<DavCalendar>> _calendarsOf(AccountModel account, DavClient client, {bool fresh = false}) async {
    if (!fresh && _calendars[account.id] != null) return _calendars[account.id]!;
    final ep = _calendarEndpoints(providerOf(account)!, account.email)!;
    final cals = await client.discoverCalendars(ep.start, fallback: ep.fallback);
    if (!client.denied) {
      _calendars[account.id] = cals;
      if (cals.isNotEmpty) _discoveredAt['${account.id}:cal'] = DateTime.now();
    }
    return cals;
  }

  /// Куда создавать новые события: у Google — основной календарь, у
  /// остальных — первый календарь событий с правом записи («по умолчанию»,
  /// если такой есть), не список дел и не подписка.
  DavCalendar? _targetCalendar(String provider, String email, List<DavCalendar> cals) {
    final ok = cals.where((c) => c.events && c.writable).toList();
    if (ok.isEmpty) return cals.where((c) => c.events).firstOrNull;
    if (provider == 'google') {
      // У Google у каждого календаря адрес «…/caldav/v2/<id>/events/»;
      // основной — тот, чей id совпадает с адресом почты.
      final enc = Uri.encodeComponent(email).toLowerCase();
      return ok.where((c) {
            final u = c.url.toLowerCase();
            return u.contains('/$enc/') || u.contains('/${email.toLowerCase()}/');
          }).firstOrNull ??
          ok.first;
    }
    return ok.where((c) => c.url.toLowerCase().contains('default')).firstOrNull ??
        ok.where((c) => !c.todos).firstOrNull ??
        ok.first;
  }

  // Где лежит каждое событие на сервере: UID → адрес и версия ресурса.
  static String _resKey(String accountId) => 'dav_res_$accountId';

  static Future<Map<String, Map<String, dynamic>>> _loadRes(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_resKey(accountId));
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveRes(String accountId, Map<String, Map<String, dynamic>> m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_resKey(accountId), jsonEncode(m));
    } catch (_) {}
  }

  static Future<void> forgetAccount(String accountId) async {
    _calendars.remove(accountId);
    _books.remove(accountId);
    _discoveredAt.remove('$accountId:cal');
    _discoveredAt.remove('$accountId:card');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resKey(accountId));
      await prefs.remove(_cardKey(accountId));
      await prefs.remove(_cardTagKey(accountId));
      await prefs.remove(_calTagKey(accountId));
      await prefs.remove(_todoKey(accountId));
    } catch (_) {}
  }

  /// Префикс id событий аккаунта.
  static String idPrefix(String accountId) => 'dav_${accountId}_';

  /// Разобрать id события: UID и ключ дня вхождения серии (или null).
  static ({String uid, String? day})? parseId(String accountId, String id) {
    final p = idPrefix(accountId);
    if (!id.startsWith(p)) return null;
    var rest = id.substring(p.length);
    String? day;
    final hash = rest.lastIndexOf('#');
    if (hash > 0 && RegExp(r'^\d{8}$').hasMatch(rest.substring(hash + 1))) {
      day = rest.substring(hash + 1);
      rest = rest.substring(0, hash);
    }
    return rest.isEmpty ? null : (uid: rest, day: day);
  }

  static RecurrenceType _recType(String? rrule) {
    if (rrule == null) return RecurrenceType.none;
    final u = rrule.toUpperCase();
    final interval = int.tryParse(RegExp(r'INTERVAL=(\d+)').firstMatch(u)?.group(1) ?? '') ?? 1;
    if (u.contains('FREQ=DAILY')) return RecurrenceType.daily;
    if (u.contains('FREQ=WEEKLY')) return interval == 2 ? RecurrenceType.biweekly : RecurrenceType.weekly;
    if (u.contains('FREQ=MONTHLY')) return RecurrenceType.monthly;
    if (u.contains('FREQ=YEARLY')) return RecurrenceType.yearly;
    return RecurrenceType.none;
  }

  static String? rruleFor(RecurrenceType t) => switch (t) {
        RecurrenceType.none => null,
        RecurrenceType.daily => 'FREQ=DAILY',
        RecurrenceType.weekly => 'FREQ=WEEKLY',
        RecurrenceType.biweekly => 'FREQ=WEEKLY;INTERVAL=2',
        RecurrenceType.monthly => 'FREQ=MONTHLY',
        RecurrenceType.yearly => 'FREQ=YEARLY',
      };

  static int _partstat(String? s) => switch (s) {
        'ACCEPTED' => 1,
        'TENTATIVE' => 2,
        'DECLINED' => 3,
        _ => 0,
      };

  CalendarEventModel _model(AccountModel account, String id, VEvent ev,
      {DateTime? start, DateTime? end, RecurrenceType rec = RecurrenceType.none}) {
    return CalendarEventModel(
      id: id,
      accountId: account.id,
      title: ev.summary ?? '(без темы)',
      description: ev.description,
      location: ev.location,
      onlineMeetingUrl: _meetingUrl(ev),
      startTime: start ?? ev.start!,
      endTime: end ?? ev.end!,
      isAllDay: ev.isAllDay,
      organizerEmail: ev.organizerEmail,
      attendees: [
        for (final a in ev.attendees)
          if (a.email.toLowerCase() != (ev.organizerEmail ?? '').toLowerCase())
            EventAttendee(email: a.email, displayName: a.name, isRequired: a.required,
                response: _partstat(a.partstat)),
      ],
      recurrence: rec,
      // Все напоминания события (1.7.2+110; раньше — только первое).
      reminders: [
        for (final m in ev.alarms.isNotEmpty ? ev.alarms : [if (ev.alarmMinutes != null) ev.alarmMinutes!])
          EventReminder(minutesBefore: m),
      ],
      createdAt: DateTime.now(),
    );
  }

  /// Ссылка на видеовстречу из описания или места (Google Meet, Zoom,
  /// Телемост, Teams).
  static String? _meetingUrl(VEvent ev) {
    final text = '${ev.location ?? ''}\n${ev.description ?? ''}';
    final m = RegExp(r'https://(?:meet\.google\.com|[\w.-]*zoom\.us|telemost\.yandex\.ru|teams\.microsoft\.com|teams\.live\.com)/[^\s<>"]+')
        .firstMatch(text);
    return m?.group(0);
  }

  /// Развернуть содержимое одного ресурса (серия + изменённые вхождения)
  /// в события периода.
  List<CalendarEventModel> _expandResource(AccountModel account, String data, DateTime from, DateTime to) {
    final out = <CalendarEventModel>[];
    final all = ICalParser.parse(data).where((e) => e.start != null && e.end != null).toList();
    final byUid = <String, List<VEvent>>{};
    for (final ev in all) {
      byUid.putIfAbsent(ev.uid ?? 'h${data.hashCode}', () => []).add(ev);
    }
    for (final entry in byUid.entries) {
      final base = '${idPrefix(account.id)}${entry.key}';
      final master = entry.value.where((e) => e.recurrenceId == null).firstOrNull;
      final overrides = entry.value.where((e) => e.recurrenceId != null).toList();
      final occs = master == null || master.cancelled
          ? null
          : ICalSeries.expand(master, from, to, skip: [for (final o in overrides) o.recurrenceId!]);
      if (master != null && !master.cancelled && occs == null) {
        // Одиночное событие (или правило, которое мы не умеем развернуть).
        if (!master.end!.isBefore(from) && !master.start!.isAfter(to)) {
          out.add(_model(account, base, master, rec: _recType(master.rrule)));
        }
      } else if (master != null && occs != null) {
        final rec = _recType(master.rrule);
        for (final occ in occs) {
          out.add(_model(account, '$base#${occ.day}', master, start: occ.start, end: occ.end, rec: rec));
        }
      }
      for (final o in overrides) {
        if (o.cancelled || o.end!.isBefore(from) || o.start!.isAfter(to)) continue;
        final day = master == null ? EasRecurrence.dayKey(o.recurrenceId!) : ICalSeries.dayOf(master, o.recurrenceId!);
        out.add(_model(account, '$base#$day', o, rec: _recType(master?.rrule)));
      }
    }
    return out;
  }

  /// События периода [window] со всех календарей аккаунта. [ok] = false —
  /// хотя бы один календарь не прочитался (тогда пропавшие события локально
  /// не удаляются).
  ///
  /// [allowSkip] — события уже есть локально: если метки изменений всех
  /// календарей не изменились (и окно дат то же), выгрузка пропускается —
  /// результат пустой с ok = false, локально ничего не удаляется.
  Future<({List<CalendarEventModel> events, bool ok, DateTime from, DateTime to})> fetchEventsResult(
      AccountModel account, String authorization, {bool allowSkip = false}) async {
    final w = window();
    final provider = providerOf(account);
    final ep = provider == null ? null : _calendarEndpoints(provider, account.email);
    if (ep == null) return (events: const <CalendarEventModel>[], ok: false, from: w.from, to: w.to);
    final key = '${account.id}:cal';
    if (_paused(key)) {
      AppLogger.debug('CalDAV $provider: пауза после отказа в доступе');
      return (events: const <CalendarEventModel>[], ok: false, from: w.from, to: w.to);
    }
    final client = DavClient(authorization);
    try {
      final cals = (await _calendarsOf(account, client,
              fresh: _calendars[account.id]?.isEmpty != false || _discoveryStale('${account.id}:cal')))
          .where((c) => c.events)
          .toList();
      // Метки изменений календарей + начало окна: при смене дня окно
      // сдвигается и серии нужно развернуть заново. Полная выгрузка — не
      // реже раза в 6 часов.
      String? tagLine;
      if (cals.isNotEmpty) {
        final tags = <String>['${w.from.year}-${w.from.month}-${w.from.day}'];
        for (final c in cals) {
          final t = await client.collectionTag(c.url);
          if (t == null) {
            tags.clear();
            break;
          }
          tags.add('${c.url}=$t');
        }
        if (tags.isNotEmpty) tagLine = tags.join('\n');
      }
      if (allowSkip && tagLine != null && !client.denied) {
        final prev = await _loadTag(_calTagKey(account.id));
        if (prev != null &&
            prev.tag == tagLine &&
            DateTime.now().difference(prev.at) < const Duration(hours: 6)) {
          AppLogger.debug('CalDAV $provider: календари без изменений — выгрузка пропущена');
          return (events: const <CalendarEventModel>[], ok: false, from: w.from, to: w.to);
        }
      }
      final out = <CalendarEventModel>[];
      final seen = <String>{};
      final res = <String, Map<String, dynamic>>{};
      var ok = cals.isNotEmpty && !client.denied;
      var resources = 0;
      for (final cal in cals) {
        final items = await client.reportCalendarItems(cal.url, from: w.from, to: w.to);
        if (items == null) {
          ok = false;
          continue;
        }
        for (final it in items) {
          resources++;
          final evs = _expandResource(account, it.data, w.from, w.to);
          final uid = ICalParser.parse(it.data).map((e) => e.uid).whereType<String>().firstOrNull;
          if (uid != null && it.href.isNotEmpty) {
            res[uid] = {'h': it.href, 'e': it.etag, 'w': cal.writable};
          }
          for (final e in evs) {
            if (seen.add(e.id)) out.add(e);
          }
        }
      }
      if (ok) {
        await _saveRes(account.id, res);
        if (tagLine != null) await _saveTag(_calTagKey(account.id), tagLine);
      } else if (res.isNotEmpty) {
        await _saveRes(account.id, {...await _loadRes(account.id), ...res});
      }
      _noteResult(key, client, out.isEmpty);
      AppLogger.info('CalDAV $provider: календарей ${cals.length}, ресурсов $resources, событий ${out.length}'
          '${ok ? '' : ', не все календари прочитаны'}${client.denied ? ', отказ в доступе (401/403)' : ''}');
      return (events: out, ok: ok, from: w.from, to: w.to);
    } finally {
      client.dispose();
    }
  }

  /// [authorization] — полное значение заголовка Authorization (DavCredentials).
  Future<List<CalendarEventModel>> fetchEvents(AccountModel account, String authorization) async =>
      (await fetchEventsResult(account, authorization)).events;

  static String _newUid() {
    final r = Random.secure();
    final hex = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '$hex@ogneliss';
  }

  /// Создать событие на сервере. Возвращает id, под которым оно придёт при
  /// синхронизации (null — сервер не принял).
  Future<String?> createEvent(AccountModel account, String authorization, CalendarEventModel e) async {
    final provider = providerOf(account);
    if (provider == null) return null;
    final client = DavClient(authorization);
    try {
      final target = _targetCalendar(provider, account.email, await _calendarsOf(account, client));
      if (target == null) {
        AppLogger.warning('CalDAV $provider: нет календаря для записи');
        return null;
      }
      final uid = _newUid();
      final url = '${target.url.endsWith('/') ? target.url : '${target.url}/'}${Uri.encodeComponent(uid)}.ics';
      final ics = ICalWriter.event(
        uid: uid,
        summary: e.title,
        description: e.description,
        location: e.location ?? e.onlineMeetingUrl,
        start: e.startTime,
        end: e.endTime,
        allDay: e.isAllDay,
        alarms: [for (final r in e.reminders) r.minutesBefore],
        organizerEmail: account.email,
        attendees: [for (final a in e.attendees) (email: a.email, name: a.displayName, required: a.isRequired)],
        rrule: rruleFor(e.recurrence),
      );
      final r = await client.putResource(url, ics, create: true);
      if (r.status < 200 || r.status >= 300) {
        AppLogger.warning('CalDAV $provider: событие не создано (HTTP ${r.status})');
        return null;
      }
      final res = await _loadRes(account.id);
      res[uid] = {'h': url, 'e': r.etag, 'w': true};
      await _saveRes(account.id, res);
      AppLogger.info('CalDAV $provider: событие создано');
      return '${idPrefix(account.id)}$uid';
    } finally {
      client.dispose();
    }
  }

  /// Адрес ресурса события: из сохранённой карты, иначе — после полной выборки.
  Future<String?> _hrefOf(AccountModel account, String authorization, String uid) async {
    var res = await _loadRes(account.id);
    if (res[uid] == null) {
      await fetchEventsResult(account, authorization);
      res = await _loadRes(account.id);
    }
    return res[uid]?['h'] as String?;
  }

  /// Исходное начало вхождения серии по ключу дня.
  DateTime? _originalStart(String ics, String day) {
    final evs = ICalParser.parse(ics);
    final master = evs.where((e) => e.recurrenceId == null && e.start != null && e.end != null).firstOrNull;
    for (final o in evs.where((e) => e.recurrenceId != null)) {
      final d = master == null ? EasRecurrence.dayKey(o.recurrenceId!) : ICalSeries.dayOf(master, o.recurrenceId!);
      if (d == day) return o.recurrenceId;
    }
    if (master == null) return null;
    if (master.rrule == null) return master.start;
    final d = DateTime(int.parse(day.substring(0, 4)), int.parse(day.substring(4, 6)), int.parse(day.substring(6, 8)));
    final occs = ICalSeries.expand(master, d.subtract(const Duration(days: 2)), d.add(const Duration(days: 3)));
    if (occs == null) return master.start;
    for (final occ in occs) {
      if (occ.day == day) return occ.original;
    }
    return null;
  }

  /// Прочитать ресурс, применить правку и записать с проверкой версии
  /// (If-Match); ресурс успели изменить — ещё одна попытка с новой версией.
  Future<void> _modify(AccountModel account, String authorization, String uid,
      String Function(String ics) change) async {
    final href = await _hrefOf(account, authorization, uid);
    if (href == null) throw Exception('Событие на сервере не найдено');
    final client = DavClient(authorization);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final cur = await client.getResource(href);
        if (cur == null) throw Exception('Событие на сервере не найдено');
        final r = await client.putResource(href, change(cur.body), ifMatch: cur.etag);
        if (r.status >= 200 && r.status < 300) {
          final res = await _loadRes(account.id);
          res[uid] = {...?res[uid], 'h': href, 'e': r.etag};
          await _saveRes(account.id, res);
          return;
        }
        if (r.status != 412) {
          throw Exception(client.denied
              ? 'Нет прав на изменение этого календаря'
              : 'Сервер не принял изменение (HTTP ${r.status})');
        }
      }
      throw Exception('Событие изменено на сервере, повторите');
    } finally {
      client.dispose();
    }
  }

  /// Изменить событие: серию или одиночное событие — целиком, вхождение
  /// серии — отдельным изменённым вхождением.
  Future<void> updateEvent(AccountModel account, String authorization, CalendarEventModel e) async {
    final id = parseId(account.id, e.id);
    if (id == null) return;
    // Все напоминания (1.7.2+110): CalDAV хранит несколько VALARM.
    final alarms = [for (final r in e.reminders) r.minutesBefore];
    await _modify(account, authorization, id.uid, (ics) {
      final seriesType = _recType(
          ICalParser.parse(ics).where((x) => x.recurrenceId == null).firstOrNull?.rrule);
      // Вхождение серии правится отдельно; сменили тип повторения — правится
      // вся серия.
      if (id.day != null && seriesType == e.recurrence) {
        final orig = _originalStart(ics, id.day!);
        if (orig != null) {
          return ICalPatch.upsertOverride(ics,
              uid: id.uid,
              originalStart: orig,
              summary: e.title,
              description: e.description,
              location: e.location ?? e.onlineMeetingUrl,
              start: e.startTime,
              end: e.endTime,
              allDay: e.isAllDay,
              alarms: alarms);
        }
      }
      // Правило не трогаем, если тип повторения не меняли: сложные правила
      // («по понедельникам и средам») иначе упростились бы.
      final master = ICalParser.parse(ics).where((x) => x.recurrenceId == null).firstOrNull;
      final oldType = _recType(master?.rrule);
      final String? rrule = oldType == e.recurrence ? null : (rruleFor(e.recurrence) ?? '');
      // У вхождения серии время берём из серии: правится всё повторение.
      return ICalPatch.patchMaster(ics,
          summary: e.title,
          description: e.description,
          location: e.location ?? e.onlineMeetingUrl,
          start: id.day != null && master?.start != null ? master!.start! : e.startTime,
          end: id.day != null && master?.end != null ? master!.end! : e.endTime,
          allDay: e.isAllDay,
          alarms: alarms,
          rrule: rrule);
    });
  }

  /// Ответ на приглашение в своём календаре: событие уже есть (Google сам
  /// кладёт приглашения в календарь) — меняется наш PARTSTAT; нет — при
  /// «Принять»/«Под вопросом» событие создаётся из приглашения. Возвращает,
  /// записано ли что-то в календарь. [partstat] — ACCEPTED, TENTATIVE, DECLINED.
  Future<bool> applyInvite(AccountModel account, String authorization, String inviteIcs, String partstat) async {
    final provider = providerOf(account);
    final ev = ICalITip.parse(inviteIcs)?.event;
    final uid = ev?.uid;
    if (provider == null || uid == null || uid.isEmpty) return false;
    var res = await _loadRes(account.id);
    if (res[uid] == null) {
      await fetchEventsResult(account, authorization);
      res = await _loadRes(account.id);
    }
    final name = account.displayName.isNotEmpty ? account.displayName : null;
    if (res[uid] != null) {
      await _modify(account, authorization, uid,
          (ics) => ICalITip.patchPartstat(ics, email: account.email, name: name, partstat: partstat));
      return true;
    }
    if (partstat == 'DECLINED') return false;
    final client = DavClient(authorization);
    try {
      final target = _targetCalendar(provider, account.email, await _calendarsOf(account, client));
      if (target == null) return false;
      final url = '${target.url.endsWith('/') ? target.url : '${target.url}/'}${Uri.encodeComponent(uid)}.ics';
      final r = await client.putResource(
          url, ICalITip.forCalendar(inviteIcs, email: account.email, name: name, partstat: partstat),
          create: true);
      if (r.status < 200 || r.status >= 300) {
        AppLogger.warning('CalDAV $provider: приглашение не добавлено в календарь (HTTP ${r.status})');
        return false;
      }
      res[uid] = {'h': url, 'e': r.etag, 'w': true};
      await _saveRes(account.id, res);
      return true;
    } finally {
      client.dispose();
    }
  }

  /// Удалить событие; вхождение серии — только его (EXDATE), не всю серию.
  Future<void> deleteEvent(AccountModel account, String authorization, String modelId) async {
    final id = parseId(account.id, modelId);
    if (id == null) return;
    if (id.day != null) {
      await _modify(account, authorization, id.uid, (ics) {
        final orig = _originalStart(ics, id.day!);
        if (orig == null) return ics;
        final allDay = ICalParser.parse(ics).where((x) => x.recurrenceId == null).firstOrNull?.isAllDay ?? false;
        return ICalPatch.addExdate(ics, orig, allDay: allDay);
      });
      return;
    }
    final href = await _hrefOf(account, authorization, id.uid);
    if (href == null) return; // на сервере уже нет
    final client = DavClient(authorization);
    try {
      final st = await client.deleteResource(href);
      if (st != 404 && (st < 200 || st >= 300)) {
        throw Exception(client.denied
            ? 'Нет прав на изменение этого календаря'
            : 'Сервер не удалил событие (HTTP $st)');
      }
      final res = await _loadRes(account.id);
      res.remove(id.uid);
      await _saveRes(account.id, res);
    } finally {
      client.dispose();
    }
  }

  Future<List<ContactModel>> fetchContacts(AccountModel account, String authorization) async =>
      (await fetchContactsResult(account, authorization)).contacts;

  /// Контакты всех адресных книг. [ok] = false — не все книги прочитались
  /// (тогда пропавшие контакты локально не удаляются).
  ///
  /// [allowSkip] — локально контакты уже есть: если метки изменений всех
  /// адресных книг (getctag / sync-token) совпали с прошлой полной выгрузкой,
  /// карточки не скачиваются (`unchanged` = true). Раньше каждая
  /// синхронизация выгружала всю книгу — сотни карточек с фото.
  Future<({List<ContactModel> contacts, bool ok, bool unchanged})> fetchContactsResult(
      AccountModel account, String authorization, {bool allowSkip = false}) async {
    const none = (contacts: <ContactModel>[], ok: false, unchanged: false);
    final provider = providerOf(account);
    final ep = provider == null ? null : _contactsEndpoints(provider, account.email);
    if (ep == null) return none;
    final key = '${account.id}:card';
    if (_paused(key)) return none;
    final client = DavClient(authorization);
    try {
      final cached = _books[account.id];
      final books = cached != null && cached.isNotEmpty && !_discoveryStale('${account.id}:card')
          ? cached
          : await client.discoverCollections(ep.start,
              homeProp: 'addressbook-home-set', collType: 'addressbook', fallback: ep.fallback);
      if (!identical(books, cached) && books.isNotEmpty && !client.denied) {
        _discoveredAt['${account.id}:card'] = DateTime.now();
      }
      // Метки изменений книг. Полная выгрузка всё равно раз в 12 часов —
      // на случай сервера, который метку не обновляет.
      final tags = <String>[];
      for (final b in books) {
        final t = await client.collectionTag(b);
        if (t == null) {
          tags.clear();
          break;
        }
        tags.add('$b=$t');
      }
      final tagLine = tags.isEmpty ? null : tags.join('\n');
      if (allowSkip && tagLine != null && !client.denied) {
        final prev = await _loadCardTag(account.id);
        if (prev != null &&
            prev.tag == tagLine &&
            DateTime.now().difference(prev.at) < const Duration(hours: 12)) {
          _books[account.id] = books;
          AppLogger.info('CardDAV $provider: адресные книги без изменений — выгрузка пропущена');
          return (contacts: const <ContactModel>[], ok: false, unchanged: true);
        }
      }
      final out = <ContactModel>[];
      final seen = <String>{};
      final res = <String, Map<String, dynamic>>{};
      var ok = !client.denied;
      for (final book in books) {
        final items = await client.reportAddressItems(book);
        if (items == null) {
          ok = false;
          continue;
        }
        for (final item in items) {
          for (final vc in VCardParser.parse(item.data)) {
            final email = vc.email.trim();
            final key = email.isNotEmpty ? email.toLowerCase() : vc.displayName.toLowerCase();
            if (key.isEmpty || !seen.add(key)) continue;
            if (item.href.isNotEmpty) res[key] = {'h': item.href, 'e': item.etag};
            out.add(ContactModel(
              id: 'dav_${account.id}_$key',
              accountId: account.id,
              email: email,
              additionalEmails: vc.emails.length > 1 ? vc.emails.sublist(1) : const [],
              displayName: vc.displayName,
              firstName: vc.given,
              lastName: vc.family,
              middleName: vc.middle,
              jobTitle: vc.title,
              company: vc.org,
              phoneWork: vc.phoneWork,
              phoneMobile: vc.phoneMobile,
              avatarUrl: vc.photo,
              source: ContactSource.personal,
            ));
          }
        }
      }
      _books[account.id] = books;
      if (ok) {
        await _saveCardRes(account.id, res);
        if (tagLine != null && books.isNotEmpty) await _saveCardTag(account.id, tagLine);
      } else if (res.isNotEmpty) {
        await _saveCardRes(account.id, {...await _loadCardRes(account.id), ...res});
      }
      _noteResult(key, client, out.isEmpty);
      AppLogger.info('CardDAV $provider: адресных книг ${books.length}, контактов ${out.length}'
          '${client.denied ? ', отказ в доступе (401/403)' : ''}');
      return (contacts: out, ok: ok && books.isNotEmpty, unchanged: false);
    } finally {
      client.dispose();
    }
  }

  static String _cardTagKey(String accountId) => 'dav_cardtag_$accountId';
  static String _calTagKey(String accountId) => 'dav_caltag_$accountId';

  static Future<({String tag, DateTime at})?> _loadCardTag(String accountId) =>
      _loadTag(_cardTagKey(accountId));

  static Future<void> _saveCardTag(String accountId, String tag) => _saveTag(_cardTagKey(accountId), tag);

  static Future<({String tag, DateTime at})?> _loadTag(String prefKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (tag: m['t'] as String, at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveTag(String prefKey, String tag) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey,
          jsonEncode({'t': tag, 'at': DateTime.now().millisecondsSinceEpoch}));
    } catch (_) {}
  }

  /// Сбросить метки изменений — следующая синхронизация выгрузит календари и
  /// адресные книги целиком (ручное «Обновить»).
  static Future<void> invalidateTags(String accountId) async {
    // «Обновить» — и списки календарей/книг обнаружить заново.
    _discoveredAt.remove('$accountId:cal');
    _discoveredAt.remove('$accountId:card');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cardTagKey(accountId));
      await prefs.remove(_calTagKey(accountId));
    } catch (_) {}
  }

  // ── Контакты: запись ──

  static final Map<String, List<String>> _books = {};
  static String _cardKey(String accountId) => 'dav_card_$accountId';

  static Future<Map<String, Map<String, dynamic>>> _loadCardRes(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cardKey(accountId));
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCardRes(String accountId, Map<String, Map<String, dynamic>> m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cardKey(accountId), jsonEncode(m));
    } catch (_) {}
  }

  static String contactKey(ContactModel c) =>
      c.email.trim().isNotEmpty ? c.email.trim().toLowerCase() : c.displayName.toLowerCase();

  /// Можно ли записывать контакты (у Mail.ru CardDAV нет).
  static bool canWriteContacts(AccountModel account) {
    final p = providerOf(account);
    return p != null && hasContacts(p);
  }

  /// Создать или изменить контакт на сервере. Возвращает id, под которым он
  /// придёт при синхронизации (null — сервер не принял).
  Future<String?> saveContact(AccountModel account, String authorization, ContactModel c) async {
    final provider = providerOf(account);
    if (provider == null || !hasContacts(provider)) return null;
    final prefix = idPrefix(account.id);
    final oldKey = c.id.startsWith(prefix) ? c.id.substring(prefix.length) : null;
    var res = await _loadCardRes(account.id);
    if (oldKey != null && res[oldKey] == null) {
      await fetchContacts(account, authorization);
      res = await _loadCardRes(account.id);
    }
    final href = oldKey == null ? null : res[oldKey]?['h'] as String?;
    final newKey = contactKey(c);
    if (newKey.isEmpty) return null;
    final client = DavClient(authorization);
    try {
      if (href != null) {
        for (var attempt = 0; attempt < 2; attempt++) {
          final cur = await client.getResource(href);
          if (cur == null) break; // удалён на сервере — создадим заново
          final body = VCardWriter.patch(cur.body,
              displayName: c.displayName,
              firstName: c.firstName,
              lastName: c.lastName,
              middleName: c.middleName,
              email: c.email,
              phoneWork: c.phoneWork,
              phoneMobile: c.phoneMobile,
              company: c.company,
              jobTitle: c.jobTitle);
          final r = await client.putResource(href, body,
              ifMatch: cur.etag, contentType: 'text/vcard; charset=utf-8');
          if (r.status >= 200 && r.status < 300) {
            res.remove(oldKey);
            res[newKey] = {'h': href, 'e': r.etag};
            await _saveCardRes(account.id, res);
            return '$prefix$newKey';
          }
          if (r.status != 412) {
            throw Exception(client.denied
                ? 'Нет прав на изменение контактов'
                : 'Сервер не принял изменение контакта (HTTP ${r.status})');
          }
          if (attempt == 1) throw Exception('Контакт изменён на сервере, повторите');
        }
      }
      // Новый контакт — в первую адресную книгу.
      var books = _books[account.id];
      if (books == null || books.isEmpty) {
        final ep = _contactsEndpoints(provider, account.email)!;
        books = await client.discoverCollections(ep.start,
            homeProp: 'addressbook-home-set', collType: 'addressbook', fallback: ep.fallback);
        if (!client.denied) _books[account.id] = books;
      }
      if (books.isEmpty) return null;
      final book = books.first;
      final uid = _newUid().replaceFirst('@ogneliss', '');
      final url = '${book.endsWith('/') ? book : '$book/'}$uid.vcf';
      final r = await client.putResource(
          url,
          VCardWriter.card(
            uid: uid,
            displayName: c.displayName,
            firstName: c.firstName,
            lastName: c.lastName,
            middleName: c.middleName,
            email: c.email,
            phoneWork: c.phoneWork,
            phoneMobile: c.phoneMobile,
            company: c.company,
            jobTitle: c.jobTitle,
          ),
          create: true,
          contentType: 'text/vcard; charset=utf-8');
      if (r.status < 200 || r.status >= 300) {
        AppLogger.warning('CardDAV $provider: контакт не создан (HTTP ${r.status})');
        return null;
      }
      if (oldKey != null) res.remove(oldKey);
      res[newKey] = {'h': url, 'e': r.etag};
      await _saveCardRes(account.id, res);
      AppLogger.info('CardDAV $provider: контакт создан');
      return '$prefix$newKey';
    } finally {
      client.dispose();
    }
  }

  /// Удалить контакт на сервере.
  Future<void> deleteContact(AccountModel account, String authorization, String modelId) async {
    final prefix = idPrefix(account.id);
    if (!modelId.startsWith(prefix)) return;
    final key = modelId.substring(prefix.length);
    var res = await _loadCardRes(account.id);
    if (res[key] == null) {
      await fetchContacts(account, authorization);
      res = await _loadCardRes(account.id);
    }
    final href = res[key]?['h'] as String?;
    if (href == null) return;
    final client = DavClient(authorization);
    try {
      final st = await client.deleteResource(href);
      if (st != 404 && (st < 200 || st >= 300)) {
        throw Exception(client.denied
            ? 'Нет прав на изменение контактов'
            : 'Сервер не удалил контакт (HTTP $st)');
      }
      res.remove(key);
      await _saveCardRes(account.id, res);
    } finally {
      client.dispose();
    }
  }

  // ── Задачи (VTODO): Яндекс, Mail.ru и другие серверы со списками дел ──
  // У Google задачи не в CalDAV (отдельный Tasks API) — там список дел не найдётся.

  static String _todoKey(String accountId) => 'dav_todo_$accountId';

  static Future<Map<String, Map<String, dynamic>>> _loadTodoRes(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_todoKey(accountId));
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveTodoRes(String accountId, Map<String, Map<String, dynamic>> m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_todoKey(accountId), jsonEncode(m));
    } catch (_) {}
  }

  /// Префикс id задач аккаунта.
  static String taskPrefix(String accountId) => 'davt_${accountId}_';

  static TaskPriority _taskPriority(int p) => p >= 1 && p <= 4
      ? TaskPriority.high
      : (p >= 6 ? TaskPriority.low : TaskPriority.normal);

  // «Важная» (звезда) — локальная отметка: в PRIORITY не пишется, иначе после
  // синхронизации задача становилась ещё и «высокой важности».
  static int _icalPriority(TaskModel t) => t.priority == TaskPriority.high || t.priority == TaskPriority.urgent
      ? 1
      : (t.priority == TaskPriority.low ? 9 : 5);

  static String _icalStatus(TaskModel t) => switch (t.status) {
        TaskStatus.completed => 'COMPLETED',
        TaskStatus.inProgress => 'IN-PROCESS',
        TaskStatus.cancelled => 'CANCELLED',
        TaskStatus.pending => 'NEEDS-ACTION',
      };

  static TaskStatus _taskStatus(VTodo v) => v.isDone
      ? TaskStatus.completed
      : switch (v.status) {
          'IN-PROCESS' => TaskStatus.inProgress,
          'CANCELLED' => TaskStatus.cancelled,
          _ => TaskStatus.pending,
        };

  /// Есть ли у аккаунта списки дел (по последнему обнаружению календарей).
  static bool? hasTodoLists(String accountId) {
    final c = _calendars[accountId];
    return c?.any((x) => x.todos);
  }

  /// Задачи всех списков дел. [ok] = false — не все списки прочитались.
  Future<({List<TaskModel> tasks, bool ok})> fetchTasks(AccountModel account, String authorization) async {
    final provider = providerOf(account);
    if (provider == null || provider == 'google' || _paused('${account.id}:cal')) {
      return (tasks: const <TaskModel>[], ok: false);
    }
    final client = DavClient(authorization);
    try {
      final lists = (await _calendarsOf(account, client)).where((c) => c.todos).toList();
      if (lists.isEmpty) return (tasks: const <TaskModel>[], ok: false);
      final out = <TaskModel>[];
      final res = <String, Map<String, dynamic>>{};
      var ok = true;
      for (final list in lists) {
        final items = await client.reportCalendarItems(list.url, component: 'VTODO');
        if (items == null) {
          ok = false;
          continue;
        }
        for (final it in items) {
          for (final v in ICalTodoParser.parse(it.data)) {
            final uid = v.uid;
            if (uid == null || uid.isEmpty) continue;
            if (it.href.isNotEmpty) res[uid] = {'h': it.href, 'e': it.etag};
            out.add(TaskModel(
              id: '${taskPrefix(account.id)}$uid',
              accountId: account.id,
              title: v.summary ?? '(без названия)',
              description: v.description,
              status: _taskStatus(v),
              priority: _taskPriority(v.priority),
              createdAt: v.created ?? DateTime.now(),
              dueDate: v.due,
              completedAt: v.completed,
              reminderAt: v.reminderAt,
            ));
          }
        }
      }
      if (ok) {
        await _saveTodoRes(account.id, res);
      } else if (res.isNotEmpty) {
        await _saveTodoRes(account.id, {...await _loadTodoRes(account.id), ...res});
      }
      AppLogger.info('CalDAV $provider: списков дел ${lists.length}, задач ${out.length}');
      return (tasks: out, ok: ok);
    } finally {
      client.dispose();
    }
  }

  /// Создать или изменить задачу. Возвращает id задачи на сервере (null —
  /// у аккаунта нет списка дел или сервер не принял).
  Future<String?> saveTask(AccountModel account, String authorization, TaskModel t) async {
    final provider = providerOf(account);
    if (provider == null || provider == 'google') return null;
    final prefix = taskPrefix(account.id);
    final uid0 = t.id.startsWith(prefix) ? t.id.substring(prefix.length) : null;
    if (uid0 != null) {
      var res = await _loadTodoRes(account.id);
      if (res[uid0] == null) {
        await fetchTasks(account, authorization);
        res = await _loadTodoRes(account.id);
      }
      return _saveExistingTask(account, authorization, t, uid0, res[uid0]?['h'] as String?);
    }
    final client = DavClient(authorization);
    try {
      final lists = (await _calendarsOf(account, client)).where((c) => c.todos).toList();
      final target = lists.where((c) => c.writable).firstOrNull ?? lists.firstOrNull;
      if (target == null) return null; // списка дел нет — задача остаётся на телефоне
      final uid = _newUid();
      final url = '${target.url.endsWith('/') ? target.url : '${target.url}/'}${Uri.encodeComponent(uid)}.ics';
      final r = await client.putResource(
          url,
          ICalTodoWriter.todo(
            uid: uid,
            summary: t.title,
            description: t.description,
            due: t.dueDate,
            status: _icalStatus(t),
            priority: _icalPriority(t),
            reminderAt: t.reminderAt,
          ),
          create: true);
      if (r.status < 200 || r.status >= 300) {
        AppLogger.warning('CalDAV $provider: задача не создана (HTTP ${r.status})');
        return null;
      }
      final res = await _loadTodoRes(account.id);
      res[uid] = {'h': url, 'e': r.etag};
      await _saveTodoRes(account.id, res);
      return '$prefix$uid';
    } finally {
      client.dispose();
    }
  }

  Future<String?> _saveExistingTask(AccountModel account, String authorization, TaskModel t, String uid,
      String? href) async {
    if (href == null) return null; // на сервере задачи уже нет
    final client = DavClient(authorization);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final cur = await client.getResource(href);
        if (cur == null) return null;
        final body = ICalTodoWriter.patch(cur.body,
            summary: t.title,
            description: t.description,
            due: t.dueDate,
            status: _icalStatus(t),
            priority: _icalPriority(t),
            reminderAt: t.reminderAt);
        final r = await client.putResource(href, body, ifMatch: cur.etag);
        if (r.status >= 200 && r.status < 300) {
          final res = await _loadTodoRes(account.id);
          res[uid] = {'h': href, 'e': r.etag};
          await _saveTodoRes(account.id, res);
          return t.id;
        }
        if (r.status != 412) {
          throw Exception(client.denied
              ? 'Нет прав на изменение списка дел'
              : 'Сервер не принял изменение задачи (HTTP ${r.status})');
        }
      }
      throw Exception('Задача изменена на сервере, повторите');
    } finally {
      client.dispose();
    }
  }

  /// Удалить задачу на сервере.
  Future<void> deleteTask(AccountModel account, String authorization, String modelId) async {
    final prefix = taskPrefix(account.id);
    if (!modelId.startsWith(prefix)) return;
    final uid = modelId.substring(prefix.length);
    final res = await _loadTodoRes(account.id);
    final href = res[uid]?['h'] as String?;
    if (href == null) return;
    final client = DavClient(authorization);
    try {
      final st = await client.deleteResource(href);
      if (st != 404 && (st < 200 || st >= 300)) {
        throw Exception('Сервер не удалил задачу (HTTP $st)');
      }
      res.remove(uid);
      await _saveTodoRes(account.id, res);
    } finally {
      client.dispose();
    }
  }
}

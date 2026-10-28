// lib/services/mail/dav/ical_parser.dart
// Парсер и генератор iCalendar (RFC 5545) для CalDAV (Google, Яндекс,
// Mail.ru, Yahoo). Без внешних зависимостей, кроме базы часовых поясов.
//
// Что учитывается при чтении:
//  · развёртка строк и параметры свойств;
//  · вложенные компоненты (VALARM): раньше их свойства перезаписывали
//    свойства события — DESCRIPTION напоминания («This is an event
//    reminder») заменял описание встречи;
//  · часовой пояс TZID: раньше время без «Z» считалось временем телефона, и
//    встреча «10:00 по Москве» в Екатеринбурге показывалась в 10:00, а не в 12:00;
//  · правило повторения RRULE, исключённые даты EXDATE, изменённые
//    вхождения (RECURRENCE-ID), напоминание (VALARM TRIGGER), участники,
//    отмена (STATUS:CANCELLED).

import 'dart:convert' show utf8;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../calendar/eas_recurrence.dart';

class VEvent {
  final String? uid;
  final String? summary;
  final String? description;
  final String? location;
  final DateTime? start;
  final DateTime? end;
  final bool isAllDay;
  final String? organizerEmail;
  /// Правило повторения как есть («FREQ=WEEKLY;BYDAY=MO,WE»).
  final String? rrule;
  /// Исключённые вхождения (локальное время).
  final List<DateTime> exdates;
  /// Исходное начало изменённого вхождения серии (у отдельного VEVENT с тем же UID).
  final DateTime? recurrenceId;
  /// Пояс начала (TZID как в файле) — серия разворачивается в нём.
  final String? tzid;
  /// Напоминание: за сколько минут до начала (первое из [alarms]).
  final int? alarmMinutes;

  /// Все напоминания события (VALARM с TRIGGER «до начала»), без повторов,
  /// в порядке файла (1.7.2+110: Google и Яндекс хранят несколько).
  final List<int> alarms;
  final List<({String email, String? name, bool required, String? partstat})> attendees;
  final bool cancelled;

  const VEvent({
    this.uid,
    this.summary,
    this.description,
    this.location,
    this.start,
    this.end,
    this.isAllDay = false,
    this.organizerEmail,
    this.rrule,
    this.exdates = const [],
    this.recurrenceId,
    this.alarmMinutes,
    this.alarms = const [],
    this.attendees = const [],
    this.cancelled = false,
    this.tzid,
  });
}

class ICalParser {
  static bool _tzReady = false;

  static void _ensureTz() {
    if (_tzReady) return;
    try {
      if (tz.timeZoneDatabase.locations.isEmpty) tzdata.initializeTimeZones();
    } catch (_) {}
    _tzReady = true;
  }

  /// Windows-имена поясов (приглашения из Outlook/Exchange) → IANA.
  static const _windowsZones = {
    'russian standard time': 'Europe/Moscow',
    'russia time zone 3': 'Europe/Samara',
    'ekaterinburg standard time': 'Asia/Yekaterinburg',
    'n. central asia standard time': 'Asia/Novosibirsk',
    'north asia standard time': 'Asia/Krasnoyarsk',
    'north asia east standard time': 'Asia/Irkutsk',
    'yakutsk standard time': 'Asia/Yakutsk',
    'vladivostok standard time': 'Asia/Vladivostok',
    'kaliningrad standard time': 'Europe/Kaliningrad',
    'omsk standard time': 'Asia/Omsk',
    'w. europe standard time': 'Europe/Berlin',
    'romance standard time': 'Europe/Paris',
    'gmt standard time': 'Europe/London',
    'utc': 'UTC',
    'coordinated universal time': 'UTC',
  };

  static tz.Location? location(String? tzid) => _location(tzid);

  static tz.Location? _location(String? tzid) {
    if (tzid == null || tzid.isEmpty) return null;
    _ensureTz();
    final id = tzid.replaceAll('"', '').trim();
    // «/mozilla.org/20050126_1/Europe/Moscow» и подобные префиксы.
    final slash = RegExp(r'([A-Za-z]+/[A-Za-z_+\-]+(?:/[A-Za-z_+\-]+)?)$').firstMatch(id);
    try {
      return tz.getLocation(id);
    } catch (_) {}
    final win = _windowsZones[id.toLowerCase()];
    if (win != null) {
      try {
        return tz.getLocation(win);
      } catch (_) {}
    }
    if (slash != null) {
      try {
        return tz.getLocation(slash.group(1)!);
      } catch (_) {}
    }
    return null;
  }

  /// Разобрать iCalendar-документ в список событий.
  static List<VEvent> parse(String ics) {
    final lines = _unfold(ics);
    final events = <VEvent>[];
    Map<String, _Prop>? cur;
    List<_Prop> multi = [];
    var alarms = <int>[];
    var depth = 0; // вложенные компоненты внутри VEVENT (VALARM и т. п.)
    for (final line in lines) {
      final up = line.toUpperCase();
      if (up == 'BEGIN:VEVENT') {
        cur = {};
        multi = [];
        alarms = <int>[];
        depth = 0;
        continue;
      }
      if (cur == null) continue;
      if (up == 'END:VEVENT' && depth == 0) {
        events.add(_build(cur, multi, alarms));
        cur = null;
        continue;
      }
      if (up.startsWith('BEGIN:')) {
        depth++;
        continue;
      }
      if (up.startsWith('END:')) {
        if (depth > 0) depth--;
        continue;
      }
      final p = _parseLine(line);
      if (p == null) continue;
      if (depth > 0) {
        // Из VALARM берём только время напоминания — у каждого своё.
        if (p.name == 'TRIGGER') {
          final m = _triggerMinutes(p.value);
          if (m != null && !alarms.contains(m)) alarms.add(m);
        }
        continue;
      }
      if (p.name == 'EXDATE' || p.name == 'ATTENDEE') {
        multi.add(p);
      } else {
        cur[p.name] = p;
      }
    }
    return events;
  }

  static VEvent _build(Map<String, _Prop> p, List<_Prop> multi, List<int> alarms) {
    final dtStart = p['DTSTART'];
    final dtEnd = p['DTEND'];
    final allDay = (dtStart?.params['VALUE'] == 'DATE') ||
        (dtStart != null && dtStart.value.trim().length == 8);
    final start = _date(dtStart);
    var end = _date(dtEnd);
    if (end == null && start != null) {
      final dur = _duration(p['DURATION']?.value);
      end = dur != null
          ? start.add(dur)
          : (allDay ? start.add(const Duration(days: 1)) : start.add(const Duration(hours: 1)));
    }
    final exdates = <DateTime>[];
    final attendees = <({String email, String? name, bool required, String? partstat})>[];
    for (final m in multi) {
      if (m.name == 'EXDATE') {
        for (final v in m.value.split(',')) {
          final d = _date(_Prop('EXDATE', v.trim(), m.params, m.rawParams));
          if (d != null) exdates.add(d);
        }
      } else if (m.name == 'ATTENDEE') {
        final email = _mailto(m.value);
        if (email == null) continue;
        attendees.add((
          email: email,
          name: m.rawParams['CN']?.replaceAll('"', ''),
          required: (m.params['ROLE'] ?? 'REQ-PARTICIPANT') != 'OPT-PARTICIPANT',
          partstat: m.params['PARTSTAT'],
        ));
      }
    }
    return VEvent(
      uid: p['UID']?.value,
      summary: _unescape(p['SUMMARY']?.value),
      description: _unescape(p['DESCRIPTION']?.value),
      location: _unescape(p['LOCATION']?.value),
      start: start,
      end: end,
      isAllDay: allDay,
      organizerEmail: _mailto(p['ORGANIZER']?.value),
      rrule: p['RRULE']?.value,
      exdates: exdates,
      recurrenceId: _date(p['RECURRENCE-ID']),
      alarmMinutes: alarms.firstOrNull,
      alarms: List.unmodifiable(alarms),
      attendees: attendees,
      cancelled: (p['STATUS']?.value.toUpperCase() ?? '') == 'CANCELLED',
      // Время в UTC («…Z») — серия считается в UTC, а не в поясе телефона.
      tzid: dtStart?.rawParams['TZID']?.replaceAll('"', '') ??
          (dtStart != null && dtStart.value.trim().toUpperCase().endsWith('Z') ? 'UTC' : null),
    );
  }

  /// TRIGGER:-PT15M / -P1D / -PT1H30M → минуты до начала (только «до начала»).
  static int? _triggerMinutes(String v) {
    final d = _duration(v.replaceFirst('-', ''));
    if (d == null) return null;
    if (!v.trim().startsWith('-') && d.inMinutes != 0) return 0;
    return d.inMinutes;
  }

  /// Длительность ISO 8601 (P1DT2H30M, PT15M, P1W).
  static Duration? _duration(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^[+-]?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
        .firstMatch(v.trim().toUpperCase());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return Duration(days: g(1) * 7 + g(2), hours: g(3), minutes: g(4), seconds: g(5));
  }

  // ── Развёртка строк: продолжения начинаются с пробела/таба ──
  static List<String> _unfold(String text) {
    final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <String>[];
    for (final l in raw) {
      if (l.isEmpty) continue;
      if ((l.startsWith(' ') || l.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = out.last + l.substring(1);
      } else {
        out.add(l);
      }
    }
    return out;
  }

  // ── Разбор строки "NAME;PARAM=VAL:VALUE" ──
  static _Prop? _parseLine(String line) {
    // Двоеточие внутри кавычек параметра (CN="Иванов: отдел") — не разделитель.
    var colon = -1;
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') quoted = !quoted;
      if (c == ':' && !quoted) {
        colon = i;
        break;
      }
    }
    if (colon < 0) return null;
    final left = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = left.split(';');
    final name = parts.first.toUpperCase();
    final params = <String, String>{};
    final raw = <String, String>{};
    for (final seg in parts.skip(1)) {
      final eq = seg.indexOf('=');
      if (eq > 0) {
        final k = seg.substring(0, eq).toUpperCase();
        params[k] = seg.substring(eq + 1).toUpperCase();
        raw[k] = seg.substring(eq + 1);
      }
    }
    return _Prop(name, value, params, raw);
  }

  static DateTime? _date(_Prop? p) {
    if (p == null || p.value.isEmpty) return null;
    final v = p.value.trim();
    // YYYYMMDD (весь день)
    final dOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
    if (dOnly != null) {
      return DateTime(int.parse(dOnly[1]!), int.parse(dOnly[2]!), int.parse(dOnly[3]!));
    }
    // YYYYMMDDTHHMMSS[Z]
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$').firstMatch(v);
    if (m != null) {
      final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
      final h = int.parse(m[4]!), mi = int.parse(m[5]!), s = int.parse(m[6]!);
      if (m[7] == 'Z') return DateTime.utc(y, mo, d, h, mi, s).toLocal();
      final loc = _location(p.rawParams['TZID']);
      if (loc != null) {
        // Не TZDateTime.toLocal(): tz.local в приложении не задан (UTC), и
        // «местное» время оказалось бы UTC — серии сдвигались на 3–5 часов.
        return DateTime.fromMillisecondsSinceEpoch(tz.TZDateTime(loc, y, mo, d, h, mi, s).millisecondsSinceEpoch);
      }
      return DateTime(y, mo, d, h, mi, s); // «плавающее» время — как на телефоне
    }
    try {
      return DateTime.parse(v).toLocal();
    } catch (_) {}
    return null;
  }

  static String? _mailto(String? v) {
    if (v == null) return null;
    final m = RegExp(r'mailto:([^\s;]+)', caseSensitive: false).firstMatch(v);
    return m?.group(1);
  }

  static String? _unescape(String? v) => v
      ?.replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', '\\');
}

/// Правило RRULE → правило в формате ActiveSync (MS-ASCAL) для общей
/// развёртки EasRecurrence: Type 0 ежедневно, 1 еженедельно, 2 ежемесячно
/// по числу, 3 ежемесячно «n-й день недели», 5 ежегодно, 6 ежегодно «n-й
/// день недели». null — правило не поддерживается (показываем одно событие).
class ICalRecurrence {
  static const _dowBits = {'SU': 1, 'MO': 2, 'TU': 4, 'WE': 8, 'TH': 16, 'FR': 32, 'SA': 64};

  static Map<String, String>? toEasRule(String rrule, DateTime start) {
    final parts = <String, String>{};
    for (final seg in rrule.split(';')) {
      final eq = seg.indexOf('=');
      if (eq > 0) parts[seg.substring(0, eq).toUpperCase()] = seg.substring(eq + 1).toUpperCase();
    }
    final freq = parts['FREQ'];
    final out = <String, String>{};
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    out['Interval'] = '$interval';
    final count = int.tryParse(parts['COUNT'] ?? '');
    if (count != null) out['Occurrences'] = '$count';
    final until = parts['UNTIL'];
    if (until != null) {
      out['Until'] = until.length == 8 ? '${until}T235959Z' : until;
    }
    // BYDAY: «MO,WE» или «2TU» / «-1FR».
    var mask = 0;
    int? nth;
    for (final d in (parts['BYDAY'] ?? '').split(',')) {
      final m = RegExp(r'^([+-]?\d+)?([A-Z]{2})$').firstMatch(d.trim());
      if (m == null) continue;
      mask |= _dowBits[m.group(2)] ?? 0;
      if (m.group(1) != null) nth = int.tryParse(m.group(1)!);
    }
    final setPos = int.tryParse(parts['BYSETPOS'] ?? '');
    nth ??= setPos;
    int week(int n) => n < 0 ? 5 : n.clamp(1, 5);
    switch (freq) {
      case 'DAILY':
        if (mask != 0) {
          out['Type'] = '1';
          out['DayOfWeek'] = '$mask';
        } else {
          out['Type'] = '0';
        }
        return out;
      case 'WEEKLY':
        out['Type'] = '1';
        out['DayOfWeek'] = '${mask != 0 ? mask : 1 << (start.weekday % 7)}';
        return out;
      case 'MONTHLY':
        if (mask != 0 && nth != null) {
          out['Type'] = '3';
          out['DayOfWeek'] = '$mask';
          out['WeekOfMonth'] = '${week(nth)}';
        } else {
          out['Type'] = '2';
          out['DayOfMonth'] = parts['BYMONTHDAY'] ?? '${start.day}';
          if (int.tryParse(out['DayOfMonth']!) == null) return null;
        }
        return out;
      case 'YEARLY':
        out['MonthOfYear'] = parts['BYMONTH'] ?? '${start.month}';
        if (mask != 0 && nth != null) {
          out['Type'] = '6';
          out['DayOfWeek'] = '$mask';
          out['WeekOfMonth'] = '${week(nth)}';
        } else {
          out['Type'] = '5';
          out['DayOfMonth'] = parts['BYMONTHDAY'] ?? '${start.day}';
        }
        if (int.tryParse(out['MonthOfYear']!) == null) return null;
        return out;
    }
    return null;
  }
}

/// Вхождение серии: ключ дня (в поясе серии — одинаков на всех устройствах),
/// исходное начало по правилу и фактические начало и конец (момент времени).
typedef ICalOccurrence = ({String day, DateTime original, DateTime start, DateTime end});

class ICalSeries {
  /// Развернуть серию [master] в периоде. Правило считается в поясе самой
  /// серии (TZID), а не телефона: «по понедельникам в 01:00 по Москве» в
  /// Лондоне остаётся понедельником, а переход на летнее время в поясе
  /// серии не сдвигает встречи. [skip] — исходные начала изменённых
  /// вхождений (они показываются отдельно). null — правило не поддерживается.
  static List<ICalOccurrence>? expand(VEvent master, DateTime from, DateTime to, {List<DateTime> skip = const []}) {
    final start = master.start, end = master.end, rrule = master.rrule;
    if (start == null || end == null || rrule == null) return null;
    final loc = master.isAllDay ? null : ICalParser._location(master.tzid);
    // «Настенное» время в поясе серии — без пояса (как его видит EasRecurrence).
    DateTime wall(DateTime d) {
      if (loc == null) return d;
      final t = tz.TZDateTime.from(d, loc);
      return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    }

    DateTime instant(DateTime w) => loc == null
        ? w
        : DateTime.fromMillisecondsSinceEpoch(
            tz.TZDateTime(loc, w.year, w.month, w.day, w.hour, w.minute, w.second).millisecondsSinceEpoch);
    String iso(DateTime w) => DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second).toIso8601String();

    final ws = wall(start);
    final rule = ICalRecurrence.toEasRule(rrule, ws);
    if (rule == null) return null;
    // UNTIL сравниваем сами, точно и в поясе серии: общая развёртка допускает
    // «+1 день» (так нужно ActiveSync), и после правки Google «это и
    // последующие» (старая серия заканчивается UNTIL перед новой) первое
    // вхождение новой серии показывалось дважды.
    rule.remove('Until');
    DateTime? untilWall;
    final um = RegExp(r'UNTIL=(\d{8})(?:T(\d{2})(\d{2})(\d{2})(Z?))?', caseSensitive: false).firstMatch(rrule);
    if (um != null) {
      final d = um.group(1)!;
      final y = int.parse(d.substring(0, 4)), mo = int.parse(d.substring(4, 6)), da = int.parse(d.substring(6, 8));
      if (um.group(2) == null) {
        untilWall = DateTime(y, mo, da, 23, 59, 59);
      } else {
        final h = int.parse(um.group(2)!), mi = int.parse(um.group(3)!), se = int.parse(um.group(4)!);
        untilWall = um.group(5)!.isNotEmpty
            ? wall(DateTime.fromMillisecondsSinceEpoch(DateTime.utc(y, mo, da, h, mi, se).millisecondsSinceEpoch))
            : DateTime(y, mo, da, h, mi, se);
      }
    }
    final out = <ICalOccurrence>[];
    for (final occ in EasRecurrence.expand(
      start: ws,
      end: wall(end),
      rule: rule,
      exceptions: [
        for (final x in [...master.exdates, ...skip]) {'ExceptionStartTime': iso(wall(x)), 'Deleted': '1'},
      ],
      windowStart: wall(from),
      windowEnd: untilWall != null && untilWall.isBefore(wall(to)) ? untilWall.add(const Duration(days: 1)) : wall(to),
    )) {
      if (untilWall != null && occ.originalStart.isAfter(untilWall)) continue;
      out.add((
        day: EasRecurrence.dayKey(occ.originalStart),
        original: instant(occ.originalStart),
        start: instant(occ.start),
        end: instant(occ.end),
      ));
    }
    return out;
  }

  /// Ключ дня момента [d] в поясе серии (для изменённых вхождений).
  static String dayOf(VEvent master, DateTime d) {
    final loc = master.isAllDay ? null : ICalParser._location(master.tzid);
    if (loc == null) return EasRecurrence.dayKey(d);
    final t = tz.TZDateTime.from(d, loc);
    return EasRecurrence.dayKey(DateTime(t.year, t.month, t.day));
  }
}

/// Генерация VCALENDAR с одним VEVENT — для создания и изменения событий.
class ICalWriter {
  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  /// Строка длиннее 75 октетов переносится (RFC 5545, 3.1).
  /// Считаются байты UTF-8 (кириллица — 2 байта), символ не разрывается.
  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final b = StringBuffer();
    var bytes = 0;
    for (final r in line.runes) {
      final ch = String.fromCharCode(r);
      final n = utf8.encode(ch).length;
      if (bytes + n > 74) {
        b.write('\r\n ');
        bytes = 1;
      }
      b.write(ch);
      bytes += n;
    }
    return b.toString();
  }

  static String event({
    required String uid,
    required String summary,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    int? alarmMinutes,
    List<int> alarms = const [],
    String? organizerEmail,
    List<({String email, String? name, bool required})> attendees = const [],
    List<DateTime> exdates = const [],
    String? rrule,
  }) {
    final all = ICalPatch.alarmList(alarmMinutes, alarms);
    final l = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Ogneliss//Ogneliss Mail//RU',
      'CALSCALE:GREGORIAN',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:${_utc(DateTime.now())}',
      if (allDay) 'DTSTART;VALUE=DATE:${_day(start)}' else 'DTSTART:${_utc(start)}',
      if (allDay)
        'DTEND;VALUE=DATE:${_day(end.isAfter(start) ? end : start.add(const Duration(days: 1)))}'
      else
        'DTEND:${_utc(end)}',
      'SUMMARY:${_esc(summary)}',
      if (description != null && description.trim().isNotEmpty) 'DESCRIPTION:${_esc(description)}',
      if (location != null && location.trim().isNotEmpty) 'LOCATION:${_esc(location)}',
      if (rrule != null && rrule.isNotEmpty) 'RRULE:$rrule',
      for (final x in exdates)
        allDay ? 'EXDATE;VALUE=DATE:${_day(x)}' : 'EXDATE:${_utc(x)}',
      if (organizerEmail != null && attendees.isNotEmpty) 'ORGANIZER:mailto:$organizerEmail',
      for (final a in attendees)
        'ATTENDEE;${a.name != null && a.name!.isNotEmpty ? 'CN="${a.name!.replaceAll('"', '')}";' : ''}'
            'ROLE=${a.required ? 'REQ-PARTICIPANT' : 'OPT-PARTICIPANT'};PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${a.email}',
      for (final m in all) ...ICalPatch._alarm(summary, m),
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return '${l.map(_fold).join('\r\n')}\r\n';
  }
}

/// Правка существующего ресурса без потери того, чего приложение не знает
/// (часовые пояса, X-свойства, участники, изменённые вхождения): заменяются
/// только нужные строки. Раньше такой правки не было вовсе — события
/// Google/Яндекс/Mail.ru в приложении нельзя было ни изменить, ни удалить.
class ICalPatch {
  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _name(String line) {
    final i = line.indexOf(RegExp('[;:]'));
    return (i < 0 ? line : line.substring(0, i)).toUpperCase();
  }

  /// Границы VEVENT верхнего уровня: [начало, конец] (индексы строк BEGIN/END).
  static List<(int, int)> _events(List<String> l) {
    final out = <(int, int)>[];
    var depth = 0;
    int? begin;
    for (var i = 0; i < l.length; i++) {
      final up = l[i].toUpperCase();
      if (up == 'BEGIN:VEVENT' && begin == null) {
        begin = i;
        depth = 0;
      } else if (begin != null && up.startsWith('BEGIN:')) {
        depth++;
      } else if (begin != null && up == 'END:VEVENT' && depth == 0) {
        out.add((begin, i));
        begin = null;
      } else if (begin != null && up.startsWith('END:')) {
        depth--;
      }
    }
    return out;
  }

  static bool _hasRecurrenceId(List<String> l, (int, int) ev) {
    for (var i = ev.$1 + 1; i < ev.$2; i++) {
      if (_name(l[i]) == 'RECURRENCE-ID') return true;
    }
    return false;
  }

  static DateTime? _recurrenceId(List<String> l, (int, int) ev) {
    for (var i = ev.$1 + 1; i < ev.$2; i++) {
      if (_name(l[i]) == 'RECURRENCE-ID') return ICalParser._date(ICalParser._parseLine(l[i]));
    }
    return null;
  }

  static String _join(List<String> l) => '${l.map(ICalWriter._fold).join('\r\n')}\r\n';

  static List<String> _fields({
    required String summary,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    String? tzid,
  }) =>
      [
        'DTSTAMP:${_utc(DateTime.now())}',
        'LAST-MODIFIED:${_utc(DateTime.now())}',
        if (allDay) 'DTSTART;VALUE=DATE:${_day(start)}' else _stamp('DTSTART', start, tzid),
        if (allDay)
          'DTEND;VALUE=DATE:${_day(end.isAfter(start) ? end : start.add(const Duration(days: 1)))}'
        else
          _stamp('DTEND', end, tzid),
        'SUMMARY:${ICalWriter._esc(summary)}',
        if (description != null && description.trim().isNotEmpty) 'DESCRIPTION:${ICalWriter._esc(description)}',
        if (location != null && location.trim().isNotEmpty) 'LOCATION:${ICalWriter._esc(location)}',
      ];

  /// Время в поясе серии (TZID как в файле) — тогда правило повторения
  /// считается в том же поясе, что и раньше; без пояса — UTC. Раньше правка
  /// серии переводила DTSTART в UTC, и BYDAY сдвигался на день, если местное
  /// время переходило через полночь UTC.
  static String _stamp(String name, DateTime d, String? tzid) {
    final loc = ICalParser._location(tzid);
    if (tzid == null || loc == null) return '$name:${_utc(d)}';
    final w = tz.TZDateTime.from(d, loc);
    return '$name;TZID=$tzid:${w.year.toString().padLeft(4, '0')}${_two(w.month)}${_two(w.day)}'
        'T${_two(w.hour)}${_two(w.minute)}${_two(w.second)}';
  }

  /// TZID начала основного события.
  static String? _masterTzid(List<String> l, (int, int)? master) {
    if (master == null) return null;
    var depth = 0;
    for (var i = master.$1 + 1; i < master.$2; i++) {
      final up = l[i].toUpperCase();
      if (up.startsWith('BEGIN:')) depth++;
      if (up.startsWith('END:')) depth--;
      if (depth != 0 || _name(l[i]) != 'DTSTART') continue;
      return ICalParser._parseLine(l[i])?.rawParams['TZID']?.replaceAll('"', '');
    }
    return null;
  }

  /// Напоминания для записи: [first] (если есть) и [more], без повторов и
  /// отрицательных.
  static List<int> alarmList(int? first, List<int> more) {
    final out = <int>[];
    for (final m in [if (first != null) first, ...more]) {
      if (m >= 0 && !out.contains(m)) out.add(m);
    }
    return out;
  }

  static List<String> _alarm(String summary, int minutes) => [
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${ICalWriter._esc(summary)}',
        'TRIGGER:-PT${minutes}M',
        'END:VALARM',
      ];

  /// Изменить основное событие (серию целиком или одиночное событие).
  /// [rrule]: null — правило не трогать, '' — убрать повторение, иначе — новое.
  static String patchMaster(
    String ics, {
    required String summary,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    int? alarmMinutes,
    List<int>? alarms,
    String? rrule,
  }) {
    // [alarms] (1.7.2+110) — весь список напоминаний: прежние VALARM
    // заменяются им; пустой — напоминаний нет. null — как раньше: одно
    // [alarmMinutes] вместо прежних, если задано.
    final all = alarms != null ? alarmList(alarmMinutes, alarms) : alarmList(alarmMinutes, const []);
    final replaceAlarms = alarms != null || alarmMinutes != null;
    final l = ICalParser._unfold(ics);
    final evs = _events(l);
    final master = evs.where((e) => !_hasRecurrenceId(l, e)).firstOrNull ?? evs.firstOrNull;
    if (master == null) return ics;
    final tzid = _masterTzid(l, master);
    const replaced = {
      'SUMMARY', 'DESCRIPTION', 'LOCATION', 'DTSTART', 'DTEND', 'DURATION',
      'DTSTAMP', 'LAST-MODIFIED', 'SEQUENCE',
    };
    var seq = 0;
    final body = <String>[];
    var depth = 0;
    var skipAlarm = false;
    for (var i = master.$1 + 1; i < master.$2; i++) {
      final line = l[i];
      final up = line.toUpperCase();
      if (up.startsWith('BEGIN:')) {
        depth++;
        if (up == 'BEGIN:VALARM' && replaceAlarms) skipAlarm = true;
        if (!skipAlarm) body.add(line);
        continue;
      }
      if (up.startsWith('END:')) {
        depth--;
        if (!skipAlarm) body.add(line);
        if (up == 'END:VALARM') skipAlarm = false;
        continue;
      }
      if (skipAlarm) continue;
      if (depth == 0) {
        final n = _name(line);
        if (n == 'SEQUENCE') seq = int.tryParse(line.substring(line.indexOf(':') + 1).trim()) ?? 0;
        if (replaced.contains(n)) continue;
        if (n == 'RRULE' && rrule != null) continue;
        if (n == 'EXDATE' && rrule == '') continue;
      }
      body.add(line);
    }
    final props = [
      ..._fields(summary: summary, description: description, location: location,
          start: start, end: end, allDay: allDay, tzid: tzid),
      'SEQUENCE:${seq + 1}',
      if (rrule != null && rrule.isNotEmpty) 'RRULE:$rrule',
    ];
    // Свойства идут до вложенных компонентов (RFC 5545: eventprop *alarmc).
    final firstComp = body.indexWhere((x) => x.toUpperCase().startsWith('BEGIN:'));
    final at = firstComp < 0 ? body.length : firstComp;
    body.insertAll(at, props);
    for (final m in all) {
      body.addAll(_alarm(summary, m));
    }
    final out = [...l.sublist(0, master.$1 + 1), ...body, ...l.sublist(master.$2)];
    // Повторение убрано — изменённые вхождения больше не нужны.
    if (rrule == '') return _join(_dropOverrides(out));
    return _join(out);
  }

  static List<String> _dropOverrides(List<String> l) {
    final evs = _events(l).where((e) => _hasRecurrenceId(l, e)).toList().reversed;
    final out = [...l];
    for (final e in evs) {
      out.removeRange(e.$1, e.$2 + 1);
    }
    return out;
  }

  /// Удалить одно вхождение серии: EXDATE в основном событии и изменённое
  /// вхождение, если было.
  static String addExdate(String ics, DateTime originalStart, {required bool allDay}) {
    final l = _removeOverride(ICalParser._unfold(ics), originalStart);
    final evs = _events(l);
    final master = evs.where((e) => !_hasRecurrenceId(l, e)).firstOrNull;
    if (master == null) return ics;
    l.insert(master.$1 + 1,
        allDay ? 'EXDATE;VALUE=DATE:${_day(originalStart)}' : _stamp('EXDATE', originalStart, _masterTzid(l, master)));
    return _join(l);
  }

  static List<String> _removeOverride(List<String> l, DateTime originalStart) {
    for (final e in _events(l).reversed) {
      final rid = _recurrenceId(l, e);
      // Совпадение по дню вхождения (сервер мог записать время в другом поясе).
      if (rid != null &&
          rid.year == originalStart.year &&
          rid.month == originalStart.month &&
          rid.day == originalStart.day) {
        l.removeRange(e.$1, e.$2 + 1);
      }
    }
    return l;
  }

  /// Изменить одно вхождение серии: отдельный VEVENT с RECURRENCE-ID
  /// (участники и организатор берутся из серии).
  static String upsertOverride(
    String ics, {
    required String uid,
    required DateTime originalStart,
    required String summary,
    String? description,
    String? location,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    int? alarmMinutes,
    List<int> alarms = const [],
  }) {
    final l = _removeOverride(ICalParser._unfold(ics), originalStart);
    final evs = _events(l);
    final master = evs.where((e) => !_hasRecurrenceId(l, e)).firstOrNull;
    final people = <String>[];
    final tzid = _masterTzid(l, master);
    var seq = 0;
    if (master != null) {
      var depth = 0;
      for (var i = master.$1 + 1; i < master.$2; i++) {
        final up = l[i].toUpperCase();
        if (up.startsWith('BEGIN:')) depth++;
        if (up.startsWith('END:')) depth--;
        if (depth != 0) continue;
        final n = _name(l[i]);
        if (n == 'ORGANIZER' || n == 'ATTENDEE') people.add(l[i]);
        if (n == 'SEQUENCE') seq = int.tryParse(l[i].substring(l[i].indexOf(':') + 1).trim()) ?? 0;
      }
    }
    final ev = [
      'BEGIN:VEVENT',
      'UID:$uid',
      allDay ? 'RECURRENCE-ID;VALUE=DATE:${_day(originalStart)}' : _stamp('RECURRENCE-ID', originalStart, tzid),
      ..._fields(summary: summary, description: description, location: location,
          start: start, end: end, allDay: allDay, tzid: tzid),
      'SEQUENCE:${seq + 1}',
      ...people,
      for (final m in alarmList(alarmMinutes, alarms)) ..._alarm(summary, m),
      'END:VEVENT',
    ];
    final endCal = l.lastIndexWhere((x) => x.toUpperCase() == 'END:VCALENDAR');
    l.insertAll(endCal < 0 ? l.length : endCal, ev);
    return _join(l);
  }
}

/// Приглашения по почте (iMIP, RFC 6047): приглашение от Google, Яндекса,
/// Outlook и др. в письме (text/calendar, METHOD:REQUEST) и ответ организатору
/// (METHOD:REPLY). Раньше у IMAP-ящиков на такие письма ответить было нельзя.
class ICalITip {
  /// METHOD календаря (REQUEST, CANCEL, REPLY…) и первое событие.
  static ({String method, VEvent event})? parse(String ics) {
    final lines = ICalParser._unfold(ics);
    var method = '';
    for (final l in lines) {
      final up = l.toUpperCase();
      if (up.startsWith('BEGIN:VEVENT')) break;
      if (up.startsWith('METHOD:')) method = up.substring(7).trim();
    }
    final evs = ICalParser.parse(ics);
    if (evs.isEmpty) return null;
    return (method: method, event: evs.first);
  }

  static List<String> _firstEvent(List<String> l) {
    final evs = ICalPatch._events(l);
    if (evs.isEmpty) return const [];
    final e = evs.first;
    return l.sublist(e.$1 + 1, e.$2);
  }

  static String _attendee(String email, String? name, String partstat) =>
      'ATTENDEE;${name != null && name.isNotEmpty ? 'CN="${name.replaceAll('"', '')}";' : ''}'
      'PARTSTAT=$partstat:mailto:$email';

  /// Ответ организатору: UID, SEQUENCE, RECURRENCE-ID, DTSTART, ORGANIZER
  /// из приглашения и одна строка ATTENDEE — мы с выбранным ответом.
  static String reply(String inviteIcs, {required String email, String? name, required String partstat}) {
    final l = ICalParser._unfold(inviteIcs);
    final body = _firstEvent(l);
    const keep = {'UID', 'SEQUENCE', 'RECURRENCE-ID', 'DTSTART', 'DTEND', 'ORGANIZER', 'SUMMARY'};
    final props = <String>[];
    var depth = 0;
    for (final line in body) {
      final up = line.toUpperCase();
      if (up.startsWith('BEGIN:')) depth++;
      if (up.startsWith('END:')) {
        depth--;
        continue;
      }
      if (depth != 0) continue;
      if (keep.contains(ICalPatch._name(line))) props.add(line);
    }
    final zones = <String>[];
    // Часовые пояса приглашения нужны, если DTSTART с TZID.
    var inTz = false;
    for (final line in l) {
      final up = line.toUpperCase();
      if (up == 'BEGIN:VTIMEZONE') inTz = true;
      if (inTz) zones.add(line);
      if (up == 'END:VTIMEZONE') inTz = false;
    }
    return ICalPatch._join([
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Ogneliss//Ogneliss Mail//RU',
      'METHOD:REPLY',
      ...zones,
      'BEGIN:VEVENT',
      ...props,
      _attendee(email, name, partstat),
      'DTSTAMP:${ICalPatch._utc(DateTime.now())}',
      'END:VEVENT',
      'END:VCALENDAR',
    ]);
  }

  /// Событие для своего календаря (CalDAV): приглашение без METHOD, наша
  /// строка ATTENDEE — с выбранным ответом (если нас нет в списке — добавляется).
  static String forCalendar(String inviteIcs, {required String email, String? name, required String partstat}) {
    final l = ICalParser._unfold(inviteIcs).where((x) => !x.toUpperCase().startsWith('METHOD:')).toList();
    final out = <String>[];
    var mine = false;
    var depth = 0;
    var inEvent = false;
    for (final line in l) {
      final up = line.toUpperCase();
      if (up == 'BEGIN:VEVENT') {
        inEvent = true;
        depth = 0;
        out.add(line);
        continue;
      }
      if (inEvent && up == 'END:VEVENT' && depth == 0) {
        if (!mine) out.add(_attendee(email, name, partstat));
        mine = false;
        inEvent = false;
        out.add(line);
        continue;
      }
      if (inEvent && up.startsWith('BEGIN:')) depth++;
      if (inEvent && up.startsWith('END:')) depth--;
      if (inEvent && depth == 0 && ICalPatch._name(line) == 'ATTENDEE' &&
          line.toLowerCase().contains('mailto:${email.toLowerCase()}')) {
        mine = true;
        out.add(setPartstat(line, partstat));
        continue;
      }
      out.add(line);
    }
    return ICalPatch._join(out);
  }

  /// Строка ATTENDEE с новым PARTSTAT (RSVP снимается — ответ дан).
  static String setPartstat(String line, String partstat) {
    final colon = line.toLowerCase().indexOf(':mailto:');
    if (colon < 0) return line;
    final left = line
        .substring(0, colon)
        .split(';')
        .where((p) => !p.toUpperCase().startsWith('PARTSTAT=') && !p.toUpperCase().startsWith('RSVP='))
        .join(';');
    return '$left;PARTSTAT=$partstat${line.substring(colon)}';
  }

  /// Наш ответ в уже сохранённом событии календаря.
  static String patchPartstat(String ics, {required String email, String? name, required String partstat}) =>
      forCalendar(ics, email: email, name: name, partstat: partstat);
}

/// Задача CalDAV (VTODO): Яндекс, Mail.ru и другие серверы со списками дел.
class VTodo {
  final String? uid;
  final String? summary;
  final String? description;
  final DateTime? due;
  final bool dueIsDate;
  final DateTime? start;
  /// NEEDS-ACTION, IN-PROCESS, COMPLETED, CANCELLED.
  final String status;
  final DateTime? completed;
  /// 0 — не задан, 1–4 — высокий, 5 — средний, 6–9 — низкий.
  final int priority;
  final int percent;
  /// Напоминание: абсолютное время (если вычислимо).
  final DateTime? reminderAt;
  final DateTime? created;

  const VTodo({
    this.uid,
    this.summary,
    this.description,
    this.due,
    this.dueIsDate = false,
    this.start,
    this.status = 'NEEDS-ACTION',
    this.completed,
    this.priority = 0,
    this.percent = 0,
    this.reminderAt,
    this.created,
  });

  bool get isDone => status == 'COMPLETED' || completed != null;
}

class ICalTodoParser {
  static List<VTodo> parse(String ics) {
    final lines = ICalParser._unfold(ics);
    final out = <VTodo>[];
    Map<String, _Prop>? cur;
    var depth = 0;
    _Prop? trigger;
    for (final line in lines) {
      final up = line.toUpperCase();
      if (up == 'BEGIN:VTODO') {
        cur = {};
        depth = 0;
        trigger = null;
        continue;
      }
      if (cur == null) continue;
      if (up == 'END:VTODO' && depth == 0) {
        out.add(_build(cur, trigger));
        cur = null;
        continue;
      }
      if (up.startsWith('BEGIN:')) {
        depth++;
        continue;
      }
      if (up.startsWith('END:')) {
        if (depth > 0) depth--;
        continue;
      }
      final p = ICalParser._parseLine(line);
      if (p == null) continue;
      if (depth > 0) {
        if (p.name == 'TRIGGER') trigger ??= p;
        continue;
      }
      cur[p.name] = p;
    }
    return out;
  }

  static VTodo _build(Map<String, _Prop> p, _Prop? trigger) {
    final dueP = p['DUE'];
    final due = ICalParser._date(dueP);
    final start = ICalParser._date(p['DTSTART']);
    DateTime? reminder;
    if (trigger != null) {
      if (trigger.params['VALUE'] == 'DATE-TIME') {
        reminder = ICalParser._date(_Prop('TRIGGER', trigger.value, trigger.params, trigger.rawParams));
      } else {
        final v = trigger.value.trim();
        final d = ICalParser._duration(v.replaceFirst(RegExp('^[+-]'), ''));
        final fromStart = trigger.params['RELATED'] == 'START';
        final base = fromStart ? (start ?? due) : (due ?? start);
        if (d != null && base != null) reminder = v.startsWith('-') ? base.subtract(d) : base.add(d);
      }
    }
    return VTodo(
      uid: p['UID']?.value,
      summary: ICalParser._unescape(p['SUMMARY']?.value),
      description: ICalParser._unescape(p['DESCRIPTION']?.value),
      due: due,
      dueIsDate: dueP != null && (dueP.params['VALUE'] == 'DATE' || dueP.value.trim().length == 8),
      start: start,
      status: (p['STATUS']?.value.trim().toUpperCase() ?? 'NEEDS-ACTION'),
      completed: ICalParser._date(p['COMPLETED']),
      priority: int.tryParse(p['PRIORITY']?.value.trim() ?? '') ?? 0,
      percent: int.tryParse(p['PERCENT-COMPLETE']?.value.trim() ?? '') ?? 0,
      reminderAt: reminder,
      created: ICalParser._date(p['CREATED']),
    );
  }
}

/// Создание и правка VTODO.
class ICalTodoWriter {
  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  /// Срок без времени (полночь) — дата (VALUE=DATE), иначе момент в UTC.
  static String _due(DateTime d) {
    final l = d.toLocal();
    return (l.hour == 0 && l.minute == 0 && l.second == 0) ? 'DUE;VALUE=DATE:${_day(l)}' : 'DUE:${_utc(d)}';
  }

  static List<String> _props({
    required String summary,
    String? description,
    DateTime? due,
    required String status,
    required int priority,
  }) =>
      [
        'DTSTAMP:${_utc(DateTime.now())}',
        'LAST-MODIFIED:${_utc(DateTime.now())}',
        'SUMMARY:${ICalWriter._esc(summary)}',
        if (description != null && description.trim().isNotEmpty) 'DESCRIPTION:${ICalWriter._esc(description)}',
        if (due != null) _due(due),
        'STATUS:$status',
        if (status == 'COMPLETED') 'COMPLETED:${_utc(DateTime.now())}',
        if (status == 'COMPLETED') 'PERCENT-COMPLETE:100',
        if (priority > 0) 'PRIORITY:$priority',
      ];

  static List<String> _alarm(String summary, DateTime at) => [
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${ICalWriter._esc(summary)}',
        'TRIGGER;VALUE=DATE-TIME:${_utc(at)}',
        'END:VALARM',
      ];

  static String todo({
    required String uid,
    required String summary,
    String? description,
    DateTime? due,
    String status = 'NEEDS-ACTION',
    int priority = 0,
    DateTime? reminderAt,
  }) {
    final l = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Ogneliss//Ogneliss Mail//RU',
      'BEGIN:VTODO',
      'UID:$uid',
      'CREATED:${_utc(DateTime.now())}',
      ..._props(summary: summary, description: description, due: due, status: status, priority: priority),
      if (reminderAt != null) ..._alarm(summary, reminderAt),
      'END:VTODO',
      'END:VCALENDAR',
    ];
    return ICalPatch._join(l);
  }

  /// Правка первой задачи ресурса: заменяются название, описание, срок,
  /// состояние, важность и напоминание; остальное (категории, повтор,
  /// подзадачи других программ) сохраняется.
  static String patch(
    String ics, {
    required String summary,
    String? description,
    DateTime? due,
    required String status,
    required int priority,
    DateTime? reminderAt,
  }) {
    final l = ICalParser._unfold(ics);
    final b = l.indexWhere((x) => x.toUpperCase() == 'BEGIN:VTODO');
    if (b < 0) return ics;
    // PERCENT-COMPLETE заменяется только при выполнении (иначе — как было).
    final replaced = {
      'SUMMARY', 'DESCRIPTION', 'DUE', 'DURATION', 'STATUS', 'COMPLETED',
      'PRIORITY', 'DTSTAMP', 'LAST-MODIFIED',
      if (status == 'COMPLETED') 'PERCENT-COMPLETE',
    };
    final body = <String>[];
    var depth = 0;
    var skip = false;
    var i = b + 1;
    for (; i < l.length; i++) {
      final line = l[i];
      final up = line.toUpperCase();
      if (depth == 0 && up == 'END:VTODO') break;
      if (up.startsWith('BEGIN:')) {
        depth++;
        if (up == 'BEGIN:VALARM') skip = true;
        if (!skip) body.add(line);
        continue;
      }
      if (up.startsWith('END:')) {
        depth--;
        if (!skip) body.add(line);
        if (up == 'END:VALARM') skip = false;
        continue;
      }
      if (skip) continue;
      if (depth == 0 && replaced.contains(ICalPatch._name(line))) continue;
      // Задачу снова открыли — «выполнено на 100 %» больше не верно.
      if (depth == 0 && status != 'COMPLETED' && ICalPatch._name(line) == 'PERCENT-COMPLETE' &&
          line.trim().endsWith(':100')) {
        continue;
      }
      // Новый срок раньше прежнего начала — сервер отверг бы задачу (DUE < DTSTART).
      if (depth == 0 && due != null && ICalPatch._name(line) == 'DTSTART') {
        final st = ICalParser._date(ICalParser._parseLine(line));
        if (st != null && st.isAfter(due)) continue;
      }
      body.add(line);
    }
    final props = _props(summary: summary, description: description, due: due, status: status, priority: priority);
    final firstComp = body.indexWhere((x) => x.toUpperCase().startsWith('BEGIN:'));
    body.insertAll(firstComp < 0 ? body.length : firstComp, props);
    if (reminderAt != null) body.addAll(_alarm(summary, reminderAt));
    return ICalPatch._join([...l.sublist(0, b + 1), ...body, ...l.sublist(i)]);
  }
}

class _Prop {
  final String name;
  final String value;
  /// Параметры в верхнем регистре (для сравнения).
  final Map<String, String> params;
  /// Параметры как есть (TZID, CN — регистр важен).
  final Map<String, String> rawParams;
  _Prop(this.name, this.value, this.params, [this.rawParams = const {}]);
}

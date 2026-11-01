// lib/features/calendar/quick_event.dart
// Встреча одной фразой, как в Fantastical (1.9.x, просьба владельца
// 31.10.2026): «Созвон с Анной в пятницу в 15 на час» → «Созвон с Анной»,
// пятница 15:00–16:00; «Обед завтра 13:00-14:00 в кафе «Ромашка»» → место
// «кафе «Ромашка»». Дату и время разбирает общий DatePhrase (тот же, что у
// быстрого ввода задач и дат в тексте письма); здесь — то, что нужно именно
// встрече: конец, «в 3» — днём, место.
//
// Место — осторожно: только «в / at / in …» после даты или времени, и только
// если это явно место — слово вроде «кафе», «офис», «переговорная», название
// в кавычках или (по-английски) имя с заглавной буквы. «Созвон в Telegram
// завтра» место не получает: «в Telegram» стоит до времени.

import '../../core/utils/date_phrase.dart';

class QuickEvent {
  /// Название (пусто — фраза из одних даты и времени).
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  /// В фразе названы день или время (иначе — ближайшие полчаса сегодня).
  final bool dated;

  const QuickEvent({
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.dated = false,
  });
}

class QuickEventParser {
  QuickEventParser._();

  static final _place = RegExp(
    r'^[\s,]*(в|во|at|in)\s+((?:кафе|ресторан|бар|кофейн|столов|офис|переговорн|кабинет|зал|комнат|аудитори'
    r'|библиотек|школ|университет|институт|парк|клуб|центр|бизнес-центр|бц|тц|отел|гостиниц|корпус|филиал'
    r'|здани|кинотеатр|театр|музей|стадион|больниц|поликлиник|банк|магазин|аэропорт|вокзал|zoom|cafe|café'
    r'|restaurant|bar|office|room|hall|library|school|park|club|cent(?:er|re)|hotel|airport|station|building'
    r'|the\s)[^\n]*|[«"„“\x27][^\n]*)$',
    caseSensitive: false,
  );

  /// «at Joe's Cafe», «in Room 5» — имя с заглавной буквы (по-английски).
  static final _placeName = RegExp(r'^[\s,]*(at|in)\s+([A-Z][^\n]*)$');

  static final _tailPrep = RegExp(r'[\s,;:–—-]+(в|во|на|к|до|с|at|on|by|from|in)?$', caseSensitive: false);

  /// Ближайшие полчаса: 19:48 → 20:00 (как у новой встречи в редакторе).
  static DateTime _nextHalfHour(DateTime t) {
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 30 : 60);
    return base;
  }

  static QuickEvent parse(
    String input, {
    DateTime? now,
    bool monthFirst = false,
    Duration length = const Duration(minutes: 30),
  }) {
    final n = now ?? DateTime.now();
    final p = DatePhrase.parse(input, now: n, monthFirst: monthFirst);

    // Место — после последнего куска с датой или временем.
    String? location;
    var cutFrom = input.length;
    if (p.found) {
      final tail = input.substring(p.lastEnd);
      final m = _place.firstMatch(tail) ?? _placeName.firstMatch(tail);
      if (m != null) {
        location = m.group(2)!.trim();
        cutFrom = p.lastEnd + m.start;
      }
    }

    // Название — фраза без даты, времени и места.
    final buf = StringBuffer();
    var at = 0;
    for (final s in p.spans) {
      if (s.$1 >= cutFrom) break;
      buf
        ..write(input.substring(at, s.$1))
        ..write(' ');
      at = s.$2;
    }
    if (at < cutFrom) buf.write(input.substring(at, cutFrom));
    var title = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceFirst(_tailPrep, '').replaceFirst(RegExp(r'^[\s,;:–—-]+'), '');
    if (title.isNotEmpty) title = title[0].toUpperCase() + title.substring(1);

    var hour = p.hour;
    // «в 3» без «дня» и минут — днём: встречи в 3 часа ночи редки.
    if (hour != null && p.loneHour && hour >= 1 && hour <= 6) hour += 12;

    final dated = p.day != null || hour != null || p.offsetMinutes != null;
    DateTime start;
    var allDay = false;
    if (p.offsetMinutes != null && p.day == null && hour == null) {
      final t = n.add(Duration(minutes: p.offsetMinutes!));
      start = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    } else if (hour != null) {
      final d = p.day ?? DateTime(n.year, n.month, n.day);
      start = DateTime(d.year, d.month, d.day, hour, p.minute);
      // «в 9» без дня, а 9 уже прошло — завтра.
      if (p.day == null && !start.isAfter(n)) start = DateTime(d.year, d.month, d.day + 1, hour, p.minute);
    } else if (p.day != null) {
      start = p.day!;
      allDay = true;
    } else {
      start = _nextHalfHour(n);
    }

    DateTime end;
    if (allDay) {
      end = start;
    } else if (p.endHour != null) {
      var eh = p.endHour!;
      // «с 3 до 4» днём — и конец днём.
      if (hour != null && hour != p.hour && eh < 12) eh += 12;
      end = DateTime(start.year, start.month, start.day, eh, p.endMinute);
      if (!end.isAfter(start)) end = DateTime(start.year, start.month, start.day + 1, eh, p.endMinute);
    } else {
      final minutes = p.durationMinutes ?? length.inMinutes;
      end = DateTime(start.year, start.month, start.day, start.hour, start.minute + minutes);
    }
    return QuickEvent(title: title, start: start, end: end, allDay: allDay, location: location, dated: dated);
  }
}

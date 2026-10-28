// lib/features/my_day/day_stats.dart
// Расчёты для «Моего дня» как мини-секретаря (10.10.2026): сколько времени
// займут встречи, где ближайшее свободное окно в рабочих часах, какие
// встречи пересекаются. Чистые функции без Flutter и базы — проверяются
// тестом day_stats_test.dart.

/// Встреча в расчётах: время и занятость.
class DayMeeting {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  /// «Свободен» в Outlook (ShowAs = Free) — время не занято.
  final bool free;
  const DayMeeting({required this.id, required this.title, required this.start, required this.end, this.free = false});
}

/// Промежуток времени.
class Span {
  final DateTime start;
  final DateTime end;
  const Span(this.start, this.end);
  Duration get length => end.difference(start);
  @override
  bool operator ==(Object other) => other is Span && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => 'Span($start–$end)';
}

class DayStats {
  DayStats._();

  /// Занятое время: встречи «не свободен», обрезанные по [day], слитые.
  static List<Span> busy(List<DayMeeting> meetings, {required DateTime dayStart, required DateTime dayEnd}) {
    final list = <Span>[
      for (final m in meetings)
        if (!m.free && m.end.isAfter(dayStart) && m.start.isBefore(dayEnd) && m.end.isAfter(m.start))
          Span(m.start.isBefore(dayStart) ? dayStart : m.start, m.end.isAfter(dayEnd) ? dayEnd : m.end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = <Span>[];
    for (final s in list) {
      if (out.isNotEmpty && !s.start.isAfter(out.last.end)) {
        final last = out.removeLast();
        out.add(Span(last.start, s.end.isAfter(last.end) ? s.end : last.end));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// Сколько времени занимают встречи (пересечения не считаются дважды).
  static Duration meetingTime(List<Span> busy) =>
      busy.fold(Duration.zero, (sum, s) => sum + s.length);

  /// Ближайшее свободное окно не короче [min] между [from] и [until]
  /// (обычно «сейчас» и конец рабочего дня). null — свободного окна нет.
  static Span? nextFree(List<Span> busy,
      {required DateTime from, required DateTime until, Duration min = const Duration(minutes: 30)}) {
    if (!until.isAfter(from)) return null;
    var cursor = from;
    for (final s in busy) {
      if (!s.end.isAfter(cursor)) continue;
      if (!s.start.isBefore(until)) break;
      if (s.start.difference(cursor) >= min) return Span(cursor, s.start);
      if (s.end.isAfter(cursor)) cursor = s.end;
      if (!cursor.isBefore(until)) return null;
    }
    return until.difference(cursor) >= min ? Span(cursor, until) : null;
  }

  /// Пересекающиеся встречи (обе «не свободен»): id → названия тех, с
  /// которыми пересекается. Встречи «встык» (10:00–11:00 и 11:00–12:00) — не
  /// пересечение.
  static Map<String, List<String>> conflicts(List<DayMeeting> meetings) {
    final list = [for (final m in meetings) if (!m.free && m.end.isAfter(m.start)) m]
      ..sort((a, b) => a.start.compareTo(b.start));
    final out = <String, List<String>>{};
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        if (!b.start.isBefore(a.end)) break; // дальше начинаются ещё позже
        (out[a.id] ??= []).add(b.title);
        (out[b.id] ??= []).add(a.title);
      }
    }
    return out;
  }

  /// Рабочие часы дня из минут от полуночи; окно через полночь или пустое —
  /// 9:00–18:00.
  static Span workHours(DateTime day, int startMinutes, int endMinutes) {
    final d = DateTime(day.year, day.month, day.day);
    if (endMinutes <= startMinutes) {
      return Span(d.add(const Duration(hours: 9)), d.add(const Duration(hours: 18)));
    }
    return Span(d.add(Duration(minutes: startMinutes)), d.add(Duration(minutes: endMinutes)));
  }
}

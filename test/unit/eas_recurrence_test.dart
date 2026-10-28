// Развёртка повторяющихся событий ActiveSync (lib/services/calendar/eas_recurrence.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/calendar/eas_recurrence.dart';

String fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

List<String> run(Map<String, String> rule,
    {DateTime? start, DateTime? ws, DateTime? we, List<Map<String, String>> ex = const []}) {
  final s = start ?? DateTime(2026, 9, 7, 9); // понедельник
  return EasRecurrence.expand(
    start: s,
    end: s.add(const Duration(minutes: 30)),
    rule: rule,
    exceptions: ex,
    windowStart: ws ?? DateTime(2026, 9, 1),
    windowEnd: we ?? DateTime(2026, 9, 20),
  ).map((o) => fmt(o.start)).toList();
}

void main() {
  test('еженедельно пн/ср/пт', () {
    expect(run({'Type': '1', 'DayOfWeek': '${2 | 8 | 32}'}),
        ['07.09 09:00', '09.09 09:00', '11.09 09:00', '14.09 09:00', '16.09 09:00', '18.09 09:00']);
  });

  test('по будням', () {
    expect(run({'Type': '0', 'DayOfWeek': '62'}, we: DateTime(2026, 9, 12)),
        ['07.09 09:00', '08.09 09:00', '09.09 09:00', '10.09 09:00', '11.09 09:00']);
  });

  test('каждые 2 дня, 4 раза', () {
    expect(run({'Type': '0', 'Interval': '2', 'Occurrences': '4'}, we: DateTime(2026, 12, 1)),
        ['07.09 09:00', '09.09 09:00', '11.09 09:00', '13.09 09:00']);
  });

  test('второй вторник месяца', () {
    expect(run({'Type': '3', 'WeekOfMonth': '2', 'DayOfWeek': '4'}, we: DateTime(2026, 12, 31)),
        ['08.09 09:00', '13.10 09:00', '10.11 09:00', '08.12 09:00']);
  });

  test('последняя пятница месяца', () {
    expect(run({'Type': '3', 'WeekOfMonth': '5', 'DayOfWeek': '32'}, we: DateTime(2026, 12, 31)),
        ['25.09 09:00', '30.10 09:00', '27.11 09:00', '25.12 09:00']);
  });

  test('31-е число — в коротких месяцах последний день', () {
    expect(
        run({'Type': '2', 'DayOfMonth': '31'},
            start: DateTime(2026, 8, 31, 9), ws: DateTime(2026, 8, 1), we: DateTime(2026, 12, 1)),
        ['31.08 09:00', '30.09 09:00', '31.10 09:00', '30.11 09:00']);
  });

  test('давняя ежедневная серия доходит до окна', () {
    expect(
        run({'Type': '0'},
            start: DateTime(2020, 1, 1, 9), ws: DateTime(2026, 9, 28), we: DateTime(2026, 10, 1)),
        ['28.09 09:00', '29.09 09:00', '30.09 09:00']);
  });

  test('удалённое и перенесённое вхождения', () {
    final moved = DateTime(2026, 9, 9, 15).toUtc();
    final res = run({'Type': '1', 'DayOfWeek': '${2 | 8}'}, ex: [
      {'ExceptionStartTime': DateTime(2026, 9, 7, 9).toUtc().toIso8601String(), 'Deleted': '1'},
      {
        'ExceptionStartTime': DateTime(2026, 9, 9, 9).toUtc().toIso8601String(),
        'StartTime': moved.toIso8601String(),
        'EndTime': moved.add(const Duration(hours: 1)).toIso8601String(),
      },
    ]);
    expect(res, ['09.09 15:00', '14.09 09:00', '16.09 09:00']);
  });

  test('Until: разделённая серия не захватывает день новой', () {
    // Ежедневно в 10:00; Outlook разделил серию — Until = начало последнего
    // вхождения старой (13-е). 14-е уже принадлежит новой серии.
    final start = DateTime(2026, 10, 12, 10);
    final occ = EasRecurrence.expand(
      start: start,
      end: start.add(const Duration(minutes: 30)),
      rule: {'Type': '0', 'Interval': '1', 'Until': DateTime(2026, 10, 13, 10).toUtc().toIso8601String()},
      windowStart: DateTime(2026, 10, 1),
      windowEnd: DateTime(2026, 11, 1),
    );
    expect(occ.map((o) => o.start.day), [12, 13]);
  });

  test('Until: полночь последнего дня включает этот день', () {
    final start = DateTime(2026, 10, 12, 10);
    final occ = EasRecurrence.expand(
      start: start,
      end: start.add(const Duration(minutes: 30)),
      rule: {'Type': '0', 'Interval': '1', 'Until': DateTime(2026, 10, 14).toUtc().toIso8601String()},
      windowStart: DateTime(2026, 10, 1),
      windowEnd: DateTime(2026, 11, 1),
    );
    expect(occ.map((o) => o.start.day), [12, 13, 14]);
  });
}

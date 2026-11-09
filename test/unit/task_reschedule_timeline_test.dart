// Перенос срока задачи (карточка по удержанию) и расчёты шкалы «Моего дня»
// (решения владельца 09.11.2026).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/tasks/task_actions_service.dart';
import 'package:ogneliss/services/tasks/task_blocks.dart';

void main() {
  final now = DateTime(2026, 11, 9, 15, 0); // понедельник

  group('перенос срока', () {
    test('просроченная со временем — на сегодня без времени, если время прошло', () {
      final p = TaskReschedule.plan(
          due: DateTime(2026, 11, 8, 10, 0), reminder: DateTime(2026, 11, 8, 9, 30), day: DateTime(2026, 11, 9), now: now);
      expect(p.due, DateTime(2026, 11, 9));
      expect(p.reminder, isNull, reason: 'напоминание в прошлом не ставится');
    });

    test('на завтра — время срока и напоминания сохраняются', () {
      final p = TaskReschedule.plan(
          due: DateTime(2026, 11, 8, 10, 0), reminder: DateTime(2026, 11, 8, 9, 30), day: DateTime(2026, 11, 10), now: now);
      expect(p.due, DateTime(2026, 11, 10, 10, 0));
      expect(p.reminder, DateTime(2026, 11, 10, 9, 30));
    });

    test('без срока — снимаются и срок, и напоминание', () {
      final p = TaskReschedule.plan(due: DateTime(2026, 11, 8), reminder: DateTime(2026, 11, 8, 9), day: null, now: now);
      expect(p.due, isNull);
      expect(p.reminder, isNull);
    });

    test('на следующей неделе — понедельник', () {
      expect(TaskReschedule.nextWeek(now), DateTime(2026, 11, 16));
      expect(TaskReschedule.nextWeek(DateTime(2026, 11, 15, 22)), DateTime(2026, 11, 16), reason: 'воскресенье');
      expect(TaskReschedule.nextWeek(DateTime(2026, 11, 13)), DateTime(2026, 11, 16), reason: 'пятница');
    });
  });

  group('шкала', () {
    final day = DateTime(2026, 11, 9);

    test('шаг 15 минут, в пределах суток', () {
      expect(DayTimeline.snap(day, 11.4), DateTime(2026, 11, 9, 11, 30));
      expect(DayTimeline.snap(day, 11.1), DateTime(2026, 11, 9, 11, 0));
      expect(DayTimeline.snap(day, -1), DateTime(2026, 11, 9));
      expect(DayTimeline.snap(day, 30), DateTime(2026, 11, 9, 23, 45));
      expect(DayTimeline.hourOf(DateTime(2026, 11, 9, 13, 30), day), 13.5);
    });

    test('пересекающиеся встречи — рядом, отдельные — во всю ширину', () {
      final c = DayTimeline.columns([
        (from: 10, to: 11.5), // планёрка
        (from: 10.5, to: 11), // звонок — рядом
        (from: 13, to: 14), // отдельно
        (from: 11.5, to: 12), // встык с планёркой — новая группа
      ]);
      expect(c[0], (col: 0, cols: 2));
      expect(c[1], (col: 1, cols: 2));
      expect(c[2], (col: 0, cols: 1));
      expect(c[3], (col: 0, cols: 1));
    });

    test('свободные окна не короче 30 минут', () {
      final f = DayTimeline.free([(from: 10, to: 11.5), (from: 13, to: 14), (from: 14.25, to: 15)], from: 9, to: 18);
      expect(f, [(from: 9.0, to: 10.0), (from: 11.5, to: 13.0), (from: 15.0, to: 18.0)]);
    });
  });

  group('время задачи — только в приложении', () {
    test('чтение: старые и испорченные записи пропускаются', () {
      final now = DateTime(2026, 11, 9, 12);
      final m = TaskBlocksNotifier.decode(
        '{"a|1":{"s":"2026-11-09T11:30:00.000","m":60},"a|2":{"s":"2026-10-01T10:00:00.000","m":30},'
        '"a|3":{"s":"нет","m":30},"a|4":{"s":"2026-11-09T09:00:00.000","m":0}}',
        now: now,
      );
      expect(m.keys, ['a|1']);
      expect(m['a|1'], TaskBlock(DateTime(2026, 11, 9, 11, 30), 60));
      expect(m['a|1']!.end, DateTime(2026, 11, 9, 12, 30));
      expect(TaskBlocksNotifier.decode('не json', now: now), isEmpty);
    });
  });
}

// test/unit/ical_parser_test.dart
// Разбор и правка iCalendar для CalDAV (Google, Яндекс, Mail.ru, Yahoo).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/dav/ical_parser.dart';

const _series = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:abc@google.com\r\n'
    'DTSTART;TZID=Europe/Moscow:20260302T100000\r\n'
    'DTEND;TZID=Europe/Moscow:20260302T103000\r\n'
    'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r\n'
    'EXDATE;TZID=Europe/Moscow:20260304T100000\r\n'
    'SUMMARY:Планёрка\r\n'
    'DESCRIPTION:Повестка\\, вопросы\r\n'
    'ATTENDEE;CN="Иванов: отдел";PARTSTAT=ACCEPTED:mailto:ivanov@example.com\r\n'
    'BEGIN:VALARM\r\n'
    'ACTION:DISPLAY\r\n'
    'DESCRIPTION:This is an event reminder\r\n'
    'TRIGGER:-PT15M\r\n'
    'END:VALARM\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:abc@google.com\r\n'
    'RECURRENCE-ID;TZID=Europe/Moscow:20260309T100000\r\n'
    'DTSTART;TZID=Europe/Moscow:20260309T120000\r\n'
    'DTEND;TZID=Europe/Moscow:20260309T123000\r\n'
    'SUMMARY:Планёрка (перенос)\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  test('VALARM не подменяет описание, напоминание и участники читаются', () {
    final evs = ICalParser.parse(_series);
    expect(evs.length, 2);
    final m = evs.first;
    expect(m.description, 'Повестка, вопросы');
    expect(m.alarmMinutes, 15);
    expect(m.attendees.single.email, 'ivanov@example.com');
    expect(m.attendees.single.name, 'Иванов: отдел');
    expect(m.attendees.single.partstat, 'ACCEPTED');
  });

  test('TZID учитывается', () {
    final m = ICalParser.parse(_series).first;
    expect(m.start!.toUtc(), DateTime.utc(2026, 3, 2, 7));
    // Местное время телефона, а не UTC (иначе серии сдвигались).
    expect(m.start!.isUtc, isFalse);
    expect(m.tzid, 'Europe/Moscow');
    expect(m.exdates.single.toUtc(), DateTime.utc(2026, 3, 4, 7));
    expect(ICalParser.parse(_series)[1].recurrenceId!.toUtc(), DateTime.utc(2026, 3, 9, 7));
  });

  test('RRULE разворачивается в поясе серии, с EXDATE и перенесённым вхождением', () {
    final evs = ICalParser.parse(_series);
    final m = evs.first;
    final rule = ICalRecurrence.toEasRule(m.rrule!, m.start!)!;
    expect(rule['Type'], '1');
    expect(rule['DayOfWeek'], '${2 | 8}');
    final occ = ICalSeries.expand(m, DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31),
        skip: [evs[1].recurrenceId!])!;
    // 6 вхождений по правилу: одно исключено (EXDATE), одно перенесено.
    expect(occ.length, 4);
    // Ключи дней — по Москве, одинаковые на любом телефоне.
    expect(occ.map((o) => o.day), ['20260302', '20260311', '20260316', '20260318']);
    // Время — 10:00 по Москве (07:00 UTC) в каждом вхождении.
    for (final o in occ) {
      expect(o.start.toUtc().hour, 7);
      expect(o.start.isUtc, isFalse);
    }
    expect(ICalSeries.dayOf(m, evs[1].recurrenceId!), '20260309');
  });

  test('Ежемесячно во второй вторник', () {
    final rule = ICalRecurrence.toEasRule('FREQ=MONTHLY;BYDAY=2TU', DateTime(2026, 1, 13))!;
    expect(rule['Type'], '3');
    expect(rule['WeekOfMonth'], '2');
    expect(rule['DayOfWeek'], '4');
  });

  test('Удаление вхождения добавляет EXDATE и убирает изменённое вхождение', () {
    final orig = ICalParser.parse(_series)[1].recurrenceId!;
    final out = ICalPatch.addExdate(_series, orig, allDay: false);
    final evs = ICalParser.parse(out);
    expect(evs.length, 1);
    expect(evs.single.exdates.length, 2);
  });

  test('Правка серии сохраняет правило, участников и пояс исключений', () {
    final out = ICalPatch.patchMaster(_series,
        summary: 'Новая тема',
        description: null,
        location: 'Переговорная',
        start: DateTime.utc(2026, 3, 2, 8),
        end: DateTime.utc(2026, 3, 2, 9),
        allDay: false,
        alarmMinutes: 30);
    final evs = ICalParser.parse(out);
    final m = evs.first;
    expect(m.summary, 'Новая тема');
    expect(m.location, 'Переговорная');
    expect(m.description, isNull);
    expect(m.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6');
    expect(m.attendees.length, 1);
    expect(m.alarmMinutes, 30);
    expect(evs.length, 2); // изменённое вхождение на месте
    expect(out.contains('SEQUENCE:1'), isTrue);
    // Пояс серии сохранён: 08:00 UTC = 11:00 по Москве.
    expect(out.contains('DTSTART;TZID=Europe/Moscow:20260302T110000'), isTrue);
  });

  test('Отмена повторения убирает правило и изменённые вхождения', () {
    final out = ICalPatch.patchMaster(_series,
        summary: 'Разово',
        start: DateTime.utc(2026, 3, 2, 7),
        end: DateTime.utc(2026, 3, 2, 8),
        allDay: false,
        rrule: '');
    final evs = ICalParser.parse(out);
    expect(evs.length, 1);
    expect(evs.single.rrule, isNull);
    expect(evs.single.exdates, isEmpty);
  });

  test('Изменённое вхождение заменяется, участники копируются', () {
    final orig = ICalParser.parse(_series)[1].recurrenceId!;
    final out = ICalPatch.upsertOverride(_series,
        uid: 'abc@google.com',
        originalStart: orig,
        summary: 'Ещё раз перенос',
        start: DateTime.utc(2026, 3, 9, 11),
        end: DateTime.utc(2026, 3, 9, 12),
        allDay: false);
    final evs = ICalParser.parse(out);
    expect(evs.length, 2);
    expect(evs[1].summary, 'Ещё раз перенос');
    expect(evs[1].attendees.length, 1);
  });

  test('Новое событие: перенос длинных строк и экранирование', () {
    final ics = ICalWriter.event(
      uid: 'u1@ogneliss',
      summary: 'Встреча; итоги, планы',
      description: 'Строка 1\nСтрока 2 ${'x' * 120}',
      start: DateTime.utc(2026, 5, 1, 9),
      end: DateTime.utc(2026, 5, 1, 10),
      alarmMinutes: 10,
      rrule: 'FREQ=DAILY',
    );
    final ev = ICalParser.parse(ics).single;
    expect(ev.summary, 'Встреча; итоги, планы');
    expect(ev.description, startsWith('Строка 1\nСтрока 2 xxx'));
    expect(ev.description!.length, 'Строка 1\nСтрока 2 '.length + 120);
    expect(ev.alarmMinutes, 10);
    expect(ev.rrule, 'FREQ=DAILY');
    for (final line in ics.split('\r\n')) {
      expect(line.length <= 75, isTrue);
    }
  });

  test('VTODO: срок, состояние, важность, напоминание; правка сохраняет прочее', () {
    const todo = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VTODO\r\n'
        'UID:t1@yandex.ru\r\n'
        'SUMMARY:Сдать отчёт\r\n'
        'DTSTART:20261001T050000Z\r\n'
        'DUE;VALUE=DATE:20261009\r\n'
        'PRIORITY:1\r\n'
        'STATUS:NEEDS-ACTION\r\n'
        'CATEGORIES:Работа\r\n'
        'BEGIN:VALARM\r\n'
        'ACTION:DISPLAY\r\n'
        'TRIGGER;VALUE=DATE-TIME:20261008T050000Z\r\n'
        'END:VALARM\r\n'
        'END:VTODO\r\n'
        'END:VCALENDAR\r\n';
    final t = ICalTodoParser.parse(todo).single;
    expect(t.summary, 'Сдать отчёт');
    expect(t.due, DateTime(2026, 10, 9));
    expect(t.dueIsDate, isTrue);
    expect(t.priority, 1);
    expect(t.isDone, isFalse);
    expect(t.reminderAt!.toUtc(), DateTime.utc(2026, 10, 8, 5));

    final out = ICalTodoWriter.patch(todo,
        summary: 'Сдать отчёт за квартал',
        due: DateTime(2026, 10, 10),
        status: 'COMPLETED',
        priority: 5);
    final t2 = ICalTodoParser.parse(out).single;
    expect(t2.summary, 'Сдать отчёт за квартал');
    expect(t2.due, DateTime(2026, 10, 10));
    expect(t2.isDone, isTrue);
    expect(t2.priority, 5);
    expect(t2.reminderAt, isNull);
    // Начало раньше нового срока — остаётся.
    expect(t2.start, isNotNull);
    expect(out.contains('CATEGORIES:Работа'), isTrue);
  });

  test('VTODO: новая задача', () {
    final ics = ICalTodoWriter.todo(
        uid: 'n1', summary: 'Позвонить', due: DateTime.utc(2026, 10, 9, 9, 17), reminderAt: DateTime.utc(2026, 10, 9, 8));
    final t = ICalTodoParser.parse(ics).single;
    expect(t.uid, 'n1');
    expect(t.due!.toUtc(), DateTime.utc(2026, 10, 9, 9, 17));
    expect(t.reminderAt!.toUtc(), DateTime.utc(2026, 10, 9, 8));
    expect(t.isDone, isFalse);
  });

  test('UNTIL: серия, разделённая правкой «это и последующие», без дубля', () {
    const ics = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:split@google.com\r\n'
        'DTSTART;TZID=Europe/Moscow:20261012T100000\r\n'
        'DTEND;TZID=Europe/Moscow:20261012T103000\r\n'
        'RRULE:FREQ=DAILY;UNTIL=20261014T065959Z\r\n'
        'SUMMARY:Планёрка\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
    final m = ICalParser.parse(ics).single;
    final occ = ICalSeries.expand(m, DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1))!;
    // 12 и 13 октября; 14-го в 10:00 по Москве (07:00Z) — уже новая серия.
    expect(occ.map((o) => o.day), ['20261012', '20261013']);
  });

  group('Приглашения по почте (iMIP)', () {
    const invite = 'BEGIN:VCALENDAR\r\n'
        'METHOD:REQUEST\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:inv1@google.com\r\n'
        'SEQUENCE:2\r\n'
        'DTSTART:20261020T070000Z\r\n'
        'DTEND:20261020T080000Z\r\n'
        'SUMMARY:Обсуждение бюджета\r\n'
        'ORGANIZER;CN=Анна:mailto:anna@gmail.com\r\n'
        'ATTENDEE;CN=Анна;PARTSTAT=ACCEPTED:mailto:anna@gmail.com\r\n'
        'ATTENDEE;CN=Олег;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:oleg@yandex.ru\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    test('Разбор: метод, организатор, участники', () {
      final p = ICalITip.parse(invite)!;
      expect(p.method, 'REQUEST');
      expect(p.event.organizerEmail, 'anna@gmail.com');
      expect(p.event.attendees.length, 2);
    });

    test('Ответ: METHOD:REPLY, тот же UID и SEQUENCE, одна строка участника', () {
      final r = ICalITip.reply(invite, email: 'oleg@yandex.ru', name: 'Олег', partstat: 'ACCEPTED');
      expect(r.contains('METHOD:REPLY'), isTrue);
      expect(r.contains('UID:inv1@google.com'), isTrue);
      expect(r.contains('SEQUENCE:2'), isTrue);
      expect(r.contains('ORGANIZER;CN=Анна:mailto:anna@gmail.com'), isTrue);
      final ev = ICalParser.parse(r).single;
      expect(ev.attendees.single.email, 'oleg@yandex.ru');
      expect(ev.attendees.single.partstat, 'ACCEPTED');
    });

    test('В свой календарь: без METHOD, наш ответ проставлен', () {
      final c = ICalITip.forCalendar(invite, email: 'oleg@yandex.ru', partstat: 'TENTATIVE');
      expect(c.contains('METHOD:'), isFalse);
      final ev = ICalParser.parse(c).single;
      final me = ev.attendees.firstWhere((a) => a.email == 'oleg@yandex.ru');
      expect(me.partstat, 'TENTATIVE');
      expect(c.contains('RSVP=TRUE:mailto:oleg'), isFalse);
      expect(ev.attendees.length, 2);
    });

    test('Нас нет в списке участников — строка добавляется', () {
      final c = ICalITip.forCalendar(invite, email: 'boss@corp.ru', partstat: 'ACCEPTED');
      expect(ICalParser.parse(c).single.attendees.length, 3);
    });
  });
}

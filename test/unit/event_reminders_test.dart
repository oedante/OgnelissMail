// test/unit/event_reminders_test.dart
// 1.7.2+110: несколько напоминаний у встречи — хранение (remindersJson),
// что уходит на сервер Exchange, слияние при синхронизации, напоминания
// телефона; CalDAV — несколько VALARM.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/calendar/event_reminders.dart';
import 'package:ogneliss/services/mail/dav/ical_parser.dart';
import 'package:ogneliss/services/notifications/reminder_scheduler_service.dart';

List<Map<String, dynamic>> _list(String? json) =>
    (jsonDecode(json!) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

void main() {
  test('по возрастанию, без повторов и отрицательных', () {
    expect(EventReminders.normalize([1440, 15, 15, -1, 0]), [0, 15, 1440]);
  });

  test('Exchange: ближайшее — на сервер, остальные — только телефон', () {
    final json = EventReminders.encode([1440, 15, 60], serverKeepsAll: false);
    expect(_list(json), [
      {'minutesBefore': 15},
      {'minutesBefore': 60, 'local': true},
      {'minutesBefore': 1440, 'local': true},
    ]);
    // Планировщик видит все три.
    expect(ReminderSchedulerService.remindersOf(json), [15, 60, 1440]);
  });

  test('CalDAV и встреча без сервера: все без отметок; пусто — явно без напоминаний', () {
    expect(_list(EventReminders.encode([30, 10], serverKeepsAll: true)), [
      {'minutesBefore': 10},
      {'minutesBefore': 30},
    ]);
    final none = EventReminders.encode(const [], serverKeepsAll: false);
    expect(none, '[]');
    expect(ReminderSchedulerService.remindersOf(none), isEmpty);
  });

  test('синхронизация: серверное заменяется, телефонные остаются', () {
    final mine = EventReminders.encode([15, 1440], serverKeepsAll: false);
    // В Outlook напоминание сменили на 30 минут.
    final merged = EventReminders.merge([30], mine);
    expect(ReminderSchedulerService.remindersOf(merged), [30, 1440]);
    expect(_list(merged).last['local'], isTrue);
    // Сервер прислал то же, что телефонное, — без повтора.
    expect(ReminderSchedulerService.remindersOf(EventReminders.merge([1440], mine)), [1440]);
  });

  test('сервер ничего не прислал — остаётся, что было', () {
    final mine = EventReminders.encode([15, 60], serverKeepsAll: false);
    expect(EventReminders.merge(const [], mine), mine);
    expect(EventReminders.merge(const [], null), isNull);
  });

  test('напоминания телефона (карточка встречи) синхронизация не трогает', () {
    final phone = EventReminders.encodePhoneOnly([60, 5]);
    expect(EventReminders.merge([15], phone), phone);
    // «Без напоминания» на телефоне — тоже.
    final off = EventReminders.encodePhoneOnly(const []);
    expect(ReminderSchedulerService.remindersOf(off), isEmpty);
    expect(EventReminders.merge([15], off), off);
  });

  test('старый формат (до 1.7.2+110) — как раньше: сервер заменяет', () {
    const old = '[{"minutesBefore":45}]';
    expect(ReminderSchedulerService.remindersOf(EventReminders.merge([15], old)), [15]);
  });

  group('CalDAV: несколько VALARM', () {
    const ics = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:x@ya\r\n'
        'DTSTART:20261101T090000Z\r\n'
        'DTEND:20261101T100000Z\r\n'
        'SUMMARY:Сверка\r\n'
        'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n'
        'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-P1D\r\nEND:VALARM\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    test('читаются все напоминания', () {
      final ev = ICalParser.parse(ics).single;
      expect(ev.alarms, [15, 1440]);
      expect(ev.alarmMinutes, 15);
    });

    test('новое событие — все напоминания', () {
      final out = ICalWriter.event(
        uid: 'n@ogneliss',
        summary: 'Обход',
        start: DateTime.utc(2026, 11, 2, 9),
        end: DateTime.utc(2026, 11, 2, 10),
        alarms: const [60, 10, 60],
      );
      expect(ICalParser.parse(out).single.alarms, [60, 10]);
    });

    test('правка заменяет набор напоминаний; пустой — без напоминаний', () {
      final changed = ICalPatch.patchMaster(ics,
          summary: 'Сверка',
          start: DateTime.utc(2026, 11, 1, 9),
          end: DateTime.utc(2026, 11, 1, 10),
          allDay: false,
          alarms: const [5, 120, 10080]);
      expect(ICalParser.parse(changed).single.alarms, [5, 120, 10080]);
      final cleared = ICalPatch.patchMaster(ics,
          summary: 'Сверка',
          start: DateTime.utc(2026, 11, 1, 9),
          end: DateTime.utc(2026, 11, 1, 10),
          allDay: false,
          alarms: const []);
      expect(ICalParser.parse(cleared).single.alarms, isEmpty);
      // Без списка и без alarmMinutes — напоминания не трогаются.
      final kept = ICalPatch.patchMaster(ics,
          summary: 'Сверка 2',
          start: DateTime.utc(2026, 11, 1, 9),
          end: DateTime.utc(2026, 11, 1, 10),
          allDay: false);
      expect(ICalParser.parse(kept).single.alarms, [15, 1440]);
    });
  });
}

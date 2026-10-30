// События на весь день (1.8.13, замечание владельца 29.10.2026: «события
// ящика iCloud относятся на два дня»).
//  · В календаре приложения событие iCloud на весь день — ровно один день.
//  · Напоминание iCloud «в день события в 9:00» (TRIGGER после начала)
//    звучит утром этого дня, а не в полночь.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart' show CalendarEvent;
import 'package:ogneliss/features/calendar/calendar_data.dart' show CalendarViewUtils;
import 'package:ogneliss/services/mail/dav/ical_parser.dart';
import 'package:ogneliss/services/notifications/reminder_scheduler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _icloudAllDay = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Apple Inc.//iOS 18.1//EN\r\n'
    'BEGIN:VEVENT\r\n'
    'DTSTART;VALUE=DATE:20261030\r\n'
    'DTEND;VALUE=DATE:20261031\r\n'
    'SUMMARY:День рождения\r\n'
    'UID:AD-1\r\n'
    'BEGIN:VALARM\r\n'
    'ACTION:DISPLAY\r\n'
    'TRIGGER:PT9H\r\n'
    'END:VALARM\r\n'
    'BEGIN:VALARM\r\n'
    'ACTION:DISPLAY\r\n'
    'TRIGGER:-PT15H\r\n'
    'END:VALARM\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

CalendarEvent _event(DateTime start, DateTime end, {bool allDay = false}) => CalendarEvent(
      id: 'e',
      accountId: 'a',
      title: 'T',
      startTime: start,
      endTime: end,
      createdAt: DateTime(2026),
      isAllDay: allDay,
      recurrence: 0,
      priority: 1,
      showAs: 2,
      isPrivate: false,
      isCancelled: false,
      isLocallyModified: false,
    );

void main() {
  test('событие iCloud на весь день — один день в календаре', () {
    final ev = ICalParser.parse(_icloudAllDay).single;
    expect(ev.isAllDay, isTrue);
    expect(ev.start, DateTime(2026, 10, 30));
    expect(ev.end, DateTime(2026, 10, 31));
    final row = _event(ev.start!, ev.end!, allDay: true);
    expect(CalendarViewUtils.eventsForDay([row], DateTime(2026, 10, 30)), hasLength(1));
    expect(CalendarViewUtils.eventsForDay([row], DateTime(2026, 10, 31)), isEmpty);
    expect(CalendarViewUtils.eventsForDay([row], DateTime(2026, 10, 29)), isEmpty);
    // «В день события в 9:00» — после начала: «в момент начала» (0),
    // «накануне в 9:00» — за 15 часов.
    expect(ev.alarms, [0, 900]);
  });

  test('напоминание «в момент начала» у события на весь день — утром, не в полночь', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final allDay = _event(DateTime(2026, 10, 30), DateTime(2026, 10, 31), allDay: true);
    expect(ReminderSchedulerService.reminderTime(allDay, 0, prefs), DateTime(2026, 10, 30, 9));
    expect(ReminderSchedulerService.reminderTime(allDay, 900, prefs), DateTime(2026, 10, 29, 9));
    await prefs.setInt('mod_task_due_hour', 8);
    expect(ReminderSchedulerService.reminderTime(allDay, 0, prefs), DateTime(2026, 10, 30, 8));
    final timed = _event(DateTime(2026, 10, 30, 10), DateTime(2026, 10, 30, 11));
    expect(ReminderSchedulerService.reminderTime(timed, 0, prefs), DateTime(2026, 10, 30, 10));
    expect(ReminderSchedulerService.reminderTime(timed, 15, prefs), DateTime(2026, 10, 30, 9, 45));
  });
}

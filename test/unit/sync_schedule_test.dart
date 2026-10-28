import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/sync/sync_schedule.dart';

void main() {
  setUp(() {
    SyncSchedule.startMinutes = 7 * 60;
    SyncSchedule.endMinutes = 19 * 60;
    SyncSchedule.days = {1, 2, 3, 4, 5};
  });

  test('рабочее окно пн–пт 7:00–19:00', () {
    // 12.10.2026 — понедельник.
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 12, 6, 59)), isFalse);
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 12, 7, 0)), isTrue);
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 12, 18, 59)), isTrue);
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 12, 19, 0)), isFalse);
    // Суббота.
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 10, 12, 0)), isFalse);
  });

  test('окно через полночь относится ко дню начала', () {
    SyncSchedule.startMinutes = 22 * 60;
    SyncSchedule.endMinutes = 6 * 60;
    SyncSchedule.days = {5}; // пятница
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 16, 23, 0)), isTrue); // пт 23:00
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 17, 5, 0)), isTrue); // сб 5:00 — ночь пятницы
    expect(SyncSchedule.inWindow(DateTime(2026, 10, 17, 23, 0)), isFalse); // сб 23:00
  });

  test('подпись окна', () {
    expect(SyncSchedule.windowLabel(), '7:00–19:00');
  });
}

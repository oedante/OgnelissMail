// Приглашение в письме (2.2.0, план 08.11.2026 п. 5): повторение,
// пересечение с моим календарём (без самой встречи).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/calendar/event_conflicts.dart';
import 'package:ogneliss/features/mail/widgets/meeting_invite_banner.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('повторение по RRULE — на языке приложения', () {
    final l10n = AppLocalizations(const Locale('ru'));
    expect(inviteRecurrenceText(null, l10n, 'ru'), isNull);
    expect(inviteRecurrenceText('FREQ=DAILY', l10n, 'ru'), 'Ежедневно');
    expect(inviteRecurrenceText('FREQ=WEEKLY;BYDAY=MO,WE', l10n, 'ru'), 'Еженедельно: пн, ср');
    expect(inviteRecurrenceText('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR', l10n, 'ru'), 'Раз в 2 недели: пт');
    expect(inviteRecurrenceText('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', l10n, 'ru'), 'По будням');
    expect(inviteRecurrenceText('FREQ=MONTHLY;BYMONTHDAY=1', l10n, 'ru'), 'Ежемесячно');
    expect(inviteRecurrenceText('FREQ=DAILY;INTERVAL=3', l10n, 'ru'), 'Повторяющаяся встреча');
  });

  group('пересечения', () {
    late AppDatabase db;
    final start = DateTime.utc(2026, 11, 10, 7);
    final end = DateTime.utc(2026, 11, 10, 8);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
      Future<void> ev(String id, String title, DateTime s, DateTime e, {int showAs = 2}) =>
          db.into(db.calendarEvents).insert(CalendarEventsCompanion.insert(
              id: id, accountId: 'a1', title: title, startTime: s, endTime: e, showAs: Value(showAs), createdAt: DateTime(2026)));
      // Сама встреча — Exchange поставил её «под вопросом».
      await ev('self', 'Стартовое совещание', start, end, showAs: 1);
      await ev('p', 'Планёрка', start.subtract(const Duration(minutes: 30)), start.add(const Duration(minutes: 15)));
      await ev('free', 'Обед', start, end, showAs: 0);
      await ev('later', 'Звонок', end, end.add(const Duration(hours: 1)));
    });
    tearDown(() => db.close());

    test('пересекается с «Планёркой»; сама встреча, «свободно» и встреча после — нет', () async {
      final r = await meetingConflicts(db, start: start, end: end, accountId: 'a1', subject: 'Приглашение: Стартовое совещание');
      expect([for (final e in r) e.title], ['Планёрка']);
    });
  });
}

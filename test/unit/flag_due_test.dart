// Срок флажка, как в Outlook (2.7.2, просьба владельца 24.11.2026:
// «флажок устанавливается без даты — нужно, как в Outlook, „сегодня“»).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/flag_due.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Понедельник 23.11.2026 … воскресенье 29.11.2026.
  DateTime day(int d, [int h = 10]) => DateTime(2026, 11, d, h);

  test('«Сегодня» и «Завтра» — начало и срок в один день', () {
    expect(FlagDues.datesOf(FlagDue.today, day(24)), (start: DateTime(2026, 11, 24), due: DateTime(2026, 11, 24)));
    expect(FlagDues.datesOf(FlagDue.tomorrow, day(24)), (start: DateTime(2026, 11, 25), due: DateTime(2026, 11, 25)));
    // Конец месяца.
    expect(FlagDues.datesOf(FlagDue.tomorrow, DateTime(2026, 11, 30, 9))!.due, DateTime(2026, 12, 1));
    expect(FlagDues.datesOf(FlagDue.none, day(24)), isNull);
  });

  test('«На этой неделе» — срок в пятницу, начало через два дня, но не позже срока', () {
    expect(FlagDues.datesOf(FlagDue.thisWeek, day(23)), (start: DateTime(2026, 11, 25), due: DateTime(2026, 11, 27)));
    expect(FlagDues.datesOf(FlagDue.thisWeek, day(26)), (start: DateTime(2026, 11, 27), due: DateTime(2026, 11, 27)));
    // Пятница и выходные — сегодня.
    expect(FlagDues.datesOf(FlagDue.thisWeek, day(27)), (start: DateTime(2026, 11, 27), due: DateTime(2026, 11, 27)));
    expect(FlagDues.datesOf(FlagDue.thisWeek, day(29)), (start: DateTime(2026, 11, 29), due: DateTime(2026, 11, 29)));
  });

  test('«На следующей неделе» — с понедельника по пятницу', () {
    for (final d in [23, 25, 27, 28, 29]) {
      expect(FlagDues.datesOf(FlagDue.nextWeek, day(d)), (start: DateTime(2026, 11, 30), due: DateTime(2026, 12, 4)),
          reason: 'из $d.11');
    }
  });

  test('срок в базе — 18:00 дня; просрочен только со следующего дня', () {
    final at = FlagDues.atFor(FlagDue.today, day(24))!;
    expect(at, DateTime(2026, 11, 24, 18));
    expect(FlagDues.overdue(at, DateTime(2026, 11, 24, 23, 30)), isFalse, reason: 'вечером «Сегодня» ещё не просрочен');
    expect(FlagDues.overdue(at, DateTime(2026, 11, 25, 0, 5)), isTrue);
  });

  test('срок из Outlook (полночь UTC дня срока) — тот же день, 18:00', () {
    expect(FlagDues.fromServer(DateTime.utc(2026, 11, 26)), DateTime(2026, 11, 26, 18));
    expect(FlagDues.fromServer(null), isNull);
  });

  test('подписи срока', () async {
    final l10n = await AppLocalizations.load('ru');
    expect(FlagDues.label(DateTime(2026, 11, 24, 18), l10n, day(24)), 'Сегодня');
    expect(FlagDues.label(DateTime(2026, 11, 25, 18), l10n, day(24)), 'Завтра');
    expect(FlagDues.label(DateTime(2026, 11, 23, 18), l10n, day(24)), 'Вчера');
    expect(FlagDues.label(DateTime(2026, 11, 27, 18), l10n, day(24)), contains('27'));
  });

  test('напоминание «нет ответа» не снимает срок флажка', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
        "INSERT INTO accounts (id, type, email, display_name, username, created_at) VALUES ('a1', 0, 'me@x.ru', 'Я', 'me', 0)");
    Future<void> mail(String id, {required bool flagged, required int control}) => db.customStatement(
        'INSERT INTO emails (id, account_id, folder_id, from_email, to_recipients, subject, received_at, is_flagged, control_state, follow_up_at) '
        "VALUES (?, 'a1', 'INBOX', 'x@y.ru', '[]', 's', 0, ?, ?, ?)",
        [id, flagged ? 1 : 0, control, DateTime(2026, 11, 20, 18).millisecondsSinceEpoch ~/ 1000]);
    await mail('flag', flagged: true, control: 0);
    await mail('control', flagged: true, control: 1);
    await mail('stale', flagged: false, control: 0);
    final due = await db.dueFollowUps(DateTime(2026, 11, 24));
    expect({for (final e in due) e.id}, {'control', 'stale'});
  });
}

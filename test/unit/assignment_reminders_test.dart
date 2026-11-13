// Напоминания о сроках поручений (просьба владельца 13.11.2026):
// исполнителю — накануне и в день срока, поручившему — утром после срока.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:ogneliss/services/notifications/reminder_scheduler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  const me = 'me@corp.ru';
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: me, displayName: 'Я', username: me, createdAt: DateTime(2026)));
  });
  tearDown(() => db.close());

  final mine = {
    'a1': {me}
  };
  final now = DateTime(2026, 11, 13, 12);

  Future<void> add(String id, {required String owner, String? to, DateTime? due, int status = 1, bool project = false, String? after, String? parent}) async {
    await AssignmentStore.insert(db,
        id: id,
        accountId: 'a1',
        title: 'Поручение $id',
        ownerEmail: owner,
        ownerName: owner == me ? 'Я' : 'Начальник',
        assigneeEmail: to,
        assigneeName: to == me ? 'Я' : 'Вера',
        due: due,
        at: now.subtract(const Duration(days: 3)),
        outgoing: owner == me,
        isProject: project,
        afterId: after,
        parentId: parent);
    if (status != 1) await AssignmentStore.update(db, id, status: status);
  }

  test('исполнителю — накануне и в день срока, поручившему — после срока', () async {
    await add('AAAAAAAAAAA2', owner: 'boss@corp.ru', to: me, due: DateTime(2026, 11, 15));
    await add('AAAAAAAAAAA3', owner: me, to: 'vera@corp.ru', due: DateTime(2026, 11, 14));
    final list = await AssignmentStore.all(db, mine);
    final r = ReminderSchedulerService.assignmentReminders(list, now, dueHour: 9);
    final got = {for (final x in r) '${x.v.id}|${x.kind}': x.when};
    expect(got, {
      'AAAAAAAAAAA2|tomorrow': DateTime(2026, 11, 14, 9),
      'AAAAAAAAAAA2|today': DateTime(2026, 11, 15, 9),
      'AAAAAAAAAAA3|late': DateTime(2026, 11, 15, 9),
    });
  });

  test('без напоминаний: сдано, выполнено, снято, без срока, прошло, проект, ждёт этапа', () async {
    await add('BBBBBBBBBBB2', owner: 'boss@corp.ru', to: me, due: DateTime(2026, 11, 15), status: AssignmentStatus.review);
    await add('BBBBBBBBBBB3', owner: 'boss@corp.ru', to: me, due: DateTime(2026, 11, 15), status: AssignmentStatus.done);
    await add('BBBBBBBBBBB4', owner: me, to: 'vera@corp.ru', due: DateTime(2026, 11, 14), status: AssignmentStatus.cancelled);
    await add('BBBBBBBBBBB5', owner: 'boss@corp.ru', to: me);
    // Срок был вчера: накануне и в день срока — уже прошли.
    await add('BBBBBBBBBBB6', owner: 'boss@corp.ru', to: me, due: DateTime(2026, 11, 12));
    await add('BBBBBBBBBBB7', owner: me, due: DateTime(2026, 11, 20), project: true);
    // Этап ждёт предыдущего (afterId) — о сроке не напоминаем.
    await add('BBBBBBBBBBB8', owner: 'boss@corp.ru', to: me, due: DateTime(2026, 11, 18), after: 'BBBBBBBBBBB9');
    // Наблюдателю — ничего.
    await add('BBBBBBBBBBC2', owner: 'boss@corp.ru', to: 'vera@corp.ru', due: DateTime(2026, 11, 16));
    await AssignmentStore.addParticipant(db, 'BBBBBBBBBBC2', me, AssignmentRole.observer);
    final list = await AssignmentStore.all(db, mine);
    expect(ReminderSchedulerService.assignmentReminders(list, now), isEmpty);
  });

  test('контролирующему — после срока; за горизонтом — нет', () async {
    await add('CCCCCCCCCCC2', owner: 'boss@corp.ru', to: 'vera@corp.ru', due: DateTime(2026, 11, 16));
    await AssignmentStore.addParticipant(db, 'CCCCCCCCCCC2', me, AssignmentRole.controller);
    await add('CCCCCCCCCCC3', owner: 'boss@corp.ru', to: me, due: DateTime(2027, 1, 20));
    final list = await AssignmentStore.all(db, mine);
    final r = ReminderSchedulerService.assignmentReminders(list, now, dueHour: 10);
    expect([for (final x in r) '${x.v.id}|${x.kind}|${x.when}'], ['CCCCCCCCCCC2|late|${DateTime(2026, 11, 17, 10)}']);
  });

  test('текст: срок, исполнитель, проект', () async {
    await AppLocalizations.load('ru');
    final l10n = AppLocalizations(const Locale('ru'));
    await add('DDDDDDDDDDD2', owner: me, to: 'vera@corp.ru', due: DateTime(2026, 11, 14));
    final v = (await AssignmentStore.all(db, mine)).single;
    expect(ReminderSchedulerService.assignmentBody(v, 'tomorrow', l10n), 'Поручение: срок завтра, 14.11');
    expect(ReminderSchedulerService.assignmentBody(v, 'late', l10n, projectTitle: 'Ремонт'),
        'Срок прошёл 14.11 · исполнитель: Вера · Ремонт');
  });
}

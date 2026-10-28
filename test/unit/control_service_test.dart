// test/unit/control_service_test.dart
// «На контроле»: ответ находится по беседе и по References, исполненные
// отметки не трогаются, сопоставление отправленного письма.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/control_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'me@example.com';

Future<void> _mail(
  AppDatabase db,
  String id, {
  required String from,
  required DateTime at,
  String? conv,
  String? mid,
  String? refs,
  int control = 0,
  String subject = 'Смета',
  String to = '[]',
}) =>
    db.into(db.emails).insert(EmailsCompanion.insert(
          id: id,
          accountId: 'a1',
          folderId: 'INBOX',
          fromEmail: from,
          toRecipients: to,
          subject: subject,
          receivedAt: at,
          conversationId: Value(conv),
          internetMessageId: Value(mid),
          referencesStr: Value(refs),
          controlState: Value(control),
        ));

Future<int> _state(AppDatabase db, String id) async =>
    (await (db.select(db.emails)..where((e) => e.id.equals(id))).getSingle()).controlState;

void main() {
  late Directory dir;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ogneliss_control_test');
    db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/c.db')));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1',
          type: 7,
          email: _me,
          displayName: 'a1',
          username: 'a1',
          createdAt: DateTime(2026, 1, 1),
        ));
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('начальное состояние: своё письмо — ждём ответа, чужое — нужно ответить', () {
    expect(ControlService.initialFor(fromEmail: 'Me@Example.com', myEmail: _me), ControlState.awaitingReply);
    expect(ControlService.initialFor(fromEmail: 'boss@example.com', myEmail: _me), ControlState.mustReply);
  });

  test('я только в копии — ждём ответа; в «Кому» — нужно ответить', () {
    expect(ControlService.initialFor(fromEmail: 'boss@example.com', myEmail: _me, to: ['colleague@example.com']),
        ControlState.awaitingReply);
    expect(ControlService.initialFor(fromEmail: 'boss@example.com', myEmail: _me, to: ['colleague@example.com', 'ME@example.com']),
        ControlState.mustReply);
    expect(ControlService.initialFor(fromEmail: 'boss@example.com', myEmail: _me, to: const []), ControlState.mustReply);
  });

  test('ждём ответа: ответ в беседе → «Исполнено»; мой же следующий ответ — не считается', () async {
    await _mail(db, 'sent', from: _me, at: DateTime(2026, 10, 1, 10), conv: 'c1',
        control: ControlState.awaitingReply);
    await _mail(db, 'mine', from: _me, at: DateTime(2026, 10, 1, 11), conv: 'c1');
    expect(await ControlService.check(db, {'a1': _me}), 0);
    expect(await _state(db, 'sent'), ControlState.awaitingReply);

    await _mail(db, 'reply', from: 'boss@example.com', at: DateTime(2026, 10, 1, 12), conv: 'c1');
    expect(await ControlService.check(db, {'a1': _me}), 1);
    expect(await _state(db, 'sent'), ControlState.done);
    // Исполненное больше не проверяется и не снимается автоматически.
    expect(await ControlService.check(db, {'a1': _me}), 0);
    expect(await _state(db, 'sent'), ControlState.done);
  });

  test('нужно ответить: мой ответ без беседы находится по References', () async {
    await _mail(db, 'in', from: 'boss@example.com', at: DateTime(2026, 10, 1, 10),
        mid: '<abc123@corp.example>', control: ControlState.mustReply);
    await _mail(db, 'other', from: 'x@example.com', at: DateTime(2026, 10, 1, 11),
        refs: '<abc123@corp.example>');
    expect(await ControlService.check(db, {'a1': _me}), 0);

    await _mail(db, 'answer', from: _me, at: DateTime(2026, 10, 1, 12),
        refs: '<zzz@corp.example> <abc123@corp.example>');
    expect(await ControlService.check(db, {'a1': _me}), 1);
    expect(await _state(db, 'in'), ControlState.done);
  });

  test('«На контроль» при отправке: письмо в «Отправленных» получает отметку', () async {
    SharedPreferences.setMockInitialValues({});
    final sentAt = DateTime.now();
    await ControlService.addPending(accountId: 'a1', subject: '  Смета  на ремонт', firstTo: 'Boss@Example.com');
    await _mail(db, 's1', from: _me, at: sentAt, subject: 'Смета на ремонт');
    final model = EmailModel(
      id: 's1',
      accountId: 'a1',
      folderId: 'SENT',
      from: const EmailAddress(email: _me),
      to: const [EmailAddress(email: 'boss@example.com')],
      subject: 'Смета на ремонт',
      receivedAt: sentAt,
    );
    await ControlService.matchSent(db, 'a1', [model]);
    expect(await _state(db, 's1'), ControlState.awaitingReply);
    // Второе такое же письмо не отмечается — ожидание уже использовано.
    await _mail(db, 's2', from: _me, at: sentAt, subject: 'Смета на ремонт');
    await ControlService.matchSent(db, 'a1', [model.copyWith(id: 's2')]);
    expect(await _state(db, 's2'), ControlState.none);
  });

  test('несколько адресатов: «Исполнено», когда ответили все из «Кому»; копия не считается', () async {
    const to = '[{"email":"a@example.com"},{"email":"b@example.com"},{"email":"me@example.com"}]';
    await _mail(db, 'sent', from: _me, at: DateTime(2026, 10, 1, 10), conv: 'c9', control: 1, to: to);
    // Ответил человек из копии — не считается.
    await _mail(db, 'cc', from: 'cc@example.com', at: DateTime(2026, 10, 1, 11), conv: 'c9');
    await ControlService.check(db, {'a1': _me});
    expect(await _state(db, 'sent'), ControlState.awaitingReply);
    // Ответил один из двух — 1 из 2, ещё ждём.
    await _mail(db, 'r1', from: 'A@example.com', at: DateTime(2026, 10, 1, 12), conv: 'c9');
    expect(await ControlService.check(db, {'a1': _me}), 0);
    final row = await (db.select(db.emails)..where((e) => e.id.equals('sent'))).getSingle();
    expect(row.controlReplied, 'a@example.com');
    expect(ControlService.progress(state: 1, to: ControlService.toRecipients(to, _me), replied: row.controlReplied),
        (replied: 1, total: 2));
    // Ответил второй — исполнено.
    await _mail(db, 'r2', from: 'b@example.com', at: DateTime(2026, 10, 1, 13), conv: 'c9');
    expect(await ControlService.check(db, {'a1': _me}), 1);
    expect(await _state(db, 'sent'), ControlState.done);
  });
}

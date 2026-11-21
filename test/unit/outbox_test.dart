// «Исходящие», как в Outlook (21.11.2026): письмо с отсчётом — сразу в
// списке; «Отменить» возвращает его в «Черновики»; неотправленное остаётся
// с ошибкой; отправляемое отменить нельзя; отправленное пропадает.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/mail/screens/outbox_screen.dart';
import 'package:ogneliss/services/mail/offline_send_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
        username: 'me', createdAt: DateTime(2026)));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Список «Исходящих», когда поток из базы его обновит.
  Future<List<OutboxItem>> items([bool Function(List<OutboxItem>)? until]) async {
    final sub = container.listen(outboxItemsProvider, (_, __) {});
    try {
      for (var i = 0; i < 50; i++) {
        final v = container.read(outboxItemsProvider).value;
        if (v != null && (until == null || until(v))) return v;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return container.read(outboxItemsProvider).value ?? const [];
    } finally {
      sub.close();
    }
  }

  Future<int> failed(String subject, String error) => db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
        accountId: 'a1',
        operationType: 'send_failed',
        targetId: 'q_$subject',
        payloadJson: jsonEncode({
          'to': [{'email': 'boss@example.com', 'displayName': 'Начальник'}],
          'subject': subject,
          'bodyHtml': '<p>Текст <b>письма</b></p>',
        }),
        createdAt: DateTime.now(),
        errorMessage: Value(error),
      ));

  test('письмо с отсчётом — сразу в «Исходящих»; «Отменить» — в черновики', () async {
    final service = container.read(offlineSendProvider);
    final id = await service.scheduleUndoSend(
      accountId: 'a1',
      fromEmail: 'me@example.com',
      to: const [EmailAddress(email: 'boss@example.com', displayName: 'Начальник')],
      subject: 'Отчёт',
      bodyHtml: '<p>Привет</p>',
      window: const Duration(hours: 1),
    );
    final list = await items((l) => l.isNotEmpty);
    expect(list, hasLength(1));
    final item = list.single;
    expect(item.subject, 'Отчёт');
    expect(item.to, 'Начальник');
    expect(item.preview, 'Привет');
    expect(item.waiting(DateTime.now()), isTrue);
    expect(item.cancellable, isTrue);

    final op = await (db.select(db.syncQueue)..where((q) => q.id.equals(item.queueId))).getSingle();
    expect(await service.cancelToDraft(op), id);
    expect(await db.select(db.syncQueue).get(), isEmpty);
    final row = await (db.select(db.emails)..where((e) => e.id.equals(id))).getSingle();
    expect(row.folderId, 'drafts');
    expect(row.isDraft, isTrue);
  });

  test('не отправленное — с ошибкой; «Отменить» — в черновики', () async {
    await failed('Счёт', 'Сервер не принял письмо');
    final item = (await items((l) => l.isNotEmpty)).single;
    expect(item.failed, isTrue);
    expect(item.error, 'Сервер не принял письмо');
    expect(item.cancellable, isTrue);
    final op = await (db.select(db.syncQueue)..where((q) => q.id.equals(item.queueId))).getSingle();
    final draftId = await container.read(offlineSendProvider).cancelToDraft(op);
    expect(draftId, isNotNull);
    expect(await db.select(db.syncQueue).get(), isEmpty);
    final draft = await (db.select(db.emails)..where((e) => e.id.equals(draftId!))).getSingle();
    expect(draft.subject, 'Счёт');
  });

  test('отправляемое отменить нельзя; отправленное пропадает из списка', () async {
    final id = await failed('Акт', '');
    await (db.update(db.syncQueue)..where((q) => q.id.equals(id)))
        .write(const SyncQueueCompanion(operationType: Value('send_inflight')));
    final item = (await items((l) => l.isNotEmpty && l.single.sending)).single;
    expect(item.sending, isTrue);
    expect(item.cancellable, isFalse);
    final op = await (db.select(db.syncQueue)..where((q) => q.id.equals(id))).getSingle();
    expect(await container.read(offlineSendProvider).cancelToDraft(op), isNull);
    expect(await db.select(db.syncQueue).get(), hasLength(1), reason: 'письмо остаётся, пока отправляется');

    // Отправилось — строка очереди удалена, в списке пусто.
    await (db.delete(db.syncQueue)..where((q) => q.id.equals(id))).go();
    expect(await items((l) => l.isEmpty), isEmpty);
  });
}

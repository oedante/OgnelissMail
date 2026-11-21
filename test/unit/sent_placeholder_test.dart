// Отправленное письмо в беседе (2.6.8, замечания владельца 21.11.2026):
// «карточки в беседах… пустыми, а потом подгружают. Часто если только
// отправил» и «дублирование писем в беседах» — временная строка быстрого
// ответа оставалась рядом с серверной копией навсегда.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart' show FolderType;
import 'package:ogneliss/features/mail/screens/conversation_screen.dart' show conversationWithoutPlaceholders;
import 'package:ogneliss/services/mail/sent_placeholder.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  final account = AccountModel(
      id: 'a1', type: AccountType.google, email: 'me@gmail.com', displayName: 'Я', username: 'me', createdAt: DateTime(2026));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: AccountType.google.index, email: 'me@gmail.com', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'INBOX', accountId: 'a1', displayName: 'Входящие', type: Value(FolderType.inbox.index)));
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: '[Gmail]/Sent', accountId: 'a1', displayName: 'Отправленные', type: Value(FolderType.sent.index)));
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'INBOX:1',
          accountId: 'a1',
          folderId: 'INBOX',
          conversationId: const Value('c1'),
          internetMessageId: const Value('<orig@mail.example>'),
          fromEmail: 'valery@gmail.com',
          toRecipients: '[]',
          subject: 'Виджет',
          receivedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ));
  });
  tearDown(() => db.close());

  test('беседа — по последнему Message-ID цепочки «References + Message-ID»', () async {
    expect(await SentPlaceholder.conversationOf(db, 'a1', '<a@x> <b@y> <orig@mail.example>'), 'c1');
    expect(await SentPlaceholder.conversationOf(db, 'a1', 'orig@mail.example'), 'c1');
    expect(await SentPlaceholder.conversationOf(db, 'a1', '<other@x>'), isNull);
    expect(await SentPlaceholder.conversationOf(db, 'a1', null), isNull);
  });

  test('пришла серверная копия без текста — строка убрана, её превью — в копию', () async {
    await SentPlaceholder.insert(db, account,
        conversationId: 'c1',
        to: const [EmailAddress(email: 'valery@gmail.com')],
        subject: 'RE: Виджет',
        html: '<p>Это в новой версии?</p>',
        text: 'Это в новой версии?');
    // Серверная копия в «Отправленных» — только заголовки (IMAP).
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: '[Gmail]/Sent:7',
          accountId: 'a1',
          folderId: '[Gmail]/Sent',
          conversationId: const Value('c1'),
          fromEmail: 'me@gmail.com',
          toRecipients: '[]',
          subject: 'Re: Виджет',
          receivedAt: DateTime.now(),
        ));
    expect(await SentPlaceholder.dropReplaced(db, 'a1'), 0);
    final rows = await (db.select(db.emails)..where((e) => e.folderId.equals('[Gmail]/Sent'))).get();
    expect(rows.map((r) => r.id), ['[Gmail]/Sent:7']);
    expect(rows.single.bodyPreview, 'Это в новой версии?');
  });

  test('копии нет — строка живёт 30 минут, потом убирается', () async {
    await SentPlaceholder.insert(db, account,
        conversationId: 'c1', to: const [], subject: 'RE: Виджет', html: '<p>Добрый вечер!</p><p>Текст</p>');
    expect(await SentPlaceholder.dropReplaced(db, 'a1'), 1);
    final row = await (db.select(db.emails)..where((e) => e.folderId.equals('[Gmail]/Sent'))).getSingle();
    expect(row.id, startsWith(SentPlaceholder.prefix));
    expect(row.bodyPreview, 'Добрый вечер! Текст', reason: 'превью из HTML письма редактора');
    expect(await SentPlaceholder.dropReplaced(db, 'a1', now: DateTime.now().add(const Duration(minutes: 31))), 0);
  });

  test('в беседе временная строка не показывается рядом с серверной копией', () async {
    final at = DateTime(2026, 11, 21, 19, 10);
    Future<void> row(String id, String from, String subject, DateTime when) => db.into(db.emails).insert(
        EmailsCompanion.insert(
            id: id, accountId: 'a1', folderId: 'f', fromEmail: from, toRecipients: '[]', subject: subject, receivedAt: when));
    await row('qr_1', 'me@gmail.com', 'RE: Виджет', at);
    await row('S:7', 'me@gmail.com', 'Re: Виджет', at.subtract(const Duration(minutes: 1)));
    await row('I:1', 'valery@gmail.com', 'RE: Виджет', at);
    Future<List<Email>> get(List<String> ids) async {
      final all = await (db.select(db.emails)..where((e) => e.id.isIn(ids))).get();
      return [for (final id in ids) all.firstWhere((r) => r.id == id)];
    }

    expect(conversationWithoutPlaceholders(await get(['qr_1', 'S:7', 'I:1'])).map((r) => r.id), ['S:7', 'I:1']);
    expect(conversationWithoutPlaceholders(await get(['qr_1', 'I:1'])).map((r) => r.id), ['qr_1', 'I:1'],
        reason: 'копии ещё нет — строка видна');
  });
}

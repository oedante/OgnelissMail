// Письма серверных «Черновиков» — черновики (2.6.8, замечание владельца
// 22.11.2026: «у черновиков нет кнопки „Редактировать“, непонятно, что
// делать с черновиком»). IMAP отметку черновика не присылает: письмо из
// «[Gmail]/Черновики» в беседе и на экране письма выглядело обычным — с
// «Ответить», без «Редактировать».

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart' show FolderType;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;

  Future<void> folder(String account, String id, FolderType type) => db.into(db.folders).insert(
      FoldersCompanion.insert(id: id, accountId: account, displayName: id, type: Value(type.index)));

  Future<void> mail(String account, String id, String folderId) => db.into(db.emails).insert(EmailsCompanion.insert(
        id: id,
        accountId: account,
        folderId: folderId,
        fromEmail: 'me@gmail.com',
        toRecipients: '[]',
        subject: 'RE: Ogneliss',
        receivedAt: DateTime(2026, 11, 22, 11, 43),
      ));

  Future<bool> isDraft(String account, String id) async =>
      (await db.getEmailById(id, accountId: account))!.isDraft;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final a in ['a1', 'a2']) {
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: a, type: 0, email: '$a@gmail.com', displayName: a, username: a, createdAt: DateTime(2026)));
    }
    await folder('a1', 'INBOX', FolderType.inbox);
    await folder('a1', '[Gmail]/Черновики', FolderType.drafts);
    await folder('a2', '[Gmail]/Черновики', FolderType.drafts);
    await mail('a1', 'INBOX:7', 'INBOX');
    await mail('a1', '[Gmail]/Черновики:3', '[Gmail]/Черновики');
    await mail('a2', '[Gmail]/Черновики:3', '[Gmail]/Черновики');
  });

  tearDown(() => db.close());

  test('письмо в «Черновиках» сервера становится черновиком, остальные — нет', () async {
    expect(await isDraft('a1', '[Gmail]/Черновики:3'), isFalse, reason: 'так сохраняла синхронизация до 2.6.8');

    expect(await db.markServerDrafts('a1', FolderType.drafts.index), 1);
    expect(await isDraft('a1', '[Gmail]/Черновики:3'), isTrue);
    expect(await isDraft('a1', 'INBOX:7'), isFalse);
    expect(await isDraft('a2', '[Gmail]/Черновики:3'), isFalse, reason: 'другой ящик — своим проходом');

    expect(await db.markServerDrafts('a1', FolderType.drafts.index), 0, reason: 'повторно — ничего не меняет');
  });
}

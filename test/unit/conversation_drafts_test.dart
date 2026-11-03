// Черновики ответов в беседе (1.10.5, замечание владельца 03.11.2026: «в
// беседах не отображаются черновики. В ленте черновик видно, в папке
// черновик есть, а в беседе он отсутствует»). Черновик ответа хранится на
// сервере без заголовков ответа — у него своя беседа; экран беседы находит
// его по связи «письмо → черновик» (как «Черновик: …» в ленте), свой
// черновик на устройстве — и по parentId.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/mail/reply_drafts.dart';

EmailModel _m(String id, {String folder = 'INBOX', String subject = 'Документы', String? conv, String? parent}) =>
    EmailModel(
      id: id,
      accountId: 'a1',
      folderId: folder,
      from: const EmailAddress(email: 'me@example.com'),
      to: const [EmailAddress(email: 'boss@example.com')],
      subject: subject,
      receivedAt: DateTime(2026, 11, 3, 12),
      conversationId: conv,
      parentId: parent,
    );

ReplyDraft _link(String emailId, {String? conv, String subject = 'RE: Документы', String account = 'a1'}) =>
    ReplyDraft(
      accountId: account,
      emailId: emailId,
      conversationId: conv,
      subject: subject,
      text: 'Тест',
      at: DateTime(2026, 11, 3, 19, 35),
    );

void main() {
  group('conversationReplyDrafts', () {
    final conv = [_m('INBOX:1', conv: 't1'), _m('INBOX:2', conv: 't1')];

    List<String> found(List<EmailModel> drafts, Map<String, ReplyDraft> links) => [
          for (final d in conversationReplyDrafts(
              drafts: drafts, conversation: conv, accountId: 'a1', conversationId: 't1', replyDrafts: links))
            d.id,
        ];

    test('черновик из серверных «Черновиков» — по связи с письмом беседы и теме', () {
      final drafts = [_m('Drafts:9', folder: '[Gmail]/Drafts', subject: 'RE: Документы', conv: 'другая')];
      expect(found(drafts, {'a1|INBOX:2': _link('INBOX:2')}), ['Drafts:9']);
      // Связь с беседой, а не с письмом (ответ из свёрнутой беседы).
      expect(found(drafts, {'a1|INBOX:7': _link('INBOX:7', conv: 't1')}), ['Drafts:9']);
    });

    test('найденный — с пометкой черновика; без превью — с текстом из связи', () {
      final d = conversationReplyDrafts(
        drafts: [_m('Drafts:9', folder: 'Drafts', subject: 'RE: Документы')],
        conversation: conv,
        accountId: 'a1',
        conversationId: 't1',
        replyDrafts: {'a1|INBOX:2': _link('INBOX:2')},
      ).single;
      expect(d.isDraft, isTrue);
      expect(d.preview, 'Тест');
    });

    test('свой черновик на устройстве — по parentId, и без связи', () {
      expect(found([_m('local-1', folder: 'drafts', subject: 'RE: Документы', parent: 'INBOX:1')], {}), ['local-1']);
    });

    test('чужое не берётся: другая тема, другая беседа, другой ящик, уже в беседе', () {
      final links = {
        'a1|INBOX:2': _link('INBOX:2'),
        'a1|X:5': _link('X:5', conv: 'другая', subject: 'RE: Отпуск'),
        'a2|INBOX:2': _link('INBOX:2', account: 'a2', subject: 'RE: Банк'),
      };
      final drafts = [
        _m('Drafts:1', folder: 'Drafts', subject: 'RE: Отпуск'),
        _m('Drafts:2', folder: 'Drafts', subject: 'RE: Банк'),
        _m('INBOX:1', folder: 'Drafts', subject: 'RE: Документы'),
        _m('Drafts:3', folder: 'Drafts', subject: 'FW: Документы'),
      ];
      // «FW: Документы» — та же тема без приставки: ответ или пересылка из
      // этой беседы.
      expect(found(drafts, links), ['Drafts:3']);
      expect(found(drafts, {}), isEmpty);
    });
  });

  group('watchDraftsLight', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 1, email: 'me@example.com', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'b', type: 1, email: 'b@example.com', displayName: 'Б', username: 'b', createdAt: DateTime(2026)));
      await db.into(db.folders).insert(FoldersCompanion.insert(
          id: '[Gmail]/Черновики', accountId: 'a1', displayName: 'Черновики', type: Value(FolderType.drafts.index)));
      await db.into(db.folders).insert(FoldersCompanion.insert(
          id: 'INBOX', accountId: 'a1', displayName: 'Входящие', type: Value(FolderType.inbox.index)));
    });
    tearDown(() => db.close());

    Future<void> mail(String id, String folder, {String account = 'a1', int minute = 0}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: account,
              folderId: folder,
              fromEmail: 'me@example.com',
              toRecipients: '[]',
              subject: 'RE: Документы',
              receivedAt: DateTime(2026, 11, 3, 19, minute),
              bodyHtml: const Value('<p>Тест</p>'),
            ));

    test('черновики ящика: серверная папка и свои, без тел, новые первыми', () async {
      await mail('[Gmail]/Черновики:5', '[Gmail]/Черновики', minute: 35);
      await mail('local-1', 'drafts', minute: 40);
      await mail('INBOX:1', 'INBOX');
      await mail('b:1', 'drafts', account: 'b');
      final rows = await db.watchDraftsLight('a1').first;
      expect([for (final r in rows) r.id], ['local-1', '[Gmail]/Черновики:5']);
      expect(rows.every((r) => r.bodyHtml == null), isTrue);
    });
  });
}

// Письмо самому себе (1.8.12, замечание владельца 29.10.2026): копии в
// «Отправленных» и во «Входящих» с одним Message-ID. В списке беседа была
// «2», а экран беседы показывал одно письмо. Теперь копии — одно письмо и
// в счётчике; карточка — непрочитанная копия, с метками обеих папок.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';

Future<void> _mail(AppDatabase db, String id,
    {required String folder,
    String? folderName,
    String? mid,
    bool read = true,
    String conv = '<t@icloud.com>',
    int minute = 21}) {
  return db.into(db.emails).insert(EmailsCompanion.insert(
        id: id,
        accountId: 'a1',
        folderId: folder,
        folderName: Value(folderName ?? folder),
        fromEmail: 'me@icloud.com',
        toRecipients: '[{"email":"me@icloud.com"}]',
        subject: 'Тест',
        receivedAt: DateTime(2026, 10, 29, 21, minute),
        conversationId: Value(conv),
        internetMessageId: Value(mid),
        isRead: Value(read),
      ));
}

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 1, email: 'me@icloud.com', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
  });
  tearDown(() => db.close());

  test('копии одного письма — одно письмо в счётчике беседы', () async {
    await _mail(db, 'Sent Messages:7', folder: 'Sent Messages', mid: '<T@icloud.com>');
    await _mail(db, 'INBOX:42', folder: 'INBOX', mid: '<t@icloud.com> ', read: false);
    // Беседа из одного письма в сводку не входит: строка — обычное письмо.
    expect(await db.conversationStats({'<t@icloud.com>'}), isEmpty);
    expect(await db.conversationSizes({'<t@icloud.com>'}), isEmpty);

    // Ответ — уже беседа из двух писем, непрочитанное — одно.
    await _mail(db, 'INBOX:43', folder: 'INBOX', mid: '<r@icloud.com>', minute: 30);
    final stats = (await db.conversationStats({'<t@icloud.com>'}))['a1|<t@icloud.com>']!;
    expect(stats.count, 2);
    expect(stats.unread, 1);
    expect((await db.conversationSizes({'<t@icloud.com>'}))['a1|<t@icloud.com>'], 2);

    // Письма без Message-ID не склеиваются.
    await _mail(db, 'INBOX:44', folder: 'INBOX', minute: 31);
    await _mail(db, 'INBOX:45', folder: 'INBOX', minute: 32);
    expect((await db.conversationStats({'<t@icloud.com>'}))['a1|<t@icloud.com>']!.count, 4);
  });

  test('беседа: одна карточка — непрочитанная копия, остальные копии — отдельно', () async {
    await _mail(db, 'Sent Messages:7', folder: 'Sent Messages', mid: '<t@icloud.com>');
    await _mail(db, 'INBOX:42', folder: 'INBOX', mid: '<t@icloud.com>', read: false);
    final all = await db.watchConversationLight(conversationId: '<t@icloud.com>', accountId: 'a1', dedup: false).first;
    expect(all.length, 2);
    final copies = <String, List<Email>>{};
    final rows = AppDatabase.dedupCopies(all, copies: copies);
    expect(rows.single.id, 'INBOX:42');
    expect(copies['INBOX:42']!.single.folderId, 'Sent Messages');

    // Поток по умолчанию — уже без копий.
    final light = await db.watchConversationLight(conversationId: '<t@icloud.com>', accountId: 'a1').first;
    expect(light.single.id, 'INBOX:42');
  });

  test('Gmail: из копий — не служебная папка, даже прочитанная', () async {
    await _mail(db, 'all:1', folder: '[Gmail]/All Mail', mid: '<g@gmail.com>', read: false, conv: 'g');
    await _mail(db, 'in:1', folder: 'INBOX', mid: '<g@gmail.com>', conv: 'g');
    final copies = <String, List<Email>>{};
    final rows = AppDatabase.dedupCopies(
        await db.watchConversationLight(conversationId: 'g', accountId: 'a1', dedup: false).first,
        copies: copies);
    expect(rows.single.id, 'in:1');
    expect(AppDatabase.isGmailVirtualCopy(copies['in:1']!.single), isTrue);
  });
}

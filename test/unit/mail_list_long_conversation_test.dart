// «Вся почта» (15.11.2026): беседа из 41 письма занимала всё первое окно
// ленты (30 писем) — после сворачивания бесед оставалась одна строка без
// прокрутки, и остальные письма не догружались. Теперь окно расширяется само.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart' show FolderType;
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('41 письмо одной беседы сверху — в ленте и остальные письма', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final acc = AccountModel(
        id: 'a', type: AccountType.exchange, email: 'me@corp.ru', displayName: 'Я', username: 'me', createdAt: DateTime(2026));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a', type: AccountType.exchange.index, email: 'me@corp.ru', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(
        FoldersCompanion.insert(id: 'in', accountId: 'a', displayName: 'Входящие', type: Value(FolderType.inbox.index)));
    final base = DateTime(2026, 11, 15, 18);
    // 41 напоминание одной беседы — самые новые.
    for (var i = 0; i < 41; i++) {
      await db.into(db.emails).insert(EmailsCompanion.insert(
            id: 'r$i',
            accountId: 'a',
            folderId: 'in',
            fromEmail: 'klinov@corp.ru',
            toRecipients: '[]',
            subject: 'Re: Поручение: Гостиница',
            conversationId: const Value('conv-1'),
            receivedAt: base.subtract(Duration(seconds: i)),
          ));
    }
    // 25 других писем — раньше.
    for (var i = 0; i < 25; i++) {
      await db.into(db.emails).insert(EmailsCompanion.insert(
            id: 'o$i',
            accountId: 'a',
            folderId: 'in',
            fromEmail: 'p$i@corp.ru',
            toRecipients: '[]',
            subject: 'Письмо $i',
            conversationId: Value('c-$i'),
            receivedAt: base.subtract(Duration(hours: 1, minutes: i)),
          ));
    }
    final provider = StateNotifierProvider<EmailsNotifier, EmailListState>((ref) => EmailsNotifier(
          ref: ref,
          db: db,
          account: acc,
          accounts: [acc],
          folderId: null,
          isUnified: true,
          allAccountsMode: false,
          groupByConversation: true,
        ));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sub = c.listen(provider, (_, __) {});
    addTearDown(sub.close);
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await settle();
    // Окно расширилось само: не одна строка, а экран писем — и прокрутка.
    var rows = c.read(provider).emails;
    expect(rows.where((e) => e.conversationId == 'conv-1').length, 1);
    expect(rows.length, greaterThanOrEqualTo(15));
    expect(c.read(provider).hasMore, isTrue);
    // Прокрутка вниз — остальные письма.
    await c.read(provider.notifier).loadNextPage();
    await settle();
    rows = c.read(provider).emails;
    expect(rows.length, 26);
  });
}

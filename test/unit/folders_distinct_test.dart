// Папки после синхронизации (план 08.11.2026 п. 3): строка папки меняется
// записывается заново, а видимое в меню не меняется — поток не повторяется.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';

void main() {
  test('та же папка после синхронизации — без нового списка; переименование — новый', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@example.com', displayName: 'me', username: 'me', createdAt: DateTime(2026, 1, 1)));
    await db.into(db.folders).insert(FoldersCompanion.insert(id: 'INBOX', accountId: 'a1', displayName: 'Входящие'));
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    var emits = 0;
    final sub = c.listen(accountFoldersProvider('a1'), (_, next) {
      if (next.hasValue) emits++;
    }, fireImmediately: true);
    addTearDown(sub.close);
    await c.read(accountFoldersProvider('a1').future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final base = emits;

    await (db.update(db.folders)..where((f) => f.id.equals('INBOX')))
        .write(const FoldersCompanion(unreadCount: Value(0)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emits, base, reason: 'запись тех же значений после синхронизации — меню не перестраивается');

    await (db.update(db.folders)..where((f) => f.id.equals('INBOX')))
        .write(const FoldersCompanion(displayName: Value('Входящие (рабочие)')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emits, base + 1);
  });
}

// Первая синхронизация нового ящика (1.9.x, журнал владельца 31.10.2026):
// Outlook после входа через браузер — «Ещё не обновлялось», письма только по
// «обновить». Её ждали от проверки при возврате в приложение, а приложение
// возвращается раньше, чем ящик записан. Теперь — сразу при добавлении.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/sync/sync_service.dart';

class _FakeSync extends SyncService {
  _FakeSync(super.ref);
  final started = <String>[];

  @override
  Future<void> syncNewAccount(AccountModel account) async => started.add(account.id);
}

void main() {
  test('добавленный ящик сразу синхронизируется', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    late _FakeSync sync;
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      syncServiceProvider.overrideWith((ref) => sync = _FakeSync(ref)),
    ]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    c.read(syncServiceProvider);
    await c.read(accountsProvider.notifier).reload();
    await c.read(accountsProvider.notifier).addAccount(AccountModel(
          id: 'o1',
          type: AccountType.imap,
          email: 'user@outlook.com',
          displayName: 'User',
          username: 'user@outlook.com',
          createdAt: DateTime(2026, 10, 31),
        ));
    await Future<void>.delayed(Duration.zero);
    expect(sync.started, ['o1']);
  });
}

// Правила организации (MDM `allowed_domains`, план 08.11.2026 п. 1):
// действуют и на уже добавленные ящики, не только при добавлении. Ящик
// чужого домена скрыт и не синхронизируется; данные остаются и вернутся,
// когда домен разрешат.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/security/managed_config.dart';

Future<void> _account(AppDatabase db, String id, String email) => db.into(db.accounts).insert(AccountsCompanion.insert(
      id: id,
      type: AccountType.imap.index,
      email: email,
      displayName: email,
      username: email,
      createdAt: DateTime(2026, 11, 1),
    ));

void main() {
  tearDown(() => ManagedPolicy.current = ManagedPolicy.none);

  test('ящик чужого домена скрыт, вернётся после снятия правила', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await _account(db, 'w', 'i.petrov@romashka.ru');
    await _account(db, 'p', 'ivan@gmail.com');
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });

    ManagedPolicy.current = ManagedPolicy.fromMap(const {'allowed_domains': 'romashka.ru'});
    await c.read(accountsProvider.notifier).reload();
    expect(c.read(accountsProvider).map((a) => a.id), ['w']);
    expect(hiddenByPolicyAccounts, ['ivan@gmail.com']);

    // Организация сняла ограничение — список перечитывается сам.
    ManagedPolicy.current = ManagedPolicy.none;
    ManagedPolicy.allowedDomainsChanged.value++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(accountsProvider).map((a) => a.id).toSet(), {'w', 'p'});
    expect(hiddenByPolicyAccounts, isEmpty);
    // Данные не удалялись.
    expect((await db.select(db.accounts).get()).length, 2);
  });
}

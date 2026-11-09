// После синхронизации список ящиков не пересобирается, если число
// непрочитанных и фото не изменились (план 08.11.2026 п. 3: всё, что
// зависит от ящиков, перестраивалось на каждую синхронизацию).

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('то же число непрочитанных и то же фото — список не меняется', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@corp.ru', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    final n = AccountsNotifier(db, SecureStorageService());
    await n.loaded;
    var changes = 0;
    n.addListener((_) => changes++, fireImmediately: false);

    await n.updateUnreadCount('a1', 5);
    expect(changes, 1);
    await n.updateUnreadCount('a1', 5);
    await n.updateUnreadCount('a1', 5);
    expect(changes, 1, reason: 'число то же — без пересборки');
    await n.updateUnreadCount('a1', 6);
    expect(changes, 2);

    await n.setAccountPhoto('a1', 'https://example.com/p.png');
    await n.setAccountPhoto('a1', 'https://example.com/p.png');
    expect(changes, 3);
    n.dispose();
  });
}

// После синхронизации список ящиков не пересобирается: число непрочитанных
// пишется только в базу, фото — только если изменилось (план 08.11.2026
// п. 3; 2.7.1 — микрофризы 24.11.2026: всё, что зависит от ящиков,
// перестраивалось на каждую синхронизацию).

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

    // 2.7.1: число непрочитанных — только в базу, список ящиков не
    // пересобирается вовсе (за ним следят десятки экранов — микрофризы).
    await n.updateUnreadCount('a1', 5);
    await n.updateUnreadCount('a1', 5);
    await n.updateUnreadCount('a1', 6);
    expect(changes, 0, reason: 'непрочитанные — не повод пересобирать список ящиков');
    final row = await (db.select(db.accounts)..where((a) => a.id.equals('a1'))).getSingle();
    expect(row.unreadCount, 6);

    await n.setAccountPhoto('a1', 'https://example.com/p.png');
    await n.setAccountPhoto('a1', 'https://example.com/p.png');
    expect(changes, 1);
    n.dispose();
  });
}

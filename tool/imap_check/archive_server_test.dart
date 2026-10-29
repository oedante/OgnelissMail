// Архивация старых писем прямо с сервера IMAP — на настоящем сервере
// (Dovecot и т. п.). Обычный `flutter test` (папка test/) эту проверку не
// запускает: нужен сервер с ящиком, где лежат письма старше полугода.
//
//   OGN_IMAP=127.0.0.1:1143:tester:secret123 flutter test tool/imap_check
//
// Ящик: INBOX (2 старых + 1 свежее), Work/2019 (1 старое), Sent (1 старое),
// Trash. После проверки старые письма лежат в Trash.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/archive/archive_container.dart';
import 'package:ogneliss/services/archive/archive_db.dart';
import 'package:ogneliss/services/archive/archive_runner.dart';
import 'package:ogneliss/services/archive/archive_vault.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault extends ArchiveVault {
  _Vault(this._fake);
  final ArchiveDb _fake;

  @override
  ArchiveDb? get db => _fake;

  @override
  Future<ArchiveVaultState> build() async => ArchiveVaultState(ArchiveStatus.open,
      header: ArchiveHeader(id: 't', name: '', created: DateTime(2026), app: 'test', keys: const {}));
}

void main() {
  final cfg = Platform.environment['OGN_IMAP']?.split(':');
  TestWidgetsFlutterBinding.ensureInitialized();
  test('старые письма — с сервера в архив, на сервере — в корзину', () async {
    final (host, port, user, pass) = (cfg![0], int.parse(cfg[1]), cfg[2], cfg[3]);
    FlutterSecureStorage.setMockInitialValues({'pwd_a1': pass});
    SharedPreferences.setMockInitialValues({'ogna_set_app': false});
    final prefs = await SharedPreferences.getInstance();
    final app = AppDatabase.forTesting(NativeDatabase.memory());
    final adb = ArchiveDb(NativeDatabase.memory());
    await app.into(app.accounts).insert(AccountsCompanion.insert(
          id: 'a1',
          type: AccountType.imap.index,
          email: '$user@corp.example',
          displayName: 'Тест',
          username: user,
          imapServer: Value(host),
          imapPort: Value(port),
          imapEncryption: Value(EncryptionType.none.index),
          createdAt: DateTime(2026),
        ));
    Future<void> folder(String id, String name, FolderType t, {String? parent}) =>
        app.into(app.folders).insert(FoldersCompanion.insert(
            id: id, accountId: 'a1', displayName: name, type: Value(t.index), parentId: Value(parent)));
    await folder('INBOX', 'Входящие', FolderType.inbox);
    await folder('Work', 'Work', FolderType.custom);
    await folder('Work/2019', '2019', FolderType.custom, parent: 'Work');
    await folder('Sent', 'Отправленные', FolderType.sent);
    await folder('Trash', 'Удалённые', FolderType.trash);
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(app),
      sharedPrefsProvider.overrideWithValue(prefs),
      archiveVaultProvider.overrideWith(() => _Vault(adb)),
    ]);
    addTearDown(() async {
      c.dispose();
      await adb.close();
      await app.close();
    });
    await c.read(archiveVaultProvider.future);
    await c.read(accountsProvider.notifier).loaded;

    final r = await c.read(archiveRunnerProvider.notifier).run(months: 6);
    expect(r.errorKey, isNull);
    expect(r.mails, 4);
    expect(r.deleted, 4);
    expect(r.failed, 0);
    final paths = [for (final f in await adb.folders()) f.path];
    expect(paths, containsAll(['Входящие', 'Work', 'Work/2019', 'Отправленные']));
    final subjects = [for (final h in await adb.search('Body')) h.subject]..sort();
    expect(subjects, ['Old inbox 1', 'Old inbox 2', 'Old sent', 'Old work']);

    // На сервере старых писем больше нет (они в корзине), свежее — на месте.
    final account = c.read(accountsProvider).single;
    final imap = c.read(imapServiceProvider);
    expect(await imap.uidsBefore(account, folderId: 'INBOX', before: DateTime(2030)), hasLength(1));
    expect(await imap.uidsBefore(account, folderId: 'Work/2019', before: DateTime(2030)), isEmpty);
    expect(await imap.uidsBefore(account, folderId: 'Trash', before: DateTime(2030)), hasLength(4));

    // Повторная архивация: ничего нового и ничего лишнего.
    final again = await c.read(archiveRunnerProvider.notifier).run(months: 6);
    expect(again.mails, 0);
    expect(again.failed, 0);
  }, skip: cfg == null || cfg.length < 4 ? 'нет OGN_IMAP=host:port:user:password' : null);
}

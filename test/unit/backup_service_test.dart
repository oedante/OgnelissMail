// test/unit/backup_service_test.dart
// Резервная копия: файл открывается только верным паролем, служебные ключи
// (DeviceId Exchange, токены синхронизации) не переносятся, ящик без
// пароля в копии просит войти, подписи и заметки с телефона возвращаются.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/services/backup/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ogneliss_backup_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('копия: пароль, состав, восстановление на «новом телефоне»', () async {
    final db1 = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/a.db')));
    await db1.into(db1.accounts).insert(AccountsCompanion.insert(
          id: 'a1',
          type: 7,
          email: 'me@example.com',
          displayName: 'Я',
          username: 'me@example.com',
          createdAt: DateTime(2026, 1, 1),
          sortOrder: const Value(3),
        ));
    await db1.into(db1.signatures).insert(SignaturesCompanion.insert(
          id: 's1', name: 'Работа', htmlContent: '<p>С уважением</p>', plainContent: 'С уважением'));
    await db1.into(db1.notes).insert(NotesCompanion.insert(
          id: 'n1', title: const Value('Список'), createdAt: DateTime(2026, 2, 1), modifiedAt: DateTime(2026, 2, 1)));
    await db1.into(db1.notes).insert(NotesCompanion.insert(
          id: 'n2', serverId: const Value('srv'), createdAt: DateTime(2026, 2, 1), modifiedAt: DateTime(2026, 2, 1)));

    SharedPreferences.setMockInitialValues({
      's_locale': 'ru',
      's_mail_control': true,
      'eas_device_id_a1': 'DEVICE',
      'synctok_mail_a1_INBOX': 'tok',
      'focus_vips': <String>['boss@example.com'],
    });
    var prefs = await SharedPreferences.getInstance();

    final bytes = await BackupService.create(
      db: db1,
      prefs: prefs,
      secure: SecureStorageService(),
      passphrase: 'correct horse',
      includeSecrets: false,
      appVersion: '1.5.0',
    );
    await db1.close();

    // Неверный пароль — понятная ошибка, а не падение.
    await expectLater(
      BackupService.open(bytes, 'wrong pass'),
      throwsA(isA<BackupException>().having((e) => e.key, 'key', 'backupErrPassword')),
    );
    // Не файл копии.
    await expectLater(
      BackupService.open(Uint8List.fromList('hello'.codeUnits), 'x'),
      throwsA(isA<BackupException>().having((e) => e.key, 'key', 'backupErrFormat')),
    );

    final payload = await BackupService.open(bytes, 'correct horse');

    // «Новый телефон»: пустая база и настройки.
    final db2 = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/b.db')));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final report = await BackupService.restore(
      payload: payload,
      db: db2,
      prefs: prefs,
      secure: SecureStorageService(),
    );

    expect(report.accountsAdded, 1);
    expect(report.accountsSkipped, 0);
    expect(report.signatures, 1);
    expect(report.notes, 1); // только заметка без serverId
    expect(report.withSecrets, isFalse);

    final acc = await (db2.select(db2.accounts)..where((a) => a.id.equals('a1'))).getSingle();
    expect(acc.email, 'me@example.com');
    expect(acc.sortOrder, 3);
    expect(acc.authFailedAt, isNotNull); // без пароля — попросит войти

    expect(prefs.getString('s_locale'), 'ru');
    expect(prefs.getBool('s_mail_control'), isTrue);
    expect(prefs.getStringList('focus_vips'), ['boss@example.com']);
    expect(prefs.containsKey('eas_device_id_a1'), isFalse);
    expect(prefs.containsKey('synctok_mail_a1_INBOX'), isFalse);

    // Повторное восстановление: ящик уже есть — не дублируется.
    final again = await BackupService.restore(
      payload: payload,
      db: db2,
      prefs: prefs,
      secure: SecureStorageService(),
    );
    expect(again.accountsAdded, 0);
    expect(again.accountsSkipped, 1);
    expect(again.notes, 0);
    await db2.close();
  });
}

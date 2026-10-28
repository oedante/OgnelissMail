// test/unit/database_test.dart
// Локальная база: миграции, аренда синхронизации между изолятами, поиск.
// База — во временном файле (NativeDatabase), как на устройстве, но без
// шифрования.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';

Future<void> _addAccount(AppDatabase db, String id) => db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: id,
        type: 7,
        email: '$id@example.com',
        displayName: id,
        username: id,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final r in rows) r.data['name'] as String};
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ogneliss_db_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('Новая база: все таблицы, поисковый индекс и текущая версия', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/new.db')));
    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
        .map((r) => r.data['name'] as String)
        .toSet();
    for (final t in ['accounts', 'emails', 'folders', 'calendar_events', 'tasks', 'contacts', 'notes',
        'sync_queue', 'emails_fts', 'sync_lease']) {
      expect(tables, contains(t), reason: t);
    }
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, db.schemaVersion);
    await db.close();
  });

  test('Обновление 19 → 20: у задач появляется напоминание, данные сохраняются', () async {
    final file = File('${dir.path}/v19.db');
    // База текущей схемы, приведённая к версии 19: без столбца reminder_at.
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await _addAccount(db, 'a1');
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't1',
          accountId: 'a1',
          title: 'Отчёт',
          createdAt: DateTime(2026, 10, 1),
        ));
    await db.customStatement('ALTER TABLE tasks DROP COLUMN reminder_at');
    await db.customStatement('PRAGMA user_version = 19');
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    expect(await _columns(db, 'tasks'), contains('reminder_at'));
    final t = await (db.select(db.tasks)..where((x) => x.id.equals('t1'))).getSingle();
    expect(t.title, 'Отчёт');
    expect(t.reminderAt, isNull);
    await db.close();
  });

  test('Обновление 22 → 23: «Напомнить» становится «Позже» с датой', () async {
    final file = File('${dir.path}/v22.db');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await _addAccount(db, 'a1');
    Future<void> mail(String id, DateTime? remind) => db.into(db.emails).insert(EmailsCompanion.insert(
          id: id,
          accountId: 'a1',
          folderId: 'INBOX',
          fromEmail: 'boss@example.com',
          toRecipients: '[]',
          subject: id,
          receivedAt: DateTime(2026, 10, 1),
          remindAt: Value(remind),
        ));
    await mail('m1', DateTime(2026, 10, 10, 9));
    await mail('m2', null);
    await db.customStatement('DROP INDEX IF EXISTS idx_emails_later');
    await db.customStatement('ALTER TABLE emails DROP COLUMN later_state');
    await db.customStatement('PRAGMA user_version = 22');
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    expect(await _columns(db, 'emails'), contains('later_state'));
    final later = await db.laterEmails();
    expect(later.map((e) => e.id), ['m1']);
    expect(later.single.laterState, 1);
    // Срок наступил — письмо в списке наступивших.
    expect((await db.dueLaterEmails(DateTime(2026, 10, 10, 10))).single.id, 'm1');
    expect(await db.dueLaterEmails(DateTime(2026, 10, 10, 8)), isEmpty);
    await db.close();
  });

  test('Обновление 23 → 24: столбец заголовка рассылки, письма сохраняются', () async {
    final file = File('${dir.path}/v23.db');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await _addAccount(db, 'a1');
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'n1',
          accountId: 'a1',
          folderId: 'INBOX',
          fromEmail: 'news@shop.example',
          toRecipients: '[]',
          subject: 'Акции недели',
          receivedAt: DateTime(2026, 10, 1),
        ));
    await db.customStatement('ALTER TABLE emails DROP COLUMN list_unsubscribe');
    await db.customStatement('PRAGMA user_version = 23');
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    expect(await _columns(db, 'emails'), contains('list_unsubscribe'));
    final row = await (db.select(db.emails)..where((e) => e.id.equals('n1'))).getSingle();
    expect(row.subject, 'Акции недели');
    expect(row.listUnsubscribe, isNull);
    await (db.update(db.emails)..where((e) => e.id.equals('n1')))
        .write(const EmailsCompanion(listUnsubscribe: Value('{"u":"<https://shop.example/u>"}')));
    expect((await (db.select(db.emails)..where((e) => e.id.equals('n1'))).getSingle()).listUnsubscribe,
        contains('shop.example'));
    await db.close();
  });

  test('«Позже»: порядок — вернувшиеся, по сроку, без даты в конце', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/later.db')));
    await _addAccount(db, 'a1');
    Future<void> mail(String id) => db.into(db.emails).insert(EmailsCompanion.insert(
          id: id, accountId: 'a1', folderId: 'INBOX', fromEmail: 'x@example.com',
          toRecipients: '[]', subject: id, receivedAt: DateTime(2026, 10, 1)));
    for (final id in ['late', 'nodate', 'soon', 'back', 'none']) {
      await mail(id);
    }
    await db.setLaterState('late', 'a1', 1, remindAt: DateTime(2026, 10, 20, 9));
    await db.setLaterState('nodate', 'a1', 1);
    await db.setLaterState('soon', 'a1', 1, remindAt: DateTime(2026, 10, 10, 9));
    await db.setLaterState('back', 'a1', 2);
    expect((await db.laterEmails()).map((e) => e.id), ['back', 'soon', 'late', 'nodate']);
    await db.close();
  });

  test('Шаги миграции идемпотентны: повтор с 5-й версии на актуальной схеме', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/idem.db')));
    await _addAccount(db, 'a1');
    await db.into(db.contacts).insert(ContactsCompanion.insert(
          id: 'c1',
          accountId: const Value('a1'),
          email: 'ivan@example.com',
          displayName: 'Иван',
        ));
    // Все шаги onUpgrade поверх уже обновлённой базы — не должны падать
    // («столбец уже есть», перенос таблиц) и терять данные.
    // Как при настоящем обновлении: миграция идёт до beforeOpen, внешние
    // ключи выключены (перенос таблицы accounts пересоздаёт её).
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.migration.onUpgrade(db.createMigrator(), 5, db.schemaVersion);
    expect((await db.select(db.accounts).get()).single.id, 'a1');
    expect((await db.select(db.contacts).get()).single.email, 'ivan@example.com');
    await db.close();
  });

  test('Аренда синхронизации: второй владелец ждёт, после срока или освобождения — получает', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/lease.db')));
    await db.customSelect('SELECT 1').get(); // открыть базу (beforeOpen создаёт sync_lease)
    expect(await db.tryAcquireSyncLease('a1', 'ui', const Duration(minutes: 3)), isTrue);
    expect(await db.tryAcquireSyncLease('a1', 'bg', const Duration(minutes: 3)), isFalse);
    // Продление своим владельцем.
    expect(await db.tryAcquireSyncLease('a1', 'ui', const Duration(minutes: 3)), isTrue);
    // Другой аккаунт — независимо.
    expect(await db.tryAcquireSyncLease('a2', 'bg', const Duration(minutes: 3)), isTrue);
    await db.releaseSyncLease('a1', 'ui');
    expect(await db.tryAcquireSyncLease('a1', 'bg', const Duration(milliseconds: 1)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Аренда «bg» истекла — процесс, видимо, убит; «ui» может взять.
    expect(await db.tryAcquireSyncLease('a1', 'ui', const Duration(minutes: 3)), isTrue);
    await db.close();
  });

  test('Аренда прежнего процесса забирается сразу, своего процесса — нет (1.6.4)', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/lease2.db')));
    await db.customSelect('SELECT 1').get();
    // Прежний процесс (pid 100) взял аренду и был убит.
    expect(await db.tryAcquireSyncLease('a1', 'p100:iso_old', const Duration(minutes: 3)), isTrue);
    // Новый процесс (pid 200) — забирает, не дожидаясь срока.
    expect(await db.tryAcquireSyncLease('a1', 'p200:iso_ui', const Duration(minutes: 3)), isTrue);
    // Другой изолят того же процесса (фоновая задача) — ждёт.
    expect(await db.tryAcquireSyncLease('a1', 'p200:iso_bg', const Duration(minutes: 3)), isFalse);
    // Аренда старого формата (до 1.6.4) — тоже от прежнего процесса.
    expect(await db.tryAcquireSyncLease('a2', 'iso_legacy', const Duration(minutes: 3)), isTrue);
    expect(await db.tryAcquireSyncLease('a2', 'p200:iso_ui', const Duration(minutes: 3)), isTrue);
    await db.close();
  });

  test('Аренда: этап синхронизации виден другому изоляту (1.6.12)', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/lease3.db')));
    await db.customSelect('SELECT 1').get();
    expect(await db.tryAcquireSyncLease('a1', 'p1:bg', const Duration(minutes: 3)), isTrue);
    await db.setSyncLeaseStage('a1', 'p1:bg', 'фон: папка Входящие');
    // Чужой владелец этап не меняет.
    await db.setSyncLeaseStage('a1', 'p1:ui', 'приложение: подключение');
    final info = await db.syncLeaseInfo('a1');
    expect(info?.owner, 'p1:bg');
    expect(info?.stage, 'фон: папка Входящие');
    expect(info?.stageAt, isNotNull);
    await db.releaseSyncLease('a1', 'p1:bg');
    expect(await db.syncLeaseInfo('a1'), isNull);
    await db.close();
  });

  test('Поиск: кириллица без учёта регистра, только свой аккаунт', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/fts.db')));
    await _addAccount(db, 'a1');
    await _addAccount(db, 'a2');
    Future<void> mail(String acc, String id, String subject) async {
      await db.into(db.emails).insert(EmailsCompanion.insert(
            id: id,
            accountId: acc,
            folderId: 'INBOX',
            fromEmail: 'boss@example.com',
            toRecipients: '[]',
            subject: subject,
            receivedAt: DateTime(2026, 10, 1),
          ));
      await db.indexEmailFts(emailId: id, accountId: acc, subject: subject, fromText: 'boss@example.com', body: '');
    }

    await mail('a1', 'm1', 'Отчёт за квартал');
    await mail('a1', 'm2', 'Обед');
    await mail('a2', 'm3', 'Отчёт другого ящика');
    final hits = await db.searchEmailsFts(accountId: 'a1', query: 'отчёт');
    expect(hits.map((e) => e.id), ['m1']);
    // Префикс слова.
    expect((await db.searchEmailsFts(accountId: 'a1', query: 'кварт')).single.id, 'm1');
    // Запасной поиск LIKE (без индекса) тоже не зависит от регистра.
    expect((await db.searchEmails(accountId: 'a1', query: 'отчёт')).single.id, 'm1');
    await db.close();
  });

  test('Очистка выключенных папок: порциями, только с телефона, черновики и правки остаются (1.5.10)', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/drop.db')));
    await _addAccount(db, 'a1');
    Future<void> mail(String id, String folder, {bool draft = false, bool modified = false}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
            id: id, accountId: 'a1', folderId: folder, fromEmail: 'x@example.com',
            toRecipients: '[]', subject: id, receivedAt: DateTime(2026, 10, 1),
            isDraft: Value(draft), isLocallyModified: Value(modified)));
    for (var i = 0; i < 12; i++) {
      await mail('arc$i', 'ARCHIVE');
    }
    await mail('keep-draft', 'ARCHIVE', draft: true);
    await mail('keep-edit', 'ARCHIVE', modified: true);
    await mail('inbox', 'INBOX');
    expect(await db.countLocalFolderEmails('a1', ['ARCHIVE']), 12);
    final progress = <int>[];
    final n = await db.deleteLocalFolderEmails('a1', ['ARCHIVE'], batch: 5, onProgress: progress.add);
    expect(n, 12);
    expect(progress, [5, 10, 12]);
    final left = (await db.select(db.emails).get()).map((e) => e.id).toSet();
    expect(left, {'keep-draft', 'keep-edit', 'inbox'});
    await db.close();
  });
}

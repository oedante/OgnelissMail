// Тексты писем — в конце строки таблицы (аудит 11.10.2026): разбор CREATE
// TABLE и перестановка столбцов без потери данных и индексов.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';

void main() {
  test('определения столбцов делятся только по запятым верхнего уровня', () {
    final parts = AppDatabase.splitColumnDefs(
        '"a" TEXT DEFAULT \'x,y\', "b" INTEGER CHECK ("b" IN (0, 1)), PRIMARY KEY ("a", "b")');
    expect(parts, hasLength(3));
    expect(AppDatabase.columnNameOf(parts[0]), 'a');
    expect(AppDatabase.columnNameOf(parts[1]), 'b');
    expect(AppDatabase.columnNameOf(parts[2]), isNull);
  });

  test('тексты переносятся в конец, ограничения — последними', () {
    final sql = AppDatabase.reorderedCreateSql(
        'CREATE TABLE "emails" ("id" TEXT NOT NULL, "body_plain" TEXT NULL, "body_html" TEXT NULL, '
        '"is_read" INTEGER NOT NULL DEFAULT 0 CHECK ("is_read" IN (0, 1)), PRIMARY KEY ("id"))',
        'emails_reorder')!;
    expect(sql.indexOf('"is_read"'), lessThan(sql.indexOf('"body_plain"')));
    expect(sql.indexOf('"body_html"'), lessThan(sql.indexOf('PRIMARY KEY')));
  });

  test('перестановка в настоящей базе: данные и индексы на месте', () async {
    final dir = await Directory.systemTemp.createTemp('ogneliss_bodies_test');
    final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/b.db')));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'me@x', displayName: 'a1', username: 'a1', createdAt: DateTime(2026)));
    for (var i = 0; i < 20; i++) {
      await db.into(db.emails).insert(EmailsCompanion.insert(
            id: 'm$i',
            accountId: 'a1',
            folderId: 'INBOX',
            fromEmail: 'p@x',
            toRecipients: '[]',
            subject: 'S$i',
            receivedAt: DateTime(2026, 10, 1 + i % 10),
            bodyHtml: Value('<p>${'x' * (i * 500)}</p>'),
            bodyPlain: Value('t$i'),
            isRead: Value(i.isEven),
          ));
    }
    if (!await db.bodiesAtEnd()) {
      expect(await db.moveBodiesToEnd(), isTrue);
    }
    expect(await db.bodiesAtEnd(), isTrue);
    expect(await db.moveBodiesToEnd(), isFalse); // второй раз — ничего
    final rows = await (db.select(db.emails)..orderBy([(e) => OrderingTerm(expression: e.id)])).get();
    expect(rows, hasLength(20));
    final m5 = rows.firstWhere((r) => r.id == 'm5');
    expect(m5.bodyPlain, 't5');
    expect(m5.bodyHtml!.length, 2500 + 7);
    expect(m5.isRead, isFalse);
    final idx = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'emails'").get();
    expect(idx.map((r) => r.data['name']), contains('idx_emails_account_folder_date'));
    await db.close();
    await dir.delete(recursive: true);
  });
}

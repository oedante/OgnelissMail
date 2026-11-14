// Результаты поиска — в выбранной сортировке (14.11.2026, замечание
// владельца: при «Сначала новые» найденное шло вперемешку по датам — по
// релевантности, по ящикам, найденное на сервере в конце).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';

EmailModel _m(String id, DateTime at, {String from = 'Зеленина Оксана', String subject = 'Отчёт', int size = 10}) =>
    EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'INBOX',
      from: EmailAddress(email: '${from.hashCode}@corp.example', displayName: from),
      to: const [],
      subject: subject,
      receivedAt: at,
      size: size,
    );

void main() {
  group('порядок найденного', () {
    final a = _m('1', DateTime(2026, 10, 16), from: 'Яковлев', subject: 'Б', size: 30);
    final b = _m('2', DateTime(2026, 11, 13, 9), from: 'Абрамов', subject: 'В', size: 10);
    final c = _m('3', DateTime(2026, 10, 20), from: 'Зеленина', subject: 'А', size: 20);
    final d = _m('4', DateTime(2026, 11, 13, 9), from: 'Зеленина', subject: 'А', size: 20);
    List<String> by(MailSort s) => ([a, b, c, d]..sort((x, y) => EmailsNotifier.compareForSort(s, x, y))).map((e) => e.id).toList();

    test('по дате: новые и старые; одна дата — порядок стабилен', () {
      expect(by(MailSort.dateNewest), ['4', '2', '3', '1']);
      expect(by(MailSort.dateOldest), ['1', '3', '2', '4']);
    });

    test('по отправителю, теме, размеру — внутри одинаковых по дате', () {
      expect(by(MailSort.senderAZ), ['2', '4', '3', '1']);
      expect(by(MailSort.subjectAZ), ['4', '3', '1', '2']);
      expect(by(MailSort.sizeLargest), ['1', '4', '3', '2']);
      expect(by(MailSort.sizeSmallest), ['2', '4', '3', '1']);
    });
  });

  group('поиск на устройстве', () {
    late Directory dir;
    late AppDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('search_sort');
      db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/t.db')));
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'a1@example.com', displayName: 'a1', username: 'a1', createdAt: DateTime(2026)));
      // Пять писем одного человека в случайном порядке дат.
      for (final (id, day) in [('m1', 16), ('m2', 2), ('m3', 28), ('m4', 9), ('m5', 21)]) {
        await db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a1',
              folderId: 'INBOX',
              fromEmail: 'zelenina@corp.example',
              toRecipients: '[]',
              subject: 'Зеленина: отчёт $id',
              receivedAt: DateTime(2026, 10, day),
            ));
        await db.indexEmailFts(
            emailId: id, accountId: 'a1', subject: 'Зеленина: отчёт $id', fromText: 'zelenina@corp.example', body: '');
      }
    });

    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<List<String>> find({bool? oldest, int limit = 3}) async => [
          for (final e in await db.searchEmailsFts(accountId: 'a1', query: 'зеленина', limit: limit, oldestFirst: oldest)) e.id,
        ];

    test('«Сначала новые» — самые новые совпадения, а не самые релевантные', () async {
      expect(await find(oldest: false), ['m3', 'm5', 'm1']);
      expect(await find(oldest: true), ['m2', 'm4', 'm1']);
      expect(await find(limit: 10), hasLength(5), reason: 'по релевантности — как раньше');
    });

    test('без индекса (запасной поиск LIKE) — тот же порядок', () async {
      await db.customStatement('DELETE FROM emails_fts');
      expect(await find(oldest: false), ['m3', 'm5', 'm1']);
      expect(await find(oldest: true), ['m2', 'm4', 'm1']);
    });
  });
}

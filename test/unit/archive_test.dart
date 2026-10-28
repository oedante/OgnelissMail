// 1.7.3: архив Ogneliss (.ogna) — ключ архива в конвертах паролем и кодом
// восстановления, файл копии, база архива (папки с путём, письма с
// вложениями, поиск, настройки приложения) и правило «какое письмо
// архивировать».

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/archive/archive_container.dart';
import 'package:ogneliss/services/archive/archive_crypto.dart';
import 'package:ogneliss/services/archive/archive_db.dart';
import 'package:ogneliss/services/archive/archive_runner.dart';
import 'package:ogneliss/services/archive/archive_settings.dart';

void main() {
  group('ключ архива', () {
    test('конверт паролем и кодом: верный открывает, неверный — нет', () async {
      final key = ArchiveCrypto.newArchiveKey();
      final env = await ArchiveCrypto.wrap(key, 'пароль-архива', iterations: 1000);
      expect(await ArchiveCrypto.unwrap(env, 'пароль-архива'), key);
      expect(await ArchiveCrypto.unwrap(env, 'не тот'), isNull);
      // Конверт — JSON (лежит в заголовке файла).
      final back = jsonDecode(jsonEncode(env)) as Map<String, dynamic>;
      expect(await ArchiveCrypto.unwrap(back, 'пароль-архива'), key);
    });

    test('код восстановления: 24 знака, ввод без дефисов и строчными', () {
      final code = ArchiveCrypto.newRecoveryCode();
      expect(code.length, 29); // 24 знака и 5 дефисов
      expect(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){5}$').hasMatch(code), isTrue);
      final typed = code.toLowerCase().replaceAll('-', ' ');
      expect(ArchiveCrypto.normalizeCode(typed), code.replaceAll('-', ''));
      expect(ArchiveCrypto.looksLikeCode(typed), isTrue);
      expect(ArchiveCrypto.looksLikeCode('короткий пароль'), isFalse);
    });
  });

  group('файл .ogna', () {
    ArchiveHeader header() => ArchiveHeader(
          id: 'abc123',
          name: 'Архив',
          created: DateTime(2026, 10, 25),
          app: '1.7.3',
          keys: const {
            'password': {'salt': 's', 'iter': 1, 'iv': 'i', 'ct': 'c'},
          },
        );

    test('заголовок: запись и разбор', () {
      final bytes = ArchiveContainer.prefix(header());
      final r = ArchiveContainer.parsePrefix(Uint8List.fromList([...bytes, 1, 2, 3]));
      expect(r.header.id, 'abc123');
      expect(r.header.name, 'Архив');
      expect(r.header.keys['password']?['iter'], 1);
      expect(r.dataOffset, bytes.length);
    });

    test('чужой файл и новая версия формата', () {
      expect(() => ArchiveContainer.parsePrefix(Uint8List.fromList(utf8.encode('SQLite format 3\u0000'))),
          throwsA(isA<ArchiveFormatException>().having((e) => e.key, 'key', 'archiveNotOgna')));
      final b = ArchiveContainer.prefix(header());
      b[4] = 99;
      expect(() => ArchiveContainer.parsePrefix(b),
          throwsA(isA<ArchiveFormatException>().having((e) => e.key, 'key', 'archiveNewerFormat')));
    });

    test('копия: база внутри файла без изменений', () async {
      final dir = await Directory.systemTemp.createTemp('ogna');
      try {
        final db = File('${dir.path}/a.db')..writeAsBytesSync(List<int>.generate(70000, (i) => i % 251));
        final out = File('${dir.path}/copy.ogna');
        await ArchiveContainer.write(out, header(), db);
        final h = await ArchiveContainer.readHeader(out);
        expect(h.header.id, 'abc123');
        final back = File('${dir.path}/b.db');
        await ArchiveContainer.extractDb(out, h.dataOffset, back);
        expect(back.readAsBytesSync(), db.readAsBytesSync());
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('база архива', () {
    late ArchiveDb db;
    setUp(() => db = ArchiveDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    ArchiveMessageInput mail(String id, List<({String name, String type})> chain,
            {String subject = 'Отчёт за квартал', String body = 'Смета по ремонту насоса', String? mid}) =>
        ArchiveMessageInput(
          accountId: 'a1',
          folderChain: chain,
          sourceId: id,
          messageId: mid,
          subject: subject,
          fromName: 'Иван Петров',
          fromEmail: 'ivan@corp.ru',
          to: const [(name: 'Олег', email: 'oleg@corp.ru')],
          date: DateTime(2025, 3, 1),
          bodyHtml: '<p>$body</p>',
          searchText: body,
          attachments: [
            ArchiveAttachmentInput(name: 'смета.xlsx', mime: 'application/vnd.ms-excel', bytes: Uint8List.fromList([1, 2, 3])),
            ArchiveAttachmentInput(
                name: 'image001.png', mime: 'image/png', bytes: Uint8List.fromList([9]), contentId: 'img1', isInline: true),
          ],
        );

    test('структура папок сохраняется, повтор не дублируется', () async {
      const chain = [(name: 'Входящие', type: 'inbox'), (name: 'Проекты', type: 'custom'), (name: '2025', type: 'custom')];
      final id = await db.addMessage(mail('m1', chain, mid: '<a@corp>'));
      // То же письмо ещё раз (повторная архивация) — тот же id.
      expect(await db.addMessage(mail('m1', chain, mid: '<a@corp>')), id);
      final folders = await db.folders();
      expect([for (final f in folders) f.path], ['Входящие', 'Входящие/Проекты', 'Входящие/Проекты/2025']);
      final leaf = folders.last;
      expect(leaf.parentId, folders[1].id);
      expect(leaf.count, 1);
      expect(folders.first.type, 'inbox');
    });

    test('письмо целиком: адресаты, вложения, картинка в тексте', () async {
      final id = await db.addMessage(mail('m2', const [(name: 'Inbox', type: 'inbox')]));
      final m = await db.message(id);
      expect(m, isNotNull);
      expect(m!.head.fromLabel, 'Иван Петров');
      expect(m.to.single.email, 'oleg@corp.ru');
      expect(m.head.hasAttachments, isTrue);
      expect(m.attachments.length, 2);
      final inline = m.attachments.firstWhere((a) => a.isInline);
      expect(inline.contentId, 'img1');
      expect(await db.attachmentData(m.attachments.first.id), [1, 2, 3]);
      final stats = await db.stats();
      expect(stats.messages, 1);
      expect(stats.attachments, 2);
    });

    test('поиск по теме, тексту, людям и имени файла', () async {
      await db.addMessage(mail('m3', const [(name: 'Inbox', type: 'inbox')]));
      await db.addMessage(mail('m4', const [(name: 'Sent', type: 'sent')], subject: 'Отпуск', body: 'График отпусков'));
      expect((await db.search('насос')).length, 1);
      expect((await db.search('отпуск')).single.folderPath, 'Sent');
      expect(await db.searchCount('Петров'), 2);
      expect(await db.searchCount('смета.xlsx'), 2);
      expect(await db.searchCount('нет-такого'), 0);
      // Кавычки и знаки в запросе не ломают поиск.
      expect(await db.searchCount('"насос'), 1);
    });

    test('удалить письмо из архива — вместе с вложениями и поиском', () async {
      final id = await db.addMessage(mail('m5', const [(name: 'Inbox', type: 'inbox')]));
      await db.deleteMessage(id);
      expect(await db.message(id), isNull);
      expect(await db.searchCount('насос'), 0);
      expect((await db.stats()).attachments, 0);
    });

    test('встречи, задачи и контакты — без повторов', () async {
      for (var i = 0; i < 2; i++) {
        await db.upsertEvent(
            accountId: 'a1', sourceId: 'e1', title: 'Планёрка', start: DateTime(2025, 1, 1, 9), end: DateTime(2025, 1, 1, 10), allDay: false);
        await db.upsertTask(accountId: 'a1', sourceId: 't1', title: 'Отчёт', completedAt: DateTime(2025, 1, 2));
        await db.upsertContact(accountId: 'a1', sourceId: 'c1', name: 'Иван', email: 'ivan@corp.ru');
      }
      final s = await db.stats();
      expect([s.events, s.tasks, s.contacts], [1, 1, 1]);
      expect((await db.contacts()).single.subtitle, 'ivan@corp.ru');
    });

    test('настройки приложения: хранятся последние пять', () async {
      for (var i = 0; i < 7; i++) {
        await db.saveSettings(data: Uint8List.fromList([i]), app: '1.7.3', device: 'test', accounts: i, secrets: false);
      }
      final list = await db.settingsSnapshots();
      expect(list.length, ArchiveDb.keepSettings);
      expect(await db.settingsData(list.first.id), isNotNull);
    });
  });

  group('какое письмо архивировать', () {
    late AppDatabase app;
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ogna_rules');
      app = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/r.db')));
      // Письмо ссылается на ящик (внешний ключ) — без ящика вставка падает.
      await app.into(app.accounts).insert(AccountsCompanion.insert(
            id: 'a1',
            type: 7,
            email: 'me@corp.example',
            displayName: 'a1',
            username: 'a1',
            createdAt: DateTime(2026, 1, 1),
          ));
    });
    tearDown(() async {
      await app.close();
      await dir.delete(recursive: true);
    });

    Future<Email> row(String id,
        {DateTime? at, bool flagged = false, int control = 0, int later = 0, bool draft = false}) async {
      await app.into(app.emails).insert(EmailsCompanion.insert(
            id: id,
            accountId: 'a1',
            folderId: 'INBOX',
            fromEmail: 'x@corp.ru',
            toRecipients: '[]',
            subject: id,
            receivedAt: at ?? DateTime(2025, 1, 1),
            isFlagged: Value(flagged),
            controlState: Value(control),
            laterState: Value(later),
            isDraft: Value(draft),
          ));
      return (app.select(app.emails)..where((e) => e.id.equals(id))).getSingle();
    }

    final now = DateTime(2026, 10, 25);
    final cutoff = const ArchiveSettings(months: 6).cutoff(now);

    bool ok(Email e, {FolderType? type = FolderType.inbox, bool flagged = false, bool manual = false}) =>
        ArchiveRules.mailEligible(e, folderType: type, cutoff: cutoff, includeFlagged: flagged, now: now, manual: manual);

    test('старше срока — да; свежее — нет', () async {
      expect(ok(await row('old')), isTrue);
      expect(ok(await row('new', at: DateTime(2026, 10, 1))), isFalse);
    });

    test('флажок и «На контроле» — только с настройкой', () async {
      final f = await row('f', flagged: true);
      final c = await row('c', control: 1);
      final done = await row('d', control: 3);
      expect(ok(f), isFalse);
      expect(ok(c), isFalse);
      expect(ok(done), isTrue);
      expect(ok(f, flagged: true), isTrue);
      expect(ok(c, flagged: true), isTrue);
    });

    test('черновики, корзина, «Позже» — нет; вручную — без проверок', () async {
      expect(ok(await row('dr', draft: true)), isFalse);
      expect(ok(await row('tr'), type: FolderType.trash), isFalse);
      final later = await row('l', later: 1);
      expect(ok(later), isFalse);
      expect(ok(await row('fresh', at: DateTime(2026, 10, 24), flagged: true), manual: true), isTrue);
    });

    test('цепочка папок от корня ящика', () {
      Folder f(String id, String name, int type, String? parent) =>
          Folder(id: id, accountId: 'a1', parentId: parent, displayName: name, type: type, unreadCount: 0, totalCount: 0,
              showInUnified: true, isFavorite: false, sortOrder: 0, isSynced: true);
      final folders = {
        'INBOX': f('INBOX', 'Входящие', FolderType.inbox.index, null),
        'INBOX/P': f('INBOX/P', 'Проекты', FolderType.custom.index, 'INBOX'),
      };
      expect(ArchiveRunner.folderChain('INBOX/P', folders),
          [(name: 'Входящие', type: 'inbox'), (name: 'Проекты', type: 'custom')]);
      // Папки нет в базе — её id одной папкой.
      expect(ArchiveRunner.folderChain('X', folders), [(name: 'X', type: 'custom')]);
    });
  });
}

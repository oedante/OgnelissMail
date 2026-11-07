// Текст вложений в поисковом индексе (1.12.x, поиск по тексту вложений,
// просьба владельца 04.11.2026): части по вложениям, переиндексация письма
// их не стирает, поиск находит слово только из вложения, выключенная
// настройка убирает текст, понемногу разбираются файлы из кэша.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/services/mail/attachment_cache_service.dart';
import 'package:ogneliss/services/search/attachment_text.dart';
import 'package:ogneliss/services/search/attachment_text_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кэш вложений без диска приложения: ключ → путь к файлу.
class _FakeCache extends AttachmentCacheService {
  _FakeCache(this.files);
  final Map<String, String> files;

  @override
  Future<void> ensureLoaded() async {}
  @override
  List<String> get keys => files.keys.toList();
  @override
  String? pathOf(String attachmentId) => files[attachmentId];
}

Future<void> _account(AppDatabase db) => db
    .into(db.accounts)
    .insert(
      AccountsCompanion.insert(
        id: 'a1',
        type: 7,
        email: 'a1@example.com',
        displayName: 'a1',
        username: 'a1',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

Future<void> _mail(AppDatabase db, String id, {String subject = 'Письмо', String attachments = '[]'}) => db
    .into(db.emails)
    .insert(
      EmailsCompanion.insert(
        id: id,
        accountId: 'a1',
        folderId: 'INBOX',
        fromEmail: 'sender@example.com',
        toRecipients: '[]',
        subject: subject,
        receivedAt: DateTime(2026, 11, 4),
        attachmentsJson: Value(attachments),
      ),
    );

Future<List<String>> _find(AppDatabase db, String q) async => [
  for (final e in await db.searchEmailsFts(accountId: 'a1', query: q)) e.id,
];

void main() {
  late Directory dir;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('attachment_index');
    db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/t.db')));
    await _account(db);
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('части текста вложений', () {
    test('метка — 12 управляющих знаков, у разных вложений разная', () {
      final m = AttachmentTextIndex.markerOf('AAMkAGI2…attachment=1');
      expect(m.length, 12);
      expect(m.codeUnits.every((c) => c < 0x20), isTrue);
      expect(AttachmentTextIndex.markerOf('AAMkAGI2…attachment=1'), m);
      expect(AttachmentTextIndex.markerOf('AAMkAGI2…attachment=2'), isNot(m));
    });

    test('замена своей части, остальные остаются', () {
      var s = AttachmentTextIndex.merge('', 'att1', 'первый документ');
      s = AttachmentTextIndex.merge(s, 'att2', 'вторая таблица');
      s = AttachmentTextIndex.merge(s, 'att1', 'первый документ, новая версия');
      final parts = AttachmentTextIndex.sectionsOf(s);
      expect(parts.values, ['вторая таблица', 'первый документ, новая версия']);
      // Вложение без текста — метка без текста (разобрано, повторно не берётся).
      s = AttachmentTextIndex.merge(s, 'logo', '');
      expect(AttachmentTextIndex.sectionsOf(s).length, 3);
    });

    test('предел на письмо: новой части — остаток', () {
      final chunk = 'а' * (AttachmentText.maxChars);
      var s = '';
      for (final id in ['a', 'b', 'c', 'd']) {
        s = AttachmentTextIndex.merge(s, id, chunk);
      }
      final parts = AttachmentTextIndex.sectionsOf(s);
      expect(parts.length, 4);
      final total = parts.values.fold<int>(0, (n, t) => n + t.length);
      expect(total, lessThanOrEqualTo(AttachmentText.maxMessageChars));
      expect(parts.values.last, isEmpty);
    });

    test('ключ кэша и имя файла', () {
      expect(AttachmentTextIndex.parseKey('acc|INBOX:12|2'), (
        accountId: 'acc',
        emailId: 'INBOX:12',
        attachmentId: '2',
      ));
      expect(AttachmentTextIndex.parseKey('acc|a|b|att'), (accountId: 'acc', emailId: 'a|b', attachmentId: 'att'));
      expect(AttachmentTextIndex.parseKey('acc|nope'), isNull);
      expect(
        AttachmentTextIndex.nameFromPath('/c/attachments/0cc175b9c0f1b6a831c399e269772661_____.docx'),
        '____.docx',
      );
      expect(
        AttachmentTextIndex.nameFromPath('/c/0cc175b9c0f1b6a831c399e269772661_Otchet_2026.xlsx'),
        'Otchet_2026.xlsx',
      );
    });
  });

  group('индекс', () {
    test('слово только из вложения находится; переиндексация письма текст не стирает', () async {
      await _mail(db, 'm1', subject: 'Отчёт за месяц');
      await db.indexEmailFts(
        emailId: 'm1',
        accountId: 'a1',
        subject: 'Отчёт за месяц',
        fromText: 'x',
        body: 'см. файл',
      );
      expect(await _find(db, 'картриджи'), isEmpty);

      await db.setFtsAttachmentsText('a1', 'm1', AttachmentTextIndex.merge('', 'att1', 'Картриджи 98 765,43'));
      expect(await _find(db, 'картриджи'), ['m1']);
      expect(await _find(db, 'картр'), ['m1'], reason: 'префикс');

      // Синхронизация сохранила письмо снова — по одному и пачкой.
      await db.indexEmailFts(emailId: 'm1', accountId: 'a1', subject: 'Отчёт за месяц', fromText: 'x', body: 'новое');
      expect(await _find(db, 'картриджи'), ['m1']);
      expect(await _find(db, 'новое'), ['m1']);
      await db.indexEmailFtsBatch('a1', [(emailId: 'm1', subject: 'Отчёт за месяц', fromText: 'x', body: 'пачка')]);
      expect(await _find(db, 'картриджи'), ['m1']);
      expect(await _find(db, 'пачка'), ['m1']);
      // Явно переданный текст вложений заменяет прежний.
      await db.indexEmailFts(
        emailId: 'm1',
        accountId: 'a1',
        subject: 'Отчёт',
        fromText: 'x',
        body: '',
        attachmentsText: 'бумага',
      );
      expect(await _find(db, 'картриджи'), isEmpty);
      expect(await _find(db, 'бумага'), ['m1']);
    });

    test('письма нет в индексе — строка создаётся с темой; метки словами не становятся', () async {
      await _mail(db, 'm2', subject: 'Счёт на оплату');
      await db.setFtsAttachmentsText('a1', 'm2', AttachmentTextIndex.merge('', 'x', 'Итого 100 011,93'));
      expect(await _find(db, 'итого'), ['m2']);
      expect(await _find(db, 'счёт'), ['m2']);
      await db.customStatement("CREATE VIRTUAL TABLE v USING fts5vocab('emails_fts', 'row')");
      final terms = [for (final r in await db.customSelect('SELECT term FROM v').get()) r.data['term'] as String];
      expect(terms.where((t) => t.codeUnits.any((c) => c < 0x20)), isEmpty);
      // Письма нет вовсе — ничего не создаётся.
      await db.setFtsAttachmentsText('a1', 'нет', 'текст');
      expect(await db.ftsAttachmentsText('a1', 'нет'), isNull);
    });

    test('что уже разобрано — по меткам в индексе', () async {
      await _mail(db, 'm3');
      await db.setFtsAttachmentsText('a1', 'm3', AttachmentTextIndex.merge('', 'att1', 'текст'));
      String needle(String att) => '\u001E${AttachmentTextIndex.markerOf(att)}';
      final got = await db.ftsAttachmentsContaining({
        'k1': (accountId: 'a1', emailId: 'm3', needle: needle('att1')),
        'k2': (accountId: 'a1', emailId: 'm3', needle: needle('att2')),
        'k3': (accountId: 'a1', emailId: 'другое', needle: needle('att1')),
      });
      expect(got, {'k1'});
    });

    test('«найдено во вложении» — только когда тема и текст письма не подходят', () async {
      await _mail(db, 'm4', subject: 'Договор поставки');
      await _mail(db, 'm5', subject: 'Протокол');
      await db.indexEmailFts(emailId: 'm4', accountId: 'a1', subject: 'Договор поставки', fromText: '', body: 'привет');
      await db.indexEmailFts(emailId: 'm5', accountId: 'a1', subject: 'Протокол', fromText: '', body: 'привет');
      await db.setFtsAttachmentsText(
        'a1',
        'm4',
        AttachmentTextIndex.merge('', 'a', 'Срок поставки оборудования — до пятницы, неустойка 5 %'),
      );
      await db.setFtsAttachmentsText('a1', 'm5', AttachmentTextIndex.merge('', 'a', 'Поставки и договор'));
      expect((await _find(db, 'неустойка')), ['m4']);
      final hits = await db.ftsAttachmentHits(accountId: 'a1', query: 'неустойка', ids: ['m4']);
      expect(hits.keys, ['m4']);
      expect(hits['m4'], contains('неустойка'));
      expect(hits['m4']!.codeUnits.any((c) => c < 0x20), isFalse);
      // «договор» есть в теме m4 — строка результата как обычно.
      final both = await db.ftsAttachmentHits(accountId: 'a1', query: 'договор', ids: ['m4', 'm5']);
      expect(both.keys, ['m5']);
    });
  });

  // 1.15.1: письмо получило на сервере новый номер — текст вложений не
  // теряется.
  group('новый номер письма', () {
    test('переименование: текст вложений — у письма под новым номером', () async {
      await _mail(db, 'INBOX:7', subject: 'Смета');
      await db.indexEmailFts(emailId: 'INBOX:7', accountId: 'a1', subject: 'Смета', fromText: 's', body: 'тело');
      await db.setFtsAttachmentsText('a1', 'INBOX:7', 'ракетостроение');
      await db.customStatement("UPDATE emails SET id = 'Archive:3' WHERE id = 'INBOX:7'");
      await db.renameEmailFts('a1', 'INBOX:7', 'Archive:3', subject: 'Смета', fromText: 's', body: 'тело');
      expect(await db.ftsAttachmentsText('a1', 'INBOX:7'), isNull);
      expect(await db.ftsAttachmentsText('a1', 'Archive:3'), 'ракетостроение');
    });

    test('перенос без нового номера: текст возвращается по Message-ID', () async {
      await _mail(db, 'INBOX:8', subject: 'Счёт');
      await db.customStatement("UPDATE emails SET internet_message_id = '<A1@Example.com>' WHERE id = 'INBOX:8'");
      await db.indexEmailFts(emailId: 'INBOX:8', accountId: 'a1', subject: 'Счёт', fromText: 's', body: 'тело');
      await db.setFtsAttachmentsText('a1', 'INBOX:8', 'аккредитив');
      await db.keepAttachmentsTextForReturn('a1', 'INBOX:8');
      await db.removeEmailFts('INBOX:8', accountId: 'a1');
      await db.customStatement("DELETE FROM emails WHERE id = 'INBOX:8'");
      // Письмо пришло синхронизацией папки назначения под новым номером.
      await _mail(db, 'Archive:9', subject: 'Счёт');
      await db.customStatement("UPDATE emails SET internet_message_id = '<a1@example.com>' WHERE id = 'Archive:9'");
      await db.indexEmailFts(emailId: 'Archive:9', accountId: 'a1', subject: 'Счёт', fromText: 's', body: 'тело');
      expect(await db.ftsAttachmentsText('a1', 'Archive:9'), 'аккредитив');
      // Один раз: следующее письмо с тем же Message-ID текст не получает.
      await _mail(db, 'Other:1', subject: 'Копия');
      await db.customStatement("UPDATE emails SET internet_message_id = '<a1@example.com>' WHERE id = 'Other:1'");
      await db.indexEmailFts(emailId: 'Other:1', accountId: 'a1', subject: 'Копия', fromText: 's', body: 'тело');
      expect(await db.ftsAttachmentsText('a1', 'Other:1'), '');
    });
  });

  group('служба', () {
    late ProviderContainer c;
    late Map<String, String> files;
    late SharedPreferences prefs;

    ProviderContainer make() => ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        attachmentCacheProvider.overrideWithValue(_FakeCache(files)),
      ],
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      files = {};
      c = make();
    });
    tearDown(() => c.dispose());

    test('файлы из кэша — в индекс понемногу; повторно не разбираются; выключили — текст убран', () async {
      String file(String name, List<int> bytes) =>
          (File('${dir.path}/0cc175b9c0f1b6a831c399e269772661_$name')..writeAsBytesSync(bytes)).path;
      await _mail(
        db,
        'm1',
        subject: 'Квартальный отчёт',
        attachments:
            '[{"id":"d1","name":"Отчёт.docx","mimeType":"application/octet-stream","size":1},'
            '{"id":"t1","name":"notes.txt","size":1},{"id":"p1","name":"logo.png","size":1}]',
      );
      await db.indexEmailFts(emailId: 'm1', accountId: 'a1', subject: 'Квартальный отчёт', fromText: '', body: '');
      files['a1|m1|d1'] = file('_____.docx', File('test/fixtures/office/text_sample.docx').readAsBytesSync());
      files['a1|m1|t1'] = file('notes.txt', utf8.encode('Протокол совещания отдела снабжения'));
      files['a1|m1|p1'] = file('logo.png', [0x89, 0x50, 0x4E, 0x47]);
      files['a1|нет|x'] = file('x.txt', [0x41]);

      final index = c.read(attachmentTextIndexProvider)..start();
      expect(await index.backfill('a1'), 2);
      expect(await _find(db, 'снабжения'), ['m1']);
      expect(await _find(db, 'подготовка'), ['m1']); // из DOCX
      expect(await _find(db, 'квартальный'), ['m1']);

      // Новый экземпляр (перезапуск): уже разобранное узнаётся по индексу.
      final c2 = make();
      addTearDown(c2.dispose);
      expect(await c2.read(attachmentTextIndexProvider).backfill('a1'), 0);

      await c.read(settingsProvider.notifier).setSearchAttachments(false);
      for (var i = 0; i < 20 && (await db.ftsAttachmentsText('a1', 'm1'))!.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await db.ftsAttachmentsText('a1', 'm1'), isEmpty);
      expect(await _find(db, 'снабжения'), isEmpty);
      expect(await _find(db, 'квартальный'), ['m1']);
      expect(await index.backfill('a1'), 0, reason: 'выключено');
    });
  });
}

// Строки писем без тел (1.5.9): беседа и превью. Лента с 1.5.8 читает строки
// без текстов; у писем IMAP превью в строке не было — оно бралось из текста.
// Теперь превью заполняется из сохранённого текста (разово и при загрузке),
// а беседа не перечитывает тексты всех писем при каждом изменении.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/mail_body_processor.dart';
import 'package:ogneliss/core/utils/text_safe.dart';
import 'package:ogneliss/data/database/app_database.dart';

Future<AppDatabase> _db(Directory dir) async {
  final db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/l.db')));
  await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@x', displayName: 'a1', username: 'a1', createdAt: DateTime(2026)));
  return db;
}

Future<void> _mail(AppDatabase db, String id,
    {String? plain, String? html, String? preview, String conv = 'c1', String? mid, String folder = 'INBOX'}) {
  return db.into(db.emails).insert(EmailsCompanion.insert(
        id: id,
        accountId: 'a1',
        folderId: folder,
        fromEmail: 'p@x',
        toRecipients: '[]',
        subject: 'S $id',
        receivedAt: DateTime(2026, 10, 1, 9, int.parse(id.substring(1))),
        conversationId: Value(conv),
        internetMessageId: Value(mid),
        bodyPlain: Value(plain),
        bodyHtml: Value(html),
        bodyPreview: Value(preview),
      ));
}

void main() {
  group('previewOf', () {
    test('пробелы и переводы строк — одним пробелом', () {
      expect(previewOf('  Привет,\r\n\r\n\tкак дела?  '), 'Привет, как дела?');
    });
    test('пустой текст — null', () {
      expect(previewOf(null), isNull);
      expect(previewOf(''), isNull);
      expect(previewOf(' \n\t '), isNull);
    });
    test('не длиннее 200 и без разрыва эмодзи', () {
      final p = previewOf('${'a' * 199}😀 хвост')!;
      expect(p.length, lessThanOrEqualTo(200));
      expect(fixUtf16(p), p);
    });
  });

  test('текст из HTML: без заголовка документа и условных блоков Outlook', () {
    const html = '<html><head><title>Рассылка недели</title><style>p{color:red}</style></head>'
        '<body><!--[if mso]><v:rect>VML</v:rect><![endif]--><p>Здравствуйте!</p>'
        '<header>Шапка</header></body></html>';
    final t = MailBodyProcessor.htmlToPlain(html);
    expect(t, 'Здравствуйте! Шапка');
  });

  test('превью из сохранённых текстов: только у писем без превью', () async {
    final dir = await Directory.systemTemp.createTemp('ogneliss_light_test');
    final db = await _db(dir);
    await _mail(db, 'm1', plain: 'Первая строка\r\nвторая строка');
    await _mail(db, 'm2', plain: 'Текст', preview: 'Своё превью');
    await _mail(db, 'm3', html: '<p>Только HTML</p>');
    await _mail(db, 'm4', plain: '   \r\n  ');
    await _mail(db, 'm5', plain: 'x' * 5000);

    expect(await db.fillMissingPreviews(chunk: 2), 3);
    final rows = {for (final r in await db.select(db.emails).get()) r.id: r};
    expect(rows['m1']!.bodyPreview, 'Первая строка  вторая строка');
    expect(rows['m2']!.bodyPreview, 'Своё превью');
    expect(rows['m3']!.bodyPreview, isNull); // текста нет — нечего брать
    expect(rows['m4']!.bodyPreview, ''); // пусто, но больше не выбирается
    expect(rows['m5']!.bodyPreview!.length, 200);
    expect(await db.fillMissingPreviews(), 0); // второй раз — ничего

    await db.close();
    await dir.delete(recursive: true);
  });

  test('беседа: строки без тел, копии из «Вся почта» убраны, превью из текста', () async {
    final dir = await Directory.systemTemp.createTemp('ogneliss_light_test');
    final db = await _db(dir);
    await _mail(db, 'm1', plain: 'Ответ на письмо', html: '<p>Ответ</p>', mid: '<1@x>');
    await _mail(db, 'm2', plain: 'Второе', preview: 'Второе', mid: '<2@x>');
    await _mail(db, 'm3', plain: 'Копия', mid: '<2@x>', folder: '[Gmail]/All Mail');
    await _mail(db, 'm4', plain: 'Чужая беседа', conv: 'c2');

    final rows = await db.watchConversationLight(conversationId: 'c1', accountId: 'a1').first;
    expect(rows.map((r) => r.id), ['m2', 'm1']); // новое первым, копия m3 убрана
    expect(rows.every((r) => r.bodyPlain == null && r.bodyHtml == null), isTrue);

    final p = await db.previewsFromBody('a1', ['m1', 'm2']);
    expect(p['m1'], 'Ответ на письмо');

    final thread = await db.getConversationLight(conversationId: 'c1', accountId: 'a1');
    expect(thread.first.id, 'm1'); // старое первым
    expect(thread.first.bodyPreview, 'Ответ на письмо');
    expect(thread.first.bodyPlain, isNull);

    await db.close();
    await dir.delete(recursive: true);
  });

  test('дубли ActiveSync: остаётся свежая строка, отметки переносятся', () async {
    final dir = await Directory.systemTemp.createTemp('ogneliss_light_test');
    final db = await _db(dir);
    Future<void> put(String id, int cachedSec, {int later = 0, String? tags}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a1',
              folderId: '8',
              fromEmail: 'Boss@X.ru',
              toRecipients: '[]',
              subject: 'RE: СКУД',
              receivedAt: DateTime(2026, 10, 12, 18, 29),
              size: const Value(5000),
              laterState: Value(later),
              tagsStr: Value(tags),
              cachedAt: Value(DateTime.fromMillisecondsSinceEpoch(cachedSec * 1000)),
            ));
    await put('8:100', 1000, later: 1, tags: 'важно');
    await put('8:900', 2000);
    // Другое письмо с той же темой, но в другое время — не дубль.
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: '8:101', accountId: 'a1', folderId: '8', fromEmail: 'boss@x.ru', toRecipients: '[]',
          subject: 'RE: СКУД', receivedAt: DateTime(2026, 10, 12, 18, 30), size: const Value(5000)));
    expect(await db.removeEasDuplicates(['a1']), 1);
    final rows = {for (final r in await db.select(db.emails).get()) r.id: r};
    expect(rows.keys.toSet(), {'8:900', '8:101'});
    expect(rows['8:900']!.laterState, 1);
    expect(rows['8:900']!.tagsStr, 'важно');
    expect(await db.removeEasDuplicates(['a1']), 0);
    await db.close();
    await dir.delete(recursive: true);
  });
}

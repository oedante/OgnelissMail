// Текст вложений для поиска (1.12.x, поиск по тексту вложений, просьба
// владельца 04.11.2026): документы, таблицы, презентации, текст, HTML,
// вложенные письма; пределы и чужие файлы.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/office_reader.dart';
import 'package:ogneliss/services/search/attachment_text.dart';

Uint8List _fx(String name) => File('test/fixtures/office/$name').readAsBytesSync();

/// Письмо RFC 822 с текстом и вложениями (имя, тип, байты).
String _eml(String subject, String body, List<(String, String, List<int>)> parts) {
  final b = StringBuffer()
    ..write('From: Отдел <office@example.com>\r\n')
    ..write('To: user@example.com\r\n')
    ..write('Subject: =?utf-8?B?${base64Encode(utf8.encode(subject))}?=\r\n')
    ..write('Date: Wed, 04 Nov 2026 10:00:00 +0300\r\n')
    ..write('MIME-Version: 1.0\r\n')
    ..write('Content-Type: multipart/mixed; boundary="b1"\r\n\r\n')
    ..write('--b1\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n')
    ..write('${base64Encode(utf8.encode(body))}\r\n');
  for (final (name, type, bytes) in parts) {
    b
      ..write('--b1\r\nContent-Type: $type; name="$name"\r\n')
      ..write('Content-Disposition: attachment; filename="$name"\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n\r\n')
      ..write('${base64Encode(bytes)}\r\n');
  }
  b.write('--b1--\r\n');
  return b.toString();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('attachment_text'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) => File('${dir.path}/$name')..writeAsBytesSync(bytes);

  Future<String> text(String name, List<int> bytes, {String? mimeType}) async =>
      (await AttachmentText.extractPath(write(name, bytes).path, name, mimeType: mimeType, lang: 'ru')).text;

  test('вид вложения — по имени и типу', () {
    for (final n in [
      'a.docx',
      'a.odt',
      'a.rtf',
      'a.xlsx',
      'a.ods',
      'a.csv',
      'a.tsv',
      'a.pptx',
      'a.odp',
      'a.doc',
      'a.xls',
    ]) {
      expect(AttachmentText.kindOf(n), AttachmentTextKind.office, reason: n);
    }
    expect(AttachmentText.kindOf('Отчёт.TXT'), AttachmentTextKind.text);
    expect(AttachmentText.kindOf('page.html'), AttachmentTextKind.html);
    expect(AttachmentText.kindOf('fwd.eml'), AttachmentTextKind.eml);
    expect(AttachmentText.kindOf('Сообщение', mimeType: 'message/rfc822'), AttachmentTextKind.eml);
    expect(AttachmentText.kindOf('readme', mimeType: 'text/plain'), AttachmentTextKind.text);
    expect(AttachmentText.kindOf('ATT00001'), AttachmentTextKind.sniff);
    for (final n in ['photo.jpg', 'image001.png', 'archive.zip', 'scan.pdf', 'setup.exe']) {
      expect(AttachmentText.kindOf(n), isNull, reason: n);
    }
  });

  test('документы: абзацы, списки, таблицы, сноски', () async {
    for (final f in ['text_sample.docx', 'text_sample.odt', 'text_sample.rtf']) {
      final t = await text(f, _fx(f));
      expect(t, contains('Отчёт о работе отдела'), reason: f);
      expect(t, contains('Вложенный пункт'), reason: f);
      expect(t, contains('Февраль'), reason: f);
      expect(t, contains('Данные условные'), reason: f);
      expect(t, isNot(contains('<')), reason: f);
    }
    expect(await text('записка.rtf', _fx('text_cp1251.rtf')), contains('Служебная записка'));
  });

  test('таблицы: ячейки строка за строкой, все листы', () async {
    for (final f in ['sheet_sample.xlsx', 'sheet_sample.ods']) {
      final t = await text(f, _fx(f));
      expect(t, contains('Отчёт по продажам за ноябрь'), reason: f);
      expect(t.split('\n'), contains(startsWith('Картриджи ')), reason: f);
      expect(t, contains('Справочник'), reason: f);
      expect(t, contains('Двойка'), reason: f);
    }
    expect(await text('sheet.csv', _fx('sheet_cp1251.csv')), contains('Шариковая'));
    expect(await text('sheet.tsv', _fx('sheet_tabs.tsv')), contains('альфа 1'));
  });

  test('презентации: надписи и таблицы слайдов, повторы — один раз', () async {
    for (final f in ['slides.pptx', 'slides.odp']) {
      final t = await text(f, _fx(f));
      expect(t, contains('Квартальный отчёт'), reason: f);
      expect(t, contains('Новосибирск'), reason: f);
      expect(t, contains('Казань'), reason: f);
      expect(t, contains('Спасибо!'), reason: f);
      expect('\n$t\n'.split('\nКвартальный отчёт\n').length, 2, reason: f);
    }
  });

  test('текстовый файл: UTF-8 и Windows-1251, без управляющих знаков', () async {
    expect(
      await text('notes.txt', utf8.encode('Протокол\u001E совещания\u0001\r\n\r\n\tитоги')),
      'Протокол совещания\nитоги',
    );
    final cp1251 = [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x20, 0xEC, 0xE8, 0xF0]; // «Привет мир»
    expect(await text('old.txt', cp1251), 'Привет мир');
  });

  test('HTML: блоки — строками, строчные теги не делят слово, скрипты и стили — без текста', () {
    const html =
        '<html><head><title>Заголовок</title><style>.x{color:red}</style></head><body>'
        '<p>При<b>вет</b>,&nbsp;мир &amp; друзья &#8212; &laquo;да&raquo;</p><!-- скрыто -->'
        '<script>alert("секрет")</script><div>второй<br>третий</div><SCRIPT>ещё</SCRIPT></body></html>';
    expect(AttachmentText.htmlToText(html), 'Привет, мир & друзья — «да»\nвторой\nтретий');
    // Незакрытый скрипт — текста после него нет; «<» в тексте — не тег.
    expect(AttachmentText.htmlToText('<p>a < b</p><script>x'), 'a < b');
    // Глубокая вложенность — без рекурсии.
    expect(AttachmentText.htmlToText('${'<div>' * 50000}слово${'</div>' * 50000}'), 'слово');
  });

  test('вложенное письмо: тема, адреса, текст и его вложения', () async {
    final inner = _eml('Вложенный договор', 'Текст вложенного письма', []);
    final eml = _eml('Пересылка отчёта', 'Смотрите приложение', [
      (
        'Отчёт.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _fx('text_sample.docx'),
      ),
      ('note.txt', 'text/plain', utf8.encode('заметка на полях')),
      ('inner.eml', 'message/rfc822', utf8.encode(inner)),
      ('logo.png', 'image/png', [0x89, 0x50, 0x4E, 0x47]),
    ]);
    final t = await text('fwd.eml', utf8.encode(eml));
    expect(t, contains('Пересылка отчёта'));
    expect(t, contains('office@example.com'));
    expect(t, contains('Смотрите приложение'));
    expect(t, contains('Отчёт о работе отдела'));
    expect(t, contains('заметка на полях'));
    expect(t, contains('Текст вложенного письма'));
    // Без расширения (так Exchange отдаёт вложенные письма) — по содержимому.
    expect(await text('ATT00001', utf8.encode(eml)), contains('Смотрите приложение'));
  });

  test('вложенные письма — не глубже предела', () async {
    var eml = _eml('Уровень 0', 'самое глубокое', []);
    for (var i = 1; i <= 3; i++) {
      eml = _eml('Уровень $i', 'текст $i', [('m$i.eml', 'message/rfc822', utf8.encode(eml))]);
    }
    final t = await text('top.eml', utf8.encode(eml));
    expect(t, contains('текст 3'));
    expect(t, contains('текст 2'));
    expect(t, isNot(contains('текст 1')));
    expect(t, isNot(contains('самое глубокое')));
  });

  test('пределы: текст вложения не длиннее maxChars, без разрыва эмодзи', () async {
    final big = List.generate(40000, (i) => 'слово$i').join(' ');
    final t = await text('big.txt', utf8.encode(big));
    expect(t.length, lessThanOrEqualTo(AttachmentText.maxChars));
    expect(t, startsWith('слово0 слово1'));
    final cut = AttachmentText.clean('${'a' * 9}😀', max: 10);
    expect(cut, 'a' * 9);
    final doc = OfficeReader.readBytes(_fx('sheet_sample.xlsx'), 'a.xlsx', lang: 'ru');
    expect(AttachmentText.textOfDoc(doc, max: 40).length, lessThanOrEqualTo(40));
  });

  test('в изоляте: документ с диска; чужие и сломанные файлы — без текста и без ошибок', () async {
    final docx = write('Отчёт.docx', _fx('text_sample.docx'));
    final r = await AttachmentText.extractFile(docx.path, 'Отчёт.docx', lang: 'ru');
    expect(r.text, contains('Отчёт о работе отдела'));
    expect(r.retryLater, isFalse);

    final broken = write('broken.docx', utf8.encode('не документ'));
    final b = await AttachmentText.extractFile(broken.path, 'broken.docx');
    expect(b.text, isEmpty);
    expect(b.retryLater, isFalse);

    final ole = write('old.doc', [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(512, 0)]);
    expect((await AttachmentText.extractFile(ole.path, 'old.doc')).text, isEmpty);

    final png = write('image001.png', [0x89, 0x50, 0x4E, 0x47]);
    expect((await AttachmentText.extractFile(png.path, 'image001.png')).text, isEmpty);

    // Файла нет (кэш очистила система) — попробовать позже.
    final gone = await AttachmentText.extractFile('${dir.path}/нет.txt', 'нет.txt');
    expect(gone.retryLater, isTrue);
  });
}

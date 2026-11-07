// Текст PDF для поиска по вложениям (1.15.1): образцы — tool/dev/pdf_fixtures.py
// (свои тексты; защита — pypdf), плюс PDF, который делает само приложение
// (пакет pdf, шрифт Roboto, кириллица).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/pdf_text.dart';
import 'package:ogneliss/services/search/attachment_text.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List _fixture(String name) => File('test/fixtures/pdf/$name').readAsBytesSync();

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  test('WinAnsi: строки, TJ с кернингом, экранирование, строки по Td и Tm', () {
    final t = PdfText.extract(_fixture('winansi.pdf'));
    expect(t, contains('Invoice No. 2026-117'));
    // Кернинг 20 — не пробел, −400 — пробел.
    expect(t, contains('Smeta total'));
    expect(t, contains('(net) price: 100 ä EUR'));
    expect(t.split('\n').map((l) => l.trim()), containsAll(['Second', 'line']));
  });

  test('кириллица через /Differences (afii и uniXXXX)', () {
    expect(_flat(PdfText.extract(_fixture('differences.pdf'))), 'Привет Жук');
  });

  test('составной шрифт: ToUnicode, bfchar и bfrange (массив и строка)', () {
    expect(_flat(PdfText.extract(_fixture('type0.pdf'))), 'Смет абв');
  });

  test('объекты в сжатом потоке объектов (PDF 1.5)', () {
    expect(_flat(PdfText.extract(_fixture('objstm.pdf'))), 'Packed objects work');
  });

  for (final f in ['rc4_40.pdf', 'rc4_128.pdf', 'aes_128.pdf', 'aes_256.pdf']) {
    test('защита без пароля на открытие: $f', () {
      expect(PdfText.extract(_fixture(f)), contains('Invoice No. 2026-117'));
    });
  }

  test('пароль на открытие — текста нет, без ошибки', () {
    expect(PdfText.extract(_fixture('locked.pdf')), isNot(contains('Invoice')));
  });

  test('не PDF, обрезанный, мусор — пустая строка без ошибки', () {
    expect(PdfText.extract(Uint8List.fromList('hello'.codeUnits)), '');
    final w = _fixture('winansi.pdf');
    PdfText.extract(Uint8List.sublistView(w, 0, w.length ~/ 2));
    final junk = Uint8List.fromList([...'%PDF-1.7\n'.codeUnits, ...List.generate(5000, (i) => (i * 37) % 256)]);
    expect(PdfText.extract(junk), '');
  });

  test('предел длины текста', () {
    expect(PdfText.extract(_fixture('winansi.pdf'), maxChars: 10).length, lessThanOrEqualTo(10));
  });

  test('PDF приложения (пакет pdf, Roboto): кириллица и латиница', () async {
    final font = pw.Font.ttf(File('assets/fonts/pdf/Roboto-Regular.ttf').readAsBytesSync().buffer.asByteData());
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(children: [
        pw.Text('Смета на ремонт офиса', style: pw.TextStyle(font: font)),
        pw.Text('Total: 1 250 000 руб.', style: pw.TextStyle(font: font)),
      ]),
    ));
    doc.addPage(pw.Page(build: (_) => pw.Text('Вторая страница', style: pw.TextStyle(font: font))));
    final t = _flat(PdfText.extract(await doc.save()));
    expect(t, contains('Смета на ремонт офиса'));
    expect(t, contains('Total: 1 250 000 руб.'));
    expect(t, contains('Вторая страница'));
  });

  test('поиск по вложениям: PDF читается', () async {
    expect(AttachmentText.kindOf('счёт.pdf'), AttachmentTextKind.pdf);
    expect(AttachmentText.kindOf('scan', mimeType: 'application/pdf'), AttachmentTextKind.pdf);
    final r = await AttachmentText.extractPath('test/fixtures/pdf/aes_128.pdf', 'счёт.pdf');
    expect(r.text, contains('Invoice No. 2026-117'));
    expect(AttachmentText.textOfBytes(_fixture('differences.pdf'), 'a.pdf'), contains('Привет'));
  });
}

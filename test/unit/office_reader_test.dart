// Формат документа — по содержимому, а не только по расширению (1.11.x,
// предпросмотр документов): переименованные файлы открываются своим
// читателем; составной файл OLE (1.12.x) — по своим потокам: Word, Excel,
// PowerPoint 97–2003, OOXML с паролем (EncryptedPackage), прочее — «не
// умею», испорченный — «повреждён».

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/doc_sheets.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/office_reader.dart';

import 'cfb_writer.dart';

Uint8List _fx(String name) => File('test/fixtures/office/$name').readAsBytesSync();

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

void main() {
  final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(512, 0)]);
  // Документ OOXML с паролем: пакет зашифрован в потоке EncryptedPackage.
  final encrypted = (CfbWriter()
        ..add('EncryptionInfo', List.filled(200, 1))
        ..add('EncryptedPackage', List.filled(5000, 2)))
      .build();

  test('по расширению — свой читатель', () {
    expect(OfficeReader.readBytes(_fx('text_sample.docx'), 'a.docx'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('sheet_sample.xlsx'), 'a.xlsx'), isA<OfficeSheetsDoc>());
    expect(OfficeReader.readBytes(_fx('slides.odp'), 'a.odp'), isA<OfficeSlidesDoc>());
    expect(OfficeReader.readBytes(_fx('sheet_utf8.csv'), 'a.csv'), isA<OfficeSheetsDoc>());
    expect(OfficeReader.readBytes(_fx('text_sample.rtf'), 'a.rtf'), isA<OfficeTextDoc>());
  });

  test('переименованные: ODS как .xlsx, DOCX как .rtf и .doc, RTF как .doc', () {
    expect(OfficeReader.readBytes(_fx('sheet_sample.ods'), 'a.xlsx'), isA<OfficeSheetsDoc>());
    expect(OfficeReader.readBytes(_fx('text_sample.docx'), 'a.rtf'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('text_sample.docx'), 'a.doc'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('text_cp1251.rtf'), 'a.doc'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('slides.pptx'), 'a.docx'), isA<OfficeSlidesDoc>());
  });

  test('OLE: Word, Excel, PowerPoint 97–2003 — по потокам, под любым именем', () {
    expect(OfficeReader.readBytes(_fx('text_sample.doc'), 'a.doc'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('sheet_sample.xls'), 'a.xls'), isA<OfficeSheetsDoc>());
    expect(OfficeReader.readBytes(_fx('slides.ppt'), 'a.pps'), isA<OfficeSlidesDoc>());
    expect(OfficeReader.readBytes(_fx('text_sample.doc'), 'a.xls'), isA<OfficeTextDoc>());
    expect(OfficeReader.readBytes(_fx('sheet_sample.xls'), 'Выгрузка.doc'), isA<OfficeSheetsDoc>());
    expect(OfficeReader.readBytes(_fx('slides.ppt'), 'a.docx'), isA<OfficeSlidesDoc>());
  });

  test('OLE: OOXML с паролем — «защищён», прочие — «не умею», испорченный — «повреждён»', () {
    expect(() => OfficeReader.readBytes(encrypted, 'a.docx'), _error(OfficeDocError.encrypted));
    expect(() => OfficeReader.readBytes(encrypted, 'a.xlsx'), _error(OfficeDocError.encrypted));
    expect(() => OfficeReader.readBytes(encrypted, 'a.doc'), _error(OfficeDocError.encrypted));
    final visio = (CfbWriter()..add('VisioDocument', List.filled(100, 3))).build();
    expect(() => OfficeReader.readBytes(visio, 'a.doc'), _error(OfficeDocError.unsupported));
    expect(() => OfficeReader.readBytes(ole, 'a.docx'), _error(OfficeDocError.damaged));
    expect(() => OfficeReader.readBytes(ole, 'a.doc'), _error(OfficeDocError.damaged));
  });

  test('не документ — «повреждён»; «.doc» текстом — «не умею»', () {
    final text = Uint8List.fromList('просто текст, не документ'.codeUnits.map((c) => c & 0xFF).toList());
    expect(() => OfficeReader.readBytes(text, 'a.docx'), _error(OfficeDocError.damaged));
    expect(() => OfficeReader.readBytes(text, 'a.doc'), _error(OfficeDocError.unsupported));
    expect(OfficeReader.previews('a.doc'), isTrue);
    expect(OfficeReader.previews('a.xls'), isTrue);
    expect(OfficeReader.previews('a.bin', mimeType: 'application/vnd.ms-powerpoint'), isTrue);
    expect(OfficeReader.previews('a.docx'), isTrue);
    expect(OfficeReader.previews('a.jpg'), isFalse);
  });

  test('в изоляте: файл с диска, ошибка — тем же видом', () async {
    final dir = await Directory.systemTemp.createTemp('office_reader');
    try {
      final f = File('${dir.path}/Отчёт.docx')..writeAsBytesSync(_fx('text_sample.docx'));
      expect(await OfficeReader.readFile(f.path, 'Отчёт.docx', lang: 'ru'), isA<OfficeTextDoc>());
      final p = File('${dir.path}/Зарплата.xlsx')..writeAsBytesSync(encrypted);
      await expectLater(OfficeReader.readFile(p.path, 'Зарплата.xlsx'), _error(OfficeDocError.encrypted));
      await expectLater(OfficeReader.readFile('${dir.path}/нет.docx', 'нет.docx'), _error(OfficeDocError.damaged));
      final x = File('${dir.path}/Смета.xls')..writeAsBytesSync(_fx('sheet_sample.xls'));
      final book = await OfficeReader.readFile(x.path, 'Смета.xls', lang: 'ru');
      expect((book as OfficeSheetsDoc).sheets.first.name, 'Отчёт');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

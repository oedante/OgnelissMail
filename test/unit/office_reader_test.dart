// Формат документа — по содержимому, а не только по расширению (1.11.x,
// предпросмотр документов): переименованные файлы открываются своим
// читателем, составной файл OLE — «с паролем» или «старый формат».

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/doc_sheets.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/office_reader.dart';

Uint8List _fx(String name) => File('test/fixtures/office/$name').readAsBytesSync();

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

void main() {
  final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(512, 0)]);

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

  test('OLE: у OOXML — пароль, у остальных — старый формат', () {
    expect(() => OfficeReader.readBytes(ole, 'a.docx'), _error(OfficeDocError.encrypted));
    expect(() => OfficeReader.readBytes(ole, 'a.xlsx'), _error(OfficeDocError.encrypted));
    expect(() => OfficeReader.readBytes(ole, 'a.doc'), _error(OfficeDocError.legacy));
    expect(() => OfficeReader.readBytes(ole, 'a.rtf'), _error(OfficeDocError.legacy));
    expect(() => OfficeReader.readBytes(ole, 'a.odt'), _error(OfficeDocError.legacy));
  });

  test('не документ — «повреждён»; старый .doc текстом — «старый формат»', () {
    final text = Uint8List.fromList('просто текст, не документ'.codeUnits.map((c) => c & 0xFF).toList());
    expect(() => OfficeReader.readBytes(text, 'a.docx'), _error(OfficeDocError.damaged));
    expect(() => OfficeReader.readBytes(text, 'a.doc'), _error(OfficeDocError.legacy));
    expect(OfficeReader.previews('a.doc', head: _fx('text_cp1251.rtf').sublist(0, 8)), isTrue);
    expect(OfficeReader.previews('a.doc', head: ole.sublist(0, 8)), isFalse);
    expect(OfficeReader.previews('a.docx'), isTrue);
    expect(OfficeReader.previews('a.jpg'), isFalse);
  });

  test('в изоляте: файл с диска, ошибка — тем же видом', () async {
    final dir = await Directory.systemTemp.createTemp('office_reader');
    try {
      final f = File('${dir.path}/Отчёт.docx')..writeAsBytesSync(_fx('text_sample.docx'));
      expect(await OfficeReader.readFile(f.path, 'Отчёт.docx', lang: 'ru'), isA<OfficeTextDoc>());
      final p = File('${dir.path}/Зарплата.xlsx')..writeAsBytesSync(ole);
      await expectLater(OfficeReader.readFile(p.path, 'Зарплата.xlsx'), _error(OfficeDocError.encrypted));
      await expectLater(OfficeReader.readFile('${dir.path}/нет.docx', 'нет.docx'), _error(OfficeDocError.damaged));
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

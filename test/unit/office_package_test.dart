// Пакет документа (1.11.x, предпросмотр документов): свой читатель ZIP с
// пределами на распакованное — «ZIP-бомба» не занимает память, начало
// большой части читается, имена частей и цели связей нормализуются.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';

Uint8List _zip(Map<String, List<int>> files, {bool store = false}) {
  final a = Archive();
  files.forEach((name, data) {
    final f = ArchiveFile.bytes(name, data);
    if (store) f.compression = CompressionType.none;
    a.add(f);
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('части читаются, имена — без учёта регистра и с нормализацией', () {
    final z = OfficeZip.open(_zip({
      '[Content_Types].xml': utf8.encode('<Types/>'),
      'word/document.xml': utf8.encode('<w:document xmlns:w="urn:w"><w:body>Привет</w:body></w:document>'),
      'word/media/Image1.PNG': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0],
    }));
    expect(z.has('word/document.xml'), isTrue);
    expect(z.find('/WORD/Document.xml'), 'word/document.xml');
    expect(z.find('word/../word/./document.xml'), 'word/document.xml');
    expect(z.readText('word/document.xml'), contains('Привет'));
    expect(z.readXml('word/document.xml')!.rootElement.local, 'document');
    expect(z.read('нет такой'), isNull);
    final img = z.image('word/media/image1.png');
    expect(img?.mime, 'image/png');
    expect(img!.dataUri, startsWith('data:image/png;base64,'));
  });

  test('без сжатия (stored) — тоже', () {
    final z = OfficeZip.open(_zip({'mimetype': utf8.encode('application/vnd.oasis.opendocument.text')}, store: true));
    expect(z.odfMimeType, 'application/vnd.oasis.opendocument.text');
  });

  test('«ZIP-бомба»: распакованное больше предела — отказ, начало — по readHead', () {
    // 40 МБ нулей сжимаются в ~40 КБ; объявленный размер — настоящий, но
    // предел проверяется по распакованному.
    final bomb = Uint8List(40 * 1024 * 1024);
    final z = OfficeZip.open(_zip({'xl/worksheets/sheet1.xml': bomb}));
    expect(
        () => z.read('xl/worksheets/sheet1.xml'),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.tooLarge)));
    final head = z.readHead('xl/worksheets/sheet1.xml', 1024 * 1024)!;
    expect(head.truncated, isTrue);
    expect(head.bytes.length, 1024 * 1024);
    final small = z.readHead('xl/worksheets/sheet1.xml', 64 * 1024 * 1024)!;
    expect(small.truncated, isTrue, reason: 'предел части — 32 МБ');
    expect(small.bytes.length, OfficeLimits.maxPartBytes);
  });

  test('все прочитанные части вместе — не больше общего предела', () {
    final z = OfficeZip.open(_zip({'a.xml': Uint8List(30 * 1024 * 1024)}));
    var n = 0;
    expect(() {
      for (; n < 10; n++) {
        z.read('a.xml');
      }
    }, throwsA(isA<OfficeDocException>()));
    expect(n, OfficeLimits.maxTotalBytes ~/ (30 * 1024 * 1024));
  });

  test('цели связей: относительно части, от корня, «..»; внешние — как есть', () {
    expect(OfficeZip.resolveTarget('word/document.xml', 'media/image1.png'), 'word/media/image1.png');
    expect(OfficeZip.resolveTarget('ppt/slides/slide1.xml', '../media/image2.jpeg'), 'ppt/media/image2.jpeg');
    expect(OfficeZip.resolveTarget('xl/workbook.xml', '/xl/worksheets/sheet1.xml'), 'xl/worksheets/sheet1.xml');
    expect(OfficeZip.resolveTarget('word/document.xml', '../../../../etc/passwd'), 'etc/passwd');
    final z = OfficeZip.open(_zip({
      '_rels/.rels': utf8.encode('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>'),
      'word/document.xml': utf8.encode('<document/>'),
      'word/_rels/document.xml.rels': utf8.encode(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>'
          '<Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.org/a%20b" TargetMode="External"/>'
          '</Relationships>'),
    }));
    expect(z.officeDocumentPart(), 'word/document.xml');
    final rels = z.rels('word/document.xml');
    expect(rels['rId5']!.target, 'word/media/image1.png');
    expect(rels['rId5']!.isType('image'), isTrue);
    expect(rels['rId6']!.external, isTrue);
    expect(rels['rId6']!.target, 'https://example.org/a%20b');
  });

  test('документ с паролем (OLE), не ZIP, обрезанный файл — понятные ошибки', () {
    final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(600, 0)]);
    expect(() => OfficeZip.open(ole),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.encrypted)));
    expect(() => OfficeZip.open(Uint8List.fromList(utf8.encode('просто текст, не архив, достаточно длинный'))),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.damaged)));
    final good = _zip({'a.xml': utf8.encode('<a/>')});
    expect(() => OfficeZip.open(Uint8List.sublistView(good, 0, good.length - 30)),
        throwsA(isA<OfficeDocException>()));
  });

  test('объявленные в документе сущности не раскрываются', () {
    const xml = '<?xml version="1.0"?><!DOCTYPE d [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;">]>'
        '<d>&b;&amp;&#1046;</d>';
    final z = OfficeZip.open(_zip({'d.xml': utf8.encode(xml)}));
    final text = z.readXml('d.xml')!.rootElement.innerText;
    expect(text, isNot(contains('aaaaaaaaaa')));
    expect(text, contains('&Ж'));
  });

  test('форматы по расширению и MIME-типу', () {
    expect(OfficeFormats.of('Отчёт.DOCX'), OfficeFormat.docx);
    expect(OfficeFormats.of('макрос.xlsm'), OfficeFormat.xlsx);
    expect(OfficeFormats.of('показ.ppsx'), OfficeFormat.pptx);
    expect(OfficeFormats.of('выгрузка.csv'), OfficeFormat.csv);
    expect(OfficeFormats.of('договор.odt'), OfficeFormat.odt);
    expect(OfficeFormats.of('письмо.rtf'), OfficeFormat.rtf);
    expect(OfficeFormats.of('attachment', mimeType: 'application/vnd.oasis.opendocument.spreadsheet; name=x'),
        OfficeFormat.ods);
    // Office 97–2003 — тоже форматы (1.12.x): разбор — по содержимому.
    expect(OfficeFormats.of('старый.doc'), OfficeFormat.doc);
    expect(OfficeFormats.of('выгрузка.XLS'), OfficeFormat.xls);
    expect(OfficeFormats.of('показ.pps'), OfficeFormat.ppt);
    expect(OfficeFormats.of('attachment', mimeType: 'application/msword'), OfficeFormat.doc);
    expect(OfficeFormats.isLegacy('старый.doc'), isTrue);
    expect(OfficeFormats.of('фото.jpg'), isNull);
  });
}

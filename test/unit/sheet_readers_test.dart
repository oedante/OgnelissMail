// Таблицы во вложениях (1.11.x, предпросмотр документов): XLSX, ODS, CSV/TSV
// читаются в листы — по образцам из tool/dev/office_fixtures/sheet_fixtures.py
// и по «враждебным» файлам: огромные повторы и объявленные размеры не стоят
// памяти, испорченный XML и чужие части не роняют разбор.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/csv_reader.dart';
import 'package:ogneliss/services/documents/doc_sheets.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/ods_reader.dart';
import 'package:ogneliss/services/documents/xlsx_reader.dart';

const _dir = 'test/fixtures/office';
const nb = ' ';

Uint8List _fixture(String name) => File('$_dir/$name').readAsBytesSync();

Uint8List _zip(Map<String, String> parts) {
  final a = Archive();
  parts.forEach((name, text) => a.addFile(ArchiveFile.bytes(name, utf8.encode(text))));
  return ZipEncoder().encodeBytes(a);
}

String? _text(DocSheet s, String ref) {
  final r = SheetRef.parse(ref)!;
  return s.cell(r.row, r.col)?.text;
}

// ── XLSX вручную ──

const _ct = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>';
const _rootRels =
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>';
const _wb =
    '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
    '<sheet name="Лист1" sheetId="1" r:id="rId1"/></sheets></workbook>';
const _wbRels =
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" '
    'Target="sharedStrings.xml"/></Relationships>';

String _sheet(String data, {String extra = ''}) =>
    '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '$extra<sheetData>$data</sheetData></worksheet>';

OfficeSheetsDoc _xlsx(String sheetXml, {String? sst, String lang = 'ru'}) => XlsxReader.read(
  OfficeZip.open(
    _zip({
      '[Content_Types].xml': _ct,
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _wb,
      'xl/_rels/workbook.xml.rels': _wbRels,
      'xl/worksheets/sheet1.xml': sheetXml,
      if (sst != null) 'xl/sharedStrings.xml': sst,
    }),
  ),
  lang: lang,
);

// ── ODS вручную ──

const _odsNs =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:config="urn:oasis:names:tc:opendocument:xmlns:config:1.0"';

Uint8List _odsBytes(
  String body, {
  String styles = '',
  String mime = 'application/vnd.oasis.opendocument.spreadsheet',
  String? manifest,
  String? settings,
}) => _zip({
  'mimetype': mime,
  'META-INF/manifest.xml':
      manifest ??
      '<?xml version="1.0"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"/>',
  'content.xml':
      '<?xml version="1.0"?><office:document-content $_odsNs><office:automatic-styles>$styles'
      '</office:automatic-styles><office:body><office:spreadsheet>$body</office:spreadsheet></office:body>'
      '</office:document-content>',
  if (settings != null) 'settings.xml': settings,
});

OfficeSheetsDoc _ods(String body, {String styles = '', String? settings}) => OdsReader.read(
  OfficeZip.open(_odsBytes(body, styles: styles, settings: settings)),
  lang: 'ru',
);

void main() {
  group('XLSX', () {
    late OfficeSheetsDoc doc;
    setUpAll(() => doc = XlsxReader.read(OfficeZip.open(_fixture('sheet_sample.xlsx')), lang: 'ru'));

    test('видимые листы, скрытый — нет', () {
      expect(doc.sheets.map((s) => s.name), ['Отчёт', 'Справочник']);
      expect(doc.truncated, isFalse);
    });

    test('форматы чисел, даты, формула со значением, логическое', () {
      final s = doc.sheets.first;
      expect(_text(s, 'A1'), 'Отчёт по продажам за ноябрь');
      expect(_text(s, 'B3'), '1${nb}234,50');
      expect(_text(s, 'C3'), '13%');
      expect(_text(s, 'D3'), '05.11.2026');
      expect(_text(s, 'B6'), '100${nb}011,93 ₽');
      expect(_text(s, 'A10'), 'ИСТИНА');
      expect(_text(s, 'B10'), '-42,50');
      expect(s.cell(2, 1)!.kind, DocCellKind.number);
      expect(s.cell(0, 0)!.kind, DocCellKind.text);
    });

    test('английский язык — свои разделители и краткая дата', () {
      final en = XlsxReader.read(OfficeZip.open(_fixture('sheet_sample.xlsx')), lang: 'en').sheets.first;
      expect(_text(en, 'B3'), '1,234.50');
      expect(_text(en, 'A10'), 'TRUE');
    });

    test('оформление: жирный, заливка, цвет, «[Red]», перенос', () {
      final s = doc.sheets.first;
      final head = doc.styleOf(s.cell(1, 0)!);
      expect(head.bold, isTrue);
      expect(head.fill, 0xFF1F4E79);
      expect(head.color, 0xFFFFFFFF);
      expect(doc.styleOf(s.cell(5, 1)!).fill, 0xFFFFFF99);
      expect(doc.styleOf(s.cell(5, 2)!).color, 0xFFC00000);
      expect(doc.styleOf(s.cell(9, 1)!).color, 0xFFFF0000);
      expect(doc.styleOf(s.cell(7, 0)!).wrap, isTrue);
      expect(doc.styleOf(s.cell(0, 0)!).fontSize, greaterThan(doc.styleOf(s.cell(2, 0)!).fontSize!));
    });

    test('объединение, ширины, скрытая строка, закрепление', () {
      final s = doc.sheets.first;
      expect(s.merges, hasLength(1));
      expect((s.merges.first.row, s.merges.first.col, s.merges.first.lastRow, s.merges.first.lastCol), (0, 0, 0, 3));
      expect(s.colWidths[0], greaterThan(150));
      expect(s.colWidths[2], 64);
      expect(s.rowHeights[8], 0);
      // Перенос по словам без высоты из файла — строка выше обычной.
      expect(s.rowHeights[7], greaterThan(30));
      expect(s.frozenRows, 2);
      expect(s.frozenCols, 0);
    });

    test('«A1:XFD1048576» в dimension и одна ячейка — ничего не выделяется', () {
      final d = _xlsx(_sheet('<row r="1"><c r="A1"><v>5</v></c></row>', extra: '<dimension ref="A1:XFD1048576"/>'));
      final s = d.sheets.single;
      expect((s.rowCount, s.colCount), (1, 1));
      expect(_text(s, 'A1'), '5');
    });

    test('ячейка далеко за пределами — «показано начало», не память', () {
      final d = _xlsx(
        _sheet(
          '<row r="1"><c r="A1"><v>1</v></c></row>'
          '<row r="1048576"><c r="XFD1048576"><v>2</v></c></row>',
        ),
      );
      final s = d.sheets.single;
      expect(s.rowCount, 1);
      expect(s.truncated, isTrue);
      expect(d.truncated, isTrue);
    });

    test('номер общей строки вне списка — пустая ячейка', () {
      final d = _xlsx(
        _sheet(
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>99</v></c><c r="C1" t="s"><v>x</v></c></row>',
        ),
        sst:
            '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<si><r><t>Пре</t></r><r><rPr><b/></rPr><t>вью</t></r><rPh><t>ふりがな</t></rPh></si></sst>',
      );
      final s = d.sheets.single;
      expect(_text(s, 'A1'), 'Превью');
      expect(s.cell(0, 1), isNull);
      expect(s.cell(0, 2), isNull);
    });

    test('без styles.xml, строки inlineStr и _x000D_, ошибки, ячейки без адреса', () {
      final d = _xlsx(
        _sheet(
          '<row><c t="inlineStr"><is><t>Строка_x000D_\nвторая</t></is></c>'
          '<c t="e"><v>#DIV/0!</v></c><c t="str"><v>формула</v></c><c><v>0.30000000000000004</v></c></row>',
        ),
      );
      final s = d.sheets.single;
      expect(_text(s, 'A1'), 'Строка\nвторая');
      expect(_text(s, 'B1'), '#DIV/0!');
      expect(s.cell(0, 1)!.kind, DocCellKind.error);
      expect(_text(s, 'C1'), 'формула');
      expect(_text(s, 'D1'), '0,3');
    });

    test('испорченный XML листа — книга испорчена; испорченный конец — прочитанное', () {
      expect(
        () => _xlsx('<worksheet><sheetData><row r="1"><c r="A1"<v>1</v></c>'),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.damaged)),
      );
      final d = _xlsx('<worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c></row><row r="2"><c r="A2"<<');
      expect(_text(d.sheets.single, 'A1'), '1');
    });

    test('не книга — damaged', () {
      final z = OfficeZip.open(_zip({'word/document.xml': '<w:document/>'}));
      expect(() => XlsxReader.read(z), throwsA(isA<OfficeDocException>()));
    });

    test('предел ячеек документа', () {
      final b = StringBuffer();
      for (var r = 1; r <= 1200; r++) {
        b.write('<row r="$r">');
        for (var c = 0; c < 256; c++) {
          b.write('<c r="${SheetRef.colName(c)}$r"><v>$c</v></c>');
        }
        b.write('</row>');
      }
      final d = _xlsx(_sheet(b.toString()));
      final s = d.sheets.single;
      expect(s.truncated, isTrue);
      expect(s.rows.fold<int>(0, (n, r) => n + r.length), lessThanOrEqualTo(SheetLimits.maxCells));
    });
  });

  group('ODS', () {
    late OfficeSheetsDoc doc;
    setUpAll(() => doc = OdsReader.read(OfficeZip.open(_fixture('sheet_sample.ods')), lang: 'ru'));

    test('листы, текст ячеек, объединение, скрытая строка', () {
      expect(doc.sheets.map((s) => s.name), ['Отчёт', 'Справочник']);
      final s = doc.sheets.first;
      expect(_text(s, 'A1'), 'Отчёт по продажам за ноябрь');
      expect(_text(s, 'D3'), '05.11.2026');
      expect(_text(s, 'C3'), '13%');
      expect(s.cell(2, 1)!.kind, DocCellKind.number);
      expect(s.merges.single.lastCol, 3);
      expect(s.rowHeights[8], 0);
      expect(s.colWidths[0], greaterThan(150));
    });

    test('оформление и красные отрицательные', () {
      final s = doc.sheets.first;
      final head = doc.styleOf(s.cell(1, 0)!);
      expect(head.bold, isTrue);
      expect(head.fill, 0xFF1F4E79);
      expect(head.color, 0xFFFFFFFF);
      expect(doc.styleOf(s.cell(9, 1)!).color, 0xFFFF0000);
      expect(doc.styleOf(s.cell(7, 0)!).wrap, isTrue);
    });

    test('повторы строк и столбцов в миллион — бесплатно', () {
      final sw = Stopwatch()..start();
      final d = _ods(
        '<table:table table:name="Лист1">'
        '<table:table-column table:number-columns-repeated="16384"/>'
        '<table:table-row><table:table-cell office:value-type="string"><text:p>A</text:p></table:table-cell>'
        '<table:table-cell table:number-columns-repeated="16383"/></table:table-row>'
        '<table:table-row table:number-rows-repeated="1048574"><table:table-cell table:number-columns-repeated="16384"/>'
        '</table:table-row>'
        '<table:table-row><table:table-cell table:number-columns-repeated="3"/>'
        '<table:table-cell><text:p>B<text:s text:c="3"/>C</text:p><text:p>вторая</text:p></table:table-cell></table:table-row>'
        '</table:table>',
      );
      expect(sw.elapsedMilliseconds, lessThan(2000));
      final s = d.sheets.single;
      expect(_text(s, 'A1'), 'A');
      expect((s.rowCount, s.colCount), (1, 1));
      // Ячейка после миллиона пустых строк — за пределом.
      expect(s.truncated, isTrue);
    });

    test('повтор строки с данными и ячеек с данными — в пределах', () {
      final d = _ods(
        '<table:table table:name="T">'
        '<table:table-row table:number-rows-repeated="50000"><table:table-cell table:number-columns-repeated="1000" '
        'office:value-type="float" office:value="7"><text:p>7</text:p></table:table-cell></table:table-row></table:table>',
      );
      final s = d.sheets.single;
      expect(s.colCount, SheetLimits.maxCols);
      expect(s.rowCount, lessThanOrEqualTo(SheetLimits.maxRows));
      expect(s.truncated, isTrue);
      // Одинаковые строки — один список ячеек.
      expect(identical(s.rows[0], s.rows[1]), isTrue);
    });

    test('значения без text:p, скрытый лист, закрепление из settings.xml', () {
      final d = _ods(
        '<table:table table:name="Скрытый" table:style-name="ta2"><table:table-row><table:table-cell><text:p>x</text:p>'
        '</table:table-cell></table:table-row></table:table>'
        '<table:table table:name="Данные"><table:table-row>'
        '<table:table-cell office:value-type="float" office:value="1234.5"/>'
        '<table:table-cell office:value-type="date" office:date-value="2026-11-05"/>'
        '<table:table-cell office:value-type="boolean" office:boolean-value="true"/>'
        '<table:table-cell office:value-type="percentage" office:value="0.25"/>'
        '<table:table-cell office:value-type="time" office:time-value="PT12H30M00S"/>'
        '</table:table-row></table:table>',
        styles:
            '<style:style style:name="ta2" style:family="table"><style:table-properties table:display="false"/>'
            '</style:style>',
        settings:
            '<?xml version="1.0"?><office:document-settings $_odsNs><office:settings>'
            '<config:config-item-set config:name="ooo:view-settings"><config:config-item-map-indexed config:name="Views">'
            '<config:config-item-map-entry><config:config-item config:name="ActiveTable">Данные</config:config-item>'
            '<config:config-item-map-named config:name="Tables"><config:config-item-map-entry config:name="Данные">'
            '<config:config-item config:name="HorizontalSplitMode">2</config:config-item>'
            '<config:config-item config:name="VerticalSplitMode">2</config:config-item>'
            '<config:config-item config:name="HorizontalSplitPosition">1</config:config-item>'
            '<config:config-item config:name="VerticalSplitPosition">1</config:config-item>'
            '</config:config-item-map-entry></config:config-item-map-named></config:config-item-map-entry>'
            '</config:config-item-map-indexed></config:config-item-set></office:settings></office:document-settings>',
      );
      final s = d.sheets.single;
      expect(s.name, 'Данные');
      expect(_text(s, 'A1'), '1234,5');
      expect(_text(s, 'B1'), '05.11.2026');
      expect(_text(s, 'C1'), 'ИСТИНА');
      expect(_text(s, 'D1'), '25%');
      expect(_text(s, 'E1'), '12:30:00');
      expect((s.frozenRows, s.frozenCols), (1, 1));
    });

    test('пароль, чужой mimetype, испорченный content.xml', () {
      final enc = _odsBytes(
        '',
        manifest:
            '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">'
            '<manifest:file-entry manifest:full-path="content.xml"><manifest:encryption-data/></manifest:file-entry>'
            '</manifest:manifest>',
      );
      expect(
        () => OdsReader.read(OfficeZip.open(enc)),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.encrypted)),
      );
      final text = _odsBytes('<table:table/>', mime: 'application/vnd.oasis.opendocument.text');
      expect(
        () => OdsReader.read(OfficeZip.open(text)),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.damaged)),
      );
      final broken = _zip({
        'mimetype': 'application/vnd.oasis.opendocument.spreadsheet',
        'content.xml':
            '<office:document-content $_odsNs><office:body><office:spreadsheet><table:table table:name="a">'
            '<table:table-row><table:table-cell<<<',
      });
      expect(() => OdsReader.read(OfficeZip.open(broken)), throwsA(isA<OfficeDocException>()));
    });

    test('глубокая вложенность и примечания не попадают в текст', () {
      final deep = '<text:span>' * 200;
      final d = _ods(
        '<table:table table:name="a"><table:table-row><table:table-cell><office:annotation><text:p>коммент'
        '</text:p></office:annotation><text:p>$deepтекст${'</text:span>' * 200}</text:p></table:table-cell>'
        '</table:table-row></table:table>',
      );
      expect(_text(d.sheets.single, 'A1'), 'текст');
    });
  });

  group('CSV', () {
    test('UTF-8 с BOM, запятые, многострочное поле и кавычки', () {
      final s = CsvReader.read(_fixture('sheet_utf8.csv'), fileName: 'sheet_utf8.csv').sheets.single;
      expect(s.name, 'sheet_utf8');
      expect(_text(s, 'A1'), 'Имя');
      expect(_text(s, 'C2'), '1,234.50');
      expect(_text(s, 'D2'), 'первая строка\nвторая строка');
      expect(_text(s, 'B3'), 'Санкт-Петербург, центр');
      expect(_text(s, 'D3'), 'кавычки "внутри"');
      expect(s.cell(1, 2)!.kind, DocCellKind.number);
      expect(s.rowHeights[1], greaterThan(30));
    });

    test('Windows-1251, «sep=;», десятичная запятая', () {
      final s = CsvReader.read(_fixture('sheet_cp1251.csv'), fileName: 'sheet_cp1251.csv', lang: 'en').sheets.single;
      expect(_text(s, 'A1'), 'Наименование');
      expect(_text(s, 'C2'), '1 234,56');
      expect(_text(s, 'A3'), 'Ручка «Шариковая»');
      expect(s.cell(1, 3)!.kind, DocCellKind.number);
      expect(s.rowCount, 4);
    });

    test('TSV по расширению', () {
      final s = CsvReader.read(_fixture('sheet_tabs.tsv'), fileName: 'sheet_tabs.tsv').sheets.single;
      expect(_text(s, 'B3'), '2,5');
      expect(_text(s, 'A4'), 'с\tтабом');
    });

    test('разделитель: «;» при запятых в числах, табуляция, одна колонка', () {
      expect(CsvReader.detectDelimiter('a;1,5;2,5\nb;3,5;4,5\n'), ';');
      expect(CsvReader.detectDelimiter('a,b,c\n1,2,3\n'), ',');
      expect(CsvReader.detectDelimiter('a\tb\n1\t2\n'), '\t');
      expect(CsvReader.detectDelimiter('"x;y",b\n"z;w",c\n'), ',');
      expect(CsvReader.detectDelimiter('одна колонка\nещё строка\n'), ',');
    });

    test('кодировки: cp1252 и cp1251 без подсказки, UTF-16', () {
      expect(CsvReader.decode(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9, 0x80])), 'café€');
      expect(CsvReader.decode(Uint8List.fromList([0xC0, 0x31]), lang: 'ru'), 'А1');
      expect(CsvReader.decode(Uint8List.fromList([0xC0, 0x31]), lang: 'de'), 'À1');
      final cp = Uint8List.fromList([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x20, 0xEC, 0xE8, 0xF0]);
      expect(CsvReader.decode(cp), 'Привет мир');
      final u16 = Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00, 0x3B, 0x00, 0x16, 0x04]);
      expect(CsvReader.decode(u16), 'A;Ж');
    });

    test('обрезанный большой файл: последняя неполная строка отброшена', () {
      final b = StringBuffer();
      var i = 0;
      while (b.length < SheetLimits.maxCsvBytes + 1000) {
        b.write('строка $i;значение $i;${i * 2}\n');
        i++;
      }
      final s = CsvReader.read(Uint8List.fromList(utf8.encode(b.toString())), fileName: 'big.csv').sheets.single;
      expect(s.truncated, isTrue);
      expect(s.rowCount, SheetLimits.maxRows);
    });

    test('числа и даты вправо, текст — нет', () {
      for (final v in ['1 234,56', '-12,5', '1,234.56', '15%', '100 ₽', '05.11.2026', '2026-11-05', '12:30']) {
        expect(CsvReader.looksNumeric(v), isTrue, reason: v);
      }
      for (final v in ['+7 912 345-67-89', 'abc', '12 яблок', '']) {
        expect(CsvReader.looksNumeric(v), isFalse, reason: v);
      }
    });
  });

  test('адреса ячеек', () {
    expect(SheetRef.colName(0), 'A');
    expect(SheetRef.colName(25), 'Z');
    expect(SheetRef.colName(26), 'AA');
    expect(SheetRef.colName(16383), 'XFD');
    expect(SheetRef.parse(r'$B$12'), (row: 11, col: 1));
    expect(SheetRef.parse('A0'), isNull);
    expect(SheetRef.parse('ZZZZZ1'), isNull);
    expect(SheetRef.range('C3:A1')!.lastCol, 2);
  });
}

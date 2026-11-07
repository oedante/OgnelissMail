// Книга Excel 97–2003 (.xls, BIFF8) в предпросмотре (1.12.x, просьба
// владельца 04.11.2026): образец LibreOffice и книги, собранные здесь по
// MS-XLS, — строки SST с продолжением в CONTINUE (и сменой кодировки на
// границе), формулы со строкой, RK, закрепление; пароль — «защищён»,
// Excel 5/95 — «старый формат»; испорченные записи — без падения.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/services/documents/cfb_reader.dart';
import 'package:ogneliss/services/documents/doc_sheets.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/xls_reader.dart';

import 'cfb_writer.dart';

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

/// Разделители разрядов (неразрывные пробелы русского формата) — обычным пробелом.
String _t(DocCell? c) => (c?.text ?? '').replaceAll('\u00A0', ' ').replaceAll('\u202F', ' ');

OfficeSheetsDoc _fixture({String lang = 'ru'}) =>
    XlsReader.read(CfbFile.open(File('test/fixtures/office/sheet_sample.xls').readAsBytesSync()), lang: lang);

/// Запись BIFF: тип, длина, данные.
List<int> _rec(int type, List<int> data) => [type & 0xFF, type >> 8, data.length & 0xFF, data.length >> 8, ...data];
List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [..._u16(v & 0xFFFF), ..._u16(v >> 16)];
List<int> _f64(double v) => (ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List();

List<int> _bof(int dt, {int vers = 0x0600}) => _rec(0x0809, [..._u16(vers), ..._u16(dt), ...List.filled(12, 0)]);
List<int> _eof() => _rec(0x000A, const []);

/// XLUnicodeString: длина (2 байта), флаг, знаки.
List<int> _str(String s) {
  final wide = s.codeUnits.any((c) => c > 0xFF);
  return [
    ..._u16(s.length),
    wide ? 1 : 0,
    for (final c in s.codeUnits) ...(wide ? _u16(c) : [c]),
  ];
}

/// Книга: общая часть [globals] и листы [sheets] (имя, записи листа);
/// смещения листов в BoundSheet8 — настоящие.
Uint8List _book(List<int> globals, List<(String, List<int>)> sheets, {bool hiddenFirst = false}) {
  List<int> bound(String name, int pos, bool hidden) =>
      _rec(0x0085, [..._u32(pos), hidden ? 1 : 0, 0, name.length, 1, for (final c in name.codeUnits) ..._u16(c)]);
  var head = <int>[..._bof(0x0005), ...globals];
  for (var i = 0; i < sheets.length; i++) {
    head.addAll(bound(sheets[i].$1, 0, hiddenFirst && i == 0));
  }
  head.addAll(_eof());
  final out = <int>[];
  var pos = head.length;
  final starts = <int>[];
  for (final s in sheets) {
    starts.add(pos);
    pos += _bof(0x0010).length + s.$2.length + 4;
  }
  head = <int>[..._bof(0x0005), ...globals];
  for (var i = 0; i < sheets.length; i++) {
    head.addAll(bound(sheets[i].$1, starts[i], hiddenFirst && i == 0));
  }
  head.addAll(_eof());
  out.addAll(head);
  for (final s in sheets) {
    out
      ..addAll(_bof(0x0010))
      ..addAll(s.$2)
      ..addAll(_eof());
  }
  return Uint8List.fromList(out);
}

Uint8List _xls(Uint8List workbook, {String stream = 'Workbook'}) => (CfbWriter()..add(stream, workbook)).build();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
  });

  test('образец LibreOffice: листы, числа, даты, объединение, оформление', () {
    final d = _fixture();
    expect(d.sheets.map((s) => s.name), ['Отчёт', 'Справочник'], reason: 'скрытый лист не показывается');
    final s = d.sheets.first;
    expect(s.cell(0, 0)!.text, 'Отчёт по продажам за ноябрь');
    expect(d.styleOf(s.cell(0, 0)!).bold, isTrue);
    expect(s.merges.single.lastCol, 3);
    expect(_t(s.cell(2, 1)), '1 234,50');
    expect(s.cell(2, 1)!.kind, DocCellKind.number);
    expect(s.cell(2, 2)!.text, '13%');
    expect(s.cell(2, 3)!.text, '05.11.2026');
    expect(_t(s.cell(5, 1)), '100 011,93 ₽');
    expect(s.cell(9, 0)!.text, 'ИСТИНА', reason: 'сохранённое значение формулы');
    expect(d.styleOf(s.cell(9, 1)!).color, 0xFFFF0000, reason: '[Red] из формата числа');
    expect(d.styleOf(s.cell(1, 0)!).fill, 0xFF1F4E79);
    expect(s.rowHeights[8], 0, reason: 'скрытая строка');
    expect(s.colWidths[0], greaterThan(150));
    expect(_fixture(lang: 'en').sheets.first.cell(2, 1)!.text, '1,234.50');
  });

  test('ручная книга: SST с CONTINUE посреди строки, формула со строкой, RK, закрепление', () {
    // «Кириллица» начинается в SST, обрывается и продолжается в CONTINUE с
    // флагом UTF-16; вторая строка — «сжатая» латиница.
    const s1 = 'Кириллица';
    final sst = [..._u32(3), ..._u32(2), ..._u16(s1.length), 1, for (final c in s1.codeUnits.take(4)) ..._u16(c)];
    final cont = [1, for (final c in s1.codeUnits.skip(4)) ..._u16(c), ..._str('plain')];
    final globals = [..._rec(0x0022, _u16(0)), ..._rec(0x00FC, sst), ..._rec(0x003C, cont)];
    final sheet = [
      ..._rec(0x00FD, [..._u16(0), ..._u16(0), ..._u16(0), ..._u32(0)]),
      ..._rec(0x00FD, [..._u16(0), ..._u16(1), ..._u16(0), ..._u32(1)]),
      // RK: целое 123450 со «÷ 100» → 1234,5.
      ..._rec(0x027E, [..._u16(1), ..._u16(0), ..._u16(0), ..._u32((123450 << 2) | 3)]),
      ..._rec(0x00BD, [
        ..._u16(1),
        ..._u16(1),
        ..._u16(0),
        ..._u32((7 << 2) | 2),
        ..._u16(0),
        ..._u32((8 << 2) | 2),
        ..._u16(2),
      ]),
      ..._rec(0x0203, [..._u16(2), ..._u16(0), ..._u16(0), ..._f64(0.1 + 0.2)]),
      // Формула со строковым результатом и запись String за ней.
      ..._rec(0x0006, [
        ..._u16(2),
        ..._u16(1),
        ..._u16(0),
        0,
        0,
        0,
        0,
        0,
        0,
        0xFF,
        0xFF,
        ..._u16(0),
        ..._u32(0),
        ..._u16(0),
      ]),
      ..._rec(0x0207, _str('итог')),
      ..._rec(0x0205, [..._u16(2), ..._u16(2), ..._u16(0), 0x07, 1]),
      ..._rec(0x0204, [..._u16(3), ..._u16(0), ..._u16(0), ..._str('Метка')]),
      ..._rec(0x007D, [..._u16(2), ..._u16(2), ..._u16(10 * 256), ..._u16(0), ..._u16(1), ..._u16(0)]),
      ..._rec(0x023E, [..._u16(0x0002 | 0x0008), ...List.filled(16, 0)]),
      ..._rec(0x0041, [..._u16(1), ..._u16(1), ..._u16(1), ..._u16(1), 0, 0]),
    ];
    final d = XlsReader.read(CfbFile.open(_xls(_book(globals, [('Лист1', sheet)]))), lang: 'ru');
    final s = d.sheets.single;
    expect(s.name, 'Лист1');
    expect(s.cell(0, 0)!.text, 'Кириллица');
    expect(s.cell(0, 1)!.text, 'plain');
    expect(s.cell(1, 0)!.text, '1234,5');
    expect([s.cell(1, 1)!.text, s.cell(1, 2)!.text], ['7', '8']);
    expect(s.cell(2, 0)!.text, '0,3');
    expect(s.cell(2, 1)!.text, 'итог');
    expect(s.cell(2, 2)!.text, '#DIV/0!');
    expect(s.cell(2, 2)!.kind, DocCellKind.error);
    expect(s.cell(3, 0)!.text, 'Метка');
    expect(s.colWidths[2], 0, reason: 'скрытый столбец');
    expect((s.frozenRows, s.frozenCols), (1, 1));
  });

  test('обфускация XOR — «защищён», Excel 4 — «старый формат», пустая книга 5/95 — без листов', () {
    final encrypted = Uint8List.fromList([..._bof(0x0005), ..._rec(0x002F, List.filled(54, 0)), ..._eof()]);
    expect(() => XlsReader.read(CfbFile.open(_xls(encrypted))), _error(OfficeDocError.encrypted));
    final biff5 = Uint8List.fromList([..._bof(0x0005, vers: 0x0500), ..._eof()]);
    expect(XlsReader.read(CfbFile.open(_xls(biff5, stream: 'Book'))).sheets, isEmpty);
    final biff4 = Uint8List.fromList(_rec(0x0409, List.filled(6, 0)));
    expect(() => XlsReader.read(CfbFile.open(_xls(biff4))), _error(OfficeDocError.legacy));
  });

  // 1.15.1: образцы — LibreOffice (tool/dev/office_fixtures/lo_fixtures.py),
  // своя книга Excel 95 (biff5_fixture.py) и тестовые файлы Apache POI
  // (Apache License 2.0, test/fixtures/office/README.md).
  OfficeSheetsDoc file(String name, {String? password}) {
    final cfb = CfbFile.open(File('test/fixtures/office/$name').readAsBytesSync());
    return password == null ? XlsReader.read(cfb, lang: 'ru') : XlsReader.read(cfb, lang: 'ru', password: password);
  }

  test('книга со стандартным паролем Excel (VelvetSweatshop) открывается без вопросов', () {
    final d = file('velvet.xls');
    expect(d.sheets.map((s) => s.name), ['Смета', 'Склад']);
    final s = d.sheets.first;
    expect(s.cell(1, 0)!.text, 'Кирпич облицовочный');
    expect(s.cell(1, 1)!.text, '1200');
    expect(s.cell(3, 2)!.text, '59400', reason: 'сохранённое значение формулы');
  });

  test('книга с паролем на открытие — «защищена»', () {
    expect(() => file('xls_password.xls'), _error(OfficeDocError.encrypted));
    expect(() => file('poi_password.xls'), _error(OfficeDocError.encrypted));
  });

  test('расшифровка — книги Excel: RC4 и RC4 CryptoAPI (свой пароль из тестов POI)', () {
    final rc4 = file('poi_password.xls', password: 'password');
    expect(rc4.sheets.first.rows.expand((r) => r).map((c) => c.text).join(' '), contains('A ZIP bomb is a variant'));
    final capi = file('poi_cryptoapi.xls', password: 'freedom');
    expect(capi.sheets.first.cell(0, 0)!.text, 'hello there!');
  });

  test('Excel 5/95: кириллица в кодовой странице 1251, формат, жирный, формула со строкой', () {
    final d = file('excel95_cp1251.xls');
    expect(d.sheets.map((s) => s.name), ['Смета', 'Склад']);
    final s = d.sheets.first;
    expect(s.cell(0, 0)!.text, 'Наименование');
    expect(d.styleOf(s.cell(0, 0)!).bold, isTrue);
    expect(s.cell(1, 0)!.text, 'Кирпич облицовочный');
    expect(s.cell(1, 2)!.text, '35,50');
    expect(s.cell(3, 0)!.text, 'Итого по смете');
    expect(d.sheets[1].cell(0, 0)!.text, 'Остатки на 01.11.2026');
  });

  test('Excel 5 из Excel для Mac (POI) и поток «BOOK» заглавными', () {
    final mac = file('poi_excel5.xls');
    expect(mac.sheets.first.cell(0, 0)!.text, 'Sample Excel Worksheet - Numbers and their Squares');
    final caps = file('poi_book_caps.xls');
    expect(caps.sheets.first.cell(0, 0)!.text, startsWith('301. Exposures by Counterparty'));
  });

  test('испорченные записи: огромные количества, смещения вне потока, обрыв', () {
    final globals = [
      // SST обещает 2 млрд строк, а данных — на одну.
      ..._rec(0x00FC, [..._u32(0x7FFFFFFF), ..._u32(0x7FFFFFFF), ..._str('одна')]),
    ];
    final sheet = [
      ..._rec(0x00FD, [..._u16(0), ..._u16(0), ..._u16(0), ..._u32(0)]),
      ..._rec(0x00FD, [..._u16(0), ..._u16(1), ..._u16(0), ..._u32(999999)]),
      // Объединений «65535», столбец 60000, строка за пределом.
      ..._rec(0x00E5, [..._u16(0xFFFF), ..._u16(0), ..._u16(1), ..._u16(0), ..._u16(1)]),
      ..._rec(0x0203, [..._u16(0), ..._u16(60000), ..._u16(0), ..._f64(1)]),
      ..._rec(0x0203, [..._u16(0xFFFF), ..._u16(0), ..._u16(0), ..._f64(1)]),
      ..._rec(0x00BD, [..._u16(1), ..._u16(0xFFF0), ...List.filled(600, 0x41), ..._u16(0xFFFF)]),
      ..._rec(0x007D, [..._u16(0), ..._u16(0xFFFF), ..._u16(0xFFFF), ..._u16(0), ..._u16(0), ..._u16(0)]),
      ..._rec(0x0208, [..._u16(0xFFFF), ...List.filled(14, 0xFF)]),
    ];
    final d = XlsReader.read(CfbFile.open(_xls(_book(globals, [('Лист', sheet)]))));
    final s = d.sheets.single;
    expect(s.cell(0, 0)!.text, 'одна');
    expect(s.cell(0, 1), isNull);
    expect(s.merges.single.lastCol, 1);
    expect(s.colCount, lessThanOrEqualTo(SheetLimits.maxCols));

    // Смещение листа вне потока — лист по порядку частей потока.
    final book = _book(const [], [
      ('А', _rec(0x0204, [..._u16(0), ..._u16(0), ..._u16(0), ..._str('да')])),
    ]);
    final bd = ByteData.sublistView(book);
    var p = 0;
    while (bd.getUint16(p, Endian.little) != 0x0085) {
      p += 4 + bd.getUint16(p + 2, Endian.little);
    }
    bd.setUint32(p + 4, 0x7FFFFFF0, Endian.little);
    expect(XlsReader.read(CfbFile.open(_xls(book))).sheets.single.cell(0, 0)!.text, 'да');

    // Обрыв посреди записи — что успели прочитать.
    final cut = Uint8List.sublistView(book, 0, book.length - 6);
    expect(() => XlsReader.read(CfbFile.open(_xls(cut))), returnsNormally);
    // Нет потока книги, мусор вместо BOF.
    expect(
      () => XlsReader.read(CfbFile.open((CfbWriter()..add('Other', [1, 2, 3])).build())),
      _error(OfficeDocError.damaged),
    );
    expect(
      () => XlsReader.read(CfbFile.open(_xls(Uint8List.fromList(List.filled(64, 0x33))))),
      _error(OfficeDocError.damaged),
    );
  });

  test('скрытый лист в начале: открыт первый видимый', () {
    final sheet = _rec(0x0204, [..._u16(0), ..._u16(0), ..._u16(0), ..._str('видно')]);
    final d = XlsReader.read(
      CfbFile.open(_xls(_book(const [], [('Скрытый', sheet), ('Видимый', sheet)], hiddenFirst: true))),
    );
    expect(d.sheets.map((s) => s.name), ['Видимый']);
    expect(d.activeSheet, 0);
  });
}

// Документ Word 97–2003 (.doc) в предпросмотре (1.12.x, просьба владельца
// 04.11.2026): образец LibreOffice (заголовки, списки с номерами, таблица
// с объединениями, ссылки, картинка, сноска) и документ, собранный здесь
// по MS-DOC: «сжатый» кусок (cp1252) и кусок UTF-16 с кириллицей и полем
// HYPERLINK; пароль — «защищён», Word 6/95 — «старый формат»; испорченные
// структуры — «повреждён» или показ того, что прочиталось, без падения.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/cfb_reader.dart';
import 'package:ogneliss/services/documents/doc_reader.dart';
import 'package:ogneliss/services/documents/office_package.dart';

import 'cfb_writer.dart';

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

/// Документ Word 97 из кусков текста: (текст, «сжатый»). FIB — с нужными
/// полями, таблица кусков — в «1Table»; ни стилей, ни FKP (всё по умолчанию).
Uint8List _doc(List<(String, bool)> pieces, {int ident = 0xA5EC, int flags = 0x0200, List<int>? clx}) {
  final wd = ByteData(0x2000);
  wd.setUint16(0, ident, Endian.little);
  wd.setUint16(2, 0x00C1, Endian.little);
  wd.setUint16(0x0A, flags, Endian.little);
  wd.setUint16(0x20, 14, Endian.little);
  wd.setUint16(0x3E, 22, Endian.little);
  wd.setUint16(0x98, 93, Endian.little);
  var cp = 0;
  var at = 0x400;
  final cps = <int>[0];
  final pcds = <int>[];
  for (final (text, compressed) in pieces) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (compressed) {
        wd.setUint8(at + i, c == 0x201C ? 0x93 : (c == 0x201D ? 0x94 : (c == 0x2013 ? 0x96 : c)));
      } else {
        wd.setUint16(at + i * 2, c, Endian.little);
      }
    }
    pcds.add(compressed ? (at * 2) | 0x40000000 : at);
    at += (text.length * (compressed ? 1 : 2) + 0x100) & ~0xFF;
    cp += text.length;
    cps.add(cp);
  }
  wd.setUint32(0x40 + 3 * 4, cp, Endian.little);
  final plc = ByteData(cps.length * 4 + pcds.length * 8);
  for (var i = 0; i < cps.length; i++) {
    plc.setUint32(i * 4, cps[i], Endian.little);
  }
  for (var i = 0; i < pcds.length; i++) {
    plc.setUint32(cps.length * 4 + i * 8 + 2, pcds[i], Endian.little);
  }
  final table =
      clx ??
      [
        2,
        ...(ByteData(4)..setUint32(0, plc.lengthInBytes, Endian.little)).buffer.asUint8List(),
        ...plc.buffer.asUint8List(),
      ];
  // fcClx / lcbClx — пара 33 в FibRgFcLcb.
  wd.setUint32(0x9A + 33 * 8, 0, Endian.little);
  wd.setUint32(0x9A + 33 * 8 + 4, table.length, Endian.little);
  final w = CfbWriter()
    ..add('WordDocument', wd.buffer.asUint8List())
    ..add(flags & 0x0200 != 0 ? '1Table' : '0Table', table);
  return w.build();
}

void main() {
  test('образец LibreOffice: заголовки, списки, таблица, ссылки, картинка, сноска', () {
    final d = DocReader.read(CfbFile.open(File('test/fixtures/office/text_sample.doc').readAsBytesSync()));
    final h = d.html;
    expect(h, contains('<h1'));
    expect(h, contains('Отчёт о работе отдела'));
    expect(h, contains('font-weight:bold">жирный'));
    expect(h, contains('font-style:italic">курсив'));
    expect(h, contains(RegExp(r'•\s</span>Первый пункт')));
    expect(h, contains(RegExp(r'◦\s</span>Вложенный пункт')));
    expect(h, contains(RegExp(r'1\.1\.\s</span>Сбор данных')));
    expect(h, contains(RegExp(r'2\.\s</span>Выпуск')));
    expect(h, contains('colspan="2"'));
    expect(h, contains('rowspan="2"'));
    expect(h, contains('<a href="https://example.org/">'));
    expect(h, contains('<a href="mailto:info@example.org">'));
    expect(h, isNot(contains('HYPERLINK')), reason: 'код поля скрыт, виден результат');
    expect(h, contains('<img src="cid:img1"'));
    expect(d.images.keys, ['img1']);
    expect(d.images['img1'], startsWith('data:image/png;base64,'));
    expect(h, contains('Данные условные'), reason: 'сноска под чертой');
    expect(h, contains('border-top:1px dashed'), reason: 'разрыв страницы');
    expect(d.truncated, isFalse);
  });

  test('ручной документ: «сжатый» кусок — cp1252, кусок UTF-16 — кириллица, поле — ссылкой', () {
    final d = DocReader.read(
      CfbFile.open(
        _doc([
          ('“Hello” – world\r', true),
          ('Привет, мир\r\x13 HYPERLINK "https://example.org/a b" \x14сайт\x15 и\x0Bперенос\r', false),
        ]),
      ),
    );
    expect(d.html, contains('“Hello” – world'));
    expect(d.html, contains('Привет, мир'));
    expect(d.html, contains('<a href="https://example.org/a%20b">сайт</a>'));
    expect(d.html, contains(' и<br>перенос'));
    expect(d.html, isNot(contains('HYPERLINK')));
  });

  test('пароль, Word 6/95, нет таблицы, испорченная таблица кусков', () {
    final ok = [('Текст\r', false)];
    expect(() => DocReader.read(CfbFile.open(_doc(ok, flags: 0x0300))), _error(OfficeDocError.encrypted));
    expect(() => DocReader.read(CfbFile.open(_doc(ok, ident: 0xA5DC))), _error(OfficeDocError.legacy));
    expect(() => DocReader.read(CfbFile.open(_doc(ok, ident: 0x1234))), _error(OfficeDocError.damaged));
    expect(() => DocReader.read(CfbFile.open(_doc(ok, clx: const [7, 0, 0, 0, 0]))), _error(OfficeDocError.damaged));
    final noTable =
        (CfbWriter()..add(
              'WordDocument',
              Uint8List(0x400)
                ..[0] = 0xEC
                ..[1] = 0xA5
                ..[2] = 0xC1,
            ))
            .build();
    expect(() => DocReader.read(CfbFile.open(noTable)), _error(OfficeDocError.damaged));
  });

  test('куски за пределами потока и огромные CP — без падения и без зависания', () {
    // Кусок «на 2 млрд знаков» с данными за концом потока.
    final plc = ByteData(4 * 2 + 8)
      ..setUint32(0, 0, Endian.little)
      ..setUint32(4, 0x7FFFFFF0, Endian.little)
      ..setUint32(8 + 2, 0x1F00, Endian.little);
    final clx = [
      2,
      ...(ByteData(4)..setUint32(0, plc.lengthInBytes, Endian.little)).buffer.asUint8List(),
      ...plc.buffer.asUint8List(),
    ];
    final sw = Stopwatch()..start();
    final d = DocReader.read(CfbFile.open(_doc([('x\r', false)], clx: clx)));
    expect(sw.elapsed.inSeconds, lessThan(5));
    expect(d.html.length, lessThan(400000));
  });
}

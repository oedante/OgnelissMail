// Презентация PowerPoint 97–2003 (.ppt) в предпросмотре (1.12.x, просьба
// владельца 04.11.2026): образец LibreOffice и презентация, собранная здесь
// по MS-PPT, — каталог правок, текст заполнителей из списка слайдов
// (OutlineTextRefAtom), надпись со своим оформлением, скрытый слайд;
// пароль — «защищён»; петля в цепочке правок, глубокие группы, ссылки за
// пределы потока — без зависания и падения.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/cfb_reader.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/ppt_reader.dart';

import 'cfb_writer.dart';

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [..._u16(v & 0xFFFF), ..._u16((v >> 16) & 0xFFFF)];

/// Запись: версия (0xF — контейнер), экземпляр, тип, данные.
List<int> _rec(int type, List<int> data, {int ver = 0, int inst = 0}) => [
  ..._u16(ver | (inst << 4)),
  ..._u16(type),
  ..._u32(data.length),
  ...data,
];
List<int> _box(int type, List<List<int>> kids, {int inst = 0}) =>
    _rec(type, [for (final k in kids) ...k], ver: 0xF, inst: inst);

List<int> _chars(String s) => _rec(0x0FA0, [for (final c in s.codeUnits) ..._u16(c)]);

/// Фигура: прямоугольник с рамкой (в 1/576 дюйма) и текстом.
List<int> _shape(List<int> anchor, List<List<int>> text, {List<int>? opt, bool placeholder = false}) => _box(0xF004, [
  _rec(0xF00A, [..._u32(1024), ..._u32(0x0A00)], ver: 2, inst: 1),
  if (opt != null) opt,
  _rec(0xF010, [for (final v in anchor) ..._u16(v)]),
  if (placeholder) _box(0xF011, [_rec(0x0BC3, List.filled(8, 0))]),
  _box(0xF00D, text),
]);

List<int> _drawing(List<List<int>> shapes) => _box(0x040C, [
  _box(0xF002, [
    _box(0xF003, [
      _box(0xF004, [
        _rec(0xF009, List.filled(16, 0), ver: 1),
        _rec(0xF00A, [..._u32(1024), ..._u32(5)], ver: 2),
      ]),
      ...shapes,
    ]),
  ]),
]);

/// Презентация: слайд с заголовком и текстом из списка слайдов, надписью и
/// скрытый слайд. [edits] — испортить цепочку правок; [token] — признак
/// шифрования в Current User.
Uint8List _ppt({int token = 0xE391C05F, bool loopEdit = false, bool currentUser = true, List<int>? extraShape}) {
  final doc = _box(0x03E8, [
    _rec(0x03E9, [..._u32(5760), ..._u32(4320), ...List.filled(32, 0)], ver: 1),
    _box(0x0FF0, [
      _rec(0x03F3, [..._u32(2), ..._u32(0), ..._u32(2), ..._u32(256), ..._u32(0)]),
      _rec(0x0F9F, _u32(0)),
      _chars('Заголовок слайда'),
      _rec(0x0F9F, _u32(1)),
      _rec(0x0FA8, 'Line one\rLine two'.codeUnits),
      _rec(0x03F3, [..._u32(3), ..._u32(0), ..._u32(1), ..._u32(257), ..._u32(0)]),
      _rec(0x0F9F, _u32(0)),
      _chars('Скрытый'),
    ]),
    _rec(0x03EA, const []),
  ]);
  // Надпись: красная заливка, текст «Надпись» жирным 20 pt.
  final fill = _rec(
    0xF00B,
    [..._u16(0x0181), ..._u32(0x000000FF), ..._u16(0x01BF), ..._u32(0x00100010)],
    ver: 3,
    inst: 2,
  );
  final styled = [
    _rec(0x0F9F, _u32(4)),
    _chars('Надпись'),
    _rec(0x0FA1, [
      ..._u32(8), ..._u16(0), ..._u32(0), // абзац: без свойств
      ..._u32(8), ..._u32((1 << 0) | (1 << 17)), ..._u16(1), ..._u16(20), // знаки: жирный, 20 pt
    ]),
  ];
  final slide = _box(0x03EE, [
    _rec(0x03EF, List.filled(24, 0), ver: 2),
    _drawing([
      _shape([288, 288, 5472, 1152], [_rec(0x0F9E, _u32(0))], placeholder: true),
      _shape([1440, 288, 5472, 3600], [_rec(0x0F9E, _u32(1))], placeholder: true),
      _shape([3700, 288, 2000, 4200], styled, opt: fill),
      ?extraShape,
    ]),
  ]);
  final hidden = _box(0x03EE, [
    _rec(0x03EF, List.filled(24, 0), ver: 2),
    _rec(0x03F9, [...List.filled(10, 0), ..._u16(0x4), ...List.filled(4, 0)]),
  ]);
  final body = <int>[...doc];
  final offDoc = 0, offSlide = body.length;
  body.addAll(slide);
  final offHidden = body.length;
  body.addAll(hidden);
  final offDir = body.length;
  body.addAll(_rec(0x1772, [..._u32(1 | (3 << 20)), ..._u32(offDoc), ..._u32(offSlide), ..._u32(offHidden)]));
  final offEdit = body.length;
  body.addAll(
    _rec(0x0FF5, [
      ..._u32(256), ..._u16(0), 0, 3, //
      ..._u32(loopEdit ? offEdit : 0), ..._u32(offDir), ..._u32(1), ..._u32(4), ..._u16(1), ..._u16(0),
    ]),
  );
  final cu = [
    ..._rec(0x0FF6, [..._u32(0x14), ..._u32(token), ..._u32(offEdit), ..._u16(0), ..._u16(0x03F4), 3, 0, ..._u16(0)]),
    ..._u32(8),
  ];
  final w = CfbWriter()..add('PowerPoint Document', body);
  if (currentUser) w.add('Current User', cu);
  return w.build();
}

void main() {
  test('образец LibreOffice: слайды, заголовки, маркеры, картинка, фигуры', () {
    final d = PptReader.read(CfbFile.open(File('test/fixtures/office/slides.ppt').readAsBytesSync()));
    expect((d.width, d.height), (720, 540));
    expect(d.slides.length, 6, reason: 'скрытый слайд не показывается');
    String text(DocSlide s) => s.shapes.map((x) => x.plainText).join('\n');
    expect(text(d.slides[0]), contains('Квартальный отчёт'));
    final body = d.slides[1].shapes.firstWhere((s) => s.plainText.contains('Выручка'));
    expect(body.text!.paragraphs.first.bullet?.text, '•');
    expect(body.text!.paragraphs[1].level, 1);
    expect(d.slides[2].shapes.any((s) => s.picture?.image.mime == 'image/png'), isTrue);
    final plate = d.slides[2].shapes.firstWhere((s) => s.plainText == 'Оранжевая плашка');
    expect(plate.fill?.flatColor, 0xFFE06C2A);
    expect(plate.text!.paragraphs.first.runs.first.bold, isTrue);
    expect(text(d.slides[3]), contains('Казань'));
    expect(text(d.slides[4]), contains('В группе'));
    expect(d.slides[5].background?.flatColor, 0xFFFFF4D6);
  });

  test('ручная презентация: текст из списка слайдов, надпись, скрытый слайд', () {
    final d = PptReader.read(CfbFile.open(_ppt()));
    expect(d.slides.length, 1);
    final shapes = d.slides.single.shapes;
    expect(shapes.length, 3);
    final title = shapes[0];
    expect(title.plainText, 'Заголовок слайда');
    expect((title.x, title.y, title.w, title.h), (36, 36, 648, 108));
    expect(title.text!.paragraphs.single.runs.single.size, 44);
    expect(shapes[1].text!.paragraphs.map((p) => p.text), ['Line one', 'Line two']);
    final box = shapes[2];
    expect(box.fill?.flatColor, 0xFFFF0000);
    final run = box.text!.paragraphs.single.runs.single;
    expect((run.text, run.bold, run.size), ('Надпись', true, 20));
  });

  test('пароль — «защищён»; без Current User — по записям потока; петля правок', () {
    expect(() => PptReader.read(CfbFile.open(_ppt(token: 0xF3D1C4DF))), _error(OfficeDocError.encrypted));
    final scanned = PptReader.read(CfbFile.open(_ppt(currentUser: false)));
    expect(scanned.slides.length, 1);
    expect(scanned.slides.single.shapes.first.plainText, isNot(contains('Скрытый')));
    final loop = PptReader.read(CfbFile.open(_ppt(loopEdit: true)));
    expect(loop.slides.single.shapes.first.plainText, 'Заголовок слайда');
  });

  test('глубокие группы, огромные рамки, мусор — без падения', () {
    var g = _shape([0, 0, 100, 100], [_rec(0x0F9F, _u32(4)), _chars('глубоко')]);
    for (var i = 0; i < 200; i++) {
      g = _box(0xF003, [
        _box(0xF004, [
          _rec(0xF009, [..._u32(0), ..._u32(0), ..._u32(100), ..._u32(100)], ver: 1),
        ]),
        g,
      ]);
    }
    final d = PptReader.read(CfbFile.open(_ppt(extraShape: g)));
    expect(d.slides.single.shapes.length, greaterThanOrEqualTo(3));
    expect(d.truncated, isTrue, reason: 'глубже предела — пропущено');

    final huge = _shape([0x7FFF, 0x7FFF, 0x8000, 0x8000], [_rec(0x0F9F, _u32(4)), _chars('x')]);
    expect(() => PptReader.read(CfbFile.open(_ppt(extraShape: huge))), returnsNormally);

    final junk =
        (CfbWriter()
              ..add('PowerPoint Document', List.filled(300, 0x0F))
              ..add('Current User', List.filled(40, 0)))
            .build();
    expect(() => PptReader.read(CfbFile.open(junk)), _error(OfficeDocError.legacy));
  });

  test('заметки докладчика и диаграмма LibreOffice (OLE, картинка EMF) — плашкой', () {
    final d = PptReader.read(CfbFile.open(File('test/fixtures/office/ppt_notes_chart.ppt').readAsBytesSync()));
    final slide = d.slides.single;
    expect(slide.notes, 'Сказать про новых клиентов из Казани');
    final text = slide.shapes.map((s) => s.plainText).join('\n');
    expect(text, contains('Итоги квартала'));
    expect(text, isNot(contains('Сказать про')), reason: 'заметки — не на слайде');
    expect(
      slide.shapes.where((s) => s.embed == DocEmbed.chart).length,
      1,
      reason: 'CompObj: LibreOffice.ChartDocument',
    );
  });
}

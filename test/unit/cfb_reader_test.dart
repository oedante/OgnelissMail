// Составной файл OLE (1.12.x, старые форматы Office в предпросмотре):
// потоки и хранилища читаются в обеих версиях; испорченный нарочно файл
// (петли в FAT и DIFAT, сектор вне файла, обрезанный файл, испорченный
// каталог, огромные размеры) — «повреждён» или «слишком большой», без
// зависания и без лишней памяти.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/cfb_reader.dart';
import 'package:ogneliss/services/documents/office_package.dart';

import 'cfb_writer.dart';

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

Uint8List _bytes(int n, int seed) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + seed) & 0xFF]);

void _u32(Uint8List b, int at, int v) => ByteData.sublistView(b).setUint32(at, v, Endian.little);

void main() {
  for (final v4 in [false, true]) {
    test('потоки и хранилища, версия ${v4 ? 4 : 3}', () {
      final w = CfbWriter(v4: v4)
        ..add('WordDocument', _bytes(9000, 1))
        ..add('1Table', _bytes(700, 2))
        ..add('Пусто', const [])
        ..add('ObjectPool/_1234/\x01Ole', _bytes(20, 3))
        ..add('ObjectPool/_1234/CONTENTS', _bytes(5000, 4));
      final f = CfbFile.open(w.build());
      expect(f.read('WordDocument'), _bytes(9000, 1));
      expect(f.read('1table'), _bytes(700, 2), reason: 'имена — без учёта регистра');
      expect(f.read('Пусто'), isEmpty);
      expect(f.read('ObjectPool/_1234/\x01Ole'), _bytes(20, 3));
      expect(f.read('objectpool/_1234/contents'), _bytes(5000, 4));
      expect(f.read('Нет'), isNull);
      expect(f.entry('ObjectPool')!.isStorage, isTrue);
      expect(f.root.children.map((e) => e.name), containsAll(['WordDocument', '1Table', 'ObjectPool']));
      final head = f.readHead('WordDocument', 100)!;
      expect(head.bytes, _bytes(9000, 1).sublist(0, 100));
      expect(head.truncated, isTrue);
      expect(() => f.read('WordDocument', max: 4096), _error(OfficeDocError.tooLarge));
    });
  }

  test('не составной файл и обрезанный — «повреждён»', () {
    expect(() => CfbFile.open(Uint8List(600)), _error(OfficeDocError.damaged));
    final ok = (CfbWriter()..add('Workbook', _bytes(20000, 5))).build();
    expect(() => CfbFile.open(Uint8List.sublistView(ok, 0, 300)), _error(OfficeDocError.damaged));
    // Обрезан посередине потока: каталог и FAT — в конце файла, их нет.
    expect(() => CfbFile.open(Uint8List.sublistView(ok, 0, 12000)).read('Workbook'), _error(OfficeDocError.damaged));
  });

  test('петля в FAT и сектор вне файла — «повреждён»', () {
    final w = CfbWriter()..add('Workbook', _bytes(20000, 6));
    final b = w.build();
    final start = w.starts['Workbook']!;
    // Второй сектор потока указывает на первый.
    _u32(b, w.fatAt + (start + 1) * 4, start);
    expect(() => CfbFile.open(b).read('Workbook'), _error(OfficeDocError.damaged));
    final c = w.build();
    _u32(c, w.fatAt + (start + 3) * 4, 0x00FFFFFF);
    expect(() => CfbFile.open(c).read('Workbook'), _error(OfficeDocError.damaged));
  });

  test('петля в DIFAT и огромное число секторов FAT', () {
    final w = CfbWriter()..add('Big', _bytes(120000, 7));
    final b = w.build();
    final s = w.starts['Big']!;
    _u32(b, 0x2C, 200);
    _u32(b, 0x44, s);
    _u32(b, 0x48, 1000000);
    final sector = (s + 1) * 512;
    for (var i = 0; i < 127; i++) {
      _u32(b, sector + i * 4, 0xFFFFFFFF);
    }
    _u32(b, sector + 127 * 4, s);
    expect(() => CfbFile.open(b), _error(OfficeDocError.damaged));
    final c = w.build();
    _u32(c, 0x2C, 0x7FFFFFFF);
    expect(() => CfbFile.open(c), _error(OfficeDocError.damaged));
  });

  test('испорченный каталог: петли в дереве, не тот корень, огромный размер', () {
    final w = CfbWriter()
      ..add('A', _bytes(10, 1))
      ..add('B', _bytes(10, 2))
      ..add('C', _bytes(10, 3));
    final b = w.build();
    // Дерево братьев: B — вершина, A слева, C справа. Ссылки назад, на себя
    // и «ребёнок» — корень: каждый виден один раз, обход не зацикливается.
    int at(String name) => w.dirAt + w.ids[name]! * 128;
    _u32(b, at('A') + 0x44, w.ids['B']!);
    _u32(b, at('A') + 0x48, w.ids['A']!);
    _u32(b, at('C') + 0x48, w.ids['B']!);
    _u32(b, at('B') + 0x4C, 0);
    _u32(b, at('C') + 0x4C, 0x7FFFFFFF);
    final f = CfbFile.open(b);
    expect(f.root.children.map((e) => e.name).toList()..sort(), ['A', 'B', 'C']);
    expect(f.read('C'), _bytes(10, 3));

    final c = w.build();
    c[w.dirAt + 0x42] = 2; // корень — не корень
    expect(() => CfbFile.open(c), _error(OfficeDocError.damaged));

    final d = w.build();
    _u32(d, w.dirAt + w.ids['A']! * 128 + 0x78, 0x7FFFFFF0);
    expect(() => CfbFile.open(d).read('A'), _error(OfficeDocError.tooLarge));
    expect(() => CfbFile.open(d).read('A', max: 0x7FFFFFFF), _error(OfficeDocError.damaged));
  });

  test('файл больше предела — «слишком большой»', () {
    final big = Uint8List(OfficeLimits.maxFileBytes + 1);
    big.setRange(0, 8, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    expect(() => CfbFile.open(big), _error(OfficeDocError.tooLarge));
  });
}

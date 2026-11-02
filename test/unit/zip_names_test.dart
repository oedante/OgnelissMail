// Имена файлов в ZIP в кодировке архиватора (1.10.2).
//
// Замечание владельца 02.11.2026: в архиве из «Сжатой папки» русской
// Windows имя «Ермишин …xls» показывалось как «Ŕà¬¨è¨ …» — имя записано в
// CP866 без флага UTF-8, а пакет archive читает его как Latin-1.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/zip_names.dart';
import 'package:ogneliss/features/mail/widgets/zip_view.dart';

// Байты имён — как их пишут архиваторы (проверено по таблицам CP866,
// CP437 и CP1251).
Uint8List _cp866(String s) => Uint8List.fromList([
      for (final r in s.runes)
        if (r < 0x80)
          r
        else if (r >= 0x410 && r <= 0x42F)
          0x80 + (r - 0x410)
        else if (r >= 0x430 && r <= 0x43F)
          0xA0 + (r - 0x430)
        else if (r >= 0x440 && r <= 0x44F)
          0xE0 + (r - 0x440)
        else if (r == 0x401)
          0xF0
        else if (r == 0x451)
          0xF1
        else
          throw ArgumentError(s),
    ]);

Uint8List _cp1251(String s) => Uint8List.fromList([
      for (final r in s.runes)
        if (r < 0x80)
          r
        else if (r >= 0x410 && r <= 0x44F)
          0xC0 + (r - 0x410)
        else if (r == 0x401)
          0xA8
        else if (r == 0x451)
          0xB8
        else
          throw ArgumentError(s),
    ]);

/// Архив ZIP без сжатия с одним файлом: имя — готовыми байтами, без флага
/// UTF-8 (как у «Сжатой папки» Windows).
Uint8List _zip(Uint8List name, List<int> data, {int flags = 0}) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  final crc = getCrc32(data);
  u32(0x04034b50);
  u16(20);
  u16(flags);
  u16(0);
  u16(0);
  u16(0x5B5D); // дата
  u32(crc);
  u32(data.length);
  u32(data.length);
  u16(name.length);
  u16(0);
  b.add(name);
  b.add(data);
  final cdStart = b.length;
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(flags);
  u16(0);
  u16(0);
  u16(0x5B5D);
  u32(crc);
  u32(data.length);
  u32(data.length);
  u16(name.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  b.add(name);
  final cdSize = b.length - cdStart;
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(cdSize);
  u32(cdStart);
  u16(0);
  return b.toBytes();
}

void main() {
  const russian = 'Ермишин Олег Андреевич_Отчёт 2026.xls';

  group('распознавание кодировки имени', () {
    test('CP866 («Сжатая папка» русской Windows)', () {
      expect(decodeZipName(_cp866(russian), lang: 'ru'), russian);
      expect(decodeZipName(_cp866(russian), lang: 'en'), russian, reason: 'и на английском телефоне');
    });

    test('CP1251 (старые архиваторы)', () {
      expect(decodeZipName(_cp1251('Отчёт за октябрь.docx'), lang: 'ru'), 'Отчёт за октябрь.docx');
    });

    test('CP437 (западная Windows): «Résumé» не превращается в «RВsumВ»', () {
      final bytes = Uint8List.fromList([0x52, 0x82, 0x73, 0x75, 0x6D, 0x82, 0x2E, 0x70, 0x64, 0x66]);
      expect(decodeZipName(bytes, lang: 'ru'), 'Résumé.pdf');
      expect(decodeZipName(bytes, lang: 'fr'), 'Résumé.pdf');
    });

    test('UTF-8 с флагом, без флага (macOS) и поле Unicode Path', () {
      final u = Uint8List.fromList(utf8.encode(russian));
      expect(decodeZipName(u, flags: 0x800), russian);
      expect(decodeZipName(u), russian);
      expect(decodeZipName(_cp866('x.txt'), unicodePath: 'Отчёт.txt'), 'Отчёт.txt');
    });

    test('латиница — как есть', () {
      expect(decodeZipName(Uint8List.fromList(utf8.encode('report-2026.pdf'))), 'report-2026.pdf');
    });

    test('имя, уже прочитанное как Latin-1, — исправляется', () {
      final latin1 = String.fromCharCodes(_cp866(russian));
      expect(fixLatin1ZipName(latin1, lang: 'ru'), russian);
      expect(fixLatin1ZipName('Отчёт.pdf'), 'Отчёт.pdf', reason: 'уже Юникод — не трогать');
    });
  });

  group('архив целиком', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('zip_names_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('оглавление — по-русски; файл распаковывается под русским именем', () async {
      final path = '${dir.path}/a.zip';
      File(path).writeAsBytesSync(_zip(_cp866('Папка/$russian'), utf8.encode('данные')));
      expect(readZipRawNames(path)?.single.bytes, _cp866('Папка/$russian'));
      final entries = await PackedArchive.list(path, PackedKind.zip, 'a.zip');
      final file = entries.singleWhere((e) => !e.isDir);
      expect(file.path, 'Папка/$russian');
      expect(file.name, russian);
      final out = await PackedArchive.extract(path, PackedKind.zip, file, '${dir.path}/out');
      expect(out.endsWith(russian), isTrue, reason: out);
      expect(utf8.decode(File(out).readAsBytesSync()), 'данные');
    });

    test('испорченный архив — имена пакета archive, без падения', () {
      final path = '${dir.path}/bad.zip';
      File(path).writeAsBytesSync([1, 2, 3]);
      expect(readZipRawNames(path), isNull);
    });
  });
}

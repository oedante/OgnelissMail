// Архивы внутри приложения (1.8.14, просьба пользователей через владельца
// 29.10.2026: «открытие zip, даже с паролем»).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/zip_view.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('ogneliss_zip'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Archive sample() => Archive()
    ..add(ArchiveFile.string('Отчёт.txt', 'Квартал'))
    ..add(ArchiveFile.string('docs/2025/смета.csv', 'a;b'))
    ..add(ArchiveFile.string('../../evil.txt', 'zip slip'));

  String write(String name, List<int> bytes) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  test('вид архива — по имени файла', () {
    expect(PackedArchive.kindOf('Документы.ZIP'), PackedKind.zip);
    expect(PackedArchive.kindOf('src.tar.gz'), PackedKind.tgz);
    expect(PackedArchive.kindOf('src.tgz'), PackedKind.tgz);
    expect(PackedArchive.kindOf('log.gz'), PackedKind.gz);
    expect(PackedArchive.kindOf('a.7z'), isNull);
    expect(PackedArchive.kindOf('report.pdf'), isNull);
  });

  test('zip: оглавление без распаковки, «..» в имени не выводит за папку', () async {
    final path = write('a.zip', ZipEncoder().encodeBytes(sample()));
    final list = await PackedArchive.list(path, PackedKind.zip, 'a.zip');
    expect(list.map((e) => e.path), containsAll(['Отчёт.txt', 'docs/2025/смета.csv', 'evil.txt']));
    expect(list.any((e) => e.encrypted), isFalse);
    final out = await PackedArchive.extract(
        path, PackedKind.zip, list.firstWhere((e) => e.path == 'evil.txt'), '${dir.path}/x');
    expect(out, '${dir.path}/x${Platform.pathSeparator}evil.txt');
    expect(File(out).readAsStringSync(), 'zip slip');
    final csv = await PackedArchive.extract(
        path, PackedKind.zip, list.firstWhere((e) => e.path.endsWith('смета.csv')), '${dir.path}/x');
    expect(File(csv).readAsStringSync(), 'a;b');
  });

  test('zip с паролем: неверный — нет, верный — да', () async {
    final path = write('p.zip', ZipEncoder(password: 'secret').encodeBytes(sample()));
    final list = await PackedArchive.list(path, PackedKind.zip, 'p.zip');
    expect(list.where((e) => !e.isDir).every((e) => e.encrypted), isTrue);
    await expectLater(PackedArchive.checkPassword(path, list, 'wrong'), throwsA(isA<PackedWrongPassword>()));
    final pw = await PackedArchive.checkPassword(path, list, 'secret');
    final f = list.firstWhere((e) => e.path == 'Отчёт.txt');
    await expectLater(PackedArchive.extract(path, PackedKind.zip, f, '${dir.path}/y'), throwsA(isA<PackedNeedsPassword>()));
    final out = await PackedArchive.extract(path, PackedKind.zip, f, '${dir.path}/y', password: pw);
    expect(File(out).readAsStringSync(), 'Квартал');
  });

  test('русский пароль, записанный архиватором в UTF-8', () async {
    // Архиватор записал пароль байтами UTF-8 — так его и проверяют.
    final path = write('r.zip', ZipEncoder(password: String.fromCharCodes(utf8.encode('Пароль'))).encodeBytes(sample()));
    final list = await PackedArchive.list(path, PackedKind.zip, 'r.zip');
    final pw = await PackedArchive.checkPassword(path, list, 'Пароль');
    final out = await PackedArchive.extract(
        path, PackedKind.zip, list.firstWhere((e) => e.path == 'Отчёт.txt'), '${dir.path}/r',
        password: pw);
    expect(File(out).readAsStringSync(), 'Квартал');
  });

  test('tar.gz и одиночный .gz', () async {
    final tgz = write('s.tar.gz', const GZipEncoder().encodeBytes(TarEncoder().encodeBytes(sample())));
    final list = await PackedArchive.list(tgz, PackedKind.tgz, 's.tar.gz');
    final f = list.firstWhere((e) => e.path == 'docs/2025/смета.csv');
    expect(File(await PackedArchive.extract(tgz, PackedKind.tgz, f, '${dir.path}/t')).readAsStringSync(), 'a;b');

    final gz = write('журнал.log.gz', const GZipEncoder().encodeBytes(utf8.encode('строка')));
    final one = await PackedArchive.list(gz, PackedKind.gz, 'журнал.log.gz');
    expect(one.single.name, 'журнал.log');
    expect(File(await PackedArchive.extract(gz, PackedKind.gz, one.single, '${dir.path}/g')).readAsStringSync(),
        'строка');
  });
}

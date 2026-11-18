// Фото по ссылке (профили Google) — с копией на диске (замечание владельца
// 18.11.2026: «фото было, а потом появляется — каждый раз запрашиваются через
// Google?»). Скачивается один раз; после сворачивания — с диска.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/widgets/common/photo_disk_cache.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('photos');
    PhotoDiskCache.debugDir = dir;
  });
  tearDown(() {
    PhotoDiskCache.debugDir = null;
    PhotoDiskCache.debugClient = null;
    dir.deleteSync(recursive: true);
  });

  const url = 'https://lh3.googleusercontent.com/a/photo=s100';
  final png = Uint8List.fromList(List<int>.generate(64, (i) => i));

  test('скачивается один раз, дальше — с диска', () async {
    var asked = 0;
    PhotoDiskCache.debugClient = MockClient((r) async {
      asked++;
      return http.Response.bytes(png, 200);
    });
    expect(await PhotoDiskCache.bytes(url), png);
    expect(await PhotoDiskCache.bytes(url), png);
    expect(asked, 1);
    expect(File('${dir.path}/${PhotoDiskCache.fileName(url)}').existsSync(), isTrue);
  });

  test('одновременные запросы одной ссылки — один запрос в сеть', () async {
    var asked = 0;
    PhotoDiskCache.debugClient = MockClient((r) async {
      asked++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response.bytes(png, 200);
    });
    final all = await Future.wait([for (var i = 0; i < 5; i++) PhotoDiskCache.bytes(url)]);
    expect(all.every((b) => b != null), isTrue);
    expect(asked, 1);
  });

  test('копия старше недели: показывается сразу, обновляется в фоне; без сети — старая', () async {
    final f = File('${dir.path}/${PhotoDiskCache.fileName(url)}')..writeAsBytesSync(png);
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
    final fresh = Uint8List.fromList([9, 9, 9]);
    var asked = 0;
    PhotoDiskCache.debugClient = MockClient((r) async {
      asked++;
      return http.Response.bytes(fresh, 200);
    });
    expect(await PhotoDiskCache.bytes(url), png, reason: 'старая копия — без ожидания сети');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(asked, 1);
    expect(f.readAsBytesSync(), fresh);

    // Нет сети и нет копии — null (покажется буква).
    PhotoDiskCache.debugClient = MockClient((r) async => throw const SocketException('offline'));
    expect(await PhotoDiskCache.bytes('https://lh3.googleusercontent.com/a/other'), isNull);
  });

  test('ответ не 200 — не сохраняется', () async {
    PhotoDiskCache.debugClient = MockClient((r) async => http.Response('nope', 404));
    expect(await PhotoDiskCache.bytes(url), isNull);
    expect(File('${dir.path}/${PhotoDiskCache.fileName(url)}').existsSync(), isFalse);
  });
}

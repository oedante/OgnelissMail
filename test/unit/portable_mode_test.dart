// Переносная версия для Windows (13.11.2026): папки приложения — в UserData
// рядом с программой; «Документы» и «Загрузки» не подменяются.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/portable_mode_io.dart';

void main() {
  test('Support, Cache, Temp — в папке данных; не Windows — режим выключен', () async {
    final root = Directory.systemTemp.createTempSync('portable').path;
    final p = PortablePaths(root);
    expect(await p.getApplicationSupportPath(), '$root\\Support');
    expect(await p.getApplicationCachePath(), '$root\\Cache');
    expect(await p.getTemporaryPath(), '$root\\Temp');
    expect(Directory('$root\\Support').existsSync(), isTrue);
    PortableMode.init();
    if (!Platform.isWindows) expect(PortableMode.active, isFalse);
  });
}

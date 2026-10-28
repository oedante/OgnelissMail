// test/flutter_test_config.dart
// Общая подготовка всех тестов: строки интерфейса (1.7.3 — файлы
// assets/l10n/<код>.xml) загружаются с диска до тестов — AppLocalizations
// читает их синхронно, а делегат локализации тогда отвечает сразу.

import 'dart:async';
import 'dart:io';

import 'package:ogneliss/l10n/strings_store.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  for (final code in const ['ru', 'en', 'de', 'fr']) {
    final f = File('assets/l10n/$code.xml');
    if (f.existsSync()) StringsStore.put(code, f.readAsStringSync());
  }
  await testMain();
}

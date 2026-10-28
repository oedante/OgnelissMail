// tool/shots/flutter_test_config.dart
// Снимки экранов для проверки вида (1.8.0): настоящие шрифты (Roboto
// приложения, Material Symbols) вместо квадратиков тестового шрифта и
// строки всех языков из assets/l10n.
//
// Запуск (CI, задание «screens»; локально — так же):
//   flutter test tool/shots --update-goldens
// Снимки — tool/shots/out/*.png (в git не попадают).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/l10n/strings_store.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final f in Directory('assets/l10n').listSync().whereType<File>()) {
    if (!f.path.endsWith('.xml')) continue;
    final code = f.uri.pathSegments.last.replaceAll('.xml', '');
    StringsStore.put(code, f.readAsStringSync());
  }
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  await initializeDateFormatting();
  await testMain();
}

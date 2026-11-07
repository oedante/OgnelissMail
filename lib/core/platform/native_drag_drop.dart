// lib/core/platform/native_drag_drop.dart
// Перетаскивание между приложением и системой — пакет super_drag_and_drop
// (1.15.0): вложение из письма наружу (attachment_drag_out.dart) и файлы с
// компьютера в новое письмо (file_drop_zone.dart).

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class NativeDragDrop {
  NativeDragDrop._();

  /// Нативная часть пакета есть в сборке приложения; в `flutter test` её
  /// нет — там виджеты перетаскивания не ставятся.
  static bool enabled = !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Название в «Текстах лицензий».
  static const licensePackage = 'super_native_extensions (Rust)';

  /// Ядро пакета на Rust: крейты из его Cargo.lock вкомпилированы в
  /// библиотеку приложения — их лицензии (MIT, Apache-2.0 и др.) в
  /// «Настройки → О приложении → Тексты лицензий». Файл собирает
  /// tool/dev/rust_licenses.py.
  static void registerLicenses() {
    LicenseRegistry.addLicense(() async* {
      final raw = await rootBundle.loadString('assets/licenses/rust_crates.json');
      for (final (crates, text) in licenseParagraphs(jsonDecode(raw) as Map<String, Object?>)) {
        yield LicenseEntryWithLineBreaks(const [licensePackage], '$crates\n\n$text');
      }
    });
  }

  /// Абзацы для страницы лицензий: крейты с одинаковыми текстами — одним
  /// абзацем («Крейты: …» и тексты).
  @visibleForTesting
  static List<(String, String)> licenseParagraphs(Map<String, Object?> data) {
    final texts = [for (final t in data['texts'] as List) t as String];
    final groups = <String, List<String>>{};
    final bodies = <String, String>{};
    for (final c in (data['crates'] as List).cast<Map<String, Object?>>()) {
      final ids = [for (final i in c['texts'] as List) i as int];
      final name = '${c['name']} ${c['version']}';
      final key = ids.isEmpty ? 'spdx:${c['license']}' : ids.join(',');
      groups.putIfAbsent(key, () => []).add(name);
      bodies[key] = ids.isEmpty
          ? 'License: ${c['license']}. These crates are published without a separate license file; '
              'their source and terms are on https://crates.io.'
          : [for (final i in ids) texts[i]].join('\n\n');
    }
    return [
      for (final e in groups.entries) ('Rust crates: ${e.value.join(', ')}', bodies[e.key]!),
    ];
  }
}

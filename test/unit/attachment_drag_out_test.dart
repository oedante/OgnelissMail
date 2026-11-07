// Перетаскивание вложения наружу (1.15.0, решение владельца 07.11.2026):
// где включено, тип файла для систем Apple, лицензии Rust-крейтов ядра.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/native_drag_drop.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/widgets/attachment_drag_out.dart';

void main() {
  test('платформы: компьютер и Android — да, iPhone — нет, iPad — да', () {
    for (final p in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.android]) {
      expect(AttachmentDragOut.supportedOn(p, tablet: false), isTrue, reason: '$p');
    }
    expect(AttachmentDragOut.supportedOn(TargetPlatform.iOS, tablet: false), isFalse);
    expect(AttachmentDragOut.supportedOn(TargetPlatform.iOS, tablet: true), isTrue);
    expect(AttachmentDragOut.supportedOn(TargetPlatform.fuchsia, tablet: true), isFalse);
    // На сенсорном экране перетаскивание начинает удержание.
    expect(AttachmentDragOut.touchDrag(TargetPlatform.android), isTrue);
    expect(AttachmentDragOut.touchDrag(TargetPlatform.windows), isFalse);
  });

  test('тип файла для Finder и «Файлов» — по расширению, иначе «данные»', () {
    expect(AttachmentDragOut.utiFor('Смета.XLSX'), 'org.openxmlformats.spreadsheetml.sheet');
    expect(AttachmentDragOut.utiFor('скан.pdf'), 'com.adobe.pdf');
    expect(AttachmentDragOut.utiFor('архив.7z'), 'org.7-zip.7-zip-archive');
    expect(AttachmentDragOut.utiFor('без расширения'), 'public.data');
    expect(AttachmentDragOut.utiFor('report.xyz'), 'public.data');
  });

  test('формат: тип MIME из письма, пустой — octet-stream', () {
    const att = EmailAttachment(id: '1', name: 'a.pdf', mimeType: 'Application/PDF', size: 10);
    final f = AttachmentDragOut.formatFor(att);
    expect(f.mimeTypes, ['application/pdf']);
    expect(f.uniformTypeIdentifiers, ['com.adobe.pdf']);
    const bare = EmailAttachment(id: '2', name: 'x', mimeType: '', size: 1);
    expect(AttachmentDragOut.formatFor(bare).mimeTypes, ['application/octet-stream']);
  });

  test('в тестах нативной части нет — перетаскивание выключено', () {
    expect(NativeDragDrop.enabled, isFalse);
  });

  group('лицензии Rust-крейтов', () {
    test('одинаковые тексты — одним абзацем, без файла — название лицензии', () {
      final p = NativeDragDrop.licenseParagraphs({
        'texts': ['MIT text A', 'Apache text'],
        'crates': [
          {'name': 'a', 'version': '1.0.0', 'license': 'MIT', 'texts': [0]},
          {'name': 'b', 'version': '2.0.0', 'license': 'MIT OR Apache-2.0', 'texts': [1]},
          {'name': 'c', 'version': '0.1.0', 'license': 'MIT', 'texts': [0]},
          {'name': 'objc2', 'version': '0.5.2', 'license': 'MIT', 'texts': []},
        ],
      });
      expect(p, hasLength(3));
      expect(p[0].$1, 'Rust crates: a 1.0.0, c 0.1.0');
      expect(p[0].$2, 'MIT text A');
      expect(p[2].$1, contains('objc2 0.5.2'));
      expect(p[2].$2, startsWith('License: MIT.'));
    });

    test('файл в assets соответствует формату и не пуст', () {
      final data = jsonDecode(File('assets/licenses/rust_crates.json').readAsStringSync()) as Map<String, Object?>;
      expect(data['package'], startsWith('super_native_extensions '));
      final paragraphs = NativeDragDrop.licenseParagraphs(data);
      expect(paragraphs.length, greaterThan(10));
      // Ни одного крейта под GPL/LGPL/AGPL.
      for (final c in (data['crates'] as List).cast<Map<String, Object?>>()) {
        expect('${c['license']}', isNot(matches(RegExp(r'\bA?L?GPL'))), reason: '${c['name']}');
      }
    });
  });
}

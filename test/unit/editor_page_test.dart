// test/unit/editor_page_test.dart
// Страница редактора письма (1.6.19): хэш скрипта для CSP считается один
// раз (в изоляте) и передаётся готовым — при каждом открытии «Нового
// сообщения» он не пересчитывается; без готового — считается как раньше.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/widgets/mail_editor.dart';

void main() {
  test('готовый хэш попадает в CSP как есть', () {
    final page = buildMailEditorPage(script: 'console.log(1);', skinCss: '', config: const {}, scriptHash: 'HASH');
    expect(page, contains("script-src 'sha256-HASH'"));
  });

  test('без готового хэша — тот же, что считает editorScriptHash', () {
    const script = 'console.log(2);';
    final page = buildMailEditorPage(script: script, skinCss: '', config: const {});
    expect(page, contains("script-src 'sha256-${editorScriptHash(script)}'"));
  });
}

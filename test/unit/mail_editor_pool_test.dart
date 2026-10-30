// Запасное окно редактора (1.8.12): ключ — язык, тема и подсказка; без
// готового окна «Новое сообщение» идёт обычным путём, а ключ запоминается
// для следующего раза.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/widgets/mail_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ключ: язык, тема и подсказка; стиль ящика и панель в него не входят', () {
    final a = MailEditorPool.keyOf(lang: 'ru', dark: false, placeholder: 'Текст письма');
    expect(a, MailEditorPool.keyOf(lang: 'ru', dark: false, placeholder: 'Текст письма'));
    expect(a, isNot(MailEditorPool.keyOf(lang: 'ru', dark: true, placeholder: 'Текст письма')));
    expect(a, isNot(MailEditorPool.keyOf(lang: 'en', dark: false, placeholder: 'Текст письма')));
  });

  test('нет запасного окна — обычный путь, ключ запомнен', () async {
    SharedPreferences.setMockInitialValues({});
    final key = MailEditorPool.keyOf(lang: 'ru', dark: false, placeholder: '');
    expect(MailEditorPool.take(key, size: const Size(360, 400)), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final saved = (await SharedPreferences.getInstance()).getString('mail_editor_spare_v1');
    expect(saved, contains('"w":360'));
  });
}

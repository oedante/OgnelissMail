// Свои приветствия (21.11.2026): перенос строки сохраняется (до трёх
// строк), порядок меняется, поле вплотную к тексту вставляется через пробел.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/widgets/mail_tag_chips.dart';
import 'package:ogneliss/services/mail/greeting_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('перенос строки сохраняется, пустые строки и края — нет', () {
    expect(CustomGreetingsNotifier.clean('  {время_суток}\r\n\n\n {дата} '), '{время_суток}\n\n{дата}');
    expect(CustomGreetingsNotifier.clean('a\nb\nc\nd'), 'a\nb\nc');
    expect(CustomGreetingsNotifier.clean('\n\nПривет\n\n'), 'Привет');
  });

  test('порядок своих приветствий меняется', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final n = c.read(customGreetingsProvider.notifier);
    final a = await n.add('Первое');
    final b = await n.add('Второе\n{дата}');
    expect(c.read(customGreetingsProvider).items.map((g) => g.text), ['Первое', 'Второе\n{дата}']);
    await n.move(b.id, -1);
    expect(c.read(customGreetingsProvider).items.map((g) => g.id), [b.id, a.id]);
    await n.move(b.id, -1); // уже первое — без изменений
    expect(c.read(customGreetingsProvider).items.first.id, b.id);
    // Сохраняется между запусками.
    final c2 = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c2.dispose);
    expect(c2.read(customGreetingsProvider).items.map((g) => g.id), [b.id, a.id]);
  });

  test('поле вплотную к тексту — через пробел', () {
    final t = TextEditingController(text: 'Добрый день,');
    insertAtCursor(t, '{обращение}');
    expect(t.text, 'Добрый день, {обращение}');
    insertAtCursor(t, '\n');
    insertAtCursor(t, '{дата}');
    expect(t.text, 'Добрый день, {обращение}\n{дата}');
  });
}

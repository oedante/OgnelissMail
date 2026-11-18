// Свои приветствия (18.11.2026): общий список, у ящика — выбранное; одна
// строка; переживают перезапуск.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/mail/greeting_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  test('добавить, выбрать для ящика, изменить, удалить; после перезапуска — то же', () async {
    SharedPreferences.setMockInitialValues({});
    var c = await container();
    final n = c.read(customGreetingsProvider.notifier);
    expect(c.read(customGreetingsProvider).forAccount('acc1'), isNull);

    final a = await n.add('Здравствуйте, {обращение}!');
    final b = await n.add('{время_суток},\n {обращение}! ');
    expect(b.text, '{время_суток}, {обращение}!', reason: 'приветствие — одна строка');
    expect(c.read(customGreetingsProvider).forAccount('acc1')?.id, a.id, reason: 'не выбрано — первое');

    await n.choose('acc1', b.id);
    await c.read(greetingModeProvider.notifier).set('acc1', GreetingMode.custom);
    expect(c.read(customGreetingsProvider).forAccount('acc1')?.id, b.id);
    expect(c.read(customGreetingsProvider).forAccount('acc2')?.id, a.id);

    await n.update(a.id, 'Добрый день, {имя_адресата}!');

    // Перезапуск приложения.
    c = await container();
    final s = c.read(customGreetingsProvider);
    expect(s.items.map((g) => g.text), ['Добрый день, {имя_адресата}!', '{время_суток}, {обращение}!']);
    expect(s.forAccount('acc1')?.id, b.id);
    expect(c.read(greetingModeProvider.notifier).of('acc1'), GreetingMode.custom);

    await c.read(customGreetingsProvider.notifier).remove(b.id);
    expect(c.read(customGreetingsProvider).forAccount('acc1')?.text, 'Добрый день, {имя_адресата}!',
        reason: 'выбранное удалили — первое из оставшихся');
  });

  test('режимы, сохранённые раньше (0–2), читаются как прежде', () async {
    SharedPreferences.setMockInitialValues({'greeting_mode_acc1': 1, 'greeting_mode_acc2': 0});
    final c = await container();
    expect(c.read(greetingModeProvider.notifier).of('acc1'), GreetingMode.hello);
    expect(c.read(greetingModeProvider.notifier).of('acc2'), GreetingMode.off);
    expect(c.read(greetingModeProvider.notifier).of('acc3'), GreetingMode.helloName);
  });
}

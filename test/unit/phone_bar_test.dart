// Нижняя панель телефона по выбору пользователя (2.2.0, просьба 10.11.2026:
// «контакты — в избранное, а „Мой день“ — в нижний бар»): четыре места по
// краям от «Создать», «Меню» не убирается, убранный раздел — в «Избранном»,
// сторона «Меню» на панели и сторона меню согласованы.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/drawer_prefs.dart';
import 'package:ogneliss/widgets/navigation/phone_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> init = const {}]) async {
  SharedPreferences.setMockInitialValues(init);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('по умолчанию — как раньше: «Меню» слева или справа по стороне меню', () async {
    var c = await _container();
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.contacts]);
    c = await _container({'menu_on_right': true});
    expect(c.read(phoneBarProvider), [BarItem.mail, BarItem.calendar, BarItem.contacts, BarItem.menu]);
  });

  test('контакты — в избранное, «Мой день» — на панель', () async {
    final c = await _container();
    expect(c.read(hiddenQuickItemsProvider), contains(DrawerQuickItem.contacts), reason: 'по умолчанию не дублируется');
    final removed = await c.read(phoneBarProvider.notifier).place(3, BarItem.myDay);
    expect(removed, BarItem.contacts);
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.myDay]);
    expect(c.read(hiddenQuickItemsProvider), isNot(contains(DrawerQuickItem.contacts)), reason: 'контакты — в «Избранном»');

    // Сохранилось между запусками.
    final again = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance())]);
    addTearDown(again.dispose);
    expect(again.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.myDay]);
    expect(again.read(hiddenQuickItemsProvider), isNot(contains(DrawerQuickItem.contacts)));
  });

  test('раздел с панели — меняются местами; «Меню» не убирается', () async {
    final c = await _container();
    final n = c.read(phoneBarProvider.notifier);
    expect(await n.place(1, BarItem.calendar), isNull);
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.calendar, BarItem.mail, BarItem.contacts]);
    expect(await n.place(0, BarItem.notes), isNull, reason: 'на место «Меню» — только раздел с панели');
    expect(c.read(phoneBarProvider).first, BarItem.menu);
    await n.place(0, BarItem.mail);
    expect(c.read(phoneBarProvider), [BarItem.mail, BarItem.calendar, BarItem.menu, BarItem.contacts]);
  });

  test('«Меню» на другой половине панели — меню выезжает с той стороны, и наоборот', () async {
    final c = await _container();
    final n = c.read(phoneBarProvider.notifier);
    await n.place(3, BarItem.menu);
    expect(c.read(menuOnRightProvider), isTrue);
    await c.read(menuOnRightProvider.notifier).set(false);
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.contacts]);
    // Не меняли панель — она просто следует стороне меню.
    await n.reset();
    await c.read(menuOnRightProvider.notifier).set(true);
    expect(c.read(phoneBarProvider).last, BarItem.menu);
    expect(n.customized, isFalse);
  });

  test('выключенный раздел заменяется доступным; испорченная запись — по умолчанию', () async {
    final shown = PhoneBarNotifier.visible(
        const [BarItem.menu, BarItem.tasks, BarItem.mail, BarItem.notes], (i) => i != BarItem.tasks && i != BarItem.notes);
    expect(shown, [BarItem.menu, BarItem.calendar, BarItem.mail, BarItem.contacts]);
    expect(PhoneBarNotifier.parse(['mail', 'mail', 'menu', 'notes']), isNull);
    expect(PhoneBarNotifier.parse(['mail', 'calendar', 'notes', 'tasks']), isNull, reason: 'без «Меню»');
    expect(PhoneBarNotifier.parse(['mail', 'menu']), isNull);
    final c = await _container({'phone_bar': ['mail', 'x', 'menu', 'notes']});
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.contacts]);
  });

  test('выбранное место: раздел экрана, экран из меню — «Меню»', () {
    const items = [BarItem.menu, BarItem.mail, BarItem.myDay, BarItem.files];
    expect(barSelected(items, '/mail'), 1);
    expect(barSelected(items, '/mail/conversation/x'), 1);
    expect(barSelected(items, '/my-day'), 2);
    expect(barSelected(items, '/files'), 3);
    expect(barSelected(items, '/notes'), 0);
    expect(barSelected(items, '/calendar'), 0);
  });
}

// Мышь на компьютере (14.11.2026, замечание владельца 14.11.2026: «нет обработки
// двойного клика и не везде есть обработка клика правой клавишей»):
// правая кнопка — то же, что удержание; двойной щелчок не задерживает
// одиночный.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/quick_long_press.dart';

Future<void> _rightClick(WidgetTester tester, Finder f) async {
  final g = await tester.startGesture(tester.getCenter(f), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await g.up();
  await tester.pump();
}

void main() {
  testWidgets('правая кнопка на QuickLongPress — меню, как удержание; место щелчка запоминается', (tester) async {
    var holds = 0;
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuickLongPress(
            onLongPress: () => holds++,
            child: InkWell(
              onTap: () => taps++,
              child: const SizedBox(width: 200, height: 60, child: Text('строка')),
            ),
          ),
        ),
      ),
    ));
    await _rightClick(tester, find.text('строка'));
    expect(holds, 1);
    expect(taps, 0);
    expect(HoldPointer.instance.pressedAt, tester.getCenter(find.text('строка')));

    // Обычный щелчок — по-прежнему касание, не меню.
    await tester.tap(find.text('строка'));
    await tester.pump();
    expect(taps, 1);
    expect(holds, 1);
  });

  testWidgets('строка со своим onSecondaryTap: меню открывается один раз', (tester) async {
    var menus = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuickLongPress(
            onLongPress: () => menus++,
            child: InkWell(
              onTap: () {},
              onSecondaryTap: () => menus++,
              child: const SizedBox(width: 200, height: 60, child: Text('письмо')),
            ),
          ),
        ),
      ),
    ));
    await _rightClick(tester, find.text('письмо'));
    expect(menus, 1);
  });

  testWidgets('SecondaryTap и secondaryAsHold — для ListTile и InkWell', (tester) async {
    var tile = 0;
    var ink = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SecondaryTap(
            onTap: () => tile++,
            child: ListTile(title: const Text('папка'), onTap: () {}, onLongPress: () => tile++),
          ),
          InkWell(
            onTap: () {},
            onSecondaryTapUp: secondaryAsHold(() => ink++),
            child: const SizedBox(height: 48, child: Text('вложение')),
          ),
          // Без действия удержания правая кнопка ничего не делает.
          SecondaryTap(onTap: null, child: ListTile(title: const Text('пусто'), onTap: () {})),
        ]),
      ),
    ));
    await _rightClick(tester, find.text('папка'));
    await _rightClick(tester, find.text('вложение'));
    await _rightClick(tester, find.text('пусто'));
    expect(tile, 1);
    expect(ink, 1);
  });

  test('двойной щелчок: второй по тому же месту в пределах 500 мс', () {
    final t0 = DateTime(2026, 11, 14, 12);
    expect(DoubleClick.isDoubleClick('a', now: t0), isFalse);
    expect(DoubleClick.isDoubleClick('a', now: t0.add(const Duration(milliseconds: 400))), isTrue);
    // Третий щелчок — снова первый.
    expect(DoubleClick.isDoubleClick('a', now: t0.add(const Duration(milliseconds: 600))), isFalse);
    // Другое место — не двойной.
    expect(DoubleClick.isDoubleClick('b', now: t0.add(const Duration(milliseconds: 700))), isFalse);
    // Медленно — не двойной.
    expect(DoubleClick.isDoubleClick('b', now: t0.add(const Duration(milliseconds: 1300))), isFalse);
    // Записи с одинаковыми полями — одно место (ключ строки письма).
    final t1 = t0.add(const Duration(seconds: 5));
    expect(DoubleClick.isDoubleClick(('mail', 'acc', '42'), now: t1), isFalse);
    expect(DoubleClick.isDoubleClick(('mail', 'acc', '42'), now: t1.add(const Duration(milliseconds: 200))), isTrue);
  });
}

// Мышь на компьютере (14.11.2026, замечание владельца 14.11.2026: «нет обработки
// двойного клика и не везде есть обработка клика правой клавишей»):
// правая кнопка — то же, что удержание; двойной щелчок не задерживает
// одиночный.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/widgets/common/quick_long_press.dart';

Future<void> _rightClick(WidgetTester tester, Finder f) => _rightClickAt(tester, tester.getCenter(f));

Future<void> _rightClickAt(WidgetTester tester, Offset at, {Duration hold = Duration.zero}) async {
  final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  if (hold > Duration.zero) await tester.pump(hold);
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

  testWidgets('ссылка в письме: правой кнопкой — «Открыть» и «Копировать»', (tester) async {
    final links = <String>[];
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final mail = buildNativeMailForced(
        '<p><a href="https://example.com/smeta">Смета</a></p><p><a href="mailto:anna@corp.example">Анна</a></p>')!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: MailNativeBody(mail: mail, onLink: (u, _) => links.add(u)))),
    ));
    await tester.pump();
    // Строка во всю ширину — щелчок по самому слову, у левого края.
    Offset word(String text) {
      final f = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().trim() == text).first;
      return tester.getTopLeft(f) + Offset(12, tester.getSize(f).height / 2);
    }

    await _rightClickAt(tester, word('Смета'));
    await tester.pumpAndSettle();
    expect(find.text('Открыть'), findsOneWidget);
    await tester.tap(find.text('Копировать'));
    await tester.pumpAndSettle();
    expect(copied, ['https://example.com/smeta']);
    expect(links, isEmpty, reason: 'копирование не открывает ссылку');

    await _rightClickAt(tester, word('Анна'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Копировать адрес'));
    await tester.pumpAndSettle();
    expect(copied.last, 'anna@corp.example');

    // Кнопку подержали (дольше 100 мс): меню одно — ссылки, без меню
    // выделения текста.
    await _rightClickAt(tester, word('Смета'), hold: const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsNothing);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(links, ['https://example.com/smeta']);
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

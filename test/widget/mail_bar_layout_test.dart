// Панель кнопок письма и горячие клавиши экрана письма (1.10.1).
//
// Замечание владельца 02.11.2026 (nubia, Android 15): письмо открывалось
// пустым, кнопки панели стояли вверху, под строкой состояния. Панель —
// bottomNavigationBar, внутри ReadableWidth (Align): без heightFactor Align
// занимал всю высоту, которую Scaffold даёт панели, — весь экран. Со
// строкой «Ответить…» панель стоит в Column, и этого не было видно.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/keyboard_shortcuts.dart';
import 'package:ogneliss/widgets/common/readable_width.dart';

Widget _bar({double? heightFactor}) => Container(
      key: const ValueKey('bar'),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: ReadableWidth(
          maxWidth: 600,
          fill: true,
          heightFactor: heightFactor,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [Icon(Icons.delete), Icon(Icons.reply)],
          ),
        ),
      ),
    );

void main() {
  testWidgets('панель письма — внизу и высотой по кнопкам (heightFactor: 1)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: const Text('письмо'), bottomNavigationBar: _bar(heightFactor: 1)),
    ));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byKey(const ValueKey('bar')));
    expect(bar.height, lessThan(100), reason: 'высота панели ${bar.height}');
    expect(bar.bottom, closeTo(screen.height, 0.5));
    expect(tester.getTopLeft(find.byIcon(Icons.reply)).dy, greaterThan(screen.height / 2));
    expect(tester.getRect(find.text('письмо')).top, lessThan(screen.height / 2));
  });

  testWidgets('без heightFactor панель занимала весь экран — так было в 1.10.0', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: const Text('письмо'), bottomNavigationBar: _bar()),
    ));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byKey(const ValueKey('bar'))).top, 0);
    expect(tester.getTopLeft(find.byIcon(Icons.reply)).dy, lessThan(screen.height / 4));
  });

  testWidgets('Backspace, Delete, Insert не трогают письмо, пока набирают ответ', (tester) async {
    var archived = 0;
    var deleted = 0;
    var replied = 0;
    final text = TextEditingController(text: 'Добрый день');
    final field = FocusNode();
    final page = FocusNode();
    addTearDown(text.dispose);
    addTearDown(field.dispose);
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
      home: TypingAwareShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => replied++},
        plain: {
          const SingleActivator(LogicalKeyboardKey.backspace): () => archived++,
          const SingleActivator(LogicalKeyboardKey.delete): () => deleted++,
        },
        child: Focus(
          focusNode: page,
          autofocus: true,
          child: Scaffold(body: Column(children: [TextField(controller: text, focusNode: field)])),
        ),
      ),
    ));
    await tester.pump();

    // Строка ответа в фокусе: Backspace стирает букву, письмо не архивируется.
    field.requestFocus();
    await tester.pump();
    text.selection = TextSelection.collapsed(offset: text.text.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(archived, 0);
    expect(text.text, 'Добрый ден');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(deleted, 0);
    // Сочетание с Ctrl работает и из поля.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(replied, 1);

    // Фокус на самом письме: клавиши снова действуют.
    page.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(archived, 1);
    expect(deleted, 1);
  });
}

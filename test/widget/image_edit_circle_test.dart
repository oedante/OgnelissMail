// Обрезка фото для портрета (1.15.1, просьба владельца 07.11.2026): круглый
// режим редактора — квадрат по центру, просмотр в кружках, «Готово»
// возвращает квадратный снимок; без правки — снимок как есть.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/features/compose/screens/image_edit_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 60, 40));
  return Uint8List.fromList(img.encodePng(im));
}

Future<({String name, Uint8List bytes})?> _run(WidgetTester tester, Uint8List bytes) async {
  ({String name, Uint8List bytes})? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await ImageEditScreen.open(context, bytes: bytes, name: 'me.png', circle: true);
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  for (var i = 0; i < 40 && find.text('open').evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(find.text('open'));
  for (var i = 0; i < 20 && find.text('Готово').evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Снимок раскодирован — просмотр в трёх кружках и подсказка для круга.
  for (var i = 0; i < 20 && find.byType(CustomPaint).evaluate().length < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.textContaining('Передвиньте круг'), findsOneWidget);
  expect(find.bySemanticsLabel('Так фото будет выглядеть в ленте, письме и карточке'), findsOneWidget);
  // Переход страницы редактора закончился.
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('Готово'));
  for (var i = 0; i < 40 && !done; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue);
  return result;
}

void main() {
  testWidgets('широкий снимок — квадрат по центру', (tester) async {
    final semantics = tester.ensureSemantics();
    final r = await _run(tester, _png(300, 120));
    expect(r, isNotNull);
    final out = img.decodeImage(r!.bytes)!;
    expect(out.width, out.height, reason: 'портрет — квадрат');
    expect(out.width, 120);
    semantics.dispose();
  });

  testWidgets('квадратный снимок без правки — как есть, а не отмена', (tester) async {
    final semantics = tester.ensureSemantics();
    final bytes = _png(64, 64);
    final r = await _run(tester, bytes);
    expect(r, isNotNull);
    expect(r!.bytes, same(bytes));
    semantics.dispose();
  });
}

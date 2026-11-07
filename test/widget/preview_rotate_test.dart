// Поворот при просмотре (07.11.2026, просьба владельца «в PDF и изображения
// добавить функцию поворота страницы и изображения»): картинка во вложении —
// по кнопке на четверть оборота; PDF — текущая страница или все, растр
// повёрнутой страницы перерисовывается под новый размер.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/features/mail/widgets/pdf_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

Future<void> _settle(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) break;
  }
}

int _turnsOf(WidgetTester tester) => tester.widget<RotatedBox>(find.byType(RotatedBox).first).quarterTurns;

void main() {
  testWidgets('картинка во вложении поворачивается кнопкой', (tester) async {
    final dir = Directory.systemTemp.createTempSync('rot');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/scan.png')..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 20)));
    await tester.pumpWidget(_app(AttachmentPreviewScreen(
      items: [PreviewItem(filePath: file.path, fileName: 'scan.png', sizeBytes: file.lengthSync())],
    )));
    await _settle(tester, () => find.byTooltip('Повернуть').evaluate().isNotEmpty);
    expect(_turnsOf(tester), 0);
    await tester.tap(find.byTooltip('Повернуть'));
    await tester.pump();
    expect(_turnsOf(tester), 1);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Повернуть'));
      await tester.pump();
    }
    expect(_turnsOf(tester), 0, reason: 'четыре поворота — как было');
  });

  testWidgets('PDF: страница и все страницы, растр под новую ширину', (tester) async {
    const ch = MethodChannel('ogneliss/pdf');
    final renders = <(int, int)>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
      final a = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'open':
          return {
            'id': 1,
            'sizes': [
              [600, 800],
              [600, 800],
              [800, 600],
            ],
          };
        case 'render':
          final w = a['width'] as int;
          renders.add((a['index'] as int, w));
          return {'w': 4, 'h': 4, 'pixels': Uint8List(4 * 4 * 4)};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    final c = PdfViewController();
    addTearDown(c.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(Scaffold(body: PdfView(path: '/x.pdf', controller: c, onUnsupported: (_, __) {}))));
    await _settle(tester, () => find.byType(RotatedBox).evaluate().isNotEmpty);
    expect(c.pageCount, 3);

    double heightOf(int page) => tester.getSize(find.byType(DecoratedBox).at(page)).height;
    final first = heightOf(0);
    final width0 = renders.firstWhere((r) => r.$1 == 0).$2;

    // Первая страница (посередине экрана — она) — боком: ниже, растр уже.
    renders.clear();
    c.rotatePage();
    await _settle(tester, () => false); // растр перерисован и раскодирован
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox).first).quarterTurns, 1);
    expect(heightOf(0), lessThan(first));
    expect(renders.firstWhere((r) => r.$1 == 0).$2, (width0 * 600 / 800).round(),
        reason: 'боком: высота растра станет шириной на экране — растр уже');

    // Все страницы: первая — на пол-оборота, остальные — на четверть.
    c.rotateAll();
    await _settle(tester, () => false);
    final turns = [for (final e in find.byType(RotatedBox).evaluate()) (e.widget as RotatedBox).quarterTurns];
    expect(turns.first, 2);
    expect(turns.skip(1), everyElement(1));
  });
}

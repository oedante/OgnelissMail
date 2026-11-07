// Слайды презентации в просмотре вложения (1.11.x, предпросмотр документов,
// план владельца 04.11.2026): список слайдов с номерами и подписью для
// чтения с экрана; касание — на весь экран (листание стрелками, закрытие);
// пустая презентация — сообщение, а не пустой экран.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/widgets/doc_slides_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/pptx_reader.dart';

Future<void> _pump(WidgetTester tester, OfficeSlidesDoc doc, {bool dark = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      darkTheme: AppTheme.darkTheme(1.0),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: DocSlidesView(doc: doc)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final doc = PptxReader.read(OfficeZip.open(File('test/fixtures/office/slides.pptx').readAsBytesSync()));

  testWidgets('список: слайды с номерами и подписью «Слайд N из M»', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, doc);
    expect(find.byType(DocSlideCanvas), findsWidgets);
    expect(find.text('1 / 6'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Слайд 1 из 6')), findsOneWidget);
    expect(find.text('Квартальный отчёт'), findsOneWidget);
    // Строятся только видимые слайды; прокрутка — к последнему.
    expect(find.text('6 / 6'), findsNothing);
    await tester.scrollUntilVisible(find.text('6 / 6'), 400);
    expect(find.text('Спасибо!'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('касание слайда — на весь экран; стрелки листают, «Закрыть» возвращает', (tester) async {
    await _pump(tester, doc);
    await tester.tap(find.text('Квартальный отчёт'));
    await tester.pumpAndSettle();
    expect(find.byType(DocSlidesFullScreen), findsOneWidget);
    expect(find.text('1 / 6'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    expect(find.text('Итоги квартала'), findsOneWidget);
    // Листание пальцем.
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 6'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(DocSlidesFullScreen), findsNothing);
    expect(find.byType(DocSlidesView), findsOneWidget);
  });

  testWidgets('заметки докладчика — под слайдом, с подписью; диаграмма — плашкой', (tester) async {
    final notesDoc = PptxReader.read(
      OfficeZip.open(File('test/fixtures/office/pptx_notes_chart.pptx').readAsBytesSync()),
    );
    await _pump(tester, notesDoc);
    expect(find.text('Заметки докладчика'), findsOneWidget);
    expect(find.text('Сказать про новых клиентов из Казани'), findsOneWidget);
    expect(find.byIcon(AppIcons.bar_chart), findsOneWidget);
    // Без заметок карточки нет.
    await _pump(tester, doc);
    expect(find.text('Заметки докладчика'), findsNothing);
  });

  testWidgets('тёмная тема: слайд остаётся белым', (tester) async {
    await _pump(tester, doc, dark: true);
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(DocSlideCanvas).first, matching: find.byType(ColoredBox)).first,
    );
    expect(box.color, const Color(0xFFFFFFFF));
  });

  testWidgets('пустая презентация — сообщение', (tester) async {
    await _pump(tester, const OfficeSlidesDoc(width: 720, height: 540, slides: []));
    expect(find.text('В документе нет текста.'), findsOneWidget);
  });

  testWidgets('крупный шрифт системы не раздувает текст слайда', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: DocSlidesView(doc: doc)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<RichText>(
      find.descendant(of: find.byType(DocSlideCanvas).first, matching: find.byType(RichText)).first,
    );
    expect(text.textScaler, TextScaler.noScaling);
  });
}

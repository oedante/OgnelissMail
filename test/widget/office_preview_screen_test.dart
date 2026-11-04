// Предпросмотр документов в экране вложений (1.11.x, план владельца
// 04.11.2026): DOCX — текстом (на компьютере и в тестах — виджетами),
// XLSX — сеткой листов, PPTX — слайдами; документ с паролем и старый .doc —
// понятной строкой и кнопкой другого приложения; формат — по содержимому.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/features/mail/widgets/doc_sheet_view.dart';
import 'package:ogneliss/features/mail/widgets/doc_slides_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, PreviewItem item, bool Function() ready) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(1.0),
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AttachmentPreviewScreen(items: [item]),
  ));
  // Разбор идёт в отдельном изоляте — настоящим временем.
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) break;
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('office_preview');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<PreviewItem> copy(WidgetTester tester, String fixture, String name) async {
    final f = File('${dir.path}/$name');
    await tester.runAsync(() => File('test/fixtures/office/$fixture').copy(f.path));
    return PreviewItem(filePath: f.path, fileName: name);
  }

  testWidgets('DOCX — текст документа в приложении', (tester) async {
    final item = await copy(tester, 'text_sample.docx', 'Отчёт.docx');
    await _pump(tester, item, () => find.textContaining('Отчёт о работе отдела').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Отчёт о работе отдела'), findsWidgets);
    expect(find.textContaining('Предпросмотр для этого формата'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('XLSX — сетка с листами', (tester) async {
    final item = await copy(tester, 'sheet_sample.xlsx', 'Смета.xlsx');
    await _pump(tester, item, () => find.byType(DocSheetView).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(DocSheetView), findsOneWidget);
    expect(find.text('Справочник'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PPTX — слайды', (tester) async {
    final item = await copy(tester, 'slides.pptx', 'Доклад.pptx');
    await _pump(tester, item, () => find.byType(DocSlidesView).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(DocSlidesView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('таблица OpenDocument с расширением .xlsx — по содержимому', (tester) async {
    final item = await copy(tester, 'sheet_sample.ods', 'Выгрузка.xlsx');
    await _pump(tester, item, () => find.byType(DocSheetView).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(DocSheetView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('документ с паролем и старый .doc — понятная строка и другое приложение', (tester) async {
    const ole = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    final protected = File('${dir.path}/Зарплата.docx');
    await tester.runAsync(() => protected.writeAsBytes([...ole, ...List.filled(1024, 0)]));
    await _pump(tester, PreviewItem(filePath: protected.path, fileName: 'Зарплата.docx'),
        () => find.textContaining('защищён паролем').evaluate().isNotEmpty);
    expect(find.textContaining('защищён паролем'), findsOneWidget);
    expect(find.text('Открыть во внешнем приложении'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final legacy = File('${dir.path}/Приказ.doc');
    await tester.runAsync(() => legacy.writeAsBytes([...ole, ...List.filled(1024, 0)]));
    await _pump(tester, PreviewItem(filePath: legacy.path, fileName: 'Приказ.doc'),
        () => find.textContaining('старого формата').evaluate().isNotEmpty);
    expect(find.textContaining('старого формата'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«.doc», который на деле RTF, — текстом', (tester) async {
    final item = await copy(tester, 'text_cp1251.rtf', 'Письмо.doc');
    await _pump(tester, item, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('старого формата'), findsNothing);
    expect(find.textContaining('повреждён'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

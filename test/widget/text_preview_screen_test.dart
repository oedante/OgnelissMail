// Предпросмотр .txt и .md в экране вложений (1.14.0, просьба владельца
// 05.11.2026): Markdown — документом, текст — в своей кодировке.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
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
    dir = await Directory.systemTemp.createTemp('text_preview');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<PreviewItem> write(WidgetTester tester, String name, List<int> bytes) async {
    final f = File('${dir.path}/$name');
    await tester.runAsync(() => f.writeAsBytes(bytes));
    return PreviewItem(filePath: f.path, fileName: name);
  }

  testWidgets('Markdown — оформленным документом, без разметки', (tester) async {
    final item = await write(tester, 'README.md',
        utf8.encode('# Порядок работы\n\nСначала **проверьте** отчёт.\n\n- первый шаг\n- второй шаг\n'));
    await _pump(tester, item, () => find.textContaining('Порядок работы').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Порядок работы'), findsWidgets);
    expect(find.textContaining('# Порядок'), findsNothing, reason: 'заголовок, а не исходный текст');
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('первый шаг'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('.txt в Windows-1251 — читается по-русски', (tester) async {
    const text = 'Добрый день! Высылаю отчёт за октябрь.';
    final bytes = [
      for (final c in text.codeUnits)
        c < 0x80 ? c : (c == 0x451 ? 0xB8 : (c >= 0x410 && c <= 0x44F ? c - 0x410 + 0xC0 : 0x3F)),
    ];
    final item = await write(tester, 'Письмо.txt', bytes);
    await _pump(tester, item, () => find.textContaining('Высылаю отчёт').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Добрый день! Высылаю отчёт за октябрь.'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}

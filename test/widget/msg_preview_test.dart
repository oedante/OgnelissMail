// Вложение Outlook .msg в просмотре — письмом, как .eml (1.12.x, просьба
// владельца 05.11.2026): тема, отправитель, получатели, вложения (тело
// рисует окно письма — его текст проверяет msg_reader_test.dart);
// испорченный .msg — понятной строкой.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

import '../unit/msg_builder.dart';

Future<void> _pump(WidgetTester tester, PreviewItem item, bool Function() ready) async {
  await tester.pumpWidget(
    MaterialApp(
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
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
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
    dir = await Directory.systemTemp.createTemp('msg_preview');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('.msg — письмом: тема, отправитель, получатели, вложения', (tester) async {
    final m = MsgBuilder();
    m.props
      ..str(0x0037, 'Счёт на оплату')
      ..str(0x0C1A, 'Бухгалтерия')
      ..str(0x5D01, 'buh@example.org')
      ..time(0x0039, DateTime.utc(2026, 11, 5, 9))
      ..str(0x1000, 'Добрый день! Счёт во вложении.');
    m.recipients.add(
      MsgProps()
        ..i32(0x0C15, 1)
        ..str(0x3001, 'Склад')
        ..str(0x39FE, 'store@example.org'),
    );
    m.attachments.add((
      MsgProps()
        ..i32(0x3705, 1)
        ..str(0x3707, 'Счёт.pdf')
        ..bin(0x3701, utf8Bytes('%PDF-1.4')),
      null,
    ));
    final f = File('${dir.path}/Счёт.msg');
    await tester.runAsync(() => f.writeAsBytes(m.build()));
    final item = PreviewItem(filePath: f.path, fileName: 'Счёт.msg');
    expect(await tester.runAsync(() => AttachmentPreviewScreen.opensInApp(item)), isTrue);
    await _pump(tester, item, () => find.textContaining('Счёт на оплату').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Счёт на оплату'), findsWidgets);
    expect(find.textContaining('buh@example.org'), findsOneWidget);
    expect(find.textContaining('store@example.org'), findsOneWidget);
    expect(find.text('Счёт.pdf'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('испорченный .msg — «повреждён», без падения', (tester) async {
    final f = File('${dir.path}/Письмо.msg');
    await tester.runAsync(
      () => f.writeAsBytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(600, 0)]),
    );
    await _pump(
      tester,
      PreviewItem(filePath: f.path, fileName: 'Письмо.msg', mimeType: 'application/vnd.ms-outlook'),
      () => find.textContaining('повреждён').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('повреждён'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

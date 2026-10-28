// Вложение .eml в просмотре — письмом: тема и отправитель раскодированы,
// внизу — вложения этого письма. Прежде показывался сырой MIME-текст.
// Также: вложенное письмо без расширения (так его отдаёт Exchange)
// узнаётся по заголовкам.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

const _subject = 'Ответ: отчёт по ремонтам';

List<int> _eml() => latin1.encode([
      'Received: from mx.corp.ru by exch01.corp.ru',
      'From: =?koi8-r?B?6dfBzs/XIOnXwc4=?= <ivanov@corp.ru>',
      'To: me@corp.ru',
      'Subject: =?koi8-r?B?79TXxdQ6IM/U3qPUINDPINLFzc/O1MHN?=',
      'Date: Mon, 5 Oct 2026 10:15:00 +0300',
      'MIME-Version: 1.0',
      'Content-Type: multipart/mixed; boundary="mix"',
      '',
      '--mix',
      'Content-Type: text/plain; charset="koi8-r"',
      'Content-Transfer-Encoding: quoted-printable',
      '',
      '=E4=CF=C2=D2=D9=CA =C4=C5=CE=D8!',
      '',
      '--mix',
      'Content-Type: text/plain; charset="utf-8"; name="report.txt"',
      'Content-Transfer-Encoding: base64',
      'Content-Disposition: attachment; filename="report.txt"',
      '',
      base64Encode(utf8.encode('data')),
      '',
      '--mix--',
      '',
    ].join('\r\n'));

Future<void> _pump(WidgetTester tester, PreviewItem item) async {
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
  // Чтение файла и разбор идут настоящим временем.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    if (find.textContaining(_subject).evaluate().isNotEmpty) break;
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eml_preview');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('.eml открывается письмом, а не текстом', (tester) async {
    final f = File('${dir.path}/reply.eml');
    await tester.runAsync(() => f.writeAsBytes(_eml()));

    await _pump(tester, PreviewItem(filePath: f.path, fileName: 'reply.eml'));

    expect(tester.takeException(), isNull);
    expect(find.textContaining(_subject), findsWidgets);
    expect(find.textContaining('ivanov@corp.ru'), findsWidgets);
    expect(find.text('report.txt'), findsOneWidget);
    expect(find.textContaining('koi8-r'), findsNothing);
    expect(find.textContaining('Content-Type'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('письмо без расширения узнаётся по заголовкам', (tester) async {
    final f = File('${dir.path}/attachment');
    await tester.runAsync(() => f.writeAsBytes(_eml()));

    await _pump(tester, PreviewItem(filePath: f.path, fileName: 'Ответ'));

    expect(tester.takeException(), isNull);
    expect(find.textContaining(_subject), findsWidgets);
    expect(find.text('report.txt'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

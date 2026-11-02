// Задача одной фразой (1.10.2): предпросмотр и переход в карточку задачи с
// заполненными полями (встреча одной фразой убрана по просьбе владельца).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/tasks/task_quick_parser.dart';
import 'package:ogneliss/features/tasks/widgets/quick_task_sheet.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('фраза → предпросмотр → «Далее» отдаёт заполненную задачу', (tester) async {
    ParsedTask? got;
    await tester.pumpWidget(_host(QuickTaskPanel(day: DateTime(2026, 11, 2), onNext: (d) => got = d)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quickTaskField')), 'Позвонить Анне завтра в 15 !');
    await tester.pump();
    expect(find.byKey(const ValueKey('quickTaskPreview')), findsOneWidget);
    expect(find.text('Позвонить Анне'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(got, isNotNull);
    expect(got!.title, 'Позвонить Анне');
    expect(got!.important, isTrue);
    expect(got!.due!.day, 3);
    expect(got!.due!.hour, 15);
  });

  testWidgets('без срока во фразе — срок из календаря (день или ячейка)', (tester) async {
    ParsedTask? got;
    final cell = DateTime(2026, 11, 6, 10, 30);
    await tester.pumpWidget(_host(QuickTaskPanel(day: DateTime(2026, 11, 6), due: cell, onNext: (d) => got = d)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quickTaskField')), 'Отчёт');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(got!.title, 'Отчёт');
    expect(got!.due, cell);
  });
}

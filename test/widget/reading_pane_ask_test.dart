// Первый запуск на планшете и компьютере (2.3.0, решение владельца
// 10.11.2026: «спрашивать при первом запуске»): как открывать письма.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/reading_pane.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/adaptive_layout.dart' show PanePosition;
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, Map<String, Object> init) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(init);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(onPressed: () => maybeAskReadingPane(context, ref), child: const Text('лента')),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('первый раз — вопрос; выбор сохраняется; второй раз — без вопроса', (tester) async {
    final c = await _pump(tester, {});
    await tester.tap(find.text('лента'));
    await tester.pumpAndSettle();
    expect(find.text('Как открывать письма?'), findsOneWidget);
    expect(find.textContaining('Область чтения'), findsOneWidget, reason: 'подсказка, где поменять');
    await tester.tap(find.text('Скрыта'));
    await tester.pumpAndSettle();
    expect(c.read(readingPaneProvider), PanePosition.hidden);

    await tester.tap(find.text('лента'));
    await tester.pumpAndSettle();
    expect(find.text('Как открывать письма?'), findsNothing);
  });

  testWidgets('вид уже выбирали — не спрашиваем', (tester) async {
    final c = await _pump(tester, {'reading_pane': 'bottom'});
    await tester.tap(find.text('лента'));
    await tester.pumpAndSettle();
    expect(find.text('Как открывать письма?'), findsNothing);
    expect(c.read(readingPaneProvider), PanePosition.bottom);
  });
}

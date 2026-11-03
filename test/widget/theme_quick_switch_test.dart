// test/widget/theme_quick_switch_test.dart
// Быстрый выбор темы в панели папок (1.10.5, «боковая панель слева занимает
// слишком много места»): в узкой панели подписи не обрезаются («Светл…»),
// а прячутся — остаются значки с подсказкой; в широкой — значки с подписями.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/ui/theme_quick_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, double width) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: const ThemeQuickSwitch()),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('узкая панель — только значки, подписи в подсказках', (t) async {
    await _pump(t, 200);
    expect(find.descendant(of: find.byType(ThemeQuickSwitch), matching: find.byType(Text)), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(4));
    expect(find.bySemanticsLabel('Тёмная'), findsOneWidget);
  });

  testWidgets('широкая — значки с подписями', (t) async {
    await _pump(t, 600);
    expect(find.text('Тёмная'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });
}

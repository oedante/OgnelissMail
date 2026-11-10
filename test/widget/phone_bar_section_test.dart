// «Общие → Нижняя панель» (2.2.0): нажал место — выбрал раздел; убранный
// раздел — в «Избранном»; «Меню» — слева или справа, «Почта» — только
// перестановка.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/drawer_prefs.dart';
import 'package:ogneliss/features/settings/widgets/phone_bar_section.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: SingleChildScrollView(child: PhoneBarSection())),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('контакты → «Мой день»: панель, «Избранное», «Как по умолчанию»', (tester) async {
    final c = await _pump(tester);
    expect(find.text('Нижняя панель'), findsOneWidget);
    expect(find.text('Контакты'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar_reset')), findsNothing, reason: 'панель не меняли');

    await tester.tap(find.byKey(const ValueKey('bar_slot_3')));
    await tester.pumpAndSettle();
    expect(find.text('Раздел на этом месте'), findsOneWidget);
    await tester.tap(find.text('Мой день').last);
    await tester.pumpAndSettle();

    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.myDay]);
    expect(c.read(hiddenQuickItemsProvider), isNot(contains(DrawerQuickItem.contacts)));
    expect(find.byKey(const ValueKey('bar_reset')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bar_reset')));
    await tester.pumpAndSettle();
    expect(c.read(phoneBarProvider), [BarItem.menu, BarItem.mail, BarItem.calendar, BarItem.contacts]);
  });

  testWidgets('место «Меню»: слева или справа; место «Почты»: только перестановка', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('bar_slot_0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('с края панели'), findsOneWidget);
    expect(find.text('Заметки'), findsNothing, reason: 'на место «Меню» раздел не выбирается');
    await tester.tap(find.text('Справа').last);
    await tester.pumpAndSettle();
    expect(c.read(menuOnRightProvider), isTrue, reason: 'меню выезжает справа');
    expect(c.read(phoneBarProvider), [BarItem.mail, BarItem.calendar, BarItem.contacts, BarItem.menu]);

    await tester.tap(find.byKey(const ValueKey('bar_slot_0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('«Почта» всегда на панели'), findsOneWidget);
    expect(find.text('Заметки'), findsNothing, reason: '«Почту» не убрать — только переставить');
    expect(find.text('Поменяются местами'), findsNWidgets(2));
    await tester.tap(find.text('Контакты').last);
    await tester.pumpAndSettle();
    expect(c.read(phoneBarProvider), [BarItem.contacts, BarItem.calendar, BarItem.mail, BarItem.menu]);
  });
}

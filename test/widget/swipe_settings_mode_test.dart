// Свайпы (решение владельца 10.11.2026): по умолчанию — прежняя логика
// (одно действие срабатывает сразу, два — кнопки на выбор); «Короткий и
// длинный свайп» — по желанию в настройках, подписи действий меняются.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/features/settings/screens/swipe_settings_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('по умолчанию — кнопки на выбор; переключатель — короткий и длинный свайп', (t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'s_locale': 'ru'});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
    addTearDown(c.dispose);
    final ru = AppLocalizations(const Locale('ru'));
    await t.pumpWidget(UncontrolledProviderScope(
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
        home: const SwipeSettingsScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).swipeTwoStep, isFalse);
    expect(find.text(ru.tr('swipeFirstAction')), findsNWidgets(2));
    expect(find.text(ru.tr('swipeShortAction')), findsNothing);

    await t.tap(find.descendant(of: find.byKey(const ValueKey('swipe_two_step')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).swipeTwoStep, isTrue);
    expect(sp.getBool('s_swipe_two_step'), isTrue);
    expect(find.text(ru.tr('swipeShortAction')), findsNWidgets(2));
    expect(find.text(ru.tr('swipeLongAction')), findsNWidgets(2));
  });
}

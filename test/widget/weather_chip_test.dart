// Погода в «Моём дне» (2.7.2, просьба пользователей 23.11.2026): город под
// температурой, второй город — строкой ниже.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/my_day/weather_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/weather/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeatherForecast _f(double t, WeatherKind k) =>
    WeatherForecast(now: WeatherPoint(at: DateTime.now(), temp: t, kind: k), min: t - 2, max: t + 2);

Future<void> _pump(WidgetTester t, {bool second = false}) async {
  SharedPreferences.setMockInitialValues({
    'weather_on': true,
    'weather_place_v1': jsonEncode({'name': 'Екатеринбург', 'region': '', 'lat': 56.84, 'lon': 60.61}),
    if (second) 'weather_place2_v1': jsonEncode({'name': 'Москва', 'region': '', 'lat': 55.75, 'lon': 37.62}),
  });
  final sp = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      weatherApprovedProvider.overrideWithValue(true),
      weatherProvider.overrideWith((ref) async => _f(-3, WeatherKind.cloudy)),
      weatherSecondProvider.overrideWith((ref) async => second ? _f(5, WeatherKind.clear) : null),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: Align(alignment: Alignment.topRight, child: WeatherChip())),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('город под температурой', (t) async {
    await _pump(t);
    expect(find.text('−3°'), findsOneWidget);
    expect(find.text('Екатеринбург'), findsOneWidget);
    expect(find.byKey(const ValueKey('weather_city2')), findsNothing);
  });

  testWidgets('второй город — строкой ниже, с температурой', (t) async {
    await _pump(t, second: true);
    expect(find.text('Екатеринбург'), findsOneWidget);
    expect(find.text('+5° Москва'), findsOneWidget);
  });
}

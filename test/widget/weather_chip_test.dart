// Погода в «Моём дне»: город под температурой (2.7.2, просьба пользователей
// 23.11.2026); несколько городов — листанием, с часами каждого в его поясе
// (2.7.2, просьба владельца 24.11.2026).
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

const _ekb = {'name': 'Екатеринбург', 'region': '', 'lat': 56.84, 'lon': 60.61, 'tz': 'Asia/Yekaterinburg'};
const _msk = {'name': 'Москва', 'region': '', 'lat': 55.75, 'lon': 37.62, 'tz': 'Europe/Moscow'};
const _kzn = {'name': 'Казань', 'region': '', 'lat': 55.8, 'lon': 49.11};

Future<void> _pump(WidgetTester t, Widget child, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'weather_on': true, ...prefs});
  final sp = await SharedPreferences.getInstance();
  final temps = {'56.84,60.61': -3.0, '55.75,37.62': 5.0, '55.8,49.11': 1.0};
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      weatherApprovedProvider.overrideWithValue(true),
      weatherForProvider.overrideWith((ref, key) async => _f(temps[key] ?? 0, WeatherKind.cloudy)),
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
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    ),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('город под температурой', (t) async {
    await _pump(t, const Align(alignment: Alignment.topRight, child: WeatherChip()),
        prefs: {'weather_place_v1': jsonEncode(_ekb)});
    expect(find.text('−3°'), findsOneWidget);
    expect(find.text('Екатеринбург'), findsOneWidget);
  });

  testWidgets('один город — часы и значок, без листания', (t) async {
    await _pump(t, const CityClocks(reduceMotion: true), prefs: {'weather_place_v1': jsonEncode(_ekb)});
    expect(find.byKey(const ValueKey('city_pages')), findsNothing);
    expect(find.text('Екатеринбург'), findsOneWidget);
  });

  testWidgets('города до 2.7.2 (первый и второй) — листанием; часы города в его поясе', (t) async {
    await _pump(t, const CityClocks(reduceMotion: true),
        prefs: {'weather_place_v1': jsonEncode(_ekb), 'weather_place2_v1': jsonEncode(_msk)});
    expect(find.byKey(const ValueKey('city_pages')), findsOneWidget);
    expect(find.text('Екатеринбург'), findsOneWidget);
    await t.drag(find.byKey(const ValueKey('city_pages')), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.text('+5°'), findsOneWidget);
    final label = t.widget<Text>(find.byKey(const ValueKey('city_clock_55.75,37.62'))).data!;
    expect(label, startsWith('Москва'));
  });

  test('часы города: пояс есть — время пояса и разница с телефоном; нет — null', () {
    const msk = WeatherPlace(name: 'Москва', lat: 55.75, lon: 37.62, tz: 'Europe/Moscow');
    final at = DateTime.utc(2026, 11, 24, 9, 0);
    expect(cityNow(msk, at), DateTime(2026, 11, 24, 12, 0));
    expect(cityNow(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11), at), isNull);
    const tokyo = WeatherPlace(name: 'Токио', lat: 35.68, lon: 139.69, tz: 'Asia/Tokyo');
    expect(cityNow(tokyo, at), DateTime(2026, 11, 24, 18, 0));
  });

  testWidgets('окно погоды: города, «в виджетах» не больше двух, добавить', (t) async {
    final places = [
      {..._ekb, 'w': true},
      {..._msk, 'w': true},
      _kzn,
    ];
    await _pump(t, Builder(builder: (c) => TextButton(onPressed: () => showWeatherSheet(c), child: const Text('open'))),
        prefs: {'weather_places_v2': jsonEncode(places)});
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('weather_place_55.8,49.11')), findsOneWidget);
    // Третий город в виджеты не ставится, пока там два.
    final kznWidget = t.widget<IconButton>(find.byKey(const ValueKey('weather_widget_55.8,49.11')));
    expect(kznWidget.onPressed, isNull);
    expect(find.text('В виджетах — не больше двух городов'), findsOneWidget);
    expect(find.byKey(const ValueKey('weather_add_city')), findsOneWidget);
  });

  // 2.7.5 (замечание владельца 27.11.2026): сверху окна — не всегда первый
  // город; «в виджетах» — заметно.
  testWidgets('окно погоды: открывается на пролистанном городе, нажатие — другой город; «в виджетах» залито', (t) async {
    final places = [
      {..._ekb, 'w': true},
      _msk,
      _kzn,
    ];
    await _pump(t,
        Builder(builder: (c) => TextButton(onPressed: () => showWeatherSheet(c, placeKey: '55.75,37.62'), child: const Text('open'))),
        prefs: {'weather_places_v2': jsonEncode(places)});
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // Заголовок — Москва (первая строка окна — titleLarge).
    Text title() => t.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == Theme.of(t.element(find.byType(Scaffold))).textTheme.titleLarge?.fontSize));
    expect(title().data, 'Москва');
    await t.tap(find.byKey(const ValueKey('weather_place_55.8,49.11')));
    await t.pumpAndSettle();
    expect(title().data, 'Казань');
    // «В виджетах» — залитая кнопка (filledTonal), остальные — обычные.
    expect(find.descendant(of: find.byKey(const ValueKey('weather_widget_56.84,60.61')), matching: find.byType(IconButton)),
        findsNothing, reason: 'сам ключ — у IconButton');
    final ekb = t.widget<IconButton>(find.byKey(const ValueKey('weather_widget_56.84,60.61')));
    final kzn = t.widget<IconButton>(find.byKey(const ValueKey('weather_widget_55.8,49.11')));
    expect(ekb.isSelected, isTrue);
    expect(kzn.isSelected, isFalse);
    expect(kzn.onPressed, isNotNull, reason: 'в виджетах один город — можно добавить');
  });
}


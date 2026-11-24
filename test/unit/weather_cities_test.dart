// Несколько городов погоды (2.7.2, просьба владельца 24.11.2026): часы и
// погода до пяти городов в «Моём дне», в виджетах — отмеченные (не больше
// двух); часовой пояс — от сервера поиска (GeoNames).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/home_widget_service.dart';
import 'package:ogneliss/services/weather/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ekb = WeatherPlace(name: 'Екатеринбург', lat: 56.84, lon: 60.61);
const _msk = WeatherPlace(name: 'Москва', lat: 55.75, lon: 37.62);
const _kzn = WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11);
const _spb = WeatherPlace(name: 'Санкт-Петербург', lat: 59.94, lon: 30.31);
const _nsk = WeatherPlace(name: 'Новосибирск', lat: 55.03, lon: 82.92);
const _sab = WeatherPlace(name: 'Сабетта', lat: 71.27, lon: 72.06);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('города до 2.7.2 — первым и вторым, оба в виджетах', () async {
    await prefs.setBool('weather_on', true);
    await prefs.setString(WeatherSettingsNotifier.kPlace, jsonEncode(_ekb.toJson()));
    await prefs.setString(WeatherSettingsNotifier.kSecond, jsonEncode(_msk.toJson()));
    final s = WeatherSettingsNotifier(prefs).state;
    expect([for (final p in s.places) p.name], ['Екатеринбург', 'Москва']);
    expect([for (final p in s.widgetPlaces) p.name], ['Екатеринбург', 'Москва']);
    expect(s.active, isTrue);
  });

  test('до пяти городов; в виджеты — первые два, третий не ставится', () async {
    final n = WeatherSettingsNotifier(prefs);
    await n.setPlace(_ekb);
    expect(await n.addPlace(_msk), isTrue);
    expect(await n.addPlace(_kzn), isTrue);
    expect(await n.addPlace(_msk), isFalse, reason: 'уже есть');
    expect(await n.addPlace(_spb), isTrue);
    expect(await n.addPlace(_nsk), isTrue);
    expect(await n.addPlace(_sab), isFalse, reason: 'больше пяти нельзя');
    expect(n.state.places, hasLength(5));
    expect([for (final p in n.state.widgetPlaces) p.name], ['Екатеринбург', 'Москва']);
    expect(await n.setInWidgets(_kzn.key, true), isFalse);
    expect(await n.setInWidgets(_msk.key, false), isTrue);
    expect(await n.setInWidgets(_kzn.key, true), isTrue);
    expect([for (final p in n.state.widgetPlaces) p.name], ['Екатеринбург', 'Казань']);

    // После перезапуска — то же.
    final again = WeatherSettingsNotifier(prefs).state;
    expect(again.places, hasLength(5));
    expect(again.widgetKeys, {_ekb.key, _kzn.key});
  });

  test('сделать первым, убрать первый; кэш убранного стирается', () async {
    final n = WeatherSettingsNotifier(prefs);
    await n.setPlace(_ekb);
    await n.addPlace(_msk);
    await n.addPlace(_kzn);
    await prefs.setString('${WeatherCache.cityPrefix}${_kzn.key}', '{}');
    await n.makeFirst(_kzn.key);
    expect(n.state.place?.name, 'Казань');
    expect(WeatherSettingsNotifier.cacheKeyFor(n.state, _kzn), WeatherCache.key);
    expect(WeatherSettingsNotifier.cacheKeyFor(n.state, _ekb), '${WeatherCache.cityPrefix}${_ekb.key}');
    await n.removePlace(_kzn.key);
    expect(n.state.place?.name, 'Екатеринбург');
    expect(prefs.getString('${WeatherCache.cityPrefix}${_kzn.key}'), isNull);
  });

  test('пояс от сервера поиска; города без пояса — дополняются поиском по имени', () async {
    final found = WeatherApi.parseNominatim(jsonEncode([
      {'name': 'Сабетта', 'display_name': 'Сабетта, Ямало-Ненецкий АО, Россия', 'lat': '71.2700', 'lon': '72.0600', 'timezone': 'Asia/Yekaterinburg'},
      {'name': 'Бад', 'display_name': 'Бад', 'lat': '1', 'lon': '2', 'timezone': 'Not a zone!'},
    ]));
    expect(found.first.tz, 'Asia/Yekaterinburg');
    expect(found.last.tz, isNull);

    final n = WeatherSettingsNotifier(prefs);
    await n.setPlace(_ekb);
    await n.addPlace(_sab);
    await n.fillTimeZones((name) async => name == 'Сабетта' ? found : const []);
    expect(n.state.byKey(_sab.key)?.tz, 'Asia/Yekaterinburg');
    expect(n.state.place?.tz, isNull, reason: 'не нашёлся — без часов');
    expect(WeatherSettingsNotifier(prefs).state.byKey(_sab.key)?.tz, 'Asia/Yekaterinburg');
  });

  test('виджет — погода городов «в виджетах», по порядку списка', () async {
    final n = WeatherSettingsNotifier(prefs);
    await n.setPlace(_ekb);
    await n.addPlace(_msk);
    await n.addPlace(_kzn);
    await n.setInWidgets(_msk.key, false);
    await n.setInWidgets(_kzn.key, true);
    final now = DateTime.now().toUtc();
    String body(double t) => jsonEncode({
          'properties': {
            'timeseries': [
              {
                'time': DateTime.utc(now.year, now.month, now.day, now.hour).toIso8601String(),
                'data': {
                  'instant': {
                    'details': {'air_temperature': t}
                  },
                  'next_1_hours': {
                    'summary': {'symbol_code': 'cloudy'}
                  }
                }
              }
            ]
          }
        });
    for (final (p, t) in [(_ekb, -3.0), (_msk, 5.0), (_kzn, 1.0)]) {
      await WeatherCache.write(prefs,
          key: WeatherSettingsNotifier.cacheKeyFor(n.state, p),
          lat: WeatherApi.round2(p.lat),
          lon: WeatherApi.round2(p.lon),
          expires: DateTime.now().add(const Duration(hours: 1)),
          body: body(t),
          fetched: DateTime.now());
    }
    final line = HomeWidgetService.weatherLine(prefs, DateTime.now())!;
    expect(line, contains('Екатеринбург'));
    expect(line, contains('Казань'));
    expect(line, isNot(contains('Москва')));
    expect(line.indexOf('Екатеринбург'), lessThan(line.indexOf('Казань')));
  });
}

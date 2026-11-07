// Погода в «Моём дне» (1.15.1): разбор ответов MET Norway и Nominatim, кэш
// по Expires и If-Modified-Since, запрет организацией, округление
// координат и User-Agent по условиям сервисов.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:ogneliss/services/weather/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _met(DateTime start) {
  Map<String, Object> point(int h, double t, String symbol) => {
        'time': start.add(Duration(hours: h)).toUtc().toIso8601String(),
        'data': {
          'instant': {
            'details': {'air_temperature': t, 'wind_speed': 3.1},
          },
          'next_1_hours': {
            'summary': {'symbol_code': symbol},
            'details': {'precipitation_amount': 0.0},
          },
        },
      };
  return jsonEncode({
    'type': 'Feature',
    'properties': {
      'meta': {'updated_at': start.toUtc().toIso8601String()},
      'timeseries': [
        point(0, -1.4, 'clearsky_night'),
        point(1, 0.2, 'fair_day'),
        point(2, 2.6, 'lightrainshowers_day'),
        point(3, 4.4, 'heavyrainandthunder'),
        point(4, 3.0, 'sleet'),
        point(30, 9.0, 'snow'),
      ],
    },
  });
}

void main() {
  test('коды значков MET Norway → вид погоды', () {
    expect(WeatherApi.kindOf('clearsky_day'), WeatherKind.clear);
    expect(WeatherApi.kindOf('fair_night'), WeatherKind.fair);
    expect(WeatherApi.kindOf('partlycloudy_polartwilight'), WeatherKind.partlyCloudy);
    expect(WeatherApi.kindOf('cloudy'), WeatherKind.cloudy);
    expect(WeatherApi.kindOf('fog'), WeatherKind.fog);
    expect(WeatherApi.kindOf('lightrainshowers_day'), WeatherKind.lightRain);
    expect(WeatherApi.kindOf('rain'), WeatherKind.rain);
    expect(WeatherApi.kindOf('heavyrain'), WeatherKind.heavyRain);
    expect(WeatherApi.kindOf('lightsleet'), WeatherKind.sleet);
    expect(WeatherApi.kindOf('heavysnowshowers_night'), WeatherKind.snow);
    expect(WeatherApi.kindOf('rainandthunder'), WeatherKind.thunder);
    expect(WeatherApi.kindOf('something_new'), isNull);
  });

  test('прогноз: сейчас, сегодня наименьшая и наибольшая, ближайшие часы', () {
    final start = DateTime(2026, 11, 7, 10);
    final f = WeatherApi.parseMet(_met(start), now: start.add(const Duration(minutes: 70)))!;
    expect(f.now.temp, 0.2, reason: 'последняя точка не позже текущего времени');
    expect(f.now.kind, WeatherKind.fair);
    expect(f.min, -1.4);
    expect(f.max, 4.4, reason: 'завтрашние +9 — не сегодня');
    expect(f.hours.first.kind, WeatherKind.lightRain);
    expect(WeatherApi.parseMet('not json'), isNull);
    expect(WeatherApi.parseMet('{"properties":{"timeseries":[]}}'), isNull);
  });

  test('поиск города: название, область и страна; координаты до сотых', () {
    const body = '[{"lat":"55.7505412","lon":"37.6174782","name":"Москва",'
        '"display_name":"Москва, Центральный федеральный округ, Россия"},'
        '{"lat":"bad","lon":"1"},{"lat":"53.2","lon":"50.15","name":"",'
        '"display_name":"Самара, городской округ Самара, Самарская область, Приволжский федеральный округ, Россия"}]';
    final p = WeatherApi.parseNominatim(body);
    expect(p.length, 2);
    expect(p[0].name, 'Москва');
    expect(p[0].region, 'Центральный федеральный округ, Россия');
    expect((p[0].lat, p[0].lon), (55.75, 37.62));
    expect(p[1].name, 'Самара');
    expect(p[1].region, 'Приволжский федеральный округ, Россия');
    expect(WeatherApi.parseNominatim('{}'), isEmpty);
  });

  test('services.json: https — замена, пусто — выключено, мусор — по умолчанию', () {
    final e = WeatherEndpoints.parse('{"weather":{"forecast":"https://a.example/x","geocoder":""}}');
    expect(e.forecast, 'https://a.example/x');
    expect(e.geocoder, '');
    final bad = WeatherEndpoints.parse('{"weather":{"forecast":"http://plain.example","geocoder":"https://g.example/s?key=1"}}');
    expect(bad.forecast, WeatherApi.metUrl, reason: 'только https');
    expect(bad.geocoder, WeatherApi.nominatimUrl, reason: 'без параметров в адресе');
    expect(WeatherEndpoints.parse('oops').geocoder, WeatherApi.nominatimUrl);
    expect(WeatherEndpoints.parse('{}').forecast, WeatherApi.metUrl);
  });

  test('сайт недоступен — прежние адреса', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var down = false;
    final client = MockClient((r) async {
      if (down) throw http.ClientException('offline');
      return http.Response('{"weather":{"geocoder":""}}', 200);
    });
    final now = DateTime(2026, 11, 7, 12);
    expect((await WeatherEndpoints.load(prefs, client, now: now)).geocoder, '');
    down = true;
    final later = now.add(const Duration(days: 3));
    expect((await WeatherEndpoints.load(prefs, client, now: later)).geocoder, '');
  });

  group('прогноз для города', () {
    late SharedPreferences prefs;
    late List<http.Request> all;
    // Запросы прогноза (без services.json с сайта проекта).
    List<http.Request> met() => [for (final r in all) if (r.url.host == 'api.met.no') r];
    var status = 200;
    var expires = '';
    String? services; // null — файла на сайте нет (404)

    ProviderContainer make({ManagedPolicy policy = ManagedPolicy.none, bool approved = true}) {
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        weatherHttpProvider.overrideWithValue(MockClient((r) async {
          all.add(r);
          if (r.url.toString() == WeatherEndpoints.servicesUrl) {
            return services == null ? http.Response('', 404) : http.Response(services!, 200);
          }
          return http.Response(status == 200 ? _met(DateTime.now()) : '', status,
              headers: {if (expires.isNotEmpty) 'expires': expires, 'last-modified': 'Sat, 07 Nov 2026 10:00:00 GMT'});
        })),
        managedPolicyProvider.overrideWith(() => _FixedPolicy(policy)),
        weatherApprovedProvider.overrideWithValue(approved),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      all = [];
      status = 200;
      expires = '';
      services = null;
    });

    test('выключено — запросов нет; город выбран — запрос с User-Agent и координатами до сотых', () async {
      var c = make();
      expect(await c.read(weatherProvider.future), isNull);
      expect(met(), isEmpty);
      await c.read(weatherSettingsProvider.notifier).setPlace(
            const WeatherPlace(name: 'Казань', lat: 55.796127, lon: 49.106405),
          );
      c = make();
      final f = await c.read(weatherProvider.future);
      expect(f, isNotNull);
      expect(met().single.url.queryParameters, {'lat': '55.8', 'lon': '49.11'});
      expect(met().single.headers['User-Agent'], startsWith('OgnelissMail/'));
      expect(met().single.headers['User-Agent'], contains('github.com/oedante/OgnelissMail'));
    });

    test('до срока Expires — из кэша без сети; потом — If-Modified-Since, 304 — прежний прогноз', () async {
      await WeatherSettingsNotifier(prefs).setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      expires = HttpDateFormat.inHours(2);
      expect(await make().read(weatherProvider.future), isNotNull);
      expect(met().length, 1);
      expect(await make().read(weatherProvider.future), isNotNull);
      expect(met().length, 1, reason: 'срок не вышел — сеть не нужна');

      // Срок вышел: запрос с If-Modified-Since, сервер отвечает 304.
      final cached = jsonDecode(prefs.getString(WeatherCache.key)!) as Map<String, dynamic>;
      cached['expires'] = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      await prefs.setString(WeatherCache.key, jsonEncode(cached));
      status = 304;
      expect(await make().read(weatherProvider.future), isNotNull);
      expect(met().length, 2);
      expect(met().last.headers['If-Modified-Since'], 'Sat, 07 Nov 2026 10:00:00 GMT');
    });

    test('сеть недоступна — последний сохранённый прогноз; запрет организацией — ничего', () async {
      await WeatherSettingsNotifier(prefs).setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      expect(await make().read(weatherProvider.future), isNotNull);
      final cached = jsonDecode(prefs.getString(WeatherCache.key)!) as Map<String, dynamic>;
      cached['expires'] = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      await prefs.setString(WeatherCache.key, jsonEncode(cached));
      status = 500;
      expect(await make().read(weatherProvider.future), isNotNull);

      final before = all.length;
      expect(await make(policy: const ManagedPolicy(blockWeather: true)).read(weatherProvider.future), isNull);
      expect(all.length, before);
    });

    test('адреса с сайта проекта: замена, выключение, раз в сутки', () async {
      await WeatherSettingsNotifier(prefs).setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      // Файла нет — MET Norway; файл спрашивается один раз в сутки.
      expect(await make().read(weatherProvider.future), isNotNull);
      await prefs.remove(WeatherCache.key);
      expect(await make().read(weatherProvider.future), isNotNull);
      expect(all.where((r) => r.url.host == 'ogneliss.ru').length, 1);
      expect(met().length, 2);

      // Сутки прошли, на сайте прогноз выключен — запроса прогноза нет.
      services = '{"weather":{"forecast":""}}';
      await prefs.remove(WeatherEndpoints.key);
      await prefs.remove(WeatherCache.key);
      expect(await make().read(weatherProvider.future), isNull);
      expect(met().length, 2);

      // Замена адреса — запрос идёт на новый.
      services = '{"weather":{"forecast":"https://weather.example.org/compact"}}';
      await prefs.remove(WeatherEndpoints.key);
      await make().read(weatherProvider.future);
      expect(all.last.url.host, 'weather.example.org');
      expect(all.last.url.queryParameters, {'lat': '55.8', 'lon': '49.11'});
    });

    test('условия не приняты владельцем — погоды нет и запросов нет', () async {
      await WeatherSettingsNotifier(prefs).setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      expect(WeatherApi.termsAccepted, isFalse, reason: 'включает владелец, docs/guides/WEATHER.md');
      expect(await make(approved: false).read(weatherProvider.future), isNull);
      expect(all, isEmpty);
    });

    test('время получения; 429 — час без запросов', () async {
      await WeatherSettingsNotifier(prefs).setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      final f = await make().read(weatherProvider.future);
      expect(f!.fetchedAt, isNotNull);
      expect(DateTime.now().difference(f.fetchedAt!).inMinutes, 0);
      // Срок вышел, сервис отвечает 429 — прежний прогноз, потом час тишины.
      final cached = jsonDecode(prefs.getString(WeatherCache.key)!) as Map<String, dynamic>;
      cached['expires'] = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      await prefs.setString(WeatherCache.key, jsonEncode(cached));
      status = 429;
      expect(await make().read(weatherProvider.future), isNotNull);
      final n = met().length;
      status = 200;
      expect(await make().read(weatherProvider.future), isNotNull);
      expect(met().length, n, reason: 'после 429 — час без запросов');
    });

    test('выключить — кэш стирается, город запоминается', () async {
      final n = WeatherSettingsNotifier(prefs);
      await n.setPlace(const WeatherPlace(name: 'Казань', lat: 55.8, lon: 49.11));
      await make().read(weatherProvider.future);
      expect(prefs.getString(WeatherCache.key), isNotNull);
      await n.turnOff();
      expect(prefs.getString(WeatherCache.key), isNull);
      final again = WeatherSettingsNotifier(prefs).state;
      expect(again.active, isFalse);
      expect(again.place?.name, 'Казань');
    });
  });
}

class _FixedPolicy extends ManagedPolicyNotifier {
  _FixedPolicy(this.policy);
  final ManagedPolicy policy;
  @override
  ManagedPolicy build() => policy;
}

/// Дата HTTP через [hours] часов.
abstract final class HttpDateFormat {
  static String inHours(int hours) {
    final d = DateTime.now().toUtc().add(Duration(hours: hours));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} ${d.year} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
  }
}

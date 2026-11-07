// lib/services/weather/weather_service.dart
// Погода в «Моём дне» (1.15.1, просьба владельца 07.11.2026: «в мой день
// добавить погоду»). Выключена по умолчанию; включается выбором города.
//
// 07.11.2026 (решение владельца: условия MET приняты, данные пользователей
// сторонним сервисам не передаются) — и прогноз, и поиск города идут через
// прокси на сервере Ogneliss (server/weather-proxy); MET Norway видит только
// сервер, поиск города наружу не уходит (список GeoNames на сервере).
//
// Откуда данные (условия проверены 07.11.2026, docs/LICENSING.md, раздел 2):
//  · прогноз — MET Norway, Locationforecast 2.0 «compact», через прокси:
//    бесплатно, в том числе для коммерческих приложений; данные — CC BY 4.0
//    и NLOD 2.0 (подпись «Данные: MET Norway» со ссылкой — в окне погоды).
//    Условия MET (User-Agent, не больше 4 знаков в координатах, Expires и
//    If-Modified-Since, 429) соблюдают и прокси, и приложение;
//  · поиск города — список GeoNames (CC BY 4.0) на сервере Ogneliss, только
//    по нажатию «Найти» (подпись «Города: GeoNames» — в окне поиска).
// Адреса обоих можно сменить или выключить без обновления приложения:
// файл services.json на сайте проекта, см. [WeatherEndpoints] и
// docs/guides/WEATHER.md.
// Местоположение телефона не используется: город выбирает человек. В
// запросы уходят только название города (поиск) и его координаты,
// округлённые до сотых (~1 км), — без адресов, имён и идентификаторов.
// Организация может запретить погоду (MDM, block_weather).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../security/managed_config.dart';

/// Город для погоды.
class WeatherPlace {
  final String name;

  /// Уточнение для выбора среди одноимённых (область, страна).
  final String region;
  final double lat, lon;
  const WeatherPlace({required this.name, this.region = '', required this.lat, required this.lon});

  Map<String, Object> toJson() => {'name': name, 'region': region, 'lat': lat, 'lon': lon};

  static WeatherPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = (j['lat'] as num?)?.toDouble(), lon = (j['lon'] as num?)?.toDouble();
    final name = j['name'];
    if (lat == null || lon == null || name is! String || name.isEmpty) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return WeatherPlace(name: name, region: (j['region'] as String?) ?? '', lat: lat, lon: lon);
  }
}

/// Вид погоды — по кодам значков MET Norway, без дня и ночи.
enum WeatherKind { clear, fair, partlyCloudy, cloudy, fog, lightRain, rain, heavyRain, sleet, snow, thunder }

class WeatherPoint {
  final DateTime at;
  final double temp;
  final WeatherKind? kind;
  final bool night;
  const WeatherPoint({required this.at, required this.temp, this.kind, this.night = false});
}

/// Прогноз: сейчас, сегодняшние наименьшая и наибольшая, ближайшие часы.
class WeatherForecast {
  final WeatherPoint now;
  final double min, max;
  final List<WeatherPoint> hours;

  /// Когда прогноз получен с сервиса (условия MET Norway: показывать, чтобы
  /// человек видел, не устарели ли данные); null — неизвестно.
  final DateTime? fetchedAt;
  const WeatherForecast({required this.now, required this.min, required this.max, this.hours = const [], this.fetchedAt});

  WeatherForecast withFetchedAt(DateTime? at) =>
      WeatherForecast(now: now, min: min, max: max, hours: hours, fetchedAt: at);
}

class WeatherApi {
  WeatherApi._();

  /// Условия MET Norway (обязательное соглашение, которое должен прочитать и
  /// принять человек с полномочиями, раздел «Use of AI agents») владелец
  /// проекта принял 07.11.2026 — с условием «данные пользователей не
  /// передаём». Поэтому приложение ходит не к MET Norway, а к прокси на
  /// сервере Ogneliss (server/weather-proxy): MET видит только сервер.
  /// Nominatim не используется — поиск города по списку GeoNames на том же
  /// сервере. false — погоды нет совсем (ни кнопки, ни запросов).
  static const termsAccepted = true;

  /// Прогноз — через прокси на сервере Ogneliss (тело — ответ MET Norway
  /// Locationforecast 2.0 «compact» как есть).
  static const metUrl = 'https://www.ogneliss.ru/weather/forecast';

  /// Поиск города — там же, по списку GeoNames (ответ — как у Nominatim
  /// format=jsonv2, разбор [parseNominatim]).
  static const nominatimUrl = 'https://www.ogneliss.ru/weather/search';

  /// User-Agent по условиям обоих сервисов: приложение, версия, адрес проекта.
  static String get userAgent {
    final v = AppConstants.appVersion.isEmpty ? '1' : AppConstants.appVersion;
    return 'OgnelissMail/$v (+https://github.com/oedante/OgnelissMail)';
  }

  /// Координаты — до сотых (~1 км): меньше сведений о человеке и тот же
  /// ответ из кэша сервиса для соседей (условия MET Norway — не больше 4).
  static double round2(double v) => (v * 100).round() / 100;

  /// Код значка MET Norway («lightrainshowers_day») → вид погоды.
  static WeatherKind? kindOf(String? symbol) {
    if (symbol == null || symbol.isEmpty) return null;
    final s = symbol.split('_').first;
    if (s.contains('thunder')) return WeatherKind.thunder;
    if (s.contains('snow')) return WeatherKind.snow;
    if (s.contains('sleet')) return WeatherKind.sleet;
    if (s.startsWith('heavyrain')) return WeatherKind.heavyRain;
    if (s.startsWith('lightrain')) return WeatherKind.lightRain;
    if (s.contains('rain')) return WeatherKind.rain;
    if (s == 'fog') return WeatherKind.fog;
    if (s == 'partlycloudy') return WeatherKind.partlyCloudy;
    if (s == 'cloudy') return WeatherKind.cloudy;
    if (s == 'fair') return WeatherKind.fair;
    if (s == 'clearsky') return WeatherKind.clear;
    return null;
  }

  static bool _isNight(String? symbol) => symbol != null && symbol.endsWith('_night');

  /// Ответ Locationforecast «compact» → прогноз; null — не разобрать.
  /// [now] — для тестов (сегодня по местному времени устройства).
  static WeatherForecast? parseMet(String body, {DateTime? now}) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      return null;
    }
    final props = j is Map ? j['properties'] : null;
    final series = props is Map ? props['timeseries'] : null;
    if (series is! List || series.isEmpty) return null;
    final clock = now ?? DateTime.now();
    final points = <WeatherPoint>[];
    for (final e in series.take(400)) {
      if (e is! Map) continue;
      final at = DateTime.tryParse('${e['time']}');
      final data = e['data'];
      if (at == null || data is! Map) continue;
      final temp = ((((data['instant'] as Map?)?['details']) as Map?)?['air_temperature'] as num?)?.toDouble();
      if (temp == null || !temp.isFinite) continue;
      String? symbol;
      for (final k in const ['next_1_hours', 'next_6_hours', 'next_12_hours']) {
        final s = (((data[k] as Map?)?['summary']) as Map?)?['symbol_code'];
        if (s is String && s.isNotEmpty) {
          symbol = s;
          break;
        }
      }
      points.add(WeatherPoint(at: at.toLocal(), temp: temp, kind: kindOf(symbol), night: _isNight(symbol)));
    }
    if (points.isEmpty) return null;
    // «Сейчас» — последняя точка не позже текущего часа (или первая).
    var nowPoint = points.first;
    for (final p in points) {
      if (p.at.isAfter(clock)) break;
      nowPoint = p;
    }
    final today = points.where((p) =>
        p.at.year == clock.year && p.at.month == clock.month && p.at.day == clock.day);
    final temps = [for (final p in today.isEmpty ? [nowPoint] : today) p.temp];
    final hours = [
      for (final p in points)
        if (p.at.isAfter(nowPoint.at) && p.kind != null) p,
    ].take(12).toList();
    return WeatherForecast(
      now: nowPoint,
      min: temps.reduce((a, b) => a < b ? a : b),
      max: temps.reduce((a, b) => a > b ? a : b),
      hours: hours,
    );
  }

  /// Ответ поиска Nominatim (format=jsonv2) → города; мусор пропускается.
  static List<WeatherPlace> parseNominatim(String body) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    if (j is! List) return const [];
    final out = <WeatherPlace>[];
    for (final e in j.take(10)) {
      if (e is! Map) continue;
      final lat = double.tryParse('${e['lat']}'), lon = double.tryParse('${e['lon']}');
      final display = '${e['display_name'] ?? ''}'.trim();
      var name = '${e['name'] ?? ''}'.trim();
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) continue;
      if (name.isEmpty) name = display.split(',').first.trim();
      if (name.isEmpty) continue;
      final parts = display.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty && parts.first == name) parts.removeAt(0);
      // Уточнение — область и страна (последние две части), не весь адрес.
      final region = parts.length > 2 ? parts.sublist(parts.length - 2).join(', ') : parts.join(', ');
      out.add(WeatherPlace(name: name, region: region, lat: round2(lat), lon: round2(lon)));
    }
    return out;
  }

  /// Поиск города (по нажатию «Найти»). Ошибка сети — исключение.
  static Future<List<WeatherPlace>> search(http.Client client, String query, String lang,
      {String url = nominatimUrl}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse(url).replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'limit': '6',
      'accept-language': lang,
    });
    final r = await client.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw http.ClientException('nominatim ${r.statusCode}', uri);
    return parseNominatim(utf8.decode(r.bodyBytes, allowMalformed: true));
  }
}

// ── Адреса сервисов: сменить или выключить без обновления приложения ──

/// Адреса прогноза и поиска города. Файл на сайте проекта
/// ([servicesUrl]) — `{"weather": {"forecast": "https://…", "geocoder":
/// "https://…"}}`: адрес https — замена (сервис с тем же форматом ответа),
/// пустая строка — сервис выключен, ключа или файла нет — адрес по
/// умолчанию. Файл читается не чаще раза в сутки и только перед запросом
/// погоды или поиском города; без сети — прежние адреса.
class WeatherEndpoints {
  /// '' — прогноз выключен.
  final String forecast;

  /// '' — поиск города выключен.
  final String geocoder;
  const WeatherEndpoints({this.forecast = WeatherApi.metUrl, this.geocoder = WeatherApi.nominatimUrl});

  static const servicesUrl = 'https://ogneliss.ru/mail/services.json';
  static const key = 'weather_services_v1';
  static const maxAge = Duration(hours: 24);

  static String _url(Object? v, String fallback) {
    if (v is! String) return fallback;
    final t = v.trim();
    if (t.isEmpty) return '';
    final u = Uri.tryParse(t);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty && !u.hasQuery ? t : fallback;
  }

  /// Содержимое services.json; не разобрать — адреса по умолчанию.
  static WeatherEndpoints parse(String body) {
    Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {}
    final w = j is Map ? j['weather'] : null;
    if (w is! Map) return const WeatherEndpoints();
    return WeatherEndpoints(
      forecast: _url(w['forecast'], WeatherApi.metUrl),
      geocoder: _url(w['geocoder'], WeatherApi.nominatimUrl),
    );
  }

  static WeatherEndpoints? _cached(SharedPreferences p, DateTime now) {
    try {
      final raw = p.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map;
      final at = DateTime.parse(j['at'] as String);
      if (now.difference(at).abs() > maxAge) return null;
      return WeatherEndpoints(forecast: j['forecast'] as String, geocoder: j['geocoder'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(SharedPreferences p, WeatherEndpoints e, DateTime now) => p.setString(
      key, jsonEncode({'at': now.toUtc().toIso8601String(), 'forecast': e.forecast, 'geocoder': e.geocoder}));

  /// Адреса на сейчас: из сохранённых (моложе суток) или с сайта.
  static Future<WeatherEndpoints> load(SharedPreferences p, http.Client client, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final fresh = _cached(p, t);
    if (fresh != null) return fresh;
    try {
      final r = await client
          .get(Uri.parse(servicesUrl), headers: {'User-Agent': WeatherApi.userAgent})
          .timeout(const Duration(seconds: 8));
      // Файла нет — адреса по умолчанию (тоже на сутки, без повторов).
      final e = r.statusCode == 200
          ? parse(utf8.decode(r.bodyBytes, allowMalformed: true))
          : (r.statusCode == 404 || r.statusCode == 410)
              ? const WeatherEndpoints()
              : null;
      if (e != null) {
        await _save(p, e, t);
        return e;
      }
    } catch (_) {}
    // Сайт недоступен — прежние адреса, даже старше суток.
    try {
      final j = jsonDecode(p.getString(key) ?? '') as Map;
      return WeatherEndpoints(forecast: j['forecast'] as String, geocoder: j['geocoder'] as String);
    } catch (_) {
      return const WeatherEndpoints();
    }
  }
}

/// Погода разрешена владельцем проекта ([WeatherApi.termsAccepted]); тесты
/// и снимки экрана подменяют.
final weatherApprovedProvider = Provider<bool>((ref) => WeatherApi.termsAccepted);

// ── Настройка: включена ли погода и для какого города ──

class WeatherSettings {
  final bool enabled;
  final WeatherPlace? place;
  const WeatherSettings({this.enabled = false, this.place});
  bool get active => enabled && place != null;
}

class WeatherSettingsNotifier extends StateNotifier<WeatherSettings> {
  WeatherSettingsNotifier(this._p) : super(_load(_p));
  final SharedPreferences _p;

  static const _kOn = 'weather_on';
  static const _kPlace = 'weather_place_v1';

  static WeatherSettings _load(SharedPreferences p) {
    WeatherPlace? place;
    try {
      final raw = p.getString(_kPlace);
      if (raw != null) place = WeatherPlace.fromJson(jsonDecode(raw));
    } catch (_) {}
    return WeatherSettings(enabled: p.getBool(_kOn) ?? false, place: place);
  }

  /// Город выбран — погода включается.
  Future<void> setPlace(WeatherPlace place) async {
    await _p.setString(_kPlace, jsonEncode(place.toJson()));
    await _p.setBool(_kOn, true);
    state = WeatherSettings(enabled: true, place: place);
  }

  Future<void> turnOff() async {
    await _p.setBool(_kOn, false);
    await _p.remove(WeatherCache.key);
    state = WeatherSettings(enabled: false, place: state.place);
  }
}

final weatherSettingsProvider = StateNotifierProvider<WeatherSettingsNotifier, WeatherSettings>(
  (ref) => WeatherSettingsNotifier(ref.watch(sharedPrefsProvider)),
);

/// Клиент HTTP для погоды (тесты подменяют).
final weatherHttpProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

// ── Кэш ответа MET Norway: до Expires — без сети, потом If-Modified-Since ──

class WeatherCache {
  WeatherCache._();
  static const key = 'weather_cache_v1';

  static ({double lat, double lon, DateTime expires, String? lastModified, String body, DateTime? fetched})? read(
      SharedPreferences p) {
    try {
      final raw = p.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map;
      return (
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        expires: DateTime.parse(j['expires'] as String),
        lastModified: j['lastModified'] as String?,
        body: j['body'] as String,
        fetched: DateTime.tryParse('${j['fetched'] ?? ''}')?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(SharedPreferences p,
          {required double lat,
          required double lon,
          required DateTime expires,
          String? lastModified,
          required String body,
          required DateTime fetched}) =>
      p.setString(
          key,
          jsonEncode({
            'lat': lat,
            'lon': lon,
            'expires': expires.toUtc().toIso8601String(),
            'lastModified': ?lastModified,
            'body': body,
            'fetched': fetched.toUtc().toIso8601String(),
          }));
}

/// Не чаще раза в 10 минут, даже если Expires раньше; ответ без Expires —
/// на 30 минут.
const _minAge = Duration(minutes: 10);
const _defaultAge = Duration(minutes: 30);

DateTime _expiresOf(http.Response r, DateTime now) {
  DateTime? e;
  try {
    final h = r.headers['expires'];
    if (h != null) e = HttpDate.parse(h);
  } catch (_) {}
  final floor = now.add(_minAge);
  if (e == null) return now.add(_defaultAge);
  return e.isBefore(floor) ? floor : e;
}

/// Прогноз для выбранного города; null — погода выключена (или запрещена
/// организацией). Сеть недоступна — последний сохранённый прогноз.
final weatherProvider = FutureProvider.autoDispose<WeatherForecast?>((ref) async {
  final settings = ref.watch(weatherSettingsProvider);
  final place = settings.place;
  if (!ref.watch(weatherApprovedProvider)) return null;
  if (!settings.active || place == null) return null;
  if (ref.watch(managedPolicyProvider).blockWeather) return null;
  final prefs = ref.read(sharedPrefsProvider);
  final lat = WeatherApi.round2(place.lat), lon = WeatherApi.round2(place.lon);
  final now = DateTime.now();
  final cached = WeatherCache.read(prefs);
  final sameSpot = cached != null && cached.lat == lat && cached.lon == lon;
  WeatherForecast? fromCache() => sameSpot ? WeatherApi.parseMet(cached.body)?.withFetchedAt(cached.fetched) : null;
  if (sameSpot && cached.expires.isAfter(now)) return fromCache();
  // Сервис просил сбавить частоту (429) — час без запросов.
  final pause = DateTime.tryParse(prefs.getString(_backoffKey) ?? '');
  if (pause != null && pause.isAfter(now)) return fromCache();
  final client = ref.read(weatherHttpProvider);
  try {
    final ends = await WeatherEndpoints.load(prefs, client, now: now);
    if (ends.forecast.isEmpty) {
      AppLogger.info('Погода: прогноз выключен на сайте проекта');
      return null;
    }
    final uri = Uri.parse(ends.forecast).replace(queryParameters: {'lat': '$lat', 'lon': '$lon'});
    final r = await client.get(uri, headers: {
      'User-Agent': WeatherApi.userAgent,
      if (sameSpot && cached.lastModified != null) 'If-Modified-Since': cached.lastModified!,
    }).timeout(const Duration(seconds: 12));
    if (r.statusCode == 304 && sameSpot) {
      await WeatherCache.write(prefs,
          lat: lat,
          lon: lon,
          expires: _expiresOf(r, now),
          lastModified: cached.lastModified,
          body: cached.body,
          fetched: now);
      return WeatherApi.parseMet(cached.body)?.withFetchedAt(now);
    }
    if (r.statusCode == 429) {
      await prefs.setString(_backoffKey, now.add(const Duration(hours: 1)).toUtc().toIso8601String());
      AppLogger.warning('Погода: сервис просит реже (429) — час без запросов');
      return fromCache();
    }
    if (r.statusCode == 200 || r.statusCode == 203) {
      // 203 — версия API устарела и скоро закроется (условия MET Norway:
      // записать предупреждение).
      if (r.statusCode == 203) AppLogger.warning('Погода: MET Norway сообщает, что версия API устарела (203)');
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final f = WeatherApi.parseMet(body);
      if (f != null) {
        await WeatherCache.write(prefs,
            lat: lat,
            lon: lon,
            expires: _expiresOf(r, now),
            lastModified: r.headers['last-modified'],
            body: body,
            fetched: now);
        return f.withFetchedAt(now);
      }
    }
    AppLogger.warning('Погода: ответ ${r.statusCode}');
  } catch (e) {
    AppLogger.warning('Погода: прогноз не получен — $e');
  }
  return fromCache();
});

const _backoffKey = 'weather_backoff_until';

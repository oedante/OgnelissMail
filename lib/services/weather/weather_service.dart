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

  /// Часовой пояс города (IANA, «Asia/Yekaterinburg») — для часов города в
  /// «Моём дне» (2.7.2); null — неизвестен (город выбран до 2.7.2 или сервер
  /// поиска его не прислал).
  final String? tz;
  const WeatherPlace({required this.name, this.region = '', required this.lat, required this.lon, this.tz});

  /// Ключ города: координаты, округлённые до сотых (как в запросах).
  String get key => '${WeatherApi.round2(lat)},${WeatherApi.round2(lon)}';

  WeatherPlace withTz(String? zone) => WeatherPlace(name: name, region: region, lat: lat, lon: lon, tz: zone);

  Map<String, Object> toJson() =>
      {'name': name, 'region': region, 'lat': lat, 'lon': lon, if (tz != null && tz!.isNotEmpty) 'tz': tz!};

  static WeatherPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = (j['lat'] as num?)?.toDouble(), lon = (j['lon'] as num?)?.toDouble();
    final name = j['name'];
    if (lat == null || lon == null || name is! String || name.isEmpty) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    final tz = j['tz'];
    return WeatherPlace(
        name: name,
        region: (j['region'] as String?) ?? '',
        lat: lat,
        lon: lon,
        tz: tz is String && WeatherApi.validTz(tz) ? tz : null);
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
      // Часовой пояс (2.7.2) — сервер поиска Ogneliss берёт его из GeoNames.
      final zone = '${e['timezone'] ?? ''}'.trim();
      out.add(WeatherPlace(
          name: name, region: region, lat: round2(lat), lon: round2(lon), tz: validTz(zone) ? zone : null));
    }
    return out;
  }

  /// Похоже ли на имя пояса IANA («Europe/Moscow», «UTC»).
  static bool validTz(String v) => v.length < 64 && RegExp(r'^[A-Za-z_]+(/[A-Za-z0-9_+\-]+){0,2}$').hasMatch(v);

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

// ── Настройка: включена ли погода и для каких городов ──

class WeatherSettings {
  final bool enabled;

  /// Города (2.7.2, просьба владельца 24.11.2026: часы и погода нескольких
  /// городов в «Моём дне», листанием): первый — свой, всего до
  /// [WeatherSettingsNotifier.maxPlaces].
  final List<WeatherPlace> places;

  /// Ключи городов для виджетов «Мой день» и «Календарь» — не больше
  /// [WeatherSettingsNotifier.maxWidget].
  final Set<String> widgetKeys;
  const WeatherSettings({this.enabled = false, this.places = const [], this.widgetKeys = const {}});

  bool get active => enabled && places.isNotEmpty;

  /// Свой (первый) город.
  WeatherPlace? get place => places.firstOrNull;

  /// Второй город (2.7.2) — второй в списке.
  WeatherPlace? get second => places.length > 1 ? places[1] : null;

  /// Города для виджетов — в порядке списка.
  List<WeatherPlace> get widgetPlaces => [for (final p in places) if (widgetKeys.contains(p.key)) p];

  WeatherPlace? byKey(String key) => places.where((p) => p.key == key).firstOrNull;
}

class WeatherSettingsNotifier extends StateNotifier<WeatherSettings> {
  WeatherSettingsNotifier(this._p) : super(_load(_p));
  final SharedPreferences _p;

  static const maxPlaces = 5;
  static const maxWidget = 2;

  static const _kOn = 'weather_on';

  /// Города до 2.7.2 (первый и второй) — читаются, если списка ещё нет.
  static const kPlace = 'weather_place_v1';
  static const kSecond = 'weather_place2_v1';

  /// Список городов (2.7.2): `[{…город…, "w": true}]`, «w» — в виджетах.
  static const kPlaces = 'weather_places_v2';

  static WeatherPlace? readPlace(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw != null) return WeatherPlace.fromJson(jsonDecode(raw));
    } catch (_) {}
    return null;
  }

  /// Города и отметки «в виджетах» из настроек; до 2.7.2 — первый и второй
  /// город, оба в виджетах. Читает и обновление виджетов (без Riverpod).
  static ({List<WeatherPlace> places, Set<String> widgets}) readPlaces(SharedPreferences p) {
    try {
      final raw = p.getString(kPlaces);
      if (raw != null) {
        final list = jsonDecode(raw);
        final places = <WeatherPlace>[];
        final widgets = <String>{};
        if (list is List) {
          for (final e in list) {
            final place = WeatherPlace.fromJson(e);
            if (place == null || places.any((x) => x.key == place.key) || places.length >= maxPlaces) continue;
            places.add(place);
            if (e is Map && e['w'] == true && widgets.length < maxWidget) widgets.add(place.key);
          }
        }
        return (places: places, widgets: widgets);
      }
    } catch (_) {}
    final places = [
      ?readPlace(p, kPlace),
      ?readPlace(p, kSecond),
    ];
    if (places.length == 2 && places[0].key == places[1].key) places.removeLast();
    return (places: places, widgets: {for (final x in places) x.key});
  }

  /// Ключ кэша прогноза города: у первого — прежний ([WeatherCache.key]),
  /// у остальных — по координатам. Кэш хранит и координаты: чужой (город
  /// сменился местом) не берётся.
  static String cacheKeyFor(WeatherSettings s, WeatherPlace place) =>
      s.places.isNotEmpty && s.places.first.key == place.key ? WeatherCache.key : '${WeatherCache.cityPrefix}${place.key}';

  static WeatherSettings _load(SharedPreferences p) {
    final r = readPlaces(p);
    return WeatherSettings(enabled: p.getBool(_kOn) ?? false, places: r.places, widgetKeys: r.widgets);
  }

  Future<void> _save(List<WeatherPlace> places, Set<String> widgets, {bool? enabled}) async {
    final keep = places.take(maxPlaces).toList();
    final w = {for (final x in keep) if (widgets.contains(x.key)) x.key};
    await _p.setString(kPlaces, jsonEncode([for (final x in keep) {...x.toJson(), if (w.contains(x.key)) 'w': true}]));
    // Прежние ключи — для обновления виджета старой сборкой не нужны.
    await _p.remove(kSecond);
    if (keep.isNotEmpty) await _p.setString(kPlace, jsonEncode(keep.first.toJson()));
    if (enabled != null) await _p.setBool(_kOn, enabled);
    // Кэш убранных городов — стереть.
    final live = {for (final x in keep) x.key};
    for (final k in _p.getKeys().where((k) => k.startsWith(WeatherCache.cityPrefix)).toList()) {
      if (!live.contains(k.substring(WeatherCache.cityPrefix.length))) await _p.remove(k);
    }
    await _p.remove(WeatherCache.secondKey);
    state = WeatherSettings(enabled: enabled ?? state.enabled, places: keep, widgetKeys: w);
  }

  /// Свой город выбран — погода включается. Был в списке — становится
  /// первым.
  Future<void> setPlace(WeatherPlace place) async {
    final rest = [for (final x in state.places.skip(1)) if (x.key != place.key) x];
    final widgets = {...state.widgetKeys};
    if (state.places.isEmpty || widgets.contains(state.places.first.key) || widgets.length < maxWidget) {
      widgets.add(place.key);
    }
    if (state.places.isNotEmpty && state.places.first.key != place.key) widgets.remove(state.places.first.key);
    await _save([place, ...rest], widgets, enabled: true);
  }

  /// Ещё один город (до [maxPlaces]); в виджеты — если там меньше двух.
  /// Уже есть — не добавляется. false — не добавлен.
  Future<bool> addPlace(WeatherPlace place) async {
    if (state.places.any((x) => x.key == place.key) || state.places.length >= maxPlaces) return false;
    final widgets = {...state.widgetKeys};
    if (widgets.length < maxWidget) widgets.add(place.key);
    await _save([...state.places, place], widgets, enabled: state.places.isEmpty ? true : null);
    return true;
  }

  /// Второй город (2.7.2): второй в списке; тот же, что первый, — нет.
  Future<void> setSecond(WeatherPlace place) async {
    final first = state.place;
    if (first == null || first.key == place.key) return;
    final rest = [for (final x in state.places.skip(2)) if (x.key != place.key) x];
    final widgets = {...state.widgetKeys}..remove(state.second?.key);
    if (widgets.length < maxWidget) widgets.add(place.key);
    await _save([first, place, ...rest], widgets);
  }

  Future<void> removeSecond() async {
    final second = state.second;
    if (second != null) await removePlace(second.key);
  }

  /// Убрать город. Первый убрали — первым становится следующий.
  Future<void> removePlace(String key) async {
    final rest = [for (final x in state.places) if (x.key != key) x];
    await _save(rest, {...state.widgetKeys}..remove(key));
  }

  /// Сделать город первым (своим).
  Future<void> makeFirst(String key) async {
    final p = state.byKey(key);
    if (p == null) return;
    await _save([p, for (final x in state.places) if (x.key != key) x], state.widgetKeys);
  }

  /// Показывать ли город в виджетах. Третий — не ставится (false).
  Future<bool> setInWidgets(String key, bool on) async {
    final widgets = {...state.widgetKeys};
    if (on) {
      if (widgets.contains(key)) return true;
      if (widgets.length >= maxWidget) return false;
      widgets.add(key);
    } else {
      widgets.remove(key);
    }
    await _save(state.places, widgets);
    return true;
  }

  /// Часовые пояса городов, выбранных до 2.7.2: тот же поиск по имени,
  /// город с теми же координатами (до 0,1°). Не нашёлся — останется без
  /// часов.
  Future<void> fillTimeZones(Future<List<WeatherPlace>> Function(String name) search) async {
    var changed = false;
    final out = <WeatherPlace>[];
    for (final p in state.places) {
      if (p.tz != null) {
        out.add(p);
        continue;
      }
      String? zone;
      try {
        for (final f in await search(p.name)) {
          if (f.tz != null && (f.lat - p.lat).abs() <= 0.1 && (f.lon - p.lon).abs() <= 0.1) {
            zone = f.tz;
            break;
          }
        }
      } catch (_) {}
      if (zone != null) changed = true;
      out.add(zone == null ? p : p.withTz(zone));
    }
    if (changed) await _save(out, state.widgetKeys);
  }

  Future<void> turnOff() async {
    await _p.setBool(_kOn, false);
    await _p.remove(WeatherCache.key);
    await _p.remove(WeatherCache.secondKey);
    for (final k in _p.getKeys().where((k) => k.startsWith(WeatherCache.cityPrefix)).toList()) {
      await _p.remove(k);
    }
    state = WeatherSettings(enabled: false, places: state.places, widgetKeys: state.widgetKeys);
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

  /// Кэш второго города (первый вариант второго города; со списком городов
  /// не пишется, стирается).
  static const secondKey = 'weather_cache2_v1';

  /// Кэш остальных городов (2.7.2): префикс + ключ города.
  static const cityPrefix = 'weather_cache_city:';

  static ({double lat, double lon, DateTime expires, String? lastModified, String body, DateTime? fetched})? read(
      SharedPreferences p, {String key = key}) {
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
          {String key = key,
          required double lat,
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

/// Прогноз для своего (первого) города; null — погода выключена (или
/// запрещена организацией). Сеть недоступна — последний сохранённый прогноз.
final weatherProvider = FutureProvider.autoDispose<WeatherForecast?>((ref) async {
  final key = ref.watch(weatherSettingsProvider.select((s) => s.active ? s.place?.key : null));
  if (key == null) return null;
  return ref.watch(weatherForProvider(key).future);
});

/// Прогноз второго города (2.7.2); null — второго города нет или погода
/// выключена.
final weatherSecondProvider = FutureProvider.autoDispose<WeatherForecast?>((ref) async {
  final key = ref.watch(weatherSettingsProvider.select((s) => s.active ? s.second?.key : null));
  if (key == null) return null;
  return ref.watch(weatherForProvider(key).future);
});

/// Прогноз города по ключу ([WeatherPlace.key], 2.7.2); null — такого города
/// нет, погода выключена или запрещена.
final weatherForProvider = FutureProvider.autoDispose.family<WeatherForecast?, String>((ref, key) async {
  final settings = ref.watch(weatherSettingsProvider);
  if (!ref.watch(weatherApprovedProvider)) return null;
  if (!settings.active) return null;
  if (ref.watch(managedPolicyProvider).blockWeather) return null;
  final place = settings.byKey(key);
  if (place == null) return null;
  return _forecast(ref, place, WeatherSettingsNotifier.cacheKeyFor(settings, place));
});

Future<WeatherForecast?> _forecast(Ref ref, WeatherPlace place, String cacheKey) =>
    fetchForecast(ref.read(sharedPrefsProvider), ref.read(weatherHttpProvider), place, cacheKey);

/// Прогнозы городов виджетов — свежие и без открытия «Моего дня» (2.7.4,
/// замечание владельца 25.11.2026: «в виджете пропадает погода, приходится
/// заходить в приложение и в „Мой день“» — прогноз обновлялся только там, а
/// виджет прячет прогноз старше [widgetMaxAge]). Обновление виджетов после
/// синхронизации зовёт это перед сборкой; запрос — только если прогнозу
/// больше часа.
Future<void> refreshWidgetWeather(SharedPreferences prefs, http.Client client, {DateTime? now}) async {
  if (!WeatherApi.termsAccepted || ManagedPolicy.current.blockWeather) return;
  if (prefs.getBool('weather_on') != true) return;
  final r = WeatherSettingsNotifier.readPlaces(prefs);
  final s = WeatherSettings(enabled: true, places: r.places, widgetKeys: r.widgets);
  final clock = now ?? DateTime.now();
  for (final p in s.widgetPlaces) {
    final key = WeatherSettingsNotifier.cacheKeyFor(s, p);
    final fetched = WeatherCache.read(prefs, key: key)?.fetched;
    if (fetched != null && clock.difference(fetched) < const Duration(hours: 1)) continue;
    await fetchForecast(prefs, client, p, key, now: clock);
  }
}

/// Сколько виджет показывает сохранённый прогноз (дальше — без погоды):
/// прогноз почасовой на двое суток вперёд, «сейчас» берётся из него по
/// часам.
const widgetMaxAge = Duration(hours: 12);

/// Прогноз города: из кэша до Expires, потом — запрос (If-Modified-Since);
/// сеть недоступна — последний сохранённый.
Future<WeatherForecast?> fetchForecast(SharedPreferences prefs, http.Client client, WeatherPlace place, String cacheKey,
    {DateTime? now}) async {
  final lat = WeatherApi.round2(place.lat), lon = WeatherApi.round2(place.lon);
  now ??= DateTime.now();
  final cached = WeatherCache.read(prefs, key: cacheKey);
  final sameSpot = cached != null && cached.lat == lat && cached.lon == lon;
  WeatherForecast? fromCache() => sameSpot ? WeatherApi.parseMet(cached.body)?.withFetchedAt(cached.fetched) : null;
  if (sameSpot && cached.expires.isAfter(now)) return fromCache();
  // Сервис просил сбавить частоту (429) — час без запросов.
  final pause = DateTime.tryParse(prefs.getString(_backoffKey) ?? '');
  if (pause != null && pause.isAfter(now)) return fromCache();
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
          key: cacheKey,
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
            key: cacheKey,
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
}

const _backoffKey = 'weather_backoff_until';

// lib/core/platform/device_time_zone.dart
// Пояс устройства по имени и его имя в Windows (1.6.2): Exchange по одному
// смещению выбирал первый пояс из списка — приглашение из Екатеринбурга
// приходило с поясом «Ашхабад, Ташкент» (замечание 13.10.2026). Теперь в
// TIME_ZONE_INFORMATION ActiveSync уходит и имя пояса Windows.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceTimeZone {
  DeviceTimeZone._();

  static const _prefKey = 'device_tz_id';
  static const _channel = MethodChannel('ogneliss/time_zone');

  /// IANA-имя пояса устройства (Asia/Yekaterinburg); null — неизвестно.
  static String? id;

  /// При запуске (основной изолят): спросить систему и запомнить для фона.
  static Future<void> load(SharedPreferences prefs) async {
    id ??= prefs.getString(_prefKey);
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final v = await _channel.invokeMethod<String>('id');
      if (v != null && v.isNotEmpty) {
        id = v;
        if (prefs.getString(_prefKey) != v) await prefs.setString(_prefKey, v);
      }
    } catch (_) {}
  }

  /// Фоновый изолят: имя, сохранённое основным.
  static void restore(SharedPreferences prefs) => id ??= prefs.getString(_prefKey);

  /// Имя пояса в Windows для [iana] (или пояса устройства); null — не знаем.
  static String? windowsName([String? iana]) => _windows[iana ?? id];

  /// Имена StandardName/DaylightName для TIME_ZONE_INFORMATION — значения Std
  /// и Dlt из реестра Windows. Обычно «X Standard Time» / «X Daylight Time»;
  /// у части поясов России и у UTC в реестре другие (ниже).
  static ({String std, String dlt})? tziNames(String? windows) {
    if (windows == null || windows.isEmpty) return null;
    final special = _tziSpecial[windows];
    if (special != null) return special;
    if (windows.endsWith(' Standard Time')) {
      return (std: windows, dlt: windows.replaceFirst(RegExp(r' Standard Time$'), ' Daylight Time'));
    }
    return (std: windows, dlt: windows);
  }

  static const _tziSpecial = <String, ({String std, String dlt})>{
    'Russia Time Zone 3': (std: 'Russia TZ 3 Standard Time', dlt: 'Russia TZ 3 Daylight Time'),
    'Russia Time Zone 10': (std: 'Russia TZ 10 Standard Time', dlt: 'Russia TZ 10 Daylight Time'),
    'Russia Time Zone 11': (std: 'Russia TZ 11 Standard Time', dlt: 'Russia TZ 11 Daylight Time'),
    'UTC': (std: 'Coordinated Universal Time', dlt: 'Coordinated Universal Time'),
  };

  static const _windows = <String, String>{
    'Europe/Kaliningrad': 'Kaliningrad Standard Time',
    'Europe/Moscow': 'Russian Standard Time',
    'Europe/Simferopol': 'Russian Standard Time',
    'Europe/Kirov': 'Russian Standard Time',
    'Europe/Volgograd': 'Volgograd Standard Time',
    'Europe/Astrakhan': 'Astrakhan Standard Time',
    'Europe/Ulyanovsk': 'Astrakhan Standard Time',
    'Europe/Saratov': 'Saratov Standard Time',
    'Europe/Samara': 'Russia Time Zone 3',
    'Asia/Yekaterinburg': 'Ekaterinburg Standard Time',
    'Asia/Omsk': 'Omsk Standard Time',
    'Asia/Novosibirsk': 'N. Central Asia Standard Time',
    'Asia/Barnaul': 'Altai Standard Time',
    'Asia/Tomsk': 'Tomsk Standard Time',
    'Asia/Novokuznetsk': 'North Asia Standard Time',
    'Asia/Krasnoyarsk': 'North Asia Standard Time',
    'Asia/Irkutsk': 'North Asia East Standard Time',
    'Asia/Chita': 'Transbaikal Standard Time',
    'Asia/Yakutsk': 'Yakutsk Standard Time',
    'Asia/Khandyga': 'Yakutsk Standard Time',
    'Asia/Vladivostok': 'Vladivostok Standard Time',
    'Asia/Ust-Nera': 'Vladivostok Standard Time',
    'Asia/Sakhalin': 'Sakhalin Standard Time',
    'Asia/Magadan': 'Magadan Standard Time',
    'Asia/Srednekolymsk': 'Russia Time Zone 10',
    'Asia/Kamchatka': 'Russia Time Zone 11',
    'Asia/Anadyr': 'Russia Time Zone 11',
    'Europe/Minsk': 'Belarus Standard Time',
    'Europe/Kiev': 'FLE Standard Time',
    'Europe/Kyiv': 'FLE Standard Time',
    'Asia/Almaty': 'Central Asia Standard Time',
    'Asia/Bishkek': 'Central Asia Standard Time',
    'Asia/Tashkent': 'West Asia Standard Time',
    'Asia/Ashgabat': 'West Asia Standard Time',
    'Asia/Dushanbe': 'West Asia Standard Time',
    'Asia/Baku': 'Azerbaijan Standard Time',
    'Asia/Tbilisi': 'Georgian Standard Time',
    'Asia/Yerevan': 'Caucasus Standard Time',
    'Asia/Dubai': 'Arabian Standard Time',
    'Europe/Istanbul': 'Turkey Standard Time',
    'Europe/London': 'GMT Standard Time',
    'Europe/Berlin': 'W. Europe Standard Time',
    'Europe/Paris': 'Romance Standard Time',
    'Asia/Shanghai': 'China Standard Time',
    'Asia/Tokyo': 'Tokyo Standard Time',
    'Asia/Kolkata': 'India Standard Time',
    'UTC': 'UTC',
  };
}

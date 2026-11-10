// lib/core/device/device_user_agent.dart
//
// Честный User-Agent для подключений к почтовым серверам (EAS/EWS/IMAP),
// сформированный из РЕАЛЬНЫХ системных данных устройства. Раньше движок
// маскировался под чужое устройство (Pixel 6 / iPhone) — это некорректно и
// рискованно при модерации в сторах. Теперь клиент представляется честно:
//   Ogneliss/<версия приложения> (<ОС> <версия ОС>; <модель>)
//
// Значение вычисляется один раз и кэшируется. Есть синхронный геттер `value`
// (для мест, где нельзя await) — он возвращает кэш либо нейтральный фолбэк,
// поэтому важно прогреть кэш при старте: `await DeviceUserAgent.warmUp()`.

// Режим совместимости (выключен по умолчанию, включает пользователь):
// часть корпоративных шлюзов перед Exchange (анти-бот-защита вроде ServicePipe)
// пропускает POST-команды ActiveSync только от мобильных почтовых клиентов и
// отвечает 403 на Provision/Sync/SendMail от любого другого User-Agent. В
// этом режиме клиент представляется штатной почтой своей платформы
// (2.2.x, просьба владельца 10.11.2026 — механизм для всех платформ):
//   · Android — почта Android («Android-Android/14 (Pixel 7/…)»);
//   · iPhone и iPad — Почта iOS («Apple-iPhone15C2/2401.446»);
//   · Windows — Почта Windows для ActiveSync («MSFT-WIN-3/10.0.<сборка>»,
//     тип WindowsMail) и Outlook для EWS;
//   · Mac — Почта Apple: EWS — как Mail на Mac («Mac OS X/…;
//     ExchangeWebServices/…; Mail/16.0 (…)»), ActiveSync — как Почта iPad
//     (у Mail на Mac ActiveSync нет; iPad-приложения на Mac — обычное дело);
//   · Linux — EWS как Thunderbird, ActiveSync — как почта Android (у Linux
//     нет своего клиента ActiveSync, который пропускают шлюзы).
// Сетевой стек системы (отпечаток TLS как у штатной почты) — пока только на
// Android и iPhone; на компьютерах — только представление.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceUserAgent {
  DeviceUserAgent._();

  static String? _cached;
  static String? _deviceType;

  /// Provision → DeviceInformation (EAS 16). На Android — как раньше
  /// («Android», «Mail»); на iPhone — модель и система, как у Почты iOS.
  static String _model = 'Android';
  static String _os = 'Android';
  static String _friendlyName = 'Mail';
  static String get deviceModel => _model;
  static String get deviceOs => _os;
  static String get deviceFriendlyName => _friendlyName;
  static String _language = 'en-us';
  /// OSLanguage для Provision: на iPhone — язык системы («ru-RU»), как у
  /// Почты iOS (снимок сервера 17.10.2026); на Android — как раньше.
  static String get deviceLanguage => _language;

  static const _compatKey = 'eas_compat_user_agent';
  static bool _compat = false;
  static String? _compatUa;

  /// User-Agent EWS (и Autodiscover ящика EWS) в режиме совместимости, если
  /// он у платформы другой, чем у ActiveSync (Windows — Outlook, Mac — Mail,
  /// Linux — Thunderbird).
  static String? _compatEwsUa;

  /// Тип и сведения об устройстве (Provision) в режиме совместимости, если
  /// они не такие, как без него (Mac — как iPad).
  static String? _compatType;
  static String? _compatModel;
  static String? _compatOs;
  static String? _compatFriendly;

  /// User-Agent, с которым такой шлюз пропускал ActiveSync в проверочном
  /// движке (connect_test, июнь 2026). На Android берутся реальные версия
  /// и модель устройства.
  static const String _compatFallback = 'Android-Android/13 (Pixel 6/TP1A.221005.002)';

  /// Включён ли режим совместимости со шлюзом — по умолчанию для новых
  /// ящиков (экран входа, список аккаунтов).
  static bool get compatMode => _compat;

  /// Ящики, для которых режим включён/выключен явно. Раньше режим был один
  /// на всё приложение: переключатель в окне повторного входа одного ящика
  /// менял его для всех — у соседнего ящика «пропадала маскировка».
  static const _compatOnKey = 'eas_compat_accounts_on';
  static const _compatOffKey = 'eas_compat_accounts_off';
  static Set<String> _on = {};
  static Set<String> _off = {};

  /// Режим совместимости для конкретного ящика.
  static bool compatFor(String accountId) =>
      _on.contains(accountId) || (_compat && !_off.contains(accountId));

  static Future<void> setCompatFor(String accountId, bool on) async {
    (on ? _on : _off).add(accountId);
    (on ? _off : _on).remove(accountId);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_compatOnKey, _on.toList());
      await p.setStringList(_compatOffKey, _off.toList());
    } catch (_) {}
  }

  /// User-Agent для ящика (с учётом его режима совместимости). [ews] —
  /// ящик EWS: у компьютеров в режиме совместимости — свой клиент EWS.
  static String valueFor(String accountId, {bool ews = false}) => compatFor(accountId)
      ? ((ews ? _compatEwsUa : null) ?? _compatUa ?? _compatFallback)
      : (_cached ?? _fallback);

  /// Сведения об устройстве для Provision с учётом режима ящика.
  static String deviceModelFor(String accountId) => compatFor(accountId) ? (_compatModel ?? _model) : _model;
  static String deviceOsFor(String accountId) => compatFor(accountId) ? (_compatOs ?? _os) : _os;
  static String deviceFriendlyNameFor(String accountId) =>
      compatFor(accountId) ? (_compatFriendly ?? _friendlyName) : _friendlyName;

  static String deviceTypeFor(String accountId) =>
      compatFor(accountId) ? _compatDeviceType : _nativeDeviceType;

  /// Тип устройства в режиме совместимости: на iPhone — как у Почты iOS
  /// (1.6.12; раньше и с iPhone приложение называло себя Android-устройством,
  /// и шлюз видел расхождение с отпечатком TLS iOS).
  static String get _compatDeviceType =>
      _compatType ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? (_deviceType ?? 'iPhone') : 'Android');

  /// Включить/выключить режим совместимости (сохраняется). Уже открытые
  /// подключения Exchange нужно переоткрыть — UA задаётся при подключении.
  static Future<void> setCompatMode(bool on) async {
    _compat = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_compatKey, on);
    } catch (_) {}
  }

  /// User-Agent Почты iOS для ActiveSync: «Apple-iPhone15C2/2401.446» —
  /// модель с «C» вместо запятой и номер сборки iOS (24A446: 24, буква A —
  /// 01, 446). Без номера сборки — по версии системы.
  static String appleMailUserAgent(String machine, String osVersion) {
    final model = (machine.isEmpty ? 'iPhone' : machine).replaceAll(',', 'C');
    final m = RegExp(r'Build\s+(\d+)([A-Z])(\d+)').firstMatch(osVersion);
    String build;
    if (m != null) {
      final letter = m.group(2)!.codeUnitAt(0) - 64;
      build = '${m.group(1)}${letter.toString().padLeft(2, '0')}.${m.group(3)}';
    } else {
      final v = RegExp(r'(\d+)\.(\d+)').firstMatch(osVersion);
      build = v == null ? '2101.0' : '${int.parse(v.group(1)!) + 4}${v.group(2)!.padLeft(2, '0')}.0';
    }
    return 'Apple-$model/$build';
  }

  /// Почта Windows (ActiveSync): «MSFT-WIN-3/10.0.<сборка>».
  static String windowsMailUserAgent(int build) => 'MSFT-WIN-3/10.0.${build > 0 ? build : 19045}';

  /// Outlook для Windows (EWS).
  static const outlookUserAgent = 'Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook 16.0.18129; Pro)';

  /// Mail на Mac (EWS): «Mac OS X/14.6.1 (23G93); ExchangeWebServices/10.0
  /// (269); Mail/16.0 (3774.600.62)». Сборка Mail — по версии системы.
  static String macMailEwsUserAgent(String version, String build) {
    final major = int.tryParse(version.split('.').first) ?? 14;
    final mail = switch (major) {
      <= 12 => '3696.120.41.1.1',
      13 => '3731.700.6',
      14 => '3774.600.62',
      _ => '3826.400.131.1.6',
    };
    final b = build.isEmpty ? '' : ' ($build)';
    return 'Mac OS X/$version$b; ExchangeWebServices/10.0 (269); Mail/16.0 ($mail)';
  }

  /// Версия iOS/iPadOS той же поры, что macOS [macVersion] (macOS 15 — iOS
  /// 18; с 26 номера общие): для Почты iPad на Mac.
  static String iosVersionForMac(String macVersion) {
    final parts = macVersion.split('.');
    final major = int.tryParse(parts.first) ?? 15;
    final minor = parts.length > 1 ? parts[1] : '0';
    final ios = major >= 26 ? major : major + 3;
    return '$ios.$minor';
  }

  /// Thunderbird на Linux (EWS).
  static const thunderbirdUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Thunderbird/140.5.0';

  /// Язык системы для Provision («ru-RU»).
  static String? _systemLanguage() {
    final loc = Platform.localeName.split('.').first.replaceAll('_', '-');
    return RegExp(r'^[a-z]{2}(-[A-Z]{2})?$').hasMatch(loc) ? loc : null;
  }

  /// Нейтральный фолбэк (без обмана) — до прогрева кэша или при ошибке.
  static const String _fallback = 'Ogneliss/1.0.0';

  /// Синхронный доступ: кэш или фолбэк. Не бросает.
  static String get value =>
      _compat ? (_compatUa ?? _compatFallback) : (_cached ?? _fallback);

  /// EAS DeviceType по реальной платформе (не выдумываем).
  static String get deviceType => _compat ? _compatDeviceType : _nativeDeviceType;

  static String get _nativeDeviceType {
    if (_deviceType != null) return _deviceType!;
    if (kIsWeb) return 'Browser';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'iPhone';
    if (defaultTargetPlatform == TargetPlatform.android) return 'Android';
    return 'Computer';
  }

  /// Прогрев кэша (вызвать один раз при старте). Идемпотентно.
  static Future<String> warmUp() async {
    try {
      final p = await SharedPreferences.getInstance();
      // На iPhone режим совместимости по умолчанию включён (1.6.12): это
      // запросы через сетевой стек iOS с User-Agent Почты iPhone — так,
      // как работает штатная Почта. Без него шлюз перед Exchange отвечал
      // 403 «If you are not a bot» (журналы пользователей iPhone 16.10).
      _compat = p.getBool(_compatKey) ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
      _on = (p.getStringList(_compatOnKey) ?? const []).toSet();
      _off = (p.getStringList(_compatOffKey) ?? const []).toSet();
    } catch (_) {}
    if (_cached != null) return _cached!;
    var version = '1.0.0';
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.version.isNotEmpty) version = pkg.version;
    } catch (_) {/* оставляем дефолт версии */}

    final app = 'Ogneliss/$version';
    try {
      if (kIsWeb) {
        _cached = app;
        _deviceType = 'Browser';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await DeviceInfoPlugin().androidInfo;
        _cached = '$app (Android ${a.version.release}; ${a.model})';
        _compatUa = 'Android-Android/${a.version.release} (${a.model}/${a.display})';
        _deviceType = 'Android';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        // Симулятор отдаёт архитектуру Mac («arm64»), а не модель: берём
        // модель симулируемого iPhone — иначе UA был бы «Apple-arm64/…».
        var machine = i.utsname.machine;
        if (!machine.startsWith('iPhone') && !machine.startsWith('iPad')) {
          machine = Platform.environment['SIMULATOR_MODEL_IDENTIFIER'] ?? 'iPhone15,2';
        }
        _cached = '$app (iOS ${i.systemVersion}; $machine)';
        _compatUa = appleMailUserAgent(machine, Platform.operatingSystemVersion);
        _deviceType = machine.startsWith('iPad') ? 'iPad' : 'iPhone';
        _model = (machine.isEmpty ? 'iPhone' : machine).replaceAll(',', 'C');
        final build = RegExp(r'Build\s+(\w+)').firstMatch(Platform.operatingSystemVersion)?.group(1);
        _os = 'iOS ${i.systemVersion}${build == null ? '' : ' $build'}';
        _friendlyName = machine.startsWith('iPad') ? 'iPad' : 'iPhone';
        final loc = Platform.localeName.split('.').first.replaceAll('_', '-');
        if (RegExp(r'^[a-z]{2}(-[A-Z]{2})?$').hasMatch(loc)) _language = loc;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        _cached = '$app (Windows)';
        _deviceType = 'Computer';
        final w = await DeviceInfoPlugin().windowsInfo;
        // Сведения для Provision — настоящие: система, сборка, имя компьютера.
        _model = 'PC';
        _os = 'Windows 10.0.${w.buildNumber}';
        _friendlyName = w.computerName.isEmpty ? 'PC' : w.computerName;
        _language = _systemLanguage()?.toLowerCase() ?? _language;
        _compatUa = windowsMailUserAgent(w.buildNumber);
        _compatEwsUa = outlookUserAgent;
        _compatType = 'WindowsMail';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        _cached = '$app (macOS)';
        _deviceType = 'Computer';
        final m = await DeviceInfoPlugin().macOsInfo;
        final version = '${m.majorVersion}.${m.minorVersion}${m.patchVersion > 0 ? '.${m.patchVersion}' : ''}';
        final build = RegExp(r'Build\s+(\w+)').firstMatch(Platform.operatingSystemVersion)?.group(1) ?? '';
        _model = m.model.isEmpty ? 'Mac' : m.model;
        _os = 'macOS $version${build.isEmpty ? '' : ' $build'}';
        _friendlyName = m.computerName.isEmpty ? 'Mac' : m.computerName;
        _language = _systemLanguage() ?? _language;
        // ActiveSync — как Почта iPad (у Mail на Mac ActiveSync нет), EWS —
        // как Mail на Mac.
        final ios = iosVersionForMac(version);
        _compatUa = appleMailUserAgent('iPad13,1', ios);
        _compatEwsUa = macMailEwsUserAgent(version, build);
        _compatType = 'iPad';
        _compatModel = 'iPad13C1';
        _compatOs = 'iOS $ios';
        _compatFriendly = 'iPad';
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        _cached = '$app (Linux)';
        _deviceType = 'Computer';
        _model = 'PC';
        _os = 'Linux';
        _friendlyName = Platform.localHostname.isEmpty ? 'Linux' : Platform.localHostname;
        _language = _systemLanguage()?.toLowerCase() ?? _language;
        // ActiveSync — как почта Android (как раньше), EWS — как Thunderbird.
        _compatEwsUa = thunderbirdUserAgent;
        _compatModel = 'Android';
        _compatOs = 'Android';
        _compatFriendly = 'Mail';
      } else {
        _cached = app;
      }
    } catch (_) {
      // Любой сбой плагина — честный минимальный UA без модели.
      _cached = app;
    }
    return _cached!;
  }
}

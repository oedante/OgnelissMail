// lib/core/platform/platform_diagnostics.dart
// Что мешает фоновой работе и уведомлениям на этом устройстве.
//
// Android: корзина ожидания (App Standby Bucket), «Батарея → Ограничено»
// (isBackgroundRestricted), исключение из оптимизации батареи, экономия
// энергии и трафика, точные будильники, разрешение и каналы уведомлений,
// оболочка производителя (MIUI/HyperOS, EMUI/MagicOS, ColorOS/OxygenOS,
// Funtouch/OriginOS, One UI, MyOS/nubia UI…) и причины, по которым система
// завершала процесс (Android 11+).
// iOS: «Обновление контента», режим энергосбережения, разрешение на
// уведомления.
//
// Всё это пишется в журнал при запуске, в пакет диагностики и показывается
// на экране «Разрешения» с кнопками исправления.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';

/// Проблема, из-за которой почта в фоне может не приходить.
enum BgIssue {
  notificationsOff,
  /// Android: уведомления разрешены, но категория «Почта» выключена (1.6.44).
  mailChannelOff,
  batteryOptimized,
  backgroundRestricted,
  standbyRare,
  dataSaver,
  exactAlarmsOff,
  powerSave,
  oemManager,
  iosRefreshOff,
  iosLowPower,
}

class PlatformDiagnostics {
  PlatformDiagnostics._();

  static const _android = MethodChannel('ogneliss/foreground_sync');
  static const _ios = MethodChannel('ogneliss/platform');
  static const _kExitSince = 'diag_exit_since_ms';

  /// Сведения об устройстве (кэш оболочки производителя — getprop медленный).
  static Map<String, dynamic>? _full;

  static bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Полные сведения ([light] — без оболочки производителя, для частых замеров).
  static Future<Map<String, dynamic>> collect({bool light = false}) async {
    if (!_mobile) return const {};
    try {
      if (Platform.isAndroid) {
        final full = !light || _full == null;
        final raw = await _android.invokeMethod<Map>('diagnostics', {'full': full});
        final m = Map<String, dynamic>.from(raw ?? const {});
        if (full) {
          _full = m;
        } else {
          m['rom'] = _full?['rom'];
          m['romVersion'] = _full?['romVersion'];
        }
        return m;
      }
      final raw = await _ios.invokeMethod<Map>('diagnostics');
      return Map<String, dynamic>.from(raw ?? const {});
    } catch (_) {
      // Фоновый изолят: каналов приложения там нет.
      return const {};
    }
  }

  /// Семейство прошивки для подсказок: xiaomi, huawei, honor, oppo, oneplus,
  /// realme, vivo, samsung, zte, nubia, asus, meizu, pixel, other.
  static String family(Map<String, dynamic> d) {
    final m = '${d['manufacturer'] ?? ''} ${d['brand'] ?? ''}'.toLowerCase();
    const keys = ['xiaomi', 'redmi', 'poco', 'huawei', 'honor', 'oneplus', 'oppo', 'realme',
      'vivo', 'iqoo', 'samsung', 'nubia', 'zte', 'asus', 'meizu', 'google', 'motorola', 'tecno', 'infinix'];
    for (final k in keys) {
      if (m.contains(k)) {
        return switch (k) {
          'redmi' || 'poco' => 'xiaomi',
          'iqoo' => 'vivo',
          'google' => 'pixel',
          _ => k,
        };
      }
    }
    return 'other';
  }

  /// Производители с собственным «оптимизатором», который закрывает
  /// приложения в фоне (по опыту dontkillmyapp.com).
  static bool hasOemManager(Map<String, dynamic> d) => const {
        'xiaomi', 'huawei', 'honor', 'oppo', 'oneplus', 'realme', 'vivo',
        'samsung', 'zte', 'nubia', 'asus', 'meizu', 'tecno', 'infinix',
      }.contains(family(d));

  /// Android: категория «Почта» выключена в настройках уведомлений телефона
  /// (1.6.44). Разрешение на уведомления при этом есть, и прежняя проверка
  /// ничего не замечала, а о письмах телефон молчал. Канал «Почта» —
  /// email_default_<звук><вибрация>; выключенный — важность 0.
  static bool mailChannelsOff(Map<String, dynamic> d) {
    final ch = d['channels'];
    if (ch is! List) return false;
    final mail = [
      for (final c in ch)
        if (c is Map && '${c['id']}'.startsWith('email_default')) c,
    ];
    return mail.isNotEmpty && mail.every((c) => c['importance'] == 0);
  }

  static List<BgIssue> issues(Map<String, dynamic> d) {
    final out = <BgIssue>[];
    if (d.isEmpty) return out;
    if (Platform.isIOS) {
      if (d['notifications'] == 'denied') out.add(BgIssue.notificationsOff);
      if (d['backgroundRefresh'] != null && d['backgroundRefresh'] != 'available') out.add(BgIssue.iosRefreshOff);
      if (d['lowPowerMode'] == true) out.add(BgIssue.iosLowPower);
      return out;
    }
    if (d['notificationsEnabled'] == false) out.add(BgIssue.notificationsOff);
    if (d['notificationsEnabled'] != false && mailChannelsOff(d)) out.add(BgIssue.mailChannelOff);
    if (d['backgroundRestricted'] == true) out.add(BgIssue.backgroundRestricted);
    if (d['ignoringBatteryOptimizations'] == false) out.add(BgIssue.batteryOptimized);
    final bucket = d['standbyBucket'];
    if (bucket == 'rare' || bucket == 'restricted') out.add(BgIssue.standbyRare);
    if (d['dataSaver'] == 'on') out.add(BgIssue.dataSaver);
    if (d['exactAlarms'] == false) out.add(BgIssue.exactAlarmsOff);
    if (d['powerSaveMode'] == true) out.add(BgIssue.powerSave);
    if (hasOemManager(d)) out.add(BgIssue.oemManager);
    return out;
  }

  /// Одна строка для журнала.
  static String summary(Map<String, dynamic> d) {
    if (d.isEmpty) return Platform.operatingSystem;
    if (Platform.isIOS) {
      return '${d['system']} (${d['model']}), обновление контента: ${d['backgroundRefresh']}, '
          'энергосбережение: ${d['lowPowerMode'] == true ? 'вкл' : 'выкл'}, '
          'уведомления: ${d['notifications']}, заряд ${d['batteryPct']}%${d['charging'] == true ? ' (заряжается)' : ''}';
    }
    final rom = (d['rom'] ?? '').toString();
    final ch = (d['channels'] as List?)
        ?.map((c) => '${(c as Map)['id']}=${c['importance']}')
        .join(',');
    return 'Android ${d['release']} (SDK ${d['sdk']}), ${d['manufacturer']} ${d['model']}'
        '${rom.isNotEmpty ? ', $rom ${d['romVersion']}' : ''}; '
        'батарея: ${d['ignoringBatteryOptimizations'] == true ? 'без ограничений' : 'оптимизация'}, '
        'фон ограничен: ${d['backgroundRestricted'] == true ? 'ДА' : 'нет'}, '
        'корзина: ${d['standbyBucket'] ?? '?'}, '
        'экономия энергии: ${d['powerSaveMode'] == true ? 'вкл' : 'выкл'}, '
        'экономия трафика: ${d['dataSaver'] ?? '?'}, '
        'точные будильники: ${d['exactAlarms'] == true ? 'да' : 'нет'}, '
        'уведомления: ${d['notificationsEnabled'] == true ? 'да' : 'НЕТ'}'
        '${ch != null && ch.isNotEmpty ? ' [$ch]' : ''}, '
        'экран: ${d['interactive'] == true ? 'вкл' : 'выкл'}${d['deviceIdleMode'] == true ? ' (Doze)' : ''}, '
        'заряд ${d['batteryPct']}%${d['charging'] == true ? ' (заряжается)' : ''}, '
        'служба: ${d['foregroundService'] == true ? 'работает' : 'нет'}'
        '${d['networkBlocked'] == true ? ', сеть: ЗАКРЫТА системой' : ''}';
  }

  /// Короткое состояние для каждой фоновой задачи в журнале.
  static String brief(Map<String, dynamic> d) {
    if (d.isEmpty) return '';
    if (Platform.isIOS) {
      return 'заряд ${d['batteryPct']}%${d['lowPowerMode'] == true ? ', энергосбережение' : ''}';
    }
    final parts = <String>[
      'экран ${d['interactive'] == true ? 'вкл' : 'выкл'}',
      if (d['deviceIdleMode'] == true) 'Doze',
      if (d['powerSaveMode'] == true) 'энергосбережение',
      if (d['standbyBucket'] != null) 'корзина ${d['standbyBucket']}',
      'заряд ${d['batteryPct']}%${d['charging'] == true ? '+' : ''}',
      if (d['foregroundService'] != true) 'без службы',
      // 1.6.43: сеть приложению закрыта системой (Doze, ограничения фона).
      if (d['networkBlocked'] == true) 'сеть закрыта',
    ];
    return parts.join(', ');
  }

  /// Почему система завершала процесс с прошлой проверки (Android 11+).
  static Future<List<Map<String, dynamic>>> newExitReasons(SharedPreferences prefs) async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final since = prefs.getInt(_kExitSince) ?? 0;
      final raw = await _android.invokeMethod<List>('exitReasons', {'since': since});
      final list = [for (final e in raw ?? const []) Map<String, dynamic>.from(e as Map)]
        ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      if (list.isNotEmpty) await prefs.setInt(_kExitSince, list.last['ts'] as int);
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Понятное имя причины завершения процесса.
  static String exitReasonText(String r) => switch (r) {
        'low_memory' => 'нехватка памяти',
        'user_requested' => 'закрыто пользователем (смахивание или «Остановить»)',
        'user_stopped' => 'остановлено пользователем',
        'other' => 'завершено системой или оптимизатором производителя',
        'signaled' => 'принудительно завершено (оптимизатор производителя?)',
        'excessive_resource_usage' => 'слишком большое потребление ресурсов в фоне',
        'freezer' => 'заморожено системой',
        'crash' || 'crash_native' => 'сбой приложения',
        'anr' => 'приложение не отвечало (ANR)',
        'package_updated' => 'обновление приложения',
        'permission_change' => 'изменены разрешения',
        'exit_self' => 'завершилось само',
        _ => r,
      };

  /// При запуске: устройство, ограничения, причины прошлых завершений.
  /// Возвращает новые записи о завершении процесса (для журнала фона).
  static Future<List<Map<String, dynamic>>> logStartup(SharedPreferences prefs) async {
    if (!_mobile) return const [];
    final d = await collect();
    AppLogger.info('Платформа: ${summary(d)}');
    final iss = issues(d);
    if (iss.isNotEmpty) {
      AppLogger.warning('Фоновая работа может быть ограничена: ${iss.map((e) => e.name).join(', ')}'
          '${hasOemManager(d) ? ' (оболочка ${family(d)} — проверьте автозапуск и «без ограничений»)' : ''}');
    }
    final exits = await newExitReasons(prefs);
    for (final e in exits) {
      final at = DateTime.fromMillisecondsSinceEpoch(e['ts'] as int);
      AppLogger.info('Процесс был завершён ${at.toIso8601String().substring(0, 19)}: '
          '${exitReasonText('${e['reason']}')} [${e['reason']}, importance ${e['importance']}'
          '${e['pid'] != null ? ', pid ${e['pid']}' : ''}'
          '${(e['process'] as String?)?.isNotEmpty == true ? ', ${e['process']}' : ''}'
          '${(e['description'] as String?)?.isNotEmpty == true ? ', ${e['description']}' : ''}]');
      // Падение в машинном коде (1.7.2+114): сигнал, причина и библиотеки
      // из записи системы — где именно упало.
      final trace = e['trace'] as String?;
      if (trace != null && trace.isNotEmpty) AppLogger.warning('Сбой в машинном коде: $trace');
    }
    return exits;
  }

  /// Открыть экран автозапуска/фоновой работы производителя (Android).
  /// Возвращает, что открылось ('' — ничего).
  static Future<String> openOemSettings() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      final r = await _android.invokeMethod<String>('openOemSettings') ?? '';
      AppLogger.info('Настройки фоновой работы производителя: ${r.isEmpty ? 'не найдены' : r}');
      return r;
    } catch (e) {
      AppLogger.warning('Настройки производителя: $e');
      return '';
    }
  }

  /// Android: настройки уведомлений приложения (включить категорию «Почта»).
  /// false — не открылось (вызывающий откроет сведения о приложении).
  static Future<bool> openNotificationSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return (await _android.invokeMethod<bool>('openAppNotificationSettings')) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAppDetails() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _android.invokeMethod('openAppDetails');
    } catch (_) {}
  }
}

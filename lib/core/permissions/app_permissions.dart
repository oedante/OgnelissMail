// lib/core/permissions/app_permissions.dart
// Разрешения ОС: что приложение просит, зачем и когда.
//
// Правила:
//  · при запуске ничего не спрашиваем — системный диалог появляется только
//    в момент, когда функция действительно нужна (диктовка → микрофон,
//    выгрузка в календарь телефона → календарь и т.д.);
//  · перед системным диалогом — короткое пояснение «зачем», чтобы
//    пользователь не отказал по привычке;
//  · если разрешение отклонено навсегда, Android больше не покажет диалог —
//    предлагаем открыть настройки приложения;
//  · после входа в первый ящик один раз показываем экран «Разрешения»
//    (maybeShowSetup): все разрешения с пояснением и «Разрешить всё».
//
// Все разрешения с состоянием и кнопками — экран «Настройки → Разрешения».

import 'dart:io' show Platform;
import '../theme/app_icons.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import '../../l10n/app_localizations.dart';

enum AppPermission {
  notifications,
  contacts,
  calendar,
  exactAlarms,
  battery,
}

/// Состояние для экрана разрешений.
enum AppPermissionState { granted, denied, blocked, notApplicable }

class AppPermissionInfo {
  final AppPermission id;
  final IconData icon;
  final String titleKey;
  final String purposeKey;

  /// Особый доступ: Android открывает отдельный экран настроек, а не диалог.
  final bool special;

  const AppPermissionInfo(this.id, this.icon, this.titleKey, this.purposeKey,
      {this.special = false});
}

class AppPermissions {
  AppPermissions._();

  static const all = <AppPermissionInfo>[
    AppPermissionInfo(AppPermission.notifications, AppIcons.notifications,
        'permNotifications', 'permNotificationsWhy'),
    AppPermissionInfo(AppPermission.contacts, AppIcons.contacts,
        'permContacts', 'permContactsWhy'),
    AppPermissionInfo(AppPermission.calendar, AppIcons.event,
        'permCalendar', 'permCalendarWhy'),
    AppPermissionInfo(AppPermission.exactAlarms, AppIcons.alarm,
        'permExactAlarms', 'permExactAlarmsWhy', special: true),
    AppPermissionInfo(AppPermission.battery, AppIcons.battery_saver,
        'permBattery', 'permBatteryWhy', special: true),
  ];

  static AppPermissionInfo info(AppPermission p) => all.firstWhere((i) => i.id == p);

  /// Разрешения ОС есть только на мобильных платформах.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Permission? _os(AppPermission p) {
    switch (p) {
      case AppPermission.notifications:
        return Permission.notification;
      case AppPermission.contacts:
        return Permission.contacts;
      case AppPermission.calendar:
        return Permission.calendarFullAccess;
      case AppPermission.exactAlarms:
        return Platform.isAndroid ? Permission.scheduleExactAlarm : null;
      case AppPermission.battery:
        return null; // не разрешение, а системный список — см. _battery*
    }
  }

  static const _fgChannel = MethodChannel('ogneliss/foreground_sync');

  /// Работа в фоне без ограничений — не разрешение, а исключение из
  /// оптимизации батареи. Прямой запрос (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
  /// Google Play почтовым клиентам не разрешает, поэтому открываем системный
  /// список, где пользователь выбирает приложение сам.
  static Future<AppPermissionState> _batteryState() async {
    try {
      final ok = await _fgChannel.invokeMethod<bool>('batteryUnrestricted');
      return ok == true ? AppPermissionState.granted : AppPermissionState.denied;
    } catch (_) {
      return AppPermissionState.notApplicable;
    }
  }

  static Future<AppPermissionState> state(AppPermission p) async {
    if (!supported) return AppPermissionState.notApplicable;
    if (p == AppPermission.battery) {
      if (!Platform.isAndroid) return AppPermissionState.notApplicable;
      return _batteryState();
    }
    final os = _os(p);
    if (os == null) return AppPermissionState.notApplicable;
    try {
      final s = await os.status;
      if (s.isGranted || s.isLimited || s.isProvisional) return AppPermissionState.granted;
      if (s.isPermanentlyDenied || s.isRestricted) return AppPermissionState.blocked;
      return AppPermissionState.denied;
    } catch (e) {
      AppLogger.warning('Разрешение $p: статус недоступен ($e)');
      return AppPermissionState.notApplicable;
    }
  }

  /// Получить разрешение перед использованием функции. true — можно работать.
  /// [explain] — показать пояснение перед системным диалогом.
  static Future<bool> ensure(BuildContext context, AppPermission p,
      {bool explain = true}) async {
    if (!supported) return true;
    if (p == AppPermission.battery) return _ensureBattery(context);
    final os = _os(p);
    if (os == null) return true;
    final st = await state(p);
    if (st == AppPermissionState.granted || st == AppPermissionState.notApplicable) {
      return true;
    }
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context);
    final inf = info(p);

    if (st == AppPermissionState.blocked && !inf.special) {
      // Android больше не покажет системный диалог — только настройки.
      final go = await _dialog(context,
          icon: inf.icon,
          title: l10n.tr(inf.titleKey),
          body: '${l10n.tr(inf.purposeKey)}\n\n${l10n.tr('permBlockedHint')}',
          ok: l10n.tr('permOpenSettings'),
          cancel: l10n.tr('permNotNow'));
      if (go) await openAppSettings();
      return false;
    }

    if (explain) {
      final go = await _dialog(context,
          icon: inf.icon,
          title: l10n.tr(inf.titleKey),
          body: l10n.tr(inf.purposeKey),
          ok: l10n.tr(inf.special ? 'permOpenSettings' : 'permAllow'),
          cancel: l10n.tr('permNotNow'));
      if (!go) return false;
    }
    try {
      final s = await os.request();
      AppLogger.info('Разрешение $p: ${s.isGranted ? 'разрешено' : 'не разрешено ($s)'}');
      return s.isGranted || s.isLimited;
    } catch (e) {
      AppLogger.warning('Запрос разрешения $p: $e');
      return false;
    }
  }

  static Future<bool> _ensureBattery(BuildContext context) async {
    final st = await _batteryState();
    if (st != AppPermissionState.denied) return true;
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context);
    final inf = info(AppPermission.battery);
    final go = await _dialog(context,
        icon: inf.icon,
        title: l10n.tr(inf.titleKey),
        body: '${l10n.tr(inf.purposeKey)}\n\n${l10n.tr('permBatteryHow')}',
        ok: l10n.tr('permOpenSettings'),
        cancel: l10n.tr('permNotNow'));
    if (!go) return false;
    try {
      await _fgChannel.invokeMethod('openBatterySettings');
    } catch (e) {
      AppLogger.warning('Настройки батареи: $e');
    }
    return false; // результат станет известен после возврата из настроек
  }

  // v2 (1.6.12): новая настройка из двух шагов — показать один раз и тем,
  // кто видел прежнюю.
  static const _setupShownKey = 'perm_setup_shown_v2';

  /// Один раз — сразу после входа в первый ящик (до этого приложению нечего
  /// синхронизировать и не о чем напоминать): экран «Разрешения» со всеми
  /// разрешениями, пояснением к каждому и кнопкой «Разрешить всё».
  /// Повторно — из «Настройки → Разрешения». Администратора устройства этот
  /// экран показывает, только если его требует политика ящика Exchange.
  ///
  /// 1.6.12: настройка идёт до конца всегда — после разрешений (если чего-то
  /// не хватает) шаг 2: календарь и контакты в телефоне, папки для
  /// синхронизации (/setup/mailbox). На компьютере — только шаг 2.
  static Future<void> maybeShowSetup(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_setupShownKey) ?? false) return;
    var missing = false;
    if (supported) {
      for (final i in all) {
        if (await state(i.id) case AppPermissionState.denied || AppPermissionState.blocked) {
          missing = true;
          break;
        }
      }
    }
    await prefs.setBool(_setupShownKey, true);
    if (!context.mounted) return;
    await GoRouter.of(context).push(missing ? '/settings/permissions?setup=1' : '/setup/mailbox');
  }

  /// «Разрешить всё»: системные диалоги подряд (уведомления, контакты,
  /// календарь) — пояснения уже на экране. Особый доступ (точные будильники,
  /// работа в фоне) открывает отдельные экраны Android — по кнопкам.
  static Future<void> requestAllDialogs(BuildContext context) async {
    for (final i in all.where((i) => !i.special)) {
      if (!context.mounted) return;
      if (await state(i.id) == AppPermissionState.denied && context.mounted) {
        await ensure(context, i.id, explain: false);
      }
    }
  }

  static Future<bool> _dialog(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      required String ok,
      required String cancel}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }
}

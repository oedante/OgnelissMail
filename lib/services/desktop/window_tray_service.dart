// lib/services/desktop/window_tray_service.dart
// Управление окном desktop и сворачивание в системный трей.
// При закрытии окно прячется в трей вместо завершения приложения.

import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../l10n/app_localizations.dart';

class WindowTrayService {
  static final SystemTray _systemTray = SystemTray();

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Инициализация окна и трея. Вызывать в main() после ensureInitialized.
  static Future<void> init() async {
    if (!_isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(800, 600),
        center: true,
        title: AppConstants.appName,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      // «Закрыть = свернуть в трей» включаем ТОЛЬКО если трей поднялся.
      // Раньше перехват закрытия ставился до инициализации трея: не нашлась
      // иконка — окно по крестику пряталось, а вернуть его или выйти было
      // нечем (только через диспетчер задач).
      final trayOk = await _initTray();
      await windowManager.setPreventClose(trayOk);
      AppLogger.info('Window инициализировано; трей: ${trayOk ? "есть" : "нет"}');
    } catch (e) {
      AppLogger.warning('Window/Tray init: $e');
    }
  }

  /// Находит путь к иконке трея относительно исполняемого файла.
  /// В собранном приложении рабочая директория ≠ корень проекта,
  /// поэтому ищем рядом с exe (data/flutter_assets) и в стандартных местах.
  static String? _resolveTrayIcon() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Windows-трей понимает только .ico (PNG не загрузится через LoadImage).
    final candidates = Platform.isWindows
        ? [
            '$exeDir\\data\\flutter_assets\\assets\\icons\\tray_icon.ico',
            '$exeDir\\app_icon.ico',
            'assets\\icons\\tray_icon.ico',
            'windows\\runner\\resources\\app_icon.ico',
          ]
        : [
            '$exeDir/data/flutter_assets/assets/icons/app_icon.png',
            'assets/icons/app_icon.png',
          ];
    for (final p in candidates) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }

  /// Строки меню трея на языке интерфейса. BuildContext здесь нет (трей
  /// поднимается в main() до runApp), поэтому язык читается из настроек
  /// (s_locale), иначе — системный (ru/en/de/fr), иначе английский.
  static Future<AppLocalizations> _l10n() async {
    final supported = AppLocalizations.supportedCodes;
    String? lang;
    try {
      lang = (await SharedPreferences.getInstance()).getString('s_locale');
    } catch (_) {}
    if (lang == null || !supported.contains(lang)) {
      final sys = PlatformDispatcher.instance.locale.languageCode;
      lang = supported.contains(sys) ? sys : 'en';
    }
    // Строки языка — из файла assets/l10n (1.7.3): загрузить до чтения.
    return AppLocalizations.load(lang);
  }

  /// Поднять значок в трее. Возвращает true, если трей работает.
  static Future<bool> _initTray() async {
    final iconPath = _resolveTrayIcon();
    try {
      if (iconPath != null) {
        final ok = await _systemTray.initSystemTray(
            title: AppConstants.appName,
            toolTip: AppConstants.appName,
            iconPath: iconPath);
        if (!ok) {
          AppLogger.warning('Tray: системный трей не инициализировался ($iconPath)');
          return false;
        }
      } else {
        AppLogger.warning('Tray: иконка не найдена — работаем без трея');
        return false;
      }

      final l10n = await _l10n();
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: l10n.tr('trayOpen'), onClicked: (_) async {
          await windowManager.show();
          await windowManager.focus();
        }),
        MenuItemLabel(label: l10n.tr('trayHide'), onClicked: (_) async {
          await windowManager.hide();
        }),
        MenuSeparator(),
        MenuItemLabel(label: l10n.tr('trayExit'), onClicked: (_) async {
          await windowManager.setPreventClose(false);
          await windowManager.close();
        }),
      ]);
      await _systemTray.setContextMenu(menu);

      _systemTray.registerSystemTrayEventHandler((eventName) async {
        if (eventName == kSystemTrayEventClick || eventName == kSystemTrayEventDoubleClick) {
          if (await windowManager.isVisible()) {
            await windowManager.focus();
          } else {
            await windowManager.show();
            await windowManager.focus();
          }
        } else if (eventName == kSystemTrayEventRightClick) {
          // На Windows меню по правому клику само не появляется.
          await _systemTray.popUpContextMenu();
        }
      });
      return true;
    } catch (e) {
      AppLogger.warning('Tray init: $e');
      return false;
    }
  }
}

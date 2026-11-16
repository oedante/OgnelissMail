// lib/core/platform/windows_webview_env.dart
// Windows: общее окружение WebView2 с папкой данных в профиле пользователя
// (16.11.2026, замечание владельца «на компьютере не работает отображение
// сложных писем»).
//
// Без окружения плагин создаёт WebView2 с папкой данных рядом с
// ogneliss.exe («ogneliss.exe.WebView2»). Сборка для Windows — переносной
// архив: распакованный в «Program Files» или в другую папку без права
// записи, он не может создать эту папку, и окно WebView2 не создаётся вовсе
// — сложное письмо показывалось упрощённо, перевод Bergamot не запускался.
// Теперь папка — в данных приложения (%APPDATA%\…\WebView2), одна на все
// окна приложения (письмо, перевод).

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

class WindowsWebViewEnv {
  WindowsWebViewEnv._();

  static Future<WebViewEnvironment?>? _env;

  /// Окружение WebView2 (только Windows; на других системах — null). Не
  /// создалось — null: окно попробует окружение по умолчанию, как раньше.
  static Future<WebViewEnvironment?> get() {
    if (kIsWeb || !Platform.isWindows) return Future.value();
    return _env ??= _create();
  }

  static Future<WebViewEnvironment?> _create() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}WebView2');
      await dir.create(recursive: true);
      final env = await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: dir.path));
      AppLogger.info('WebView2: папка данных — в данных приложения');
      return env;
    } catch (e) {
      AppLogger.warning('WebView2: своё окружение не создано — $e');
      return null;
    }
  }
}

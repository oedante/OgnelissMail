// lib/core/platform/portable_mode_io.dart
// Переносная версия для Windows (просьба владельца 13.11.2026).
//
// Включается файлом portable.txt рядом с ogneliss.exe (он есть в архиве
// ogneliss-windows-portable.zip). Тогда всё, что приложение хранит, — в
// папке UserData рядом с программой:
//  · база писем, ключи (DPAPI), вложения, черновики, архив, журналы,
//    модели перевода — папки приложения path_provider (Support, Cache,
//    Temp) указывают в UserData;
//  · настройки (shared_preferences_windows берёт папку у своего
//    PathProviderWindows, а не у общего — подменяем и его);
//  · данные WebView2 (окно письма, редактор, перевод) — переменная
//    WEBVIEW2_USER_DATA_FOLDER до первого окна WebView2.
// «Документы» и «Загрузки» — папки пользователя: сохранённые им файлы идут
// туда, как обычно.
//
// Ключи защищены DPAPI — Windows привязывает их к учётной записи: на
// другом компьютере или под другим пользователем ящики придётся добавить
// заново (база без ключа не открывается). Папка программы недоступна для
// записи (Program Files) — обычный режим, в журнал.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

abstract final class PortableMode {
  /// Файл-признак рядом с exe.
  static const markerName = 'portable.txt';

  /// Папка данных рядом с exe.
  static const dataName = 'UserData';

  static String? _root;

  /// Папка данных (UserData) — в переносном режиме, иначе null.
  static String? get root => _root;
  static bool get active => _root != null;

  /// Почему переносной режим не включился (для диагностики), если файл
  /// portable.txt есть.
  static String? failure;

  /// Включить, если рядом с exe есть portable.txt. Вызывается первым делом в
  /// main() — до базы, настроек и окон WebView2.
  static void init() {
    if (!Platform.isWindows || _root != null) return;
    final String exeDir;
    try {
      exeDir = File(Platform.resolvedExecutable).parent.path;
      if (!File('$exeDir\\$markerName').existsSync()) return;
    } catch (_) {
      return;
    }
    final dir = Directory('$exeDir\\$dataName');
    try {
      dir.createSync(recursive: true);
      final probe = File('${dir.path}\\.write-check');
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
    } catch (e) {
      failure = 'папка программы недоступна для записи: $e';
      return;
    }
    _root = dir.path;
    final paths = PortablePaths(dir.path);
    PathProviderPlatform.instance = paths;
    // Поле помечено «для тестов», но это единственный способ сказать
    // shared_preferences_windows, где лежит файл настроек.
    final prefs = SharedPreferencesStorePlatform.instance;
    // ignore: invalid_use_of_visible_for_testing_member
    if (prefs is SharedPreferencesWindows) prefs.pathProvider = paths;
    final prefsAsync = SharedPreferencesAsyncPlatform.instance;
    // ignore: invalid_use_of_visible_for_testing_member
    if (prefsAsync is SharedPreferencesAsyncWindows) prefsAsync.pathProvider = paths;
    _setEnv('WEBVIEW2_USER_DATA_FOLDER', '${dir.path}\\WebView2');
  }

  /// Переменная окружения процесса (WebView2 читает её при создании окна).
  static void _setEnv(String name, String value) {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final set = kernel32.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('SetEnvironmentVariableW');
      final n = name.toNativeUtf16();
      final v = value.toNativeUtf16();
      try {
        set(n, v);
      } finally {
        calloc.free(n);
        calloc.free(v);
      }
    } catch (_) {}
  }
}

/// Папки приложения в переносном режиме: Support, Cache и Temp — в
/// UserData; «Документы» и «Загрузки» — как обычно.
class PortablePaths extends PathProviderWindows {
  PortablePaths(this.root);
  final String root;

  String _sub(String name) {
    final d = Directory('$root\\$name');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async => _sub('Support');

  @override
  Future<String?> getApplicationCachePath() async => _sub('Cache');

  @override
  Future<String?> getTemporaryPath() async => _sub('Temp');
}

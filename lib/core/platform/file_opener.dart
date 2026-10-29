// lib/core/platform/file_opener.dart
// Открыть файл внешним приложением (1.6.2). На Android — свой канал
// ogneliss/open_file (FileOpenBridge.kt): канал плагина open_filex живёт,
// только пока плагин подключён к окну, и после пересоздания окна у общего
// движка пропадал («MissingPluginException … open_file», 13.10.2026).
// iOS и компьютер — open_filex.

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

enum OpenFileOutcome { done, noApp, error }

class FileOpener {
  FileOpener._();

  static const _channel = MethodChannel('ogneliss/open_file');

  /// [name] — имя файла, как в письме. Вложение хранится в кэше под
  /// служебным именем (хеш), и внешнее приложение показывало его
  /// («acf2592652c4…pdf» вместо «УВЕДОМЛЕНИЕ Хуснутдинова….pdf», 13.10.2026):
  /// перед открытием делается копия с настоящим именем.
  static Future<OpenFileOutcome> open(String path, {String? mime, String? name}) async {
    path = await namedCopy(path, name);
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final r = await _channel.invokeMethod<String>('open', {'path': path, 'mime': mime});
        switch (r) {
          case 'done':
            return OpenFileOutcome.done;
          case 'no_app':
            return OpenFileOutcome.noApp;
        }
        AppLogger.warning('Открытие файла: $r');
        return OpenFileOutcome.error;
      } on MissingPluginException {
        // Старая сборка без канала — путь плагина.
      } catch (e) {
        AppLogger.warning('Открытие файла: $e');
        return OpenFileOutcome.error;
      }
    }
    try {
      final res = await OpenFilex.open(path, type: mime);
      return switch (res.type) {
        ResultType.done => OpenFileOutcome.done,
        ResultType.noAppToOpen => OpenFileOutcome.noApp,
        _ => OpenFileOutcome.error,
      };
    } catch (e) {
      AppLogger.warning('Открытие файла (open_filex): $e');
      return OpenFileOutcome.error;
    }
  }

  /// Форматы, которые показывает «Просмотр» iOS (QuickLook): PDF, Office и
  /// iWork, RTF, текст, картинки, звук и видео, 3D. Остальное (архивы,
  /// неизвестные форматы) QuickLook показывает пустым экраном с кнопкой
  /// «Скопировать в …», и эта кнопка не срабатывала (замечание владельца
  /// 29.10.2026, ZIP из письма) — такие файлы на iPhone и iPad идут сразу в
  /// лист «Поделиться» (AttachmentSafety.openExternally).
  static const _quickLook = {
    'pdf',
    'doc', 'docx', 'docm', 'dot', 'dotx', 'xls', 'xlsx', 'xlsm', 'xlt', 'xltx',
    'ppt', 'pptx', 'pptm', 'pps', 'ppsx', 'pot', 'potx',
    'pages', 'numbers', 'key', 'rtf', 'rtfd',
    'txt', 'text', 'log', 'md', 'csv', 'tsv', 'xml', 'json',
    'jpg', 'jpeg', 'png', 'gif', 'heic', 'heif', 'tif', 'tiff', 'bmp', 'webp',
    'mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff', 'caf',
    'mp4', 'm4v', 'mov', '3gp',
    'usdz', 'reality',
    // Приглашение и визитка — как раньше, через «Просмотр».
    'ics', 'vcf',
  };

  /// «Просмотр» iOS покажет файл [name] (по расширению).
  static bool quickLookShows(String name) {
    final ext = p.extension(name.trim()).toLowerCase();
    return ext.length > 1 && _quickLook.contains(ext.substring(1));
  }

  /// Недопустимые в именах файлов символы и управляющие — на «_».
  static String safeName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    while (n.startsWith('.')) {
      n = n.substring(1);
    }
    if (n.isEmpty) return '';
    if (n.length > 120) {
      final ext = p.extension(n);
      n = '${n.substring(0, 120 - ext.length)}$ext';
    }
    return n;
  }

  /// Копия [path] под именем [name] в кэше (cache/open/<ключ>/имя); старше
  /// суток — удаляются. Имя уже такое или копия не удалась — исходный путь.
  static Future<String> namedCopy(String path, String? name) async {
    final want = safeName(name ?? '');
    if (want.isEmpty || p.basename(path) == want) return path;
    try {
      final src = File(path);
      if (!await src.exists()) return path;
      final root = Directory(p.join((await getTemporaryDirectory()).path, 'open'));
      if (await root.exists()) {
        final now = DateTime.now();
        await for (final d in root.list()) {
          try {
            if (now.difference((await d.stat()).modified) > const Duration(days: 1)) {
              await d.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
      // Подкаталог по исходному пути: два вложения с одним именем не
      // затирают друг друга.
      var h = 0x811c9dc5;
      for (final c in path.codeUnits) {
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
      }
      final dir = Directory(p.join(root.path, h.toRadixString(16)));
      await dir.create(recursive: true);
      final dst = File(p.join(dir.path, want));
      final srcStat = await src.stat();
      if (!await dst.exists() || (await dst.length()) != srcStat.size ||
          (await dst.stat()).modified.isBefore(srcStat.modified)) {
        await src.copy(dst.path);
      }
      return dst.path;
    } catch (e) {
      AppLogger.debug('Открытие файла: копия с именем не создана ($e)');
      return path;
    }
  }
}

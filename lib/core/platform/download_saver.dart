// lib/core/platform/download_saver.dart
// «Сохранить в Загрузки» одним нажатием (1.6.33, замечание 18.10.2026:
// «нельзя просто сохранить в Загрузки, только дать доступ другому
// приложению»).
//
//  · Android 10+ — общая папка «Загрузки» через MediaStore (FileOpenBridge.kt,
//    метод saveDownload): без разрешений и без диалогов.
//  · Android 7–9 — системный выбор места сохранения (file_picker, SAF).
//  · Windows, Mac, Linux — папка «Загрузки» пользователя (на Mac в песочнице
//    доступ к ней разрешён, см. scripts/build_macos.sh).
//  · iPhone и iPad — общей папки «Загрузки» нет: там остаётся лист
//    «Поделиться» с пунктом «Сохранить в Файлы» ([supported] = false).

import 'dart:async' show unawaited;
import 'dart:io' show File, Platform;

import 'file_pick.dart' show FilePick;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';
import '../logging/app_logger.dart';
import '../security/attachment_safety.dart' show AttachmentSafety;
import 'file_opener.dart';
import '../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

/// Итог сохранения: [name] — имя, под которым файл лёг (система может
/// добавить « (1)»), [path] — полный путь там, где он известен (компьютер).
class SavedDownload {
  final String name;
  final String? path;
  const SavedDownload(this.name, {this.path});
}

class DownloadSaver {
  DownloadSaver._();

  static const _channel = MethodChannel('ogneliss/open_file');

  /// Есть ли «Сохранить в Загрузки» на этой платформе.
  static bool get supported => !kIsWeb && !Platform.isIOS;

  /// Сохранить [path] в «Загрузки» под именем [name]. null — отменено
  /// пользователем (Android 7–9) или не удалось (причина — в журнале).
  static Future<SavedDownload?> save(String path, String name) async {
    if (!supported) return null;
    final safe = FileOpener.safeName(name).isEmpty ? p.basename(path) : FileOpener.safeName(name);
    try {
      if (Platform.isAndroid) {
        final r = await _channel.invokeMethod<String>('saveDownload', {
          'path': path,
          'name': safe,
          'mime': AttachmentSafety.mimeOf(safe),
        });
        if (r == 'unsupported') return await _pickAndSave(path, safe);
        if (r == null) {
          AppLogger.warning('Загрузки: не удалось сохранить «$safe»');
          return null;
        }
        AppLogger.info('Загрузки: сохранён файл (${await File(path).length()} байт)');
        return SavedDownload(r);
      }
      final dir = await getDownloadsDirectory();
      if (dir == null) return await _pickAndSave(path, safe);
      await dir.create(recursive: true);
      final dst = _unique(dir.path, safe);
      await File(path).copy(dst);
      AppLogger.info('Загрузки: сохранён файл на компьютере');
      return SavedDownload(p.basename(dst), path: dst);
    } on MissingPluginException {
      return _pickAndSave(path, safe);
    } catch (e) {
      AppLogger.warning('Загрузки: $e');
      return null;
    }
  }

  /// Сохранить файлы и сказать итог плашкой («Открыть» — у одного файла).
  static Future<void> saveWithFeedback(BuildContext context, List<({String path, String name})> items) async {
    final l10n = AppLocalizations.of(context);
    final saved = <SavedDownload>[];
    var failed = 0;
    for (final it in items) {
      final r = await save(it.path, it.name);
      if (r == null) {
        failed++;
      } else {
        saved.add(r);
      }
    }
    if (saved.isEmpty) {
      if (failed > 0) showInlineError(l10n.tr('saveToDownloadsFailed'));
      return;
    }
    final one = saved.length == 1 && items.length == 1 ? items.first : null;
    final text = saved.length == 1
        ? l10n.tr('savedToDownloads').replaceAll('{name}', saved.first.name)
        : l10n.tr('savedToDownloadsN').replaceAll('{n}', '${saved.length}');
    // Куда сохранилось — строкой вверху с кнопкой «Открыть» (1.8.0).
    showInlineNotice(
      failed == 0 ? text : '$text · ${l10n.tr('saveToDownloadsFailed')}: $failed',
      actionLabel: one == null ? null : l10n.tr('snackOpen'),
      onAction: one == null
          ? null
          : () => unawaited(FileOpener.open(saved.first.path ?? one.path,
              mime: AttachmentSafety.mimeOf(one.name), name: one.name)),
    );
  }

  /// Системный диалог «Сохранить как» (Android 7–9, компьютер без папки
  /// «Загрузки»).
  static Future<SavedDownload?> _pickAndSave(String path, String name) async {
    final bytes = await File(path).readAsBytes();
    final saved = await FilePick.save(fileName: name, bytes: bytes);
    if (saved == null) return null;
    // На компьютере — путь (откроется по «Открыть»), на Android — документ
    // в выбранной папке: имя для показа, путь не нужен. (Своё имя, не path:
    // локальная path ниже по блоку закрывала параметр — ошибка анализатора.)
    final out = saved.path;
    return SavedDownload(out != null ? p.basename(out) : saved.shown, path: out);
  }

  /// «Отчёт.pdf» → «Отчёт (2).pdf», если такой уже есть.
  static String _unique(String dir, String name) {
    var dst = p.join(dir, name);
    if (!File(dst).existsSync()) return dst;
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; i < 1000; i++) {
      dst = p.join(dir, '$base ($i)$ext');
      if (!File(dst).existsSync()) return dst;
    }
    return p.join(dir, '$base ${DateTime.now().millisecondsSinceEpoch}$ext');
  }
}

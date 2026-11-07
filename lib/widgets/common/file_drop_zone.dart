// lib/widgets/common/file_drop_zone.dart
//
// Файлы, перетащенные из Проводника, Finder или файлового менеджера, — на
// окно приложения (1.9.x, просьба владельца 31.10.2026): в новом письме
// они становятся вложениями.
//
// 1.15.0: приём — пакетом super_drag_and_drop (MIT), тем же, что
// перетаскивает вложения из письма наружу. Прежний desktop_drop убран: два
// пакета ставили на окно каждый свой приёмник, и на Windows второй снимал
// первый (RevokeDragDrop) — файлы в новое письмо перестали бы бросаться.
//
// 1.15.1: ещё iPad и Android (файл из «Файлов» или соседнего приложения на
// разделённом экране) и файлы без пути на компьютере — вложение,
// перетащенное из Outlook, письмо из Почты Mac («виртуальный файл»):
// содержимое пишется во временную папку, письмо получает её путь.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/file_opener.dart';
import '../../core/platform/native_drag_drop.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Пути брошенных файлов (папки и пустые пути отброшены не здесь). Файлы
  /// без пути (iPad, Android, «виртуальные») — уже во временной папке.
  final ValueChanged<List<String>> onFiles;

  /// Подпись поверх окна, пока файлы держат над ним.
  final String hint;

  const FileDropZone({super.key, required this.child, required this.onFiles, required this.hint});

  static bool get supported =>
      !kIsWeb &&
      NativeDragDrop.enabled &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isAndroid || Platform.isIOS);

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    if (!FileDropZone.supported) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (e) => e.session.items.any(looksLikeFile) && e.session.allowedOperations.contains(DropOperation.copy)
          ? DropOperation.copy
          : DropOperation.none,
      onDropEnter: (_) => setState(() => _over = true),
      onDropLeave: (_) => setState(() => _over = false),
      onDropEnded: (_) {
        if (mounted && _over) setState(() => _over = false);
      },
      onPerformDrop: (e) async {
        final paths = await receiveDroppedFiles(e.session.items);
        if (paths.isNotEmpty) widget.onFiles(paths);
      },
      child: Stack(children: [
        widget.child,
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(Space.s),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  border: Border.all(color: scheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(AppIcons.attach_file, color: scheme.onPrimaryContainer),
                      const SizedBox(width: Space.s),
                      Text(widget.hint,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Пути брошенных файлов: только адреса file:// (папки и пустые пути
/// отбрасывает тот, кто прикладывает).
Future<List<String>> droppedPaths(List<DropItem> items) async {
  final paths = <String>[];
  for (final item in items) {
    final reader = item.dataReader;
    if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
    final done = Completer<Uri?>();
    final progress = reader.getValue<Uri>(Formats.fileUri, (uri) => done.complete(uri), onError: (e) {
      AppLogger.warning('Брошенный файл не прочитан: $e');
      if (!done.isCompleted) done.complete(null);
    });
    if (progress == null) continue;
    final uri = await done.future;
    if (uri != null && uri.isScheme('file')) {
      final path = uri.toFilePath();
      if (path.isNotEmpty) paths.add(path);
    }
  }
  return paths;
}

/// Типы, которые файлом не считаются: перетащенный текст, ссылка, HTML.
const _textOnly = {
  'text/plain', 'text/html', 'text/uri-list', 'text/x-moz-url', 'public.utf8-plain-text', 'public.plain-text',
  'public.html', 'public.url', 'public.url-name', 'NSStringPboardType', 'CF_UNICODETEXT', 'CF_TEXT', 'HTML Format',
  'UniformResourceLocatorW', 'UniformResourceLocator',
};

/// Похоже на файл: путь к файлу или тип, кроме текста и ссылки. На iPad и
/// Android до броска известны только типы.
bool looksLikeFile(DropItem item) {
  if (item.canProvide(Formats.fileUri)) return true;
  return item.platformFormats.any((f) => !_textOnly.contains(f) && !f.startsWith('text/'));
}

/// Брошенные файлы: путь, если он есть (Проводник, Finder), иначе
/// содержимое — во временную папку (iPad, Android, вложение из Outlook).
Future<List<String>> receiveDroppedFiles(List<DropItem> items, {Directory? into}) async {
  final paths = <String>[];
  Directory? dir = into;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final own = await droppedPaths([item]);
    if (own.isNotEmpty) {
      paths.addAll(own);
      continue;
    }
    final reader = item.dataReader;
    if (reader == null || !looksLikeFile(item)) continue;
    dir ??= Directory(p.join((await getTemporaryDirectory()).path, 'dropped', '${DateTime.now().microsecondsSinceEpoch}'));
    final target = Directory(p.join(dir.path, '$i'));
    final saved = await _saveFile(reader, target, 'file-${i + 1}');
    if (saved != null) paths.add(saved);
  }
  return paths;
}

Future<String?> _saveFile(DataReader reader, Directory dir, String fallbackName) async {
  final done = Completer<String?>();
  final progress = reader.getFile(null, (file) async {
    try {
      final suggested = file.fileName ?? await reader.getSuggestedName();
      var name = FileOpener.safeName(suggested ?? '');
      if (name.isEmpty) name = fallbackName;
      await dir.create(recursive: true);
      final out = File(p.join(dir.path, name));
      final sink = out.openWrite();
      await sink.addStream(file.getStream());
      await sink.close();
      if (!done.isCompleted) done.complete(out.path);
    } catch (e) {
      AppLogger.warning('Брошенный файл не сохранён: $e');
      if (!done.isCompleted) done.complete(null);
    }
  }, onError: (e) {
    AppLogger.warning('Брошенный файл не прочитан: $e');
    if (!done.isCompleted) done.complete(null);
  });
  if (progress == null) return null;
  return done.future;
}

// lib/widgets/common/file_drop_zone.dart
//
// Файлы, перетащенные из Проводника, Finder или файлового менеджера, — на
// окно приложения (1.9.x, просьба владельца 31.10.2026): в новом письме
// они становятся вложениями. Только компьютер (Windows, macOS, Linux).
//
// 1.15.0: приём — пакетом super_drag_and_drop (MIT), тем же, что
// перетаскивает вложения из письма наружу. Прежний desktop_drop убран: два
// пакета ставили на окно каждый свой приёмник, и на Windows второй снимал
// первый (RevokeDragDrop) — файлы в новое письмо перестали бы бросаться.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/native_drag_drop.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Пути брошенных файлов (папки и пустые пути отброшены не здесь).
  final ValueChanged<List<String>> onFiles;

  /// Подпись поверх окна, пока файлы держат над ним.
  final String hint;

  const FileDropZone({super.key, required this.child, required this.onFiles, required this.hint});

  static bool get supported =>
      !kIsWeb && NativeDragDrop.enabled && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (e) => e.session.items.any((i) => i.canProvide(Formats.fileUri)) &&
              e.session.allowedOperations.contains(DropOperation.copy)
          ? DropOperation.copy
          : DropOperation.none,
      onDropEnter: (_) => setState(() => _over = true),
      onDropLeave: (_) => setState(() => _over = false),
      onDropEnded: (_) {
        if (mounted && _over) setState(() => _over = false);
      },
      onPerformDrop: (e) async {
        final paths = await droppedPaths(e.session.items);
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

// lib/widgets/common/file_drop_zone.dart
//
// Файлы, перетащенные из Проводника, Finder или файлового менеджера, — на
// окно приложения (1.9.x, просьба владельца 31.10.2026): в новом письме
// они становятся вложениями. Только компьютер (Windows, macOS, Linux):
// Flutter сам файлы не принимает, плагин desktop_drop (Apache-2.0) на iPad не
// работает, а на Android отдаёт адреса content://, которые не прочитать как
// файл.

import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Пути брошенных файлов (папки и пустые пути отброшены не здесь).
  final ValueChanged<List<String>> onFiles;

  /// Подпись поверх окна, пока файлы держат над ним.
  final String hint;

  const FileDropZone({super.key, required this.child, required this.onFiles, required this.hint});

  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    if (!FileDropZone.supported) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        final paths = [for (final f in d.files) if (f.path.isNotEmpty) f.path];
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

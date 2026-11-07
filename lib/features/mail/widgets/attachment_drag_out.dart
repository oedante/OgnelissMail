// lib/features/mail/widgets/attachment_drag_out.dart
// Перетаскивание вложения из письма наружу — в Проводник, Finder, на рабочий
// стол, в другое приложение рядом на планшете (1.15.0, решение владельца
// 07.11.2026). Пакет super_drag_and_drop (MIT, ядро на Rust): пакет сам
// называет себя экспериментальным, поэтому каждую платформу владелец
// проверяет отдельно (docs/release/OWNER_STEPS_1.15.0.md).
//
// Что получает приложение, куда бросили вложение:
//  · Windows, macOS: файл уже скачан — путь к копии с именем из письма
//    (Проводник и Finder копируют её); не скачан — «виртуальный файл»:
//    вложение скачивается, когда его отпустили.
//  · iPad: «виртуальный файл» (на iPhone система перетаскивание между
//    приложениями не включает).
//  · Android: содержимое файла с его типом (content:// пакета); скачивается,
//    когда его запросит приложение, куда бросили.
//  · Linux: путь к файлу — вложение скачивается до начала перетаскивания.
//
// Политика организации (MDM): «Поделиться» или «Открыть в других
// приложениях» запрещены — перетаскивания нет.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart' show SimpleFileFormat, VirtualFileEventSinkProvider;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/file_opener.dart';
import '../../../core/platform/native_drag_drop.dart';
import '../../../data/models/email_model.dart';
import '../../../services/security/managed_config.dart';

/// Где перетаскивание вложений наружу включено.
class AttachmentDragOut {
  AttachmentDragOut._();

  /// Платформа умеет отдавать файл другому приложению. iPhone — нет: там
  /// система перетаскивание между приложениями не включает, а долгое
  /// нажатие остаётся за листом действий вложения.
  static bool supportedOn(TargetPlatform platform, {required bool tablet}) => switch (platform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.android => true,
    TargetPlatform.iOS => tablet,
    _ => false,
  };

  /// Можно ли сейчас перетаскивать вложения: платформа и политика
  /// организации.
  static bool available(BuildContext context) {
    if (!NativeDragDrop.enabled) return false;
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    if (!supportedOn(defaultTargetPlatform, tablet: tablet)) return false;
    final policy = ManagedPolicy.current;
    return !policy.blocks(ManagedRule.share) && !policy.blocks(ManagedRule.openIn);
  }

  /// На сенсорном экране перетаскивание начинается удержанием — тем же
  /// жестом, что открывал лист действий вложения. Лист тогда — когда
  /// вложение удержали и отпустили, не сдвинув.
  static bool touchDrag(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// Тип файла для систем Apple (UTI) по расширению имени. Неизвестный —
  /// «данные»: Finder и «Файлы» принимают и его, с именем из письма.
  @visibleForTesting
  static String utiFor(String name) => _uti[p.extension(name).toLowerCase().replaceFirst('.', '')] ?? 'public.data';

  static const _uti = {
    'pdf': 'com.adobe.pdf',
    'doc': 'com.microsoft.word.doc',
    'docx': 'org.openxmlformats.wordprocessingml.document',
    'xls': 'com.microsoft.excel.xls',
    'xlsx': 'org.openxmlformats.spreadsheetml.sheet',
    'ppt': 'com.microsoft.powerpoint.ppt',
    'pptx': 'org.openxmlformats.presentationml.presentation',
    'odt': 'org.oasis-open.opendocument.text',
    'ods': 'org.oasis-open.opendocument.spreadsheet',
    'odp': 'org.oasis-open.opendocument.presentation',
    'rtf': 'public.rtf',
    'txt': 'public.plain-text',
    'csv': 'public.comma-separated-values-text',
    'md': 'net.daringfireball.markdown',
    'html': 'public.html',
    'htm': 'public.html',
    'xml': 'public.xml',
    'json': 'public.json',
    'jpg': 'public.jpeg',
    'jpeg': 'public.jpeg',
    'png': 'public.png',
    'gif': 'com.compuserve.gif',
    'heic': 'public.heic',
    'tif': 'public.tiff',
    'tiff': 'public.tiff',
    'bmp': 'com.microsoft.bmp',
    'webp': 'org.webmproject.webp',
    'svg': 'public.svg-image',
    'mp3': 'public.mp3',
    'm4a': 'com.apple.m4a-audio',
    'wav': 'com.microsoft.waveform-audio',
    'mp4': 'public.mpeg-4',
    'mov': 'com.apple.quicktime-movie',
    'zip': 'public.zip-archive',
    '7z': 'org.7-zip.7-zip-archive',
    'rar': 'com.rarlab.rar-archive',
    'gz': 'org.gnu.gnu-zip-archive',
    'eml': 'com.apple.mail.email',
    'ics': 'com.apple.ical.ics',
    'vcf': 'public.vcard',
  };

  /// Формат файла для пакета: UTI на Apple, тип MIME на остальных.
  static SimpleFileFormat formatFor(EmailAttachment att) {
    final mime = att.mimeType.trim().isEmpty ? 'application/octet-stream' : att.mimeType.trim().toLowerCase();
    return SimpleFileFormat(uniformTypeIdentifiers: [utiFor(att.name)], mimeTypes: [mime]);
  }
}

/// Плашка вложения, которую можно вытащить из окна. [localPath] — уже
/// скачанный файл (или null), [fetch] — скачать в кэш и вернуть путь,
/// [onHoldWithoutMove] — удержали и отпустили на месте (сенсорный экран):
/// лист действий вложения.
class AttachmentDragSource extends StatelessWidget {
  const AttachmentDragSource({
    super.key,
    required this.attachment,
    required this.localPath,
    required this.fetch,
    required this.child,
    this.onHoldWithoutMove,
  });

  final EmailAttachment attachment;
  final String? Function() localPath;
  final Future<String?> Function() fetch;
  final VoidCallback? onHoldWithoutMove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AttachmentDragOut.available(context)) return child;
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      dragItemProvider: _item,
      child: DraggableWidget(child: child),
    );
  }

  Future<DragItem?> _item(DragItemRequest request) async {
    final att = attachment;
    final platform = defaultTargetPlatform;
    final item = DragItem(suggestedName: att.name);
    _watchHold(request);
    try {
      final have = localPath();
      final desktopPath = platform == TargetPlatform.windows || platform == TargetPlatform.macOS;
      if (desktopPath && have != null && File(have).existsSync()) {
        // Проводник и Finder копируют файл по пути — копия с именем из
        // письма (в кэше файл лежит под служебным именем).
        item.add(Formats.fileUri(Uri.file(await FileOpener.namedCopy(have, att.name))));
        return item;
      }
      if (item.virtualFileSupported) {
        // Windows, macOS, iPad: файл отдаётся, когда его отпустили.
        item.addVirtualFile(
          format: AttachmentDragOut.formatFor(att),
          provider: (sinkProvider, progress) => unawaited(_writeVirtual(sinkProvider)),
        );
        return item;
      }
      if (platform == TargetPlatform.android) {
        // Содержимое — по запросу приложения, куда бросили.
        item.add(
          AttachmentDragOut.formatFor(att).lazy(() async {
            final path = await fetch();
            if (path == null) throw StateError('вложение не скачано');
            return File(path).readAsBytes();
          }),
        );
        return item;
      }
      // Linux: только путь — файл нужен до начала перетаскивания.
      final path = (have != null && File(have).existsSync()) ? have : await fetch();
      if (path == null) return null;
      item.add(Formats.fileUri(Uri.file(await FileOpener.namedCopy(path, att.name))));
      return item;
    } catch (e) {
      AppLogger.warning('Перетаскивание вложения: $e');
      return null;
    }
  }

  Future<void> _writeVirtual(VirtualFileEventSinkProvider sinkProvider) async {
    try {
      final path = await fetch();
      if (path == null) throw StateError('вложение не скачано');
      final bytes = await File(path).readAsBytes();
      final sink = sinkProvider(fileSize: bytes.length);
      sink.add(bytes);
      sink.close();
    } catch (e) {
      AppLogger.warning('Перетаскивание вложения (файл по запросу): $e');
      try {
        sinkProvider(fileSize: 0)
          ..addError(e)
          ..close();
      } catch (_) {}
    }
  }

  /// Сенсорный экран: удержали и отпустили, не сдвинув, — лист действий.
  void _watchHold(DragItemRequest request) {
    final onHold = onHoldWithoutMove;
    if (onHold == null || !AttachmentDragOut.touchDrag(defaultTargetPlatform)) return;
    final session = request.session;
    // Сдвиг — по самим обновлениям положения сессии (они в координатах
    // экрана, а [request.location] — в координатах окна Flutter).
    Offset? first;
    var moved = false;
    void move() {
      final at = session.lastScreenLocation.value;
      if (at == null) return;
      first ??= at;
      if ((at - first!).distance > 24) moved = true;
    }

    void done() {
      final op = session.dragCompleted.value;
      if (op == null) return;
      session.dragCompleted.removeListener(done);
      session.lastScreenLocation.removeListener(move);
      if (!moved && (op == DropOperation.none || op == DropOperation.userCancelled || op == DropOperation.forbidden)) {
        onHold();
      }
    }

    session.lastScreenLocation.addListener(move);
    session.dragCompleted.addListener(done);
  }
}

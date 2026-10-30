// lib/widgets/common/photo_viewer.dart
// Фото человека на весь экран (1.6.49, как фото профиля в Telegram):
// нажатие на фото в карточке человека. Пальцами — приблизить, касание или
// «Назад» — закрыть. Фото — в исходном размере (в списках оно уменьшено до
// 288 точек, см. photoImage).

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show Uint8List;

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'image_actions.dart';
import 'inline_notice.dart' show showInlineError, showInlineNotice;

/// Картинка без уменьшения: data URI или https-ссылка.
ImageProvider? fullPhotoImage(String? photo) {
  if (photo == null || photo.isEmpty) return null;
  if (photo.startsWith('data:')) {
    final comma = photo.indexOf(',');
    if (comma <= 0) return null;
    try {
      final bytes = base64.decode(photo.substring(comma + 1));
      return bytes.isEmpty ? null : MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
  if (photo.startsWith('https://')) return NetworkImage(photo);
  if (photo.startsWith('http://')) return NetworkImage('https://${photo.substring(7)}');
  return null;
}

Future<void> showPhotoViewer(BuildContext context, {required String photo, String? title}) {
  final image = fullPhotoImage(photo);
  if (image == null) return Future.value();
  return showImageViewer(context, image, title: title);
}

/// Картинка на весь экран (1.8.12: картинка в письме — по нажатию, «иногда
/// они мелкие»): пальцами — приблизить до ×6, касание или «Назад» — закрыть.
/// [bytes] — данные картинки для «Копировать», «Сохранить», «Поделиться»
/// (кнопки — только когда задано); [name] — имя файла, если известно.
Future<void> showImageViewer(BuildContext context, ImageProvider image,
    {String? title, Future<Uint8List?> Function()? bytes, String? name}) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).closeButtonLabel,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _PhotoView(image: image, title: title, bytes: bytes, name: name),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _PhotoView extends StatelessWidget {
  final ImageProvider image;
  final String? title;
  final Future<Uint8List?> Function()? bytes;
  final String? name;
  const _PhotoView({required this.image, this.title, this.bytes, this.name});

  Future<void> _act(BuildContext context, String what) async {
    final l10n = AppLocalizations.of(context);
    final b = await bytes?.call();
    if (b == null || b.isEmpty) {
      showInlineError(l10n.tr('error'));
      return;
    }
    switch (what) {
      case 'copy':
        if (await ImageActions.copy(b, name: name)) {
          // Android 13+ сам показывает, что скопировано.
          if (Platform.isIOS) showInlineNotice(l10n.tr('copied'));
        } else {
          showInlineError(l10n.tr('error'));
        }
      case 'save':
        final r = await ImageActions.save(b, name: name);
        if (r != null) showInlineNotice(l10n.tr('savedToDownloads').replaceAll('{name}', r.name));
      case 'share':
        await ImageActions.share(b, name: name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final close = MaterialLocalizations.of(context).closeButtonLabel;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Semantics(
                    image: true,
                    label: title,
                    child: Image(image: image, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: Space.xs,
            right: Space.l,
            top: Space.xs,
            child: Row(children: [
              IconButton(
                tooltip: close,
                color: Colors.white,
                icon: const Icon(AppIcons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: (title ?? '').isEmpty
                    ? const SizedBox.shrink()
                    : Text(title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
              ),
              // Копировать, сохранить, поделиться (1.8.12).
              if (bytes != null) ...[
                if (ImageActions.canCopy)
                  IconButton(
                    tooltip: AppLocalizations.of(context).tr('copy'),
                    color: Colors.white,
                    icon: const Icon(AppIcons.content_copy),
                    onPressed: () => _act(context, 'copy'),
                  ),
                IconButton(
                  tooltip: AppLocalizations.of(context).tr('save'),
                  color: Colors.white,
                  icon: const Icon(AppIcons.download),
                  onPressed: () => _act(context, 'save'),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).tr('share'),
                  color: Colors.white,
                  icon: const Icon(AppIcons.share),
                  onPressed: () => _act(context, 'share'),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

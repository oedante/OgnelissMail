// lib/widgets/common/photo_viewer.dart
// Фото человека на весь экран (1.6.49, как фото профиля в Telegram):
// нажатие на фото в карточке человека. Пальцами — приблизить, касание или
// «Назад» — закрыть. Фото — в исходном размере (в списках оно уменьшено до
// 288 точек, см. photoImage).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

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
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).closeButtonLabel,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _PhotoView(image: image, title: title),
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
  const _PhotoView({required this.image, this.title});

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
                maxScale: 4,
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
              if ((title ?? '').isNotEmpty)
                Expanded(
                  child: Text(title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

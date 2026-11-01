// lib/features/mail/widgets/mail_drag.dart
//
// Перетаскивание писем на папку в широком окне (компьютер, планшет): с
// 1.6.28 — одно письмо мышью; 1.9.x (просьба владельца 31.10.2026) —
// выбранные письма разом («N писем»), пальцем и пером на планшете (в режиме
// выбора — удержанием выбранной строки: обычное удержание по-прежнему
// открывает карточку письма), папки другого ящика приглушены, на «Архив
// Ogneliss» — тоже можно.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';

/// Что тащат: одно или несколько писем.
class MailDragData {
  final List<EmailModel> emails;
  const MailDragData(this.emails);

  /// Бросить в папку [f] можно: все письма — её ящика, и хотя бы одно ещё
  /// не в ней.
  bool fitsFolder(FolderModel f) =>
      emails.isNotEmpty && emails.every((e) => e.accountId == f.accountId) && emails.any((e) => e.folderId != f.id);

  /// Письма, которые в папке [f] ещё не лежат.
  List<EmailModel> movingTo(FolderModel f) => [for (final e in emails) if (e.folderId != f.id) e];
}

abstract final class MailDrag {
  /// Что тащат сейчас (null — ничего): папки, куда нельзя, приглушаются.
  static final active = ValueNotifier<MailDragData?>(null);

  /// Палец и перо: перетаскивание — после удержания. Короче удержания строки
  /// (оно открывает карточку письма), чтобы перетаскивание выигрывало у неё
  /// только там, где включено (выбранная строка в режиме выбора).
  static const touchDelay = Duration(milliseconds: 420);
}

/// Draggable со своим набором устройств: мышью — сразу (письмо тянется, как
/// файл в проводнике), пальцем и пером — после удержания [MailDrag.touchDelay].
/// У Draggable нет «только мышь», а без этого палец начинал перетаскивание
/// вместо прокрутки ленты.
class MailDraggable extends Draggable<MailDragData> {
  /// true — пальцем и пером (после удержания), false — мышью.
  final bool touch;

  const MailDraggable({
    super.key,
    required super.child,
    required super.feedback,
    required MailDragData super.data,
    required this.touch,
    super.childWhenDragging,
    super.dragAnchorStrategy = pointerDragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    final r = touch
        ? DelayedMultiDragGestureRecognizer(
            delay: MailDrag.touchDelay,
            supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
          )
        : ImmediateMultiDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.mouse});
    return r..onStart = onStart;
  }
}

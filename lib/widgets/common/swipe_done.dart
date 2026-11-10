// lib/widgets/common/swipe_done.dart
//
// «Сделано» после свайпа (2.2.0, замечание владельца 09.11.2026: «в беседах
// свайп "На контроль" никак не отображается… свайпам не хватает понимания,
// что что-то сделано»): после «Прочитано», «Флаг», «На контроль» внизу —
// строка с результатом и «Вернуть», та же, что «Письмо удалено · Вернуть»
// ([UndoStrip], [EmailUndoManager]). Экранный диктор слышит результат.
//
// Сначала (09.11) результат был плашкой поверх самой строки; владелец
// 10.11.2026: «не нравится, как при свайпе зависает информация о
// выполненном действии. При удалении нормально работает» — теперь как при
// удалении. Действие выполнено сразу; «Вернуть» возвращает как было.
// Архив, удаление и спам — свои «Вернуть» (перенос ждёт 7 секунд).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/models/email_model.dart';
import '../../features/settings/providers/settings_provider.dart' show SwipeAction;
import '../../l10n/app_localizations.dart';
import 'undo_manager.dart';

/// Подпись результата свайпа [a] над письмом [e] — состояние ПОСЛЕ действия.
/// [read] — строка до действия прочитана (у свёрнутой беседы — вся),
/// [control] — её отметка «На контроле» до действия. Для действий, которые
/// убирают письмо или открывают окно, — null.
String? swipeDoneLabel(SwipeAction a, EmailModel e, AppLocalizations l10n, {bool? read, int? control}) => switch (a) {
      SwipeAction.markRead => l10n.tr((read ?? e.isRead) ? 'swipeDoneUnread' : 'swipeDoneRead'),
      SwipeAction.flag => l10n.tr(e.isFlagged ? 'swipeDoneUnflag' : 'swipeDoneFlag'),
      SwipeAction.control => l10n.tr((control ?? e.controlState) != 0 ? 'swipeDoneControlOff' : 'swipeDoneControl'),
      _ => null,
    };

/// Результат свайпа строкой внизу с «Вернуть» ([onUndo] — вернуть как было).
/// Для действий без своей строки результата — ничего.
void showSwipeDone(BuildContext context, SwipeAction a, EmailModel e, AppLocalizations l10n,
    {bool? read, int? control, required VoidCallback onUndo}) {
  final label = swipeDoneLabel(a, e, l10n, read: read, control: control);
  if (label == null) return;
  EmailUndoManager.perform(
    context,
    // Сделано сразу: по истечении ждать нечего, «Вернуть» — откат.
    UndoableAction(description: label, execute: () async {}, undo: () async {}, onUndo: onUndo),
  );
  final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
  unawaited(SemanticsService.sendAnnouncement(View.of(context), label, dir));
}

// lib/widgets/common/undo_manager.dart
// Отложенное выполнение действия с возможностью отмены («· Вернуть»).
//
// Раньше новое действие ОТМЕНЯЛО предыдущее ожидающее: три письма, удалённые
// свайпом подряд, — удалялось только последнее, два других молча оставались
// на месте (и «пропадали» из списка до следующей синхронизации). Теперь
// предыдущее действие выполняется сразу, а отменить можно последнее.
// onUndo возвращает письмо в список, onSettled — когда действие выполнено
// или отменено.

import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';

class UndoableAction {
  final String description;
  final Future<void> Function() execute;
  final Future<void> Function() undo;

  /// Вернуть элемент в интерфейс после отмены (до выполнения).
  final VoidCallback? onUndo;

  /// Действие выполнено (успешно или с ошибкой) — можно снять локальное
  /// скрытие: дальше список отражает базу.
  final VoidCallback? onSettled;

  const UndoableAction({
    required this.description,
    required this.execute,
    required this.undo,
    this.onUndo,
    this.onSettled,
  });
}

/// Email-specific undo manager (renamed to avoid conflict with Flutter UndoManager)
///
/// 1.6.49+95: плашки (SnackBar) в приложении скрыты (решение владельца
/// 19.10.2026), и «Отменить» из плашки было не нажать — удалённое письмо
/// нельзя было вернуть. Теперь ожидающее действие видно строкой над лентой
/// ([pending], [UndoStrip]): «Письмо удалено · Вернуть» с отсчётом.
class EmailUndoManager {
  EmailUndoManager._();

  static Timer? _timer;
  static UndoableAction? _pendingAction;
  static const _undoDelaySeconds = 7;

  /// Ожидающее действие (null — нет) — для строки «· Вернуть».
  static final ValueNotifier<UndoableAction?> pending = ValueNotifier<UndoableAction?>(null);

  /// Когда ожидающее действие выполнится.
  static DateTime? deadline;

  static Future<void> _run(UndoableAction action) async {
    try {
      await action.execute();
      AppLogger.info('Executed: ${action.description}');
    } catch (e) {
      AppLogger.error('Execute failed: ${action.description}', e);
    } finally {
      action.onSettled?.call();
    }
  }

  static void _clearPending(UndoableAction action) {
    if (pending.value == action) {
      pending.value = null;
      deadline = null;
    }
  }

  /// Выполнить ожидающее действие немедленно (например, при уходе с экрана).
  static Future<void> flush() async {
    final p = _pendingAction;
    _timer?.cancel();
    _pendingAction = null;
    if (p != null) {
      _clearPending(p);
      await _run(p);
    }
  }

  /// Отменить ожидающее действие («Вернуть»). false — уже выполнено.
  static bool undoPending() {
    final action = _pendingAction;
    if (action == null) return false;
    _timer?.cancel();
    _pendingAction = null;
    _clearPending(action);
    action.onUndo?.call();
    action.onSettled?.call();
    AppLogger.info('Undo: ${action.description}');
    return true;
  }

  // context — для совместимости вызовов (раньше — плашка с «Отменить»).
  static void perform(BuildContext context, UndoableAction action) {
    // Предыдущее — выполнить, а не потерять.
    final previous = _pendingAction;
    _timer?.cancel();
    _pendingAction = action;
    if (previous != null) unawaited(_run(previous));
    deadline = DateTime.now().add(const Duration(seconds: _undoDelaySeconds));
    pending.value = action;

    _timer = Timer(const Duration(seconds: _undoDelaySeconds), () {
      if (_pendingAction == action) {
        _pendingAction = null;
        _clearPending(action);
        unawaited(_run(action));
      }
    });
  }
}

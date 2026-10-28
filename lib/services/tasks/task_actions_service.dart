// lib/services/tasks/task_actions_service.dart
// Операции над задачами — одни для экрана «Напоминания», уведомлений
// («Выполнено» в шторке) и календаря. Раньше логика жила в экране: кнопка
// уведомления ничего не делала, а удаление шло от имени АКТИВНОГО ящика, а не
// того, чья задача.
//
// Каждая правка: локальная база → напоминания в ОС → сервер (ActiveSync/EWS),
// при сбое сети — офлайн-очередь (иначе правку перезаписал бы следующий синк).

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/task_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../mail/engine/mail_engine_service.dart';
import '../notifications/reminder_scheduler_service.dart';
import '../sync/sync_service.dart';

final taskActionsProvider = Provider<TaskActionsService>((ref) => TaskActionsService(ref));

/// Увеличивается после любой правки задач — экраны пересчитывают списки.
final tasksRevisionProvider = StateProvider<int>((ref) => 0);

class TaskActionsService {
  final Ref _ref;
  TaskActionsService(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  Future<Task?> _row(String accountId, String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id) & t.accountId.equals(accountId)))
          .getSingleOrNull();

  void _bump() {
    try {
      _ref.read(tasksRevisionProvider.notifier).state++;
    } catch (_) {}
  }

  /// Создать задачу. Возвращает её id (после выгрузки на сервер он может
  /// смениться на серверный — экран получит его со следующим списком).
  Future<String> create({
    required String accountId,
    required String title,
    String? description,
    DateTime? dueDate,
    DateTime? reminderAt,
    int repeat = TaskRepeat.none,
    bool important = false,
    TaskPriority priority = TaskPriority.normal,
    String? linkedEmailId,
    String? linkedEmailSubject,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: id,
          accountId: accountId,
          title: title,
          description: Value(description),
          createdAt: DateTime.now(),
          dueDate: Value(dueDate),
          reminderAt: Value(reminderAt),
          isRecurring: Value(repeat != TaskRepeat.none),
          recurrenceDays: Value(repeat == TaskRepeat.none ? null : repeat),
          isFlagged: Value(important),
          priority: Value(priority.index),
          linkedEmailId: Value(linkedEmailId),
          linkedEmailSubject: Value(linkedEmailSubject),
        ));
    await _afterChange(accountId, id);
    return id;
  }

  /// Записать изменения полей задачи.
  Future<void> update(String accountId, String id, TasksCompanion changes) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id) & t.accountId.equals(accountId)))
        .write(changes);
    await _afterChange(accountId, id);
  }

  /// Отметить выполненной (или вернуть в работу). У повторяющейся задачи
  /// «выполнено» переносит срок и напоминание на следующий раз — как в
  /// Outlook и Microsoft To Do; отметка о выполнении остаётся в журнале.
  Future<void> setDone(String accountId, String id, bool done) async {
    final row = await _row(accountId, id);
    if (row == null) return;
    final task = taskFromRow(row);
    if (done && task.isRepeating && (task.dueDate != null || task.reminderAt != null)) {
      final rule = task.repeatDays!;
      final base = task.dueDate ?? task.reminderAt!;
      var nextDue = TaskRepeat.next(base.toLocal(), rule);
      // Просроченную серию двигаем до будущего, а не на один шаг.
      final now = DateTime.now();
      var guard = 0;
      while (nextDue.isBefore(now) && guard++ < 400) {
        nextDue = TaskRepeat.next(nextDue, rule);
      }
      DateTime? nextReminder;
      if (task.reminderAt != null) {
        final shift = nextDue.difference(base.toLocal());
        nextReminder = task.reminderAt!.toLocal().add(shift);
      }
      // Подзадачи начинаются заново.
      final subs = [for (final s in task.subtasks) s.copyWith(done: false)];
      await update(accountId, id, TasksCompanion(
        dueDate: Value(task.dueDate == null ? null : nextDue),
        reminderAt: Value(nextReminder),
        subtasksJson: Value(subs.isEmpty ? row.subtasksJson : encodeSubtasks(subs)),
        status: Value(TaskStatus.pending.index),
        completedAt: const Value(null),
      ));
      return;
    }
    await update(accountId, id, TasksCompanion(
      status: Value((done ? TaskStatus.completed : TaskStatus.pending).index),
      completedAt: Value(done ? DateTime.now() : null),
      progress: Value(done ? 100 : (row.progress >= 100 ? 0 : row.progress)),
    ));
  }

  Future<void> toggleImportant(String accountId, String id) async {
    final row = await _row(accountId, id);
    if (row == null) return;
    await update(accountId, id, TasksCompanion(isFlagged: Value(!row.isFlagged)));
  }

  /// Удалить задачу: локально, напоминание, на сервере (офлайн — через очередь).
  /// Возвращает удалённую строку — для «Отменить».
  Future<Task?> delete(String accountId, String id) async {
    final row = await _row(accountId, id);
    if (row == null) return null;
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(id) & t.accountId.equals(accountId))).go();
    try {
      await _ref.read(reminderSchedulerProvider).cancelTask(accountId, id);
    } catch (_) {}
    _bump();
    final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    // Созданная локально и ещё не выгруженная задача (uuid) на сервере
    // отсутствует — удалять там нечего.
    final onServer = id.startsWith('eas_') || id.startsWith('davt_') || id.length > 60;
    if (account != null && onServer) {
      try {
        await _ref.read(mailEngineServiceProvider).deleteTaskServer(account, id);
      } catch (e) {
        AppLogger.warning('Удаление задачи на сервере отложено: $e');
        try {
          await _ref.read(syncServiceProvider).enqueueOperation(
              accountId: accountId, operationType: 'delete_task', targetId: id);
        } catch (_) {}
      }
    }
    return row;
  }

  /// Вернуть удалённую задачу («Отменить» в подсказке).
  Future<void> restore(Task row) async {
    await _db.into(_db.tasks).insert(row, mode: InsertMode.insertOrReplace);
    // Если удаление уже ушло в очередь — снимаем его.
    try {
      await (_db.delete(_db.syncQueue)
            ..where((q) =>
                q.accountId.equals(row.accountId) &
                q.targetId.equals(row.id) &
                q.operationType.equals('delete_task')))
          .go();
    } catch (_) {}
    await _afterChange(row.accountId, row.id);
  }

  /// После правки: напоминания, список, сервер.
  Future<void> _afterChange(String accountId, String id) async {
    _bump();
    try {
      await _ref.read(reminderSchedulerProvider).rescheduleAll();
    } catch (_) {}
    await _push(accountId, id);
    _bump();
  }

  /// Выгрузить задачу на сервер; при сбое — в офлайн-очередь.
  Future<void> _push(String accountId, String id) async {
    final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (account == null) return;
    try {
      await _ref.read(mailEngineServiceProvider).pushTask(account, id);
    } catch (e) {
      AppLogger.warning('pushTask не удался, ставим в очередь: $e');
      try {
        await _ref.read(syncServiceProvider).enqueueOperation(
              accountId: accountId,
              operationType: 'upsert_task',
              targetId: id,
              payload: const {},
            );
      } catch (e2) {
        AppLogger.warning('enqueue upsert_task: $e2');
      }
    }
  }
}

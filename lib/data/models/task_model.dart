// lib/data/models/task_model.dart

import 'dart:convert';

enum TaskStatus { pending, inProgress, completed, cancelled }
enum TaskPriority { low, normal, high, urgent }

/// Подзадача (вложенный пункт задачи).
class SubTask {
  final String title;
  final bool done;
  const SubTask({required this.title, this.done = false});
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
  factory SubTask.fromJson(Map<String, dynamic> j) =>
      SubTask(title: j['title']?.toString() ?? '', done: j['done'] == true);
  SubTask copyWith({String? title, bool? done}) =>
      SubTask(title: title ?? this.title, done: done ?? this.done);
}

List<SubTask> parseSubtasks(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => SubTask.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return const [];
  }
}

String encodeSubtasks(List<SubTask> subs) => jsonEncode(subs.map((s) => s.toJson()).toList());

class TaskModel {
  final String id;
  final String accountId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime createdAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final int progress;
  final String? assigneeEmail;
  final String? assigneeName;
  final String? linkedEmailId;
  final String? linkedEmailSubject;
  final List<String> tags;
  final bool isFlagged;
  final List<SubTask> subtasks;

  /// Когда напомнить (null — без напоминания).
  final DateTime? reminderAt;

  /// Повтор: шаг в днях ([TaskRepeat]); null/0 — без повтора.
  final int? repeatDays;

  const TaskModel({
    required this.id, required this.accountId, required this.title,
    this.description, this.status = TaskStatus.pending,
    this.priority = TaskPriority.normal, required this.createdAt,
    this.dueDate, this.completedAt, this.progress = 0,
    this.assigneeEmail, this.assigneeName,
    this.linkedEmailId, this.linkedEmailSubject,
    this.tags = const [], this.isFlagged = false,
    this.subtasks = const [],
    this.reminderAt, this.repeatDays,
  });

  bool get isOverdue => dueDate != null && DateTime.now().isAfter(dueDate!) && status != TaskStatus.completed;
  bool get isDone => status == TaskStatus.completed;
  bool get isRepeating => (repeatDays ?? 0) != 0;

  factory TaskModel.fromMap(Map<String, dynamic> m) => TaskModel(
    id: m['id'] ?? '', accountId: m['accountId'] ?? '', title: m['title'] ?? '',
    description: m['description'], status: TaskStatus.values[(m['status'] as int?) ?? 0],
    priority: TaskPriority.values[(m['priority'] as int?) ?? 1],
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate']) : null,
    completedAt: m['completedAt'] != null ? DateTime.tryParse(m['completedAt']) : null,
    progress: m['progress'] ?? 0, assigneeEmail: m['assigneeEmail'],
    assigneeName: m['assigneeName'], linkedEmailId: m['linkedEmailId'],
    linkedEmailSubject: m['linkedEmailSubject'],
    tags: (m['tags'] as String?)?.split(';').where((s) => s.isNotEmpty).toList() ?? [],
    isFlagged: (m['isFlagged'] as int?) == 1,
    subtasks: parseSubtasks(m['subtasks'] as String?),
    reminderAt: m['reminderAt'] != null ? DateTime.tryParse(m['reminderAt']) : null,
    repeatDays: (m['isRecurring'] as int?) == 1 ? (m['recurrenceDays'] as int?) : null,
  );
}

/// Повтор задачи. Хранится числом в tasks.recurrenceDays (isRecurring = 1):
/// положительное — шаг в днях, особые значения — календарные правила.
class TaskRepeat {
  static const none = 0;
  static const daily = 1;
  static const weekly = 7;
  static const biweekly = 14;
  /// Тот же день следующего месяца (31-е → последний день короткого месяца).
  static const monthly = -30;
  static const yearly = -365;
  /// По будням: пятница → понедельник.
  static const weekdays = -5;

  static const all = [daily, weekdays, weekly, biweekly, monthly, yearly];

  /// Следующая дата после [from] по правилу [rule].
  static DateTime next(DateTime from, int rule) {
    DateTime keep(DateTime d) => DateTime(d.year, d.month, d.day, from.hour, from.minute);
    switch (rule) {
      case monthly:
        final lastDay = DateTime(from.year, from.month + 2, 0).day;
        return keep(DateTime(from.year, from.month + 1, from.day > lastDay ? lastDay : from.day));
      case yearly:
        final lastDay = DateTime(from.year + 1, from.month + 1, 0).day;
        return keep(DateTime(from.year + 1, from.month, from.day > lastDay ? lastDay : from.day));
      case weekdays:
        var d = DateTime(from.year, from.month, from.day + 1);
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = DateTime(d.year, d.month, d.day + 1);
        }
        return keep(d);
      default:
        final step = rule > 0 ? rule : 1;
        return keep(DateTime(from.year, from.month, from.day + step));
    }
  }
}

/// Маппинг строки БД → модель задачи. Живёт в модели, а не в экране:
/// используется и провайдером списка, и сервисом синхронизации при выгрузке
/// отложенных правок из офлайн-очереди. Вынесен отдельно, чтобы одинаково
/// использоваться и в провайдере, и при выгрузке правок на сервер.
TaskModel taskFromRow(dynamic r) => TaskModel.fromMap({
        'id': r.id,
        'accountId': r.accountId,
        'title': r.title,
        'description': r.description,
        'status': r.status,
        'priority': r.priority,
        'createdAt': r.createdAt.toIso8601String(),
        'dueDate': r.dueDate?.toIso8601String(),
        'completedAt': r.completedAt?.toIso8601String(),
        'progress': r.progress,
        'assigneeEmail': r.assigneeEmail,
        'assigneeName': r.assigneeName,
        'linkedEmailId': r.linkedEmailId,
        'linkedEmailSubject': r.linkedEmailSubject,
        'tags': r.tagsStr,
        'isFlagged': r.isFlagged ? 1 : 0,
        'subtasks': r.subtasksJson,
        'reminderAt': r.reminderAt?.toIso8601String(),
        'isRecurring': r.isRecurring ? 1 : 0,
        'recurrenceDays': r.recurrenceDays,
      });

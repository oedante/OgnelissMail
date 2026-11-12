// lib/services/assignments/assignment_stats.dart
// Сводка по поручениям (просьба владельца 12.11.2026: «сводные данные и
// визуальные отчёты по одной задаче и по нескольким сразу»). Что взято из
// аналогов: панель Jira (статусы, по исполнителям) и
// «Эффективность» Битрикс24 (доля выполненных в срок). Расчёт — без
// интерфейса, чтобы его проверяли тесты.
//
// Дата выполнения — время последнего изменения принятого поручения
// (updatedAt): отдельного поля нет, а после «Принято» поручение не меняется.

import 'assignment_codec.dart' show AssignmentStatus;
import 'assignment_store.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Когда принято (для выполненных), иначе null.
DateTime? assignmentDoneAt(AssignmentView v) =>
    v.status == AssignmentStatus.done ? v.row.updatedAt.toLocal() : null;

/// Принято в срок: день принятия не позже дня срока (без срока — в срок).
bool assignmentOnTime(AssignmentView v) {
  final done = assignmentDoneAt(v);
  if (done == null) return false;
  final due = v.due;
  return due == null || !_day(done).isAfter(_day(due));
}

/// Человек в сводке: исполнитель моего поручения или поручивший мне.
class PersonStats {
  final String email;
  final String name;
  int active = 0;
  int overdue = 0;
  int review = 0;
  int done = 0;
  int onTime = 0;
  PersonStats(this.email, this.name);

  /// Доля принятых в срок (за период); null — принятых нет.
  double? get onTimeShare => done == 0 ? null : onTime / done;
}

class AssignmentStats {
  /// В работе (не выполнено и не снято), просрочено, на проверке.
  final int active, overdue, review;

  /// За период: поставлено, выполнено, из них в срок.
  final int created, done, onTime;

  /// Среднее время выполнения (дней) за период; null — выполненных нет.
  final double? avgDays;

  /// Действующие по статусам (Новое, В работе, На проверке) и выполненные
  /// за период.
  final Map<int, int> byStatus;

  /// По людям: больше всего в работе — первыми.
  final List<PersonStats> people;

  const AssignmentStats({
    required this.active,
    required this.overdue,
    required this.review,
    required this.created,
    required this.done,
    required this.onTime,
    required this.avgDays,
    required this.byStatus,
    required this.people,
  });

  double? get onTimeShare => done == 0 ? null : onTime / done;

  /// Сводка по [items] (проекты — по их этапам: строки проектов не
  /// считаются). [periodDays] — период для «поставлено/выполнено».
  static AssignmentStats of(List<AssignmentView> items, DateTime now, {int periodDays = 30}) {
    final today = _day(now);
    final from = today.subtract(Duration(days: periodDays - 1));
    final list = [for (final v in items) if (!v.isProject) v];
    var active = 0, overdue = 0, review = 0, created = 0, done = 0, onTime = 0;
    var daysSum = 0.0;
    final byStatus = <int, int>{};
    final people = <String, PersonStats>{};
    for (final v in list) {
      final key = (v.otherEmail ?? '').toLowerCase();
      final p = people.putIfAbsent(key, () => PersonStats(key, v.otherName));
      final createdAt = v.row.createdAt.toLocal();
      if (!_day(createdAt).isBefore(from)) created++;
      if (v.active) {
        active++;
        p.active++;
        byStatus[v.status] = (byStatus[v.status] ?? 0) + 1;
        if (v.overdue(now)) {
          overdue++;
          p.overdue++;
        }
        if (v.status == AssignmentStatus.review) {
          review++;
          p.review++;
        }
      }
      final doneAt = assignmentDoneAt(v);
      if (doneAt != null) {
        if (!_day(doneAt).isBefore(from)) {
          done++;
          p.done++;
          byStatus[AssignmentStatus.done] = (byStatus[AssignmentStatus.done] ?? 0) + 1;
          daysSum += doneAt.difference(createdAt).inMinutes / (60 * 24);
          if (assignmentOnTime(v)) {
            onTime++;
            p.onTime++;
          }
        }
      }
    }
    final ranked = people.values.where((p) => p.active + p.done > 0).toList()
      ..sort((a, b) {
        final c = b.active.compareTo(a.active);
        return c != 0 ? c : b.done.compareTo(a.done);
      });
    return AssignmentStats(
      active: active,
      overdue: overdue,
      review: review,
      created: created,
      done: done,
      onTime: onTime,
      avgDays: done == 0 ? null : daysSum / done,
      byStatus: byStatus,
      people: ranked,
    );
  }
}

/// План и факт этапа: плановый срок, когда принят, отклонение в днях
/// (+ — позже срока; у непринятого с прошедшим сроком — по сегодня).
typedef StageFact = ({AssignmentView stage, DateTime? plannedDue, DateTime? doneAt, int? deviationDays});

List<StageFact> stageFacts(List<AssignmentView> stages, DateTime now) => [
      for (final s in stages)
        (
          stage: s,
          plannedDue: s.due,
          doneAt: assignmentDoneAt(s),
          deviationDays: () {
            final due = s.due;
            if (due == null || s.status == AssignmentStatus.cancelled) return null;
            final end = assignmentDoneAt(s) ?? (s.overdue(now) ? now : null);
            if (end == null) return null;
            return _day(end).difference(_day(due)).inDays;
          }(),
        ),
    ];

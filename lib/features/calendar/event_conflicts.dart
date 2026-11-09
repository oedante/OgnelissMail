// lib/features/calendar/event_conflicts.dart
// Пересечения новой встречи с уже назначенными (1.6.49, как в Outlook:
// «Пересекается с: Планёрка 10:00–11:00»): строка под временем в окне
// встречи. Из базы на телефоне, без сервера: свои календари (не общие
// ящики), без отменённых, «свободно» и встреч на весь день.

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';

Future<List<CalendarEvent>> eventConflicts(
  AppDatabase db, {
  required DateTime start,
  required DateTime end,
  required Set<String> accountIds,
  String? excludeId,
  int limit = 5,
}) async {
  if (accountIds.isEmpty || !end.isAfter(start)) return const [];
  final rows = await (db.select(db.calendarEvents)
        ..where((e) =>
            e.accountId.isIn(accountIds) &
            e.isCancelled.equals(false) &
            e.isAllDay.equals(false) &
            e.showAs.equals(0).not() &
            e.startTime.isSmallerThanValue(end) &
            e.endTime.isBiggerThanValue(start))
        ..orderBy([(e) => OrderingTerm(expression: e.startTime)])
        ..limit(limit + 2))
      .get();
  // Своя же встреча (правка) и её копия из другого ящика — не пересечение.
  final ex = excludeId;
  return [
    for (final r in rows)
      if (ex == null || (r.id != ex && !r.id.startsWith('$ex#'))) r,
  ].take(limit).toList();
}

/// Пересечения приглашения из письма (2.2.0, план 08.11.2026 п. 5) — без
/// самой встречи: Exchange ставит её в календарь «под вопросом», как только
/// приходит приглашение (то же время и та же тема).
Future<List<CalendarEvent>> meetingConflicts(
  AppDatabase db, {
  required DateTime start,
  required DateTime end,
  required String accountId,
  String subject = '',
}) async {
  final rows = await eventConflicts(db, start: start, end: end, accountIds: {accountId}, limit: 8);
  String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'^(\s*(re|fw|fwd|ответ|пересл|приглашение|invitation|updated|обновлено)\s*:\s*)+'), '')
      .trim();
  final subj = norm(subject);
  bool same(CalendarEvent r) =>
      r.startTime.isAtSameMomentAs(start) &&
      r.endTime.isAtSameMomentAs(end) &&
      (subj.isEmpty || norm(r.title) == subj || subj.contains(norm(r.title)));
  return [for (final r in rows) if (!same(r)) r];
}

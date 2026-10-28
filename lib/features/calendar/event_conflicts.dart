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

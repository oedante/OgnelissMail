// Поручения со сроком — слой календаря (замечание владельца 10.11.2026:
// «в календаре поручения не отображаются»).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/calendar/calendar_data.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';

AssignmentView _v(
  String id, {
  DateTime? due,
  int status = AssignmentStatus.open,
  String account = 'acc1',
  bool outgoing = true,
}) {
  final at = DateTime(2026, 11, 1);
  return AssignmentView(
    row: Assignment(
      id: id,
      accountId: account,
      title: 'Отчёт $id',
      kind: 0,
      status: status,
      priority: 1,
      ownerEmail: 'boss@example.com',
      dueAt: due,
      isTemplate: false,
      autoDecideEnabled: true,
      createdAt: at,
      updatedAt: at,
      isArchived: false,
      isProject: false,
      stageOrder: 0,
      waiting: false,
    ),
    assignee: const AssignmentParticipant(
        assignmentId: 'x', email: 'ivan@example.com', displayName: 'Иван Петров', role: AssignmentRole.responsible, inviteStatus: 0),
    owner: const AssignmentParticipant(
        assignmentId: 'x', email: 'boss@example.com', displayName: 'Олег', role: AssignmentRole.owner, inviteStatus: 0),
    outgoing: outgoing,
  );
}

void main() {
  final from = DateTime(2026, 11, 9);
  final to = DateTime(2026, 11, 16);

  List<CalendarEvent> items(List<AssignmentView> all, {List<String> ids = const ['acc1']}) =>
      assignmentCalendarItems(all, accountIds: ids, from: from, to: to);

  test('поручение со сроком в периоде — событие на весь день', () {
    final r = items([_v('A', due: DateTime(2026, 11, 12))]);
    expect(r, hasLength(1));
    final e = r.single;
    expect(e.id, 'assign_A');
    expect(isAssignItem(e), isTrue);
    expect(isTodoItem(e), isTrue);
    expect(isRealEvent(e), isFalse);
    expect(e.isAllDay, isTrue);
    expect(e.startTime, DateTime(2026, 11, 12));
    expect(e.title, 'Отчёт A');
  });

  test('срок со временем — на полчаса, не на весь день', () {
    final e = items([_v('A', due: DateTime(2026, 11, 12, 15, 30))]).single;
    expect(e.isAllDay, isFalse);
    expect(e.endTime.difference(e.startTime), const Duration(minutes: 30));
  });

  test('без срока, вне периода, выполненные, снятые, чужой ящик — не показываются', () {
    final r = items([
      _v('none'),
      _v('early', due: DateTime(2026, 11, 8, 23)),
      _v('late', due: DateTime(2026, 11, 16)),
      _v('done', due: DateTime(2026, 11, 12), status: AssignmentStatus.done),
      _v('cancel', due: DateTime(2026, 11, 12), status: AssignmentStatus.cancelled),
      _v('other', due: DateTime(2026, 11, 12), account: 'acc2'),
      _v('work', due: DateTime(2026, 11, 13), status: AssignmentStatus.inProgress),
      _v('review', due: DateTime(2026, 11, 14), status: AssignmentStatus.review),
    ]);
    expect([for (final e in r) e.id], ['assign_work', 'assign_review']);
  });

  test('другая сторона — как организатор: исполнитель у моего, поручивший — у порученного мне', () {
    final mine = items([_v('A', due: DateTime(2026, 11, 12))]).single;
    expect(mine.organizerEmail, 'ivan@example.com');
    expect(attendeeSummary(mine).organizer, 'Иван Петров');
    final toMe = items([_v('B', due: DateTime(2026, 11, 12), outgoing: false)]).single;
    expect(toMe.organizerEmail, 'boss@example.com');
    expect(attendeeSummary(toMe).organizer, 'Олег');
  });
}

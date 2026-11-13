// Сводка по поручениям (12.11.2026): показатели, по людям,
// план и факт этапов, отчёт HTML; «Важное» в отметке письма.

import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/l10n/strings_store.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_report.dart';
import 'package:ogneliss/services/assignments/assignment_stats.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';

AssignmentView v(
  String id, {
  String who = 'vera@corp.example',
  String name = 'Вера',
  int status = AssignmentStatus.open,
  required DateTime created,
  DateTime? updated,
  DateTime? due,
  bool outgoing = true,
  bool project = false,
  String? parent,
  int priority = 1,
}) =>
    AssignmentView(
      row: Assignment(
        id: id,
        accountId: 'a1',
        title: 'Поручение $id',
        kind: 0,
        status: status,
        priority: priority,
        ownerEmail: 'boss@corp.example',
        parentAssignmentId: parent,
        isTemplate: false,
        autoDecideEnabled: true,
        createdAt: created,
        updatedAt: updated ?? created,
        isArchived: false,
        isProject: project,
        dueAt: due,
        stageOrder: 0,
        waiting: false,
        revision: 0,
        visibility: 0,
      ),
      assignee: AssignmentParticipant(
          assignmentId: id, email: who, displayName: name, role: AssignmentRole.responsible, inviteStatus: 0),
      owner: AssignmentParticipant(
          assignmentId: id, email: 'boss@corp.example', displayName: 'Олег', role: AssignmentRole.owner, inviteStatus: 0),
      outgoing: outgoing,
    );

void main() {
  final now = DateTime(2026, 11, 12, 15);
  DateTime d(int days) => DateTime(2026, 11, 12).add(Duration(days: days));

  group('сводка', () {
    final items = [
      // Вера: просрочено, на проверке, выполнено в срок, выполнено с опозданием.
      v('A', status: AssignmentStatus.inProgress, created: d(-10), due: d(-2)),
      v('B', status: AssignmentStatus.review, created: d(-3), due: d(3)),
      v('C', status: AssignmentStatus.done, created: d(-6), updated: d(-2), due: d(-1)),
      v('D', status: AssignmentStatus.done, created: d(-8), updated: d(-1), due: d(-4)),
      // Дмитрий: новое; давно выполненное (вне периода).
      v('E', who: 'dmitry@corp.example', name: 'Дмитрий', created: d(-1)),
      v('F', who: 'dmitry@corp.example', name: 'Дмитрий', status: AssignmentStatus.done, created: d(-80), updated: d(-70)),
      // Снятое и строка проекта — не в работе и не в людях.
      v('G', status: AssignmentStatus.cancelled, created: d(-2)),
      v('P', project: true, created: d(-5), due: d(10)),
    ];

    test('показатели, статусы и доля в срок', () {
      final s = AssignmentStats.of(items, now, periodDays: 30);
      expect(s.active, 3);
      expect(s.overdue, 1);
      expect(s.review, 1);
      expect(s.done, 2, reason: 'выполненное 70 дней назад — вне периода');
      expect(s.onTime, 1);
      expect(s.onTimeShare, 0.5);
      expect(s.created, 6, reason: 'A, B, C, D, E, G; проект не считается, F — вне периода');
      expect(s.avgDays, closeTo((4 + 7) / 2, 0.01));
      expect(s.byStatus, {
        AssignmentStatus.inProgress: 1,
        AssignmentStatus.review: 1,
        AssignmentStatus.open: 1,
        AssignmentStatus.done: 2,
      });
    });

    test('по людям: больше всего в работе — первыми', () {
      final s = AssignmentStats.of(items, now, periodDays: 30);
      expect([for (final p in s.people) p.name], ['Вера', 'Дмитрий']);
      final vera = s.people.first;
      expect((vera.active, vera.overdue, vera.review, vera.done, vera.onTime), (2, 1, 1, 2, 1));
      expect(s.people.last.done, 0, reason: 'выполненное вне периода не считается');
    });

    test('план и факт этапов: + — позже срока, у непринятого просроченного — по сегодня', () {
      final facts = stageFacts([
        v('S1', status: AssignmentStatus.done, created: d(-9), updated: d(-3), due: d(-5)),
        v('S2', status: AssignmentStatus.done, created: d(-9), updated: d(-6), due: d(-5)),
        v('S3', status: AssignmentStatus.inProgress, created: d(-9), due: d(-4)),
        v('S4', status: AssignmentStatus.inProgress, created: d(-9), due: d(5)),
        v('S5', status: AssignmentStatus.cancelled, created: d(-9), due: d(-5)),
      ], now);
      expect([for (final f in facts) f.deviationDays], [2, -1, 4, null, null]);
      expect(facts.first.doneAt, d(-3));
    });
  });

  test('отчёт HTML: показатели, люди (с экранированием), просроченные, проект', () async {
    await initializeDateFormatting('ru');
    for (final f in Directory('assets/l10n').listSync().whereType<File>()) {
      if (f.path.endsWith('/ru.xml')) StringsStore.put('ru', f.readAsStringSync());
    }
    final l10n = AppLocalizations(const Locale('ru'));
    final items = [
      v('A', name: 'Вера <b>', status: AssignmentStatus.inProgress, created: d(-10), due: d(-2)),
      v('P', project: true, created: d(-5), due: d(10)),
      v('S1', parent: 'P', status: AssignmentStatus.done, created: d(-5), updated: d(-1), due: d(-2)),
    ];
    final html = assignmentReportHtml(
      l10n: l10n,
      title: 'Отчёт по поручениям',
      subtitle: 'Я поручил',
      stats: AssignmentStats.of(items, now),
      items: items,
      now: now,
    );
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('Отчёт по поручениям'));
    expect(html, contains('Вера &lt;b&gt;'));
    expect(html, isNot(contains('Вера <b>')));
    expect(html, contains('+2'), reason: 'A просрочено на 2 дня');
    expect(html, contains('Поручение S1'), reason: 'этап проекта в таблице плана и факта');
  });

  test('«Важное» — в отметке письма; старые письма без отметки — обычные', () {
    final t = AssignmentCodec.parseTask(AssignmentCodec.taskMarker(id: 'ABCDEFGHJKMN', important: true))!;
    expect(t.important, isTrue);
    expect(AssignmentCodec.parseTask(AssignmentCodec.taskMarker(id: 'ABCDEFGHJKMN'))!.important, isFalse);
    expect(v('X', created: now, priority: AssignmentPriority.important).important, isTrue);
    expect(v('Y', created: now).important, isFalse);
  });
}

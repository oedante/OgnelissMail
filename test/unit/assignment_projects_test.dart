// Проекты с этапами в поручениях (12.11.2026): отметки писем, чек-лист,
// прогресс, сдвиг сроков, шаблоны и разбор писем этапа у участников с
// разными ролями.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart' show ProjectDraft, StageDraft;
import 'package:ogneliss/services/assignments/assignment_store.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('отметки писем проекта', () {
    test('этап: роли, сроки, порядок, чек-лист и план — туда и обратно', () {
      final plan = PlanStage.encode([
        PlanStage(id: 'ABCDEFGHJKMN', title: 'Сбор', due: DateTime(2026, 11, 20)),
        const PlanStage(id: 'BCDEFGHJKMNP', title: 'Отчёт', after: 'ABCDEFGHJKMN', order: 1),
      ]);
      final marker = AssignmentCodec.taskMarker(
        id: 'BCDEFGHJKMNP',
        ev: 'created:BCDEFGHJKMNP',
        parent: 'KMNPQRSTVWXY',
        start: DateTime(2026, 11, 21),
        due: DateTime(2026, 11, 25),
        after: 'ABCDEFGHJKMN',
        order: 1,
        to: 'Vera@Corp.ru',
        co: ['dmitry@corp.ru', 'anna@corp.ru'],
        ctl: 'chief@corp.ru',
        obs: ['hr@corp.ru'],
        title: 'Отчёт; итог | выводы',
        checklist: ['Таблица', 'Слайды | графики', '  '],
        plan: plan,
      );
      final t = AssignmentCodec.parseTask('<p>текст</p>$marker')!;
      expect(t.id, 'BCDEFGHJKMNP');
      expect(t.parent, 'KMNPQRSTVWXY');
      expect(t.start, DateTime(2026, 11, 21));
      expect(t.due, DateTime(2026, 11, 25));
      expect(t.after, 'ABCDEFGHJKMN');
      expect(t.order, 1);
      expect(t.to, 'vera@corp.ru');
      expect(t.co, ['dmitry@corp.ru', 'anna@corp.ru']);
      expect(t.ctl, 'chief@corp.ru');
      expect(t.obs, ['hr@corp.ru']);
      expect(t.title, 'Отчёт; итог | выводы');
      expect(t.checklist, ['Таблица', 'Слайды | графики']);
      expect(t.project, isFalse);
      final back = PlanStage.decode(t.plan);
      expect([for (final p in back) p.title], ['Сбор', 'Отчёт']);
      expect(back.last.after, 'ABCDEFGHJKMN');
      expect(back.first.due, DateTime(2026, 11, 20));
    });

    test('проект; связь «после» с самим собой или с чужим кодом не пишется', () {
      final t = AssignmentCodec.parseTask(
          AssignmentCodec.taskMarker(id: 'KMNPQRSTVWXY', project: true, after: 'KMNPQRSTVWXY'))!;
      expect(t.project, isTrue);
      expect(t.after, isNull);
      expect(AssignmentCodec.parseTask(AssignmentCodec.taskMarker(id: 'KMNPQRSTVWXY', after: 'x"><script>'))!.after,
          isNull);
    });

    test('статус с отметками чек-листа и «Можно начинать»; соисполнитель', () {
      final s = AssignmentCodec.parseStatus(
          AssignmentCodec.statusMarker('ABCDEFGHJKMN', AssignmentStatus.inProgress, ev: 'ev:1', checks: '0110', go: true))!;
      expect(s.status, AssignmentStatus.inProgress);
      expect(s.checks, '0110');
      expect(s.go, isTrue);
      expect(
          AssignmentCodec.parseStatus(AssignmentCodec.statusMarker('ABCDEFGHJKMN', 2, checks: '01x'))!.checks, isNull);

      final p = AssignmentCodec.parsePeople(
          AssignmentCodec.peopleMarker('ABCDEFGHJKMN', 'Dmitry@Corp.ru', AssignmentRole.co, name: 'Дмитрий; Орлов', ev: 'ev:2'))!;
      expect(p.email, 'dmitry@corp.ru');
      expect(p.role, AssignmentRole.co);
      expect(p.name, 'Дмитрий; Орлов');
      expect(p.ev, 'ev:2');
    });
  });

  group('чек-лист, прогресс, сдвиг сроков', () {
    test('чек-лист: хранение и отметки строкой', () {
      final items = [const ChecklistItem('А'), const ChecklistItem('Б', done: true), const ChecklistItem('В')];
      expect(ChecklistItem.decode(ChecklistItem.encode(items)).map((i) => i.done), [false, true, false]);
      expect(ChecklistItem.bits(items), '010');
      expect(ChecklistItem.applyBits(items, '1').map((i) => i.done), [true, true, false]);
      expect(ChecklistItem.applyBits(items, '0011').map((i) => i.done), [false, false, true]);
      expect(ChecklistItem.fraction(items), closeTo(1 / 3, 1e-9));
      expect(ChecklistItem.fraction(const []), isNull);
      expect(ChecklistItem.decode('мусор'), isEmpty);
    });

    test('прогресс этапа и проекта (снятые не считаются)', () {
      expect(stageProgress(AssignmentStatus.done, const []), 1);
      expect(stageProgress(AssignmentStatus.open, const []), 0);
      expect(stageProgress(AssignmentStatus.inProgress, const []), 0.4);
      expect(stageProgress(AssignmentStatus.review, const []), 0.8);
      expect(stageProgress(AssignmentStatus.inProgress, [const ChecklistItem('а', done: true), const ChecklistItem('б')]),
          0.5);
      expect(stageProgress(AssignmentStatus.review, [const ChecklistItem('а', done: true), const ChecklistItem('б')]), 0.9);
      expect(
          projectProgress(const [
            PlanStage(id: '1', title: 'а', status: AssignmentStatus.done, progress: 1),
            PlanStage(id: '2', title: 'б', status: AssignmentStatus.open, progress: 0),
            PlanStage(id: '3', title: 'в', status: AssignmentStatus.cancelled, progress: 0),
          ]),
          0.5);
      expect(projectProgress(const []), 0);
    });

    test('опоздание сдвигает цепочку, длительность сохраняется; параллельный этап не трогается', () {
      final today = DateTime(2026, 11, 12);
      final stages = [
        PlanStage(id: 'a', title: 'Сбор', start: DateTime(2026, 11, 3), due: DateTime(2026, 11, 10), status: 2),
        PlanStage(id: 'b', title: 'Анализ', start: DateTime(2026, 11, 11), due: DateTime(2026, 11, 13), after: 'a', status: 1),
        PlanStage(id: 'c', title: 'Отчёт', start: DateTime(2026, 11, 14), due: DateTime(2026, 11, 14), after: 'b', status: 1),
        PlanStage(id: 'd', title: 'Слайды', start: DateTime(2026, 11, 3), due: DateTime(2026, 11, 20), status: 1),
      ];
      final moved = shiftSuccessors(stages, today);
      expect(moved.keys, unorderedEquals(['b', 'c']));
      // «Сбор» не принят и срок прошёл — идёт до сегодня; «Анализ» — с завтра, 2 дня.
      expect(moved['b'], (start: DateTime(2026, 11, 13), due: DateTime(2026, 11, 15)));
      expect(moved['c'], (start: DateTime(2026, 11, 16), due: DateTime(2026, 11, 16)));

      // Принят раньше срока — сдвигать нечего; принят позже — от дня принятия.
      expect(
          shiftSuccessors([
            PlanStage(id: 'a', title: 'Сбор', due: DateTime(2026, 11, 10), status: AssignmentStatus.done, doneAt: DateTime(2026, 11, 9)),
            PlanStage(id: 'b', title: 'Анализ', start: DateTime(2026, 11, 11), due: DateTime(2026, 11, 13), after: 'a'),
          ], today),
          isEmpty);
      final late = shiftSuccessors([
        PlanStage(id: 'a', title: 'Сбор', due: DateTime(2026, 11, 10), status: AssignmentStatus.done, doneAt: DateTime(2026, 11, 11, 18)),
        PlanStage(id: 'b', title: 'Анализ', start: DateTime(2026, 11, 11), due: DateTime(2026, 11, 13), after: 'a'),
      ], today);
      expect(late['b'], (start: DateTime(2026, 11, 12), due: DateTime(2026, 11, 14)));
    });

    test('статус проекта по этапам', () {
      const open = AssignmentStatus.open, work = AssignmentStatus.inProgress, done = AssignmentStatus.done;
      const cancelled = AssignmentStatus.cancelled;
      expect(projectStatus(open, const []), open);
      expect(projectStatus(open, const [open, open]), open);
      expect(projectStatus(open, const [done, open]), work);
      expect(projectStatus(open, const [AssignmentStatus.review, open]), work);
      expect(projectStatus(open, const [done, cancelled, done]), done);
      expect(projectStatus(cancelled, const [done]), cancelled);
    });

    test('план участника: свои этапы — с текущим статусом, порядок — по плану', () {
      final merged = mergePlan(
        own: const [PlanStage(id: 'b', title: 'Анализ', order: 1, status: AssignmentStatus.review, progress: 0.8)],
        fromMail: const [
          PlanStage(id: 'a', title: 'Сбор', order: 0),
          PlanStage(id: 'b', title: 'Анализ', order: 1),
          PlanStage(id: 'c', title: 'Отчёт', order: 2),
        ],
      );
      expect([for (final p in merged) p.id], ['a', 'b', 'c']);
      expect(merged[1].status, AssignmentStatus.review);
      expect(merged[0].status, isNull);
    });

    test('сроки нового этапа по порядку', () {
      final start = DateTime(2026, 11, 16);
      expect(nextStageDates(null, start), (start: start, due: DateTime(2026, 11, 18)));
      expect(nextStageDates(DateTime(2026, 11, 18), start, days: 5),
          (start: DateTime(2026, 11, 19), due: DateTime(2026, 11, 23)));
    });
  });

  test('шаблон проекта: сроки — от нового начала, участники и чек-листы сохраняются', () {
    const vera = EmailAddress(email: 'vera@corp.ru', displayName: 'Вера');
    const dmitry = EmailAddress(email: 'dmitry@corp.ru');
    const chief = EmailAddress(email: 'chief@corp.ru', displayName: 'Шеф');
    final d = ProjectDraft(
      title: 'Годовой отчёт',
      description: 'Сводный',
      start: DateTime(2026, 11, 2),
      controller: chief,
      stages: [
        StageDraft(title: 'Сбор', executor: vera, co: [dmitry], start: DateTime(2026, 11, 2), due: DateTime(2026, 11, 6),
            checklist: ['Продажи', 'Склад']),
        StageDraft(title: 'Отчёт', executor: dmitry, start: DateTime(2026, 11, 9), due: DateTime(2026, 11, 10), after: 0),
      ],
    );
    final json = d.toTemplateJson(DateTime(2026, 11, 2));
    expect(jsonDecode(json), isA<Map>());
    final t = ProjectDraft.fromTemplateJson(json, DateTime(2027, 2, 1));
    expect(t.title, 'Годовой отчёт');
    expect(t.controller!.email, 'chief@corp.ru');
    expect(t.stages, hasLength(2));
    expect(t.stages[0].executor.displayName, 'Вера');
    expect(t.stages[0].co.single.email, 'dmitry@corp.ru');
    expect(t.stages[0].start, DateTime(2027, 2, 1));
    expect(t.stages[0].due, DateTime(2027, 2, 5));
    expect(t.stages[0].checklist, ['Продажи', 'Склад']);
    expect(t.stages[1].after, 0);
    expect(t.stages[1].start, DateTime(2027, 2, 8));
  });

  group('разбор писем этапа', () {
    late AppDatabase db;
    const boss = 'boss@corp.ru';
    const vera = 'vera@corp.ru';
    const dmitry = 'dmitry@corp.ru';
    const chief = 'chief@corp.ru';
    final t0 = DateTime(2026, 11, 12, 9);
    const project = 'KMNPQRSTVWXY';
    const stage = 'ABCDEFGHJKMN';
    const next = 'BCDEFGHJKMNP';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      for (final (id, email) in [('a1', boss), ('a2', vera), ('a3', dmitry), ('a4', chief)]) {
        await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: id, type: 7, email: email, displayName: email, username: email, createdAt: DateTime(2026)));
        await db.into(db.folders).insert(FoldersCompanion.insert(
            id: 'in$id', accountId: id, displayName: 'Входящие', type: Value(FolderType.inbox.index)));
      }
    });
    tearDown(() => db.close());

    var n = 0;
    Future<void> mail(String account, String from, String subject, String html, DateTime at,
            {String to = '[]', String? cc}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: 'p${n++}',
              accountId: account,
              folderId: 'in$account',
              fromEmail: from,
              toRecipients: to,
              ccJson: Value(cc),
              subject: subject,
              bodyHtml: Value(html),
              receivedAt: at,
            ));

    String stageMail({String id = stage, String? after}) => AssignmentCodec.body(
          id: id,
          greeting: 'Вера, добрый день!',
          whatLabel: 'Поручение:',
          what: 'Сбор данных',
          footer: 'Поручение из Ogneliss Mail',
          marker: AssignmentCodec.taskMarker(
            id: id,
            ev: 'created:$id',
            parent: project,
            to: vera,
            co: [dmitry],
            ctl: chief,
            title: 'Сбор данных',
            after: after,
            order: after == null ? 0 : 1,
            checklist: ['Продажи', 'Склад'],
          ),
        );
    const toVera = '[{"email":"$vera","displayName":"Вера"},{"email":"$dmitry","displayName":"Дмитрий"}]';
    const ccChief = '[{"email":"$chief","displayName":"Шеф"}]';

    test('исполнитель, соисполнитель и контролирующий видят этап каждый со своей ролью', () async {
      for (final acc in ['a2', 'a3', 'a4']) {
        await mail(acc, boss, 'Поручение: Сбор данных', stageMail(), t0, to: toVera, cc: ccChief);
      }
      await AssignmentStore.scan(db, {'a2': {vera}}, since: t0.subtract(const Duration(days: 1)));
      await AssignmentStore.scan(db, {'a3': {dmitry}}, since: t0.subtract(const Duration(days: 1)));
      await AssignmentStore.scan(db, {'a4': {chief}}, since: t0.subtract(const Duration(days: 1)));

      // Одна база на всех: код этапа один — запись одна, участники — все.
      final v = (await AssignmentStore.all(db, {'a2': {vera}})).single;
      expect(v.iExecute, isTrue);
      expect(v.parentId, project);
      expect(v.checklist.map((c) => c.text), ['Продажи', 'Склад']);
      expect(v.coExecutors.single.email, dmitry);
      expect(v.controller!.email, chief);
      final asDmitry = AssignmentStore.view(v.row, v.people, {dmitry});
      expect(asDmitry.iCoExecute, isTrue);
      expect(asDmitry.iExecute, isFalse);
      final asChief = AssignmentStore.view(v.row, v.people, {chief});
      expect(asChief.iControl, isTrue);
      expect(asChief.iAccept, isTrue);
    });

    test('чужой этап в копии (я не участник) — не появляется', () async {
      await mail('a1', 'other@corp.ru', 'Поручение: Сбор данных', stageMail(), t0, to: toVera, cc: '[{"email":"$boss"}]');
      expect(await AssignmentStore.scan(db, {'a1': {boss}}, since: t0.subtract(const Duration(days: 1))), 0);
    });

    test('ход работ отмечает чек-лист у постановщика; «Можно начинать» снимает ожидание', () async {
      await AssignmentStore.insert(db,
          id: stage,
          accountId: 'a1',
          title: 'Сбор данных',
          ownerEmail: boss,
          assigneeEmail: vera,
          at: t0,
          outgoing: true,
          parentId: project,
          checklist: const [ChecklistItem('Продажи'), ChecklistItem('Склад')]);
      await mail(
          'a1',
          vera,
          'Re: Поручение: Сбор данных',
          assignmentNoteHtml('Продажи готовы',
              AssignmentCodec.statusMarker(stage, AssignmentStatus.inProgress, ev: 'ev:p1', checks: '10'), stage),
          t0.add(const Duration(hours: 2)));
      expect(await AssignmentStore.scan(db, {'a1': {boss}}, since: t0), 1);
      final row = (await AssignmentStore.byId(db, stage))!;
      expect(row.status, AssignmentStatus.inProgress);
      expect(ChecklistItem.decode(row.checklistJson).map((c) => c.done), [true, false]);

      // Следующий этап у исполнителя ждёт первого.
      await mail('a2', boss, 'Поручение: Отчёт', stageMail(id: next, after: stage), t0, to: toVera, cc: ccChief);
      await AssignmentStore.scan(db, {'a2': {vera}}, since: t0.subtract(const Duration(days: 1)));
      final waiting = (await AssignmentStore.all(db, {'a2': {vera}})).firstWhere((v) => v.id == next);
      expect(waiting.waiting, isTrue);
      await mail(
          'a2',
          boss,
          'Re: Поручение: Отчёт',
          assignmentNoteHtml(
              'Можно начинать', AssignmentCodec.statusMarker(next, AssignmentStatus.open, ev: 'ev:go', go: true), next),
          t0.add(const Duration(days: 1)));
      await AssignmentStore.scan(db, {'a2': {vera}}, since: t0);
      expect((await AssignmentStore.byId(db, next))!.waiting, isFalse);
    });

    test('передача для исполнения: соисполнитель добавляется у постановщика, исполнитель — прежний', () async {
      await AssignmentStore.insert(db,
          id: stage, accountId: 'a1', title: 'Сбор данных', ownerEmail: boss, assigneeEmail: vera, at: t0, outgoing: true);
      await mail(
          'a1',
          vera,
          'Fwd: Поручение: Сбор данных',
          assignmentNoteHtml('Подключаю Дмитрия',
              AssignmentCodec.peopleMarker(stage, dmitry, AssignmentRole.co, name: 'Дмитрий', ev: 'ev:d1'), stage),
          t0.add(const Duration(hours: 1)),
          to: '[{"email":"$dmitry","displayName":"Дмитрий"}]',
          cc: '[{"email":"$boss"}]');
      expect(await AssignmentStore.scan(db, {'a1': {boss}}, since: t0), 1);
      final v = (await AssignmentStore.all(db, {'a1': {boss}})).single;
      expect(v.assignee!.email, vera);
      expect(v.coExecutors.single.email, dmitry);
      expect(v.coExecutors.single.displayName, 'Дмитрий');
    });
  });
}

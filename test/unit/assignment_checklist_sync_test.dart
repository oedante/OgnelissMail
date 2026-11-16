// Чек-лист и пояснение поручения доходят до другой стороны (16.11.2026:
// «чек-лист и комментарий не виден другим или не копируется»): пункты в
// отметке статуса, слияние по тексту пункта, пояснение в отметке
// поручения, файлы без повторов, номер OGN-… не попадает в текст.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('без базы', () {
    test('пункты чек-листа в отметке статуса — туда и обратно', () {
      final m = AssignmentCodec.statusMarker('ABCDEFGHJKMN', AssignmentStatus.inProgress,
          checks: '10', items: [(text: 'Продажи; итог', done: true), (text: 'Склад | брак', done: false)]);
      final s = AssignmentCodec.parseStatus(m)!;
      expect(s.items, hasLength(2));
      expect(s.items![0], (text: 'Продажи; итог', done: true));
      expect(s.items![1], (text: 'Склад | брак', done: false));
      expect(s.checks, '10', reason: 'отметки строкой — для прежних версий');
      expect(AssignmentCodec.parseStatus(AssignmentCodec.statusMarker('ABCDEFGHJKMN', 2))!.items, isNull);
    });

    test('слияние: их пункты с их отметками, мои новые — в конце; по тексту, а не по номеру', () {
      final local = [
        const ChecklistItem('Склад'),
        const ChecklistItem('Продажи', done: true),
        const ChecklistItem('Кадры'),
      ];
      final merged = mergeRemoteChecklist(local, [(text: 'Продажи', done: true), (text: 'склад', done: true), (text: 'Брак', done: false)]);
      expect([for (final c in merged) c.text], ['Продажи', 'склад', 'Брак', 'Кадры']);
      expect([for (final c in merged) c.done], [true, true, false, false]);
    });

    test('файлы без повторов — по имени и размеру, а не по номеру письма', () {
      final files = uniqueFiles(const [
        AssignmentFile(name: 'Отчёт.xlsx', size: 100, mailId: 'm1', attachmentId: '1'),
        AssignmentFile(name: 'отчёт.xlsx', size: 100, mailId: 'm2', attachmentId: '1'),
        AssignmentFile(name: 'Отчёт.xlsx', size: 120, mailId: 'm3', attachmentId: '1'),
      ]);
      expect([for (final f in files) f.mailId], ['m1', 'm3']);
    });

    test('номер OGN-… с кодом действия вырезается из текста', () {
      expect(AssignmentCodec.stripTags('Готово\nОтчёт приложен OGN-ABCDEFGHJKMN-R'), 'Готово\nОтчёт приложен');
      expect(AssignmentCodec.stripTags('OGN-ABCDEFGHJKMN-T20261120 Новый срок'), 'Новый срок');
      expect(AssignmentCodec.stripTags('Без номера'), 'Без номера');
    });
  });

  group('разбор писем', () {
    late AppDatabase db;
    const boss = 'boss@corp.ru';
    const vera = 'vera@corp.ru';
    const id = 'ABCDEFGHJKMN';
    final t0 = DateTime(2026, 11, 16, 9);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      for (final (acc, email) in [('a1', boss), ('a2', vera)]) {
        await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: acc, type: 7, email: email, displayName: email, username: email, createdAt: DateTime(2026)));
        await db.into(db.folders).insert(FoldersCompanion.insert(
            id: 'in$acc', accountId: acc, displayName: 'Входящие', type: Value(FolderType.inbox.index)));
      }
    });
    tearDown(() => db.close());

    var n = 0;
    Future<void> mail(String account, String from, String subject, String html, DateTime at, {String to = '[]'}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: 'c${n++}',
              accountId: account,
              folderId: 'in$account',
              fromEmail: from,
              toRecipients: to,
              subject: subject,
              bodyHtml: Value(html),
              receivedAt: at,
            ));

    test('у исполнителя: пояснение и чек-лист обычного поручения', () async {
      await mail(
          'a2',
          boss,
          'Поручение: Годовой отчёт',
          AssignmentCodec.body(
            id: id,
            greeting: 'Вера, добрый день!',
            whatLabel: 'Поручение:',
            what: 'Годовой отчёт',
            description: 'Сводный, для правления',
            footer: 'Поручение из Ogneliss Mail',
            marker: AssignmentCodec.taskMarker(
                id: id, to: vera, title: 'Годовой отчёт', desc: 'Сводный, для правления', checklist: ['Продажи', 'Склад']),
          ),
          t0,
          to: '[{"email":"$vera"}]');
      await AssignmentStore.scan(db, {'a2': {vera}}, since: t0.subtract(const Duration(days: 1)));
      final row = (await AssignmentStore.byId(db, id))!;
      expect(row.description, 'Сводный, для правления');
      expect(ChecklistItem.decode(row.checklistJson).map((c) => c.text), ['Продажи', 'Склад']);
    });

    test('у постановщика: пункт, добавленный исполнителем, и отметки — по тексту; номер не в истории', () async {
      await AssignmentStore.insert(db,
          id: id,
          accountId: 'a1',
          title: 'Годовой отчёт',
          ownerEmail: boss,
          assigneeEmail: vera,
          at: t0,
          outgoing: true,
          checklist: const [ChecklistItem('Продажи'), ChecklistItem('Склад')]);
      await mail(
          'a1',
          vera,
          'Re: Поручение: Годовой отчёт',
          assignmentNoteHtml(
              'Чек-лист изменён:\n✓ Склад\n+ Брак',
              AssignmentCodec.statusMarker(id, AssignmentStatus.inProgress,
                  ev: 'ev:c1', items: [(text: 'Склад', done: true), (text: 'Продажи', done: false), (text: 'Брак', done: false)]),
              id),
          t0.add(const Duration(hours: 1)));
      expect(await AssignmentStore.scan(db, {'a1': {boss}}, since: t0), 1);
      final row = (await AssignmentStore.byId(db, id))!;
      final ck = ChecklistItem.decode(row.checklistJson);
      expect([for (final c in ck) c.text], ['Склад', 'Продажи', 'Брак']);
      expect([for (final c in ck) c.done], [true, false, false]);
      final events = await AssignmentStore.events(db, id);
      expect(events.last.payloadJson, isNot(contains('OGN-')));
    });
  });
}

// Поручения из письма (решения владельца 09.11.2026): метка в теме,
// скрытые отметки, статус по словам ответа на 27 языках, разбор писем.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_phrases.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('фразы ответа', () {
    AssignmentSignal? c(String t) => AssignmentPhrases.classify(t);

    test('«Принято» и «Готово» на разных языках', () {
      expect(c('Принято, сделаю к среде'), AssignmentSignal.accepted);
      expect(c('Иван Петрович, добрый день! Готово.'), AssignmentSignal.done);
      expect(c('Accepted, will send by Friday'), AssignmentSignal.accepted);
      expect(c('Done, see the attached file.'), AssignmentSignal.done);
      expect(c('Erledigt.'), AssignmentSignal.done);
      expect(c("C'est fait, merci"), AssignmentSignal.done);
      expect(c('承知しました。'), AssignmentSignal.accepted);
      expect(c('已完成，请查收'), AssignmentSignal.done);
      expect(c('Hotovo'), AssignmentSignal.done);
      expect(c('Принято, всё сделано'), AssignmentSignal.done, reason: '«Готово» главнее «Принято»');
    });

    test('отрицание, будущее, вопрос и часть слова — не статус', () {
      expect(c('Ещё не готово, будет завтра'), isNull);
      expect(c('Not done yet'), isNull);
      expect(c('It will be done by Friday'), isNull);
      expect(c('Is it done?'), isNull);
      expect(c('Всё переделано заново'), isNull);
      expect(c('Подскажите, где взять шаблон'), isNull);
      expect(c(''), isNull);
    });

    test('ответы кнопками — в словаре своего языка', () {
      for (final lang in AssignmentPhrases.accepted.keys) {
        expect(AssignmentPhrases.done.containsKey(lang), isTrue, reason: lang);
      }
      expect(AssignmentPhrases.accepted.length, 27);
    });
  });

  group('тег и отметки', () {
    test('код: 12 случайных знаков; тема — обычная, тег — в теле', () {
      final id = AssignmentCodec.newId();
      expect(id, matches(RegExp(r'^[2-9A-HJKMNP-TV-Z]{12}$')));
      expect({for (var i = 0; i < 1000; i++) AssignmentCodec.newId()}, hasLength(1000));
      final s = AssignmentCodec.subject(prefix: 'Поручение', title: 'Собрать даты отпусков', due: 'до 12.11');
      expect(s, 'Поручение: Собрать даты отпусков — до 12.11');
      expect(assignmentTitleFromSubject('Re: $s'), 'Собрать даты отпусков');

      final html = AssignmentCodec.body(
          id: id, greeting: 'Г', whatLabel: 'П:', what: 'Т', footer: 'Поручение из Ogneliss Mail', to: 'v@c.ru', title: 'Т');
      expect(AssignmentCodec.idFromBody(html), id);
      expect(AssignmentCodec.idFromBody('<p>Готово</p><blockquote>…Ogneliss Mail OGN-$id</blockquote>'), id);
      expect(AssignmentCodec.idFromBody('OGN-ABCDEFGH — короткий код'), isNull);
      // Текстовая версия письма (почта без HTML): только тег, без служебных строк.
      final plain = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
      expect(plain, contains('OGN-$id'));
      expect(plain, isNot(contains('ogneliss-task')));
      expect(plain, isNot(contains('v=1')));
    });

    test('отметка поручения и статуса — туда и обратно', () {
      final html = '<p>текст</p>${AssignmentCodec.taskMarker(id: 'ABCDEFGHJKMN', due: DateTime(2026, 11, 12), to: 'Vera@Corp.ru', title: 'Даты; отпуска', ev: 'created:ABCDEFGHJKMN')}';
      final t = AssignmentCodec.parseTask(html)!;
      expect(t.id, 'ABCDEFGHJKMN');
      expect(t.due, DateTime(2026, 11, 12));
      expect(t.to, 'vera@corp.ru');
      expect(t.title, 'Даты; отпуска');
      expect(t.ev, 'created:ABCDEFGHJKMN');
      final st = AssignmentCodec.parseStatus(AssignmentCodec.statusMarker('ABCDEFGHJKMN', AssignmentStatus.review, ev: 'ev:1'))!;
      expect(st.status, AssignmentStatus.review);
      expect(st.ev, 'ev:1');
      expect(AssignmentCodec.parseTask('<p>обычное письмо</p>'), isNull);
    });
  });

  group('разбор писем', () {
    late AppDatabase db;
    const boss = 'boss@corp.ru';
    const vera = 'vera@corp.ru';
    final t0 = DateTime(2026, 11, 9, 9, 20);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      for (final (id, email) in [('a1', boss), ('a2', vera)]) {
        await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: id, type: 7, email: email, displayName: email, username: email, createdAt: DateTime(2026)));
        await db.into(db.folders).insert(FoldersCompanion.insert(
            id: 'in$id', accountId: id, displayName: 'Входящие', type: Value(FolderType.inbox.index)));
      }
    });
    tearDown(() => db.close());

    var n = 0;
    Future<void> mail(String account, String from, String subject, String html, DateTime at,
            {String to = '[]', String? messageId, String? references, String? conversation}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: 'm${n++}',
              accountId: account,
              folderId: 'in$account',
              fromEmail: from,
              toRecipients: to,
              subject: subject,
              bodyHtml: Value(html),
              receivedAt: at,
              internetMessageId: Value(messageId),
              referencesStr: Value(references),
              conversationId: Value(conversation),
            ));

    final mineBoss = {'a1': {boss}};
    final mineVera = {'a2': {vera}};

    test('ответ по тегу в цитате, по ссылке на письмо и по беседе; статус — только вперёд', () async {
      const id = 'ABCDEFGHJKMN';
      await AssignmentStore.insert(db,
          id: id,
          accountId: 'a1',
          title: 'Собрать даты',
          ownerEmail: boss,
          assigneeEmail: vera,
          assigneeName: 'Вера Белова',
          at: t0,
          outgoing: true,
          eventId: 'created:$id');
      final original = AssignmentCodec.body(
          id: id, greeting: 'Вера, добрый день!', whatLabel: 'Поручение:', what: 'Собрать даты',
          footer: 'Поручение из Ogneliss Mail', to: vera, title: 'Собрать даты', ev: 'created:$id');
      // Своё отправленное письмо пришло в «Отправленные» — привязывается.
      await mail('a1', boss, 'Поручение: Собрать даты', original, t0.add(const Duration(minutes: 1)),
          messageId: '<orig@corp.ru>', conversation: 'conv1');
      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 0);

      // 1) Ответ из любой почты с цитатой (и со старой отметкой в цитате).
      await mail('a1', vera, 'RE: Поручение: Собрать даты', '<p>Принято, сделаю к среде</p><blockquote>$original</blockquote>',
          t0.add(const Duration(minutes: 20)));
      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 1);
      expect((await AssignmentStore.byId(db, id))!.status, AssignmentStatus.inProgress);

      // 2) Цитату удалили — по ссылке на письмо поручения.
      await mail('a1', vera, 'RE: Поручение: Собрать даты', '<p>Готово.</p>', t0.add(const Duration(hours: 2)),
          references: '<orig@corp.ru>');
      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 1);
      expect((await AssignmentStore.byId(db, id))!.status, AssignmentStatus.review);

      // 3) Та же беседа сервера; слова не возвращают статус назад.
      await mail('a1', vera, 'RE: Поручение: Собрать даты', '<p>Принято</p>', t0.add(const Duration(hours: 3)),
          conversation: 'conv1');
      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 1);
      expect((await AssignmentStore.byId(db, id))!.status, AssignmentStatus.review);

      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 0, reason: 'письма уже разобраны');
      final list = await AssignmentStore.all(db, mineBoss);
      expect(list.single.outgoing, isTrue);
      expect(list.single.otherName, 'Вера Белова');
      expect((await AssignmentStore.events(db, id)).length, 4, reason: 'создано и три ответа');
    });

    test('у исполнителя: поручение появляется само; поручено не мне — нет', () async {
      final html = AssignmentCodec.body(
        id: 'KMNPQRSTVWXY',
        greeting: 'Вера, добрый день!',
        whatLabel: 'Поручение:',
        what: 'Собрать даты отпусков',
        footer: 'Поручение из Ogneliss Mail',
        due: DateTime(2026, 11, 12),
        to: vera,
        title: 'Собрать даты отпусков',
      );
      await mail('a2', boss, 'Поручение: Собрать даты отпусков — до 12.11', html, t0);
      final other = html.replaceAll('KMNPQRSTVWXY', 'VWXYZ2345678').replaceAll(vera, 'dmitry@corp.ru');
      await mail('a2', boss, 'Поручение: Склад', other, t0);
      expect(await AssignmentStore.scan(db, mineVera, since: t0.subtract(const Duration(days: 1))), 1);
      final list = await AssignmentStore.all(db, mineVera);
      expect(list, hasLength(1));
      final v = list.single;
      expect(v.outgoing, isFalse);
      expect(v.row.title, 'Собрать даты отпусков');
      expect(v.due, DateTime(2026, 11, 12));
      expect(v.otherEmail, boss);

      // Поручивший принял работу — отметкой статуса.
      await mail('a2', boss, 'Re: Поручение: Собрать даты отпусков',
          assignmentNoteHtml('Работа принята', AssignmentCodec.statusMarker('KMNPQRSTVWXY', AssignmentStatus.done),
              'KMNPQRSTVWXY'),
          t0.add(const Duration(days: 1)));
      await AssignmentStore.scan(db, mineVera, since: t0);
      expect((await AssignmentStore.byId(db, 'KMNPQRSTVWXY'))!.status, AssignmentStatus.done);
    });

    test('письмо не от участника с тем же кодом — не трогает поручение', () async {
      await AssignmentStore.insert(db,
          id: 'ABCDEFGHJKMN', accountId: 'a1', title: 'Т', ownerEmail: boss, assigneeEmail: vera, at: t0, outgoing: true);
      await mail('a1', 'stranger@other.org', 'Re: Поручение: Т', '<p>Готово</p><p>OGN-ABCDEFGHJKMN</p>',
          t0.add(const Duration(minutes: 5)));
      expect(await AssignmentStore.scan(db, mineBoss, since: t0), 0);
      expect((await AssignmentStore.byId(db, 'ABCDEFGHJKMN'))!.status, AssignmentStatus.open);
    });

    test('своё отправленное письмо не задваивает историю', () async {
      await AssignmentStore.insert(db,
          id: 'ABCDEFGHJKMN', accountId: 'a1', title: 'Т', ownerEmail: boss, assigneeEmail: vera, at: t0, outgoing: true,
          eventId: 'created:ABCDEFGHJKMN');
      final html = AssignmentCodec.body(
          id: 'ABCDEFGHJKMN', greeting: 'Г', whatLabel: 'П:', what: 'Т', footer: 'Ф', to: vera, ev: 'created:ABCDEFGHJKMN');
      await mail('a1', boss, 'Поручение: Т', html, t0.add(const Duration(minutes: 1)));
      expect(await AssignmentStore.scan(db, mineBoss, since: t0.subtract(const Duration(days: 1))), 0);
      expect((await AssignmentStore.events(db, 'ABCDEFGHJKMN')).length, 1);
    });
  });
}

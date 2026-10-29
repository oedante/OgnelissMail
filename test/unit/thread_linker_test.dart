// Беседы IMAP по ссылкам на письма и по теме с собеседником (1.8.13,
// замечание владельца 29.10.2026: «не всегда складываются темы из-за
// некорректного определения пользователя»).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart' show imapConversationId, imapReferenceIds;
import 'package:ogneliss/services/mail/own_addresses.dart';
import 'package:ogneliss/services/mail/thread_linker.dart';

ThreadMsg _m(String id, {String? mid, List<String> refs = const [], String? conv, int day = 1,
        String subject = 'S', String from = 'x@ext', Set<String> people = const {}}) =>
    ThreadMsg(
      id: id,
      messageId: mid,
      refs: refs,
      conv: conv ?? (refs.isNotEmpty ? refs.first : mid),
      subject: subject,
      at: DateTime(2026, 10, day, 10),
      from: from,
      people: {from, ...people},
    );

final _icloud = AccountModel(
  id: 'a1',
  type: AccountType.imap,
  email: 'oleg@icloud.com',
  displayName: 'Олег',
  username: 'oleg@icloud.com',
  createdAt: DateTime(2026),
);

EmailModel _mail(String id,
        {String? mid, List<String>? refs, String subject = 'Отчёт', String from = 'ivan@ext.ru',
        List<String> to = const ['oleg@icloud.com'], int day = 1}) =>
    EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'INBOX',
      internetMessageId: mid,
      references: refs,
      conversationId: imapConversationId(refs?.join(' '), null, mid),
      from: EmailAddress(email: from),
      to: [for (final t in to) EmailAddress(email: t)],
      subject: subject,
      receivedAt: DateTime(2026, 10, day, 10),
    );

void main() {
  group('цепочка письма', () {
    test('родитель из In-Reply-To — в конце, если в References его нет', () {
      expect(imapReferenceIds('<a@x> <b@x>', '<c@x>'), ['<a@x>', '<b@x>', '<c@x>']);
      expect(imapReferenceIds('<a@x> <b@x>', '<b@x>'), ['<a@x>', '<b@x>']);
      expect(imapReferenceIds(null, ' <p@x> '), ['<p@x>']);
      expect(imapReferenceIds(null, null), isNull);
    });
  });

  group('раскладка по ссылкам', () {
    test('Outlook: в References только родитель — письмо в беседе родителя', () {
      // A — начало, B отвечает на A, C (Outlook) ссылается только на B.
      final plan = ThreadLinker.plan([
        _m('c', mid: '<c@x>', refs: ['<b@x>'], day: 3),
      ], known: {'<a@x>': '<a@x>', '<b@x>': '<a@x>'});
      expect(plan.conv['c'], '<a@x>');
    });

    test('в одном пакете: родитель раньше ответа, порядок пакета не важен', () {
      final plan = ThreadLinker.plan([
        _m('c', mid: '<c@x>', refs: ['<b@x>'], day: 3),
        _m('a', mid: '<a@x>', day: 1),
        _m('b', mid: '<b@x>', refs: ['<a@x>'], day: 2),
      ]);
      expect(plan.conv, {'a': '<a@x>', 'b': '<a@x>', 'c': '<a@x>'});
      // Беседа «<b@x>» (так её назвал бы ответ из Outlook) — в «<a@x>»: туда
      // же уйдут такие ответы, уже лежащие в базе.
      expect(plan.merge, {'<b@x>': '<a@x>'});
    });

    test('письмо связывает две беседы базы — они сливаются в раннюю', () {
      final plan = ThreadLinker.plan([
        _m('d', mid: '<d@x>', refs: ['<a@x>', '<c@x>'], day: 4),
      ], known: {'<a@x>': '<a@x>', '<c@x>': '<c@x>'});
      expect(plan.conv['d'], '<a@x>');
      expect(plan.merge, {'<c@x>': '<a@x>'});
    });

    test('ответ пришёл раньше письма, на которое отвечает: его беседа сливается', () {
      // В базе ответ с беседой «<b@x>» (ссылался только на b); приходит b.
      final plan = ThreadLinker.plan([
        _m('b', mid: '<b@x>', refs: ['<a@x>'], day: 2),
      ], known: {'<a@x>': '<a@x>'}, childConv: {'<b@x>'});
      expect(plan.conv['b'], '<a@x>');
      expect(plan.merge, {'<b@x>': '<a@x>'});
    });

    test('без известных ссылок — беседа по заголовкам', () {
      final plan = ThreadLinker.plan([_m('n', mid: '<n@x>', refs: ['<old@x>'])]);
      expect(plan.conv['n'], '<old@x>');
      expect(plan.merge, isEmpty);
    });
  });

  group('тема и собеседник (ответ без заголовков цепочки)', () {
    const own = {'oleg@icloud.com'};

    test('ответ собеседника на моё письмо', () {
      final mine = _m('1', subject: 'Отчёт', from: 'oleg@icloud.com', people: {'ivan@ext.ru'}, day: 1);
      final reply = _m('2', subject: 'RE: Отчёт', from: 'ivan@ext.ru', people: {'oleg@icloud.com'}, day: 2);
      expect(ThreadLinker.sameTopicPeer(reply, mine, own), isTrue);
    });

    test('мой ответ на письмо собеседника', () {
      final his = _m('1', subject: 'Отчёт', from: 'ivan@ext.ru', people: {'oleg@icloud.com'}, day: 1);
      final reply = _m('2', subject: 'Ответ: Отчёт', from: 'oleg@icloud.com', people: {'ivan@ext.ru'}, day: 2);
      expect(ThreadLinker.sameTopicPeer(reply, his, own), isTrue);
    });

    test('та же тема от разных людей на мой адрес — разные беседы', () {
      final a = _m('1', subject: 'Счёт', from: 'shop-a@ext.ru', people: {'oleg@icloud.com'}, day: 1);
      final b = _m('2', subject: 'RE: Счёт', from: 'shop-b@ext.ru', people: {'oleg@icloud.com'}, day: 2);
      expect(ThreadLinker.sameTopicPeer(b, a, own), isFalse);
      // И с неузнанным своим адресом — тоже не склеиваются.
      final a2 = _m('1', subject: 'Счёт', from: 'shop-a@ext.ru', people: {'nick@icloud.com'}, day: 1);
      final b2 = _m('2', subject: 'RE: Счёт', from: 'shop-b@ext.ru', people: {'nick@icloud.com'}, day: 2);
      expect(ThreadLinker.sameTopicPeer(b2, a2, own), isFalse);
    });

    test('другая тема и старше месяца — нет', () {
      final his = _m('1', subject: 'Отчёт', from: 'ivan@ext.ru', day: 1);
      expect(ThreadLinker.sameTopicPeer(_m('2', subject: 'RE: План', from: 'ivan@ext.ru'), his, own), isFalse);
      final old = ThreadMsg(
          id: '0', messageId: null, refs: const [], conv: 'c', subject: 'Отчёт', at: DateTime(2026, 8, 1),
          from: 'ivan@ext.ru', people: const {'ivan@ext.ru'});
      expect(ThreadLinker.sameTopicPeer(_m('2', subject: 'RE: Отчёт', from: 'ivan@ext.ru', day: 20), old, own),
          isFalse);
    });
  });

  group('свои адреса ящика', () {
    test('iCloud: icloud.com, me.com и mac.com — один ящик', () {
      expect(OwnAddresses.sameMailbox('Oleg@icloud.com'), {'oleg@icloud.com', 'oleg@me.com', 'oleg@mac.com'});
      expect(OwnAddresses.isMine(_icloud, 'OLEG@me.com'), isTrue);
      expect(OwnAddresses.isMine(_icloud, 'oleg@mail.ru'), isFalse);
    });

    test('Gmail: точки и «+метка» не важны; Яндекс: домены и «-»/«.»', () {
      final g = AccountModel(
          id: 'g', type: AccountType.google, email: 'i.petrov@gmail.com', displayName: 'И', username: 'u',
          createdAt: DateTime(2026));
      expect(OwnAddresses.isMine(g, 'ipetrov+work@googlemail.com'), isTrue);
      expect(OwnAddresses.isMine(g, 'ipetrova@gmail.com'), isFalse);
      expect(OwnAddresses.sameMailbox('i-petrov@yandex.ru'), contains('i.petrov@ya.ru'));
      expect(OwnAddresses.sameMailbox('boss@corp.example'), {'boss@corp.example'});
    });
  });

  group('в базе', () {
    late Directory dir;
    late AppDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ogneliss_threads');
      db = AppDatabase.forTesting(NativeDatabase(File('${dir.path}/t.db')));
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: AccountType.imap.index, email: 'oleg@icloud.com', displayName: 'Олег', username: 'oleg',
          createdAt: DateTime(2026)));
    });

    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> put(EmailModel e, {String folder = 'INBOX'}) => db.into(db.emails).insert(EmailsCompanion.insert(
          id: e.id,
          accountId: 'a1',
          folderId: folder,
          fromEmail: e.from.email,
          toRecipients: jsonEncode([for (final a in e.to) a.toMap()]),
          subject: e.subject,
          receivedAt: e.receivedAt,
          conversationId: Value(e.conversationId),
          internetMessageId: Value(e.internetMessageId),
          referencesStr: Value(e.references?.join(' ')),
        ));

    test('ответ из Outlook встаёт в беседу, ответ без заголовков — по теме', () async {
      await put(_mail('a', mid: '<a@x>', day: 1));
      await put(_mail('b', mid: '<b@x>', refs: ['<a@x>'], day: 2,
          from: 'oleg@icloud.com', to: ['ivan@ext.ru']), folder: 'Sent');
      final linked = await ThreadLinker.link(db, _icloud, [
        _mail('c', mid: '<c@x>', refs: ['<b@x>'], subject: 'RE: Отчёт', day: 3),
        // Без References и In-Reply-To (веб-форма) — по теме и собеседнику.
        _mail('d', mid: '<d@x>', subject: 'RE: Отчёт', day: 4),
        // Та же тема от другого человека — своя беседа.
        _mail('e', mid: '<e@x>', subject: 'RE: Отчёт', from: 'shop@ext.ru', day: 4),
      ]);
      final conv = {for (final e in linked) e.id: e.conversationId};
      expect(conv['c'], '<a@x>');
      expect(conv['d'], '<a@x>');
      expect(conv['e'], '<e@x>');
    });

    test('разово после обновления: разорванные беседы сливаются', () async {
      await put(_mail('a', mid: '<a@x>', day: 1));
      await put(_mail('b', mid: '<b@x>', refs: ['<a@x>'], day: 2));
      await put(_mail('c', mid: '<c@x>', refs: ['<b@x>'], day: 3)); // беседа «<b@x>»
      expect(await ThreadLinker.relinkAccount(db, _icloud), 1);
      final rows = await db.select(db.emails).get();
      expect({for (final r in rows) r.conversationId}, {'<a@x>'});
      expect(await ThreadLinker.relinkAccount(db, _icloud), 0);
    });
  });
}

// @-упоминания (2.2.0, план 08.11.2026 «из мессенджеров»: значок «@» в
// ленте и фильтр «Упоминания»).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/mentions.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/services/mail/mention_scanner.dart';

const _me = ['ivan.petrov@corp.example'];
const _names = ['Петров Иван Сергеевич'];

bool _html(String html) => Mentions.mentionsMe(html: html, emails: _me, names: _names);

void main() {
  group('распознавание', () {
    test('Outlook и OWA: ссылка-упоминание на мой адрес', () {
      expect(
          _html('<p>Коллеги, <a id="OWAAM8F2C" href="mailto:ivan.petrov@corp.example">@Петров Иван</a>, '
              'посмотрите смету.</p>'),
          isTrue);
    });

    test('Gmail: «+Имя» на мой адрес', () {
      expect(_html('<div><a class="gmail_plusreply" href="mailto:Ivan.Petrov@corp.example">+Иван</a> глянь</div>'), isTrue);
    });

    test('упоминание другого человека — не моё', () {
      expect(_html('<p><a id="OWAAM1" href="mailto:anna@corp.example">@Анна Смирнова</a>, посмотрите.</p>'), isFalse);
    });

    test('обычная ссылка на мой адрес без «@» — не упоминание (подпись, «Кому»)', () {
      expect(_html('<p>Пишите: <a href="mailto:ivan.petrov@corp.example">ivan.petrov@corp.example</a></p>'), isFalse);
    });

    test('«@Имя Фамилия» текстом: оба порядка, без отчества', () {
      expect(_html('<p>@Иван Петров, подготовьте отчёт.</p>'), isTrue);
      expect(_html('<p>@Петров Иван — на согласование.</p>'), isTrue);
      expect(_html('<p>@петров иван сергеевич, привет</p>'), isTrue);
    });

    test('одно имя, адрес почты и другое имя — не упоминание', () {
      expect(_html('<p>@Иван, привет</p>'), isFalse, reason: 'тёзок много');
      expect(_html('<p>Пишите на test@Иван Петров.рф</p>'), isFalse, reason: 'часть адреса');
      expect(_html('<p>@Ивана Петрова не будет</p>'), isFalse);
    });

    test('упоминание только в цитате прежней переписки — не новое', () {
      expect(
          _html('<p>Спасибо, принято.</p><div class="gmail_quote">'
              '<div>On Mon, Anna wrote:</div><blockquote class="gmail_quote">'
              '<a class="gmail_plusreply" href="mailto:ivan.petrov@corp.example">+Иван</a> посмотри</blockquote></div>'),
          isFalse);
    });

    test('письмо без HTML', () {
      expect(Mentions.mentionsMe(text: '@Иван Петров, нужна подпись', emails: _me, names: _names), isTrue);
      expect(
          Mentions.mentionsMe(
              text: 'Ок.\n\n> @Иван Петров, нужна подпись', emails: _me, names: _names),
          isFalse,
          reason: 'только в цитате «>»');
    });
  });

  group('база', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'ivan.petrov@corp.example', displayName: 'Иван', username: 'me',
          createdAt: DateTime(2026)));
      await db.into(db.folders).insert(FoldersCompanion.insert(id: 'INBOX', accountId: 'a1', displayName: 'Входящие'));
      Future<void> mail(String id, {bool? mentions}) => db.into(db.emails).insert(EmailsCompanion.insert(
            id: id,
            accountId: 'a1',
            folderId: 'INBOX',
            fromEmail: 'anna@corp.example',
            toRecipients: '[]',
            subject: 'Письмо $id',
            receivedAt: DateTime.now(),
            mentionsMe: Value(mentions),
          ));
      await mail('1', mentions: true);
      await mail('2', mentions: false);
      await mail('3');
    });
    tearDown(() => db.close());

    test('фильтр «Упоминания» — только отмеченные', () async {
      final rows = await db
          .watchEmailsPage(
              accountId: 'a1', folderId: 'INBOX', limit: 50, offset: 0, filter: const EmailListFilter(mentions: true))
          .first;
      expect([for (final r in rows) r.id], ['1']);
    });
  });

  test('проверка пачкой: id → упомянут ли', () {
    final r = scanMentions((
      mails: [
        (id: 'a', html: '<p>@Петров Иван, срочно</p>', plain: null),
        (id: 'b', html: null, plain: 'Без упоминаний'),
        (id: 'c', html: null, plain: null),
      ],
      emails: _me,
      names: _names,
    ));
    expect(r, {'a': true, 'b': false, 'c': false});
  });
}

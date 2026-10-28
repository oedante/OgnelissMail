// Ответ, пересылка и приглашения как в Outlook (1.5.12).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show EasEngine;
import 'package:ogneliss/data/models/calendar_event_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/calendar/itip_reply.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/reply_builder.dart';

void main() {
  const me = 'me@corp.ru';
  bool mine(String e) => e.toLowerCase() == me;
  const boss = EmailAddress(email: 'boss@corp.ru', displayName: 'Начальник');
  const a = EmailAddress(email: 'a@corp.ru', displayName: 'А');
  const b = EmailAddress(email: 'b@corp.ru', displayName: 'Б');
  const c = EmailAddress(email: 'c@corp.ru');
  const self = EmailAddress(email: 'ME@corp.ru');

  group('получатели ответа', () {
    test('«Ответить» — отправителю', () {
      final r = ReplyBuilder.recipients(from: boss, to: [self, a], cc: [b], all: false, mine: mine);
      expect(r.to.map((x) => x.email), ['boss@corp.ru']);
      expect(r.cc, isEmpty);
    });

    test('«Ответить всем»: «Кому» остаются в «Кому», «Копия» — в копии, себя нет', () {
      final r = ReplyBuilder.recipients(from: boss, to: [self, a], cc: [b, c, self], all: true, mine: mine);
      expect(r.to.map((x) => x.email), ['boss@corp.ru', 'a@corp.ru']);
      expect(r.cc.map((x) => x.email), ['b@corp.ru', 'c@corp.ru']);
    });

    test('Reply-To вместо отправителя', () {
      const list = EmailAddress(email: 'support@corp.ru');
      final r = ReplyBuilder.recipients(from: boss, replyTo: [list], to: [self], all: false, mine: mine);
      expect(r.to.map((x) => x.email), ['support@corp.ru']);
      // Reply-To на себя — отвечаем отправителю.
      final r2 = ReplyBuilder.recipients(from: boss, replyTo: [self], to: [self], all: false, mine: mine);
      expect(r2.to.map((x) => x.email), ['boss@corp.ru']);
    });

    test('ответ на своё письмо — тем, кому оно ушло', () {
      final r = ReplyBuilder.recipients(from: self, to: [a, b], cc: [c], all: false, mine: mine);
      expect(r.to.map((x) => x.email), ['a@corp.ru', 'b@corp.ru']);
      expect(r.cc, isEmpty);
      final all = ReplyBuilder.recipients(from: self, to: [a], cc: [c], all: true, mine: mine);
      expect(all.cc.map((x) => x.email), ['c@corp.ru']);
    });

    test('повторы убираются без учёта регистра', () {
      final r = ReplyBuilder.recipients(
          from: boss, to: [const EmailAddress(email: 'BOSS@corp.ru'), a], cc: [a], all: true, mine: mine);
      expect(r.to.map((x) => x.email), ['boss@corp.ru', 'a@corp.ru']);
      expect(r.cc, isEmpty);
    });
  });

  group('шапка цитаты', () {
    const labels = {'from': 'От:', 'sent': 'Отправлено:', 'to': 'Кому:', 'cc': 'Копия:', 'subject': 'Тема:'};

    test('строки Outlook, адреса через «; », пустая копия не выводится', () {
      final h = ReplyBuilder.header(
          labels: labels, from: boss, sent: 'понедельник, 12 октября 2026 г. 16:38', to: [a, c], subject: 'Отчёт <Q3>');
      expect(h, contains('<b>От:</b> Начальник &lt;boss@corp.ru&gt;'));
      expect(h, contains('<b>Отправлено:</b> понедельник, 12 октября 2026 г. 16:38'));
      expect(h, contains('<b>Кому:</b> А &lt;a@corp.ru&gt;; c@corp.ru'));
      expect(h, isNot(contains('Копия:')));
      expect(h, contains('<b>Тема:</b> Отчёт &lt;Q3&gt;'));
      expect(h, contains('border-top:solid #E1E1E1 1.0pt'));
      expect(h, contains('id="divRplyFwdMsg"'));
    });

    test('цитата без отступа-blockquote', () {
      final q = ReplyBuilder.quote('<div>h</div>', '<p>оригинал</p>');
      expect(q, isNot(contains('blockquote')));
      expect(q, '<div>h</div><div><p>оригинал</p></div>');
    });
  });

  group('EWS', () {
    test('ReplyToItem / ReplyAllToItem: получателей выбирает сервер', () {
      final xml = EwsXmlBuilder.buildReplyToItem(referenceItemId: 'X', all: true, bodyContent: 'ок', newSubject: 'RE: т');
      expect(xml, contains('<t:ReplyAllToItem>'));
      expect(xml, isNot(contains('<t:ToRecipients>')));
      expect(xml.indexOf('<t:ReferenceItemId') < xml.indexOf('<t:NewBodyContent'), isTrue);
      expect(EwsXmlBuilder.buildReplyToItem(referenceItemId: 'X', bodyContent: ''), contains('<t:ReplyToItem>'));
    });

    test('ответ на приглашение: комментарий, «не отправлять», новое время', () {
      final xml = EwsXmlBuilder.buildMeetingResponse('M1', 'DeclineItem',
          comment: 'Занят <весь день>',
          proposedStart: DateTime.utc(2026, 10, 13, 10),
          proposedEnd: DateTime.utc(2026, 10, 13, 11));
      expect(xml, contains('MessageDisposition="SendAndSaveCopy"'));
      expect(xml, contains('<t:Body BodyType="Text">Занят &lt;весь день&gt;</t:Body>'));
      final iBody = xml.indexOf('<t:Body');
      final iRef = xml.indexOf('<t:ReferenceItemId');
      final iProp = xml.indexOf('<t:ProposedStart>2026-10-13T10:00:00.000Z');
      expect(iBody < iRef && iRef < iProp, isTrue);
      expect(xml, contains('<t:ProposedEnd>2026-10-13T11:00:00.000Z</t:ProposedEnd>'));

      final quiet = EwsXmlBuilder.buildMeetingResponse('M1', 'AcceptItem', send: false);
      expect(quiet, contains('MessageDisposition="SaveOnly"'));
      expect(quiet, isNot(contains('<t:Body')));
      expect(quiet, isNot(contains('Proposed')));
    });

    test('изменение встречи меняет и участников', () {
      final e = CalendarEventModel(
        id: 'E',
        accountId: 'acc',
        title: 'Планёрка',
        startTime: DateTime(2026, 10, 13, 10),
        endTime: DateTime(2026, 10, 13, 11),
        attendees: const [
          EventAttendee(email: 'a@corp.ru', displayName: 'А'),
          EventAttendee(email: 'b@corp.ru', isRequired: false),
        ],
        createdAt: DateTime(2026),
      );
      final xml = EwsXmlBuilder.buildUpdateCalendarItem('E', 'CK', e);
      expect(xml, contains('FieldURI="calendar:RequiredAttendees"'));
      expect(xml, contains('<t:RequiredAttendees><t:Attendee><t:Mailbox><t:Name>А</t:Name><t:EmailAddress>a@corp.ru'));
      expect(xml, contains('<t:OptionalAttendees><t:Attendee><t:Mailbox><t:EmailAddress>b@corp.ru'));

      // Без участников список не трогаем — иначе ушла бы отмена всем.
      final bare = CalendarEventModel(
          id: 'E', accountId: 'acc', title: 't', startTime: DateTime(2026), endTime: DateTime(2026), createdAt: DateTime(2026));
      expect(EwsXmlBuilder.buildUpdateCalendarItem('E', 'CK', bare), isNot(contains('Attendees')));
    });
  });

  group('iMIP для ActiveSync до 16.0', () {
    test('UID из GlobalObjId: hex без даты вхождения', () {
      final b = Uint8List(56);
      for (var i = 0; i < 16; i++) {
        b[i] = i + 1;
      }
      b[16] = 0x07; b[17] = 0xEA; b[18] = 10; b[19] = 13; // вхождение 13.10.2026
      b[36] = 16; // размер данных
      for (var i = 40; i < 56; i++) {
        b[i] = 0xAB;
      }
      final g = base64.encode(b);
      final uid = EasEngine.uidFromGlobalObjId(g)!;
      expect(uid.length, 112);
      expect(uid.substring(32, 40), '00000000');
      expect(uid.startsWith('0102030405060708090A0B0C0D0E0F10'), isTrue);
      expect(EasEngine.isOccurrenceGlobalObjId(g), isTrue);
    });

    test('UID из GlobalObjId: исходный UID iCalendar после «vCal-Uid»', () {
      final data = [...ascii.encode('vCal-Uid'), 1, 0, 0, 0, ...utf8.encode('abc-123@ext'), 0];
      final b = Uint8List(40 + data.length);
      b[36] = data.length;
      b.setRange(40, b.length, data);
      expect(EasEngine.uidFromGlobalObjId(base64.encode(b)), 'abc-123@ext');
      expect(EasEngine.isOccurrenceGlobalObjId(base64.encode(b)), isFalse);
      expect(EasEngine.uidFromGlobalObjId('не base64'), isNull);
    });

    test('REPLY и COUNTER', () {
      final now = DateTime.utc(2026, 10, 12, 9);
      final reply = ItipReply.build(
        uid: 'U1',
        organizer: 'boss@corp.ru',
        attendee: me,
        attendeeName: 'Иванов, Иван',
        response: 'accept',
        start: DateTime.utc(2026, 10, 13, 10),
        end: DateTime.utc(2026, 10, 13, 11),
        summary: 'Планёрка; итоги',
        comment: 'Буду\nс отчётом',
        now: now,
      );
      expect(reply, contains('METHOD:REPLY\r\n'));
      expect(reply, contains('UID:U1\r\n'));
      expect(reply, contains('DTSTART:20261013T100000Z\r\n'));
      expect(reply, contains('SUMMARY:Планёрка\\; итоги\r\n'));
      expect(reply, contains('ATTENDEE;PARTSTAT=ACCEPTED;CN="Иванов, Иван":mailto:me@corp.ru'));
      expect(reply, contains('COMMENT:Буду\\nс отчётом\r\n'));
      expect(reply.endsWith('END:VCALENDAR\r\n'), isTrue);

      final counter = ItipReply.build(
        uid: 'U1',
        organizer: 'boss@corp.ru',
        attendee: me,
        response: 'tentative',
        start: DateTime.utc(2026, 10, 13, 10),
        end: DateTime.utc(2026, 10, 13, 11),
        proposedStart: DateTime.utc(2026, 10, 14, 12),
        proposedEnd: DateTime.utc(2026, 10, 14, 13),
        now: now,
      );
      expect(counter, contains('METHOD:COUNTER'));
      expect(counter, contains('DTSTART:20261014T120000Z'));
      expect(counter, contains('PARTSTAT=TENTATIVE'));
    });

    test('длинные строки переносятся не длиннее 75 октетов', () {
      final ics = ItipReply.build(
          uid: 'U', organizer: 'o@x.ru', attendee: 'a@x.ru', response: 'decline', comment: 'Комментарий ' * 20);
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length <= 75, isTrue, reason: line);
      }
      expect(ItipReply.organizerEmail('Иван Петров <ivan.petrov@corp.ru>'), 'ivan.petrov@corp.ru');
    });
  });
}

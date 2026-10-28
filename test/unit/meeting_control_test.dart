// Собрания как в Outlook (1.6.7): ответы участников, предложенное время,
// поиск свободного окна, рассылка обновления и серии в EWS.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/calendar_event_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/free_busy_view.dart';
import 'package:ogneliss/features/calendar/meeting_replies.dart';
import 'package:ogneliss/features/calendar/screens/create_event_screen.dart' show nextHalfHour, defaultMeetingLength;
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';

void main() {
  group('ответы на собрание', () {
    final start = DateTime.utc(2026, 10, 14, 6);
    String meeting(String cls, {DateTime? propStart, DateTime? propEnd}) => jsonEncode({
          'start': start.toIso8601String(),
          'end': start.add(const Duration(hours: 1)).toIso8601String(),
          'class': cls,
          if (propStart != null) 'propStart': propStart.toIso8601String(),
          if (propEnd != null) 'propEnd': propEnd.toIso8601String(),
        });

    test('вид ответа по классу письма', () {
      expect(EmailMeeting.parse(meeting('IPM.Schedule.Meeting.Resp.Pos'))!.responseKind, 1);
      expect(EmailMeeting.parse(meeting('IPM.Schedule.Meeting.Resp.Tent'))!.responseKind, 2);
      expect(EmailMeeting.parse(meeting('IPM.Schedule.Meeting.Resp.Neg'))!.responseKind, 3);
      expect(EmailMeeting.parse(meeting('IPM.Schedule.Meeting.Request'))!.responseKind, 0);
    });

    test('последний ответ участника, только по этой встрече', () {
      final p = start.add(const Duration(days: 1));
      final rows = [
        (id: 'a1', fromEmail: 'Ivanov@corp.ru', fromName: 'Иванов Иван Иванович', preview: 'Буду', receivedAt: DateTime(2026, 10, 13, 9), meetingJson: meeting('IPM.Schedule.Meeting.Resp.Pos')),
        (id: 'a2', fromEmail: 'ivanov@corp.ru', fromName: null, preview: 'Когда: завтра\nНе смогу, давайте позже\n-----', receivedAt: DateTime(2026, 10, 13, 10), meetingJson: meeting('IPM.Schedule.Meeting.Resp.Tent', propStart: p, propEnd: p.add(const Duration(hours: 1)))),
        (id: 'b1', fromEmail: 'petrov@corp.ru', fromName: null, preview: '', receivedAt: DateTime(2026, 10, 13, 11), meetingJson: meeting('IPM.Schedule.Meeting.Resp.Neg')),
        (id: 'x', fromEmail: 'stranger@corp.ru', fromName: null, preview: '', receivedAt: DateTime(2026, 10, 13, 12), meetingJson: meeting('IPM.Schedule.Meeting.Resp.Pos')),
      ];
      final r = matchReplies(rows, start: start, attendees: {'ivanov@corp.ru', 'petrov@corp.ru'});
      expect(r.map((e) => e.emailId), ['b1', 'a2']);
      final iv = r.last;
      expect(iv.kind, 2);
      expect(iv.hasProposal, isTrue);
      expect(iv.comment, 'Не смогу, давайте позже');
      // Ответ на другую встречу (другое начало) не учитывается.
      expect(matchReplies(rows, start: start.add(const Duration(hours: 2)), attendees: {'ivanov@corp.ru'}), isEmpty);
    });

    test('сводка ответов', () {
      final s = MeetingReplySummary.of([1, 1, 2, 3, 0, 0]);
      expect([s.accepted, s.tentative, s.declined, s.none, s.total], [2, 1, 1, 2, 6]);
    });
  });

  group('поиск свободного окна', () {
    // Понедельник 12.10.2026 08:00, 30-минутные интервалы до 18:00 (20 шт.).
    final mon = DateTime(2026, 10, 12, 8);
    test('окно только там, где свободны все', () {
      final st = List.filled(20, 0);
      for (var i = 0; i < 4; i++) {
        st[i] = 2; // 08:00–10:00 занято
      }
      final v = FreeBusyView(startLocal: mon, intervalMinutes: 30, statuses: st);
      final slots = v.freeSlots(const Duration(hours: 1));
      expect(slots.first, DateTime(2026, 10, 12, 10));
      // Окна в день не пересекаются, не больше трёх.
      expect(slots, [DateTime(2026, 10, 12, 10), DateTime(2026, 10, 12, 11), DateTime(2026, 10, 12, 12)]);
    });

    test('окно не выходит за конец рабочего дня и не в прошлом', () {
      final v = FreeBusyView(startLocal: mon, intervalMinutes: 30, statuses: List.filled(20, 0));
      final slots = v.freeSlots(const Duration(hours: 2), notBefore: DateTime(2026, 10, 12, 16, 30));
      expect(slots, isEmpty);
    });

    test('без данных о занятости окна не предлагаются', () {
      final v = FreeBusyView(startLocal: mon, intervalMinutes: 30, statuses: List.filled(20, 4));
      expect(v.freeSlots(const Duration(minutes: 30)), isEmpty);
    });

    test('выходные пропускаются', () {
      final sat = DateTime(2026, 10, 17, 8);
      final v = FreeBusyView(startLocal: sat, intervalMinutes: 30, statuses: List.filled(20, 0));
      expect(v.freeSlots(const Duration(minutes: 30)), isEmpty);
    });
  });

  test('новая встреча — с ближайшего получаса на 30 минут (1.6.8)', () {
    expect(nextHalfHour(DateTime(2026, 10, 13, 19, 48)), DateTime(2026, 10, 13, 20));
    expect(nextHalfHour(DateTime(2026, 10, 13, 20)), DateTime(2026, 10, 13, 20));
    expect(nextHalfHour(DateTime(2026, 10, 13, 20, 1)), DateTime(2026, 10, 13, 20, 30));
    expect(nextHalfHour(DateTime(2026, 10, 13, 20, 30)), DateTime(2026, 10, 13, 20, 30));
    expect(nextHalfHour(DateTime(2026, 10, 13, 23, 45)), DateTime(2026, 10, 14));
    expect(defaultMeetingLength, const Duration(minutes: 30));
  });

  group('EWS: обновление и серии', () {
    test('обновление только изменившимся участникам', () {
      final xml = EwsXmlBuilder.buildUpdateCalendarItem('id1', 'ck', _ev, sendTo: 'SendToChangedAndSaveCopy');
      expect(xml, contains('SendMeetingInvitationsOrCancellations="SendToChangedAndSaveCopy"'));
      expect(EwsXmlBuilder.buildUpdateCalendarItem('id1', 'ck', _ev), contains('"SendToAllAndSaveCopy"'));
    });

    test('удаление всей серии по вхождению', () {
      final xml = EwsXmlBuilder.buildDeleteItem('occ1', calendar: true, seriesOf: true);
      expect(xml, contains('<t:RecurringMasterItemId OccurrenceId="occ1"/>'));
      expect(xml, isNot(contains('<t:ItemId')));
      expect(EwsXmlBuilder.buildDeleteItem('occ1', calendar: true), contains('<t:ItemId Id="occ1"/>'));
    });

    test('главный элемент серии', () {
      final xml = EwsXmlBuilder.buildGetRecurringMaster('occ1');
      expect(xml, contains('RecurringMasterItemId OccurrenceId="occ1"'));
      expect(xml, contains('calendar:CalendarItemType'));
    });
  });
}

final _ev = CalendarEventModel(
  id: 'id1',
  accountId: 'a',
  title: 'Планёрка',
  startTime: DateTime(2026, 10, 14, 10),
  endTime: DateTime(2026, 10, 14, 11),
  createdAt: DateTime(2026, 10, 13),
);

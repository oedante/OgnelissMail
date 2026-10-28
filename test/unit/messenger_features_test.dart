// 1.6.49: отложенная отправка (быстрые варианты), занятость нескольких
// участников и переговорных, каталог EWS (фото, переговорные, архив),
// закреплённые письма, запланированные письма, папки общего ящика.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/send_later_presets.dart';
import 'package:ogneliss/features/contacts/contact_prefs.dart' show isVipEmail;
import 'package:ogneliss/services/mail/focus_mode_service.dart' show FocusModeState;
import 'package:ogneliss/data/models/free_busy_view.dart';
import 'package:ogneliss/features/mail/providers/pinned_mail.dart';
import 'package:ogneliss/features/mail/widgets/scheduled_sends.dart';
import 'package:ogneliss/services/mail/ews/ews_directory_extras.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:xml/xml.dart';

void main() {
  group('Отправить позже: быстрые варианты', () {
    test('вторник 10:02 — через час, вечером, завтра в 9; без понедельника', () {
      final now = DateTime(2026, 10, 20, 10, 2); // вторник
      final p = SendLaterPresets.of(now);
      expect(p.map((x) => x.key), ['inHour', 'evening', 'tomorrow']);
      expect(p[0].at, DateTime(2026, 10, 20, 11, 5));
      expect(p[1].at, DateTime(2026, 10, 20, 18));
      expect(p[2].at, DateTime(2026, 10, 21, 9));
    });

    test('вечер пятницы — без «сегодня вечером», с понедельником', () {
      final now = DateTime(2026, 10, 23, 17, 0); // пятница
      final p = SendLaterPresets.of(now);
      expect(p.map((x) => x.key), ['inHour', 'tomorrow', 'monday']);
      expect(p.last.at, DateTime(2026, 10, 26, 9));
    });

    test('воскресенье — понедельник завтра же', () {
      final p = SendLaterPresets.of(DateTime(2026, 10, 25, 20, 0));
      expect(p.last.key, 'monday');
      expect(p.last.at, DateTime(2026, 10, 26, 9));
    });

    test('ровно 10:00 — через час ровно 11:00', () {
      expect(SendLaterPresets.of(DateTime(2026, 10, 20, 10, 0)).first.at, DateTime(2026, 10, 20, 11, 0));
    });
  });

  group('Занятость', () {
    test('строки нескольких людей — самый занятый статус в интервале', () {
      expect(FreeBusyView.mergeStrings(['0002', '0200', '1000']), '1202');
      expect(FreeBusyView.mergeStrings(['44', '0']), '04');
      expect(FreeBusyView.mergeStrings(const []), '');
    });

    test('статус на отрезке: занят, свободен, нет данных', () {
      final start = DateTime(2026, 10, 20, 9);
      // 9:00 0, 9:30 0, 10:00 2, 10:30 0
      const s = '0020';
      expect(FreeBusyView.statusFor(s, start, 30, DateTime(2026, 10, 20, 9), DateTime(2026, 10, 20, 10)), 0);
      expect(FreeBusyView.statusFor(s, start, 30, DateTime(2026, 10, 20, 9, 30), DateTime(2026, 10, 20, 10, 30)), 2);
      expect(FreeBusyView.statusFor('44', start, 30, start, DateTime(2026, 10, 20, 10)), isNull);
    });
  });

  group('Каталог EWS', () {
    test('фото: данные base64, ошибка — нет фото', () {
      final jpeg = base64.encode(List<int>.generate(200, (i) => i % 256));
      final ok = XmlDocument.parse('<Envelope><Body><GetUserPhotoResponse ResponseClass="Success">'
          '<ResponseCode>NoError</ResponseCode><HasChanged>true</HasChanged>'
          '<PictureData>$jpeg</PictureData></GetUserPhotoResponse></Body></Envelope>');
      expect(EwsDirectoryExtras.parseUserPhoto(ok)!.length, 200);
      final err = XmlDocument.parse('<Envelope><Body><GetUserPhotoResponse ResponseClass="Error">'
          '<ResponseCode>ErrorItemNotFound</ResponseCode></GetUserPhotoResponse></Body></Envelope>');
      expect(EwsDirectoryExtras.parseUserPhoto(err), isNull);
    });

    test('списки переговорных и переговорные — по имени, без повторов', () {
      final lists = XmlDocument.parse('<m:GetRoomListsResponse xmlns:m="m" xmlns:t="t"><m:RoomLists>'
          '<t:Address><t:Name>Этаж 5</t:Name><t:EmailAddress>floor5@corp.ru</t:EmailAddress></t:Address>'
          '<t:Address><t:Name>Здание А</t:Name><t:EmailAddress>a@corp.ru</t:EmailAddress></t:Address>'
          '</m:RoomLists></m:GetRoomListsResponse>');
      expect(EwsDirectoryExtras.parseRoomLists(lists).map((r) => r.name), ['Здание А', 'Этаж 5']);
      final rooms = XmlDocument.parse('<m:GetRoomsResponse xmlns:m="m" xmlns:t="t"><m:Rooms>'
          '<t:Room><t:Id><t:Name>Переговорная 512</t:Name><t:EmailAddress>r512@corp.ru</t:EmailAddress></t:Id></t:Room>'
          '<t:Room><t:Id><t:Name>Переговорная 512</t:Name><t:EmailAddress>R512@corp.ru</t:EmailAddress></t:Id></t:Room>'
          '<t:Room><t:Id><t:Name>Большая</t:Name><t:EmailAddress>big@corp.ru</t:EmailAddress></t:Id></t:Room>'
          '</m:Rooms></m:GetRoomsResponse>');
      expect(EwsDirectoryExtras.parseRooms(rooms).map((r) => r.email), ['big@corp.ru', 'r512@corp.ru']);
    });

    test('стандартная папка: есть / нет доступа', () {
      final ok = XmlDocument.parse('<r><m:GetFolderResponseMessage xmlns:m="m" xmlns:t="t" ResponseClass="Success">'
          '<m:Folders><t:Folder><t:FolderId Id="AAA="/></t:Folder></m:Folders></m:GetFolderResponseMessage></r>');
      expect(EwsDirectoryExtras.parseFolderId(ok), 'AAA=');
      final denied = XmlDocument.parse('<r><m:GetFolderResponseMessage xmlns:m="m" ResponseClass="Error">'
          '<m:ResponseCode>ErrorAccessDenied</m:ResponseCode></m:GetFolderResponseMessage></r>');
      expect(EwsDirectoryExtras.parseFolderId(denied), isNull);
      expect(EwsDirectoryExtras.buildGetDistinguishedFolder('calendar', mailbox: 'boss@corp.ru'),
          contains('<t:DistinguishedFolderId Id="calendar"><t:Mailbox><t:EmailAddress>boss@corp.ru'));
    });

    test('папка общего ящика с настоящим Id — FolderId, а не DistinguishedFolderId', () {
      final real = EwsXmlBuilder.buildFindItemDelegated(delegateEmail: 'boss@corp.ru', folderId: 'AAMkADc=');
      expect(real, contains('<t:FolderId Id="AAMkADc="/>'));
      expect(real, isNot(contains('DistinguishedFolderId Id="AAMkADc="')));
      final inbox = EwsXmlBuilder.buildFindItemDelegated(delegateEmail: 'boss@corp.ru', folderId: 'inbox');
      expect(inbox, contains('<t:DistinguishedFolderId Id="inbox"><t:Mailbox>'));
    });

    test('корень архива — archivemsgfolderroot', () {
      expect(EwsXmlBuilder.buildFindFolder(root: 'archivemsgfolderroot'),
          contains('<t:DistinguishedFolderId Id="archivemsgfolderroot"/>'));
    });
  });

  group('Закреплённые письма', () {
    const inboxPin = PinRef(accountId: 'a', emailId: '1', folderId: 'inbox-a', inbox: true);
    const otherPin = PinRef(accountId: 'a', emailId: '2', folderId: 'projects');

    test('в папке — только её письма; в общей ленте — только из «Входящих»', () {
      expect(inboxPin.shownIn(folderId: 'inbox-a', accountId: 'a', accountIds: {'a'}), isTrue);
      expect(otherPin.shownIn(folderId: 'inbox-a', accountId: 'a', accountIds: {'a'}), isFalse);
      expect(otherPin.shownIn(folderId: 'projects', accountId: 'a', accountIds: {'a'}), isTrue);
      expect(inboxPin.shownIn(accountIds: {'a', 'b'}), isTrue);
      expect(otherPin.shownIn(accountIds: {'a', 'b'}), isFalse);
      expect(inboxPin.shownIn(accountIds: {'b'}), isFalse);
    });

    test('запись и чтение', () {
      final back = PinRef.fromJson(jsonEncode(inboxPin.toJson()))!;
      expect(back.key, 'a|1');
      expect(back.inbox, isTrue);
      expect(PinRef.fromJson('{bad'), isNull);
    });
  });

  test('запланированное письмо из очереди: время, тема, «Кому» с +N', () {
    final s = ScheduledSend.fromPayload(
        7,
        'acc',
        jsonEncode({
          'scheduledAt': '2026-10-21T09:00:00.000',
          'subject': ' Отчёт ',
          'to': [
            {'email': 'ivanov@corp.ru', 'displayName': 'Иванов'},
            {'email': 'petrov@corp.ru'},
          ],
        }))!;
    expect(s.queueId, 7);
    expect(s.subject, 'Отчёт');
    expect(s.who, 'Иванов +1');
    expect(s.at, DateTime(2026, 10, 21, 9));
    expect(ScheduledSend.fromPayload(1, 'acc', '{"subject":"x"}'), isNull);
  });

  test('VIP по адресу — без учёта регистра и пробелов', () {
    const st = FocusModeState(vipEmails: ['Boss@Corp.ru ']);
    expect(isVipEmail(st, 'boss@corp.ru'), isTrue);
    expect(isVipEmail(st, ' BOSS@corp.RU'), isTrue);
    expect(isVipEmail(st, 'other@corp.ru'), isFalse);
    expect(isVipEmail(st, ''), isFalse);
  });
}

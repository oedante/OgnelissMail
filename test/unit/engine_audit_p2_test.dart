// Аудит движка, P2: события на весь день, пояс EAS, Retry-After, отмена
// встречи при удалении в EWS.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';

void main() {
  test('весь день: полночь UTC+5 (19:00Z накануне) — это следующий день', () {
    final d = MailEngineService.allDayDate(DateTime.utc(2026, 10, 4, 19));
    expect([d.year, d.month, d.day], [2026, 10, 5]);
    expect([d.hour, d.minute], [0, 0]);
  });

  test('весь день: полночь UTC−8 (08:00Z) — тот же день', () {
    final d = MailEngineService.allDayDate(DateTime.utc(2026, 10, 5, 8));
    expect([d.year, d.month, d.day], [2026, 10, 5]);
  });

  test('TimeZone EAS: 172 байта, Bias = −смещение устройства', () {
    final at = DateTime(2026, 10, 5, 12);
    final bytes = base64.decode(MailEngineService.easTimeZone(at));
    expect(bytes.length, 172);
    final bias = ByteData.sublistView(Uint8List.fromList(bytes)).getInt32(0, Endian.little);
    expect(bias, -at.timeZoneOffset.inMinutes);
  });

  test('Retry-After: секунды и запасное значение', () {
    expect(me.EasEngine.retryAfter({'retry-after': '120'}), const Duration(seconds: 120));
    expect(me.EasEngine.retryAfter({}, fallback: const Duration(minutes: 2)),
        const Duration(minutes: 2));
    expect(me.EasEngine.retryAfter({'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'}), isNull);
  });

  test('EWS: удаление встречи рассылает отмену', () {
    final xml = EwsXmlBuilder.buildDeleteItem('AA=', calendar: true);
    expect(xml, contains('SendMeetingCancellations="SendToAllAndSaveCopy"'));
    expect(EwsXmlBuilder.buildDeleteItem('AA='), isNot(contains('SendMeetingCancellations')));
  });

  test('EWS: контакт — Surname последним, телефон из phoneWork', () {
    final xml = EwsXmlBuilder.buildCreateContact(const _C());
    expect(xml.indexOf('<t:GivenName>') < xml.indexOf('<t:CompanyName>'), isTrue);
    expect(xml.indexOf('<t:JobTitle>') < xml.indexOf('<t:Surname>'), isTrue);
    expect(xml, contains('BusinessPhone'));
  });

  test('EWS: письмо общего ящика — с отправителем From', () {
    final xml = EwsXmlBuilder.buildCreateAndSendItem(
        to: const [], subject: 's', bodyContent: 'b', sharedMailbox: 'sklad@corp.ru');
    expect(xml, contains('<t:From><t:Mailbox><t:EmailAddress>sklad@corp.ru'));
  });

  test('EWS: поиск без папки — по основным папкам, не по корню', () {
    final xml = EwsXmlBuilder.buildSearchItems(query: 'отчёт');
    expect(xml, isNot(contains('msgfolderroot')));
    expect(xml, contains('Id="inbox"'));
    expect(xml, contains('Id="sentitems"'));
  });

  test('EWS: автоответ без дат — Enabled, с датами — Scheduled', () {
    expect(EwsXmlBuilder.buildSetOofSettings(email: 'a@b.ru', enabled: true), contains('>Enabled<'));
    expect(
        EwsXmlBuilder.buildSetOofSettings(
            email: 'a@b.ru', enabled: true, startTime: DateTime(2026), endTime: DateTime(2026, 2)),
        contains('>Scheduled<'));
  });

  test('EWS: задача — Subject, Body, Importance, DueDate, Status по схеме', () {
    final xml = EwsXmlBuilder.buildCreateTask(
        title: 'Отчёт', body: 'текст', importance: 'High', dueDate: DateTime.utc(2026, 10, 9));
    final order = ['<t:Subject>', '<t:Body', '<t:Importance>', '<t:DueDate>', '<t:Status>']
        .map(xml.indexOf)
        .toList();
    for (var i = 1; i < order.length; i++) {
      expect(order[i] > order[i - 1], isTrue);
    }
  });

  test('EWS: поиск по списку папок', () {
    final xml = EwsXmlBuilder.buildSearchItems(query: 'x', folderIds: ['AAA', 'BBB']);
    expect(xml, contains('<t:FolderId Id="AAA"/>'));
    expect(xml, contains('<t:FolderId Id="BBB"/>'));
  });
}

class _C {
  const _C();
  String get displayName => 'Петров Иван';
  String get firstName => 'Иван';
  String? get middleName => null;
  String get lastName => 'Петров';
  String get company => 'ООО';
  String get email => 'ivan@corp.ru';
  String get phoneWork => '+7 495 000-00-00';
  String? get phoneMobile => null;
  String? get department => null;
  String get jobTitle => 'Инженер';
  String? get office => null;
}

// Аудит движка, пункты 19–23: EWS-приглашения, порядок ForwardItem,
// разбор имени контакта, id заметок с аккаунтом.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/contact_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/note_model.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';

void main() {
  test('EWS: приглашения и отмены встреч разбираются вместе с письмами', () {
    final doc = EwsXmlParser.parseResponse('''
<s:Envelope xmlns:s="s" xmlns:m="m" xmlns:t="t"><s:Body><m:FindItemResponse>
<m:ResponseMessages><m:FindItemResponseMessage><m:RootFolder><t:Items>
<t:Message><t:ItemId Id="A1"/><t:Subject>Письмо</t:Subject></t:Message>
<t:MeetingRequest><t:ItemId Id="A2"/><t:Subject>Совещание</t:Subject></t:MeetingRequest>
<t:MeetingCancellation><t:ItemId Id="A3"/><t:Subject>Отменено</t:Subject></t:MeetingCancellation>
</t:Items></m:RootFolder></m:FindItemResponseMessage></m:ResponseMessages>
</m:FindItemResponse></s:Body></s:Envelope>''');
    final emails = EwsXmlParser.parseEmails(doc, 'acc', 'inbox');
    expect(emails.map((e) => e.id), ['A1', 'A2', 'A3']);
  });

  test('EWS ForwardItem: NewBodyContent после ReferenceItemId (types.xsd)', () {
    final xml = EwsXmlBuilder.buildForwardItem(
      referenceItemId: 'X',
      to: [const EmailAddress(email: 'a@b.ru')],
      bodyContent: 'текст',
      newSubject: 'FW: тема',
    );
    final iSubj = xml.indexOf('<t:Subject>');
    final iTo = xml.indexOf('<t:ToRecipients>');
    final iRef = xml.indexOf('<t:ReferenceItemId');
    final iBody = xml.indexOf('<t:NewBodyContent');
    expect(iSubj < iTo && iTo < iRef && iRef < iBody, isTrue);
  });

  test('имя контакта: сохраняется прежний порядок «Фамилия Имя»', () {
    final r = splitDisplayName('Петров Иван',
        oldDisplay: 'Иванов Иван', oldFirst: 'Иван', oldLast: 'Иванов');
    expect(r.last, 'Петров');
    expect(r.first, 'Иван');
    final r2 = splitDisplayName('Ivan Petrov', oldDisplay: 'Ivan Ivanov', oldFirst: 'Ivan', oldLast: 'Ivanov');
    expect(r2.first, 'Ivan');
    expect(r2.last, 'Petrov');
  });

  test('id заметки с сервера включает аккаунт', () {
    final a = noteRowId(eas: true, accountId: 'acc1', serverId: '5:1');
    final b = noteRowId(eas: true, accountId: 'acc2', serverId: '5:1');
    expect(a, isNot(b));
    expect(a, 'eas_acc1:5:1');
  });
}

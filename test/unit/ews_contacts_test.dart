// test/unit/ews_contacts_test.dart
// EWS: отчество и руководитель в контактах (FindItem и ResolveNames).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';
import 'package:xml/xml.dart';

void main() {
  test('FindItem: отчество из MiddleName, руководитель и кабинет', () {
    final doc = XmlDocument.parse('''
<m:FindItemResponse xmlns:m="m" xmlns:t="t"><t:Items>
 <t:Contact>
  <t:ItemId Id="AAA"/>
  <t:DisplayName>Никитин Юрий</t:DisplayName>
  <t:GivenName>Юрий</t:GivenName>
  <t:MiddleName>Владимирович</t:MiddleName>
  <t:Surname>Никитин</t:Surname>
  <t:JobTitle>ведущий инженер</t:JobTitle>
  <t:Manager>Иванов Иван Иванович</t:Manager>
  <t:OfficeLocation>каб. 214</t:OfficeLocation>
  <t:EmailAddresses><t:Entry Key="EmailAddress1">yuriy@example.com</t:Entry></t:EmailAddresses>
 </t:Contact>
</t:Items></m:FindItemResponse>''');
    final c = EwsXmlParser.parseContacts(doc, 'a1').single;
    expect(c.middleName, 'Владимирович');
    expect(c.manager, 'Иванов Иван Иванович');
    expect(c.office, 'каб. 214');
    expect(c.fullName, 'Никитин Юрий Владимирович');
  });

  test('FindItem: отчество из CompleteName или «Инициалов» целиком', () {
    final doc = XmlDocument.parse('''
<r xmlns:t="t">
 <t:Contact><t:ItemId Id="1"/><t:DisplayName>А Б</t:DisplayName>
  <t:CompleteName><t:MiddleName>Сергеевна</t:MiddleName></t:CompleteName></t:Contact>
 <t:Contact><t:ItemId Id="2"/><t:DisplayName>В Г</t:DisplayName><t:Initials>Петрович</t:Initials></t:Contact>
 <t:Contact><t:ItemId Id="3"/><t:DisplayName>Д Е</t:DisplayName><t:Initials>Ю.В.</t:Initials></t:Contact>
</r>''');
    final list = EwsXmlParser.parseContacts(doc, 'a1');
    expect(list[0].middleName, 'Сергеевна');
    expect(list[1].middleName, 'Петрович');
    expect(list[2].middleName, isNull);
  });

  test('ResolveNames: руководитель и отдел', () {
    // Как в сервисе: ответ Exchange разбирается с удалением префиксов t:/m:.
    final doc = EwsXmlParser.parseResponse('''
<m:ResolveNamesResponse xmlns:m="m" xmlns:t="t"><m:ResolutionSet>
 <t:Resolution>
  <t:Mailbox><t:Name>Никитин Юрий</t:Name><t:EmailAddress>yuriy@example.com</t:EmailAddress><t:MailboxType>Mailbox</t:MailboxType></t:Mailbox>
  <t:Contact><t:GivenName>Юрий</t:GivenName><t:Surname>Никитин</t:Surname>
   <t:Department>Служба КИП</t:Department><t:Manager>Иванов Иван</t:Manager></t:Contact>
 </t:Resolution>
</m:ResolutionSet></m:ResolveNamesResponse>''');
    final c = EwsXmlParser.parseResolveNames(doc, 'a1').single;
    expect(c.department, 'Служба КИП');
    expect(c.manager, 'Иванов Иван');
  });

  test('patronymicFromInitials', () {
    expect(EwsXmlParser.patronymicFromInitials('Владимирович'), 'Владимирович');
    expect(EwsXmlParser.patronymicFromInitials('В.'), isNull);
    expect(EwsXmlParser.patronymicFromInitials('ЮВ'), isNull);
    expect(EwsXmlParser.patronymicFromInitials(null), isNull);
  });
}

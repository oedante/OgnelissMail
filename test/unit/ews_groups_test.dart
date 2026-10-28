import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';

void main() {
  test('ExpandDL: участники и вложенные группы', () {
    // Как в приложении: ответ EWS разбирается через parseResponse
    // (префиксы t:/m:/s: убираются).
    final doc = EwsXmlParser.parseResponse('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
  xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
 <s:Body><m:ExpandDLResponse><m:ResponseMessages>
  <m:ExpandDLResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode>
   <m:DLExpansion TotalItemsInView="3" IncludesLastItemInRange="true">
    <t:Mailbox><t:Name>Иванов Иван</t:Name><t:EmailAddress>i.ivanov@corp.ru</t:EmailAddress><t:MailboxType>Mailbox</t:MailboxType></t:Mailbox>
    <t:Mailbox><t:Name>Отдел ИТ</t:Name><t:EmailAddress>it@corp.ru</t:EmailAddress><t:MailboxType>PublicDL</t:MailboxType></t:Mailbox>
    <t:Mailbox><t:Name></t:Name><t:EmailAddress>p.petrov@corp.ru</t:EmailAddress><t:MailboxType>Mailbox</t:MailboxType></t:Mailbox>
   </m:DLExpansion>
  </m:ExpandDLResponseMessage>
 </m:ResponseMessages></m:ExpandDLResponse></s:Body></s:Envelope>''');
    final list = EwsXmlParser.parseExpandDl(doc, 'acc');
    expect(list.map((c) => c.email), ['i.ivanov@corp.ru', 'it@corp.ru', 'p.petrov@corp.ru']);
    expect(list[1].isGroup, isTrue);
    expect(list[0].isGroup, isFalse);
    expect(list[2].displayName, 'p.petrov@corp.ru');
  });

  test('ResolveNames: список рассылки помечен как группа', () {
    // Как в приложении: ответ EWS разбирается через parseResponse
    // (префиксы t:/m:/s: убираются).
    final doc = EwsXmlParser.parseResponse('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
  xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
 <s:Body><m:ResolveNamesResponse><m:ResponseMessages>
  <m:ResolveNamesResponseMessage ResponseClass="Success"><m:ResolutionSet>
   <t:Resolution><t:Mailbox><t:Name>Все сотрудники</t:Name><t:EmailAddress>all@corp.ru</t:EmailAddress><t:MailboxType>PublicDL</t:MailboxType></t:Mailbox></t:Resolution>
   <t:Resolution><t:Mailbox><t:Name>Сидоров</t:Name><t:EmailAddress>s@corp.ru</t:EmailAddress><t:MailboxType>Mailbox</t:MailboxType></t:Mailbox></t:Resolution>
  </m:ResolutionSet></m:ResolveNamesResponseMessage>
 </m:ResponseMessages></m:ResolveNamesResponse></s:Body></s:Envelope>''');
    final list = EwsXmlParser.parseResolveNames(doc, 'acc');
    expect(list.firstWhere((c) => c.email == 'all@corp.ru').isGroup, isTrue);
    expect(list.firstWhere((c) => c.email == 's@corp.ru').isGroup, isFalse);
  });
}

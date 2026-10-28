// Exchange (EWS): серверные правила и «Восстановить удалённые» — разбор
// ответов и правило для SetRule (ews_server_tools.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_server_tools.dart';
import 'package:xml/xml.dart';

const _rules = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
<m:GetInboxRulesResponse xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
  xmlns:x="http://schemas.microsoft.com/exchange/services/2006/types" ResponseClass="Success">
  <m:ResponseCode>NoError</m:ResponseCode>
  <m:OutlookRuleBlobExists>true</m:OutlookRuleBlobExists>
  <m:InboxRules>
    <x:Rule>
      <x:RuleId>AQAAAA1</x:RuleId>
      <x:DisplayName>Счета &amp; акты</x:DisplayName>
      <x:Priority>1</x:Priority>
      <x:IsEnabled>true</x:IsEnabled>
      <x:IsNotSupported>false</x:IsNotSupported>
      <x:IsInError>false</x:IsInError>
      <x:Conditions><x:ContainsSubjectStrings><x:String>счёт</x:String></x:ContainsSubjectStrings></x:Conditions>
      <x:Actions><x:MoveToFolder><x:FolderId Id="AAMk" ChangeKey="AQ"/></x:MoveToFolder><x:StopProcessingRules>true</x:StopProcessingRules></x:Actions>
    </x:Rule>
  </m:InboxRules>
</m:GetInboxRulesResponse></s:Body></s:Envelope>''';

void main() {
  test('правило для SetRule: префикс t:, новый IsEnabled, без полей только для чтения', () {
    final rule = XmlDocument.parse(_rules).findAllElements('Rule', namespace: '*').first;
    final xml = EwsServerTools.ruleXmlForSet(rule, false);
    expect(xml, startsWith('<t:Rule><t:RuleId>AQAAAA1</t:RuleId>'));
    expect(xml, contains('<t:IsEnabled>false</t:IsEnabled>'));
    expect(xml, isNot(contains('IsNotSupported')));
    expect(xml, isNot(contains('IsInError')));
    expect(xml, isNot(contains('x:')));
    expect(xml, contains('<t:DisplayName>Счета &amp; акты</t:DisplayName>'));
    expect(xml, contains('<t:FolderId Id="AAMk" ChangeKey="AQ"></t:FolderId>'));
    // Разбирается обратно как XML.
    expect(() => XmlDocument.parse('<r xmlns:t="urn:t">$xml</r>'), returnsNormally);
  });

  test('восстановить удалённые: разбор FindItem', () {
    final doc = XmlDocument.parse('''<s:Envelope xmlns:s="s"><s:Body>
<m:FindItemResponse xmlns:m="m" xmlns:t="t"><m:ResponseMessages><m:FindItemResponseMessage ResponseClass="Success">
<m:RootFolder><t:Items>
  <t:Message><t:ItemId Id="id1" ChangeKey="ck1"/><t:Subject>Отчёт</t:Subject>
    <t:DateTimeReceived>2026-10-09T08:30:00Z</t:DateTimeReceived><t:ItemClass>IPM.Note</t:ItemClass>
    <t:From><t:Mailbox><t:Name>Иванов И.</t:Name><t:EmailAddress>ivanov@x.ru</t:EmailAddress></t:Mailbox></t:From></t:Message>
  <t:CalendarItem><t:ItemId Id="id2" ChangeKey="ck2"/><t:Subject>Встреча</t:Subject><t:ItemClass>IPM.Appointment</t:ItemClass></t:CalendarItem>
</t:Items></m:RootFolder></m:FindItemResponseMessage></m:ResponseMessages></m:FindItemResponse></s:Body></s:Envelope>''');
    final items = EwsServerTools.parseRecoverable(doc);
    expect(items.length, 2);
    expect(items[0].id, 'id1');
    expect(items[0].subject, 'Отчёт');
    expect(items[0].from, 'Иванов И.');
    expect(items[0].received, DateTime.utc(2026, 10, 9, 8, 30).toLocal());
    expect(items[0].isMail, isTrue);
    expect(items[1].isMail, isFalse);
  });
}

// test/unit/ews_parser_test.dart
// Разбор ответов EWS: изменится формат — тихо потеряются письма
// (TECH_DEBT_AUDIT, раздел 3). Префиксы снимаются только в тегах, текст
// письма не меняется; приглашения приходят своими элементами; отметки
// «отвечено/переслано» — по IconIndex; скрытая копия черновика (1.7.2+111).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';

String _envelope(String items) => '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
<s:Body><m:FindItemResponse xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
 xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
<m:ResponseMessages><m:FindItemResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode>
<m:RootFolder TotalItemsInView="2" IncludesLastItemInRange="true"><t:Items>$items</t:Items></m:RootFolder>
</m:FindItemResponseMessage></m:ResponseMessages></m:FindItemResponse></s:Body></s:Envelope>''';

void main() {
  test('письмо и приглашение: поля, адреса, флаг, категории', () {
    final doc = EwsXmlParser.parseResponse(_envelope('''
<t:Message><t:ItemId Id="AAA=" ChangeKey="CK1"/><t:Subject>Отчёт за неделю</t:Subject>
<t:DateTimeReceived>2026-10-13T05:00:00Z</t:DateTimeReceived><t:IsRead>false</t:IsRead>
<t:HasAttachments>true</t:HasAttachments><t:Importance>High</t:Importance>
<t:Categories><t:String>Синяя</t:String></t:Categories>
<t:Flag><t:FlagStatus>Flagged</t:FlagStatus></t:Flag>
<t:From><t:Mailbox><t:Name>Иванов И.</t:Name><t:EmailAddress>i@corp.ru</t:EmailAddress></t:Mailbox></t:From>
<t:ToRecipients><t:Mailbox><t:Name>Олег</t:Name><t:EmailAddress>o@corp.ru</t:EmailAddress></t:Mailbox></t:ToRecipients>
</t:Message>
<t:MeetingRequest><t:ItemId Id="BBB=" ChangeKey="CK2"/><t:Subject>Совещание</t:Subject>
<t:DateTimeReceived>2026-10-13T06:00:00Z</t:DateTimeReceived><t:IsRead>true</t:IsRead></t:MeetingRequest>'''));
    final list = EwsXmlParser.parseEmails(doc, 'acc', 'inbox');
    expect(list, hasLength(2), reason: 'приглашение — тоже письмо');
    final m = list.first;
    expect(m.id, 'AAA=');
    expect(m.subject, 'Отчёт за неделю');
    expect(m.isRead, isFalse);
    expect(m.isFlagged, isTrue);
    expect(m.hasAttachments, isTrue);
    expect(m.categories, ['Синяя']);
    expect(m.from.email, 'i@corp.ru');
    expect(m.to.single.email, 'o@corp.ru');
    expect(m.receivedAt, DateTime.utc(2026, 10, 13, 5));
    expect(list.last.subject, 'Совещание');
  });

  test('текст письма не меняется при снятии префиксов (1.6.18)', () {
    const text = 'Параметры: key:value=1, mode:fast=yes; ссылка http://x/?a=b';
    final doc = EwsXmlParser.parseResponse('''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
<m:GetItemResponse xmlns:m="m" xmlns:t="t"><m:ResponseMessages><m:GetItemResponseMessage ResponseClass="Success">
<m:Items><t:Message><t:ItemId Id="CCC="/><t:Subject>Конфиг</t:Subject>
<t:Body BodyType="Text">$text</t:Body>
<t:IconIndex>MailReplied</t:IconIndex></t:Message></m:Items>
</m:GetItemResponseMessage></m:ResponseMessages></m:GetItemResponse></s:Body></s:Envelope>''');
    final e = EwsXmlParser.parseEmailDetail(doc, 'acc');
    expect(e.bodyPlain, text);
    expect(e.isReplied, isTrue, reason: 'IconIndex приходит именем MailReplied');
    expect(e.isForwarded, isFalse);
  });

  test('HTML-тело с xmlns Outlook остаётся как есть', () {
    const html = '&lt;html xmlns:o="urn:schemas-microsoft-com:office:office"&gt;&lt;p&gt;Текст&lt;o:p&gt;&lt;/o:p&gt;&lt;/p&gt;&lt;/html&gt;';
    final doc = EwsXmlParser.parseResponse('<m:R xmlns:m="m" xmlns:t="t"><t:Message><t:ItemId Id="D"/>'
        '<t:Body BodyType="HTML">$html</t:Body></t:Message></m:R>');
    final e = EwsXmlParser.parseEmailDetail(doc, 'acc');
    expect(e.bodyHtml, contains('xmlns:o="urn:schemas-microsoft-com:office:office"'));
    expect(e.bodyHtml, contains('<o:p>'));
  });

  test('IconIndex «MailForwarded» — переслано', () {
    final doc = EwsXmlParser.parseResponse('<m:R xmlns:m="m" xmlns:t="t"><t:Message><t:ItemId Id="E"/>'
        '<t:IconIndex>MailForwarded</t:IconIndex></t:Message></m:R>');
    final e = EwsXmlParser.parseEmailDetail(doc, 'acc');
    expect(e.isForwarded, isTrue);
    expect(e.isReplied, isFalse);
  });

  test('черновик: скрытая копия читается (1.7.2+111)', () {
    final doc = EwsXmlParser.parseResponse('<m:R xmlns:m="m" xmlns:t="t"><t:Message><t:ItemId Id="G"/>'
        '<t:Subject>Черновик</t:Subject>'
        '<t:ToRecipients><t:Mailbox><t:Name>Олег</t:Name><t:EmailAddress>o@corp.ru</t:EmailAddress></t:Mailbox></t:ToRecipients>'
        '<t:BccRecipients><t:Mailbox><t:Name>Шеф</t:Name><t:EmailAddress>boss@corp.ru</t:EmailAddress></t:Mailbox>'
        '<t:Mailbox><t:EmailAddress>hr@corp.ru</t:EmailAddress></t:Mailbox></t:BccRecipients>'
        '</t:Message></m:R>');
    final e = EwsXmlParser.parseEmailDetail(doc, 'acc');
    expect(e.to.single.email, 'o@corp.ru');
    expect(e.bcc.map((a) => a.email), ['boss@corp.ru', 'hr@corp.ru']);
    expect(e.cc, isEmpty);
  });

  test('элемент без ItemId пропускается, остальные разбираются', () {
    final doc = EwsXmlParser.parseResponse(_envelope(
        '<t:Message><t:Subject>Без id</t:Subject></t:Message><t:Message><t:ItemId Id="F"/><t:Subject>С id</t:Subject></t:Message>'));
    final list = EwsXmlParser.parseEmails(doc, 'acc', 'inbox');
    expect(list.map((e) => e.subject), ['С id']);
  });
}

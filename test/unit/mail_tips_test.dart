// Подсказки Exchange для адресатов (MailTips, 1.6.49).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_mail_tips.dart';
import 'package:xml/xml.dart';

const _response = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <m:GetMailTipsResponse ResponseClass="Success"
        xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
        xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
      <m:ResponseCode>NoError</m:ResponseCode>
      <m:ResponseMessages>
        <m:MailTipsResponseMessageType ResponseClass="Success">
          <m:ResponseCode>NoError</m:ResponseCode>
          <m:MailTips>
            <t:RecipientAddress><t:Name>Белова Светлана</t:Name><t:EmailAddress>S.Belova@corp.ru</t:EmailAddress></t:RecipientAddress>
            <t:OutOfOffice><t:ReplyBody><t:Message>&lt;p&gt;В отпуске до 25.10.&lt;/p&gt;&lt;p&gt;По срочным вопросам&amp;nbsp;— Иванов.&lt;/p&gt;</t:Message></t:ReplyBody></t:OutOfOffice>
            <t:MailboxFull>false</t:MailboxFull>
            <t:TotalMemberCount>1</t:TotalMemberCount>
            <t:ExternalMemberCount>0</t:ExternalMemberCount>
          </m:MailTips>
        </m:MailTipsResponseMessageType>
        <m:MailTipsResponseMessageType ResponseClass="Success">
          <m:ResponseCode>NoError</m:ResponseCode>
          <m:MailTips>
            <t:RecipientAddress><t:Name>Все сотрудники</t:Name><t:EmailAddress>all@corp.ru</t:EmailAddress></t:RecipientAddress>
            <t:OutOfOffice><t:ReplyBody><t:Message/></t:ReplyBody></t:OutOfOffice>
            <t:MailboxFull>false</t:MailboxFull>
            <t:TotalMemberCount>340</t:TotalMemberCount>
            <t:ExternalMemberCount>3</t:ExternalMemberCount>
          </m:MailTips>
        </m:MailTipsResponseMessageType>
        <m:MailTipsResponseMessageType ResponseClass="Success">
          <m:ResponseCode>NoError</m:ResponseCode>
          <m:MailTips>
            <t:RecipientAddress><t:EmailAddress>colleague@corp.ru</t:EmailAddress></t:RecipientAddress>
            <t:MailboxFull>true</t:MailboxFull>
            <t:TotalMemberCount>1</t:TotalMemberCount>
          </m:MailTips>
        </m:MailTipsResponseMessageType>
      </m:ResponseMessages>
    </m:GetMailTipsResponse>
  </s:Body>
</s:Envelope>''';

void main() {
  test('автоответ, большая рассылка, переполненный ящик', () {
    final tips = EwsMailTips.parse(XmlDocument.parse(_response));
    expect(tips.length, 3);
    final oof = tips[0];
    expect(oof.email, 's.belova@corp.ru');
    expect(oof.name, 'Белова Светлана');
    expect(oof.autoReply, 'В отпуске до 25.10. По срочным вопросам — Иванов.');
    expect(oof.notable, isTrue);
    final dl = tips[1];
    expect(dl.autoReply, isNull);
    expect(dl.isBigList, isTrue);
    expect(dl.hasExternal, isTrue);
    final full = tips[2];
    expect(full.mailboxFull, isTrue);
    expect(full.name, '');
  });

  test('обычный адресат без автоответа — не показываем', () {
    const t = MailTip(email: 'a@corp.ru', totalMembers: 1, externalMembers: 0);
    expect(t.notable, isFalse);
  });

  test('запрос: адреса экранируются', () {
    final r = EwsMailTips.buildRequest('me@corp.ru', ['a&b@corp.ru']);
    expect(r, contains('<t:EmailAddress>a&amp;b@corp.ru</t:EmailAddress>'));
    expect(r, contains('OutOfOfficeMessage'));
  });
}

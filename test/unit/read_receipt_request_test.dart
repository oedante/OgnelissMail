// «Запросить уведомление о прочтении» (2.2.0, решение владельца 09.11.2026:
// для всех писем — в настройках, по умолчанию выключено; для одного письма —
// в меню редактора). Запрос — в каждом способе подключения.

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/settings/providers/feature_flags_provider.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  test('по умолчанию — выключено', () {
    expect(const FeatureFlags().readReceipts, isFalse);
  });

  test('SMTP (IMAP): Disposition-Notification-To — на адрес отправителя', () {
    final m = ImapService.buildOutgoingMessage(
      fromName: 'Иван',
      fromEmail: 'ivan@corp.example',
      to: const [EmailAddress(email: 'anna@partner.example')],
      subject: 'Договор',
      bodyHtml: '<p>Посмотрите</p>',
      readReceipt: true,
    );
    expect(m.getHeaderValue('disposition-notification-to'), '<ivan@corp.example>');
    final plain = ImapService.buildOutgoingMessage(
      fromName: 'Иван',
      fromEmail: 'ivan@corp.example',
      to: const [EmailAddress(email: 'anna@partner.example')],
      subject: 'Договор',
      bodyHtml: '<p>Посмотрите</p>',
    );
    expect(plain.getHeaderValue('disposition-notification-to'), isNull);
  });

  test('EWS: IsReadReceiptRequested — после адресатов и до From (порядок схемы)', () {
    for (final xml in [
      EwsXmlBuilder.buildCreateAndSendItem(
          to: const [EmailAddress(email: 'anna@partner.example')],
          subject: 's',
          bodyContent: 'b',
          fromAddress: 'sklad@corp.example',
          readReceipt: true),
      EwsXmlBuilder.buildCreateDraft(
          to: const [EmailAddress(email: 'anna@partner.example')],
          subject: 's',
          bodyContent: 'b',
          fromAddress: 'sklad@corp.example',
          readReceipt: true),
    ]) {
      final at = xml.indexOf('<t:IsReadReceiptRequested>true</t:IsReadReceiptRequested>');
      expect(at, greaterThan(xml.indexOf('</t:ToRecipients>')));
      expect(at, lessThan(xml.indexOf('<t:From>')));
    }
    expect(
        EwsXmlBuilder.buildCreateAndSendItem(to: const [], subject: 's', bodyContent: 'b'),
        isNot(contains('IsReadReceiptRequested')));
  });

  test('ActiveSync: Disposition-Notification-To в MIME письма', () {
    final eng = me.EasEngine();
    const cfg = me.AccountConfig(email: 'ivan@corp.example');
    final mime = eng.debugBuildMime(
        cfg,
        const me.OutgoingMessage(
            to: [me.MailAddress('anna@partner.example')], subject: 'Договор', bodyHtml: '<p>x</p>', requestReadReceipt: true));
    expect(mime, contains('Disposition-Notification-To: <ivan@corp.example>\r\n'));
    final without = eng.debugBuildMime(
        cfg, const me.OutgoingMessage(to: [me.MailAddress('anna@partner.example')], subject: 'Договор', bodyHtml: '<p>x</p>'));
    expect(without, isNot(contains('Disposition-Notification-To')));
  });
}

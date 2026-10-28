// Гриф в MIME (11.10.2026): кодирование метки, заголовки, слияние с сервером.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/own_addresses.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/security/mail_classification.dart';

void main() {
  group('MailLabel', () {
    test('без грифа — прежняя строка Outlook', () {
      expect(const MailLabel(outlook: 'Confidential').encode(), 'Confidential');
      expect(const MailLabel().encode(), 'Normal');
    });

    test('кодирование и разбор', () {
      const l = MailLabel(outlook: 'Confidential', cls: MailClass.dsp, noForward: true, internalOnly: true);
      expect(l.encode(), 'Confidential|dsp|no-forward,internal-only');
      final d = MailLabel.decode(l.encode());
      expect(d.cls, MailClass.dsp);
      expect(d.noForward, isTrue);
      expect(d.internalOnly, isTrue);
      expect(d.outlook, 'Confidential');
    });

    test('заголовки для отправки', () {
      const l = MailLabel(outlook: 'Private', cls: MailClass.personalData, noForward: true);
      expect(l.headers, {'X-Ogneliss-Classification': 'personalData', 'X-Ogneliss-Handling': 'no-forward'});
      expect(const MailLabel(outlook: 'Confidential').headers, isEmpty);
    });

    test('из заголовков полученного письма', () {
      expect(MailLabel.fromHeaders(), isNull);
      expect(MailLabel.fromHeaders(sensitivity: 'Company-Confidential'), 'Confidential');
      expect(MailLabel.fromHeaders(sensitivity: 'Company-Confidential', classification: 'TRADESECRET', handling: 'internal-only'),
          'Confidential|tradeSecret|internal-only');
      expect(MailLabel.fromHeaders(classification: 'unknown'), isNull);
    });

    test('обновление с сервера не стирает гриф из заголовков', () {
      expect(MailLabel.merge('Confidential', 'Confidential|dsp|no-forward'), 'Confidential|dsp|no-forward');
      expect(MailLabel.merge(null, 'Normal|dsp|'), 'Normal|dsp|');
      expect(MailLabel.merge('Private', 'Private'), 'Private');
      expect(MailLabel.merge('Normal|internal||', null), 'Normal|internal||');
    });

    test('только внутри организации — внешние адреса', () {
      expect(MailLabel.domainOf('Ivan@Corp.RU'), 'corp.ru');
      expect(MailLabel.outside(['a@corp.ru', 'b@gmail.com'], {'corp.ru'}), ['b@gmail.com']);
      expect(MailLabel.outside(['b@gmail.com'], {}), isEmpty);
    });
  });

  test('EWS CreateItem: заголовки грифа как InternetHeaders', () {
    final xml = EwsXmlBuilder.labelHeadersXml('Confidential|dsp|no-forward');
    expect(xml, contains('DistinguishedPropertySetId="InternetHeaders"'));
    expect(xml, contains('PropertyName="X-Ogneliss-Classification"'));
    expect(xml, contains('<t:Value>dsp</t:Value>'));
    expect(xml, contains('<t:Value>no-forward</t:Value>'));
    expect(EwsXmlBuilder.labelHeadersXml('Confidential'), isEmpty);
  });

  group('Запрет пересылки в карточке', () {
    final acc = AccountModel(
      id: 'a1',
      type: AccountType.activesync,
      email: 'me@corp.ru',
      displayName: 'me',
      username: 'me',
      createdAt: DateTime(2026),
    );
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      OwnAddresses.load(await SharedPreferences.getInstance());
    });

    test('S/MIME едет четвёртой частью и не мешает грифу', () {
      final l = const MailLabel(outlook: 'Confidential', cls: MailClass.dsp).withSmime(sign: true, encrypt: true);
      expect(l.encode(), 'Confidential|dsp||sign,encrypt');
      final d = MailLabel.decode(l.encode());
      expect(d.smimeSign, isTrue);
      expect(d.smimeEncrypt, isTrue);
      expect(d.cls, MailClass.dsp);
      expect(d.headers.keys, isNot(contains('X-Ogneliss-Smime')));
      // Только подпись, без грифа.
      final s = const MailLabel().withSmime(sign: true, encrypt: false).encode();
      expect(s, 'Normal|||sign');
      expect(MailLabel.decode(s).smime, isTrue);
      expect(MailLabel.decode(s).hasExtras, isFalse);
      expect(MailLabel.decode('Confidential|dsp|no-forward').smime, isFalse);
    });

    test('чужое письмо «не пересылать» — пересылка закрыта', () {
      expect(MailLabel.forwardBlocked('Confidential|dsp|no-forward', 'boss@corp.ru', acc), isTrue);
    });

    test('своё письмо «не пересылать» — можно', () {
      expect(MailLabel.forwardBlocked('Confidential|dsp|no-forward', 'ME@corp.ru', acc), isFalse);
    });

    test('без запрета или только «внутри организации» — можно', () {
      expect(MailLabel.forwardBlocked('Confidential', 'boss@corp.ru', acc), isFalse);
      expect(MailLabel.forwardBlocked('Confidential|dsp|internal-only', 'boss@corp.ru', acc), isFalse);
      expect(MailLabel.forwardBlocked(null, 'boss@corp.ru', acc), isFalse);
    });
  });
}

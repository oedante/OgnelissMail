// Вход по адресу (1.8.0, п. 6): способ входа по домену и по настройкам
// сервера домена.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart' show EncryptionType;
import 'package:ogneliss/services/mail/mail_provider_detect.dart';

void main() {
  group('byDomain — известные домены', () {
    test('Google, Microsoft, Яндекс, Mail.ru, iCloud', () {
      expect(MailProviderDetect.byDomain('ivan@gmail.com')!.kind, MailKind.google);
      expect(MailProviderDetect.byDomain('Ivan@GoogleMail.com ')!.kind, MailKind.google);
      expect(MailProviderDetect.byDomain('a@outlook.com')!.kind, MailKind.microsoft);
      expect(MailProviderDetect.byDomain('a@hotmail.co.uk')!.kind, MailKind.microsoft);
      expect(MailProviderDetect.byDomain('a@live.fr')!.kind, MailKind.microsoft);
      expect(MailProviderDetect.byDomain('a@msn.com')!.kind, MailKind.microsoft);
      expect(MailProviderDetect.byDomain('a@ya.ru')!.kind, MailKind.yandex);
      expect(MailProviderDetect.byDomain('a@yandex.com.tr')!.kind, MailKind.yandex);
      final mailru = MailProviderDetect.byDomain('a@bk.ru')!;
      expect(mailru.kind, MailKind.mailru);
      expect(mailru.appPassword, isTrue);
      expect(MailProviderDetect.byDomain('a@me.com')!.kind, MailKind.icloud);
    });

    test('IMAP-службы из таблицы — с серверами и шифрованием по порту', () {
      final gmx = MailProviderDetect.byDomain('a@gmx.de')!;
      expect(gmx.kind, MailKind.imap);
      expect(gmx.appPassword, isTrue);
      expect(gmx.imap!.imapHost, 'imap.gmx.net');
      expect(gmx.imap!.imapEncryption, EncryptionType.ssl);
      expect(gmx.imap!.smtpHost, 'mail.gmx.net');
      expect(gmx.imap!.smtpPort, 587);
      expect(gmx.imap!.smtpEncryption, EncryptionType.starttls);
      final rambler = MailProviderDetect.byDomain('a@rambler.ru')!;
      expect(rambler.imap!.smtpEncryption, EncryptionType.ssl);
      expect(rambler.appPassword, isFalse);
      final yahoo = MailProviderDetect.byDomain('a@yahoo.fr')!;
      expect(yahoo.kind, MailKind.imap);
      expect(yahoo.appPassword, isTrue);
      expect(yahoo.imap!.imapHost, 'imap.mail.yahoo.com');
    });

    test('неизвестный домен и неверный адрес — null', () {
      expect(MailProviderDetect.byDomain('i.petrov@corp.example'), isNull);
      expect(MailProviderDetect.byDomain('без собаки'), isNull);
      expect(MailProviderDetect.byDomain('a@b'), isNull);
      expect(MailProviderDetect.byDomain('a@-x..ru'), isNull);
      expect(MailProviderDetect.domainOf(' A@Corp.Example '), 'corp.example');
    });
  });

  group('decide — по результатам проверки', () {
    test('Microsoft 365 важнее всего', () {
      final g = MailProviderDetect.decide(domain: 'corp.example', microsoft365: true, autodiscover: true);
      expect(g.kind, MailKind.microsoft);
      expect(g.microsoft365, isTrue);
    });

    test('autoconfig: Google и Яндекс на своём домене — вход через службу', () {
      const google = ImapPreset(
        imapHost: 'imap.gmail.com',
        imapPort: 993,
        imapEncryption: EncryptionType.ssl,
        smtpHost: 'smtp.gmail.com',
        smtpPort: 465,
        smtpEncryption: EncryptionType.ssl,
      );
      expect(MailProviderDetect.decide(domain: 'corp.example', autoconfig: google).kind, MailKind.google);
      const own = ImapPreset(
        imapHost: 'mx.corp.example',
        imapPort: 993,
        imapEncryption: EncryptionType.ssl,
        smtpHost: 'mx.corp.example',
        smtpPort: 587,
        smtpEncryption: EncryptionType.starttls,
      );
      final g = MailProviderDetect.decide(domain: 'corp.example', autoconfig: own, autodiscover: true);
      expect(g.kind, MailKind.imap);
      expect(g.sure, isTrue);
      expect(g.imap!.imapHost, 'mx.corp.example');
    });

    test('autodiscover — Exchange; imap.<домен> — IMAP-догадка; ничего — Exchange-догадка', () {
      final ex = MailProviderDetect.decide(domain: 'corp.example', autodiscover: true, imap: true);
      expect(ex.kind, MailKind.exchange);
      expect(ex.sure, isTrue);
      final imap = MailProviderDetect.decide(domain: 'corp.example', imap: true, smtp: true);
      expect(imap.kind, MailKind.imap);
      expect(imap.sure, isFalse);
      expect(imap.imap!.smtpHost, 'smtp.corp.example');
      final imapMail = MailProviderDetect.decide(domain: 'corp.example', imap: true, mail: true);
      expect(imapMail.imap!.smtpHost, 'mail.corp.example');
      final none = MailProviderDetect.decide(domain: 'corp.example', mail: true);
      expect(none.kind, MailKind.exchange);
      expect(none.sure, isFalse);
    });
  });

  test('parseAutoconfig — серверы, порты, шифрование, %EMAILDOMAIN%', () {
    const xml = '''<?xml version="1.0"?>
<clientConfig version="1.1">
  <emailProvider id="corp.example">
    <incomingServer type="pop3"><hostname>pop.corp.example</hostname><port>995</port></incomingServer>
    <incomingServer type="imap">
      <hostname>imap.%EMAILDOMAIN%</hostname><port>143</port><socketType>STARTTLS</socketType>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>SMTP.corp.example</hostname><port>465</port><socketType>SSL</socketType>
    </outgoingServer>
  </emailProvider>
</clientConfig>''';
    final p = MailProviderDetect.parseAutoconfig(xml, 'corp.example')!;
    expect(p.imapHost, 'imap.corp.example');
    expect(p.imapPort, 143);
    expect(p.imapEncryption, EncryptionType.starttls);
    expect(p.smtpHost, 'smtp.corp.example');
    expect(p.smtpEncryption, EncryptionType.ssl);
    expect(MailProviderDetect.parseAutoconfig('<html>not found</html>', 'corp.example'), isNull);
    expect(MailProviderDetect.parseAutoconfig('не xml', 'corp.example'), isNull);
  });

  group('detect — с подменой сети', () {
    test('известный домен — без сети', () async {
      var calls = 0;
      final g = await MailProviderDetect.detect('a@gmail.com', resolve: (_) async {
        calls++;
        return true;
      }, fetch: (_) async {
        calls++;
        return null;
      });
      expect(g.kind, MailKind.google);
      expect(calls, 0);
    });

    test('autoconfig на сервере домена', () async {
      const xml = '<clientConfig><emailProvider>'
          '<incomingServer type="imap"><hostname>mail.corp.example</hostname><port>993</port><socketType>SSL</socketType></incomingServer>'
          '<outgoingServer type="smtp"><hostname>mail.corp.example</hostname><port>587</port><socketType>STARTTLS</socketType></outgoingServer>'
          '</emailProvider></clientConfig>';
      final g = await MailProviderDetect.detect('a@corp.example',
          resolve: (_) async => false,
          fetch: (u) async => u.host == 'autoconfig.corp.example' ? xml : null);
      expect(g.kind, MailKind.imap);
      expect(g.imap!.smtpPort, 587);
    });

    test('зона отвечает на любые имена — узел Microsoft 365 не в счёт', () async {
      final g = await MailProviderDetect.detect('a@corp.example',
          resolve: (h) async => h.endsWith('.mail.protection.outlook.com') || h == 'autodiscover.corp.example',
          fetch: (_) async => null);
      expect(g.kind, MailKind.exchange);
      expect(g.microsoft365, isFalse);
    });

    test('узел Microsoft 365 домена', () async {
      final g = await MailProviderDetect.detect('a@corp-group.example',
          resolve: (h) async => h == 'corp-group-example.mail.protection.outlook.com',
          fetch: (_) async => null);
      expect(g.kind, MailKind.microsoft);
      expect(g.microsoft365, isTrue);
    });

    test('сеть молчит — Exchange-догадка по таймауту', () async {
      final g = await MailProviderDetect.detect('a@corp.example',
          timeout: const Duration(milliseconds: 50),
          resolve: (_) => Future.delayed(const Duration(seconds: 1), () => true),
          fetch: (_) => Future.delayed(const Duration(seconds: 1), () => null));
      expect(g.kind, MailKind.exchange);
      expect(g.sure, isFalse);
    });
  });
}

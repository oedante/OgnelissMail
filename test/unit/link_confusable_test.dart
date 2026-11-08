// Похожие на чужие домены в ссылках (план 08.11.2026 п. 2) и картинки
// http:// по https:// на Android (п. 5).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/link_opener.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

void main() {
  group('домен ссылки', () {
    test('обычные латинские и кириллические сайты — не подозрительны', () {
      expect(LinkOpener.confusableHost('www.sberbank.ru'), isFalse);
      expect(LinkOpener.confusableHost('xn--80aswg.xn--p1ai'), isFalse, reason: 'сайт.рф');
      expect(LinkOpener.confusableHost('xn--e1afmkfd.xn--p1acf'), isFalse, reason: 'пример.рус');
      expect(LinkOpener.confusableHost('xn--d1acpjx3f.xn--p1ai'), isFalse, reason: 'яндекс.рф');
    });

    test('смесь латиницы и кириллицы, кириллица под латинской зоной — подозрительны', () {
      expect(LinkOpener.confusableHost('xn--paypl-7ve.com'), isTrue, reason: 'paypаl.com с русской «а»');
      expect(LinkOpener.confusableHost('xn--80ak6aa92e.com'), isTrue, reason: 'аррӏе.com русскими буквами');
      expect(LinkOpener.confusableHost('xn--zzzzzzz'), isTrue, reason: 'неверный punycode');
    });

    test('проверка ссылки целиком', () {
      expect(LinkOpener.check('https://xn--paypl-7ve.com/login')?.suspiciousHost, isTrue);
      expect(LinkOpener.check('https://xn--80aswg.xn--p1ai/')?.suspiciousHost, isFalse);
      expect(LinkOpener.check('https://192.168.1.1/')?.suspiciousHost, isTrue);
    });
  });

  test('картинки http:// — по https:// только где это нужно (Android)', () {
    final was = MailHtmlDocument.upgradeHttpImages;
    addTearDown(() => MailHtmlDocument.upgradeHttpImages = was);
    MailHtmlDocument.upgradeHttpImages = true;
    expect(MailHtmlDocument.build('<img src="http://example.com/a.png">', allowRemoteImages: true).html,
        contains('upgrade-insecure-requests'));
    expect(MailHtmlDocument.build('<p>x</p>', allowRemoteImages: false).html,
        isNot(contains('upgrade-insecure-requests')));
    MailHtmlDocument.upgradeHttpImages = false;
    expect(MailHtmlDocument.build('<img src="http://example.com/a.png">', allowRemoteImages: true).html,
        isNot(contains('upgrade-insecure-requests')));
  });
}

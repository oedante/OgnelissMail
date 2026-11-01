// Имя отправителя, похожее на чужой адрес или сайт (1.5.10).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/sender_safety_service.dart';

void main() {
  const f = SenderSafetyService.displayNameSpoof;

  test('служебный ящик: имя — часть адреса до @', () {
    expect(f('1c.base.svc', '1c.base.svc@acmegroup.example'), isNull);
    expect(f('1C.Base.SVC', '1c.base.svc@acmegroup.example'), isNull);
  });

  test('зона, которой нет, — не сайт', () {
    expect(f('1c.base.svc', 'robot@other.ru'), isNull);
    expect(f('Яндекс.Почта', 'noreply@yandex.ru'), isNull);
    expect(f('Иванов И.И.', 'ivanov@company.ru'), isNull);
  });

  test('свой домен и поддомены — не подделка', () {
    expect(f('Ozon.ru', 'noreply@ozon.ru'), isNull);
    expect(f('Mail.ru', 'news@corp.mail.ru'), isNull);
    expect(f('Иванов <ivanov@mail.acmegroup.example>', 'ivanov@acmegroup.example'), isNull);
  });

  test('чужой адрес в имени — признак фишинга', () {
    final r = f('support@sberbank.ru', 'x@evil.example');
    expect(r?.found, 'support@sberbank.ru');
    expect(r?.address, isTrue);
  });

  test('имя-сайт другой организации — предупреждение', () {
    final r = f('PayPal.com', 'service@pp-secure.xyz');
    expect(r?.found, 'paypal.com');
    expect(r?.address, isFalse);
  });

  group('похожий домен (1.10.x)', () {
    const like = SenderSafetyService.lookalikeOf;
    final brands = SenderSafetyService.knownBrandDomains;

    test('подделки под банк, платёжку, почту', () {
      expect(like('paypa1.com', brands), 'paypal.com');
      expect(like('sberbamk.ru', brands), 'sberbank.ru');
      expect(like('sberbank-secure.ru', brands), 'sberbank.ru');
      expect(like('secure-paypal.net', brands), 'paypal.com');
      expect(like('rnicrosoft.com', brands), 'microsoft.com');
      expect(like('gosuslugi-portal.ru', brands), 'gosuslugi.ru');
    });

    test('честные домены и поддомены — не подделка', () {
      expect(like('sberbank.ru', brands), isNull);
      expect(like('online.sberbank.ru', brands), isNull);
      expect(like('news.ozon.ru', brands), isNull);
      expect(like('yandex.by', brands), isNull, reason: 'другая зона того же имени');
      expect(like('google.de', brands), isNull);
      expect(like('acmegroup.example', brands), isNull);
      expect(like('mts-bank.ru', brands), isNull, reason: 'короткое имя бренда — без «добавок»');
      expect(like('vk.ru', brands), isNull);
      expect(like('ymail.com', brands), isNull, reason: 'почта Yahoo, не подделка gmail.com');
      expect(like('email.com', brands), isNull);
      expect(like('inbox.ru', brands), isNull);
      expect(like('gmaii.com', brands), 'gmail.com');
    });

    test('домены контактов', () {
      const contacts = {'romashka-trade.ru', 'acmegroup.example'};
      expect(like('romashka-trabe.ru', contacts), 'romashka-trade.ru');
      expect(like('acmegr0up.example', contacts), 'acmegroup.example');
      expect(like('romashka-trade.ru', contacts), isNull);
    });
  });

  group('ответ на другой адрес (1.10.x)', () {
    const rt = SenderSafetyService.replyToElsewhere;
    test('чужая организация — предупреждение', () {
      expect(rt('director@acmegroup.example', ['director.acme@gmail.com']), 'director.acme@gmail.com');
    });
    test('та же организация, рассылка или без Reply-To — нет', () {
      expect(rt('ivanov@acmegroup.example', ['sales@mail.acmegroup.example']), isNull);
      expect(rt('news@shop.example', ['support@helpdesk.example'], mailingList: true), isNull);
      expect(rt('a@b.example', []), isNull);
      expect(rt('a@b.example', ['a@b.example']), isNull);
    });
  });

  group('имя контакта (1.10.x)', () {
    test('нормализация и годные для сравнения имена', () {
      expect(SenderSafetyService.normalizeName('  «Пётр  Иванов» '), 'петр иванов');
      expect(SenderSafetyService.comparableName('петр иванов'), isTrue);
      expect(SenderSafetyService.comparableName('анна'), isFalse);
      expect(SenderSafetyService.comparableName('бухгалтерия'), isTrue);
      expect(SenderSafetyService.comparableName('x@y.ru'), isFalse);
    });
  });
}

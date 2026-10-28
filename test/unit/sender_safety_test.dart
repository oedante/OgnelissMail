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
}

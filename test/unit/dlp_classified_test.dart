// Пометки о конфиденциальности в DLP (1.6.2): слово целиком. Раньше
// «конфиденциальность» в подписи-оговорке и «ЛДСП» в смете блокировали
// отправку внешним получателям.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/security/dlp_service.dart';

void main() {
  final dlp = DlpService();
  bool blocked(String body) => dlp
      .checkOutgoingEmail(
        senderEmail: 'me@firm.ru',
        recipients: const [EmailAddress(email: 'partner@other.ru')],
        subject: 'Письмо',
        body: body,
      )
      .violations
      .any((v) => v.type == 'classified');

  test('пометка словом — блокировка для внешних', () {
    expect(blocked('Документ ДСП во вложении'), isTrue);
    expect(blocked('КОНФИДЕНЦИАЛЬНО. Не пересылать.'), isTrue);
    expect(blocked('Совершенно секретно'), isTrue);
  });

  test('часть другого слова — не пометка', () {
    expect(blocked('Стоимость ЛДСП 16 мм — в смете'), isFalse);
    expect(blocked('Мы соблюдаем конфиденциальность ваших данных.'), isFalse);
    expect(blocked('Секретность обеспечивается договором'), isFalse);
  });

  test('свои адресаты — без блокировки', () {
    final r = dlp.checkOutgoingEmail(
      senderEmail: 'me@firm.ru',
      recipients: const [EmailAddress(email: 'colleague@firm.ru')],
      subject: 'ДСП',
      body: '',
    );
    expect(r.violations.where((v) => v.type == 'classified'), isEmpty);
  });
}

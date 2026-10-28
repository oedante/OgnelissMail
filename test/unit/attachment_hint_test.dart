// test/unit/attachment_hint_test.dart
// «Вы упомянули вложение, но не прикрепили файл» — фразы на 4 языках и
// цитата исходного письма.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/attachment_hint_service.dart';

bool warn(String body, {bool has = false}) =>
    AttachmentHintService.shouldWarn(bodyText: body, hasAttachments: has);

void main() {
  test('упоминание вложения на 4 языках', () {
    for (final t in [
      'Коллеги, во вложении смета.',
      'Смету прилагаю.',
      'Договор приложил, посмотрите.',
      'Направляю вам счёт на оплату.',
      'Скан прикрепила.',
      'Please find the report attached.',
      'See the attachment for details.',
      'Im Anhang finden Sie das Angebot.',
      'Anbei die Rechnung.',
      'Vous trouverez ci-joint le devis.',
      'Je vous joins le contrat.',
      'Voir la pièce jointe.',
    ]) {
      expect(warn(t), isTrue, reason: t);
    }
  });

  test('без упоминания и с прикреплённым файлом — не предупреждать', () {
    expect(warn('Добрый день! Встреча в 15:00.'), isFalse);
    expect(warn('Приложение обновилось, спасибо.'), isFalse);
    expect(warn('Во вложении смета.', has: true), isFalse);
    expect(warn('Thanks, see you tomorrow.'), isFalse);
  });

  test('упоминание только в цитате — не предупреждать', () {
    expect(warn('Спасибо, получил.\n\n08.10.2026 10:15, Иванов пишет:\n> Во вложении смета'), isFalse);
    expect(warn('Danke!\n\nAm 08.10.2026 um 10:15 schrieb Max Muster:\nIm Anhang das Angebot'), isFalse);
    expect(warn('Merci !\n\nLe 8 oct. 2026 à 10:15, Jean Dupont a écrit :\nCi-joint le devis'), isFalse);
    expect(
        warn('Принято.\n\nОт: Иванов Иван <ivanov@corp.ru>\nОтправлено: 8 октября 2026 г. 10:15\n'
            'Тема: Смета\n\nВо вложении смета.'),
        isFalse);
    expect(warn('OK\n\n-----Original Message-----\nFrom: x\nPlease find attached'), isFalse);
  });
}

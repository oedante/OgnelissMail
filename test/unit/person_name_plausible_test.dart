// Имя из заголовка письма — имя, а не текст рассылки (2.3.2, замечание
// владельца 11.11.2026). Плашка получателя «oedante@gmail.com» показывала
// «Вам перевод 166711 руб. получить тут https://tinyurl.com/…»: мошенники
// пишут сообщение в поле имени и подставляют чужой адрес, а приложение
// брало «самое полное» имя из встреченных в письмах.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/person_names.dart';
import 'package:ogneliss/services/contacts/mail_contacts_service.dart';

void main() {
  test('текст со ссылкой, длинная фраза — не имя', () {
    expect(PersonNames.plausible('Вам перевод 166711 руб. получить тут https://tinyurl.com/2udcuk63Bj1m11'), isFalse);
    expect(PersonNames.plausible('Заберите приз на www.example.com'), isFalse);
    expect(PersonNames.plausible('Скидка example.com/sale'), isFalse);
    expect(PersonNames.plausible('Срочно подтвердите получение перевода на вашу карту сегодня до вечера'), isFalse,
        reason: 'больше семи слов');
    expect(PersonNames.plausible('А' * 70), isFalse, reason: 'длиннее 64 знаков');
    expect(PersonNames.plausible(''), isFalse);
    expect(PersonNames.plausible(null), isFalse);
  });

  test('имена людей и организаций — имена', () {
    expect(PersonNames.plausible('Смирнов Андрей Викторович'), isTrue);
    expect(PersonNames.plausible('Dr. Juan Carlos de la Cruz'), isTrue);
    expect(PersonNames.plausible('ООО «Ромашка», отдел продаж'), isTrue);
    expect(PersonNames.plausible('Google Cloud Security Community'), isTrue);
    expect(PersonNames.plausible('Иван (example.com)'), isTrue, reason: 'домен без пути — не ссылка');
  });

  test('имя для карточки из переписки: не адрес, не битое, похоже на имя', () {
    expect(MailContactsService.usableName('Анна Петрова', email: 'anna@example.com'), isTrue);
    expect(MailContactsService.usableName('anna@example.com', email: 'anna@example.com'), isFalse);
    expect(MailContactsService.usableName('Ермишин Ол� 5г', email: 'o@example.com'), isFalse);
    expect(
        MailContactsService.usableName('Вам перевод 166711 руб. получить тут https://tinyurl.com/x',
            email: 'me@example.com'),
        isFalse);
  });
}

// test/unit/vcard_writer_test.dart
// Создание и правка vCard для CardDAV: правка не теряет поля, которых нет
// в приложении (фото, адрес, второй e-mail, домашний телефон).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/dav/vcard_parser.dart';

const _google = 'BEGIN:VCARD\r\n'
    'VERSION:3.0\r\n'
    'UID:c1\r\n'
    'FN:Иван Петров\r\n'
    'N:Петров;Иван;;;\r\n'
    'item1.EMAIL;TYPE=INTERNET:ivan@example.com\r\n'
    'item1.X-ABLabel:\r\n'
    'EMAIL;TYPE=HOME:ivan.home@example.com\r\n'
    'TEL;TYPE=WORK:+7 343 000-00-00\r\n'
    'TEL;TYPE=HOME:+7 343 111-11-11\r\n'
    'TEL;TYPE=CELL:+7 900 000-00-00\r\n'
    'ADR;TYPE=WORK:;;ул. Ленина\\, 1;Екатеринбург;;;Россия\r\n'
    'PHOTO:https://example.com/p.jpg\r\n'
    'ORG:Огнелисс\r\n'
    'END:VCARD\r\n';

void main() {
  test('Новая карточка разбирается обратно', () {
    final v = VCardWriter.card(
      uid: 'u1',
      displayName: 'Анна Смирнова',
      firstName: 'Анна',
      lastName: 'Смирнова',
      email: 'anna@example.com',
      phoneWork: '+7 343 222-22-22',
      phoneMobile: '+7 901 000-00-00',
      company: 'ООО «Ромашка», филиал',
      jobTitle: 'Юрист',
    );
    final c = VCardParser.parse(v).single;
    expect(c.displayName, 'Анна Смирнова');
    expect(c.family, 'Смирнова');
    expect(c.given, 'Анна');
    expect(c.email, 'anna@example.com');
    expect(c.phoneWork, '+7 343 222-22-22');
    expect(c.phoneMobile, '+7 901 000-00-00');
    expect(c.org, 'ООО «Ромашка», филиал');
    expect(c.title, 'Юрист');
  });

  test('Правка меняет только поля приложения', () {
    final v = VCardWriter.patch(_google,
        displayName: 'Иван Петров-Водкин',
        firstName: 'Иван',
        lastName: 'Петров-Водкин',
        email: 'ivan@new.example.com',
        phoneWork: '+7 343 999-99-99',
        phoneMobile: '+7 900 000-00-00',
        company: 'Огнелисс');
    final c = VCardParser.parse(v).single;
    expect(c.displayName, 'Иван Петров-Водкин');
    expect(c.family, 'Петров-Водкин');
    expect(c.emails, contains('ivan@new.example.com'));
    expect(c.emails, contains('ivan.home@example.com'));
    expect(c.emails.length, 2);
    expect(c.phoneWork, '+7 343 999-99-99');
    expect(c.photo, 'https://example.com/p.jpg');
    expect(v.contains('ADR;TYPE=WORK'), isTrue);
    expect(v.contains('TEL;TYPE=HOME:+7 343 111-11-11'), isTrue);
    expect(v.contains('UID:c1'), isTrue);
    expect('FN:'.allMatches(v).length, 1);
  });

  test('Длинные строки переносятся', () {
    final v = VCardWriter.patch(
        _google.replaceFirst('PHOTO:https://example.com/p.jpg', 'PHOTO;ENCODING=b;TYPE=JPEG:${'A' * 400}'),
        displayName: 'Иван Петров');
    for (final line in v.split('\r\n')) {
      expect(line.length <= 75, isTrue);
    }
    expect(VCardParser.parse(v).single.photo, 'data:image/jpeg;base64,${'A' * 400}');
  });
}

// test/unit/my_contact_test.dart
// Карточка для QR «Мой контакт»: vCard 3.0, ФИО с отчеством, экранирование.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/contact_model.dart';
import 'package:ogneliss/features/contacts/my_contact.dart';

void main() {
  test('vCard: ФИО, организация с отделом, телефоны, почта; пустые поля не пишутся', () {
    const c = ContactModel(
      id: 'me',
      email: 'ivanov@corp.ru',
      displayName: 'Иванов Иван',
      lastName: 'Иванов',
      firstName: 'Иван',
      middleName: 'Петрович',
      company: 'ООО «Огонёк»',
      department: 'Отдел ИТ; группа 2',
      phoneMobile: '+7 900 000-00-00',
    );
    final v = vcardOf(c);
    expect(v, startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n'));
    expect(v, contains('N:Иванов;Иван;Петрович;;'));
    expect(v, contains('FN:Иванов Иван Петрович'));
    expect(v, contains(r'ORG:ООО «Огонёк»;Отдел ИТ\; группа 2'));
    expect(v, contains('TEL;TYPE=CELL:+7 900 000-00-00'));
    expect(v, contains('EMAIL;TYPE=INTERNET:ivanov@corp.ru'));
    expect(v, isNot(contains('TITLE:')));
    expect(v, isNot(contains('TYPE=WORK')));
    expect(v, endsWith('END:VCARD\r\n'));
  });
}

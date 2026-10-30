// Адреса, набранные или вставленные в поле «Кому» (1.8.13).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/address_input.dart';

void main() {
  List<String> emails(String s) => [for (final a in AddressInput.parse(s).addresses) a.email];

  test('несколько адресов через запятую, точку с запятой, пробел и перевод строки', () {
    expect(emails('a@x.ru, b@x.ru; c@x.ru d@x.ru\ne@x.ru'), ['a@x.ru', 'b@x.ru', 'c@x.ru', 'd@x.ru', 'e@x.ru']);
  });

  test('«Имя <адрес>» из Outlook — адрес без скобок, имя отдельно', () {
    final r = AddressInput.parse('Иванов Иван <ivan@corp.ru>; "Петров, Пётр" <petr@corp.ru>');
    expect([for (final a in r.addresses) a.email], ['ivan@corp.ru', 'petr@corp.ru']);
    expect([for (final a in r.addresses) a.displayName], ['Иванов Иван', 'Петров, Пётр']);
    expect(r.rest, '');
  });

  test('mailto, параметры ссылки и точка в конце предложения', () {
    expect(emails('mailto:ivan@corp.ru?subject=Привет'), ['ivan@corp.ru']);
    expect(emails('Пишите на ivan@corp.ru.').single, 'ivan@corp.ru');
  });

  test('повтор в другом регистре — один адресат', () {
    expect(emails('IVAN@corp.ru, ivan@corp.ru'), ['IVAN@corp.ru']);
  });

  test('неверный адрес остаётся для исправления', () {
    final r = AddressInput.parse('ivan@, petr@corp.ru, @corp.ru');
    expect([for (final a in r.addresses) a.email], ['petr@corp.ru']);
    expect(r.rest, contains('ivan@'));
    expect(r.rest, contains('@corp.ru'));
    expect(AddressInput.isValid('ivan@corp.ru.'), isFalse);
    expect(AddressInput.isValid('иван@почта.рф'), isTrue);
  });
}

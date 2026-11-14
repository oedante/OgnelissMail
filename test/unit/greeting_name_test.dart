// test/unit/greeting_name_test.dart
// Обращение в письме поручения (замечание владельца 14.11.2026): было
// «Ситников, добрый день!» — одна фамилия; нужно «Имя Отчество» или «Имя».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/greeting_name.dart';

void main() {
  String? ru(String? n) => GreetingName.of(n, locale: 'ru');

  test('русские ФИО: имя и отчество, в любом порядке', () {
    expect(ru('Ситников Дмитрий'), 'Дмитрий');
    expect(ru('Дмитрий Ситников'), 'Дмитрий');
    expect(ru('Ситников Дмитрий Александрович'), 'Дмитрий Александрович');
    expect(ru('Дмитрий Александрович Ситников'), 'Дмитрий Александрович');
    expect(ru('Ситников, Дмитрий'), 'Дмитрий', reason: 'Exchange: «Фамилия, Имя»');
    expect(ru('Ситников, Дмитрий Александрович'), 'Дмитрий Александрович');
    expect(ru('Пашкевич Анна Сергеевна'), 'Анна Сергеевна', reason: 'фамилия тоже на «-вич»');
    expect(ru('Анна Сергеевна Пашкевич'), 'Анна Сергеевна');
    expect(ru('Мамедов Эльдар Рашидович'), 'Эльдар Рашидович');
    expect(ru('СИТНИКОВ ДМИТРИЙ'), 'Дмитрий');
  });

  test('два слова: имя по списку и по окончанию фамилии', () {
    expect(ru('Хабибуллина Зульфия'), 'Зульфия');
    expect(ru('Ковалёва Марина'), 'Марина');
    expect(ru('Ким Ирина'), 'Ирина', reason: 'Ким — фамилия');
    expect(ru('Ли Виктор'), 'Виктор');
    expect(ru('Гогия Нино'), 'Нино');
    expect(ru('Абвгд Ежзик'), 'Абвгд Ежзик', reason: 'не ясно, где имя, — полное имя, а не фамилия');
  });

  test('одно слово, адрес, организация', () {
    expect(ru('Дмитрий'), 'Дмитрий');
    expect(ru(''), isNull);
    expect(ru(null), isNull);
    expect(ru('d.sitnikov@corp.ru'), isNull);
    expect(ru('Служба поддержки'), isNull);
    expect(ru('ООО «Ромашка»'), isNull);
  });

  test('латиница: имя первым, транслитерация русских имён', () {
    expect(ru('John Smith'), 'John');
    expect(ru('Smith, John'), 'John');
    expect(ru('Sitnikov Dmitry'), 'Dmitry');
    expect(ru('Dmitriy Sitnikov'), 'Dmitriy');
    expect(ru('Petrov Alexander'), 'Alexander');
    expect(ru('Ivanova Natalia'), 'Natalia');
    expect(ru('Kuznetsov Sergei'), 'Sergei');
    expect(ru('Sitnikov Dmitry Aleksandrovich'), 'Dmitry Aleksandrovich');
  });

  test('другие языки: только имя', () {
    expect(GreetingName.of('Ситников Дмитрий Александрович', locale: 'en'), 'Дмитрий');
    expect(GreetingName.of('Sitnikov Dmitry Aleksandrovich', locale: 'de'), 'Dmitry');
    expect(GreetingName.of('John Michael Smith', locale: 'fr'), 'John');
    expect(GreetingName.of('Ситников, Дмитрий', locale: 'tr'), 'Дмитрий');
  });

  test('порядок «фамилия — имя»: венгерский, вьетнамский', () {
    expect(GreetingName.of('Szabó Péter', locale: 'hu'), 'Péter');
    expect(GreetingName.of('Nguyễn Văn An', locale: 'en'), 'An');
    expect(GreetingName.of('Trần Bình', locale: 'vi'), 'Bình');
  });

  test('японский, корейский, китайский', () {
    expect(GreetingName.of('山田 太郎', locale: 'ja'), '山田', reason: 'фамилия + さん');
    expect(GreetingName.of('山田太郎', locale: 'ja'), '山田太郎');
    expect(GreetingName.of('Dmitry Sitnikov', locale: 'ja'), 'Dmitry');
    expect(GreetingName.of('홍 길동', locale: 'ko'), '홍길동');
    expect(GreetingName.of('王 伟', locale: 'zh'), '王伟');
  });
}

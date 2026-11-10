// Имена в письмах и уведомлениях (1.5.9): «Фамилия И.О.», выбор полного ФИО.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/person_names.dart';

void main() {
  group('Фамилия и инициалы', () {
    test('ФИО с отчеством', () {
      expect(PersonNames.short('Морозов Андрей Николаевич'), 'Морозов А.Н.');
      expect(PersonNames.short('Сафин Руслан Рамилевич'), 'Сафин Р.Р.');
      expect(PersonNames.short('Иванова Мария Петровна'), 'Иванова М.П.');
    });

    test('Exchange «Фамилия, Имя»', () {
      expect(PersonNames.short('Смирнов, Андрей'), 'Смирнов А.');
      expect(PersonNames.short('Smith, John'), 'Smith J.');
    });

    test('иностранное «Имя Фамилия»', () {
      expect(PersonNames.short('John Smith'), 'Smith J.');
    });

    test('где сокращать ненадёжно — как есть', () {
      expect(PersonNames.short('Андрей Смирнов'), 'Андрей Смирнов');
      expect(PersonNames.short('ООО «Ромашка»'), 'ООО Ромашка');
      expect(PersonNames.short('Служба поддержки'), 'Служба поддержки');
      expect(PersonNames.short('Яндекс'), 'Яндекс');
      expect(PersonNames.short(null, email: 'a@b.ru'), 'a@b.ru');
      expect(PersonNames.short('a@b.ru', email: 'a@b.ru'), 'a@b.ru');
    });
  });

  group('Полнее ли имя', () {
    test('«Смирнов, Андрей» → полное ФИО', () {
      expect(PersonNames.better('Смирнов, Андрей', 'Смирнов Андрей Сергеевич'), isTrue);
      expect(PersonNames.better('Смирнов, Андрей', 'Смирнов Андрей'), isTrue);
      expect(PersonNames.better(null, 'Смирнов Андрей Сергеевич'), isTrue);
    });

    test('другой человек или не полнее — нет', () {
      expect(PersonNames.better('Смирнов, Андрей', 'Петров Иван Иванович'), isFalse);
      expect(PersonNames.better('Смирнов Андрей Сергеевич', 'Смирнов Андрей'), isFalse);
      expect(PersonNames.better('Смирнов Андрей', 'Смирнов, Андрей'), isFalse);
    });
  });

  test('монограмма', () {
    expect(PersonNames.monogram('Морозов Андрей Николаевич'), 'МА');
    expect(PersonNames.monogram('Смирнов, Андрей'), 'СА');
    expect(PersonNames.monogram(null, email: 'x@y.ru'), 'X');
  });

  test('ФИО из полей Outlook — в порядке «Фамилия Имя Отчество»', () {
    expect(PersonNames.russianOrder('Геннадьевич Волков Евгений'), 'Волков Евгений Геннадьевич');
    expect(PersonNames.russianOrder('Волков Геннадьевич Евгений'), 'Волков Евгений Геннадьевич');
    expect(PersonNames.russianOrder('Никитин Юрий Александрович'), 'Никитин Юрий Александрович');
    expect(PersonNames.russianOrder('Орлова Кристина Эдуардовна'), 'Орлова Кристина Эдуардовна');
    expect(PersonNames.russianOrder('Аксенов Дмитрий'), 'Аксенов Дмитрий');
    expect(PersonNames.russianOrder('John Smith Jr'), 'John Smith Jr');
  });

  // Уведомления о новом письме (2.2.x, просьба владельца 10.11.2026):
  // полное имя отправителя, без «Фамилия И.О.».
  group('полное имя для уведомлений', () {
    test('ФИО — целиком', () {
      expect(PersonNames.full('Морозов Андрей Николаевич'), 'Морозов Андрей Николаевич');
      expect(PersonNames.full('"Иванова Мария Петровна"'), 'Иванова Мария Петровна');
    });

    test('Exchange «Фамилия, Имя Отчество» — без запятой', () {
      expect(PersonNames.full('Смирнов, Андрей Сергеевич'), 'Смирнов Андрей Сергеевич');
      expect(PersonNames.full('Smith, John'), 'Smith John');
    });

    test('порядок слов — как у отправителя, организации и адрес — как есть', () {
      expect(PersonNames.full('Евгений Геннадьевич Волков'), 'Евгений Геннадьевич Волков');
      expect(PersonNames.full('ООО «Ромашка», отдел продаж'), 'ООО Ромашка, отдел продаж');
      expect(PersonNames.full('', email: 'info@example.com'), 'info@example.com');
      expect(PersonNames.full('John Smith'), 'John Smith');
    });
  });
}

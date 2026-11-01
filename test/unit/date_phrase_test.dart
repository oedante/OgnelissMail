// Общий разбор дат и времени (1.9.x): фраза быстрого ввода и даты в тексте
// письма.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/date_phrase.dart';

void main() {
  // Суббота, 31 октября 2026, 12:00.
  final ref = DateTime(2026, 10, 31, 12, 0);

  DateMention? one(String text, {DateTime? at, bool monthFirst = false}) {
    final all = DatePhrase.find(text, ref: at ?? ref, monthFirst: monthFirst);
    expect(all.length, lessThanOrEqualTo(1), reason: 'в «$text» найдено ${all.length}: $all');
    return all.isEmpty ? null : all.first;
  }

  String shown(String text, DateMention m) => text.substring(m.start, m.end);

  group('фраза: ru', () {
    test('завтра в 15', () {
      final p = DatePhrase.parse('Созвон завтра в 15', now: ref);
      expect(p.day, DateTime(2026, 11, 1));
      expect(p.hour, 15);
      expect(p.rest, 'Созвон');
    });
    test('в пятницу в 10 на час', () {
      final p = DatePhrase.parse('Созвон с Анной в пятницу в 10 на час', now: ref);
      expect(p.day, DateTime(2026, 11, 6));
      expect(p.hour, 10);
      expect(p.durationMinutes, 60);
      expect(p.rest, 'Созвон с Анной');
    });
    test('с 15 до 16, 15:00–16:30', () {
      final a = DatePhrase.parse('Встреча с 15 до 16', now: ref);
      expect((a.hour, a.endHour), (15, 16));
      final b = DatePhrase.parse('Обед 13:00-14:30', now: ref);
      expect((b.hour, b.minute, b.endHour, b.endMinute), (13, 0, 14, 30));
      expect(b.rest, 'Обед');
    });
    test('на 30 минут, на полчаса, на полтора часа', () {
      expect(DatePhrase.parse('звонок в 9 на 30 минут', now: ref).durationMinutes, 30);
      expect(DatePhrase.parse('звонок в 9 на полчаса', now: ref).durationMinutes, 30);
      expect(DatePhrase.parse('звонок в 9 на полтора часа', now: ref).durationMinutes, 90);
      expect(DatePhrase.parse('звонок в 9 на 1,5 часа', now: ref).durationMinutes, 90);
    });
    test('3 ноября, 31.10.2027, 2026-12-01', () {
      expect(DatePhrase.parse('отчёт 3 ноября', now: ref).day, DateTime(2026, 11, 3));
      expect(DatePhrase.parse('отчёт 31.10.2027', now: ref).day, DateTime(2027, 10, 31));
      expect(DatePhrase.parse('отчёт 2026-12-01', now: ref).day, DateTime(2026, 12, 1));
    });
    test('дата без года в прошлом — следующий год', () {
      expect(DatePhrase.parse('отчёт 15.03', now: ref).day, DateTime(2027, 3, 15));
      expect(DatePhrase.parse('отчёт 31.10', now: ref).day, DateTime(2026, 10, 31));
    });
    test('в следующий понедельник, через 3 дня', () {
      expect(DatePhrase.parse('в следующий понедельник', now: ref).day, DateTime(2026, 11, 2));
      expect(DatePhrase.parse('через 3 дня', now: ref).day, DateTime(2026, 11, 3));
      expect(DatePhrase.parse('через неделю', now: ref).day, DateTime(2026, 11, 7));
    });
    test('«с 1 по 5 ноября» — не часы', () {
      final p = DatePhrase.parse('отпуск с 1 по 5 ноября', now: ref);
      expect(p.hour, isNull);
      expect(p.day, DateTime(2026, 11, 5));
    });
    test('«в 5 раз», «купить 2 хлеба» — не время', () {
      expect(DatePhrase.parse('вырос в 5 раз', now: ref).hour, isNull);
      expect(DatePhrase.parse('купить 2 хлеба', now: ref).found, isFalse);
    });
    test('голый час помечен', () {
      expect(DatePhrase.parse('созвон в 3', now: ref).loneHour, isTrue);
      expect(DatePhrase.parse('созвон в 3 дня', now: ref).loneHour, isFalse);
    });
  });

  group('фраза: en и другие языки', () {
    test('next Monday at 3pm', () {
      final p = DatePhrase.parse('Review next Monday at 3pm', now: ref);
      expect(p.day, DateTime(2026, 11, 2));
      expect(p.hour, 15);
      expect(p.rest, 'Review');
    });
    test('on Nov 3 from 2 to 3pm', () {
      final p = DatePhrase.parse('Demo on Nov 3 from 2 to 3pm', now: ref);
      expect(p.day, DateTime(2026, 11, 3));
      expect((p.hour, p.endHour), (14, 15));
    });
    test('for 1 hour, for 30 minutes, for an hour', () {
      expect(DatePhrase.parse('call at 10am for 1 hour', now: ref).durationMinutes, 60);
      expect(DatePhrase.parse('call at 10am for 30 minutes', now: ref).durationMinutes, 30);
      expect(DatePhrase.parse('call at 10am for an hour', now: ref).durationMinutes, 60);
    });
    test('October 31st, 2027 / 3 de noviembre / 3. November / 3 novembre', () {
      expect(DatePhrase.parse('October 31st, 2027', now: ref).day, DateTime(2027, 10, 31));
      expect(DatePhrase.parse('3 de noviembre de 2026', now: ref).day, DateTime(2026, 11, 3));
      expect(DatePhrase.parse('am 3. November', now: ref).day, DateTime(2026, 11, 3));
      expect(DatePhrase.parse('le 3 novembre', now: ref).day, DateTime(2026, 11, 3));
    });
    test('10/31 — по стране: день/месяц или месяц/день', () {
      expect(DatePhrase.parse('due 11/12', now: ref).day, DateTime(2026, 12, 11));
      expect(DatePhrase.parse('due 11/12', now: ref, monthFirst: true).day, DateTime(2026, 11, 12));
      // Невозможное в выбранном порядке — меняется местами.
      expect(DatePhrase.parse('due 10/31', now: ref).day, DateTime(2026, 10, 31));
    });
    test('15 Uhr, 15h30', () {
      expect(DatePhrase.parse('Treffen um 15 Uhr', now: ref).hour, 15);
      final f = DatePhrase.parse('réunion 15h30', now: ref);
      expect((f.hour, f.minute), (15, 30));
    });
  });

  group('опорная дата', () {
    test('переход года: завтра 31 декабря', () {
      final p = DatePhrase.parse('завтра в 10', now: DateTime(2026, 12, 31, 9));
      expect(p.day, DateTime(2027, 1, 1));
    });
    test('письмо 28.12 про 05.01 — январь следующего года', () {
      final m = one('Встреча 05.01 в 10:00', at: DateTime(2026, 12, 28, 9))!;
      expect(m.from, DateTime(2027, 1, 5, 10));
    });
    test('письмо 05.01 про 28.12 — декабрь прошлого года', () {
      final m = one('Отчёт за 28.12 в 10:00', at: DateTime(2027, 1, 5, 9))!;
      expect(m.from, DateTime(2026, 12, 28, 10));
    });
    test('летнее время: завтра в 15 — 15:00 по часам, а не 14 или 16', () {
      // 25.10.2026 и 29.03.2026 — переход времени в Европе; при любом
      // часовом поясе устройства «завтра» — следующий день по календарю.
      for (final d in [DateTime(2026, 10, 24, 20), DateTime(2026, 3, 28, 20)]) {
        final m = one('Созвон завтра в 15:00', at: d)!;
        expect((m.from.day, m.from.hour, m.from.minute), (d.day + 1, 15, 0));
        final p = DatePhrase.parse('завтра в 15', now: d);
        expect((p.day!.day, p.day!.hour), (d.day + 1, 0));
      }
    });
  });

  group('текст письма: находит', () {
    test('завтра в 15 — от даты письма', () {
      const t = 'Давайте созвонимся завтра в 15, если удобно.';
      final m = one(t)!;
      expect(shown(t, m), 'завтра в 15');
      expect(m.from, DateTime(2026, 11, 1, 15));
    });
    test('в пятницу в 10', () {
      final m = one('Предлагаю в пятницу в 10')!;
      expect(m.from, DateTime(2026, 11, 6, 10));
    });
    test('31 октября 2026 г. в 15:00 — одно упоминание', () {
      const t = 'Начало 3 ноября 2026 г. в 15:00 по Москве';
      final m = one(t)!;
      expect(shown(t, m), '3 ноября 2026 г. в 15:00');
      expect(m.from, DateTime(2026, 11, 3, 15));
    });
    test('Friday, October 30, 2026 3:15 PM', () {
      const t = 'Sent: Friday, October 30, 2026 3:15 PM';
      final m = one(t)!;
      expect(shown(t, m), 'Friday, October 30, 2026 3:15 PM');
      expect(m.from, DateTime(2026, 10, 30, 15, 15));
    });
    test('on Nov 3 from 2 to 3pm — промежуток', () {
      final m = one('Can we meet on Nov 3 from 2 to 3pm?')!;
      expect(m.from, DateTime(2026, 11, 3, 14));
      expect(m.to, DateTime(2026, 11, 3, 15));
    });
    test('15:00–16:30 и на час', () {
      final a = one('Слот 15:00–16:30')!;
      expect(a.to, DateTime(2026, 10, 31, 16, 30));
      final b = one('Созвон 3.11 в 10:00 на час')!;
      expect((b.from, b.to), (DateTime(2026, 11, 3, 10), DateTime(2026, 11, 3, 11)));
    });
    test('дата словом без времени — весь день', () {
      final m = one('Дедлайн 15 ноября')!;
      expect(m.allDay, isTrue);
      expect(m.from, DateTime(2026, 11, 15));
    });
    test('дата числом без года — со словом «до»', () {
      final m = one('Оплатить до 15.11, пожалуйста')!;
      expect(m.from, DateTime(2026, 11, 15));
    });
    test('31.10.2026 и 2026-11-03', () {
      expect(one('Акт от 31.10.2026')!.from, DateTime(2026, 10, 31));
      expect(one('Release 2026-11-03')!.from, DateTime(2026, 11, 3));
    });
    test('10/31 at 3 pm в США', () {
      final m = one('Party 11/12 at 3 pm', monthFirst: true)!;
      expect(m.from, DateTime(2026, 11, 12, 15));
    });
    test('несколько упоминаний', () {
      final all = DatePhrase.find('Вебинар 5 ноября в 11:00, повтор 12 ноября в 18:00.', ref: ref);
      expect(all.map((m) => m.from), [DateTime(2026, 11, 5, 11), DateTime(2026, 11, 12, 18)]);
    });
  });

  group('текст письма: не даты', () {
    for (final t in [
      'Купите 15 штук',
      'Версия 1.9.0 уже в магазине',
      'Версия 1.10 и 2.5',
      'Цена 12.10 руб, скидка 15.00 €',
      'Цена \$12.10',
      'Телефон +7 (912) 345-67-89, 8-800-555-35-35',
      'Заказ №2026-10-31-1234 оформлен',
      'Заказ 20261031',
      'IP 192.168.10.10',
      'Счёт 2:1, рост в 5 раз',
      'Сегодня скидка 50%',
      'Только завтра!',
      'в 15 км от города',
      'с 15 до 16 лет',
      'Работаем 24/7',
      'Размер 1.5 ГБ',
      'Займёт 2 часа',
      'Видео 01:23:45',
    ]) {
      test(t, () => expect(DatePhrase.find(t, ref: ref), isEmpty));
    }
  });

  test('скорость: длинная рассылка', () {
    final block = StringBuffer();
    for (var i = 0; i < 500; i++) {
      block.write(
        'Скидка ${i % 90}% на товары до ${(i % 28) + 1}.11, цена ${i * 13}.99 руб. '
        'Заказ №${100000 + i}, тел. +7 (900) 123-45-${(i % 90) + 10}. Версия 1.$i.0. '
        'Вебинар ${(i % 28) + 1} ноября в 1${i % 10}:00, а также завтра в 15. '
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor. ',
      );
    }
    final text = block.toString(); // около 115 тысяч знаков
    expect(text.length, greaterThan(100000));
    DatePhrase.find(text, ref: ref); // прогрев
    final sw = Stopwatch()..start();
    final found = DatePhrase.find(text, ref: ref);
    sw.stop();
    expect(found.length, greaterThan(400));
    // Бюджет с запасом на медленную машину CI: на телефоне — заметно быстрее.
    expect(sw.elapsedMilliseconds, lessThan(400), reason: '${sw.elapsedMilliseconds} мс');
    // ignore: avoid_print
    print('Даты в рассылке ${text.length} знаков: ${sw.elapsedMilliseconds} мс');
  });
}

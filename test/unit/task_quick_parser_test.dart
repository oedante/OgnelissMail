// Быстрое добавление напоминания одной строкой (раздел «Напоминания»).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/task_model.dart';
import 'package:ogneliss/features/tasks/task_quick_parser.dart';

void main() {
  // Среда, 7 октября 2026, 10:00.
  final now = DateTime(2026, 10, 7, 10, 0);

  test('завтра в 15:00 и «!» — срок, напоминание, важная', () {
    final p = TaskQuickParser.parse('Позвонить Иванову завтра в 15:00 !', now: now);
    expect(p.title, 'Позвонить Иванову');
    expect(p.due, DateTime(2026, 10, 8, 15, 0));
    expect(p.reminder, DateTime(2026, 10, 8, 15, 0));
    expect(p.important, isTrue);
  });

  test('через 2 часа — напоминание без срока', () {
    final p = TaskQuickParser.parse('Отправить отчёт через 2 часа', now: now);
    expect(p.title, 'Отправить отчёт');
    expect(p.reminder, DateTime(2026, 10, 7, 12, 0));
    expect(p.due, isNull);
  });

  test('в пятницу — ближайшая пятница, только дата', () {
    final p = TaskQuickParser.parse('Встреча с подрядчиком в пятницу', now: now);
    expect(p.title, 'Встреча с подрядчиком');
    expect(p.due, DateTime(2026, 10, 9));
    expect(p.reminder, isNull);
  });

  test('в среду в среду — через неделю', () {
    final p = TaskQuickParser.parse('Планёрка в среду', now: now);
    expect(p.due, DateTime(2026, 10, 14));
  });

  test('каждый день в 9 — повтор, 9 уже прошло — завтра', () {
    final p = TaskQuickParser.parse('Проверить почту каждый день в 9', now: now);
    expect(p.title, 'Проверить почту');
    expect(p.repeat, TaskRepeat.daily);
    expect(p.due, DateTime(2026, 10, 8, 9, 0));
  });

  test('дата числом и «напомни мне»', () {
    final p = TaskQuickParser.parse('Напомни мне оплатить счёт 12.10', now: now);
    expect(p.title, 'оплатить счёт');
    expect(p.due, DateTime(2026, 10, 12));
  });

  test('английский: tomorrow at 3pm', () {
    final p = TaskQuickParser.parse('Call John tomorrow at 3pm', now: now);
    expect(p.title, 'Call John');
    expect(p.due, DateTime(2026, 10, 8, 15, 0));
  });

  test('без распознанных слов — название целиком', () {
    final p = TaskQuickParser.parse('Купить картриджи', now: now);
    expect(p.title, 'Купить картриджи');
    expect(p.hasExtras, isFalse);
  });

  group('время словами и с уточнением', () {
    test('«в 10 утра» вырезается целиком', () {
      final p = TaskQuickParser.parse('в 10 утра позвонить Смирнову Андрею', now: now);
      expect(p.title, 'позвонить Смирнову Андрею');
      expect(p.due, DateTime(2026, 10, 8, 10, 0)); // 10:00 уже наступило — завтра
    });
    test('«пол десятого», «в половине десятого» — 9:30', () {
      expect(TaskQuickParser.parse('завтра пол десятого планёрка', now: now).due, DateTime(2026, 10, 8, 9, 30));
      expect(TaskQuickParser.parse('завтра в половине десятого созвон', now: now).title, 'созвон');
    });
    test('«в 9:30» и «в 9.30» — время, а не дата', () {
      expect(TaskQuickParser.parse('завтра в 9:30 созвон', now: now).due, DateTime(2026, 10, 8, 9, 30));
      final p = TaskQuickParser.parse('завтра в 9.30 созвон', now: now);
      expect(p.due, DateTime(2026, 10, 8, 9, 30));
      expect(p.title, 'созвон');
    });
    test('«в 3 дня», «в десять вечера», «без четверти десять»', () {
      expect(TaskQuickParser.parse('встреча в 3 дня', now: now).due, DateTime(2026, 10, 7, 15, 0));
      expect(TaskQuickParser.parse('отчёт в десять вечера', now: now).due, DateTime(2026, 10, 7, 22, 0));
      expect(TaskQuickParser.parse('завтра без четверти десять', now: now).due, DateTime(2026, 10, 8, 9, 45));
    });
    test('«вечером в 8» — 20:00; голое число — не время', () {
      expect(TaskQuickParser.parse('сегодня вечером в 8 позвонить', now: now).due, DateTime(2026, 10, 7, 20, 0));
      final p = TaskQuickParser.parse('купить 2 хлеба', now: now);
      expect(p.title, 'купить 2 хлеба');
      expect(p.due, isNull);
    });
    test('срок из темы письма: «до 17:00 10.10.2026»', () {
      final p = TaskQuickParser.parse('Мастер-треккер (обновить до 17:00 10.10.2026)', now: now);
      expect(p.due, DateTime(2026, 10, 10, 17, 0));
    });
  });

  group('повтор задачи', () {
    test('ежемесячно с 31-го — последний день короткого месяца', () {
      expect(TaskRepeat.next(DateTime(2026, 1, 31, 9), TaskRepeat.monthly), DateTime(2026, 2, 28, 9));
    });
    test('по будням: пятница → понедельник', () {
      expect(TaskRepeat.next(DateTime(2026, 10, 9, 18), TaskRepeat.weekdays), DateTime(2026, 10, 12, 18));
    });
    test('еженедельно', () {
      expect(TaskRepeat.next(DateTime(2026, 10, 7), TaskRepeat.weekly), DateTime(2026, 10, 14));
    });
  });
}

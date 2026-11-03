// Раскладка уведомления о письме (NotificationText).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ogneliss/services/notifications/notification_text.dart';

void main() {
  group('preview: без цитаты и подписи', () {
    test('ответ Outlook: «Согласовано» без подписи и «From: … Sent: …»', () {
      expect(
        NotificationText.preview('Согласовано.\r\n\r\nС уважением,\r\nЗахаров Олег.\r\n'
            'From: Ермишин Олег Андреевич Sent: Saturday, October 10, 2026 4:42 PM To: …'),
        'Согласовано.',
      );
    });

    test('обычное письмо — целиком, пробелы сжаты', () {
      expect(NotificationText.preview('Коллеги,  добрый день!\n\nВы заявлены на рейс.'),
          'Коллеги, добрый день! Вы заявлены на рейс.');
    });

    test('английская и немецкая цитаты', () {
      expect(NotificationText.preview('Ok, agreed. On Mon, 5 Oct 2026 John wrote: > text'), 'Ok, agreed.');
      expect(NotificationText.preview('Passt. -----Ursprüngliche Nachricht----- Von: X'), 'Passt.');
    });

    test('письмо из одной подписи — не пустое', () {
      expect(NotificationText.preview('С уважением, Олег'), 'С уважением, Олег');
    });

    test('длинный текст обрезается многоточием', () {
      final p = NotificationText.preview('а' * 500, max: 100);
      expect(p.length, 101);
      expect(p.endsWith('…'), isTrue);
    });

    test('пусто и null', () {
      expect(NotificationText.preview(null), '');
      expect(NotificationText.preview('  \n '), '');
    });
  });

  test('заголовок (жирный) — отправитель; общий ящик; VIP без звёздочки', () {
    expect(NotificationText.title('  Захаров О. '), 'Захаров О.');
    expect(NotificationText.title('Захаров О.', shared: true), '👥 Захаров О.');
    // VIP (1.10.5) — не в заголовке: портрет и цвет, без портрета — шапка.
    expect(NotificationText.subText(mailbox: 'i.petrov', vip: true), 'VIP · i.petrov');
  });

  test('тема — строкой под отправителем; без темы — подпись', () {
    expect(NotificationText.subject('  RE: Смена\n рейса ', noSubject: '(Без темы)'), 'RE: Смена рейса');
    expect(NotificationText.subject(' ', noSubject: '(Без темы)'), '(Без темы)');
  });

  test('раскрытое: тема, ниже текст', () {
    expect(NotificationText.big('Смена рейса', 'Согласовано.'), 'Смена рейса\nСогласовано.');
    expect(NotificationText.big('Смена рейса', ''), 'Смена рейса');
  });

  test('короткая подпись ящика: имя до @, при совпадении — домен', () {
    expect(NotificationText.shortMailbox('i.petrov@acmegroup.example', ['i.petrov@acmegroup.example', 'me@gmail.com']),
        'i.petrov');
    expect(NotificationText.shortMailbox('i.petrov@acmegroup.example', ['i.petrov@acmegroup.example', 'i.petrov@gmail.com']),
        'acmegroup.example');
  });

  test('шапка: папка и ящик; ничего — null', () {
    expect(NotificationText.subText(folder: 'Мобилизация', mailbox: 'i.petrov'), '📁 Мобилизация · i.petrov');
    expect(NotificationText.subText(), isNull);
  });

  test('строка сводки — обычным шрифтом: отправитель и тема', () {
    expect(NotificationText.summaryLine(' Иван & Co ', 'A < B '), 'Иван & Co — A < B');
  });

  // 1.10.3: строк текста в уведомлении — отдельно для рабочих и личных ящиков.
  group('строк текста (NotificationLines)', () {
    test('по умолчанию 5; чужое значение — тоже 5', () async {
      SharedPreferences.setMockInitialValues({NotificationLines.prefWork: 12, NotificationLines.prefPersonal: 7});
      final p = await SharedPreferences.getInstance();
      expect(NotificationLines.of(p, work: true), 12);
      expect(NotificationLines.of(p, work: false), NotificationLines.byDefault);
      expect(NotificationLines.of(null, work: true), NotificationLines.byDefault);
    });

    test('длина текста растёт с числом строк; текст письма — для 8 и 12', () {
      final long = List.filled(80, 'слово').join(' ');
      final three = NotificationText.preview(long, max: NotificationLines.maxChars(3));
      final twelve = NotificationText.preview(long, max: NotificationLines.maxChars(12));
      expect(three.length, lessThanOrEqualTo(NotificationLines.maxChars(3) + 1));
      expect(twelve.length, greaterThan(three.length * 3));
      expect(NotificationLines.wantsBody(5), isFalse);
      expect(NotificationLines.wantsBody(8), isTrue);
    });
  });
}

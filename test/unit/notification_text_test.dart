// Раскладка уведомления о письме (NotificationText).
import 'package:flutter_test/flutter_test.dart';
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

  test('заголовок: тема, без темы, VIP и общий ящик', () {
    expect(NotificationText.title('  RE: Смена рейса ', noSubject: '(Без темы)'), 'RE: Смена рейса');
    expect(NotificationText.title('', noSubject: '(Без темы)'), '(Без темы)');
    expect(NotificationText.title('Отчёт', noSubject: '-', vip: true, shared: true), '👥 ★ Отчёт');
  });

  test('строки: свёрнутая и раскрытая', () {
    expect(NotificationText.line('Захаров Олег', 'Согласовано.'), 'Захаров Олег — Согласовано.');
    expect(NotificationText.line('Захаров Олег', ''), 'Захаров Олег');
    expect(NotificationText.big('Олег', 'Текст'), 'Олег\nТекст');
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

  test('строка сводки: «Отправитель — тема», без жирного и HTML', () {
    expect(NotificationText.summaryLine('A < B', 'Иван & Co'), 'Иван & Co — A < B');
  });
}

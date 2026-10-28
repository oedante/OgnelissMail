// test/unit/unsubscribe_test.dart
// Отписка от рассылок: разбор List-Unsubscribe / List-Unsubscribe-Post /
// List-Id и проверка отправителя для отписки «в одно нажатие».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/unsubscribe_service.dart';

void main() {
  group('ListUnsubscribe.fromHeaders', () {
    test('https и mailto, one-click', () {
      final r = ListUnsubscribe.fromHeaders(
        '<mailto:unsub@news.shop.ru?subject=stop>, <https://news.shop.ru/u?id=42>',
        post: 'List-Unsubscribe=One-Click',
        listId: 'Новости магазина <news.shop.ru>',
      )!;
      expect(r.web.single.host, 'news.shop.ru');
      expect(r.mail.single.path, 'unsub@news.shop.ru');
      expect(r.mail.single.queryParameters['subject'], 'stop');
      expect(r.oneClick, isTrue);
      expect(r.listName, 'Новости магазина');
    });

    test('без List-Unsubscribe-Post — не one-click', () {
      final r = ListUnsubscribe.fromHeaders('<https://x.example/u>')!;
      expect(r.oneClick, isFalse);
    });

    test('http (без шифрования) не учитывается', () {
      expect(ListUnsubscribe.fromHeaders('<http://x.example/u>'), isNull);
      final r = ListUnsubscribe.fromHeaders('<http://x.example/u>, <mailto:a@x.example>',
          post: 'List-Unsubscribe=One-Click')!;
      expect(r.web, isEmpty);
      expect(r.oneClick, isFalse);
    });

    test('перенос строки внутри заголовка', () {
      final r = ListUnsubscribe.fromHeaders('<https://x.example/u?a=1&\r\n b=2>')!;
      expect(r.web.single.queryParameters['b'], '2');
    });

    test('пусто и мусор — null', () {
      expect(ListUnsubscribe.fromHeaders(null), isNull);
      expect(ListUnsubscribe.fromHeaders('  '), isNull);
      expect(ListUnsubscribe.fromHeaders('no brackets here'), isNull);
    });

    test('List-Id без описания — идентификатор', () {
      final r = ListUnsubscribe.fromHeaders('<mailto:a@x.example>', listId: '<list.x.example>')!;
      expect(r.listName, 'list.x.example');
    });
  });

  group('encode/parse', () {
    test('круговой путь через базу', () {
      final json = encodeListUnsubscribe(
        unsubscribe: '<https://x.example/u>',
        post: 'List-Unsubscribe=One-Click',
        listId: 'X <x.example>',
      );
      final r = ListUnsubscribe.parse(json)!;
      expect(r.oneClick, isTrue);
      expect(r.listName, 'X');
    });

    test('нет заголовка — null', () {
      expect(encodeListUnsubscribe(unsubscribe: null), isNull);
      expect(encodeListUnsubscribe(unsubscribe: ' '), isNull);
      expect(ListUnsubscribe.parse(null), isNull);
      expect(ListUnsubscribe.parse('{broken'), isNull);
    });
  });

  group('senderAuthenticated', () {
    test('dkim/dmarc pass', () {
      expect(senderAuthenticated('mx.google.com; dkim=pass header.i=@shop.ru; spf=pass; dmarc=pass'), isTrue);
      expect(senderAuthenticated('mx; dmarc=pass (p=REJECT)'), isTrue);
    });

    test('провал или нет данных — нет', () {
      expect(senderAuthenticated(null), isFalse);
      expect(senderAuthenticated(''), isFalse);
      expect(senderAuthenticated('mx; spf=pass'), isFalse);
      expect(senderAuthenticated('mx; dkim=pass; dmarc=fail'), isFalse);
      expect(senderAuthenticated('mx; dkim=pass; spf=fail'), isFalse);
    });
  });
}

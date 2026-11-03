// Язык письма для перевода — по свежему тексту, без цитаты (1.10.1).
//
// Замечание владельца 02.11.2026: «Перевод вызывает ошибку, если писем в
// переписке несколько». Определитель языка получал ответ вместе с цитатой
// на другом языке, не был уверен («und») — и перевод падал с «Не удалось
// перевести».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/widgets/mail_translation.dart';

final _cyr = RegExp('[А-Яа-яЁё]');

EmailModel _mail({String? plain, String? html}) => EmailModel(
      id: 'm1',
      accountId: 'a1',
      folderId: 'INBOX',
      from: const EmailAddress(email: 'ivan@example.org'),
      to: const [EmailAddress(email: 'me@example.org')],
      subject: 'Re: hub',
      receivedAt: DateTime(2026, 10, 31, 3, 33),
      bodyPlain: plain,
      bodyHtml: html,
    );

const _reply = 'Hi Oedante,\n\nCongrats! Your contributor page is up. Thank you! '
    'Your work helps us make the world better and more predictable.\n\nIvan';

void main() {
  group('простой текст: ответ без цитаты', () {
    test('Gmail: «On … wrote:» и строки с «>»', () {
      const plain = '$_reply\n\nOn Fri, Oct 31, 2026 at 3:33 AM Олег <me@example.org> wrote:\n'
          '> Привет, Иван! Спасибо за письмо, посмотрю страницу на этой неделе.\n'
          '> Олег';
      final r = replyPartOfPlain(plain);
      expect(r, startsWith('Hi Oedante'));
      expect(r, contains('Ivan'));
      expect(_cyr.hasMatch(r), isFalse, reason: r);
    });

    test('русский Outlook: «От: … Отправлено: …»', () {
      const plain = 'Коллеги, файл во вложении.\n\nОт: Иванов И.И. <ii@example.org>\n'
          'Отправлено: 31 октября 2026 г. 10:00\nКому: me@example.org\nТема: Отчёт\n\nPlease see the report.';
      expect(replyPartOfPlain(plain), 'Коллеги, файл во вложении.');
    });

    test('«… пишет:» и «-----Original Message-----»', () {
      expect(replyPartOfPlain('Thanks!\n\n31.10.2026, 10:00, Иван пишет:\n> Добрый день'), 'Thanks!');
      expect(replyPartOfPlain('See below.\n-----Original Message-----\nFrom: x'), 'See below.');
    });

    test('без цитаты — текст как есть; только цитата — тоже как есть', () {
      expect(replyPartOfPlain(_reply), _reply);
      const onlyQuote = '> Привет\n> Как дела?';
      expect(replyPartOfPlain(onlyQuote), onlyQuote);
    });
  });

  group('образец для определения языка', () {
    test('простой текст: цитата на другом языке в образец не попадает', () async {
      final s = await MailTranslationController.debugSample(_mail(
        plain: '$_reply\n\nOn Fri, Oct 31, 2026 at 3:33 AM Олег wrote:\n'
            '${List.filled(30, '> Привет, Иван! Это длинная цитата на русском языке.').join('\n')}',
      ));
      expect(s, startsWith('Hi Oedante'));
      expect(_cyr.hasMatch(s), isFalse, reason: s);
    });

    test('HTML Gmail: блок gmail_quote не попадает в образец', () async {
      final quote = List.filled(30, '<p>Привет, Иван! Это длинная цитата на русском языке.</p>').join();
      final s = await MailTranslationController.debugSample(_mail(
        html: '<html><body><div dir="ltr"><p>Hi Oedante,</p><p>Congrats! Your contributor page is up. '
            'Thank you! Your work helps us make the world better.</p><p>Ivan</p></div>'
            '<div class="gmail_quote"><div class="gmail_attr">On Fri, Oct 31, 2026 Олег wrote:</div>'
            '<blockquote class="gmail_quote">$quote</blockquote></div></body></html>',
      ));
      expect(s, contains('Congrats'));
      expect(_cyr.hasMatch(s), isFalse, reason: s);
    });

    test('письмо без цитаты — образец прежний (пробелы и переводы строк — одним пробелом, 1.10.5)', () async {
      final s = await MailTranslationController.debugSample(_mail(plain: _reply));
      expect(s, _reply.replaceAll(RegExp(r'\s+'), ' '));
    });
  });

  // 1.10.5 (журнал владельца 03.11.2026: «Письма из нескольких писем по
  // прежнему не переводит», язык ответа со ссылками не определялся).
  test('образец без ссылок и адресов; Gmail «On … wrote:» на двух строках — начало цитаты', () async {
    const plain = 'Hi Oedante,\r\n\r\nCongrats! Your page is up: https://hub.example.org/contributors/oedante\r\n\r\n'
        'Thank you! Your work helps us make the world better.\r\n\r\nIvan\r\nhttps://github.com/example/x\r\n\r\n'
        'On Thu, 29 Oct 2026 at 21:55, Олег Ермишин\r\n<oedante@example.com> wrote:\r\n'
        '> Hi Ivan,\r\n> От: Ivan N <founders@example.org>\r\n> Отправлено: четверг, 29 октября 2026 г. 21:50\r\n';
    final s = await MailTranslationController.debugSample(_mail(plain: plain));
    expect(s, startsWith('Hi Oedante, Congrats!'));
    expect(s, isNot(contains('http')));
    expect(s, isNot(contains('@')));
    expect(_cyr.hasMatch(s), isFalse, reason: 'имя из «On … wrote:» на двух строках — уже цитата');
    expect(MailTranslationController.latinShare(s), greaterThan(0.95));
    expect(MailTranslationController.latinShare('Привет, как дела'), 0);
  });
}

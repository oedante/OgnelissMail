// Цитата и свежий текст (план 08.11.2026, п. 5): цитата не сворачивается,
// если под ней ответ (Gmail, Thunderbird, Apple Mail при ответе снизу); в
// письме без HTML сворачиваются строки «>» и длинная подпись «-- ».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';

void main() {
  group('HTML', () {
    test('ответ сверху, цитата Gmail снизу — сворачивается', () {
      final s = splitQuotedHtml('<div>Да, согласен, давайте в четверг.</div>'
          '<div class="gmail_quote"><div class="gmail_attr">On Thu, Nov 5, 2026 Ivan wrote:</div>'
          '<blockquote>Встречаемся в среду?</blockquote></div>');
      expect(s.hasQuote, isTrue);
      expect(s.reply, contains('давайте в четверг'));
      expect(s.reply, isNot(contains('в среду')));
    });

    test('ответ под цитатой Gmail — письмо целиком', () {
      final s = splitQuotedHtml('<div>Коллеги,</div>'
          '<div class="gmail_quote"><div class="gmail_attr">On Thu, Nov 5, 2026 Ivan wrote:</div>'
          '<blockquote>Встречаемся в среду?</blockquote></div>'
          '<div>Нет, в среду не получится — предлагаю четверг, 11:00, переговорная 3.</div>');
      expect(s.hasQuote, isFalse);
    });

    test('Apple Mail: «… wrote:», цитата, ответы вперемежку — письмо целиком', () {
      final s = splitQuotedHtml('<div>Отвечаю по пунктам.</div>'
          '<div>On 5 Nov 2026, at 10:00, Ivan wrote:</div>'
          '<blockquote type="cite">1. Сроки?</blockquote>'
          '<div>Сроки — до пятницы, без переносов.</div>'
          '<blockquote type="cite">2. Бюджет?</blockquote>'
          '<div>Бюджет утверждён в прежнем размере.</div>');
      expect(s.hasQuote, isFalse);
    });

    test('под цитатой только короткая подпись — сворачивается', () {
      final s = splitQuotedHtml('<div>Принято.</div><blockquote>Отчёт во вложении.</blockquote><div>Иван</div>');
      expect(s.hasQuote, isTrue);
    });

    test('шапка Outlook: после неё старое письмо — сворачивается как раньше', () {
      final s = splitQuotedHtml('<p>Согласовано.</p><div id="divRplyFwdMsg"><p><b>От:</b> Иванов И.И.<br>'
          '<b>Отправлено:</b> 4 ноября 2026 г. 15:40</p></div><p>Прошу согласовать перекрытие автодороги.</p>');
      expect(s.hasQuote, isTrue);
      expect(s.reply, contains('Согласовано'));
    });
  });

  group('простой текст', () {
    test('ответ сверху, цитата «>» снизу — сворачивается', () {
      final s = splitQuotedPlain('Да, в четверг удобно.\n\nOn Thu, Nov 5, 2026 Ivan wrote:\n> Встречаемся в среду?\n');
      expect(s.hasQuote, isTrue);
      expect(s.reply, 'Да, в четверг удобно.');
      expect(s.quoted, contains('> Встречаемся'));
    });

    test('ответ под цитатой «>» — письмо целиком', () {
      final s = splitQuotedPlain('Привет!\n\n> Встречаемся в среду?\nНет, в среду не получится, давай в четверг.\n');
      expect(s.hasQuote, isFalse);
    });

    test('длинная подпись «-- » сворачивается, короткая — нет', () {
      final long = splitQuotedPlain('Текст письма.\n-- \nИван Петров\nОтдел снабжения\nтел. 123\n'
          'моб. 456\nhttps://example.com\nНе печатайте это письмо без необходимости.');
      expect(long.hasQuote, isTrue);
      expect(long.reply, 'Текст письма.');
      final short = splitQuotedPlain('Текст письма.\n-- \nИван Петров\nтел. 123');
      expect(short.hasQuote, isFalse);
    });

    test('подпись и цитата под ней — сворачиваются вместе', () {
      final s = splitQuotedPlain('Принято.\n-- \nИван\n\nOn Thu, Ivan wrote:\n> Отчёт готов?');
      expect(s.hasQuote, isTrue);
      expect(s.reply, 'Принято.');
    });

    test('без цитаты и пересылка целиком — не сворачивается', () {
      expect(splitQuotedPlain('Просто письмо без цитаты.').hasQuote, isFalse);
      expect(splitQuotedPlain('> только цитата\n> и всё').hasQuote, isFalse);
    });
  });
}

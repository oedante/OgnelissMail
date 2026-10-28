// test/unit/quote_splitter_test.dart
// Разбор цитат: ошибка здесь скрывает часть письма (TECH_DEBT_AUDIT, раздел 3).
// Форматы почтовых программ, которые чаще всего приходят в корпоративную и
// личную почту. Русский Outlook (жирное «От:», шапка в таблице), пересылка без
// комментария и «пишет:» в длинном абзаце — в audit_fixes_test.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';

void expectSplit(String html, {required String reply, required String quoted}) {
  final s = splitQuotedHtml(html);
  expect(s.hasQuote, isTrue, reason: 'цитата должна быть найдена');
  expect(s.reply, contains(reply));
  expect(s.reply, isNot(contains(quoted)), reason: 'старый текст не попадает в ответ');
  expect(s.quoted, contains(quoted));
  expect(s.quoted, isNot(contains(reply)), reason: 'ответ не дублируется в цитате');
}

void main() {
  test('Gmail: div.gmail_quote', () {
    expectSplit(
      '<div dir="ltr">Спасибо, получил.</div><br>'
      '<div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Oct 13, 2026 at 10:00 AM Ivan '
      '&lt;i@example.com&gt; wrote:<br></div><blockquote class="gmail_quote">Высылаю отчёт</blockquote></div>',
      reply: 'Спасибо, получил',
      quoted: 'Высылаю отчёт',
    );
  });

  test('Outlook в браузере и новый Outlook: линия и divRplyFwdMsg', () {
    expectSplit(
      '<div>Согласовано.</div><hr style="display:inline-block;width:98%" tabindex="-1">'
      '<div id="divRplyFwdMsg" dir="ltr"><font><b>From:</b> Ivan<br><b>Sent:</b> Monday, October 13, 2026</font></div>'
      '<div>Прошу согласовать график</div>',
      reply: 'Согласовано',
      quoted: 'Прошу согласовать график',
    );
  });

  test('Outlook для Windows: линия, затем «От: … Отправлено:»', () {
    expectSplit(
      '<div class="WordSection1"><p class="MsoNormal">Принято в работу.</p>'
      '<div><div style="border:none;border-top:solid #E1E1E1 1.0pt"><p class="MsoNormal">'
      '<b>От:</b> Петров П.П. &lt;p@corp.ru&gt;<br><b>Отправлено:</b> 13 октября 2026 г. 10:00</p></div></div>'
      '<p class="MsoNormal">Нужен акт до пятницы</p></div>',
      reply: 'Принято в работу',
      quoted: 'Нужен акт до пятницы',
    );
  });

  test('Thunderbird: moz-cite-prefix и blockquote', () {
    expectSplit(
      '<p>Да, подойдёт.</p><div class="moz-cite-prefix">13.10.2026 10:00, Иван пишет:<br></div>'
      '<blockquote type="cite">Встречаемся в 15:00?</blockquote>',
      reply: 'Да, подойдёт',
      quoted: 'Встречаемся в 15:00',
    );
  });

  test('Почта iPhone и Mac: «On … wrote:» перед blockquote', () {
    expectSplit(
      '<div dir="ltr">Хорошо</div><div dir="ltr"><br><blockquote type="cite">On 13 Oct 2026, at 10:00, '
      'Ivan &lt;i@example.com&gt; wrote:<br><br></blockquote></div>'
      '<blockquote type="cite"><div dir="ltr">Перенесём на завтра</div></blockquote>',
      reply: 'Хорошо',
      quoted: 'Перенесём на завтра',
    );
  });

  test('Яндекс и Mail.ru: blockquote после строки с датой', () {
    final s = splitQuotedHtml('<div>Принято</div><div>&nbsp;</div>'
        '<div>13.10.2026, 10:00, "Иван" &lt;i@yandex.ru&gt;:</div><blockquote>Отправь счёт</blockquote>');
    expect(s.hasQuote, isTrue);
    expect(s.reply, contains('Принято'));
    expect(s.reply, isNot(contains('Отправь счёт')));
    expect(s.quoted, contains('Отправь счёт'));
  });

  test('старый Outlook: «-----Original Message-----»', () {
    expectSplit(
      '<p>Ок</p><p>-----Original Message-----<br>From: X<br>Sent: Monday</p><p>Старый текст письма</p>',
      reply: 'Ок',
      quoted: 'Старый текст письма',
    );
  });

  test('ответ — только картинка (подпись-изображение) перед цитатой', () {
    final s = splitQuotedHtml('<p><img src="cid:sig1"></p><blockquote>Старое письмо</blockquote>');
    expect(s.hasQuote, isTrue);
    expect(s.reply, contains('cid:sig1'));
    expect(s.quoted, contains('Старое письмо'));
  });

  test('обёртка всего письма сохраняется в обеих половинах', () {
    final s = splitQuotedHtml('<div class="body"><p>Ответ</p><blockquote>Старое</blockquote></div>');
    expect(s.hasQuote, isTrue);
    expect(s.reply, contains('class="body"'));
    expect(s.quoted, contains('class="body"'));
    expect(s.reply, isNot(contains('Старое')));
  });

  test('письмо без цитаты — целиком, «Показать цитату» нет', () {
    const html = '<p>Добрый день!</p><p>Отчёт во вложении.</p>';
    final s = splitQuotedHtml(html);
    expect(s.hasQuote, isFalse);
    expect(s.reply, html);
  });

  test('пустая цитата не сворачивается (1.6.18)', () {
    final s = splitQuotedHtml('<p>Ответ без цитаты</p><blockquote> &nbsp; </blockquote>');
    expect(s.hasQuote, isFalse);
  });

  test('битый HTML не роняет разбор', () {
    final s = splitQuotedHtml('<p>Ответ<div><blockquote>Старое<table><tr><td>');
    expect(s.reply, contains('Ответ'));
  });

  group('quoteHasContent', () {
    test('текст, картинка, пустота', () {
      expect(quoteHasContent(''), isFalse);
      expect(quoteHasContent('<html><head><style>p{color:red}</style></head><body><p>&nbsp;</p></body></html>'),
          isFalse);
      expect(quoteHasContent('<body><blockquote>ок</blockquote></body>'), isTrue);
      expect(quoteHasContent('<body><blockquote><img src="cid:a"></blockquote></body>'), isTrue);
    });
  });
}

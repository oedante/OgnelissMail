// Люди в шапках цитат (1.10.3, экспериментальная функция): строки «От:»,
// «Кому:», «Копия:» шапок Outlook и пересылок Gmail — плашками с портретом
// и ссылкой на карточку человека; остальное письмо не меняется.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_people.dart';

void main() {
  group('разбор строки', () {
    test('Outlook: «Имя <адрес>; Имя <адрес>»', () {
      final p = QuotePeople.parse('Москотов Сергей Федорович <sergey.moskotov@yamalspg.ru>; '
          'Утешев Сергей Русланович <Sergey.Uteshev@yamalspg.ru>');
      expect(p.map((e) => e.toString()), [
        'Москотов Сергей Федорович <sergey.moskotov@yamalspg.ru>',
        'Утешев Сергей Русланович <Sergey.Uteshev@yamalspg.ru>',
      ]);
    });

    test('внутренний адрес Exchange — имя без адреса', () {
      final p = QuotePeople.parse(' Хабиров Ренат Фанильевич ');
      expect(p.single.name, 'Хабиров Ренат Фанильевич');
      expect(p.single.email, isNull);
    });

    test('голые адреса через запятую, «[mailto:…]», кавычки', () {
      expect(QuotePeople.parse('a@x.ru, b@y.com').map((e) => e.email), ['a@x.ru', 'b@y.com']);
      expect(QuotePeople.parse('Rob Kowal [mailto:rkowal@microsoft.com]').single.toString(),
          'Rob Kowal <rkowal@microsoft.com>');
      expect(QuotePeople.parse('"Иванов, Иван" <ivan@x.ru>').single.name, 'Иванов, Иван');
    });
  });

  test('шапка Outlook: От, Кому, Копия — плашками; Отправлено и Тема — как были', () {
    const html = '<div><p><b>От:</b> Rob Kowal (CELA) &lt;rkowal@microsoft.com&gt;<br>'
        '<b>Отправлено:</b> среда, 28 октября 2026 г. 18:00<br>'
        '<b>Кому:</b> Олег Ермишин &lt;oedante@gmail.com&gt;<br>'
        '<b>Тема:</b> Re: EAS Client</p></div><p>Hi Oleg</p>';
    final out = QuotePeople.enrich(html);
    expect(RegExp('href="ogperson:').allMatches(out).length, 2);
    expect(out, contains('<a href="ogperson:rkowal%40microsoft.com?n=Rob+Kowal+%28CELA%29">Rob Kowal (CELA)</a>'));
    // Простые ссылки, без вёрстки (1.10.4): письмо остаётся «простым» и
    // показывается виджетами — плашки рисует экран письма.
    expect(out, isNot(contains('inline-block')));
    expect(out, isNot(contains('<img')));
    expect(out, contains('среда, 28 октября 2026 г. 18:00'));
    expect(out, contains('Re: EAS Client'));
    expect(out, contains('Hi Oleg'));
    expect(out, isNot(contains('&lt;rkowal@microsoft.com&gt;')));
  });

  test('Outlook: значение в соседнем span с переносом внутри; имя без адреса', () {
    const html = '<p class="MsoNormal"><b><span>From:</span></b><span> Хабиров Ренат Фанильевич <br>'
        '<b>Sent:</b> Thursday, October 29, 2026 8:08 AM<br>'
        '<b>To:</b> Москотов Сергей &lt;sergey.moskotov@yamalspg.ru&gt;; Утешев Сергей &lt;Sergey.Uteshev@yamalspg.ru&gt;<br>'
        '<b>Cc:</b> Ермишин Олег Андреевич &lt;o.ermishin@yamalspg.ru&gt;</span></p>';
    final out = QuotePeople.enrich(html);
    expect(RegExp('href="ogperson:').allMatches(out).length, 4);
    // Без адреса — ссылка без адреса: плашка без карточки.
    expect(out, contains('<a href="ogperson:?n=%D0%A5%D0%B0%D0%B1%D0%B8%D1%80%D0%BE%D0%B2'));
    expect(QuotePeople.fromLink('ogperson:?n=%D0%A5'), isNull);
    expect(QuotePeople.nameOf('ogperson:?n=%D0%A5'), 'Х');
    expect(out, contains('Thursday, October 29, 2026 8:08 AM'));
  });

  test('пересылка Gmail: «From:» обычным текстом, адрес ссылкой mailto', () {
    const html = '<div class="gmail_quote">---------- Forwarded message ---------<br>'
        'From: <strong class="gmail_sendername" dir="auto">GitHub</strong> '
        '<span dir="auto">&lt;<a href="mailto:noreply@github.com">noreply@github.com</a>&gt;</span><br>'
        'Date: Fri, Oct 30, 2026<br>To: &lt;<a href="mailto:oedante@gmail.com">oedante@gmail.com</a>&gt;<br></div>';
    final out = QuotePeople.enrich(html);
    expect(RegExp('href="ogperson:').allMatches(out).length, 2);
    expect(out, contains('ogperson:noreply%40github.com?n=GitHub'));
    expect(out, isNot(contains('href="mailto:')));
    expect(out, contains('Date: Fri, Oct 30, 2026'));
  });

  test('«To: всем сотрудникам» в тексте письма — без изменений', () {
    const html = '<p>To: всем сотрудникам<br>Завтра собрание.</p>';
    expect(QuotePeople.enrich(html), html);
  });

  test('ссылка плашки → адрес и имя', () {
    final r = QuotePeople.fromLink('ogperson:rkowal%40microsoft.com?n=Rob+Kowal');
    expect(r!.email, 'rkowal@microsoft.com');
    expect(r.name, 'Rob Kowal');
    expect(QuotePeople.fromLink('mailto:a@b.ru'), isNull);
  });
}

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

  test('кратко (1.10.5, по умолчанию): «Фамилия И.О.», полное имя — в ссылке и подсказке', () {
    const html = '<p><b>From:</b> Зибров Дмитрий Николаевич &lt;d.zibrov@example.ru&gt;<br>'
        '<b>To:</b> Олег Ермишин &lt;o.e@example.ru&gt;; Rob Kowal &lt;rk@example.com&gt;<br>'
        '<b>Cc:</b> Хабиров Ренат Фанильевич</p>';
    final out = QuotePeople.enrichShort(html);
    expect(out, contains('>Зибров Д.Н.</a>'));
    expect(out, contains('title="Зибров Дмитрий Николаевич"'));
    expect(out, contains('>Ермишин О.</a>'));
    expect(out, contains('>Хабиров Р.Ф.</a>'));
    // Латиницу без отчества не сокращаем — без подсказки.
    expect(out, contains('<a href="ogperson:rk%40example.com?n=Rob+Kowal">Rob Kowal</a>'));
    final zibrov = RegExp(r'href="(ogperson:d\.zibrov[^"]+)"').firstMatch(out)!.group(1)!;
    expect(QuotePeople.nameOf(zibrov.replaceAll('&amp;', '&')), 'Зибров Дмитрий Николаевич');
    // Полностью — как раньше.
    expect(QuotePeople.enrich(html), contains('>Зибров Дмитрий Николаевич</a>'));
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

  test('1.14.0: длинная «Кому» (73 человека) и «Копия» — все плашками, никто не пропадает', () {
    String people(String p, int n) => [for (var i = 0; i < n; i++) '$p$i Иван Петрович &lt;$p$i@example.ru&gt;'].join('; ');
    final html = '<p><b>От:</b> Еремина Екатерина &lt;e@example.ru&gt;<br>'
        '<b>Отправлено:</b> пятница, 6 ноября 2026 г. 09:05<br>'
        '<b>Кому:</b> ${people('to', 73)}<br>'
        '<b>Копия:</b> ${people('cc', 13)}<br>'
        '<b>Тема:</b> МСК-СБТ заезд 18.11</p>';
    final out = QuotePeople.enrich(html);
    expect(RegExp('href="ogperson:').allMatches(out).length, 1 + 73 + 13);
    expect(out, contains('ogperson:to72%40example.ru'), reason: 'последний из «Кому» на месте');
    expect(out, contains('ogperson:cc12%40example.ru'), reason: '«Копия» — тоже плашками');
  });

  test('строка сверх предела остаётся текстом целиком', () {
    final names = [for (var i = 0; i < QuotePeople.maxPeople + 5; i++) 'p$i@example.ru'].join('; ');
    final out = QuotePeople.enrich('<p><b>Кому:</b> $names<br><b>Копия:</b> a@example.ru</p>');
    expect(out, contains('p${QuotePeople.maxPeople + 4}@example.ru'), reason: 'никто не пропал');
    expect(out, isNot(contains('ogperson:p0%40')), reason: 'длинная строка — без плашек');
    expect(out, contains('ogperson:a%40example.ru'), reason: 'следующая строка — плашками');
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

  group('подписи и дата шапки на языке приложения (1.11.x, скриншоты 04.11.2026)', () {
    // intl ставит неразрывные пробелы («2026 г.», «14:48») — сравниваем с обычными.
    String sp(String s) => s.replaceAll(RegExp('[\u00a0\u202f]'), ' ');
    const ru = QuoteHeaderText('ru', {
      'from': 'От:',
      'sent': 'Отправлено:',
      'to': 'Кому:',
      'cc': 'Копия:',
      'subject': 'Тема:',
    });

    test('Outlook по-английски: подписи и дата — по-русски, люди — плашками', () {
      const html = '<div><p class="MsoNormal"><b>From:</b> Ганиев Руслан Рамилевич &lt;r.ganiev@corp.ru&gt;<br>'
          '<b>Sent:</b> Thursday, October 22, 2026 2:48 PM<br>'
          '<b>To:</b> Передерий Сергей Анатольевич &lt;s.p@corp.ru&gt;<br>'
          '<b>Cc:</b> Жаринов Александр Вячеславович &lt;a.z@corp.ru&gt;<br>'
          '<b>Subject:</b> SWOT закупки МТР</p></div><p>Сергей Анатольевич, добрый день!</p>';
      final out = sp(QuotePeople.enrich(html, local: ru));
      expect(out, contains('<b>От:</b>'));
      expect(out, contains('<b>Отправлено:</b> четверг, 22 октября 2026 г. 14:48'));
      expect(out, contains('<b>Кому:</b>'));
      expect(out, contains('<b>Копия:</b>'));
      expect(out, contains('<b>Тема:</b> SWOT закупки МТР'));
      expect(RegExp('href="ogperson:').allMatches(out).length, 3);
      expect(out, isNot(contains('Thursday')));
      expect(out, contains('Сергей Анатольевич, добрый день!'));
    });

    test('без плашек людей — подписи и дата всё равно на языке приложения', () {
      const html = '<p><b>From:</b> Зибров Дмитрий Николаевич &lt;d.z@corp.ru&gt;<br>'
          '<b>Sent:</b> Monday, November 2, 2026 5:57 PM<br><b>Subject:</b> RE: Список</p>';
      final out = sp(QuotePeople.enrich(html, people: false, local: ru));
      expect(out, contains('<b>От:</b> Зибров Дмитрий Николаевич &lt;d.z@corp.ru&gt;'));
      expect(out, contains('<b>Отправлено:</b> понедельник, 2 ноября 2026 г. 17:57'));
      expect(out, isNot(contains('ogperson:')));
    });

    test('пересылка Gmail: подписи обычным текстом, «Date: … at 5:57 PM»', () {
      const html = '<div class="gmail_quote">---------- Forwarded message ---------<br>'
          'From: <strong class="gmail_sendername" dir="auto">GitHub</strong> '
          '<span dir="auto">&lt;<a href="mailto:noreply@github.com">noreply@github.com</a>&gt;</span><br>'
          'Date: Mon, Nov 2, 2026 at 5:57 PM<br>Subject: Your build<br>'
          'To: &lt;<a href="mailto:oedante@gmail.com">oedante@gmail.com</a>&gt;<br></div>';
      final out = sp(QuotePeople.enrich(html, local: ru));
      expect(out, contains('От: '));
      expect(out, contains('Отправлено: понедельник, 2 ноября 2026 г. 17:57'));
      expect(out, contains('Тема: Your build'));
      expect(out, contains('Кому: '));
      expect(out, contains('ogperson:noreply%40github.com?n=GitHub'));
    });

    test('одна строка «Subject: …» в тексте письма — не шапка, без изменений', () {
      const html = '<p>Subject: квартальный отчёт<br>Прошу посмотреть до пятницы.</p>';
      expect(QuotePeople.enrich(html, people: false, local: ru), html);
    });

    test('язык приложения английский — английская шапка без изменений', () {
      const en = QuoteHeaderText('en', {'from': 'From:', 'sent': 'Sent:', 'to': 'To:', 'cc': 'Cc:', 'subject': 'Subject:'});
      const html = '<p><b>From:</b> A &lt;a@b.ru&gt;<br><b>Sent:</b> Thursday, October 22, 2026 2:48 PM<br>'
          '<b>Subject:</b> Hi</p>';
      expect(QuotePeople.enrich(html, people: false, local: en), html);
    });

    test('даты Outlook, Gmail, Apple и RFC 2822; не дата — null', () {
      DateTime? at(String s) => QuotePeople.parseHeaderDate(s)?.at;
      expect(at('Thursday, October 22, 2026 2:48 PM'), DateTime(2026, 10, 22, 14, 48));
      expect(at('Thursday, October 22, 2026 12:05 AM'), DateTime(2026, 10, 22, 0, 5));
      expect(at('Mon, Nov 2, 2026 at 5:57 PM'), DateTime(2026, 11, 2, 17, 57));
      expect(at('2 Nov 2026 at 17:57'), DateTime(2026, 11, 2, 17, 57));
      final rfc = QuotePeople.parseHeaderDate('Mon, 2 Nov 2026 17:57:00 +0300')!;
      expect(rfc.at, DateTime(2026, 11, 2, 17, 57));
      expect(rfc.rest, '+0300');
      final noTime = QuotePeople.parseHeaderDate('Fri, Oct 30, 2026')!;
      expect(noTime.time, isFalse);
      expect(sp(QuotePeople.formatHeaderDate(noTime, 'ru')!), 'пятница, 30 октября 2026 г.');
      expect(at('November 31, 2026 10:00'), isNull);
      expect(at('Meeting on October 22, 2026'), isNull);
      expect(at('October 22, 2026 — see agenda'), isNull);
    });
  });
}

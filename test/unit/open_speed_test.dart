// Тесты ускорения открытия письма (1.5.9): простые письма без WebView
// (классификатор и блоки), планировщик фоновой работы, документ окна
// письма. Чистая логика — без WebView, базы и сети.

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/linkify.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/services/background/work_scheduler.dart';

String _text(NativeMail m) => m.blocks.map((b) => b.spans.map((s) => s.text).join()).join('|');

void main() {
  group('Простые письма без WebView', () {
    test('ответ Outlook: абзацы, выделение, ссылка', () {
      final m = buildNativeMail('<div class="WordSection1">'
          '<p class="MsoNormal">Добрый день, <b>Анатолий</b>!</p>'
          '<p class="MsoNormal">&nbsp;</p>'
          '<p class="MsoNormal">См. <a href="https://example.com/x">реестр</a>.</p>'
          '</div>');
      expect(m, isNotNull);
      expect(_text(m!), 'Добрый день, Анатолий!||См. реестр.');
      final bold = m.blocks.first.spans.firstWhere((s) => s.text == 'Анатолий');
      expect(bold.bold, isTrue);
      final link = m.blocks.last.spans.firstWhere((s) => s.href != null);
      expect(link.href, 'https://example.com/x');
      expect(link.underline, isTrue);
    });

    test('простая таблица — без WebView (подпись в две колонки)', () {
      final m = buildNativeMail('<p>Текст</p><table><tr><td width="300">С уважением,<br>Сергей</td>'
          '<td width="300">Best regards,<br>Sergey</td></tr></table>');
      expect(m, isNotNull);
      final t = m!.blocks.firstWhere((b) => b.kind == NBlockKind.table);
      expect(t.table!.single.length, 2);
      expect(t.table!.single.first.blocks.map((b) => b.spans.map((s) => s.text).join()).join(), contains('Сергей'));
    });

    test('рамки таблицы — как в браузере (1.5.10)', () {
      int borders(String html) => buildNativeMail(html)!.blocks.firstWhere((b) => b.kind == NBlockKind.table).borders;
      // Word «Сетка таблицы» без границ: border=1, но у ячеек border:none.
      expect(
          borders("<table class=MsoTableGrid border=1 style='border-collapse:collapse;border:none'><tr>"
              "<td style='border:none;mso-border-alt:solid windowtext .5pt'>a</td>"
              "<td style='border:none'>b</td></tr></table>"),
          0);
      // Белые линии — не рамка.
      expect(borders("<table><tr><td style='border:solid white 1.0pt'>a</td><td>b</td></tr></table>"), 0);
      // Только линия между колонками.
      expect(
          borders("<table><tr><td style='border:none;border-right:solid #D9D9D9 1.0pt'>a</td>"
              "<td style='border:none'>b</td></tr></table>"),
          kBorderInsideV);
      // Обычная сетка.
      expect(borders('<table border=1><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>'),
          kBorderTop | kBorderRight | kBorderBottom | kBorderLeft | kBorderInsideH | kBorderInsideV);
    });

    test('таблица в ячейке таблицы (подпись Outlook) — без WebView (1.5.10)', () {
      final m = buildNativeMail('<table><tr><td width="80"><img src="cid:logo"></td><td>'
          '<table><tr><td>Иванов И.И.</td></tr><tr><td>+7 495 000-00-00</td></tr></table></td></tr></table>');
      expect(m, isNotNull);
      final outer = m!.blocks.single;
      expect(outer.kind, NBlockKind.table);
      // Строки внешней таблицы — без строк вложенной.
      expect(outer.table!.length, 1);
      final inner = outer.table!.single[1].blocks.single;
      expect(inner.kind, NBlockKind.table);
      expect(inner.table!.length, 2);
    });

    test('вложенность глубже одного уровня, внешняя картинка, плавающий блок — в WebView', () {
      expect(buildNativeMail('<table><tr><td><table><tr><td><table><tr><td>a</td></tr></table></td></tr></table>'
          '</td></tr></table>'), isNull);
      expect(buildNativeMail('<p>x <img src="https://t.example/p.gif"></p>'), isNull);
      expect(buildNativeMail('<div style="float:left">x</div>'), isNull);
      expect(buildNativeMail('<style>@media (max-width:600px){.a{display:none}}</style><p>x</p>'), isNull);
      expect(buildNativeMail('<v:shape>x</v:shape><p>y</p>'), isNull);
    });

    test('причина показа в браузере — в журнал (1.5.10)', () {
      expect(buildNativeMailWhy('<table><tr><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td><td>6</td><td>7</td></tr></table>').why,
          'таблица: 7 колонок');
      expect(buildNativeMailWhy('<p>x <img src="https://t.example/p.gif"></p>').why, 'картинка из интернета');
      expect(buildNativeMailWhy('<p>x</p>').why, isNull);
    });

    test('объединённые ячейки — без браузера (1.5.11)', () {
      final m = buildNativeMail('<table border=1><tr><td rowspan="2">МТР</td><td colspan="2">План</td></tr>'
          '<tr><td>2025</td><td>2026</td></tr></table>');
      expect(m, isNotNull);
      final t = m!.blocks.single.table!;
      expect(t[0][0].rowSpan, 2);
      expect(t[0][1].colSpan, 2);
      expect(t[1].length, 2);
      // Колонки — с учётом объединения: 3, а не 2.
      expect(buildNativeMailWhy('<table><tr><td colspan="5">a</td><td colspan="2">b</td></tr></table>').why,
          'таблица: 7 колонок');
    });

    test('картинки из интернета — без браузера, когда разрешены (1.5.11)', () {
      const html = '<p>Логотип <img src="https://example.com/logo.png" width="120"></p>';
      expect(buildNativeMail(html), isNull);
      final m = buildNativeMailRemote(html);
      expect(m, isNotNull);
      expect(m!.blocks.single.spans.firstWhere((s) => s.image != null).image, 'https://example.com/logo.png');
    });

    test('картинка подписи cid: и data: — можно', () {
      final m = buildNativeMail('<p>Подпись <img src="cid:image001.png@01DA" width="120"></p>');
      expect(m, isNotNull);
      final img = m!.blocks.single.spans.firstWhere((s) => s.image != null);
      expect(img.image, 'cid:image001.png@01DA');
      expect(img.imageWidth, 120);
    });

    test('маркер Outlook и цвет текста', () {
      final m = buildNativeMail(
          '<p><span style="background:yellow;mso-highlight:yellow">остановочные</span> '
          '<span style="color:#C00000">красный</span></p>');
      expect(m, isNotNull);
      final spans = m!.blocks.single.spans;
      expect(spans.firstWhere((s) => s.text.contains('остановочные')).background, 0xFFFFFF00);
      expect(spans.firstWhere((s) => s.text.contains('красный')).color, 0xFFC00000);
    });

    test('списки и цитата', () {
      final m = buildNativeMail('<ul><li>один</li><li>два</li></ul><blockquote><p>цитата</p></blockquote>');
      expect(m, isNotNull);
      final b = m!.blocks;
      expect(b[0].bullet, '•');
      expect(b[1].bullet, '•');
      expect(_text(NativeMail(b.sublist(0, 2))), 'один|два');
      expect(b.last.quote, 1);
    });

    test('пустые строки по краям убираются, подряд — не больше двух', () {
      final m = buildNativeMail('<p>&nbsp;</p><p>a</p><p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p><p>&nbsp;</p><p>b</p><p>&nbsp;</p>');
      expect(m, isNotNull);
      expect(_text(m!), 'a|||b');
    });

    test('скрытый текст не показывается', () {
      final m = buildNativeMail('<p>видно</p><div style="display:none">скрыто</div>');
      expect(_text(m!), 'видно');
    });

    test('ссылки и адреса обычным текстом — нажимаемые (1.5.10)', () {
      final m = buildNativeMail('<p>Реестр: https://example.com/r. Вопросы — ivanov@company.ru</p>'
          '<p>См. <a href="https://x.ru">https://x.ru</a></p>');
      expect(m, isNotNull);
      final spans = m!.blocks.first.spans;
      expect(_text(NativeMail([m.blocks.first])), 'Реестр: https://example.com/r. Вопросы — ivanov@company.ru');
      final url = spans.firstWhere((s) => s.text == 'https://example.com/r');
      expect(url.href, 'https://example.com/r');
      expect(url.underline, isTrue);
      expect(spans.firstWhere((s) => s.text == 'ivanov@company.ru').href, 'mailto:ivanov@company.ru');
      // Обычный текст рядом — не ссылка; ссылка письма — как была.
      expect(spans.first.href, isNull);
      expect(m.blocks.last.spans.where((s) => s.href != null).single.href, 'https://x.ru');
    });
  });

  group('Ссылки в тексте', () {
    List<String> hrefs(String t) => Linkify.find(t).map((m) => m.href).toList();

    test('ссылки, www и адреса', () {
      expect(hrefs('Реестр: https://example.com/a/b?x=1.'), ['https://example.com/a/b?x=1']);
      expect(hrefs('пишите на ivanov@company.ru, спасибо'), ['mailto:ivanov@company.ru']);
      expect(hrefs('см. www.site.ru/path)'), ['https://www.site.ru/path']);
      expect(hrefs('(https://ru.wikipedia.org/wiki/Foo_(bar))'), ['https://ru.wikipedia.org/wiki/Foo_(bar)']);
      expect(hrefs('почта info@почта.рф.'), ['mailto:info@почта.рф']);
      expect(hrefs('«https://x.ru»'), ['https://x.ru']);
    });

    test('не ссылки', () {
      expect(hrefs('abcwww.x.ru'), isEmpty);
      expect(hrefs('www.x'), isEmpty);
      expect(hrefs('http://'), isEmpty);
      expect(hrefs('logo@2x.png'), isEmpty);
      expect(hrefs('Тел. +7 (495) 123-45-67'), isEmpty);
    });

    test('документ окна письма: ссылка в тексте и в карте ссылок', () {
      final doc = MailHtmlDocument.build('<p>Сайт www.site.ru и <a href="https://a.ru">a.ru</a>, '
          'почта <b>ivanov@company.ru</b></p>', allowRemoteImages: false);
      expect(doc.html, contains('<a href="https://www.site.ru">www.site.ru</a>'));
      expect(doc.html, contains('<a href="mailto:ivanov@company.ru">ivanov@company.ru</a>'));
      expect(doc.linkTexts['mailto:ivanov@company.ru'], 'ivanov@company.ru');
      expect(RegExp('<a ').allMatches(doc.html).length, 3);
    });
  });

  group('Планировщик', () {
    test('предел параллельной синхронизации и очередь', () async {
      final s = WorkScheduler.instance;
      await s.acquire(WorkPriority.sync);
      await s.acquire(WorkPriority.sync);
      await s.acquire(WorkPriority.sync);
      var fourth = false;
      final f = s.acquire(WorkPriority.sync).then((_) => fourth = true);
      await Future<void>.delayed(Duration.zero);
      expect(fourth, isFalse);
      s.release(WorkPriority.sync);
      await f;
      expect(fourth, isTrue);
      for (var i = 0; i < 3; i++) {
        s.release(WorkPriority.sync);
      }
    });

    test('открыто письмо — подготовка заранее ждёт', () async {
      final s = WorkScheduler.instance;
      s.hold(const Duration(milliseconds: 50));
      var ran = false;
      final f = s.run(WorkPriority.prefetch, () async => ran = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ran, isFalse);
      await f;
      expect(ran, isTrue);
    });
  });

  group('Документ окна письма', () {
    test('разметка — по ширине окна, а не экрана', () {
      final doc = MailHtmlDocument.build('<p>текст</p>', allowRemoteImages: false);
      final html = MailHtmlView.composeHtml(doc,
          viewWidth: 328, fitWidth: null, dark: false, pageColor: Colors.white, textScale: 1);
      expect(html, contains('width=328, initial-scale=1'));
      expect(html, isNot(contains('device-width')));
      expect(html, contains('min-width:min-content'));
    });

    test('широкое письмо вписывается', () {
      final doc = MailHtmlDocument.build('<div style="width:800px">x</div>', allowRemoteImages: false);
      // По умолчанию (1.5.11) — обычный масштаб, вписывание — кнопкой.
      MailHtmlView.fitWide = false;
      expect(MailHtmlView.initialFit(doc, 360), isNull);
      MailHtmlView.fitWide = true;
      expect(MailHtmlView.initialFit(doc, 360), 800);
      expect(MailHtmlView.initialFit(doc, 1000), isNull);
      MailHtmlView.fitWide = false;
    });
  });
}

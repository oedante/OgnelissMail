// Уже тёмное письмо в тёмной теме — без инверсии (план 08.11.2026, п. 5):
// рассылка на чёрном фоне после инверсии становилась светлой.

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ogneliss/core/utils/mail_dark_canvas.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

bool _dark(String html) {
  final doc = html_parser.parse(html);
  return MailDarkCanvas.isDark(doc, doc.body!);
}

const _text = 'Новая коллекция уже в магазинах. Скидки до 50 % только до воскресенья. '
    'Подробности на сайте и в приложении.';

void main() {
  test('таблица на чёрном фоне со всем текстом — тёмное письмо', () {
    expect(_dark('<table width="100%" bgcolor="#000000"><tr><td style="color:#fff">$_text</td></tr></table>'), isTrue);
    expect(_dark('<div style="background:#0b1530;color:#eee"><p>$_text</p></div>'), isTrue);
    expect(_dark('<div style="background-color: rgb(20, 20, 24)"><p>$_text</p></div>'), isTrue);
  });

  test('тёмная рамка вокруг белого блока с текстом — светлое письмо', () {
    expect(
        _dark('<table width="100%" bgcolor="#222222"><tr><td align="center">'
            '<table width="600" bgcolor="#ffffff"><tr><td>$_text</td></tr></table></td></tr></table>'),
        isFalse);
  });

  test('тёмная шапка, а текст на белом — светлое письмо', () {
    expect(
        _dark('<div style="background:#000"><img src="cid:logo"> Магазин</div>'
            '<div style="background:#fff"><p>$_text</p></div>'),
        isFalse);
  });

  test('фон body — атрибутом, стилем или правилом', () {
    expect(_dark('<body bgcolor="black"><p>$_text</p></body>'), isTrue);
    expect(_dark('<body style="background-color:#111"><p>$_text</p></body>'), isTrue);
    expect(_dark('<style>body{margin:0;background:#101418 url(x.png)}</style><p>$_text</p>'), isTrue);
    expect(_dark('<style>html, body { background-color: #fafafa; }</style><p>$_text</p>'), isFalse);
  });

  test('обычное письмо без фона и полупрозрачный фон — не тёмные', () {
    expect(_dark('<p>$_text</p>'), isFalse);
    expect(_dark('<div style="background:rgba(0,0,0,.05)"><p>$_text</p></div>'), isFalse);
    expect(_dark('<div style="background:transparent"><p>$_text</p></div>'), isFalse);
    expect(_dark('<div style="background:url(cid:bg.png)"><p>$_text</p></div>'), isFalse);
  });

  test('документ письма: тёмное письмо — своё оформление, без инверсии', () {
    final dark = MailHtmlDocument.build('<table bgcolor="#000"><tr><td style="color:#fff">$_text</td></tr></table>',
        allowRemoteImages: false);
    expect(dark.darkDesign, isTrue);
    final light = MailHtmlDocument.build('<p>$_text</p>', allowRemoteImages: false);
    expect(light.darkDesign, isFalse);
  });

  test('фоновая картинка из правила <style> — помечена, инверсия её вернёт', () {
    final doc = MailHtmlDocument.build(
        '<style>.hero{background-image:url(cid:hero.png);height:200px} a:hover{background:url(x)} '
        '.plain{color:red}</style><div class="hero">Акция</div><p class="plain">$_text</p>',
        allowRemoteImages: false);
    expect(doc.html, contains('<div class="hero" data-og-bgimg="">'));
    expect(doc.html, isNot(contains('<p class="plain" data-og-bgimg')));
  });
}

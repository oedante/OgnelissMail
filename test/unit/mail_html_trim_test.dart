import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

String _body(String html) {
  final out = MailHtmlDocument.build(html, allowRemoteImages: false).html;
  return out.substring(out.indexOf('<body>') + 6, out.lastIndexOf('</body>'));
}

void main() {
  test('пустые абзацы Outlook по краям убираются', () {
    final b = _body('<style>p{}</style><div class="WordSection1">'
        '<p class="MsoNormal">&nbsp;</p><p class="MsoNormal"><br></p>'
        '<p class="MsoNormal">Коллеги, добрый день.</p>'
        '<p class="MsoNormal">&nbsp;</p><p>&nbsp;</p></div><br><br>');
    // <style> из начала разметки парсер HTML переносит в <head> — тело его
    // не содержит; проверяем только края текста.
    expect(b, contains('Коллеги'));
    expect(RegExp('&nbsp;|<br>').hasMatch(b), isFalse);
  });

  test('картинка в конце не считается пустой', () {
    final b = _body('<p>Текст</p><p><img src="data:image/png;base64,AA=="></p>');
    expect(b, contains('<img'));
  });

  test('пустые абзацы внутри текста остаются', () {
    final b = _body('<p>Раз</p><p>&nbsp;</p><p>Два</p>');
    expect(b, contains('&nbsp;'));
  });

  test('ширина вёрстки рассылки определяется по таблицам и стилям', () {
    final d = MailHtmlDocument.build(
        '<style>.wrap{width:640px} .x{max-width:900px}</style>'
        '<table width="600"><tr><td style="width:580px">Текст</td></tr></table>',
        allowRemoteImages: false);
    expect(d.declaredWidth, 640);
    expect(d.fitted(640, 0.6), contains('width=640'));
  });

  test('обычное письмо без размеров — не вписывается', () {
    final d = MailHtmlDocument.build('<p>Привет</p>', allowRemoteImages: false);
    expect(d.declaredWidth, isNull);
  });

  group('встроенные картинки (cid:)', () {
    const html = '<p>Текст</p><p><img src="cid:image001.png@01DC0000" width="80">'
        '<img src="cid:image002.png@01DC0000"></p><p>Подпись</p>';
    const data = 'data:image/png;base64,AA==';

    test('без keepCid неизвестные картинки убираются сразу', () {
      final b = _body(html);
      expect(b, isNot(contains('<img')));
      expect(b, contains('Подпись'));
    });

    test('известная картинка подставляется при сборке', () {
      final out = MailHtmlDocument.build(html,
          allowRemoteImages: false, inlineImages: const {'image001.png@01dc0000': data}).html;
      expect(out, contains('src="$data"'));
      expect(out, isNot(contains('src="cid:')));
    });

    test('keepCid: документ собирается без картинок, они подставляются потом', () {
      final d = MailHtmlDocument.build(html, allowRemoteImages: false, keepCid: true);
      expect(d.html, contains('src="cid:image001.png@01DC0000"'));
      // До подстановки ссылки cid: скрыты стилем документа.
      expect(d.html, contains('img[src^="cid:" i]{display:none'));

      final full = d.withInlineImages(const {'image001.png@01dc0000': data});
      expect(full.html, contains('<img src="$data" width="80">'));
      // Картинку, которой нет, убираем — пустого места под подписью нет.
      expect(full.html, isNot(contains('image002')));
      expect(full.html, isNot(contains('src="cid:')));
    });

    test('без ссылок cid: документ не пересобирается', () {
      final d = MailHtmlDocument.build('<p>Привет</p>', allowRemoteImages: false, keepCid: true);
      expect(identical(d.withInlineImages(const {'x@y': data}), d), isTrue);
    });

    test('cid с «%» и русскими буквами не ломает сборку', () {
      final b = _body('<p>Раз</p><img src="cid:50%off"><img src="cid:картинка.png"><p>Два</p>');
      expect(b, contains('Два'));
      expect(b, isNot(contains('<img')));
    });
  });
}

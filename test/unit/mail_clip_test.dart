// Очень длинные письма — начало и «Показать письмо целиком» (1.9.x, просьба
// владельца 31.10.2026): порог, обрезка по границе блока, признак clipped,
// картинки data: не считаются, короткие письма не меняются.

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ogneliss/core/utils/mail_clip.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';

/// Абзацы «Абзац N …» по ~100 знаков.
String paragraphs(int n) =>
    [for (var i = 0; i < n; i++) '<p>Абзац $i. ${'Текст длинного письма с цитатами и журналами. ' * 2}</p>'].join();

String bodyOf(String html) {
  final i = html.indexOf('<body>');
  return html.substring(i + 6, html.lastIndexOf('</body>'));
}

void main() {
  group('HTML', () {
    test('короткое письмо — без изменений', () {
      final html = paragraphs(50);
      final a = MailHtmlDocument.build(html, allowRemoteImages: false, clip: true);
      final b = MailHtmlDocument.build(html, allowRemoteImages: false);
      expect(a.clipped, isFalse);
      expect(a.html, b.html);
    });

    test('длинное — начало по границе абзаца, разметка цела', () {
      final html = paragraphs(3000); // ~300 КБ
      expect(html.length, greaterThan(MailClip.htmlLimit));
      final d = MailHtmlDocument.build(html, allowRemoteImages: false, clip: true);
      expect(d.clipped, isTrue);
      final body = bodyOf(d.html);
      expect(body.length, lessThanOrEqualTo(MailClip.htmlKeep + 2048));
      expect(body.length, greaterThan(MailClip.htmlKeep ~/ 2));
      // Начало письма — по порядку, последний абзац — целиком.
      expect(body, startsWith('<p>Абзац 0.'));
      expect(body, endsWith('</p>'));
      final n = RegExp('<p>').allMatches(body).length;
      expect(RegExp('</p>').allMatches(body).length, n);
      expect(body, contains('Абзац ${n - 1}.'));
      expect(body, isNot(contains('Абзац $n.')));
      // Разбор заново даёт ту же разметку — целый документ.
      expect(html_parser.parse(d.html).body!.innerHtml, body);
      // Без clip (печать, «Открыть в браузере», письмо целиком) — всё.
      expect(MailHtmlDocument.build(html, allowRemoteImages: false).html, contains('Абзац 2999.'));
    });

    test('вёрстка таблицей: режется внутри ячейки, таблица закрыта', () {
      final html =
          '<style>.x{color:red}</style><table width="600"><tr><td>${paragraphs(3000)}</td></tr></table>'
          '<p>Подвал</p>';
      final d = MailHtmlDocument.build(html, allowRemoteImages: false, clip: true);
      expect(d.clipped, isTrue);
      final body = bodyOf(d.html);
      expect(body, contains('<style>.x{color:red}</style>'));
      expect(body, contains('<table width="600"><tbody><tr><td><p>Абзац 0.'));
      expect(body, endsWith('</p></td></tr></tbody></table>'));
      expect(body, isNot(contains('Подвал')));
    });

    test('картинки data: не считаются', () {
      final img = '<img src="data:image/png;base64,${'A' * (MailClip.htmlLimit * 3)}" width="10" height="10">';
      final d = MailHtmlDocument.build('${paragraphs(40)}$img<p>Конец</p>', allowRemoteImages: false, clip: true);
      expect(d.clipped, isFalse);
      expect(d.html, contains('Конец'));
      expect(MailClip.lengthWithoutData('<p>x</p>$img'), lessThan(200));
    });

    test('порог', () {
      // Чуть меньше порога — целиком, чуть больше — начало.
      String sized(int size) {
        final p = '<p>${'ж' * 93}</p>'; // 100 знаков
        return p * (size ~/ p.length);
      }

      expect(
        MailHtmlDocument.build(sized(MailClip.htmlLimit - 2000), allowRemoteImages: false, clip: true).clipped,
        isFalse,
      );
      expect(
        MailHtmlDocument.build(sized(MailClip.htmlLimit + 2000), allowRemoteImages: false, clip: true).clipped,
        isTrue,
      );
    });

    test('журнал в <pre> — по концу строки', () {
      final log = [for (var i = 0; i < 6000; i++) 'строка журнала $i: всё в порядке, идём дальше'].join('\n');
      final d = MailHtmlDocument.build('<pre>$log</pre>', allowRemoteImages: false, clip: true);
      expect(d.clipped, isTrue);
      final body = bodyOf(d.html);
      expect(body, startsWith('<pre>строка журнала 0:'));
      expect(body, matches(RegExp(r'идём дальше</pre>$')));
    });

    test('документ с картинками сохраняет признак', () {
      final d = MailHtmlDocument.build(
        '${paragraphs(3000)}<img src="cid:a">',
        allowRemoteImages: false,
        keepCid: true,
        clip: true,
      );
      expect(d.clipped, isTrue);
      expect(d.withInlineImages(const {'a': 'data:image/png;base64,AAAA'}).clipped, isTrue);
    });
  });

  group('Текст', () {
    test('короткий — null, длинный — начало по концу строки', () {
      expect(MailClip.clipText('коротко'), isNull);
      final text = [for (var i = 0; i < 4000; i++) 'Строка $i письма без HTML, довольно длинная.'].join('\n');
      expect(text.length, greaterThan(MailClip.textLimit));
      final short = MailClip.clipText(text)!;
      expect(short.length, lessThanOrEqualTo(MailClip.textKeep));
      expect(short.length, greaterThan(MailClip.textKeep ~/ 2));
      expect(short, endsWith('довольно длинная.'));
      expect(text, startsWith(short));
    });

    test('не посреди суррогатной пары', () {
      final s = '😀' * 10;
      final cut = MailClip.cutText(s, 5);
      expect(cut, '😀😀');
    });

    test('простое письмо виджетами', () {
      final small = buildNativeMail(paragraphs(20))!;
      expect(identical(small.shortened, small), isTrue);
      final big = buildNativeMailForced(paragraphs(1500))!;
      final short = big.shortened;
      expect(short.clipped, isTrue);
      expect(big.clipped, isFalse);
      expect(short.blocks.length, lessThan(big.blocks.length));
      expect(identical(big.shortened, short), isTrue);
      // Один огромный абзац — его начало.
      final one = buildNativeMailForced('<pre>${'слово ' * 30000}</pre>')!;
      final s1 = one.shortened;
      expect(s1.clipped, isTrue);
      expect(s1.blocks, hasLength(1));
      final chars = s1.blocks.first.spans.fold<int>(0, (n, s) => n + s.text.length);
      expect(chars, lessThanOrEqualTo(MailClip.textKeep));
      expect(chars, greaterThan(MailClip.textKeep ~/ 2));
    });
  });
}

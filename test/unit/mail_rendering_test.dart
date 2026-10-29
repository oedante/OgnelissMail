// Показ сложных писем (1.8.14, замечание владельца 29.10.2026: «сложные
// письма отображаются некорректно»). Проверено на шаблонах рассылок и
// письмах Outlook в Chromium шириной телефона.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/services/security/tracker_blocker.dart';

void main() {
  group('встроенный стиль', () {
    test('url() убирает только своё объявление, а не весь стиль', () {
      const td = '<table><tr><td style="background-image:url(\'https://x.ru/bg.png\');padding:40px 30px;'
          'text-align:center">Акция</td></tr></table>';
      final web = HtmlSanitizer.sanitizeKeepingStyles(td);
      expect(web, contains('padding:40px 30px'));
      expect(web, contains('text-align:center'));
      // Окно письма: загрузку фона решает CSP документа.
      expect(web, contains('url('));
      final plain = HtmlSanitizer.sanitize(td);
      expect(plain, contains('text-align:center'));
      expect(plain, isNot(contains('url(')));
    });

    test('опасное убирается и в окне письма; «;» в кавычках и скобках — не граница', () {
      expect(HtmlSanitizer.cleanInlineStyle('color:red;width:expression(alert(1));position:fixed', keepUrls: true),
          'color:red');
      expect(HtmlSanitizer.cleanInlineStyle('font-family:"A;B";background:url(data:image/png;base64,AA)', keepUrls: true),
          'font-family:"A;B";background:url(data:image/png;base64,AA)');
      // «\75 rl(» — тоже url(: без разрешения url() объявление убирается.
      expect(HtmlSanitizer.cleanInlineStyle(r'background:\75 rl(https://t.ru/p);color:blue'), 'color:blue');
      expect(HtmlSanitizer.cleanInlineStyle('behavior:url(x.htc)'), isNull);
    });

    test('шрифт, цвет и фон из <body> — у обёртки письма', () {
      final out = HtmlSanitizer.sanitizeKeepingStyles(
          '<body bgcolor="#eef1f5" text="#333333" style="margin:0;font-family:Verdana;font-size:12px;'
          'background-image:url(https://x.ru/b.png)"><p>Текст</p></body>');
      expect(out, startsWith('<div style="'));
      expect(out, contains('background-color:#eef1f5'));
      expect(out, contains('color:#333333'));
      expect(out, contains('font-family:Verdana'));
      expect(out, contains('font-size:12px'));
      expect(out, isNot(contains('margin:0')));
      expect(out, isNot(contains('url(')));
      expect(out, contains('<p>Текст</p>'));
      // Без оформления у <body> — без обёртки.
      expect(HtmlSanitizer.sanitizeKeepingStyles('<body style="margin:0"><p>Т</p></body>'), '<p>Т</p>');
    });

    test('отступы картинок и перенос под картинку сохраняются', () {
      final out = HtmlSanitizer.sanitize('<img src="cid:a" hspace="10" vspace="5"><br clear="all">');
      expect(out, contains('hspace="10"'));
      expect(out, contains('clear="all"'));
    });
  });

  group('скрытая картинка из интернета', () {
    const block = TrackerBlockOptions(enabled: true, blockExternal: true);

    test('поле её размера с подписью', () {
      final r = TrackerBlockerNotifier.block(
          '<img src="https://x.ru/banner.png" width="600" height="300" alt="Скидки &amp; акции">', block);
      expect(r.externalBlocked, 1);
      expect(r.html, contains('data-og-img'));
      expect(r.html, contains('width:600px;aspect-ratio:600 / 300'));
      expect(r.html, contains('Скидки &amp; акции'));
    });

    test('только высота — квадрат; без размеров — значок; распорка — пустое место', () {
      expect(TrackerBlockerNotifier.placeholder('<img src="https://x.ru/vk.png" height="28" alt="VK">'),
          contains('width:28px;aspect-ratio:28 / 28'));
      expect(TrackerBlockerNotifier.placeholder('<img src="https://x.ru/a.png">'), contains('🖼'));
      final sp = TrackerBlockerNotifier.placeholder('<img src="https://x.ru/s.gif" width="600" height="2">');
      expect(sp, contains('data-og-sp'));
      expect(sp, isNot(contains('🖼')));
    });

    test('подпись не становится разметкой', () {
      final p = TrackerBlockerNotifier.placeholder('<img src="https://x.ru/a.png" width="40" height="40" alt="<b>x</b>">');
      expect(p, contains('&lt;b&gt;x&lt;/b&gt;'));
      expect(p, isNot(contains('<b>')));
    });

    test('блок картинки (display:block) — блок и у поля', () {
      expect(
          TrackerBlockerNotifier.placeholder(
              '<img src="https://x.ru/a.png" width="300" height="100" style="display:block">'),
          contains('data-og-block'));
    });
  });

  group('картинки в окне письма', () {
    test('ширина и высота — пропорция из письма, а не у файла', () {
      final d = MailHtmlDocument.build(
          '<img src="cid:a" width="800" height="600" style="width:8.3333in;height:6.25in">'
          '<img src="cid:s" width="600" height="20">',
          allowRemoteImages: false,
          keepCid: true);
      expect(d.html, contains('aspect-ratio:800 / 600'));
      expect(d.html, contains('aspect-ratio:600 / 20'));
      expect(RegExp('data-og-ar="1"').allMatches(d.html).length, 2);
    });

    test('одна высота — без height:auto (значки не раздуваются)', () {
      final d = MailHtmlDocument.build('<img src="cid:vk" height="20">', allowRemoteImages: false, keepCid: true);
      expect(d.html, isNot(contains('data-og-ar="1"')));
      expect(d.html, contains('img[data-og-ar]{height:auto !important;}'));
      expect(d.html, isNot(contains('img{max-width:100% !important;height:auto')));
    });

    test('своё ограничение ширины у картинки остаётся', () {
      final d = MailHtmlDocument.build(
          '<img src="cid:p" width="260" style="width:100%;max-width:260px;height:auto">',
          allowRemoteImages: false,
          keepCid: true);
      expect(d.html, contains('max-width:min(100%, 260px) !important'));
    });

    test('слитные рамки — только у таблиц без cellspacing', () {
      final d = MailHtmlDocument.build('<p>x</p>', allowRemoteImages: false);
      expect(d.html, contains(':where(table:not([cellspacing])){border-collapse:collapse;}'));
      expect(d.html, isNot(contains('\ntable{border-collapse:collapse;}')));
    });
  });

  group('компьютер: сложная вёрстка виджетами', () {
    test('скрытое стилями письма — вне @media; голые теги и псевдоклассы — нет', () {
      expect(
          hiddenSelectors('<!-- .preheader{display:none!important} @media (max-width:600px){.mob{display:block}} '
              '.mob, td.only-mobile {display: none; max-height:0} a:hover{display:none} div{display:none} '
              '@font-face{font-family:X} .x{color:red} -->'),
          ['.preheader', '.mob', 'td.only-mobile']);
    });

    test('рассылка таблицами — блоки без скрытого текста', () {
      const html = '<style>.mob{display:none} @media (max-width:600px){.mob{display:block!important}}</style>'
          '<div style="max-height:0;overflow:hidden;font-size:1px">Прехедер</div>'
          '<table width="600"><tr><td><table><tr><td><table><tr>'
          '<td style="background-image:url(https://x.ru/a.png)">Чёрная пятница</td>'
          '<td class="mob">Только телефон</td></tr></table></td></tr></table></td></tr></table>'
          '<p style="opacity:0">Невидимое</p><p>Отписаться</p>';
      expect(buildNativeMailWhy(html).mail, isNull); // для телефона — сложное
      final m = buildNativeMailDesktop(html);
      expect(m, isNotNull);
      final text = _text(m!.blocks);
      expect(text, contains('Чёрная пятница'));
      expect(text, contains('Отписаться'));
      expect(text, isNot(contains('Прехедер')));
      expect(text, isNot(contains('Только телефон')));
      expect(text, isNot(contains('Невидимое')));
    });
  });
}

String _text(List<NBlock> blocks) => [
      for (final b in blocks) ...[
        for (final s in b.spans) s.text,
        if (b.table != null)
          for (final r in b.table!)
            for (final c in r) _text(c.blocks),
      ],
    ].join(' ');

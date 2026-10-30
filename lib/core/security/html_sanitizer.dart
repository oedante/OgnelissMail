// lib/core/security/html_sanitizer.dart
// Очистка HTML писем по белому списку на разборе DOM.
//
// Раньше очистка делалась регулярными выражениями, и они обходились:
// обработчик без кавычек (`onerror=alert(1)`), сущности в схеме
// (`java&#x73;cript:`), вложенный тег (`<scr<script></script>ipt>`),
// `</script >`, картинки в CSS (`url(...)`). Для окна ответа это было
// критично: цитата письма вставляется в редактор, который работает в WebView
// с включённым JavaScript (G-1 аудита).
//
// Здесь HTML разбирается настоящим парсером (package:html — тем же, что
// использует flutter_html), и в результат попадают только разрешённые теги,
// атрибуты и схемы ссылок. Всё остальное удаляется или «разворачивается»
// (тег убирается, текст внутри остаётся).

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class HtmlSanitizer {
  HtmlSanitizer._();

  /// Теги, которые удаляются вместе с содержимым.
  static const _dropWithContent = {
    'script', 'style', 'noscript', 'template', 'iframe', 'frame', 'frameset',
    'object', 'embed', 'applet', 'svg', 'math', 'audio', 'video', 'source',
    'track', 'canvas', 'head', 'title', 'meta', 'link', 'base', 'input',
    'button', 'textarea', 'select', 'option', 'xml', 'portal', 'dialog',
  };

  /// Разрешённые теги (остальные разворачиваются).
  static const _allowedTags = {
    'a', 'abbr', 'acronym', 'address', 'b', 'bdi', 'bdo', 'big', 'blockquote',
    'br', 'caption', 'center', 'cite', 'code', 'col', 'colgroup', 'dd', 'del',
    'details', 'dfn', 'div', 'dl', 'dt', 'em', 'figcaption', 'figure', 'font',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'i', 'img', 'ins', 'kbd', 'li',
    'mark', 'ol', 'p', 'pre', 'q', 's', 'samp', 'small', 'span', 'strike',
    'strong', 'sub', 'summary', 'sup', 'table', 'tbody', 'td', 'tfoot', 'th',
    'thead', 'tr', 'tt', 'u', 'ul', 'var', 'wbr', 'section', 'article',
    'header', 'footer', 'nav', 'main', 'aside', 'time',
  };

  /// Разрешённые атрибуты для всех тегов. 1.8.14: и оформление старой
  /// вёрстки писем — отступы картинок (hspace, vspace), перенос под
  /// картинку (br clear), линии таблиц (rules, frame, bordercolor):
  /// без них рассылки и письма 1С слипались.
  static const _globalAttrs = {
    'style', 'class', 'id', 'title', 'dir', 'lang', 'align', 'valign',
    'width', 'height', 'bgcolor', 'color', 'face', 'size', 'border',
    'cellpadding', 'cellspacing', 'colspan', 'rowspan', 'span', 'nowrap',
    'start', 'type', 'name', 'hspace', 'vspace', 'clear', 'rules', 'frame',
    'bordercolor', 'noshade', 'reversed', 'value', 'scope', 'headers', 'abbr',
  };

  static final _cssDanger = RegExp(
    r'(url\s*\(|expression\s*\(|javascript:|vbscript:|behavior\s*:|-moz-binding|@import|position\s*:\s*fixed)',
    caseSensitive: false,
  );

  /// То же без url(): в окне письма загрузку по нему решает CSP документа.
  static final _cssDangerKeepUrl = RegExp(
    r'(expression\s*\(|javascript:|vbscript:|behavior\s*:|-moz-binding|@import|position\s*:\s*fixed)',
    caseSensitive: false,
  );

  static final _dataImage = RegExp(r'^data:image/(png|jpe?g|gif|webp|bmp);base64,', caseSensitive: false);

  /// Очистить HTML. Возвращает фрагмент (содержимое body), безопасный для
  /// показа и для вставки в редактор.
  static String sanitize(String html) {
    if (html.trim().isEmpty) return html;
    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return '';
    _clean(body);
    return body.innerHtml;
  }

  /// Для показа в WebView письма (MailHtmlView): то же, что [sanitize], но
  /// блоки <style> письма сохраняются — без них вёрстка Outlook/Word теряет
  /// отступы, шрифты и ширины таблиц. Из CSS удаляется всё, что может
  /// выполнить код или подтянуть внешний ресурс в обход CSP (@import,
  /// expression(), behavior, -moz-binding, javascript:), и position:fixed
  /// (перекрытие интерфейса). url() остаётся: загрузку по нему решает CSP
  /// документа — внешние ресурсы запрещены, пока пользователь не разрешил
  /// изображения.
  static String sanitizeKeepingStyles(String html) {
    if (html.trim().isEmpty) return html;
    // Один разбор вместо двух (1.5.6): стили собираются из того же дерева,
    // которое потом очищается, — раньше письмо разбиралось дважды.
    final doc = html_parser.parse(html);
    final css = StringBuffer();
    for (final st in doc.querySelectorAll('style')) {
      css.writeln(cleanCss(st.text));
    }
    final b = doc.body;
    var body = '';
    if (b != null) {
      _clean(b, keepUrls: true);
      // Шрифт, цвет и фон письма, заданные у <body> (1.8.14): документ для
      // показа берёт только содержимое тела, и они терялись — текст писем
      // «Verdana 12, серый» шёл шрифтом приложения.
      final look = _bodyLook(b);
      if (look != null) {
        final wrap = dom.Element.tag('div')..attributes['style'] = look;
        for (final n in b.nodes.toList()) {
          wrap.append(n..remove());
        }
        b.append(wrap);
      }
      body = b.innerHtml;
    }
    final c = css.toString().trim();
    return c.isEmpty ? body : '<style>$c</style>$body';
  }

  static const _bodyProps = {
    'color', 'background', 'background-color', 'font', 'font-family', 'font-size', 'font-weight',
    'font-style', 'line-height', 'text-align', 'direction', 'letter-spacing',
  };

  /// Оформление из атрибутов <body> для обёртки содержимого; null — нет.
  static String? _bodyLook(dom.Element body) {
    final out = <String>[];
    final bg = body.attributes['bgcolor']?.trim() ?? '';
    if (RegExp(r'^#?[0-9a-zA-Z]{3,20}$').hasMatch(bg)) out.add('background-color:$bg');
    final text = body.attributes['text']?.trim() ?? '';
    if (RegExp(r'^#?[0-9a-zA-Z]{3,20}$').hasMatch(text)) out.add('color:$text');
    final st = cleanInlineStyle(body.attributes['style'] ?? '', keepUrls: true);
    if (st != null) {
      for (final d in _declarations(st)) {
        final i = d.indexOf(':');
        if (i <= 0) continue;
        final name = d.substring(0, i).trim().toLowerCase();
        if (_bodyProps.contains(name) && !d.toLowerCase().contains('url(')) out.add(d.trim());
      }
    }
    return out.isEmpty ? null : out.join(';');
  }

  /// Встроенный стиль без опасных объявлений; null — ничего не осталось
  /// (1.8.14). Раньше стиль с url(…) убирался целиком — вместе с полями,
  /// выравниванием, цветом и шрифтом: у рассылок с фоновой картинкой
  /// заголовок съезжал влево и терял поля. [keepUrls] — для окна письма
  /// (WebView): url() остаётся, загрузку решает CSP документа. Объявление с
  /// экранированием «\» убирается, если url() не разрешён: «\75 rl(» —
  /// тоже url(.
  static String? cleanInlineStyle(String style, {bool keepUrls = false}) {
    if (style.trim().isEmpty) return null;
    final danger = keepUrls ? _cssDangerKeepUrl : _cssDanger;
    final out = <String>[];
    for (final d in _declarations(style)) {
      final t = d.trim();
      if (t.isEmpty) continue;
      final plain = _decodeEntities(t);
      if (danger.hasMatch(plain)) continue;
      if (!keepUrls && plain.contains(r'\')) continue;
      out.add(t);
    }
    return out.isEmpty ? null : out.join(';');
  }

  /// Объявления стиля по «;» — кроме «;» в кавычках и скобках
  /// (url(data:image/png;base64,…), font-family:"A;B").
  static List<String> _declarations(String s) {
    final out = <String>[];
    var depth = 0;
    String? quote;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        if (depth > 0) depth--;
      } else if (c == ';' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }

  static final _cssImport = RegExp(r'@import[^;]*;?', caseSensitive: false);
  static final _cssCode = RegExp(
    r'(expression\s*\([^)]*\)|behavior\s*:[^;}]*|-moz-binding\s*:[^;}]*|javascript:|vbscript:|position\s*:\s*fixed)',
    caseSensitive: false,
  );

  /// Очистка текста таблицы стилей (см. [sanitizeKeepingStyles]).
  static String cleanCss(String css) {
    var out = _decodeEntities(css);
    out = out.replaceAll(_cssImport, '').replaceAll(_cssCode, '');
    // «</style» внутри CSS закрыл бы блок и открыл разметку.
    return out.replaceAll(RegExp(r'</\s*style', caseSensitive: false), '');
  }

  /// Для редакторов, подставляющих HTML в строку JavaScript (так работал
  /// прежний Summernote; MailEditor передаёт строки как JSON): после очистки ещё и
  /// экранирует обратную косую черту. Редактор подставляет HTML в строку
  /// JavaScript, экранируя только кавычки, и `\'` в тексте письма закрывал
  /// бы строку — то есть выполнялся бы код из письма.
  static String forEditor(String html) =>
      sanitize(html).replaceAll(r'\', '&#92;');

  static void _clean(dom.Node node, {bool keepUrls = false}) {
    // Копия списка: дети меняются во время обхода.
    for (final child in node.nodes.toList()) {
      if (child is dom.Comment) {
        child.remove(); // условные комментарии Outlook несут разметку
        continue;
      }
      if (child is! dom.Element) continue;
      final tag = (child.localName ?? '').toLowerCase();
      if (_dropWithContent.contains(tag)) {
        child.remove();
        continue;
      }
      _clean(child, keepUrls: keepUrls);
      if (!_allowedTags.contains(tag)) {
        // Неизвестный или запрещённый тег (form, body, html, o:p …):
        // убираем сам тег, оставляя содержимое.
        final parent = child.parentNode;
        if (parent != null) {
          for (final n in child.nodes.toList()) {
            parent.insertBefore(n, child);
          }
          child.remove();
        }
        continue;
      }
      _cleanAttributes(child, tag, keepUrls: keepUrls);
    }
  }

  static void _cleanAttributes(dom.Element el, String tag, {bool keepUrls = false}) {
    final attrs = Map<Object, String>.from(el.attributes);
    el.attributes.clear();
    attrs.forEach((key, value) {
      final name = key.toString().toLowerCase();
      if (name.startsWith('on')) return; // обработчики событий
      if (tag == 'a' && name == 'href') {
        final safe = _safeUrl(value, link: true);
        if (safe != null) el.attributes['href'] = safe;
        return;
      }
      if (tag == 'img' && (name == 'src' || name == 'alt')) {
        if (name == 'alt') {
          el.attributes['alt'] = value;
        } else {
          final safe = _safeUrl(value, link: false);
          if (safe != null) el.attributes['src'] = safe;
        }
        return;
      }
      if (!_globalAttrs.contains(name)) return;
      if (name == 'style') {
        final st = cleanInlineStyle(value, keepUrls: keepUrls);
        if (st != null) el.attributes['style'] = st;
        return;
      }
      el.attributes[name] = value;
    });
  }

  /// Разрешённые схемы: ссылки — http(s), mailto, tel, якорь; картинки —
  /// http(s) (их загрузку отдельно решает блокировщик трекеров), cid:
  /// (вложенные картинки письма), data:image/* в base64.
  static String? _safeUrl(String raw, {required bool link}) {
    final v = _decodeEntities(raw).trim();
    // Управляющие символы и пробелы внутри схемы («java\tscript:»).
    final compact = v.replaceAll(RegExp(r'[\u0000- ]'), '').toLowerCase();
    if (link) {
      if (compact.startsWith('#')) return v;
      if (compact.startsWith('http://') || compact.startsWith('https://') ||
          compact.startsWith('mailto:') || compact.startsWith('tel:')) {
        return v;
      }
      return null;
    }
    if (compact.startsWith('http://') || compact.startsWith('https://') || compact.startsWith('cid:')) {
      return v;
    }
    if (_dataImage.hasMatch(compact)) return v;
    return null;
  }

  static String _char(int? code) =>
      (code == null || code < 0 || code > 0x10FFFF) ? ' ' : String.fromCharCode(code);

  /// Числовые и основные именованные сущности — чтобы `java&#x73;cript:`
  /// проверялся как `javascript:`.
  static String _decodeEntities(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]{1,6});?'),
            (m) => _char(int.tryParse(m[1]!, radix: 16)))
        .replaceAllMapped(RegExp(r'&#(\d{1,7});?'), (m) => _char(int.tryParse(m[1]!)))
        .replaceAll('&colon;', ':')
        .replaceAll('&Tab;', '\t')
        .replaceAll('&NewLine;', '\n')
        .replaceAll('&amp;', '&');
  }
}

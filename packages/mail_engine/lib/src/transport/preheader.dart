// Прехедер письма (2.2.0, вопрос владельца 10.11.2026 «а прехедер мы
// обрабатываем?»): скрытый текст в начале HTML-письма, который отправитель
// задумал как строку превью в списке писем — как его показывают Gmail и
// Почта Apple. В самом письме он скрыт (показ письма его убирает), а для
// превью ленты и уведомления — то, что нужно, вместо «Если письмо не
// отображается, откройте его в браузере».
//
// Прехедер — первый скрытый блок в начале письма:
//  · с классом или id «preheader», «preview», «previewtext» и т. п.
//    (Mailchimp — mcnPreviewText, шаблоны рассылок — preheader);
//  · или спрятанный стилем сразу несколькими способами (display:none вместе
//    с max-height:0, opacity:0, mso-hide:all, font-size:0 …): так прячут
//    именно прехедер. Один display:none — часто мобильное меню, его не берём.
// Перед ним — не больше пары коротких строк видимого текста («Открыть в
// браузере»). Разбор — по началу письма, без построения DOM.

class Preheader {
  Preheader._();

  /// Сколько начала письма смотреть.
  static const _scan = 60000;

  /// Видимого текста до прехедера — не больше.
  static const _maxBefore = 80;

  static final _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9:]*)\b([^>]*)>');
  static final _attrStyle = RegExp(r'''\bstyle\s*=\s*("([^"]*)"|'([^']*)')''', caseSensitive: false);
  static final _attrClassId = RegExp(r'''\b(?:class|id)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''', caseSensitive: false);
  static final _keyword = RegExp(r'pre-?header|preview-?text|mcnpreviewtext|^preview$|hidden-?preview|preheadertext',
      caseSensitive: false);
  static final _skipBlocks = RegExp(r'<(style|script|head|title)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false);
  static final _comment = RegExp(r'<!--[\s\S]*?-->');
  static final _body = RegExp(r'<body\b[^>]*>', caseSensitive: false);
  static const _containers = {'div', 'span', 'p', 'td', 'table', 'tr', 'font', 'center', 'a'};
  static const _void = {'br', 'img', 'hr', 'meta', 'link', 'input', 'col', 'wbr', 'source', 'area', 'base'};

  /// Текст прехедера или null.
  static String? of(String? html) {
    if (html == null || html.isEmpty || !html.contains('<')) return null;
    var h = html.length > _scan ? html.substring(0, _scan) : html;
    h = h.replaceAll(_comment, ' ').replaceAll(_skipBlocks, ' ');
    final b = _body.firstMatch(h);
    final start = b?.end ?? 0;
    final textStart = start;
    for (final m in _tag.allMatches(h, start)) {
      // Видимый текст до этого тега.
      if (visibleLength(h.substring(textStart, m.start)) > _maxBefore) return null;
      if (m.group(1) == '/') continue;
      final name = m.group(2)!.toLowerCase();
      if (!_containers.contains(name)) continue;
      final attrs = m.group(3) ?? '';
      if (!_looksLikePreheader(attrs)) continue;
      final inner = _innerOf(h, m.end, name);
      final text = clean(inner);
      if (_letters.allMatches(text).length < 2) continue;
      return text.length > 200 ? '${text.substring(0, 199)}…' : text;
    }
    return null;
  }

  static final _letters = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _looksLikePreheader(String attrs) {
    final names = _attrClassId.allMatches(attrs).map((m) => m.group(2) ?? m.group(3) ?? m.group(4) ?? '').join(' ');
    final keyword = names.split(RegExp(r'\s+')).any(_keyword.hasMatch);
    final sm = _attrStyle.firstMatch(attrs);
    final style = (sm?.group(2) ?? sm?.group(3) ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final signals = hiddenSignals(style);
    if (keyword) return true;
    return style.contains('display:none') ? signals >= 2 : signals >= 3;
  }

  /// Сколько признаков «спрятано» в стиле блока.
  static int hiddenSignals(String style) {
    var n = 0;
    if (style.contains('display:none')) n++;
    if (style.contains('mso-hide:all')) n++;
    if (RegExp(r'max-height:0(px)?(!important)?(;|$)').hasMatch(style)) n++;
    if (RegExp(r'max-width:0(px)?(!important)?(;|$)').hasMatch(style)) n++;
    if (RegExp(r'(^|;)opacity:0(\.0+)?(!important)?(;|$)').hasMatch(style)) n++;
    if (style.contains('visibility:hidden')) n++;
    if (RegExp(r'font-size:[01](px)?(!important)?(;|$)').hasMatch(style)) n++;
    if (RegExp(r'line-height:[01](px)?(!important)?(;|$)').hasMatch(style)) n++;
    return n;
  }

  /// Содержимое блока <[name]> от [from] до его закрывающего тега (с учётом
  /// вложенных таких же).
  static String _innerOf(String h, int from, String name) {
    var depth = 1;
    for (final m in _tag.allMatches(h, from)) {
      if (m.group(2)!.toLowerCase() != name) continue;
      final close = m.group(1) == '/';
      final selfClosing = (m.group(3) ?? '').trimRight().endsWith('/');
      if (close) {
        depth--;
        if (depth == 0) return h.substring(from, m.start);
      } else if (!selfClosing && !_void.contains(name)) {
        depth++;
      }
    }
    final end = from + 2000 > h.length ? h.length : from + 2000;
    return h.substring(from, end);
  }

  static final _anyTag = RegExp(r'<[^>]*>');
  static final _inlineTag =
      RegExp(r'</?(?:b|i|u|s|em|strong|span|a|font|small|big|sup|sub|mark|abbr|code)\b[^>]*>', caseSensitive: false);
  static final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});');
  static final _invisible = RegExp(
      r'[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180E\u200B\u200C\u200E\u200F\u202A-\u202E'
      r'\u2060-\u2064\u206A-\u206F\u3164\uFEFF\uFFA0]');
  static final _space = RegExp(r'[\s\u00A0\u2000-\u200A\u202F\u205F\u2800\u3000]+');
  static const _named = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'zwnj': '', 'zwj': '‍',
    'shy': '', 'laquo': '«', 'raquo': '»', 'ndash': '–', 'mdash': '—', 'hellip': '…', 'rsquo': '’',
    'lsquo': '‘', 'ldquo': '“', 'rdquo': '”', 'bdquo': '„', 'nbhy': '-', 'copy': '©', 'reg': '®',
    'trade': '™', 'euro': '€', 'numero': '№', 'middot': '·', 'bull': '•',
  };

  /// Текст из разметки: без тегов, сущностей и невидимых символов, пробелы
  /// подряд — одним.
  static String clean(String fragment) {
    // Строчные теги (b, span, a …) — без пробела: «<b>вебинар</b>:» →
    // «вебинар:»; остальные (блоки, <br>) — пробелом.
    var t = fragment.replaceAll(_inlineTag, '').replaceAll(_anyTag, ' ');
    t = t.replaceAllMapped(_entity, (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
        final code = int.tryParse(hex ? e.substring(2) : e.substring(1), radix: hex ? 16 : 10);
        if (code == null || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) || code < 0x20) return ' ';
        return String.fromCharCode(code);
      }
      return _named[e.toLowerCase()] ?? m.group(0)!;
    });
    return t.replaceAll(_invisible, '').replaceAll(_space, ' ').trim();
  }

  /// Длина видимого текста фрагмента разметки.
  static int visibleLength(String fragment) => clean(fragment).length;
}

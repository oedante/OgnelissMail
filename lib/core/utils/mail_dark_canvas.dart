import 'package:html/dom.dart' as dom;

/// Письмо, которое уже тёмное (план 08.11.2026, п. 5: «не инвертировать уже
/// тёмные рассылки»). В тёмной теме окно письма перекрашивает документ
/// инверсией — светлое письмо становится тёмным. Рассылка с чёрным или
/// тёмно-синим фоном без своего тёмного оформления (@media
/// prefers-color-scheme) после инверсии становилась светлой — ярким пятном
/// в тёмной теме. Такое письмо показывается как есть.
///
/// Решает фон, на котором лежит текст: самый глубокий элемент с фоном,
/// внутри которого не меньше 60 % текста письма. Тёмная «рамка» вокруг
/// белого блока с текстом — не тёмное письмо: решает белый блок. Нет такого
/// элемента — фон body/html (атрибут, стиль, правило в <style>).
class MailDarkCanvas {
  MailDarkCanvas._();

  /// Яркость фона ниже этой (0…1) — тёмный.
  static const darkBrightness = 0.3;

  /// Сколько элементов с фоном просматривать (большие рассылки).
  static const _maxCandidates = 80;

  static bool isDark(dom.Document doc, dom.Element body) {
    final total = _textLen(body);
    if (total > 0) {
      dom.Element? canvas;
      var canvasDepth = -1;
      var seen = 0;
      void walk(dom.Element e, int depth) {
        if (depth > 12 || seen >= _maxCandidates) return;
        for (final c in e.children) {
          final tag = c.localName;
          if (tag == 'style' || tag == 'script' || tag == 'title') continue;
          if (_background(c) != null) {
            seen++;
            if (depth > canvasDepth && _textLen(c) >= total * 0.6) {
              canvas = c;
              canvasDepth = depth;
            }
          }
          walk(c, depth + 1);
        }
      }

      walk(body, 0);
      final found = canvas;
      if (found != null) return _isDarkColor(_background(found)!);
    }
    for (final e in [body, doc.documentElement]) {
      if (e == null) continue;
      final bg = _background(e);
      if (bg != null) return _isDarkColor(bg);
    }
    for (final st in doc.querySelectorAll('style')) {
      for (final m in _pageRule.allMatches(st.text)) {
        final bg = _colorIn(m.group(1)!);
        if (bg != null) return _isDarkColor(bg);
      }
    }
    return false;
  }

  /// Правило для body или html в <style>.
  static final _pageRule = RegExp(r'(?:^|[}\s;,])(?:html|body)(?:\s*,\s*(?:html|body))*\s*\{([^}]*)\}',
      caseSensitive: false);

  static final _bgDecl = RegExp(r'(?<![-\w])background(?:-color)?\s*:\s*([^;]+)', caseSensitive: false);

  /// Цвет фона элемента: атрибут bgcolor или background(-color) в style.
  static (int, int, int)? _background(dom.Element e) {
    final st = e.attributes['style'];
    if (st != null) {
      final c = _colorIn(st);
      if (c != null) return c;
    }
    final attr = e.attributes['bgcolor'];
    return attr == null ? null : _parse(attr.trim());
  }

  /// Цвет из объявлений background / background-color (последнее важнее).
  static (int, int, int)? _colorIn(String css) {
    (int, int, int)? out;
    for (final m in _bgDecl.allMatches(css)) {
      final c = _firstColor(m.group(1)!);
      if (c != null) out = c;
    }
    return out;
  }

  static final _hex = RegExp(r'#([0-9a-f]{6}|[0-9a-f]{3})\b', caseSensitive: false);
  static final _rgb = RegExp(r'rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([\d.]+))?\s*\)',
      caseSensitive: false);

  static (int, int, int)? _firstColor(String v) {
    final s = v.trim();
    final h = _hex.firstMatch(s);
    if (h != null) return _parse('#${h.group(1)}');
    final r = _rgb.firstMatch(s);
    if (r != null) {
      final a = double.tryParse(r.group(4) ?? '1') ?? 1;
      // Полупрозрачный фон — цвет под ним неизвестен.
      if (a < 0.5) return null;
      return (int.parse(r.group(1)!).clamp(0, 255), int.parse(r.group(2)!).clamp(0, 255),
          int.parse(r.group(3)!).clamp(0, 255));
    }
    for (final word in s.toLowerCase().split(RegExp(r'[\s,!]+'))) {
      final c = _named[word];
      if (c != null) return c;
    }
    return null;
  }

  static (int, int, int)? _parse(String v) {
    final s = v.toLowerCase();
    final named = _named[s];
    if (named != null) return named;
    var hex = s.startsWith('#') ? s.substring(1) : s;
    if (!RegExp(r'^([0-9a-f]{3}|[0-9a-f]{6})$').hasMatch(hex)) return null;
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    return (int.parse(hex.substring(0, 2), radix: 16), int.parse(hex.substring(2, 4), radix: 16),
        int.parse(hex.substring(4, 6), radix: 16));
  }

  static const _named = {
    'black': (0, 0, 0),
    'white': (255, 255, 255),
    'navy': (0, 0, 128),
    'darkblue': (0, 0, 139),
    'midnightblue': (25, 25, 112),
    'darkslategray': (47, 79, 79),
    'darkslategrey': (47, 79, 79),
    'dimgray': (105, 105, 105),
    'dimgrey': (105, 105, 105),
    'darkgreen': (0, 100, 0),
    'maroon': (128, 0, 0),
    'purple': (128, 0, 128),
    'whitesmoke': (245, 245, 245),
    'gainsboro': (220, 220, 220),
    'lightgray': (211, 211, 211),
    'lightgrey': (211, 211, 211),
    'silver': (192, 192, 192),
  };

  static bool _isDarkColor((int, int, int) c) =>
      (0.299 * c.$1 + 0.587 * c.$2 + 0.114 * c.$3) / 255 < darkBrightness;

  /// Длина видимого текста: без стилей и скриптов.
  static int _textLen(dom.Node n) {
    var len = 0;
    for (final c in n.nodes) {
      if (c is dom.Text) {
        len += c.text.trim().length;
      } else if (c is dom.Element) {
        final tag = c.localName;
        if (tag == 'style' || tag == 'script' || tag == 'title') continue;
        len += _textLen(c);
      }
    }
    return len;
  }
}

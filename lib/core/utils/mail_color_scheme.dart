// lib/core/utils/mail_color_scheme.dart
// Своё тёмное оформление письма вместо инверсии (1.9.x, просьба владельца
// 31.10.2026).
//
// В тёмной теме письмо в окне браузера перекрашивалось инверсией целиком
// (MailHtmlView._themed). Многие рассылки несут своё тёмное оформление —
// блок @media (prefers-color-scheme: dark) {…} в <style> (часто с
// <meta name="color-scheme" content="light dark">) — и после инверсии оно
// выглядело чужим. Теперь у такого письма стили переписываются под нужную
// схему: блоки под неё действуют без условия, под другую — убираются.
//
// Решает приложение, а не движок окна: у Android WebView (JavaScript
// выключен), WKWebView и WebView2 своё представление о «предпочитаемой
// схеме» (тема системы, тема приложения, настройки затемнения), и с темой
// приложения оно не совпадает.

class MailColorScheme {
  MailColorScheme._();

  static final _word = RegExp('prefers-color-scheme', caseSensitive: false);

  /// В стилях есть условие по схеме цветов (быстрая проверка без разбора).
  static bool mentions(String css) => css.isNotEmpty && _word.hasMatch(css);

  /// CSS для показа в схеме [dark]: блоки @media под эту схему — без
  /// условия (вместе с остальными условиями запроса: «screen and
  /// (prefers-color-scheme: dark)» → «screen»), под другую — убраны.
  /// [darkRules] — в стилях есть правила, которые действуют только в тёмной
  /// схеме (своё тёмное оформление). Без условий по схеме — та же строка.
  static ({String css, bool darkRules}) rewrite(String css, {required bool dark}) {
    if (!mentions(css)) return (css: css, darkRules: false);
    final r = _Rewriter(css, dark);
    final out = r.run(0, css.length, 0);
    return (css: out, darkRules: r.darkRules);
  }

  /// Своё тёмное оформление в стилях письма.
  static bool hasDarkDesign(String css) => rewrite(css, dark: true).darkRules;

  static final _feature = RegExp(r'\(\s*prefers-color-scheme\s*:\s*([a-z-]+)\s*\)', caseSensitive: false);
  static final _not = RegExp(r'^\s*not\s+', caseSensitive: false);
  static final _connBefore = RegExp(r'(?:^|\s)(and|or)\s*$', caseSensitive: false);
  static final _connAfter = RegExp(r'^\s*(and|or)(?=[\s(]|$)', caseSensitive: false);

  /// Условие @media в схеме [dark]: null — не выполняется (блок убрать),
  /// '' — выполняется всегда (блок без условия), иначе — условие без схемы.
  static String? evalPrelude(String prelude, {required bool dark}) {
    final kept = <String>[];
    for (final q in _splitTop(prelude)) {
      final t = q.trim();
      if (t.isEmpty) continue;
      final r = _evalQuery(t, dark);
      if (r == null) continue;
      if (r.isEmpty) return '';
      kept.add(r);
    }
    return kept.isEmpty ? null : kept.join(', ');
  }

  /// Один запрос списка (через запятую). Запрос без схемы или со схемой в
  /// непонятном виде («(prefers-color-scheme)») — как есть: решит движок.
  static String? _evalQuery(String q, bool dark) {
    final m = _feature.firstMatch(q);
    if (m == null) return q;
    final value = m.group(1)!.toLowerCase();
    if (value != 'dark' && value != 'light') return q;
    final hit = (value == 'dark') == dark;
    var head = q.substring(0, m.start);
    var tail = q.substring(m.end);
    // «not» относится ко всему запросу («not screen and (…)»).
    var negated = false;
    final n = _not.firstMatch(head);
    if (n != null) {
      negated = true;
      head = head.substring(n.end);
    }
    // Связка при самом условии схемы: до него или после.
    String? conn;
    final b = _connBefore.firstMatch(head);
    if (b != null) {
      conn = b.group(1)!.toLowerCase();
      head = head.substring(0, b.start);
    } else {
      final a = _connAfter.firstMatch(tail);
      if (a != null) {
        conn = a.group(1)!.toLowerCase();
        tail = tail.substring(a.end);
      }
    }
    final rest = '${head.trim()} ${tail.trim()}'.trim();
    final restAll = rest.isEmpty || const {'all', 'only all', 'only'}.contains(rest.toLowerCase());
    // Значение без «not»: true / false / условие [rest].
    bool? value0;
    if (conn == 'or') {
      value0 = hit ? true : (restAll ? true : null);
    } else {
      value0 = !hit ? false : (restAll ? true : null);
    }
    if (value0 == null) return negated ? 'not $rest' : rest;
    final v = negated ? !value0 : value0;
    return v ? '' : null;
  }

  /// Части списка запросов через запятую вне скобок.
  static List<String> _splitTop(String s) {
    final out = <String>[];
    var depth = 0;
    var from = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (depth > 0) depth--;
      } else if (c == 0x2C && depth == 0) {
        out.add(s.substring(from, i));
        from = i + 1;
      }
    }
    out.add(s.substring(from));
    return out;
  }
}

/// Проход по CSS: комментарии, строки и url(…) — как есть, блоки @media с
/// условием по схеме — переписываются; вложенные (@media внутри @media или
/// @supports, вложенность правил CSS) — тоже.
class _Rewriter {
  _Rewriter(this.s, this.dark);

  final String s;
  final bool dark;
  bool darkRules = false;

  static const _maxDepth = 16;

  String run(int from, int to, int depth) {
    final out = StringBuffer();
    var seg = from;
    var i = from;
    while (i < to) {
      final c = s.codeUnitAt(i);
      if (c == 0x2F && i + 1 < to && s.codeUnitAt(i + 1) == 0x2A) {
        i = _skipComment(i, to);
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        i = _skipString(i, to);
        continue;
      }
      if ((c == 0x75 || c == 0x55) && _word(i, to, 'url(')) {
        i = _skipUrl(i + 4, to);
        continue;
      }
      if (c == 0x40 && _word(i + 1, to, 'media') && !_identAt(i + 6, to)) {
        final open = _preludeEnd(i + 6, to);
        if (open >= to || s.codeUnitAt(open) != 0x7B) {
          // «@media …;» без блока или обрыв — как есть.
          i = open >= to ? to : open + 1;
          continue;
        }
        final prelude = s.substring(i + 6, open);
        if (!MailColorScheme.mentions(prelude)) {
          // Обычный @media: его содержимое просматривается дальше этим же
          // проходом (вложенный блок со схемой внутри).
          i = open + 1;
          continue;
        }
        final close = _blockEnd(open + 1, to);
        out.write(s.substring(seg, i));
        final cond = MailColorScheme.evalPrelude(prelude, dark: dark);
        if (cond != null) {
          final inner = depth < _maxDepth ? run(open + 1, close, depth + 1) : s.substring(open + 1, close);
          // Тёмное оформление — правила, которые в тёмной схеме действуют,
          // а в светлой нет.
          if (dark && MailColorScheme.evalPrelude(prelude, dark: false) == null && _hasRules(open + 1, close)) {
            darkRules = true;
          }
          out.write(cond.isEmpty ? inner : '@media $cond{$inner}');
        }
        i = close < to ? close + 1 : to;
        seg = i;
        continue;
      }
      i++;
    }
    out.write(s.substring(seg, to));
    return out.toString();
  }

  bool _word(int i, int to, String w) {
    if (i + w.length > to) return false;
    for (var k = 0; k < w.length; k++) {
      var c = s.codeUnitAt(i + k);
      if (c >= 0x41 && c <= 0x5A) c += 0x20;
      if (c != w.codeUnitAt(k)) return false;
    }
    return true;
  }

  bool _identAt(int i, int to) {
    if (i >= to) return false;
    final c = s.codeUnitAt(i);
    return (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F;
  }

  int _skipComment(int i, int to) {
    final e = s.indexOf('*/', i + 2);
    return e < 0 || e + 2 > to ? to : e + 2;
  }

  int _skipString(int i, int to) {
    final q = s.codeUnitAt(i);
    var j = i + 1;
    while (j < to) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C) {
        j += 2;
        continue;
      }
      // Незакрытая строка кончается с концом строки (как в CSS).
      if (c == q || c == 0x0A) return j + 1;
      j++;
    }
    return to;
  }

  int _skipUrl(int i, int to) {
    var j = i;
    while (j < to) {
      final c = s.codeUnitAt(j);
      if (c == 0x22 || c == 0x27) {
        j = _skipString(j, to);
        continue;
      }
      if (c == 0x29) return j + 1;
      j++;
    }
    return to;
  }

  /// Конец условия @media: «{» или «;» вне скобок, строк и комментариев.
  int _preludeEnd(int i, int to) {
    var depth = 0;
    var j = i;
    while (j < to) {
      final c = s.codeUnitAt(j);
      if (c == 0x2F && j + 1 < to && s.codeUnitAt(j + 1) == 0x2A) {
        j = _skipComment(j, to);
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        j = _skipString(j, to);
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29 && depth > 0) depth--;
      // «}» раньше «{» — неверный CSS: условие кончается здесь, проход
      // идёт дальше.
      if (depth == 0 && (c == 0x7B || c == 0x3B || c == 0x7D)) return j;
      j++;
    }
    return to;
  }

  /// Парная «}» блока, который открылся перед [i]; нет — [to].
  int _blockEnd(int i, int to) {
    var depth = 1;
    var j = i;
    while (j < to) {
      final c = s.codeUnitAt(j);
      if (c == 0x2F && j + 1 < to && s.codeUnitAt(j + 1) == 0x2A) {
        j = _skipComment(j, to);
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        j = _skipString(j, to);
        continue;
      }
      if ((c == 0x75 || c == 0x55) && _word(j, to, 'url(')) {
        j = _skipUrl(j + 4, to);
        continue;
      }
      if (c == 0x7B) depth++;
      if (c == 0x7D && --depth == 0) return j;
      j++;
    }
    return to;
  }

  /// В блоке есть объявления (не пусто и не одни комментарии).
  bool _hasRules(int from, int to) {
    var j = from;
    while (j < to) {
      final c = s.codeUnitAt(j);
      if (c == 0x2F && j + 1 < to && s.codeUnitAt(j + 1) == 0x2A) {
        j = _skipComment(j, to);
        continue;
      }
      if (c == 0x3A) return true;
      j++;
    }
    return false;
  }
}

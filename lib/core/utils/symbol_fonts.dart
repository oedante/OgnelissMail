// lib/core/utils/symbol_fonts.dart
// Символы из шрифтов Wingdings и Symbol — обычными знаками Unicode (1.5.6).
//
// Outlook и Word заменяют «->» на стрелку из шрифта Wingdings: в письме это
// буква «à» с font-family:Wingdings (а «<-» — «ß», «=>» — «è», маркеры
// списков — «§», «Ø», «ü»). На телефоне шрифта Wingdings нет, и вместо
// стрелки виден символ «à» (замечание 11.10.2026). Здесь такие символы
// заменяются на настоящие: в HTML — по шрифту элемента, в простом тексте
// (превью письма в списке, где шрифта уже нет) — только отдельно стоящие
// «à», «ß», «è» в русском тексте: французское «à» так не тронется.

import 'package:html/dom.dart' as dom;

/// Символьный шрифт элемента письма.
enum SymbolFont { wingdings, symbol }

class SymbolFonts {
  SymbolFonts._();

  /// Wingdings → Unicode: стрелки, маркеры, галочки, смайлы — то, что
  /// встречается в деловых письмах. Неизвестные символы не меняются.
  static const Map<int, String> _wingdings = {
    0x21: '✏', 0x22: '✂', 0x23: '✁', 0x28: '☎', 0x2A: '✉', 0x36: '⌛', 0x37: '⌨',
    0x3F: '✍', 0x41: '✌', 0x43: '👍', 0x44: '👎', 0x45: '☜', 0x46: '☞', 0x47: '☝',
    0x48: '☟', 0x4A: '☺', 0x4B: '😐', 0x4C: '☹', 0x4D: '💣', 0x4E: '☠', 0x4F: '⚐',
    0x52: '☼', 0x54: '❄', 0x56: '✞', 0x58: '✠', 0x59: '✡', 0x5A: '☪', 0x5B: '☯',
    0x5D: '☸', 0x5E: '♈', 0x5F: '♉', 0x60: '♊', 0x61: '♋', 0x62: '♌', 0x63: '♍',
    0x64: '♎', 0x65: '♏', 0x66: '♐', 0x67: '♑', 0x68: '♒', 0x69: '♓',
    0x6C: '●', 0x6D: '❍', 0x6E: '■', 0x6F: '□', 0x70: '□', 0x71: '❑', 0x72: '❒',
    0x73: '⬧', 0x74: '⧫', 0x75: '◆', 0x76: '❖', 0x77: '⬥', 0x78: '⌧', 0x7A: '⌘',
    0x7B: '❀', 0x7C: '✿', 0x7D: '❝', 0x7E: '❞',
    0x9F: '•', 0xA1: '○', 0xA7: '▪', 0xA8: '◻',
    0xD8: '➢', 0xDF: '←', 0xE0: '→', 0xE1: '↑', 0xE2: '↓', 0xE3: '↖', 0xE4: '↗',
    0xE5: '↙', 0xE6: '↘', 0xE7: '⬅', 0xE8: '➔', 0xE9: '⬆', 0xEA: '⬇',
    0xEF: '⇦', 0xF0: '⇨', 0xF1: '⇧', 0xF2: '⇩', 0xF3: '⬄', 0xF4: '⇳',
    0xFB: '✘', 0xFC: '✔', 0xFD: '☒', 0xFE: '☑',
  };

  /// Symbol → Unicode: греческие буквы, математические знаки, стрелки,
  /// маркер списка Word (0xB7).
  static const Map<int, String> _symbol = {
    0x22: '∀', 0x24: '∃', 0x27: '∋', 0x2D: '−', 0x40: '≅', 0x5C: '∴', 0x5E: '⊥', 0x7E: '∼',
    0x41: 'Α', 0x42: 'Β', 0x43: 'Χ', 0x44: 'Δ', 0x45: 'Ε', 0x46: 'Φ', 0x47: 'Γ', 0x48: 'Η',
    0x49: 'Ι', 0x4A: 'ϑ', 0x4B: 'Κ', 0x4C: 'Λ', 0x4D: 'Μ', 0x4E: 'Ν', 0x4F: 'Ο', 0x50: 'Π',
    0x51: 'Θ', 0x52: 'Ρ', 0x53: 'Σ', 0x54: 'Τ', 0x55: 'Υ', 0x56: 'ς', 0x57: 'Ω', 0x58: 'Ξ',
    0x59: 'Ψ', 0x5A: 'Ζ',
    0x61: 'α', 0x62: 'β', 0x63: 'χ', 0x64: 'δ', 0x65: 'ε', 0x66: 'φ', 0x67: 'γ', 0x68: 'η',
    0x69: 'ι', 0x6A: 'ϕ', 0x6B: 'κ', 0x6C: 'λ', 0x6D: 'μ', 0x6E: 'ν', 0x6F: 'ο', 0x70: 'π',
    0x71: 'θ', 0x72: 'ρ', 0x73: 'σ', 0x74: 'τ', 0x75: 'υ', 0x76: 'ϖ', 0x77: 'ω', 0x78: 'ξ',
    0x79: 'ψ', 0x7A: 'ζ',
    0xA2: '′', 0xA3: '≤', 0xA5: '∞', 0xA7: '♣', 0xA8: '♦', 0xA9: '♥', 0xAA: '♠',
    0xAB: '↔', 0xAC: '←', 0xAD: '↑', 0xAE: '→', 0xAF: '↓', 0xB0: '°', 0xB1: '±',
    0xB2: '″', 0xB3: '≥', 0xB4: '×', 0xB6: '∂', 0xB7: '•', 0xB8: '÷', 0xB9: '≠',
    0xBA: '≡', 0xBB: '≈', 0xBC: '…', 0xC4: '⊗', 0xC5: '⊕', 0xC6: '∅', 0xC7: '∩',
    0xC8: '∪', 0xCE: '∈', 0xCF: '∉', 0xD1: '∇', 0xD6: '√', 0xD7: '⋅', 0xD8: '¬',
    0xD9: '∧', 0xDA: '∨', 0xDB: '⇔', 0xDC: '⇐', 0xDD: '⇑', 0xDE: '⇒', 0xDF: '⇓',
    0xE0: '◊', 0xE5: '∑', 0xF2: '∫',
  };

  /// Заменить символы текста по шрифту.
  static String map(String text, SymbolFont font) {
    final table = font == SymbolFont.wingdings ? _wingdings : _symbol;
    StringBuffer? out;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      // Outlook иногда пишет символ в области частного использования
      // (U+F020–U+F0FF) — тот же код со смещением 0xF000.
      final code = (c >= 0xF020 && c <= 0xF0FF) ? c - 0xF000 : c;
      final rep = table[code];
      if (rep == null) {
        out?.writeCharCode(c);
        continue;
      }
      out ??= StringBuffer(text.substring(0, i));
      out.write(rep);
    }
    return out?.toString() ?? text;
  }

  static final _family = RegExp(r'''(?:^|;|\s)(mso-symbol-font-family|font-family)\s*:\s*([^;]+)''', caseSensitive: false);

  /// Шрифт, заданный элементу: символьный, null — шрифт не задан, или
  /// [_plain] — задан обычный шрифт (символы внутри уже не символьные).
  static Object? _fontOf(dom.Element e) {
    Object? fromName(String raw) {
      final first = raw.split(',').first.replaceAll(RegExp(r'''["']|&quot;'''), '').trim().toLowerCase();
      if (first.isEmpty) return null;
      if (first == 'wingdings') return SymbolFont.wingdings;
      if (first == 'symbol') return SymbolFont.symbol;
      return _plain;
    }

    final style = e.attributes['style'];
    if (style != null && style.isNotEmpty) {
      Object? found;
      for (final m in _family.allMatches(style)) {
        final f = fromName(m.group(2)!);
        // mso-symbol-font-family важнее font-family (Outlook пишет оба).
        if (m.group(1)!.toLowerCase() == 'mso-symbol-font-family' && f is SymbolFont) return f;
        found ??= f;
      }
      if (found != null) return found;
    }
    final face = e.attributes['face'];
    if (face != null && face.isNotEmpty) return fromName(face);
    return null;
  }

  static const _plain = Object();

  static final _anySymbolFont = RegExp('wingdings|symbol', caseSensitive: false);

  /// Есть ли в разметке письма символьные шрифты (быстрая проверка до
  /// обхода дерева).
  static bool mayContain(String html) => _anySymbolFont.hasMatch(html);

  /// Заменить символы шрифтов Wingdings и Symbol во всём дереве письма.
  /// Вызывать, если [mayContain] для исходной разметки вернул true.
  static void mapDom(dom.Element root) {
    void walk(dom.Node n, SymbolFont? font) {
      if (n is dom.Text) {
        if (font != null) {
          final t = n.data;
          final m = map(t, font);
          if (!identical(m, t) && m != t) n.data = m;
        }
        return;
      }
      if (n is dom.Element) {
        final tag = n.localName ?? '';
        if (tag == 'style' || tag == 'script') return;
        final f = _fontOf(n);
        final next = f is SymbolFont ? f : (f == null ? font : null);
        for (final c in n.nodes) {
          walk(c, next);
        }
      }
    }

    walk(root, null);
  }

  static final _cyrillic = RegExp('[А-Яа-яЁё]');
  static final _loneArrow = RegExp(r'(^|[\s\d.,:;()«»"\-–—])([àßè])(?=$|[\s\d.,:;()«»"\-–—])');

  /// Простой текст (превью в списке, текстовые письма): отдельно стоящие
  /// «à» → «→», «ß» → «←», «è» → «➔», если текст русский.
  static String fixPlain(String text) {
    if (!(text.contains('à') || text.contains('ß') || text.contains('è'))) return text;
    if (!_cyrillic.hasMatch(text)) return text;
    return text.replaceAllMapped(_loneArrow, (m) {
      final ch = m.group(2)!;
      final rep = ch == 'à' ? '→' : (ch == 'ß' ? '←' : '➔');
      return '${m.group(1)}$rep';
    });
  }
}

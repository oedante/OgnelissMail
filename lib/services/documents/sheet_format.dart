// lib/services/documents/sheet_format.dart
// Числа и даты в ячейках таблиц так, как их показывает Excel (1.11.x,
// предпросмотр документов, план владельца 04.11.2026).
//
// В XLSX в ячейке лежит голое число (45966, 0.125, 1234.5) и номер формата:
// встроенного («0.00», «0%», краткая дата) или своего («#,##0.00 [$₽-419]»,
// «dd.mm.yyyy», «0.00;[Red]-0.00»). Показать нужно как Excel: «1 234,50 ₽»,
// «05.11.2026», «12,5%». Здесь — разбор строки формата (ECMA-376, часть 1,
// 18.8.31) и вывод:
//  · разделы «положительные;отрицательные;ноль;текст», условия «[<100]»;
//  · цифры 0 # ?, дробная часть, разряды «,», деление на 1000 запятой в
//    конце, %, экспонента E+, дроби «# ?/?», текст в кавычках и после «\»;
//  · «[$₽-419]» — символ валюты и язык названий месяцев, «[$-F800]» —
//    длинная дата системы, «[Red]», «[Color10]» — цвет текста;
//  · даты и время: y m d h s, AM/PM, «[h]» — часы сверх суток, доли секунды;
//    число дней от 1900 года (с ошибкой Lotus 1-2-3: 29.02.1900) или 1904.
// Десятичный разделитель, разряды и краткая дата — по языку приложения:
// русский «1 234,56» и «05.11.2026», немецкий «1.234,56», английский
// «1,234.56» и «11/5/2026».
//
// «Общий» формат — как у Excel: до 11 знаков, без «шума» двоичных дробей
// (0,1 + 0,2 — «0,3»); целые до 15 цифр — полностью (ИНН, номера счетов в
// числах), как LibreOffice.

import 'dart:math' as math;

import 'package:intl/date_symbol_data_local.dart' show dateTimeSymbolMap;
import 'package:intl/date_symbols.dart';

/// Язык показа чисел и дат.
class SheetLocale {
  const SheetLocale._(
    this.lang,
    this.decimal,
    this.group,
    this.shortDate,
    this.longDate,
    this.longTime,
    this.trueText,
    this.falseText,
  );

  final String lang;

  /// Десятичный разделитель и разделитель разрядов.
  final String decimal;
  final String group;

  /// Краткая и длинная дата, длинное время — строкой формата Excel.
  final String shortDate;
  final String longDate;
  final String longTime;

  /// ИСТИНА/ЛОЖЬ — как у Excel этого языка.
  final String trueText;
  final String falseText;

  static const _nbsp = ' ';
  static const _nnbsp = ' ';

  static final Map<String, SheetLocale> _cache = {};

  /// Для языка приложения (27 языков; прочие — по ближайшему, иначе как
  /// английский).
  static SheetLocale of(String lang) {
    final l = lang.toLowerCase().split(RegExp('[-_]')).first;
    return _cache[l] ??= _make(l);
  }

  static SheetLocale _make(String l) {
    SheetLocale m(String dec, String grp, String sd, {String? ld, String? lt, String t = 'TRUE', String f = 'FALSE'}) =>
        SheetLocale._(l, dec, grp, sd, ld ?? 'd mmmm yyyy', lt ?? 'h:mm:ss', t, f);
    switch (l) {
      case 'ru':
        return m(',', _nbsp, 'dd.mm.yyyy', ld: 'd mmmm yyyy "г."', t: 'ИСТИНА', f: 'ЛОЖЬ');
      case 'uk':
        return m(',', _nbsp, 'dd.mm.yyyy', ld: 'd mmmm yyyy "р."', t: 'ІСТИНА', f: 'ХИБНІСТЬ');
      case 'be':
      case 'kk':
      case 'bg':
        return m(',', _nbsp, 'dd.mm.yyyy');
      case 'de':
        return m(',', '.', 'dd.mm.yyyy', ld: 'dddd, d. mmmm yyyy', t: 'WAHR', f: 'FALSCH');
      case 'fr':
        return m(',', _nnbsp, 'dd/mm/yyyy', ld: 'dddd d mmmm yyyy', t: 'VRAI', f: 'FAUX');
      case 'es':
        return m(',', '.', 'dd/mm/yyyy', ld: 'dddd, d "de" mmmm "de" yyyy', t: 'VERDADERO', f: 'FALSO');
      case 'it':
        return m(',', '.', 'dd/mm/yyyy', ld: 'dddd d mmmm yyyy', t: 'VERO', f: 'FALSO');
      case 'pt':
        return m(',', '.', 'dd/mm/yyyy', ld: 'dddd, d "de" mmmm "de" yyyy', t: 'VERDADEIRO', f: 'FALSO');
      case 'nl':
        return m(',', '.', 'd-m-yyyy', ld: 'dddd d mmmm yyyy', t: 'WAAR', f: 'ONWAAR');
      case 'pl':
        return m(',', _nbsp, 'dd.mm.yyyy', t: 'PRAWDA', f: 'FAŁSZ');
      case 'cs':
        return m(',', _nbsp, 'dd.mm.yyyy', ld: 'dddd d. mmmm yyyy', t: 'PRAVDA', f: 'NEPRAVDA');
      case 'sk':
        return m(',', _nbsp, 'dd.mm.yyyy', ld: 'dddd d. mmmm yyyy', t: 'PRAVDA', f: 'NEPRAVDA');
      case 'hu':
        return m(',', _nbsp, 'yyyy.mm.dd.', ld: 'yyyy. mmmm d.', t: 'IGAZ', f: 'HAMIS');
      case 'ro':
        return m(',', '.', 'dd.mm.yyyy', t: 'ADEVĂRAT', f: 'FALS');
      case 'fi':
        return m(',', _nbsp, 'd.m.yyyy', ld: 'dddd d. mmmm yyyy', lt: 'h.mm.ss', t: 'TOSI', f: 'EPÄTOSI');
      case 'sv':
        return m(',', _nbsp, 'yyyy-mm-dd', ld: '"den "d mmmm yyyy', t: 'SANT', f: 'FALSKT');
      case 'da':
        return m(',', '.', 'dd-mm-yyyy', ld: 'dddd "den" d. mmmm yyyy', t: 'SAND', f: 'FALSK');
      case 'nb':
      case 'no':
      case 'nn':
        return m(',', _nbsp, 'dd.mm.yyyy', ld: 'd. mmmm yyyy', t: 'SANN', f: 'USANN');
      case 'tr':
        return m(',', '.', 'dd.mm.yyyy', ld: 'd mmmm yyyy dddd', t: 'DOĞRU', f: 'YANLIŞ');
      case 'el':
        return m(',', '.', 'd/m/yyyy');
      case 'id':
        return m(',', '.', 'dd/mm/yyyy');
      case 'vi':
        return m(',', '.', 'dd/mm/yyyy');
      case 'ar':
      case 'he':
        return m('.', ',', 'dd/mm/yyyy');
      case 'hi':
        return m('.', ',', 'dd-mm-yyyy');
      case 'th':
        return m('.', ',', 'd/m/yyyy');
      case 'ja':
        return m('.', ',', 'yyyy/mm/dd', ld: 'yyyy"年"m"月"d"日"');
      case 'zh':
        return m('.', ',', 'yyyy/m/d', ld: 'yyyy"年"m"月"d"日"');
      case 'ko':
        return m('.', ',', 'yyyy-mm-dd', ld: 'yyyy"년" m"월" d"일" dddd');
      default:
        return SheetLocale._(
          l == 'en' ? 'en' : 'en',
          '.',
          ',',
          'm/d/yyyy',
          'dddd, mmmm d, yyyy',
          'h:mm:ss AM/PM',
          'TRUE',
          'FALSE',
        );
    }
  }

  // ── Названия месяцев и дней (данные intl, уже в приложении) ──

  static final Map<String, DateSymbols?> _symbols = {};

  DateSymbols? get _sym => _symbols.putIfAbsent(lang, () {
    final map = dateTimeSymbolMap();
    return map[lang] ?? map['en'];
  });

  static const _ruShort = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

  /// Месяц 1–12: [len] 3 — краткое, 4 — полное, 5 — первая буква; [withDay]
  /// — форма «5 ноября» (родительный падеж там, где он есть).
  String month(int m, int len, {required bool withDay}) {
    final s = _sym;
    final i = (m - 1).clamp(0, 11);
    if (s == null) return '$m';
    if (len == 3) return lang == 'ru' ? _ruShort[i] : (withDay ? s.SHORTMONTHS[i] : s.STANDALONESHORTMONTHS[i]);
    final full = withDay ? s.MONTHS[i] : s.STANDALONEMONTHS[i];
    if (len >= 5) return full.isEmpty ? '' : full.substring(0, 1).toUpperCase();
    // «Ноябрь 2026» — у русского Excel месяц без числа с большой буквы.
    if (!withDay && lang == 'ru' && full.isNotEmpty) return full[0].toUpperCase() + full.substring(1);
    return full;
  }

  /// День недели: [weekday] — DateTime.weekday (1 — понедельник).
  String weekday(int weekday, {required bool short}) {
    final s = _sym;
    if (s == null) return '';
    final i = weekday % 7; // intl: 0 — воскресенье
    return short ? s.SHORTWEEKDAYS[i] : s.WEEKDAYS[i];
  }

  String ampm(bool pm) {
    final s = _sym;
    if (s == null || s.AMPMS.length < 2) return pm ? 'PM' : 'AM';
    return s.AMPMS[pm ? 1 : 0];
  }
}

/// Результат форматирования: текст и цвет из формата («[Red]»), если есть.
class SheetFormatted {
  final String text;
  final int? color;
  const SheetFormatted(this.text, [this.color]);
}

// Виды элементов формата.
const _lit = 0, _digit = 1, _point = 2, _comma = 3, _pct = 4, _exp = 5, _text = 6, _general = 7, _slash = 8;
const _date = 9, _ampm = 10, _elapsed = 11;

class _T {
  final int k;
  final String s;
  final int n;
  const _T(this.k, [this.s = '', this.n = 0]);
}

class _Cond {
  final String op;
  final double v;
  const _Cond(this.op, this.v);

  bool test(double x) => switch (op) {
    '<' => x < v,
    '<=' => x <= v,
    '>' => x > v,
    '>=' => x >= v,
    '=' => x == v,
    '<>' => x != v,
    _ => false,
  };
}

class _Section {
  final List<_T> t;
  final int? color;
  final _Cond? cond;

  /// Язык названий месяцев из «[$-419]».
  final String? lang;
  final bool isDate;
  final bool hasText;
  final bool sysDate;
  final bool sysTime;
  const _Section(this.t, this.color, this.cond, this.lang, this.isDate, this.hasText, this.sysDate, this.sysTime);

  bool get isEmpty => t.isEmpty;
}

/// Формат числа Excel, разобранный один раз.
class SheetNumberFormat {
  SheetNumberFormat._(this.code, this._sections);

  final String code;
  final List<_Section> _sections;

  static final Map<String, SheetNumberFormat> _cache = {};

  /// Разобранный [code] (из кэша).
  factory SheetNumberFormat(String code) {
    final hit = _cache[code];
    if (hit != null) return hit;
    if (_cache.length > 4000) _cache.clear();
    return _cache[code] = SheetNumberFormat._(code, _parse(code));
  }

  static final general = SheetNumberFormat('General');

  /// Формат даты или времени (первый раздел).
  bool get isDate => _sections.isNotEmpty && _sections.first.isDate;

  /// Встроенные форматы Excel (ECMA-376, 18.8.30); зависящие от языка
  /// (краткая дата 14, 22) — по [loc]. null — неизвестный номер (как «Общий»).
  static String? builtin(int id, SheetLocale loc) {
    switch (id) {
      case 0:
        return 'General';
      case 1:
        return '0';
      case 2:
        return '0.00';
      case 3:
        return '#,##0';
      case 4:
        return '#,##0.00';
      case 5:
        return '#,##0;-#,##0';
      case 6:
        return '#,##0;[Red]-#,##0';
      case 7:
        return '#,##0.00;-#,##0.00';
      case 8:
        return '#,##0.00;[Red]-#,##0.00';
      case 9:
        return '0%';
      case 10:
        return '0.00%';
      case 11:
        return '0.00E+00';
      case 12:
        return '# ?/?';
      case 13:
        return '# ??/??';
      case 14:
        return loc.shortDate;
      case 15:
        return 'd-mmm-yy';
      case 16:
        return 'd-mmm';
      case 17:
        return 'mmm-yy';
      case 18:
        return 'h:mm AM/PM';
      case 19:
        return 'h:mm:ss AM/PM';
      case 20:
        return 'h:mm';
      case 21:
        return 'h:mm:ss';
      case 22:
        return '${loc.shortDate} h:mm';
      case 37:
        return '#,##0 ;(#,##0)';
      case 38:
        return '#,##0 ;[Red](#,##0)';
      case 39:
        return '#,##0.00;(#,##0.00)';
      case 40:
        return '#,##0.00;[Red](#,##0.00)';
      case 41:
        return '_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)';
      case 42:
        return '_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)';
      case 43:
        return '_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)';
      case 44:
        return '_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)';
      case 45:
        return 'mm:ss';
      case 46:
        return '[h]:mm:ss';
      case 47:
        return 'mm:ss.0';
      case 48:
        return '##0.0E+0';
      case 49:
        return '@';
    }
    // Восточноазиатские даты (27–36, 50–58) — краткой датой.
    if ((id >= 27 && id <= 36) || (id >= 50 && id <= 58)) return loc.shortDate;
    return null;
  }

  // ── Разбор ──

  static List<_Section> _parse(String code) {
    final parts = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    var inBracket = false;
    for (var i = 0; i < code.length; i++) {
      final ch = code[i];
      if (inQuote) {
        buf.write(ch);
        if (ch == '"') inQuote = false;
        continue;
      }
      if (ch == '\\' && i + 1 < code.length) {
        buf
          ..write(ch)
          ..write(code[++i]);
        continue;
      }
      if (ch == '"') inQuote = true;
      if (ch == '[') inBracket = true;
      if (ch == ']') inBracket = false;
      if (ch == ';' && !inBracket) {
        parts.add(buf.toString());
        buf.clear();
        if (parts.length >= 4) break;
        continue;
      }
      buf.write(ch);
    }
    if (parts.length < 4) parts.add(buf.toString());
    return [for (final p in parts) _section(p)];
  }

  static const _colors = {
    'black': 0xFF000000,
    'blue': 0xFF0000FF,
    'cyan': 0xFF00FFFF,
    'green': 0xFF00FF00,
    'magenta': 0xFFFF00FF,
    'red': 0xFFFF0000,
    'white': 0xFFFFFFFF,
    'yellow': 0xFFFFFF00,
  };

  static _Section _section(String s) {
    final t = <_T>[];
    int? color;
    _Cond? cond;
    String? lang;
    var sysDate = false;
    var sysTime = false;
    var i = 0;
    bool at(String w) => s.length - i >= w.length && s.substring(i, i + w.length).toLowerCase() == w.toLowerCase();
    while (i < s.length) {
      final ch = s[i];
      switch (ch) {
        case '"':
          final end = s.indexOf('"', i + 1);
          final lit = end < 0 ? s.substring(i + 1) : s.substring(i + 1, end);
          if (lit.isNotEmpty) t.add(_T(_lit, lit));
          i = end < 0 ? s.length : end + 1;
          continue;
        case '\\':
          if (i + 1 < s.length) t.add(_T(_lit, s[i + 1]));
          i += 2;
          continue;
        case '_':
          // Место под ширину знака (выравнивание скобок) — пробел.
          t.add(const _T(_lit, ' '));
          i += 2;
          continue;
        case '*':
          // Заполнение ячейки повтором знака — не показывается.
          i += 2;
          continue;
        case '[':
          final end = s.indexOf(']', i + 1);
          final body = end < 0 ? s.substring(i + 1) : s.substring(i + 1, end);
          i = end < 0 ? s.length : end + 1;
          final low = body.toLowerCase().trim();
          if (_colors.containsKey(low)) {
            color = _colors[low];
          } else if (low.startsWith('color')) {
            final n = int.tryParse(low.substring(5).trim());
            if (n != null && n >= 1 && n <= 56) color = excelPalette[n + 7];
          } else if (low.startsWith('<') || low.startsWith('>') || low.startsWith('=')) {
            final m = RegExp(r'^(<=|>=|<>|<|>|=)\s*(-?[0-9.]+(?:e[-+]?\d+)?)$').firstMatch(low);
            if (m != null) cond = _Cond(m.group(1)!, double.tryParse(m.group(2)!) ?? 0);
          } else if (low.startsWith(r'$')) {
            final dash = body.indexOf('-');
            final sym = dash < 0 ? body.substring(1) : body.substring(1, dash);
            if (sym.isNotEmpty) t.add(_T(_lit, sym));
            if (dash >= 0) {
              final tag = body.substring(dash + 1).trim().toLowerCase();
              if (tag == 'f800' || tag == 'x-sysdate') {
                sysDate = true;
              } else if (tag == 'f400' || tag == 'x-systime') {
                sysTime = true;
              } else {
                lang = _langOfTag(tag) ?? lang;
              }
            }
          } else if (RegExp(r'^(h+|m+|s+)$').hasMatch(low)) {
            t.add(_T(_elapsed, low[0], low.length));
          }
          continue;
      }
      if (at('general')) {
        t.add(const _T(_general));
        i += 7;
        continue;
      }
      if (at('am/pm')) {
        t.add(_T(_ampm, s.substring(i, i + 5)));
        i += 5;
        continue;
      }
      if (at('a/p')) {
        t.add(_T(_ampm, s.substring(i, i + 3)));
        i += 3;
        continue;
      }
      switch (ch) {
        case '0':
        case '#':
        case '?':
          t.add(_T(_digit, ch));
          i++;
          continue;
        case '.':
          t.add(const _T(_point));
          i++;
          continue;
        case ',':
          t.add(const _T(_comma));
          i++;
          continue;
        case '%':
          t.add(const _T(_pct));
          i++;
          continue;
        case '@':
          t.add(const _T(_text));
          i++;
          continue;
        case '/':
          t.add(const _T(_slash));
          i++;
          continue;
        case 'E':
        case 'e':
          if (i + 1 < s.length && (s[i + 1] == '+' || s[i + 1] == '-')) {
            t.add(_T(_exp, '$ch${s[i + 1]}'));
            i += 2;
            continue;
          }
      }
      final low = ch.toLowerCase();
      if (low == 'y' || low == 'm' || low == 'd' || low == 'h' || low == 's') {
        var n = 1;
        while (i + n < s.length && s[i + n].toLowerCase() == low) {
          n++;
        }
        t.add(_T(_date, low, n));
        i += n;
        continue;
      }
      // Буддийский год («bbbb») и эры — как обычный год.
      if (low == 'b' || low == 'e') {
        var n = 1;
        while (i + n < s.length && s[i + n].toLowerCase() == low) {
          n++;
        }
        t.add(_T(_date, 'y', math.max(n, 3)));
        i += n;
        continue;
      }
      t.add(_T(_lit, ch));
      i++;
    }
    final isDate = sysDate || sysTime || t.any((x) => x.k == _date || x.k == _ampm || x.k == _elapsed);
    final hasText = t.any((x) => x.k == _text);
    return _Section(isDate ? _resolveDate(t) : t, color, cond, lang, isDate, hasText, sysDate, sysTime);
  }

  /// «m» — месяц или минуты: минуты сразу после часов или перед секундами.
  /// «.0» после секунд — доли секунды; прочие «.» «,» «/» «0» — как есть.
  static List<_T> _resolveDate(List<_T> t) {
    final out = <_T>[];
    for (var i = 0; i < t.length; i++) {
      final x = t[i];
      if (x.k == _date) {
        if (x.s == 'm' && x.n <= 2) {
          String? prev;
          for (var j = out.length - 1; j >= 0; j--) {
            if (out[j].k == _date || out[j].k == _elapsed) {
              prev = out[j].s;
              break;
            }
          }
          String? next;
          for (var j = i + 1; j < t.length; j++) {
            if (t[j].k == _date || t[j].k == _elapsed) {
              next = t[j].s;
              break;
            }
          }
          out.add(_T(_date, prev == 'h' || next == 's' ? 'i' : 'M', x.n));
        } else {
          out.add(_T(_date, x.s == 'm' ? 'M' : x.s, x.n));
        }
        continue;
      }
      if (x.k == _point && i + 1 < t.length && t[i + 1].k == _digit && t[i + 1].s == '0') {
        final prev = out.isEmpty ? null : out.last;
        if (prev != null && ((prev.k == _date && prev.s == 's') || (prev.k == _elapsed && prev.s == 's'))) {
          var n = 0;
          while (i + 1 < t.length && t[i + 1].k == _digit && t[i + 1].s == '0') {
            n++;
            i++;
          }
          out.add(_T(_date, 'f', math.min(n, 3)));
          continue;
        }
      }
      switch (x.k) {
        case _point:
          out.add(const _T(_lit, '.'));
        case _comma:
          out.add(const _T(_lit, ','));
        case _slash:
          out.add(const _T(_lit, '/'));
        case _digit:
          out.add(_T(_lit, x.s == '?' ? ' ' : (x.s == '#' ? '' : '0')));
        case _pct:
          out.add(const _T(_lit, '%'));
        case _exp:
          out.add(_T(_lit, x.s));
        default:
          out.add(x);
      }
    }
    return out;
  }

  /// Язык по тегу «419», «F419», «1010409», «ru-RU».
  static String? _langOfTag(String tag) {
    if (tag.contains(RegExp('[g-z]'))) {
      final l = tag.split(RegExp('[-_]')).first;
      return l.length == 2 || l.length == 3 ? l : null;
    }
    final v = int.tryParse(tag, radix: 16);
    if (v == null) return null;
    return _lcidLang[v & 0x3FF];
  }

  static const _lcidLang = {
    0x01: 'ar',
    0x02: 'bg',
    0x04: 'zh',
    0x05: 'cs',
    0x06: 'da',
    0x07: 'de',
    0x08: 'el',
    0x09: 'en',
    0x0A: 'es',
    0x0B: 'fi',
    0x0C: 'fr',
    0x0D: 'he',
    0x0E: 'hu',
    0x10: 'it',
    0x11: 'ja',
    0x12: 'ko',
    0x13: 'nl',
    0x14: 'nb',
    0x15: 'pl',
    0x16: 'pt',
    0x18: 'ro',
    0x19: 'ru',
    0x1B: 'sk',
    0x1D: 'sv',
    0x1E: 'th',
    0x1F: 'tr',
    0x21: 'id',
    0x22: 'uk',
    0x23: 'be',
    0x2A: 'vi',
    0x39: 'hi',
    0x3F: 'kk',
  };

  // ── Вывод ──

  /// Число [v] этим форматом.
  SheetFormatted format(double v, SheetLocale loc, {bool date1904 = false}) {
    if (v.isNaN || v.isInfinite) return const SheetFormatted('#NUM!');
    if (_sections.isEmpty) return SheetFormatted(generalText(v, loc));
    // Разделы для чисел: текстовый («@») — всегда последний, его не считаем.
    var nums = _sections;
    if (nums.length == 4) {
      nums = nums.sublist(0, 3);
    } else if (nums.length > 1 && nums.last.hasText && !nums.last.t.any((x) => x.k == _digit || x.k == _general)) {
      nums = nums.sublist(0, nums.length - 1);
    }
    _Section sec;
    bool signed;
    if (nums.any((s) => s.cond != null)) {
      // «[<100]…;[>=100]…;…»: первый подходящий раздел, знак — у числа.
      signed = true;
      final s0 = nums[0];
      if (s0.cond == null ? v >= 0 : s0.cond!.test(v)) {
        sec = s0;
      } else if (nums.length > 1 && (nums[1].cond == null || nums[1].cond!.test(v))) {
        sec = nums[1];
        // Второй раздел без условия после «[>=0]» — обычный «отрицательный».
        if (nums[1].cond == null && v < 0) signed = false;
      } else {
        sec = nums.length > 2 ? nums[2] : s0;
      }
    } else if (nums.length == 1) {
      sec = nums[0];
      signed = true;
    } else if (nums.length == 2) {
      sec = v >= 0 ? nums[0] : nums[1];
      signed = false;
    } else {
      sec = v > 0 ? nums[0] : (v < 0 ? nums[1] : nums[2]);
      signed = false;
    }
    if (sec.isEmpty) return SheetFormatted('', sec.color);
    if (sec.isDate) return SheetFormatted(_formatDate(sec, v, loc, date1904), sec.color);
    var text = _formatNumber(sec, v.abs(), loc);
    // Знак — только когда раздел один на все числа («-0» у отрицательного,
    // округлённого до нуля, Excel тоже показывает); у раздела «только
    // подпись» знака нет.
    if (signed && v < 0 && sec.t.any((x) => x.k == _digit || x.k == _general)) text = '-$text';
    return SheetFormatted(text, sec.color);
  }

  /// Текст в ячейке с этим форматом: текстовый раздел («@» и подписи);
  /// null — показать текст как есть.
  String? formatText(String s) {
    _Section? sec;
    if (_sections.length >= 4) {
      sec = _sections[3];
    } else if (_sections.isNotEmpty && _sections.last.hasText) {
      sec = _sections.last;
    }
    if (sec == null || sec.isDate) return null;
    final out = StringBuffer();
    for (final x in sec.t) {
      if (x.k == _text) {
        out.write(s);
      } else if (x.k == _lit) {
        out.write(x.s);
      }
    }
    return out.toString();
  }

  // ── «Общий» ──

  /// Число в «Общем» формате.
  static String generalText(double v, SheetLocale loc) {
    if (v.isNaN || v.isInfinite) return '#NUM!';
    if (v == 0) return '0';
    final neg = v < 0;
    final a = v.abs();
    String body;
    if (a == a.truncateToDouble() && a < 1e15) {
      body = a.toInt().toString();
    } else {
      final e = _exp10(a);
      if (e >= 11 || e < -4) {
        body = _sci(a, loc, 5);
      } else {
        final intDigits = e >= 0 ? e + 1 : 1;
        final decimals = math.max(0, 10 - intDigits);
        final r = roundDecimal(a, decimals);
        var frac = r.frac.replaceFirst(RegExp(r'0+$'), '');
        if (r.int == '0' && frac.isEmpty) return _sci(a, loc, 5, neg: neg);
        // Округление дало больше 11 знаков (99999999999,6) — экспонента.
        if (r.int.length > 11) return _sci(a, loc, 5, neg: neg);
        if (r.int.length + frac.length > 11) frac = frac.substring(0, math.max(0, 11 - r.int.length));
        body = frac.isEmpty ? r.int : '${r.int}${loc.decimal}$frac';
      }
    }
    return neg ? '-$body' : body;
  }

  static int _exp10(double a) {
    final s = a.toStringAsExponential(14);
    return int.parse(s.substring(s.indexOf('e') + 1));
  }

  /// «1,23457E+11».
  static String _sci(double a, SheetLocale loc, int decimals, {bool neg = false}) {
    var e = _exp10(a);
    var m = a / math.pow(10.0, e);
    var r = roundDecimal(m, decimals);
    if (r.int.length > 1) {
      e += 1;
      m = a / math.pow(10.0, e);
      r = roundDecimal(m, decimals);
    }
    final frac = r.frac.replaceFirst(RegExp(r'0+$'), '');
    final mant = frac.isEmpty ? r.int : '${r.int}${loc.decimal}$frac';
    final es = e.abs().toString().padLeft(2, '0');
    return '${neg ? '-' : ''}${mant}E${e < 0 ? '-' : '+'}$es';
  }

  /// [a] ≥ 0, округлённое до [decimals] знаков после запятой по-Excel'евски:
  /// сначала до 15 значащих цифр (так Excel избавляется от «шума» двоичных
  /// дробей), затем половина — вверх. Целая часть без ведущих нулей.
  static ({String int, String frac}) roundDecimal(double a, int decimals) {
    if (a == 0 || a.isNaN) return (int: '0', frac: ''.padRight(decimals, '0'));
    final s = a.toStringAsExponential(14);
    final ePos = s.indexOf('e');
    var digits = s.substring(0, ePos).replaceAll('.', '');
    var point = int.parse(s.substring(ePos + 1)) + 1;
    final keep = point + decimals;
    if (keep < 0) return (int: '0', frac: ''.padRight(decimals, '0'));
    if (digits.length < keep) digits = digits.padRight(keep, '0');
    if (keep < digits.length) {
      final up = digits.codeUnitAt(keep) >= 0x35;
      digits = digits.substring(0, keep);
      if (up) {
        final codes = digits.codeUnits.toList();
        var i = codes.length - 1;
        while (i >= 0 && codes[i] == 0x39) {
          codes[i] = 0x30;
          i--;
        }
        if (i >= 0) {
          codes[i]++;
          digits = String.fromCharCodes(codes);
        } else {
          digits = '1${String.fromCharCodes(codes)}';
          point += 1;
        }
      }
    }
    String ip;
    String fp;
    if (point <= 0) {
      ip = '0';
      fp = ''.padRight(-point, '0') + digits;
    } else {
      ip = digits.substring(0, math.min(point, digits.length)).padRight(point, '0');
      fp = point < digits.length ? digits.substring(point) : '';
    }
    ip = ip.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (fp.length < decimals) fp = fp.padRight(decimals, '0');
    if (fp.length > decimals) fp = fp.substring(0, decimals);
    return (int: ip, frac: fp);
  }

  // ── Числа ──

  static String _formatNumber(_Section sec, double a, SheetLocale loc) {
    final t = sec.t;
    if (t.any((x) => x.k == _general)) {
      final out = StringBuffer();
      for (final x in t) {
        if (x.k == _general) {
          out.write(generalText(a, loc));
        } else if (x.k == _lit) {
          out.write(x.s);
        }
      }
      return out.toString();
    }
    final digitsAny = t.any((x) => x.k == _digit);
    if (!digitsAny) {
      // Только подписи («"нет"»), «@» у числа — «Общий».
      if (t.any((x) => x.k == _text)) return generalText(a, loc);
      final out = StringBuffer();
      for (final x in t) {
        if (x.k == _lit) out.write(x.s);
        if (x.k == _pct) out.write('%');
      }
      return out.toString();
    }
    var v = a;
    for (final x in t) {
      if (x.k == _pct) v *= 100;
    }
    final expAt = t.indexWhere((x) => x.k == _exp);
    final slashAt = _fractionSlash(t);
    if (slashAt >= 0 && expAt < 0) return _formatFraction(t, slashAt, v, loc);

    // Запятые: между цифрами целой части — разряды, после последней цифры —
    // деление на 1000 (каждая).
    final end = expAt >= 0 ? expAt : t.length;
    var pointAt = -1;
    for (var i = 0; i < end; i++) {
      if (t[i].k == _point) {
        pointAt = i;
        break;
      }
    }
    final intEnd = pointAt >= 0 ? pointAt : end;
    var grouping = false;
    final skip = <int>{};
    var lastDigit = -1;
    for (var i = 0; i < end; i++) {
      if (t[i].k == _digit) lastDigit = i;
    }
    for (var i = 0; i < end; i++) {
      if (t[i].k != _comma) continue;
      final before = t.sublist(0, i).any((x) => x.k == _digit);
      final afterInt = i < intEnd && t.sublist(i + 1, intEnd).any((x) => x.k == _digit);
      if (before && afterInt) {
        grouping = true;
        skip.add(i);
      } else if (before && i > lastDigit) {
        v /= 1000;
        skip.add(i);
      } else if (before) {
        skip.add(i);
      }
    }

    if (expAt >= 0) return _formatExp(t, expAt, pointAt, v, loc, skip);

    var decimals = 0;
    if (pointAt >= 0) {
      for (var i = pointAt + 1; i < end; i++) {
        if (t[i].k == _digit) decimals++;
      }
    }
    final r = roundDecimal(v, decimals);
    final out = StringBuffer();
    _writeInt(out, t, 0, intEnd, r.int, grouping ? loc.group : null, skip);
    if (pointAt >= 0) {
      out.write(loc.decimal);
      _writeFrac(out, t, pointAt + 1, end, r.frac, skip);
    }
    for (var i = end; i < t.length; i++) {
      _writeLit(out, t[i]);
    }
    return out.toString();
  }

  static void _writeLit(StringBuffer out, _T x) {
    switch (x.k) {
      case _lit:
        out.write(x.s);
      case _pct:
        out.write('%');
      case _point:
        out.write('.');
      case _slash:
        out.write('/');
    }
  }

  /// Целая часть [digits] по местам цифр t[from..to): справа налево, лишние
  /// цифры — в самое левое место; «0» — ноль, «?» — пробел, «#» — ничего.
  static void _writeInt(StringBuffer out, List<_T> t, int from, int to, String digits, String? group, Set<int> skip) {
    final slots = <int>[];
    for (var i = from; i < to; i++) {
      if (t[i].k == _digit) slots.add(i);
    }
    final d = digits == '0' ? '' : digits;
    if (slots.isEmpty) {
      for (var i = from; i < to; i++) {
        if (!skip.contains(i)) _writeLit(out, t[i]);
      }
      if (d.isNotEmpty) out.write(d);
      return;
    }
    final first = slots.first;
    final last = slots.last;
    var interleaved = false;
    for (var i = first; i < last; i++) {
      if (t[i].k == _lit || t[i].k == _pct) interleaved = true;
    }
    for (var i = from; i < first; i++) {
      if (!skip.contains(i)) _writeLit(out, t[i]);
    }
    if (!interleaved) {
      final buf = StringBuffer();
      final n = slots.length;
      if (d.length > n) buf.write(d.substring(0, d.length - n));
      for (var k = 0; k < n; k++) {
        final j = d.length - (n - k);
        if (j >= 0) {
          buf.write(d[j]);
        } else {
          final s = t[slots[k]].s;
          if (s == '0') buf.write('0');
          if (s == '?') buf.write(' ');
        }
      }
      var s = buf.toString();
      if (group != null) s = _group(s, group);
      out.write(s);
    } else {
      // «000-00-00», «(###) ###-####»: цифры по местам справа налево.
      final parts = <String>[];
      var j = d.length - 1;
      for (var i = last; i >= first; i--) {
        final x = t[i];
        if (x.k == _digit) {
          if (i == first) {
            parts.add(j >= 0 ? d.substring(0, j + 1) : (x.s == '0' ? '0' : (x.s == '?' ? ' ' : '')));
            j = -1;
          } else if (j >= 0) {
            parts.add(d[j]);
            j--;
          } else {
            parts.add(x.s == '0' ? '0' : (x.s == '?' ? ' ' : ''));
          }
        } else if (!skip.contains(i)) {
          final b = StringBuffer();
          _writeLit(b, x);
          parts.add(b.toString());
        }
      }
      out.write(parts.reversed.join());
    }
    for (var i = last + 1; i < to; i++) {
      if (!skip.contains(i)) _writeLit(out, t[i]);
    }
  }

  static String _group(String s, String sep) {
    // Разряды — только у цифр; ведущие пробелы «?» не трогаем.
    final m = RegExp(r'^(\D*)(\d+)$').firstMatch(s);
    if (m == null) return s;
    final digits = m.group(2)!;
    if (digits.length <= 3) return s;
    final b = StringBuffer(m.group(1)!);
    final head = digits.length % 3;
    if (head > 0) b.write(digits.substring(0, head));
    for (var i = head; i < digits.length; i += 3) {
      if (i > 0) b.write(sep);
      b.write(digits.substring(i, i + 3));
    }
    return b.toString();
  }

  /// Дробная часть: «0» — цифра всегда, «#» — без хвостовых нулей, «?» —
  /// хвостовые нули пробелами.
  static void _writeFrac(StringBuffer out, List<_T> t, int from, int to, String frac, Set<int> skip) {
    var lastNonZero = -1;
    for (var i = 0; i < frac.length; i++) {
      if (frac.codeUnitAt(i) != 0x30) lastNonZero = i;
    }
    var k = 0;
    for (var i = from; i < to; i++) {
      final x = t[i];
      if (x.k == _digit) {
        final ch = k < frac.length ? frac[k] : '0';
        if (x.s == '0' || k <= lastNonZero) {
          out.write(ch);
        } else if (x.s == '?') {
          out.write(' ');
        }
        k++;
      } else if (!skip.contains(i)) {
        _writeLit(out, x);
      }
    }
  }

  static String _formatExp(List<_T> t, int expAt, int pointAt, double v, SheetLocale loc, Set<int> skip) {
    final intEnd = pointAt >= 0 ? pointAt : expAt;
    var nInt = 0;
    var hashInt = false;
    for (var i = 0; i < intEnd; i++) {
      if (t[i].k == _digit) {
        nInt++;
        if (t[i].s == '#') hashInt = true;
      }
    }
    if (nInt == 0) nInt = 1;
    var decimals = 0;
    if (pointAt >= 0) {
      for (var i = pointAt + 1; i < expAt; i++) {
        if (t[i].k == _digit) decimals++;
      }
    }
    final engineering = nInt > 1 && hashInt;
    var e = 0;
    if (v != 0) {
      final e10 = _exp10(v);
      e = engineering ? (e10 / nInt).floor() * nInt : e10 - (nInt - 1);
    }
    var r = roundDecimal(v / math.pow(10.0, e), decimals);
    if (v != 0 && r.int.length > (engineering ? nInt : nInt)) {
      e += engineering ? nInt : 1;
      r = roundDecimal(v / math.pow(10.0, e), decimals);
    }
    final out = StringBuffer();
    _writeInt(out, t, 0, intEnd, r.int, null, skip);
    if (pointAt >= 0) {
      out.write(loc.decimal);
      _writeFrac(out, t, pointAt + 1, expAt, r.frac, skip);
    }
    final x = t[expAt];
    var expDigits = 0;
    var i = expAt + 1;
    while (i < t.length && t[i].k == _digit) {
      expDigits++;
      i++;
    }
    out
      ..write(x.s[0])
      ..write(e < 0 ? '-' : (x.s[1] == '+' ? '+' : ''))
      ..write(e.abs().toString().padLeft(math.max(1, expDigits), '0'));
    for (; i < t.length; i++) {
      _writeLit(out, t[i]);
    }
    return out.toString();
  }

  /// «/» дроби — между цифрами (или «?/8» — с числом знаменателя); -1 — нет.
  static int _fractionSlash(List<_T> t) {
    for (var i = 1; i < t.length - 1; i++) {
      if (t[i].k != _slash) continue;
      if (t[i - 1].k != _digit) continue;
      final n = t[i + 1];
      if (n.k == _digit || (n.k == _lit && RegExp(r'^\d$').hasMatch(n.s))) return i;
    }
    return -1;
  }

  static String _formatFraction(List<_T> t, int slash, double v, SheetLocale loc) {
    // Числитель — цифры прямо перед «/», целая часть — цифры до них.
    var numStart = slash;
    while (numStart > 0 && t[numStart - 1].k == _digit) {
      numStart--;
    }
    var intEnd = numStart;
    while (intEnd > 0 && t[intEnd - 1].k != _digit) {
      intEnd--;
    }
    final hasInt = intEnd > 0;
    var denEnd = slash + 1;
    var fixedDen = '';
    while (denEnd < t.length &&
        (t[denEnd].k == _digit || (t[denEnd].k == _lit && RegExp(r'^\d$').hasMatch(t[denEnd].s)))) {
      if (t[denEnd].k == _lit) fixedDen += t[denEnd].s;
      denEnd++;
    }
    final denSlots = denEnd - slash - 1;
    var ip = hasInt ? v.floorToDouble() : 0.0;
    final f = v - ip;
    int num;
    int den;
    final fixed = fixedDen.isNotEmpty && fixedDen.length == denSlots ? int.tryParse(fixedDen) : null;
    if (fixed != null && fixed > 0) {
      den = fixed;
      num = (f * den).round();
    } else {
      final maxDen = math.min(9999, math.pow(10, math.max(1, denSlots)).toInt() - 1);
      den = 1;
      num = f.round();
      var best = (f - num).abs();
      for (var d = 2; d <= maxDen && best > 1e-12; d++) {
        final n = (f * d).round();
        final err = (f - n / d).abs();
        if (err < best - 1e-12) {
          best = err;
          num = n;
          den = d;
        }
      }
    }
    if (hasInt && num == den) {
      ip += 1;
      num = 0;
    }
    final out = StringBuffer();
    if (hasInt) {
      final ipStr = ip.toInt().toString();
      _writeInt(out, t, 0, intEnd, ip == 0 && num != 0 ? '0' : ipStr, null, const {});
      if (ip == 0 && num == 0) return '0';
      if (num == 0) return out.toString().trimRight();
    } else if (num == 0) {
      // Без целой части: «0/1» Excel показывает как «0».
      return '0';
    }
    for (var i = intEnd; i < numStart; i++) {
      _writeLit(out, t[i]);
    }
    final ns = num.toString();
    final numSlots = slash - numStart;
    out
      ..write(ns.padLeft(numSlots))
      ..write('/')
      ..write(fixed != null ? fixedDen : den.toString().padRight(denSlots));
    for (var i = denEnd; i < t.length; i++) {
      _writeLit(out, t[i]);
    }
    return out.toString();
  }

  // ── Даты ──

  static String _formatDate(_Section sec, double v, SheetLocale loc, bool date1904) {
    final names = sec.lang != null ? SheetLocale.of(sec.lang!) : loc;
    var t = sec.t;
    if (sec.sysDate) t = _section(loc.longDate).t;
    if (sec.sysTime) t = _section(loc.longTime).t;
    var frac = 0;
    var hour12 = false;
    var withDay = false;
    for (final x in t) {
      if (x.k == _date && x.s == 'f') frac = math.max(frac, x.n);
      if (x.k == _ampm) hour12 = true;
      if (x.k == _date && x.s == 'd' && x.n <= 2) withDay = true;
    }
    final p = ExcelDate.parts(v, date1904: date1904, fracDigits: frac);
    if (p == null) return '########';
    final out = StringBuffer();
    String two(int n) => n.toString().padLeft(2, '0');
    for (final x in t) {
      switch (x.k) {
        case _lit:
          out.write(x.s);
        case _ampm:
          final pm = p.hour >= 12;
          if (x.s.length == 3) {
            final ap = pm ? 'P' : 'A';
            out.write(x.s[0] == x.s[0].toLowerCase() ? ap.toLowerCase() : ap);
          } else {
            final s = names.ampm(pm);
            out.write(x.s[0] == 'a' || x.s[0] == 'p' ? s.toLowerCase() : s);
          }
        case _elapsed:
          final total = p.totalSeconds;
          final n = switch (x.s) {
            'h' => total ~/ 3600,
            'm' => total ~/ 60,
            _ => total,
          };
          out.write(n.toString().padLeft(x.n, '0'));
        case _date:
          switch (x.s) {
            case 'y':
              out.write(x.n <= 2 ? two(p.year % 100) : p.year.toString().padLeft(4, '0'));
            case 'M':
              out.write(
                x.n == 1
                    ? '${p.month}'
                    : x.n == 2
                    ? two(p.month)
                    : names.month(p.month, x.n, withDay: withDay),
              );
            case 'd':
              out.write(
                x.n == 1
                    ? '${p.day}'
                    : x.n == 2
                    ? two(p.day)
                    : names.weekday(p.weekday, short: x.n == 3),
              );
            case 'h':
              var h = p.hour;
              if (hour12) {
                h %= 12;
                if (h == 0) h = 12;
              }
              out.write(x.n >= 2 ? two(h) : '$h');
            case 'i':
              out.write(x.n >= 2 ? two(p.minute) : '${p.minute}');
            case 's':
              out.write(x.n >= 2 ? two(p.second) : '${p.second}');
            case 'f':
              out
                ..write(loc.decimal)
                ..write(p.fraction.toString().padLeft(frac, '0').substring(0, x.n));
          }
      }
    }
    return out.toString();
  }
}

/// Даты Excel: число дней от 0 января 1900 года (с несуществующим
/// 29.02.1900 — наследство Lotus 1-2-3) или от 1 января 1904 (старые Mac).
class ExcelDate {
  ExcelDate._();

  /// Части даты и времени числа [v]; null — вне 1900–9999 (Excel: «####»).
  static ({
    int year,
    int month,
    int day,
    int weekday,
    int hour,
    int minute,
    int second,
    int fraction,
    int totalSeconds,
  })?
  parts(double v, {bool date1904 = false, int fracDigits = 0}) {
    if (v < 0 || v > 2958466) return null;
    final scale = math.pow(10, fracDigits).toInt();
    // До 14 значащих цифр, затем округление: 61,25 с не становятся 61,2499…
    final units = double.parse((v * 86400 * scale).toStringAsPrecision(14)).round();
    final perDay = 86400 * scale;
    final days = units ~/ perDay;
    final rem = units - days * perDay;
    final secs = rem ~/ scale;
    final totalSeconds = units ~/ scale;
    int y, m, d, wd;
    if (date1904) {
      final dt = DateTime.utc(1904, 1, 1).add(Duration(days: days));
      y = dt.year;
      m = dt.month;
      d = dt.day;
      wd = dt.weekday;
    } else if (days == 0) {
      // «0 января 1900» — так Excel показывает время без даты.
      y = 1900;
      m = 1;
      d = 0;
      wd = DateTime.saturday;
    } else if (days == 60) {
      y = 1900;
      m = 2;
      d = 29;
      wd = DateTime.wednesday;
    } else {
      final dt = days < 60
          ? DateTime.utc(1899, 12, 31).add(Duration(days: days))
          : DateTime.utc(1899, 12, 30).add(Duration(days: days));
      y = dt.year;
      m = dt.month;
      d = dt.day;
      wd = dt.weekday;
    }
    if (y > 9999) return null;
    return (
      year: y,
      month: m,
      day: d,
      weekday: wd,
      hour: secs ~/ 3600,
      minute: (secs ~/ 60) % 60,
      second: secs % 60,
      fraction: rem - secs * scale,
      totalSeconds: totalSeconds,
    );
  }

  /// Дата и время → число Excel (для ISO-дат XLSX «t="d"» и ODS).
  static double serial(DateTime d, {bool date1904 = false}) {
    final utc = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
    final base = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
    var v = utc.difference(base).inMilliseconds / 86400000.0;
    if (!date1904 && v < 61) v -= 1;
    return v;
  }
}

/// Палитра Excel по умолчанию (индексы цветов BIFF8: indexed="10" — красный).
/// 64 и 65 — «системные» цвета текста и фона (авто).
const excelPalette = <int>[
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, //
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, //
  0xFF800000, 0xFF008000, 0xFF000080, 0xFF808000, 0xFF800080, 0xFF008080, 0xFFC0C0C0, 0xFF808080, //
  0xFF9999FF, 0xFF993366, 0xFFFFFFCC, 0xFFCCFFFF, 0xFF660066, 0xFFFF8080, 0xFF0066CC, 0xFFCCCCFF, //
  0xFF000080, 0xFFFF00FF, 0xFFFFFF00, 0xFF00FFFF, 0xFF800080, 0xFF800000, 0xFF008080, 0xFF0000FF, //
  0xFF00CCFF, 0xFFCCFFFF, 0xFFCCFFCC, 0xFFFFFF99, 0xFF99CCFF, 0xFFFF99CC, 0xFFCC99FF, 0xFFFFCC99, //
  0xFF3366FF, 0xFF33CCCC, 0xFF99CC00, 0xFFFFCC00, 0xFFFF9900, 0xFFFF6600, 0xFF666699, 0xFF969696, //
  0xFF003366, 0xFF339966, 0xFF003300, 0xFF333300, 0xFF993300, 0xFF993366, 0xFF333399, 0xFF333333, //
];

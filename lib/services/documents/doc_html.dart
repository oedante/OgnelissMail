// lib/services/documents/doc_html.dart
// Текстовый документ (DOCX, ODT, RTF) → HTML для окна письма (1.11.x,
// предпросмотр документов, план владельца 04.11.2026).
//
// Три читателя разбирают свои форматы в одну модель — абзацы с фрагментами
// текста, таблицы, картинки, сноски ([DocBlock]), а HTML из неё пишет
// [DocHtml.render]. Так все три формата выглядят одинаково и проходят одни и
// те же проверки, а правила вывода — в одном месте:
//  · только встроенные стили и теги, которые оставляет HtmlSanitizer
//    (sanitizeKeepingStyles); блоков <style> и классов нет — на компьютере
//    документ рисуют виджеты (mail_native_body.dart), они <style> не читают;
//  · шрифт приложения: font-family не задаётся (кроме monospace для
//    Courier-подобных), цвет «авто» — тоже: работают тёмная тема и шрифт
//    приложения; явные цвета и маркер документа остаются;
//  · размер шрифта — в em от «основного» размера документа (размер, которым
//    набрано больше всего текста): основной текст — обычным размером окна
//    письма, заголовки и мелкий шрифт — в тех же пропорциях, что в
//    документе. В pt пропорции ломались: документ, набранный 14 pt (так
//    пишутся служебные записки), шёл 15 px, а его заголовки 16 pt — 21 px;
//  · отступы и интервалы абзацев — в pt; большие отступы — не шире доли
//    окна (min(…, 40%)): подпись «отодвинута вправо» на 9 см и на телефоне
//    остаётся читаемой;
//  · ширины таблиц и картинок — в %, а не в px: объявленная ширина больше
//    экрана заставила бы окно письма уменьшить весь документ
//    (MailHtmlDocument.declaredWidth). У ячеек ещё и атрибут width — доля
//    колонки числом: виджеты компьютера по нему делят ширину;
//  · пустой абзац Word сохраняет высоту (<p>&nbsp;</p>);
//  · пределы ([DocBudget]): знаки текста плюс [OfficeLimits.blockWeight] за
//    абзац, ячейку и строку таблицы; дальше — «показано начало».

import 'dart:math' as math;

import '../../core/utils/symbol_fonts.dart';
import 'office_document.dart';
import 'office_package.dart';

/// Надстрочный или подстрочный текст.
enum DocVert { none, sup, sub }

/// Оформление фрагмента текста. Цвета — 0xAARRGGBB; [size] — pt, null —
/// основной размер документа.
class DocFont {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool smallCaps;
  final bool mono;
  final DocVert vert;
  final int? color;
  final int? background;
  final double? size;

  const DocFont({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.smallCaps = false,
    this.mono = false,
    this.vert = DocVert.none,
    this.color,
    this.background,
    this.size,
  });

  static const plain = DocFont();

  DocFont copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? smallCaps,
    bool? mono,
    DocVert? vert,
    int? color,
    int? background,
    double? size,
  }) => DocFont(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    smallCaps: smallCaps ?? this.smallCaps,
    mono: mono ?? this.mono,
    vert: vert ?? this.vert,
    color: color ?? this.color,
    background: background ?? this.background,
    size: size ?? this.size,
  );

  @override
  bool operator ==(Object other) =>
      other is DocFont &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.smallCaps == smallCaps &&
      other.mono == mono &&
      other.vert == vert &&
      other.color == color &&
      other.background == background &&
      other.size == size;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strike, smallCaps, mono, vert, color, background, size);
}

/// Линия рамки: толщина в pt, вид (solid, dashed, dotted, double), цвет
/// (null — чёрный, как «авто» у Word).
class DocLine {
  final double width;
  final String style;
  final int? color;
  const DocLine({this.width = 0.5, this.style = 'solid', this.color});

  String get css {
    // Тоньше точки линия не видна; толще 3 px — рамка «плакатом» на телефоне.
    final px = (width * 4 / 3).clamp(1.0, 3.0);
    final st = style == 'double' && px < 3 ? 'solid' : style;
    return '${DocHtml.num(px)}px $st ${DocHtml.hex(color ?? 0xFF000000)}';
  }
}

/// Стороны рамки абзаца или ячейки; null — линии нет.
class DocBorders {
  final DocLine? top;
  final DocLine? right;
  final DocLine? bottom;
  final DocLine? left;
  const DocBorders({this.top, this.right, this.bottom, this.left});

  static const none = DocBorders();
  bool get isEmpty => top == null && right == null && bottom == null && left == null;
}

/// Оформление абзаца. Отступы и интервалы — pt; [firstLine] < 0 — выступ
/// (висячая строка, как у пунктов списка).
class DocParaStyle {
  /// 0 — обычный абзац, 1–6 — заголовок h1–h6.
  final int heading;

  /// 'center', 'right', 'justify'; null — по левому краю (по началу строки).
  final String? align;
  final double before;
  final double after;
  final double left;
  final double right;
  final double firstLine;
  final int? background;
  final DocBorders borders;
  final bool rtl;

  /// Размер шрифта абзаца (pt) — для заголовка и высоты пустой строки;
  /// null — основной.
  final double? size;

  const DocParaStyle({
    this.heading = 0,
    this.align,
    this.before = 0,
    this.after = 0,
    this.left = 0,
    this.right = 0,
    this.firstLine = 0,
    this.background,
    this.borders = DocBorders.none,
    this.rtl = false,
    this.size,
  });

  /// Тот же стиль с другими интервалами (интервалы между абзацами одного
  /// стиля убираются, когда стиль так просит, — contextual spacing).
  DocParaStyle withSpacing({double? before, double? after}) => DocParaStyle(
    heading: heading,
    align: align,
    before: before ?? this.before,
    after: after ?? this.after,
    left: left,
    right: right,
    firstLine: firstLine,
    background: background,
    borders: borders,
    rtl: rtl,
    size: size,
  );
}

/// Строчный элемент абзаца.
sealed class DocInline {
  const DocInline();
}

/// Фрагмент текста; [href] — ссылка (уже проверенная [DocHtml.safeHref]).
class DocText extends DocInline {
  final String text;
  final DocFont font;
  final String? href;
  const DocText(this.text, [this.font = DocFont.plain, this.href]);
}

/// Картинка документа: ключ в [DocImages.map] (в HTML — `cid:ключ`),
/// размер в CSS-пикселях.
class DocPicture extends DocInline {
  final String key;
  final double? width;
  final double? height;
  final String alt;
  final String? href;
  const DocPicture(this.key, {this.width, this.height, this.alt = '', this.href});
}

/// Перевод строки внутри абзаца.
class DocBreak extends DocInline {
  const DocBreak();
}

/// Блок документа.
sealed class DocBlock {
  const DocBlock();
}

class DocPara extends DocBlock {
  final DocParaStyle style;
  final List<DocInline> inlines;

  /// Номер или маркер пункта списка («1.2.», «•») — перед текстом, шириной
  /// не меньше выступа первой строки: текст пунктов начинается ровно, как у
  /// Word с табуляцией после номера.
  final DocText? label;

  const DocPara(this.style, this.inlines, {this.label});
}

/// Горизонтальная линия: разрыв страницы или раздела ([page]) либо черта
/// перед сносками.
class DocRule extends DocBlock {
  final bool page;
  const DocRule({this.page = true});
}

class DocCell {
  final List<DocBlock> blocks;
  final int colSpan;
  final int rowSpan;
  final int? background;
  final DocBorders borders;

  /// 0 — сверху, 1 — по центру, 2 — снизу.
  final int valign;

  /// Поля ячейки, pt: сверху, справа, снизу, слева.
  final List<double> padding;

  const DocCell(
    this.blocks, {
    this.colSpan = 1,
    this.rowSpan = 1,
    this.background,
    this.borders = DocBorders.none,
    this.valign = 0,
    this.padding = const [0, 5.4, 0, 5.4],
  });
}

class DocRow {
  final List<DocCell> cells;
  const DocRow(this.cells);
}

class DocTable extends DocBlock {
  final List<DocRow> rows;

  /// Ширины колонок сетки в любых одинаковых единицах (доли); пусто — не
  /// заданы.
  final List<double> columns;

  /// Ширина таблицы, % от ширины окна (текста страницы); null — по
  /// содержимому.
  final double? widthPct;

  /// 'center', 'right'; null — слева.
  final String? align;

  const DocTable(this.rows, {this.columns = const [], this.widthPct, this.align});
}

/// Пределы текста документа (см. [OfficeLimits.maxTextWeight]). Читатель
/// спрашивает разрешение на каждый абзац, ячейку, строку и фрагмент текста;
/// как только места нет — [full], и читатель прекращает обход.
class DocBudget {
  DocBudget([this.max = OfficeLimits.maxTextWeight]);

  final int max;
  int _weight = 0;

  /// Документ не поместился: показано начало.
  bool truncated = false;

  bool get full => truncated;
  int get used => _weight;

  /// Новый абзац, ячейка или строка таблицы; false — места больше нет.
  bool block() {
    if (truncated) return false;
    _weight += OfficeLimits.blockWeight;
    if (_weight > max) {
      truncated = true;
      return false;
    }
    return true;
  }

  /// Сколько из [s] помещается (начало строки; '' — ничего).
  String text(String s) {
    if (truncated || s.isEmpty) return '';
    final left = max - _weight;
    if (s.length <= left) {
      _weight += s.length;
      return s;
    }
    truncated = true;
    var cut = left < 0 ? 0 : left;
    // Не разрезать пару суррогатов.
    if (cut > 0 && cut < s.length && _isHigh(s.codeUnitAt(cut - 1))) cut--;
    _weight = max;
    return s.substring(0, cut);
  }

  static bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
}

/// Картинки документа: имя части (или своё имя у RTF) → ключ `imgN`.
/// Ключи — строчными: окно письма сравнивает cid без учёта регистра
/// (MailHtmlDocument._normCid).
class DocImages {
  final Map<String, String> map = {};
  final Map<String, String?> _byName = {};

  /// Ключ картинки [name]; [load] вызывается один раз. null — картинку не
  /// показать (формат, размер, нет такой части).
  String? add(String name, OfficeImage? Function() load) {
    if (_byName.containsKey(name)) return _byName[name];
    OfficeImage? img;
    try {
      img = load();
    } on OfficeDocException catch (e) {
      // Общий предел прочитанного — это предел документа; прочее — без
      // картинки.
      if (e.kind == OfficeDocError.tooLarge) rethrow;
      img = null;
    }
    if (img == null) {
      _byName[name] = null;
      return null;
    }
    final key = 'img${map.length + 1}';
    map[key] = img.dataUri;
    _byName[name] = key;
    return key;
  }
}

/// Номера пунктов списков и сносок.
class DocNumbers {
  DocNumbers._();

  /// Русские буквы нумерации Word (russianLower): без ё, й, ъ, ы, ь.
  static const _ru = 'абвгдежзиклмнопрстуфхцчшщэюя';

  /// [n] в формате [fmt]: decimal, decimalZero, lowerLetter, upperLetter,
  /// lowerRoman, upperRoman, russianLower, russianUpper, none. [sync] —
  /// после «z» идут «aa», «bb» (как у Word), иначе «aa», «ab» (ODF).
  static String format(int n, String fmt, {bool sync = true}) {
    switch (fmt) {
      case 'none':
      case 'bullet':
        return '';
      case 'decimalZero':
        return n < 10 && n >= 0 ? '0$n' : '$n';
      case 'lowerRoman':
        return roman(n).toLowerCase();
      case 'upperRoman':
        return roman(n);
      case 'lowerLetter':
        return letters(n, 'abcdefghijklmnopqrstuvwxyz', sync: sync);
      case 'upperLetter':
        return letters(n, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', sync: sync);
      case 'russianLower':
        return letters(n, _ru, sync: sync);
      case 'russianUpper':
        return letters(n, _ru.toUpperCase(), sync: sync);
      default:
        return '$n';
    }
  }

  static String roman(int n) {
    if (n <= 0 || n >= 4000) return '$n';
    const v = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const s = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    final out = StringBuffer();
    var x = n;
    for (var i = 0; i < v.length; i++) {
      while (x >= v[i]) {
        out.write(s[i]);
        x -= v[i];
      }
    }
    return out.toString();
  }

  static String letters(int n, String abc, {bool sync = true}) {
    if (n <= 0) return '$n';
    final k = abc.length;
    if (sync) {
      // Ограничение повтора: номер 100 000 не должен стать строкой из 4000 букв.
      final times = math.min((n - 1) ~/ k + 1, 8);
      return abc[(n - 1) % k] * times;
    }
    final out = <String>[];
    var x = n;
    while (x > 0 && out.length < 8) {
      x--;
      out.add(abc[x % k]);
      x ~/= k;
    }
    return out.reversed.join();
  }
}

class DocHtml {
  DocHtml._();

  /// Число для CSS: без лишних нулей («12», «10.5», «0.875»).
  static String num(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e9) return v.round().toString();
    var s = v.toStringAsFixed(3);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  /// Цвет 0xAARRGGBB → «#rrggbb».
  static String hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Цвет из «RRGGBB» или «#RRGGBB»; null — не цвет («auto», мусор).
  static int? parseHex(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 3) v = v.split('').map((c) => '$c$c').join();
    if (v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : 0xFF000000 | n;
  }

  /// Цвета маркера Word (w:highlight) — те же имена в RTF и ODF не нужны.
  static const highlight = <String, int>{
    'black': 0xFF000000,
    'blue': 0xFF0000FF,
    'cyan': 0xFF00FFFF,
    'green': 0xFF00FF00,
    'magenta': 0xFFFF00FF,
    'red': 0xFFFF0000,
    'yellow': 0xFFFFFF00,
    'white': 0xFFFFFFFF,
    'darkBlue': 0xFF000080,
    'darkCyan': 0xFF008080,
    'darkGreen': 0xFF008000,
    'darkMagenta': 0xFF800080,
    'darkRed': 0xFF800000,
    'darkYellow': 0xFF808000,
    'darkGray': 0xFF808080,
    'lightGray': 0xFFC0C0C0,
  };

  /// Ссылка, которую можно показать: только http, https, mailto (окно письма
  /// откроет её через LinkOpener с проверкой на фишинг). Внутренние ссылки
  /// документа (#закладка), file:, javascript: и прочее — null: текст
  /// остаётся, ссылки нет.
  static String? safeHref(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    final low = v.toLowerCase();
    if (!(low.startsWith('http://') || low.startsWith('https://') || low.startsWith('mailto:'))) return null;
    if (v.length > 4096) return null;
    // Пробелы и кавычки в адресе — кодами: атрибут не рвётся.
    return v.replaceAll(' ', '%20').replaceAll('"', '%22');
  }

  /// Поле HYPERLINK (Word, RTF): «HYPERLINK "https://…" \o "подсказка"» →
  /// адрес; «HYPERLINK \l "закладка"» (ссылка внутрь документа) — null.
  static String? fieldLink(String instr) {
    final m = RegExp(r'^\s*HYPERLINK\b(.*)$', caseSensitive: false, dotAll: true).firstMatch(instr);
    if (m == null) return null;
    final tokens = [
      for (final t in RegExp(r'"([^"]*)"|(\S+)').allMatches(m.group(1)!))
        (value: t.group(1) ?? t.group(2)!, key: t.group(2)?.startsWith(r'\') ?? false),
    ];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.key) {
        // У ключей \l (закладка), \o (подсказка), \t (окно) есть значение —
        // это не адрес; \m, \n — без значения.
        final k = t.value.toLowerCase();
        if (k == r'\l' || k == r'\o' || k == r'\t') i++;
        continue;
      }
      return safeHref(t.value);
    }
    return null;
  }

  /// Знак символьного шрифта (Symbol, Wingdings) — обычным знаком Unicode;
  /// [font] — имя шрифта текста. Знаки из области частного использования
  /// (U+F020–U+F0FF) без символьного шрифта — как у Word-маркеров: Symbol
  /// для «», остальное — Wingdings.
  static String symbols(String text, String? font) {
    final f = (font ?? '').toLowerCase();
    if (f.contains('wingdings')) return SymbolFonts.map(text, SymbolFont.wingdings);
    if (f.contains('symbol')) return SymbolFonts.map(text, SymbolFont.symbol);
    if (!_hasPua(text)) return text;
    final out = StringBuffer();
    for (final r in text.runes) {
      if (r >= 0xF020 && r <= 0xF0FF) {
        final ch = String.fromCharCode(r);
        final m = r == 0xF0B7 ? '•' : SymbolFonts.map(ch, SymbolFont.wingdings);
        out.write(m == ch ? SymbolFonts.map(ch, SymbolFont.symbol) : m);
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  static bool _hasPua(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0xF020 && c <= 0xF0FF) return true;
    }
    return false;
  }

  /// Маркер пункта списка: знак символьного шрифта — обычным знаком;
  /// «o» (так Word шрифтом Courier рисует пустой кружок) — «◦»; знак из
  /// области частного использования, которого нет в таблицах, — «•».
  static String bullet(String raw, String? font) {
    // «o» без точки или скобки — всегда кружок (у готового номера RTF шрифт
    // Courier бывает потерян): буква номером пункта так не пишется.
    if (raw == 'o') return '◦';
    var s = symbols(raw, font);
    if (_hasPua(s)) s = s.replaceAll(RegExp('[\uF020-\uF0FF]'), '•');
    return s.trim().isEmpty ? '•' : s;
  }

  static String escape(String s) {
    final out = StringBuffer();
    var spaces = 0;
    void flushSpaces(bool atEnd) {
      // Несколько пробелов подряд (выравнивание пробелами в Word) HTML
      // схлопнул бы в один: все, кроме последнего, — неразрывные.
      if (spaces == 0) return;
      for (var i = 0; i < spaces - 1; i++) {
        out.write('\u00A0');
      }
      out.write(atEnd && spaces > 1 ? '\u00A0' : ' ');
      spaces = 0;
    }

    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x20) {
        spaces++;
        continue;
      }
      flushSpaces(false);
      switch (c) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0x09:
        case 0x0A:
        case 0x0D:
          out.write(' ');
        default:
          if (c < 0x20 || c == 0x7F || c == 0xFFFE || c == 0xFFFF) continue;
          // Одиночные суррогаты (испорченный \u в RTF) — знак замены.
          if (c >= 0xD800 && c <= 0xDBFF) {
            if (i + 1 < s.length) {
              final d = s.codeUnitAt(i + 1);
              if (d >= 0xDC00 && d <= 0xDFFF) {
                out.writeCharCode(c);
                out.writeCharCode(d);
                i++;
                continue;
              }
            }
            out.write('\uFFFD');
            continue;
          }
          if (c >= 0xDC00 && c <= 0xDFFF) {
            out.write('\uFFFD');
            continue;
          }
          out.writeCharCode(c);
      }
    }
    flushSpaces(true);
    return out.toString();
  }

  static String attr(String s) =>
      escape(s).replaceAll('"', '&quot;').replaceAll("'", '&#39;').replaceAll('\u00A0', ' ');

  /// Отступ в pt; большой — не больше доли ширины окна.
  static String _len(double pt) {
    // Десятые доли пункта: «0,111 in» у LibreOffice — 8 pt, а не 7.992pt.
    final v = num((pt * 10).roundToDouble() / 10);
    if (pt.abs() <= 36) return '${v}pt';
    return pt > 0 ? 'min(${v}pt,40%)' : 'max(${v}pt,-40%)';
  }

  /// Основной размер шрифта: каким набрано больше всего текста.
  static double? _baseSize(List<DocBlock> blocks) {
    final count = <double, int>{};
    void walk(List<DocBlock> list, int depth) {
      if (depth > OfficeLimits.maxDepth) return;
      for (final b in list) {
        switch (b) {
          case DocPara():
            for (final i in b.inlines) {
              if (i is DocText && i.font.size != null && i.font.vert == DocVert.none) {
                count[i.font.size!] = (count[i.font.size!] ?? 0) + i.text.length;
              }
            }
          case DocTable():
            for (final r in b.rows) {
              for (final c in r.cells) {
                walk(c.blocks, depth + 1);
              }
            }
          case DocRule():
            break;
        }
      }
    }

    walk(blocks, 0);
    double? best;
    var most = 0;
    count.forEach((size, n) {
      if (n > most || (n == most && best != null && size < best!)) {
        best = size;
        most = n;
      }
    });
    return best;
  }

  /// HTML документа: [blocks], под чертой — [notes] (сноски) и
  /// [comments] (примечания); [header] и [footer] — колонтитулы серым
  /// вверху и внизу (1.15.1).
  static OfficeTextDoc render(
    List<DocBlock> blocks, {
    List<DocBlock> notes = const [],
    List<DocBlock> header = const [],
    List<DocBlock> footer = const [],
    List<DocBlock> comments = const [],
    Map<String, String> images = const {},
    bool truncated = false,
  }) {
    final base = _baseSize([...blocks, ...notes]);
    final w = _Writer(base);
    if (header.isNotEmpty) {
      w.out.write('<div style="color:#808080;font-size:85%;border-bottom:1px solid #d0d0d0;margin-bottom:12pt">');
      w.blocks(header, 0);
      w.out.write('</div>');
    }
    w.blocks(blocks, 0);
    if (notes.isNotEmpty) {
      w.out.write('<hr style="border:0;border-top:1px solid #a0a0a0;width:33%;margin:12pt auto 6pt 0">');
      w.blocks(notes, 0);
    }
    if (comments.isNotEmpty) {
      w.out.write('<div style="background:#fff8d6;color:#303030;border-left:3px solid #e0b000;'
          'padding:4pt 8pt;margin:12pt 0">');
      w.blocks(comments, 0);
      w.out.write('</div>');
    }
    if (footer.isNotEmpty) {
      w.out.write('<div style="color:#808080;font-size:85%;border-top:1px solid #d0d0d0;margin-top:12pt">');
      w.blocks(footer, 0);
      w.out.write('</div>');
    }
    return OfficeTextDoc(w.out.toString(), images: Map.unmodifiable(images), truncated: truncated);
  }
}

class _Writer {
  _Writer(this.base);

  final double? base;
  final out = StringBuffer();

  void blocks(List<DocBlock> list, int depth) {
    if (depth > OfficeLimits.maxDepth) return;
    for (final b in list) {
      switch (b) {
        case DocPara():
          para(b);
        case DocTable():
          table(b, depth);
        case DocRule():
          out.write(
            b.page
                ? '<hr style="border:0;border-top:1px dashed #b0b0b0;margin:12pt 0">'
                : '<hr style="border:0;border-top:1px solid #a0a0a0;margin:12pt 0">',
          );
      }
    }
  }

  String _borders(DocBorders b) {
    final s = <String>[];
    if (b.top != null) s.add('border-top:${b.top!.css}');
    if (b.right != null) s.add('border-right:${b.right!.css}');
    if (b.bottom != null) s.add('border-bottom:${b.bottom!.css}');
    if (b.left != null) s.add('border-left:${b.left!.css}');
    return s.join(';');
  }

  void para(DocPara p) {
    final st = p.style;
    final h = st.heading.clamp(0, 6);
    final tag = h == 0 ? 'p' : 'h$h';
    final zero = st.before == 0 && st.right == 0 && st.after == 0 && st.left == 0;
    final css = <String>[
      zero ? 'margin:0' : 'margin:${_m(st.before)} ${_m(st.right)} ${_m(st.after)} ${_m(st.left)}',
      if (st.firstLine != 0) 'text-indent:${DocHtml._len(st.firstLine)}',
      if (st.align != null) 'text-align:${st.align}',
      if (st.background != null) 'background-color:${DocHtml.hex(st.background!)}',
      if (!st.borders.isEmpty) ...[_borders(st.borders), 'padding:1pt 2pt'],
    ];
    final blockSize = st.size ?? base;
    if (h > 0) {
      // Заголовок — своим размером и без жирности тега: жирность и цвет — у
      // фрагментов текста, как в документе (у Word 2013+ «Заголовок 1» не
      // жирный).
      css.add('font-size:${_em(blockSize, base) ?? '1em'}');
      css.add('font-weight:normal');
    } else {
      final em = _em(blockSize, base);
      if (em != null) css.add('font-size:$em');
    }
    out.write('<$tag style="${css.join(';')}"${st.rtl ? ' dir="rtl"' : ''}>');
    final label = p.label;
    var visible = false;
    if (label != null && label.text.isNotEmpty) {
      final lcss = _font(label.font, blockSize, mono: false);
      final hang = st.firstLine < 0 ? -st.firstLine : 0.0;
      final text = DocHtml.escape(label.text);
      if (hang > 0) {
        // Номер — в рамке шириной с выступ, текст — от левого отступа, как
        // после табуляции у Word; номер длиннее выступа отодвигает текст на
        // пробел. text-indent наследуется — в рамке он не нужен.
        out.write(
          '<span style="display:inline-block;min-width:${DocHtml.num(hang)}pt;text-indent:0'
          '${lcss.isEmpty ? '' : ';$lcss'}">$text\u00A0</span>',
        );
      } else {
        out.write(lcss.isEmpty ? '$text ' : '<span style="$lcss">$text</span> ');
      }
      visible = true;
    }
    if (inlines(p.inlines, blockSize)) visible = true;
    if (!visible) out.write('&nbsp;');
    out.write('</$tag>');
  }

  static String _m(double pt) => pt == 0 ? '0' : DocHtml._len(pt);

  /// Размер [size] относительно [of] в em; null — тот же.
  String? _em(double? size, double? of) {
    final s = size ?? base;
    final o = of ?? base;
    if (s == null || o == null || o <= 0) return null;
    // Пределы: крупнее 2,5 раза (титульный лист 28 pt и больше) на экране
    // телефона — две-три буквы в строке; мельче 0,5 — не прочитать.
    final r = (s / o).clamp(0.5, 2.5);
    if ((r - 1).abs() < 0.02) return null;
    return '${DocHtml.num(r)}em';
  }

  String _font(DocFont f, double? blockSize, {bool mono = true}) {
    final s = <String>[];
    if (f.bold) s.add('font-weight:bold');
    if (f.italic) s.add('font-style:italic');
    if (f.underline || f.strike) {
      s.add('text-decoration:${[if (f.underline) 'underline', if (f.strike) 'line-through'].join(' ')}');
    }
    if (f.color != null) s.add('color:${DocHtml.hex(f.color!)}');
    if (f.background != null) s.add('background-color:${DocHtml.hex(f.background!)}');
    if (f.vert == DocVert.none) {
      final em = _em(f.size, blockSize);
      if (em != null) s.add('font-size:$em');
    }
    if (f.smallCaps) s.add('font-variant:small-caps');
    if (mono && f.mono) s.add('font-family:monospace');
    return s.join(';');
  }

  /// Строчные элементы; true — показано что-то видимое.
  bool inlines(List<DocInline> list, double? blockSize) {
    var visible = false;
    String? href;
    String? css;
    DocVert vert = DocVert.none;
    var spanOpen = false;

    void closeSpan() {
      if (spanOpen) out.write('</span>');
      if (vert != DocVert.none) out.write(vert == DocVert.sup ? '</sup>' : '</sub>');
      spanOpen = false;
      vert = DocVert.none;
      css = null;
    }

    void setLink(String? to) {
      if (to == href) return;
      closeSpan();
      if (href != null) out.write('</a>');
      href = to;
      if (to != null) out.write('<a href="${DocHtml.attr(to)}">');
    }

    for (final i in list) {
      switch (i) {
        case DocText():
          if (i.text.isEmpty) continue;
          setLink(i.href);
          final c = _font(i.font, blockSize);
          if (c != css || i.font.vert != vert) {
            closeSpan();
            vert = i.font.vert;
            if (vert != DocVert.none) out.write(vert == DocVert.sup ? '<sup>' : '<sub>');
            css = c;
            if (c.isNotEmpty) {
              out.write('<span style="$c">');
              spanOpen = true;
            }
          }
          out.write(DocHtml.escape(i.text));
          if (i.text.trim().isNotEmpty) visible = true;
        case DocBreak():
          out.write('<br>');
        case DocPicture():
          closeSpan();
          setLink(i.href);
          final wh = [
            if (i.width != null && i.width! > 0) 'width="${i.width!.round()}"',
            if (i.height != null && i.height! > 0) 'height="${i.height!.round()}"',
          ].join(' ');
          // max-width в стиле: окно письма не считает ширину картинки
          // шириной вёрстки и не уменьшает из-за неё весь документ.
          out.write(
            '<img src="cid:${i.key}"${wh.isEmpty ? '' : ' $wh'} alt="${DocHtml.attr(i.alt)}" '
            'style="max-width:100%">',
          );
          visible = true;
      }
    }
    closeSpan();
    setLink(null);
    return visible;
  }

  void table(DocTable t, int depth) {
    if (t.rows.isEmpty) return;
    final css = <String>[
      'border-collapse:collapse',
      if (t.widthPct != null) 'width:${DocHtml.num(t.widthPct!.clamp(5, 100).toDouble())}%',
      if (t.align == 'center') 'margin-left:auto;margin-right:auto',
      if (t.align == 'right') 'margin-left:auto',
    ];
    out.write('<table style="${css.join(';')}"><tbody>');
    final cols = t.columns;
    final total = cols.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
    // Колонки сетки, занятые объединёнными по вертикали ячейками: ширина
    // ячейки — по её настоящим колонкам.
    final busy = <int, Set<int>>{};
    for (var r = 0; r < t.rows.length; r++) {
      out.write('<tr>');
      var col = 0;
      for (final c in t.rows[r].cells) {
        while (busy[r]?.contains(col) ?? false) {
          col++;
        }
        final span = c.colSpan.clamp(1, 1000);
        final rows = c.rowSpan.clamp(1, 10000);
        if (rows > 1) {
          for (var k = 1; k < rows && k < t.rows.length - r; k++) {
            final set = busy[r + k] ??= <int>{};
            for (var j = 0; j < span; j++) {
              set.add(col + j);
            }
          }
        }
        var w = 0.0;
        if (total > 0) {
          for (var j = col; j < col + span && j < cols.length; j++) {
            w += cols[j] > 0 ? cols[j] : 0;
          }
        }
        col += span;
        final pad = c.padding.length == 4 ? c.padding : const [0.0, 5.4, 0.0, 5.4];
        final st = <String>[
          if (w > 0) 'width:${DocHtml.num((w / total * 100).clamp(1, 100).toDouble())}%',
          'vertical-align:${const ['top', 'middle', 'bottom'][c.valign.clamp(0, 2)]}',
          'padding:${pad.map((v) => v == 0 ? '0' : '${DocHtml.num(v)}pt').join(' ')}',
          if (!c.borders.isEmpty) _borders(c.borders),
          if (c.background != null) 'background-color:${DocHtml.hex(c.background!)}',
        ];
        final attrs = StringBuffer();
        if (span > 1) attrs.write(' colspan="$span"');
        if (rows > 1) attrs.write(' rowspan="$rows"');
        // Доля колонки числом — для виджетов компьютера (NCell.flex); в окне
        // письма её перекрывает width в % из стиля.
        if (w > 0) attrs.write(' width="${math.max(1, (w / total * 1000).round())}"');
        out.write('<td$attrs style="${st.join(';')}">');
        blocks(c.blocks, depth + 1);
        out.write('</td>');
      }
      out.write('</tr>');
    }
    out.write('</tbody></table>');
  }
}

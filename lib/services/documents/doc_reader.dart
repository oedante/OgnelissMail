// lib/services/documents/doc_reader.dart
// Документ Word 97–2003 (.doc, .dot) → HTML для просмотра вложения (1.12.x,
// просьба владельца 04.11.2026: старые .doc — частые вложения в русской
// рабочей почте). По открытой спецификации Microsoft [MS-DOC] (Open
// Specification Promise), без сторонних библиотек; HTML пишет общий
// doc_html.dart — документ выглядит так же, как DOCX.
//
// Устройство: поток «WordDocument» начинается с FIB — там версия, флаги
// (пароль, какой из потоков «0Table»/«1Table» — таблицы документа), длины
// частей текста и смещения структур в потоке таблиц. Текст — по таблице
// кусков (CLX): каждый кусок — либо «сжатые» байты (кодовая страница 1252,
// как велит спецификация: кириллицу Word всегда пишет в UTF-16), либо
// UTF-16. Оформление — «страницы» FKP по 512 байт: CHPX (знаки) и PAPX
// (абзацы) по смещениям в файле, наборы свойств «sprm» поверх стилей (STSH,
// цепочки istdBase).
//
// Что показывается: абзацы (выравнивание, отступы, интервалы), заголовки
// (встроенные стили «Заголовок 1–9», уровень структуры), жирный, курсив,
// подчёркнутый, зачёркнутый, размер, цвет, маркер, надстрочный и
// подстрочный; списки Word (номера «1.2.», «а)», маркеры Symbol/Wingdings);
// таблицы (в том числе вложенные; объединения ячеек, ширины столбцов,
// рамки, заливка, выравнивание по вертикали); поля — их результатом
// (\x13 код \x14 результат \x15), ссылка HYPERLINK — ссылкой; разрывы
// страниц и разделов — чертой; сноски и концевые сноски — под чертой в
// конце; встроенные картинки PNG/JPEG/BMP. Исправления — принятыми,
// скрытый текст — не показывается.
// Не показываются: колонтитулы, примечания, надписи и фигуры (они вне
// основного текста), EMF/WMF, табуляция (пробелом), «быстро сохранённые»
// изменения кусков (Prm), поля страницы.
//
// Word 6/95 и старше — [OfficeDocError.legacy]; документ с паролем (или
// «XOR-обфускацией») — [OfficeDocError.encrypted]. Все смещения и длины —
// из чужого файла: проверяются по границам потоков, объявленным количествам
// не верим, текст — в пределах [DocBudget].

import 'dart:math' as math;
import 'dart:typed_data';

import 'cfb_reader.dart';
import 'doc_codepages.dart';
import 'doc_html.dart';
import 'office_art.dart';
import 'office_document.dart';
import 'office_package.dart';

class DocReader {
  DocReader._();

  /// Похоже на документ Word: есть поток «WordDocument».
  static bool isWordDocument(CfbFile cfb) => cfb.hasStream('WordDocument');

  /// Разобрать документ. Ошибки — только [OfficeDocException].
  static OfficeTextDoc read(CfbFile cfb) {
    try {
      return _Doc(cfb).run();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      // RangeError, FormatException, StateError … из чужого файла —
      // повреждённый документ, а не сбой приложения.
      throw OfficeDocException(OfficeDocError.damaged, 'doc: $e');
    }
  }
}

/// Кусок текста: CP [cp, cpEnd), байты с [fc] в WordDocument.
class _Piece {
  final int cp, cpEnd, fc;
  final bool compressed;
  const _Piece(this.cp, this.cpEnd, this.fc, this.compressed);
}

/// Диапазон смещений в WordDocument [fc, fcEnd) с набором свойств.
class _Fkp {
  final int fc, fcEnd;
  final Uint8List grpprl;
  final int istd;
  const _Fkp(this.fc, this.fcEnd, this.grpprl, [this.istd = 0]);
}

class _Style {
  int sti = 0x0FFE;
  int stk = 1;
  int base = 0x0FFF;
  Uint8List? papx;
  Uint8List? chpx;
}

/// Свойства знаков.
class _Chp {
  bool bold = false, italic = false, strike = false, caps = false, smallCaps = false;
  bool vanish = false, deleted = false, underline = false, special = false;
  int vert = 0;
  int? color, highlight;
  double size = 10;
  int font = -1;
  int? picLocation;
  int? symbolChar, symbolFont;

  _Chp copy() => _Chp()
    ..bold = bold
    ..italic = italic
    ..strike = strike
    ..caps = caps
    ..smallCaps = smallCaps
    ..vanish = vanish
    ..deleted = deleted
    ..underline = underline
    ..special = special
    ..vert = vert
    ..color = color
    ..highlight = highlight
    ..size = size
    ..font = font
    ..picLocation = picLocation
    ..symbolChar = symbolChar
    ..symbolFont = symbolFont;
}

/// Свойства абзаца.
class _Pap {
  int jc = 0;
  double left = 0, right = 0, first = 0, before = 0, after = 0;
  bool inTable = false, ttp = false, innerCell = false, innerTtp = false;
  int itap = 0;
  int outline = 9;
  bool pageBreakBefore = false, bidi = false;
  int ilfo = 0, ilvl = 0;
  int? shade;

  _Pap copy() => _Pap()
    ..jc = jc
    ..left = left
    ..right = right
    ..first = first
    ..before = before
    ..after = after
    ..inTable = inTable
    ..ttp = ttp
    ..innerCell = innerCell
    ..innerTtp = innerTtp
    ..itap = itap
    ..outline = outline
    ..pageBreakBefore = pageBreakBefore
    ..bidi = bidi
    ..ilfo = ilfo
    ..ilvl = ilvl
    ..shade = shade;
}

/// Уровень списка (LVL).
class _Lvl {
  int start = 1;
  int nfc = 0;
  int follow = 0;
  bool legal = false;
  String text = '';

  /// Позиции (с 1) знаков-подстановок номеров уровней в [text].
  List<int> places = const [];
  Uint8List papx = Uint8List(0);
  Uint8List chpx = Uint8List(0);
}

/// Строчный элемент абзаца до разрешения стиля (стиль абзаца известен
/// только у его знака конца).
sealed class _Raw {
  const _Raw();
}

class _RawText extends _Raw {
  final String text;
  final int run;
  final String? href;
  const _RawText(this.text, this.run, this.href);
}

class _RawBreak extends _Raw {
  const _RawBreak();
}

class _RawPage extends _Raw {
  const _RawPage();
}

class _RawPic extends _Raw {
  final int run;
  final String? href;
  const _RawPic(this.run, this.href);
}

class _RawNote extends _Raw {
  final String mark;
  final int run;
  const _RawNote(this.mark, this.run);
}

class _Field {
  bool code = true;
  final StringBuffer instr = StringBuffer();
  String? href;
}

/// Строка таблицы до сборки: ячейки и свойства строки (из знака её конца).
class _RowB {
  final List<List<DocBlock>> cells;
  final Uint8List tap;
  const _RowB(this.cells, this.tap);
}

class _TableB {
  final rows = <_RowB>[];
  List<List<DocBlock>> cells = [];
  List<DocBlock> cell = [];
}

class _Doc {
  _Doc(this.cfb);

  final CfbFile cfb;
  late Uint8List wd;
  late ByteData wbd;
  Uint8List table = Uint8List(0);
  late ByteData tbd;
  Uint8List? data;
  final budget = DocBudget();
  final images = DocImages();
  int _imagesTotal = 0;

  final pieces = <_Piece>[];
  final chpx = <_Fkp>[];
  final papx = <_Fkp>[];
  final styles = <_Style?>[];
  final fonts = <String>[];
  final lists = <int, List<_Lvl>>{};
  final lfos = <int>[];
  final lfoStart = <int, Map<int, int>>{};
  final counters = <int, List<int?>>{};
  final lfoSeen = <int>{};
  final Map<int, _Chp> _styleChp = {};
  final Map<int, _Pap> _stylePap = {};
  double pageWidth = 8640;

  /// Ссылки на сноски в основном тексте: CP → номер.
  final noteMarks = <int, String>{};

  int ccpText = 0, ccpFtn = 0, ccpHdd = 0, ccpAtn = 0, ccpEdn = 0;

  // ── FIB ──

  late int _blob;
  late int _blobCount;

  ({int fc, int lcb}) _fcLcb(int index) {
    if (index >= _blobCount) return (fc: 0, lcb: 0);
    final at = _blob + index * 8;
    if (at + 8 > wd.length) return (fc: 0, lcb: 0);
    return (fc: wbd.getUint32(at, Endian.little), lcb: wbd.getUint32(at + 4, Endian.little));
  }

  /// Часть потока таблиц [index] FIB; null — нет или вне потока.
  Uint8List? _tablePart(int index) {
    final r = _fcLcb(index);
    if (r.lcb == 0 || r.fc + r.lcb > table.length) return null;
    return Uint8List.sublistView(table, r.fc, r.fc + r.lcb);
  }

  OfficeTextDoc run() {
    final head = cfb.readHead('WordDocument', OfficeLimits.maxPartBytes)!;
    wd = head.bytes;
    wbd = ByteData.sublistView(wd);
    if (wd.length < 0x9A) throw const OfficeDocException(OfficeDocError.damaged, 'short fib');
    final ident = wbd.getUint16(0, Endian.little);
    final nFib = wbd.getUint16(2, Endian.little);
    // Word 6/95 (0xA5DC, nFib 101–105) и Word 2 — старый формат.
    if (ident == 0xA5DC || (ident == 0xA5EC && nFib < 0xC0)) {
      throw const OfficeDocException(OfficeDocError.legacy, 'word 6/95');
    }
    if (ident != 0xA5EC) throw const OfficeDocException(OfficeDocError.damaged, 'not a word document');
    final flags = wbd.getUint16(0x0A, Endian.little);
    if (flags & 0x0100 != 0 || flags & 0x8000 != 0) throw const OfficeDocException(OfficeDocError.encrypted, 'doc');
    final tableName = flags & 0x0200 != 0 ? '1Table' : '0Table';
    final t = cfb.read(tableName);
    if (t == null) throw OfficeDocException(OfficeDocError.damaged, 'no $tableName');
    table = t;
    tbd = ByteData.sublistView(table);
    try {
      data = cfb.read('Data');
    } on OfficeDocException catch (e) {
      // Без картинок, но с текстом.
      if (e.kind != OfficeDocError.damaged) rethrow;
    }

    // Размеры частей FIB — по их собственным длинам (csw, cslw, cbRgFcLcb).
    var p = 32;
    final csw = wbd.getUint16(p, Endian.little);
    p += 2 + csw * 2;
    if (p + 2 > wd.length) throw const OfficeDocException(OfficeDocError.damaged, 'fib');
    final cslw = wbd.getUint16(p, Endian.little);
    final lw = p + 2;
    p = lw + cslw * 4;
    if (p + 2 > wd.length || cslw < 11) throw const OfficeDocException(OfficeDocError.damaged, 'fib');
    int lwAt(int i) => wbd.getInt32(lw + i * 4, Endian.little);
    ccpText = math.max(0, lwAt(3));
    ccpFtn = math.max(0, lwAt(4));
    ccpHdd = math.max(0, lwAt(5));
    ccpAtn = math.max(0, lwAt(7));
    ccpEdn = math.max(0, lwAt(8));
    _blobCount = wbd.getUint16(p, Endian.little);
    _blob = p + 2;
    if (_blobCount < 34) throw const OfficeDocException(OfficeDocError.damaged, 'fib blob');

    _readPieces();
    _readFonts();
    _readStyles();
    _readLists();
    _readSection();
    chpx.addAll(_readBte(12, chp: true));
    papx.addAll(_readBte(13, chp: false));

    final footnotes = _notes(2, 3, ccpText, 'f');
    final endnotes = _notes(46, 47, ccpText + ccpFtn + ccpHdd + ccpAtn, 'e');
    final body = _range(0, ccpText);
    final notes = <DocBlock>[];
    for (final n in [...footnotes, ...endnotes]) {
      if (budget.full) break;
      notes.addAll(n());
    }
    return DocHtml.render(body, notes: notes, images: images.map, truncated: budget.truncated || head.truncated);
  }

  // ── Куски текста ──

  void _readPieces() {
    final clx = _tablePart(33);
    if (clx == null) throw const OfficeDocException(OfficeDocError.damaged, 'no clx');
    final bd = ByteData.sublistView(clx);
    var p = 0;
    while (p < clx.length) {
      final kind = clx[p];
      if (kind == 1) {
        // Prc — наборы свойств «быстрого сохранения»: пропускаются.
        if (p + 3 > clx.length) break;
        p += 3 + bd.getUint16(p + 1, Endian.little);
        continue;
      }
      if (kind != 2 || p + 5 > clx.length) throw const OfficeDocException(OfficeDocError.damaged, 'clx');
      final lcb = bd.getUint32(p + 1, Endian.little);
      final at = p + 5;
      if (at + lcb > clx.length || lcb < 4) throw const OfficeDocException(OfficeDocError.damaged, 'plcpcd');
      final n = (lcb - 4) ~/ 12;
      for (var i = 0; i < n; i++) {
        final cp = bd.getUint32(at + i * 4, Endian.little);
        final cpEnd = bd.getUint32(at + (i + 1) * 4, Endian.little);
        final pcd = at + (n + 1) * 4 + i * 8;
        final raw = bd.getUint32(pcd + 2, Endian.little);
        final compressed = raw & 0x40000000 != 0;
        final fc = raw & 0x3FFFFFFF;
        if (cpEnd <= cp) continue;
        pieces.add(_Piece(cp, cpEnd, compressed ? fc ~/ 2 : fc, compressed));
      }
      break;
    }
    pieces.sort((a, b) => a.cp.compareTo(b.cp));
    if (pieces.isEmpty) throw const OfficeDocException(OfficeDocError.damaged, 'no text');
  }

  // ── Шрифты, стили, списки, раздел ──

  void _readFonts() {
    final b = _tablePart(15);
    if (b == null || b.length < 4) return;
    final bd = ByteData.sublistView(b);
    var p = 0;
    var count = bd.getUint16(0, Endian.little);
    p = 4;
    if (count == 0xFFFF) {
      // Расширенная таблица строк: число — четыре байта.
      if (b.length < 6) return;
      count = bd.getUint16(2, Endian.little);
      p = 6;
    }
    for (var i = 0; i < count && i < 4096 && p < b.length; i++) {
      final len = b[p];
      final start = p + 1;
      final end = math.min(b.length, start + len);
      // FFN: 39 байт описания, затем имя UTF-16 с нулём.
      final units = <int>[];
      for (var q = start + 39; q + 1 < end; q += 2) {
        final c = bd.getUint16(q, Endian.little);
        if (c == 0) break;
        units.add(c);
      }
      fonts.add(String.fromCharCodes(units));
      p = end;
    }
  }

  String? _fontName(int i) => i >= 0 && i < fonts.length ? fonts[i] : null;

  void _readStyles() {
    final b = _tablePart(1);
    if (b == null || b.length < 4) return;
    final bd = ByteData.sublistView(b);
    final cbStshi = bd.getUint16(0, Endian.little);
    if (cbStshi + 2 > b.length || cbStshi < 4) return;
    final cstd = bd.getUint16(2, Endian.little);
    final cbBase = bd.getUint16(4, Endian.little);
    var p = 2 + cbStshi;
    for (var i = 0; i < cstd && i < 4096 && p + 2 <= b.length; i++) {
      final cb = bd.getUint16(p, Endian.little);
      final start = p + 2;
      p = start + cb;
      if (cb == 0 || p > b.length || cb < 10) {
        styles.add(null);
        continue;
      }
      try {
        styles.add(_style(b, bd, start, start + cb, cbBase));
      } on RangeError {
        styles.add(null);
      }
    }
  }

  _Style _style(Uint8List b, ByteData bd, int start, int end, int cbBase) {
    final s = _Style()
      ..sti = bd.getUint16(start, Endian.little) & 0x0FFF
      ..stk = bd.getUint16(start + 2, Endian.little) & 0xF
      ..base = bd.getUint16(start + 2, Endian.little) >> 4;
    final cupx = bd.getUint16(start + 4, Endian.little) & 0xF;
    var p = start + cbBase;
    // Имя: длина, знаки UTF-16, ноль.
    if (p + 2 > end) return s;
    final cch = bd.getUint16(p, Endian.little);
    p += 2 + cch * 2 + 2;
    final upx = <Uint8List>[];
    for (var i = 0; i < cupx && p + 2 <= end; i++) {
      final cb = bd.getUint16(p, Endian.little);
      final at = p + 2;
      if (at + cb > end) break;
      upx.add(Uint8List.sublistView(b, at, at + cb));
      p = at + cb;
      if ((p - start).isOdd) p++;
    }
    if (s.stk == 1) {
      // Стиль абзаца: свойства абзаца (с номером стиля впереди) и знаков.
      if (upx.isNotEmpty && upx[0].length >= 2) s.papx = Uint8List.sublistView(upx[0], 2);
      if (upx.length > 1) s.chpx = upx[1];
    } else if (s.stk == 2) {
      if (upx.isNotEmpty) s.chpx = upx[0];
    }
    return s;
  }

  _Style? _styleAt(int istd) => istd >= 0 && istd < styles.length ? styles[istd] : null;

  /// Свойства знаков стиля [istd] (по цепочке базовых, не глубже предела).
  _Chp _chpOfStyle(int istd, [int depth = 0]) {
    final hit = _styleChp[istd];
    if (hit != null) return hit;
    final s = _styleAt(istd);
    if (s == null || depth > 16) return _Chp();
    final base = s.base == 0x0FFF || s.base == istd ? _Chp() : _chpOfStyle(s.base, depth + 1);
    final out = base.copy();
    if (s.chpx != null) _applyChp(out, s.chpx!, base);
    return _styleChp[istd] = out;
  }

  _Pap _papOfStyle(int istd, [int depth = 0]) {
    final hit = _stylePap[istd];
    if (hit != null) return hit;
    final s = _styleAt(istd);
    if (s == null || depth > 16) return _Pap();
    final out = (s.base == 0x0FFF || s.base == istd ? _Pap() : _papOfStyle(s.base, depth + 1)).copy();
    if (s.papx != null) _applyPap(out, s.papx!);
    return _stylePap[istd] = out;
  }

  /// Уровень заголовка стиля: встроенные «heading 1–9» (sti 1–9) и
  /// «Title» (sti 62) — по цепочке базовых стилей.
  int _headingOf(int istd) {
    var i = istd;
    for (var hop = 0; hop < 16; hop++) {
      final s = _styleAt(i);
      if (s == null) return 0;
      if (s.sti >= 1 && s.sti <= 9) return math.min(s.sti, 6);
      if (s.sti == 62) return 1;
      if (s.base == 0x0FFF || s.base == i) return 0;
      i = s.base;
    }
    return 0;
  }

  void _readLists() {
    // Уровни списков (LVL) лежат сразу за PlfLst, но в его длину не входят:
    // читаем до конца потока таблиц.
    final at = _fcLcb(73);
    final lst = at.lcb == 0 || at.fc >= table.length ? null : Uint8List.sublistView(table, at.fc);
    if (lst != null && lst.length >= 2) {
      final bd = ByteData.sublistView(lst);
      final count = math.min(bd.getInt16(0, Endian.little), 2048);
      final ids = <(int, bool)>[];
      var p = 2;
      for (var i = 0; i < count && p + 28 <= lst.length; i++) {
        ids.add((bd.getInt32(p, Endian.little), lst[p + 26] & 1 != 0));
        p += 28;
      }
      for (final (id, simple) in ids) {
        final lvls = <_Lvl>[];
        for (var k = 0; k < (simple ? 1 : 9); k++) {
          final r = _lvl(lst, bd, p);
          if (r == null) {
            p = lst.length;
            break;
          }
          lvls.add(r.lvl);
          p = r.next;
        }
        lists[id] = lvls;
      }
    }
    final lfo = _tablePart(74);
    if (lfo != null && lfo.length >= 4) {
      final bd = ByteData.sublistView(lfo);
      final count = math.min(bd.getUint32(0, Endian.little), 2048);
      final levels = <int>[];
      var p = 4;
      for (var i = 0; i < count && p + 16 <= lfo.length; i++) {
        lfos.add(bd.getInt32(p, Endian.little));
        levels.add(lfo[p + 12]);
        p += 16;
      }
      // LFOData: «начать с N» у уровней (LFOLVL), иногда со своим LVL.
      for (var i = 0; i < levels.length && p + 4 <= lfo.length; i++) {
        p += 4;
        for (var k = 0; k < levels[i] && p + 8 <= lfo.length; k++) {
          final start = bd.getInt32(p, Endian.little);
          final f = lfo[p + 4];
          p += 8;
          if (f & 0x10 != 0) (lfoStart[i + 1] ??= {})[f & 0xF] = start;
          if (f & 0x20 != 0) {
            final r = _lvl(lfo, bd, p);
            if (r == null) return;
            p = r.next;
          }
        }
      }
    }
  }

  ({_Lvl lvl, int next})? _lvl(Uint8List b, ByteData bd, int p) {
    if (p + 28 > b.length) return null;
    final l = _Lvl()
      ..start = bd.getInt32(p, Endian.little)
      ..nfc = b[p + 4]
      ..legal = b[p + 5] & 0x4 != 0
      ..follow = b[p + 15];
    final places = <int>[];
    for (var i = 0; i < 9; i++) {
      final v = b[p + 6 + i];
      if (v == 0) break;
      places.add(v);
    }
    l.places = places;
    final cbChpx = b[p + 24];
    final cbPapx = b[p + 25];
    var q = p + 28;
    if (q + cbPapx + cbChpx + 2 > b.length) return null;
    l.papx = Uint8List.sublistView(b, q, q + cbPapx);
    q += cbPapx;
    l.chpx = Uint8List.sublistView(b, q, q + cbChpx);
    q += cbChpx;
    final cch = bd.getUint16(q, Endian.little);
    q += 2;
    if (q + cch * 2 > b.length) return null;
    l.text = String.fromCharCodes([for (var i = 0; i < cch; i++) bd.getUint16(q + i * 2, Endian.little)]);
    return (lvl: l, next: q + cch * 2);
  }

  /// Ширина текста страницы первого раздела (twips) — для ширины таблиц в %.
  void _readSection() {
    final sed = _tablePart(6);
    if (sed == null || sed.length < 20) return;
    final bd = ByteData.sublistView(sed);
    // PlcfSed: n + 1 CP, затем n описаний по 12 байт (fn, fcSepx …).
    final n = (sed.length - 4) ~/ 16;
    final fc = bd.getUint32((n + 1) * 4 + 2, Endian.little);
    if (fc == 0xFFFFFFFF || fc + 2 > wd.length) return;
    final cb = wbd.getUint16(fc, Endian.little);
    if (fc + 2 + cb > wd.length) return;
    var page = 12240.0, left = 1800.0, right = 1800.0;
    _sprms(Uint8List.sublistView(wd, fc + 2, fc + 2 + cb), (sprm, g, at, len) {
      final v = len >= 2 ? ByteData.sublistView(g).getUint16(at, Endian.little).toDouble() : 0.0;
      switch (sprm) {
        case 0xB01F:
          page = v;
        case 0xB021:
          left = v;
        case 0xB022:
          right = v;
      }
    });
    if (page - left - right > 1440) pageWidth = page - left - right;
  }

  // ── Страницы свойств (FKP) ──

  List<_Fkp> _readBte(int index, {required bool chp}) {
    final b = _tablePart(index);
    if (b == null || b.length < 8) return const [];
    final bd = ByteData.sublistView(b);
    final n = (b.length - 4) ~/ 8;
    final out = <_Fkp>[];
    final seen = <int>{};
    for (var i = 0; i < n; i++) {
      final pn = bd.getUint32((n + 1) * 4 + i * 4, Endian.little) & 0x3FFFFF;
      final at = pn * 512;
      if (!seen.add(pn) || at + 512 > wd.length) continue;
      final count = wd[at + 511];
      for (var k = 0; k < count; k++) {
        if ((count + 1) * 4 > 511) break;
        final fc = wbd.getUint32(at + k * 4, Endian.little);
        final fcEnd = wbd.getUint32(at + (k + 1) * 4, Endian.little);
        if (chp) {
          final off = wd[at + (count + 1) * 4 + k] * 2;
          if (off == 0 || at + off >= at + 511) {
            out.add(_Fkp(fc, fcEnd, Uint8List(0)));
            continue;
          }
          final cb = wd[at + off];
          final end = math.min(at + off + 1 + cb, at + 511);
          out.add(_Fkp(fc, fcEnd, Uint8List.sublistView(wd, at + off + 1, end)));
        } else {
          final bx = at + (count + 1) * 4 + k * 13;
          if (bx + 13 > at + 511) break;
          final off = wd[bx] * 2;
          if (off == 0) {
            out.add(_Fkp(fc, fcEnd, Uint8List(0)));
            continue;
          }
          var q = at + off;
          var cb = wd[q];
          int size;
          if (cb == 0) {
            q++;
            cb = wd[q];
            size = cb * 2;
          } else {
            size = cb * 2 - 1;
          }
          q++;
          final end = math.min(q + size, at + 511);
          if (end - q < 2) {
            out.add(_Fkp(fc, fcEnd, Uint8List(0)));
            continue;
          }
          out.add(_Fkp(fc, fcEnd, Uint8List.sublistView(wd, q + 2, end), wbd.getUint16(q, Endian.little)));
        }
      }
    }
    out.sort((a, b) => a.fc.compareTo(b.fc));
    return out;
  }

  /// Первый набор, начинающийся после [fc]; -1 — нет.
  static int _nextAfter(List<_Fkp> list, int fc) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].fc <= fc) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < list.length ? lo : -1;
  }

  /// Набор с диапазоном, в который попадает [fc]; -1 — нет.
  static int _find(List<_Fkp> list, int fc) {
    var lo = 0, hi = list.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = list[mid];
      if (fc < r.fc) {
        hi = mid - 1;
      } else if (fc >= r.fcEnd) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  // ── Наборы свойств (sprm) ──

  /// Обойти sprm набора [g]: (код, данные, начало операнда, его длина).
  static void _sprms(Uint8List g, void Function(int sprm, Uint8List g, int at, int len) f) {
    var p = 0;
    final bd = ByteData.sublistView(g);
    while (p + 2 <= g.length) {
      final sprm = bd.getUint16(p, Endian.little);
      p += 2;
      int len;
      switch (sprm >> 13) {
        case 0 || 1:
          len = 1;
        case 2 || 4 || 5:
          len = 2;
        case 3:
          len = 4;
        case 7:
          len = 3;
        default:
          if (p >= g.length) return;
          if (sprm == 0xD608 || sprm == 0xD606) {
            // sprmTDefTable: длина — два байта, «плюс один».
            if (p + 2 > g.length) return;
            len = bd.getUint16(p, Endian.little) + 1;
          } else if (sprm == 0xC615 && g[p] == 255) {
            // sprmPChgTabs с длиной 255 — длина по самим спискам табуляции.
            var q = p + 1;
            if (q >= g.length) return;
            final del = g[q];
            q += 1 + del * 4;
            if (q >= g.length) return;
            final add = g[q];
            q += 1 + add * 3;
            len = q - p;
          } else {
            len = g[p] + 1;
          }
      }
      if (p + len > g.length) return;
      f(sprm, g, p, len);
      p += len;
    }
  }

  static bool _toggle(int op, bool style) => switch (op) {
    0 => false,
    1 => true,
    0x80 => style,
    0x81 => !style,
    _ => false,
  };

  static const _ico = <int>[
    0, 0xFF000000, 0xFF0000FF, 0xFF00FFFF, 0xFF00FF00, 0xFFFF00FF, 0xFFFF0000, 0xFFFFFF00, 0xFFFFFFFF, //
    0xFF000080, 0xFF008080, 0xFF008000, 0xFF800080, 0xFF800000, 0xFF808000, 0xFF808080, 0xFFC0C0C0,
  ];

  static int? _icoColor(int ico) => ico > 0 && ico < _ico.length ? _ico[ico] : null;

  /// COLORREF (r, g, b, признак «авто»); null — «авто».
  static int? _cv(Uint8List g, int at) {
    if (at + 4 > g.length || g[at + 3] == 0xFF) return null;
    return 0xFF000000 | (g[at] << 16) | (g[at + 1] << 8) | g[at + 2];
  }

  void _applyChp(_Chp c, Uint8List g, _Chp style, [int depth = 0]) {
    _sprms(g, (sprm, g, at, len) {
      final op = g[at];
      int u16() => len >= 2 ? g[at] | (g[at + 1] << 8) : 0;
      switch (sprm) {
        case 0x0835:
          c.bold = _toggle(op, style.bold);
        case 0x0836:
          c.italic = _toggle(op, style.italic);
        case 0x0837:
          c.strike = _toggle(op, style.strike);
        case 0x2A53:
          c.strike = op != 0;
        case 0x083A:
          c.smallCaps = _toggle(op, style.smallCaps);
        case 0x083B:
          c.caps = _toggle(op, style.caps);
        case 0x083C:
          c.vanish = _toggle(op, style.vanish);
        case 0x0800:
          c.deleted = op != 0;
        case 0x0855:
          c.special = op != 0;
        case 0x2A3E:
          c.underline = op != 0;
        case 0x4A43:
          final hps = u16();
          if (hps >= 2 && hps <= 3276) c.size = hps / 2;
        case 0x2A42:
          c.color = _icoColor(op);
        case 0x6870:
          c.color = _cv(g, at);
        case 0x2A0C:
          c.highlight = _icoColor(op);
        case 0x2A48:
          c.vert = op;
        case 0x4A4F || 0x4A3D:
          c.font = u16();
        case 0x6A03:
          if (len >= 4) c.picLocation = ByteData.sublistView(g).getUint32(at, Endian.little);
        case 0x6A09:
          if (len >= 4) {
            c.symbolFont = u16();
            c.symbolChar = g[at + 2] | (g[at + 3] << 8);
          }
        case 0x4A30:
          // Стиль знаков: его свойства, затем остальные sprm поверх.
          if (depth < 4) {
            final s = _styleAt(u16());
            if (s?.chpx != null && s!.stk == 2) _applyChp(c, s.chpx!, style, depth + 1);
          }
      }
    });
  }

  void _applyPap(_Pap p, Uint8List g) {
    _sprms(g, (sprm, g, at, len) {
      final bd = ByteData.sublistView(g);
      final op = g[at];
      int i16() => len >= 2 ? bd.getInt16(at, Endian.little) : 0;
      switch (sprm) {
        case 0x2403 || 0x2461:
          p.jc = op;
        case 0x840F || 0x845E:
          p.left = i16() / 20;
        case 0x840E || 0x845D:
          p.right = i16() / 20;
        case 0x8411 || 0x8460:
          p.first = i16() / 20;
        case 0xA413:
          p.before = (i16() & 0xFFFF) / 20;
        case 0xA414:
          p.after = (i16() & 0xFFFF) / 20;
        case 0x2416:
          p.inTable = op != 0;
        case 0x2417:
          p.ttp = op != 0;
        case 0x6649:
          if (len >= 4) p.itap = bd.getInt32(at, Endian.little).clamp(0, OfficeLimits.maxDepth);
        case 0x244B:
          p.innerCell = op != 0;
        case 0x244C:
          p.innerTtp = op != 0;
        case 0x2640:
          p.outline = op;
        case 0x2407:
          p.pageBreakBefore = op != 0;
        case 0x2441:
          p.bidi = op != 0;
        case 0x460B:
          p.ilfo = i16() & 0xFFFF;
        case 0x260A:
          p.ilvl = op.clamp(0, 8);
        case 0x442D:
          // SHD80: цвет фона — номером палитры, узор «сплошной» — цвет узора.
          final v = i16() & 0xFFFF;
          final ipat = v >> 10;
          p.shade = ipat == 1 ? _icoColor(v & 0x1F) : (ipat == 0 ? _icoColor((v >> 5) & 0x1F) : null);
        case 0xC64D:
          if (len >= 11) {
            final ipat = bd.getUint16(at + 9, Endian.little);
            p.shade = ipat == 1 ? _cv(g, at + 1) : (ipat == 0 ? _cv(g, at + 5) : null);
          }
      }
    });
  }

  // ── Текст ──

  /// Сноски: ссылки (PlcffndRef / PlcfendRef) и тексты; номера —
  /// по порядку автоматических ссылок.
  List<List<DocBlock> Function()> _notes(int refIndex, int txtIndex, int base, String kind) {
    final ref = _tablePart(refIndex);
    final txt = _tablePart(txtIndex);
    if (ref == null || txt == null || ref.length < 6) return const [];
    final rbd = ByteData.sublistView(ref);
    final tbd = ByteData.sublistView(txt);
    final n = math.min((ref.length - 4) ~/ 6, 10000);
    final out = <List<DocBlock> Function()>[];
    var auto = 0;
    for (var i = 0; i < n; i++) {
      final cp = rbd.getUint32(i * 4, Endian.little);
      final nAuto = rbd.getInt16((n + 1) * 4 + i * 2, Endian.little);
      final mark = nAuto != 0 ? '${++auto}' : '*';
      noteMarks[cp] = mark;
      if ((i + 2) * 4 > txt.length) continue;
      final from = base + tbd.getUint32(i * 4, Endian.little);
      final to = base + tbd.getUint32((i + 1) * 4, Endian.little);
      out.add(() {
        final blocks = _range(from, to);
        if (blocks.isNotEmpty && blocks.first is DocPara) {
          final p = blocks.first as DocPara;
          blocks[0] = DocPara(p.style, [DocText('$mark ', const DocFont(vert: DocVert.sup)), ...p.inlines]);
        }
        return blocks;
      });
    }
    return out;
  }

  /// Блоки текста [from, to) (основной текст или одна сноска).
  List<DocBlock> _range(int from, int to) {
    final out = <DocBlock>[];
    final tables = <_TableB>[];
    var raws = <_Raw>[];
    final fields = <_Field>[];
    final quick = <int, _Chp>{};

    List<DocBlock> target() => tables.isEmpty ? out : tables.last.cell;

    _Chp quickChp(int run) => quick[run] ??= run < 0 ? _Chp() : (_Chp().._applyChpQuick(chpx[run].grpprl));

    void closeTable() {
      final depth = tables.length;
      final t = tables.removeLast();
      if (t.cells.isNotEmpty || t.cell.isNotEmpty) {
        if (t.cell.isNotEmpty) t.cells.add(t.cell);
        t.rows.add(_RowB(t.cells, Uint8List(0)));
      }
      final built = _table(t, depth);
      if (built != null) target().add(built);
    }

    void endParagraph(int markRun, int markFc, bool cellMark) {
      final i = _find(papx, markFc);
      final pf = i < 0 ? null : papx[i];
      final istd = pf?.istd ?? 0;
      final pap = _papOfStyle(istd).copy();
      if (pf != null) _applyPap(pap, pf.grpprl);
      final depth = pap.inTable ? math.max(pap.itap, 1) : 0;
      while (tables.length > depth) {
        closeTable();
      }
      while (tables.length < depth) {
        tables.add(_TableB());
      }
      final rowEnd = depth > 0 && (depth == 1 ? pap.ttp : pap.innerTtp);
      if (rowEnd) {
        final t = tables.last;
        t.rows.add(_RowB(t.cells, pf?.grpprl ?? Uint8List(0)));
        t.cells = [];
        t.cell = [];
        raws = [];
        return;
      }
      if (budget.block()) _paragraph(raws, istd, pap, markRun, target());
      raws = [];
      final cellEnd = depth > 0 && (depth == 1 ? cellMark : pap.innerCell);
      if (cellEnd) {
        final t = tables.last;
        t.cells.add(t.cell);
        t.cell = [];
      }
    }

    String? href() {
      for (var k = fields.length - 1; k >= 0; k--) {
        if (fields[k].href != null) return fields[k].href;
      }
      return null;
    }

    for (final pc in pieces) {
      if (budget.full) break;
      final a = math.max(pc.cp, from), b = math.min(pc.cpEnd, to);
      if (a >= b) continue;
      final step = pc.compressed ? 1 : 2;
      var cp = a;
      while (cp < b && !budget.full) {
        final fc = pc.fc + (cp - pc.cp) * step;
        // Участок одного набора свойств знаков.
        final runIdx = _find(chpx, fc);
        int segEnd;
        if (runIdx >= 0) {
          segEnd = math.min(b, pc.cp + ((chpx[runIdx].fcEnd - pc.fc) + step - 1) ~/ step);
        } else {
          // Ближайший следующий набор — граница участка без свойств.
          final next = _nextAfter(chpx, fc);
          segEnd = next < 0 ? b : math.min(b, pc.cp + (chpx[next].fc - pc.fc) ~/ step);
        }
        if (segEnd <= cp) segEnd = cp + 1;
        final q = quickChp(runIdx);
        final text = StringBuffer();
        void flush() {
          if (text.isNotEmpty) {
            raws.add(_RawText(text.toString(), runIdx, href()));
            text.clear();
          }
        }

        for (var x = cp; x < segEnd && !budget.full; x++) {
          final f = pc.fc + (x - pc.cp) * step;
          if (f + step > wd.length) break;
          final c = pc.compressed ? DocCodePages.char(wd[f], 1252) : wbd.getUint16(f, Endian.little);
          switch (c) {
            case 0x13:
              flush();
              fields.add(_Field());
              continue;
            case 0x14:
              flush();
              if (fields.isNotEmpty) {
                final fl = fields.last;
                fl.code = false;
                fl.href = DocHtml.fieldLink(fl.instr.toString());
              }
              continue;
            case 0x15:
              flush();
              if (fields.isNotEmpty) fields.removeLast();
              continue;
          }
          if (fields.any((fl) => fl.code)) {
            if (fields.last.code && fields.last.instr.length < 4096) fields.last.instr.writeCharCode(c);
            if (c != 0x0D && c != 0x07) continue;
          }
          switch (c) {
            case 0x0D || 0x07:
              flush();
              endParagraph(runIdx, f, c == 0x07);
            case 0x0B:
              flush();
              raws.add(const _RawBreak());
            case 0x0C:
              flush();
              raws.add(const _RawPage());
            case 0x09:
              text.write('\t');
            case 0x1E:
              text.write('-');
            case 0xA0:
              text.write(' ');
            case 0x01:
              flush();
              if (q.special) raws.add(_RawPic(runIdx, href()));
            case 0x02:
              flush();
              final mark = noteMarks[x];
              if (q.special && mark != null) raws.add(_RawNote(mark, runIdx));
            case 0x28 when q.special && q.symbolChar != null:
              text.write(DocHtml.symbols(String.fromCharCode(q.symbolChar!), _fontName(q.symbolFont ?? -1)));
            default:
              if (c < 0x20 || c == 0x1F) continue;
              text.writeCharCode(c);
          }
        }
        flush();
        cp = segEnd;
      }
    }
    // Абзац без знака конца (обрезанный документ) — тоже показать.
    if (raws.isNotEmpty && budget.block()) _paragraph(raws, 0, _papOfStyle(0), -1, target());
    while (tables.isNotEmpty) {
      closeTable();
    }
    return out;
  }

  void _paragraph(List<_Raw> raws, int istd, _Pap pap, int markRun, List<DocBlock> out) {
    final base = _chpOfStyle(istd);
    _Chp chpOf(int run) {
      if (run < 0 || run >= chpx.length) return base;
      final c = base.copy();
      _applyChp(c, chpx[run].grpprl, base);
      return c;
    }

    // Номер пункта списка.
    DocText? label;
    final inlines = <DocInline>[];
    final lvl = _listLevel(pap);
    var p = pap;
    if (lvl != null) {
      p = pap.copy();
      final sp = _papOfStyle(istd).copy();
      _applyPap(sp, lvl.$1.papx);
      // Отступы уровня, если у абзаца нет своих.
      p.left = pap.left == _papOfStyle(istd).left ? sp.left : pap.left;
      p.first = pap.first == _papOfStyle(istd).first ? sp.first : pap.first;
      final lc = chpOf(markRun).copy();
      _applyChp(lc, lvl.$1.chpx, lc);
      var t = lvl.$2;
      if (lvl.$1.nfc == 23) t = DocHtml.bullet(t, _fontName(lc.font));
      final font = DocFont(bold: lc.bold, italic: lc.italic, color: lc.color, size: lc.size);
      if (t.isNotEmpty) {
        if (lvl.$1.follow == 0) {
          label = DocText(t, font);
        } else {
          inlines.add(DocText(lvl.$1.follow == 1 ? '$t ' : t, font));
        }
      }
    }

    var heading = _headingOf(istd);
    if (heading == 0 && p.outline >= 0 && p.outline < 6) heading = p.outline + 1;
    final mark = chpOf(markRun);
    final style = DocParaStyle(
      heading: heading,
      align: switch (p.jc) {
        1 => 'center',
        2 => 'right',
        3 || 4 || 5 => 'justify',
        _ => null,
      },
      before: p.before.clamp(0, 144).toDouble(),
      after: p.after.clamp(0, 144).toDouble(),
      left: p.left.clamp(-144, 1440).toDouble(),
      right: p.right.clamp(-144, 1440).toDouble(),
      firstLine: p.first.clamp(-720, 720).toDouble(),
      background: p.shade,
      rtl: p.bidi,
      size: mark.size,
    );

    final blocks = <DocBlock>[];
    if (p.pageBreakBefore) blocks.add(const DocRule());
    var ruled = false;

    for (final r in raws) {
      switch (r) {
        case _RawText():
          final c = chpOf(r.run);
          if (c.vanish || c.deleted) continue;
          var t = budget.text(r.text);
          if (t.isEmpty) continue;
          if (c.caps) t = t.toUpperCase();
          final name = _fontName(c.font);
          t = DocHtml.symbols(t, name);
          inlines.add(DocText(t, _docFont(c, name), r.href));
        case _RawBreak():
          inlines.add(const DocBreak());
        case _RawPage():
          // Разрыв страницы или раздела: текст до него — абзацем, черта.
          if (inlines.isNotEmpty || label != null) {
            blocks.add(DocPara(style, List.of(inlines), label: label));
            inlines.clear();
            label = null;
          }
          blocks.add(const DocRule());
          ruled = true;
        case _RawPic():
          final pic = _picture(chpOf(r.run), r.href);
          if (pic != null) inlines.add(pic);
        case _RawNote():
          final c = chpOf(r.run);
          inlines.add(DocText(r.mark, _docFont(c, null).copyWith(vert: DocVert.sup)));
      }
    }
    if (inlines.isNotEmpty || label != null || !ruled) {
      blocks.add(DocPara(style, inlines, label: label));
    }
    out.addAll(blocks);
  }

  DocFont _docFont(_Chp c, String? name) {
    final f = (name ?? '').toLowerCase();
    return DocFont(
      bold: c.bold,
      italic: c.italic,
      underline: c.underline,
      strike: c.strike,
      smallCaps: c.smallCaps && !c.caps,
      mono: f.contains('courier') || f.contains('consolas') || f.contains('lucida console') || f.contains('mono'),
      vert: c.vert == 1 ? DocVert.sup : (c.vert == 2 ? DocVert.sub : DocVert.none),
      color: c.color,
      background: c.highlight,
      size: c.size,
    );
  }

  /// Уровень списка абзаца и текст номера; null — не пункт.
  (_Lvl, String)? _listLevel(_Pap p) {
    if (p.ilfo <= 0 || p.ilfo > lfos.length || p.ilfo == 0x7FF) return null;
    final lsid = lfos[p.ilfo - 1];
    final lvls = lists[lsid];
    if (lvls == null || lvls.isEmpty) return null;
    final il = lvls.length == 1 ? 0 : p.ilvl.clamp(0, lvls.length - 1);
    final cur = lvls[il];
    final c = counters.putIfAbsent(lsid, () => List<int?>.filled(9, null));
    final so = lfoStart[p.ilfo];
    if (so != null && lfoSeen.add(p.ilfo)) {
      for (final e in so.entries) {
        if (e.key > 8) continue;
        c[e.key] = e.value - 1;
        for (var d = e.key + 1; d < 9; d++) {
          c[d] = null;
        }
      }
    }
    c[il] = c[il] == null ? cur.start : c[il]! + 1;
    for (var d = il + 1; d < 9; d++) {
      c[d] = null;
    }
    if (cur.nfc == 23) return (cur, cur.text);
    if (cur.nfc == 0xFF) return (cur, _withoutPlaces(cur));
    final out = StringBuffer();
    for (var i = 0; i < cur.text.length; i++) {
      final ch = cur.text.codeUnitAt(i);
      if (cur.places.contains(i + 1) && ch < 9) {
        final lk = ch < lvls.length ? lvls[ch] : cur;
        final n = c[ch] ?? lk.start;
        out.write(DocNumbers.format(n, cur.legal ? 'decimal' : _nfc(lk.nfc)));
      } else {
        out.writeCharCode(ch);
      }
    }
    return (cur, out.toString());
  }

  static String _withoutPlaces(_Lvl l) {
    final out = StringBuffer();
    for (var i = 0; i < l.text.length; i++) {
      if (!l.places.contains(i + 1)) out.writeCharCode(l.text.codeUnitAt(i));
    }
    return out.toString();
  }

  static String _nfc(int nfc) => switch (nfc) {
    1 => 'upperRoman',
    2 => 'lowerRoman',
    3 => 'upperLetter',
    4 => 'lowerLetter',
    22 => 'decimalZero',
    58 => 'russianLower',
    59 => 'russianUpper',
    0xFF => 'none',
    _ => 'decimal',
  };

  /// Встроенная картинка (знак 0x01): PICF в потоке Data, за ним — записи
  /// OfficeArt с BLIP.
  DocPicture? _picture(_Chp c, String? href) {
    final d = data;
    final at = c.picLocation;
    if (d == null || at == null || at + 0x44 > d.length) return null;
    if (_imagesTotal >= OfficeLimits.maxImagesTotal) return null;
    final bd = ByteData.sublistView(d);
    final lcb = bd.getUint32(at, Endian.little);
    final cbHeader = bd.getUint16(at + 4, Endian.little);
    final mm = bd.getUint16(at + 6, Endian.little);
    if (lcb < cbHeader || at + lcb > d.length || (mm != 0x64 && mm != 0x66)) return null;
    var p = at + cbHeader;
    if (mm == 0x66 && p < d.length) p += 1 + d[p];
    final img = OfficeArt.firstBlip(d, p, at + lcb);
    if (img == null || _imagesTotal + img.bytes.length > OfficeLimits.maxImagesTotal) return null;
    final key = images.add('pic$at', () => img);
    if (key == null) return null;
    _imagesTotal += img.bytes.length;
    final dxa = bd.getUint16(at + 28, Endian.little) * bd.getUint16(at + 32, Endian.little) / 1000;
    final dya = bd.getUint16(at + 30, Endian.little) * bd.getUint16(at + 34, Endian.little) / 1000;
    return DocPicture(key, width: dxa > 0 ? dxa / 15 : null, height: dya > 0 ? dya / 15 : null, href: href);
  }

  // ── Таблицы ──

  DocTable? _table(_TableB t, int depth) {
    final rows = t.rows.where((r) => r.cells.isNotEmpty).toList();
    if (rows.isEmpty) return null;
    // Границы ячеек каждой строки (twips) из sprmTDefTable её знака конца.
    final bounds = <List<int>>[];
    final tcs = <List<int>>[];
    final shades = <List<int?>>[];
    final rowBorders = <List<DocLine?>>[];
    final vMerge = <Map<int, int>>[];
    final vAlign = <Map<int, int>>[];
    var jc = 0;
    for (final r in rows) {
      final b = <int>[];
      final tc = <int>[];
      final sh = <int?>[];
      final tb = List<DocLine?>.filled(6, null);
      final vm = <int, int>{};
      final va = <int, int>{};
      final brc = <int, List<DocLine?>>{};
      _sprms(r.tap, (sprm, g, at, len) {
        final bd = ByteData.sublistView(g);
        switch (sprm) {
          case 0xD608:
            if (len < 3) return;
            final n = math.min(g[at + 2], 63);
            final xs = at + 3;
            if (xs + (n + 1) * 2 > at + len) return;
            for (var i = 0; i <= n; i++) {
              b.add(bd.getInt16(xs + i * 2, Endian.little));
            }
            final tcAt = xs + (n + 1) * 2;
            for (var i = 0; i < n && tcAt + (i + 1) * 20 <= at + len; i++) {
              final q = tcAt + i * 20;
              tc.add(bd.getUint16(q, Endian.little));
              brc[i] = [for (var k = 0; k < 4; k++) _brc80(g, q + 4 + k * 4)];
            }
          case 0xD612:
            for (var q = at + 1; q + 10 <= at + len; q += 10) {
              final ipat = bd.getUint16(q + 8, Endian.little);
              sh.add(ipat == 1 ? _cv(g, q) : (ipat == 0 ? _cv(g, q + 4) : null));
            }
          case 0xD605:
            for (var k = 0; k < 6 && at + 1 + (k + 1) * 4 <= at + len; k++) {
              tb[k] = _brc80(g, at + 1 + k * 4);
            }
          case 0xD613:
            for (var k = 0; k < 6 && at + 1 + (k + 1) * 8 <= at + len; k++) {
              tb[k] = _brc(g, at + 1 + k * 8);
            }
          case 0xD62B:
            if (len >= 3) vm[g[at + 1]] = g[at + 2];
          case 0xD62C:
            if (len >= 4) {
              for (var i = g[at + 1]; i < g[at + 2] && i < 64; i++) {
                va[i] = g[at + 3];
              }
            }
          case 0x5400 || 0x548A:
            jc = g[at];
        }
      });
      bounds.add(b);
      tcs.add(tc);
      shades.add(sh);
      rowBorders.add([
        for (var i = 0; i < r.cells.length; i++) ...(brc[i] ?? const [null, null, null, null]),
        ...tb,
      ]);
      vMerge.add(vm);
      vAlign.add(va);
    }
    // Сетка столбцов — все границы всех строк.
    final grid = <int>{for (final b in bounds) ...b}.toList()..sort();
    final hasGrid = grid.length >= 2 && grid.length <= 128;
    final outRows = <List<DocCell>>[];
    // Ячейка, начавшая объединение по вертикали, по столбцу сетки.
    final owner = <int, (int, int)>{};
    final spans = <(int, int), int>{};
    for (var ri = 0; ri < rows.length; ri++) {
      final r = rows[ri];
      final b = bounds[ri];
      final cells = <DocCell>[];
      final n = r.cells.length;
      for (var ci = 0; ci < n; ci++) {
        final tcgrf = ci < tcs[ri].length ? tcs[ri][ci] : 0;
        final horz = tcgrf & 3;
        final vert = vMerge[ri][ci] ?? ((tcgrf >> 5) & 3);
        var col = ci, span = 1;
        if (hasGrid && ci + 1 < b.length) {
          col = grid.indexOf(b[ci]);
          final end = grid.indexOf(b[ci + 1]);
          span = math.max(1, end - col);
        }
        // Объединение по горизонтали (Word 97): продолжение — в первую ячейку.
        if (horz >= 2 && cells.isNotEmpty) {
          final last = cells.removeLast();
          cells.add(_cell(last.blocks, last.colSpan + span, last.background, last.borders, last.valign));
          continue;
        }
        if (vert == 1 && owner.containsKey(col)) {
          final o = owner[col]!;
          spans[o] = (spans[o] ?? 1) + 1;
          continue;
        }
        final lines = rowBorders[ri];
        final tb = lines.sublist(n * 4);
        DocLine? side(int k, DocLine? outer, DocLine? inner) => lines[ci * 4 + k] ?? outer ?? inner;
        final borders = DocBorders(
          top: side(0, ri == 0 ? tb[0] : null, tb[4]),
          left: side(1, ci == 0 ? tb[1] : null, tb[5]),
          bottom: side(2, ri == rows.length - 1 ? tb[2] : null, tb[4]),
          right: side(3, ci == n - 1 ? tb[3] : null, tb[5]),
        );
        final bg = ci < shades[ri].length ? shades[ri][ci] : null;
        final va = vAlign[ri][ci] ?? ((tcgrf >> 7) & 3);
        cells.add(_cell(r.cells[ci], span, bg, borders, va));
        if (vert == 3) {
          owner[col] = (ri, cells.length - 1);
        } else {
          owner.remove(col);
        }
      }
      outRows.add(cells);
    }
    final docRows = <DocRow>[];
    for (var ri = 0; ri < outRows.length; ri++) {
      docRows.add(
        DocRow([
          for (var ci = 0; ci < outRows[ri].length; ci++)
            () {
              final c = outRows[ri][ci];
              final rs = spans[(ri, ci)];
              return rs == null
                  ? c
                  : DocCell(
                      c.blocks,
                      colSpan: c.colSpan,
                      rowSpan: rs,
                      background: c.background,
                      borders: c.borders,
                      valign: c.valign,
                    );
            }(),
        ]),
      );
    }
    final columns = hasGrid
        ? [for (var i = 0; i + 1 < grid.length; i++) (grid[i + 1] - grid[i]).toDouble()]
        : <double>[];
    double? widthPct;
    if (hasGrid) {
      widthPct = (grid.last - grid.first) / pageWidth * 100;
      if (widthPct <= 0 || widthPct.isNaN) widthPct = null;
      if (widthPct != null && widthPct > 90) widthPct = 100;
    }
    // Вложенная таблица — во всю ширину ячейки, как у DOCX.
    if (depth > 1) widthPct = 100;
    return DocTable(
      docRows,
      columns: columns,
      widthPct: widthPct,
      align: switch (jc) {
        1 => 'center',
        2 => 'right',
        _ => null,
      },
    );
  }

  static DocCell _cell(List<DocBlock> blocks, int span, int? bg, DocBorders borders, int valign) =>
      DocCell(blocks, colSpan: span, background: bg, borders: borders, valign: valign.clamp(0, 2));

  /// Рамка Brc80: толщина в 1/8 пт, вид, цвет номером палитры.
  static DocLine? _brc80(Uint8List g, int at) {
    if (at + 4 > g.length) return null;
    final type = g[at + 1];
    if (type == 0 || type == 0xFF) return null;
    return DocLine(width: math.max(g[at], 2) / 8, style: _brcStyle(type), color: _icoColor(g[at + 2]));
  }

  /// Рамка Brc: цвет COLORREF, толщина, вид.
  static DocLine? _brc(Uint8List g, int at) {
    if (at + 8 > g.length) return null;
    final type = g[at + 5];
    if (type == 0 || type == 0xFF) return null;
    return DocLine(width: math.max(g[at + 4], 2) / 8, style: _brcStyle(type), color: _cv(g, at));
  }

  static String _brcStyle(int type) => switch (type) {
    3 || 10 => 'double',
    6 => 'dotted',
    7 || 8 || 9 || 22 => 'dashed',
    _ => 'solid',
  };
}

extension on _Chp {
  /// Только то, что нужно при чтении текста: «особый знак», картинка,
  /// символ шрифта (стиль и остальное — у абзаца, при сборке).
  void _applyChpQuick(Uint8List g) {
    _Doc._sprms(g, (sprm, g, at, len) {
      switch (sprm) {
        case 0x0855:
          special = g[at] != 0;
        case 0x6A09:
          if (len >= 4) {
            symbolFont = g[at] | (g[at + 1] << 8);
            symbolChar = g[at + 2] | (g[at + 3] << 8);
          }
      }
    });
  }
}

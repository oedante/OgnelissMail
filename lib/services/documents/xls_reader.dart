// lib/services/documents/xls_reader.dart
// Книга Excel 97–2003 (.xls, .xlt; BIFF8 в потоке «Workbook» составного
// файла) → листы для показа сеткой (1.12.x, просьба владельца 04.11.2026:
// старые .xls — частые вложения в русской рабочей почте, выгрузки 1С).
// По открытой спецификации Microsoft [MS-XLS] (Open Specification Promise),
// без сторонних библиотек; модель и форматы чисел — общие с XLSX
// (doc_sheets.dart, sheet_format.dart).
//
// Поток — записи «тип, длина, данные» (длина до 8224 байт, длиннее — в
// следующих записях CONTINUE). Сначала — общая часть книги (globals):
// шрифты, форматы чисел, оформления ячеек (XF), палитра, система дат 1904,
// открытый лист, список листов (BoundSheet8: смещение листа в потоке,
// скрытый ли) и таблица общих строк (SST). Затем — листы, каждый от BOF до
// EOF: ширины столбцов (ColInfo), высоты и скрытые строки (Row), ячейки
// (LabelSst, Label, Number, RK, MulRk, BoolErr, Formula с сохранённым
// значением и строкой из следующей записи String, Blank и MulBlank — только
// оформление), объединения (MergeCells), сетка и закрепление (Window2, Pane).
// Формулы не вычисляются: показывается сохранённое значение, как в XLSX.
//
// Книга с паролем на открытие (запись FilePass) — [OfficeDocError.encrypted];
// Excel 5/95 и старше (BIFF5–BIFF2: поток «Book», другая версия в BOF) —
// [OfficeDocError.legacy], как раньше. Диаграммы, картинки, примечания,
// условное форматирование, гиперссылки — не показываются. Пределы — как у
// XLSX ([SheetLimits]); записям и объявленным в них количествам не верим:
// всё читается в пределах самих данных записи.

import 'dart:math' as math;
import 'dart:typed_data';

import 'cfb_reader.dart';
import 'doc_sheets.dart';
import 'office_package.dart';
import 'sheet_format.dart';
import 'xlsx_reader.dart';

class XlsReader {
  XlsReader._();

  /// Похоже на книгу Excel: в файле есть поток книги (BIFF8 или старше).
  static bool isWorkbook(CfbFile cfb) => cfb.hasStream('Workbook') || cfb.hasStream('Book');

  /// Разобрать книгу. Ошибки — только [OfficeDocException].
  static OfficeSheetsDoc read(CfbFile cfb, {String lang = 'en'}) {
    try {
      return _Xls(cfb, SheetLocale.of(lang)).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      // RangeError, FormatException … из чужого файла — повреждённая книга.
      throw OfficeDocException(OfficeDocError.damaged, 'xls: $e');
    }
  }
}

// Типы записей BIFF8.
const _bof = 0x0809;
const _eof = 0x000A;
const _continue = 0x003C;
const _filePass = 0x002F;
const _date1904 = 0x0022;
const _window1 = 0x003D;
const _font = 0x0031;
const _formatRec = 0x041E;
const _xf = 0x00E0;
const _palette = 0x0092;
const _boundSheet = 0x0085;
const _sst = 0x00FC;
const _labelSst = 0x00FD;
const _label = 0x0204;
const _rString = 0x00D6;
const _number = 0x0203;
const _rk = 0x027E;
const _mulRk = 0x00BD;
const _boolErr = 0x0205;
const _formula = 0x0006;
const _string = 0x0207;
const _blank = 0x0201;
const _mulBlank = 0x00BE;
const _colInfo = 0x007D;
const _defColWidth = 0x0055;
const _standardWidth = 0x0099;
const _row = 0x0208;
const _defaultRowHeight = 0x0225;
const _mergeCells = 0x00E5;
const _window2 = 0x023E;
const _pane = 0x0041;

class _Font {
  final bool b, i, u, s;
  final double px;
  final int icv;
  const _Font(this.b, this.i, this.u, this.s, this.px, this.icv);
}

class _Xf {
  final int font, fmt;
  final int alc, alcV, indent;
  final bool wrap;
  final int dgLeft, dgRight, dgTop, dgBottom;
  final int icvLeft, icvRight, icvTop, icvBottom;
  final int fls, icvFore, icvBack;
  const _Xf(
    this.font,
    this.fmt,
    this.alc,
    this.alcV,
    this.indent,
    this.wrap,
    this.dgLeft,
    this.dgRight,
    this.dgTop,
    this.dgBottom,
    this.icvLeft,
    this.icvRight,
    this.icvTop,
    this.icvBottom,
    this.fls,
    this.icvFore,
    this.icvBack,
  );
}

/// Лист из списка книги.
class _Bound {
  final String name;
  final int pos;
  final int index;
  const _Bound(this.name, this.pos, this.index);
}

/// Данные записи и её продолжений (CONTINUE) подряд: строка, разрезанная
/// между записями, продолжается в следующей с нового байта флагов
/// (1 — UTF-16, 0 — «сжатая», младшие байты знаков).
class _Chunks {
  _Chunks(this.parts);

  final List<Uint8List> parts;
  int _i = 0;
  int _p = 0;

  bool get atEnd {
    while (_i < parts.length && _p >= parts[_i].length) {
      _i++;
      _p = 0;
    }
    return _i >= parts.length;
  }

  int byte() {
    if (atEnd) throw const FormatException('short record');
    return parts[_i][_p++];
  }

  int u16() => byte() | (byte() << 8);
  int u32() => u16() | (u16() << 16);

  void skip(int n) {
    var left = n;
    while (left > 0 && !atEnd) {
      final take = math.min(left, parts[_i].length - _p);
      _p += take;
      left -= take;
    }
  }

  /// [n] знаков; [high] — UTF-16. Лишнее сверх [SheetLimits.maxCellText]
  /// пропускается, а не копится.
  String chars(int n, bool high) {
    final out = <int>[];
    var left = n;
    var wide = high;
    while (left > 0) {
      if (_i >= parts.length) break;
      if (_p >= parts[_i].length) {
        _i++;
        _p = 0;
        if (_i >= parts.length) break;
        if (parts[_i].isEmpty) continue;
        wide = parts[_i][_p++] & 1 == 1;
        continue;
      }
      final part = parts[_i];
      if (wide) {
        if (_p + 1 >= part.length) {
          _p = part.length;
          continue;
        }
        final c = part[_p] | (part[_p + 1] << 8);
        _p += 2;
        if (out.length < SheetLimits.maxCellText) out.add(c);
      } else {
        final c = part[_p++];
        if (out.length < SheetLimits.maxCellText) out.add(c);
      }
      left--;
    }
    return String.fromCharCodes(out);
  }
}

class _Xls {
  _Xls(this.cfb, this.loc);

  final CfbFile cfb;
  final SheetLocale loc;
  final book = DocBookBuilder();

  late Uint8List w;
  late ByteData bd;
  bool date1904 = false;
  int activeTab = 0;
  final fonts = <_Font>[];
  final formats = <int, String>{};
  final xfs = <_Xf>[];
  final palette = List<int>.of(excelPalette);
  final bound = <_Bound>[];
  List<String> sst = const [];
  bool sstTruncated = false;
  final Map<int, int> _xfStyle = {};
  final Map<int, SheetNumberFormat> _xfFormat = {};

  int u16(int at) => bd.getUint16(at, Endian.little);
  int u32(int at) => bd.getUint32(at, Endian.little);

  OfficeSheetsDoc read() {
    final entry = cfb.entry('Workbook');
    if (entry == null || !entry.isStream) {
      // Excel 5/95 пишет поток «Book» (BIFF5) — старый формат.
      if (cfb.hasStream('Book')) throw const OfficeDocException(OfficeDocError.legacy, 'biff5');
      throw const OfficeDocException(OfficeDocError.damaged, 'no workbook');
    }
    final head = cfb.readHead('Workbook', OfficeLimits.maxPartBytes)!;
    w = head.bytes;
    bd = ByteData.sublistView(w);
    if (head.truncated) book.truncated = true;
    if (w.length < 8) throw const OfficeDocException(OfficeDocError.damaged, 'short workbook');
    final type = u16(0);
    // BOF у BIFF2–4 — другие записи, у BIFF5 версия 0x0500.
    if (type == 0x0009 || type == 0x0209 || type == 0x0409) {
      throw const OfficeDocException(OfficeDocError.legacy, 'biff4');
    }
    if (type != _bof) throw const OfficeDocException(OfficeDocError.damaged, 'no bof');
    if (u16(4) != 0x0600) throw OfficeDocException(OfficeDocError.legacy, 'biff ${u16(4).toRadixString(16)}');
    final globalsEnd = _globals();

    // Листы — по смещениям из BoundSheet8; смещение не на BOF — по порядку
    // частей потока (так пишут некоторые программы).
    final starts = _substreams(globalsEnd);
    final sheets = <DocSheet>[];
    var active = 0;
    var damaged = 0;
    final visible = <(_Bound, int)>[];
    for (var k = 0; k < bound.length; k++) {
      final b = bound[k];
      var pos = b.pos;
      if (!starts.contains(pos)) pos = k < starts.length ? starts[k] : -1;
      if (pos < 0) continue;
      visible.add((b, pos));
    }
    for (var i = 0; i < visible.length; i++) {
      final (b, pos) = visible[i];
      try {
        final s = _sheet(b.name, pos, book.budgetFor(i, visible.length));
        if (s == null) continue;
        sheets.add(s);
        if (b.index == activeTab) active = sheets.length - 1;
      } on OfficeDocException catch (e) {
        // Испорченный лист — без него; предел всего документа — ошибка.
        if (e.kind != OfficeDocError.damaged) rethrow;
        damaged++;
      } on RangeError {
        damaged++;
      } on FormatException {
        damaged++;
      }
    }
    if (sheets.isEmpty && damaged > 0) throw const OfficeDocException(OfficeDocError.damaged, 'sheets');
    return OfficeSheetsDoc(
      sheets: sheets,
      styles: List.unmodifiable(book.styles),
      activeSheet: active,
      truncated: book.truncated || damaged > 0,
    );
  }

  /// Записи от [p]: вызывает [onRecord] (тип, начало данных, длина), пока
  /// он не вернёт false; возвращает смещение после последней записи.
  int _records(int p, bool Function(int type, int at, int len) onRecord) {
    while (p + 4 <= w.length) {
      final type = u16(p);
      final len = u16(p + 2);
      final at = p + 4;
      if (at + len > w.length) return w.length;
      p = at + len;
      if (!onRecord(type, at, len)) break;
    }
    return p;
  }

  /// Данные записи с её продолжениями CONTINUE.
  _Chunks _withContinues(int at, int len, int next) {
    final parts = [Uint8List.sublistView(w, at, at + len)];
    var p = next;
    while (p + 4 <= w.length && u16(p) == _continue) {
      final l = u16(p + 2);
      if (p + 4 + l > w.length) break;
      parts.add(Uint8List.sublistView(w, p + 4, p + 4 + l));
      p += 4 + l;
    }
    return _Chunks(parts);
  }

  // ── Общая часть книги ──

  int _globals() {
    var depth = 0;
    return _records(0, (type, at, len) {
      switch (type) {
        case _bof:
          depth++;
        case _eof:
          return --depth > 0;
        case _filePass:
          throw const OfficeDocException(OfficeDocError.encrypted, 'xls filepass');
        case _date1904:
          if (len >= 2) date1904 = u16(at) == 1;
        case _window1:
          if (len >= 12) activeTab = u16(at + 10);
        case _font:
          if (len >= 14 && fonts.length < SheetLimits.maxStyles) fonts.add(_readFont(at, len));
        case _formatRec:
          if (len >= 5 && formats.length < 2000) {
            final c = _Chunks([Uint8List.sublistView(w, at + 2, at + len)]);
            final cch = c.u16();
            formats[u16(at)] = c.chars(cch, c.byte() & 1 == 1);
          }
        case _xf:
          if (len >= 20 && xfs.length < SheetLimits.maxStyles * 4) xfs.add(_readXf(at));
        case _palette:
          if (len >= 2) {
            final n = math.min(u16(at), math.min(56, (len - 2) ~/ 4));
            for (var i = 0; i < n; i++) {
              final q = at + 2 + i * 4;
              palette[8 + i] = 0xFF000000 | (w[q] << 16) | (w[q + 1] << 8) | w[q + 2];
            }
          }
        case _boundSheet:
          if (len >= 8 && bound.length < SheetLimits.maxSheets * 4) {
            final index = _sheetIndex++;
            final hidden = w[at + 4] & 3 != 0;
            final dt = w[at + 5];
            final c = _Chunks([Uint8List.sublistView(w, at + 6, at + len)]);
            final cch = c.byte();
            final name = c.chars(cch, c.byte() & 1 == 1).trim();
            // Только видимые рабочие листы: диаграммы, модули VBA и листы
            // макросов Excel 4 — не таблицы.
            if (!hidden && dt == 0) {
              if (bound.length >= SheetLimits.maxSheets) {
                book.truncated = true;
              } else {
                bound.add(_Bound(name.isEmpty ? 'Sheet${index + 1}' : name, u32(at), index));
              }
            }
          }
        case _sst:
          _readSst(_withContinues(at, len, at + len));
      }
      return true;
    });
  }

  int _sheetIndex = 0;

  _Font _readFont(int at, int len) {
    final height = u16(at) / 20;
    final grbit = u16(at + 2);
    final icv = u16(at + 4);
    final bls = u16(at + 6);
    final uls = w[at + 10];
    var name = '';
    if (len >= 16) {
      final c = _Chunks([Uint8List.sublistView(w, at + 14, at + len)]);
      final cch = c.byte();
      name = c.chars(cch, c.byte() & 1 == 1);
    }
    final px = height <= 0 || height > 409 ? SheetFonts.px(10, name) : SheetFonts.px(height, name);
    return _Font(bls >= 600, grbit & 0x2 != 0, uls != 0, grbit & 0x8 != 0, px, icv);
  }

  _Xf _readXf(int at) {
    final align = w[at + 6];
    final b1 = u32(at + 10);
    final b2 = u32(at + 14);
    final c = u16(at + 18);
    return _Xf(
      u16(at),
      u16(at + 2),
      align & 7,
      (align >> 4) & 7,
      w[at + 8] & 0xF,
      align & 0x8 != 0,
      b1 & 0xF,
      (b1 >> 4) & 0xF,
      (b1 >> 8) & 0xF,
      (b1 >> 12) & 0xF,
      (b1 >> 16) & 0x7F,
      (b1 >> 23) & 0x7F,
      b2 & 0x7F,
      (b2 >> 7) & 0x7F,
      (b2 >> 26) & 0x3F,
      c & 0x7F,
      (c >> 7) & 0x7F,
    );
  }

  void _readSst(_Chunks c) {
    try {
      c.u32(); // всего строк в книге
      final unique = c.u32();
      const maxStrings = 1000000;
      final out = <String>[];
      while (out.length < unique && !c.atEnd) {
        if (out.length >= maxStrings) {
          sstTruncated = true;
          break;
        }
        final cch = c.u16();
        final flags = c.byte();
        final runs = flags & 0x8 != 0 ? c.u16() : 0;
        final ext = flags & 0x4 != 0 ? c.u32() : 0;
        out.add(_lines(c.chars(cch, flags & 1 == 1)));
        c.skip(runs * 4);
        c.skip(ext);
      }
      sst = out;
    } on FormatException {
      // Обрезанная таблица строк — что успели прочитать.
      sstTruncated = true;
    }
  }

  /// Переводы строк Excel («\r\n» и «\n» в ячейке) — «\n».
  static String _lines(String s) => s.contains('\r') ? s.replaceAll('\r\n', '\n').replaceAll('\r', '\n') : s;

  // ── Цвета и оформление ──

  /// Цвет из палитры по номеру; 64 и больше — «авто» (системные цвета).
  int? _pal(int icv) => icv >= 0 && icv < 64 ? palette[icv] : null;

  static int _mix(int fg, int bg, double k) {
    int ch(int shift) => (((fg >> shift) & 0xFF) * k + ((bg >> shift) & 0xFF) * (1 - k)).round().clamp(0, 255);
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  DocBorder? _side(int dg, int icv) {
    if (dg == 0) return null;
    final width = switch (dg) {
      2 || 8 || 10 || 12 || 13 => 2.0,
      5 || 6 => 3.0,
      _ => 1.0,
    };
    return DocBorder(color: _pal(icv), width: width);
  }

  /// Номер оформления в книге для XF [ixfe] ячейки.
  int _style(int ixfe) {
    final hit = _xfStyle[ixfe];
    if (hit != null) return hit;
    if (ixfe < 0 || ixfe >= xfs.length) return _xfStyle[ixfe] = 0;
    final x = xfs[ixfe];
    // Шрифта номер 4 в BIFF нет: номера от 5 — это (n − 1)-я запись Font.
    final fi = x.font < 4 ? x.font : x.font - 1;
    final f = fi >= 0 && fi < fonts.length ? fonts[fi] : null;
    int? fill;
    if (x.fls == 1) {
      fill = x.icvFore == 64 ? 0xFF000000 : (x.icvFore == 65 ? 0xFFFFFFFF : _pal(x.icvFore));
    } else if (x.fls > 1) {
      final fg = _pal(x.icvFore) ?? 0xFF000000;
      final bg = _pal(x.icvBack) ?? 0xFFFFFFFF;
      // Узор — средним цветом по плотности (как у XLSX).
      final k = switch (x.fls) {
        2 => 0.5,
        3 => 0.25,
        4 => 0.75,
        17 => 0.125,
        18 => 0.0625,
        _ => 0.5,
      };
      fill = _mix(fg, bg, k);
    }
    final style = DocCellStyle(
      bold: f?.b ?? false,
      italic: f?.i ?? false,
      underline: f?.u ?? false,
      strike: f?.s ?? false,
      fontSize: f?.px,
      // Чёрный текст — «авто»: так LibreOffice и 1С пишут цвет текста по
      // умолчанию (Excel — номером 0x7FFF); в тёмной теме он светлый.
      color: f == null || _pal(f.icv) == 0xFF000000 ? null : _pal(f.icv),
      fill: fill,
      hAlign: switch (x.alc) {
        1 => DocHAlign.left,
        2 || 6 => DocHAlign.center,
        3 => DocHAlign.right,
        5 || 7 => DocHAlign.justify,
        _ => DocHAlign.general,
      },
      vAlign: switch (x.alcV) {
        0 || 3 || 4 => DocVAlign.top,
        1 => DocVAlign.center,
        _ => DocVAlign.bottom,
      },
      wrap: x.wrap,
      indent: x.indent * 9.0,
      left: _side(x.dgLeft, x.icvLeft),
      top: _side(x.dgTop, x.icvTop),
      right: _side(x.dgRight, x.icvRight),
      bottom: _side(x.dgBottom, x.icvBottom),
    );
    return _xfStyle[ixfe] = book.style(style);
  }

  SheetNumberFormat _format(int ixfe) {
    final hit = _xfFormat[ixfe];
    if (hit != null) return hit;
    final id = ixfe >= 0 && ixfe < xfs.length ? xfs[ixfe].fmt : 0;
    final code = formats[id] ?? SheetNumberFormat.builtin(id, loc) ?? 'General';
    return _xfFormat[ixfe] = SheetNumberFormat(code);
  }

  // ── Листы ──

  /// Начала частей потока после общей: смещения записей BOF верхнего уровня.
  List<int> _substreams(int from) {
    final out = <int>[];
    var depth = 0;
    _records(from, (type, at, len) {
      if (type == _bof) {
        if (depth == 0) out.add(at - 4);
        depth++;
      } else if (type == _eof && depth > 0) {
        depth--;
      }
      return out.length <= SheetLimits.maxSheets * 4;
    });
    return out;
  }

  DocSheet? _sheet(String name, int pos, int budget) {
    if (pos < 0 || pos + 8 > w.length || u16(pos) != _bof) {
      throw const OfficeDocException(OfficeDocError.damaged, 'sheet bof');
    }
    // Только рабочий лист (у диаграммы и макросов — другой вид в BOF).
    final dt = u16(pos + 6);
    if (dt != 0x0010) return null;
    final sb = DocSheetBuilder(book, name, budget: budget);
    var depth = 0;
    var frozen = false;
    var full = false;
    // Ячейка формулы со строковым результатом ждёт следующую запись String.
    var strRow = -1, strCol = -1, strXf = 0;

    void cell(int row, int col, int ixfe, String text, DocCellKind kind) {
      if (full) return;
      var t = text;
      if (kind == DocCellKind.text && t.isNotEmpty) {
        final fmt = _format(ixfe);
        if (fmt.code != 'General') t = fmt.formatText(t) ?? t;
      }
      if (row >= SheetLimits.maxRows) {
        if (t.isNotEmpty) sb.truncated = true;
        return;
      }
      if (!sb.add(row, col, t, style: _style(ixfe), kind: kind)) full = true;
    }

    void number(int row, int col, int ixfe, double v) {
      if (full) return;
      final fmt = _format(ixfe);
      final r = identical(fmt, SheetNumberFormat.general) || fmt.code == 'General'
          ? SheetFormatted(SheetNumberFormat.generalText(v, loc))
          : fmt.format(v, loc, date1904: date1904);
      var st = _style(ixfe);
      if (r.color != null) st = book.withColor(st, r.color!);
      if (row >= SheetLimits.maxRows) {
        sb.truncated = true;
        return;
      }
      if (!sb.add(row, col, r.text, style: st, kind: DocCellKind.number)) full = true;
    }

    _records(pos, (type, at, len) {
      if (type == _bof) {
        depth++;
        return true;
      }
      if (type == _eof) return --depth > 0;
      // Вложенные части (диаграмма на листе) — пропускаются.
      if (depth != 1) return true;
      if (type != _string && type != _continue) strRow = -1;
      switch (type) {
        case _labelSst:
          if (len >= 10) {
            final i = u32(at + 6);
            if (i < sst.length) {
              cell(u16(at), u16(at + 2), u16(at + 4), sst[i], DocCellKind.text);
            } else if (sstTruncated) {
              sb.truncated = true;
            }
          }
        case _label || _rString:
          if (len >= 9) {
            final c = _Chunks([Uint8List.sublistView(w, at + 6, at + len)]);
            final cch = c.u16();
            cell(u16(at), u16(at + 2), u16(at + 4), _lines(c.chars(cch, c.byte() & 1 == 1)), DocCellKind.text);
          }
        case _number:
          if (len >= 14) number(u16(at), u16(at + 2), u16(at + 4), bd.getFloat64(at + 6, Endian.little));
        case _rk:
          if (len >= 10) number(u16(at), u16(at + 2), u16(at + 4), _rkValue(u32(at + 6)));
        case _mulRk:
          if (len >= 6) {
            final row = u16(at);
            final first = u16(at + 2);
            final n = (len - 6) ~/ 6;
            for (var i = 0; i < n && !full; i++) {
              final q = at + 4 + i * 6;
              number(row, first + i, u16(q), _rkValue(u32(q + 2)));
            }
          }
        case _boolErr:
          if (len >= 8) {
            final v = w[at + 6];
            if (w[at + 7] == 0) {
              cell(u16(at), u16(at + 2), u16(at + 4), v != 0 ? loc.trueText : loc.falseText, DocCellKind.boolean);
            } else {
              cell(u16(at), u16(at + 2), u16(at + 4), _error(v), DocCellKind.error);
            }
          }
        case _formula:
          if (len >= 20) {
            final row = u16(at), col = u16(at + 2), ixfe = u16(at + 4);
            if (u16(at + 12) == 0xFFFF) {
              switch (w[at + 6]) {
                case 0:
                  strRow = row;
                  strCol = col;
                  strXf = ixfe;
                case 1:
                  cell(row, col, ixfe, w[at + 8] != 0 ? loc.trueText : loc.falseText, DocCellKind.boolean);
                case 2:
                  cell(row, col, ixfe, _error(w[at + 8]), DocCellKind.error);
                default:
                  cell(row, col, ixfe, '', DocCellKind.text);
              }
            } else {
              number(row, col, ixfe, bd.getFloat64(at + 6, Endian.little));
            }
          }
        case _string:
          if (strRow >= 0 && len >= 3) {
            final c = _withContinues(at, len, at + len);
            final cch = c.u16();
            cell(strRow, strCol, strXf, _lines(c.chars(cch, c.byte() & 1 == 1)), DocCellKind.text);
          }
          strRow = -1;
        case _blank:
          if (len >= 6) cell(u16(at), u16(at + 2), u16(at + 4), '', DocCellKind.text);
        case _mulBlank:
          if (len >= 6) {
            final row = u16(at);
            final first = u16(at + 2);
            final n = (len - 6) ~/ 2;
            for (var i = 0; i < n && !full; i++) {
              cell(row, first + i, u16(at + 4 + i * 2), '', DocCellKind.text);
            }
          }
        case _colInfo:
          if (len >= 10) {
            final first = u16(at), last = u16(at + 2);
            final hidden = u16(at + 8) & 1 != 0;
            final px = hidden ? 0.0 : XlsxReader.colWidthPx(u16(at + 4) / 256);
            for (var c = first; c <= math.min(last, SheetLimits.maxCols - 1); c++) {
              sb.colWidth(c, px);
            }
          }
        case _defColWidth:
          if (len >= 2) sb.defaultColWidth = ((u16(at) + 0.43) * 7 + 5).roundToDouble();
        case _standardWidth:
          if (len >= 2 && u16(at) > 0) sb.defaultColWidth = XlsxReader.colWidthPx(u16(at) / 256);
        case _defaultRowHeight:
          if (len >= 4) {
            final hidden = u16(at) & 2 != 0;
            final h = u16(at + 2) / 20 * 96 / 72;
            sb.defaultRowHeight = hidden ? 0 : (h > 0 ? h : 20);
          }
        case _row:
          if (len >= 16) {
            final r = u16(at);
            if (r < SheetLimits.maxRows) {
              final hidden = w[at + 12] & 0x20 != 0;
              sb.rowHeight(r, hidden ? 0 : (u16(at + 6) & 0x7FFF) / 20 * 96 / 72);
            }
          }
        case _mergeCells:
          if (len >= 2) {
            final n = math.min(u16(at), (len - 2) ~/ 8);
            for (var i = 0; i < n; i++) {
              final q = at + 2 + i * 8;
              final m = DocMerge(u16(q), u16(q + 4), u16(q + 2), u16(q + 6));
              if (m.lastRow >= m.row && m.lastCol >= m.col && (m.lastRow > m.row || m.lastCol > m.col)) sb.merge(m);
            }
          }
        case _window2:
          if (len >= 2) {
            final f = u16(at);
            sb.showGrid = f & 0x2 != 0;
            frozen = f & 0x8 != 0;
          }
        case _pane:
          if (len >= 4 && frozen) {
            sb.frozenCols = u16(at).clamp(0, SheetLimits.maxCols);
            sb.frozenRows = u16(at + 2).clamp(0, SheetLimits.maxRows);
          }
      }
      return true;
    });
    return sb.build();
  }

  /// Число RK: 30 бит целого или старшие 30 бит double; бит 0 — «÷ 100».
  static double _rkValue(int rk) {
    double v;
    if (rk & 2 != 0) {
      v = (rk.toSigned(32) >> 2).toDouble();
    } else {
      final b = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      v = b.getFloat64(0, Endian.little);
    }
    return rk & 1 != 0 ? v / 100 : v;
  }

  static String _error(int code) => switch (code) {
    0x00 => '#NULL!',
    0x07 => '#DIV/0!',
    0x0F => '#VALUE!',
    0x17 => '#REF!',
    0x1D => '#NAME?',
    0x24 => '#NUM!',
    0x2A => '#N/A',
    _ => '#N/A',
  };
}

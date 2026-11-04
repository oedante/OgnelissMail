// lib/services/documents/csv_reader.dart
// CSV и TSV → лист для показа сеткой (1.11.x, предпросмотр документов, план
// владельца 04.11.2026). По RFC 4180: поля в кавычках, «""» — кавычка,
// переводы строки внутри кавычек, концы строк CRLF, LF и CR.
//
// Русский Excel сохраняет «CSV (разделители — запятые)» в Windows-1251 и с
// «;» (запятая у нас — десятичный разделитель), поэтому:
//  · кодировка — по метке BOM (UTF-8, UTF-16), иначе UTF-8, если байты им
//    являются, иначе Windows-1251 для кириллицы (по байтам или по языку
//    приложения), иначе Windows-1252;
//  · разделитель — подсказка Excel «sep=;» в первой строке, у .tsv —
//    табуляция, иначе самый «ровный» из «,» «;» табуляции «|» по первым
//    строкам (вне кавычек): одинаковое число в каждой строке;
//  · числа и даты вправо, как в Excel; ширина столбцов — по тексту.
// Большой файл — только начало ([SheetLimits.maxCsvBytes]): «показано начало».

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/utils/charset_handler.dart';
import 'doc_sheets.dart';
import 'office_package.dart';

class CsvReader {
  CsvReader._();

  /// Разобрать файл [bytes]; [fileName] — для разделителя (.tsv) и имени
  /// листа, [lang] — язык приложения (кириллица — Windows-1251 по умолчанию).
  static OfficeSheetsDoc read(Uint8List bytes, {String fileName = '', String lang = 'en'}) {
    try {
      return _read(bytes, fileName, lang);
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, 'csv: $e');
    }
  }

  static OfficeSheetsDoc _read(Uint8List bytes, String fileName, String lang) {
    final cut = bytes.length > SheetLimits.maxCsvBytes;
    final head = cut ? Uint8List.sublistView(bytes, 0, SheetLimits.maxCsvBytes) : bytes;
    var text = decode(head, lang: lang, truncated: cut);
    final ext = fileName.toLowerCase();
    String? delim = ext.endsWith('.tsv') || ext.endsWith('.tab') ? '\t' : null;
    // Подсказка Excel: «sep=;» первой строкой.
    final hint = RegExp(r'^sep=(.)\r?\n', caseSensitive: false).firstMatch(text);
    if (hint != null) {
      delim = hint.group(1);
      text = text.substring(hint.end);
    }
    delim ??= detectDelimiter(text);
    final book = DocBookBuilder();
    final name = _sheetName(fileName);
    final sb = DocSheetBuilder(book, name, defaultColWidth: 64, defaultRowHeight: 20);
    final number = book.style(const DocCellStyle());
    final rows = parse(text, delim, maxRows: SheetLimits.maxRows + 1, dropLastPartial: cut);
    final widths = <int, int>{};
    var r = 0;
    for (final row in rows) {
      if (r >= SheetLimits.maxRows) {
        sb.truncated = true;
        break;
      }
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        if (v.isEmpty) continue;
        if (c >= SheetLimits.maxCols) {
          sb.truncated = true;
          break;
        }
        final kind = looksNumeric(v) ? DocCellKind.number : DocCellKind.text;
        if (!sb.add(r, c, v, style: number, kind: kind)) break;
        if (r < 1000) {
          var len = 0;
          for (final line in v.split('\n')) {
            len = math.max(len, line.length);
          }
          widths[c] = math.max(widths[c] ?? 0, len);
        }
      }
      if (sb.full) {
        sb.truncated = true;
        break;
      }
      r++;
    }
    // Ширина по самому длинному значению первых строк (≈ 7 точек на знак),
    // в разумных пределах: длинный текст читается в строке сверху.
    widths.forEach((c, len) => sb.colWidth(c, (len * 7.2 + 12).clamp(48, 320).roundToDouble()));
    if (cut) sb.truncated = true;
    return OfficeSheetsDoc(sheets: [sb.build()], styles: List.unmodifiable(book.styles));
  }

  static String _sheetName(String fileName) {
    var n = fileName.split(RegExp(r'[/\\]')).last;
    final dot = n.lastIndexOf('.');
    if (dot > 0) n = n.substring(0, dot);
    return n.isEmpty ? 'CSV' : n;
  }

  /// Текст файла: BOM → UTF-8/UTF-16; верный UTF-8 → UTF-8; кириллица
  /// (по байтам или по языку) → Windows-1251; иначе Windows-1252.
  static String decode(Uint8List b, {String lang = 'en', bool truncated = false}) {
    if ((b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) ||
        (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF)))) {
      return OfficeZip.decodeText(b);
    }
    // UTF-16 без метки (выгрузки «Юникод» из старых программ): через байт нули.
    if (b.length >= 4 && b[1] == 0 && b[3] == 0 && b[0] != 0) {
      final units = Uint16List(b.length ~/ 2);
      for (var i = 0; i < units.length; i++) {
        units[i] = b[2 * i] | (b[2 * i + 1] << 8);
      }
      return String.fromCharCodes(units);
    }
    var end = b.length;
    if (truncated) {
      // Обрезанный посередине знак UTF-8 — не повод решить, что это не UTF-8.
      var k = end - 1;
      var back = 0;
      while (k >= 0 && back < 3 && (b[k] & 0xC0) == 0x80) {
        k--;
        back++;
      }
      if (k >= 0 && b[k] >= 0xC0) end = k;
    }
    try {
      return utf8.decode(Uint8List.sublistView(b, 0, end));
    } on FormatException {
      // не UTF-8
    }
    if (_cyrillicLang(lang) || looksCp1251(b)) return CharsetHandler.decode(b, 'windows-1251');
    return _cp1252(b);
  }

  static bool _cyrillicLang(String lang) => const {
    'ru',
    'uk',
    'be',
    'bg',
    'kk',
    'sr',
    'mk',
    'ky',
    'tg',
    'mn',
  }.contains(lang.toLowerCase().split(RegExp('[-_]')).first);

  /// Байты похожи на русский текст в Windows-1251: среди букв много байтов
  /// 0xC0–0xFF, и они идут подряд (слово целиком), а не по одной, как
  /// «é» и «ü» в западных языках.
  static bool looksCp1251(Uint8List b) {
    var high = 0;
    var latin = 0;
    var runs = 0;
    var run = 0;
    final n = math.min(b.length, 64 * 1024);
    for (var i = 0; i < n; i++) {
      final x = b[i];
      if (x >= 0xC0 || x == 0xA8 || x == 0xB8) {
        high++;
        run++;
        if (run == 3) runs++;
      } else {
        run = 0;
        if ((x >= 0x41 && x <= 0x5A) || (x >= 0x61 && x <= 0x7A)) latin++;
      }
    }
    if (high == 0) return false;
    return runs >= 2 && high * 2 >= latin;
  }

  static const _w1252 = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, //
    0x017D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
    0x0153, 0x9D, 0x017E, 0x0178,
  ];

  static String _cp1252(Uint8List b) {
    final out = Uint16List(b.length);
    for (var i = 0; i < b.length; i++) {
      final x = b[i];
      out[i] = x >= 0x80 && x < 0xA0 ? _w1252[x - 0x80] : x;
    }
    return String.fromCharCodes(out);
  }

  /// Разделитель по первым строкам: у кого число вхождений вне кавычек
  /// одинаковое в большинстве строк. При равенстве — табуляция, «;», «|»,
  /// затем «,»: в русских файлах запятая — ещё и в числах («1,5;2,5»).
  static String detectDelimiter(String text) {
    const candidates = ['\t', ';', '|', ','];
    final counts = {for (final c in candidates) c: <int>[]};
    final cur = {for (final c in candidates) c: 0};
    var quoted = false;
    var lines = 0;
    var any = false;
    for (var i = 0; i < text.length && lines < 30 && i < 256 * 1024; i++) {
      final ch = text[i];
      if (ch == '"') {
        quoted = !quoted;
        continue;
      }
      if (quoted) continue;
      if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        if (any) {
          for (final c in candidates) {
            counts[c]!.add(cur[c]!);
            cur[c] = 0;
          }
          lines++;
        }
        any = false;
        continue;
      }
      any = true;
      if (cur.containsKey(ch)) cur[ch] = cur[ch]! + 1;
    }
    if (any && lines < 30) {
      for (final c in candidates) {
        counts[c]!.add(cur[c]!);
      }
    }
    String? best;
    var bestScore = 0.0;
    for (final c in candidates) {
      final list = counts[c]!;
      if (list.isEmpty) continue;
      final freq = <int, int>{};
      for (final n in list) {
        if (n > 0) freq[n] = (freq[n] ?? 0) + 1;
      }
      if (freq.isEmpty) continue;
      final mode = freq.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final consistency = mode.value / list.length;
      // Строгий порядок предпочтения при «ровном» разделителе.
      if (consistency >= 0.8) return c;
      if (consistency > bestScore) {
        bestScore = consistency;
        best = c;
      }
    }
    return best ?? ',';
  }

  /// Строки полей. [dropLastPartial] — у обрезанного файла последняя строка
  /// неполная: её не показываем.
  static List<List<String>> parse(String text, String delim, {int maxRows = 1 << 30, bool dropLastPartial = false}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var wasQuoted = false;
    final d = delim.codeUnitAt(0);
    final n = text.length;
    var i = 0;
    void endField() {
      row.add(
        field.length > SheetLimits.maxCellText
            ? field.toString().substring(0, SheetLimits.maxCellText)
            : field.toString(),
      );
      field.clear();
      wasQuoted = false;
    }

    while (i < n) {
      final ch = text.codeUnitAt(i);
      if (quoted) {
        if (ch == 0x22) {
          if (i + 1 < n && text.codeUnitAt(i + 1) == 0x22) {
            field.writeCharCode(0x22);
            i += 2;
            continue;
          }
          quoted = false;
          i++;
          continue;
        }
        if (ch == 0x0D) {
          // Перевод строки внутри поля — «\n».
          field.writeCharCode(0x0A);
          i += (i + 1 < n && text.codeUnitAt(i + 1) == 0x0A) ? 2 : 1;
          continue;
        }
        if (field.length <= SheetLimits.maxCellText) field.writeCharCode(ch);
        i++;
        continue;
      }
      if (ch == 0x22 && field.isEmpty && !wasQuoted) {
        quoted = true;
        wasQuoted = true;
        i++;
        continue;
      }
      if (ch == d) {
        endField();
        i++;
        continue;
      }
      if (ch == 0x0A || ch == 0x0D) {
        endField();
        rows.add(row);
        row = <String>[];
        if (rows.length >= maxRows) return rows;
        i += (ch == 0x0D && i + 1 < n && text.codeUnitAt(i + 1) == 0x0A) ? 2 : 1;
        continue;
      }
      if (field.length <= SheetLimits.maxCellText) field.writeCharCode(ch);
      i++;
    }
    if (!dropLastPartial && (field.isNotEmpty || row.isNotEmpty || wasQuoted)) {
      endField();
      rows.add(row);
    }
    // Пустые строки в конце файла — не строки таблицы.
    while (rows.isNotEmpty && rows.last.every((f) => f.isEmpty)) {
      rows.removeLast();
    }
    return rows;
  }

  static final _num = RegExp(
    r'^[-+−]?[(]?(?:[$€£¥₽]\s?)?(?:\d{1,3}(?:[   .,’\x27]\d{3})+|\d+)(?:[.,]\d+)?(?:[eE][-+]?\d+)?[)]?'
    r'\s?(?:%|[$€£¥₽]|руб\.?|р\.)?$',
  );
  static final _date = RegExp(
    r'^(?:\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}-\d{2}-\d{2})(?:[ T]\d{1,2}:\d{2}(?::\d{2})?)?$',
  );
  static final _time = RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$');

  /// Число, сумма, процент, дата или время — как Excel, вправо.
  static bool looksNumeric(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 40) return false;
    return _num.hasMatch(t) || _date.hasMatch(t) || _time.hasMatch(t);
  }
}

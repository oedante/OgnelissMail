// lib/services/documents/pdf_text.dart
// Текст PDF для поиска по вложениям (1.15.1, технические хвосты по решению
// владельца 07.11.2026: «PDF во вложениях не ищется — нет читателя PDF»).
//
// Свой разбор по ISO 32000 без сторонних библиотек: объекты (и сжатые потоки
// объектов PDF 1.5+), фильтры FlateDecode (zlib из dart:io), ASCIIHex,
// ASCII85 и LZW, дерево страниц и формы (XObject), операторы текста (Tj, TJ,
// ', ", Td, TD, T*, Tm), шрифты: таблица ToUnicode, кодировки WinAnsi,
// MacRoman, Standard и /Differences (в том числе кириллица по именам
// afii100xx и uniXXXX). PDF, защищённые без пароля на открытие (стандартная
// защита: RC4 40–128 бит, AES-128, AES-256), расшифровываются — так
// защищены многие выписки и счета; с паролем на открытие текста нет.
//
// Файл — из чужого письма: пределы на размер, распакованные потоки, число
// объектов и глубину вложенности; ошибки не бросаются — что разобрали, то и
// текст. Вызывается в изоляте поиска по вложениям с пределом времени
// (AttachmentText.extractFile).

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

/// Имя PDF (/Type и т. п.) — без косой черты.
class PdfName {
  final String name;
  const PdfName(this.name);
  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => '/$name';
}

/// Строка PDF — байты (кодировку знает шрифт).
class PdfString {
  final Uint8List bytes;
  const PdfString(this.bytes);
}

/// Ссылка на объект «N G R».
class PdfRef {
  final int num;
  final int gen;
  const PdfRef(this.num, this.gen);
}

/// Поток: словарь и сырые (ещё не распакованные) данные.
class PdfStream {
  final Map<String, Object?> dict;
  final Uint8List raw;
  const PdfStream(this.dict, this.raw);
}

/// Оператор содержимого страницы (Tj, BT…).
class _Op {
  final String name;
  const _Op(this.name);
}

class PdfText {
  PdfText._();

  /// Файл крупнее — не читается.
  static const maxBytes = 80 * 1024 * 1024;

  /// Распакованный поток — не больше.
  static const maxStream = 32 * 1024 * 1024;

  /// Всего распакованных данных на файл.
  static const maxTotalDecoded = 160 * 1024 * 1024;

  /// Объектов в файле — не больше.
  static const maxObjects = 400000;

  /// Страниц — не больше.
  static const maxPages = 5000;

  /// Файл похож на PDF (сигнатура в первом килобайте).
  static bool looksLikePdf(Uint8List head) {
    final n = math.min(head.length, 1024);
    for (var i = 0; i + 4 < n; i++) {
      if (head[i] == 0x25 && head[i + 1] == 0x50 && head[i + 2] == 0x44 && head[i + 3] == 0x46 && head[i + 4] == 0x2D) {
        return true;
      }
    }
    return false;
  }

  /// Текст PDF: страницы через пустую строку, не длиннее [maxChars]. Ошибок
  /// не бросает.
  static String extract(Uint8List data, {int maxChars = 100 * 1024}) {
    if (data.length > maxBytes || !looksLikePdf(data)) return '';
    try {
      return _Pdf(data).text(maxChars);
    } catch (_) {
      return '';
    }
  }
}

// ───────────────────────────── лексер ─────────────────────────────

bool _isWs(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00;
bool _isDelim(int c) =>
    c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

class _Lexer {
  _Lexer(this.b, [this.pos = 0]);
  final Uint8List b;
  int pos;

  bool get atEnd => pos >= b.length;

  void skipWs() {
    while (pos < b.length) {
      final c = b[pos];
      if (_isWs(c)) {
        pos++;
      } else if (c == 0x25) {
        // Комментарий до конца строки.
        while (pos < b.length && b[pos] != 0x0A && b[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  String _word() {
    final start = pos;
    while (pos < b.length && !_isWs(b[pos]) && !_isDelim(b[pos])) {
      pos++;
    }
    return latin1.decode(Uint8List.sublistView(b, start, pos));
  }

  /// Следующий объект или оператор; [ops] — содержимое страницы (слова —
  /// операторы), иначе слова — ключевые (true/false/null/R/obj/stream).
  /// [depth] — вложенность массивов и словарей.
  Object? next({bool ops = false, int depth = 0}) {
    skipWs();
    if (atEnd) throw const FormatException('конец данных');
    if (depth > 64) throw const FormatException('слишком глубоко');
    final c = b[pos];
    if (c == 0x2F) {
      pos++;
      return PdfName(_nameValue(_word()));
    }
    if (c == 0x28) return PdfString(_literal());
    if (c == 0x3C) {
      if (pos + 1 < b.length && b[pos + 1] == 0x3C) {
        pos += 2;
        return _dict(ops: ops, depth: depth + 1);
      }
      return PdfString(_hex());
    }
    if (c == 0x5B) {
      pos++;
      final list = <Object?>[];
      while (true) {
        skipWs();
        if (atEnd) break;
        if (b[pos] == 0x5D) {
          pos++;
          break;
        }
        final v = next(ops: ops, depth: depth + 1);
        if (!ops && v is _Op && v.name == 'R' && list.length >= 2) {
          final g = list.removeLast(), n = list.removeLast();
          list.add(PdfRef((n as num).toInt(), (g as num).toInt()));
        } else {
          list.add(v);
        }
      }
      return list;
    }
    if (c == 0x5D || c == 0x3E || c == 0x29 || c == 0x7B || c == 0x7D) {
      pos++;
      return const _Op('?');
    }
    final w = _word();
    if (w.isEmpty) {
      pos++;
      return const _Op('?');
    }
    final n = num.tryParse(w);
    if (n != null) return n;
    if (w.startsWith('+') || w.startsWith('-') || w.startsWith('.')) {
      final d = double.tryParse(w.startsWith('.') ? '0$w' : w);
      if (d != null) return d;
    }
    switch (w) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    return _Op(w);
  }

  Map<String, Object?> _dict({bool ops = false, int depth = 0}) {
    final m = <String, Object?>{};
    while (true) {
      skipWs();
      if (atEnd) break;
      if (b[pos] == 0x3E && pos + 1 < b.length && b[pos + 1] == 0x3E) {
        pos += 2;
        break;
      }
      final k = next(ops: ops, depth: depth);
      if (k is! PdfName) continue;
      var v = next(ops: ops, depth: depth);
      // «N G R» — ссылка.
      if (!ops && v is num) {
        final save = pos;
        try {
          final g = next(ops: ops, depth: depth);
          final r = next(ops: ops, depth: depth);
          if (g is num && r is _Op && r.name == 'R') {
            v = PdfRef(v.toInt(), g.toInt());
          } else {
            pos = save;
          }
        } catch (_) {
          pos = save;
        }
      }
      m[k.name] = v;
    }
    return m;
  }

  static String _nameValue(String w) {
    if (!w.contains('#')) return w;
    final out = StringBuffer();
    for (var i = 0; i < w.length; i++) {
      if (w[i] == '#' && i + 2 < w.length) {
        final v = int.tryParse(w.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          out.writeCharCode(v);
          i += 2;
          continue;
        }
      }
      out.write(w[i]);
    }
    return out.toString();
  }

  Uint8List _literal() {
    pos++; // (
    final out = BytesBuilder(copy: false);
    var depth = 1;
    while (pos < b.length) {
      final c = b[pos++];
      if (c == 0x5C) {
        if (pos >= b.length) break;
        final e = b[pos++];
        switch (e) {
          case 0x6E:
            out.addByte(0x0A);
          case 0x72:
            out.addByte(0x0D);
          case 0x74:
            out.addByte(0x09);
          case 0x62:
            out.addByte(0x08);
          case 0x66:
            out.addByte(0x0C);
          case 0x0D:
            if (pos < b.length && b[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var k = 0; k < 2 && pos < b.length && b[pos] >= 0x30 && b[pos] <= 0x37; k++) {
                v = v * 8 + (b[pos++] - 0x30);
              }
              out.addByte(v & 0xFF);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.addByte(c);
      } else {
        out.addByte(c);
      }
    }
    return out.takeBytes();
  }

  Uint8List _hex() {
    pos++; // <
    final out = BytesBuilder(copy: false);
    int? hi;
    while (pos < b.length) {
      final c = b[pos++];
      if (c == 0x3E) break;
      final v = _hexVal(c);
      if (v < 0) continue;
      if (hi == null) {
        hi = v;
      } else {
        out.addByte(hi * 16 + v);
        hi = null;
      }
    }
    if (hi != null) out.addByte(hi * 16);
    return out.takeBytes();
  }
}

int _hexVal(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x37;
  if (c >= 0x61 && c <= 0x66) return c - 0x57;
  return -1;
}

int _indexOf(Uint8List b, List<int> pat, int from, [int? to]) {
  final end = math.min(to ?? b.length, b.length) - pat.length;
  outer:
  for (var i = math.max(0, from); i <= end; i++) {
    for (var k = 0; k < pat.length; k++) {
      if (b[i + k] != pat[k]) continue outer;
    }
    return i;
  }
  return -1;
}

int _lastIndexOf(Uint8List b, List<int> pat) {
  for (var i = b.length - pat.length; i >= 0; i--) {
    var ok = true;
    for (var k = 0; k < pat.length; k++) {
      if (b[i + k] != pat[k]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

final _kObj = ascii.encode('obj');
final _kStream = ascii.encode('stream');
final _kEndstream = ascii.encode('endstream');
final _kTrailer = ascii.encode('trailer');

// ───────────────────────────── документ ─────────────────────────────

class _Pdf {
  _Pdf(this.data) {
    _scanObjects();
    _readTrailer();
    _setupEncryption();
    _loadObjectStreams();
  }

  final Uint8List data;

  /// Номер объекта → смещение «N G obj» в файле (последнее определение).
  final _offsets = <int, int>{};

  /// Уже прочитанные объекты.
  final _cache = <int, Object?>{};

  /// Объекты из сжатых потоков объектов.
  final _packed = <int, Object?>{};

  Map<String, Object?> _trailer = {};
  _Crypt? _crypt;
  int _decoded = 0;

  // Все «N G obj» по файлу: таблицы xref бывают испорчены, а дописанные
  // в конец версии объектов — позже прежних.
  void _scanObjects() {
    var i = 0;
    while (_offsets.length < PdfText.maxObjects) {
      final at = _indexOf(data, _kObj, i);
      if (at < 0) break;
      i = at + 3;
      // После «obj» — разделитель (не «object»).
      if (at + 3 < data.length && !_isWs(data[at + 3]) && !_isDelim(data[at + 3])) continue;
      // Назад: пробел, поколение, пробел, номер.
      var p = at - 1;
      if (p < 0 || !_isWs(data[p])) continue;
      while (p >= 0 && _isWs(data[p])) {
        p--;
      }
      final genEnd = p + 1;
      while (p >= 0 && data[p] >= 0x30 && data[p] <= 0x39) {
        p--;
      }
      if (p + 1 == genEnd || p < 0 || !_isWs(data[p])) continue;
      while (p >= 0 && _isWs(data[p])) {
        p--;
      }
      final numEnd = p + 1;
      while (p >= 0 && data[p] >= 0x30 && data[p] <= 0x39) {
        p--;
      }
      if (p + 1 == numEnd) continue;
      final num = int.tryParse(latin1.decode(Uint8List.sublistView(data, p + 1, numEnd)));
      if (num == null) continue;
      _offsets[num] = p + 1;
    }
  }

  void _readTrailer() {
    // Классический «trailer <<…>>» (последний — самый новый).
    final at = _lastIndexOf(data, _kTrailer);
    if (at >= 0) {
      try {
        final lx = _Lexer(data, at + _kTrailer.length);
        final d = lx.next();
        if (d is Map<String, Object?>) _trailer = d;
      } catch (_) {}
    }
    if (_trailer['Root'] != null) return;
    // PDF 1.5+: словарь потока перекрёстных ссылок (/Type /XRef).
    for (final n in _offsets.keys.toList().reversed) {
      final o = _rawObject(n);
      if (o is PdfStream && _isName(o.dict['Type'], 'XRef')) {
        _trailer = {..._trailer, ...o.dict};
        if (_trailer['Root'] != null) return;
      }
    }
  }

  void _setupEncryption() {
    final e = _resolve(_trailer['Encrypt']);
    if (e is! Map<String, Object?>) return;
    final ids = _trailer['ID'];
    final id = ids is List && ids.isNotEmpty && ids.first is PdfString ? (ids.first as PdfString).bytes : Uint8List(0);
    _crypt = _Crypt.standard(e, id, (o) => _resolve(o));
    _encryptNum = _trailer['Encrypt'] is PdfRef ? (_trailer['Encrypt'] as PdfRef).num : null;
  }

  int? _encryptNum;

  void _loadObjectStreams() {
    for (final n in _offsets.keys.toList()) {
      if (_packed.length > PdfText.maxObjects) break;
      final o = _object(n);
      if (o is! PdfStream || !_isName(o.dict['Type'], 'ObjStm')) continue;
      try {
        final body = _decode(o, n, 0);
        final count = _int(o.dict['N']), first = _int(o.dict['First']);
        if (body == null || count == null || first == null || first > body.length) continue;
        final lx = _Lexer(body);
        final pairs = <(int, int)>[];
        for (var k = 0; k < count && k < 100000; k++) {
          final on = lx.next(), off = lx.next();
          if (on is! num || off is! num) break;
          pairs.add((on.toInt(), off.toInt()));
        }
        for (final (on, off) in pairs) {
          // Объект вне потока (дописанный позже) — главнее.
          if (_offsets.containsKey(on) && on != n) {
            final direct = _rawObject(on);
            if (direct != null) continue;
          }
          try {
            _packed[on] = _Lexer(body, first + off).next();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  static bool _isName(Object? o, String n) => o is PdfName && o.name == n;
  static int? _int(Object? o) => o is num ? o.toInt() : null;

  /// Объект без расшифровки строк (для словаря шифрования и служебного).
  Object? _rawObject(int n) {
    final off = _offsets[n];
    if (off == null) return null;
    try {
      final lx = _Lexer(data, off);
      lx.next(); // номер
      lx.next(); // поколение
      final kw = lx.next();
      if (kw is! _Op || kw.name != 'obj') return null;
      final v = lx.next();
      if (v is Map<String, Object?>) {
        lx.skipWs();
        if (_indexOf(data, _kStream, lx.pos, lx.pos + 6) == lx.pos) {
          var start = lx.pos + 6;
          if (start < data.length && data[start] == 0x0D) start++;
          if (start < data.length && data[start] == 0x0A) start++;
          var len = _int(v['Length']);
          if (len == null && v['Length'] is PdfRef) {
            final ln = _rawObject((v['Length'] as PdfRef).num);
            len = _int(ln);
          }
          int end;
          if (len != null && len >= 0 && start + len <= data.length) {
            end = start + len;
            // Длина неверна — ищем endstream.
            final check = _indexOf(data, _kEndstream, end, math.min(data.length, end + 32));
            if (check < 0) {
              final e = _indexOf(data, _kEndstream, start);
              if (e > 0) end = e;
            }
          } else {
            final e = _indexOf(data, _kEndstream, start);
            if (e < 0) return null;
            end = e;
          }
          return PdfStream(v, Uint8List.sublistView(data, start, end));
        }
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Объект номер [n] (строки расшифрованы).
  Object? _object(int n) {
    if (_cache.containsKey(n)) return _cache[n];
    _cache[n] = null; // защита от циклов
    Object? v;
    if (_packed.containsKey(n)) {
      // Строки в потоке объектов не шифруются отдельно.
      v = _packed[n];
    } else {
      v = _rawObject(n);
      final c = _crypt;
      if (c != null && n != _encryptNum) v = _decryptStrings(v, c, n, 0);
    }
    _cache[n] = v;
    return v;
  }

  Object? _decryptStrings(Object? v, _Crypt c, int n, int depth) {
    if (depth > 32) return v;
    if (v is PdfString) return PdfString(c.decryptString(v.bytes, n, 0));
    if (v is List) return [for (final e in v) _decryptStrings(e, c, n, depth + 1)];
    if (v is Map<String, Object?>) return {for (final e in v.entries) e.key: _decryptStrings(e.value, c, n, depth + 1)};
    if (v is PdfStream) return PdfStream(_decryptStrings(v.dict, c, n, depth + 1) as Map<String, Object?>, v.raw);
    return v;
  }

  Object? _resolve(Object? o, [int depth = 0]) {
    var v = o;
    var d = depth;
    while (v is PdfRef && d < 16) {
      v = _object(v.num);
      d++;
    }
    return v;
  }

  /// Распакованные данные потока [s] объекта [n].
  Uint8List? _decode(PdfStream s, int n, int gen) {
    var bytes = s.raw;
    final c = _crypt;
    if (c != null && !_isName(s.dict['Type'], 'XRef') && !_packed.containsKey(n) && n >= 0) {
      bytes = c.decryptStream(bytes, n, gen);
    }
    var filters = _resolve(s.dict['Filter']);
    var parms = _resolve(s.dict['DecodeParms']);
    if (filters is PdfName) filters = [filters];
    if (parms is! List) parms = [parms];
    if (filters is List) {
      for (var i = 0; i < filters.length; i++) {
        final f = _resolve(filters[i]);
        final p = i < parms.length ? _resolve(parms[i]) : null;
        final name = f is PdfName ? f.name : '';
        final out = _filter(name, bytes, p is Map<String, Object?> ? p : null);
        if (out == null) return null;
        bytes = out;
        _decoded += bytes.length;
        if (bytes.length > PdfText.maxStream || _decoded > PdfText.maxTotalDecoded) return null;
      }
    }
    return bytes;
  }

  Uint8List? _filter(String name, Uint8List b, Map<String, Object?>? parms) {
    switch (name) {
      case 'FlateDecode':
      case 'Fl':
        return _predict(_inflate(b), parms);
      case 'ASCIIHexDecode':
      case 'AHx':
        return _Lexer(Uint8List.fromList([0x3C, ...b, 0x3E]))._hex();
      case 'ASCII85Decode':
      case 'A85':
        return _ascii85(b);
      case 'LZWDecode':
      case 'LZW':
        return _predict(_lzw(b, parms), parms);
      default:
        // Картинки (DCT, JPX, CCITT…) текста не содержат.
        return null;
    }
  }

  static Uint8List? _inflate(Uint8List b) {
    if (b.isEmpty) return b;
    try {
      return Uint8List.fromList(ZLibDecoder().convert(b));
    } catch (_) {
      // Оборванный поток: что успели распаковать.
      try {
        final out = BytesBuilder(copy: false);
        final sink = ZLibDecoder().startChunkedConversion(_ByteSink(out));
        for (var i = 0; i < b.length; i += 4096) {
          sink.add(Uint8List.sublistView(b, i, math.min(b.length, i + 4096)));
        }
        return out.takeBytes();
      } catch (_) {
        return null;
      }
    }
  }

  /// Предиктор PNG (/Predictor ≥ 10) — потоки перекрёстных ссылок, иногда
  /// содержимое.
  static Uint8List? _predict(Uint8List? b, Map<String, Object?>? parms) {
    if (b == null || parms == null) return b;
    final pred = _int(parms['Predictor']) ?? 1;
    if (pred < 10) return b;
    final colors = _int(parms['Colors']) ?? 1, bpc = _int(parms['BitsPerComponent']) ?? 8;
    final columns = _int(parms['Columns']) ?? 1;
    final bpp = math.max(1, (colors * bpc + 7) ~/ 8);
    final row = (colors * bpc * columns + 7) ~/ 8;
    if (row <= 0) return b;
    final out = BytesBuilder(copy: false);
    var prev = Uint8List(row);
    for (var i = 0; i + 1 + row <= b.length; i += row + 1) {
      final type = b[i];
      final cur = Uint8List.fromList(b.sublist(i + 1, i + 1 + row));
      for (var k = 0; k < row; k++) {
        final left = k >= bpp ? cur[k - bpp] : 0, up = prev[k], ul = k >= bpp ? prev[k - bpp] : 0;
        switch (type) {
          case 1:
            cur[k] = (cur[k] + left) & 0xFF;
          case 2:
            cur[k] = (cur[k] + up) & 0xFF;
          case 3:
            cur[k] = (cur[k] + ((left + up) >> 1)) & 0xFF;
          case 4:
            final pp = left + up - ul;
            final pa = (pp - left).abs(), pb = (pp - up).abs(), pc = (pp - ul).abs();
            final pr = pa <= pb && pa <= pc ? left : (pb <= pc ? up : ul);
            cur[k] = (cur[k] + pr) & 0xFF;
        }
      }
      out.add(cur);
      prev = cur;
    }
    return out.takeBytes();
  }

  static Uint8List _ascii85(Uint8List b) {
    final out = BytesBuilder(copy: false);
    final group = <int>[];
    for (var i = 0; i < b.length; i++) {
      final c = b[i];
      if (c == 0x7E) break; // ~>
      if (_isWs(c)) continue;
      if (c == 0x7A && group.isEmpty) {
        out.add(const [0, 0, 0, 0]);
        continue;
      }
      if (c < 0x21 || c > 0x75) continue;
      group.add(c - 0x21);
      if (group.length == 5) {
        var v = 0;
        for (final g in group) {
          v = v * 85 + g;
        }
        out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
        group.clear();
      }
    }
    if (group.isNotEmpty) {
      final n = group.length;
      while (group.length < 5) {
        group.add(84);
      }
      var v = 0;
      for (final g in group) {
        v = v * 85 + g;
      }
      final bytes = [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
      out.add(bytes.sublist(0, n - 1));
    }
    return out.takeBytes();
  }

  static Uint8List _lzw(Uint8List b, Map<String, Object?>? parms) {
    final early = _int(parms?['EarlyChange']) ?? 1;
    final out = BytesBuilder(copy: false);
    final dict = <List<int>>[for (var i = 0; i < 256; i++) [i]];
    dict.add(const []); // 256 clear
    dict.add(const []); // 257 eod
    var bits = 9, buf = 0, nbuf = 0;
    List<int>? prev;
    for (var i = 0; i < b.length; i++) {
      buf = (buf << 8) | b[i];
      nbuf += 8;
      while (nbuf >= bits) {
        final code = (buf >> (nbuf - bits)) & ((1 << bits) - 1);
        nbuf -= bits;
        if (code == 256) {
          dict.length = 258;
          bits = 9;
          prev = null;
          continue;
        }
        if (code == 257) return out.takeBytes();
        List<int> entry;
        if (code < dict.length) {
          entry = dict[code];
        } else if (prev != null) {
          entry = [...prev, prev.first];
        } else {
          return out.takeBytes();
        }
        out.add(entry);
        if (prev != null && dict.length < 4096) dict.add([...prev, entry.first]);
        prev = entry;
        if (dict.length + early >= (1 << bits) && bits < 12) bits++;
        if (out.length > PdfText.maxStream) return out.takeBytes();
      }
    }
    return out.takeBytes();
  }

  // ─────────────────────────── страницы ───────────────────────────

  String text(int maxChars) {
    final root = _resolve(_trailer['Root']) ?? _findCatalog();
    final out = _TextOut(maxChars);
    if (root is Map<String, Object?>) {
      final pages = <(Map<String, Object?>, Map<String, Object?>?)>[];
      _collectPages(_resolve(root['Pages']), null, pages, 0, <Object>{});
      for (final (page, res) in pages) {
        if (out.full) break;
        _page(page, res, out);
        out.paragraph();
      }
    }
    return out.result;
  }

  Object? _findCatalog() {
    for (final n in _offsets.keys) {
      final o = _object(n);
      if (o is Map<String, Object?> && _isName(o['Type'], 'Catalog')) return o;
    }
    return null;
  }

  void _collectPages(
    Object? node,
    Map<String, Object?>? inherited,
    List<(Map<String, Object?>, Map<String, Object?>?)> out,
    int depth,
    Set<Object> seen,
  ) {
    if (node is! Map<String, Object?> || depth > 64 || out.length >= PdfText.maxPages || !seen.add(node)) return;
    final res = _resolve(node['Resources']);
    final resources = res is Map<String, Object?> ? res : inherited;
    final kids = _resolve(node['Kids']);
    if (kids is List && !_isName(node['Type'], 'Page')) {
      for (final k in kids) {
        _collectPages(_resolve(k), resources, out, depth + 1, seen);
      }
    } else if (node['Contents'] != null || _isName(node['Type'], 'Page')) {
      out.add((node, resources));
    }
  }

  void _page(Map<String, Object?> page, Map<String, Object?>? resources, _TextOut out) {
    final contents = <Uint8List>[];
    final c = page['Contents'];
    final list = _resolve(c) is List ? _resolve(c) as List : [c];
    for (final item in list) {
      final s = _resolve(item);
      if (s is PdfStream) {
        final n = item is PdfRef ? item.num : -1;
        final g = item is PdfRef ? item.gen : 0;
        final d = _decode(s, n, g);
        if (d != null) contents.add(d);
      }
    }
    if (contents.isEmpty) return;
    final joined = BytesBuilder(copy: false);
    for (final d in contents) {
      joined.add(d);
      joined.addByte(0x0A);
    }
    _run(joined.takeBytes(), resources, out, 0);
  }

  final _fontCache = <Object, _Font>{};

  _Font _font(Object? ref) {
    final key = ref is PdfRef ? ref.num : ref ?? 'none';
    return _fontCache[key] ??= _Font.load(_resolve(ref), this);
  }

  /// Содержимое страницы или формы.
  void _run(Uint8List content, Map<String, Object?>? resources, _TextOut out, int depth) {
    if (depth > 8) return;
    final fonts = _resolve(resources?['Font']);
    final xobjects = _resolve(resources?['XObject']);
    final lx = _Lexer(content);
    final stack = <Object?>[];
    _Font? font;
    // Высота строки текста (матрица строки, без масштаба) и высота, на
    // которой выводился прошлый текст: другая — новая строка.
    var lineY = 0.0;
    double? shownY;
    var ops = 0;
    void show(Uint8List bytes) {
      final t = _show(font, bytes);
      if (t.isEmpty) return;
      if (shownY != null && (lineY - shownY!).abs() > 0.5) out.line();
      shownY = lineY;
      out.add(t);
    }

    while (!out.full) {
      Object? t;
      try {
        lx.skipWs();
        if (lx.atEnd) break;
        t = lx.next(ops: true);
      } catch (_) {
        break;
      }
      if (t is! _Op) {
        if (stack.length > 1000) stack.removeAt(0);
        stack.add(t);
        continue;
      }
      if (++ops > 2000000) break;
      switch (t.name) {
        case 'BT':
          lineY = 0;
        case 'Tf':
          if (stack.length >= 2 && stack[stack.length - 2] is PdfName && fonts is Map<String, Object?>) {
            font = _font(fonts[(stack[stack.length - 2] as PdfName).name]);
          }
        case 'Tj':
          if (stack.isNotEmpty && stack.last is PdfString) show((stack.last as PdfString).bytes);
        case "'":
        case '"':
          out.line();
          lineY -= 1;
          shownY = lineY;
          if (stack.isNotEmpty && stack.last is PdfString) show((stack.last as PdfString).bytes);
        case 'TJ':
          if (stack.isNotEmpty && stack.last is List) {
            for (final e in stack.last as List) {
              if (e is PdfString) {
                show(e.bytes);
              } else if (e is num && e < -180) {
                out.space();
              }
            }
          }
        case 'Td':
        case 'TD':
          if (stack.length >= 2 && stack[stack.length - 1] is num && stack[stack.length - 2] is num) {
            final ty = (stack[stack.length - 1] as num).toDouble(), tx = (stack[stack.length - 2] as num).toDouble();
            lineY += ty;
            if (ty.abs() <= 0.5 && tx.abs() > 0.5) out.space();
          }
        case 'T*':
          out.line();
          lineY -= 1;
          shownY = lineY;
        case 'Tm':
          if (stack.length >= 6 && stack[stack.length - 1] is num) {
            final y = (stack[stack.length - 1] as num).toDouble();
            if ((y - lineY).abs() <= 0.5) out.space();
            lineY = y;
          }
        case 'ET':
          out.space();
        case 'Do':
          if (stack.isNotEmpty && stack.last is PdfName && xobjects is Map<String, Object?>) {
            final ref = xobjects[(stack.last as PdfName).name];
            final x = _resolve(ref);
            if (x is PdfStream && _isName(x.dict['Subtype'], 'Form')) {
              final d = _decode(x, ref is PdfRef ? ref.num : -1, ref is PdfRef ? ref.gen : 0);
              final r = _resolve(x.dict['Resources']);
              if (d != null) _run(d, r is Map<String, Object?> ? r : resources, out, depth + 1);
            }
          }
        case 'BI':
          // Встроенная картинка: данные до « EI».
          final ei = _indexOf(content, const [0x45, 0x49], lx.pos);
          lx.pos = ei < 0 ? content.length : ei + 2;
      }
      stack.clear();
    }
  }

  static String _show(_Font? font, Uint8List bytes) => (font ?? _Font.fallback).decode(bytes);
}

class _ByteSink implements Sink<List<int>> {
  _ByteSink(this.out);
  final BytesBuilder out;
  @override
  void add(List<int> data) => out.add(data);
  @override
  void close() {}
}

// ───────────────────────────── текст ─────────────────────────────

class _TextOut {
  _TextOut(this.max);
  final int max;
  final _b = StringBuffer();
  int _len = 0;
  bool _pendingSpace = false;
  bool _pendingLine = false;

  bool get full => _len >= max;

  void add(String s) {
    if (s.isEmpty || full) return;
    final clean = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F�]'), '');
    if (clean.trim().isEmpty) {
      if (clean.isNotEmpty) _pendingSpace = true;
      return;
    }
    if (_len > 0) {
      if (_pendingLine) {
        _write('\n');
      } else if (_pendingSpace && !clean.startsWith(' ')) {
        _write(' ');
      }
    }
    _pendingLine = false;
    _pendingSpace = false;
    _write(clean.replaceAll(RegExp(r'[\t\r\n]+'), ' '));
  }

  void _write(String s) {
    final left = max - _len;
    if (left <= 0) return;
    final part = s.length > left ? s.substring(0, left) : s;
    _b.write(part);
    _len += part.length;
  }

  void space() => _pendingSpace = true;
  void line() => _pendingLine = true;
  void paragraph() {
    if (_len > 0 && !full) {
      _write('\n\n');
      _pendingLine = false;
      _pendingSpace = false;
    }
  }

  String get result => _b.toString().replaceAll(RegExp(r'[  ]{2,}'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

// ───────────────────────────── шрифты ─────────────────────────────

class _Font {
  _Font({this.toUnicode, this.codeLengths = const [1], this.simple, this.composite = false});

  /// Код → текст (ToUnicode).
  final Map<int, String>? toUnicode;

  /// Длины кодов (1 или 2 байта) по пространствам кодов CMap.
  final List<_CodeRange> codeLengthsRanges = [];
  final List<int> codeLengths;

  /// Простой шрифт: байт → знак.
  final List<String?>? simple;

  /// Составной (Type0) без ToUnicode — кодов не перевести.
  final bool composite;

  static final fallback = _Font(simple: _winAnsi);

  static _Font load(Object? f, _Pdf pdf) {
    if (f is! Map<String, Object?>) return fallback;
    final subtype = pdf._resolve(f['Subtype']);
    final isType0 = subtype is PdfName && subtype.name == 'Type0';
    Map<int, String>? map;
    var ranges = <_CodeRange>[];
    final tu = pdf._resolve(f['ToUnicode']);
    if (tu is PdfStream) {
      final ref = f['ToUnicode'];
      final d = pdf._decode(tu, ref is PdfRef ? ref.num : -1, ref is PdfRef ? ref.gen : 0);
      if (d != null) {
        final cmap = _CMap.parse(d);
        map = cmap.map;
        ranges = cmap.ranges;
      }
    }
    if (isType0) {
      final font = _Font(toUnicode: map, codeLengths: const [2], composite: map == null);
      font.codeLengthsRanges.addAll(ranges.isEmpty ? [const _CodeRange(0, 0xFFFF, 2)] : ranges);
      return font;
    }
    // Простой шрифт: кодировка и /Differences.
    final enc = pdf._resolve(f['Encoding']);
    List<String?> table = _winAnsi;
    if (enc is PdfName) {
      table = _baseEncoding(enc.name);
    } else if (enc is Map<String, Object?>) {
      final base = pdf._resolve(enc['BaseEncoding']);
      table = List.of(base is PdfName ? _baseEncoding(base.name) : _winAnsi);
      final diff = pdf._resolve(enc['Differences']);
      if (diff is List) {
        var code = 0;
        for (final e in diff) {
          final v = pdf._resolve(e);
          if (v is num) {
            code = v.toInt();
          } else if (v is PdfName) {
            if (code >= 0 && code < 256) table[code] = _glyphName(v.name) ?? table[code];
            code++;
          }
        }
      }
    }
    final font = _Font(toUnicode: map, simple: table);
    font.codeLengthsRanges.addAll(ranges);
    return font;
  }

  static List<String?> _baseEncoding(String name) => switch (name) {
        'MacRomanEncoding' => _macRoman,
        _ => _winAnsi,
      };

  String decode(Uint8List bytes) {
    if (composite) return '';
    final map = toUnicode;
    final out = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      var len = _lengthAt(bytes, i);
      if (i + len > bytes.length) len = bytes.length - i;
      var code = 0;
      for (var k = 0; k < len; k++) {
        code = (code << 8) | bytes[i + k];
      }
      i += len;
      final m = map?[code];
      if (m != null) {
        out.write(m);
        continue;
      }
      if (len == 1 && simple != null) {
        final s = simple![code];
        if (s != null) out.write(s);
      }
    }
    return out.toString();
  }

  int _lengthAt(Uint8List b, int i) {
    if (codeLengthsRanges.isEmpty) return codeLengths.first;
    for (final len in const [1, 2, 3, 4]) {
      if (i + len > b.length) break;
      var code = 0;
      for (var k = 0; k < len; k++) {
        code = (code << 8) | b[i + k];
      }
      for (final r in codeLengthsRanges) {
        if (r.bytes == len && code >= r.lo && code <= r.hi) return len;
      }
    }
    return codeLengthsRanges.first.bytes;
  }
}

class _CodeRange {
  const _CodeRange(this.lo, this.hi, this.bytes);
  final int lo, hi, bytes;
}

/// Таблица ToUnicode (CMap): codespacerange, bfchar, bfrange.
class _CMap {
  final map = <int, String>{};
  final ranges = <_CodeRange>[];

  static _CMap parse(Uint8List d) {
    final c = _CMap();
    final lx = _Lexer(d);
    final stack = <Object?>[];
    var guard = 0;
    while (!lx.atEnd && guard++ < 1000000) {
      Object? t;
      try {
        lx.skipWs();
        if (lx.atEnd) break;
        t = lx.next(ops: true);
      } catch (_) {
        break;
      }
      if (t is! _Op) {
        stack.add(t);
        continue;
      }
      switch (t.name) {
        case 'endcodespacerange':
          for (var i = 0; i + 1 < stack.length; i += 2) {
            final lo = stack[i], hi = stack[i + 1];
            if (lo is PdfString && hi is PdfString && lo.bytes.isNotEmpty) {
              c.ranges.add(_CodeRange(_code(lo.bytes), _code(hi.bytes), lo.bytes.length));
            }
          }
        case 'endbfchar':
          for (var i = 0; i + 1 < stack.length; i += 2) {
            final src = stack[i], dst = stack[i + 1];
            if (src is PdfString && dst is PdfString) c.map[_code(src.bytes)] = _utf16(dst.bytes);
          }
        case 'endbfrange':
          for (var i = 0; i + 2 < stack.length; i += 3) {
            final lo = stack[i], hi = stack[i + 1], dst = stack[i + 2];
            if (lo is! PdfString || hi is! PdfString) continue;
            final a = _code(lo.bytes), b = _code(hi.bytes);
            if (b < a || b - a > 65535) continue;
            if (dst is PdfString) {
              final base = Uint8List.fromList(dst.bytes);
              for (var k = 0; k <= b - a; k++) {
                c.map[a + k] = _utf16(_plus(base, k));
              }
            } else if (dst is List) {
              for (var k = 0; k <= b - a && k < dst.length; k++) {
                final e = dst[k];
                if (e is PdfString) c.map[a + k] = _utf16(e.bytes);
              }
            }
          }
      }
      stack.clear();
    }
    return c;
  }

  static int _code(Uint8List b) {
    var v = 0;
    for (final x in b) {
      v = (v << 8) | x;
    }
    return v;
  }

  static Uint8List _plus(Uint8List base, int k) {
    final out = Uint8List.fromList(base);
    var carry = k;
    for (var i = out.length - 1; i >= 0 && carry > 0; i--) {
      final s = out[i] + carry;
      out[i] = s & 0xFF;
      carry = s >> 8;
    }
    return out;
  }

  static String _utf16(Uint8List b) {
    if (b.length == 1) return String.fromCharCode(b[0]);
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add((b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}

/// Имя знака → текст: uniXXXX, uXXXX[XX], кириллица afii100xx, латиница.
String? _glyphName(String n) {
  if (n.startsWith('uni') && n.length >= 7) {
    final v = int.tryParse(n.substring(3, 7), radix: 16);
    if (v != null) return String.fromCharCode(v);
  }
  if (n.startsWith('u') && n.length >= 5 && n.length <= 7) {
    final v = int.tryParse(n.substring(1), radix: 16);
    if (v != null) return String.fromCharCode(v);
  }
  final afii = _afii[n];
  if (afii != null) return String.fromCharCode(afii);
  if (n.length == 1) return n;
  final g = _glyphs[n];
  if (g != null) return g;
  // «a.sc», «one.oldstyle» — основа до точки.
  final dot = n.indexOf('.');
  if (dot > 0) return _glyphName(n.substring(0, dot));
  return null;
}

/// Кириллица Adobe (afii10017 «А» … afii10097 «я», Ё/ё и др.).
final Map<String, int> _afii = () {
  final m = <String, int>{};
  // А..Я (без Ё): afii10017..afii10049 — по порядку Adobe: А Б В Г Д Е Ё Ж…
  const upper = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ';
  const lower = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
  for (var i = 0; i < upper.length; i++) {
    m['afii${10017 + i}'] = upper.codeUnitAt(i);
    m['afii${10065 + i}'] = lower.codeUnitAt(i);
  }
  // Украинские и др.: Є І Ї Ў Ґ.
  m['afii10053'] = 0x0404;
  m['afii10055'] = 0x0406;
  m['afii10056'] = 0x0407;
  m['afii10062'] = 0x040E;
  m['afii10050'] = 0x0490;
  m['afii10101'] = 0x0454;
  m['afii10103'] = 0x0456;
  m['afii10104'] = 0x0457;
  m['afii10110'] = 0x045E;
  m['afii10098'] = 0x0491;
  m['afii61352'] = 0x2116; // №
  return m;
}();

const _glyphs = <String, String>{
  'space': ' ', 'exclam': '!', 'quotedbl': '"', 'numbersign': '#', 'dollar': r'$', 'percent': '%',
  'ampersand': '&', 'quotesingle': "'", 'quoteright': '’', 'quoteleft': '‘', 'parenleft': '(', 'parenright': ')',
  'asterisk': '*', 'plus': '+', 'comma': ',', 'hyphen': '-', 'minus': '−', 'period': '.', 'slash': '/',
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7',
  'eight': '8', 'nine': '9', 'colon': ':', 'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>',
  'question': '?', 'at': '@', 'bracketleft': '[', 'backslash': r'\', 'bracketright': ']', 'asciicircum': '^',
  'underscore': '_', 'grave': '`', 'braceleft': '{', 'bar': '|', 'braceright': '}', 'asciitilde': '~',
  'endash': '–', 'emdash': '—', 'bullet': '•', 'ellipsis': '…', 'quotedblleft': '“', 'quotedblright': '”',
  'quotedblbase': '„', 'guillemotleft': '«', 'guillemotright': '»', 'guilsinglleft': '‹', 'guilsinglright': '›',
  'degree': '°', 'copyright': '©', 'registered': '®', 'trademark': '™', 'section': '§', 'paragraph': '¶',
  'nbspace': ' ', 'fi': 'fi', 'fl': 'fl', 'ff': 'ff', 'ffi': 'ffi', 'ffl': 'ffl', 'Euro': '€', 'euro': '€',
  'multiply': '×', 'divide': '÷', 'plusminus': '±', 'periodcentered': '·', 'dagger': '†', 'daggerdbl': '‡',
  'quotesinglbase': '‚', 'perthousand': '‰', 'tilde': '˜', 'circumflex': 'ˆ', 'dotlessi': 'ı',
};

/// WinAnsiEncoding (кодовая страница 1252).
final List<String?> _winAnsi = () {
  const hi = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F\u0090‘’“”•–—˜™š›œ\u009DžŸ';
  return List<String?>.generate(256, (i) {
    if (i < 0x20) return i == 0x09 || i == 0x0A || i == 0x0D ? ' ' : null;
    if (i >= 0x80 && i < 0xA0) return hi[i - 0x80];
    return String.fromCharCode(i);
  });
}();

/// MacRomanEncoding (верхняя половина).
final List<String?> _macRoman = () {
  const hi = 'ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ';
  return List<String?>.generate(256, (i) {
    if (i < 0x20) return null;
    if (i >= 0x80) return i - 0x80 < hi.length ? hi[i - 0x80] : null;
    return String.fromCharCode(i);
  });
}();

// ───────────────────────────── защита ─────────────────────────────

/// Стандартная защита PDF с пустым паролем на открытие (ISO 32000-1 7.6.3,
/// 32000-2 для AES-256).
class _Crypt {
  _Crypt._(this.key, this.aes, this.aes256, this.identityStrings, this.identityStreams);

  final Uint8List key;
  final bool aes;
  final bool aes256;
  final bool identityStrings;
  final bool identityStreams;

  static const _pad = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  static _Crypt? standard(Map<String, Object?> e, Uint8List id, Object? Function(Object?) resolve) {
    final filter = resolve(e['Filter']);
    if (filter is! PdfName || filter.name != 'Standard') return null;
    final v = (resolve(e['V']) as num?)?.toInt() ?? 0;
    final r = (resolve(e['R']) as num?)?.toInt() ?? 2;
    final o = resolve(e['O']), u = resolve(e['U']);
    if (o is! PdfString || u is! PdfString) return null;
    var stmAes = false, strAes = false, stmIdentity = false, strIdentity = false;
    var lengthBits = (resolve(e['Length']) as num?)?.toInt() ?? 40;
    if (v >= 4) {
      final cf = resolve(e['CF']);
      String? method(Object? name) {
        final n = resolve(name);
        if (n is! PdfName) return null;
        if (n.name == 'Identity') return 'Identity';
        if (cf is Map<String, Object?>) {
          final f = resolve(cf[n.name]);
          if (f is Map<String, Object?>) {
            final m = resolve(f['CFM']);
            final l = resolve(f['Length']);
            if (l is num && l > 0) lengthBits = l < 64 ? l.toInt() * 8 : l.toInt();
            return m is PdfName ? m.name : null;
          }
        }
        return null;
      }

      final sm = method(e['StmF']) ?? 'Identity', st = method(e['StrF']) ?? 'Identity';
      stmAes = sm.startsWith('AES');
      strAes = st.startsWith('AES');
      stmIdentity = sm == 'Identity';
      strIdentity = st == 'Identity';
    }
    if (v == 5 || r >= 5) {
      final ue = resolve(e['UE']);
      if (ue is! PdfString || u.bytes.length < 48) return null;
      final salt = Uint8List.sublistView(u.bytes, 40, 48);
      final k = r >= 6 ? _hash2B(Uint8List(0), salt, Uint8List(0)) : Uint8List.fromList(hash.sha256.convert(salt).bytes);
      final fileKey = _aesRaw(k, Uint8List(16), ue.bytes, decrypt: true);
      return _Crypt._(fileKey, true, true, strIdentity, stmIdentity);
    }
    final p = (resolve(e['P']) as num?)?.toInt() ?? 0;
    final encMeta = resolve(e['EncryptMetadata']);
    final n = r == 2 ? 5 : (lengthBits ~/ 8).clamp(5, 16);
    final input = BytesBuilder()
      ..add(_pad)
      ..add(o.bytes.length >= 32 ? o.bytes.sublist(0, 32) : o.bytes)
      ..add([p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF, (p >> 24) & 0xFF])
      ..add(id);
    if (r >= 4 && encMeta == false) input.add(const [0xFF, 0xFF, 0xFF, 0xFF]);
    var k = Uint8List.fromList(hash.md5.convert(input.takeBytes()).bytes);
    if (r >= 3) {
      for (var i = 0; i < 50; i++) {
        k = Uint8List.fromList(hash.md5.convert(k.sublist(0, n)).bytes);
      }
    }
    final key = k.sublist(0, n);
    // AES у потоков и строк задаётся по отдельности; обычно одинаково.
    return _Crypt._(key, stmAes || strAes, false, strIdentity, stmIdentity);
  }

  /// Алгоритм 2.B (AES-256, R6).
  static Uint8List _hash2B(Uint8List password, Uint8List salt, Uint8List udata) {
    var k = Uint8List.fromList(hash.sha256.convert([...password, ...salt, ...udata]).bytes);
    for (var round = 0;; round++) {
      final k1 = BytesBuilder();
      for (var i = 0; i < 64; i++) {
        k1
          ..add(password)
          ..add(k)
          ..add(udata);
      }
      final e = _aesRaw(k.sublist(0, 16), k.sublist(16, 32), k1.takeBytes(), decrypt: false);
      var sum = 0;
      for (var i = 0; i < 16; i++) {
        sum += e[i];
      }
      k = Uint8List.fromList(switch (sum % 3) {
        0 => hash.sha256.convert(e).bytes,
        1 => hash.sha384.convert(e).bytes,
        _ => hash.sha512.convert(e).bytes,
      });
      // Не меньше 64 кругов, дальше — пока последний байт E больше
      // (номер круга − 32), считая круги с единицы.
      if (round + 1 >= 64 && e.last <= round + 1 - 32) break;
      if (round > 2000) break;
    }
    return k.sublist(0, 32);
  }

  /// AES-CBC без дополнения.
  static Uint8List _aesRaw(Uint8List key, Uint8List iv, Uint8List data, {required bool decrypt}) {
    final c = CBCBlockCipher(AESEngine())..init(!decrypt, ParametersWithIV(KeyParameter(key), iv));
    final n = data.length - data.length % 16;
    final out = Uint8List(n);
    for (var i = 0; i < n; i += 16) {
      c.processBlock(data, i, out, i);
    }
    return out;
  }

  Uint8List _objectKey(int num, int gen) {
    if (aes256) return key;
    final b = BytesBuilder()
      ..add(key)
      ..add([num & 0xFF, (num >> 8) & 0xFF, (num >> 16) & 0xFF, gen & 0xFF, (gen >> 8) & 0xFF]);
    if (aes) b.add(const [0x73, 0x41, 0x6C, 0x54]); // «sAlT»
    final d = hash.md5.convert(b.takeBytes()).bytes;
    return Uint8List.fromList(d.sublist(0, math.min(key.length + 5, 16)));
  }

  Uint8List decryptString(Uint8List b, int num, int gen) => identityStrings ? b : _decrypt(b, num, gen);
  Uint8List decryptStream(Uint8List b, int num, int gen) => identityStreams ? b : _decrypt(b, num, gen);

  Uint8List _decrypt(Uint8List b, int num, int gen) {
    final k = _objectKey(num, gen);
    if (!aes) {
      final rc4 = RC4Engine()..init(false, KeyParameter(k));
      final out = Uint8List(b.length);
      rc4.processBytes(b, 0, b.length, out, 0);
      return out;
    }
    if (b.length < 16) return Uint8List(0);
    return _aesTail(k, b);
  }

  static Uint8List _aesTail(Uint8List k, Uint8List b) {
    try {
      final iv = Uint8List.sublistView(b, 0, 16);
      final body = Uint8List.sublistView(b, 16, 16 + (b.length - 16) - (b.length - 16) % 16);
      final out = _aesRaw(k, Uint8List.fromList(iv), Uint8List.fromList(body), decrypt: true);
      if (out.isEmpty) return out;
      final padLen = out.last;
      if (padLen >= 1 && padLen <= 16 && padLen <= out.length) return Uint8List.sublistView(out, 0, out.length - padLen);
      return out;
    } catch (_) {
      return Uint8List(0);
    }
  }
}

// lib/core/utils/zip_names.dart
//
// Имена файлов в ZIP (1.10.2, замечание владельца 02.11.2026: в архиве
// «Ермишин Олег Андреевич_….zip» имя файла показывалось как «Ŕà¬¨è¨ …»).
//
// По стандарту ZIP имя — в UTF-8, только если в записи стоит флаг 0x800.
// Без флага имя записано в кодовой странице, которой пользовалась
// программа: «Сжатая папка» Windows и 7-Zip пишут в OEM-странице системы —
// у русской Windows это CP866 (DOS), у западноевропейской — CP437/850;
// старые архиваторы — в ANSI (CP1251); macOS — в UTF-8 без флага. Пакет
// archive такие имена читает как Latin-1 — отсюда «à¬¨è».
//
// Здесь: сырые байты имён — из центрального каталога архива; UTF-8 (флаг,
// поле «Unicode Path» 0x7075 или просто корректный UTF-8), иначе — та из
// CP866, CP1251 и CP437, что даёт осмысленный текст (буквы одной
// письменности, без псевдографики), при равенстве — по языку устройства.
// Японские и китайские имена (Shift-JIS, GBK) не распознаются — остаются
// как были.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Имя записи центрального каталога: байты, флаги, имя из поля 0x7075.
typedef ZipRawName = ({Uint8List bytes, int flags, String? unicodePath});

/// Имена записей центрального каталога [path] по порядку; null — не удалось
/// прочитать (тогда остаются имена пакета archive).
List<ZipRawName>? readZipRawNames(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final len = f.lengthSync();
    if (len < 22) return null;
    final tailLen = len < 65557 ? len : 65557;
    f.setPositionSync(len - tailLen);
    final tail = f.readSync(tailLen);
    final bd = ByteData.sublistView(tail);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;
    var entries = bd.getUint16(eocd + 10, Endian.little);
    var cdSize = bd.getUint32(eocd + 12, Endian.little);
    var cdOffset = bd.getUint32(eocd + 16, Endian.little);
    if (entries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      // ZIP64: локатор — за 20 байт до конца каталога.
      final loc = eocd - 20;
      if (loc < 0 || bd.getUint32(loc, Endian.little) != 0x07064b50) return null;
      final recOffset = bd.getUint64(loc + 8, Endian.little);
      f.setPositionSync(recOffset);
      final rec = f.readSync(56);
      final rd = ByteData.sublistView(rec);
      if (rec.length < 56 || rd.getUint32(0, Endian.little) != 0x06064b50) return null;
      entries = rd.getUint64(32, Endian.little);
      cdSize = rd.getUint64(40, Endian.little);
      cdOffset = rd.getUint64(48, Endian.little);
    }
    if (cdSize <= 0 || cdSize > 64 * 1024 * 1024 || cdOffset + cdSize > len) return null;
    f.setPositionSync(cdOffset);
    final cd = f.readSync(cdSize);
    final cdd = ByteData.sublistView(cd);
    final out = <ZipRawName>[];
    var p = 0;
    while (p + 46 <= cd.length && out.length < entries) {
      if (cdd.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = cdd.getUint16(p + 8, Endian.little);
      final nameLen = cdd.getUint16(p + 28, Endian.little);
      final extraLen = cdd.getUint16(p + 30, Endian.little);
      final commentLen = cdd.getUint16(p + 32, Endian.little);
      final nameStart = p + 46;
      final extraStart = nameStart + nameLen;
      final next = extraStart + extraLen + commentLen;
      if (next > cd.length) break;
      final name = Uint8List.fromList(cd.sublist(nameStart, extraStart));
      out.add((bytes: name, flags: flags, unicodePath: _unicodePath(cd, extraStart, extraLen)));
      p = next;
    }
    return out;
  } catch (_) {
    return null;
  } finally {
    try {
      f?.closeSync();
    } catch (_) {}
  }
}

/// Поле «Info-ZIP Unicode Path» (0x7075): версия 1, CRC исходного имени,
/// имя в UTF-8.
String? _unicodePath(Uint8List cd, int start, int len) {
  final bd = ByteData.sublistView(cd);
  var p = start;
  final end = start + len;
  while (p + 4 <= end) {
    final id = bd.getUint16(p, Endian.little);
    final size = bd.getUint16(p + 2, Endian.little);
    final data = p + 4;
    if (data + size > end) break;
    if (id == 0x7075 && size > 5 && cd[data] == 1) {
      try {
        return utf8.decode(cd.sublist(data + 5, data + size));
      } catch (_) {
        return null;
      }
    }
    p = data + size;
  }
  return null;
}

/// Имя записи ZIP по сырым байтам. [lang] — язык устройства (ru, en…):
/// при равных вариантах русская Windows пишет CP866, западная — CP437.
String decodeZipName(Uint8List bytes, {int flags = 0, String? unicodePath, String? lang}) {
  if (unicodePath != null && unicodePath.isNotEmpty) return unicodePath;
  if (flags & 0x800 != 0) return utf8.decode(bytes, allowMalformed: true);
  if (bytes.every((b) => b < 0x80)) return String.fromCharCodes(bytes);
  try {
    return utf8.decode(bytes); // macOS и Linux: UTF-8 без флага
  } on FormatException {
    // ниже — кодовые страницы
  }
  final cyr = const {'ru', 'uk', 'be', 'kk', 'ky', 'tg', 'uz', 'bg', 'sr', 'mk', 'mn'}.contains(lang);
  final pages = cyr ? const [_cp866, _cp1251, _cp437] : const [_cp437, _cp866, _cp1251];
  String? best;
  var bestScore = -1 << 30;
  for (final t in pages) {
    final s = _decode(bytes, t);
    final sc = _score(s);
    if (sc > bestScore) {
      best = s;
      bestScore = sc;
    }
  }
  return best!;
}

/// Имя, которое пакет archive уже прочитал как Latin-1 (сырые байты
/// недоступны): то же распознавание по кодам символов.
String fixLatin1ZipName(String name, {String? lang}) {
  final units = name.codeUnits;
  if (units.every((c) => c < 0x80) || units.any((c) => c > 0xFF)) return name;
  final bytes = Uint8List.fromList(units);
  try {
    utf8.decode(bytes);
    return name; // корректный UTF-8 пакет прочитал бы сам — значит, это не он
  } on FormatException {
    return decodeZipName(bytes, lang: lang);
  }
}

String _decode(Uint8List bytes, String table) {
  final b = StringBuffer();
  for (final x in bytes) {
    b.writeCharCode(x < 0x80 ? x : table.codeUnitAt(x - 0x80));
  }
  return b.toString();
}

bool _isCyrillic(int r) => r >= 0x0400 && r <= 0x04FF;
bool _isLatinLetter(int r) => (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7);
bool _asciiLetter(int r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

/// Насколько текст похож на имя файла: буквы одной письменности — плюс,
/// псевдографика, символы, греческий и кириллица вплотную к латинице
/// («RВsumВ» вместо «Résumé») — минус.
int _score(String s) {
  final r = s.runes.toList();
  var score = 0;
  for (var i = 0; i < r.length; i++) {
    final c = r[i];
    if (c < 0x80) continue;
    if (_isCyrillic(c)) {
      score += 2;
      if ((i > 0 && _asciiLetter(r[i - 1])) || (i + 1 < r.length && _asciiLetter(r[i + 1]))) score -= 3;
    } else if (_isLatinLetter(c)) {
      score += 2;
    } else {
      score -= 3;
    }
  }
  return score;
}

/// Верхняя половина кодовых страниц (байты 0x80–0xFF).
const _cp866 =
      '\u0410\u0411\u0412\u0413\u0414\u0415\u0416\u0417\u0418\u0419\u041A\u041B\u041C\u041D\u041E\u041F'
      '\u0420\u0421\u0422\u0423\u0424\u0425\u0426\u0427\u0428\u0429\u042A\u042B\u042C\u042D\u042E\u042F'
      '\u0430\u0431\u0432\u0433\u0434\u0435\u0436\u0437\u0438\u0439\u043A\u043B\u043C\u043D\u043E\u043F'
      '\u2591\u2592\u2593\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255D\u255C\u255B\u2510'
      '\u2514\u2534\u252C\u251C\u2500\u253C\u255E\u255F\u255A\u2554\u2569\u2566\u2560\u2550\u256C\u2567'
      '\u2568\u2564\u2565\u2559\u2558\u2552\u2553\u256B\u256A\u2518\u250C\u2588\u2584\u258C\u2590\u2580'
      '\u0440\u0441\u0442\u0443\u0444\u0445\u0446\u0447\u0448\u0449\u044A\u044B\u044C\u044D\u044E\u044F'
      '\u0401\u0451\u0404\u0454\u0407\u0457\u040E\u045E\u00B0\u2219\u00B7\u221A\u2116\u00A4\u25A0\u00A0';
const _cp437 =
      '\u00C7\u00FC\u00E9\u00E2\u00E4\u00E0\u00E5\u00E7\u00EA\u00EB\u00E8\u00EF\u00EE\u00EC\u00C4\u00C5'
      '\u00C9\u00E6\u00C6\u00F4\u00F6\u00F2\u00FB\u00F9\u00FF\u00D6\u00DC\u00A2\u00A3\u00A5\u20A7\u0192'
      '\u00E1\u00ED\u00F3\u00FA\u00F1\u00D1\u00AA\u00BA\u00BF\u2310\u00AC\u00BD\u00BC\u00A1\u00AB\u00BB'
      '\u2591\u2592\u2593\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255D\u255C\u255B\u2510'
      '\u2514\u2534\u252C\u251C\u2500\u253C\u255E\u255F\u255A\u2554\u2569\u2566\u2560\u2550\u256C\u2567'
      '\u2568\u2564\u2565\u2559\u2558\u2552\u2553\u256B\u256A\u2518\u250C\u2588\u2584\u258C\u2590\u2580'
      '\u03B1\u00DF\u0393\u03C0\u03A3\u03C3\u00B5\u03C4\u03A6\u0398\u03A9\u03B4\u221E\u03C6\u03B5\u2229'
      '\u2261\u00B1\u2265\u2264\u2320\u2321\u00F7\u2248\u00B0\u2219\u00B7\u221A\u207F\u00B2\u25A0\u00A0';
const _cp1251 =
      '\u0402\u0403\u201A\u0453\u201E\u2026\u2020\u2021\u20AC\u2030\u0409\u2039\u040A\u040C\u040B\u040F'
      '\u0452\u2018\u2019\u201C\u201D\u2022\u2013\u2014\uFFFD\u2122\u0459\u203A\u045A\u045C\u045B\u045F'
      '\u00A0\u040E\u045E\u0408\u00A4\u0490\u00A6\u00A7\u0401\u00A9\u0404\u00AB\u00AC\u00AD\u00AE\u0407'
      '\u00B0\u00B1\u0406\u0456\u0491\u00B5\u00B6\u00B7\u0451\u2116\u0454\u00BB\u0458\u0405\u0455\u0457'
      '\u0410\u0411\u0412\u0413\u0414\u0415\u0416\u0417\u0418\u0419\u041A\u041B\u041C\u041D\u041E\u041F'
      '\u0420\u0421\u0422\u0423\u0424\u0425\u0426\u0427\u0428\u0429\u042A\u042B\u042C\u042D\u042E\u042F'
      '\u0430\u0431\u0432\u0433\u0434\u0435\u0436\u0437\u0438\u0439\u043A\u043B\u043C\u043D\u043E\u043F'
      '\u0440\u0441\u0442\u0443\u0444\u0445\u0446\u0447\u0448\u0449\u044A\u044B\u044C\u044D\u044E\u044F';

// lib/core/utils/charset_handler.dart
// Обработка кодировок писем: CP1251, KOI8-R, ISO-8859-1, UTF-8.
// Автоопределение кодировки из Content-Type заголовка.
// Конвертация в UTF-8.

import 'dart:convert';
import 'dart:typed_data';

class CharsetHandler {
  CharsetHandler._();

  /// Определить charset из Content-Type заголовка
  static String detectCharset(String? contentType) {
    if (contentType == null) return 'utf-8';
    final lower = contentType.toLowerCase();

    final match = RegExp(r'charset\s*=\s*"?([^"\s;]+)"?').firstMatch(lower);
    if (match != null) return match.group(1)!.trim();

    if (lower.contains('utf-8') || lower.contains('utf8')) return 'utf-8';
    if (lower.contains('windows-1251') || lower.contains('cp1251')) return 'windows-1251';
    if (lower.contains('koi8-r') || lower.contains('koi8r')) return 'koi8-r';
    if (lower.contains('iso-8859-1') || lower.contains('latin1')) return 'iso-8859-1';
    if (lower.contains('iso-8859-5')) return 'iso-8859-5';

    return 'utf-8';
  }

  /// Декодировать байты в строку с учётом charset
  static String decode(Uint8List bytes, String charset) {
    final lower = charset.toLowerCase().replaceAll('-', '').replaceAll('_', '');

    switch (lower) {
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'windows1251':
      case 'cp1251':
        return _decodeWindows1251(bytes);
      case 'koi8r':
        return _decodeKoi8r(bytes);
      case 'iso88591':
      case 'latin1':
        return latin1.decode(bytes);
      case 'iso88595':
        return _decodeIso88595(bytes);
      default:
        // Пробуем UTF-8, если не получилось — latin1
        try {
          return utf8.decode(bytes);
        } catch (_) {
          return latin1.decode(bytes);
        }
    }
  }

  /// Декодировать строку из неизвестной кодировки
  static String decodeString(String input, String charset) {
    if (charset.toLowerCase().contains('utf') || charset.toLowerCase().contains('utf8')) {
      return input; // Уже UTF-8
    }
    return decode(Uint8List.fromList(input.codeUnits), charset);
  }

  /// Автоопределение кодировки из содержимого (эвристика)
  static String autoDetect(Uint8List bytes) {
    // BOM detection
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) return 'utf-8';
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return 'utf-16le';
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return 'utf-16be';

    // Статистический анализ
    int cp1251Score = 0;
    int koi8rScore = 0;
    int utf8Score = 0;

    for (int i = 0; i < bytes.length && i < 1000; i++) {
      final b = bytes[i];

      // UTF-8 multi-byte sequences
      if (b >= 0xC0 && b <= 0xDF && i + 1 < bytes.length) {
        if (bytes[i + 1] >= 0x80 && bytes[i + 1] <= 0xBF) utf8Score += 2;
      }

      // CP1251: русские буквы в диапазоне 0xC0-0xFF
      if (b >= 0xC0 && b <= 0xFF) cp1251Score++;

      // KOI8-R: русские буквы в диапазоне 0xC0-0xFF (другой порядок)
      if (b >= 0xC0 && b <= 0xDF) koi8rScore++;
    }

    if (utf8Score > cp1251Score && utf8Score > koi8rScore) return 'utf-8';
    if (cp1251Score > koi8rScore) return 'windows-1251';
    if (koi8rScore > 0) return 'koi8-r';
    return 'utf-8';
  }

  /// Декодировать MIME encoded-word (=?charset?encoding?text?=)
  static String decodeMimeEncodedWord(String input) {
    return input.replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]+)\?='),
      (match) {
        final charset = match.group(1)!;
        final encoding = match.group(2)!.toUpperCase();
        final encodedText = match.group(3)!;

        Uint8List bytes;
        if (encoding == 'B') {
          bytes = base64.decode(encodedText);
        } else {
          // Q-encoding (quoted-printable variant)
          bytes = _decodeQEncoding(encodedText);
        }

        return decode(bytes, charset);
      },
    );
  }

  static Uint8List _decodeQEncoding(String input) {
    final result = BytesBuilder();
    int i = 0;
    while (i < input.length) {
      if (input[i] == '=' && i + 2 < input.length) {
        final hex = input.substring(i + 1, i + 3);
        result.addByte(int.parse(hex, radix: 16));
        i += 3;
      } else if (input[i] == '_') {
        result.addByte(0x20); // Space
        i++;
      } else {
        result.addByte(input.codeUnitAt(i));
        i++;
      }
    }
    return Uint8List.fromList(result.toBytes());
  }

  // ════════════════════════ CODEPAGE TABLES ════════════════════════

  static String _decodeWindows1251(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else {
        buf.writeCharCode(_cp1251[b - 0x80]);
      }
    }
    return buf.toString();
  }

  static const _cp1251 = [
    0x0402,0x0403,0x201A,0x0453,0x201E,0x2026,0x2020,0x2021,0x20AC,0x2030,0x0409,0x2039,0x040A,0x040C,0x040B,0x040F,
    0x0452,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,0x0098,0x2122,0x0459,0x203A,0x045A,0x045C,0x045B,0x045F,
    0x00A0,0x040E,0x045E,0x0408,0x00A4,0x0490,0x00A6,0x00A7,0x0401,0x00A9,0x0404,0x00AB,0x00AC,0x00AD,0x00AE,0x0407,
    0x00B0,0x00B1,0x0406,0x0456,0x0491,0x00B5,0x00B6,0x00B7,0x0451,0x2116,0x0454,0x00BB,0x0458,0x0405,0x0455,0x0457,
    0x0410,0x0411,0x0412,0x0413,0x0414,0x0415,0x0416,0x0417,0x0418,0x0419,0x041A,0x041B,0x041C,0x041D,0x041E,0x041F,
    0x0420,0x0421,0x0422,0x0423,0x0424,0x0425,0x0426,0x0427,0x0428,0x0429,0x042A,0x042B,0x042C,0x042D,0x042E,0x042F,
    0x0430,0x0431,0x0432,0x0433,0x0434,0x0435,0x0436,0x0437,0x0438,0x0439,0x043A,0x043B,0x043C,0x043D,0x043E,0x043F,
    0x0440,0x0441,0x0442,0x0443,0x0444,0x0445,0x0446,0x0447,0x0448,0x0449,0x044A,0x044B,0x044C,0x044D,0x044E,0x044F,
  ];

  static String _decodeKoi8r(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else {
        buf.writeCharCode(_koi8r[b - 0x80]);
      }
    }
    return buf.toString();
  }

  static const _koi8r = [
    0x2500,0x2502,0x250C,0x2510,0x2514,0x2518,0x251C,0x2524,0x252C,0x2534,0x253C,0x2580,0x2584,0x2588,0x258C,0x2590,
    0x2591,0x2592,0x2593,0x2320,0x25A0,0x2219,0x221A,0x2248,0x2264,0x2265,0x00A0,0x2321,0x00B0,0x00B2,0x00B7,0x00F7,
    0x2550,0x2551,0x2552,0x0451,0x2553,0x2554,0x2555,0x2556,0x2557,0x2558,0x2559,0x255A,0x255B,0x255C,0x255D,0x255E,
    0x255F,0x2560,0x2561,0x0401,0x2562,0x2563,0x2564,0x2565,0x2566,0x2567,0x2568,0x2569,0x256A,0x256B,0x256C,0x00A9,
    0x044E,0x0430,0x0431,0x0446,0x0434,0x0435,0x0444,0x0433,0x0445,0x0438,0x0439,0x043A,0x043B,0x043C,0x043D,0x043E,
    0x043F,0x044F,0x0440,0x0441,0x0442,0x0443,0x0436,0x0432,0x044C,0x044B,0x0437,0x0448,0x044D,0x0449,0x0447,0x044A,
    0x042E,0x0410,0x0411,0x0426,0x0414,0x0415,0x0424,0x0413,0x0425,0x0418,0x0419,0x041A,0x041B,0x041C,0x041D,0x041E,
    0x041F,0x042F,0x0420,0x0421,0x0422,0x0423,0x0416,0x0412,0x042C,0x042B,0x0417,0x0428,0x042D,0x0429,0x0427,0x042A,
  ];

  static String _decodeIso88595(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0xA0) {
        buf.writeCharCode(b);
      } else if (b >= 0xA0 && b <= 0xAF) {
        buf.writeCharCode(b - 0xA0 + 0x0400); // Ёё etc
      } else if (b >= 0xB0 && b <= 0xEF) {
        buf.writeCharCode(b - 0xB0 + 0x0410); // А-я
      } else if (b >= 0xF0) {
        buf.writeCharCode(b - 0xF0 + 0x0450);
      } else {
        buf.writeCharCode(b);
      }
    }
    return buf.toString();
  }
}

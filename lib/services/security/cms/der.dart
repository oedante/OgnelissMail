// lib/services/security/cms/der.dart
// Минимальный разбор и сборка ASN.1 (DER/BER) для S/MIME.
//
// Разбор понимает и BER: неопределённую длину (0x80 … 00 00) и составные
// OCTET STRING — так кодирует письма Outlook (CryptoAPI). Сборка — строго
// DER (определённая длина, SET OF отсортирован).

import 'dart:convert';
import 'dart:typed_data';

class DerTag {
  DerTag._();
  static const boolean = 0x01;
  static const integer = 0x02;
  static const bitString = 0x03;
  static const octetString = 0x04;
  static const nullTag = 0x05;
  static const oid = 0x06;
  static const utf8String = 0x0C;
  static const printableString = 0x13;
  static const t61String = 0x14;
  static const ia5String = 0x16;
  static const utcTime = 0x17;
  static const generalizedTime = 0x18;
  static const bmpString = 0x1E;
  static const sequence = 0x30;
  static const set = 0x31;
}

/// Узел ASN.1 внутри общего буфера.
class Der {
  final Uint8List buf;

  /// Первый байт тега (класс, составной, номер).
  final int tag;

  /// Начало узла (тег), начало и конец содержимого, конец узла.
  final int start;
  final int contentStart;
  final int contentEnd;
  final int end;

  Der._(this.buf, this.tag, this.start, this.contentStart, this.contentEnd, this.end);

  bool get constructed => tag & 0x20 != 0;
  bool get isContext => tag & 0xC0 == 0x80;
  int get tagNumber => tag & 0x1F;

  /// Узел целиком (тег, длина, содержимое) — для подписи и копирования.
  Uint8List get encoded => Uint8List.sublistView(buf, start, end);

  /// Содержимое (для примитивных узлов).
  Uint8List get content => Uint8List.sublistView(buf, contentStart, contentEnd);

  /// Разобрать один узел с начала [data].
  static Der parse(Uint8List data, [int offset = 0]) => _parse(data, offset);

  static Der _parse(Uint8List b, int pos) {
    final start = pos;
    if (pos >= b.length) throw const FormatException('ASN.1: unexpected end');
    final tag = b[pos++];
    if (tag & 0x1F == 0x1F) {
      // Длинный номер тега (в S/MIME не встречается) — пропускаем.
      while (pos < b.length && b[pos] & 0x80 != 0) {
        pos++;
      }
      pos++;
    }
    if (pos >= b.length) throw const FormatException('ASN.1: unexpected end');
    final first = b[pos++];
    if (first == 0x80) {
      // Неопределённая длина: дети до 00 00.
      if (tag & 0x20 == 0) throw const FormatException('ASN.1: indefinite primitive');
      final cs = pos;
      while (true) {
        if (pos + 1 >= b.length) throw const FormatException('ASN.1: missing end-of-contents');
        if (b[pos] == 0 && b[pos + 1] == 0) {
          return Der._(b, tag, start, cs, pos, pos + 2);
        }
        pos = _parse(b, pos).end;
      }
    }
    int len;
    if (first & 0x80 == 0) {
      len = first;
    } else {
      final n = first & 0x7F;
      if (n > 4) throw const FormatException('ASN.1: length too long');
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | b[pos++];
      }
    }
    final cs = pos;
    final ce = pos + len;
    if (ce > b.length) throw const FormatException('ASN.1: length beyond data');
    return Der._(b, tag, start, cs, ce, ce);
  }

  /// Дети составного узла.
  List<Der> get children {
    if (!constructed) return const [];
    final out = <Der>[];
    var p = contentStart;
    while (p < contentEnd) {
      final c = _parse(buf, p);
      out.add(c);
      p = c.end;
    }
    return out;
  }

  Der operator [](int i) => children[i];

  /// Байты OCTET STRING (в том числе составной BER).
  Uint8List get octets {
    if (!constructed) return Uint8List.fromList(content);
    final out = BytesBuilder(copy: false);
    for (final c in children) {
      out.add(c.octets);
    }
    return out.toBytes();
  }

  /// INTEGER → BigInt (дополнительный код).
  BigInt get integer {
    final c = content;
    if (c.isEmpty) return BigInt.zero;
    var v = BigInt.zero;
    for (final x in c) {
      v = (v << 8) | BigInt.from(x);
    }
    if (c[0] & 0x80 != 0) v -= BigInt.one << (c.length * 8);
    return v;
  }

  int get intValue => integer.toInt();

  /// OBJECT IDENTIFIER строкой «1.2.840…».
  String get oid {
    final c = content;
    if (c.isEmpty) return '';
    final parts = <int>[];
    var v = 0;
    for (var i = 0; i < c.length; i++) {
      v = (v << 7) | (c[i] & 0x7F);
      if (c[i] & 0x80 == 0) {
        parts.add(v);
        v = 0;
      }
    }
    final first = parts.first;
    final a = first < 40 ? 0 : (first < 80 ? 1 : 2);
    return [a, first - a * 40, ...parts.skip(1)].join('.');
  }

  /// Строка любого из строковых типов.
  String get string {
    final c = content;
    switch (tag) {
      case DerTag.bmpString:
        return String.fromCharCodes([for (var i = 0; i + 1 < c.length; i += 2) (c[i] << 8) | c[i + 1]]);
      case DerTag.t61String:
        return latin1.decode(c);
      default:
        return utf8.decode(c, allowMalformed: true);
    }
  }

  /// UTCTime / GeneralizedTime → DateTime (UTC).
  DateTime? get time {
    final s = ascii.decode(content, allowInvalid: true).replaceAll('Z', '');
    try {
      if (tag == DerTag.utcTime) {
        var y = int.parse(s.substring(0, 2));
        y += y < 50 ? 2000 : 1900;
        return DateTime.utc(y, int.parse(s.substring(2, 4)), int.parse(s.substring(4, 6)),
            int.parse(s.substring(6, 8)), int.parse(s.substring(8, 10)), s.length >= 12 ? int.parse(s.substring(10, 12)) : 0);
      }
      if (tag == DerTag.generalizedTime) {
        return DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)),
            int.parse(s.substring(8, 10)), int.parse(s.substring(10, 12)), s.length >= 14 ? int.parse(s.substring(12, 14)) : 0);
      }
    } catch (_) {}
    return null;
  }
}

// ─────────────────────────── сборка DER ───────────────────────────

Uint8List derLength(int n) {
  if (n < 0x80) return Uint8List.fromList([n]);
  final bytes = <int>[];
  var v = n;
  while (v > 0) {
    bytes.insert(0, v & 0xFF);
    v >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

Uint8List derTlv(int tag, List<int> content) {
  final out = BytesBuilder(copy: false)
    ..addByte(tag)
    ..add(derLength(content.length))
    ..add(content);
  return out.toBytes();
}

Uint8List _concat(Iterable<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

Uint8List derSeq(List<List<int>> items) => derTlv(DerTag.sequence, _concat(items));

/// SET OF — элементы сортируются по кодировке (требование DER).
Uint8List derSet(List<List<int>> items) {
  final sorted = List<List<int>>.of(items)..sort(_compareBytes);
  return derTlv(DerTag.set, _concat(sorted));
}

int _compareBytes(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

Uint8List derNull() => Uint8List.fromList([DerTag.nullTag, 0]);

Uint8List derOctets(List<int> b) => derTlv(DerTag.octetString, b);

Uint8List derInt(BigInt v) {
  if (v == BigInt.zero) return derTlv(DerTag.integer, [0]);
  final bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.insert(0, (x & BigInt.from(0xFF)).toInt());
    x >>= 8;
  }
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return derTlv(DerTag.integer, bytes);
}

Uint8List derSmallInt(int v) => derInt(BigInt.from(v));

Uint8List derOid(String oid) {
  final p = oid.split('.').map(int.parse).toList();
  final out = <int>[p[0] * 40 + p[1]];
  for (final v in p.skip(2)) {
    final chunk = <int>[v & 0x7F];
    var x = v >> 7;
    while (x > 0) {
      chunk.insert(0, (x & 0x7F) | 0x80);
      x >>= 7;
    }
    out.addAll(chunk);
  }
  return derTlv(DerTag.oid, out);
}

Uint8List derUtcTime(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final s = '${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  return derTlv(DerTag.utcTime, ascii.encode(s));
}

/// [n] EXPLICIT — составной контекстный тег вокруг готового узла.
Uint8List derExplicit(int n, List<int> inner) => derTlv(0xA0 | n, inner);

/// [n] IMPLICIT для составного содержимого (SET OF сертификатов и т. п.).
Uint8List derImplicitConstructed(int n, List<int> content) => derTlv(0xA0 | n, content);

/// [n] IMPLICIT для примитивного содержимого (encryptedContent и т. п.).
Uint8List derImplicitPrimitive(int n, List<int> content) => derTlv(0x80 | n, content);

/// AlgorithmIdentifier { oid, params? }.
Uint8List derAlg(String oid, [List<int>? params]) => derSeq([derOid(oid), if (params != null) params]);

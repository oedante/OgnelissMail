// lib/core/security/ca_chain_verifier.dart
// Проверка, что сертификат сервера выпущен одним из заданных центров
// сертификации (ЦС) — без добавления ЦС в общее хранилище доверия.
//
// Зачем: сертификаты Минцифры включаются для отдельных ящиков. Если добавить
// их в SecurityContext.defaultContext, приложение доверяло бы этому ЦС для
// ЛЮБЫХ серверов (Google, Microsoft…). Вместо этого ЦС в хранилище нет, а
// сертификат, который системная проверка отвергла, проверяется здесь: только
// для хостов ящиков, где пользователь включил ЦС Минцифры.
//
// Проверяется: подпись сертификата ключом выпускающего ЦС (RSA PKCS#1 v1.5,
// SHA-256/384/512), имя издателя = имя ЦС, срок действия сертификата и ЦС,
// имя хоста по subjectAltName (или CN, если SAN нет). Конечные сертификаты
// НУЦ выпускаются прямо «Russian Trusted Sub CA» — цепочка из одного звена.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CaChainVerifier {
  CaChainVerifier._();

  /// [leafDer] выпущен одним из [issuers] (DER) и подходит для [host]?
  static bool verify({
    required Uint8List leafDer,
    required List<Uint8List> issuers,
    required String host,
    DateTime? now,
  }) {
    try {
      final at = (now ?? DateTime.now()).toUtc();
      final leaf = _Cert.parse(leafDer);
      if (!leaf.validAt(at)) return false;
      if (!_hostMatches(leaf, host.toLowerCase())) return false;
      for (final der in issuers) {
        final ca = _Cert.parse(der);
        if (!_bytesEq(leaf.issuerRaw, ca.subjectRaw)) continue;
        if (!ca.validAt(at)) continue;
        if (_verifyRsa(leaf, ca)) return true;
      }
    } catch (_) {
      // Не разобрали — не доверяем.
    }
    return false;
  }

  // ─────────────────────────── подпись ───────────────────────────

  static const _oidSha256Rsa = '2a864886f70d01010b';
  static const _oidSha384Rsa = '2a864886f70d01010c';
  static const _oidSha512Rsa = '2a864886f70d01010d';

  static bool _verifyRsa(_Cert leaf, _Cert ca) {
    final key = ca.rsaKey;
    if (key == null) return false;
    final List<int> digestInfoPrefix;
    final List<int> hash;
    switch (leaf.sigAlgOid) {
      case _oidSha256Rsa:
        digestInfoPrefix = _hex('3031300d060960864801650304020105000420');
        hash = sha256.convert(leaf.tbsRaw).bytes;
      case _oidSha384Rsa:
        digestInfoPrefix = _hex('3041300d060960864801650304020205000430');
        hash = sha384.convert(leaf.tbsRaw).bytes;
      case _oidSha512Rsa:
        digestInfoPrefix = _hex('3051300d060960864801650304020305000440');
        hash = sha512.convert(leaf.tbsRaw).bytes;
      default:
        return false; // ГОСТ и ECDSA здесь не поддерживаются
    }
    final k = (key.n.bitLength + 7) >> 3;
    final s = _toBigInt(leaf.signature);
    if (s >= key.n) return false;
    final em = _toBytes(s.modPow(key.e, key.n), k);
    // EM = 00 01 FF…FF 00 || DigestInfo || hash
    final t = [...digestInfoPrefix, ...hash];
    final psLen = k - 3 - t.length;
    if (psLen < 8) return false;
    if (em[0] != 0x00 || em[1] != 0x01) return false;
    for (var i = 0; i < psLen; i++) {
      if (em[2 + i] != 0xff) return false;
    }
    if (em[2 + psLen] != 0x00) return false;
    for (var i = 0; i < t.length; i++) {
      if (em[3 + psLen + i] != t[i]) return false;
    }
    return true;
  }

  // ─────────────────────────── имя хоста ───────────────────────────

  static bool _hostMatches(_Cert c, String host) {
    final names = c.dnsNames.isNotEmpty ? c.dnsNames : [if (c.commonName != null) c.commonName!];
    for (final raw in names) {
      final n = raw.toLowerCase();
      if (n == host) return true;
      // *.corp.ru — ровно одна метка слева.
      if (n.startsWith('*.')) {
        final suffix = n.substring(1); // .corp.ru
        if (host.endsWith(suffix)) {
          final left = host.substring(0, host.length - suffix.length);
          if (left.isNotEmpty && !left.contains('.')) return true;
        }
      }
    }
    return false;
  }

  // ─────────────────────────── утилиты ───────────────────────────

  static List<int> _hex(String h) =>
      [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

  static BigInt _toBigInt(List<int> b) {
    var r = BigInt.zero;
    for (final x in b) {
      r = (r << 8) | BigInt.from(x);
    }
    return r;
  }

  static List<int> _toBytes(BigInt v, int len) {
    final out = List<int>.filled(len, 0);
    var x = v;
    for (var i = len - 1; i >= 0 && x > BigInt.zero; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static bool _bytesEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─────────────────────────── разбор DER ───────────────────────────

class _Tlv {
  final int tag;
  final int start; // начало заголовка
  final int content; // начало содержимого
  final int end; // конец содержимого
  const _Tlv(this.tag, this.start, this.content, this.end);
}

_Tlv _read(Uint8List b, int pos) {
  final tag = b[pos];
  var p = pos + 1;
  var len = b[p++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    if (n == 0 || n > 4) throw const FormatException('DER: длина');
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | b[p++];
    }
  }
  if (p + len > b.length) throw const FormatException('DER: выход за границу');
  return _Tlv(tag, pos, p, p + len);
}

List<_Tlv> _children(Uint8List b, _Tlv t) {
  final out = <_Tlv>[];
  var p = t.content;
  while (p < t.end) {
    final c = _read(b, p);
    out.add(c);
    p = c.end;
  }
  return out;
}

String _hexOf(Uint8List b, _Tlv t) =>
    b.sublist(t.content, t.end).map((x) => x.toRadixString(16).padLeft(2, '0')).join();

DateTime _time(Uint8List b, _Tlv t) {
  final s = String.fromCharCodes(b.sublist(t.content, t.end));
  // UTCTime YYMMDDHHMMSSZ или GeneralizedTime YYYYMMDDHHMMSSZ
  int year;
  String rest;
  if (t.tag == 0x17) {
    final yy = int.parse(s.substring(0, 2));
    year = yy >= 50 ? 1900 + yy : 2000 + yy;
    rest = s.substring(2);
  } else {
    year = int.parse(s.substring(0, 4));
    rest = s.substring(4);
  }
  return DateTime.utc(
    year,
    int.parse(rest.substring(0, 2)),
    int.parse(rest.substring(2, 4)),
    int.parse(rest.substring(4, 6)),
    int.parse(rest.substring(6, 8)),
    rest.length >= 10 && rest[8] != 'Z' ? int.parse(rest.substring(8, 10)) : 0,
  );
}

class _Cert {
  final Uint8List tbsRaw;
  final Uint8List issuerRaw;
  final Uint8List subjectRaw;
  final DateTime notBefore;
  final DateTime notAfter;
  final String sigAlgOid;
  final Uint8List signature;
  final ({BigInt n, BigInt e})? rsaKey;
  final List<String> dnsNames;
  final String? commonName;

  _Cert(this.tbsRaw, this.issuerRaw, this.subjectRaw, this.notBefore, this.notAfter,
      this.sigAlgOid, this.signature, this.rsaKey, this.dnsNames, this.commonName);

  bool validAt(DateTime t) => !t.isBefore(notBefore) && !t.isAfter(notAfter);

  static _Cert parse(Uint8List b) {
    final cert = _read(b, 0);
    final parts = _children(b, cert);
    final tbs = parts[0];
    final sigAlg = _children(b, parts[1]);
    final sigBits = parts[2];
    final f = _children(b, tbs);
    final off = f[0].tag == 0xa0 ? 1 : 0;
    final issuer = f[off + 2];
    final validity = _children(b, f[off + 3]);
    final subject = f[off + 4];
    final spki = f[off + 5];

    // Открытый ключ RSA: SPKI = SEQ { AlgId, BIT STRING { SEQ { n, e } } }
    ({BigInt n, BigInt e})? rsa;
    final spkiParts = _children(b, spki);
    final algOid = _hexOf(b, _children(b, spkiParts[0])[0]);
    if (algOid == '2a864886f70d010101') {
      final bits = spkiParts[1];
      final seq = _read(b, bits.content + 1);
      final ne = _children(b, seq);
      rsa = (
        n: CaChainVerifier._toBigInt(b.sublist(ne[0].content, ne[0].end)),
        e: CaChainVerifier._toBigInt(b.sublist(ne[1].content, ne[1].end)),
      );
    }

    // subjectAltName (2.5.29.17) → dNSName [2]
    final dns = <String>[];
    for (final ext in f.skip(off + 6)) {
      if (ext.tag != 0xa3) continue;
      final list = _children(b, ext);
      if (list.isEmpty) continue;
      for (final e in _children(b, list[0])) {
        final ep = _children(b, e);
        if (ep.isEmpty || _hexOf(b, ep[0]) != '551d11') continue;
        final octet = ep.last; // OCTET STRING с GeneralNames
        final names = _read(b, octet.content);
        for (final gn in _children(b, names)) {
          if (gn.tag == 0x82) dns.add(String.fromCharCodes(b.sublist(gn.content, gn.end)));
        }
      }
    }

    // CN (2.5.4.3) — на случай сертификата без SAN.
    String? cn;
    for (final rdn in _children(b, subject)) {
      for (final atv in _children(b, rdn)) {
        final p = _children(b, atv);
        if (p.length == 2 && _hexOf(b, p[0]) == '550403') {
          cn = String.fromCharCodes(b.sublist(p[1].content, p[1].end));
        }
      }
    }

    return _Cert(
      b.sublist(tbs.start, tbs.end),
      b.sublist(issuer.start, issuer.end),
      b.sublist(subject.start, subject.end),
      _time(b, validity[0]),
      _time(b, validity[1]),
      _hexOf(b, sigAlg[0]),
      b.sublist(sigBits.content + 1, sigBits.end),
      rsa,
      dns,
      cn,
    );
  }
}

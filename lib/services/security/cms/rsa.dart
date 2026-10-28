// lib/services/security/cms/rsa.dart
// RSA для S/MIME: подпись и проверка PKCS#1 v1.5, шифрование ключа
// PKCS#1 v1.5 (как Outlook по умолчанию), расшифровка v1.5 и OAEP.
// Арифметика — BigInt.modPow; закрытый ключ — по китайской теореме об
// остатках (в несколько раз быстрее).

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

class RsaPublicKey {
  final BigInt n;
  final BigInt e;
  const RsaPublicKey(this.n, this.e);

  /// Длина модуля в байтах.
  int get k => (n.bitLength + 7) ~/ 8;
}

class RsaPrivateKey {
  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt? p;
  final BigInt? q;
  final BigInt? dp;
  final BigInt? dq;
  final BigInt? qInv;
  const RsaPrivateKey(this.n, this.e, this.d, {this.p, this.q, this.dp, this.dq, this.qInv});

  int get k => (n.bitLength + 7) ~/ 8;
  RsaPublicKey get publicKey => RsaPublicKey(n, e);
}

class RsaException implements Exception {
  final String message;
  const RsaException(this.message);
  @override
  String toString() => 'RSA: $message';
}

BigInt os2ip(List<int> b) {
  var v = BigInt.zero;
  for (final x in b) {
    v = (v << 8) | BigInt.from(x);
  }
  return v;
}

Uint8List i2osp(BigInt x, int len) {
  final out = Uint8List(len);
  var v = x;
  for (var i = len - 1; i >= 0 && v > BigInt.zero; i--) {
    out[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  if (v > BigInt.zero) throw const RsaException('integer too large');
  return out;
}

BigInt _privateOp(RsaPrivateKey key, BigInt c) {
  final p = key.p, q = key.q, dp = key.dp, dq = key.dq, qInv = key.qInv;
  if (p != null && q != null && dp != null && dq != null && qInv != null) {
    final m1 = c.modPow(dp, p);
    final m2 = c.modPow(dq, q);
    final h = (qInv * (m1 - m2)) % p;
    return m2 + h * q;
  }
  return c.modPow(key.d, key.n);
}

/// DigestInfo-префиксы (RFC 8017, 9.2).
const _digestInfoPrefix = <String, List<int>>{
  'sha1': [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14],
  'sha256': [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20],
  'sha384': [0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30],
  'sha512': [0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40],
};

/// Префикс без NULL-параметров (некоторые подписывающие так кодируют).
List<int> _prefixWithoutNull(List<int> p) {
  // 30 L 30 L' 06 … 05 00 04 n  →  30 (L-2) 30 (L'-2) 06 … 04 n
  final out = List<int>.of(p);
  final nullAt = out.length - 4;
  out.removeRange(nullAt, nullAt + 2);
  out[1] -= 2;
  out[3] -= 2;
  return out;
}

Uint8List _emsaPkcs1(String hashName, List<int> digest, int k) {
  final prefix = _digestInfoPrefix[hashName];
  if (prefix == null) throw RsaException('unsupported hash $hashName');
  final t = [...prefix, ...digest];
  if (k < t.length + 11) throw const RsaException('key too short');
  return Uint8List.fromList([0x00, 0x01, ...List.filled(k - t.length - 3, 0xFF), 0x00, ...t]);
}

/// Подпись RSASSA-PKCS1-v1_5 готового хеша [digest].
Uint8List rsaSign(RsaPrivateKey key, String hashName, List<int> digest) {
  final em = _emsaPkcs1(hashName, digest, key.k);
  return i2osp(_privateOp(key, os2ip(em)), key.k);
}

/// Проверка RSASSA-PKCS1-v1_5.
bool rsaVerify(RsaPublicKey key, String hashName, List<int> digest, List<int> signature) {
  if (signature.length > key.k) return false;
  final s = os2ip(signature);
  if (s >= key.n) return false;
  final em = i2osp(s.modPow(key.e, key.n), key.k);
  final expected = _emsaPkcs1(hashName, digest, key.k);
  if (_eq(em, expected)) return true;
  // Вариант DigestInfo без NULL.
  final prefix = _prefixWithoutNull(_digestInfoPrefix[hashName]!);
  final t = [...prefix, ...digest];
  final alt = [0x00, 0x01, ...List.filled(key.k - t.length - 3, 0xFF), 0x00, ...t];
  return _eq(em, alt);
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

final _rnd = Random.secure();

Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rnd.nextInt(256)));

/// Шифрование RSAES-PKCS1-v1_5 (ключ содержимого для получателя).
Uint8List rsaEncryptPkcs1(RsaPublicKey key, List<int> m) {
  final k = key.k;
  if (m.length > k - 11) throw const RsaException('message too long');
  final ps = List.generate(k - m.length - 3, (_) => 1 + _rnd.nextInt(255));
  final em = [0x00, 0x02, ...ps, 0x00, ...m];
  return i2osp(os2ip(em).modPow(key.e, key.n), k);
}

/// Расшифровка RSAES-PKCS1-v1_5.
Uint8List rsaDecryptPkcs1(RsaPrivateKey key, List<int> c) {
  final em = i2osp(_privateOp(key, os2ip(c)), key.k);
  if (em[0] != 0 || em[1] != 2) throw const RsaException('decryption error');
  var i = 2;
  while (i < em.length && em[i] != 0) {
    i++;
  }
  if (i >= em.length || i < 10) throw const RsaException('decryption error');
  return Uint8List.fromList(em.sublist(i + 1));
}

List<int> _hashBytes(String name, List<int> data) => switch (name) {
      'sha1' => hash.sha1.convert(data).bytes,
      'sha384' => hash.sha384.convert(data).bytes,
      'sha512' => hash.sha512.convert(data).bytes,
      _ => hash.sha256.convert(data).bytes,
    };

List<int> _mgf1(String hashName, List<int> seed, int len) {
  final out = <int>[];
  var counter = 0;
  while (out.length < len) {
    final c = [(counter >> 24) & 0xFF, (counter >> 16) & 0xFF, (counter >> 8) & 0xFF, counter & 0xFF];
    out.addAll(_hashBytes(hashName, [...seed, ...c]));
    counter++;
  }
  return out.sublist(0, len);
}

/// Расшифровка RSAES-OAEP (по умолчанию SHA-1 и MGF1-SHA-1, пустая метка).
Uint8List rsaDecryptOaep(RsaPrivateKey key, List<int> c, {String hashName = 'sha1', String mgfHash = 'sha1'}) {
  final k = key.k;
  final em = i2osp(_privateOp(key, os2ip(c)), k);
  final hLen = _hashBytes(hashName, const []).length;
  if (em[0] != 0) throw const RsaException('decryption error');
  final maskedSeed = em.sublist(1, 1 + hLen);
  final maskedDb = em.sublist(1 + hLen);
  final seedMask = _mgf1(mgfHash, maskedDb, hLen);
  final seed = [for (var i = 0; i < hLen; i++) maskedSeed[i] ^ seedMask[i]];
  final dbMask = _mgf1(mgfHash, seed, maskedDb.length);
  final db = [for (var i = 0; i < maskedDb.length; i++) maskedDb[i] ^ dbMask[i]];
  final lHash = _hashBytes(hashName, const []);
  if (!_eq(db.sublist(0, hLen), lHash)) throw const RsaException('decryption error');
  var i = hLen;
  while (i < db.length && db[i] == 0) {
    i++;
  }
  if (i >= db.length || db[i] != 1) throw const RsaException('decryption error');
  return Uint8List.fromList(db.sublist(i + 1));
}

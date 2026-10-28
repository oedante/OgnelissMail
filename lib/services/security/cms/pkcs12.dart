// lib/services/security/cms/pkcs12.dart
// Чтение .p12/.pfx (RFC 7292): закрытый ключ RSA и сертификаты.
//
// Понимает и старые файлы (Windows по умолчанию: PBE-SHA1-3DES, сертификаты
// PBE-SHA1-RC2-40), и современные (OpenSSL 3, «AES256-SHA256» в Windows:
// PBES2 + PBKDF2 + AES-CBC). Пароль проверяется по MAC файла.

import 'dart:convert';
import 'dart:typed_data';

import 'der.dart';
import 'rsa.dart';
import 'sym.dart';
import 'x509.dart';

class Pkcs12Exception implements Exception {
  /// 'password' — неверный пароль; 'nokey' — в файле нет ключа;
  /// 'unsupported' — алгоритм не поддерживается; 'format' — не .pfx.
  final String code;
  final String message;
  const Pkcs12Exception(this.code, this.message);
  @override
  String toString() => message;
}

/// Ключ и сертификат S/MIME.
class SmimeIdentity {
  final RsaPrivateKey key;
  final SmimeCert certificate;

  /// Остальные сертификаты файла (цепочка издателей).
  final List<SmimeCert> chain;

  const SmimeIdentity(this.key, this.certificate, this.chain);
}

class Pkcs12 {
  Pkcs12._();

  static const _pbeSha1_3des = '1.2.840.113549.1.12.1.3';
  static const _pbeSha1_2des = '1.2.840.113549.1.12.1.4';
  static const _pbeSha1Rc2x128 = '1.2.840.113549.1.12.1.5';
  static const _pbeSha1Rc2x40 = '1.2.840.113549.1.12.1.6';
  static const _pbes2 = '1.2.840.113549.1.5.13';
  static const _pbkdf2 = '1.2.840.113549.1.5.12';

  static const _keyBag = '1.2.840.113549.1.12.10.1.1';
  static const _shroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
  static const _certBag = '1.2.840.113549.1.12.10.1.3';
  static const _x509Cert = '1.2.840.113549.1.9.22.1';

  static SmimeIdentity parse(Uint8List pfx, String password) {
    Der root;
    try {
      root = Der.parse(pfx);
      if (root.tag != DerTag.sequence) throw const FormatException('not a sequence');
    } catch (e) {
      throw Pkcs12Exception('format', 'not a PKCS#12 file: $e');
    }
    final f = root.children;
    if (f.length < 2 || f[1][0].oid != Oids.data) {
      throw const Pkcs12Exception('format', 'unsupported PKCS#12 (public-key integrity)');
    }
    final authSafe = f[1][1][0].octets; // [0] EXPLICIT OCTET STRING

    final bmp = pkcs12Password(password);
    if (f.length > 2) _checkMac(f[2], authSafe, bmp);

    final keys = <RsaPrivateKey>[];
    final certs = <SmimeCert>[];
    for (final ci in Der.parse(authSafe).children) {
      final type = ci[0].oid;
      Uint8List? safeContents;
      if (type == Oids.data) {
        safeContents = ci[1][0].octets;
      } else if (type == Oids.encryptedData) {
        final eci = ci[1][0][1]; // EncryptedData → EncryptedContentInfo
        final alg = eci[1];
        final enc = eci.children.length > 2 ? eci[2].octets : Uint8List(0);
        safeContents = _decrypt(alg, enc, password, bmp);
      }
      if (safeContents == null) continue;
      for (final bag in Der.parse(safeContents).children) {
        final id = bag[0].oid;
        final value = bag[1][0];
        try {
          if (id == _certBag && value[0].oid == _x509Cert) {
            certs.add(SmimeCert.parse(value[1][0].octets));
          } else if (id == _keyBag) {
            keys.add(_privateKeyInfo(value));
          } else if (id == _shroudedKeyBag) {
            final plain = _decrypt(value[0], value[1].octets, password, bmp);
            keys.add(_privateKeyInfo(Der.parse(plain)));
          }
        } on Pkcs12Exception {
          rethrow;
        } catch (_) {
          // Нечитаемый мешок (CRL, секрет) — пропускаем.
        }
      }
    }
    if (keys.isEmpty) throw const Pkcs12Exception('nokey', 'no private key in file');
    for (final k in keys) {
      final own = certs.where((c) => c.rsa != null && c.rsa!.n == k.n).firstOrNull;
      if (own != null) {
        return SmimeIdentity(k, own, [for (final c in certs) if (!identical(c, own)) c]);
      }
    }
    throw const Pkcs12Exception('nokey', 'no certificate for the private key');
  }

  static void _checkMac(Der macData, Uint8List authSafe, Uint8List bmp) {
    try {
      final digestInfo = macData[0];
      final digestName = hashNameOf(digestInfo[0][0].oid);
      if (digestName == null) return; // PBMAC1 и прочее — не проверяем
      final expected = digestInfo[1].content;
      final salt = macData[1].content;
      final iter = macData.children.length > 2 ? macData[2].intValue : 1;
      bool ok(Uint8List pw) {
        final key = pkcs12Kdf(pw, Uint8List.fromList(salt), iter, 3, expected.length, digest: digestName);
        return bytesEqual(hmac(digestName, key, authSafe), expected);
      }
      // Пустой пароль Windows иногда кодирует без завершающих нулей.
      if (!ok(bmp) && !(bmp.length == 2 && ok(Uint8List(0)))) {
        throw const Pkcs12Exception('password', 'wrong password');
      }
    } on Pkcs12Exception {
      rethrow;
    } catch (_) {}
  }

  static Uint8List _decrypt(Der alg, Uint8List data, String password, Uint8List bmp) {
    final oid = alg[0].oid;
    try {
      if (oid == _pbes2) {
        final params = alg[1];
        final kdf = params[0];
        if (kdf[0].oid != _pbkdf2) throw const Pkcs12Exception('unsupported', 'unsupported KDF');
        final kp = kdf[1].children;
        final salt = kp[0].content;
        final iter = kp[1].intValue;
        int? keyLen;
        var prf = 'sha1';
        for (final x in kp.skip(2)) {
          if (x.tag == DerTag.integer) keyLen = x.intValue;
          if (x.tag == DerTag.sequence) {
            prf = switch (x[0].oid) {
              '1.2.840.113549.2.9' => 'sha256',
              '1.2.840.113549.2.10' => 'sha384',
              '1.2.840.113549.2.11' => 'sha512',
              '1.2.840.113549.2.8' => 'sha224',
              _ => 'sha1',
            };
          }
        }
        final scheme = params[1];
        final (cipher, len) = switch (scheme[0].oid) {
          Oids.aes128Cbc => (SymCipher.aes, 16),
          Oids.aes192Cbc => (SymCipher.aes, 24),
          Oids.aes256Cbc => (SymCipher.aes, 32),
          Oids.desEde3Cbc => (SymCipher.desEde3, 24),
          _ => throw const Pkcs12Exception('unsupported', 'unsupported cipher'),
        };
        final iv = scheme[1].content;
        final key = pbkdf2(utf8.encode(password), salt, iter, keyLen ?? len, prf: prf);
        return cbcProcess(false, cipher, key, Uint8List.fromList(iv), data);
      }
      final p = alg[1];
      final salt = Uint8List.fromList(p[0].content);
      final iter = p[1].intValue;
      final (cipher, keyLen, bits) = switch (oid) {
        _pbeSha1_3des => (SymCipher.desEde3, 24, null),
        _pbeSha1_2des => (SymCipher.desEde3, 16, null),
        _pbeSha1Rc2x128 => (SymCipher.rc2, 16, 128),
        _pbeSha1Rc2x40 => (SymCipher.rc2, 5, 40),
        _ => throw const Pkcs12Exception('unsupported', 'unsupported PBE'),
      };
      final key = pkcs12Kdf(bmp, salt, iter, 1, keyLen);
      final iv = pkcs12Kdf(bmp, salt, iter, 2, 8);
      return cbcProcess(false, cipher, key, iv, data, rc2Bits: bits);
    } on CipherException {
      throw const Pkcs12Exception('password', 'wrong password');
    }
  }

  /// PrivateKeyInfo (PKCS#8) → ключ RSA.
  static RsaPrivateKey _privateKeyInfo(Der pki) {
    if (pki[1][0].oid != Oids.rsaEncryption) {
      throw const Pkcs12Exception('unsupported', 'only RSA keys are supported');
    }
    final k = Der.parse(pki[2].content).children;
    return RsaPrivateKey(
      k[1].integer,
      k[2].integer,
      k[3].integer,
      p: k[4].integer,
      q: k[5].integer,
      dp: k[6].integer,
      dq: k[7].integer,
      qInv: k[8].integer,
    );
  }
}

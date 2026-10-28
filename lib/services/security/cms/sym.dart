// lib/services/security/cms/sym.dart
// Симметричные шифры и выработка ключей для S/MIME и PKCS#12:
// AES-128/192/256-CBC, 3DES-CBC, RC2-CBC (старые .pfx), PBKDF2 (PBES2),
// KDF PKCS#12 (RFC 7292, приложение B).

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

class CipherException implements Exception {
  final String message;
  const CipherException(this.message);
  @override
  String toString() => message;
}

enum SymCipher { aes, desEde3, rc2 }

/// CBC с дополнением PKCS#7. [rc2Bits] — эффективная длина ключа RC2.
Uint8List cbcProcess(
  bool encrypt,
  SymCipher cipher,
  Uint8List key,
  Uint8List iv,
  Uint8List data, {
  int? rc2Bits,
}) {
  final BlockCipher engine = switch (cipher) {
    SymCipher.aes => AESEngine(),
    SymCipher.desEde3 => DESedeEngine(),
    SymCipher.rc2 => RC2Engine(),
  };
  final KeyParameter keyParam =
      cipher == SymCipher.rc2 ? RC2Parameters(key, bits: rc2Bits ?? key.length * 8) : KeyParameter(key);
  final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(engine))
    ..init(encrypt, PaddedBlockCipherParameters(ParametersWithIV(keyParam, iv), null));
  try {
    return c.process(data);
  } catch (_) {
    // Неверное дополнение — неверный ключ (пароль) или повреждённые данные.
    throw const CipherException('bad padding');
  }
}

String _hmacName(String prf) => prf;

/// PBKDF2 (RFC 8018) на HMAC с хешем [prf] ('sha1', 'sha256', …).
Uint8List pbkdf2(List<int> password, List<int> salt, int iterations, int length, {String prf = 'sha1'}) {
  final h = switch (_hmacName(prf)) {
    'sha256' => hash.sha256,
    'sha384' => hash.sha384,
    'sha512' => hash.sha512,
    'sha224' => hash.sha224,
    _ => hash.sha1,
  };
  final mac = hash.Hmac(h, password);
  final out = BytesBuilder(copy: false);
  var block = 1;
  while (out.length < length) {
    var u = mac.convert([...salt, (block >> 24) & 0xFF, (block >> 16) & 0xFF, (block >> 8) & 0xFF, block & 0xFF]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
    block++;
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

/// Пароль для KDF PKCS#12: BMPString (UTF-16BE) с двумя нулями в конце.
Uint8List pkcs12Password(String password) {
  final out = <int>[];
  for (final u in password.codeUnits) {
    out
      ..add(u >> 8)
      ..add(u & 0xFF);
  }
  out
    ..add(0)
    ..add(0);
  return Uint8List.fromList(out);
}

Digest _digest(String name) => switch (name) {
      'sha256' => SHA256Digest(),
      'sha384' => SHA384Digest(),
      'sha512' => SHA512Digest(),
      _ => SHA1Digest(),
    };

/// KDF PKCS#12: ключ ([id] = 1), IV (2) или ключ MAC (3).
Uint8List pkcs12Kdf(Uint8List password, Uint8List salt, int iterations, int id, int length, {String digest = 'sha1'}) {
  final g = PKCS12ParametersGenerator(_digest(digest))..init(password, salt, iterations);
  switch (id) {
    case 1:
      return g.generateDerivedParameters(length).key;
    case 2:
      final p = g.generateDerivedParametersWithIV(length, length);
      return p.iv;
    default:
      return g.generateDerivedMacParameters(length).key;
  }
}

/// HMAC для проверки целостности .pfx.
Uint8List hmac(String digest, List<int> key, List<int> data) {
  final h = switch (digest) {
    'sha256' => hash.sha256,
    'sha384' => hash.sha384,
    'sha512' => hash.sha512,
    _ => hash.sha1,
  };
  return Uint8List.fromList(hash.Hmac(h, key).convert(data).bytes);
}

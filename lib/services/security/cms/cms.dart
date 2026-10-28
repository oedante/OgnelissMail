// lib/services/security/cms/cms.dart
// CMS (RFC 5652) для S/MIME: подпись (SignedData) и шифрование
// (EnvelopedData) в том виде, который понимает Outlook.
//
// Подпись: SHA-256, RSA PKCS#1 v1.5, подписанные атрибуты (тип, время,
// хеш, возможности S/MIME), сертификат подписавшего внутри.
// Шифрование: AES-256-CBC, ключ содержимого — RSA PKCS#1 v1.5 для каждого
// получателя и для себя (чтобы читать своё отправленное).
// Чтение: подписи SHA-1/256/384/512 (rsaEncryption и shaXWithRSA);
// расшифровка AES-128/192/256-CBC и 3DES-CBC, ключ — PKCS#1 v1.5 или OAEP.

import 'dart:typed_data';

import 'der.dart';
import 'pkcs12.dart';
import 'rsa.dart';
import 'sym.dart';
import 'x509.dart';

class CmsException implements Exception {
  /// 'notForMe' — письмо зашифровано не для этого сертификата;
  /// 'unsupported' — алгоритм не поддерживается; 'format' — повреждено.
  final String code;
  final String message;
  const CmsException(this.code, this.message);
  @override
  String toString() => message;
}

/// Результат проверки подписи.
class CmsSignature {
  /// Подпись математически верна и хеш совпал с содержимым.
  final bool valid;

  /// Сертификат подписавшего (если есть в письме).
  final SmimeCert? signer;

  final DateTime? signingTime;

  /// Почему не верна / не проверена.
  final String? error;

  /// Содержимое внутри подписи (для «непрозрачной» подписи smime.p7m).
  final Uint8List? content;

  /// Сертификаты из подписи (для шифрования ответа этому человеку).
  final List<SmimeCert> certificates;

  const CmsSignature({
    required this.valid,
    this.signer,
    this.signingTime,
    this.error,
    this.content,
    this.certificates = const [],
  });
}

class Cms {
  Cms._();

  // ─────────────────────────── подпись ───────────────────────────

  /// Отделённая подпись [content] (байты подписываемой MIME-части).
  static Uint8List signDetached(SmimeIdentity id, Uint8List content, {DateTime? now}) {
    final digest = digestOf('sha256', content);
    final attrs = <Uint8List>[
      derSeq([derOid(Oids.contentType), derSet([derOid(Oids.data)])]),
      derSeq([derOid(Oids.signingTime), derSet([derUtcTime(now ?? DateTime.now())])]),
      derSeq([derOid(Oids.messageDigest), derSet([derOctets(digest)])]),
      derSeq([
        derOid(Oids.smimeCapabilities),
        derSet([
          derSeq([
            derAlg(Oids.aes256Cbc),
            derAlg(Oids.aes192Cbc),
            derAlg(Oids.aes128Cbc),
            derAlg(Oids.desEde3Cbc),
          ]),
        ]),
      ]),
    ];
    // Подписывается кодировка атрибутов как SET (тег 0x31)…
    final attrSet = derSet(attrs);
    final signature = rsaSign(id.key, 'sha256', digestOf('sha256', attrSet));
    // …а в SignerInfo они лежат как [0] IMPLICIT (тот же DER, тег 0xA0).
    final signedAttrs = Uint8List.fromList(attrSet)..[0] = 0xA0;

    final signerInfo = derSeq([
      derSmallInt(1),
      derSeq([id.certificate.issuerDer, id.certificate.serialDer]),
      derAlg(Oids.sha256),
      signedAttrs,
      derAlg(Oids.rsaEncryption, derNull()),
      derOctets(signature),
    ]);
    final certs = <int>[...id.certificate.der, for (final c in id.chain) ...c.der];
    final signedData = derSeq([
      derSmallInt(1),
      derSet([derAlg(Oids.sha256)]),
      derSeq([derOid(Oids.data)]),
      derImplicitConstructed(0, certs),
      derSet([signerInfo]),
    ]);
    return derSeq([derOid(Oids.signedData), derExplicit(0, signedData)]);
  }

  /// Проверить подпись. [detachedContent] — подписанная часть письма
  /// (для multipart/signed); без неё берётся содержимое из самой подписи.
  static CmsSignature verify(Uint8List cms, {Uint8List? detachedContent}) {
    Der sd;
    try {
      final ci = Der.parse(cms);
      if (ci[0].oid != Oids.signedData) throw const CmsException('format', 'not SignedData');
      sd = ci[1][0];
    } catch (e) {
      return CmsSignature(valid: false, error: 'format: $e');
    }
    final parts = sd.children;
    final encap = parts[2];
    Uint8List? content = detachedContent;
    if (content == null && encap.children.length > 1) {
      content = encap[1][0].octets;
    }
    final certs = <SmimeCert>[];
    Der? signerInfos;
    for (final p in parts.skip(3)) {
      if (p.tag == 0xA0) {
        for (final c in p.children) {
          try {
            certs.add(SmimeCert.parse(Uint8List.fromList(c.encoded)));
          } catch (_) {}
        }
      } else if (p.tag == DerTag.set) {
        signerInfos = p;
      }
    }
    if (signerInfos == null || signerInfos.children.isEmpty) {
      return CmsSignature(valid: false, error: 'no signer', content: content, certificates: certs);
    }
    if (content == null) {
      return CmsSignature(valid: false, error: 'no content', certificates: certs);
    }
    final si = signerInfos.children.first;
    final f = si.children;
    // sid: IssuerAndSerialNumber или [0] SubjectKeyIdentifier.
    final sid = f[1];
    SmimeCert? signer;
    if (sid.tag == DerTag.sequence) {
      final issuer = Uint8List.fromList(sid[0].encoded);
      final serial = sid[1].integer;
      signer = certs.where((c) => c.matchesIssuerSerial(issuer, serial)).firstOrNull;
    } else if (sid.tag == 0x80) {
      signer = certs.where((c) => c.matchesKeyId(sid.content)).firstOrNull;
    }
    final hashName = hashNameOf(f[2][0].oid);
    var i = 3;
    Der? signedAttrs;
    if (f[i].tag == 0xA0) signedAttrs = f[i++];
    final sigAlg = f[i++][0].oid;
    final signature = f[i].content;
    DateTime? signingTime;

    if (signer == null || signer.rsa == null) {
      return CmsSignature(valid: false, error: 'signer certificate missing', content: content, certificates: certs);
    }
    if (hashName == null || sigAlg == Oids.rsaPss) {
      return CmsSignature(
          valid: false, signer: signer, error: 'unsupported algorithm', content: content, certificates: certs);
    }
    final digest = digestOf(hashName, content);
    Uint8List toVerify;
    if (signedAttrs != null) {
      Uint8List? md;
      for (final a in signedAttrs.children) {
        final id = a[0].oid;
        if (id == Oids.messageDigest) md = a[1][0].content;
        if (id == Oids.signingTime) signingTime = a[1][0].time;
      }
      if (md == null || !bytesEqual(md, digest)) {
        return CmsSignature(
          valid: false,
          signer: signer,
          signingTime: signingTime,
          error: 'content changed',
          content: content,
          certificates: certs,
        );
      }
      final enc = Uint8List.fromList(signedAttrs.encoded)..[0] = DerTag.set;
      toVerify = digestOf(hashName, enc);
    } else {
      toVerify = digest;
    }
    final ok = rsaVerify(signer.rsa!, hashName, toVerify, signature);
    return CmsSignature(
      valid: ok,
      signer: signer,
      signingTime: signingTime,
      error: ok ? null : 'bad signature',
      content: content,
      certificates: certs,
    );
  }

  // ─────────────────────────── шифрование ───────────────────────────

  /// Зашифровать [content] для [recipients] (сертификаты RSA).
  static Uint8List envelope(Uint8List content, List<SmimeCert> recipients) {
    if (recipients.isEmpty) throw const CmsException('format', 'no recipients');
    final cek = randomBytes(32);
    final iv = randomBytes(16);
    final encrypted = cbcProcess(true, SymCipher.aes, cek, iv, content);
    final infos = <Uint8List>[];
    final seen = <String>{};
    for (final r in recipients) {
      final pk = r.rsa;
      if (pk == null) throw const CmsException('unsupported', 'recipient key is not RSA');
      if (!seen.add(r.thumbprint)) continue;
      infos.add(derSeq([
        derSmallInt(0),
        derSeq([r.issuerDer, r.serialDer]),
        derAlg(Oids.rsaEncryption, derNull()),
        derOctets(rsaEncryptPkcs1(pk, cek)),
      ]));
    }
    final env = derSeq([
      derSmallInt(0),
      derSet(infos),
      derSeq([
        derOid(Oids.data),
        derAlg(Oids.aes256Cbc, derOctets(iv)),
        derImplicitPrimitive(0, encrypted),
      ]),
    ]);
    return derSeq([derOid(Oids.envelopedData), derExplicit(0, env)]);
  }

  /// Расшифровать EnvelopedData ключом [id].
  static Uint8List decrypt(Uint8List cms, SmimeIdentity id) {
    Der env;
    try {
      final ci = Der.parse(cms);
      if (ci[0].oid != Oids.envelopedData) throw const CmsException('format', 'not EnvelopedData');
      env = ci[1][0];
    } on CmsException {
      rethrow;
    } catch (e) {
      throw CmsException('format', 'damaged: $e');
    }
    final f = env.children;
    var i = 1;
    if (f[i].tag == 0xA0) i++; // originatorInfo
    final recipientInfos = f[i++];
    final eci = f[i];

    Uint8List? cek;
    var sawKeyTrans = false;
    for (final ri in recipientInfos.children) {
      if (ri.tag != DerTag.sequence) continue; // kari/kekri/pwri — не поддерживаем
      sawKeyTrans = true;
      final rid = ri[1];
      final mine = rid.tag == DerTag.sequence
          ? id.certificate.matchesIssuerSerial(Uint8List.fromList(rid[0].encoded), rid[1].integer)
          : (rid.tag == 0x80 && id.certificate.matchesKeyId(rid.content));
      if (!mine) continue;
      final alg = ri[2];
      final encKey = ri[3].content;
      if (alg[0].oid == Oids.rsaOaep) {
        var h = 'sha1';
        var mgf = 'sha1';
        if (alg.children.length > 1) {
          for (final p in alg[1].children) {
            if (p.tag == 0xA0) h = hashNameOf(p[0][0].oid) ?? 'sha1';
            if (p.tag == 0xA1) mgf = hashNameOf(p[0][1][0].oid) ?? 'sha1';
          }
        }
        cek = rsaDecryptOaep(id.key, encKey, hashName: h, mgfHash: mgf);
      } else {
        cek = rsaDecryptPkcs1(id.key, encKey);
      }
      break;
    }
    if (cek == null) {
      throw CmsException(sawKeyTrans ? 'notForMe' : 'unsupported',
          sawKeyTrans ? 'encrypted for another certificate' : 'unsupported recipient type');
    }

    final alg = eci[1];
    final (cipher, keyLen) = switch (alg[0].oid) {
      Oids.aes128Cbc => (SymCipher.aes, 16),
      Oids.aes192Cbc => (SymCipher.aes, 24),
      Oids.aes256Cbc => (SymCipher.aes, 32),
      Oids.desEde3Cbc => (SymCipher.desEde3, 24),
      final o => throw CmsException('unsupported', 'content cipher $o'),
    };
    if (cek.length != keyLen) throw const CmsException('format', 'wrong key length');
    final iv = Uint8List.fromList(alg[1].content);
    final data = eci.children.length > 2 ? eci[2].octets : Uint8List(0);
    try {
      return cbcProcess(false, cipher, cek, iv, data);
    } on CipherException {
      throw const CmsException('format', 'decryption failed');
    }
  }

  /// Тип содержимого CMS: signedData, envelopedData или null.
  static String? contentType(Uint8List cms) {
    try {
      return Der.parse(cms)[0].oid;
    } catch (_) {
      return null;
    }
  }
}

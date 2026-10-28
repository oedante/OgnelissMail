// lib/services/security/cms/x509.dart
// Сертификат X.509 — то, что нужно для S/MIME: кому выдан (имя, адрес),
// кем, срок, серийный номер и издатель (для поиска в CMS), открытый ключ RSA.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import 'der.dart';
import 'rsa.dart';

class Oids {
  Oids._();
  static const data = '1.2.840.113549.1.7.1';
  static const signedData = '1.2.840.113549.1.7.2';
  static const envelopedData = '1.2.840.113549.1.7.3';
  static const encryptedData = '1.2.840.113549.1.7.6';

  static const rsaEncryption = '1.2.840.113549.1.1.1';
  static const rsaOaep = '1.2.840.113549.1.1.7';
  static const mgf1 = '1.2.840.113549.1.1.8';
  static const rsaPss = '1.2.840.113549.1.1.10';
  static const sha1WithRsa = '1.2.840.113549.1.1.5';
  static const sha256WithRsa = '1.2.840.113549.1.1.11';
  static const sha384WithRsa = '1.2.840.113549.1.1.12';
  static const sha512WithRsa = '1.2.840.113549.1.1.13';

  static const sha1 = '1.3.14.3.2.26';
  static const sha256 = '2.16.840.1.101.3.4.2.1';
  static const sha384 = '2.16.840.1.101.3.4.2.2';
  static const sha512 = '2.16.840.1.101.3.4.2.3';

  static const aes128Cbc = '2.16.840.1.101.3.4.1.2';
  static const aes192Cbc = '2.16.840.1.101.3.4.1.22';
  static const aes256Cbc = '2.16.840.1.101.3.4.1.42';
  static const desEde3Cbc = '1.2.840.113549.3.7';
  static const rc2Cbc = '1.2.840.113549.3.2';

  static const contentType = '1.2.840.113549.1.9.3';
  static const messageDigest = '1.2.840.113549.1.9.4';
  static const signingTime = '1.2.840.113549.1.9.5';
  static const smimeCapabilities = '1.2.840.113549.1.9.15';
  static const emailAddress = '1.2.840.113549.1.9.1';

  static const commonName = '2.5.4.3';
  static const subjectAltName = '2.5.29.17';
  static const subjectKeyId = '2.5.29.14';
}

/// Имя хеша по OID (для RSA PKCS#1 и подписи CMS).
String? hashNameOf(String oid) => switch (oid) {
      Oids.sha1 || Oids.sha1WithRsa => 'sha1',
      Oids.sha256 || Oids.sha256WithRsa => 'sha256',
      Oids.sha384 || Oids.sha384WithRsa => 'sha384',
      Oids.sha512 || Oids.sha512WithRsa => 'sha512',
      _ => null,
    };

Uint8List digestOf(String name, List<int> data) => Uint8List.fromList(switch (name) {
      'sha1' => hash.sha1.convert(data).bytes,
      'sha384' => hash.sha384.convert(data).bytes,
      'sha512' => hash.sha512.convert(data).bytes,
      _ => hash.sha256.convert(data).bytes,
    });

class SmimeCert {
  /// Сертификат целиком (DER).
  final Uint8List der;

  /// Издатель (DER-узел Name) — копируется в IssuerAndSerialNumber.
  final Uint8List issuerDer;

  /// Серийный номер (DER-узел INTEGER).
  final Uint8List serialDer;
  final BigInt serial;

  final Map<String, String> subject;
  final Map<String, String> issuer;
  final DateTime? notBefore;
  final DateTime? notAfter;

  /// Адреса из subjectAltName (rfc822Name) и emailAddress субъекта.
  final List<String> emails;

  /// Идентификатор ключа (subjectKeyIdentifier), если есть.
  final Uint8List? subjectKeyId;

  final RsaPublicKey? rsa;

  SmimeCert._({
    required this.der,
    required this.issuerDer,
    required this.serialDer,
    required this.serial,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.emails,
    required this.subjectKeyId,
    required this.rsa,
  });

  static SmimeCert parse(Uint8List der) {
    final cert = Der.parse(der);
    final tbs = cert[0];
    final f = tbs.children;
    var i = 0;
    if (f[i].tag == 0xA0) i++; // [0] version
    final serial = f[i++];
    i++; // signature AlgId
    final issuer = f[i++];
    final validity = f[i++];
    final subject = f[i++];
    final spki = f[i++];
    Uint8List? ski;
    final emails = <String>[];
    for (; i < f.length; i++) {
      if (f[i].tag != 0xA3) continue;
      for (final ext in f[i][0].children) {
        final id = ext[0].oid;
        final value = ext.children.last; // OCTET STRING (critical — посередине)
        try {
          if (id == Oids.subjectAltName) {
            for (final gn in Der.parse(value.content).children) {
              if (gn.tag == 0x81) emails.add(ascii.decode(gn.content, allowInvalid: true));
            }
          } else if (id == Oids.subjectKeyId) {
            ski = Der.parse(value.content).content;
          }
        } catch (_) {}
      }
    }
    final subj = _name(subject);
    final e = subj['E'];
    if (e != null && !emails.any((x) => x.toLowerCase() == e.toLowerCase())) emails.add(e);

    RsaPublicKey? rsa;
    try {
      if (spki[0][0].oid == Oids.rsaEncryption) {
        final bits = spki[1].content; // первый байт — неиспользуемые биты
        final key = Der.parse(Uint8List.fromList(bits.sublist(1)));
        rsa = RsaPublicKey(key[0].integer, key[1].integer);
      }
    } catch (_) {}

    return SmimeCert._(
      der: Uint8List.fromList(der),
      issuerDer: Uint8List.fromList(issuer.encoded),
      serialDer: Uint8List.fromList(serial.encoded),
      serial: serial.integer,
      subject: subj,
      issuer: _name(issuer),
      notBefore: validity[0].time,
      notAfter: validity[1].time,
      emails: emails,
      subjectKeyId: ski == null ? null : Uint8List.fromList(ski),
      rsa: rsa,
    );
  }

  static SmimeCert fromPem(String pem) {
    final b64 = pem
        .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return parse(base64.decode(b64));
  }

  static Map<String, String> _name(Der name) {
    const short = {
      Oids.commonName: 'CN',
      '2.5.4.10': 'O',
      '2.5.4.11': 'OU',
      '2.5.4.6': 'C',
      '2.5.4.7': 'L',
      '2.5.4.8': 'ST',
      '2.5.4.4': 'SN',
      '2.5.4.42': 'GN',
      Oids.emailAddress: 'E',
    };
    final out = <String, String>{};
    for (final rdn in name.children) {
      for (final atv in rdn.children) {
        try {
          final k = short[atv[0].oid] ?? atv[0].oid;
          out.putIfAbsent(k, () => atv[1].string);
        } catch (_) {}
      }
    }
    return out;
  }

  String get commonName => subject['CN'] ?? (emails.isNotEmpty ? emails.first : '');
  String get issuerName => issuer['CN'] ?? issuer['O'] ?? '';
  String? get email => emails.isEmpty ? null : emails.first;

  bool isValidAt(DateTime t) =>
      (notBefore == null || !t.isBefore(notBefore!)) && (notAfter == null || !t.isAfter(notAfter!));

  bool hasEmail(String address) => emails.any((e) => e.toLowerCase() == address.trim().toLowerCase());

  /// Отпечаток SHA-1 (как показывает Windows).
  String get thumbprint =>
      hash.sha1.convert(der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  /// Совпадает ли с IssuerAndSerialNumber из CMS.
  bool matchesIssuerSerial(Uint8List issuerDer, BigInt serial) =>
      serial == this.serial && _bytesEqual(issuerDer, this.issuerDer);

  bool matchesKeyId(Uint8List keyId) => subjectKeyId != null && _bytesEqual(keyId, subjectKeyId!);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool bytesEqual(List<int> a, List<int> b) => _bytesEqual(a, b);

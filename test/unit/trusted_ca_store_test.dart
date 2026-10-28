// Разбор сертификатов ЦС (встроенные сертификаты Минцифры) и импорт.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/trusted_ca_store.dart';

void main() {
  test('встроенные сертификаты Минцифры разбираются, отпечатки совпадают', () {
    for (final e in TrustedCaStore.bundledAssets.entries) {
      final c = TrustedCaStore.parse(File(e.key).readAsBytesSync());
      expect(c, isNotNull, reason: e.key);
      expect(c!.fingerprint, e.value, reason: e.key);
      expect(c.commonName, startsWith('Russian Trusted'));
      expect(c.validTo, isNotNull);
    }
  });

  test('DER и PEM дают один и тот же сертификат', () {
    final pem = File('assets/certs/russian_trusted_root_ca.pem').readAsBytesSync();
    final a = TrustedCaStore.parse(pem)!;
    final b = TrustedCaStore.parse(a.der)!;
    expect(b.fingerprint, a.fingerprint);
    expect(TrustedCaStore.parse(TrustedCaStore.toPem(a.der).codeUnits)!.fingerprint, a.fingerprint);
  });

  test('не сертификат — null', () {
    expect(TrustedCaStore.parse('hello'.codeUnits), isNull);
  });
}

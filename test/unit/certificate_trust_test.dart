// Доверие сертификату по отпечатку для одного хоста.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/certificate_pinning_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cert implements X509Certificate {
  final List<int> bytes;
  _Cert(this.bytes);
  @override
  Uint8List get der => Uint8List.fromList(bytes);
  @override
  String get pem => '';
  @override
  Uint8List get sha1 => Uint8List(20);
  @override
  String get subject => '/CN=*.example.com';
  @override
  String get issuer => '/CN=Corp Issuing CA';
  @override
  DateTime get startValidity => DateTime(2026, 1, 1);
  @override
  DateTime get endValidity => DateTime(2027, 1, 1);
}

void main() {
  late CertificatePinningService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    svc = CertificatePinningService(await SharedPreferences.getInstance());
  });

  test('недоверенный сертификат отклоняется и запоминается', () {
    final started = DateTime.now().subtract(const Duration(seconds: 1));
    expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isFalse);
    final r = svc.lastRejected(since: started)!;
    expect(r.host, 'mail.example.com');
    expect(r.issuer, contains('Corp Issuing CA'));
    expect(r.fingerprintHex.split(':').length, 32);
  });

  test('после «доверять» принимается только этот сертификат и только на этом хосте', () async {
    svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443);
    await svc.trustCertificate(svc.lastRejected()!);
    expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isTrue);
    expect(svc.evaluate(_Cert([1, 2, 3]), 'MAIL.example.com', 443), isTrue);
    // Подмена сертификата — отказ.
    expect(svc.evaluate(_Cert([9, 9, 9]), 'mail.example.com', 443), isFalse);
    // Другой хост того же домена — отказ.
    expect(svc.evaluate(_Cert([1, 2, 3]), 'evil.example.com', 443), isFalse);
  });

  test('несовпадение с правилом администратора: доверять не предлагаем, его правило не перекрыть', () async {
    await svc.addRule(PinRule(
      domain: 'example.com',
      sha256Fingerprints: [CertificatePinningService.fingerprintOf(_Cert([7, 7, 7]))],
    ));
    expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isFalse);
    final r = svc.lastRejected(hosts: ['mail.example.com'])!;
    expect(r.pinMismatch, isTrue);
    // Даже если правило пользователя появится, правило домена продолжает действовать.
    await svc.trustCertificate(r);
    expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isFalse);
  });

  test('отказы других хостов не подменяют причину входа', () {
    svc.evaluate(_Cert([1]), 'autodiscover.example.com', 443);
    expect(svc.lastRejected(hosts: ['mail.example.com']), isNull);
  });

  test('сетевой стек Android получает отпечатки доверенного хоста', () async {
    expect(svc.nativeTrustFor('mail.example.com').fingerprints, isEmpty);
    expect(svc.evaluateDer(der: [1, 2, 3], subject: 's', issuer: 'i',
        validFrom: DateTime(2026), validTo: DateTime(2027),
        host: 'mail.example.com', port: 443), isFalse);
    final r = svc.lastRejected(hosts: ['mail.example.com'])!;
    await svc.trustCertificate(r);
    final t = svc.nativeTrustFor('MAIL.example.com');
    expect(t.fingerprints, contains(r.fingerprint));
    expect(t.acceptAny, isFalse);
    expect(svc.nativeTrustFor('evil.example.com').fingerprints, isEmpty);
  });
}

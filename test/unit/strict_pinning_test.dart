// Закрепление сертификата администратора — и при успешной системной
// проверке (решение владельца 08.11.2026, план п. 2). Настоящий TLS:
// локальный сервер с тестовым сертификатом (CN=localhost, до 2126 г.).
// Отметка пользователя «Доверять?» (=хост) — только при ошибке системной
// проверки: сервер сменил сертификат на обычный — вход не закрывается.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/network/certificate_pinning_bridge.dart';
import 'package:ogneliss/core/network/strict_pinning.dart';
import 'package:ogneliss/core/security/certificate_pinning_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cert = '''-----BEGIN CERTIFICATE-----
MIIDJzCCAg+gAwIBAgIUUGSSWJUa2ZQVoMePH/rwFOBpxzQwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTEwODE2MDQ1NloYDzIxMjYx
MDE1MTYwNDU2WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQC3icOypM3TxttVZhrf1XCtHnJsWUrgQa0Th4QSTlXk
t8Cr8KHb5rmYLKJnJShujMd7X9kWWwRefnQdAY5AlRqCaw58CIvLeHj9JxogpfQX
nXdP2/d+pylbc4ciqRLZWbxMJpDQt4C0R1VOIl3S0Mzz01nvkXboIkugQQjyZTnW
NArVmpTUydmgP6p7FVaVTm/ZR0WKqAZD1/jeJPqLu79mZBesYPWx2Zk6ZUsem6S1
9SFoMpP8j2uM17W06UgU+A6Fzi1OV9JJyeKkwPnDslQZEoZb6YhJyRpZVpQ10uSd
TTGalKeZX/SDBKLpXebMVjOBTN9xS1LscUNpt4ri/w4TAgMBAAGjbzBtMB0GA1Ud
DgQWBBT1ToKhHYVjoT1X0HYr8YW8FsYXVTAfBgNVHSMEGDAWgBT1ToKhHYVjoT1X
0HYr8YW8FsYXVTAPBgNVHRMBAf8EBTADAQH/MBoGA1UdEQQTMBGCCWxvY2FsaG9z
dIcEfwAAATANBgkqhkiG9w0BAQsFAAOCAQEAQN/bjXKUerpWKGeD/2GpUahtZL5V
WB/ceA+mGVmv1mA1NX0vHUxNDVBnsAWhpaUGmw5xEw3au0mg7vNpEotfe6FRPcs6
7YQkP2sYWD73vzCiLhBQAvhVu/0+/khuhEW5jNwcZanHw1iF+7D1nlVFVm6rEI7d
6jhwOZSl8c/zRlGrXBO5RWoabqEdem2ErGQ/FpfWK71ZxNokFfHeEFE6unXqWg3A
kvkJK3Xr4raxrjz43zEseaNQ1I9SzmdRgm5o/ZUfxo/hb3/8uj/xeXXfPN2ZIqkp
ulmW/Zmun74VoZQ7xK2z2MeKchNQh/xyksMDgB00cUCNXebzs79QddUvnw==
-----END CERTIFICATE-----''';
const _key = '''-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC3icOypM3TxttV
Zhrf1XCtHnJsWUrgQa0Th4QSTlXkt8Cr8KHb5rmYLKJnJShujMd7X9kWWwRefnQd
AY5AlRqCaw58CIvLeHj9JxogpfQXnXdP2/d+pylbc4ciqRLZWbxMJpDQt4C0R1VO
Il3S0Mzz01nvkXboIkugQQjyZTnWNArVmpTUydmgP6p7FVaVTm/ZR0WKqAZD1/je
JPqLu79mZBesYPWx2Zk6ZUsem6S19SFoMpP8j2uM17W06UgU+A6Fzi1OV9JJyeKk
wPnDslQZEoZb6YhJyRpZVpQ10uSdTTGalKeZX/SDBKLpXebMVjOBTN9xS1LscUNp
t4ri/w4TAgMBAAECggEAGEPh+CXawoN5bwZzSiGFZpXuac26XQDB2aGif+sUZws2
MWU8eP69jdVk2T8r48W//9sxr8dzwex0/Hq+rGIqIZD21sYoeUuhr1JynVtjdJXQ
duHtjDScfqc8+AOjZtH615SHs9h27x65M/3OKreJSTkpnEc+kb0rA3JltOpWJa/9
YSRaW9LLqk38A4mRFBuvXf+BECgTcdruYUbh8LJl+J9sCSjrZPegnfuOpyWhjV8b
v9PzjXSCF7FKl7Psb5B64jhVw6tK7ifLsbMvtFbnr88Yqfc7pXnXeBN47nMLeK3o
mUwPdxyFCO2YmIas9i9XrkZ79d4R2RorPzSUzpbhlQKBgQDfYfEm6IJ9z/D392M6
PgWVF6uR2bwB46DKJ/2f23pCraE2EqIP1POlWv7t/l6nvDDW8aNhhIY48Zp4moWN
UH5Cmr5qXs1pDqFWQ7tvUGEsOQghD4Ywiqo0kguGCh8NGF2ycbhTGPn0aRwzUld3
YYtLD4eqTFOogM6D7LY1+dXfvwKBgQDSVm8iqhsz5PDV5RskjK5Q0Oqw4SbEGdOE
couJrcdavk3jyNfVPyb+zSZv9JNrLnyQk8n/NajNjb19IQ064O5P6IswkMGC2U+G
FfqNdp93XKgY8zjDjZ3yQ5gj52w5nqES5cWpIWx7PC1hY7m8DGY/ztmDbjXxJev7
WhZLSd+mrQKBgF0zsDpbqJZ1vES5o10Zo5qhVaR1BEyFfQDbzqZ0HH7Vkv3MqHGS
mFXVsaf7CeNSUc5c4548fQQlSh4n2rErdIK1rd0T0QCUahxkBkBbeS/KW+nvYD3A
nWNxy/0RHAOKtw1NBWsmcKPZdzqykGvu9v9Ka4BSeFVF6OSCT0QWCXZhAoGBAJ1b
JndzdThkjTwn0x+L05kIQpujRUIt5AzROMz+YgbkGhdQGRAi18SFq7zT5zmnJG9w
8Qxpk2h8IoerI1+qCP9lBESH9w0yEAlLBg+w7+n3Opa31v6NQt2MbhRmPJP6tZwS
o8Y9CBBF29lhJwGk8RXJZPari9Vlvl5jbgxTLutdAoGBAJqFbWQA6TC2U12Yf4az
h499828B1fNVhQWhwa57t48j0/r3caENs8i4DtDY4df6LXM00yQB5wnmEoGVyney
raGowPWMRPocyb22bIAumRAhKm9DxQV1ieGWpK9dI+5le3qLECzX0zQsOpM6RxSv
SltnFBK9TIM+Jx6AntLQ9MG3
-----END PRIVATE KEY-----''';
const _other = '''-----BEGIN CERTIFICATE-----
MIIDAzCCAeugAwIBAgIUD6zcjYkkOCBFaCy9vVIpUM/PER8wDQYJKoZIhvcNAQEL
BQAwEDEOMAwGA1UEAwwFb3RoZXIwIBcNMjYxMTA4MTYwNDU2WhgPMjEyNjEwMTUx
NjA0NTZaMBAxDjAMBgNVBAMMBW90aGVyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
MIIBCgKCAQEA79Rf9fFTK4NohvcL1YbrlTf/Knq5BVAiVOw3o3Em0CXU5mlX1GU1
d6SM7Zs3F+x1TPVKya1nUXQpTCrDOzaHYx62HxQ79VgYBcdli8FMZetJVhazEQzA
nvfIeTYkyRt16KNNKZjEX14sTYI7LN4+MgSVtdoug6YW1Q5WU3SpaVMB85bgjpj3
A4Vh9lHCK9wzQxULIC1xVIUwLaPlJZm43e/tsDywTQ8tqjoGS0ZjsbJ5eNTlB92i
Yfgi2R3WEo1U7btUq0aUW6y0aCxol1jBa+UN54wZSaeSDWJfyaOk/5J97P2b0CZX
LBNPx+UBHqQaArp2Sozd8MSINnCEOS1kwQIDAQABo1MwUTAdBgNVHQ4EFgQURDt0
VIVDHVC11dHebaSQkvRgg+QwHwYDVR0jBBgwFoAURDt0VIVDHVC11dHebaSQkvRg
g+QwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEA2KsyJfVR1drt
90Wvu5aCONnVXIX4JOE5tJsMTJPvxEL9t6EAaxqqHWaeCUqYK0WllH28xP0z8jvS
9PZe8Qq69bICUtFH1AvAZYI0Tcpst3CMo5jsklxMDGiQLBAppuWg71++CQ+j6E1R
ey/kWj5rYDdmrtVtBzLsaT/GU5+RwpbeF2ycTRrsisQ+e0LybHvH1QsWNLp22+59
S53ammKmUZKSoQiv+csyHBpiiPMy9bwQFgrSHDjfe6Uskdrvsy0dDjP5/5RnJbWL
dHBLJL2YZJN0FV2R3d+w21lMAahaXUxK/dTtGDwrK7K7CgrjsaUgofyee4Zg/2St
3uytwgOeIw==
-----END CERTIFICATE-----''';

String _fp(String pem) {
  final b64 = pem.split('\n').where((l) => !l.startsWith('-----')).join();
  return base64.encode(sha256.convert(base64.decode(b64)).bytes);
}

void main() {
  late HttpServer server;
  late CertificatePinningService pins;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pins = CertificatePinningService(await SharedPreferences.getInstance());
    CertificatePinningBridge.instance = pins;
    final ctx = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_cert))
      ..usePrivateKeyBytes(utf8.encode(_key));
    server = await HttpServer.bindSecure('localhost', 0, ctx);
    server.listen((r) => r.response
      ..write('ok')
      ..close());
  });

  tearDown(() async {
    CertificatePinningBridge.instance = null;
    await server.close(force: true);
  });

  /// [trusted] — сертификат сервера в доверенных (системная проверка прошла).
  Future<String> get({required bool trusted}) async {
    final ctx = SecurityContext(withTrustedRoots: false);
    if (trusted) ctx.setTrustedCertificatesBytes(utf8.encode(_cert));
    final hc = HttpClient(context: ctx)..findProxy = (_) => 'DIRECT';
    bool decide(X509Certificate c, String h, int p) => pins.evaluate(c, h, p);
    hc.badCertificateCallback = decide;
    installStrictPinning(hc, context: ctx, onBadCertificate: decide);
    try {
      final req = await hc.getUrl(Uri.parse('https://localhost:${server.port}/'));
      final resp = await req.close();
      return await resp.transform(utf8.decoder).join();
    } finally {
      hc.close(force: true);
    }
  }

  test('без правил — как обычно', () async {
    expect(await get(trusted: true), 'ok');
  });

  test('правило администратора совпало — соединение есть', () async {
    await pins.addRule(PinRule(domain: 'localhost', sha256Fingerprints: [_fp(_cert)]));
    expect(await get(trusted: true), 'ok');
  });

  test('правило администратора не совпало — отказ, хотя системная проверка прошла', () async {
    await pins.addRule(PinRule(domain: 'localhost', sha256Fingerprints: [_fp(_other)]));
    await expectLater(get(trusted: true), throwsA(anything));
    final r = pins.lastRejected();
    expect(r?.host, 'localhost');
    expect(r?.pinMismatch, isTrue, reason: 'доверять такому не предлагается');
  });

  test('отметка пользователя (=хост) другого сертификата — не мешает, если системная проверка прошла', () async {
    await pins.addRule(PinRule(domain: '=localhost', sha256Fingerprints: [_fp(_other)], includeSubdomains: false));
    expect(await get(trusted: true), 'ok');
  });

  test('системная проверка не прошла: отметка пользователя совпала — соединение есть, нет — отказ', () async {
    await pins.addRule(PinRule(domain: '=localhost', sha256Fingerprints: [_fp(_cert)], includeSubdomains: false));
    expect(await get(trusted: false), 'ok');
    await pins.setRules([PinRule(domain: '=localhost', sha256Fingerprints: [_fp(_other)], includeSubdomains: false)]);
    await expectLater(get(trusted: false), throwsA(anything));
  });

  test('строгие отпечатки для Android и iPhone (режим совместимости)', () async {
    expect(pins.nativeTrustFor('localhost').strict, isNull);
    await pins.addRule(PinRule(domain: 'localhost', sha256Fingerprints: [_fp(_cert)]));
    await pins.addRule(PinRule(domain: '=localhost', sha256Fingerprints: [_fp(_other)], includeSubdomains: false));
    expect(pins.nativeTrustFor('localhost').strict, [_fp(_cert)]);
    expect(pins.nativeTrustFor('mail.localhost').strict, [_fp(_cert)], reason: 'поддомены — по правилу домена');
  });
}

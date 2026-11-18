// Сертификаты клиента TLS (2.6.5, mTLS): сервер требует сертификат
// устройства. Настоящий TLS: локальные серверы IMAP (неявный TLS и
// STARTTLS) и HTTPS с проверкой сертификата клиента по тестовому ЦС; файлы
// PKCS#12 — новый (AES), старый (3DES/RC2, как у Windows) и с ключом EC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:mail_engine/mail_engine.dart';
import 'package:ogneliss/core/network/native_android_http_client.dart';
import 'package:ogneliss/core/network/strict_pinning.dart';
import 'package:ogneliss/core/security/client_cert_store.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:ogneliss/services/security/managed_feedback.dart';

/// Сертификат сервера (CN=localhost, до 2126 г.) — как в strict_pinning_test.
const _serverCert = '''-----BEGIN CERTIFICATE-----
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
const _serverKey = '''-----BEGIN PRIVATE KEY-----
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

/// ЦС, выпустивший сертификаты клиента (сервер доверяет только ему).
const _clientCa = '''-----BEGIN CERTIFICATE-----
MIIDFTCCAf2gAwIBAgIUb3Um+hJ6RISNVR7aUNdo/yZTyEQwDQYJKoZIhvcNAQEL
BQAwGTEXMBUGA1UEAwwOVGVzdCBDbGllbnQgQ0EwIBcNMjYxMTE3MjMwODUwWhgP
MjEyNjEwMjQyMzA4NTBaMBkxFzAVBgNVBAMMDlRlc3QgQ2xpZW50IENBMIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApGkcUjW/SmBczEvKKWtWG4hPbuu7
nrc2oEDeQpcHkdkf+B5BuGuReTOYfuhTdhMjOp3vWgaX5KuEnr18TOzBDNbM3RI9
dN1xuTVBo7CCKNvTIyHZZOkAX1gWY8hfBsKLIRh8DIls92ZTPF9AAapvzGlYHmVY
5F0JaTNTT2PNA/VxUXkp9mE0tLqVUzYZ/mlj8E67u+vL0TlW2Iw8RLCKN9qcWhZk
jf9GVsXyRux2XC2FjJKPZW61sc/JsU2KV2IKzEDYWzA1x+BnFNX7rP+5YKh5NS6s
YVbz4VS7W85aZvmFf5aNmp2B2UUTPH5MPWWP9fblfL/H+vIZNLw2RmBF1wIDAQAB
o1MwUTAdBgNVHQ4EFgQU5pF3HLPxuybLEGCYOwFS+3aSltEwHwYDVR0jBBgwFoAU
5pF3HLPxuybLEGCYOwFS+3aSltEwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0B
AQsFAAOCAQEAMhBAEMc8IWmo1RDwmzcxC3nExfRukcK8+/hLUsRwt/vLrdVuin7D
1LgRIhQJHJHqT2nHAT/d5320JFYHX/9e+eTS/vftg8wr98CrVs6TQYMgndV8He3k
kXwXy+4RLLgqlAbYud58Orm81nr+Er2NDHYtn3CKe/2aQ7xrhF+LKSHt+eNUDOqX
WspKDnoBOUly/+TIo+Ruuu5LiN+ds94VGcBgW9kEPMXziL3godt3/+1fsue/YO3d
LpUKZg/kyypewB2aR8Rn5912qEeCu3Si1VggPQ8ynxI3m/326ljewildC6P8b/Zh
b2avIfPDHy+OO90s6XuU3q8uqLlDR42GZA==
-----END CERTIFICATE-----''';

/// «Ivanov Ivan» (RSA): OpenSSL 3 по умолчанию (PBES2, AES-256).
const _rsaModern = '''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
hgQIGphuZEy75ogCAggA''';

/// Тот же сертификат в старом формате (3DES + RC2-40, как экспорт Windows).
const _rsaLegacy = '''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
qRNKCpNUxxk3BAgHVpDZnDprIwICCAA=''';

/// «EC User» (ключ P-256).
const _ec = '''MIIEfAIBAzCCBDIGCSqGSIb3DQEHAaCCBCMEggQfMIIEGzCCAtIGCSqGSIb3DQEHBqCCAsMwggK/AgEAMIICuAYJKoZIhvcNAQcB
MFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAjRa69KwGxM9AICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEH6D
w46TwYI+1e+rq1fnW5GAggJQEi0CZXDZirXyW+Wr5h2gKh7tczK+EefLR968HPZF7Xn52myHX0+inPVjIgFj/ezh1fYWwT0wwVeZ
r1OZsAclzxW4a9S1U5EQMJ13ywxGI5hn5GPsEi115IdnPF/pgN9oM/YCqLnM5crFRwyTdusIMP24U4H7I+6RGrxe5gVSlxYBB/z7
S+ucsGYh6492xxcwVcwCuzXuTogooeEtio76yDFxs6E3buUAuOccgf6DXg7sV/+7qCFEJowuapU5sL1qxdtoqsnfErWppWa6gZyw
wU9L3w5ubncfWoQJNgq/tHvPCSGWDS9abTuJRD6iK4Yl5AYiG38WBBCcn4oiMmfoIF8xjeSYrl7S6QqFxfcFD96Ut8V40jjRkvXW
U0eDbjX5a/hM2MqAsQ5qQkaJfsCRnYEaNS2O209svnI35JpWM+7XWr/WU2MbTKU03CB6G503yqtdhyza8D5LTgLrJaf7Xn9h3izK
ZJAq7oOUOn82U6aPLRL66th7DTC+8jczgqm+lfJdgJyLD0FmqQ1yBNCMJAKE4HfixZcgfdm+RA9f1HCGEc1OEGP2b7ueM50NHrDR
2ttLiAZKRzyMmSFe6GZHy9gDsJ2ske02uSQLPa6keCj2erEAObs6RuT5lNYXw2+s3hKXckBJG49HcLWcYfiLaUh09EiTb6mVIL21
LOIvzGuaZws0jSP1/82S+0bEZRBlRiJHlsY6hsblXcX2xLBVh/akB3yAWvWJ6HqtngiDtn93WB6C9sRePhDKG8K9C54l0X1dgpva
FInUU7oLWZ5mKzCCAUEGCSqGSIb3DQEHAaCCATIEggEuMIIBKjCCASYGCyqGSIb3DQEMCgECoIHvMIHsMFcGCSqGSIb3DQEFDTBK
MCkGCSqGSIb3DQEFDDAcBAgev+xaDbUNMAICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEAOItDQJ6eCP5RHlrnaCCr0E
gZDxRwIFFlG1TpzBV+vatGuuwBxXlwyrBX2Q+L5OloabHDyVsUDGZJylxzdh/6yWEAyuCQQksHOwHAixglNL2kxZq53bcYzk+JL8
dmCTB2T2AjAtgc3GKEIFwLvGoiuVIgRMZ+D/oLTOByrTQ2xLI5T2idHM+edmjvehkIEd9qeIyp9gF4kNiDyyPCKPbANVZsYxJTAj
BgkqhkiG9w0BCRUxFgQUmoI6g1gkOqK17K43bo4Tsc6+zIgwQTAxMA0GCWCGSAFlAwQCAQUABCBvETu/VqOQsih1Jvz7d4rVtLrz
iibf454gY+TTW1v10wQIqrT/kN+pC+cCAggA''';

/// Самоподписанный «Stranger» — сервер его не примет.
const _other = '''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''';

Uint8List _p12(String b64) => base64.decode(b64.replaceAll(RegExp(r'\s+'), ''));

/// Хранилище в памяти вместо Keychain / Keystore.
class _MemStorage extends SecureStorageService {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(_serverCert))
  ..usePrivateKeyBytes(utf8.encode(_serverKey))
  ..setTrustedCertificatesBytes(utf8.encode(_clientCa))
  ..setClientAuthoritiesBytes(utf8.encode(_clientCa));

/// IMAP-сервер, требующий сертификат клиента: неявный TLS или STARTTLS.
class _Imap {
  _Imap._(this.port, this._close);
  final int port;
  final Future<void> Function() _close;
  final clients = <String>[];
  Future<void> close() => _close();

  static Future<_Imap> start({required bool tls}) async {
    late _Imap me;
    if (tls) {
      final s = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, _serverContext(),
          requestClientCertificate: true, requireClientCertificate: true);
      me = _Imap._(s.port, s.close);
      s.listen((c) => me._session(c, secure: true), onError: (_) {});
    } else {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      me = _Imap._(s.port, s.close);
      s.listen((c) => me._session(c, secure: false));
    }
    return me;
  }

  void _session(Socket c, {required bool secure}) {
    if (c is SecureSocket) clients.add(c.peerCertificate?.subject ?? '—');
    c.write('* OK [CAPABILITY IMAP4rev1${secure ? '' : ' STARTTLS'}] ready\r\n');
    late StreamSubscription<String> sub;
    sub = c.cast<List<int>>().transform(latin1.decoder).transform(const LineSplitter()).listen((line) async {
      final sp = line.indexOf(' ');
      final tag = line.substring(0, sp);
      final verb = line.substring(sp + 1).split(' ').first.toUpperCase();
      switch (verb) {
        case 'STARTTLS':
          sub.pause();
          c.write('$tag OK Begin TLS\r\n');
          try {
            final s = await SecureSocket.secureServer(c, _serverContext(),
                requestClientCertificate: true, requireClientCertificate: true);
            unawaited(sub.cancel());
            clients.add(s.peerCertificate?.subject ?? '—');
            _session2(s);
          } catch (_) {
            c.destroy();
          }
        case 'CAPABILITY':
          c.write('* CAPABILITY IMAP4rev1\r\n$tag OK done\r\n');
        case 'LOGIN':
          c.write('$tag OK LOGIN done\r\n');
        case 'LOGOUT':
          c.write('* BYE\r\n$tag OK bye\r\n');
          await c.close();
        default:
          c.write('$tag BAD unknown\r\n');
      }
    }, onError: (_) {});
  }

  void _session2(SecureSocket c) {
    c.cast<List<int>>().transform(latin1.decoder).transform(const LineSplitter()).listen((line) async {
      final sp = line.indexOf(' ');
      final tag = line.substring(0, sp);
      final verb = line.substring(sp + 1).split(' ').first.toUpperCase();
      if (verb == 'LOGIN') c.write('$tag OK LOGIN done\r\n');
      if (verb == 'CAPABILITY') c.write('* CAPABILITY IMAP4rev1\r\n$tag OK done\r\n');
      if (verb == 'LOGOUT') {
        c.write('* BYE\r\n$tag OK bye\r\n');
        await c.close();
      }
    }, onError: (_) {});
  }
}

void main() {
  late ClientCertStore store;
  late _MemStorage storage;

  setUp(() async {
    storage = _MemStorage();
    store = await ClientCertStore.init(storage, policy: ManagedPolicy.none);
  });

  tearDown(ClientCertStore.debugReset);

  group('файл .p12/.pfx', () {
    test('новый и старый формат, ключ EC: владелец, срок, издатель', () {
      for (final f in [_rsaModern, _rsaLegacy]) {
        final i = ClientCertStore.inspect(_p12(f), 'secret', domains: ['corp.test']);
        expect(i.name, 'Ivanov Ivan');
        expect(i.issuer, 'Test Client CA');
        expect(i.validTo!.year, greaterThan(2100));
        expect(i.expired, isFalse);
      }
      expect(ClientCertStore.inspect(_p12(_ec), 'secret').name, 'EC User');
    });

    test('неверный пароль и не тот файл', () {
      expect(() => ClientCertStore.inspect(_p12(_rsaModern), 'wrong'),
          throwsA(isA<ClientCertException>().having((e) => e.code, 'code', 'password')));
      expect(() => ClientCertStore.inspect(utf8.encode(_clientCa), ''),
          throwsA(isA<ClientCertException>().having((e) => e.code, 'code', 'format')));
    });

    test('домены: разбор, совпадение, самый точный', () async {
      expect(ClientCertStore.parseDomains('*.Corp.Test; https://mail.corp.test/EWS/Exchange.asmx, corp.test.'),
          ['corp.test', 'mail.corp.test']);
      expect(ClientCertStore.matches('mail.corp.test', 'corp.test'), isTrue);
      expect(ClientCertStore.matches('corp.test', 'corp.test'), isTrue);
      expect(ClientCertStore.matches('notcorp.test', 'corp.test'), isFalse);
      await store.importBytes(_p12(_rsaModern), 'secret', ['corp.test']);
      await store.importBytes(_p12(_ec), 'secret', ['owa.corp.test']);
      expect(store.infoFor('mail.corp.test')?.name, 'Ivanov Ivan');
      expect(store.infoFor('owa.corp.test')?.name, 'EC User', reason: 'точный домен важнее');
      expect(store.infoFor('imap.yandex.ru'), isNull, reason: 'чужим серверам — не предъявляется');
      expect(store.contextFor('imap.yandex.ru'), isNull);
      expect(store.contextFor('mail.corp.test'), isNotNull);
    });

    test('хранится в защищённом хранилище; после перезапуска — те же; удаление', () async {
      final i = await store.importBytes(_p12(_rsaLegacy), 'secret', ['corp.test']);
      expect(storage.map.values.join(), isNot(contains('Ivanov Ivan@')));
      final again = await ClientCertStore.init(storage, policy: ManagedPolicy.none);
      expect(again.items.single.id, i.id);
      expect(again.contextFor('corp.test'), isNotNull);
      await again.setDomains(i.id, ['mail.corp.test']);
      expect(again.infoFor('corp.test'), isNull);
      await again.remove(i.id);
      expect(again.items, isEmpty);
      expect((await ClientCertStore.init(storage, policy: ManagedPolicy.none)).items, isEmpty);
    });
  });

  group('MDM', () {
    test('сертификат организации: в копии политики — только отпечаток; фон берёт файл из хранилища', () async {
      final raw = {
        'account_email': 'ivanov@corp.test',
        'account_server': 'https://mail.corp.test/EWS/Exchange.asmx',
        'client_cert_pkcs12': _rsaModern,
        'client_cert_password': 'secret',
      };
      final p = ManagedPolicy.fromMap(raw);
      expect(p.hasClientCert, isTrue);
      final json = jsonEncode(p.toJson());
      expect(json, isNot(contains('secret')));
      expect(json, isNot(contains(_rsaModern.substring(0, 40))));
      await store.applyPolicy(p);
      final m = store.items.single;
      expect(m.managed, isTrue);
      expect(m.domains, ['corp.test', 'mail.corp.test']);
      // Фоновый изолят: политика из prefs (без файла) — сертификат тот же.
      final bg = await ClientCertStore.init(storage, policy: ManagedPolicy.fromMap(p.toJson()));
      expect(bg.items.single.id, m.id);
      expect(bg.contextFor('mail.corp.test'), isNotNull);
      // Политику сняли — сертификата нет.
      await bg.applyPolicy(ManagedPolicy.none);
      expect(bg.items, isEmpty);
      expect(storage.map.containsKey('client_cert_mdm_v1'), isFalse);
    });

    test('свои домены и отчёт консоли', () {
      List<FeedbackState> report(Map<Object?, Object?> raw) =>
          managedFeedback(raw, ManagedPolicy.fromMap(raw), pinSet: false, accountAdded: false);
      FeedbackState? of(List<FeedbackState> l) => l.where((e) => e.key == 'client_cert_pkcs12').firstOrNull;
      final ok = report({'client_cert_pkcs12': _ec, 'client_cert_password': 'secret', 'client_cert_domains': 'corp.test'});
      expect(of(ok)!.severity, FeedbackSeverity.info);
      expect(of(ok)!.message, contains('EC User'));
      expect(ok.map((e) => '${e.message} ${e.data}').join(), isNot(contains('secret')));
      expect(of(report({'client_cert_pkcs12': _ec, 'client_cert_password': 'x'}))!.message, contains('Wrong'));
      expect(of(report({'client_cert_pkcs12': '%%%', 'client_cert_password': 'x'}))!.severity, FeedbackSeverity.error);
      expect(of(report({'client_cert_password': 'x'}))!.severity, FeedbackSeverity.error);
    });
  });

  group('соединения (mTLS)', () {
    test('IMAP с неявным TLS: сертификат клиента предъявлен; без него — отказ сервера', () async {
      final imap = await _Imap.start(tls: true);
      await store.importBytes(_p12(_rsaModern), 'secret', ['localhost']);
      final client = TolerantImapClient(onBadCertificate: (_) => true);
      await client.connectToServer('localhost', imap.port, isSecure: true);
      await client.login('u', 'p');
      expect(imap.clients.single, contains('Ivanov Ivan'));
      await client.logout();

      // Сертификат не для этого сервера — не предъявляется, сервер не пускает.
      await store.setDomains(store.items.single.id, ['corp.test']);
      final bare = TolerantImapClient(onBadCertificate: (_) => true);
      await expectLater(
          bare.connectToServer('localhost', imap.port, isSecure: true).timeout(const Duration(seconds: 5)),
          throwsA(anything));
      await imap.close();
    });

    test('IMAP STARTTLS напрямую: сертификат — при переходе на TLS', () async {
      final imap = await _Imap.start(tls: false);
      await store.importBytes(_p12(_ec), 'secret', ['localhost']);
      final client = TolerantImapClient(onBadCertificate: (_) => true);
      await client.connectToServer('localhost', imap.port, isSecure: false);
      await client.startTls();
      await client.login('u', 'p');
      expect(imap.clients.single, contains('EC User'));
      await client.logout();
      await imap.close();
    });

    test('чужой сертификат — сервер отказывает', () async {
      final imap = await _Imap.start(tls: true);
      await store.importBytes(_p12(_other), 'secret', ['localhost']);
      final client = TolerantImapClient(onBadCertificate: (_) => true);
      await expectLater(
          client.connectToServer('localhost', imap.port, isSecure: true).timeout(const Duration(seconds: 5)),
          throwsA(anything));
      await imap.close();
    });

    test('HTTPS (Exchange, DAV): фабрика соединений приложения', () async {
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, _serverContext(),
          requestClientCertificate: true);
      server.listen((r) => r.response
        ..write('cert=${r.certificate?.subject ?? '-'}')
        ..close());
      Future<String> get() async {
        final hc = HttpClient()..findProxy = (_) => 'DIRECT';
        installStrictPinning(hc, onBadCertificate: (_, __, ___) => true);
        try {
          final resp = await (await hc.getUrl(Uri.parse('https://localhost:${server.port}/EWS'))).close();
          return await resp.transform(utf8.decoder).join();
        } finally {
          hc.close(force: true);
        }
      }

      expect(await get(), 'cert=-', reason: 'без сертификата для узла — как раньше');
      await store.importBytes(_p12(_rsaLegacy), 'secret', ['localhost']);
      expect(await get(), contains('Ivanov Ivan'));
      await server.close(force: true);
    });
  });

  group('сертификат устройства (Android KeyChain)', () {
    test('псевдоним по домену; TLS Dart его не берёт; точный домен важнее', () async {
      await store.importBytes(_p12(_rsaModern), 'secret', ['corp.test']);
      await store.importDevice('corp-cba', name: 'Ivanov (device)', domains: ['eas.corp.test']);
      expect(store.aliasFor('eas.corp.test'), 'corp-cba');
      expect(store.contextFor('eas.corp.test'), isNull, reason: 'ключ в системе — не в TLS Dart');
      expect(store.aliasFor('imap.corp.test'), isNull);
      expect(store.contextFor('imap.corp.test'), isNotNull, reason: 'остальное — файлом');
      expect(store.hasDeviceCerts, isTrue);
      final again = await ClientCertStore.init(storage, policy: ManagedPolicy.none);
      expect(again.aliasFor('eas.corp.test'), 'corp-cba');
      expect(again.items.firstWhere((c) => c.isDevice).name, 'Ivanov (device)');
    });

    test('MDM client_cert_alias: домены ящика организации', () async {
      final p = ManagedPolicy.fromMap(const {
        'account_email': 'ivanov@corp.test',
        'client_cert_alias': 'intune-pkcs',
      });
      expect(p.hasClientCert, isTrue);
      expect(ManagedPolicy.fromMap(p.toJson()).clientCertAlias, 'intune-pkcs');
      await store.applyPolicy(p);
      expect(store.aliasFor('mail.corp.test'), 'intune-pkcs');
      expect(store.items.single.managed, isTrue);
      await store.applyPolicy(ManagedPolicy.none);
      expect(store.items, isEmpty);
    });

    test('запросы Exchange: к серверу сертификата — через Android с псевдонимом, остальные — как раньше', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <Map<Object?, Object?>>[];
      const ch = MethodChannel('ogneliss/native_http');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
        calls.add(c.arguments as Map<Object?, Object?>);
        return {'status': 200, 'reason': 'OK', 'headers': <String, String>{}, 'body': Uint8List.fromList(utf8.encode('native'))};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));
      await store.importDevice('corp-cba', name: 'Ivanov', domains: ['corp.test']);
      final client = NativeAndroidHttpClient(MockClient((_) async => http.Response('dart', 200)), nativeAll: false);
      expect((await client.get(Uri.parse('https://eas.corp.test/Microsoft-Server-ActiveSync'))).body, 'native');
      expect(calls.single['clientAlias'], 'corp-cba');
      expect((await client.get(Uri.parse('https://outlook.office365.com/EWS'))).body, 'dart');
      expect(calls, hasLength(1));
    });
  });
}

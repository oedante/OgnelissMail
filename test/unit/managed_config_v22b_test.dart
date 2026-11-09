// Ключи MDM 2.2.0, вторая партия (план 08.11.2026 п. 1, запросы ИТ-служб):
// закреплённый ящик, протокол Exchange, только TLS, ЦС организации, запрет
// доверять сертификатам самому, перенос контактов и встреч в устройство.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/errors/app_exceptions.dart';
import 'package:ogneliss/core/security/certificate_pinning_service.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/core/security/trusted_ca_store.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/mail/oauth/oauth_proxy_client.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_imap_server.dart';

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
  String get subject => '/CN=mail.example.com';
  @override
  String get issuer => '/CN=Self';
  @override
  DateTime get startValidity => DateTime(2026, 1, 1);
  @override
  DateTime get endValidity => DateTime(2027, 1, 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ManagedPolicy.current = ManagedPolicy.none);

  test('разбор: Android (Bundle) и iOS (строки plist); без ключей — как без MDM', () {
    final a = ManagedPolicy.fromMap(const {
      'account_email': 'Ivanov@Romashka.ru',
      'account_locked': true,
      'account_transport': 'eas',
      'require_tls': true,
      'trusted_ca_pem': '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----',
      'allow_user_cert_trust': false,
      'block_device_contacts': true,
      'block_device_calendar': true,
    });
    expect(a.accountLocked, isTrue);
    expect(a.accountTransport, 'eas');
    expect(a.requireTls, isTrue);
    expect(a.trustedCaPem, contains('BEGIN CERTIFICATE'));
    expect(a.allowUserCertTrust, isFalse);
    expect(a.blockDeviceContacts, isTrue);
    expect(a.blockDeviceCalendar, isTrue);

    expect(ManagedPolicy.fromMap(const {'account_transport': 'ActiveSync'}).accountTransport, 'eas');
    expect(ManagedPolicy.fromMap(const {'account_transport': 'EWS'}).accountTransport, 'ews');
    expect(ManagedPolicy.fromMap(const {'account_transport': 'auto'}).accountTransport, isNull);
    expect(ManagedPolicy.fromMap(const {'allow_user_cert_trust': 'no', 'require_tls': 'yes'}).allowUserCertTrust,
        isFalse);

    final none = ManagedPolicy.fromMap(const {'org_name': 'Ромашка'});
    expect(none.accountLocked, isFalse);
    expect(none.accountTransport, isNull);
    expect(none.requireTls, isFalse);
    expect(none.trustedCaPem, isNull);
    expect(none.allowUserCertTrust, isTrue, reason: 'нет ключа — можно, как без MDM');
    expect(none.blockDeviceContacts, isFalse);
    expect(none.blockDeviceCalendar, isFalse);
  });

  test('закреплён только ящик из account_email, без учёта регистра', () {
    final p = ManagedPolicy.fromMap(const {'account_email': 'Ivanov@Romashka.ru', 'account_locked': true});
    expect(p.lockedAccount('ivanov@romashka.ru'), isTrue);
    expect(p.lockedAccount(' IVANOV@ROMASHKA.RU '), isTrue);
    expect(p.lockedAccount('me@gmail.com'), isFalse);
    expect(ManagedPolicy.fromMap(const {'account_email': 'ivanov@romashka.ru'}).lockedAccount('ivanov@romashka.ru'),
        isFalse, reason: 'без account_locked');
    expect(ManagedPolicy.fromMap(const {'account_locked': true}).lockedAccount('ivanov@romashka.ru'), isFalse,
        reason: 'без account_email закреплять нечего');
  });

  test('запреты действий: доверие сертификатам, контакты и календарь устройства', () {
    ManagedPolicy.current = ManagedPolicy.fromMap(const {
      'allow_user_cert_trust': false,
      'block_device_contacts': true,
      'block_device_calendar': true,
    });
    expect(ManagedPolicy.deny(ManagedRule.certTrust), isTrue);
    expect(ManagedPolicy.deny(ManagedRule.deviceContacts), isTrue);
    expect(ManagedPolicy.deny(ManagedRule.deviceCalendar), isTrue);
    expect(ManagedPolicy.deny(ManagedRule.share), isFalse);
    ManagedPolicy.current = ManagedPolicy.none;
    expect(ManagedPolicy.deny(ManagedRule.certTrust), isFalse);
  });

  test('копия политики для фона — с новыми ключами', () {
    const p = ManagedPolicy(
      accountEmail: 'ivanov@romashka.ru',
      accountLocked: true,
      accountTransport: 'ews',
      requireTls: true,
      trustedCaPem: '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----',
      allowUserCertTrust: false,
      blockDeviceContacts: true,
      blockDeviceCalendar: true,
    );
    expect(ManagedPolicy.fromMap(p.toJson()), p);
  });

  test('ЦС организации: несколько блоков PEM, мусор пропускается', () {
    final root = File('assets/certs/russian_trusted_root_ca.pem').readAsStringSync();
    final sub = File('assets/certs/russian_trusted_sub_ca.pem').readAsStringSync();
    final list = TrustedCaStore.parsePemList('$root\nкакой-то текст\n$sub\n'
        '-----BEGIN CERTIFICATE-----\nне base64\n-----END CERTIFICATE-----');
    expect(list, hasLength(2));
    expect(list.first.fingerprint, TrustedCaStore.bundledAssets['assets/certs/russian_trusted_root_ca.pem']);
    expect(TrustedCaStore.parsePemList(null), isEmpty);
    expect(TrustedCaStore.parsePemList('  '), isEmpty);
  });

  test('внешние службы запрещены — к серверу входа Ogneliss не обращаемся', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final proxy = OAuthProxyClient(SecureStorageService());
    ManagedPolicy.current = const ManagedPolicy(blockExternalServices: true, blockWeather: true);
    expect(OAuthProxyClient.blockedByPolicy, isTrue);
    if (proxy.isEnabled) {
      // Сборка с сервером входа: обновление входа — без запроса, «войти снова».
      await expectLater(
          proxy.refreshWithBlob('blob', 'yandex'),
          throwsA(isA<OAuthRefreshFailure>().having((e) => e.needsSignIn, 'needsSignIn', isTrue)));
      await expectLater(proxy.refreshWithBlob('blob', 'exchange', resource: 'graph'),
          throwsA(isA<OAuthRefreshFailure>().having((e) => e.needsSignIn, 'needsSignIn', isFalse)));
    }
    expect(await proxy.getAccessToken('a1'), isNull);
    ManagedPolicy.current = ManagedPolicy.none;
    expect(OAuthProxyClient.blockedByPolicy, isFalse);
    expect(const LoginServerBlockedException().messageKey, 'mdmLoginServerBlocked');
  });

  group('запрет доверять самому: прежние решения пользователя не действуют', () {
    late CertificatePinningService svc;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      svc = CertificatePinningService(await SharedPreferences.getInstance());
    });

    test('сертификат, принятый в «Доверять?», и доверенный домен', () async {
      svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443);
      await svc.trustCertificate(svc.lastRejected()!);
      await svc.ensureTrustedCaDomain('corp.example');
      expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isTrue);
      expect(svc.evaluate(_Cert([5]), 'mail.corp.example', 443), isTrue);

      ManagedPolicy.current = const ManagedPolicy(allowUserCertTrust: false);
      expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isFalse);
      expect(svc.evaluate(_Cert([5]), 'mail.corp.example', 443), isFalse);
      final native = svc.nativeTrustFor('mail.example.com');
      expect(native.fingerprints, isEmpty);
      expect(native.acceptAny, isFalse);
      expect(svc.nativeTrustFor('mail.corp.example').acceptAny, isFalse);

      // Новое «Доверять?» — тоже нет.
      svc.evaluate(_Cert([7]), 'other.example.com', 443);
      await svc.trustCertificate(svc.lastRejected(hosts: ['other.example.com'])!);
      ManagedPolicy.current = ManagedPolicy.none;
      expect(svc.evaluate(_Cert([7]), 'other.example.com', 443), isFalse, reason: 'правило не сохранено');
      // Запрет снят — прежние решения снова действуют.
      expect(svc.evaluate(_Cert([1, 2, 3]), 'mail.example.com', 443), isTrue);
    });

    test('закрепление администратора действует как обычно', () async {
      await svc.addRule(PinRule(
        domain: 'example.com',
        sha256Fingerprints: [CertificatePinningService.fingerprintOf(_Cert([4, 4]))],
      ));
      ManagedPolicy.current = const ManagedPolicy(allowUserCertTrust: false);
      expect(svc.evaluate(_Cert([4, 4]), 'mail.example.com', 443), isTrue);
      expect(svc.evaluate(_Cert([1]), 'mail.example.com', 443), isFalse);
      expect(svc.strictPinsFor('mail.example.com'), isNotNull);
    });
  });

  group('только шифрованные соединения', () {
    late FakeImapServer srv;
    late ImapService imap;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({'pwd_a1': 'secret'});
      imap = ImapService(SecureStorageService());
      srv = FakeImapServer(caps: 'IMAP4rev1');
      srv.box('INBOX').add('Письмо');
      await srv.start();
    });

    tearDown(() async {
      imap.dispose();
      await srv.close();
    });

    AccountModel account() => AccountModel(
          id: 'a1',
          type: AccountType.imap,
          email: 'me@example.com',
          displayName: 'Me',
          username: 'me@example.com',
          imapServer: '127.0.0.1',
          imapPort: srv.port,
          imapEncryption: EncryptionType.none,
          createdAt: DateTime(2026),
        );

    test('IMAP без SSL/STARTTLS не подключается — и пароль не уходит', () async {
      ManagedPolicy.current = const ManagedPolicy(requireTls: true);
      await expectLater(imap.syncFolderDelta(account(), folderId: 'INBOX', backfill: 0),
          throwsA(isA<TlsRequiredException>()));
      expect(srv.commands.where((c) => c.startsWith('LOGIN')), isEmpty);
    });

    test('без политики — как раньше', () async {
      final d = await imap.syncFolderDelta(account(), folderId: 'INBOX', backfill: 0);
      expect(d.reset, isTrue);
    });
  });
}

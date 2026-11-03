// Управление со стороны организации через MDM (1.10.5, просьба владельца
// 03.11.2026): разбор управляемых настроек (Android Bundle и iOS plist дают
// разные типы), домены ящиков, копия политики для фона, запреты действий.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/app_share.dart';
import 'package:ogneliss/core/platform/file_opener.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    ManagedPolicy.current = ManagedPolicy.none;
    ManagedConfigService.debugSupported = null;
  });

  group('разбор', () {
    test('пусто — не управляется', () {
      expect(ManagedPolicy.fromMap(null).isManaged, isFalse);
      expect(ManagedPolicy.fromMap(const {}).isManaged, isFalse);
      expect(ManagedPolicy.fromMap(const {'org_name': '  '}).isManaged, isFalse);
    });

    test('Android: типы Bundle; iOS: строки и числа plist', () {
      final a = ManagedPolicy.fromMap(const {
        'org_name': 'ООО Ромашка',
        'require_app_lock': true,
        'min_pin_length': 6,
        'block_share': true,
        'allowed_domains': 'romashka.ru, @mail.romashka.ru;example.org',
        'account_email': ' I.Petrov@Romashka.ru ',
        'account_protocol': 'eas',
      });
      expect(a.isManaged, isTrue);
      expect(a.orgName, 'ООО Ромашка');
      expect(a.requireAppLock, isTrue);
      expect(a.minPinLength, 6);
      expect(a.blockShare, isTrue);
      expect(a.blockCopy, isFalse);
      expect(a.allowedDomains, ['romashka.ru', 'mail.romashka.ru', 'example.org']);
      expect(a.accountEmail, 'i.petrov@romashka.ru');
      expect(a.accountProtocol, 'exchange', reason: 'eas и ews — Exchange: транспорт выбирает приложение');
      expect(a.hasAccount, isTrue);

      final i = ManagedPolicy.fromMap(const {
        'require_app_lock': 'YES',
        'block_copy': 1,
        'hide_notification_content': 'true',
        'min_pin_length': '9',
        'allowed_domains': ['romashka.ru', 'не домен'],
        'account_protocol': 'IMAP',
        'imap_port': '993',
      });
      expect(i.requireAppLock, isTrue);
      expect(i.blockCopy, isTrue);
      expect(i.hideNotificationContent, isTrue);
      expect(i.minPinLength, 6, reason: 'PIN — от 4 до 6 цифр');
      expect(i.allowedDomains, ['romashka.ru']);
      expect(i.accountProtocol, 'imap');
      expect(i.imapPort, 993);
      expect(ManagedPolicy.fromMap(const {'account_protocol': 'pop3'}).accountProtocol, isNull);
      expect(ManagedPolicy.fromMap(const {'block_share': 'нет'}).blockShare, isFalse);
    });

    test('домены ящиков: поддомены подходят, другие — нет; пусто — любые', () {
      final p = ManagedPolicy.fromMap(const {'allowed_domains': 'romashka.ru'});
      expect(p.allowsAccount('i.petrov@romashka.ru'), isTrue);
      expect(p.allowsAccount('i.petrov@MAIL.Romashka.ru'), isTrue);
      expect(p.allowsAccount('me@gmail.com'), isFalse);
      expect(p.allowsAccount('me@notromashka.ru'), isFalse);
      expect(p.allowsAccount('без адреса'), isFalse);
      expect(ManagedPolicy.none.allowsAccount('me@gmail.com'), isTrue);
    });

    test('копия в prefs — та же политика (фон и уведомления)', () async {
      final p = ManagedPolicy.fromMap(const {
        'org_name': 'Ромашка',
        'allowed_domains': 'romashka.ru',
        'hide_notification_content': true,
        'min_pin_length': 5,
        'smtp_port': 465,
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(ManagedPolicy.fromPrefs(prefs), ManagedPolicy.none);
      await prefs.setString(ManagedPolicy.prefKey, '{"broken"');
      expect(ManagedPolicy.fromPrefs(prefs), ManagedPolicy.none);
      ManagedConfigService.debugSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('ogneliss/mdm'), (call) async => call.method == 'get' ? p.toJson() : null);
      final loaded = await ManagedConfigService(prefs).load();
      expect(loaded, p);
      await Future<void>.delayed(Duration.zero);
      expect(ManagedPolicy.fromPrefs(prefs), p);
      // Политику сняли в MDM — копия очищается.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('ogneliss/mdm'), (call) async => <String, Object?>{});
      expect((await ManagedConfigService(prefs).load()).isManaged, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(ManagedPolicy.prefKey), isNull);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ogneliss/mdm'), null);
    });

    test('компьютер — MDM нет, политика пустая', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ManagedConfigService.debugSupported = false;
      expect((await ManagedConfigService(prefs).load()).isManaged, isFalse);
    });
  });

  group('запреты действий', () {
    test('«Поделиться» и открыть в другом приложении — запрещено политикой', () async {
      ManagedPolicy.current = ManagedPolicy.fromMap(const {'block_share': true, 'block_open_in': true});
      expect(ManagedPolicy.deny(ManagedRule.share), isTrue);
      expect(ManagedPolicy.deny(ManagedRule.copy), isFalse);
      expect(await appShare(ShareParams(text: 'письмо')), ShareResult.unavailable);
      expect(await FileOpener.open('/tmp/нет.pdf'), OpenFileOutcome.blocked);
    });

    test('без политики — ничего не запрещено', () {
      ManagedPolicy.current = ManagedPolicy.none;
      for (final r in ManagedRule.values) {
        expect(ManagedPolicy.deny(r), isFalse);
      }
    });
  });
}

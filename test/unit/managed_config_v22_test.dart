// Ключи MDM 2.2.0 (план 08.11.2026 п. 1, запросы ИТ-служб): срок почты на
// устройстве, запрет вложений, блокировка после бездействия, вход по
// биометрии, внешние службы.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ManagedPolicy.current = ManagedPolicy.none);

  test('разбор: Android (Bundle) и iOS (строки plist); без ключей — как без MDM', () {
    final a = ManagedPolicy.fromMap(const {
      'max_sync_days': 90,
      'block_attachment_download': true,
      'pin_timeout_minutes': 5,
      'allow_biometrics': false,
      'block_external_services': true,
    });
    expect(a.maxSyncDays, 90);
    expect(a.blockAttachmentDownload, isTrue);
    expect(a.pinTimeoutMinutes, 5);
    expect(a.allowBiometrics, isFalse);
    expect(a.blockExternalServices, isTrue);
    expect(a.blockWeather, isTrue, reason: 'внешние службы — и погода');

    final i = ManagedPolicy.fromMap(const {'max_sync_days': '30', 'pin_timeout_minutes': '999', 'allow_biometrics': 'no'});
    expect(i.maxSyncDays, 30);
    expect(i.pinTimeoutMinutes, 60, reason: 'не больше часа');
    expect(i.allowBiometrics, isFalse);

    final none = ManagedPolicy.fromMap(const {'org_name': 'Ромашка', 'max_sync_days': 0, 'pin_timeout_minutes': 0});
    expect(none.maxSyncDays, isNull);
    expect(none.pinTimeoutMinutes, isNull);
    expect(none.allowBiometrics, isTrue);
    expect(none.blockAttachmentDownload, isFalse);
  });

  test('срок почты: «вся почта» и длиннее — до предела, короче — как есть', () {
    const p = ManagedPolicy(maxSyncDays: 90);
    expect(p.capSyncDays(0), 90);
    expect(p.capSyncDays(365), 90);
    expect(p.capSyncDays(30), 30);
    expect(ManagedPolicy.none.capSyncDays(0), 0);
  });

  test('блокировка после бездействия — меньшее из политики Exchange и MDM', () {
    const p = ManagedPolicy(pinTimeoutMinutes: 5);
    expect(p.idleTimeout(null), const Duration(minutes: 5));
    expect(p.idleTimeout(const Duration(minutes: 2)), const Duration(minutes: 2));
    expect(p.idleTimeout(const Duration(minutes: 15)), const Duration(minutes: 5));
    expect(ManagedPolicy.none.idleTimeout(const Duration(minutes: 15)), const Duration(minutes: 15));
    expect(ManagedPolicy.none.idleTimeout(null), isNull);
  });

  test('вложения — запрет действия', () {
    ManagedPolicy.current = ManagedPolicy.fromMap(const {'block_attachment_download': true});
    expect(ManagedPolicy.deny(ManagedRule.attachments), isTrue);
    expect(ManagedPolicy.deny(ManagedRule.share), isFalse);
  });

  test('копия политики для фона — с новыми ключами', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Из MDM: внешние службы запрещены — значит, и погода.
    const p = ManagedPolicy(
        maxSyncDays: 60, pinTimeoutMinutes: 3, allowBiometrics: false, blockExternalServices: true, blockWeather: true);
    expect(ManagedPolicy.fromMap(p.toJson()), p);
    await prefs.setString(ManagedPolicy.prefKey, '');
    expect(ManagedPolicy.fromPrefs(prefs), ManagedPolicy.none);
  });
}

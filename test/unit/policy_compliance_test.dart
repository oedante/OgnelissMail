// Политика Exchange → требования к устройству (Android).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/device_security_service.dart';
import 'package:ogneliss/services/security/eas_policy_store.dart';
import 'package:ogneliss/services/security/policy_compliance.dart';

DeviceSecurityStatus _dev({
  LockComplexity complexity = LockComplexity.none,
  bool secure = false,
  StorageEncryption enc = StorageEncryption.active,
  bool admin = false,
}) =>
    DeviceSecurityStatus(
      supported: true,
      sdk: 34,
      deviceSecure: secure,
      complexity: complexity,
      encryption: enc,
      adminActive: admin,
    );

void main() {
  group('Требуемая сложность блокировки', () {
    test('без требования пароля — none', () {
      expect(requiredLockComplexity(const StoredEasPolicy()), LockComplexity.none);
    });
    test('пароль, простые PIN разрешены, длина 4 — low', () {
      expect(
          requiredLockComplexity(const StoredEasPolicy(pinRequired: true, minPasswordLength: 4)),
          LockComplexity.low);
    });
    test('простые PIN запрещены — medium', () {
      expect(
          requiredLockComplexity(const StoredEasPolicy(
              pinRequired: true, minPasswordLength: 4, allowSimplePassword: false)),
          LockComplexity.medium);
    });
    test('нужны буквы — medium', () {
      expect(
          requiredLockComplexity(
              const StoredEasPolicy(pinRequired: true, alphanumericRequired: true)),
          LockComplexity.medium);
    });
    test('длина 6 — high (Android не сообщает точную длину)', () {
      const p = StoredEasPolicy(pinRequired: true, minPasswordLength: 6);
      expect(requiredLockComplexity(p), LockComplexity.high);
      expect(PolicyCompliance.lengthRoundedUp(p), isTrue);
    });
    test('длина 8 — high без округления', () {
      const p = StoredEasPolicy(pinRequired: true, minPasswordLength: 8);
      expect(requiredLockComplexity(p), LockComplexity.high);
      expect(PolicyCompliance.lengthRoundedUp(p), isFalse);
    });
  });

  group('Проверка устройства', () {
    const policy = StoredEasPolicy(pinRequired: true, allowSimplePassword: false);

    test('нет блокировки — почта закрыта', () {
      final c = evaluatePolicy(policy, _dev());
      expect(c.blocking, isTrue);
      expect(c.screenLockOk, isFalse);
    });
    test('графический ключ (low) при требовании medium — закрыта', () {
      expect(evaluatePolicy(policy, _dev(complexity: LockComplexity.low)).blocking, isTrue);
    });
    test('PIN medium — открыта', () {
      expect(evaluatePolicy(policy, _dev(complexity: LockComplexity.medium)).blocking, isFalse);
    });
    test('Android 9: уровень неизвестен, блокировка есть — открыта', () {
      final c = evaluatePolicy(policy, _dev(complexity: LockComplexity.unknown, secure: true));
      expect(c.blocking, isFalse);
    });
    test('Android 9: уровень неизвестен, блокировки нет — закрыта', () {
      expect(evaluatePolicy(policy, _dev(complexity: LockComplexity.unknown)).blocking, isTrue);
    });
    test('шифрование по ключу по умолчанию при требовании шифрования — закрыта', () {
      const p = StoredEasPolicy(requireEncryption: true);
      expect(evaluatePolicy(p, _dev(enc: StorageEncryption.defaultKey)).blocking, isTrue);
      expect(evaluatePolicy(p, _dev(enc: StorageEncryption.active)).blocking, isFalse);
    });
    test('не Android — политика исполняется PIN-кодом приложения', () {
      final c = evaluatePolicy(policy, DeviceSecurityStatus.unsupported);
      expect(c.applies, isFalse);
      expect(c.blocking, isFalse);
    });
    test('тайм-аут без администратора — предлагаем включить', () {
      const p = StoredEasPolicy(maxInactivitySeconds: 300);
      expect(evaluatePolicy(p, _dev()).adminWanted, isTrue);
      expect(evaluatePolicy(p, _dev(admin: true)).adminWanted, isFalse);
    });
  });

  group('Несколько ящиков', () {
    test('берётся самое строгое', () {
      final m = const StoredEasPolicy(pinRequired: true, minPasswordLength: 4, maxFailedAttempts: 10)
          .merge(const StoredEasPolicy(
              pinRequired: true,
              minPasswordLength: 6,
              allowSimplePassword: false,
              requireEncryption: true,
              maxFailedAttempts: 5));
      expect(m.minPasswordLength, 6);
      expect(m.allowSimplePassword, isFalse);
      expect(m.requireEncryption, isTrue);
      expect(m.maxFailedAttempts, 5);
    });
    test('старая запись без новых полей читается с безопасными значениями', () {
      final p = StoredEasPolicy.fromJson({'pin': true, 'min': 4, 'idle': 600});
      expect(p.pinRequired, isTrue);
      expect(p.allowSimplePassword, isTrue);
      expect(p.minPasswordLength, 0);
      expect(p.maxInactivitySeconds, 600);
    });
  });
}

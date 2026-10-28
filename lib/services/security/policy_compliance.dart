// lib/services/security/policy_compliance.dart
// Выполняет ли устройство политику Exchange. Чистая логика без платформы —
// покрыта тестами (test/unit/policy_compliance_test.dart).
//
// Android 10+ не сообщает длину и состав PIN — только уровень сложности
// блокировки экрана (low/medium/high). Поэтому требования политики
// переводятся в минимальный уровень с запасом в сторону строгости: при
// «длина не меньше 5–7» нужен уровень high (PIN от 8 цифр или пароль
// от 6 символов) — medium гарантирует только 4.

import 'device_security_service.dart';
import 'eas_policy_store.dart';

int _rank(LockComplexity c) => switch (c) {
      LockComplexity.none => 0,
      LockComplexity.low => 1,
      LockComplexity.medium => 2,
      LockComplexity.high => 3,
      LockComplexity.unknown => -1,
    };

/// Минимальная сложность блокировки экрана, которая выполняет [p].
LockComplexity requiredLockComplexity(StoredEasPolicy p) {
  if (!p.pinRequired) return LockComplexity.none;
  if (p.minPasswordLength > 4) return LockComplexity.high;
  if (p.alphanumericRequired || !p.allowSimplePassword) return LockComplexity.medium;
  return LockComplexity.low;
}

class PolicyCompliance {
  /// Устройство можно проверить (Android) и политика что-то от него требует.
  final bool applies;
  final LockComplexity required;
  final bool screenLockOk;
  final bool encryptionOk;

  /// Политика задаёт тайм-аут блокировки, а администратор устройства,
  /// который мог бы его применить, не включён.
  final bool adminWanted;

  const PolicyCompliance({
    required this.applies,
    required this.required,
    required this.screenLockOk,
    required this.encryptionOk,
    required this.adminWanted,
  });

  /// Почту показывать нельзя, пока требование не выполнено.
  bool get blocking => applies && (!screenLockOk || !encryptionOk);

  /// Длина из политики (5–7) строже, чем уровень medium, но мягче high.
  static bool lengthRoundedUp(StoredEasPolicy p) =>
      p.pinRequired && p.minPasswordLength > 4 && p.minPasswordLength < 8;
}

PolicyCompliance evaluatePolicy(StoredEasPolicy p, DeviceSecurityStatus s) {
  final need = requiredLockComplexity(p);
  final applies = s.supported && p.hasDeviceRequirements;

  bool lockOk;
  if (need == LockComplexity.none) {
    lockOk = true;
  } else if (s.complexity == LockComplexity.unknown) {
    // Android 7–9 или устройство не разблокировано после перезагрузки:
    // уровень не узнать, проверяем хотя бы наличие блокировки.
    lockOk = s.deviceSecure;
  } else {
    lockOk = _rank(s.complexity) >= _rank(need);
  }

  final encOk = !p.requireEncryption ||
      switch (s.encryption) {
        StorageEncryption.active || StorageEncryption.activating => true,
        // Ключ по умолчанию: блокировки экрана нет (её потребует проверка
        // выше) либо это Android 7–9 с полным шифрованием без «безопасного
        // запуска» — при установленной блокировке это принимаем.
        StorageEncryption.defaultKey => s.deviceSecure,
        StorageEncryption.inactive => false,
        // Устройство не умеет шифровать / не удалось узнать — не блокируем
        // почту без возможности что-то исправить.
        StorageEncryption.unsupported || StorageEncryption.unknown => true,
      };

  return PolicyCompliance(
    applies: applies,
    required: need,
    screenLockOk: lockOk,
    encryptionOk: encOk,
    adminWanted: applies && p.maxInactivitySeconds > 0 && !s.adminActive,
  );
}

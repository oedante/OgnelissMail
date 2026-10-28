// lib/services/security/eas_policy_store.dart
// Политика безопасности, полученная от Exchange (EAS Provision), по аккаунтам.
//
// Раньше политика разбиралась, записывалась в журнал и принималась серверу
// как выполненная (Status 1), но приложение её не применяло: администратор
// видел «устройство соответствует», а почта открывалась без всякой защиты.
// Теперь приложение исполняет то, что в его силах:
// - DevicePasswordEnabled → на Android: блокировка экрана нужной сложности
//   (см. policy_compliance.dart); на остальных платформах — PIN приложения;
// - MaxInactivityTimeDeviceLock → блокировка приложения после бездействия и,
//   если пользователь включил администратора устройства, тайм-аут экрана;
// - RequireDeviceEncryption → проверка шифрования хранилища.
// Камеру, срок действия пароля и правила символов на Android 10+ обычное
// приложение задать не может (Google закрыл это для администраторов
// устройства) — их исполняет MDM.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;

/// Итоговая политика по всем подключённым ящикам. Движок обновляет её
/// (invalidate) после каждого подключения.
final easPolicyProvider = Provider<StoredEasPolicy>((ref) {
  final ids = ref.watch(accountsProvider.select((l) => l.map((a) => a.id).join(',')));
  if (ids.isEmpty) return const StoredEasPolicy();
  return EasPolicyStore(ref.watch(sharedPrefsProvider)).effective(ids.split(','));
});

class StoredEasPolicy {
  final bool pinRequired;
  /// Длина PIN приложения (4–6: поле ввода PIN рассчитано на 6 цифр).
  final int minPinLength;
  final int maxInactivitySeconds;
  /// Минимальная длина пароля устройства из политики как есть (0 — не задана).
  final int minPasswordLength;
  /// Простые PIN (1111, 1234) разрешены.
  final bool allowSimplePassword;
  /// Нужен пароль с буквами.
  final bool alphanumericRequired;
  final bool requireEncryption;
  /// Число неудачных попыток до стирания (0 — не задано).
  final int maxFailedAttempts;

  const StoredEasPolicy({
    this.pinRequired = false,
    this.minPinLength = 4,
    this.maxInactivitySeconds = 0,
    this.minPasswordLength = 0,
    this.allowSimplePassword = true,
    this.alphanumericRequired = false,
    this.requireEncryption = false,
    this.maxFailedAttempts = 0,
  });

  /// Политика что-то требует от устройства.
  bool get hasDeviceRequirements =>
      pinRequired || requireEncryption || maxInactivitySeconds > 0;

  Map<String, dynamic> toJson() => {
        'pin': pinRequired,
        'min': minPinLength,
        'idle': maxInactivitySeconds,
        'pwLen': minPasswordLength,
        'simple': allowSimplePassword,
        'alnum': alphanumericRequired,
        'enc': requireEncryption,
        'fail': maxFailedAttempts,
      };

  factory StoredEasPolicy.fromJson(Map<String, dynamic> j) => StoredEasPolicy(
        pinRequired: j['pin'] == true,
        minPinLength: (j['min'] as num?)?.toInt() ?? 4,
        maxInactivitySeconds: (j['idle'] as num?)?.toInt() ?? 0,
        // Записи до октября 2026 без pwLen: длина хранилась только в min (4–6).
        minPasswordLength: (j['pwLen'] as num?)?.toInt() ??
            (((j['min'] as num?)?.toInt() ?? 0) > 4 ? (j['min'] as num).toInt() : 0),
        allowSimplePassword: j['simple'] != false,
        alphanumericRequired: j['alnum'] == true,
        requireEncryption: j['enc'] == true,
        maxFailedAttempts: (j['fail'] as num?)?.toInt() ?? 0,
      );

  /// Самая строгая из нескольких политик (несколько ящиков Exchange).
  StoredEasPolicy merge(StoredEasPolicy o) => StoredEasPolicy(
        pinRequired: pinRequired || o.pinRequired,
        minPinLength: minPinLength > o.minPinLength ? minPinLength : o.minPinLength,
        maxInactivitySeconds: _minPositive(maxInactivitySeconds, o.maxInactivitySeconds),
        minPasswordLength:
            minPasswordLength > o.minPasswordLength ? minPasswordLength : o.minPasswordLength,
        allowSimplePassword: allowSimplePassword && o.allowSimplePassword,
        alphanumericRequired: alphanumericRequired || o.alphanumericRequired,
        requireEncryption: requireEncryption || o.requireEncryption,
        maxFailedAttempts: _minPositive(maxFailedAttempts, o.maxFailedAttempts),
      );

  static int _minPositive(int a, int b) {
    if (a <= 0) return b;
    if (b <= 0) return a;
    return a < b ? a : b;
  }
}

class EasPolicyStore {
  final SharedPreferences _prefs;
  EasPolicyStore(this._prefs);

  static const _prefix = 'eas_policy_';

  Future<void> save(String accountId, StoredEasPolicy p) =>
      _prefs.setString('$_prefix$accountId', jsonEncode(p.toJson()));

  Future<void> remove(String accountId) => _prefs.remove('$_prefix$accountId');

  /// Аккаунты, чья политика что-то требует от устройства.
  List<String> accountsWithRequirements(Iterable<String> accountIds) => [
        for (final id in accountIds)
          if (_read(id)?.hasDeviceRequirements ?? false) id,
      ];

  StoredEasPolicy? _read(String id) {
    final raw = _prefs.getString('$_prefix$id');
    if (raw == null) return null;
    try {
      return StoredEasPolicy.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Итоговая политика по всем аккаунтам из [accountIds].
  StoredEasPolicy effective(Iterable<String> accountIds) {
    var result = const StoredEasPolicy();
    for (final id in accountIds) {
      final raw = _prefs.getString('$_prefix$id');
      if (raw == null) continue;
      try {
        result = result.merge(StoredEasPolicy.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    return result;
  }
}

// lib/services/security/device_security_service.dart
// Состояние безопасности устройства для политик Exchange (Android).
//
// Канал "ogneliss/device_security" (android/.../DeviceSecurityPlugin.kt):
// сложность блокировки экрана, шифрование хранилища, администратор
// устройства (только тайм-аут блокировки экрана). На других платформах
// сервис сообщает supported = false, и политика исполняется PIN-кодом
// приложения, как раньше.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';

/// Сложность блокировки экрана по классификации Android 10+.
///  low    — графический ключ или PIN с повторами (1111, 1234);
///  medium — PIN без повторов от 4 цифр или пароль от 4 символов;
///  high   — PIN без повторов от 8 цифр или пароль от 6 символов.
/// unknown — Android 7–9 (сложность не сообщается) или устройство ещё не
/// разблокировано после перезагрузки.
enum LockComplexity { none, low, medium, high, unknown }

LockComplexity _complexityOf(String? s) => switch (s) {
      'none' => LockComplexity.none,
      'low' => LockComplexity.low,
      'medium' => LockComplexity.medium,
      'high' => LockComplexity.high,
      _ => LockComplexity.unknown,
    };

/// active — зашифровано; defaultKey — зашифровано ключом по умолчанию
/// (блокировки экрана нет, защита фактически не действует).
enum StorageEncryption { active, defaultKey, activating, inactive, unsupported, unknown }

StorageEncryption _encryptionOf(String? s) => switch (s) {
      'active' => StorageEncryption.active,
      'default_key' => StorageEncryption.defaultKey,
      'activating' => StorageEncryption.activating,
      'inactive' => StorageEncryption.inactive,
      'unsupported' => StorageEncryption.unsupported,
      _ => StorageEncryption.unknown,
    };

class DeviceSecurityStatus {
  /// Платформа умеет проверять устройство (сейчас — только Android).
  final bool supported;
  final int sdk;
  final bool deviceSecure;
  final LockComplexity complexity;
  final StorageEncryption encryption;
  final bool adminActive;
  final int maxTimeToLockMs;

  const DeviceSecurityStatus({
    this.supported = false,
    this.sdk = 0,
    this.deviceSecure = false,
    this.complexity = LockComplexity.unknown,
    this.encryption = StorageEncryption.unknown,
    this.adminActive = false,
    this.maxTimeToLockMs = 0,
  });

  static const unsupported = DeviceSecurityStatus();

  factory DeviceSecurityStatus.fromMap(Map<Object?, Object?> m) => DeviceSecurityStatus(
        supported: true,
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        deviceSecure: m['deviceSecure'] == true,
        complexity: _complexityOf(m['complexity'] as String?),
        encryption: _encryptionOf(m['encryption'] as String?),
        adminActive: m['adminActive'] == true,
        maxTimeToLockMs: (m['maxTimeToLockMs'] as num?)?.toInt() ?? 0,
      );
}

class DeviceSecurityService {
  static const _ch = MethodChannel('ogneliss/device_security');

  bool get _android => !kIsWeb && Platform.isAndroid;

  Future<DeviceSecurityStatus> status() async {
    if (!_android) return DeviceSecurityStatus.unsupported;
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('status');
      return m == null ? DeviceSecurityStatus.unsupported : DeviceSecurityStatus.fromMap(m);
    } catch (e) {
      AppLogger.warning('Безопасность устройства: статус недоступен ($e)');
      return DeviceSecurityStatus.unsupported;
    }
  }

  /// Открыть системный экран установки блокировки не ниже [min].
  Future<void> requestScreenLock(LockComplexity min) async {
    if (!_android) return;
    final level = switch (min) {
      LockComplexity.high => 'high',
      LockComplexity.low => 'low',
      _ => 'medium',
    };
    try {
      await _ch.invokeMethod('requestScreenLock', {'complexity': level});
    } catch (e) {
      AppLogger.warning('Не удалось открыть настройку блокировки экрана: $e');
    }
  }

  /// Системный экран включения администратора устройства.
  Future<void> requestAdmin(String explanation) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('requestAdmin', {'explanation': explanation});
    } catch (e) {
      AppLogger.warning('Не удалось открыть экран администратора устройства: $e');
    }
  }

  /// Тайм-аут блокировки экрана (0 — снять ограничение). Работает, только
  /// если администратор устройства включён; возвращает, применилось ли.
  Future<bool> setMaxTimeToLock(Duration d) async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('setMaxTimeToLock', {'ms': d.inMilliseconds}) ?? false;
    } catch (e) {
      AppLogger.warning('Тайм-аут блокировки экрана не применён: $e');
      return false;
    }
  }

  Future<void> openSecuritySettings() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('openSecuritySettings');
    } catch (e) {
      AppLogger.warning('Не удалось открыть настройки безопасности: $e');
    }
  }

  Future<void> removeAdmin() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('removeAdmin');
    } catch (e) {
      AppLogger.warning('Не удалось выключить администратора устройства: $e');
    }
  }
}

final deviceSecurityServiceProvider = Provider<DeviceSecurityService>((_) => DeviceSecurityService());

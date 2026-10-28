// lib/services/device/device_contacts_sync.dart
// Синхронизация контактов с системной адресной книгой устройства.
// Импорт контактов с устройства → БД.
// Экспорт контактов из БД → устройство.
// Двунаправленная синхронизация по запросу пользователя.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/contact_model.dart';
import '../../data/providers/database_provider.dart';
import 'package:drift/drift.dart';

final deviceContactsSyncProvider = Provider<DeviceContactsSync>((ref) {
  final db = ref.watch(databaseProvider);
  return DeviceContactsSync(db);
});

class DeviceContactsSync {
  final AppDatabase _db;

  /// Platform channel для нативного доступа к контактам
  static const _channel = MethodChannel('ogneliss/device_contacts');

  DeviceContactsSync(this._db);

  /// Доступна ли синхронизация на этой платформе
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Реально ли подключён нативный канал (иначе импорт/экспорт — фикция и молча
  /// вернут 0). Пробуем лёгкий вызов 'ping': если нативная часть не встроена —
  /// прилетит MissingPluginException. UI показывает раздел только при true.
  Future<bool> isChannelReady() async {
    if (!isAvailable) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('ping');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Проверить разрешение на контакты
  Future<bool> hasPermission() async {
    if (!isAvailable) return false;
    return await Permission.contacts.isGranted;
  }

  /// Запросить разрешение
  Future<bool> requestPermission() async {
    if (!isAvailable) return false;
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  /// Импортировать контакты с устройства в БД
  Future<int> importFromDevice() async {
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return 0;
    }

    try {
      AppLogger.info('DeviceContactsSync: начало импорта');

      // Получаем контакты через platform channel
      final List<dynamic> rawContacts = await _channel.invokeMethod('getContacts') ?? [];

      int imported = 0;
      await _db.batch((batch) {
        for (final raw in rawContacts) {
          final m = raw as Map<dynamic, dynamic>;
          final email = m['email'] as String?;
          if (email == null || email.isEmpty) continue;

          batch.insert(
            _db.contacts,
            ContactsCompanion.insert(
              id: 'device_${email.hashCode}_${DateTime.now().millisecondsSinceEpoch}',
              email: email,
              displayName: m['displayName'] as String? ?? email,
              firstName: Value(m['givenName'] as String?),
              lastName: Value(m['familyName'] as String?),
              middleName: Value(m['middleName'] as String?),
              phoneWork: Value(m['phoneWork'] as String?),
              phoneMobile: Value(m['phoneMobile'] as String?),
              company: Value(m['company'] as String?),
              department: Value(m['department'] as String?),
              jobTitle: Value(m['jobTitle'] as String?),
              source: Value(ContactSource.personal.index),
            ),
            mode: InsertMode.insertOrIgnore,
          );
          imported++;
        }
      });

      AppLogger.info('DeviceContactsSync: импортировано $imported контактов');
      return imported;
    } on MissingPluginException {
      AppLogger.warning('DeviceContactsSync: platform channel not available');
      return 0;
    } catch (e, stack) {
      AppLogger.error('DeviceContactsSync: ошибка импорта', e, stack);
      return 0;
    }
  }

  /// Экспортировать контакты из БД на устройство
  Future<int> exportToDevice(String accountId) async {
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return 0;
    }

    try {
      final contacts = await (_db.select(_db.contacts)
            ..where((c) => c.accountId.equals(accountId) | c.accountId.isNull())
            ..limit(500))
          .get();

      int exported = 0;
      for (final contact in contacts) {
        try {
          await _channel.invokeMethod('addContact', {
            'displayName': contact.displayName,
            'givenName': contact.firstName,
            'familyName': contact.lastName,
            'email': contact.email,
            'phoneWork': contact.phoneWork,
            'phoneMobile': contact.phoneMobile,
            'company': contact.company,
            'jobTitle': contact.jobTitle,
            'department': contact.department,
          });
          exported++;
        } catch (e) {
          AppLogger.warning('Export contact ${contact.email}: $e');
        }
      }

      AppLogger.info('DeviceContactsSync: экспортировано $exported контактов');
      return exported;
    } on MissingPluginException {
      return 0;
    } catch (e) {
      AppLogger.error('DeviceContactsSync: ошибка экспорта', e);
      return 0;
    }
  }
}

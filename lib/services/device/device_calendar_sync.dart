// lib/services/device/device_calendar_sync.dart
// Синхронизация событий с системным календарём устройства.
// Запись событий из БД в системный календарь (Android/iOS).

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';

final deviceCalendarSyncProvider = Provider<DeviceCalendarSync>((ref) {
  final db = ref.watch(databaseProvider);
  return DeviceCalendarSync(db);
});

class DeviceCalendarSync {
  final AppDatabase _db;
  static const _channel = MethodChannel('ogneliss/device_calendar');

  DeviceCalendarSync(this._db);

  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Реально ли подключён нативный канал (иначе экспорт — фикция и молча вернёт
  /// false/0). Лёгкий вызов 'ping': нет нативной части → MissingPluginException.
  /// UI показывает раздел только при true.
  Future<bool> isChannelReady() async {
    if (!isAvailable) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('ping');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    if (!isAvailable) return false;
    return await Permission.calendarFullAccess.isGranted;
  }

  Future<bool> requestPermission() async {
    if (!isAvailable) return false;
    final status = await Permission.calendarFullAccess.request();
    return status.isGranted;
  }

  /// Экспортировать событие в системный календарь
  Future<bool> exportEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? location,
    bool allDay = false,
    int? reminderMinutes,
  }) async {
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    try {
      // Весь день — полночь UTC первого дня и полночь после последнего
      // (1.8.13), как в «Календаре в телефоне»: так их ждут календари
      // Android и iPhone.
      int ms(DateTime d) => allDay
          ? DateTime.utc(d.toLocal().year, d.toLocal().month, d.toLocal().day).millisecondsSinceEpoch
          : d.millisecondsSinceEpoch;
      final end = allDay && !endTime.isAfter(startTime) ? startTime.add(const Duration(days: 1)) : endTime;
      final result = await _channel.invokeMethod<bool>('addEvent', {
        'title': title,
        'startTime': ms(startTime),
        'endTime': ms(end),
        'description': description,
        'location': location,
        'allDay': allDay,
        'reminderMinutes': reminderMinutes,
      });

      AppLogger.info('DeviceCalendar: event exported: $title');
      return result ?? false;
    } on MissingPluginException {
      AppLogger.warning('DeviceCalendar: platform channel not available');
      return false;
    } catch (e) {
      AppLogger.error('DeviceCalendar: export error', e);
      return false;
    }
  }

  /// Экспортировать все события аккаунта
  Future<int> exportAllEvents(String accountId) async {
    if (!await hasPermission()) return 0;

    try {
      final now = DateTime.now();
      final events = await (_db.select(_db.calendarEvents)
            ..where((e) => e.accountId.equals(accountId))
            ..where((e) => e.startTime.isBiggerOrEqualValue(now.subtract(const Duration(days: 7))))
            ..where((e) => e.isCancelled.equals(false)))
          .get();

      int exported = 0;
      for (final event in events) {
        final success = await exportEvent(
          title: event.title,
          startTime: event.startTime,
          endTime: event.endTime,
          description: event.description,
          location: event.location,
          allDay: event.isAllDay,
        );
        if (success) exported++;
      }

      AppLogger.info('DeviceCalendar: exported $exported events');
      return exported;
    } catch (e) {
      AppLogger.error('DeviceCalendar: bulk export error', e);
      return 0;
    }
  }
}

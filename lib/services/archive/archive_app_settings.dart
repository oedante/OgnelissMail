// lib/services/archive/archive_app_settings.dart
// Настройки приложения в архиве Ogneliss (замечание владельца 25.10.2026):
// ящики, настройки, подписи, заметки и — по выбору — пароли ящиков
// хранятся в архиве снимком. На новом устройстве (или после переустановки)
// подключили копию архива — тут же восстановили и ящики с настройками.
//
// Содержимое то же, что у резервной копии (BackupService.collect), но без
// отдельного пароля: архив и так зашифрован своим ключом. Снимок
// обновляется при каждой архивации и кнопкой на экране архива; хранятся
// последние пять.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/device/device_user_agent.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/database/app_database.dart';
import '../backup/backup_service.dart';
import 'archive_db.dart';

abstract final class ArchiveAppSettings {
  /// Положить снимок настроек в архив.
  static Future<void> save({
    required ArchiveDb archive,
    required AppDatabase db,
    required SharedPreferences prefs,
    required SecureStorageService secure,
    required bool withSecrets,
  }) async {
    final payload = await BackupService.collect(db: db, prefs: prefs, secure: secure, includeSecrets: withSecrets);
    final data = Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(payload))));
    final accounts = (payload['accounts'] as List).length;
    await archive.saveSettings(
      data: data,
      app: AppConstants.appVersion,
      device: '${DeviceUserAgent.deviceOs} ${DeviceUserAgent.deviceModel}'.trim(),
      accounts: accounts,
      secrets: withSecrets && (payload['secrets'] as Map).isNotEmpty,
    );
    AppLogger.info('Архив Ogneliss: настройки приложения сохранены (ящиков $accounts)');
  }

  /// Восстановить снимок [id] на этом устройстве: ящиков, которых здесь
  /// нет, — добавляются; настройки заменяются настройками из архива.
  static Future<RestoreReport> restore({
    required ArchiveDb archive,
    required int id,
    required AppDatabase db,
    required SharedPreferences prefs,
    required SecureStorageService secure,
  }) async {
    final data = await archive.settingsData(id);
    if (data == null) throw const BackupException('backupErrFormat');
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(gzip.decode(data))) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('backupErrFormat');
    }
    return BackupService.restore(payload: payload, db: db, prefs: prefs, secure: secure);
  }
}

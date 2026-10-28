// lib/services/security/remote_wipe_service.dart
// Удалённое стирание по команде сервера Exchange (EAS Provision).
//
// RemoteWipe — администратор стирает устройство: удаляются ВСЕ данные
// приложения (все ящики, кэш вложений, настройки, токены, журнал).
// AccountOnlyRemoteWipe (EAS 16.1) — стирается только этот ящик.
//
// Раньше команда в рабочем движке только записывалась в журнал, а в старом
// модуле стирался один ящик и не полностью (оставались поисковый индекс,
// заметки, поручения, кэш вложений). Получение подтверждается серверу
// движком до вызова сюда.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' show RemoteWipeKind;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../mail/attachment_cache_service.dart';
import 'device_security_service.dart';
import 'pin_lock_service.dart';

final remoteWipeProvider = Provider<RemoteWipeService>((ref) => RemoteWipeService(ref));

class RemoteWipeService {
  final Ref _ref;
  RemoteWipeService(this._ref);

  bool _running = false;

  /// Команда от сервера для ящика [email] (вызывается движком).
  Future<void> handleRemoteWipe({
    String? accountId,
    String? email,
    required RemoteWipeKind kind,
  }) async {
    if (_running) return;
    _running = true;
    try {
      if (kind == RemoteWipeKind.device) {
        await wipeAll();
        return;
      }
      var id = accountId;
      if (id == null && email != null) {
        final db = _ref.read(databaseProvider);
        final rows = await db.select(db.accounts).get();
        for (final r in rows) {
          if (r.email.toLowerCase() == email.toLowerCase()) id = r.id;
        }
      }
      if (id != null) await wipeAccount(id);
    } catch (e, st) {
      AppLogger.error('REMOTE WIPE: сбой', e, st);
    } finally {
      _running = false;
    }
  }

  /// Полная очистка данных одного аккаунта — тем же путём, что и удаление
  /// аккаунта пользователем (все таблицы, индекс, кэш, токены, состояние
  /// синхронизации).
  Future<void> wipeAccount(String accountId) async {
    AppLogger.warning('REMOTE WIPE аккаунта');
    await _ref.read(accountsProvider.notifier).removeAccount(accountId);
    AppLogger.warning('REMOTE WIPE аккаунта завершён');
  }

  /// Полная очистка ВСЕХ данных приложения.
  Future<void> wipeAll() async {
    AppLogger.warning('REMOTE WIPE: полная очистка приложения');
    final db = _ref.read(databaseProvider);
    final notifier = _ref.read(accountsProvider.notifier);
    for (final a in await db.select(db.accounts).get()) {
      await notifier.removeAccount(a.id);
    }
    // Всё, что не привязано к аккаунту (журнал аудита, шаблоны, история
    // поиска, общие таблицы): очищаем каждую таблицу базы.
    try {
      await db.transaction(() async {
        for (final t in db.allTables) {
          await db.customStatement('DELETE FROM "${t.actualTableName}"');
        }
        await db.customStatement('DELETE FROM emails_fts');
      });
    } catch (e) {
      AppLogger.warning('REMOTE WIPE: очистка таблиц: $e');
    }
    try { await db.customStatement('VACUUM'); } catch (_) {}
    // Администратор устройства (тайм-аут экрана) больше не нужен; без этого
    // приложение нельзя удалить, не выключив его вручную в настройках.
    await _ref.read(deviceSecurityServiceProvider).removeAdmin();

    try { await _ref.read(attachmentCacheProvider).clear(); } catch (_) {}
    try { await _ref.read(pinLockProvider.notifier).removePin(); } catch (_) {}
    await _ref.read(secureStorageProvider).deleteAll();
    try { await (await SharedPreferences.getInstance()).clear(); } catch (_) {}
    await _deleteLogs();
    AppLogger.warning('REMOTE WIPE: приложение очищено');
  }

  Future<void> _deleteLogs() async {
    if (kIsWeb) return;
    try {
      for (final dir in [await getApplicationSupportDirectory(), await getApplicationDocumentsDirectory()]) {
        final logs = Directory('${dir.path}/logs');
        if (await logs.exists()) await logs.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Совместимость со старым модулем ActiveSync (вход и SmartForward).
  Future<bool> handleProvisionRemoteWipe(String accountId,
      {required bool remoteWipeRequested, bool accountOnly = false}) async {
    if (!remoteWipeRequested) return false;
    await handleRemoteWipe(
        accountId: accountId,
        kind: accountOnly ? RemoteWipeKind.account : RemoteWipeKind.device);
    return true;
  }
}

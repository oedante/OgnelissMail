// lib/services/notifications/account_notify_mode.dart
// Уведомления о письмах — по ящику (1.6.45): рабочий ящик со звуком, личный
// без звука или только VIP. Раньше настройка была одна на всё приложение:
// чтобы не отвлекаться на личную почту в рабочее время, приходилось
// выключать уведомления целиком — и пропускать рабочие письма.
//
// Хранится в SharedPreferences (`acc_notify_<id>`), а не в базе: читается и
// фоновой задачей, и не требует миграции базы.

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/folder_model.dart' show FolderType;

enum AccountNotifyMode {
  /// Все новые письма — как раньше (по умолчанию).
  all,

  /// В шторке, но без звука и вибрации.
  quiet,

  /// Только VIP и письма по правилу «уведомлять всегда».
  vipOnly,
}

class AccountNotify {
  AccountNotify._();

  static String _key(String accountId) => 'acc_notify_$accountId';

  static AccountNotifyMode of(SharedPreferences p, String accountId) =>
      switch (p.getString(_key(accountId))) {
        'quiet' => AccountNotifyMode.quiet,
        'vip' => AccountNotifyMode.vipOnly,
        _ => AccountNotifyMode.all,
      };

  static Future<void> set(SharedPreferences p, String accountId, AccountNotifyMode m) => switch (m) {
        AccountNotifyMode.all => p.remove(_key(accountId)),
        AccountNotifyMode.quiet => p.setString(_key(accountId), 'quiet'),
        AccountNotifyMode.vipOnly => p.setString(_key(accountId), 'vip'),
      };

  /// Ключ строки для подписи режима.
  static String labelKey(AccountNotifyMode m) => switch (m) {
        AccountNotifyMode.all => 'accNotifyAll',
        AccountNotifyMode.quiet => 'accNotifyQuiet',
        AccountNotifyMode.vipOnly => 'accNotifyVip',
      };
}

/// Уведомления по папкам (1.7.2, просьба пользователя через владельца
/// 21.10.2026): папку можно синхронизировать, но не получать о ней
/// уведомлений («Синхронизация папок» — колокольчик у папки). Хранится список
/// выключенных «ящик|папка» в SharedPreferences: его читает и фоновая задача.
/// Правило «уведомлять всегда» пробивает и выключенную папку.
class FolderNotify {
  FolderNotify._();

  static const _key = 'folder_notify_off';

  /// Типы папок, о которых уведомлений нет никогда: свои письма, корзина,
  /// спам (как [SyncService._noNotifyFolderTypes]).
  static const neverTypes = <FolderType>{
    FolderType.trash, FolderType.junk,
    FolderType.sent, FolderType.drafts, FolderType.outbox,
  };

  static String key(String accountId, String folderId) => '$accountId|$folderId';

  static Set<String> off(SharedPreferences p) => (p.getStringList(_key) ?? const <String>[]).toSet();

  static bool isMuted(SharedPreferences p, String accountId, String folderId) =>
      off(p).contains(key(accountId, folderId));

  /// Включить ([notify]) или выключить уведомления папок [folderIds] ящика.
  static Future<Set<String>> set(
      SharedPreferences p, String accountId, Iterable<String> folderIds, bool notify) async {
    final next = off(p);
    for (final id in folderIds) {
      if (notify) {
        next.remove(key(accountId, id));
      } else {
        next.add(key(accountId, id));
      }
    }
    await p.setStringList(_key, next.toList()..sort());
    return next;
  }

  /// Ящик удалён — его папки из списка убрать.
  static Future<void> forgetAccount(SharedPreferences p, String accountId) async {
    final next = off(p)..removeWhere((k) => k.startsWith('$accountId|'));
    await p.setStringList(_key, next.toList()..sort());
  }
}

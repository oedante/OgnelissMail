// lib/services/mail/shared_access.dart
// Общий (делегированный) ящик «только календарь» (1.6.49): секретарю часто
// выдают доступ к календарю руководителя, а к его почте — нет. Тогда список
// папок такого ящика пуст (FindFolder отвечает «нет доступа»), и синхронизация
// раз за разом просила его зря. Признак — в настройках, без новых полей в
// базе: время, когда доступа к почте не оказалось. Раз в сутки — проверка
// заново (доступ могли выдать).

import 'package:shared_preferences/shared_preferences.dart';

abstract final class SharedAccess {
  static String _key(String accountId) => 'shared_cal_only_$accountId';

  /// Доступ только к календарю (по последней проверке).
  static bool calendarOnly(SharedPreferences prefs, String accountId) => (prefs.getInt(_key(accountId)) ?? 0) > 0;

  /// Пора проверить доступ к почте снова.
  static bool recheckDue(SharedPreferences prefs, String accountId, {DateTime? now}) {
    final at = prefs.getInt(_key(accountId)) ?? 0;
    if (at <= 0) return true;
    final n = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return n - at > const Duration(hours: 24).inMilliseconds;
  }

  static Future<void> setCalendarOnly(SharedPreferences prefs, String accountId, bool on) =>
      on ? prefs.setInt(_key(accountId), DateTime.now().millisecondsSinceEpoch) : prefs.remove(_key(accountId));
}

// lib/services/background/background_alarm.dart
//
// Будильник фоновой проверки почты (Android, 2.3.2). Требование владельца
// 11.11.2026: «для всех режимов (15, 30, час, по расписанию, пуш) проверки
// должны срабатывать вовремя, а не когда придётся».
//
// Журнал пользователя 10.11.2026 (Android 10, ящик «раз в 15 минут»): днём
// почта проверялась в 16:05, 17:28 и 19:39. Службы почты у такого ящика
// нет, а плановую задачу WorkManager и сигнал сервера Android в глубоком
// сне (Doze) откладывает до редких окон обслуживания.
//
// Здесь — расчёт для нативной части (SyncHeartbeat.kt): после каждой
// проверки в настройки записываются
//  · [minutesKey] — наименьший интервал проверки среди ящиков, минуты
//    (0 — фоновые проверки не нужны: будильник снимается);
//  · [nextDueKey] — когда подойдёт срок ближайшего ящика, мс эпохи.
// Будильник ОС (срабатывает и в глубоком сне) выставляется на этот срок и
// на время проверки поднимает службу почты — у процесса со службой сеть
// есть и в глубоком сне. Если почту к сроку уже проверили (приложение
// открыто, плановая задача, сигнал сервера) — срок сдвинулся, и будильник
// только переставляется.

import '../../data/models/account_model.dart';
import '../sync/sync_schedule.dart';

class BackgroundAlarm {
  BackgroundAlarm._();

  /// Интервал будильника без службы, минуты (int в настройках).
  static const minutesKey = 'bg_alarm_minutes';

  /// Срок ближайшего ящика, мс эпохи (int в настройках).
  static const nextDueKey = 'bg_next_due_at';

  /// Ящик, почту которого проверяют по расписанию: активен, вход не
  /// сломан, не «только вручную».
  static bool eligible(AccountModel a) =>
      a.isActive && a.authFailedAt == null && SyncSchedule.checkMinutes(a) != null;

  /// Наименьший интервал проверки среди ящиков, минуты; 0 — будильник не
  /// нужен. [globalInterval] — настройка приложения (< 0 — «Никогда»).
  static int minutesFor({required int globalInterval, required Iterable<AccountModel> accounts, DateTime? now}) {
    if (globalInterval < 0) return 0;
    var best = 0;
    for (final a in accounts) {
      if (!eligible(a)) continue;
      final m = SyncSchedule.checkMinutes(a, at: now)!;
      if (best == 0 || m < best) best = m;
    }
    return best;
  }

  /// Интервал и срок ближайшего ящика. [lastSync] — когда ящик последний
  /// раз синхронизирован (по id). Ящик, срок которого уже прошёл (проверка
  /// только что не удалась или пропустила его — «только по Wi‑Fi»), ждёт
  /// следующей попытки через свой интервал, но не дольше [retryMinutes].
  static ({int minutes, int nextDueMs}) plan({
    required int globalInterval,
    required Iterable<AccountModel> accounts,
    required Map<String, DateTime?> lastSync,
    required DateTime now,
  }) {
    final minutes = minutesFor(globalInterval: globalInterval, accounts: accounts, now: now);
    if (minutes == 0) return (minutes: 0, nextDueMs: 0);
    DateTime? due;
    for (final a in accounts) {
      if (!eligible(a)) continue;
      final m = SyncSchedule.checkMinutes(a, at: now)!;
      final last = lastSync[a.id];
      var at = last == null ? now : last.add(Duration(minutes: m));
      // Запас в минуту — как у проверки («ещё не пора», SyncService).
      if (!at.isAfter(now.add(const Duration(minutes: 1)))) {
        at = now.add(Duration(minutes: m < retryMinutes ? m : retryMinutes));
      }
      if (due == null || at.isBefore(due)) due = at;
    }
    return (minutes: minutes, nextDueMs: due?.millisecondsSinceEpoch ?? 0);
  }

  /// Через сколько повторить проверку ящика, срок которого прошёл.
  static const retryMinutes = 15;
}

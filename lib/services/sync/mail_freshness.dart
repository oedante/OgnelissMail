// lib/services/sync/mail_freshness.dart
// Насколько свежа почта на экране (1.6.47, просьба владельца 19.10.2026):
// под названием папки — «Обновлено сейчас» или время последнего обновления.
// Значок «нет сети» в шапке появлялся не всегда: при зависшей проверке сеть
// есть, а почта не обновляется — снаружи этого было не видно.
//
// Свежесть ящика — последняя успешная синхронизация (accounts.lastSyncAt) или
// «сейчас», если push ящика на связи (письма приходят сами). На экране
// несколько ящиков («Вся почта» Хаба, группа) — по самому несвежему: иначе
// «обновлено сейчас» одного ящика прятало бы зависший второй.
//
// «Давно» — дольше двух интервалов проверки ящика и ещё 5 минут: таймер
// открытого приложения тикает раз в 5 минут, проверка ящика — по его
// интервалу. «Только вручную» и общая «Никогда» давними не бывают.

import '../../data/models/account_model.dart';
import 'sync_schedule.dart';

class MailFreshness {
  /// Когда почта на экране была свежей (по самому несвежему ящику);
  /// null — ящики ещё не обновлялись.
  final DateTime? at;

  /// Дольше положенного без обновления (или нужен вход) — показать заметно.
  final bool stale;

  const MailFreshness({required this.at, required this.stale});

  /// Push «на связи», если отчитывался за это время.
  static const pushAliveWindow = Duration(minutes: 5);

  /// Интервал автоматической проверки ящика в минутах; null — только вручную.
  static int? expectedMinutes(AccountModel a, DateTime now) => switch (a.syncInterval) {
        SyncInterval.manual => null,
        SyncInterval.minutes5 => 5,
        SyncInterval.minutes30 => 30,
        SyncInterval.hour1 => 60,
        SyncInterval.scheduled when !SyncSchedule.inWindow(now) => SyncSchedule.offMinutes,
        // Push без связи и «каждые 15 минут» — резервная проверка раз в 15.
        _ => 15,
      };

  /// [boxes] — ящики на экране и их последняя синхронизация, [pushAlive] —
  /// последний пульс push ящика, [autoSync] — общая настройка проверки не
  /// «Никогда».
  static MailFreshness of(
    Iterable<({AccountModel account, DateTime? last})> boxes, {
    required DateTime now,
    required DateTime? Function(String accountId) pushAlive,
    bool autoSync = true,
  }) {
    final auto = <DateTime?>[];
    final manual = <DateTime?>[];
    var stale = false;
    for (final b in boxes) {
      final a = b.account;
      if (!a.isActive) continue;
      // Нужен вход: ящик не обновится сам, сколько ни жди.
      if (a.authFailedAt != null) stale = true;
      var t = b.last;
      final alive = pushAlive(a.id);
      if (a.authFailedAt == null &&
          SyncSchedule.pushNow(a) &&
          alive != null &&
          now.difference(alive) < pushAliveWindow) {
        t = now;
      }
      final every = autoSync ? expectedMinutes(a, now) : null;
      if (every == null) {
        manual.add(t);
        continue;
      }
      auto.add(t);
      if (t != null && now.difference(t) > Duration(minutes: every * 2 + 5)) stale = true;
    }
    // Ящики «вручную» — в счёт, только если других нет: их время не говорит
    // о том, работает ли автоматическая проверка.
    final pool = auto.isNotEmpty ? auto : manual;
    if (pool.isEmpty) return const MailFreshness(at: null, stale: false);
    DateTime? oldest;
    for (final t in pool) {
      if (t == null) return MailFreshness(at: null, stale: stale);
      if (oldest == null || t.isBefore(oldest)) oldest = t;
    }
    return MailFreshness(at: oldest, stale: stale);
  }
}

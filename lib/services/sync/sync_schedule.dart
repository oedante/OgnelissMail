// lib/services/sync/sync_schedule.dart
// Проверка почты «По расписанию» (предложение владельца 10.10.2026): в
// рабочие часы — мгновенная доставка (push), в остальное время — проверка
// раз в N минут. Push держит соединение с сервером и будит радио каждые
// несколько минут; ночью и в выходные это лишний расход батареи, а письма
// всё равно можно прочитать утром.
//
// Расписание одно на все ящики в этом режиме (у каждого ящика свой выбор:
// «Мгновенно», «По расписанию», «Раз в 15 минут»…). Хранится в настройках
// приложения; [load] вызывается при запуске в главном и фоновом процессе.
//
// Переходы: в начале рабочего дня push поднимает сторож (пульс фоновой
// службы раз в ~10 минут и возврат в приложение), в конце — останавливает.
// Фоновая служба для ящиков «По расписанию» работает весь день: запустить
// её из фона в 7:00 Android 12+ не разрешает, а без push она лишь будит
// проверку по интервалу.

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/account_model.dart';

class SyncSchedule {
  SyncSchedule._();

  static const _kStart = 'sched_push_start';
  static const _kEnd = 'sched_push_end';
  static const _kDays = 'sched_push_days';
  static const _kOff = 'sched_push_off';

  /// Начало и конец рабочего окна — минуты от полуночи (по умолчанию 7:00–19:00).
  static int startMinutes = 7 * 60;
  static int endMinutes = 19 * 60;

  /// Дни push (1 — понедельник … 7 — воскресенье); по умолчанию пн–пт.
  static Set<int> days = {1, 2, 3, 4, 5};

  /// Интервал проверки вне окна, минуты: 15, 30 или 60.
  static int offMinutes = 15;

  static void load(SharedPreferences p) {
    startMinutes = (p.getInt(_kStart) ?? 7 * 60).clamp(0, 24 * 60 - 1);
    endMinutes = (p.getInt(_kEnd) ?? 19 * 60).clamp(0, 24 * 60 - 1);
    final d = p.getStringList(_kDays);
    days = d == null ? {1, 2, 3, 4, 5} : {for (final s in d) if (int.tryParse(s) case final v? when v >= 1 && v <= 7) v};
    final off = p.getInt(_kOff) ?? 15;
    offMinutes = const [15, 30, 60].contains(off) ? off : 15;
  }

  static Future<void> save(SharedPreferences p,
      {int? start, int? end, Set<int>? days, int? off}) async {
    if (start != null) startMinutes = start;
    if (end != null) endMinutes = end;
    if (days != null) SyncSchedule.days = {...days};
    if (off != null) offMinutes = off;
    await p.setInt(_kStart, startMinutes);
    await p.setInt(_kEnd, endMinutes);
    await p.setStringList(_kDays, [for (final d in SyncSchedule.days.toList()..sort()) '$d']);
    await p.setInt(_kOff, offMinutes);
  }

  /// Сейчас рабочее окно? Окно может переходить через полночь (22:00–6:00):
  /// тогда ночная часть относится ко дню начала.
  static bool inWindow([DateTime? at]) {
    final now = at ?? DateTime.now();
    final m = now.hour * 60 + now.minute;
    if (startMinutes == endMinutes) return days.contains(now.weekday); // круглые сутки
    if (startMinutes < endMinutes) {
      return days.contains(now.weekday) && m >= startMinutes && m < endMinutes;
    }
    if (m >= startMinutes) return days.contains(now.weekday);
    if (m < endMinutes) {
      final prev = now.weekday == 1 ? 7 : now.weekday - 1;
      return days.contains(prev);
    }
    return false;
  }

  /// Push у ящика сейчас: «Мгновенно» — всегда, «По расписанию» — в окне.
  static bool pushNow(AccountModel a) =>
      a.syncInterval == SyncInterval.push || (a.syncInterval == SyncInterval.scheduled && inWindow());

  /// Ящику нужна фоновая служба (сторож push): мгновенно или по расписанию.
  static bool needsService(AccountModel a) =>
      a.syncInterval == SyncInterval.push || a.syncInterval == SyncInterval.scheduled;

  /// «7:00–19:00» для подписей.
  static String windowLabel() => '${_hm(startMinutes)}–${_hm(endMinutes)}';

  static String _hm(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

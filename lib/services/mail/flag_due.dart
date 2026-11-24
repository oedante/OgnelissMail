// lib/services/mail/flag_due.dart
// Срок флажка письма, как в Outlook (2.7.2, просьба владельца 24.11.2026:
// «флажок на письма устанавливается без даты — нужно, как в Outlook,
// флажок „сегодня“»).
//
// Нажатие на флажок — срок «Сегодня» (быстрый флажок Outlook). Удержание
// флажка в письме — выбор: сегодня, завтра, на этой неделе, на следующей
// неделе, без даты. Срок хранится в поле follow_up_at письма (то же, что
// срок «На контроле»; у письма с «На контроле» срок — его, флажок срок не
// меняет), в Exchange (ActiveSync) уходит датами начала и срока флажка —
// Outlook показывает «Сегодня», «Завтра» и т. д. В IMAP у флажка дат нет:
// срок остаётся на устройстве.
//
// Время срока — 18:00 дня (как у «На контроле»): флажок со сроком виден в
// календаре («Письма с флажком») и в виджете календаря в конце рабочего
// дня. Просроченным флажок считается со следующего дня, как в Outlook.

import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

enum FlagDue { today, tomorrow, thisWeek, nextWeek, none }

/// Начало и срок флажка (дни, полночь по местному времени).
typedef FlagDates = ({DateTime start, DateTime due});

abstract final class FlagDues {
  /// Час срока в поле follow_up_at.
  static const dueHour = 18;

  /// Даты флажка для варианта; null — без даты. [now] — для тестов.
  ///
  /// Как в Outlook: «На этой неделе» — срок в пятницу этой недели (в
  /// пятницу и выходные — сегодня), начало — через два дня, но не позже
  /// срока; «На следующей неделе» — с понедельника по пятницу следующей
  /// недели.
  static FlagDates? datesOf(FlagDue d, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    DateTime plus(DateTime day, int days) => DateTime(day.year, day.month, day.day + days);
    switch (d) {
      case FlagDue.today:
        return (start: today, due: today);
      case FlagDue.tomorrow:
        final t = plus(today, 1);
        return (start: t, due: t);
      case FlagDue.thisWeek:
        final toFriday = DateTime.friday - today.weekday;
        final due = toFriday > 0 ? plus(today, toFriday) : today;
        final start = plus(today, 2).isAfter(due) ? due : plus(today, 2);
        return (start: start, due: due);
      case FlagDue.nextWeek:
        final monday = plus(today, 8 - today.weekday);
        return (start: monday, due: plus(monday, 4));
      case FlagDue.none:
        return null;
    }
  }

  /// Значение follow_up_at для срока [dueDay]: этот день, 18:00.
  static DateTime at(DateTime dueDay) {
    final l = dueDay.isUtc ? dueDay.toLocal() : dueDay;
    return DateTime(l.year, l.month, l.day, dueHour);
  }

  /// follow_up_at для варианта; null — без даты.
  static DateTime? atFor(FlagDue d, [DateTime? now]) {
    final dates = datesOf(d, now);
    return dates == null ? null : at(dates.due);
  }

  /// Срок с сервера Exchange («плавающая» дата — полночь UTC дня срока) —
  /// в follow_up_at: тот же календарный день, 18:00 по местному времени.
  static DateTime? fromServer(DateTime? due) {
    if (due == null) return null;
    final u = due.toUtc();
    return DateTime(u.year, u.month, u.day, dueHour);
  }

  /// Просрочен: день срока раньше сегодняшнего (не по часам — как в
  /// Outlook, флажок «Сегодня» вечером ещё не просрочен).
  static bool overdue(DateTime dueAt, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final l = dueAt.toLocal();
    return DateTime(l.year, l.month, l.day).isBefore(DateTime(n.year, n.month, n.day));
  }

  /// «Сегодня», «Завтра», «Вчера», «пт, 28 нояб.», «28 нояб.».
  static String label(DateTime dueAt, AppLocalizations l10n, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final l = dueAt.toLocal();
    final diff = DateTime(l.year, l.month, l.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    if (diff == 0) return l10n.tr('today');
    if (diff == 1) return l10n.tr('tomorrow');
    if (diff == -1) return l10n.tr('yesterday');
    if (diff > 1 && diff < 7) return DateFormat('EEE, d MMM', l10n.localeCode).format(l);
    return DateFormat('d MMM', l10n.localeCode).format(l);
  }
}

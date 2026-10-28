// lib/services/mail/later_service.dart
// «Посмотреть позже»: письмо откладывается на время (через час, завтра, на
// следующей неделе…) или без даты. Отложенное с датой в срок возвращается:
// снова непрочитанное (и на сервере), приходит уведомление; до открытия оно
// отмечено «Вернулось». Список отложенных — фильтр «Позже» и «Мой день».
//
// Хранение — emails.later_state + emails.remind_at (срок). Уведомление
// планируется в ОС заранее (EmailActionsService.setLater) и приходит даже при
// выгруженном приложении; «непрочитанное» ставится при ближайшем запуске или
// фоновой синхронизации (returnDue).

class LaterState {
  static const none = 0;
  static const waiting = 1;
  static const returned = 2;
}

/// Вариант быстрого выбора: подпись — ключ перевода, [at] — срок
/// (null — «Без даты»).
class LaterOption {
  final String key;
  final DateTime? at;
  const LaterOption(this.key, this.at);
}

class LaterService {
  /// Утренний час для «Завтра», «Послезавтра», «На следующей неделе».
  static const morningHour = 9;

  /// Быстрые варианты от момента [now]. «На следующей неделе» — понедельник
  /// следующей недели (в понедельник — через неделю), 9:00.
  static List<LaterOption> options(DateTime now) {
    DateTime morning(int addDays) => DateTime(now.year, now.month, now.day + addDays, morningHour);
    final toMonday = (DateTime.monday - now.weekday + 7) % 7;
    return [
      LaterOption('laterIn1h', _roundUp(now.add(const Duration(hours: 1)))),
      LaterOption('laterIn3h', _roundUp(now.add(const Duration(hours: 3)))),
      LaterOption('laterTomorrow', morning(1)),
      LaterOption('laterDayAfter', morning(2)),
      LaterOption('laterNextWeek', morning(toMonday == 0 ? 7 : toMonday)),
      const LaterOption('laterNoDate', null),
    ];
  }

  /// До ближайших 5 минут вверх: «14:05», а не «14:03:27».
  static DateTime _roundUp(DateTime t) {
    final m = t.minute % 5;
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    return m == 0 && t.second == 0 ? base : base.add(Duration(minutes: 5 - m));
  }
}

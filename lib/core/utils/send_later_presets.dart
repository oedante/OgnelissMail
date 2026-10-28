// lib/core/utils/send_later_presets.dart
// Быстрые варианты «Отправить позже» (1.6.49, как «Отложенное сообщение» в
// Telegram): удержание «Отправить» — меню над кнопкой, те же варианты —
// чипами в шторке выбора даты и времени.
//
//   · через час (к ближайшим 5 минутам вверх);
//   · сегодня в 18:00 — если до вечера ещё не меньше полутора часов;
//   · завтра в 9:00;
//   · в понедельник в 9:00 — с пятницы по воскресенье (письмо к началу
//     рабочей недели, а не в выходные).

class LaterPreset {
  /// Ключ строки: inHour, evening, tomorrow, monday.
  final String key;
  final DateTime at;
  const LaterPreset(this.key, this.at);

  @override
  String toString() => '$key@$at';
}

abstract final class SendLaterPresets {
  static const morningHour = 9;
  static const eveningHour = 18;

  /// Ключ строки «{время}» для меню: schedInHour, schedEvening…
  static String labelKey(LaterPreset p) => switch (p.key) {
        'inHour' => 'schedInHour',
        'evening' => 'schedEvening',
        'tomorrow' => 'schedTomorrow',
        _ => 'schedMonday',
      };

  static DateTime _up5(DateTime t) {
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    final extra = (5 - t.minute % 5) % 5;
    return base.add(Duration(minutes: extra));
  }

  static List<LaterPreset> of(DateTime now) {
    final out = <LaterPreset>[LaterPreset('inHour', _up5(now.add(const Duration(hours: 1))))];
    final evening = DateTime(now.year, now.month, now.day, eveningHour);
    if (evening.difference(now) >= const Duration(minutes: 90)) out.add(LaterPreset('evening', evening));
    // Через конструктор, а не add(Duration(days: 1)): при переходе на летнее
    // время сутки короче и «завтра в 9» стало бы 10:00.
    out.add(LaterPreset('tomorrow', DateTime(now.year, now.month, now.day + 1, morningHour)));
    if (now.weekday >= DateTime.friday) {
      out.add(LaterPreset('monday', DateTime(now.year, now.month, now.day + 8 - now.weekday, morningHour)));
    }
    return out;
  }
}

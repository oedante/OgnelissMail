// lib/services/calendar/event_reminders.dart
// Несколько напоминаний у встречи (1.7.2+110, просьба владельца 24.10.2026:
// «обычно можно ставить несколько напоминаний, а у нас только один период»).
//
// Хранение — колонка remindersJson: [{"minutesBefore": 15}, {"minutesBefore":
// 1440, "local": true}]. Планировщик уведомлений берёт все минуты
// (`ReminderSchedulerService.remindersOf`), лишние ключи ему не мешают.
//
// Сервер:
//  · CalDAV (Google, Яндекс, Mail.ru, Yahoo) хранит несколько VALARM — уходят
//    все напоминания, отметок нет;
//  · Exchange (ActiveSync и EWS) хранит одно напоминание у встречи — уходит
//    ближайшее к началу (его покажет и Outlook), остальные помечаются
//    "local": true и звучат только на этом телефоне. Синхронизация приносит
//    одно серверное напоминание — помеченные остаются ([merge]); раньше она
//    затирала всё, что было задано на телефоне.
//  · Напоминания из карточки встречи (без отправки на сервер) — все с
//    отметкой: это настройка телефона, синхронизация её не трогает. «Без
//    напоминания» там — [{"local": true}] (запись без минут).

import 'dart:convert';

class EventReminders {
  EventReminders._();

  /// Варианты выбора (минуты до начала): в момент начала, 5, 10, 15, 30 мин,
  /// 1 и 2 ч, 1 и 2 дня, неделя — как в календарях Google и Samsung.
  static const presets = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];

  /// Больше пяти напоминаний у одной встречи не бывает нужно.
  static const max = 5;

  /// Без повторов и отрицательных, по возрастанию (ближайшее к началу —
  /// первым: оно и уходит на сервер Exchange).
  static List<int> normalize(Iterable<int> minutes) => (minutes.where((m) => m >= 0).toSet().toList()..sort());

  /// JSON для встречи, сохраняемой на сервер. [serverKeepsAll] — сервер
  /// хранит все напоминания (CalDAV) или сервера нет (встреча только на
  /// телефоне): отметки не нужны. Пустой список — явно «без напоминаний».
  static String encode(Iterable<int> minutes, {required bool serverKeepsAll}) {
    final list = normalize(minutes);
    return jsonEncode([
      for (var i = 0; i < list.length; i++)
        {'minutesBefore': list[i], if (!serverKeepsAll && i > 0) 'local': true},
    ]);
  }

  /// Напоминания, заданные в карточке встречи, — только для этого телефона.
  static String encodePhoneOnly(Iterable<int> minutes) {
    final list = normalize(minutes);
    if (list.isEmpty) return jsonEncode([{'local': true}]);
    return jsonEncode([for (final m in list) {'minutesBefore': m, 'local': true}]);
  }

  /// Записи JSON: минуты (null — запись без минут) и отметка «только телефон».
  /// null — JSON нет или он не читается.
  static List<({int? minutes, bool local})>? entries(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final list = jsonDecode(json);
      if (list is! List) return null;
      return [
        for (final e in list)
          if (e is Map)
            (
              minutes: (e['minutesBefore'] as num?)?.toInt(),
              local: e['local'] == true,
            ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Напоминания встречи после синхронизации: [server] — что прислал сервер,
  /// [existing] — что было на телефоне.
  ///  · На телефоне своё (все записи с отметкой, из карточки встречи) — оно
  ///    и остаётся.
  ///  · Сервер ничего не прислал — остаётся, что было.
  ///  · Иначе — серверные и сверху телефонные с отметкой (кроме совпавших).
  static String? merge(List<int> server, String? existing) {
    final old = entries(existing);
    if (old != null && old.isNotEmpty && old.every((e) => e.local)) return existing;
    final s = normalize(server);
    if (s.isEmpty) return existing;
    final extra = normalize([
      for (final e in old ?? const <({int? minutes, bool local})>[])
        if (e.local && e.minutes != null && !s.contains(e.minutes)) e.minutes!,
    ]);
    return jsonEncode([
      for (final m in s) {'minutesBefore': m},
      for (final m in extra) {'minutesBefore': m, 'local': true},
    ]);
  }
}

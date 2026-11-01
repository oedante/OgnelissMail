// lib/features/tasks/task_quick_parser.dart
// Быстрое добавление напоминания одной строкой, как в Microsoft To Do и
// Todoist: «Позвонить Иванову завтра в 15:00 !» → задача «Позвонить
// Иванову», срок и напоминание завтра в 15:00, важная.
//
// Понимает (ru/en): сегодня/завтра/послезавтра, дни недели («в пятницу»),
// время («в 15:00», «в 9», «15:30»), «через N минут/часов/дней», «!» —
// важная, «каждый день/неделю/месяц» — повтор. Распознанные слова из
// названия убираются. Ничего не распознано — строка целиком в название.
// Даты и время с 1.9.x разбирает общий DatePhrase (им же пользуются
// календарь и даты в тексте письма).

import '../../core/utils/date_phrase.dart';
import '../../data/models/task_model.dart';

class ParsedTask {
  final String title;
  /// Срок: дата (полночь) или дата со временем.
  final DateTime? due;
  final DateTime? reminder;
  final bool important;
  final int repeat;
  const ParsedTask({
    required this.title,
    this.due,
    this.reminder,
    this.important = false,
    this.repeat = TaskRepeat.none,
  });

  bool get hasExtras => due != null || reminder != null || important || repeat != TaskRepeat.none;
}

class TaskQuickParser {
  TaskQuickParser._();

  static ParsedTask parse(String input, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var text = ' ${input.trim()} ';
    var important = false;
    var repeat = TaskRepeat.none;

    // Первое подходящее совпадение вырезается из текста.
    String cut(RegExp re, void Function(RegExpMatch m) onMatch) {
      final m = re.firstMatch(text);
      if (m == null) return text;
      onMatch(m);
      return text.replaceRange(m.start, m.end, ' ');
    }

    // Важная: «!» отдельным словом или в конце.
    text = cut(RegExp(r'\s!{1,3}(?=\s)'), (_) => important = true);

    // Повтор.
    text = cut(RegExp(r'\s(каждый день|ежедневно|every day|daily)(?=\s)', caseSensitive: false),
        (_) => repeat = TaskRepeat.daily);
    text = cut(RegExp(r'\s(по будням|every weekday|weekdays)(?=\s)', caseSensitive: false),
        (_) => repeat = TaskRepeat.weekdays);
    text = cut(RegExp(r'\s(каждую неделю|еженедельно|every week|weekly)(?=\s)', caseSensitive: false),
        (_) => repeat = TaskRepeat.weekly);
    text = cut(RegExp(r'\s(каждый месяц|ежемесячно|every month|monthly)(?=\s)', caseSensitive: false),
        (_) => repeat = TaskRepeat.monthly);
    text = cut(RegExp(r'\s(каждый год|ежегодно|every year|yearly)(?=\s)', caseSensitive: false),
        (_) => repeat = TaskRepeat.yearly);

    // Дата и время — общий разбор фраз (core/utils/date_phrase.dart, 1.9.x):
    // тот же, что у встречи одной фразой и дат в тексте письма.
    final p = DatePhrase.parse(text, now: n);
    // «через 2 часа» — напоминание без срока.
    DateTime? reminder = p.offsetMinutes == null ? null : n.add(Duration(minutes: p.offsetMinutes!));

    // «Напомни …» в начале — служебное слово.
    text = ' ${p.rest} '.replaceFirst(RegExp(r'^\s*(напомни(ть)?( мне)?|remind me( to)?)\s+', caseSensitive: false), ' ');

    DateTime? due;
    final date = p.day;
    final hour = p.hour;
    if (date != null || hour != null) {
      final base = date ?? DateTime(n.year, n.month, n.day);
      if (hour != null) {
        var dt = DateTime(base.year, base.month, base.day, hour, p.minute);
        // «в 9» без даты, а 9 уже прошло — завтра (календарём, не сутками).
        if (date == null && !dt.isAfter(n)) dt = DateTime(dt.year, dt.month, dt.day + 1, dt.hour, dt.minute);
        due = dt;
        reminder ??= dt; // со временем — напомнить в это время
      } else {
        due = base;
      }
    }

    var title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Хвостовые предлоги после вырезания («позвонить в» → «позвонить»).
    title = title.replaceFirst(RegExp(r'\s+(в|во|на|к|до|at|on|by)$', caseSensitive: false), '');
    if (title.isEmpty) title = input.trim();
    return ParsedTask(title: title, due: due, reminder: reminder, important: important, repeat: repeat);
  }
}

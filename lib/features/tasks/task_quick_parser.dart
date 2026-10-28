// lib/features/tasks/task_quick_parser.dart
// Быстрое добавление напоминания одной строкой, как в Microsoft To Do и
// Todoist: «Позвонить Иванову завтра в 15:00 !» → задача «Позвонить
// Иванову», срок и напоминание завтра в 15:00, важная.
//
// Понимает (ru/en): сегодня/завтра/послезавтра, дни недели («в пятницу»),
// время («в 15:00», «в 9», «15:30»), «через N минут/часов/дней», «!» —
// важная, «каждый день/неделю/месяц» — повтор. Распознанные слова из
// названия убираются. Ничего не распознано — строка целиком в название.

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

  static const _weekdaysRu = {
    'понедельник': 1, 'вторник': 2, 'среду': 3, 'среда': 3, 'четверг': 4,
    'пятницу': 5, 'пятница': 5, 'субботу': 6, 'суббота': 6,
    'воскресенье': 7,
  };
  static const _weekdaysEn = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  /// «первого» … «двенадцатого» — для «пол десятого» (9:30).
  static const _ordinals = {
    'первого': 1, 'второго': 2, 'третьего': 3, 'четвертого': 4, 'пятого': 5, 'шестого': 6,
    'седьмого': 7, 'восьмого': 8, 'девятого': 9, 'десятого': 10, 'одиннадцатого': 11, 'двенадцатого': 12,
  };
  static const _ordinalAlt =
      'первого|второго|третьего|четв[её]ртого|пятого|шестого|седьмого|восьмого|девятого|десятого|одиннадцатого|двенадцатого';

  /// Часы словами: «в десять утра», «без четверти десять».
  static const _cardinals = {
    'один': 1, 'два': 2, 'три': 3, 'четыре': 4, 'пять': 5, 'шесть': 6, 'семь': 7,
    'восемь': 8, 'девять': 9, 'десять': 10, 'одиннадцать': 11, 'двенадцать': 12,
  };
  static const _cardinalAlt = 'одиннадцать|двенадцать|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять';

  static ParsedTask parse(String input, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var text = ' ${input.trim()} ';
    DateTime? date;
    int? hour;
    int minute = 0;
    DateTime? reminder;
    var important = false;
    var repeat = TaskRepeat.none;
    var evening = false;

    // Первое подходящее совпадение вырезается из текста; [accept] отсеивает
    // ложные (тогда берётся следующее).
    String cut(RegExp re, void Function(RegExpMatch m) onMatch, {bool Function(RegExpMatch m)? accept}) {
      for (final m in re.allMatches(text)) {
        if (accept != null && !accept(m)) continue;
        onMatch(m);
        return text.replaceRange(m.start, m.end, ' ');
      }
      return text;
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

    // «через 2 часа», «через 30 минут», «через 3 дня», «in 2 hours».
    text = cut(
        RegExp(r'\s(?:через|in)\s+(\d{1,3})\s*(мин[а-яё]*|min\w*|час[а-яё]*|ч|hours?|h|дн[а-яё]*|день|days?|d)(?=\s)',
            caseSensitive: false), (m) {
      final k = int.parse(m.group(1)!);
      final unit = m.group(2)!.toLowerCase();
      if (unit.startsWith('мин') || unit.startsWith('min')) {
        reminder = n.add(Duration(minutes: k));
      } else if (unit.startsWith('ч') || unit.startsWith('h')) {
        reminder = n.add(Duration(hours: k));
      } else {
        date = DateTime(n.year, n.month, n.day + k);
      }
    });

    // Дата словом.
    text = cut(RegExp(r'\s(послезавтра|day after tomorrow)(?=\s)', caseSensitive: false),
        (_) => date = DateTime(n.year, n.month, n.day + 2));
    text = cut(RegExp(r'\s(завтра|tomorrow)(?=\s)', caseSensitive: false),
        (_) => date = DateTime(n.year, n.month, n.day + 1));
    text = cut(RegExp(r'\s(сегодня|today)(?=\s)', caseSensitive: false),
        (_) => date = DateTime(n.year, n.month, n.day));
    // «вечером», «tonight» — отдельно: «сегодня вечером в 8», «завтра вечером».
    text = cut(RegExp(r'\s(tonight|вечером|in the evening)(?=\s)', caseSensitive: false), (_) {
      date ??= DateTime(n.year, n.month, n.day);
      evening = true;
    });

    // День недели: «в пятницу», «on friday», «пятница».
    text = cut(
        RegExp(r'\s(?:(?:в|во|on)\s+)?(понедельник|вторник|среду|среда|четверг|пятницу|пятница|субботу|суббота|воскресенье|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=\s)',
            caseSensitive: false), (m) {
      final w = m.group(1)!.toLowerCase();
      final wd = _weekdaysRu[w] ?? _weekdaysEn[w]!;
      var add = (wd - n.weekday) % 7;
      if (add <= 0) add += 7; // «в пятницу» в пятницу — следующая
      date = DateTime(n.year, n.month, n.day + add);
    });

    // Время словами (до чисел: «пол десятого» не должно стать датой):
    // «пол десятого», «в половине десятого» — 9:30; «в четверть десятого» —
    // 9:15; «без четверти десять», «без пятнадцати 10» — 9:45; «в полдень».
    text = cut(
        RegExp(r'\s(?:в\s+)?(?:пол|полов[иу]н[аеу])[\s-]*(' + _ordinalAlt + r')(?=\s)', caseSensitive: false),
        (m) {
      hour = _ordinals[m.group(1)!.toLowerCase().replaceAll('ё', 'е')]! - 1;
      minute = 30;
    });
    if (hour == null) {
      text = cut(RegExp(r'\s(?:в\s+)?четверть\s+(' + _ordinalAlt + r')(?=\s)', caseSensitive: false), (m) {
        hour = _ordinals[m.group(1)!.toLowerCase().replaceAll('ё', 'е')]! - 1;
        minute = 15;
      });
    }
    if (hour == null) {
      text = cut(
          RegExp(r'\s(?:в\s+)?без\s+(четверти|пятнадцати|двадцати|десяти|пяти)\s+(\d{1,2}|' + _cardinalAlt + r')(?=\s)',
              caseSensitive: false), (m) {
        final h = int.tryParse(m.group(2)!) ?? _cardinals[m.group(2)!.toLowerCase()]!;
        const off = {'четверти': 15, 'пятнадцати': 15, 'двадцати': 20, 'десяти': 10, 'пяти': 5};
        hour = (h + 23) % 24;
        minute = 60 - off[m.group(1)!.toLowerCase()]!;
      });
    }
    if (hour == null) {
      text = cut(RegExp(r'\s(?:в\s+)?(полдень|noon|полночь|midnight)(?=\s)', caseSensitive: false), (m) {
        final w = m.group(1)!.toLowerCase();
        hour = (w == 'полдень' || w == 'noon') ? 12 : 0;
      });
    }

    // Дата числом: 12.10, 12.10.2026, 12/10. Невозможная дата («9.30») и
    // число после «в» («в 9.30») не вырезаются — это время.
    text = cut(RegExp(r'(?<=[\s(])(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?(?=[\s),;!?])'), (m) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = m.group(3) == null ? n.year : int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      var dt = DateTime(y, mo, d);
      if (m.group(3) == null && dt.isBefore(DateTime(n.year, n.month, n.day))) {
        dt = DateTime(y + 1, mo, d);
      }
      date = dt;
    }, accept: (m) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final before = text.substring(0, m.start);
      final afterPrep = m.group(3) == null && RegExp(r'\s(в|во|к|at)\s*$', caseSensitive: false).hasMatch(before);
      return !afterPrep && mo >= 1 && mo <= 12 && d >= 1 && d <= 31;
    });

    // Время числом: «в 15:00», «в 9.30», «в 9», «в 10 утра», «в 3 дня»,
    // «в 9 часов», «в десять вечера», «at 3pm», «15:30», «10 утра».
    if (hour == null) {
      text = cut(
          // ignore: prefer_interpolation_to_compose_strings
          RegExp(r'\s(?:(в|во|к|at)\s+)?(\d{1,2}|' + _cardinalAlt + r')(?:[:.](\d{2}))?'
              r'(\s*(?:часов|часам|часа|час|ч)\.?)?(?:\s*(am|pm|утра|дня|вечера|ночи))?(?=[\s),;!?])',
              caseSensitive: false), (m) {
        var h = int.tryParse(m.group(2)!) ?? _cardinals[m.group(2)!.toLowerCase()]!;
        final mi = int.tryParse(m.group(3) ?? '') ?? 0;
        final ap = m.group(5)?.toLowerCase();
        if ((ap == 'pm' || ap == 'вечера' || ap == 'дня') && h < 12) h += 12;
        if ((ap == 'am' || ap == 'ночи' || ap == 'утра') && h == 12) h = 0;
        hour = h;
        minute = mi;
      }, accept: (m) {
        final h = int.tryParse(m.group(2)!) ?? _cardinals[m.group(2)!.toLowerCase()];
        final mi = int.tryParse(m.group(3) ?? '') ?? 0;
        if (h == null || h > 23 || mi > 59) return false;
        // Голое число («купить 2 хлеба») — не время: нужен предлог, минуты,
        // «часов» или «утра/вечера».
        return m.group(1) != null || m.group(3) != null || m.group(4) != null || m.group(5) != null;
      });
    }
    // «утром», «днём» без точного часа.
    text = cut(RegExp(r'\s(утром|днём|днем|in the morning|in the afternoon)(?=\s)', caseSensitive: false), (m) {
      final w = m.group(1)!.toLowerCase();
      hour ??= (w == 'утром' || w == 'in the morning') ? 9 : 14;
    });

    // «вечером»: без часа — 19:00, «вечером в 8» — 20:00.
    if (evening) {
      if (hour == null) {
        hour = 19;
      } else if (hour! < 12) {
        hour = hour! + 12;
      }
    }

    // «Напомни …» в начале — служебное слово.
    text = text.replaceFirst(RegExp(r'^\s*(напомни(ть)?( мне)?|remind me( to)?)\s+', caseSensitive: false), ' ');

    DateTime? due;
    if (date != null || hour != null) {
      final base = date ?? DateTime(n.year, n.month, n.day);
      if (hour != null) {
        var dt = DateTime(base.year, base.month, base.day, hour!, minute);
        // «в 9» без даты, а 9 уже прошло — завтра.
        if (date == null && !dt.isAfter(n)) dt = dt.add(const Duration(days: 1));
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

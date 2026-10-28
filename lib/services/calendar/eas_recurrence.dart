// lib/services/calendar/eas_recurrence.dart
// Развёртка повторяющихся событий ActiveSync в отдельные вхождения.
//
// EWS отдаёт календарь через CalendarView — сервер сам разворачивает серии.
// В ActiveSync приходит ОДИН элемент с правилом (MS-ASCAL, Recurrence), и
// без развёртки ежедневная планёрка показывалась бы только в день первого
// вхождения. Здесь — чистая функция без зависимостей, покрыта тестом
// test/unit/eas_recurrence_test.dart.

/// Одно вхождение серии.
class EasOccurrence {
  /// Исходное (по правилу) начало вхождения — ключ для сопоставления с
  /// исключениями и для идентификатора вхождения.
  final DateTime originalStart;
  final DateTime start;
  final DateTime end;
  /// Изменённые поля исключения (Subject, Location, ...), если вхождение
  /// было изменено отдельно от серии.
  final Map<String, String> overrides;

  const EasOccurrence({
    required this.originalStart,
    required this.start,
    required this.end,
    this.overrides = const {},
  });
}

class EasRecurrence {
  /// Развернуть серию.
  ///
  /// [start]/[end] — первое вхождение (локальное время). [rule] — ключи без
  /// префикса «Recurrence_»: Type, Interval, Until, Occurrences, DayOfWeek,
  /// DayOfMonth, WeekOfMonth, MonthOfYear. [exceptions] — ExceptionStartTime,
  /// Deleted и изменённые поля. Возвращает вхождения, пересекающие окно
  /// [windowStart, windowEnd], не больше [maxCount].
  static List<EasOccurrence> expand({
    required DateTime start,
    required DateTime end,
    required Map<String, String> rule,
    List<Map<String, String>> exceptions = const [],
    required DateTime windowStart,
    required DateTime windowEnd,
    int maxCount = 500,
  }) {
    final type = int.tryParse(rule['Type'] ?? '') ?? -1;
    final interval = (int.tryParse(rule['Interval'] ?? '') ?? 1).clamp(1, 1000);
    final occurrences = int.tryParse(rule['Occurrences'] ?? '');
    final until = _parse(rule['Until']);
    final dowMask = int.tryParse(rule['DayOfWeek'] ?? '') ?? 0;
    final dom = int.tryParse(rule['DayOfMonth'] ?? '') ?? start.day;
    final wom = int.tryParse(rule['WeekOfMonth'] ?? '') ?? 1;
    final moy = int.tryParse(rule['MonthOfYear'] ?? '') ?? start.month;
    final duration = end.difference(start);

    // Исключения по дате исходного вхождения.
    final exByDay = <String, Map<String, String>>{};
    for (final e in exceptions) {
      final t = _parse(e['ExceptionStartTime']);
      if (t != null) exByDay[_dayKey(t.toLocal())] = e;
    }

    // Дата вхождения → то же время суток, что у первого.
    DateTime at(DateTime d) =>
        DateTime(d.year, d.month, d.day, start.hour, start.minute, start.second);

    final dates = <DateTime>[];
    // Жёсткий предел перебора — защита от «бесконечных» серий.
    final hardEnd = until != null && until.isBefore(windowEnd) ? until.toLocal() : windowEnd;
    var produced = 0;

    // Возвращает false, когда перебор пора заканчивать.
    bool accept(DateTime occ) {
      if (occ.isBefore(at(start))) return true; // до первого вхождения — пропуск
      // Until — по дню, а не «+1 сутки»: Exchange присылает либо начало
      // последнего вхождения, либо полночь его дня. Прежний допуск в сутки
      // после разделения серии в Outlook («это и последующие») показывал
      // первое вхождение новой серии дважды.
      if (until != null && _date(occ).isAfter(_date(until.toLocal()))) return false;
      if (occurrences != null && produced >= occurrences) return false;
      produced++; // считаем и вхождения до окна — от этого зависит Occurrences
      if (occ.add(duration).isBefore(windowStart)) return true;
      dates.add(occ);
      return dates.length < maxCount;
    }

    switch (type) {
      case 0: // ежедневно (с маской дней недели — «по будням»)
        for (var d = _date(start); !d.isAfter(hardEnd); d = _addDays(d, dowMask != 0 ? 1 : interval)) {
          if (dowMask != 0 && !_hasDow(dowMask, d)) continue;
          if (!accept(at(d))) break;
        }
        break;
      case 1: // еженедельно по дням маски, каждые [interval] недель
        final mask = dowMask != 0 ? dowMask : _dowBit(start);
        final weekStart = _addDays(_date(start), -(start.weekday % 7)); // воскресенье
        outer:
        for (var w = weekStart; !w.isAfter(hardEnd); w = _addDays(w, 7 * interval)) {
          for (var i = 0; i < 7; i++) {
            final d = _addDays(w, i);
            if (!_hasDow(mask, d)) continue;
            if (d.isBefore(_date(start))) continue;
            if (d.isAfter(hardEnd)) break outer;
            if (!accept(at(d))) break outer;
          }
        }
        break;
      case 2: // ежемесячно, число месяца
        for (var m = 0;; m += interval) {
          final first = DateTime(start.year, start.month + m, 1);
          if (first.isAfter(hardEnd)) break;
          final d = DateTime(first.year, first.month, dom.clamp(1, _daysIn(first.year, first.month)));
          if (!accept(at(d))) break;
        }
        break;
      case 3: // ежемесячно, n-й день недели
        for (var m = 0;; m += interval) {
          final first = DateTime(start.year, start.month + m, 1);
          if (first.isAfter(hardEnd)) break;
          final d = _nthDow(first.year, first.month, wom, dowMask != 0 ? dowMask : _dowBit(start));
          if (d != null && !accept(at(d))) break;
        }
        break;
      case 5: // ежегодно, число месяца
        for (var y = 0;; y += interval) {
          final year = start.year + y;
          if (DateTime(year, moy, 1).isAfter(hardEnd)) break;
          final d = DateTime(year, moy, dom.clamp(1, _daysIn(year, moy)));
          if (!accept(at(d))) break;
        }
        break;
      case 6: // ежегодно, n-й день недели месяца
        for (var y = 0;; y += interval) {
          final year = start.year + y;
          if (DateTime(year, moy, 1).isAfter(hardEnd)) break;
          final d = _nthDow(year, moy, wom, dowMask != 0 ? dowMask : _dowBit(start));
          if (d != null && !accept(at(d))) break;
        }
        break;
      default:
        dates.add(at(start));
    }

    final out = <EasOccurrence>[];
    for (final d in dates) {
      final ex = exByDay[_dayKey(d)];
      var s = d;
      var e = d.add(duration);
      var overrides = const <String, String>{};
      if (ex != null) {
        if (ex['Deleted'] == '1') continue;
        s = _parse(ex['StartTime'])?.toLocal() ?? s;
        e = _parse(ex['EndTime'])?.toLocal() ?? s.add(duration);
        overrides = ex;
      }
      if (e.isBefore(windowStart) || s.isAfter(windowEnd)) continue;
      out.add(EasOccurrence(originalStart: d, start: s, end: e, overrides: overrides));
      if (out.length >= maxCount) break;
    }
    return out;
  }

  /// Ключ дня вхождения (для id вхождения и сопоставления исключений).
  static String dayKey(DateTime local) => _dayKey(local);

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Сдвиг по календарным дням (не по 24 часам — не ломается на переходе
  /// на летнее время).
  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  /// Бит дня недели по MS-ASCAL: воскресенье=1, понедельник=2, ... суббота=64.
  static int _dowBit(DateTime d) => 1 << (d.weekday % 7);
  static bool _hasDow(int mask, DateTime d) => (mask & _dowBit(d)) != 0;

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  /// n-й (1–4; 5 = последний) день месяца, подходящий под маску.
  static DateTime? _nthDow(int year, int month, int n, int mask) {
    final days = <DateTime>[
      for (var d = 1; d <= _daysIn(year, month); d++)
        if (_hasDow(mask, DateTime(year, month, d))) DateTime(year, month, d),
    ];
    if (days.isEmpty) return null;
    if (n >= 5) return days.last;
    return n - 1 < days.length ? days[n - 1] : null;
  }

  /// Дата EAS: ISO 8601 или компактная yyyyMMddTHHmmssZ.
  static DateTime? _parse(String? s) {
    if (s == null || s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})').firstMatch(s);
    if (m == null) return null;
    return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
        int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  }
}

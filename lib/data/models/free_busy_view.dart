// lib/data/models/free_busy_view.dart
// Результат запроса занятости (EWS MergedFreeBusy): статусы по равным интервалам
// начиная со startLocal. Статус: 0=свободен,1=под вопросом,2=занят,3=нет на месте,
// 4=нет данных. Объединённый вид по всем участникам (кто-то занят → интервал занят).

class FreeBusyView {
  final DateTime startLocal;
  final int intervalMinutes;
  final List<int> statuses; // по одному на интервал

  const FreeBusyView({
    required this.startLocal,
    required this.intervalMinutes,
    required this.statuses,
  });

  bool get isEmpty => statuses.isEmpty;

  /// Интервал занят (занят/под вопросом/нет на месте — т.е. не «свободен»/«нет данных»).
  bool _busyAt(int i) => statuses[i] == 1 || statuses[i] == 2 || statuses[i] == 3;

  /// Занятые окна как пары (начало, конец) в локальном времени.
  List<({DateTime start, DateTime end})> busyWindows() {
    final windows = <({DateTime start, DateTime end})>[];
    int? runStart;
    for (var i = 0; i < statuses.length; i++) {
      if (_busyAt(i)) {
        runStart ??= i;
      } else if (runStart != null) {
        windows.add((
          start: startLocal.add(Duration(minutes: runStart * intervalMinutes)),
          end: startLocal.add(Duration(minutes: i * intervalMinutes)),
        ));
        runStart = null;
      }
    }
    if (runStart != null) {
      windows.add((
        start: startLocal.add(Duration(minutes: runStart * intervalMinutes)),
        end: startLocal.add(Duration(minutes: statuses.length * intervalMinutes)),
      ));
    }
    return windows;
  }

  /// Свободные для всех окна длиной [length] (1.6.7, «Найти время» как
  /// помощник планирования Outlook): только рабочие дни с [fromHour] до
  /// [toHour], не раньше [notBefore]; в день — не больше [perDay] окон, не
  /// пересекающихся друг с другом; всего — не больше [max]. Интервал «нет
  /// данных» считается свободным, но окно целиком без данных не предлагается.
  List<DateTime> freeSlots(
    Duration length, {
    int fromHour = 8,
    int toHour = 18,
    DateTime? notBefore,
    int perDay = 3,
    int max = 9,
  }) {
    if (statuses.isEmpty || intervalMinutes <= 0) return const [];
    final need = (length.inMinutes / intervalMinutes).ceil().clamp(1, statuses.length);
    final out = <DateTime>[];
    DateTime? lastEnd;
    var dayCount = 0;
    int? day;
    for (var i = 0; i + need <= statuses.length && out.length < max; i++) {
      final s = startLocal.add(Duration(minutes: i * intervalMinutes));
      final e = s.add(length);
      if (notBefore != null && s.isBefore(notBefore)) continue;
      if (s.weekday > DateTime.friday || s.hour < fromHour) continue;
      if (e.isAfter(DateTime(s.year, s.month, s.day, toHour))) continue;
      final key = s.year * 10000 + s.month * 100 + s.day;
      if (key != day) {
        day = key;
        dayCount = 0;
      }
      if (dayCount >= perDay) continue;
      if (lastEnd != null && s.isBefore(lastEnd)) continue;
      var ok = true;
      var known = false;
      for (var k = i; k < i + need; k++) {
        if (_busyAt(k)) {
          ok = false;
          break;
        }
        if (statuses[k] == 0) known = true;
      }
      if (!ok || !known) continue;
      out.add(s);
      lastEnd = e;
      dayCount++;
    }
    return out;
  }

  /// Разобрать строку MergedFreeBusy (например "0022200…") в статусы.
  static List<int> parseMerged(String merged) =>
      merged.trim().split('').map((c) => int.tryParse(c) ?? 4).toList();

  /// Важность статуса при объединении: «нет на месте» > «занят» > «под
  /// вопросом» > «свободен» > «нет данных» (кто-то свободен, о другом данных
  /// нет — интервал свободен: «Найти время» его предложит).
  static const _rank = {'4': 0, '0': 1, '1': 2, '2': 3, '3': 4};

  /// Строки занятости нескольких людей — в одну: в каждом интервале самый
  /// «занятый» статус (1.6.49: у EWS раньше бралась строка только первого
  /// участника — «Найти время» не видело занятость остальных).
  static String mergeStrings(Iterable<String> strings) {
    final list = [for (final v in strings) if (v.trim().isNotEmpty) v.trim()];
    if (list.isEmpty) return '';
    final len = list.map((v) => v.length).reduce((a, b) => a > b ? a : b);
    final merged = StringBuffer();
    for (var i = 0; i < len; i++) {
      var best = '4';
      var bestRank = -1;
      for (final v in list) {
        if (i >= v.length) continue;
        final r = _rank[v[i]];
        if (r != null && r > bestRank) {
          bestRank = r;
          best = v[i];
        }
      }
      merged.write(best);
    }
    return merged.toString();
  }

  /// Статус одного человека на отрезке [from, to) по его строке [s] с
  /// началом [start] и шагом [intervalMinutes]: самый «занятый» из
  /// интервалов отрезка; null — данных нет (1.6.49, занятость переговорных).
  static int? statusFor(String s, DateTime start, int intervalMinutes, DateTime from, DateTime to) {
    if (s.isEmpty || intervalMinutes <= 0 || !to.isAfter(from)) return null;
    final first = (from.difference(start).inMinutes / intervalMinutes).floor();
    final last = (to.difference(start).inMinutes / intervalMinutes).ceil();
    int? best;
    for (var i = first < 0 ? 0 : first; i < last && i < s.length; i++) {
      final c = s[i];
      if (c == '4') continue;
      final r = _rank[c];
      if (r == null) continue;
      if (best == null || r > (_rank['$best'] ?? 0)) best = int.parse(c);
    }
    return best;
  }
}

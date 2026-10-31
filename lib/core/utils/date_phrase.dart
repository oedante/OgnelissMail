// lib/core/utils/date_phrase.dart
// Даты и время в обычном тексте — общий разбор (1.9.x, просьба владельца
// 31.10.2026): быстрый ввод задач («Позвонить завтра в 15»), встреча одной
// фразой в календаре («Созвон с Анной в пятницу в 15 на час») и даты в тексте
// письма, которые нажимаются, как у iOS.
//
// Раньше разбор жил только в быстром вводе задач (TaskQuickParser). Теперь
// здесь один сканер: правила находят в тексте «кусочки» —
//  · день: «сегодня», «завтра», «в пятницу», «next Monday», «31.10»,
//    «31.10.2026», «2026-10-31», «10/31» (порядок — по стране устройства),
//    «3 ноября 2026 г.», «Nov 3», «3. November», «3 novembre», «3 de
//    noviembre»;
//  · время: «в 15», «15:30», «в 9.30», «3 pm», «в 10 утра», «пол десятого»,
//    «без четверти десять», «в полдень», «15 Uhr», «15h30»;
//  · промежуток: «с 15 до 16», «15:00–16:30», «from 2 to 3pm»;
//  · длительность: «на час», «на 30 минут», «for 1 hour»;
//  · «через 2 часа», «in 3 days» и часть дня («вечером», «tonight»).
// Дальше два режима:
//  · [DatePhrase.parse] — фраза быстрого ввода: берётся первый кусочек
//    каждого вида, остальной текст — название;
//  · [DatePhrase.find] — текст письма: соседние кусочки (через пробел,
//    запятую, «в», «at») собираются в одно упоминание. Упоминание без
//    времени и без явной даты не считается: просто «завтра», число, версия
//    «1.9.0», цена, телефон, номер заказа — не даты.
// Всё считается от опорного момента — для письма это дата письма («завтра» —
// день после отправки), для ввода — сейчас; часовой пояс — устройства. Дни
// прибавляются календарём (DateTime(г, м, д + n)), а не сутками по 24 часа:
// переход на летнее время не сдвигает «завтра в 15» на 14:00 или 16:00.

/// Упоминание даты или времени в тексте ([DatePhrase.find]).
class DateMention {
  /// Где в тексте (начало и конец, как у substring).
  final int start;
  final int end;

  /// Начало; у дня без времени — полночь.
  final DateTime from;

  /// Конец: промежуток («с 15 до 16») или длительность («на час»); null —
  /// не указан.
  final DateTime? to;

  /// Указан только день, без времени.
  final bool allDay;

  const DateMention(this.start, this.end, this.from, {this.to, this.allDay = false});

  @override
  String toString() => 'DateMention($start–$end: $from${to == null ? '' : ' – $to'}${allDay ? ', весь день' : ''})';
}

/// Дата и время из фразы быстрого ввода ([DatePhrase.parse]).
class PhraseDate {
  /// День (полночь), если назван.
  final DateTime? day;
  final int? hour;
  final int minute;

  /// Конец промежутка («с 15 до 16»).
  final int? endHour;
  final int endMinute;

  /// «на час», «for 30 minutes».
  final int? durationMinutes;

  /// «через 2 часа», «in 30 minutes» — от момента ввода.
  final int? offsetMinutes;

  /// Час без минут и уточнений («в 3», «at 3»): утро это или день — не
  /// сказано (календарь считает «в 3» днём).
  final bool loneHour;

  /// Куски фразы, из которых взяты дата и время (начало, конец).
  final List<(int, int)> spans;

  /// Фраза без этих кусков, пробелы схлопнуты.
  final String rest;

  const PhraseDate({
    this.day,
    this.hour,
    this.minute = 0,
    this.endHour,
    this.endMinute = 0,
    this.durationMinutes,
    this.offsetMinutes,
    this.loneHour = false,
    this.spans = const [],
    required this.rest,
  });

  bool get found => spans.isNotEmpty;

  /// Конец последнего распознанного куска (0 — ничего не распознано).
  int get lastEnd => spans.fold(0, (a, s) => s.$2 > a ? s.$2 : a);
}

enum _K { day, weekday, date, time, range, part, duration, offset }

/// Кусочек: что найдено и где.
class _T {
  _T(
    this.k,
    this.s,
    this.e, {
    this.y,
    this.m,
    this.d,
    this.yearless = false,
    this.numeric = false,
    this.add,
    this.wd,
    this.h,
    this.mi = 0,
    this.h2,
    this.mi2 = 0,
    this.strong = false,
    this.part = 0,
    this.minutes,
    this.days,
  });

  final _K k;
  final int s;
  final int e;

  // День: число (год может не быть), «завтра» (+add), день недели.
  final int? y, m, d;
  final bool yearless;

  /// Числом (31.10, 10/31), а не словом месяца.
  final bool numeric;
  final int? add;
  final int? wd;

  // Время и промежуток.
  final int? h, h2;
  final int mi, mi2;

  /// Время названо явно (минуты, am/pm, «часов», «утра»), а не голым числом
  /// после предлога.
  final bool strong;

  /// Часть дня: 1 — утро, 2 — день, 3 — вечер.
  final int part;

  /// Длительность или «через N минут».
  final int? minutes;

  /// «через N дней».
  final int? days;

  int get len => e - s;

  _T _shift(int by) => _T(
    k,
    s + by,
    e + by,
    y: y,
    m: m,
    d: d,
    yearless: yearless,
    numeric: numeric,
    add: add,
    wd: wd,
    h: h,
    mi: mi,
    h2: h2,
    mi2: mi2,
    strong: strong,
    part: part,
    minutes: minutes,
    days: days,
  );
  bool get dateish => k == _K.day || k == _K.date || k == _K.weekday;
  bool get timeish => k == _K.time || k == _K.range;
}

class DatePhrase {
  DatePhrase._();

  // ───────────────────────── словари ─────────────────────────

  static const _months = <String, int>{
    // Русский — в родительном падеже («3 ноября») и сокращения.
    'января': 1, 'февраля': 2, 'марта': 3, 'апреля': 4, 'мая': 5, 'июня': 6, 'июля': 7,
    'августа': 8, 'сентября': 9, 'октября': 10, 'ноября': 11, 'декабря': 12,
    'янв': 1, 'фев': 2, 'февр': 2, 'мар': 3, 'апр': 4, 'июн': 6, 'июл': 7, 'авг': 8,
    'сен': 9, 'сент': 9, 'окт': 10, 'ноя': 11, 'нояб': 11, 'дек': 12,
    // Английский (и совпадающие немецкие: April, August, September, November).
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6, 'july': 7,
    'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9,
    'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    // Немецкий.
    'januar': 1, 'jänner': 1, 'februar': 2, 'märz': 3, 'mär': 3, 'mrz': 3, 'mai': 5, 'juni': 6,
    'juli': 7, 'oktober': 10, 'okt': 10, 'dezember': 12, 'dez': 12,
    // Французский.
    'janvier': 1, 'janv': 1, 'février': 2, 'fevrier': 2, 'févr': 2, 'mars': 3, 'avril': 4,
    'avr': 4, 'juin': 6, 'juillet': 7, 'juil': 7, 'août': 8, 'aout': 8, 'septembre': 9,
    'octobre': 10, 'novembre': 11, 'décembre': 12, 'decembre': 12, 'déc': 12,
    // Испанский.
    'enero': 1, 'ene': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'abr': 4, 'mayo': 5,
    'junio': 6, 'julio': 7, 'agosto': 8, 'ago': 8, 'septiembre': 9, 'setiembre': 9,
    'octubre': 10, 'noviembre': 11, 'diciembre': 12, 'dic': 12,
  };

  static const _weekdays = <String, int>{
    'понедельник': 1,
    'вторник': 2,
    'среду': 3,
    'среда': 3,
    'четверг': 4,
    'пятницу': 5,
    'пятница': 5,
    'субботу': 6,
    'суббота': 6,
    'воскресенье': 7,
    'monday': 1,
    'tuesday': 2,
    'wednesday': 3,
    'thursday': 4,
    'friday': 5,
    'saturday': 6,
    'sunday': 7,
  };

  /// «первого» … «двенадцатого» — для «пол десятого» (9:30).
  static const _ordinals = {
    'первого': 1,
    'второго': 2,
    'третьего': 3,
    'четвертого': 4,
    'пятого': 5,
    'шестого': 6,
    'седьмого': 7,
    'восьмого': 8,
    'девятого': 9,
    'десятого': 10,
    'одиннадцатого': 11,
    'двенадцатого': 12,
  };
  static const _ordinalAlt =
      'первого|второго|третьего|четв[её]ртого|пятого|шестого|седьмого|восьмого|девятого|десятого|одиннадцатого|двенадцатого';

  /// Часы словами: «в десять утра», «без четверти десять».
  static const _cardinals = {
    'один': 1,
    'два': 2,
    'три': 3,
    'четыре': 4,
    'пять': 5,
    'шесть': 6,
    'семь': 7,
    'восемь': 8,
    'девять': 9,
    'десять': 10,
    'одиннадцать': 11,
    'двенадцать': 12,
  };
  static const _cardinalAlt = 'одиннадцать|двенадцать|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять';

  static String _alt(Iterable<String> words) {
    final list = words.toSet().toList()..sort((a, b) => b.length - a.length);
    return list.map(RegExp.escape).join('|');
  }

  // Без unicode: true — с ним и без учёта регистра движок в разы медленнее
  // (рассылка в 100 тысяч знаков); буквы — явными диапазонами (латиница с
  // диакритикой и кириллица), регистр кириллицы движок сравнивает и так.
  static RegExp _re(String p) => RegExp(p, caseSensitive: false);

  static final String _monthAlt = _alt(_months.keys);
  static final String _wdAlt = _alt(_weekdays.keys);

  // Границы: не внутри слова или числа.
  static const _l0 = 'a-zà-öø-ÿа-яё0-9';
  static const _lb = r'(?<![a-zà-öø-ÿа-яё0-9])';
  static const _rb = r'(?![a-zà-öø-ÿа-яё0-9])';

  /// Перед числом даты — не буква, цифра, «№», точка, косая черта (номер
  /// заказа, версия, путь, IP-адрес).
  static const _nb = r'(?<![a-zà-öø-ÿа-яё0-9#№./,:+_-])';

  static const _ampm = r'am|pm|a\.m\.|p\.m\.';

  // ───────────────────────── правила ─────────────────────────

  static final _reDay = _re('$_lb(послезавтра|day\\s+after\\s+tomorrow|завтра|tomorrow|сегодня|today|tonight)$_rb');

  static final _rePart = _re(
    '$_lb(вечером|утром|дн[её]м|in\\s+the\\s+(?:evening|morning|afternoon)'
    '|this\\s+(?:evening|morning|afternoon))$_rb',
  );

  static final _reWeekday = _re('$_lb($_wdAlt)$_rb');

  // Предлоги и связки перед кусочком («в пятницу», «at 3pm», «с 15 до 16»)
  // ищутся не в самом правиле, а перед найденным ([_lead]): необязательное
  // слово в начале правила движок пробует на каждой букве текста — на
  // длинной рассылке это в разы медленнее.
  static final _leadWeekday = _re(
    '(?<![$_l0])(в|во|on|this|next|coming|this\\s+coming|в\\s+эт(?:у|от|о)'
    '|в\\s+следующ(?:ую|ий|ее)|в\\s+ближайш(?:ую|ий|ее))\\s+\$',
  );
  static final _leadTime = _re('(?<![$_l0])(в|во|к|at|um|à|a\\s+las|around|by)\\s+\$');
  static final _leadWord = _re('(?<![$_l0])(в|at)\\s+\$');
  static final _leadRange = _re('(?<![$_l0])(с|со|from|between|между|von|de|entre)\\s+\$');

  /// «3 ноября 2026 г.», «31 Oct», «1er novembre», «31 de octubre de 2026»,
  /// «3. November». День недели перед датой («пятница, 30 октября») —
  /// отдельный кусочек того же упоминания.
  static final _reDayMonth = _re(
    '$_lb(\\d{1,2})(?:-?(?:го|е|ое)|st|nd|rd|th|er|\\.)?'
    '\\s*(?:(?:de|of)\\s+)?($_monthAlt)(?:\\.(?=\\s*\\d))?'
    '(?:,?\\s*(?:de\\s+)?(\\d{4})(?:\\s*(?:г\\.?|года|год)(?![a-zà-öø-ÿа-яё]))?)?$_rb',
  );

  /// «Nov 3», «October 31st, 2026».
  static final _reMonthDay = _re(
    '$_lb($_monthAlt)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?'
    '(?![a-zà-öø-ÿа-яё0-9]|[:.][0-9])(?:,?\\s+(\\d{4})(?![0-9]))?',
  );

  /// 2026-10-31.
  static final _reIso = _re('$_nb(\\d{4})-(\\d{1,2})-(\\d{1,2})(?![0-9]|[-./:][0-9])');

  /// 31.10.2026, 31/10/26, 31-10-2026.
  static final _reDmy = _re('$_nb(\\d{1,2})([./-])(\\d{1,2})\\2(\\d{4}|\\d{2})(?![0-9]|[-./,:][0-9])');

  /// 31.10, 10/31 — без года.
  static final _reDm = _re('$_nb(\\d{1,2})([./])(\\d{1,2})(?![0-9]|[-./,:][0-9]|/)');

  /// 15:30, в 9:00, 3:30 pm, 15:00 Uhr.
  static final _reHm = _re(
    '(?<![a-zà-öø-ÿа-яё0-9:.,/])([01]?\\d|2[0-3]):([0-5]\\d)'
    '(?![0-9]|[:.,][0-9])(?:\\s*($_ampm)(?![a-zà-öø-ÿа-яё]))?(?:\\s*(?:uhr|ч\\.?)(?![a-zà-öø-ÿа-яё]))?',
  );

  /// «в 9.30» — точка вместо двоеточия только после предлога (иначе это
  /// дата или число).
  static final _reHdot = _re(
    '$_lb(в|во|к|at|um|à)\\s+(\\d{1,2})\\.(\\d{2})(?![0-9]|[.,][0-9])'
    '(?:\\s*($_ampm|утра|дня|вечера|ночи)(?![a-zà-öø-ÿа-яё]))?',
  );

  /// «15h30», «à 15h».
  static final _reHfr = _re('$_lb(\\d{1,2})h(\\d{2})?$_rb');

  /// «3 pm», «at 11am».
  static final _reAmPm = _re('(?<![a-zà-öø-ÿа-яё0-9:.,])(1[0-2]|0?[1-9])\\s*($_ampm)(?![a-zà-öø-ÿа-яё])');

  /// «в 15», «в 9 часов», «в 10 утра», «в десять вечера», «at 3», «um 15 Uhr».
  static final _rePrep = _re(
    '$_lb(в|во|к|at|um|à|a\\s+las)\\s+(\\d{1,2}|$_cardinalAlt)'
    "(?:\\s*(часов|часам|часа|час|ч\\.?|uhr|o['’]clock))?"
    '(?:\\s*(утра|дня|вечера|ночи|$_ampm))?(?![a-zà-öø-ÿа-яё0-9]|[:.,/][0-9])',
  );

  /// «15 Uhr», «3 o'clock», «10 утра».
  static final _reUnit = _re(
    "(?<![a-zà-öø-ÿа-яё0-9:.,])(\\d{1,2})\\s*(uhr|o['’]clock|утра|вечера|ночи)(?![a-zà-öø-ÿа-яё])",
  );

  static final _reHalf = _re('$_lb(?:пол|полов[иу]н[аеу])[\\s-]*($_ordinalAlt)$_rb');
  static final _reQuarter = _re('$_lb(?:четверть)\\s+($_ordinalAlt)$_rb');
  static final _reWithout = _re(
    '$_lb(?:без)\\s+(четверти|пятнадцати|двадцати|десяти|пяти)\\s+(\\d{1,2}|$_cardinalAlt)$_rb',
  );
  static final _reNoon = _re('$_lb(полдень|noon|полночь|midnight)$_rb');

  /// «с 15 до 16», «15:00–16:30», «from 2 to 3pm», «between 2 and 3 pm».
  static final _reRange = _re(
    '(?<![a-zà-öø-ÿа-яё0-9:.,/-])'
    '(\\d{1,2})(?::(\\d{2}))?(?:\\s*($_ampm))?'
    '(\\s*[-–—]\\s*|\\s+(?:до|to|till|until|and|и|bis|à|a|y)\\s+)'
    '(\\d{1,2})(?::(\\d{2}))?(?:\\s*($_ampm))?'
    '(?:\\s*(часов|часа|ч\\.?|uhr|h)(?![a-zà-öø-ÿа-яё]))?(?:\\s*(утра|дня|вечера|ночи))?(?![a-zà-öø-ÿа-яё0-9]|[:.,/][0-9])',
  );

  /// «на час», «на 30 минут», «на полтора часа», «for 1 hour».
  static final _reDuration = _re(
    '$_lb(?:на|for)\\s+(?:(\\d{1,3}(?:[.,]\\d{1,2})?)\\s*(минут[ауы]?|мин\\.?|minutes?|mins?'
    '|часа|часов|час|ч\\.?|hours?|hrs?|h)|(полчаса|полтора\\s+часа|час|half\\s+an\\s+hour|an\\s+hour|one\\s+hour))$_rb',
  );

  /// «через 2 часа», «через 3 дня», «через неделю», «in 30 minutes».
  static final _reOffset = _re(
    '$_lb(?:через|in)\\s+(?:(\\d{1,3})\\s*(мин[a-zà-öø-ÿа-яё]*|min[a-zà-öø-ÿа-яё]*|час[a-zà-öø-ÿа-яё]*|ч|hours?|hrs?|h'
    '|дн[a-zà-öø-ÿа-яё]*|день|days?|d|недел[a-zà-öø-ÿа-яё]*|weeks?)|(минуту|час|полчаса|день|неделю|an\\s+hour|half\\s+an\\s+hour'
    '|a\\s+day|a\\s+week))$_rb',
  );

  /// После голого числа — не время: «в 5 раз», «в 15 км», «at 3 people».
  static final _notTimeAfter = _re(
    '^\\s*(?:раз|лет|год|%|процент|руб|р\\.|₽|\\\$|€|£|км|кг|шт|чел|минут|мин|сек|дн'
    '|недел|месяц|тыс|млн|млрд|years?|times?|percent|people|days?|weeks?|months?|minutes?|mins?|hours?'
    '|seconds?|kg|km|pcs|eur|usd|rub)',
  );

  /// После числа даты — деньги и размеры («12.10 руб», «1.10 ГБ»).
  static final _moneyAfter = _re('^\\s*(?:руб|р\\.|₽|\\\$|€|£|eur|usd|rub|коп|%|гб|мб|кб|gb|mb|kb|kg|кг|км|km)');
  static final _moneyBefore = _re('[\$€£₽]\\s*\$');

  /// Перед числом даты без года — слово, по которому видно, что это дата
  /// («до 15.11», «с 1.11», «by 10/31»).
  static final _dateContext = _re(
    '(?:^|[^a-zà-öø-ÿа-яё])(?:до|с|со|по|к|на|от|за|срок|on|by|until|till|from|since|due'
    '|before|after|deadline)[\\s:]*\$',
  );

  /// Между кусочками одного упоминания — пробелы, запятые, тире, скобки и
  /// связки «в», «at», «on», «am» («Friday, Oct 30, 2026 at 3:15 PM»,
  /// «31 октября 2026 г., в 15:00»).
  static final _gap = _re(
    '^(?:[\\s,;()–—-]|(?:в|во|at|on|um|am|le|el|à)(?![a-zà-öø-ÿа-яё])|г\\.|года(?![a-zà-öø-ÿа-яё]))*\$',
  );

  // ───────────────────────── сканер ─────────────────────────

  /// Есть ли в тексте цифра (без неё в письме дат не ищем — быстро).
  static bool mayContain(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) return true;
    }
    return false;
  }

  static bool _validDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2200) return false;
    final dt = DateTime(y, m, d);
    return dt.month == m && dt.day == d;
  }

  static int _year(String s) {
    final v = int.parse(s);
    return s.length == 2 ? 2000 + v : v;
  }

  /// am/pm, «утра», «вечера», «дня», «ночи» — к 24 часам.
  static int _apply(int h, String? suffix) {
    final s = suffix?.toLowerCase().replaceAll('.', '');
    if (s == null) return h;
    if ((s == 'pm' || s == 'вечера' || s == 'дня') && h < 12) return h + 12;
    if ((s == 'am' || s == 'ночи' || s == 'утра') && h == 12) return 0;
    return h;
  }

  /// Предлог перед кусочком ([_leadTime] и др.): новое начало кусочка и
  /// сам предлог (null — предлога нет).
  static (int, String?) _lead(String text, int start, RegExp re) {
    final from = start < 24 ? 0 : start - 24;
    final m = re.firstMatch(text.substring(from, start));
    return m == null ? (start, null) : (from + m.start, m.group(1)!.toLowerCase());
  }

  static int? _hourWord(String w) => int.tryParse(w) ?? _cardinals[w.toLowerCase()];

  static List<_T> _scan(String text, {required bool phrase, required bool monthFirst}) {
    final out = <_T>[];
    String after(int end) => text.substring(end, end + 16 > text.length ? text.length : end + 16);
    String before(int start) => text.substring(start < 16 ? 0 : start - 16, start);

    for (final m in _reDay.allMatches(text)) {
      final w = m.group(1)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final add = switch (w) {
        'послезавтра' || 'day after tomorrow' => 2,
        'завтра' || 'tomorrow' => 1,
        _ => 0,
      };
      out.add(_T(_K.day, m.start, m.end, add: add, part: w == 'tonight' ? 3 : 0));
    }
    for (final m in _rePart.allMatches(text)) {
      final w = m.group(1)!.toLowerCase();
      final part = w == 'утром' || w.endsWith('morning') ? 1 : (w.startsWith('дн') || w.endsWith('afternoon') ? 2 : 3);
      out.add(_T(_K.part, m.start, m.end, part: part));
    }
    for (final m in _reWeekday.allMatches(text)) {
      out.add(_T(_K.weekday, _lead(text, m.start, _leadWeekday).$1, m.end, wd: _weekdays[m.group(1)!.toLowerCase()]));
    }

    // Дни месяца словами.
    for (final m in _reDayMonth.allMatches(text)) {
      final d = int.parse(m.group(1)!);
      final mo = _months[m.group(2)!.toLowerCase()];
      final y = m.group(3) == null ? null : int.parse(m.group(3)!);
      if (mo == null || !_validDate(y ?? 2000, mo, d)) continue;
      out.add(_T(_K.date, m.start, m.end, y: y, m: mo, d: d, yearless: y == null));
    }
    for (final m in _reMonthDay.allMatches(text)) {
      final mo = _months[m.group(1)!.toLowerCase()];
      final d = int.parse(m.group(2)!);
      final y = m.group(3) == null ? null : int.parse(m.group(3)!);
      if (mo == null || !_validDate(y ?? 2000, mo, d)) continue;
      out.add(_T(_K.date, m.start, m.end, y: y, m: mo, d: d, yearless: y == null));
    }

    // Дни числом.
    for (final m in _reIso.allMatches(text)) {
      final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
      if (!_validDate(y, mo, d)) continue;
      out.add(_T(_K.date, m.start, m.end, y: y, m: mo, d: d, numeric: true));
    }
    (int, int)? dayMonth(int a, int b, String sep) {
      // Косая черта: «месяц/день» в США, иначе «день/месяц»; невозможное
      // («10/31» у «день/месяц») — меняется местами.
      var (d, mo) = sep == '/' && monthFirst ? (b, a) : (a, b);
      if (mo > 12 && d <= 12) (d, mo) = (mo, d);
      return mo >= 1 && mo <= 12 && d >= 1 && d <= 31 ? (d, mo) : null;
    }

    bool money(int s, int e) => _moneyAfter.hasMatch(after(e)) || _moneyBefore.hasMatch(before(s));
    for (final m in _reDmy.allMatches(text)) {
      final sep = m.group(2)!;
      final ys = m.group(4)!;
      if (sep == '-' && ys.length != 4) continue; // 12-34-56 — телефон
      final dm = dayMonth(int.parse(m.group(1)!), int.parse(m.group(3)!), sep);
      if (dm == null) continue;
      final y = _year(ys);
      if (!_validDate(y, dm.$2, dm.$1) || money(m.start, m.end)) continue;
      out.add(_T(_K.date, m.start, m.end, y: y, m: dm.$2, d: dm.$1, numeric: true));
    }
    for (final m in _reDm.allMatches(text)) {
      final sep = m.group(2)!;
      final mStr = m.group(3)!;
      // В письме месяц — двумя цифрами («31.10», «5.11»): «1.5», «2.5» —
      // скорее числа, версии и размеры.
      if (!phrase && mStr.length != 2 && sep == '.') continue;
      final dm = dayMonth(int.parse(m.group(1)!), int.parse(mStr), sep);
      if (dm == null || !_validDate(2000, dm.$2, dm.$1) || money(m.start, m.end)) continue;
      out.add(_T(_K.date, m.start, m.end, m: dm.$2, d: dm.$1, yearless: true, numeric: true));
    }

    // Время.
    bool notTime(int end) => _notTimeAfter.hasMatch(after(end));
    for (final m in _reHm.allMatches(text)) {
      final h = _apply(int.parse(m.group(1)!), m.group(3));
      out.add(_T(_K.time, _lead(text, m.start, _leadTime).$1, m.end, h: h, mi: int.parse(m.group(2)!), strong: true));
    }
    for (final m in _reHdot.allMatches(text)) {
      final h = _apply(int.parse(m.group(2)!), m.group(4));
      final mi = int.parse(m.group(3)!);
      if (h > 23 || mi > 59 || money(m.start, m.end)) continue;
      out.add(_T(_K.time, m.start, m.end, h: h, mi: mi, strong: true));
    }
    for (final m in _reHfr.allMatches(text)) {
      final h = int.parse(m.group(1)!);
      final mi = m.group(2) == null ? 0 : int.parse(m.group(2)!);
      final (s, prep) = _lead(text, m.start, _leadTime);
      // «15h» без минут — только «à 15h» (иначе это «15 часов» длительности).
      if ((prep != 'à' && m.group(2) == null) || h > 23 || mi > 59) continue;
      out.add(_T(_K.time, s, m.end, h: h, mi: mi, strong: true));
    }
    for (final m in _reAmPm.allMatches(text)) {
      out.add(
        _T(
          _K.time,
          _lead(text, m.start, _leadTime).$1,
          m.end,
          h: _apply(int.parse(m.group(1)!), m.group(2)),
          strong: true,
        ),
      );
    }
    for (final m in _rePrep.allMatches(text)) {
      final raw = _hourWord(m.group(2)!);
      if (raw == null) continue;
      final unit = m.group(3), suffix = m.group(4);
      final h = _apply(raw, suffix);
      if (h > 23) continue;
      final strong = unit != null || suffix != null;
      if (!strong && notTime(m.end)) continue;
      out.add(_T(_K.time, m.start, m.end, h: h, strong: strong));
    }
    for (final m in _reUnit.allMatches(text)) {
      final h = _apply(int.parse(m.group(1)!), m.group(2));
      if (h > 23) continue;
      out.add(_T(_K.time, m.start, m.end, h: h, strong: true));
    }
    for (final m in _reHalf.allMatches(text)) {
      final h = _ordinals[m.group(1)!.toLowerCase().replaceAll('ё', 'е')]! - 1;
      out.add(_T(_K.time, _lead(text, m.start, _leadWord).$1, m.end, h: h, mi: 30, strong: true));
    }
    for (final m in _reQuarter.allMatches(text)) {
      final h = _ordinals[m.group(1)!.toLowerCase().replaceAll('ё', 'е')]! - 1;
      out.add(_T(_K.time, _lead(text, m.start, _leadWord).$1, m.end, h: h, mi: 15, strong: true));
    }
    for (final m in _reWithout.allMatches(text)) {
      final h = _hourWord(m.group(2)!);
      if (h == null || h > 24) continue;
      const off = {'четверти': 15, 'пятнадцати': 15, 'двадцати': 20, 'десяти': 10, 'пяти': 5};
      out.add(
        _T(
          _K.time,
          _lead(text, m.start, _leadWord).$1,
          m.end,
          h: (h + 23) % 24,
          mi: 60 - off[m.group(1)!.toLowerCase()]!,
          strong: true,
        ),
      );
    }
    for (final m in _reNoon.allMatches(text)) {
      final w = m.group(1)!.toLowerCase();
      out.add(
        _T(_K.time, _lead(text, m.start, _leadWord).$1, m.end, h: w == 'полдень' || w == 'noon' ? 12 : 0, strong: true),
      );
    }

    // Промежутки.
    for (final m in _reRange.allMatches(text)) {
      final (start, prefix) = _lead(text, m.start, _leadRange);
      final dash = m.group(4)!.trim().length == 1 && '-–—'.contains(m.group(4)!.trim());
      final mi1 = m.group(2) == null ? 0 : int.parse(m.group(2)!);
      final mi2 = m.group(6) == null ? 0 : int.parse(m.group(6)!);
      var h1 = int.parse(m.group(1)!), h2 = int.parse(m.group(5)!);
      final ap1 = m.group(3), ap2 = m.group(7), unit = m.group(8), part = m.group(9);
      final strong =
          m.group(2) != null || m.group(6) != null || ap1 != null || ap2 != null || unit != null || part != null;
      // Без «с», «from»: только явное время через тире («15:00–16:30»,
      // «2-3pm», «15–16 ч»), иначе это номер, счёт, телефон.
      if (prefix == null && (!strong || !dash && m.group(2) == null)) continue;
      if (h1 > 23 || h2 > 23 || mi1 > 59 || mi2 > 59) continue;
      // «с 1 по 5 ноября», «from 3 to 5 October» — дни, а не часы.
      if (_monthAfter.hasMatch(after(m.end))) continue;
      if (!strong && notTime(m.end)) continue;
      final suffix2 = ap2 ?? part;
      h2 = _apply(h2, suffix2);
      h1 = ap1 != null ? _apply(h1, ap1) : h1;
      // «2-3pm», «с 7 до 9 вечера»: уточнение у конца — и для начала, если
      // так начало не позже конца.
      if (ap1 == null && suffix2 != null && h1 < 12 && h1 + 12 <= h2) h1 += 12;
      // «с 11 до 1», «from 9 to 5» — конец днём.
      if (suffix2 == null && h2 < h1 && h2 < 12 && h2 + 12 > h1) h2 += 12;
      out.add(_T(_K.range, start, m.end, h: h1, mi: mi1, h2: h2, mi2: mi2, strong: strong));
    }

    for (final m in _reDuration.allMatches(text)) {
      int? minutes;
      final word = m.group(3)?.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (word != null) {
        minutes = switch (word) {
          'полчаса' || 'half an hour' => 30,
          'полтора часа' => 90,
          _ => 60,
        };
      } else {
        final n = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        final unit = m.group(2)!.toLowerCase();
        if (n == null) continue;
        minutes = (unit.startsWith('мин') || unit.startsWith('min') ? n : n * 60).round();
      }
      if (minutes <= 0 || minutes > 24 * 60) continue;
      out.add(_T(_K.duration, m.start, m.end, minutes: minutes));
    }

    if (phrase) {
      for (final m in _reOffset.allMatches(text)) {
        final word = m.group(3)?.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (word != null) {
          switch (word) {
            case 'минуту':
              out.add(_T(_K.offset, m.start, m.end, minutes: 1));
            case 'полчаса' || 'half an hour':
              out.add(_T(_K.offset, m.start, m.end, minutes: 30));
            case 'час' || 'an hour' || 'a hour':
              out.add(_T(_K.offset, m.start, m.end, minutes: 60));
            case 'день' || 'a day':
              out.add(_T(_K.offset, m.start, m.end, days: 1));
            default:
              out.add(_T(_K.offset, m.start, m.end, days: 7));
          }
          continue;
        }
        final k = int.parse(m.group(1)!);
        final unit = m.group(2)!.toLowerCase();
        if (unit.startsWith('мин') || unit.startsWith('min')) {
          out.add(_T(_K.offset, m.start, m.end, minutes: k));
        } else if (unit.startsWith('ч') || unit.startsWith('h')) {
          out.add(_T(_K.offset, m.start, m.end, minutes: k * 60));
        } else if (unit.startsWith('недел') || unit.startsWith('week')) {
          out.add(_T(_K.offset, m.start, m.end, days: k * 7));
        } else {
          out.add(_T(_K.offset, m.start, m.end, days: k));
        }
      }
    }
    return _resolveOverlaps(out);
  }

  static final _monthAfter = _re('^\\s*(?:(?:de|of)\\s+)?(?:$_monthAlt)(?![a-zà-öø-ÿа-яё])');

  /// Пересекающиеся кусочки: из каждой группы пересечений — сначала самые
  /// длинные («в 9.30» — время, а не дата «9.30»; «2-3pm» — промежуток, а не
  /// «at 2»), при равной длине — раньше начавшийся.
  static List<_T> _resolveOverlaps(List<_T> all) {
    if (all.length < 2) return all;
    all.sort((a, b) => a.s != b.s ? a.s - b.s : b.len - a.len);
    final res = <_T>[];
    var i = 0;
    while (i < all.length) {
      // Группа пересекающихся по цепочке.
      var j = i + 1;
      var end = all[i].e;
      while (j < all.length && all[j].s < end) {
        if (all[j].e > end) end = all[j].e;
        j++;
      }
      if (j == i + 1) {
        res.add(all[i]);
      } else {
        final group = all.sublist(i, j)..sort((a, b) => a.len != b.len ? b.len - a.len : a.s - b.s);
        final picked = <_T>[];
        for (final t in group) {
          if (picked.every((p) => t.e <= p.s || t.s >= p.e)) picked.add(t);
        }
        picked.sort((a, b) => a.s - b.s);
        res.addAll(picked);
      }
      i = j;
    }
    return res;
  }

  // ───────────────────────── день по опорной дате ─────────────────────────

  /// День кусочка от опорного дня [ref]. [future] — дата без года: этот
  /// год, а прошедшая — следующий (ввод); иначе — ближайшая к [ref]
  /// (письмо от 28.12 про «05.01» — январь следующего года, письмо от 05.01
  /// про «28.12» — декабрь прошлого).
  static DateTime? _dayOf(_T t, DateTime ref, {required bool future}) {
    final today = DateTime(ref.year, ref.month, ref.day);
    switch (t.k) {
      case _K.day:
        return DateTime(ref.year, ref.month, ref.day + t.add!);
      case _K.weekday:
        var add = (t.wd! - ref.weekday) % 7;
        if (add <= 0) add += 7; // «в пятницу» в пятницу — следующая
        return DateTime(ref.year, ref.month, ref.day + add);
      case _K.date:
        if (!t.yearless) return DateTime(t.y!, t.m!, t.d!);
        if (future) {
          var y = ref.year;
          while (!_validDate(y, t.m!, t.d!)) {
            y++; // 29.02 — ближайший високосный год
            if (y > ref.year + 8) return null;
          }
          final dt = DateTime(y, t.m!, t.d!);
          if (!dt.isBefore(today)) return dt;
          for (var n = y + 1; n <= y + 8; n++) {
            if (_validDate(n, t.m!, t.d!)) return DateTime(n, t.m!, t.d!);
          }
          return null;
        }
        DateTime? best;
        for (var y = ref.year - 1; y <= ref.year + 1; y++) {
          if (!_validDate(y, t.m!, t.d!)) continue;
          final dt = DateTime(y, t.m!, t.d!);
          if (best == null || dt.difference(today).abs() < best.difference(today).abs()) best = dt;
        }
        return best;
      case _K.offset:
        return DateTime(ref.year, ref.month, ref.day + t.days!);
      default:
        return null;
    }
  }

  /// Время с учётом части дня: «вечером в 8» — 20:00.
  static int _withPart(int h, int part) => part == 3 && h < 12 ? h + 12 : h;

  // ───────────────────────── текст письма ─────────────────────────

  /// Упоминания дат и времени в тексте [text]. [ref] — опорный момент (дата
  /// письма, по часам устройства); [monthFirst] — «10/31» значит 31 октября
  /// (США).
  static List<DateMention> find(String text, {required DateTime ref, bool monthFirst = false}) {
    if (!mayContain(text)) return const [];
    final toks = text.length < 4096
        ? _scan(text, phrase: false, monthFirst: monthFirst)
        : _scanNearNumbers(text, monthFirst);
    if (toks.isEmpty) return const [];
    final out = <DateMention>[];
    var group = <_T>[];
    void flush() {
      if (group.isEmpty) return;
      final m = _mention(group, text, ref);
      if (m != null) out.add(m);
      group = <_T>[];
    }

    for (final t in toks) {
      if (group.isNotEmpty) {
        final last = group.last;
        final gap = text.substring(last.e, t.s);
        final fits = gap.length <= 16 && _gap.hasMatch(gap) && _slotFree(group, t);
        if (!fits) flush();
      }
      group.add(t);
    }
    flush();
    return out;
  }

  /// Длинный текст — только окрестности цифр (по 48 знаков в обе стороны,
  /// до пробела): упоминание без цифры в письме не считается, а в рассылке
  /// большая часть текста — без цифр.
  static List<_T> _scanNearNumbers(String text, bool monthFirst) {
    bool space(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0;
    final n = text.length;
    final wins = <List<int>>[];
    for (var i = 0; i < n; i++) {
      final c = text.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) continue;
      var s = i < 48 ? 0 : i - 48;
      var e = i + 49 > n ? n : i + 49;
      if (wins.isNotEmpty && s <= wins.last[1]) {
        s = wins.last[0];
      } else {
        while (s > 0 && !space(text.codeUnitAt(s - 1))) {
          s--;
        }
      }
      while (e < n && !space(text.codeUnitAt(e))) {
        e++;
      }
      if (wins.isNotEmpty && s <= wins.last[1]) {
        wins.last[1] = e;
      } else {
        wins.add([s, e]);
      }
    }
    return [
      for (final w in wins)
        for (final t in _scan(text.substring(w[0], w[1]), phrase: false, monthFirst: monthFirst)) t._shift(w[0]),
    ];
  }

  /// В упоминании — один день, одно время, одна часть дня, одна длительность
  /// (день недели рядом с датой — «пт, 31.10» — тоже можно).
  static bool _slotFree(List<_T> group, _T t) {
    bool has(bool Function(_T) f) => group.any(f);
    switch (t.k) {
      case _K.day || _K.date:
        return !has((g) => g.k == _K.day || g.k == _K.date);
      case _K.weekday:
        return !has((g) => g.k == _K.weekday || g.k == _K.day);
      case _K.time || _K.range:
        return !has((g) => g.timeish);
      case _K.part:
        return !has((g) => g.k == _K.part);
      case _K.duration:
        return !has((g) => g.k == _K.duration || g.k == _K.range);
      case _K.offset:
        return false;
    }
  }

  static DateMention? _mention(List<_T> g, String text, DateTime ref) {
    _T? first(bool Function(_T) f) {
      for (final t in g) {
        if (f(t)) return t;
      }
      return null;
    }

    final date = first((t) => t.k == _K.date);
    final day = first((t) => t.k == _K.day);
    final weekday = first((t) => t.k == _K.weekday);
    final time = first((t) => t.timeish);
    final part = first((t) => t.k == _K.part);
    final duration = first((t) => t.k == _K.duration);

    // Что считается датой в письме: время (голое «в 15» — только рядом с
    // днём), явная дата (словом месяца или с годом), дата без года — рядом
    // со временем, днём недели или словом «до», «с», «by».
    final hasDay = date != null || day != null || weekday != null;
    var ok = false;
    if (time != null) ok = time.strong || hasDay;
    if (!ok && date != null) {
      if (!date.numeric || !date.yearless) {
        ok = true;
      } else {
        ok = weekday != null || _dateContext.hasMatch(text.substring(date.s < 16 ? 0 : date.s - 16, date.s));
      }
    }
    if (!ok) return null;

    final dayTok = date ?? weekday ?? day;
    final base = dayTok == null ? DateTime(ref.year, ref.month, ref.day) : _dayOf(dayTok, ref, future: false);
    if (base == null) return null;
    final start = g.first.s;
    final end = g.last.e;
    if (time == null) return DateMention(start, end, base, allDay: true);
    final p = (part?.part ?? 0) != 0 ? part!.part : (day?.part ?? 0);
    final from = DateTime(base.year, base.month, base.day, _withPart(time.h!, p), time.mi);
    DateTime? to;
    if (time.k == _K.range) {
      to = DateTime(base.year, base.month, base.day, _withPart(time.h2!, p), time.mi2);
      if (!to.isAfter(from)) to = DateTime(base.year, base.month, base.day + 1, to.hour, to.minute);
    } else if (duration != null) {
      to = DateTime(from.year, from.month, from.day, from.hour, from.minute + duration.minutes!);
    }
    return DateMention(start, end, from, to: to);
  }

  // ───────────────────────── фраза быстрого ввода ─────────────────────────

  /// Дата и время из фразы быстрого ввода. Из каждого вида берётся первый
  /// кусочек (день — самый точный: дата, затем день недели, «завтра»,
  /// «через N дней»), остальное — [PhraseDate.rest]. «вечером» без дня —
  /// сегодня, без часа — 19:00; «утром» — 9:00, «днём» — 14:00.
  static PhraseDate parse(String input, {DateTime? now, bool monthFirst = false}) {
    final n = now ?? DateTime.now();
    final toks = _scan(input, phrase: true, monthFirst: monthFirst);
    if (toks.isEmpty) return PhraseDate(rest: _squash(input));
    _T? first(bool Function(_T) f) {
      for (final t in toks) {
        if (f(t)) return t;
      }
      return null;
    }

    final dayTok =
        first((t) => t.k == _K.date) ??
        first((t) => t.k == _K.weekday) ??
        first((t) => t.k == _K.day) ??
        first((t) => t.k == _K.offset && t.days != null);
    final time = first((t) => t.timeish);
    final duration = first((t) => t.k == _K.duration);
    final offset = first((t) => t.k == _K.offset && t.minutes != null);
    final partTok = first((t) => t.k == _K.part);
    final used = [dayTok, time, duration, offset, partTok].whereType<_T>().toList();
    // «tonight» — день и часть дня одним словом.
    final tonight = first((t) => t.k == _K.day && t.part != 0);
    if (tonight != null && !used.contains(tonight)) used.add(tonight);

    var day = dayTok == null ? null : _dayOf(dayTok, n, future: true);
    int? hour = time?.h;
    var minute = time?.mi ?? 0;
    final part = partTok?.part ?? tonight?.part ?? 0;
    if (part == 3) {
      day ??= DateTime(n.year, n.month, n.day);
      hour = hour == null ? 19 : _withPart(hour, 3);
    } else if (part == 1) {
      hour ??= 9;
    } else if (part == 2) {
      hour ??= 14;
    }
    int? endHour;
    var endMinute = 0;
    if (time?.k == _K.range) {
      endHour = part == 3 ? _withPart(time!.h2!, 3) : time!.h2;
      endMinute = time.mi2;
    }
    if (time == null && hour != null) minute = 0;

    final spans = [for (final t in used) (t.s, t.e)]..sort((a, b) => a.$1 - b.$1);
    final buf = StringBuffer();
    var at = 0;
    for (final s in spans) {
      buf
        ..write(input.substring(at, s.$1))
        ..write(' ');
      at = s.$2;
    }
    buf.write(input.substring(at));
    return PhraseDate(
      day: day,
      hour: hour,
      minute: minute,
      endHour: endHour,
      endMinute: endMinute,
      durationMinutes: duration?.minutes,
      offsetMinutes: offset?.minutes,
      loneHour: time != null && !time.strong && time.k == _K.time && part == 0,
      spans: spans,
      rest: _squash(buf.toString()),
    );
  }

  static String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

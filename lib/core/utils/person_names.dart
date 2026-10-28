// lib/core/utils/person_names.dart
// Имена людей в письмах и уведомлениях (1.5.9).
//
//  · [PersonNames.short] — «Фамилия И.О.» для тесных мест: панель
//    получателей, уведомления. Правила:
//      «Морозов Андрей Николаевич» (ФИО с отчеством)  → «Морозов А.Н.»
//      «Смирнов, Андрей» (Exchange: «Фамилия, Имя»)       → «Смирнов А.»
//      «John Smith» (латиница, имя и фамилия)            → «Smith J.»
//      «Smith, John»                                     → «Smith J.»
//    Где фамилию и инициалы надёжно не выделить — полное имя как есть:
//    организации («ООО …», «Служба поддержки»), два русских слова (неясно,
//    где фамилия: «Андрей Смирнов» или «Смирнов Андрей»), одно слово, адрес.
//  · [PersonNames.better] — какое из двух написаний полнее (для замены
//    «Смирнов, Андрей» на «Смирнов Андрей Сергеевич» из адресной книги).
//  · [PersonNames.monogram] — две буквы для кружка без фото.

class PersonNames {
  PersonNames._();

  static final _cyrWord = RegExp(r'^[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)?$');
  static final _latWord = RegExp(r"^[A-Z][a-z']+(?:-[A-Z][a-z']+)?$");
  static final _patronymic = RegExp(r'(вич|вна|ична|инична|чна|оглы|кызы|улы|уулу)$', caseSensitive: false);
  static final _orgMarkers = RegExp(
      r'(?:^|[\s"«])(?:ООО|ОАО|ПАО|АО|ЗАО|НАО|ИП|ФГУП|МУП|ГУП|LLC|Ltd|Inc|GmbH|Corp|Co\.|JSC|PLC|S\.A\.|AG'
      r'|служба|отдел|поддержк[а-яё]*|компания|банк|сервис|команда|рассылка|support|service|team|noreply|no-reply'
      r'|info|news)(?:[\s"»,.]|$)',
      caseSensitive: false);

  /// Имя без кавычек, скобок и лишних пробелов; адрес вместо имени — пусто.
  static String clean(String? raw) {
    final n = (raw ?? '')
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp('["«»\']'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (n.contains('@')) return '';
    return n;
  }

  /// «Фамилия И.О.» или полное имя, если сокращать ненадёжно. [email] —
  /// когда имени нет.
  static String short(String? displayName, {String email = ''}) {
    final n = clean(displayName);
    if (n.isEmpty) return email;
    if (_orgMarkers.hasMatch(n) || RegExp(r'\d').hasMatch(n) || n.contains('&')) return n;

    // «Фамилия, Имя [Отчество]» — так Exchange пишет имена в адресной книге.
    final comma = n.indexOf(',');
    if (comma > 0) {
      final last = n.substring(0, comma).trim();
      final rest = n.substring(comma + 1).trim().split(' ').where((w) => w.isNotEmpty).toList();
      final lastOk = _cyrWord.hasMatch(last) || _latWord.hasMatch(last);
      if (lastOk && rest.isNotEmpty && rest.length <= 2 && rest.every((w) => _cyrWord.hasMatch(w) || _latWord.hasMatch(w))) {
        return '$last ${rest.map((w) => '${w[0]}.').join()}';
      }
      return n;
    }

    final w = n.split(' ');
    // «Фамилия Имя Отчество».
    if (w.length == 3 && w.every(_cyrWord.hasMatch) && _patronymic.hasMatch(w[2])) {
      return '${w[0]} ${w[1][0]}.${w[2][0]}.';
    }
    // Иностранное «Имя Фамилия» (латиница) — «Фамилия И.».
    if (w.length == 2 && w.every(_latWord.hasMatch)) return '${w[1]} ${w[0][0]}.';
    return n;
  }

  /// Русское ФИО в порядке «Фамилия Имя Отчество». Outlook разбирает
  /// введённое «Волков Евгений Геннадьевич» по-английски (имя — «Волков»,
  /// отчество — «Евгений», фамилия — «Геннадьевич»), и из полей карточки
  /// получалось «Геннадьевич Волков Евгений» (замечание 12.10.2026).
  /// Три кириллических слова, отчество — одно и не последнее: оно уходит в
  /// конец, остальные — в прежнем порядке. Иначе — как есть.
  static String russianOrder(String name) {
    final w = name.trim().split(RegExp(r'\s+'));
    if (w.length != 3 || !w.every(_cyrWord.hasMatch)) return name;
    final p = [for (var i = 0; i < 3; i++) if (_patronymic.hasMatch(w[i])) i];
    if (p.length != 1 || p.first == 2) return name;
    final rest = [for (var i = 0; i < 3; i++) if (i != p.first) w[i]];
    return '${rest.join(' ')} ${w[p.first]}';
  }

  /// Число слов имени.
  static int words(String? name) => clean(name).split(' ').where((w) => w.isNotEmpty).length;

  /// [candidate] полнее, чем [current]: больше слов и те же буквы (не другой
  /// человек): «Смирнов, Андрей» → «Смирнов Андрей Сергеевич».
  static bool better(String? current, String? candidate) {
    final c = clean(candidate);
    if (c.isEmpty || c.contains(',')) return false;
    final raw = clean(current);
    final cur = raw.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cur.isEmpty) return true;
    final have = c.toLowerCase().split(' ').toSet();
    final was = cur.toLowerCase().split(' ').where((x) => x.isNotEmpty).toList();
    // Другой человек или другое написание — не заменять.
    if (!was.every(have.contains)) return false;
    return have.length > was.length || raw.contains(',');
  }

  /// «Морозов Андрей Николаевич» → «МА», «Смирнов, Андрей» → «СА», одно
  /// слово — одна буква.
  static String monogram(String? displayName, {String email = ''}) {
    final n = clean(displayName).replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final w = n.split(' ').where((x) => x.isNotEmpty && RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(x[0])).toList();
    if (w.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    if (w.length == 1) return w[0][0].toUpperCase();
    return '${w[0][0]}${w[1][0]}'.toUpperCase();
  }
}

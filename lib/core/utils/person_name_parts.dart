// lib/core/utils/person_name_parts.dart
// Части имени человека для обращения (14.11.2026, замечание владельца: в
// письме поручения «Ситников, добрый день!» — одна фамилия). Обращение и
// шаблоны языков — GreetingHelper (приветствие редактора, быстрого ответа
// и поручений); здесь — где в ФИО имя, отчество и фамилия:
//  · «Фамилия, Имя Отчество» (так пишет Exchange) — фамилия до запятой;
//  · отчество («…вич», «…вна», «…оглы», «…ovich») — по нему порядок:
//    «Фамилия Имя Отчество», «Имя Отчество Фамилия», «Имя Отчество»;
//  · два слова — где имя, решают список имён ([GivenNames]) и окончания
//    фамилий («-ов», «-ина», «-ский», «-енко», «-ov», «-sky»…); не ясно —
//    латиница «Имя Фамилия», по-венгерски «Фамилия Имя», кириллица — имени
//    не выделить (обращение полным именем, а не одной фамилией);
//  · вьетнамское имя (Nguyễn, Trần…) — имя последнее слово;
//  · иероглифы и хангыль — фамилия первая.

import 'person_names.dart';

/// Части имени человека; неизвестное — null.
class PersonNameParts {
  final String full;
  final String? given;
  final String? patronymic;
  final String? family;

  /// Имя написано иероглифами или хангылем (фамилия первая).
  final bool cjk;

  const PersonNameParts({required this.full, this.given, this.patronymic, this.family, this.cjk = false});

  static final _cyr = RegExp(r'^[А-ЯЁа-яё]+(?:-[А-ЯЁа-яё]+)*$');
  static final _lat = RegExp(r"^[A-Za-zÀ-ɏḀ-ỿ'’]+(?:-[A-Za-zÀ-ɏḀ-ỿ'’]+)*$");
  static final _cjk = RegExp(r'[぀-ヿ㐀-鿿가-힯豈-﫿]');
  static final _patronymic = RegExp(r'(вич|вна|ична|инична|чна|оглы|кызы|улы|уулу|ovich|evich|ovna|evna|ichna|vich|vna|ogly|kyzy)$',
      caseSensitive: false);
  static final _surnameCyr = RegExp(
      r'(ов|ев|ёв|ин|ын|ова|ева|ёва|ина|ына|ский|цкий|ской|цкой|ская|цкая|ых|их|енко|ко|ук|юк|чук|швили|дзе|ян|янц|ия)$',
      caseSensitive: false);
  static final _surnameLat = RegExp(
      r'(ov|ev|yov|in|yn|ova|eva|ina|yna|sky|skiy|skii|ski|skaya|skaia|enko|uk|chuk|shvili|dze|yan|ian|ich)$',
      caseSensitive: false);
  static const _vietFamilies = {
    'nguyễn', 'nguyen', 'trần', 'tran', 'lê', 'le', 'phạm', 'pham', 'hoàng', 'hoang', 'huỳnh', 'huynh', 'phan', 'vũ', 'vu',
    'võ', 'vo', 'đặng', 'dang', 'bùi', 'bui', 'đỗ', 'do', 'hồ', 'ho', 'ngô', 'ngo', 'dương', 'duong', 'lý', 'ly', 'đinh', 'dinh',
  };

  /// Разбор имени [displayName]; [locale] — язык письма (порядок по
  /// умолчанию: «hu» — фамилия первая). null — имени нет, адрес вместо
  /// имени или организация.
  static PersonNameParts? parse(String? displayName, {String locale = 'en'}) {
    var n = PersonNames.clean(displayName);
    if (n.isEmpty || RegExp(r'\d').hasMatch(n) || PersonNames.isOrganization(n)) return null;
    if (_cjk.hasMatch(n)) {
      final w = n.split(' ').where((x) => x.isNotEmpty).toList();
      return PersonNameParts(
        full: n,
        family: w.length >= 2 ? w.first : null,
        given: w.length >= 2 ? w.sublist(1).join(' ') : null,
        cjk: true,
      );
    }
    // «Фамилия, Имя [Отчество]».
    final comma = n.indexOf(',');
    if (comma > 0) {
      final family = n.substring(0, comma).trim();
      final rest = n.substring(comma + 1).trim().split(' ').where((x) => x.isNotEmpty).toList();
      if (rest.isNotEmpty && rest.length <= 2 && [family, ...rest].every(_word)) {
        final pat = rest.length == 2 && _patronymic.hasMatch(rest[1]) ? rest[1] : null;
        return PersonNameParts(full: [family, ...rest].join(' '), family: family, given: rest.first, patronymic: pat);
      }
      n = n.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final w = n.split(' ').where((x) => x.isNotEmpty).toList();
    if (!w.every(_word)) return PersonNameParts(full: n);
    if (w.length == 1) return PersonNameParts(full: n, given: w.first);
    if (_vietFamilies.contains(w.first.toLowerCase()) && w.length >= 2 && (w.length >= 3 || locale == 'vi')) {
      return PersonNameParts(full: n, family: w.first, given: w.last);
    }
    // Отчество: после имени из списка («Анна Сергеевна Пашкевич», где и
    // фамилия на «-вич») или единственное слово на «-вич», «-вна»…
    if (w.length == 3) {
      for (final (g, f) in [(0, 2), (1, 0)]) {
        if (GivenNames.known(w[g]) && _patronymic.hasMatch(w[g + 1]) && !GivenNames.known(w[f])) {
          return PersonNameParts(full: n, given: w[g], patronymic: w[g + 1], family: w[f]);
        }
      }
      final p = [for (var i = 0; i < 3; i++) if (_patronymic.hasMatch(w[i])) i];
      if (p.length == 1 && p.first == 2) return PersonNameParts(full: n, family: w[0], given: w[1], patronymic: w[2]);
      if (p.length == 1 && p.first == 1) return PersonNameParts(full: n, given: w[0], patronymic: w[1], family: w[2]);
    }
    // «Имя Отчество» (без фамилии); «Анна Пашкевич» — не отчество: мужское
    // «-вич» после женского имени.
    if (w.length == 2 && _patronymic.hasMatch(w[1]) && !_patronymic.hasMatch(w[0]) && !_femaleWithMale(w[0], w[1])) {
      return PersonNameParts(full: n, given: w[0], patronymic: w[1]);
    }
    final cyr = w.every(_cyr.hasMatch);
    final known = [for (final x in w) GivenNames.known(x)];
    // Имя — то слово, которое есть в списке имён (одно из всех).
    if (known.where((k) => k).length == 1) {
      final i = known.indexOf(true);
      return PersonNameParts(full: n, given: w[i], family: w.length == 2 ? w[1 - i] : (i == 0 ? w.last : w.first));
    }
    if (w.length == 2) {
      final s0 = _surname(w[0]), s1 = _surname(w[1]);
      if (s0 && !s1) return PersonNameParts(full: n, family: w[0], given: w[1]);
      if (s1 && !s0) return PersonNameParts(full: n, given: w[0], family: w[1]);
      if (locale == 'hu' && !cyr) return PersonNameParts(full: n, family: w[0], given: w[1]);
      if (locale == 'vi' && !cyr) return PersonNameParts(full: n, family: w[0], given: w[1]);
      // Кириллица: где имя — не ясно; обращение — полным именем.
      if (cyr) return PersonNameParts(full: n);
      return PersonNameParts(full: n, given: w[0], family: w[1]);
    }
    if (cyr) return PersonNameParts(full: n);
    return PersonNameParts(full: n, given: locale == 'vi' ? w.last : w.first, family: locale == 'vi' ? w.first : w.last);
  }

  static bool _word(String x) => _cyr.hasMatch(x) || _lat.hasMatch(x);

  static final _malePatronymic = RegExp(r'(вич|оглы|улы|уулу|vich|ogly)$', caseSensitive: false);
  static const _maleOnA = {'никита', 'илья', 'савва', 'лука', 'фома', 'кузьма', 'nikita', 'ilya', 'savva', 'luka', 'foma'};

  static bool _femaleWithMale(String given, String pat) {
    final g = given.toLowerCase();
    return _malePatronymic.hasMatch(pat) && RegExp(r'[аяay]$').hasMatch(g) && !_maleOnA.contains(g);
  }

  static bool _surname(String x) =>
      _cyr.hasMatch(x) ? _surnameCyr.hasMatch(x) : _surnameLat.hasMatch(x) && !GivenNames.known(x);
}

/// Частые имена (русские, а также татарские, башкирские, кавказские,
/// среднеазиатские, украинские в обиходе в России) — чтобы в «Ситников
/// Дмитрий» узнать имя. Латиница — те же имена в транслитерации (Dmitry,
/// Dmitriy, Dmitrii, Aleksandr, Alexander…).
abstract final class GivenNames {
  static const _cyr = <String>{
    // Мужские.
    'авраам', 'адам', 'адриан', 'азат', 'айдар', 'айрат', 'алан', 'алексей', 'александр', 'али', 'алик', 'алишер', 'альберт',
    'альфред', 'амир', 'анатолий', 'андрей', 'антон', 'аркадий', 'арсений', 'арсен', 'артем', 'артур', 'архип', 'аслан',
    'афанасий', 'бахтияр', 'богдан', 'борис', 'булат', 'вадим', 'валентин', 'валерий', 'василий', 'вениамин', 'виктор',
    'виль', 'вилен', 'виталий', 'влад', 'владимир', 'владислав', 'владлен', 'всеволод', 'вячеслав', 'гаврил', 'гавриил',
    'геннадий', 'георгий', 'герман', 'глеб', 'гордей', 'григорий', 'давид', 'дамир', 'даниил', 'данил', 'даниэль', 'данияр',
    'демид', 'денис', 'дмитрий', 'дмитро', 'евгений', 'егор', 'елисей', 'емельян', 'ефим', 'жан', 'захар', 'зиновий', 'ибрагим',
    'иван', 'игнат', 'игорь', 'израиль', 'ильдар', 'ильнур', 'ильяс', 'илья', 'иннокентий', 'иосиф', 'ислам', 'исмаил',
    'камиль', 'карен', 'кирилл', 'клим', 'константин', 'лев', 'леон', 'леонид', 'леонтий', 'лука', 'магомед',
    'майкл', 'макар', 'максим', 'марат', 'марк', 'мартин', 'матвей', 'мирон', 'мирослав', 'михаил', 'мурат', 'мустафа',
    'назар', 'наиль', 'нестор', 'никита', 'никифор', 'николай', 'нурлан', 'олег', 'олександр', 'оскар', 'остап', 'павел',
    'петр', 'платон', 'прохор', 'радик', 'радий', 'раиль', 'рамиль', 'рамзан', 'расул', 'ратмир', 'ренат', 'ринат', 'роберт',
    'родион', 'роман', 'ростислав', 'рузиль', 'руслан', 'рустам', 'рустем', 'савва', 'савелий', 'салават', 'самуил',
    'святослав', 'семен', 'серафим', 'сергей', 'сергій', 'спартак', 'станислав', 'степан', 'тагир', 'тарас', 'тимофей',
    'тимур', 'тихон', 'трофим', 'фарид', 'фархад', 'федор', 'феликс', 'филипп', 'фома', 'хасан', 'эдгар', 'эдуард',
    'эльдар', 'эмиль', 'эрик', 'эрнест', 'юлиан', 'юлий', 'юрий', 'юсуф', 'яков', 'ярослав',
    // Женские.
    'аделина', 'адель', 'аида', 'айгуль', 'айсылу', 'алевтина', 'александра', 'алена', 'алеся', 'алина', 'алиса', 'алия',
    'алла', 'алсу', 'альбина', 'амина', 'анастасия', 'ангелина', 'анжела', 'анжелика', 'анна', 'антонина', 'анфиса',
    'арина', 'ася', 'белла', 'валентина', 'валерия', 'варвара', 'василиса', 'вера', 'вероника', 'виктория', 'виолетта',
    'галина', 'гульнара', 'гульшат', 'гузель', 'дана', 'дарина', 'дарья', 'диана', 'дина', 'динара', 'ева', 'евгения',
    'евдокия', 'екатерина', 'елена', 'елизавета', 'жанна', 'зарина', 'зинаида', 'злата', 'зоя', 'зульфия', 'изабелла',
    'илона', 'инга', 'инесса', 'инна', 'ирина', 'камила', 'карина', 'кира', 'клавдия', 'кристина', 'ксения', 'лада',
    'лариса', 'лейла', 'лиана', 'лидия', 'лилиана', 'лилия', 'лина', 'любовь', 'людмила', 'ляйсан', 'майя',
    'маргарита', 'марианна', 'марина', 'мария', 'марьям', 'марта', 'милана', 'мирослава', 'надежда', 'наиля', 'наталия',
    'наталья', 'нелли', 'ника', 'нина', 'нонна', 'оксана', 'олеся', 'ольга', 'полина', 'рада', 'раиса', 'регина', 'римма',
    'роза', 'сабина', 'светлана', 'серафима', 'снежана', 'софия', 'софья', 'стефания', 'таисия', 'тамара', 'татьяна',
    'ульяна', 'фаина', 'элеонора', 'элина', 'элла', 'эльвира', 'эльмира', 'эмилия', 'юлиана', 'юлия', 'яна', 'ярослава',
  };

  static Set<String>? _lat;

  /// Слово — частое имя (кириллица или транслитерация).
  static bool known(String word) {
    final w = word.toLowerCase().replaceAll('ё', 'е');
    if (_cyr.contains(w)) return true;
    if (!RegExp(r'^[a-z]+$').hasMatch(w)) return false;
    return (_lat ??= {for (final c in _cyr) ..._variants(c)}).contains(_key(w));
  }

  static const _tr = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l',
    'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
    'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'і': 'i',
  };

  static Iterable<String> _variants(String c) sync* {
    final t = c.split('').map((ch) => _tr[ch] ?? '').join();
    yield _key(t);
  }

  /// Ключ сравнения транслитераций: Dmitry = Dmitriy = Dmitrii,
  /// Alexander = Aleksandr, Mikhail = Mihail, Natalia = Natalya.
  static String _key(String t) => t
      .replaceAll('x', 'ks')
      .replaceAll('kh', 'h')
      .replaceAll('j', 'y')
      .replaceAll(RegExp(r'^ye'), 'e')
      .replaceAll(RegExp(r'(iy|ii|yi)$'), 'y')
      .replaceAll(RegExp(r'ei$'), 'ey')
      .replaceAll(RegExp(r'iy(?=a)'), 'y')
      .replaceAll(RegExp(r'i(?=[aeou])'), 'y')
      .replaceAllMapped(RegExp(r'([a-z])\1'), (m) => m[1]!)
      .replaceAll(RegExp(r'der$'), 'dr');
}

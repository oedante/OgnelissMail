// lib/core/utils/greeting_helper.dart
// Приветствие в начале письма — на любом языке приложения (1.7.3).
//
// Шаблоны — ключи greet* в assets/l10n/<код>.xml: у каждого языка свой
// деловой оборот («Добрый день, {name},», «Hello {name},», «{name}様»).
// Варианты (просьба владельца 25.10.2026):
//   full  — «Добрый день, Максим Геннадьевич,» / «Добрый день, коллеги,»;
//   short — «Максим Геннадьевич,» / «Коллеги,» — ответ в переписке, где вы
//           уже писали: полное приветствие во втором и третьем ответе
//           звучит странно;
//   hello — «Добрый день!» без имени;
//   none  — без приветствия.
// «Коллеги» — только если все адресаты «Кому» из доменов вашей организации
// (адреса на gmail.com, yandex.ru и других общих почтах — не коллеги);
// иначе нескольким адресатам — «Добрый день!».
// Обращение — в именительном падеже: «Фамилия Имя Отчество» → «Имя
// Отчество», «Имя Фамилия» и «Фамилия Имя» → имя.

import '../../l10n/languages.g.dart';
import '../../l10n/strings_store.dart';
import 'mail_domains.dart';

/// Вариант приветствия в письме.
enum GreetingVariant { full, short, hello, none }

/// Тексты вариантов приветствия для одних адресатов.
class GreetingSet {
  /// Язык текста (код файла строк).
  final String lang;

  /// «Добрый день, Имя Отчество,» / «Добрый день, коллеги,» / «Добрый день!».
  final String full;

  /// «Имя Отчество,» / «Коллеги,»; '' — короткого варианта нет (адресат без
  /// имени, адресаты из разных организаций).
  final String short;

  /// «Добрый день!».
  final String hello;

  const GreetingSet({required this.lang, required this.full, required this.short, required this.hello});

  /// Текст варианта [v]; '' — без приветствия. Короткого нет — полное.
  String text(GreetingVariant v) => switch (v) {
        GreetingVariant.full => full,
        GreetingVariant.short => short.isNotEmpty ? short : full,
        GreetingVariant.hello => hello,
        GreetingVariant.none => '',
      };

  /// Варианты для выбора — без повторов текста, «без приветствия» последним.
  List<(GreetingVariant, String)> get choices {
    final seen = <String>{};
    return [
      for (final v in GreetingVariant.values)
        if (v == GreetingVariant.none || (text(v).isNotEmpty && seen.add(text(v)))) (v, text(v)),
    ];
  }
}

class GreetingHelper {
  GreetingHelper._();

  static final _cyr = RegExp('[А-Яа-яЁёІіЇїЄєҐґ]');
  static final _ukr = RegExp('[ІіЇїЄєҐґ]');

  /// Языки приложения на кириллице: имя кириллицей — приветствие на нём.
  static const _cyrLangs = {'ru', 'uk', 'bg'};

  /// Язык приветствия: имя адресата кириллицей — русский (украинские буквы —
  /// украинский, если он есть в приложении; приложение на русском,
  /// украинском или болгарском — его язык); иначе язык приложения.
  static String languageFor(List<String> names, String appLang) {
    var app = appLang.trim().toLowerCase().split(RegExp('[-_]')).first;
    if (app.isEmpty) app = 'ru';
    if (!names.any(_cyr.hasMatch)) return app;
    if (names.any(_ukr.hasMatch) && kAppLanguages.any((l) => l.code == 'uk')) return 'uk';
    if (_cyrLangs.contains(app)) return app;
    return 'ru';
  }

  /// Строка [key] на языке [lang] (нет — английская; нет и её — '').
  static String _t(String lang, String key) =>
      StringsStore.get(lang, key) ?? StringsStore.get('en', key) ?? '';

  /// Все адресаты — из доменов организации [ownDomains] (домены общих почт
  /// не считаются). Пустой [ownDomains] — домены неизвестны: да.
  static bool allInternal(List<String> emails, Set<String> ownDomains) {
    final own = {for (final d in ownDomains) if (!isPublicMailDomain(d)) d.toLowerCase()};
    if (ownDomains.isEmpty) return true;
    if (own.isEmpty) return false;
    return emails.every((e) {
      final d = mailDomainOf(e);
      return d.isNotEmpty && own.any((o) => sameOrgDomain(d, o));
    });
  }

  /// Варианты приветствия для адресатов «Кому»: [names] — имена из адресной
  /// книги (пустая строка — имени нет), [emails] — адреса, [appLang] — язык
  /// приложения, [ownDomains] — домены своих адресов ящика.
  static GreetingSet variants({
    required List<String> names,
    required List<String> emails,
    required String appLang,
    Set<String> ownDomains = const {},
  }) {
    final clean = [for (final n in names) cleanName(n)];
    final lang = languageFor(clean, appLang);
    final hello = _t(lang, 'greetHelloOnly');
    final count = emails.length > clean.length ? emails.length : clean.length;
    if (count == 0) return GreetingSet(lang: lang, full: hello, short: '', hello: hello);
    if (count > 1) {
      if (!allInternal(emails, ownDomains)) return GreetingSet(lang: lang, full: hello, short: '', hello: hello);
      return GreetingSet(
          lang: lang, full: _t(lang, 'greetGroup'), short: _t(lang, 'greetGroupShort'), hello: hello);
    }
    final addr = clean.isEmpty ? '' : addressOf(clean.first);
    if (addr.isEmpty) return GreetingSet(lang: lang, full: hello, short: '', hello: hello);
    return GreetingSet(
      lang: lang,
      full: _t(lang, 'greetName').replaceAll('{name}', addr),
      short: _t(lang, 'greetNameShort').replaceAll('{name}', addr),
      hello: hello,
    );
  }

  /// Образец для настроек: «Добрый день, Имя Отчество,» на языке [lang].
  static String sample(String lang, {bool withName = true}) => withName
      ? _t(lang, 'greetName').replaceAll('{name}', _t(lang, 'greetSampleName'))
      : _t(lang, 'greetHelloOnly');

  /// Имя без пояснений: «Кузнецов Максим Геннадьевич (ОТК)» → без скобок,
  /// «Petrov, Ivan» → «Ivan Petrov», кавычки убираются.
  static String cleanName(String raw) {
    var n = raw
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp('["«»]'), '')
        .trim();
    if (n.contains('@')) return '';
    final comma = n.indexOf(',');
    if (comma > 0) {
      final left = n.substring(0, comma).trim();
      final right = n.substring(comma + 1).trim();
      n = right.isEmpty ? left : '$right $left';
    }
    return n.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Как обратиться: «Фамилия Имя Отчество» и «Имя Отчество» → «Имя
  /// Отчество»; «Имя Фамилия» и «Фамилия Имя» → имя; одно слово — оно.
  static String addressOf(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length >= 3 && _isPatronymic(parts[2])) return '${parts[1]} ${parts[2]}';
    if (parts.length >= 2 && _isPatronymic(parts[1])) return '${parts[0]} ${parts[1]}';
    if (parts.length >= 3 && _isPatronymic(parts[1])) return '${parts[0]} ${parts[1]}';
    if (parts.length >= 2) {
      // Русская фамилия первой («Петров Иван») — обращаемся по второму слову.
      return _looksLikeSurname(parts[0]) && !_looksLikeSurname(parts[1]) ? parts[1] : parts[0];
    }
    return parts.first;
  }

  static bool _looksLikeSurname(String w) {
    final l = w.toLowerCase();
    return RegExp(r'(ов|ев|ёв|ин|ын|ский|цкий|ской|ова|ева|ёва|ина|ына|ская|цкая|енко|ук|юк|ян|дзе|швили)$')
        .hasMatch(l);
  }

  static bool _isPatronymic(String word) {
    final lower = word.toLowerCase();
    return lower.endsWith('ович') || lower.endsWith('евич') ||
        lower.endsWith('овна') || lower.endsWith('евна') ||
        lower.endsWith('ич') || lower.endsWith('ична');
  }
}

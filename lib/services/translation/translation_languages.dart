// lib/services/translation/translation_languages.dart
//
// Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026): выбор
// языков — когда предлагать перевод письма и в каком порядке показывать
// языки при переводе своего письма.

/// Код языка в одном виде для приложения, ML Kit и Apple: основной подтег
/// в нижнем регистре («pt-BR» → «pt», «zh-Hans» → «zh»), старые коды Java —
/// новыми («iw» → «he»), норвежский — «no» (как в ML Kit; у приложения
/// язык «nb»). Пусто, «und» и латиница вместо своего письма («ru-Latn») —
/// null: такой язык переводчику не назвать.
String? normalizeLang(String? code) {
  if (code == null) return null;
  final c = code.trim().replaceAll('_', '-');
  if (c.isEmpty) return null;
  final parts = c.split('-');
  if (parts.length > 1 && parts[1].toLowerCase() == 'latn' && !_latinScript.contains(parts[0].toLowerCase())) {
    return null;
  }
  final p = parts.first.toLowerCase();
  if (p == 'und' || p == 'zxx' || p == 'mul') return null;
  return _aliases[p] ?? p;
}

const _aliases = {'iw': 'he', 'in': 'id', 'ji': 'yi', 'nb': 'no', 'nn': 'no', 'fil': 'tl', 'jw': 'jv'};

/// Языки, у которых «-Latn» — их обычное письмо (не транслит).
const _latinScript = {'sr', 'uz', 'az', 'bs', 'ms', 'tk'};

/// Русский, который определитель принял за другой кириллический язык
/// (1.11.0, письмо Google Play 03.11.2026: русский текст с вкраплениями
/// латиницы — «Play Console», «non-trader» — ML Kit назвал болгарским).
/// Проверка по буквам: в болгарском, македонском, сербском и украинском нет
/// «ы», «э», «ё»; в белорусском они есть, но у него есть и «і», «ў», которых
/// нет в русском. Пара слов с «ы» (русское имя в болгарском письме) язык не
/// меняет: таких букв должно быть заметно больше — как в русском тексте
/// (около 2 % букв).
///
/// Украинский, сербский, македонский (1.11.x, скриншот владельца 04.11.2026:
/// «Добрый день, Андрей Сергеевич, Тестирую перевод письма» — «Язык
/// письма: украинский»): у короткого письма «ы», «э», «ё» бывает одна, а
/// ML Kit на коротком русском тексте часто называет украинский. В этих
/// языках таких букв нет совсем, а своих («і», «ї», «є», «ј», «љ», «њ» …) в
/// тексте из 20 букв почти всегда несколько. Поэтому достаточно одной
/// русской буквы, если своих букв нет (меньше 1 %). У болгарского и
/// белорусского — прежний порог: в болгарском много русских имён, а
/// белорусский сам пишется с «ы», «э», «ё».
String? refineCyrillicLang(String? lang, String text) {
  if (lang == null || !_ruLookalikes.contains(lang)) return lang;
  final low = text.toLowerCase();
  final letters = _cyrillic.allMatches(low).length;
  if (letters < 20) return lang;
  // Буквы, которых нет в русском: украинские, белорусские, сербские,
  // македонские.
  final foreign = _notRussian.allMatches(low).length;
  if (foreign * 100 >= letters) return lang;
  final russian = _onlyRussian.allMatches(low).length;
  if (_noRussianLetters.contains(lang) && russian >= 1) return 'ru';
  return russian >= 2 && russian * 200 >= letters ? 'ru' : lang;
}

/// Языки, где «ы», «э», «ё» не пишутся вовсе.
const _noRussianLetters = {'uk', 'sr', 'mk'};

const _ruLookalikes = {'bg', 'mk', 'sr', 'uk', 'be'};
final _cyrillic = RegExp('[\u0400-\u04ff]');
final _onlyRussian = RegExp('[ыэё]');
final _notRussian = RegExp('[іїєґўјљњђћџѓќѕ]');

/// Предлагать ли перевод входящего письма: язык определён, он не язык
/// приложения, не в списке «не переводить», и переводчик его знает.
bool shouldOfferTranslation({
  required String? detected,
  required String appLang,
  required bool enabled,
  required Iterable<String> never,
  required Iterable<String> available,
}) =>
    decideTranslationOffer(
        detected: detected, confident: true, appLang: appLang, enabled: enabled, never: never, available: available) ==
    TranslationOffer.offer;

/// Что делать с переводом открытого письма (1.12.x).
enum TranslationOffer {
  /// Ничего: язык приложения или знакомый, перевод не предлагать.
  none,

  /// Плашка «Язык письма: … · Перевести».
  offer,

  /// Плашка «Письмо на другом языке» — язык не определён уверенно, но
  /// письмо другим алфавитом, чем приложение; язык — по нажатию.
  otherLanguage,

  /// «Всегда переводить с …»: перевод сразу, без плашки-предложения.
  auto,
}

/// Решение о переводе входящего письма (1.12.x, просьба владельца
/// 04.11.2026: плашка «сбоит и предлагает другие языки»).
///
/// Перевод предлагается только с языка, в котором определитель уверен
/// ([confident]): слабая догадка (ML Kit с порогом 0,2) на письме с
/// цитатой, подписью на двух языках или ссылками называла чужой язык.
/// Без уверенного языка — только «Письмо на другом языке» ([otherScript]:
/// письмо другим алфавитом, чем приложение), и не с языка из списков
/// «не переводить» и знакомых ([known] — языки телефона).
///
/// «Всегда переводить с …» ([always]) — выбор самого человека: работает и
/// при выключенном «Предлагать перевод», и для языка телефона, но не для
/// «не переводить» и не по догадке.
TranslationOffer decideTranslationOffer({
  required String? detected,
  required bool confident,
  required String appLang,
  required bool enabled,
  required Iterable<String> never,
  Iterable<String> always = const [],
  Iterable<String> known = const [],
  required Iterable<String> available,
  bool otherScript = false,
}) {
  final d = normalizeLang(detected);
  final app = normalizeLang(appLang);
  if (app == null) return TranslationOffer.none;
  bool listed(Iterable<String> list) => d != null && list.map(normalizeLang).contains(d);
  if (d == null || !confident) {
    if (!enabled || !otherScript || listed(never) || listed(known)) return TranslationOffer.none;
    return TranslationOffer.otherLanguage;
  }
  if (d == app || listed(never)) return TranslationOffer.none;
  final av = available.map(normalizeLang).toSet();
  if (!av.contains(d) || !av.contains(app)) return TranslationOffer.none;
  if (listed(always)) return TranslationOffer.auto;
  if (!enabled || listed(known)) return TranslationOffer.none;
  return TranslationOffer.offer;
}

/// Список языков [list] с [lang] (без повторов, по алфавиту) — для
/// «не переводить» и «всегда переводить».
List<String> withLang(Iterable<String> list, String lang) {
  final n = normalizeLang(lang) ?? lang;
  return {...list.map((c) => normalizeLang(c) ?? c), n}.toList()..sort();
}

/// Список языков [list] без [lang].
List<String> withoutLang(Iterable<String> list, String lang) {
  final n = normalizeLang(lang) ?? lang;
  return [for (final c in list) if ((normalizeLang(c) ?? c) != n) c];
}

/// Порядок языков в выборе «Перевести на…»: язык собеседника ([suggested],
/// по переписке), затем недавние, затем остальные по названию. Язык самого
/// текста ([source]) не предлагается.
List<String> orderTargetLanguages({
  required Iterable<String> available,
  List<String> recent = const [],
  String? suggested,
  String? source,
  Map<String, String> names = const {},
}) {
  final av = <String>{};
  for (final a in available) {
    final n = normalizeLang(a);
    if (n != null) av.add(n);
  }
  final src = normalizeLang(source);
  final out = <String>[];
  void add(String? c) {
    final n = normalizeLang(c);
    if (n == null || n == src || !av.contains(n) || out.contains(n)) return;
    out.add(n);
  }

  add(suggested);
  recent.forEach(add);
  final rest = av.where((c) => !out.contains(c) && c != src).toList()
    ..sort((a, b) => (names[a] ?? a).toLowerCase().compareTo((names[b] ?? b).toLowerCase()));
  out.addAll(rest);
  return out;
}

/// Язык собеседника для перевода своего письма: язык цитаты (письма, на
/// которое отвечают), если он другой, чем язык своего текста.
String? suggestRecipientLanguage({required String? quoteLang, required String? ownLang}) {
  final q = normalizeLang(quoteLang);
  if (q == null || q == normalizeLang(ownLang)) return null;
  return q;
}

/// Недавние языки: [lang] — первым, без повторов, не больше [max].
List<String> pushRecent(List<String> recent, String lang, {int max = 5}) {
  final n = normalizeLang(lang);
  if (n == null) return recent;
  return [n, ...recent.where((r) => normalizeLang(r) != n)].take(max).toList();
}

/// Название языка с заглавной буквы: Android и iOS дают «английский» —
/// в списке выбора так не пишут.
String capitalizeLangName(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

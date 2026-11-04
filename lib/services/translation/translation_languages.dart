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
  return russian >= 2 && russian * 200 >= letters ? 'ru' : lang;
}

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
}) {
  if (!enabled) return false;
  final d = normalizeLang(detected);
  final app = normalizeLang(appLang);
  if (d == null || app == null || d == app) return false;
  if (never.map(normalizeLang).contains(d)) return false;
  final av = available.map(normalizeLang).toSet();
  return av.contains(d) && av.contains(app);
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

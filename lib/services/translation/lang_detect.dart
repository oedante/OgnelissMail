// lib/services/translation/lang_detect.dart
//
// Определение языка письма без движка платформы (перевод на Windows, 2.2.0):
// у Android язык определяет ML Kit, у iPhone и Mac — Apple, а Bergamot
// (Windows) языки не определяет. Здесь — по алфавиту и частым словам:
// для предложения перевода этого хватает (письмо, а не одна фраза), а
// сомнительный случай — «не уверен», и плашка-предложение не появляется
// (decideTranslationOffer).

import 'translation_languages.dart';
import 'translator.dart' show LangDetection;

/// Язык [text] и уверенность. null — букв почти нет.
LangDetection? detectLanguageHeuristic(String text) {
  // Начала письма хватает: длинная рассылка не тормозит открытие.
  if (text.length > 6000) text = text.substring(0, 6000);
  final clean = text
      .replaceAll(_urls, ' ')
      .replaceAll(_emails, ' ')
      .toLowerCase();
  final counts = <_Script, int>{};
  var letters = 0;
  for (final r in clean.runes) {
    final s = _scriptOf(r);
    if (s == null) continue;
    letters++;
    counts[s] = (counts[s] ?? 0) + 1;
  }
  if (letters < 3) return null;
  final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final share = top.value / letters;
  // Два алфавита поровну (цитата на другом языке) — язык не назвать уверенно.
  final sure = share >= 0.6 && top.value >= 20;
  String? lang;
  var confident = sure;
  switch (top.key) {
    case _Script.latin:
      final r = _latinGuess(clean);
      if (r == null) return null;
      lang = r.lang;
      confident = sure && r.confident;
    case _Script.cyrillic:
      lang = _cyrillicGuess(clean);
    case _Script.arabic:
      lang = _arabicGuess(clean);
    case _Script.han:
      // Японский текст пишется и иероглифами: кана — японский.
      lang = (counts[_Script.kana] ?? 0) * 10 >= top.value ? 'ja' : 'zh';
    case _Script.kana:
      lang = 'ja';
    case _Script.hangul:
      lang = 'ko';
    case _Script.greek:
      lang = 'el';
    case _Script.hebrew:
      lang = 'he';
    case _Script.thai:
      lang = 'th';
    case _Script.devanagari:
      lang = 'hi';
    case _Script.bengali:
      lang = 'bn';
    case _Script.tamil:
      lang = 'ta';
    case _Script.telugu:
      lang = 'te';
    case _Script.gujarati:
      lang = 'gu';
    case _Script.kannada:
      lang = 'kn';
    case _Script.malayalam:
      lang = 'ml';
    case _Script.georgian:
      lang = 'ka';
    case _Script.armenian:
      lang = 'hy';
  }
  final refined = refineCyrillicLang(lang, text);
  return refined == null ? null : (lang: refined, confident: confident);
}

final _urls = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);
final _emails = RegExp(r'\S+@\S+');
final _words = RegExp(r"[\p{L}']+", unicode: true);

enum _Script {
  latin,
  cyrillic,
  greek,
  arabic,
  hebrew,
  han,
  kana,
  hangul,
  thai,
  devanagari,
  bengali,
  tamil,
  telugu,
  gujarati,
  kannada,
  malayalam,
  georgian,
  armenian
}

_Script? _scriptOf(int r) {
  if ((r >= 0x61 && r <= 0x7a) || (r >= 0xc0 && r <= 0x24f && r != 0xd7 && r != 0xf7) || (r >= 0x1e00 && r <= 0x1eff)) {
    return _Script.latin;
  }
  if (r >= 0x400 && r <= 0x52f) return _Script.cyrillic;
  if (r >= 0x370 && r <= 0x3ff) return _Script.greek;
  if (r >= 0x590 && r <= 0x5ff) return _Script.hebrew;
  if ((r >= 0x600 && r <= 0x6ff) || (r >= 0x750 && r <= 0x77f) || (r >= 0xfb50 && r <= 0xfdff)) return _Script.arabic;
  if (r >= 0x900 && r <= 0x97f) return _Script.devanagari;
  if (r >= 0x980 && r <= 0x9ff) return _Script.bengali;
  if (r >= 0xa80 && r <= 0xaff) return _Script.gujarati;
  if (r >= 0xb80 && r <= 0xbff) return _Script.tamil;
  if (r >= 0xc00 && r <= 0xc7f) return _Script.telugu;
  if (r >= 0xc80 && r <= 0xcff) return _Script.kannada;
  if (r >= 0xd00 && r <= 0xd7f) return _Script.malayalam;
  if (r >= 0xe00 && r <= 0xe7f) return _Script.thai;
  if (r >= 0x10a0 && r <= 0x10ff) return _Script.georgian;
  if (r >= 0x530 && r <= 0x58f) return _Script.armenian;
  if (r >= 0x3040 && r <= 0x30ff) return _Script.kana;
  if (r >= 0xac00 && r <= 0xd7af) return _Script.hangul;
  if ((r >= 0x4e00 && r <= 0x9fff) || (r >= 0x3400 && r <= 0x4dbf)) return _Script.han;
  return null;
}

/// Кириллица: свои буквы языка, затем частые слова.
String _cyrillicGuess(String t) {
  int n(String chars) => RegExp('[$chars]').allMatches(t).length;
  final uk = n('іїєґ');
  final be = n('ў');
  final sr = n('ђћџ');
  final mk = n('ѓќѕ');
  final j = n('јљњ');
  final ru = n('ыэё');
  if (be > 0 && be >= uk) return 'be';
  if (mk > 0) return 'mk';
  if (sr > 0 || (j > 0 && uk == 0)) return 'sr';
  if (uk > 0 && uk >= ru) return 'uk';
  if (ru > 0) return 'ru';
  final words = _words.allMatches(t).map((m) => m.group(0)!).toList();
  var bg = 0, ruW = 0, ukW = 0;
  for (final w in words) {
    if (_bgWords.contains(w)) bg++;
    if (_ruWords.contains(w)) ruW++;
    if (_ukWords.contains(w)) ukW++;
  }
  if (bg > ruW && bg > ukW) return 'bg';
  if (ukW > ruW) return 'uk';
  return 'ru';
}

const _ruWords = {'и', 'в', 'не', 'что', 'на', 'с', 'как', 'это', 'по', 'но', 'вы', 'мы', 'для', 'спасибо', 'здравствуйте', 'он', 'она', 'они', 'его', 'если', 'уже', 'или', 'когда', 'только'};
const _ukWords = {'і', 'й', 'та', 'що', 'не', 'на', 'з', 'як', 'це', 'ви', 'ми', 'для', 'дякую', 'вітаю', 'він', 'вона', 'вони', 'його', 'якщо', 'вже', 'або', 'коли', 'тільки'};
const _bgWords = {'и', 'в', 'не', 'че', 'на', 'с', 'като', 'това', 'по', 'но', 'вие', 'ние', 'за', 'благодаря', 'здравейте', 'той', 'тя', 'те', 'ако', 'вече', 'или', 'когато', 'само', 'е', 'са', 'да', 'ще'};

/// Арабское письмо: персидские буквы (پ چ ژ گ) и «ی», «ک» — персидский;
/// урду — свои буквы (ٹ ڈ ڑ ں ے).
String _arabicGuess(String t) {
  final fa = RegExp('[پچژگکی]').allMatches(t).length;
  final ur = RegExp('[ٹڈڑںے]').allMatches(t).length;
  if (ur > 0 && ur * 2 >= fa) return 'ur';
  final ar = RegExp('[ةيك]').allMatches(t).length;
  return fa > ar ? 'fa' : 'ar';
}

/// Латиница: частые слова языков и буквы, которых нет у других.
({String lang, bool confident})? _latinGuess(String t) {
  final words = _words.allMatches(t).map((m) => m.group(0)!).toList();
  if (words.isEmpty) return null;
  final score = <String, double>{};
  for (final e in _latinWords.entries) {
    var hits = 0;
    for (final w in words) {
      if (e.value.contains(w)) hits++;
    }
    if (hits > 0) score[e.key] = hits.toDouble();
  }
  for (final e in _latinLetters.entries) {
    final c = RegExp('[${e.value}]').allMatches(t).length;
    if (c > 0) score[e.key] = (score[e.key] ?? 0) + (c > 6 ? 3 : c / 2);
  }
  if (score.isEmpty) return (lang: 'en', confident: false);
  final ranked = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final best = ranked.first;
  final second = ranked.length > 1 ? ranked[1].value : 0.0;
  final confident = words.length >= 5 && best.value >= 3 && best.value >= second * 1.5;
  return (lang: best.key, confident: confident);
}

const _latinWords = <String, Set<String>>{
  'en': {'the', 'and', 'of', 'to', 'is', 'in', 'that', 'it', 'for', 'you', 'with', 'on', 'this', 'are', 'be', 'have', 'was', 'not', 'we', 'your', 'will', 'please', 'thanks', 'from', 'thank', 'would', 'could', 'our', 'can', 'hi'},
  'de': {'der', 'die', 'das', 'und', 'ist', 'nicht', 'ich', 'sie', 'es', 'mit', 'den', 'ein', 'eine', 'zu', 'auf', 'für', 'wir', 'von', 'dem', 'auch', 'bitte', 'ihr', 'haben', 'sind', 'danke', 'ihnen', 'wie', 'aber', 'hallo', 'gruß', 'grüße'},
  'fr': {'le', 'la', 'les', 'et', 'est', 'des', 'une', 'un', 'pour', 'que', 'dans', 'vous', 'nous', 'pas', 'sur', 'avec', 'du', 'au', 'ce', 'merci', 'bonjour', 'sont', 'qui', 'je', 'votre', 'cordialement', 'mais', 'aux'},
  'es': {'el', 'la', 'los', 'las', 'y', 'que', 'de', 'en', 'es', 'por', 'para', 'con', 'una', 'un', 'del', 'se', 'no', 'su', 'gracias', 'hola', 'está', 'como', 'pero', 'muy', 'usted', 'saludos', 'lo', 'al'},
  'it': {'il', 'la', 'che', 'di', 'e', 'è', 'per', 'non', 'una', 'un', 'con', 'sono', 'del', 'della', 'gli', 'le', 'si', 'grazie', 'ciao', 'questo', 'anche', 'ma', 'alla', 'buongiorno', 'cordiali', 'saluti', 'nel'},
  'pt': {'o', 'a', 'os', 'as', 'e', 'que', 'de', 'não', 'é', 'para', 'com', 'uma', 'um', 'do', 'da', 'em', 'você', 'obrigado', 'obrigada', 'olá', 'está', 'mais', 'mas', 'são', 'dos', 'das', 'atenciosamente', 'no', 'na'},
  'nl': {'de', 'het', 'een', 'en', 'van', 'is', 'niet', 'dat', 'ik', 'je', 'met', 'voor', 'op', 'zijn', 'ook', 'wij', 'we', 'u', 'bedankt', 'groeten', 'hebben', 'naar', 'maar', 'dank', 'graag', 'uw', 'deze'},
  'pl': {'i', 'w', 'nie', 'się', 'na', 'że', 'to', 'jest', 'z', 'do', 'jak', 'ale', 'dla', 'czy', 'są', 'dziękuję', 'pozdrawiam', 'jestem', 'mamy', 'tak', 'od', 'po', 'pan', 'pani', 'oraz', 'proszę'},
  'cs': {'a', 'je', 'se', 'na', 'že', 'to', 'v', 'ne', 's', 'pro', 'jsem', 'jako', 'ale', 'by', 'děkuji', 'prosím', 'dobrý', 'den', 'jsou', 'máme', 'také', 'od', 'jsme', 'bude', 'pozdravem'},
  'sk': {'a', 'je', 'sa', 'na', 'že', 'to', 'v', 'nie', 's', 'pre', 'som', 'ako', 'ale', 'by', 'ďakujem', 'prosím', 'dobrý', 'deň', 'sú', 'máme', 'tiež', 'od', 'sme', 'bude', 'pozdravom'},
  'sv': {'och', 'att', 'det', 'är', 'en', 'som', 'på', 'för', 'med', 'inte', 'jag', 'vi', 'till', 'av', 'har', 'den', 'tack', 'hej', 'du', 'kan', 'ett', 'om', 'också', 'vänliga', 'hälsningar', 'ni', 'från'},
  'da': {'og', 'at', 'det', 'er', 'en', 'som', 'på', 'for', 'med', 'ikke', 'jeg', 'vi', 'til', 'af', 'har', 'den', 'tak', 'hej', 'du', 'kan', 'et', 'om', 'også', 'venlig', 'hilsen', 'jer', 'fra', 'meget'},
  'no': {'og', 'å', 'det', 'er', 'en', 'som', 'på', 'for', 'med', 'ikke', 'jeg', 'vi', 'til', 'av', 'har', 'den', 'takk', 'hei', 'du', 'kan', 'et', 'om', 'også', 'vennlig', 'hilsen', 'dere', 'fra', 'mye'},
  'fi': {'ja', 'on', 'ei', 'se', 'että', 'en', 'hän', 'me', 'olen', 'kiitos', 'terveisin', 'mutta', 'tai', 'kun', 'jos', 'ole', 'ovat', 'myös', 'tämä', 'voi', 'hei', 'olemme', 'sinun'},
  'hu': {'a', 'az', 'és', 'hogy', 'nem', 'is', 'egy', 'van', 'meg', 'de', 'köszönöm', 'üdvözlettel', 'kérem', 'ez', 'mint', 'csak', 'már', 'vagy', 'szia', 'kell', 'lesz'},
  'ro': {'și', 'de', 'la', 'în', 'nu', 'este', 'că', 'cu', 'pe', 'o', 'un', 'pentru', 'mulțumesc', 'vă', 'sunt', 'ce', 'mai', 'din', 'care', 'bună', 'să', 'fi'},
  'tr': {'ve', 'bir', 'bu', 'için', 'ile', 'de', 'da', 'çok', 'teşekkürler', 'merhaba', 'ne', 'olarak', 'daha', 'sonra', 'gibi', 'değil', 'var', 'ben', 'siz', 'teşekkür', 'ederim', 'saygılarımla'},
  'id': {'dan', 'yang', 'di', 'ini', 'itu', 'dengan', 'untuk', 'tidak', 'ada', 'kami', 'saya', 'anda', 'terima', 'kasih', 'dari', 'akan', 'juga', 'bisa', 'atau', 'sudah', 'kita'},
  'vi': {'và', 'của', 'là', 'có', 'không', 'được', 'cho', 'này', 'các', 'những', 'một', 'với', 'tôi', 'bạn', 'cảm', 'ơn', 'đã', 'trong', 'chúng', 'anh', 'chị'},
  'et': {'ja', 'on', 'ei', 'see', 'et', 'ma', 'me', 'oli', 'kui', 'aga', 'tänan', 'palun', 'ka', 'või', 'mis', 'kas', 'olen', 'tere', 'lugupidamisega'},
  'is': {'og', 'að', 'er', 'ekki', 'það', 'ég', 'við', 'á', 'í', 'með', 'fyrir', 'takk', 'en', 'sem', 'um', 'til', 'kveðja', 'þú', 'þetta'},
  'hr': {'i', 'je', 'u', 'da', 'se', 'na', 'za', 'ne', 'od', 'su', 'sa', 'kao', 'ali', 'hvala', 'molim', 'što', 'šta', 'ili', 'lijep', 'pozdrav', 'smo'},
  'sl': {'in', 'je', 'da', 'se', 'na', 'za', 'ne', 'so', 'z', 'pa', 'kot', 'hvala', 'prosim', 'tudi', 'ali', 'sem', 'lep', 'pozdrav', 'bo'},
  'lt': {'ir', 'yra', 'kad', 'su', 'į', 'iš', 'ne', 'tai', 'aš', 'mes', 'ačiū', 'labas', 'bet', 'kaip', 'jūs', 'pagarbiai', 'bus'},
  'lv': {'un', 'ir', 'ka', 'ar', 'no', 'uz', 'ne', 'es', 'mēs', 'paldies', 'bet', 'kā', 'jūs', 'par', 'lai', 'sveiki', 'būs'},
  'ca': {'el', 'la', 'i', 'que', 'de', 'és', 'per', 'amb', 'una', 'un', 'no', 'els', 'les', 'del', 'gràcies', 'hola', 'això', 'molt', 'salutacions'},
  'sq': {'dhe', 'në', 'të', 'është', 'një', 'për', 'me', 'nuk', 'që', 'faleminderit', 'ju', 'ne', 'përshëndetje'},
};

/// Буквы, по которым язык узнаётся сразу (у соседей их нет или редко).
const _latinLetters = <String, String>{
  'de': 'ß',
  'es': 'ñ¿¡',
  'pt': 'ãõ',
  'pl': 'łąęśźżćń',
  'cs': 'řěů',
  'sk': 'ľĺŕô',
  'sv': 'å',
  'da': 'æøå',
  'no': 'æøå',
  'hu': 'őű',
  'ro': 'șțţă',
  'tr': 'ğış',
  'vi': 'đươạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ',
  'is': 'þð',
  'lt': 'ėųįū',
  'lv': 'āēīūģķļņ',
  'fr': 'œ',
};

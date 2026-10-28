// lib/core/utils/text_safe.dart
// Безопасная работа со строками для отображения. Эмодзи и редкие символы в
// Dart-строке занимают две «половинки» (суррогатную пару UTF-16). Обрезка
// посередине пары (substring(0, 200) у превью) или первая «буква» имени,
// начинающегося с эмодзи (name[0]), дают половинку без пары — Flutter
// падает при отрисовке: «string is not well-formed UTF-16» (журнал 09.10.2026).

bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;

/// Не длиннее [max] единиц, без разрыва суррогатной пары.
String cutSafe(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  if (end > 0 && _isHigh(s.codeUnitAt(end - 1))) end--;
  return s.substring(0, end);
}

final _entity = RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});');

const _named = <String, String>{
  'nbsp': ' ', 'ensp': ' ', 'emsp': ' ', 'thinsp': ' ', 'hairsp': ' ',
  'zwnj': '', 'zwj': '', 'shy': '', 'lrm': '', 'rlm': '',
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'laquo': '«', 'raquo': '»', 'lsquo': '‘', 'rsquo': '’', 'sbquo': '‚',
  'ldquo': '“', 'rdquo': '”', 'bdquo': '„', 'ndash': '–', 'mdash': '—',
  'hellip': '…', 'middot': '·', 'bull': '•', 'copy': '©', 'reg': '®',
  'trade': '™', 'deg': '°', 'plusmn': '±', 'times': '×', 'divide': '÷',
  'euro': '€', 'pound': '£', 'yen': '¥', 'cent': '¢', 'sect': '§', 'para': '¶',
  'numero': '№',
};

/// Невидимые символы прехедеров рассылок. Соединитель U+200D не убирается:
/// без него распадаются составные эмодзи (👨‍👩‍👧).
final _invisible = RegExp(
    r'[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180E\u200B\u200C\u200E\u200F\u202A-\u202E'
    r'\u2060-\u2064\u206A-\u206F\u3164\uFEFF\uFFA0]');
final _hspace = RegExp(r'[ \t\u00A0\u2000-\u200A\u202F\u205F\u2800\u3000]+');

String _decodeEntity(Match m) {
  final e = m.group(1)!;
  if (e.startsWith('#')) {
    final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
    final code = int.tryParse(hex ? e.substring(2) : e.substring(1), radix: hex ? 16 : 10);
    if (code == null || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return '';
    if (code < 0x20 && code != 0x0A && code != 0x09) return '';
    return String.fromCharCode(code);
  }
  return _named[e.toLowerCase()] ?? m.group(0)!;
}

/// Текст для превью: сущности HTML — символами, невидимые символы, которыми
/// рассылки забивают начало письма («&zwnj; &zwnj; …», U+200C, U+034F,
/// мягкий перенос), — убраны, пробелы подряд — одним. Переводы строк
/// сохраняются. Текстовая часть таких писем часто содержит сущности
/// буквально — в ленте было «&zwnj; &zwnj; &zwnj;…» (замечание 27.10.2026).
String cleanPreviewText(String s) {
  var t = s;
  if (t.contains('&')) t = t.replaceAllMapped(_entity, _decodeEntity);
  return t.replaceAll(_invisible, '').replaceAll(_hspace, ' ');
}

/// Превью письма из его текста: пробелы и переводы строк — одним пробелом,
/// не длиннее [max] без разрыва эмодзи. Берётся только начало текста (письмо
/// бывает в мегабайт) — с запасом: начало рассылки бывает забито невидимыми
/// символами на сотни знаков. Пустой текст — null.
String? previewOf(String? text, [int max = 200]) {
  if (text == null || text.isEmpty) return null;
  final t = cleanPreviewText(cutSafe(text, max * 20)).replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? null : cutSafe(t, max);
}

/// Превью с переводами строк (как [cleanPreviewText]) не длиннее [max]:
/// для превью, которое хранится вместе с письмом (лента показывает 1–4 его
/// строки).
String? previewKeepingLines(String? text, [int max = 200]) {
  if (text == null || text.isEmpty) return null;
  final t = cleanPreviewText(cutSafe(text, max * 20)).replaceFirst(RegExp(r'^\s+'), '');
  return t.trim().isEmpty ? null : cutSafe(t, max);
}

/// Превью с переносами строк (1.6.31): строки письма сохраняются, пробелы
/// внутри строки — одним, пустые строки убираются. Для настройки «строк
/// текста в ленте» (1–4): «Добрый день,\n\nХочу…» → «Добрый день,\nХочу…».
/// Не длиннее [max]; пустой текст — null.
String? multilinePreviewOf(String? text, [int max = 300]) {
  if (text == null || text.isEmpty) return null;
  final lines = <String>[];
  var len = 0;
  for (final raw in cleanPreviewText(cutSafe(text, max * 20)).split(RegExp(r'\r\n|\r|\n|\u2028|\u2029'))) {
    final l = raw.replaceAll(RegExp(r'[ \t\u00A0\u200B\f\v]+'), ' ').trim();
    if (l.isEmpty) continue;
    lines.add(l);
    len += l.length + 1;
    if (len >= max) break;
  }
  if (lines.isEmpty) return null;
  return cutSafe(lines.join('\n'), max);
}

/// Первая «буква» для аватара: эмодзи — целиком, иначе заглавная буква;
/// пусто — «?».
String initialOf(String? s) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return '?';
  final c = t.codeUnitAt(0);
  if (_isHigh(c)) return t.length > 1 && _isLow(t.codeUnitAt(1)) ? t.substring(0, 2) : '?';
  if (_isLow(c)) return '?';
  return t[0].toUpperCase();
}

/// Половинки без пары — заменяются на «�». Строка без них возвращается как есть.
String fixUtf16(String s) {
  var bad = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isHigh(c)) {
      if (i + 1 < s.length && _isLow(s.codeUnitAt(i + 1))) {
        i++;
        continue;
      }
      bad = true;
      break;
    }
    if (_isLow(c)) {
      bad = true;
      break;
    }
  }
  if (!bad) return s;
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isHigh(c) && i + 1 < s.length && _isLow(s.codeUnitAt(i + 1))) {
      out.writeCharCode(c);
      out.writeCharCode(s.codeUnitAt(i + 1));
      i++;
    } else if (_isHigh(c) || _isLow(c)) {
      out.write('�');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

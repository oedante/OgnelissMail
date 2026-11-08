// lib/core/utils/quote_splitter.dart
// Разбиение HTML-тела письма на «ответ» (свежий текст) и «цитату»
// (процитированная или пересланная переписка) — чтобы цитата была свёрнута при
// открытии письма и не мешала читать новый текст.
//
// ══════════════════════════════════════════════════════════════════════
// ПОЧЕМУ ПО DOM, А НЕ ПО СТРОКЕ
// ══════════════════════════════════════════════════════════════════════
// Прежде HTML резался регулярным выражением прямо по строке — по позиции
// первого маркера («От:», «-----Original Message-----», линия из «_»).
// Русский Outlook ставит шапку «От: … Отправлено: …» внутри таблицы или
// посреди вёрстки, и разрез попадал внутрь <table>: обе половины получались
// с незакрытыми тегами, таблицы рисовались пустыми, а иногда вся таблица
// уходила в свёрнутую цитату.
//
// Теперь документ разбирается в дерево, маркер ищется среди элементов, а
// разрез идёт по границе элемента: если маркер внутри таблицы — по границе
// самой внешней таблицы. Обе половины — корректные документы: у «ответа»
// отрезано всё начиная с маркера, у «цитаты» — всё до него, обёртки
// (div.WordSection1 и т.п.) сохраняются в обеих.

import 'text_safe.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class QuoteSplit {
  final String reply;
  final String quoted;

  /// Свёрнута только подпись или юридическое уведомление в конце письма —
  /// цитаты нет (2.0.0, план 08.11.2026, п. 5): кнопка — «Показать подпись
  /// и уведомление», а не «цитируемую переписку».
  final bool tailOnly;
  QuoteSplit(this.reply, this.quoted, {this.tailOnly = false});

  /// Есть что сворачивать. Раньше сравнивалась длина HTML цитаты (> 12
  /// символов) — а у пустой цитаты одна обёртка `<html><body>…` длиннее, и
  /// письмо с пустым `<blockquote>` показывало «Показать цитату» с пустотой
  /// внутри (1.6.18). Теперь — по тексту цитаты (или картинке в ней).
  /// Считается один раз: экран письма спрашивает при каждой перерисовке.
  late final bool hasQuote = quoteHasContent(quoted);
}

/// В HTML цитаты есть текст или картинка (без тегов, стилей и пробелов).
bool quoteHasContent(String html) {
  if (html.trim().isEmpty) return false;
  if (RegExp(r'<img\b', caseSensitive: false).hasMatch(html)) return true;
  final text = html
      .replaceAll(RegExp(r'<(style|script|head)\b[\s\S]*?</\1\s*>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'&nbsp;|&#160;|&#xa0;|\s|\u00a0', caseSensitive: false), '');
  return text.isNotEmpty;
}

/// Разбить тело письма на ответ и цитату. Если маркера нет или до него нет
/// текста (письмо целиком — пересылка), возвращается всё письмо как ответ.
QuoteSplit splitQuotedHtml(String html) {
  try {
    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return QuoteSplit(html, '');
    final marker = _findMarker(body);
    dom.Element? quoteCut;
    if (marker != null) {
      quoteCut = _cutPoint(marker, body);
      // Ответ под цитатой (Gmail, Thunderbird, Apple Mail при ответе снизу,
      // или ответы вперемежку с цитатой): свёрнутая цитата спрятала бы и
      // свежий текст под ней — показываем письмо целиком (план 08.11.2026,
      // п. 5).
      if (_freshTextAfter(marker, quoteCut, body)) return QuoteSplit(html, '');
    }
    // Длинная подпись или юридическое уведомление в конце ответа (2.0.0) —
    // сворачиваются вместе с цитатой под ними; не получилось (над ними
    // почти нет текста) — разрез, как раньше, по цитате.
    final tail = _findTail(body, quoteCut);
    if (tail != null) {
      final tailCut = _cutPoint(tail, body);
      // Подпись внутри таблицы-вёрстки, где и сам ответ: разрез по таблице
      // спрятал бы письмо — не сворачиваем.
      final ownCut = identical(tailCut, tail) || _textLen(tailCut) <= _textLen(tail) + _freshMin;
      final split = ownCut ? _splitAt(doc, html, tailCut, tailOnly: marker == null, reuse: false) : null;
      if (split != null) return split;
    }
    if (quoteCut == null) return QuoteSplit(html, '');
    return _splitAt(doc, html, quoteCut) ?? QuoteSplit(html, '');
  } catch (_) {
    return QuoteSplit(html, '');
  }
}

/// Разрезать документ [doc] по узлу [cut]: ответ — до него, свёрнутая часть
/// — с него. null — разрез не годится (нечего показать до него).
QuoteSplit? _splitAt(dom.Document doc, String html, dom.Element cut, {bool tailOnly = false, bool reuse = true}) {
  try {
    final body = doc.body!;
    final path = _pathFrom(body, cut);
    if (path == null) return null;

    // Один разбор вместо трёх (1.5.9): «ответ» режется на копии дерева,
    // «цитата» — на самом разобранном документе (путь к разрезу посчитан
    // до изменений). Клонирование дерева заметно дешевле повторного
    // разбора длинной цепочки Outlook.
    final replyDoc = doc.clone(true);
    // Попытка по подписи может не подойти — тогда документ нужен целым для
    // разреза по цитате ([reuse] = false: свёрнутая часть — на копии).
    final quotedDoc = reuse ? doc : doc.clone(true);
    final replyCut = _nodeAt(replyDoc.body!, path);
    final quotedCut = _nodeAt(quotedDoc.body!, path);
    if (replyCut == null || quotedCut == null) return null;

    _keepBefore(replyCut, replyDoc.body!);
    _keepFrom(quotedCut, quotedDoc.body!);

    final replyText = replyDoc.body!.text.replaceAll(RegExp(r'\s+'), '');
    // Перед маркером нет текста — это пересылка без комментария: сворачивать
    // нечего, иначе письмо открылось бы пустым. Подпись сворачиваем, только
    // если над ней есть сам ответ.
    if (replyText.isEmpty && !_hasMedia(replyDoc.body!)) return null;
    if (tailOnly && replyText.length < _freshMin && !_hasMedia(replyDoc.body!)) return null;
    // Разрез по подписи захватил бы и сам ответ (таблица-вёрстка вокруг
    // всего письма) — не годится.
    if (tailOnly && replyText.length < 2 * _freshMin) return null;
    return QuoteSplit(replyDoc.outerHtml, quotedDoc.outerHtml, tailOnly: tailOnly);
  } catch (_) {
    return null;
  }
}

// ── Подпись и юридическое уведомление ────────────────────────────────────

/// Блоки подписи почтовых программ: Gmail, Outlook (веб и новый), Thunderbird.
bool _isSignatureBox(dom.Element el) {
  final id = el.id.toLowerCase();
  if (id == 'signature' || id == 'signature_bookmark' || id == 'appendonsend_signature') return true;
  if (el.attributes['data-smartmail'] == 'gmail_signature') return true;
  return el.classes.contains('gmail_signature') ||
      el.classes.contains('moz-signature') ||
      el.classes.contains('signature');
}

/// Подпись короче — видна целиком (имя, должность, телефон).
const _signatureMin = 300;

/// Начало юридического уведомления (ru, en, de, fr) — в первых знаках блока.
final _disclaimerLead = RegExp(
  r'(конфиденциальн|данное (?:электронное )?(?:сообщение|письмо)|настоящее (?:электронное )?(?:сообщение|письмо)'
  r'|это (?:электронное )?(?:сообщение|письмо) и (?:все|любые)|если вы получили это (?:сообщение|письмо) по ошибке'
  r'|уведомление о конфиденциальности|отказ от ответственности'
  r'|confidential|this (?:e-?mail|message)(?: and any| \(including| may contain| is intended| contains)'
  r'|the information (?:contained )?in this (?:e-?mail|message)|disclaimer|if you (?:have )?received this (?:e-?mail|message) in error'
  r'|diese e-?mail (?:enthält|kann)|vertraulich|ce (?:message|courriel) (?:et|est|peut)|confidentialité)',
  caseSensitive: false,
);

/// Юридическое уведомление: начинается одной из фраз и длиннее короткой
/// пометки «Конфиденциально».
bool _isDisclaimer(dom.Element el) {
  final text = el.text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
  if (text.length < 150 || text.length > 8000) return false;
  final head = text.length > 160 ? text.substring(0, 160) : text;
  return _disclaimerLead.hasMatch(head);
}

/// Начало хвоста письма — длинной подписи или уведомления — перед цитатой
/// ([quoteCut]; null — цитаты нет): после хвоста до цитаты (или до конца
/// письма) почти нет текста. null — хвоста нет.
dom.Element? _findTail(dom.Element body, dom.Element? quoteCut) {
  final all = body.querySelectorAll('div, p, table, span, td');
  for (final el in all) {
    if (quoteCut != null) {
      // Только до цитаты: дальше — сама цитата и её элементы.
      if (identical(el, quoteCut) || _contains(quoteCut, el)) break;
      // Обёртка вокруг цитаты — не хвост.
      if (_contains(el, quoteCut)) continue;
    }
    final isTail = (_isSignatureBox(el) && _textLen(el) >= _signatureMin) || _isDisclaimer(el);
    if (!isTail) continue;
    if (_textAfter(el, body, quoteCut) < _freshMin) return el;
  }
  return null;
}

bool _contains(dom.Element outer, dom.Node inner) {
  dom.Node? cur = inner.parentNode;
  while (cur != null) {
    if (identical(cur, outer)) return true;
    cur = cur.parentNode;
  }
  return false;
}

int _textLen(dom.Element el) => el.text.replaceAll(RegExp(r'[\s\u00a0]+'), '').length;

/// Текст после [el] (вне его) до [stop] или до конца [body].
int _textAfter(dom.Element el, dom.Element body, dom.Element? stop) {
  var len = 0;
  dom.Node? cur = el;
  while (cur != null && cur != body) {
    final parent = cur.parentNode;
    if (parent == null) break;
    final idx = parent.nodes.indexOf(cur);
    for (var i = idx + 1; i < parent.nodes.length; i++) {
      final n = parent.nodes[i];
      if (stop != null && (identical(n, stop) || (n is dom.Element && _contains(n, stop)))) {
        // Дошли до цитаты (или до её обёртки — тогда считаем только текст
        // до неё внутри обёртки).
        if (n is dom.Element && !identical(n, stop)) len += _textBefore(n, stop);
        return len;
      }
      len += n is dom.Text ? n.text.replaceAll(RegExp(r'[\s\u00a0]+'), '').length : (n is dom.Element ? _textLen(n) : 0);
      if (len >= _freshMin) return len;
    }
    cur = parent;
  }
  return len;
}

/// Текст внутри [wrap] до узла [stop].
int _textBefore(dom.Element wrap, dom.Element stop) {
  var len = 0;
  for (final n in wrap.nodes) {
    if (identical(n, stop)) return len;
    if (n is dom.Element && _contains(n, stop)) return len + _textBefore(n, stop);
    len += n is dom.Text ? n.text.replaceAll(RegExp(r'[\s\u00a0]+'), '').length : (n is dom.Element ? _textLen(n) : 0);
  }
  return len;
}

// ── Поиск маркера ─────────────────────────────────────────────────────────

const _quoteClasses = [
  'gmail_quote',
  'moz-cite-prefix',
  'yahoo_quoted',
  'OutlookMessageHeader',
  'protonmail_quote',
];
const _quoteIds = ['divRplyFwdMsg', 'appendonsend', 'mail-editor-reference-message-container'];

/// Шапка цитаты одной строкой текста элемента (без учёта регистра).
final _headerLine = RegExp(
  r'^(?:-{3,}\s*(?:original message|исходное сообщение|ursprüngliche nachricht|message d.origine)'
  r'|-{3,}\s*forwarded message|начало пересланного|пересылаемое сообщение'
  r'|on\s.{3,120}?\swrote\s*:'
  r'|[^\n]{0,120}?(?:пишет|написал(?:\(а\)|а)?|schrieb|a écrit)\s*:'
  r'|_{10,})',
  caseSensitive: false,
);

/// Блок заголовков Outlook: «От: … Отправлено/Дата: …» (ru/en/de/fr).
final _outlookHeader = RegExp(
  r'^(?:от|from|von|de)\s?:\s?.{1,300}?(?:отправлено|sent|дата|date|gesendet|envoyé)\s?:',
  caseSensitive: false,
  dotAll: true,
);

dom.Element? _findMarker(dom.Element body) {
  for (final el in body.querySelectorAll('*')) {
    final name = el.localName;
    if (name == 'blockquote') return el;
    if (_quoteIds.contains(el.id)) return el;
    for (final c in _quoteClasses) {
      if (el.classes.contains(c)) return el;
    }
    // Линия перед шапкой цитаты (Outlook).
    if (name == 'hr') {
      final next = _nextElementWithText(el);
      if (next != null && _outlookHeader.hasMatch(_lead(next))) return el;
      continue;
    }
    if (name == 'p' || name == 'div' || name == 'span' || name == 'td') {
      final lead = _lead(el);
      if (lead.isEmpty) continue;
      // «… пишет:», «On … wrote:» — только в короткой строке-шапке: в длинном
      // абзаце это может быть обычная фраза ответа («коллега пишет: …»).
      if (_outlookHeader.hasMatch(lead) || (lead.length <= 200 && _headerLine.hasMatch(lead))) {
        // Не берём обёртку всего письма: её текст начинается с той же шапки
        // только когда письмо целиком — пересылка (тогда ответа нет, и
        // splitQuotedHtml вернёт письмо целиком).
        return el;
      }
    }
  }
  return null;
}

/// Начало текста элемента одной строкой.
String _lead(dom.Element el) {
  final t = el.text.replaceAll(RegExp(r'[ \s]+'), ' ').trim();
  return cutSafe(t, 400);
}

dom.Element? _nextElementWithText(dom.Element el) {
  var n = el.nextElementSibling;
  while (n != null) {
    if (n.text.trim().isNotEmpty) return n;
    n = n.nextElementSibling;
  }
  return null;
}

bool _hasMedia(dom.Element el) => el.querySelector('img') != null;

/// Сколько знаков свежего текста под цитатой достаточно, чтобы не
/// сворачивать: меньше — подпись вроде «Иван» или «--».
const _freshMin = 20;

/// Цитата — «контейнер» (blockquote, gmail_quote и т. п., или строка
/// «… wrote:» перед blockquote), а после неё есть свежий текст вне цитат.
/// Шапка Outlook («От: … Отправлено: …», линия, «-----Original Message-----»)
/// так не проверяется: после неё идёт само старое письмо, без рамки.
bool _freshTextAfter(dom.Element marker, dom.Element cut, dom.Element body) {
  dom.Element region;
  if (_isQuoteBox(marker)) {
    region = cut;
  } else if (marker.classes.contains('moz-cite-prefix') || _isWroteLine(marker)) {
    // «On … wrote:» / moz-cite-prefix, а за ним — сама цитата.
    final next = _nextElementWithText(marker);
    if (next == null || !_isQuoteBox(next)) return false;
    region = next;
    // Разрез по таблице — тогда граница цитаты — сама таблица.
    if (!identical(cut, marker)) region = cut;
  } else {
    return false;
  }
  var fresh = 0;
  dom.Node? cur = region;
  while (cur != null && cur != body) {
    final parent = cur.parentNode;
    if (parent == null) break;
    final idx = parent.nodes.indexOf(cur);
    for (var i = idx + 1; i < parent.nodes.length; i++) {
      fresh += _freshLen(parent.nodes[i]);
      if (fresh >= _freshMin) return true;
    }
    cur = parent;
  }
  return false;
}

bool _isQuoteBox(dom.Element el) =>
    el.localName == 'blockquote' ||
    _quoteClasses.any((c) => c != 'moz-cite-prefix' && c != 'OutlookMessageHeader' && el.classes.contains(c));

bool _isWroteLine(dom.Element el) {
  final lead = _lead(el);
  return lead.length <= 200 &&
      RegExp(r'(?:wrote|пишет|написал(?:\(а\)|а)?|schrieb|a écrit)\s*:\s*$', caseSensitive: false).hasMatch(lead);
}

/// Текст узла вне цитат (вложенные blockquote и т. п. не считаются).
int _freshLen(dom.Node n) {
  if (n is dom.Text) return n.text.replaceAll(RegExp(r'[\s\u00a0]+'), '').length;
  if (n is! dom.Element) return 0;
  final tag = n.localName;
  if (tag == 'style' || tag == 'script' || _isQuoteBox(n)) return 0;
  var len = 0;
  for (final c in n.nodes) {
    len += _freshLen(c);
  }
  return len;
}

// ── Точка разреза ─────────────────────────────────────────────────────────

const _tableParts = {'table', 'tbody', 'thead', 'tfoot', 'tr', 'td', 'th', 'caption', 'colgroup', 'col'};

/// Маркер внутри таблицы — режем по самой внешней таблице: иначе одна половина
/// получила бы строки без таблицы, другая — таблицу без строк.
dom.Element _cutPoint(dom.Element marker, dom.Element body) {
  dom.Element cut = marker;
  dom.Element? cur = marker.parent;
  while (cur != null && cur != body) {
    if (cur.localName == 'table') cut = cur;
    cur = cur.parent;
  }
  // Сам маркер — часть таблицы (td/tr) без внешнего table не бывает, но на
  // всякий случай поднимаемся до ближайшей таблицы.
  if (_tableParts.contains(cut.localName) && cut.localName != 'table') {
    dom.Element? p = cut.parent;
    while (p != null && p != body && p.localName != 'table') {
      p = p.parent;
    }
    if (p != null && p != body) cut = p;
  }
  return cut;
}

// ── Путь к узлу и обрезка ─────────────────────────────────────────────────

/// Индексы дочерних узлов от body до [target].
List<int>? _pathFrom(dom.Element body, dom.Node target) {
  final path = <int>[];
  dom.Node? cur = target;
  while (cur != null && cur != body) {
    final parent = cur.parentNode;
    if (parent == null) return null;
    path.insert(0, parent.nodes.indexOf(cur));
    cur = parent;
  }
  return cur == body ? path : null;
}

dom.Node? _nodeAt(dom.Element body, List<int> path) {
  dom.Node cur = body;
  for (final i in path) {
    if (i < 0 || i >= cur.nodes.length) return null;
    cur = cur.nodes[i];
  }
  return cur;
}

/// Оставить всё ДО узла: сам узел и всё после него на каждом уровне — убрать.
void _keepBefore(dom.Node cut, dom.Element body) {
  dom.Node cur = cut;
  var removeSelf = true;
  while (cur != body) {
    final parent = cur.parentNode;
    if (parent == null) break;
    final idx = parent.nodes.indexOf(cur);
    final from = removeSelf ? idx : idx + 1;
    for (var i = parent.nodes.length - 1; i >= from; i--) {
      parent.nodes[i].remove();
    }
    removeSelf = false;
    cur = parent;
  }
}

/// Оставить всё НАЧИНАЯ с узла: всё перед ним на каждом уровне — убрать.
void _keepFrom(dom.Node cut, dom.Element body) {
  dom.Node cur = cut;
  while (cur != body) {
    final parent = cur.parentNode;
    if (parent == null) break;
    final idx = parent.nodes.indexOf(cur);
    for (var i = idx - 1; i >= 0; i--) {
      parent.nodes[i].remove();
    }
    cur = parent;
  }
}

/// Свежий текст письма без цитаты — для простого текста (1.10.1). Строки,
/// начинающиеся с «>», пропускаются; на шапке цитаты («On … wrote:»,
/// «… пишет:», «-----Original Message-----», «От: … Отправлено: …») текст
/// обрывается. Перевод определяет язык письма по этой части: цитата на
/// другом языке сбивала определение — «Не удалось перевести» (замечание
/// владельца 02.11.2026).
String replyPartOfPlain(String plain) {
  final lines = plain.split('\n');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.startsWith('>')) continue;
    if (t.isNotEmpty && _headerLine.hasMatch(t)) break;
    // Gmail переносит «On Thu, 29 Oct 2026 at 21:55, Имя\n<адрес> wrote:» на
    // две строки (1.10.5, письмо владельца 03.11.2026) — проверяем и пару.
    if (t.isNotEmpty && i + 1 < lines.length && _headerLine.hasMatch('$t ${lines[i + 1].trim()}')) break;
    if (t.isNotEmpty && _outlookHeader.hasMatch(lines.skip(i).take(6).join('\n').trim())) break;
    out.add(lines[i]);
  }
  final reply = out.join('\n').trim();
  return reply.isEmpty ? plain : reply;
}


/// Письмо без HTML: свежий текст и свёрнутая часть (план 08.11.2026, п. 5:
/// «простой текст — сворачивать «>» и подпись «-- »»). Свёрнутая часть
/// начинается с шапки цитаты («On … wrote:», «… пишет:», «От: …
/// Отправлено: …», «-----Original Message-----»), с первой строки «>» или
/// с подписи «-- » (RFC 3676), если за ней цитата или подпись длинная.
/// Не сворачивается: нечего показать до разреза; ответ под цитатой «>»
/// (свежий текст после строк «>»). Нечего сворачивать — quoted пустая.
QuoteSplit splitQuotedPlain(String plain) {
  final lines = plain.split('\n');
  int? quoteAt;
  var outlook = false;
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.isEmpty) continue;
    if (t.startsWith('>')) {
      quoteAt = i;
      break;
    }
    if (_headerLine.hasMatch(t) ||
        (i + 1 < lines.length && _headerLine.hasMatch('$t ${lines[i + 1].trim()}'))) {
      quoteAt = i;
      break;
    }
    if (_outlookHeader.hasMatch(lines.skip(i).take(6).join('\n').trim())) {
      quoteAt = i;
      outlook = true;
      break;
    }
  }
  int? sigAt;
  for (var i = 0; i < (quoteAt ?? lines.length); i++) {
    if (lines[i].trimRight() == '--') {
      sigAt = i;
      break;
    }
  }
  // Подпись сворачивается, если за ней цитата или в ней больше 4 строк
  // (реклама, подвал рассылки); короткая подпись — имя, телефон — видна.
  if (sigAt != null && quoteAt == null) {
    final sigLines = lines.skip(sigAt + 1).where((l) => l.trim().isNotEmpty).length;
    if (sigLines <= 4) sigAt = null;
  }
  final cut = sigAt ?? quoteAt;
  if (cut == null) return QuoteSplit(plain, '');
  final reply = lines.take(cut).join('\n').trimRight();
  if (reply.trim().isEmpty) return QuoteSplit(plain, '');
  // Ответ под цитатой «>»: свежий текст после строк «>» (до подписи).
  if (quoteAt != null && !outlook && sigAt == null) {
    var seenQuote = false;
    var fresh = 0;
    for (var i = quoteAt; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('>')) {
        seenQuote = true;
        continue;
      }
      if (t == '--' || lines[i].trimRight() == '--') break;
      if (!seenQuote || t.isEmpty || _headerLine.hasMatch(t)) continue;
      fresh += t.replaceAll(RegExp(r'\s+'), '').length;
      if (fresh >= _freshMin) return QuoteSplit(plain, '');
    }
  }
  return QuoteSplit(reply, lines.skip(cut).join('\n'), tailOnly: sigAt != null && quoteAt == null);
}

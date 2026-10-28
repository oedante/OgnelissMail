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
  QuoteSplit(this.reply, this.quoted);

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
    if (marker == null) return QuoteSplit(html, '');
    final cut = _cutPoint(marker, body);
    final path = _pathFrom(body, cut);
    if (path == null) return QuoteSplit(html, '');

    // Один разбор вместо трёх (1.5.9): «ответ» режется на копии дерева,
    // «цитата» — на самом разобранном документе (путь к разрезу посчитан
    // до изменений). Клонирование дерева заметно дешевле повторного
    // разбора длинной цепочки Outlook.
    final replyDoc = doc.clone(true);
    final quotedDoc = doc;
    final replyCut = _nodeAt(replyDoc.body!, path);
    final quotedCut = _nodeAt(quotedDoc.body!, path);
    if (replyCut == null || quotedCut == null) return QuoteSplit(html, '');

    _keepBefore(replyCut, replyDoc.body!);
    _keepFrom(quotedCut, quotedDoc.body!);

    final replyText = replyDoc.body!.text.replaceAll(RegExp(r'\s+'), '');
    // Перед маркером нет текста — это пересылка без комментария: сворачивать
    // нечего, иначе письмо открылось бы пустым.
    if (replyText.isEmpty && !_hasMedia(replyDoc.body!)) return QuoteSplit(html, '');
    return QuoteSplit(replyDoc.outerHtml, quotedDoc.outerHtml);
  } catch (_) {
    return QuoteSplit(html, '');
  }
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

// lib/core/utils/quote_people.dart
//
// Люди в шапках цитат (1.10.3, экспериментальная функция, по умолчанию
// выключена; просьба владельца 02.11.2026: «в цитируемых письмах получатель
// и отправитель отображаются ссылками — преобразовывать в контакты с
// портретами… сначала отключаемой функцией»).
//
// Строки «От: / Кому: / Копия:» (и From, To, Cc, Von, An, De, À…) в шапках
// цитат Outlook и пересылок Gmail становятся ссылками `ogperson:` с именем;
// экран письма рисует их «плашками» людей тем же портретом, что в шапке
// письма (фото из контактов или буква), окно браузера — стилем документа.
// Нажатие — карточка человека. Человек без адреса (внутренний адрес
// Exchange, «Хабиров Ренат Фанильевич») — плашка без карточки.
//
// Скорость открытия письма не меняется: разбор идёт только когда цитата
// раскрыта и функция включена; письмо разбирается по дереву HTML один раз
// (как при подготовке документа), на 40 КБ — единицы миллисекунд.
//
// Подписи и дата шапки — на языке приложения (1.11.x, замечание владельца
// 04.11.2026: «в цитатах дата отправления и от/кому/копия отображаются на
// английском»): «From / Sent / To / Cc / Subject» (и Date, Von, Gesendet,
// De, Envoyé…) — подписями приложения (quoteFrom…, те же, что в ответе на
// письмо), «Thursday, October 22, 2026 2:48 PM» — датой и временем языка
// приложения. Только в настоящей шапке — двух и больше таких строках
// подряд, среди них «от» или «отправлено»: строка «Тема: …» в тексте
// письма остаётся как есть. Работает и при выключенных плашках людей.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show DateFormat;

import 'person_name.dart';


/// Человек из строки шапки: адрес может отсутствовать (внутренний Exchange).
class QuotePerson {
  final String name;
  final String? email;
  const QuotePerson(this.name, this.email);

  String get display => name.isNotEmpty ? name : (email ?? '');

  @override
  String toString() => email == null ? name : '$name <$email>';
}

/// Подписи шапки цитаты на языке приложения и язык для даты. Простые
/// данные: разбор письма идёт в рабочем изоляте.
class QuoteHeaderText {
  /// Язык приложения (ru, en, de …) — для формата даты.
  final String locale;

  /// from, sent, to, cc, subject → подпись с двоеточием («От:», «De :»).
  final Map<String, String> labels;
  const QuoteHeaderText(this.locale, this.labels);
}

class QuotePeople {
  QuotePeople._();

  /// Схема ссылки плашки: `ogperson:адрес?n=Имя`.
  static const scheme = 'ogperson';

  /// Подписи строк с людьми. «Отправлено», «Тема», «Дата» не трогаем.
  static final _label = RegExp(
    r'^\s*(from|to|cc|от|кому|копия|von|an|kopie|de|à|a|para|cc|da|van|aan|od|do|kopia|från|till|kopia|lähettäjä|vastaanottaja|kimden|kime|bilgi)\s*:?\s*$',
    caseSensitive: false,
  );
  static final _plainLabel = RegExp(
    r'^(\s*)(from|to|cc|от|кому|копия|von|an|kopie|de|à|para|da|van|aan)\s*:\s*',
    caseSensitive: false,
  );

  /// Не больше стольких плашек в письме: огромные списки рассылки остаются
  /// текстом. 1.14.0 (письмо владельца 06.11.2026, «Кому» — 73 человека):
  /// было 60, и строка, не влезавшая в остаток, обрезалась — люди сверх
  /// предела пропадали из шапки, а «Копия» оставалась текстом. Теперь
  /// предел больше, а строка, которая в него не помещается, остаётся
  /// текстом целиком — никто не теряется.
  static const maxPeople = 300;

  /// Разобрать значение строки: «Имя <адрес>; Имя <адрес>», «адрес, адрес»,
  /// «Имя [mailto:адрес]», «Имя» без адреса.
  static List<QuotePerson> parse(String value) {
    final v = value.replaceAll(' ', ' ').replaceAllMapped(
        RegExp(r'\[mailto:([^\]\s]+)\]', caseSensitive: false), (m) => '<${m[1]}>');
    final out = <QuotePerson>[];
    final angled = RegExp(r'"?([^"<>;]*?)"?\s*<\s*([^<>\s]+@[^<>\s]+)\s*>');
    final matches = angled.allMatches(v).toList();
    if (matches.isNotEmpty) {
      var last = 0;
      for (final m in matches) {
        // Между записями — люди без адреса («Имя;»), их тоже показываем.
        _bare(v.substring(last, m.start), out);
        final name = _cleanName(m[1] ?? '');
        out.add(QuotePerson(name, m[2]!.trim()));
        last = m.end;
      }
      _bare(v.substring(last), out);
      return out;
    }
    _bare(v, out);
    return out;
  }

  static void _bare(String chunk, List<QuotePerson> out) {
    for (final raw in chunk.split(RegExp(r'[;,]'))) {
      final t = _cleanName(raw);
      if (t.isEmpty) continue;
      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) {
        out.add(QuotePerson('', t));
      } else if (RegExp(r'\p{L}', unicode: true).hasMatch(t) && t.length <= 80) {
        out.add(QuotePerson(t, null));
      }
    }
  }

  static String _cleanName(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'''^[\s,;'"]+|[\s,;'"]+$'''), '').trim();

  /// То же, что [enrich], с краткими именами: «Фамилия И.О.» (1.10.5, по
  /// умолчанию). Полное имя остаётся в ссылке — для карточки человека.
  static String enrichShort(String html) => enrich(html, shortNames: true);

  /// Шапки цитат в [html] — ссылками на людей (плашки рисует экран письма;
  /// [people] = false — без плашек), подписи и дата — на языке приложения
  /// ([local]; null — как в письме). Ничего не изменилось — исходный HTML.
  static String enrich(String html, {bool shortNames = false, bool people = true, QuoteHeaderText? local}) {
    if (!_mayHaveHeaders(html)) return html;
    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return html;
    var changed = people && _people(body, shortNames);
    if (local != null && _localize(body, local)) changed = true;
    return changed ? (doc.documentElement?.outerHtml ?? html) : html;
  }

  /// Плашки людей в строках «От / Кому / Копия»; true — что-то заменено.
  static bool _people(dom.Element body, bool shortNames) {
    final events = <_Ev>[];
    _walk(body, events);
    var people = 0;
    var changed = false;
    for (var i = 0; i < events.length && people < maxPeople; i++) {
      final e = events[i];
      dom.Text? plainLabelNode;
      String plainRest = '';
      if (e.kind == _K.label) {
        // ok
      } else if (e.kind == _K.text && (i == 0 || events[i - 1].kind == _K.brk)) {
        final m = _plainLabel.firstMatch((e.node as dom.Text).data);
        if (m == null) continue;
        plainLabelNode = e.node as dom.Text;
        plainRest = plainLabelNode.data.substring(m.end);
        plainLabelNode.data = plainLabelNode.data.substring(0, m.end);
      } else {
        continue;
      }
      // Значение — текст и ссылки до конца строки.
      final parts = <dom.Node>[];
      final buf = StringBuffer(plainRest);
      var j = i + 1;
      for (; j < events.length; j++) {
        final x = events[j];
        if (x.kind == _K.brk || x.kind == _K.label) break;
        parts.add(x.node);
        buf.write(x.kind == _K.text ? (x.node as dom.Text).data : (x.node as dom.Element).text);
      }
      final list = parse(buf.toString());
      // Подпись обычным текстом («To: всем сотрудникам» в самом письме) —
      // только с адресами: без них это скорее фраза, а не шапка цитаты.
      if (plainLabelNode != null) list.removeWhere((p) => p.email == null);
      if (list.isEmpty || people + list.length > maxPeople) {
        if (plainLabelNode != null) plainLabelNode.data += plainRest;
        continue;
      }
      final chips = html_parser.parseFragment(' ${[for (final p in list) _chip(p, shortNames)].join(' ')}');
      people += list.length;
      final anchor = plainLabelNode ?? e.node;
      final parent = anchor.parentNode;
      if (parent == null) continue;
      final at = parent.nodes.indexOf(anchor) + 1;
      parent.nodes.insertAll(at, chips.nodes.toList());
      for (final p in parts) {
        p.remove();
      }
      changed = true;
      i = j - 1;
    }
    return changed;
  }

  /// Быстрая проверка без разбора: есть ли вообще подписи строк шапки.
  static bool _mayHaveHeaders(String html) =>
      RegExp(r'(From|To|Cc|От|Кому|Копия|Von|An|De|Sent|Date|Gesendet|Envoyé|Отправлено)\s*:', caseSensitive: false)
          .hasMatch(html);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Простая ссылка `ogperson:` с именем (1.10.4): плашку с портретом рисует
  /// экран письма — тем же портретом, что в шапке письма (QuotePersonChip),
  /// а в окне браузера — стиль документа. В 1.10.3 плашка была вёрсткой
  /// (inline-block, картинка) — письмо из-за неё переставало быть «простым»,
  /// уходило в окно браузера и широкое уменьшалось целиком (замечание
  /// владельца 03.11.2026: «делает письмо очень мелким»).
  static String _chip(QuotePerson p, bool shortNames) {
    final href = '$scheme:${p.email == null ? '' : Uri.encodeComponent(p.email!)}'
        '?n=${Uri.encodeQueryComponent(p.name)}';
    final text = shortNames && p.name.isNotEmpty ? PersonName.display(p.name, shortForm: true) : p.display;
    final title = text == p.display ? '' : ' title="${_esc(p.display)}"';
    return '<a href="${_esc(href)}"$title>${_esc(text)}</a>';
  }

  /// Ссылка плашки человека (с адресом или без).
  static bool isLink(String url) => url.toLowerCase().startsWith('$scheme:');

  /// Имя из ссылки плашки (и у человека без адреса).
  static String? nameOf(String url) {
    final q = url.indexOf('?');
    if (!isLink(url) || q < 0) return null;
    try {
      final n = Uri.splitQueryString(url.substring(q + 1))['n']?.trim();
      return (n == null || n.isEmpty) ? null : n;
    } catch (_) {
      return null;
    }
  }

  /// Адрес и имя из ссылки `ogperson:`; не она — null.
  static ({String email, String? name})? fromLink(String url) {
    if (!url.toLowerCase().startsWith('$scheme:')) return null;
    final rest = url.substring(scheme.length + 1);
    final q = rest.indexOf('?');
    final email = Uri.decodeComponent(q < 0 ? rest : rest.substring(0, q)).trim();
    if (!email.contains('@')) return null;
    String? name;
    if (q >= 0) {
      try {
        name = Uri.splitQueryString(rest.substring(q + 1))['n'];
      } catch (_) {}
    }
    return (email: email, name: (name == null || name.trim().isEmpty) ? null : name.trim());
  }

  // ── Подписи и дата шапки на языке приложения (1.11.x) ──

  /// Подпись строки шапки (без двоеточия, строчными) → её смысл. Языки —
  /// те, на которых Outlook, Gmail и почта Apple пишут шапку цитаты.
  static const _kinds = {
    'from': 'from', 'от': 'from', 'von': 'from', 'de': 'from', 'da': 'from', 'van': 'from', 'od': 'from',
    'från': 'from', 'lähettäjä': 'from', 'kimden': 'from',
    'to': 'to', 'кому': 'to', 'an': 'to', 'à': 'to', 'a': 'to', 'para': 'to', 'aan': 'to', 'do': 'to',
    'till': 'to', 'vastaanottaja': 'to', 'kime': 'to',
    'cc': 'cc', 'копия': 'cc', 'kopie': 'cc', 'kopia': 'cc', 'bilgi': 'cc',
    'sent': 'sent', 'date': 'sent', 'отправлено': 'sent', 'дата': 'sent', 'gesendet': 'sent', 'datum': 'sent',
    'envoyé': 'sent', 'enviado': 'sent', 'enviada': 'sent', 'fecha': 'sent', 'inviato': 'sent', 'data': 'sent',
    'verzonden': 'sent', 'wysłano': 'sent', 'skickat': 'sent', 'lähetetty': 'sent', 'päivämäärä': 'sent',
    'gönderildi': 'sent', 'tarih': 'sent', 'odesláno': 'sent',
    'subject': 'subject', 'тема': 'subject', 'betreff': 'subject', 'objet': 'subject', 'asunto': 'subject',
    'assunto': 'subject', 'oggetto': 'subject', 'onderwerp': 'subject', 'temat': 'subject', 'ämne': 'subject',
    'aihe': 'subject', 'konu': 'subject', 'předmět': 'subject',
  };

  /// Подпись в начале строки: слово и двоеточие (у французского — через
  /// пробел, «De :»).
  static final _lineLabel = RegExp(r'^(\s*)([\p{L}]+)(\s*:)', unicode: true);

  /// Перевести подписи и дату в шапках цитат; true — что-то заменено.
  static bool _localize(dom.Element body, QuoteHeaderText local) {
    final events = <_Ev>[];
    _walkHeaders(body, events);
    // Строки документа: события между переносами.
    final lines = <List<_Ev>>[];
    var cur = <_Ev>[];
    for (final e in events) {
      if (e.kind == _K.brk) {
        if (cur.isNotEmpty) lines.add(cur);
        cur = <_Ev>[];
      } else {
        cur.add(e);
      }
    }
    if (cur.isNotEmpty) lines.add(cur);

    String? kindOf(List<_Ev> line) {
      final first = line.first;
      final t = first.kind == _K.label || first.kind == _K.text ? first.node.text ?? '' : '';
      final m = _lineLabel.firstMatch(t);
      if (m == null) return null;
      // Подпись-элемент (<b>From:</b>) — только слово с двоеточием.
      if (first.kind == _K.label && t.substring(m.end).trim().isNotEmpty) return null;
      return _kinds[m.group(2)!.toLowerCase()];
    }

    final kinds = [for (final l in lines) kindOf(l)];
    var changed = false;
    var i = 0;
    while (i < lines.length) {
      if (kinds[i] == null) {
        i++;
        continue;
      }
      var j = i;
      while (j < lines.length && kinds[j] != null) {
        j++;
      }
      final block = {for (var k = i; k < j; k++) kinds[k]!};
      // Шапка — две и больше подписей подряд, среди них «от» или «дата».
      if (block.length >= 2 && (block.contains('from') || block.contains('sent'))) {
        for (var k = i; k < j; k++) {
          if (_localizeLine(lines[k], kinds[k]!, local)) changed = true;
        }
      }
      i = j;
    }
    return changed;
  }

  static bool _localizeLine(List<_Ev> line, String kind, QuoteHeaderText local) {
    final label = local.labels[kind];
    if (label == null) return false;
    final first = line.first;
    // Текстовый узел с подписью: у <b>From:</b> — внутри элемента.
    final dom.Text? node = first.kind == _K.text ? first.node as dom.Text : _firstText(first.node);
    if (node == null) return false;
    final m = _lineLabel.firstMatch(node.data);
    if (m == null) return false;
    var changed = false;
    // Двоеточие подписи приложения («От:», «De :») — вместо исходного.
    final word = label.replaceFirst(RegExp(r'\s*:\s*$'), '');
    final replaced = '${m.group(1)}$word${label.substring(word.length).trimRight()}';
    if (node.data.substring(0, m.end) != replaced) {
      node.data = replaced + node.data.substring(m.end);
      changed = true;
    }
    if (kind == 'sent' && _localizeDate(line, first.kind == _K.text ? replaced.length : 0, local)) changed = true;
    return changed;
  }

  static dom.Text? _firstText(dom.Node n) {
    for (final c in n.nodes) {
      if (c is dom.Text && c.data.trim().isNotEmpty) return c;
      final t = _firstText(c);
      if (t != null) return t;
    }
    return null;
  }

  /// Дата строки «Sent:» / «Date:»: весь её текст после подписи — один
  /// разбираемый текст; иначе (ссылки, разметка внутри) — как есть.
  static bool _localizeDate(List<_Ev> line, int skip, QuoteHeaderText local) {
    if (local.locale.toLowerCase().startsWith('en')) return false;
    final texts = <dom.Text>[];
    for (var k = 0; k < line.length; k++) {
      final e = line[k];
      if (k == 0 && e.kind == _K.label) continue;
      if (e.kind != _K.text) return false;
      texts.add(e.node as dom.Text);
    }
    if (texts.isEmpty) return false;
    final raw = [for (var k = 0; k < texts.length; k++) k == 0 ? texts[k].data.substring(skip) : texts[k].data].join();
    final parsed = parseHeaderDate(raw);
    if (parsed == null) return false;
    final text = formatHeaderDate(parsed, local.locale);
    if (text == null) return false;
    final lead = RegExp(r'^\s*').firstMatch(raw)!.group(0)!;
    texts.first.data = '${texts.first.data.substring(0, skip)}${lead.isEmpty && skip > 0 ? ' ' : lead}$text';
    for (final t in texts.skip(1)) {
      t.remove();
    }
    return true;
  }

  static const _months = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12, 'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _monthAlt = (_months.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');
  static final _dateRe = RegExp(
    r'^\s*(?:(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?,?\s+)?'
    '(?:(?<m1>$_monthAlt)\\.?\\s+(?<d1>\\d{1,2}),?\\s+(?<y1>\\d{4})|(?<d2>\\d{1,2})\\s+(?<m2>$_monthAlt)\\.?,?\\s+(?<y2>\\d{4}))'
    r'(?:,?\s*(?:at\s+)?(?<h>\d{1,2}):(?<mi>\d{2})(?::\d{2})?\s*(?<ap>[ap]\.?\s?m\.?)?)?'
    r'(?<rest>.*)$',
    caseSensitive: false,
    dotAll: true,
  );

  /// Дата шапки по-английски: Outlook «Thursday, October 22, 2026 2:48 PM»,
  /// Gmail «Mon, Nov 2, 2026 at 5:57 PM», Apple «2 Nov 2026 at 17:57»,
  /// RFC 2822 «Mon, 2 Nov 2026 17:57:00 +0300» (пояс — остаётся хвостом,
  /// время — как написано). Не дата — null.
  static ({DateTime at, bool weekday, bool time, String rest})? parseHeaderDate(String s) {
    final m = _dateRe.firstMatch(s);
    if (m == null) return null;
    final month = _months[(m.namedGroup('m1') ?? m.namedGroup('m2'))!.toLowerCase()]!;
    final day = int.parse((m.namedGroup('d1') ?? m.namedGroup('d2'))!);
    final year = int.parse((m.namedGroup('y1') ?? m.namedGroup('y2'))!);
    if (day < 1 || day > 31) return null;
    var hour = 0, minute = 0;
    final h = m.namedGroup('h');
    if (h != null) {
      hour = int.parse(h);
      minute = int.parse(m.namedGroup('mi')!);
      final ap = (m.namedGroup('ap') ?? '').toLowerCase().replaceAll(RegExp(r'[.\s]'), '');
      if (ap == 'pm' && hour < 12) hour += 12;
      if (ap == 'am' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) return null;
    }
    final at = DateTime(year, month, day, hour, minute);
    if (at.day != day) return null; // 31 ноября
    final rest = m.namedGroup('rest')!.trim();
    // Хвост — пояс («+0300», «(UTC+05:00) Екатеринбург») или ничего; иначе
    // это не дата, а фраза с датой внутри.
    if (rest.isNotEmpty && !RegExp(r'^[(+\-−]?\s*(utc|gmt|[+\-−]\d)', caseSensitive: false).hasMatch(rest)) return null;
    return (at: at, weekday: RegExp(r'^\s*[a-z]', caseSensitive: false).hasMatch(s), time: h != null, rest: rest);
  }

  static bool _intlReady = false;

  /// Дата шапки на языке [locale]: «четверг, 22 октября 2026 г. 14:48».
  /// Язык без данных intl — null (остаётся как в письме).
  static String? formatHeaderDate(({DateTime at, bool weekday, bool time, String rest}) d, String locale) {
    // Данные языков intl — свои у каждого изолята; разбор идёт в рабочем.
    if (!_intlReady) {
      initializeDateFormatting();
      _intlReady = true;
    }
    final loc = locale.replaceAll('-', '_');
    if (!DateFormat.localeExists(loc)) return null;
    try {
      final date = (d.weekday ? DateFormat.yMMMMEEEEd(loc) : DateFormat.yMMMMd(loc)).format(d.at);
      final time = d.time ? ' ${DateFormat.jm(loc).format(d.at)}' : '';
      return '$date$time${d.rest.isEmpty ? '' : ' ${d.rest}'}';
    } catch (_) {
      return null;
    }
  }

  /// Обход для шапок: подписи — любые жирные слова с двоеточием (Sent,
  /// Subject — тоже), остальное — как в [_walk].
  static void _walkHeaders(dom.Node n, List<_Ev> out) {
    for (final c in n.nodes.toList()) {
      if (c is dom.Text) {
        if (c.data.trim().isNotEmpty) out.add(_Ev(_K.text, c));
      } else if (c is dom.Element) {
        final tag = c.localName ?? '';
        if (tag == 'br') {
          out.add(_Ev(_K.brk, c));
        } else if ((tag == 'b' || tag == 'strong') && _lineLabel.hasMatch(c.text)) {
          out.add(_Ev(_K.label, c));
        } else if (tag == 'a') {
          out.add(_Ev(_K.link, c));
        } else if (tag == 'script' || tag == 'style' || tag == 'img') {
          continue;
        } else if (_blocks.contains(tag)) {
          out.add(_Ev(_K.brk, c));
          _walkHeaders(c, out);
          out.add(_Ev(_K.brk, c));
        } else {
          _walkHeaders(c, out);
        }
      }
    }
  }

  // ── Обход документа: текст, ссылки, переносы строк и подписи по порядку ──

  static const _blocks = {
    'p', 'div', 'table', 'tr', 'td', 'th', 'li', 'ul', 'ol', 'blockquote', 'hr', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'section', 'article', 'header', 'footer', 'body',
  };

  static void _walk(dom.Node n, List<_Ev> out) {
    for (final c in n.nodes.toList()) {
      if (c is dom.Text) {
        if (c.data.trim().isNotEmpty) out.add(_Ev(_K.text, c));
      } else if (c is dom.Element) {
        final tag = c.localName ?? '';
        if (tag == 'br') {
          out.add(_Ev(_K.brk, c));
        } else if ((tag == 'b' || tag == 'strong') && _label.hasMatch(c.text)) {
          out.add(_Ev(_K.label, c));
        } else if (tag == 'a') {
          out.add(_Ev(_K.link, c));
        } else if (tag == 'script' || tag == 'style' || tag == 'img') {
          continue;
        } else if (_blocks.contains(tag)) {
          out.add(_Ev(_K.brk, c));
          _walk(c, out);
          out.add(_Ev(_K.brk, c));
        } else {
          _walk(c, out);
        }
      }
    }
  }
}

enum _K { text, link, brk, label }

class _Ev {
  final _K kind;
  final dom.Node node;
  const _Ev(this.kind, this.node);
}

// lib/core/utils/mentions.dart
// @-упоминания (2.2.0, план 08.11.2026 «из мессенджеров»: «@-упоминания и
// значок @ в ленте», как «@» в Outlook и «+» в Gmail).
//
// Письмо упоминает владельца ящика, если в его свежей части (без цитаты
// прежней переписки):
//  · ссылка-упоминание на его адрес: Outlook и OWA вставляют
//    <a href="mailto:адрес" id="OWAAM…">@Имя</a>, Gmail —
//    <a class="gmail_plusreply" href="mailto:адрес">+Имя</a>; годится и
//    любая mailto-ссылка на его адрес с текстом, начатым с «@» или «+»;
//  · или «@Имя Фамилия» текстом — полное имя ящика или «@Фамилия Имя».
// Одно «@Иван» без фамилии — не упоминание: тёзок в рабочей переписке много.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'quote_splitter.dart';

class Mentions {
  Mentions._();

  static final _spaces = RegExp(r'\s+');

  /// Варианты имени для «@Имя»: полное имя ящика, «Имя Фамилия» и
  /// «Фамилия Имя» (у трёхсловного русского «Фамилия Имя Отчество» — оба
  /// порядка первых двух слов). Нижний регистр, одинарные пробелы.
  static List<String> nameForms(Iterable<String> names) {
    final out = <String>{};
    for (final raw in names) {
      final n = raw.replaceAll(RegExp(r'[,"«»()]'), ' ').trim().replaceAll(_spaces, ' ').toLowerCase();
      final parts = n.split(' ');
      if (parts.length < 2) continue;
      out.add(n);
      out.add('${parts[0]} ${parts[1]}');
      out.add('${parts[1]} ${parts[0]}');
    }
    return out.toList();
  }

  /// Есть ли «@Имя Фамилия» в [text] (после имени — не буква).
  static bool namedIn(String text, List<String> forms) {
    if (forms.isEmpty || !text.contains('@')) return false;
    final t = text.replaceAll(_spaces, ' ').toLowerCase();
    for (final f in forms) {
      var at = t.indexOf('@$f');
      while (at >= 0) {
        // Перед «@» — не часть адреса почты (ivan@petrov…).
        final before = at == 0 ? ' ' : t[at - 1];
        final end = at + 1 + f.length;
        final after = end >= t.length ? ' ' : t[end];
        if (!_isWordChar(before) && !_isWordChar(after)) return true;
        at = t.indexOf('@$f', at + 1);
      }
    }
    return false;
  }

  static bool _isWordChar(String c) => RegExp(r'[\p{L}\p{N}_.-]', unicode: true).hasMatch(c);

  /// Упоминает ли письмо владельца ящика: [emails] — его адреса, [names] —
  /// его имена (имя ящика, имя в адресной книге). [html] — тело письма;
  /// нет — [text] (письмо без HTML или только начало письма).
  static bool mentionsMe({
    String? html,
    String? text,
    required Iterable<String> emails,
    required Iterable<String> names,
  }) {
    final mine = {for (final e in emails) e.trim().toLowerCase()}..remove('');
    final forms = nameForms(names);
    if (mine.isEmpty && forms.isEmpty) return false;
    if (html != null && html.trim().isNotEmpty) {
      final fresh = splitQuotedHtml(html).reply;
      final body = html_parser.parse(fresh).body;
      if (body == null) return false;
      for (final a in body.querySelectorAll('a[href]')) {
        if (_mentionLink(a, mine)) return true;
      }
      return namedIn(body.text, forms);
    }
    if (text == null || text.trim().isEmpty) return false;
    return namedIn(splitQuotedPlain(text).reply, forms);
  }

  static bool _mentionLink(dom.Element a, Set<String> mine) {
    final href = (a.attributes['href'] ?? '').trim();
    if (!href.toLowerCase().startsWith('mailto:')) return false;
    var addr = href.substring(7);
    final q = addr.indexOf('?');
    if (q >= 0) addr = addr.substring(0, q);
    try {
      addr = Uri.decodeComponent(addr);
    } catch (_) {}
    if (!mine.contains(addr.trim().toLowerCase())) return false;
    final id = a.attributes['id'] ?? '';
    final cls = (a.attributes['class'] ?? '').toLowerCase();
    final shown = a.text.trim();
    return id.startsWith('OWAAM') ||
        cls.contains('gmail_plusreply') ||
        cls.contains('mention') ||
        shown.startsWith('@') ||
        shown.startsWith('+');
  }
}

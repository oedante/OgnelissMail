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

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;


/// Человек из строки шапки: адрес может отсутствовать (внутренний Exchange).
class QuotePerson {
  final String name;
  final String? email;
  const QuotePerson(this.name, this.email);

  String get display => name.isNotEmpty ? name : (email ?? '');

  @override
  String toString() => email == null ? name : '$name <$email>';
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
  /// текстом.
  static const maxPeople = 60;

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

  /// Шапки цитат в [html] — ссылками на людей (плашки рисует экран письма).
  /// Ничего не нашлось — исходный HTML.
  static String enrich(String html) {
    if (!_mayHaveHeaders(html)) return html;
    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return html;
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
      if (list.isEmpty) {
        if (plainLabelNode != null) plainLabelNode.data += plainRest;
        continue;
      }
      final chips = html_parser.parseFragment(
          ' ${[for (final p in list.take(maxPeople - people)) _chip(p)].join(' ')}');
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
    return changed ? (doc.documentElement?.outerHtml ?? html) : html;
  }

  /// Быстрая проверка без разбора: есть ли вообще подписи строк шапки.
  static bool _mayHaveHeaders(String html) =>
      RegExp(r'(From|To|Cc|От|Кому|Копия|Von|An|De)\s*:', caseSensitive: false).hasMatch(html);

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
  static String _chip(QuotePerson p) {
    final href = '$scheme:${p.email == null ? '' : Uri.encodeComponent(p.email!)}'
        '?n=${Uri.encodeQueryComponent(p.name)}';
    return '<a href="${_esc(href)}">${_esc(p.display)}</a>';
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

// lib/services/translation/translation_text.dart
//
// Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026): разбор
// текста на куски для переводчика и сборка обратно.
//
// HTML переводчику целиком не отдаём: движки на устройстве (ML Kit, Apple
// Translation) переводят текст, а разметку портят — теряются ссылки,
// таблицы рассылок разъезжаются. Поэтому переводятся только текстовые узлы,
// а разметка, ссылки и картинки остаются как были. Стили, скрипты, код и
// преформатированный текст не трогаются.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Куски текста HTML-письма: [texts] — что переводить, [rebuild] — тот же
/// документ с переводом вместо исходного текста.
class HtmlTextSegments {
  final dom.Node _root;
  final bool _document;
  final List<dom.Text> _nodes;
  final List<String> _lead;
  final List<String> _trail;

  /// Текст кусков без пробелов по краям (пробелы возвращаются при сборке).
  final List<String> texts;

  HtmlTextSegments._(this._root, this._document, this._nodes, this._lead, this._trail, this.texts);

  /// Теги, внутри которых текст не переводится: оформление, скрипты, код
  /// (имена переменных и команды перевод испортил бы), формулы.
  static const skipTags = {
    'script', 'style', 'code', 'pre', 'kbd', 'samp', 'var', 'tt', 'textarea',
    'noscript', 'template', 'svg', 'math', 'head', 'title',
  };

  factory HtmlTextSegments.parse(String html) {
    final document = _fullDocument.hasMatch(html);
    final dom.Node root = document ? html_parser.parse(html) : html_parser.parseFragment(html);
    final nodes = <dom.Text>[];
    final lead = <String>[];
    final trail = <String>[];
    final texts = <String>[];
    void walk(dom.Node n) {
      for (final c in n.nodes) {
        if (c is dom.Element) {
          if (skipTags.contains(c.localName)) continue;
          // Помеченное «не переводить» (translate="no", class="notranslate").
          if (c.attributes['translate']?.toLowerCase() == 'no' || c.classes.contains('notranslate')) continue;
          walk(c);
        } else if (c is dom.Text) {
          final s = c.data;
          final t = s.trim();
          if (!worthTranslating(t)) continue;
          final start = s.indexOf(t);
          nodes.add(c);
          lead.add(s.substring(0, start));
          trail.add(s.substring(start + t.length));
          texts.add(t);
        }
      }
    }

    walk(root);
    return HtmlTextSegments._(root, document, nodes, lead, trail, texts);
  }

  /// Документ с [translated] (по куску на каждый из [texts], в том же
  /// порядке) вместо исходного текста. Кусок, для которого перевода нет
  /// (список короче), остаётся исходным.
  String rebuild(List<String> translated) {
    for (var i = 0; i < _nodes.length && i < translated.length; i++) {
      final t = translated[i].trim();
      if (t.isEmpty) continue;
      _nodes[i].data = '${_lead[i]}$t${_trail[i]}';
    }
    return _document ? (_root as dom.Document).outerHtml : (_root as dom.DocumentFragment).outerHtml;
  }

  static final _fullDocument = RegExp(r'<!doctype|<html[\s>]|<body[\s>]', caseSensitive: false);
}

/// Куски простого текста — по строкам: знаки цитаты «>» и отступы в начале
/// строки остаются, переводится остальное.
class PlainTextSegments {
  final List<String> _lines;
  final List<int> _index;
  final List<String> _prefix;
  final List<String> _suffix;
  final List<String> texts;

  PlainTextSegments._(this._lines, this._index, this._prefix, this._suffix, this.texts);

  factory PlainTextSegments.parse(String text) {
    final lines = text.split('\n');
    final index = <int>[];
    final prefix = <String>[];
    final suffix = <String>[];
    final texts = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _line.firstMatch(lines[i])!;
      final body = m.group(2)!;
      if (!worthTranslating(body)) continue;
      index.add(i);
      prefix.add(m.group(1)!);
      suffix.add(m.group(3)!);
      texts.add(body);
    }
    return PlainTextSegments._(lines, index, prefix, suffix, texts);
  }

  String rebuild(List<String> translated) {
    final out = List<String>.of(_lines);
    for (var k = 0; k < _index.length && k < translated.length; k++) {
      final t = translated[k].trim();
      if (t.isEmpty) continue;
      out[_index[k]] = '${_prefix[k]}$t${_suffix[k]}';
    }
    return out.join('\n');
  }

  static final _line = RegExp(r'^([\s>]*)(.*?)(\s*)$', dotAll: true);
}

/// Есть ли что переводить: хотя бы одна буква, и это не адрес почты или
/// сайта (их перевод только испортил бы).
bool worthTranslating(String t) {
  if (t.isEmpty || !_letter.hasMatch(t)) return false;
  if (_urlOrEmail.hasMatch(t)) return false;
  return true;
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _urlOrEmail = RegExp(r'^(?:(?:https?://|www\.)\S+|[^\s@]+@[^\s@]+\.[^\s@]+)$', caseSensitive: false);

/// Видимый текст HTML для определения языка: без стилей, скриптов и
/// разметки, не длиннее [max] знаков.
String visibleTextSample(String html, {int max = 1500}) {
  final segs = HtmlTextSegments.parse(html);
  final b = StringBuffer();
  for (final t in segs.texts) {
    if (b.length >= max) break;
    b
      ..write(t)
      ..write(' ');
  }
  final s = b.toString().trim();
  return s.length > max ? s.substring(0, max) : s;
}

// ── Письмо, которое пишет пользователь ──────────────────────────────────

/// Как вставить перевод в письмо: заменить текст или оставить оба (сначала
/// исходный текст или сначала перевод).
enum ComposeTranslateMode { replace, originalFirst, translationFirst }

/// Текст редактора, разделённый на свой (приветствие и то, что написал
/// человек) и хвост: подпись и цитата исходного письма — их не переводим.
class ComposeOwnSplit {
  final String own;
  final String tail;
  const ComposeOwnSplit(this.own, this.tail);
}

class ComposeTranslation {
  ComposeTranslation._();

  /// Классы и id блоков цитаты (как в lib/core/utils/quote_splitter.dart):
  /// цитата ответа приложения — #divRplyFwdMsg, у других программ — свои.
  static const _quoteIds = {'divRplyFwdMsg', 'appendonsend', 'mail-editor-reference-message-container'};
  static const _quoteClasses = {'gmail_quote', 'moz-cite-prefix', 'yahoo_quoted', 'OutlookMessageHeader', 'protonmail_quote'};

  /// Разделить HTML редактора: всё до подписи (#ogn-signature) или до
  /// цитаты — своё, остальное — хвост.
  static ComposeOwnSplit splitOwn(String editorHtml) {
    final frag = html_parser.parseFragment(editorHtml);
    final nodes = frag.nodes.toList();
    var cut = nodes.length;
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n is dom.Element && _isTailStart(n)) {
        cut = i;
        break;
      }
    }
    String join(Iterable<dom.Node> ns) => ns.map(_outer).join();
    return ComposeOwnSplit(join(nodes.take(cut)), join(nodes.skip(cut)));
  }

  static bool _isTailStart(dom.Element e) {
    bool marks(dom.Element x) =>
        x.id == 'ogn-signature' ||
        x.localName == 'blockquote' ||
        _quoteIds.contains(x.id) ||
        x.classes.any(_quoteClasses.contains);
    if (marks(e)) return true;
    // Подпись или цитата внутри обёртки верхнего уровня.
    return e.querySelectorAll('*').any(marks);
  }

  static String _outer(dom.Node n) {
    if (n is dom.Element) return n.outerHtml;
    if (n is dom.Text) return _escape(n.data);
    if (n is dom.Comment) return '<!--${n.data}-->';
    return '';
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll(' ', '&nbsp;');

  /// Пустые строки в конце своего текста (три пустые строки перед подписью):
  /// при «оставить оба» они разрывали бы письмо пустотой.
  static String trimTrailingBlank(String html) {
    var s = html.trimRight();
    while (true) {
      final m = _trailingBlank.firstMatch(s);
      if (m == null) return s;
      s = s.substring(0, m.start).trimRight();
    }
  }

  static final _trailingBlank = RegExp(r'(?:<div>\s*(?:<br\s*/?>)?\s*</div>|<p>\s*(?:<br\s*/?>|&nbsp;)?\s*</p>|<br\s*/?>)$',
      caseSensitive: false);

  /// Служебная метка приветствия — только у одного блока: во второй копии
  /// текста (переводе) она дала бы два одинаковых id.
  static String _withoutGreetingId(String html) => html.replaceAll(RegExp(r'\s+id="ogn-greeting"'), '');

  /// Письмо после перевода. [label] — название языка второго блока («English»
  /// под переводом, «Русский» под исходным текстом, если перевод первым).
  static String assemble({
    required ComposeOwnSplit split,
    required String translated,
    required ComposeTranslateMode mode,
    required String label,
  }) {
    final tail = split.tail.trim().isEmpty ? '' : '<div><br></div>${split.tail}';
    if (mode == ComposeTranslateMode.replace) {
      return '${trimTrailingBlank(translated)}$tail';
    }
    final own = trimTrailingBlank(split.own);
    final tr = _withoutGreetingId(trimTrailingBlank(translated));
    final first = mode == ComposeTranslateMode.originalFirst ? own : tr;
    final second = mode == ComposeTranslateMode.originalFirst ? tr : _withoutGreetingId(own);
    // Тонкая линия и подпись языка мелким серым — как у двуязычных писем
    // в деловой переписке; стили — в самих тегах, классы почта не везде
    // сохраняет.
    final divider = '<div><br></div>'
        '<hr style="border:none;border-top:1px solid #d0d0d0;margin:8px 0;">'
        '<div style="font-size:11px;color:#888888;">${_escape(label)}</div>';
    return '$first$divider$second$tail';
  }

  /// Простое поле (без HTML-редактора): своё — всё до подписи [signature].
  static ComposeOwnSplit splitOwnPlain(String text, String? signature) {
    final sig = signature?.trim() ?? '';
    if (sig.isNotEmpty) {
      final i = text.lastIndexOf(sig);
      if (i >= 0) return ComposeOwnSplit(text.substring(0, i), text.substring(i));
    }
    return ComposeOwnSplit(text, '');
  }

  static String assemblePlain({
    required ComposeOwnSplit split,
    required String translated,
    required ComposeTranslateMode mode,
    required String label,
  }) {
    final tail = split.tail.trim().isEmpty ? '' : '\n\n${split.tail}';
    if (mode == ComposeTranslateMode.replace) return '${translated.trimRight()}$tail';
    final own = split.own.trimRight();
    final tr = translated.trimRight();
    final first = mode == ComposeTranslateMode.originalFirst ? own : tr;
    final second = mode == ComposeTranslateMode.originalFirst ? tr : own;
    return '$first\n\n——— $label ———\n\n${second.trimLeft()}$tail';
  }
}

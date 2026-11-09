// lib/features/mail/widgets/linkified_text.dart
// Текст письма без HTML (text/plain) с нажимаемыми ссылками и адресами
// почты (1.5.10). Раньше — SelectableText без ссылок. Даты в тексте —
// тоже нажимаемые (1.9.x, [dates], ссылки `ogdate:` — DateLinks).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/date_links.dart';
import 'mail_find.dart';

class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Адрес (https://…, mailto:…) и видимый текст ссылки.
  final void Function(String url, String text) onLink;

  /// Масштаб шрифта: null — системный (MediaQuery); задан — свой (текст
  /// письма, [MailHtmlView.textScaleOf]).
  final TextScaler? textScaler;

  /// Даты в тексте — нажимаемые, от даты письма; null — не искать.
  final DateContext? dates;

  /// Поиск в письме (2.2.0): совпадения — фоном, текущее — ярче.
  final MailFindController? find;

  const LinkifiedText(this.text,
      {super.key, this.style, required this.onLink, this.textScaler, this.dates, this.find});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _taps = [];
  List<_Run>? _spans;
  String? _for;
  Color? _link;
  String? _datesFor;

  void _dropTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  final _key = GlobalKey();
  String? _revealed;

  @override
  void initState() {
    super.initState();
    widget.find?.addListener(_onFind);
  }

  @override
  void didUpdateWidget(covariant LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.find != widget.find) {
      oldWidget.find?.removeListener(_onFind);
      widget.find?.addListener(_onFind);
    }
  }

  @override
  void dispose() {
    widget.find?.removeListener(_onFind);
    _dropTaps();
    super.dispose();
  }

  void _onFind() {
    if (mounted) setState(() {});
  }

  /// Даты ищутся на главном потоке — в очень длинном тексте без них
  /// (журналы, выгрузки), чтобы открытие не подтормаживало.
  static const _datesMaxChars = 30000;

  /// Куски текста: обычный текст, ссылки и даты (с нажатием и видом).
  List<_Run> _build(String text, Color link) {
    _dropTaps();
    final found = DateLinks.find(text, text.length <= _datesMaxChars ? widget.dates : null);
    if (found.isEmpty) return [(text: text, tap: null, style: null)];
    final out = <_Run>[];
    var at = 0;
    for (final m in found) {
      if (m.start > at) out.add((text: text.substring(at, m.start), tap: null, style: null));
      final shown = text.substring(m.start, m.end);
      final tap = TapGestureRecognizer()..onTap = () => widget.onLink(m.href, shown);
      _taps.add(tap);
      final date = DateLinks.isDateLink(m.href);
      out.add((
        text: shown,
        tap: tap,
        // Дата — цвета текста, пунктиром: нажимается, но не похожа на ссылку.
        style: TextStyle(
            color: date ? null : link,
            decoration: TextDecoration.underline,
            decorationStyle: date ? TextDecorationStyle.dotted : null),
      ));
      at = m.end;
    }
    if (at < text.length) out.add((text: text.substring(at), tap: null, style: null));
    return out;
  }

  static InlineSpan _span(_Run r, {String? text, Color? mark}) => TextSpan(
        text: text ?? r.text,
        recognizer: r.tap,
        mouseCursor: r.tap == null ? null : SystemMouseCursors.click,
        style: mark == null
            ? r.style
            : (r.style ?? const TextStyle()).copyWith(backgroundColor: mark, color: Colors.black),
      );

  /// Куски с подсветкой совпадений поиска; после кадра — сколько нашлось и
  /// прокрутка к текущему.
  List<InlineSpan> _spansWithFind(List<_Run> runs) {
    final f = widget.find;
    if (f == null || !f.active) {
      _revealed = null;
      return [for (final r in runs) _span(r)];
    }
    final texts = [for (final r in runs) r.text];
    final ranges = findRanges(texts.join(), f.query);
    final cur = f.current;
    final sig = '${f.query}|$cur';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.find != f) return;
      f.report(ranges.length);
      if (cur < ranges.length && _revealed != sig) {
        _revealed = sig;
        revealMatch(_key, ranges[cur].$1, ranges[cur].$2);
      }
    });
    if (ranges.isEmpty) return [for (final r in runs) _span(r)];
    return [
      for (final p in splitByMatches(texts, ranges))
        _span(runs[p.run], text: p.text, mark: p.match == null ? null : findMarkColor(current: p.match == cur)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final link = Theme.of(context).colorScheme.primary;
    final datesKey = widget.dates?.key;
    if (_spans == null || _for != widget.text || _link != link || _datesFor != datesKey) {
      _spans = _build(widget.text, link);
      _for = widget.text;
      _link = link;
      _datesFor = datesKey;
    }
    return SelectableText.rich(TextSpan(style: widget.style, children: _spansWithFind(_spans!)),
        key: _key, textScaler: widget.textScaler);
  }
}

/// Кусок текста письма: текст, нажатие (ссылка, дата) и вид.
typedef _Run = ({String text, TapGestureRecognizer? tap, TextStyle? style});

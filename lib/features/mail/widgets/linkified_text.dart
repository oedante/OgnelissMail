// lib/features/mail/widgets/linkified_text.dart
// Текст письма без HTML (text/plain) с нажимаемыми ссылками и адресами
// почты (1.5.10). Раньше — SelectableText без ссылок. Даты в тексте —
// тоже нажимаемые (1.9.x, [dates], ссылки `ogdate:` — DateLinks).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/date_links.dart';

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

  const LinkifiedText(this.text, {super.key, this.style, required this.onLink, this.textScaler, this.dates});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _taps = [];
  List<InlineSpan>? _spans;
  String? _for;
  Color? _link;
  String? _datesFor;

  void _dropTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _dropTaps();
    super.dispose();
  }

  /// Даты ищутся на главном потоке — в очень длинном тексте без них
  /// (журналы, выгрузки), чтобы открытие не подтормаживало.
  static const _datesMaxChars = 30000;

  List<InlineSpan> _build(String text, Color link) {
    _dropTaps();
    final found = DateLinks.find(text, text.length <= _datesMaxChars ? widget.dates : null);
    if (found.isEmpty) return [TextSpan(text: text)];
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in found) {
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      final shown = text.substring(m.start, m.end);
      final tap = TapGestureRecognizer()..onTap = () => widget.onLink(m.href, shown);
      _taps.add(tap);
      final date = DateLinks.isDateLink(m.href);
      out.add(TextSpan(
        text: shown,
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
        // Дата — цвета текста, пунктиром: нажимается, но не похожа на ссылку.
        style: TextStyle(
            color: date ? null : link,
            decoration: TextDecoration.underline,
            decorationStyle: date ? TextDecorationStyle.dotted : null),
      ));
      at = m.end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
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
    return SelectableText.rich(TextSpan(style: widget.style, children: _spans), textScaler: widget.textScaler);
  }
}

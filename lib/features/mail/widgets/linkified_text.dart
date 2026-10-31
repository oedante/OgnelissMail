// lib/features/mail/widgets/linkified_text.dart
// Текст письма без HTML (text/plain) с нажимаемыми ссылками и адресами
// почты (1.5.10). Раньше — SelectableText без ссылок.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/linkify.dart';

class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Адрес (https://…, mailto:…) и видимый текст ссылки.
  final void Function(String url, String text) onLink;

  /// Масштаб шрифта: null — системный (MediaQuery); задан — свой (текст
  /// письма, [MailHtmlView.textScaleOf]).
  final TextScaler? textScaler;

  const LinkifiedText(this.text, {super.key, this.style, required this.onLink, this.textScaler});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _taps = [];
  List<InlineSpan>? _spans;
  String? _for;
  Color? _link;

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

  List<InlineSpan> _build(String text, Color link) {
    _dropTaps();
    final found = Linkify.find(text);
    if (found.isEmpty) return [TextSpan(text: text)];
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in found) {
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      final shown = text.substring(m.start, m.end);
      final tap = TapGestureRecognizer()..onTap = () => widget.onLink(m.href, shown);
      _taps.add(tap);
      out.add(TextSpan(
        text: shown,
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
        style: TextStyle(color: link, decoration: TextDecoration.underline),
      ));
      at = m.end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final link = Theme.of(context).colorScheme.primary;
    if (_spans == null || _for != widget.text || _link != link) {
      _spans = _build(widget.text, link);
      _for = widget.text;
      _link = link;
    }
    return SelectableText.rich(TextSpan(style: widget.style, children: _spans), textScaler: widget.textScaler);
  }
}

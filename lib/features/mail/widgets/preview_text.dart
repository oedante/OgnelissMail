// lib/features/mail/widgets/preview_text.dart
// Начало текста письма в ленте и в карточке по удержанию — 1–4 строки
// (настройка, 1.6.31). Переносы письма сохраняются, пустые строки
// пропускаются:
//   «Добрый день, Олег Андреевич,\n\nХочу Вас уведомить…\n\nПрилагаю…»
//   две строки → «Добрый день, Олег Андреевич,» / «Хочу Вас уведомить…».
// Одна строка — как раньше: весь текст подряд, одной строкой.

import 'package:flutter/material.dart';

/// Строки превью без пустых, не больше [max].
List<String> previewLinesOf(String text, int max) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'\r\n|\r|\n| | '))) {
    final line = raw.replaceAll(RegExp(r'[ \t ​]+'), ' ').trim();
    if (line.isEmpty) continue;
    out.add(line);
    if (out.length >= max) break;
  }
  return out;
}

class PreviewText extends StatelessWidget {
  final String text;
  final int lines;
  final TextStyle? style;

  const PreviewText(this.text, {super.key, required this.lines, this.style});

  @override
  Widget build(BuildContext context) {
    if (lines <= 1) {
      return Text(
        text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final parts = previewLinesOf(text, lines);
    // Перенос в письме один (или превью с сервера одной строкой) — текст
    // занимает до [lines] строк экрана, как абзац.
    if (parts.length <= 1) {
      return Text(parts.isEmpty ? '' : parts.first, style: style, maxLines: lines, overflow: TextOverflow.ellipsis);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in parts) Text(p, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

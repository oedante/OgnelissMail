// lib/core/utils/encoded_words.dart
// Имена и темы из заголовков, в которых почтовый шлюз разрезал
// закодированное слово RFC 2047 переносом строки (замечание владельца
// 12.11.2026: получатель «Олег Ермиши? ?utf8?QD0=BD?=» вместо «Олег
// Ермишин»).
//
// Шлюз переносит длинный заголовок по ширине, не глядя на слова:
//   To: "=?utf8?Q?=D0=9E=D0=BB…=D0=B8?
//   \t= =?utf8?Q?=D0=BD?=" <o@example.ru>
// Конец слова «?=» оказался на двух строках. Сервер IMAP отдаёт имя одной
// строкой («…=D0=B8? = =?utf8?Q?=D0=BD?=»), а разбор почты принимает за конец
// первого слова «?=» внутри начала второго («Q?=D0») — выходит «Олег
// Ермиши?  =?utf8?QD0=BD?=». Для файлов .eml то же чинит
// EmlReader.repairEncodedWords по сырым заголовкам; здесь — по уже
// разобранной строке: из конверта IMAP сырого заголовка нет, и такие имена
// уже лежат в базе.

import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' show MailCodec;

import 'charset_handler.dart';

/// След разрезанного слова в кодировке Q: «?», пробелы и остаток второго
/// слова без «?=» после «Q» («=?utf8?QD0=BD?=»; знак «=» в начале мог
/// потеряться при чистке имени).
final _brokenQ = RegExp(r'\?\s+=?\?([A-Za-z0-9_\-]+)\?[Qq]([0-9A-Fa-f]{2}[^?\s]*)\?=');

/// Конец слова, разорванный пробелами: «…? =» перед следующим словом или
/// концом строки.
final _splitEnd = RegExp(r'\?\s+=(?=\s*(?:=\?|$))');

Uint8List _qBytes(String text) {
  final out = BytesBuilder();
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '=' && i + 2 < text.length) {
      final v = int.tryParse(text.substring(i + 1, i + 3), radix: 16);
      if (v != null) {
        out.addByte(v);
        i += 3;
        continue;
      }
    }
    out.addByte(c == '_' ? 0x20 : (c.codeUnitAt(0) & 0xFF));
    i++;
  }
  return out.takeBytes();
}

/// Текст заголовка (имя, тема) с восстановленными разрезанными словами.
/// Строка без их следов возвращается как есть.
String repairEncodedWordText(String s) {
  if (!s.contains('?=')) return s;
  var out = s;
  for (var n = 0; n < 8; n++) {
    final m = _brokenQ.firstMatch(out);
    if (m == null) break;
    String tail;
    try {
      tail = CharsetHandler.decode(_qBytes('=${m.group(2)}'), m.group(1)!.toLowerCase());
    } catch (_) {
      break;
    }
    if (tail.contains('�')) break;
    out = out.replaceRange(m.start, m.end, tail);
  }
  // Слово осталось нераскодированным (кодировка B: конец слова разорван, а
  // второго «?=» внутри нет) — собрать конец и раскодировать заново.
  if (out.contains('=?') && out.contains('?=')) {
    final joined = out.replaceAll(_splitEnd, '?=');
    try {
      final d = MailCodec.decodeHeader(joined);
      if (d != null && d.isNotEmpty && !d.contains('�') && !d.contains('=?')) out = d;
    } catch (_) {}
  }
  return out;
}

/// Имя из заголовка для показа и хранения: восстановленное; с остатками
/// закодированных слов или битыми буквами — null (подставится имя из
/// контактов или адрес).
String? repairedDisplayName(String? name) {
  if (name == null) return null;
  final r = repairEncodedWordText(name);
  if (r.contains('�') || hasEncodedWordLeftovers(r)) return null;
  return r;
}

/// В тексте остались куски закодированных слов («=?utf8?Q», «?utf8?QD0=BD?=»).
bool hasEncodedWordLeftovers(String s) =>
    s.contains('?=') && RegExp(r'\?[A-Za-z0-9_\-]+\?[QqBb]').hasMatch(s);

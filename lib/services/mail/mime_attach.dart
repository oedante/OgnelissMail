// lib/services/mail/mime_attach.dart
//
// Файл — вложением письма. Вложенное письмо (message/rfc822, .eml) — как
// есть, а не base64: enough_mail в addBinary кодирует любой файл в base64,
// но для message/* заголовок Content-Transfer-Encoding не пишет (RFC 2046
// разрешает там только 7bit, 8bit и binary). Получатель видел вместо
// письма строки base64 — так дошли пересланные группы контактов Outlook
// (письмо владельца 21.11.2026).

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

void addFileAttachment(PartBuilder builder, Uint8List bytes, MediaType type, String name) {
  if (type.top == MediaToptype.message) {
    final text = sevenBitMessage(bytes);
    if (text != null) {
      builder.addPart(
        mimePart: MimePart()..mimeData = TextMimeData(text, containsHeader: false),
        disposition: ContentDispositionHeader.from(ContentDisposition.attachment,
            filename: name, size: bytes.length),
      ).setContentType(type, name: name);
      return;
    }
    // 8-битное письмо как есть в 7-битной части не передать — файлом .eml
    // (почтовые программы открывают его по имени, Ogneliss — тоже).
    type = MediaType.fromText('application/octet-stream');
  }
  builder.addBinary(bytes, type, filename: name);
}

/// Письмо [bytes] как текст 7bit с переводами строк CRLF; не 7-битное или
/// со строкой длиннее 998 знаков — null.
String? sevenBitMessage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.any((b) => b >= 0x80 || b == 0)) return null;
  final text = ascii.decode(bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = text.split('\n');
  if (lines.any((l) => l.length > 998)) return null;
  var out = lines.join('\r\n');
  if (!out.endsWith('\r\n')) out = '$out\r\n';
  return out;
}

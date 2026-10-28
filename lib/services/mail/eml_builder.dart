// lib/services/mail/eml_builder.dart
// Сборка .eml (RFC822/MIME) из сохранённого письма — для «Переслать как
// вложение» и «Поделиться как .eml».
//
// Используем enough_mail MessageBuilder: корректные MIME-заголовки, кодировки,
// base64 для двоичных частей.

import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

import '../../data/models/email_model.dart';

/// Вложение для .eml: имя, тип и УЖЕ загруженный файл на диске.
typedef EmlAttachment = ({String name, String mimeType, String path});

/// Собрать .eml из письма.
///
/// Структура зависит от наличия вложений — это не косметика, а требование MIME:
///   без вложений: multipart/alternative (text/plain + text/html)
///   с вложениями: multipart/mixed
///                 ├── multipart/alternative (text/plain + text/html)
///                 └── файлы
/// Если добавить файлы прямо в multipart/alternative, почтовые клиенты сочтут
/// их АЛЬТЕРНАТИВНЫМ представлением текста и покажут вместо письма.
Future<String> buildEmlFromEmail(
  EmailModel email, {
  List<EmlAttachment> attachments = const [],
}) async {
  final html = email.bodyHtml;
  final plain = email.bodyPlain;
  final plainText = (plain != null && plain.trim().isNotEmpty)
      ? plain
      : (html ?? '')
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
  final htmlText =
      (html != null && html.trim().isNotEmpty) ? html : '<pre>$plainText</pre>';

  final MessageBuilder builder;
  if (attachments.isEmpty) {
    builder = MessageBuilder.prepareMultipartAlternativeMessage();
    builder.addTextHtml(htmlText);
    builder.addTextPlain(plainText);
  } else {
    builder = MessageBuilder.prepareMultipartMixedMessage();
    // Текст — отдельной alternative-частью внутри mixed.
    final textPart = builder.addPart(mediaSubtype: MediaSubtype.multipartAlternative);
    textPart.addTextPlain(plainText);
    textPart.addTextHtml(htmlText);

    for (final att in attachments) {
      try {
        final file = File(att.path);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        builder.addBinary(
          Uint8List.fromList(bytes),
          MediaType.fromText(att.mimeType),
          filename: att.name,
        );
      } catch (_) {
        // Один нечитаемый файл не должен рушить весь .eml.
      }
    }
  }

  _fillHeaders(builder, email);
  return builder.buildMimeMessage().renderMessage();
}

void _fillHeaders(MessageBuilder builder, EmailModel email) {
  builder.from = [MailAddress(email.from.displayName, email.from.email)];
  builder.to = email.to.map((a) => MailAddress(a.displayName, a.email)).toList();
  if (email.cc.isNotEmpty) {
    builder.cc = email.cc.map((a) => MailAddress(a.displayName, a.email)).toList();
  }
  builder.subject = email.subject;
  builder.date = email.receivedAt;
}

/// Безопасное имя файла .eml из темы письма.
String emlFileName(EmailModel email) {
  final base = email.subject.trim().isEmpty ? 'message' : email.subject.trim();
  final safe = base.replaceAll(RegExp(r'[^\w\-. а-яА-ЯёЁ]'), '_');
  final short = safe.length > 60 ? safe.substring(0, 60) : safe;
  return '$short.eml';
}

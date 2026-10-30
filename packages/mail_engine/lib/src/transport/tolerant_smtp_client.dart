// packages/mail_engine/lib/src/transport/tolerant_smtp_client.dart
// SMTP-клиент enough_mail, терпимый к коротким ответам сервера (1.8.12).
//
// Яндекс на «AUTH XOAUTH2» отвечает голым «334» — без пробела и пустого
// вызова (RFC 4954 требует «334 »). Разбор строки в enough_mail 2.1.x берёт
// text.substring(4) и падает с RangeError внутри обработчика сокета: команда
// входа не завершается, отправка ждёт тайм-аут и сдаётся. Письма с ящиков
// Яндекса через OAuth не уходили (журнал владельца 30.10.2026 13:29).
//
// Строка из одного кода дополняется пробелом до разбора; остальное — как в
// enough_mail.

import 'package:enough_mail/enough_mail.dart' as em;

class TolerantSmtpClient extends em.SmtpClient {
  TolerantSmtpClient(
    super.clientDomain, {
    super.isLogEnabled,
    super.logName,
    super.onBadCertificate,
  });

  /// Строки ответа в виде, который понимает enough_mail: «334» → «334 ».
  static List<String> normalize(List<String> lines) => [
        for (final l in lines) RegExp(r'^\d{3}$').hasMatch(l) ? '$l ' : l,
      ];

  @override
  void onServerResponse(List<String> responseTexts) => super.onServerResponse(normalize(responseTexts));
}

/// SMTP: письмо не отправлено — сбой до передачи письма (подключение или
/// вход). Повтор безопасен: сервер письма не получал. Тайм-аут здесь — не
/// «сервер мог принять письмо» (1.8.12: такое письмо сразу падало в «не
/// отправлено» без повтора).
class SmtpNotSentException implements Exception {
  final Object cause;
  const SmtpNotSentException(this.cause);

  @override
  String toString() => 'SMTP: вход не выполнен, письмо не отправлено ($cause)';
}

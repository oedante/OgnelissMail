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
//
// DSN (RFC 3461, 1.9.x, просьба владельца 31.10.2026): если сервер объявил
// DSN в EHLO, к MAIL FROM добавляются RET=HDRS ENVID=<Message-ID>, к
// RCPT TO — NOTIFY=FAILURE,DELAY (или SUCCESS,FAILURE,DELAY по просьбе
// «Запросить подтверждение доставки»). enough_mail параметров конверта не
// принимает, а файлы его не меняем (MPL-2.0): строки команд дополняются в
// writeText — через неё уходят все команды клиента.

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

  /// Запрос DSN для следующей отправки; null — без DSN.
  DsnRequest? dsn;

  bool _dsnUsed = false;
  bool _dataStarted = false;

  /// В последней отправке параметры DSN ушли серверу.
  bool get dsnUsed => _dsnUsed;

  /// Сервер уже получил DATA: сбой после этого — не из-за параметров DSN.
  bool get dataStarted => _dataStarted;

  /// Сервер объявил DSN (RFC 3461) в ответе на EHLO.
  bool get supportsDsn => serverInfo.capabilities.any((c) => c.trim().toUpperCase() == 'DSN');

  @override
  Future writeText(String text, [dynamic logObject, Duration? timeout]) {
    if (text == 'DATA') _dataStarted = true;
    final req = dsn;
    if (req != null && supportsDsn) {
      final line = applyDsn(text, req);
      if (!identical(line, text)) {
        if (text.startsWith('MAIL FROM:')) {
          _dsnUsed = true;
          _dataStarted = false;
        }
        return super.writeText(line, logObject, timeout);
      }
    }
    if (text.startsWith('MAIL FROM:')) {
      _dsnUsed = false;
      _dataStarted = false;
    }
    return super.writeText(text, logObject, timeout);
  }

  static final _mailFrom = RegExp(r'^MAIL FROM:<[^<>\r\n]*>( BODY=8BITMIME)?$');
  static final _rcptTo = RegExp(r'^RCPT TO:<[^<>\r\n]*>$');

  /// Строка команды с параметрами DSN; другая строка (текст письма, прочие
  /// команды) — без изменений, тем же объектом.
  static String applyDsn(String line, DsnRequest req) {
    if (_mailFrom.hasMatch(line)) {
      final env = req.envelopeId;
      return '$line RET=HDRS${env == null || env.isEmpty ? '' : ' ENVID=${xtext(env)}'}';
    }
    if (_rcptTo.hasMatch(line)) return '$line NOTIFY=${req.notify}';
    return line;
  }

  /// xtext (RFC 3461, 4): «+», «=», управляющие и не-ASCII символы — «+XX»;
  /// не длиннее 100 знаков, как требует ENVID.
  static String xtext(String v) {
    final b = StringBuffer();
    for (final c in v.codeUnits) {
      if (c < 33 || c > 126 || c == 0x2B || c == 0x3D) {
        b.write('+${(c & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        b.writeCharCode(c);
      }
    }
    final s = b.toString();
    return s.length > 100 ? s.substring(0, 100) : s;
  }
}

/// Что просить у сервера об отчётах о доставке (RFC 3461).
class DsnRequest {
  /// ENVID: Message-ID письма без <> — по нему отчёт находит своё письмо.
  final String? envelopeId;

  /// Сообщать и об успешной доставке («Запросить подтверждение доставки»).
  final bool notifySuccess;

  const DsnRequest({this.envelopeId, this.notifySuccess = false});

  String get notify => notifySuccess ? 'SUCCESS,FAILURE,DELAY' : 'FAILURE,DELAY';
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

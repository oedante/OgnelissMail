// packages/mail_engine/lib/src/transport/tolerant_imap_client.dart
// IMAP-клиент enough_mail, который не зависает на ответе, который не смог
// разобрать (2.6.0; журнал Samsung S24 16.11.2026: «перестаёт
// синхронизировать почту»).
//
// В enough_mail 2.1.7 строка ответа сервера разбирается прямо в обработчике
// данных сокета. Исключение при разборе (там — RangeError «0..10: 11» на
// списке параметров BODYSTRUCTURE нечётной длины у одного письма Mail.ru и
// Яндекса) вылетало из обработчика необработанной ошибкой, а остаток уже
// полученных данных — вместе с ответом «OK» на саму команду — оставался в
// буфере до следующей порции данных. Сервер больше ничего не присылал, и
// команда ждала до тайм-аута (5 мин), на каждой проверке заново: папка с
// таким письмом не синхронизировалась, а очередь операций ящика стояла.
//
// Здесь — переопределение открытого onServerResponse, как в
// NotifyImapClient и TolerantSmtpClient: ошибка разбора одной строки
// ловится, строка запоминается (номер письма и UID), остальные строки
// разбираются как обычно, и команда завершается в срок. Какие письма не
// разобрались — [takeParseFailures]; ImapService загружает их заново без
// BODYSTRUCTURE. Сам пакет enough_mail не изменён.

import 'package:enough_mail/enough_mail.dart' as em;

/// Строка ответа сервера, которую enough_mail не смог разобрать.
class ImapParseFailure {
  const ImapParseFailure({this.sequenceId, this.uid, required this.error});

  /// Порядковый номер письма («* N FETCH …»); null — не ответ FETCH.
  final int? sequenceId;

  /// UID письма, если он есть в строке.
  final int? uid;

  /// Что случилось (тип и текст исключения, без данных письма).
  final String error;

  @override
  String toString() => 'ImapParseFailure(seq: $sequenceId, uid: $uid, $error)';
}

class TolerantImapClient extends em.ImapClient {
  TolerantImapClient({
    super.isLogEnabled,
    super.logName,
    super.defaultWriteTimeout,
    super.defaultResponseTimeout,
    super.onBadCertificate,
    this.onParseFailure,
  });

  /// Сообщение о строке, которая не разобралась, — в журнал приложения.
  final void Function(String message)? onParseFailure;

  /// Не больше стольких сбоев хранится до [takeParseFailures].
  static const maxKept = 200;

  final _failures = <ImapParseFailure>[];

  /// Сбои разбора с прошлого вызова (и очистить список).
  List<ImapParseFailure> takeParseFailures() {
    final r = List<ImapParseFailure>.of(_failures);
    _failures.clear();
    return r;
  }

  static final _fetchLine = RegExp(r'^\*\s+(\d+)\s+FETCH\b', caseSensitive: false);
  static final _uid = RegExp(r'\bUID\s+(\d+)', caseSensitive: false);

  // Тип параметра выводится из ImapClient (внутренний класс enough_mail, его
  // не подключаем): нужен только текст ответа parseText.
  @override
  void onServerResponse(imapResponse) {
    final text = imapResponse.parseText;
    try {
      super.onServerResponse(imapResponse);
    } catch (e) {
      final seq = int.tryParse(_fetchLine.firstMatch(text)?.group(1) ?? '');
      final uid = seq == null ? null : int.tryParse(_uid.firstMatch(text)?.group(1) ?? '');
      final error = '${e.runtimeType}: ${_short('$e')}';
      if (_failures.length < maxKept) {
        _failures.add(ImapParseFailure(sequenceId: seq, uid: uid, error: error));
      }
      try {
        onParseFailure?.call(seq == null
            ? 'IMAP: ответ сервера не разобран — $error'
            : 'IMAP: письмо №$seq${uid == null ? '' : ' (UID $uid)'} не разобрано — $error');
      } catch (_) {}
    }
  }

  static String _short(String s) => s.length <= 160 ? s : '${s.substring(0, 160)}…';
}

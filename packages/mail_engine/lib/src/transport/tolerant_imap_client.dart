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

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;
// ConnectionInfo не вынесен в открытый API enough_mail (как в
// TolerantSmtpClient).
// ignore: implementation_imports
import 'package:enough_mail/src/private/util/client_base.dart' show ConnectionInfo;

import 'net_proxy.dart';

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

  // ── Прокси и сертификат клиента (2.6.5) ──

  /// Туннель CONNECT и/или свой контекст TLS; STARTTLS — на том же соединении.
  final _transport = MailTransport();

  /// Через прокси, если он нужен узлу ([NetProxy.lookup]); иначе — как в
  /// enough_mail, напрямую.
  @override
  Future<ConnectionInfo> connectToServer(String host, int port,
      {bool isSecure = true, Duration timeout = const Duration(seconds: 20)}) async {
    final socket = await _transport.open(host, port,
        isSecure: isSecure, timeout: timeout, onBadCertificate: onBadCertificate);
    if (socket == null) return super.connectToServer(host, port, isSecure: isSecure, timeout: timeout);
    // Свой сокет — через обычный путь enough_mail (приветствие, тайм-аут);
    // TLS, если нужен, уже на сокете.
    return NetProxy.viaSocket(
      socket,
      () => super.connectToServer(host, port, isSecure: false, timeout: timeout),
      onUse: () => connectionInfo = ConnectionInfo(host, port, isSecure: isSecure),
    );
  }

  /// STARTTLS через прокси: у enough_mail сокет — обёртка туннеля, TLS
  /// ставится на настоящее соединение с проверкой сертификата узла
  /// почтового сервера.
  @override
  Future<void> upgradeToSslSocket() async {
    final up = _transport.upgrade(onBadCertificate: onBadCertificate);
    if (up == null) return super.upgradeToSslSocket();
    connect(await up);
  }

  // ── Ход приёма и обрыв (2.7.2) ──
  //
  // Журнал владельца 23.11.2026: при плохой связи вложение качалось без
  // конца, а после смены сети не начиналось снова. enough_mail при закрытом
  // сокете (disconnect, обрыв) не завершает команды, ждущие ответа, — они
  // висели до тайм-аута операции (у вложения — 20 мин), и очередь ящика
  // стояла. [lost] завершается ошибкой при обрыве и при [abort]; ImapService
  // ждёт команду наперегонки с ним. [lastDataAt] — когда пришли данные:
  // по нему видно, что приём встал.

  int _received = 0;
  DateTime _lastData = DateTime.now();

  /// Сколько байт пришло от сервера за всё время соединения.
  int get bytesReceived => _received;

  /// Когда от сервера пришли последние данные.
  DateTime get lastDataAt => _lastData;

  /// Отметить начало операции: ожидание приёма считается с этой минуты.
  void touch() => _lastData = DateTime.now();

  @override
  void onDataReceived(Uint8List data) {
    _received += data.length;
    _lastData = DateTime.now();
    super.onDataReceived(data);
  }

  Completer<void>? _lostCompleter;

  Completer<void> get _lostC {
    final c = _lostCompleter;
    if (c != null) return c;
    final n = Completer<void>();
    // Никто может и не ждать — ошибка не должна считаться необработанной.
    n.future.ignore();
    return _lostCompleter = n;
  }

  /// Завершается ошибкой [SocketException], когда соединение оборвано
  /// (сеть, сервер) или закрыто через [abort]; пока соединение живо — ждёт.
  Future<void> get lost => _lostC.future;

  /// Оборвано ли соединение.
  bool get isLost => _lostCompleter?.isCompleted ?? false;

  void _markLost(Object reason) {
    final c = _lostC;
    if (!c.isCompleted) c.completeError(SocketException('IMAP: соединение потеряно — $reason'));
  }

  @override
  void onConnectionError(dynamic error) {
    super.onConnectionError(error);
    _markLost(error ?? 'закрыто');
  }

  /// Закрыть соединение так, чтобы команды, ждущие ответа, сразу получили
  /// ошибку (а не ждали тайм-аута).
  Future<void> abort(String reason) async {
    _markLost(reason);
    try {
      await disconnect();
    } catch (_) {}
  }

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

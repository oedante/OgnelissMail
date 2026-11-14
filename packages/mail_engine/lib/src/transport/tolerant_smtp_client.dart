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
//
// Ответы по правилам SMTP (жалоба пользователя 14.11.2026, Mercury из
// XAMPP). enough_mail считал ответом всё, что пришло одним пакетом TCP, а
// EHLO — завершённым, как только в пакете больше одной строки. Сервер,
// который шлёт строки ответа отдельными пакетами, сбивал клиента: хвост
// ответа на EHLO засчитывался как ответ на AUTH, дальше всё сдвигалось на
// один ответ, и «354 OK, send data» принимался за ответ на конец письма —
// письмо доходило, а в очереди висело с этой ошибкой. Сервер, ответивший
// на EHLO одной строкой, не дожидался продолжения совсем. Теперь ответ
// собирается целиком (SmtpReplyFramer: «250-…» — продолжение, «250 …» —
// последняя строка), приветствие из нескольких пакетов дочитывается, EHLO —
// своя команда, завершённая по целому ответу.
//
// Имя в EHLO (там же): «EHLO 192.168.1.67» неверно (RFC 5321, 4.1.3) —
// Mercury отвечал «554 Invalid HELO format». Адрес IP — в квадратных
// скобках: «EHLO [192.168.1.67]» (heloName).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;
// SmtpCommand и ConnectionInfo не вынесены в открытый API enough_mail;
// файлы пакета не меняем — своя команда EHLO наследует его класс.
// ignore: implementation_imports
import 'package:enough_mail/src/private/smtp/smtp_command.dart' show SmtpCommand;
// ignore: implementation_imports
import 'package:enough_mail/src/private/util/client_base.dart' show ConnectionInfo;

class TolerantSmtpClient extends em.SmtpClient {
  TolerantSmtpClient(
    String clientDomain, {
    super.isLogEnabled,
    super.logName,
    super.onBadCertificate,
  })  : heloDomain = heloName(clientDomain),
        super(heloName(clientDomain));

  /// Имя клиента в EHLO (см. [heloName]).
  final String heloDomain;

  /// Имя для EHLO из домена [domain]: адрес IP — в квадратных скобках
  /// («[192.168.1.67]», «[IPv6:::1]»), имя узла — как есть; пустое или
  /// неверное — «localhost».
  static String heloName(String domain) {
    var d = domain.trim();
    if (d.startsWith('[') && d.endsWith(']')) d = d.substring(1, d.length - 1);
    if (d.toUpperCase().startsWith('IPV6:')) d = d.substring(5);
    final ip = InternetAddress.tryParse(d);
    if (ip != null) return ip.type == InternetAddressType.IPv6 ? '[IPv6:${ip.address}]' : '[${ip.address}]';
    return _host.hasMatch(d) ? d : 'localhost';
  }

  static final _host = RegExp(r'^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');

  final _bytes = BytesBuilder(copy: false);
  final _framer = SmtpReplyFramer();

  /// Приветствие пришло не целиком — его остаток не ответ на команду.
  bool _greetingRest = false;

  @override
  Future<ConnectionInfo> connectToServer(String host, int port, {bool isSecure = true, Duration timeout = const Duration(seconds: 20)}) {
    _bytes.clear();
    _framer.reset();
    _greetingRest = false;
    return super.connectToServer(host, port, isSecure: isSecure, timeout: timeout);
  }

  @override
  void onConnectionEstablished(ConnectionInfo connectionInfo, String serverGreeting) {
    super.onConnectionEstablished(connectionInfo, serverGreeting);
    final lines = serverGreeting.split('\r\n');
    _greetingRest = !serverGreeting.endsWith('\r\n') || (lines.length > 1 && SmtpReplyFramer.isContinuation(lines[lines.length - 2]));
  }

  @override
  void onDataReceived(Uint8List data) {
    _bytes.add(data);
    final all = _bytes.takeBytes();
    final end = _lastLineEnd(all);
    if (end < 0) {
      _bytes.add(all);
      return;
    }
    if (end + 1 < all.length) _bytes.add(Uint8List.sublistView(all, end + 1));
    final text = utf8.decode(Uint8List.sublistView(all, 0, end + 1), allowMalformed: true);
    final lines = text.split('\r\n')..removeLast();
    for (final reply in _framer.add(lines)) {
      if (_greetingRest) {
        _greetingRest = false;
        continue;
      }
      onServerResponse(reply);
    }
  }

  static int _lastLineEnd(Uint8List b) {
    for (var i = b.length - 1; i > 0; i--) {
      if (b[i] == 10 && b[i - 1] == 13) return i;
    }
    return -1;
  }

  /// EHLO своей командой: ответ уже собран целиком, команда завершена им
  /// (у enough_mail ответ из одной строки «250 имя» не завершал EHLO).
  @override
  Future<em.SmtpResponse> ehlo() async {
    final r = await sendCommand(_EhloCommand(heloDomain));
    final info = serverInfo
      ..capabilities = <String>[]
      ..authMechanisms = <em.AuthMechanism>[];
    for (final line in r.responseLines.skip(1)) {
      if (line.code != 250) continue;
      final ext = line.message.trim();
      info.capabilities.add(ext);
      final up = ext.toUpperCase();
      if (up.startsWith('AUTH ') || up.startsWith('AUTH=')) {
        final names = up.substring(5).split(RegExp(r'\s+'));
        for (final (name, m) in [
          ('PLAIN', em.AuthMechanism.plain),
          ('LOGIN', em.AuthMechanism.login),
          ('CRAM-MD5', em.AuthMechanism.cramMd5),
          ('XOAUTH2', em.AuthMechanism.xoauth2),
        ]) {
          if (names.contains(name) && !info.authMechanisms.contains(m)) info.authMechanisms.add(m);
        }
      } else if (up.startsWith('SIZE ')) {
        info.maxMessageSize = int.tryParse(ext.substring(5).trim());
      }
    }
    return r;
  }

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

/// EHLO с именем клиента; завершается ответом сервера (собранным целиком).
class _EhloCommand extends SmtpCommand {
  _EhloCommand(this.name) : super('EHLO');

  final String name;

  @override
  String get command => 'EHLO $name';

  @override
  bool isCommandDone(em.SmtpResponse response) => true;
}

/// Сборка ответов SMTP из строк (RFC 5321, 4.2.1): «250-…» — продолжение,
/// строка без «-» после кода («250 …», «334») — последняя. Строки приходят
/// пакетами как угодно: ответ может быть разрезан на несколько пакетов,
/// а в одном пакете — быть несколько ответов.
class SmtpReplyFramer {
  final _pending = <String>[];

  static final _cont = RegExp(r'^\d{3}-');

  static bool isContinuation(String line) => _cont.hasMatch(line);

  /// Строки [lines] очередного пакета → готовые ответы.
  List<List<String>> add(Iterable<String> lines) {
    final out = <List<String>>[];
    for (final l in lines) {
      if (l.isEmpty && _pending.isEmpty) continue;
      _pending.add(l);
      if (!isContinuation(l)) {
        out.add(List.of(_pending));
        _pending.clear();
      }
    }
    return out;
  }

  void reset() => _pending.clear();
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

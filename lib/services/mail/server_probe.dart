// lib/services/mail/server_probe.dart
// Подбор портов и шифрования IMAP и SMTP рабочей почты (2.6.0).
//
// Серверы организации часто отвечают не на стандартных для приложения
// портах: только STARTTLS на 143, отправка на 587 или 25. Раньше вход
// падал с «сервер недоступен», и человек сам перебирал порты в
// «Расширенных настройках».
//
// Проверяется только доступность сервера — без логина и пароля: TCP,
// TLS (сразу или после STARTTLS) и приветствие сервера («* OK», «220»).
// Лишних попыток входа нет: в Active Directory каждая неудачная попытка
// пароля приближает блокировку учётной записи. Пароль в проверке не
// участвует, поэтому сертификат здесь не проверяется — это делает
// настоящее подключение (с проверкой сертификата и закреплением).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart' show EncryptionType;

/// Порт и шифрование, на которых сервер ответил.
typedef ProbeResult = ({String host, int port, EncryptionType encryption});

/// Проверка одного варианта: сервер ответил как надо (подмена в тестах).
typedef ProbeCheck = Future<bool> Function(String host, int port, EncryptionType encryption);

class ServerProbe {
  ServerProbe._();

  /// Варианты IMAP по порядку: SSL на 993, STARTTLS на 143.
  static const imapCandidates = [(993, EncryptionType.ssl), (143, EncryptionType.starttls)];

  /// Варианты SMTP: SSL на 465, STARTTLS на 587, STARTTLS на 25.
  static const smtpCandidates = [
    (465, EncryptionType.ssl),
    (587, EncryptionType.starttls),
    (25, EncryptionType.starttls),
  ];

  /// Первый отвечающий вариант IMAP на [host], кроме уже проверенного
  /// [tried]. null — не ответил ни один.
  static Future<ProbeResult?> imap(String host, {(int, EncryptionType)? tried, ProbeCheck? check}) =>
      _first([host], imapCandidates, tried: tried, check: check ?? checkImap);

  /// Первый отвечающий вариант SMTP: на [host], затем на [moreHosts]
  /// (например, на сервере IMAP — у небольших организаций он один).
  static Future<ProbeResult?> smtp(String host,
          {List<String> moreHosts = const [], (int, EncryptionType)? tried, ProbeCheck? check}) =>
      _first([host, ...moreHosts], smtpCandidates, tried: tried, check: check ?? checkSmtp);

  static Future<ProbeResult?> _first(
    List<String> hosts,
    List<(int, EncryptionType)> candidates, {
    required (int, EncryptionType)? tried,
    required ProbeCheck check,
  }) async {
    final seen = <String>{};
    for (final h in hosts) {
      final host = h.trim().toLowerCase();
      if (host.isEmpty || !seen.add(host)) continue;
      for (final (port, enc) in candidates) {
        if (host == hosts.first.trim().toLowerCase() && tried != null && tried.$1 == port && tried.$2 == enc) {
          continue;
        }
        try {
          if (await check(host, port, enc)) {
            AppLogger.info('Подбор сервера: ответил $host:$port ${enc.name}');
            return (host: host, port: port, encryption: enc);
          }
        } catch (_) {
          // Не ответил — следующий вариант.
        }
      }
    }
    return null;
  }

  static const _connectTimeout = Duration(seconds: 6);
  static const _readTimeout = Duration(seconds: 6);

  /// IMAP отвечает на [port] с шифрованием [encryption]: приветствие
  /// «* OK» (или «* PREAUTH»), у STARTTLS — ещё и переход на TLS.
  static Future<bool> checkImap(String host, int port, EncryptionType encryption) async {
    final s = await _Line.open(host, port, tls: encryption == EncryptionType.ssl);
    try {
      final hello = await s.read();
      if (!(hello.startsWith('* OK') || hello.startsWith('* PREAUTH'))) return false;
      if (encryption != EncryptionType.starttls) return true;
      s.write('a1 STARTTLS');
      final r = await s.readUntil((l) => l.startsWith('a1 '));
      if (!r.toUpperCase().startsWith('A1 OK')) return false;
      return await s.upgrade(host);
    } finally {
      s.close();
    }
  }

  /// SMTP отвечает: приветствие «220», у STARTTLS — EHLO, STARTTLS и
  /// переход на TLS.
  static Future<bool> checkSmtp(String host, int port, EncryptionType encryption) async {
    final s = await _Line.open(host, port, tls: encryption == EncryptionType.ssl);
    // Последняя строка ответа SMTP — «NNN текст»; строка не в виде ответа
    // SMTP (другой протокол на порту) — тоже конец.
    bool last(String l) => l.length < 4 || l[3] == ' ' || int.tryParse(l.substring(0, 3)) == null;
    try {
      final hello = await s.readUntil(last);
      if (!hello.startsWith('220')) return false;
      if (encryption != EncryptionType.starttls) return true;
      s.write('EHLO localhost');
      final ehlo = await s.readUntil(last);
      if (!ehlo.startsWith('250')) return false;
      s.write('STARTTLS');
      final r = await s.readUntil(last);
      if (!r.startsWith('220')) return false;
      return await s.upgrade(host);
    } finally {
      s.close();
    }
  }
}

/// Построчный разговор с сервером (CRLF).
class _Line {
  Socket _socket;
  StreamSubscription<List<int>>? _sub;
  final _buf = StringBuffer();
  final _lines = <String>[];
  Completer<void>? _wait;
  bool _closed = false;

  _Line(this._socket) {
    _listen();
  }

  static Future<_Line> open(String host, int port, {required bool tls}) async {
    final Socket socket = tls
        ? await SecureSocket.connect(host, port, timeout: ServerProbe._connectTimeout, onBadCertificate: (_) => true)
        : await Socket.connect(host, port, timeout: ServerProbe._connectTimeout);
    return _Line(socket);
  }

  void _listen() {
    _sub = _socket.listen((data) {
      _buf.write(latin1.decode(data, allowInvalid: true));
      var text = _buf.toString();
      var i = text.indexOf('\n');
      while (i >= 0) {
        _lines.add(text.substring(0, i).replaceAll('\r', ''));
        text = text.substring(i + 1);
        i = text.indexOf('\n');
      }
      _buf
        ..clear()
        ..write(text);
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
    }, onError: (Object _) {
      _closed = true;
      _wake();
    }, cancelOnError: true);
  }

  void _wake() {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<String> read() async {
    while (_lines.isEmpty) {
      if (_closed) throw const SocketException('сервер закрыл соединение');
      _wait = Completer<void>();
      await _wait!.future.timeout(ServerProbe._readTimeout);
    }
    return _lines.removeAt(0);
  }

  /// Строки до той, что подходит под [last] (включительно), склеенные; у
  /// SMTP — многострочный ответ «250-…», «250 …».
  Future<String> readUntil(bool Function(String line) last) async {
    final out = <String>[];
    for (var i = 0; i < 64; i++) {
      final l = await read();
      out.add(l);
      if (last(l)) return out.join('\n');
    }
    return out.join('\n');
  }

  void write(String line) => _socket.add(latin1.encode('$line\r\n'));

  /// Переход на TLS после STARTTLS.
  Future<bool> upgrade(String host) async {
    await _sub?.cancel();
    _sub = null;
    final secure = await SecureSocket.secure(_socket, host: host, onBadCertificate: (_) => true)
        .timeout(ServerProbe._connectTimeout);
    _socket = secure;
    return true;
  }

  void close() {
    try {
      unawaited(_sub?.cancel());
      _socket.destroy();
    } catch (_) {}
  }
}

// lib/services/mail/sieve/managesieve_client.dart
// Клиент ManageSieve (RFC 5804): фильтры почты на сервере IMAP.
//
// Sieve — язык правил, которые сервер выполняет при доставке письма
// (переложить в папку, отметить, переслать). ManageSieve — протокол, по
// которому их читают и меняют (порт 4190). Есть у Dovecot (Pigeonhole) —
// корпоративные и свои серверы, Fastmail, mailbox.org, Posteo; у Gmail,
// Яндекса и Mail.ru — нет (там правила — в веб-интерфейсе).
//
// Команды: STARTTLS, AUTHENTICATE "PLAIN", LISTSCRIPTS, GETSCRIPT,
// PUTSCRIPT, SETACTIVE, LOGOUT. Сертификат сервера проверяется по тем же
// правилам, что у IMAP (принятые по отпечатку — onBadCertificate).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Ответ сервера NO/BYE или нарушение протокола.
class SieveException implements Exception {
  /// Код ответа без скобок («QUOTA», «AUTH-TOO-WEAK»…), если есть.
  final String? code;
  final String message;
  const SieveException(this.message, {this.code});

  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// Скрипт на сервере.
class SieveScriptInfo {
  final String name;
  final bool active;
  const SieveScriptInfo(this.name, this.active);
}

/// Слово ответа: атом (OK, NO, ACTIVE…) или строка (в кавычках / литерал).
class SieveToken {
  final String value;
  final bool atom;
  const SieveToken(this.value, {required this.atom});

  @override
  String toString() => atom ? value : '"$value"';
}

/// Разбор строк ответа ManageSieve. Отдельно от сокета — для тестов.
class SieveResponseReader {
  final List<int> _buf = [];
  final _waiters = <Completer<void>>[];
  bool _closed = false;

  void add(List<int> data) {
    _buf.addAll(data);
    _wake();
  }

  void close() {
    _closed = true;
    _wake();
  }

  void _wake() {
    final w = List.of(_waiters);
    _waiters.clear();
    for (final c in w) {
      if (!c.isCompleted) c.complete();
    }
  }

  Future<void> _more() {
    if (_closed) throw const SieveException('connection closed');
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  Future<List<int>> _line() async {
    while (true) {
      for (var i = 0; i + 1 < _buf.length; i++) {
        if (_buf[i] == 13 && _buf[i + 1] == 10) {
          final line = _buf.sublist(0, i);
          _buf.removeRange(0, i + 2);
          return line;
        }
      }
      await _more();
    }
  }

  Future<List<int>> _bytes(int n) async {
    while (_buf.length < n) {
      await _more();
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  /// Одна логическая строка ответа (литералы {n} внутри читаются целиком).
  Future<List<SieveToken>> readLine() async {
    final tokens = <SieveToken>[];
    var line = await _line();
    var i = 0;
    while (true) {
      while (i < line.length && line[i] == 32) {
        i++;
      }
      if (i >= line.length) break;
      final c = line[i];
      if (c == 34) {
        // "строка" с экранированием \" и \\
        final out = <int>[];
        i++;
        while (i < line.length && line[i] != 34) {
          if (line[i] == 92 && i + 1 < line.length) i++;
          out.add(line[i]);
          i++;
        }
        i++; // закрывающая кавычка
        tokens.add(SieveToken(utf8.decode(out, allowMalformed: true), atom: false));
      } else if (c == 123) {
        // {n} или {n+} в конце строки — дальше n байт литерала
        final close = line.indexOf(125, i);
        if (close < 0) throw const SieveException('bad literal');
        final n = int.parse(ascii.decode(line.sublist(i + 1, close)).replaceAll('+', ''));
        final data = await _bytes(n);
        tokens.add(SieveToken(utf8.decode(data, allowMalformed: true), atom: false));
        line = await _line(); // продолжение логической строки
        i = 0;
      } else if (c == 40) {
        // (КОД "доп") — код ответа: берём первое слово
        var depth = 0;
        final start = i;
        var inQuote = false;
        while (i < line.length) {
          final ch = line[i];
          if (ch == 34) inQuote = !inQuote;
          if (!inQuote && ch == 40) depth++;
          if (!inQuote && ch == 41) {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
          i++;
        }
        tokens.add(SieveToken(utf8.decode(line.sublist(start, i), allowMalformed: true), atom: true));
      } else {
        final start = i;
        while (i < line.length && line[i] != 32) {
          i++;
        }
        tokens.add(SieveToken(ascii.decode(line.sublist(start, i), allowInvalid: true), atom: true));
      }
    }
    return tokens;
  }

  /// Строки до OK/NO/BYE. OK — возвращает строки данных; NO/BYE — исключение.
  Future<List<List<SieveToken>>> readResponse() async {
    final data = <List<SieveToken>>[];
    while (true) {
      final t = await readLine();
      if (t.isEmpty) continue;
      final head = t.first;
      if (head.atom) {
        final s = head.value.toUpperCase();
        if (s == 'OK') return data;
        if (s == 'NO' || s == 'BYE') {
          String? code;
          String msg = s == 'BYE' ? 'connection closed by server' : 'command failed';
          for (final x in t.skip(1)) {
            if (x.atom && x.value.startsWith('(')) {
              code = x.value.substring(1, x.value.length - 1).split(' ').first.replaceAll('"', '');
            } else if (!x.atom) {
              msg = x.value;
            }
          }
          throw SieveException(msg, code: code);
        }
      }
      data.add(t);
    }
  }
}

/// Строка в кавычках для команды.
String sieveQuote(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

/// Литерал {n+} — для текста скрипта (переводы строк, любые символы).
List<int> sieveLiteral(String s) {
  final b = utf8.encode(s);
  return [...ascii.encode('{${b.length}+}\r\n'), ...b];
}

class ManageSieveClient {
  final String host;
  final int port;
  final bool Function(X509Certificate cert)? onBadCertificate;
  final Duration timeout;

  /// Ожидание соединения (1.7.3): у служб без ManageSieve (iCloud и др.)
  /// порт 4190 молчит — раньше экран ждал ответа 20 с и дольше.
  final Duration connectTimeout;

  ManageSieveClient({
    required this.host,
    this.port = 4190,
    this.onBadCertificate,
    this.timeout = const Duration(seconds: 20),
    this.connectTimeout = const Duration(seconds: 10),
  });

  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  SieveResponseReader _reader = SieveResponseReader();

  /// Возможности сервера: SIEVE (расширения), SASL, STARTTLS, VERSION…
  Map<String, String> capabilities = {};

  /// Расширения Sieve на сервере (fileinto, imap4flags, copy…).
  Set<String> get extensions =>
      (capabilities['SIEVE'] ?? '').toLowerCase().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();

  void _listen(Socket s) {
    _reader = SieveResponseReader();
    _sub = s.listen(_reader.add, onDone: _reader.close, onError: (_) => _reader.close());
  }

  Future<T> _t<T>(Future<T> f) => f.timeout(timeout);

  void _parseCapabilities(List<List<SieveToken>> lines) {
    capabilities = {
      for (final l in lines)
        if (l.isNotEmpty) l.first.value.toUpperCase(): l.length > 1 ? l[1].value : '',
    };
  }

  /// Подключиться, включить TLS (STARTTLS) и войти.
  Future<void> connect(String user, String password) async {
    final Socket s;
    try {
      s = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException catch (e) {
      throw SieveException('no answer from $host:$port (${e.osError?.message ?? e.message})', code: 'NO-ANSWER');
    }
    _socket = s;
    _listen(s);
    try {
      // Приветствие с возможностями — сразу после соединения.
      _parseCapabilities(await _reader.readResponse().timeout(connectTimeout));
    } on TimeoutException {
      throw SieveException('no greeting from $host:$port', code: 'NO-ANSWER');
    }
    if (!capabilities.containsKey('STARTTLS')) {
      // Пароль открытым текстом не отправляем.
      throw const SieveException('server does not offer STARTTLS', code: 'NO-TLS');
    }
    await _send(ascii.encode('STARTTLS\r\n'));
    await _t(_reader.readResponse());
    _sub?.pause();
    final secure = await _t(SecureSocket.secure(s, host: host, onBadCertificate: onBadCertificate));
    unawaited(_sub?.cancel());
    _socket = secure;
    _listen(secure);
    // После TLS сервер заново присылает возможности (RFC 5804, 2.2).
    _parseCapabilities(await _t(_reader.readResponse()));

    final sasl = (capabilities['SASL'] ?? '').toUpperCase().split(RegExp(r'\s+'));
    if (!sasl.contains('PLAIN')) {
      throw SieveException('PLAIN not supported (${capabilities['SASL'] ?? ''})', code: 'NO-PLAIN');
    }
    final token = base64.encode(utf8.encode('\u0000$user\u0000$password'));
    await _send(ascii.encode('AUTHENTICATE "PLAIN" "$token"\r\n'));
    final List<List<SieveToken>> after;
    try {
      after = await _t(_reader.readResponse());
    } on SieveException catch (e) {
      // Отказ на входе — логин или пароль (код ответа — если сервер его дал).
      throw SieveException(e.message, code: e.code ?? 'AUTH');
    }
    // Некоторые серверы присылают возможности и после входа.
    if (after.isNotEmpty) _parseCapabilities(after);
  }

  Future<void> _send(List<int> bytes) async {
    final s = _socket;
    if (s == null) throw const SieveException('not connected');
    s.add(bytes);
    await _t(s.flush());
  }

  Future<List<List<SieveToken>>> _command(String line, [List<int>? literal]) async {
    await _send([...utf8.encode(line), if (literal != null) ...[32, ...literal], 13, 10]);
    return _t(_reader.readResponse());
  }

  Future<List<SieveScriptInfo>> listScripts() async {
    final lines = await _command('LISTSCRIPTS');
    return [
      for (final l in lines)
        if (l.isNotEmpty && !l.first.atom)
          SieveScriptInfo(l.first.value, l.length > 1 && l[1].atom && l[1].value.toUpperCase() == 'ACTIVE'),
    ];
  }

  Future<String> getScript(String name) async {
    final lines = await _command('GETSCRIPT ${sieveQuote(name)}');
    for (final l in lines) {
      if (l.isNotEmpty && !l.first.atom) return l.first.value;
    }
    return '';
  }

  /// Записать скрипт; сервер проверяет синтаксис и отвечает NO с причиной.
  Future<void> putScript(String name, String text) =>
      _command('PUTSCRIPT ${sieveQuote(name)}', sieveLiteral(text));

  Future<void> setActive(String name) => _command('SETACTIVE ${sieveQuote(name)}');

  Future<void> logout() async {
    try {
      await _command('LOGOUT');
    } catch (_) {}
    await close();
  }

  Future<void> close() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    try {
      await _socket?.close();
    } catch (_) {}
    _socket?.destroy();
    _socket = null;
  }
}

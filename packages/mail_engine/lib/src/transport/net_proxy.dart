// lib/src/transport/net_proxy.dart
// Прокси для соединений с почтовыми серверами (2.6.5, план 08.11.2026 п. 1:
// «в корпоративном Wi-Fi с обязательным прокси EAS/EWS/IMAP не работают»).
//
// Какой прокси нужен для узла, решает приложение ([NetProxy.lookup]: ключи
// MDM, настройки системы и PAC, переменные окружения). Здесь — только
// подключение через него: туннель HTTP CONNECT (RFC 9110, 9.3.6) к узлу
// почтового сервера, поверх него — TLS с проверкой сертификата самого
// сервера (имя — узла, а не прокси). Так работают и HTTPS (Exchange, EWS,
// Graph, DAV), и IMAP/SMTP: неявный TLS, открытый текст и STARTTLS.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Прокси-сервер: узел, порт и, если нужен, вход (Basic).
class ProxyHop {
  final String host;
  final int port;

  /// «логин:пароль» для заголовка Proxy-Authorization: Basic (null — без входа).
  final String? credentials;

  const ProxyHop(this.host, this.port, {this.credentials});

  @override
  String toString() => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is ProxyHop && other.host == host && other.port == port && other.credentials == credentials;

  @override
  int get hashCode => Object.hash(host, port, credentials);
}

/// Прокси для узла [host]:[port]; null — напрямую. [secure] — соединение
/// будет шифроваться (TLS сразу или после STARTTLS).
typedef ProxyLookup = Future<ProxyHop?> Function(String host, int port, {required bool secure});

/// Прокси требует входа, а данных нет или они не подошли (407).
class ProxyAuthRequiredException implements IOException {
  final ProxyHop proxy;
  const ProxyAuthRequiredException(this.proxy);
  @override
  String toString() => 'Прокси $proxy требует входа (HTTP 407)';
}

/// Прокси отказал в туннеле к узлу (403, 502…).
class ProxyTunnelException implements IOException {
  final ProxyHop proxy;
  final String target;
  final String status;
  const ProxyTunnelException(this.proxy, this.target, this.status);
  @override
  String toString() => 'Прокси $proxy не открыл туннель к $target: $status';
}

class NetProxy {
  NetProxy._();

  /// Задаёт приложение (и в фоновом изоляте). null — всегда напрямую.
  static ProxyLookup? lookup;

  /// Прокси для узла или null (напрямую). Сбой определения — напрямую:
  /// без прокси почта хотя бы там, где он не обязателен, работает.
  static Future<ProxyHop?> forHost(String host, int port, {bool secure = true}) async {
    final l = lookup;
    if (l == null || isLocalHost(host)) return null;
    try {
      return await l(host, port, secure: secure).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// Заметки для журнала приложения (туннель не открылся — напрямую).
  static void Function(String message)? onNote;

  /// Туннель к [host]:[port], если узлу нужен прокси; null — напрямую.
  /// Прокси отказал или недоступен — тоже напрямую, как браузеры при
  /// «PROXY …; DIRECT» в PAC: прокси часто пускает CONNECT только на 443,
  /// а IMAP и SMTP в такой сети открыты напрямую. Не вышло и напрямую —
  /// ошибка будет обычной ошибкой соединения.
  static Future<ProxyTunnel?> tunnelFor(String host, int port,
      {bool secure = true, Duration timeout = const Duration(seconds: 20)}) async {
    final key = '$host:$port';
    final until = _directUntil[key];
    if (until != null && DateTime.now().isBefore(until)) return null;
    final hop = await forHost(host, port, secure: secure);
    if (hop == null) return null;
    try {
      return await openTunnel(hop, host, port, timeout: timeout);
    } catch (e) {
      // Не ждать отказа прокси при каждой синхронизации: 2 минуты напрямую.
      _directUntil[key] = DateTime.now().add(const Duration(minutes: 2));
      onNote?.call('Прокси $hop → $key: ${e is IOException ? e : e.runtimeType}; соединение напрямую');
      return null;
    }
  }

  static final _directUntil = <String, DateTime>{};

  /// Забыть отказы прокси (сменилась сеть или настройки).
  static void resetFailures() => _directUntil.clear();

  /// Подключить клиента enough_mail к готовому сокету туннеля его же
  /// connectToServer (без TLS: TLS уже на сокете): [connect] вызывает его,
  /// первый Socket.connect внутри получает [socket], [onUse] — в этот
  /// момент (клиент уже записал свои сведения о соединении). Так клиент
  /// сам сбрасывает своё состояние приветствия — и при повторном
  /// подключении (SMTP 465 → 587). Следующие Socket.connect — обычные.
  static Future<T> viaSocket<T>(Socket socket, Future<T> Function() connect, {void Function()? onUse}) =>
      IOOverrides.runWithIOOverrides(connect, _FirstSocket(socket, onUse));

  /// Узел этой машины (OAuth-возврат на 127.0.0.1, отладка) — всегда напрямую.
  static bool isLocalHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '::1' || h.startsWith('127.') || h == '[::1]';
  }

  /// Открыть туннель через [proxy] к [host]:[port]. Ответ прокси читается
  /// до конца заголовков; данные сервера, пришедшие следом (приветствие
  /// IMAP/SMTP в том же пакете), сохраняются в туннеле.
  static Future<ProxyTunnel> openTunnel(ProxyHop proxy, String host, int port,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final socket = await Socket.connect(proxy.host, proxy.port, timeout: timeout);
    final target = host.contains(':') && !host.startsWith('[') ? '[$host]:$port' : '$host:$port';
    final auth = proxy.credentials == null
        ? ''
        : 'Proxy-Authorization: Basic ${base64.encode(utf8.encode(proxy.credentials!))}\r\n';
    socket.write('CONNECT $target HTTP/1.1\r\nHost: $target\r\n${auth}Proxy-Connection: Keep-Alive\r\n\r\n');
    final buf = BytesBuilder(copy: false);
    final head = Completer<List<int>>();
    late final StreamSubscription<Uint8List> sub;
    final extra = <Uint8List>[];
    var headDone = false;
    final rest = StreamController<Uint8List>(sync: true);
    sub = socket.listen((data) {
      if (headDone) {
        rest.add(data);
        return;
      }
      buf.add(data);
      final bytes = buf.toBytes();
      final end = _headerEnd(bytes);
      if (end < 0) {
        if (bytes.length > 16 * 1024) {
          headDone = true;
          head.completeError(ProxyTunnelException(proxy, target, 'слишком длинный ответ'));
        }
        return;
      }
      headDone = true;
      if (end < bytes.length) extra.add(Uint8List.fromList(bytes.sublist(end)));
      head.complete(bytes.sublist(0, end));
    }, onError: (Object e, StackTrace st) {
      if (!head.isCompleted) {
        head.completeError(e, st);
      } else {
        rest.addError(e, st);
      }
    }, onDone: () {
      if (!head.isCompleted) {
        head.completeError(ProxyTunnelException(proxy, target, 'соединение закрыто'));
      } else {
        unawaited(rest.close());
      }
    });
    try {
      final h = await head.future.timeout(timeout);
      final status = latin1.decode(h).split('\r\n').first.trim();
      final code = int.tryParse(status.split(' ').length > 1 ? status.split(' ')[1] : '') ?? 0;
      if (code == 407) throw ProxyAuthRequiredException(proxy);
      if (code < 200 || code > 299) throw ProxyTunnelException(proxy, target, status);
    } catch (_) {
      await sub.cancel();
      socket.destroy();
      unawaited(rest.close());
      rethrow;
    }
    return ProxyTunnel._(socket, sub, extra, rest, host, proxy);
  }

  static int _headerEnd(List<int> b) {
    for (var i = 3; i < b.length; i++) {
      if (b[i - 3] == 13 && b[i - 2] == 10 && b[i - 1] == 13 && b[i] == 10) return i + 1;
    }
    return -1;
  }
}

/// Первый Socket.connect — готовый сокет туннеля, остальные — как обычно.
final class _FirstSocket extends IOOverrides {
  _FirstSocket(this._socket, this._onUse);
  Socket? _socket;
  final void Function()? _onUse;

  @override
  Future<Socket> socketConnect(host, int port, {sourceAddress, int sourcePort = 0, Duration? timeout}) {
    final s = _socket;
    if (s == null) {
      return super.socketConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort, timeout: timeout);
    }
    _socket = null;
    _onUse?.call();
    return Future.value(s);
  }
}

/// Открытый туннель к узлу через прокси.
class ProxyTunnel {
  ProxyTunnel._(this._socket, this._sub, this._extra, this._rest, this.host, this.proxy);

  /// Прокси, через который открыт туннель.
  final ProxyHop proxy;

  final Socket _socket;
  final StreamSubscription<Uint8List> _sub;
  final List<Uint8List> _extra;
  final StreamController<Uint8List> _rest;

  /// Узел почтового сервера (по нему проверяется сертификат).
  final String host;

  bool _used = false;

  /// TLS к серверу поверх туннеля. До рукопожатия сервер ничего не шлёт;
  /// если данные всё же пришли (сервер ждёт открытый текст) — ошибка.
  Future<SecureSocket> secure({
    SecurityContext? context,
    bool Function(X509Certificate certificate)? onBadCertificate,
  }) async {
    if (_used) throw StateError('Туннель уже использован');
    _used = true;
    _sub.pause();
    if (_extra.isNotEmpty) {
      _socket.destroy();
      throw ProxyTunnelException(proxy, host, 'сервер ответил открытым текстом вместо TLS');
    }
    return SecureSocket.secure(_socket, host: host, context: context, onBadCertificate: onBadCertificate);
  }

  /// Открытый текст поверх туннеля (IMAP/SMTP до STARTTLS): сокет, который
  /// сначала отдаёт уже прочитанное. STARTTLS — [upgrade].
  Socket plain() {
    if (_used) throw StateError('Туннель уже использован');
    _used = true;
    return TunnelSocket._(this);
  }

  /// STARTTLS на туннеле, открытом [plain]: TLS к серверу на том же
  /// соединении. Прежний сокет больше ничего не получает.
  Future<SecureSocket> upgrade({
    SecurityContext? context,
    bool Function(X509Certificate certificate)? onBadCertificate,
  }) {
    _sub.pause();
    return SecureSocket.secure(_socket, host: host, context: context, onBadCertificate: onBadCertificate);
  }
}

/// Сокет открытого текста поверх туннеля: данные — сначала прочитанные
/// вместе с ответом прокси, затем из соединения; запись — в соединение.
class TunnelSocket extends Stream<Uint8List> implements Socket {
  TunnelSocket._(this._t) {
    _out = StreamController<Uint8List>(
      onListen: () {
        for (final e in _t._extra) {
          _out.add(e);
        }
        _t._extra.clear();
        _fwd = _t._rest.stream.listen(_out.add, onError: _out.addError, onDone: _out.close);
      },
      onPause: () => _fwd?.pause(),
      onResume: () => _fwd?.resume(),
      onCancel: () => _fwd?.cancel(),
    );
  }

  final ProxyTunnel _t;
  late final StreamController<Uint8List> _out;
  StreamSubscription<Uint8List>? _fwd;

  /// Туннель (для STARTTLS — [ProxyTunnel.upgrade]).
  ProxyTunnel get tunnel => _t;

  Socket get _s => _t._socket;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _out.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  Encoding get encoding => _s.encoding;
  @override
  set encoding(Encoding value) => _s.encoding = value;
  @override
  void add(List<int> data) => _s.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _s.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _s.addStream(stream);
  @override
  Future<void> flush() => _s.flush();
  @override
  Future<void> close() => _s.close();
  @override
  Future<void> get done => _s.done;
  @override
  void write(Object? object) => _s.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) => _s.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _s.writeln(object);
  @override
  void writeCharCode(int charCode) => _s.writeCharCode(charCode);
  @override
  InternetAddress get address => _s.address;
  @override
  InternetAddress get remoteAddress => _s.remoteAddress;
  @override
  int get port => _s.port;
  @override
  int get remotePort => _s.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) => _s.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _s.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _s.setRawOption(option);
  @override
  void destroy() => _s.destroy();
}

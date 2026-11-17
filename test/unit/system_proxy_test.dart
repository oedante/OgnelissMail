// Прокси для почтовых серверов (2.6.5, план 08.11.2026 п. 1): туннель
// HTTP CONNECT для IMAP (неявный TLS и STARTTLS), SMTP и HTTPS; отказ
// прокси — напрямую; разбор настроек системы, MDM и переменных окружения.
// Настоящий TLS: локальные серверы с тестовым сертификатом
// mail.proxy.test (до 2126 г.); локальный прокси сам направляет
// mail.proxy.test на 127.0.0.1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';
import 'package:ogneliss/core/network/strict_pinning.dart';
import 'package:ogneliss/core/network/system_proxy.dart';
import 'package:ogneliss/core/network/windows_proxy.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:ogneliss/services/security/managed_feedback.dart';

const _host = 'mail.proxy.test';

const _cert = '''-----BEGIN CERTIFICATE-----
MIIDMzCCAhugAwIBAgIUIqQM1C9rQoao2x53gwdOGpAFDQQwDQYJKoZIhvcNAQEL
BQAwGjEYMBYGA1UEAwwPbWFpbC5wcm94eS50ZXN0MCAXDTI2MTExNzIyNTczN1oY
DzIxMjYxMDI0MjI1NzM3WjAaMRgwFgYDVQQDDA9tYWlsLnByb3h5LnRlc3QwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC4xj3F9YdeKeHRUGGw6iSxJyQ1
rgEyc4EpCeV7mJ4BHsHGlsyQnvMd3ehmgC3L7/Vey7d06k6lZqpktXlEICNkqI1x
Ehjfs7OUOtkNQT9K6ydH38AvwWeEqJe5ZCR1LvhsEaFOzt8dDaZVRXeK6JHp4Xg0
SwOfx7TRD8qKih6Uf+MztysnAhzV7jeYkpJKUSBalHsHyGruqLybtfUTI/xKMeru
/cH+vIl56aBkaDrMEHO1iN2fbIPxOFJi9KfaYNWxEIJuyODGN5Qb3QHeDML2LbyR
d/2Y4sk80HMre+q0yqH74NEOZ17CfyACR2NoF+4x4dMfgf2hm0l7VWWblehpAgMB
AAGjbzBtMB0GA1UdDgQWBBTdepUYjkRzqFF6t7F9HQcSy5fsxDAfBgNVHSMEGDAW
gBTdepUYjkRzqFF6t7F9HQcSy5fsxDAPBgNVHRMBAf8EBTADAQH/MBoGA1UdEQQT
MBGCD21haWwucHJveHkudGVzdDANBgkqhkiG9w0BAQsFAAOCAQEAtMFKYRv1Ntax
+8sqQ9wTuUYrGscP/R4QYdVnG+PHnOBAWGu6E24XJIqN9+AlvA6BTv5zfOFs06BG
FnbdZxEICcUW0/FSENCraCHGePz6Xfk6BLx5TlqoLRR/TfpbH9/c5t3AMnMOm2ka
jSAxmqcKVZnlpiBLWnSMt/LEkFQ3tyuqJQ9t30BQpn7Gxoy7siCzKmlhaQ8LMp+T
7A2n6lfCtHC/lH2zfyUQyth0q4iTx6Q3B3PKLOVYboZ1P+vhxwbQmwYAefMwAuMe
A5AfYZGlChhl1/SCXlleQnBdH0SB837NHOywYZ0WggxmOe1CrN0ncfwGU05cfHxD
IzKEvyCHng==
-----END CERTIFICATE-----''';
const _key = '''-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC4xj3F9YdeKeHR
UGGw6iSxJyQ1rgEyc4EpCeV7mJ4BHsHGlsyQnvMd3ehmgC3L7/Vey7d06k6lZqpk
tXlEICNkqI1xEhjfs7OUOtkNQT9K6ydH38AvwWeEqJe5ZCR1LvhsEaFOzt8dDaZV
RXeK6JHp4Xg0SwOfx7TRD8qKih6Uf+MztysnAhzV7jeYkpJKUSBalHsHyGruqLyb
tfUTI/xKMeru/cH+vIl56aBkaDrMEHO1iN2fbIPxOFJi9KfaYNWxEIJuyODGN5Qb
3QHeDML2LbyRd/2Y4sk80HMre+q0yqH74NEOZ17CfyACR2NoF+4x4dMfgf2hm0l7
VWWblehpAgMBAAECggEAEVdzExdk/Iv0EzKMRfqRC1qv6yUpHJnllztEC/Jkxe3O
jvu2jaOKur9fIUZKG2Kqhe/wXcCN4A0qKdM0Y0CcQcVl/Po6ARN7DmBANckYDnPS
gcw4sTgMJfxdZ7tuhocBhBcFgNbT7tn0m0/ZP91tsGSGZRYIluA7PVx84b1uevj6
6pj+qZXH6ks6dVo0aoYeQDVe+Oh1BMKJajIb7YQLK/d9TcTo9vvoveGk1RdE2FFh
SBf1rD7AMWbTiOew9mmxf0eHVzLHL3XnJ44S0qcUDaaVXGg+8WZmVJINPT+ZRtbD
53spSBtHM/tGJNY8fOZB9T33U8wwpuIOCdFaCpiwhwKBgQDZghHVjiZyJoJd6qBE
5yexo0axnYn8ueJP9UKmQQLEFagVp4ggOf+BliAQsE+v9GZE/IZj4RhyeYbimRb0
75a/GzGvB2Dw334scSzWsUHCOZrmxrUWSl1dAxb6fXH4JyUS4Uq4dmR7AXtFpDNt
6HRpPYOnmN6VkrLVcR+NopqeGwKBgQDZeTZZiKnFVUI2Zj3d5czCnbWNf3BClDca
tDDrEogTlfcKaSDgSy1uXi1ElvprNtrm5qEindcFuy/KtmYp61oLAJHyrduAPNxh
0FvmP8htfrhSGwWUJKTNR0wytd7HdwY4GZ6P0zTz+aBsc01qkGpYiCFaUvHwdYOz
V8R9TgQrywKBgQDRw+M3NZRWWlU4BeLzEIrzgifXe7tsBEkCG+JfPCtSuCAWYi+i
BM0pSIM8FQ2FAArxVSi2got1O0aemk3NgpK7U5qi1lbjdmbUrYE0vFZS3gNJtTFH
gghwf15VzU1wqS/T+Xp6U5OsHU2paCZBRQGfzTd/FqrzTTszJZnsmnjLKQKBgQC4
10y5pu3deszvXdFhxEtYcyF35gRtonp/qP4XH0Ynl4RFBfvaiCtSLpu9O7IW5KYE
Maxttsim52YEnymQoaiDx3VFVj5F7fTG8ojZ2AasAlP5/VutgcPNcrcyNuDmmqTf
k+7wgez1HYwcAZigZaTuIK5wjiVzYv6QtZ2df20OJwKBgAUWpJRmjcvoPJQlF8N5
E8b6qc2qQH4ZhO3F8dsSXFurvAgxs2c0oFluNf6LbO3QCJDcn/RCg0m2dXQF6o0e
5ocdO/v29lAq9oOg3gFPemzAEX6ZxfBJDSmmH00APPkfn3VhoHCTFX6KP/k4P5Xn
auyRW/NTju9pGgMI/DG2pPoX
-----END PRIVATE KEY-----''';

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(_cert))
  ..usePrivateKeyBytes(utf8.encode(_key));

/// Прокси CONNECT: mail.proxy.test → 127.0.0.1.
class _Proxy {
  _Proxy._(this._server);
  final ServerSocket _server;
  final targets = <String>[];
  final auths = <String?>[];

  /// Ждать первых данных сервера и отдать их одним пакетом с ответом 200.
  bool coalesce = false;

  /// Требовать «Proxy-Authorization: Basic …» с этими данными.
  String? requireAuth;

  /// Отказывать в туннеле (403).
  bool refuse = false;

  int get port => _server.port;
  ProxyHop hop({String? credentials}) => ProxyHop('127.0.0.1', port, credentials: credentials);

  static Future<_Proxy> start() async {
    final p = _Proxy._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    p._server.listen(p._handle);
    return p;
  }

  Future<void> close() => _server.close();

  void _handle(Socket client) {
    final buf = <int>[];
    late StreamSubscription<List<int>> sub;
    sub = client.listen((data) async {
      buf.addAll(data);
      final text = latin1.decode(buf);
      final end = text.indexOf('\r\n\r\n');
      if (end < 0) return;
      sub.pause();
      final lines = text.substring(0, end).split('\r\n');
      final target = lines.first.split(' ')[1];
      targets.add(target);
      final auth = lines
          .where((l) => l.toLowerCase().startsWith('proxy-authorization:'))
          .map((l) => l.substring(l.indexOf(':') + 1).trim())
          .firstOrNull;
      auths.add(auth);
      if (refuse) {
        client.write('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n');
        await client.close();
        return;
      }
      if (requireAuth != null && auth != 'Basic ${base64.encode(utf8.encode(requireAuth!))}') {
        client.write('HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="t"\r\n\r\n');
        await client.close();
        return;
      }
      final colon = target.lastIndexOf(':');
      final name = target.substring(0, colon);
      final port = int.parse(target.substring(colon + 1));
      final upstream = await Socket.connect(name == _host ? '127.0.0.1' : name, port);
      final rest = buf.sublist(end + 4);
      if (rest.isNotEmpty) upstream.add(rest);
      var first = true;
      const ok = 'HTTP/1.1 200 Connection established\r\n\r\n';
      if (!coalesce) client.write(ok);
      upstream.listen((d) {
        if (coalesce && first) {
          client.add([...latin1.encode(ok), ...d]);
        } else {
          client.add(d);
        }
        first = false;
      }, onDone: () => client.destroy(), onError: (_) => client.destroy());
      sub.onData(upstream.add);
      sub.onDone(upstream.destroy);
      sub.resume();
    });
  }
}

/// Строки команд из потока байт.
Stream<String> _lines(Stream<List<int>> s) => s.cast<List<int>>().transform(latin1.decoder).transform(const LineSplitter());

/// IMAP-сервер: неявный TLS ([tls]) или открытый текст со STARTTLS.
class _Imap {
  _Imap._(this.port, this._close);
  final int port;
  final Future<void> Function() _close;
  static final logins = <String>[];

  Future<void> close() => _close();

  static Future<_Imap> start({required bool tls}) async {
    if (tls) {
      final s = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, _serverContext());
      s.listen((c) => _session(c, secure: true));
      return _Imap._(s.port, s.close);
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) => _session(c, secure: false));
    return _Imap._(s.port, s.close);
  }

  static void _session(Socket c, {required bool secure}) {
    c.write('* OK [CAPABILITY IMAP4rev1${secure ? '' : ' STARTTLS'}] ready\r\n');
    late StreamSubscription<String> sub;
    sub = _lines(c).listen((line) async {
      final sp = line.indexOf(' ');
      final tag = line.substring(0, sp);
      final cmd = line.substring(sp + 1);
      final verb = cmd.split(' ').first.toUpperCase();
      switch (verb) {
        case 'CAPABILITY':
          c.write('* CAPABILITY IMAP4rev1${secure ? '' : ' STARTTLS'}\r\n$tag OK done\r\n');
        case 'STARTTLS':
          sub.pause();
          c.write('$tag OK Begin TLS\r\n');
          final s = await SecureSocket.secureServer(c, _serverContext());
          unawaited(sub.cancel());
          _session2(s);
        case 'LOGIN':
          logins.add('${secure ? 'tls' : 'plain'} $cmd');
          c.write('$tag OK LOGIN done\r\n');
        case 'LOGOUT':
          c.write('* BYE\r\n$tag OK bye\r\n');
          await c.close();
        default:
          c.write('$tag BAD unknown\r\n');
      }
    });
  }

  /// После STARTTLS — без приветствия.
  static void _session2(SecureSocket c) {
    _lines(c).listen((line) async {
      final sp = line.indexOf(' ');
      final tag = line.substring(0, sp);
      final cmd = line.substring(sp + 1);
      final verb = cmd.split(' ').first.toUpperCase();
      switch (verb) {
        case 'CAPABILITY':
          c.write('* CAPABILITY IMAP4rev1 AUTH=PLAIN\r\n$tag OK done\r\n');
        case 'LOGIN':
          logins.add('starttls $cmd');
          c.write('$tag OK LOGIN done\r\n');
        case 'LOGOUT':
          c.write('* BYE\r\n$tag OK bye\r\n');
          await c.close();
        default:
          c.write('$tag BAD unknown\r\n');
      }
    });
  }
}

/// SMTP-сервер со STARTTLS.
class _Smtp {
  _Smtp._(this._server);
  final ServerSocket _server;
  int get port => _server.port;
  final seen = <String>[];

  static Future<_Smtp> start() async {
    final s = _Smtp._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    s._server.listen(s._session);
    return s;
  }

  Future<void> close() => _server.close();

  void _session(Socket c) {
    c.write('220 $_host ESMTP\r\n');
    late StreamSubscription<String> sub;
    sub = _lines(c).listen((line) async {
      seen.add(line);
      final verb = line.split(' ').first.toUpperCase();
      switch (verb) {
        case 'EHLO':
          c.write('250-$_host\r\n250 STARTTLS\r\n');
        case 'STARTTLS':
          sub.pause();
          c.write('220 Go ahead\r\n');
          final s = await SecureSocket.secureServer(c, _serverContext());
          unawaited(sub.cancel());
          _lines(s).listen((l) async {
            seen.add('tls $l');
            final v = l.split(' ').first.toUpperCase();
            if (v == 'EHLO') s.write('250-$_host\r\n250 AUTH PLAIN\r\n');
            if (v == 'QUIT') {
              s.write('221 bye\r\n');
              await s.close();
            }
          });
        case 'QUIT':
          c.write('221 bye\r\n');
          await c.close();
      }
    });
  }
}

void main() {
  late _Proxy proxy;
  final notes = <String>[];

  setUp(() async {
    proxy = await _Proxy.start();
    NetProxy.lookup = (host, port, {required secure}) async => proxy.hop();
    NetProxy.onNote = notes.add;
    NetProxy.resetFailures();
    notes.clear();
    _Imap.logins.clear();
  });

  tearDown(() async {
    NetProxy.lookup = null;
    NetProxy.onNote = null;
    await proxy.close();
  });

  group('IMAP через прокси', () {
    test('неявный TLS: туннель к узлу, сертификат — почтового сервера', () async {
      final imap = await _Imap.start(tls: true);
      String? subject;
      final client = TolerantImapClient(onBadCertificate: (c) {
        subject = c.subject;
        return true; // тестовый сертификат не от доверенного ЦС
      });
      await client.connectToServer(_host, imap.port, isSecure: true);
      await client.login('u', 'p');
      expect(proxy.targets, ['$_host:${imap.port}']);
      expect(subject, contains(_host));
      expect(_Imap.logins.single, startsWith('tls LOGIN'));
      expect(client.connectionInfo.isSecure, isTrue);
      await client.logout();
      await imap.close();
    });

    test('STARTTLS: приветствие в одном пакете с ответом прокси, TLS на том же туннеле', () async {
      proxy.coalesce = true;
      final imap = await _Imap.start(tls: false);
      String? subject;
      final client = TolerantImapClient(onBadCertificate: (c) {
        subject = c.subject;
        return true;
      });
      await client.connectToServer(_host, imap.port, isSecure: false);
      await client.startTls();
      await client.login('u', 'p');
      expect(subject, contains(_host));
      expect(_Imap.logins.single, startsWith('starttls LOGIN'));
      expect(proxy.targets, hasLength(1));
      await client.logout();
      await imap.close();
    });

    test('без прокси для узла — напрямую', () async {
      NetProxy.lookup = (host, port, {required secure}) async => null;
      final imap = await _Imap.start(tls: false);
      final client = TolerantImapClient();
      await client.connectToServer('127.0.0.1', imap.port, isSecure: false);
      await client.login('u', 'p');
      expect(proxy.targets, isEmpty);
      await client.logout();
      await imap.close();
    });
  });

  test('SMTP: STARTTLS через прокси и повторное подключение того же клиента', () async {
    final smtp = await _Smtp.start();
    final client = TolerantSmtpClient('client.test', onBadCertificate: (_) => true);
    for (var i = 0; i < 2; i++) {
      await client.connectToServer(_host, smtp.port, isSecure: false);
      await client.ehlo();
      await client.startTls();
      await client.ehlo();
      await client.quit();
    }
    expect(proxy.targets, ['$_host:${smtp.port}', '$_host:${smtp.port}']);
    expect(smtp.seen.where((l) => l.startsWith('tls QUIT')), hasLength(2), reason: 'оба раза — через TLS');
    await smtp.close();
  });

  group('HTTPS через прокси (фабрика соединений приложения)', () {
    late HttpServer server;
    setUp(() async {
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, _serverContext());
      server.listen((r) => r.response
        ..write('ok ${r.uri.path}')
        ..close());
    });
    tearDown(() => server.close(force: true));

    Future<String> get({SecurityContext? ctx}) async {
      final context = ctx ?? (SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(utf8.encode(_cert)));
      final hc = HttpClient(context: context)..findProxy = (_) => 'DIRECT';
      installStrictPinning(hc, context: context, onBadCertificate: (_, __, ___) => false);
      try {
        final req = await hc.getUrl(Uri.parse('https://$_host:${server.port}/ews'));
        final resp = await req.close();
        return await resp.transform(utf8.decoder).join();
      } finally {
        hc.close(force: true);
      }
    }

    test('туннель, проверка сертификата по имени узла', () async {
      expect(await get(), 'ok /ews');
      expect(proxy.targets, ['$_host:${server.port}']);
    });

    test('сертификат не доверен — отказ и через прокси', () async {
      await expectLater(get(ctx: SecurityContext(withTrustedRoots: false)), throwsA(isA<HandshakeException>()));
    });

    test('вход в прокси (Basic)', () async {
      proxy.requireAuth = 'ivan:p@ss';
      NetProxy.lookup = (host, port, {required secure}) async => proxy.hop(credentials: 'ivan:p@ss');
      expect(await get(), 'ok /ews');
      expect(proxy.auths.single, 'Basic ${base64.encode(utf8.encode('ivan:p@ss'))}');
    });
  });

  group('отказ прокси', () {
    test('407 без данных входа — ProxyAuthRequiredException', () async {
      proxy.requireAuth = 'a:b';
      await expectLater(NetProxy.openTunnel(proxy.hop(), _host, 993), throwsA(isA<ProxyAuthRequiredException>()));
    });

    test('403 — напрямую, 2 минуты прокси не спрашивается; сброс', () async {
      proxy.refuse = true;
      expect(await NetProxy.tunnelFor(_host, 993), isNull);
      expect(notes.single, contains('напрямую'));
      expect(await NetProxy.tunnelFor(_host, 993), isNull);
      expect(proxy.targets, hasLength(1), reason: 'второй раз — сразу напрямую');
      NetProxy.resetFailures();
      expect(await NetProxy.tunnelFor(_host, 993), isNull);
      expect(proxy.targets, hasLength(2));
    });

    test('прокси недоступен — напрямую', () async {
      final port = proxy.port;
      await proxy.close();
      NetProxy.lookup = (host, port0, {required secure}) async => ProxyHop('127.0.0.1', port);
      expect(await NetProxy.tunnelFor(_host, 993), isNull);
      proxy = await _Proxy.start(); // для tearDown
    });

    test('свой компьютер и сбой определения — напрямую', () async {
      expect(await NetProxy.forHost('localhost', 993), isNull);
      expect(await NetProxy.forHost('127.0.0.1', 993), isNull);
      NetProxy.lookup = (host, port, {required secure}) async => throw StateError('PAC');
      expect(await NetProxy.forHost(_host, 993), isNull);
    });
  });

  group('разбор настроек', () {
    test('адрес прокси', () {
      expect(SystemProxy.parseProxy('proxy.corp:3128'), const ProxyHop('proxy.corp', 3128));
      expect(SystemProxy.parseProxy('http://proxy.corp:8080/'), const ProxyHop('proxy.corp', 8080));
      expect(SystemProxy.parseProxy('proxy.corp'), const ProxyHop('proxy.corp', 8080));
      expect(SystemProxy.parseProxy('ivan:p%40ss@proxy.corp:3128'),
          const ProxyHop('proxy.corp', 3128, credentials: 'ivan:p@ss'));
      expect(SystemProxy.parseProxy('[fd00::1]:3128'), const ProxyHop('fd00::1', 3128));
      expect(SystemProxy.parseProxy(''), isNull);
      expect(SystemProxy.parseProxy(null), isNull);
      expect(SystemProxy.parseProxy('proxy.corp:0'), isNull);
      expect(SystemProxy.parseProxy('proxy.corp:http'), isNull);
    });

    test('исключения', () {
      const list = '*.corp.local; .intra, mail.example.ru 10.0.0.0/8 <local> 192.168.*';
      expect(SystemProxy.bypassed('ex.corp.local', list), isTrue);
      expect(SystemProxy.bypassed('intra', list), isTrue);
      expect(SystemProxy.bypassed('owa.intra', list), isTrue);
      expect(SystemProxy.bypassed('mail.example.ru', list), isTrue);
      expect(SystemProxy.bypassed('imap.mail.example.ru', list), isTrue);
      expect(SystemProxy.bypassed('10.20.30.40', list), isTrue);
      expect(SystemProxy.bypassed('192.168.1.5', list), isTrue);
      expect(SystemProxy.bypassed('exchange', list), isTrue, reason: '<local> — имя без точки');
      expect(SystemProxy.bypassed('outlook.office365.com', list), isFalse);
      expect(SystemProxy.bypassed('11.0.0.1', list), isFalse);
      expect(SystemProxy.bypassed('notexample.ru', 'example.ru'), isFalse);
      expect(SystemProxy.bypassed('any', '*'), isTrue);
      expect(SystemProxy.bypassed('any', null), isFalse);
    });

    test('ответ системы (Android, iPhone, Mac)', () {
      expect(SystemProxy.firstHop([
        {'type': 'HTTP', 'host': 'proxy.corp', 'port': 3128},
        {'type': 'DIRECT'},
      ]), const ProxyHop('proxy.corp', 3128));
      expect(SystemProxy.firstHop([
        {'type': 'DIRECT'},
      ]), isNull);
      expect(SystemProxy.firstHop([
        {'type': 'SOCKS', 'host': 's', 'port': 1080},
        {'type': 'HTTPS', 'host': 'p', 'port': '8443'},
      ]), const ProxyHop('p', 8443));
      expect(SystemProxy.firstHop(null), isNull);
      expect(SystemProxy.firstHop([]), isNull);
    });

    test('переменные окружения', () {
      final env = {'HTTPS_PROXY': 'http://sp:3128', 'http_proxy': 'hp:8080', 'no_proxy': '.corp.local,localhost'};
      expect(SystemProxy.fromEnvironment(env, 'imap.yandex.ru', secure: true), const ProxyHop('sp', 3128));
      expect(SystemProxy.fromEnvironment(env, 'imap.yandex.ru', secure: false), const ProxyHop('hp', 8080));
      expect(SystemProxy.fromEnvironment(env, 'ex.corp.local', secure: true), isNull);
      expect(SystemProxy.fromEnvironment({'all_proxy': 'socks5://s:1080'}, 'x.ru', secure: true), isNull);
      expect(SystemProxy.fromEnvironment({}, 'x.ru', secure: true), isNull);
    });

    test('список прокси Windows', () {
      expect(WindowsProxy.parseList('proxy.corp:8080', secure: true), const ProxyHop('proxy.corp', 8080));
      expect(WindowsProxy.parseList('http=hp:80;https=sp:443', secure: true), const ProxyHop('sp', 443));
      expect(WindowsProxy.parseList('http=hp:80;https=sp:443', secure: false), const ProxyHop('hp', 80));
      expect(WindowsProxy.parseList('ftp=f:21;http=hp:80', secure: true), const ProxyHop('hp', 80));
      expect(WindowsProxy.parseList('p1:3128; p2:3128', secure: true), const ProxyHop('p1', 3128));
    });
  });

  group('MDM', () {
    tearDown(() {
      ManagedPolicy.current = ManagedPolicy.none;
      SystemProxy.reset();
    });

    test('ключи http_proxy и proxy_bypass', () {
      final p = ManagedPolicy.fromMap(const {'http_proxy': 'proxy.corp:3128', 'proxy_bypass': '*.corp.local'});
      expect(p.httpProxy, 'proxy.corp:3128');
      expect(p.proxyBypass, '*.corp.local');
      expect(ManagedPolicy.fromMap(p.toJson()).httpProxy, 'proxy.corp:3128');
      expect(ManagedKeys.all, containsAll(['http_proxy', 'proxy_bypass', 'pac_url']));
    });

    test('pac_url', () {
      final p = ManagedPolicy.fromMap(const {'pac_url': 'https://wpad.corp/proxy.pac'});
      expect(p.pacUrl, 'https://wpad.corp/proxy.pac');
      expect(ManagedPolicy.fromMap(p.toJson()).pacUrl, p.pacUrl);
    });

    test('отчёт консоли (Android): адрес прокси, исключения без прокси, PAC', () {
      List<FeedbackState> report(Map<Object?, Object?> raw) =>
          managedFeedback(raw, ManagedPolicy.fromMap(raw), pinSet: false, accountAdded: false);
      FeedbackState? of(List<FeedbackState> l, String k) => l.where((e) => e.key == k).firstOrNull;

      final ok = report({'http_proxy': 'ivan:secret@proxy.corp:3128', 'proxy_bypass': '*.corp'});
      expect(of(ok, 'http_proxy')!.severity, FeedbackSeverity.info);
      expect(of(ok, 'http_proxy')!.message, contains('proxy.corp:3128'));
      expect(ok.map((e) => '${e.message} ${e.data}').join(' '), isNot(contains('secret')), reason: 'пароль в отчёт не попадает');
      expect(of(ok, 'proxy_bypass'), isNull);

      final bad = report({'http_proxy': 'proxy.corp:http', 'pac_url': 'https://wpad/p.pac'});
      expect(of(bad, 'http_proxy')!.severity, FeedbackSeverity.error);
      expect(of(bad, 'pac_url')!.message, contains('Ignored'));

      final pacOnly = report({'pac_url': 'https://wpad/p.pac', 'proxy_bypass': '*.corp'});
      expect(of(pacOnly, 'pac_url')!.message, contains('recommended global proxy'));
      expect(of(pacOnly, 'proxy_bypass')!.severity, FeedbackSeverity.error);
    });

    test('прокси организации важнее системного, исключения — напрямую', () async {
      ManagedPolicy.current = ManagedPolicy.fromMap(const {'http_proxy': 'proxy.corp:3128', 'proxy_bypass': '*.corp.local'});
      SystemProxy.reset();
      expect(await SystemProxy.lookup('outlook.office365.com', 443, secure: true), const ProxyHop('proxy.corp', 3128));
      expect(await SystemProxy.lookup('ex.corp.local', 443, secure: true), isNull);
      expect(SystemProxy.summary().join('\n'), contains('outlook.office365.com:443 → proxy.corp:3128 (MDM)'));
    });
  });
}

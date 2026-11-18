// lib/core/network/strict_pinning.dart
// Закрепление сертификата администратора — и при успешной системной
// проверке (решение владельца 08.11.2026, план п. 2).
//
// badCertificateCallback вызывается, только когда системная проверка не
// прошла. Сертификат, выпущенный ЦС, которому доверяет устройство (в том
// числе ЦС, установленный пользователем или профилем, — перехват
// корпоративным прокси или вредоносным профилем), проходил мимо правил
// закрепления. Теперь соединение устанавливается своей фабрикой, и после
// рукопожатия отпечаток сертификата сверяется со строгими правилами
// (CertificatePinningService.checkStrict). Хосты без строгих правил —
// как прежде.

import 'dart:io';

import 'package:mail_engine/mail_engine.dart' show NetProxy;

import 'certificate_pinning_bridge.dart';

/// Поставить клиенту [client] фабрику соединений со сверкой закрепления.
/// [onBadCertificate] — то же решение, что и у badCertificateCallback
/// клиента (системная проверка не прошла).
void installStrictPinning(
  HttpClient client, {
  SecurityContext? context,
  required bool Function(X509Certificate cert, String host, int port) onBadCertificate,
}) {
  client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
    // Прокси, заданный самому HttpClient (findProxy), — CONNECT и TLS
    // выполняет HttpClient со своим badCertificateCallback.
    if (proxyHost != null && proxyPort != null) return Socket.startConnect(proxyHost, proxyPort);
    final host = uri.host;
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
    // Прокси системы, PAC или MDM (2.6.5, план 08.11.2026 п. 1): туннель
    // CONNECT к узлу, TLS — с сертификатом самого узла.
    // Сертификат клиента для узла (mTLS, 2.6.5) — свой контекст TLS.
    final ctx = (secure ? NetProxy.contextFor(host) : null) ?? context;
    final t = await NetProxy.tunnelFor(host, port, secure: secure);
    if (t != null) {
      if (!secure) return ConnectionTask.fromSocket(Future.value(t.plain()), () {});
      final tunneled = t
          .secure(context: ctx, onBadCertificate: (cert) => onBadCertificate(cert, host, port))
          .then<Socket>((s) => _checked(s, host, port));
      return ConnectionTask.fromSocket(tunneled, () {});
    }
    if (!secure) return Socket.startConnect(host, port);
    final task = await SecureSocket.startConnect(host, port,
        context: ctx, onBadCertificate: (cert) => onBadCertificate(cert, host, port));
    return ConnectionTask.fromSocket(task.socket.then<Socket>((s) => _checked(s, host, port)), task.cancel);
  };
}

/// Строгие правила закрепления администратора — после рукопожатия.
Socket _checked(SecureSocket s, String host, int port) {
  final svc = CertificatePinningBridge.instance;
  final cert = s.peerCertificate;
  if (svc != null && cert != null && !svc.checkStrict(cert, host, port)) {
    s.destroy();
    throw HandshakeException('Сертификат $host не совпадает с закреплённым (правило администратора)');
  }
  return s;
}

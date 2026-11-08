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
    // Через прокси HttpClient сам выполняет CONNECT и TLS со своим
    // badCertificateCallback; на телефонах прокси в Dart не настраивается.
    if (proxyHost != null && proxyPort != null) return Socket.startConnect(proxyHost, proxyPort);
    final host = uri.host;
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
    if (!secure) return Socket.startConnect(host, port);
    final task = await SecureSocket.startConnect(host, port,
        context: context, onBadCertificate: (cert) => onBadCertificate(cert, host, port));
    final checked = task.socket.then<Socket>((s) {
      final svc = CertificatePinningBridge.instance;
      final cert = s.peerCertificate;
      if (svc != null && cert != null && !svc.checkStrict(cert, host, port)) {
        s.destroy();
        throw HandshakeException('Сертификат $host не совпадает с закреплённым (правило администратора)');
      }
      return s;
    });
    return ConnectionTask.fromSocket(checked, task.cancel);
  };
}

// lib/core/network/app_http_overrides.dart
// Глобальный HttpOverrides, делегирующий решение о сертификате
// в CertificatePinningService (гибкие правила, не зашитые в код).

import 'dart:io';
import 'certificate_pinning_bridge.dart';

class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final svc = CertificatePinningBridge.instance;
      if (svc == null) return false; // до инициализации — строгая проверка
      return svc.evaluate(cert, host, port);
    };
    return client;
  }
}

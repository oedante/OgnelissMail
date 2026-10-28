// lib/core/network/corporate_http_client_io.dart
// Реализация для мобильных/десктопа (dart:io).
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../device/device_user_agent.dart';
import 'certificate_pinning_bridge.dart';
import 'native_android_http_client.dart';

/// HTTP-клиент движка почты. Решение о сертификате, который не прошёл
/// системную проверку, принимает CertificatePinningService — как у всех
/// остальных клиентов приложения. Раньше здесь всегда был отказ: движок
/// (основной путь EAS) не видел ни доверенных пользователем сертификатов,
/// ни доверенных корпоративных доменов, и вход на сервер с сертификатом
/// внутреннего центра (или без промежуточного) был невозможен.
http.Client createCorporateHttpClient({bool? compat}) {
  final hc = HttpClient();
  hc.badCertificateCallback = (X509Certificate cert, String host, int port) {
    final svc = CertificatePinningBridge.instance;
    if (svc == null) return false; // до инициализации — строгая проверка
    return svc.evaluate(cert, host, port);
  };
  final io = IOClient(hc);
  // Режим «Совместимость со шлюзом» на Android: запросы через сетевой стек
  // системы (TLS как у почтовых приложений Android). Принятые вручную
  // сертификаты и доверенные ЦС передаются в Kotlin с каждым запросом
  // (NativeAndroidHttpClient: trustedSha256, extraCas).
  // 1.6.12: на iPhone то же через NSURLSession (плагин ogneliss_native_http,
  // ios/Classes/NativeHttpPlugin.swift): с User-Agent Почты iPhone и TLS
  // Dart VM шлюз отвечал 403 «If you are not a bot».
  if ((Platform.isAndroid || Platform.isIOS) && (compat ?? DeviceUserAgent.compatMode)) {
    return NativeAndroidHttpClient(io);
  }
  return io;
}

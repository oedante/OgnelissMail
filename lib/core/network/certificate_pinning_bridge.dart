// lib/core/network/certificate_pinning_bridge.dart
// HttpOverrides создаётся вне дерева Riverpod, поэтому используем
// статический мост для доступа к настроенному сервису пиннинга.

import '../security/certificate_pinning_service.dart';

class CertificatePinningBridge {
  static CertificatePinningService? instance;
}

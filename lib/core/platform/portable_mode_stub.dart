// lib/core/platform/portable_mode_stub.dart
// Веб-сборка: переносного режима нет.

abstract final class PortableMode {
  static String? get root => null;
  static bool get active => false;
  static String? failure;
  static void init() {}
}

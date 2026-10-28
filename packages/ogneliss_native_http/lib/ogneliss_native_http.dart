/// Нативная часть режима совместимости со шлюзом (Android).
///
/// Dart-сторона канала `ogneliss/native_http` — в приложении:
/// `lib/core/network/native_android_http_client.dart` и
/// `lib/core/security/trusted_ca_store.dart`. Пакет нужен ради регистрации
/// плагина во всех движках Flutter (основной и фоновый).
library;

const String nativeHttpChannel = 'ogneliss/native_http';

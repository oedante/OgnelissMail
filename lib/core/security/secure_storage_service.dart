// lib/core/security/secure_storage_service.dart
// Безопасное хранилище через flutter_secure_storage.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    // encryptedSharedPreferences устарел (Jetpack Security снят с поддержки):
    // flutter_secure_storage 10 сам переносит данные на свои шифры.
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> deleteAll() => _storage.deleteAll();

  // ═══════════════ АККАУНТЫ ═══════════════

  Future<void> saveAccountPassword(String accountId, String password) =>
      write('pwd_$accountId', password);

  Future<String?> getAccountPassword(String accountId) =>
      read('pwd_$accountId');

  Future<void> deleteAccountPassword(String accountId) =>
      delete('pwd_$accountId');

  Future<void> deleteAccountTokens(String accountId) async {
    await delete('pwd_$accountId');
    await delete('davpw_$accountId'); // пароль приложения для календаря
    await delete('at_$accountId');
    await delete('rt_$accountId');
    await delete('exp_$accountId');
    await delete('proxy_session_$accountId');
    await delete('proxy_$accountId');
    await delete('gat_$accountId'); // токен Microsoft Graph (1.8.10)
    await delete('gexp_$accountId');
    await delete('oc_$accountId');
  }

  // ═══════════════ OAUTH-ПРОКСИ ═══════════════

  /// Данные прокси-сессии аккаунта (JSON: provider, rt(зашифрованный refresh),
  /// at(access), exp). refresh-токен зашифрован ключом функции — клиент его не
  /// читает, только пересылает на /token для обновления.
  Future<void> saveProxyData(String accountId, String json) =>
      write('proxy_$accountId', json);

  Future<String?> getProxyData(String accountId) => read('proxy_$accountId');

  Future<void> deleteProxyData(String accountId) => delete('proxy_$accountId');

  // Совместимость со stateful-вариантом (session):
  Future<void> saveProxySession(String accountId, String session) =>
      write('proxy_session_$accountId', session);

  Future<String?> getProxySession(String accountId) =>
      read('proxy_session_$accountId');

  Future<void> deleteProxySession(String accountId) =>
      delete('proxy_session_$accountId');

  // ═══════════════ OAUTH ═══════════════

  Future<void> saveOAuthTokens({
    required String accountId,
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await write('at_$accountId', accessToken);
    if (refreshToken != null) await write('rt_$accountId', refreshToken);
    if (expiry != null) await write('exp_$accountId', expiry.toIso8601String());
  }

  /// Вход без сервера входа (1.6.2): каким публичным клиентом получен
  /// токен ящика («провайдер|client_id»). null — через сервер входа.
  Future<void> saveOAuthClient(String accountId, String? marker) =>
      marker == null ? delete('oc_$accountId') : write('oc_$accountId', marker);

  Future<String?> getOAuthClient(String accountId) => read('oc_$accountId');

  Future<String?> getAccessToken(String accountId) => read('at_$accountId');
  Future<String?> getRefreshToken(String accountId) => read('rt_$accountId');

  Future<DateTime?> getTokenExpiry(String accountId) async {
    final exp = await read('exp_$accountId');
    return exp != null ? DateTime.tryParse(exp) : null;
  }
}

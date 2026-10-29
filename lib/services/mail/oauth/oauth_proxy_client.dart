// lib/services/mail/oauth/oauth_proxy_client.dart
// Клиент корпоративного OAuth-прокси (Yandex Cloud Function / Debian).
// Stateless-модель: refresh-токен зашифрован ключом функции и хранится у
// клиента как «blob» (rt). Сервер БД не нужен.
//
// Поток:
//   1) loginUrl(provider) → системный браузер → согласие
//   2) прокси редиректит в приложение:
//      com.ogneliss.mail://oauth?at=..&exp=..&rt=<blob>&provider=..
//   3) handleRedirect(accountId, uri) — сохранить токены
//   4) getAccessToken(accountId) — отдаёт кэшированный access или обновляет
//      через POST /token {rt, provider}; прокси вернёт новый access (+ при
//      ротации новый rt).

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart' show OAuthRefreshFailure;
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';

final oauthProxyClientProvider = Provider<OAuthProxyClient>((ref) {
  return OAuthProxyClient(ref.watch(secureStorageProvider));
});

class ProxyToken {
  final String accessToken;
  final DateTime expiresAt;
  final String provider;
  const ProxyToken({required this.accessToken, required this.expiresAt, required this.provider});
  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));
}

class OAuthProxyClient {
  final SecureStorageService _storage;
  OAuthProxyClient(this._storage);

  String get _base => AppConstants.oauthProxyBaseUrl.replaceAll(RegExp(r'/$'), '');
  String get _apiKey => AppConstants.oauthProxyApiKey;

  /// Включён ли прокси (задан baseUrl).
  bool get isEnabled => _base.isNotEmpty;

  /// URL для старта авторизации в браузере.
  Uri loginUrl(String provider, {String? redirect}) {
    return Uri.parse('$_base/oauth/$provider/login').replace(queryParameters: {
      'redirect': redirect ?? AppConstants.oauthProxyRedirect,
    });
  }

  /// Разобрать redirect от прокси (?at&exp&rt&provider) и сохранить.
  Future<bool> handleRedirect(String accountId, Uri uri) async {
    final at = uri.queryParameters['at'];
    final rt = uri.queryParameters['rt'];
    final provider = uri.queryParameters['provider'] ?? '';
    final exp = int.tryParse(uri.queryParameters['exp'] ?? '') ?? 0;
    if (at == null || at.isEmpty) return false;
    await _save(accountId, at: at, rt: rt ?? '', provider: provider, exp: exp);
    return true;
  }

  /// Причина последнего отказа обновления по blob (для журнала и экрана
  /// переподключения). null — последнее обновление прошло.
  static ProxyRefreshFailure? lastFailure;

  /// Разбор ответа прокси об ошибке. Поле error прокси формирует сам
  /// («unauthorized», «bad rt», «token_endpoint_401: invalid_client») —
  /// токенов в нём нет, его можно писать в журнал. Раньше в журнале был
  /// только код: «HTTP 401» не отличал неверный ключ прокси от отозванного
  /// входа Google.
  static ProxyRefreshFailure describeFailure(int status, String body) {
    var err = '';
    var aad = '';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is String) err = m['error'] as String;
      // Код Microsoft (сервер входа 1.8.11): AADSTS65001 — нет согласия.
      if (m is Map && m['aadsts'] is String) aad = m['aadsts'] as String;
    } catch (_) {}
    if (err.length > 120) err = err.substring(0, 120);
    final e = err.toLowerCase();
    if (e == 'unauthorized') {
      return const ProxyRefreshFailure(ProxyFailureKind.proxyKey,
          'прокси не принял ключ приложения (PROXY_API_KEY на сервере и в приложении различаются)');
    }
    if (e.contains('invalid_client') || e.contains('unauthorized_client')) {
      return ProxyRefreshFailure(ProxyFailureKind.serverConfig,
          'провайдер не принял клиент прокси ($err) — проверьте CLIENT_ID/CLIENT_SECRET на сервере');
    }
    if (e == 'bad rt') {
      return const ProxyRefreshFailure(ProxyFailureKind.signIn,
          'прокси не может прочитать сохранённый вход (сменился ключ шифрования на сервере) — нужен повторный вход');
    }
    if (e.contains('invalid_grant')) {
      return ProxyRefreshFailure(ProxyFailureKind.signIn,
          'вход отозван или истёк (invalid_grant${aad.isEmpty ? '' : ', $aad'}) — нужен повторный вход');
    }
    if (status >= 500 || status == 0) {
      return ProxyRefreshFailure(ProxyFailureKind.temporary, 'сбой прокси ($status${err.isEmpty ? '' : ': $err'})');
    }
    return ProxyRefreshFailure(ProxyFailureKind.unknown, err.isEmpty ? 'без пояснения' : err);
  }

  /// Получить действующий access_token (кэш или обновление через /token).
  Future<ProxyToken?> getAccessToken(String accountId) async {
    if (!isEnabled) return null;
    final data = await _load(accountId);
    if (data == null) return null;
    final cachedExp = DateTime.fromMillisecondsSinceEpoch(data['exp'] as int? ?? 0);
    final cachedAt = data['at'] as String? ?? '';
    final provider = data['provider'] as String? ?? '';
    if (cachedAt.isNotEmpty && DateTime.now().isBefore(cachedExp.subtract(const Duration(seconds: 60)))) {
      return ProxyToken(accessToken: cachedAt, expiresAt: cachedExp, provider: provider);
    }
    // Обновляем по refresh-blob
    final rt = data['rt'] as String? ?? '';
    if (rt.isEmpty) return null;
    return _refresh(accountId, rt: rt, provider: provider);
  }

  Future<ProxyToken?> _refresh(String accountId, {required String rt, required String provider}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/token'),
        headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'rt': rt, 'provider': provider}),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        final why = describeFailure(resp.statusCode, resp.body);
        AppLogger.warning('OAuth proxy /token HTTP ${resp.statusCode}: ${why.text}');
        // Данные входа удаляем, только если отозван САМ вход. Раньше — при
        // любом 400/401, в том числе при неверном ключе прокси после
        // переезда сервера: все OAuth-ящики разом теряли вход.
        if (why.needsSignIn) await _storage.deleteProxyData(accountId);
        return null;
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final at = m['access_token'] as String?;
      if (at == null) return null;
      final exp = m['expires_at'] as int? ?? DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final newRt = m['rt'] as String? ?? rt;
      await _save(accountId, at: at, rt: newRt, provider: provider, exp: exp);
      return ProxyToken(accessToken: at, expiresAt: DateTime.fromMillisecondsSinceEpoch(exp), provider: provider);
    } catch (e) {
      AppLogger.warning('OAuth proxy refresh error: $e');
      return null;
    }
  }

  /// Обновить токен по сохранённому у аккаунта rt-blob (не зависит от session).
  /// Возвращает новый access, срок и (при ротации) новый rt-blob. При отказе
  /// бросает [OAuthRefreshFailure] с причиной (раньше — null, и причина
  /// терялась: «HTTP 401» не отличал отозванный вход от неверного ключа).
  /// [resource] 'graph' — токен Microsoft Graph тем же входом Exchange Online
  /// (1.8.11; сервер входа 1.8.11+).
  Future<({String accessToken, DateTime expiresAt, String rt})> refreshWithBlob(
      String rt, String provider, {String? resource}) async {
    if (!isEnabled || rt.isEmpty) {
      throw const OAuthRefreshFailure('нет сохранённого входа', needsSignIn: true);
    }
    final http.Response resp;
    try {
      resp = await http.post(
        Uri.parse('$_base/token'),
        headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'rt': rt, 'provider': provider, if (resource != null) 'resource': resource}),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      AppLogger.warning('OAuth proxy refreshWithBlob: $e');
      throw OAuthRefreshFailure('прокси недоступен ($e)', temporary: true);
    }
    if (resp.statusCode != 200) {
      final why = describeFailure(resp.statusCode, resp.body);
      // Отказ в токене Graph — не отказ входа ящика.
      if (resource == null) lastFailure = why;
      AppLogger.warning('OAuth proxy /token (blob${resource == null ? '' : ', $resource'}) HTTP ${resp.statusCode}: ${why.text}');
      throw OAuthRefreshFailure(why.text,
          needsSignIn: why.needsSignIn, temporary: why.kind == ProxyFailureKind.temporary);
    }
    if (resource == null) lastFailure = null;
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    // Прежний сервер входа resource не знает и выдал бы токен ActiveSync.
    if (resource != null && m['resource'] != resource) {
      throw OAuthRefreshFailure('сервер входа не выдаёт токен $resource — обновите его до 1.8.11');
    }
    final at = m['access_token'] as String?;
    if (at == null || at.isEmpty) {
      throw const OAuthRefreshFailure('прокси не вернул access_token', temporary: true);
    }
    final exp = m['expires_at'] as int? ??
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
    final newRt = m['rt'] as String? ?? rt;
    return (accessToken: at, expiresAt: DateTime.fromMillisecondsSinceEpoch(exp), rt: newRt);
  }

  Future<void> revoke(String accountId) async {
    final data = await _load(accountId);
    await _storage.deleteProxyData(accountId);
    if (!isEnabled || data == null) return;
    try {
      await http.post(
        Uri.parse('$_base/revoke'),
        headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'rt': data['rt'], 'provider': data['provider']}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> _save(String accountId, {required String at, required String rt, required String provider, required int exp}) {
    return _storage.saveProxyData(accountId, jsonEncode({'at': at, 'rt': rt, 'provider': provider, 'exp': exp}));
  }

  Future<Map<String, dynamic>?> _load(String accountId) async {
    final raw = await _storage.getProxyData(accountId);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Повреждённые данные прокси — считаем, что их нет.
      return null;
    }
  }
}


enum ProxyFailureKind { proxyKey, serverConfig, signIn, temporary, unknown }

class ProxyRefreshFailure {
  final ProxyFailureKind kind;
  final String text;
  const ProxyRefreshFailure(this.kind, this.text);

  /// Помогает только повторный вход в ящик.
  bool get needsSignIn => kind == ProxyFailureKind.signIn;
}

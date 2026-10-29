// lib/services/mail/oauth/graph_tokens.dart
// Токены Microsoft Graph для ящиков Exchange Online (1.8.10; с 1.8.11 сам
// Graph — в движке: packages/mail_engine, GraphEngine). Здесь — только то,
// что движку знать не нужно: где взять токен и что делать, если его не дают.
//
// Токен. У токена Microsoft один ресурс: токен ActiveSync (outlook.office365.com)
// к Graph не подходит. Согласие на права Graph просится при входе
// (me.GraphEngine.consentScopes), а токен Graph выдаёт тот же refresh-токен
// отдельным запросом (me.GraphEngine.tokenScopes — все права, на которые
// есть согласие, в том числе выданные администратором): напрямую у Microsoft
// (вход без сервера входа) или через сервер входа (POST /token с
// resource=graph, 1.8.11). Хранится отдельно (gat_/gexp_ в защищённом
// хранилище).
//
// Нет согласия (вход до 1.8.10 или организация не разрешила) — Graph для
// ящика «недоступен» на 12 часов: функции идут по EWS, как раньше; в
// настройках ящика — «Войти снова», чтобы дать согласие. Отказ Graph никогда
// не помечает сам ящик как «требуется вход»: ActiveSync работает и без него.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_exceptions.dart' show OAuthRefreshFailure;
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../engine/engine_log.dart';
import 'direct_oauth.dart';
import 'oauth_proxy_client.dart';

final graphTokensProvider = Provider<GraphTokens>(
    (ref) => GraphTokens(ref.watch(secureStorageProvider), ref.watch(sharedPrefsProvider)));

/// Доступ к Graph у ящика (для настроек ящика).
enum GraphAccess {
  /// Не Exchange Online или ещё не пробовали.
  unknown,

  /// Токен Graph получен.
  ok,

  /// Согласия на права Graph нет — нужен повторный вход (или разрешение
  /// администратора организации).
  noConsent,
}

class GraphTokens {
  final SecureStorageService _storage;
  final SharedPreferences _prefs;
  final http.Client? _httpOverride;
  final OAuthProxyClient? _proxyOverride;

  GraphTokens(this._storage, this._prefs, {http.Client? httpClient, OAuthProxyClient? proxy})
      : _httpOverride = httpClient,
        _proxyOverride = proxy;

  /// Пауза после отказа в согласии: столько Graph для ящика не пробуется.
  static const noConsentPause = Duration(hours: 12);

  final Map<String, Future<String?>> _inflight = {};
  final Map<String, me.GraphEngine> _engines = {};
  final Map<String, AccountModel> _accounts = {};

  static String _stateKey(String accountId) => 'graph_state_$accountId';

  /// Graph есть только у ящиков Exchange Online (вход Microsoft по OAuth).
  bool supports(AccountModel a) => a.isExchangeOnlineOAuth;

  /// Движок Graph ящика (один на ящик): токен он просит здесь. null — у
  /// ящика Graph нет.
  me.GraphEngine? engine(AccountModel a) {
    if (!supports(a)) return null;
    _accounts[a.id] = a;
    return _engines[a.id] ??= me.GraphEngine(
      tokenSource: ({bool force = false}) {
        final acc = _accounts[a.id];
        return acc == null ? Future.value(null) : token(acc, force: force);
      },
      httpClient: _httpOverride,
      logger: newEngineLog(),
    );
  }

  GraphAccess access(AccountModel a) {
    if (!supports(a)) return GraphAccess.unknown;
    final s = _prefs.getString(_stateKey(a.id)) ?? '';
    if (s == 'ok') return GraphAccess.ok;
    if (s.startsWith('noconsent:')) return GraphAccess.noConsent;
    return GraphAccess.unknown;
  }

  /// Забыть отказ (после «Войти снова» — согласие могло появиться).
  Future<void> reset(String accountId) async {
    await _prefs.remove(_stateKey(accountId));
    await _storage.delete('gat_$accountId');
    await _storage.delete('gexp_$accountId');
  }

  bool _paused(String accountId) {
    final s = _prefs.getString(_stateKey(accountId)) ?? '';
    if (!s.startsWith('noconsent:')) return false;
    final at = int.tryParse(s.substring('noconsent:'.length)) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at < noConsentPause.inMilliseconds;
  }

  /// Токен Graph ящика; null — Graph недоступен (не Exchange Online, нет
  /// согласия, нет refresh-токена, сбой сети при обновлении).
  Future<String?> token(AccountModel a, {bool force = false}) {
    if (!supports(a)) return Future.value(null);
    final running = _inflight[a.id];
    if (running != null) return running;
    final f = _token(a, force: force);
    _inflight[a.id] = f;
    return f.whenComplete(() => _inflight.remove(a.id));
  }

  Future<String?> _token(AccountModel a, {required bool force}) async {
    if (!force && _paused(a.id)) return null;
    if (!force) {
      final at = await _storage.read('gat_${a.id}');
      final exp = DateTime.tryParse(await _storage.read('gexp_${a.id}') ?? '');
      if (at != null && at.isNotEmpty && exp != null && DateTime.now().isBefore(exp.subtract(const Duration(minutes: 2)))) {
        return at;
      }
    }
    final rt = await _storage.getRefreshToken(a.id);
    if (rt == null || rt.isEmpty) return null;
    final marker = await _storage.getOAuthClient(a.id);
    final client = marker == null ? null : DirectOAuth.graphClient(marker);
    final proxy = _proxyOverride ?? OAuthProxyClient(_storage);
    // Вошёл не напрямую — через сервер входа (у него свой клиент Microsoft).
    if (client == null && (marker != null || !proxy.isEnabled)) return null;
    try {
      final String accessToken;
      final DateTime expiry;
      final String? next;
      if (client != null) {
        final res = await DirectOAuth.refresh(client, rt);
        (accessToken, expiry, next) = (res.accessToken, res.expiry, res.refreshToken);
      } else {
        final res = await proxy.refreshWithBlob(rt, 'exchange', resource: 'graph');
        (accessToken, expiry, next) = (res.accessToken, res.expiresAt, res.rt);
      }
      await _storage.write('gat_${a.id}', accessToken);
      await _storage.write('gexp_${a.id}', expiry.toIso8601String());
      // Microsoft может прислать новый refresh-токен — он же и у ActiveSync.
      if (next != null && next.isNotEmpty && next != rt) await _storage.write('rt_${a.id}', next);
      if (_prefs.getString(_stateKey(a.id)) != 'ok') {
        await _prefs.setString(_stateKey(a.id), 'ok');
        AppLogger.info('Microsoft Graph для ${AppLogger.mask(a.email)}: токен получен');
      }
      return accessToken;
    } on OAuthRefreshFailure catch (e) {
      if (e.temporary) {
        AppLogger.debug('Microsoft Graph: токен не получен (временно) — ${e.reason}');
        return null;
      }
      // Нет согласия на права Graph (или вход отозван — его заметит сам
      // ActiveSync): пауза, функции — по EWS.
      await _prefs.setString(_stateKey(a.id), 'noconsent:${DateTime.now().millisecondsSinceEpoch}');
      AppLogger.info('Microsoft Graph для ${AppLogger.mask(a.email)}: нет согласия — ${e.reason}');
      return null;
    } catch (e) {
      AppLogger.debug('Microsoft Graph: токен не получен — $e');
      return null;
    }
  }
}

// lib/services/mail/graph/graph_client.dart
// Microsoft Graph для ящиков Exchange Online (1.8.10, замечание владельца
// 29.10.2026). Microsoft выключает EWS в Exchange Online: с 1 октября 2026 —
// по организациям, окончательно — в апреле 2027. Почта, календарь, контакты
// и автоответ у ящика Exchange Online идут по ActiveSync (его это не
// касается); то, что шло по EWS — подсказки MailTips, фото и карточки
// коллег, переговорные, состав рассылок, правила сервера, «Восстановить
// удалённые», — теперь сначала через Graph (graph_directory.dart,
// graph_server_tools.dart), а EWS — запасной путь, пока он открыт.
//
// Токен. У токена Microsoft один ресурс: токен ActiveSync (outlook.office365.com)
// к Graph не подходит. Согласие на права Graph просится при входе
// (DirectOAuth.graphConsentScopes), а токен Graph выдаёт тот же refresh-токен
// отдельным запросом (scope https://graph.microsoft.com/.default — все
// права, на которые есть согласие, в том числе выданные администратором).
// Хранится отдельно (gat_/gexp_ в защищённом хранилище).
//
// Нет согласия (вход до 1.8.10 или организация не разрешила) — Graph для
// ящика «недоступен» на 12 часов: функции идут по EWS, как раньше; в
// настройках ящика — «Войти снова», чтобы дать согласие. Отказ Graph никогда
// не помечает сам ящик как «требуется вход»: ActiveSync работает и без него.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_exceptions.dart' show OAuthRefreshFailure;
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../oauth/direct_oauth.dart';

final graphClientProvider = Provider<GraphClient>(
    (ref) => GraphClient(ref.watch(secureStorageProvider), ref.watch(sharedPrefsProvider)));

/// Ответ Graph с ошибкой. [status] 0 — Graph для ящика недоступен (нет
/// согласия или токена), запрос не отправлялся.
class GraphException implements Exception {
  final int status;
  final String code;
  final String message;
  const GraphException(this.status, this.code, [this.message = '']);

  /// Нет прав (не выдано согласие на нужное право или администратор его не
  /// разрешил) — функцию стоит взять из EWS.
  bool get forbidden => status == 403 || status == 0;
  bool get notFound => status == 404;

  @override
  String toString() => 'Graph $status $code${message.isEmpty ? '' : ': $message'}';
}

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

class GraphClient {
  final SecureStorageService _storage;
  final SharedPreferences _prefs;
  final http.Client? _httpOverride;

  GraphClient(this._storage, this._prefs, {http.Client? httpClient}) : _httpOverride = httpClient;

  static const base = 'https://graph.microsoft.com/v1.0';

  /// Пауза после отказа в согласии: столько Graph для ящика не пробуется.
  static const noConsentPause = Duration(hours: 12);

  final Map<String, Future<String?>> _inflight = {};

  static String _stateKey(String accountId) => 'graph_state_$accountId';

  /// Graph есть только у ящиков Exchange Online (вход Microsoft по OAuth).
  bool supports(AccountModel a) => a.isExchangeOnlineOAuth;

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
    final marker = await _storage.getOAuthClient(a.id);
    final client = marker == null ? null : DirectOAuth.graphClient(marker);
    final rt = await _storage.getRefreshToken(a.id);
    if (client == null || rt == null || rt.isEmpty) return null;
    try {
      final res = await DirectOAuth.refresh(client, rt);
      await _storage.write('gat_${a.id}', res.accessToken);
      await _storage.write('gexp_${a.id}', res.expiry.toIso8601String());
      // Microsoft может прислать новый refresh-токен — он же и у ActiveSync.
      final next = res.refreshToken;
      if (next != null && next.isNotEmpty && next != rt) await _storage.write('rt_${a.id}', next);
      if (_prefs.getString(_stateKey(a.id)) != 'ok') {
        await _prefs.setString(_stateKey(a.id), 'ok');
        AppLogger.info('Microsoft Graph для ${AppLogger.mask(a.email)}: токен получен');
      }
      return res.accessToken;
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

  // ── запросы ──

  Future<Object?> get(AccountModel a, String path, {Map<String, String>? query, Map<String, String>? headers}) async {
    final r = await _send(a, 'GET', path, query: query, headers: headers);
    return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Двоичный ответ (фото). null — нет (404).
  Future<Uint8List?> getBytes(AccountModel a, String path) async {
    try {
      final r = await _send(a, 'GET', path);
      return r.bodyBytes.isEmpty ? null : r.bodyBytes;
    } on GraphException catch (e) {
      if (e.notFound) return null;
      rethrow;
    }
  }

  Future<Object?> post(AccountModel a, String path, Object body) async {
    final r = await _send(a, 'POST', path, body: body);
    return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<Object?> patch(AccountModel a, String path, Object body) async {
    final r = await _send(a, 'PATCH', path, body: body);
    return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<void> delete(AccountModel a, String path) async {
    await _send(a, 'DELETE', path);
  }

  /// Все страницы списка (@odata.nextLink), не больше [maxPages].
  Future<List<Map<String, dynamic>>> list(AccountModel a, String path,
      {Map<String, String>? query, int maxPages = 5, Map<String, String>? headers}) async {
    final out = <Map<String, dynamic>>[];
    var r = await get(a, path, query: query, headers: headers);
    for (var page = 0; page < maxPages; page++) {
      if (r is! Map) break;
      final v = r['value'];
      if (v is List) out.addAll(v.whereType<Map<String, dynamic>>());
      final next = r['@odata.nextLink'];
      if (next is! String || !next.startsWith(base)) break;
      r = await get(a, next.substring(base.length), headers: headers);
    }
    return out;
  }

  Future<http.Response> _send(AccountModel a, String method, String path,
      {Map<String, String>? query, Object? body, Map<String, String>? headers}) async {
    var at = await token(a);
    if (at == null) throw const GraphException(0, 'unavailable');
    final uri = Uri.parse('$base$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    Future<http.Response> once(String t) async {
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $t'
        ..headers['Accept'] = 'application/json'
        ..headers.addAll(headers ?? const {});
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final client = _httpOverride ?? http.Client();
      try {
        final s = await client.send(req).timeout(const Duration(seconds: 30));
        return await http.Response.fromStream(s);
      } finally {
        if (_httpOverride == null) client.close();
      }
    }

    var r = await once(at);
    if (r.statusCode == 401) {
      at = await token(a, force: true);
      if (at == null) throw const GraphException(0, 'unavailable');
      r = await once(at);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return r;
    final err = parseError(r.body);
    final e = GraphException(r.statusCode, err.code, err.message);
    AppLogger.debug('Graph $method $path: $e');
    throw e;
  }

  /// Ошибка Graph: {"error": {"code": "...", "message": "..."}}.
  static ({String code, String message}) parseError(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map) {
        final e = m['error'] as Map;
        var msg = '${e['message'] ?? ''}'.trim();
        if (msg.length > 200) msg = '${msg.substring(0, 200)}…';
        return (code: '${e['code'] ?? ''}', message: msg);
      }
    } catch (_) {}
    return (code: '', message: '');
  }

  /// Адрес в пути запроса (/users/{адрес}).
  static String userPath(String email) => '/users/${Uri.encodeComponent(email.trim().toLowerCase())}';
}

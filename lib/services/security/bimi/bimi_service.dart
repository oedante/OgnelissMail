// lib/services/security/bimi/bimi_service.dart
// Логотипы отправителей BIMI (1.9.x, просьба владельца 31.10.2026): запрос
// к серверу Ogneliss (server/oauth-proxy, GET /bimi?d=<домен>) и кэш на
// диске. DNS читает сервер, а не телефон и не публичный DoH: домены
// отправителей не уходят третьим лицам (решено с владельцем 31.10.2026). На
// сервер уходит только домен — без адресов, писем и заголовков.
//
// Список писем не ждёт логотипов: запросы идут в фоне, не больше двух сразу
// и не больше 20 в минуту; до ответа видна буква.

import '../managed_config.dart' show ManagedPolicy;
import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../features/settings/providers/settings_provider.dart';
import 'bimi_rules.dart';

/// Где лежит кэш: файл в каталоге приложения, в тестах — память.
abstract class BimiCacheStore {
  Future<String?> read();
  Future<void> write(String data);
}

class BimiFileStore implements BimiCacheStore {
  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/bimi_cache.json');

  @override
  Future<String?> read() async {
    try {
      final f = await _file();
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}

class _BimiEntry {
  final int until;
  final String? svg;
  final bool disk;
  const _BimiEntry(this.until, this.svg, {this.disk = true});
}

/// Кэш по доменам: логотип — 7 дней, «логотипа нет» — 1 день, сбой сети или
/// сервера — 30 минут (только в памяти). Не схема базы: файл JSON.
class BimiCache {
  static const positiveTtl = Duration(days: 7);
  static const negativeTtl = Duration(days: 1);
  static const transientTtl = Duration(minutes: 30);
  static const maxEntries = 300;

  BimiCache(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final BimiCacheStore _store;
  final DateTime Function() _now;
  // Порядок вставки — для вытеснения самых старых записей.
  final _map = <String, _BimiEntry>{};
  Future<void>? _loading;
  Timer? _saveTimer;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      final now = _now().millisecondsSinceEpoch;
      for (final e in m.entries) {
        final v = e.value;
        if (v is! Map || v['u'] is! int || (v['u'] as int) <= now) continue;
        final svg = v['s'];
        // Файл мог быть изменён снаружи — логотип проверяется заново.
        if (svg is String && !BimiSvgFilter.isSafe(svg)) continue;
        _map.putIfAbsent(e.key as String, () => _BimiEntry(v['u'] as int, svg is String ? svg : null));
      }
    } catch (e) {
      AppLogger.debug('BIMI: кэш не прочитан: $e');
    }
  }

  /// hit — домен в кэше и срок не вышел; svg — логотип или null («нет»).
  ({bool hit, String? svg}) lookup(String domain) {
    final e = _map[domain];
    if (e == null) return (hit: false, svg: null);
    if (e.until <= _now().millisecondsSinceEpoch) {
      _map.remove(domain);
      return (hit: false, svg: null);
    }
    return (hit: true, svg: e.svg);
  }

  void put(String domain, String? svg, {bool transient = false}) {
    final ttl = transient ? transientTtl : (svg != null ? positiveTtl : negativeTtl);
    _map.remove(domain);
    _map[domain] = _BimiEntry(_now().add(ttl).millisecondsSinceEpoch, svg, disk: !transient);
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
    if (!transient) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(flush()));
    }
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final out = <String, Object?>{
      for (final e in _map.entries)
        if (e.value.disk) e.key: {'u': e.value.until, if (e.value.svg != null) 's': e.value.svg},
    };
    try {
      await _store.write(jsonEncode(out));
    } catch (e) {
      AppLogger.debug('BIMI: кэш не записан: $e');
    }
  }
}

/// Запросы к серверу: по одному на домен, не больше [maxConcurrent] сразу и
/// [maxPerMinute] в минуту.
/// Счётчики логотипов за запуск — для пакета диагностики (1.10.1: «непонятно,
/// работает ли BIMI»). Домены не хранятся и не пишутся — только их число.
abstract final class BimiStats {
  /// Сколько разных доменов отправителей с «dmarc=pass» от сервера
  /// пользователя появилось в ленте (только у них логотип возможен).
  static final Set<int> _eligible = {};
  static int requests = 0;
  static int logos = 0;
  static int empty = 0;
  static int errors = 0;
  static int cached = 0;
  static int? stoppedStatus;

  static void eligible(String domain) {
    if (_eligible.length < 10000) _eligible.add(domain.hashCode);
  }

  static int get eligibleDomains => _eligible.length;

  static String summary() {
    final b = StringBuffer('доменов с подписью DMARC в ленте $eligibleDomains; '
        'запросов к серверу $requests: с логотипом $logos, без логотипа $empty, ошибок $errors; '
        'из кэша $cached');
    if (stoppedStatus != null) {
      b.write('; сервер ответил HTTP $stoppedStatus — логотипы выключены до перезапуска');
    }
    return b.toString();
  }
}

class BimiResolver {
  BimiResolver({
    required String baseUrl,
    required this.apiKey,
    required this.cache,
    http.Client? client,
    this.maxConcurrent = 2,
    this.maxPerMinute = 20,
    DateTime Function()? now,
  })  : _base = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  /// Сервер задан при сборке (OAUTH_PROXY_URL и OAUTH_PROXY_KEY): без него
  /// функции нет, переключатель в настройках не показывается.
  static bool get configured =>
      AppConstants.oauthProxyBaseUrl.trim().isNotEmpty && AppConstants.oauthProxyApiKey.isNotEmpty;

  final String _base;
  final String apiKey;
  final BimiCache cache;
  final http.Client _client;
  final int maxConcurrent;
  final int maxPerMinute;
  final DateTime Function() _now;

  final _inflight = <String, Future<String?>>{};
  final _waiters = Queue<Completer<void>>();
  final _starts = Queue<DateTime>();
  int _active = 0;
  // Сервер без /bimi (старая версия) или чужой ключ — до перезапуска не
  // спрашивать: иначе каждое письмо давало бы по запросу.
  bool _stopped = false;

  /// До этого времени сервер не спрашивать (был недоступен).
  DateTime _pauseUntil = DateTime(0);

  /// Логотип домена (очищенный SVG) или null. Не бросает исключений.
  Future<String?> logoFor(String domain) async {
    // Организация запретила внешние службы (MDM block_external_services):
    // логотипы отправителей не запрашиваются.
    if (ManagedPolicy.current.blockExternalServices) return null;
    if (_stopped) return null;
    // Сервер недоступен — 10 минут не спрашивать (08.11.2026: иначе каждое
    // письмо нового отправителя ждало тайм-аута 15 с).
    if (DateTime.now().isBefore(_pauseUntil)) return null;
    await cache.load();
    final c = cache.lookup(domain);
    if (c.hit) {
      BimiStats.cached++;
      return c.svg;
    }
    // Тело в фигурных скобках: remove вернул бы этот же Future, и
    // whenComplete ждал бы сам себя.
    return _inflight[domain] ??= _fetch(domain).whenComplete(() {
      _inflight.remove(domain);
    });
  }

  Future<String?> _fetch(String domain) async {
    await _acquire();
    try {
      if (_stopped) return null;
      final uri = Uri.parse('$_base/bimi').replace(queryParameters: {'d': domain});
      BimiStats.requests++;
      final r = await _client
          .get(uri, headers: {'x-api-key': apiKey, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      switch (r.statusCode) {
        case 200:
          final svg = parseResponse(r.body);
          cache.put(domain, svg);
          if (svg != null) {
            BimiStats.logos++;
          } else {
            BimiStats.empty++;
          }
          return svg;
        case 400:
          BimiStats.empty++;
          cache.put(domain, null);
          return null;
        case 401:
        case 404:
          _stopped = true;
          BimiStats.stoppedStatus = r.statusCode;
          AppLogger.info('BIMI: сервер не отвечает на /bimi (HTTP ${r.statusCode}) — логотипы до перезапуска выключены');
          return null;
        default:
          BimiStats.errors++;
          cache.put(domain, null, transient: true);
          return null;
      }
    } catch (e) {
      BimiStats.errors++;
      _pauseUntil = DateTime.now().add(const Duration(minutes: 10));
      AppLogger.info('BIMI: сервер не отвечает ($e) — логотипы 10 минут не запрашиваются');
      return null;
    } finally {
      _release();
    }
  }

  /// Ответ сервера → логотип: только при политике quarantine/reject и если
  /// SVG проходит проверку здесь, на устройстве.
  static String? parseResponse(String body) {
    try {
      final m = jsonDecode(body);
      if (m is! Map) return null;
      final policy = m['policy'];
      final logo = m['logo'];
      if (policy != 'reject' && policy != 'quarantine') return null;
      if (logo is! String || !BimiSvgFilter.isSafe(logo)) return null;
      return logo;
    } catch (_) {
      return null;
    }
  }

  Future<void> _acquire() async {
    while (true) {
      final now = _now();
      while (_starts.isNotEmpty && now.difference(_starts.first) >= const Duration(minutes: 1)) {
        _starts.removeFirst();
      }
      if (_active < maxConcurrent && _starts.length < maxPerMinute) {
        _active++;
        _starts.add(now);
        return;
      }
      if (_active >= maxConcurrent) {
        final c = Completer<void>();
        _waiters.add(c);
        await c.future;
      } else {
        await Future<void>.delayed(const Duration(minutes: 1) - now.difference(_starts.first));
      }
    }
  }

  void _release() {
    _active--;
    if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
  }
}

final bimiResolverProvider = Provider<BimiResolver?>((ref) {
  if (!BimiResolver.configured) return null;
  return BimiResolver(
    baseUrl: AppConstants.oauthProxyBaseUrl,
    apiKey: AppConstants.oauthProxyApiKey,
    cache: BimiCache(BimiFileStore()),
  );
});

/// Логотип домена для портрета; null — показывать букву.
final bimiLogoProvider = FutureProvider.family<String?, String>((ref, domain) async {
  if (!ref.watch(settingsProvider.select((s) => s.bimiLogos))) return null;
  final r = ref.watch(bimiResolverProvider);
  return r?.logoFor(domain);
});

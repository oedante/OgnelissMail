// lib/services/push/push_wake_service.dart
// Сигналы сервера на iPhone (1.7.2, решение владельца 20.10.2026: «сервер
// будем использовать мой, где OAuth и сайт»). Зачем — docs/plan/
// IOS_BACKGROUND_DELIVERY.md, что сделать владельцу — docs/guides/
// IOS_PUSH_SETUP.md, сервер — server/push-relay.
//
// Как работает:
//  · приложение просит у iOS токен уведомлений (канал 'ogneliss/push',
//    AppDelegate.swift) и отдаёт его «будильнику» на сервере вместе с
//    окружением (production / sandbox), интервалом и режимом;
//  · сервер раз в интервал присылает через Apple пустой сигнал; iOS будит
//    приложение, и оно проверяет почту так же, как по фоновому обновлению
//    ([BackgroundService.runForPushWake]);
//  · на сервер уходят только токен, окружение, интервал и режим — ни
//    адресов, ни паролей, ни писем.
//
// Этап 1 — тихие сигналы (iOS пропускает 2–3 в час, сервер шлёт не чаще раза
// в 20 минут). Этап 2 — обычные сигналы и расширение уведомлений, после
// одобрения права Apple на фильтрацию (AppConstants.pushWakeMode = alert).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../background/background_journal.dart';
import '../background/background_service.dart' show backgroundServiceProvider;

/// Настройки: включено и интервал (минуты: 15, 30, 60).
class PushWakePrefs {
  final bool enabled;
  final int interval;
  const PushWakePrefs({this.enabled = true, this.interval = 15});
}

final pushWakePrefsProvider = NotifierProvider<PushWakePrefsNotifier, PushWakePrefs>(PushWakePrefsNotifier.new);

class PushWakePrefsNotifier extends Notifier<PushWakePrefs> {
  static const _kEnabled = 'push_wake_enabled';
  static const _kInterval = 'push_wake_interval';
  static const intervals = [15, 30, 60];

  @override
  PushWakePrefs build() {
    try {
      final p = ref.read(sharedPrefsProvider);
      final i = p.getInt(_kInterval) ?? 15;
      return PushWakePrefs(enabled: p.getBool(_kEnabled) ?? true, interval: intervals.contains(i) ? i : 15);
    } catch (_) {
      return const PushWakePrefs();
    }
  }

  Future<void> setEnabled(bool v) async {
    state = PushWakePrefs(enabled: v, interval: state.interval);
    await ref.read(sharedPrefsProvider).setBool(_kEnabled, v);
    unawaited(ref.read(pushWakeServiceProvider).apply());
  }

  Future<void> setInterval(int v) async {
    if (!intervals.contains(v)) return;
    state = PushWakePrefs(enabled: state.enabled, interval: v);
    await ref.read(sharedPrefsProvider).setInt(_kInterval, v);
    unawaited(ref.read(pushWakeServiceProvider).apply());
  }
}

final pushWakeServiceProvider = Provider<PushWakeService>((ref) => PushWakeService(ref));

/// Что видно на экране настроек и в диагностике.
class PushWakeState {
  final bool registered;
  final String? env;
  final DateTime? registeredAt;
  final DateTime? lastWake;
  final String? lastError;
  const PushWakeState({this.registered = false, this.env, this.registeredAt, this.lastWake, this.lastError});
}

class PushWakeService {
  static const _channel = MethodChannel('ogneliss/push');
  static const _kToken = 'push_wake_token';
  static const _kSent = 'push_wake_sent'; // «токен|окружение|интервал|режим»
  static const _kSentAt = 'push_wake_sent_at';
  static const _kLastWake = 'push_wake_last';
  static const _kLastError = 'push_wake_error';

  /// Повторная регистрация раз в сутки (при запуске приложения): сервер
  /// забывает токены, которые месяц не обновлялись (приложение удалили —
  /// Apple сообщит не сразу), и токены, которые Apple отклонила; сутки — чтобы
  /// после такого сбоя сигналы вернулись сами, без выключения и включения.
  static const _refreshEvery = Duration(days: 1);

  final Ref _ref;
  bool _inited = false;
  PushWakeService(this._ref);

  static bool get supported => !kIsWeb && Platform.isIOS && AppConstants.pushRelayUrl.trim().isNotEmpty;

  String get _base => AppConstants.pushRelayUrl.trim().replaceAll(RegExp(r'/+$'), '');

  SharedPreferences get _prefs => _ref.read(sharedPrefsProvider);

  Future<void> init() async {
    if (!supported || _inited) return;
    _inited = true;
    _channel.setMethodCallHandler(_onCall);
    await apply();
  }

  /// Применить настройки: включено — попросить токен у iOS (он придёт в
  /// onToken, там и регистрация на сервере); выключено — снять с сервера.
  Future<void> apply() async {
    if (!supported) return;
    final prefs = _ref.read(pushWakePrefsProvider);
    try {
      if (prefs.enabled) {
        await _channel.invokeMethod<void>('register');
      } else {
        await _unregister();
      }
    } catch (e) {
      AppLogger.warning('Сигналы сервера: $e');
    }
  }

  PushWakeState state() {
    final p = _prefs;
    final sent = p.getString(_kSent);
    final at = p.getInt(_kSentAt);
    final wake = p.getInt(_kLastWake);
    return PushWakeState(
      registered: sent != null,
      env: sent?.split('|').elementAtOrNull(1),
      registeredAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      lastWake: wake == null ? null : DateTime.fromMillisecondsSinceEpoch(wake),
      lastError: p.getString(_kLastError),
    );
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'onToken':
        if (args is Map) await _onToken('${args['token'] ?? ''}', '${args['env'] ?? 'production'}');
        return null;
      case 'onError':
        // Чаще всего — у цели Runner в Xcode не включены Push Notifications
        // (docs/guides/IOS_PUSH_SETUP.md, п. 2.1).
        AppLogger.warning('Сигналы сервера: iOS не выдала токен — $args');
        await _prefs.setString(_kLastError, 'iOS: $args');
        return null;
      case 'onWake':
        final ms = args is Map && args['deadlineMs'] is int ? args['deadlineMs'] as int : 25000;
        return _onWake(Duration(milliseconds: ms));
    }
    throw MissingPluginException(call.method);
  }

  Future<void> _onToken(String token, String env) async {
    if (!RegExp(r'^[0-9a-f]{64,200}$').hasMatch(token)) return;
    // Только в отладочной сборке (из Xcode): токен — для пробного сигнала из
    // Push Notifications Console (docs/guides/IOS_PUSH_SETUP.md, п. 5). В
    // выпускаемых сборках токен в журнал не пишется.
    if (kDebugMode) AppLogger.info('Сигналы сервера (отладка): токен $token, окружение $env');
    final prefs = _ref.read(pushWakePrefsProvider);
    if (!prefs.enabled) return;
    const mode = AppConstants.pushWakeMode == 'alert' ? 'alert' : 'silent';
    final key = '$token|$env|${prefs.interval}|$mode';
    final p = _prefs;
    final old = p.getString(_kSent);
    final at = p.getInt(_kSentAt) ?? 0;
    final fresh = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < _refreshEvery;
    if (old == key && fresh) return;
    // Токен сменился (переустановка, восстановление из копии) — прежний
    // снять, чтобы сервер не будил его зря.
    final oldToken = p.getString(_kToken);
    if (oldToken != null && oldToken != token) {
      await _post('/unregister', {'token': oldToken});
    }
    final ok = await _post('/register', {
      'token': token,
      'env': env,
      'interval': prefs.interval,
      'mode': mode,
    });
    if (ok) {
      await p.setString(_kToken, token);
      await p.setString(_kSent, key);
      await p.setInt(_kSentAt, DateTime.now().millisecondsSinceEpoch);
      await p.remove(_kLastError);
      AppLogger.info('Сигналы сервера: регистрация — $env, раз в ${prefs.interval} мин, режим $mode');
    }
  }

  Future<void> _unregister() async {
    final p = _prefs;
    final token = p.getString(_kToken);
    if (token != null) await _post('/unregister', {'token': token});
    try {
      await _channel.invokeMethod<void>('unregister');
    } catch (_) {}
    await p.remove(_kToken);
    await p.remove(_kSent);
    await p.remove(_kSentAt);
    await p.remove(_kLastError);
  }

  Future<bool> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_base$path'),
            headers: {
              'content-type': 'application/json',
              if (AppConstants.oauthProxyApiKey.isNotEmpty) 'x-api-key': AppConstants.oauthProxyApiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode >= 200 && r.statusCode < 300) return true;
      final err = 'сервер ${path.substring(1)} → HTTP ${r.statusCode}';
      AppLogger.warning('Сигналы сервера: $err');
      await _prefs.setString(_kLastError, err);
    } catch (e) {
      AppLogger.warning('Сигналы сервера: ${path.substring(1)} — $e');
      await _prefs.setString(_kLastError, '${path.substring(1)}: ${e.runtimeType}');
    }
    return false;
  }

  /// Сигнал пришёл: проверить почту тёплым движком приложения. Ответ iOS —
  /// появились ли новые письма (newData / noData / failed).
  Future<String> _onWake(Duration deadline) async {
    final limit = deadline - const Duration(milliseconds: 1500);
    final safe = limit < const Duration(seconds: 5) ? const Duration(seconds: 5) : limit;
    await _prefs.setInt(_kLastWake, DateTime.now().millisecondsSinceEpoch);
    try {
      final before = await _maxRowId();
      await BackgroundJournal.track('сигнал iOS', () => _ref.read(backgroundServiceProvider).runForPushWake(safe),
          withState: false, describe: (what) => what);
      final after = await _maxRowId();
      AppLogger.flushNow();
      return after > before ? 'newData' : 'noData';
    } catch (e) {
      AppLogger.warning('Сигнал iOS: $e');
      AppLogger.flushNow();
      return 'failed';
    }
  }

  Future<int> _maxRowId() async {
    try {
      final row = await _ref.read(databaseProvider).customSelect('SELECT MAX(rowid) AS m FROM emails').getSingle();
      return (row.data['m'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

// lib/core/platform/finish_in_background.dart
// iPhone: доделать начатое после сворачивания (1.6.44).
//
// iOS замораживает свёрнутое приложение почти сразу. Если в этот момент
// шла синхронизация или отправка письма, запрос «висел» до следующего
// открытия: по журналам iPhone 18.10.2026 — «Синхронизация идёт 98 мин —
// считаю зависшей», «не завершилась за 20 мин — ящик освобождён», а при
// открытии приложение ещё ждало прежний проход. Письмо, отправленное за
// секунду до блокировки экрана, уходило только при следующем открытии.
//
// UIApplication.beginBackgroundTask даёт приложению ~30 секунд, чтобы
// закончить начатое. Просим их, только если работа идёт, и отдаём сразу,
// как она закончилась (или через 25 с — с запасом до лимита iOS).
//
// Android (2.7.5): то же — срочной задачей WorkManager (FinishWorkKeeper.kt),
// до 3 минут: Android 12+ замораживает свёрнутое приложение за секунды.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

class FinishInBackground {
  FinishInBackground._();

  static const _channel = MethodChannel('ogneliss/platform');

  static int _busy = 0;
  static final List<Completer<void>> _idleWaiters = [];

  /// Идёт работа, которую жалко оборвать (синхронизация, отправка).
  static bool get busy => _busy > 0;

  /// Выполнить [job], отметив его как «доделать после сворачивания».
  static Future<T> guard<T>(Future<T> Function() job) async {
    _busy++;
    try {
      return await job();
    } finally {
      _busy--;
      if (_busy <= 0) {
        _busy = 0;
        final waiters = List<Completer<void>>.of(_idleWaiters);
        _idleWaiters.clear();
        for (final c in waiters) {
          if (!c.isCompleted) c.complete();
        }
      }
    }
  }

  static Future<void> _whenIdle(Duration timeout) async {
    if (!busy) return;
    final c = Completer<void>();
    _idleWaiters.add(c);
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      _idleWaiters.remove(c);
    }
  }

  static bool _running = false;

  static const _android = MethodChannel('ogneliss/finish_work');

  /// Приложение свернули: попросить у системы время, если работа идёт.
  static Future<void> onPaused() async {
    if (kIsWeb || _running || !busy) return;
    if (Platform.isAndroid) return _onPausedAndroid();
    if (!Platform.isIOS) return;
    _running = true;
    int? task;
    try {
      task = await _channel.invokeMethod<int>('beginBackgroundTask');
      if (task == null || task < 0) return;
      final started = DateTime.now();
      AppLogger.info('Свёрнуто посреди синхронизации или отправки — iOS дала время доделать');
      await _whenIdle(const Duration(seconds: 25));
      final s = DateTime.now().difference(started).inSeconds;
      AppLogger.info(busy
          ? 'Свёрнуто: за $s с не закончилось — остальное при следующем пробуждении'
          : 'Свёрнуто: начатое закончено за $s с');
    } catch (e) {
      AppLogger.debug('Доделать в фоне (iOS): $e');
    } finally {
      // Строки журнала — на диск: дальше iOS заморозит процесс.
      AppLogger.flushNow();
      if (task != null && task >= 0) {
        try {
          await _channel.invokeMethod<void>('endBackgroundTask', task);
        } catch (_) {}
      }
      _running = false;
    }
  }

  /// Android (2.7.5, журнал пользователя 27.11.2026: письмо начало уходить,
  /// приложение свернули через 3 с — и Android его заморозил, отправка
  /// встала до следующего открытия). Срочная задача WorkManager ждёт, пока
  /// работа идёт (до 3 минут): процесс с идущей задачей не замораживается.
  static Future<void> _onPausedAndroid() async {
    _running = true;
    final started = DateTime.now();
    try {
      final ok = await _android.invokeMethod<bool>('begin');
      if (ok != true) return;
      AppLogger.info('Свёрнуто посреди синхронизации или отправки — Android: задача «доделать» поставлена');
      await _whenIdle(const Duration(minutes: 3));
      final s = DateTime.now().difference(started).inSeconds;
      AppLogger.info(busy
          ? 'Свёрнуто: за $s с не закончилось — остальное при следующем пробуждении'
          : 'Свёрнуто: начатое закончено за $s с');
    } catch (e) {
      AppLogger.debug('Доделать в фоне (Android): $e');
    } finally {
      try {
        await _android.invokeMethod<void>('end');
      } catch (_) {}
      AppLogger.flushNow();
      _running = false;
    }
  }

  /// Для тестов: сколько работ идёт.
  @visibleForTesting
  static int get busyCount => _busy;
}

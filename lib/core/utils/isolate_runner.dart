// lib/core/utils/isolate_runner.dart
// Утилита запуска тяжёлых операций в Isolate + RequestDeduplicator.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../logging/app_logger.dart';

/// Запуск compute() с таймаутом и логированием
class IsolateRunner {
  IsolateRunner._();

  static Future<R> run<A, R>(
    FutureOr<R> Function(A) function,
    A argument, {
    Duration timeout = const Duration(seconds: 30),
    String? debugLabel,
  }) async {
    final label = debugLabel ?? 'isolate';
    try {
      return await compute(function, argument).timeout(timeout);
    } on TimeoutException {
      AppLogger.error('Isolate[$label]: timeout');
      rethrow;
    } catch (e) {
      AppLogger.error('Isolate[$label]: error', e);
      rethrow;
    }
  }
}

/// Предотвращает дублирование одновременных запросов
class RequestDeduplicator {
  final Map<String, Future<dynamic>> _pending = {};

  Future<T> deduplicate<T>(String key, Future<T> Function() operation) async {
    if (_pending.containsKey(key)) return await _pending[key] as T;

    final future = operation();
    _pending[key] = future;

    try {
      return await future;
    } finally {
      unawaited(_pending.remove(key));
    }
  }

  bool isRunning(String key) => _pending.containsKey(key);
  void clear() => _pending.clear();
}

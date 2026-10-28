// lib/core/utils/async_guard.dart
// SafeAsyncState — миксин для безопасной асинхронности в виджетах.
// Предотвращает setState после dispose, утечки подписок, дубли запросов.

import 'dart:async';
import 'package:flutter/material.dart';

/// Миксин для State — безопасные async-операции
mixin SafeAsyncState<T extends StatefulWidget> on State<T> {
  final List<StreamSubscription> _subs = [];
  Timer? _debounceTimer;

  /// Безопасный setState
  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// Безопасный async — возвращает null если disposed
  Future<R?> safeAsync<R>(Future<R> Function() op) async {
    try {
      final result = await op();
      if (!mounted) return null;
      return result;
    } catch (e) {
      if (!mounted) return null;
      rethrow;
    }
  }

  /// Подписка с автоотменой
  void addSubscription(StreamSubscription sub) => _subs.add(sub);

  /// Debounce
  void debounce(Duration duration, VoidCallback callback) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, () {
      if (mounted) callback();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _subs.clear();
    _debounceTimer?.cancel();
    super.dispose();
  }
}

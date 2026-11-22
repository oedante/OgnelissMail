// lib/core/logging/open_trace.dart
// Замер открытия письма (1.5.9): от нажатия на строку ленты до показа
// текста — одной строкой в журнал диагностики на каждое открытие, без
// отладчика и profile-сборки. Пример строки:
//   «Открытие письма, мс от нажатия: окно 212 · создано 268 · кадр 331 ·
//    загрузка 342 · текст 371»
// Отметки, пришедшие без нажатия (письмо из уведомления, беседы), не пишутся.
//
// 2.6.8: замер — и метка производительности «открытие письма» (PerfMark):
// в Timeline (DevTools) — участок с этапами, в журнале медленных кадров —
// «шло: открытие письма».

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_logger.dart';
import 'perf_mark.dart';

class OpenTrace {
  OpenTrace._();

  static final Stopwatch _sw = Stopwatch();
  static final List<String> _marks = [];
  static int? _span;

  /// Отметки последнего законченного замера: этап → мс от нажатия (первая
  /// отметка этапа). Для замера скорости на эмуляторе
  /// (integration_test/perf_test.dart; 1.9.x, просьба владельца 31.10.2026):
  /// по этапам видно, что именно замедлилось. Приложение их не читает.
  @visibleForTesting
  static Map<String, int> lastMarks = const {};

  /// Нажатие на письмо в ленте.
  static void start() {
    _marks.clear();
    _endSpan();
    _span = PerfMark.begin('открытие письма', limit: const Duration(seconds: 30));
    _sw
      ..reset()
      ..start();
  }

  static void _endSpan() {
    final id = _span;
    _span = null;
    if (id != null) PerfMark.end(id);
  }

  /// Промежуточная отметка (только во время замера).
  static void mark(String what) {
    if (!_sw.isRunning) return;
    _marks.add('$what ${_sw.elapsedMilliseconds}');
    PerfMark.instant('открытие письма: $what');
  }

  /// Текст письма показан — итог в журнал.
  static void done() {
    if (!_sw.isRunning) return;
    _sw.stop();
    _endSpan();
    _marks.add('текст ${_sw.elapsedMilliseconds}');
    AppLogger.info('Открытие письма, мс от нажатия: ${_marks.join(' · ')}');
    final last = <String, int>{};
    for (final m in _marks) {
      final i = m.lastIndexOf(' ');
      final ms = int.tryParse(m.substring(i + 1));
      if (i > 0 && ms != null) last.putIfAbsent(m.substring(0, i), () => ms);
    }
    lastMarks = last;
    _marks.clear();
  }

  /// Мс от нажатия; -1 — замер не идёт.
  static int get elapsedMs => _sw.isRunning ? _sw.elapsedMilliseconds : -1;

  /// Замер больше не нужен (письмо без WebView, ушли с экрана).
  static void cancel() {
    _sw.stop();
    _endSpan();
    _marks.clear();
  }
}

// lib/core/logging/jank_monitor.dart
// Медленные кадры — в журнал (2.6.0, замечание владельца 15.11.2026:
// «после запуска тормоза, потом пропадают»). Раньше подтормаживания в
// журнале не было видно совсем; теперь по журналу видно, когда интерфейс
// замирал и что в это время происходило (строки рядом).
//
// Кадр дольше [_slow] — отдельной строкой (не больше [_perMinute] строк в
// минуту, чтобы не засорять журнал), раз в минуту — сводка, если были
// подтормаживания.

import 'package:flutter/scheduler.dart';

import 'app_logger.dart';

class JankMonitor {
  JankMonitor._();

  static const _slow = Duration(milliseconds: 250);
  static const _janky = Duration(milliseconds: 34); // два кадра при 60 Гц
  static const _perMinute = 5;

  static bool _started = false;
  static DateTime _windowStart = DateTime.now();
  static int _jankyFrames = 0;
  static int _frames = 0;
  static int _worstMs = 0;
  static int _logged = 0;

  /// Подписаться на время кадров (после первого кадра, main.dart).
  static void start() {
    if (_started) return;
    _started = true;
    _windowStart = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final t in timings) {
      _frames++;
      final total = t.totalSpan;
      if (total < _janky) continue;
      _jankyFrames++;
      final ms = total.inMilliseconds;
      if (ms > _worstMs) _worstMs = ms;
      if (total >= _slow && _logged < _perMinute) {
        _logged++;
        AppLogger.info('Медленный кадр: $ms мс (сборка ${t.buildDuration.inMilliseconds}, '
            'отрисовка ${t.rasterDuration.inMilliseconds})');
      }
    }
    if (now.difference(_windowStart) >= const Duration(minutes: 1)) {
      if (_jankyFrames > 0) {
        AppLogger.info('Кадры за минуту: $_frames, с задержкой $_jankyFrames, худший $_worstMs мс');
      }
      _windowStart = now;
      _frames = 0;
      _jankyFrames = 0;
      _worstMs = 0;
      _logged = 0;
    }
  }
}

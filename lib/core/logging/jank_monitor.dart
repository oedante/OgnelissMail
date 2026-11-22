// lib/core/logging/jank_monitor.dart
// Медленные кадры — в журнал (2.6.0, замечание владельца 15.11.2026:
// «после запуска тормоза, потом пропадают»). Раньше подтормаживания в
// журнале не было видно совсем; теперь по журналу видно, когда интерфейс
// замирал и что в это время происходило (строки рядом).
//
// Кадр дольше [_slow] — отдельной строкой (не больше [_perMinute] строк в
// минуту, чтобы не засорять журнал), раз в минуту — сводка, если были
// подтормаживания.
//
// 2.6.8 (журнал владельца 21.11.2026): «Медленный кадр: 2141 мс (сборка 1,
// отрисовка 9)» — кадр, прерванный сворачиванием приложения, считался
// подтормаживанием; кадры на смене состояния приложения (свернуть,
// развернуть) больше не считаются. И у медленного кадра — где он ждал:
// «ожидание» — главный поток был занят до начала кадра (синхронизация,
// разбор ответа сервера), «очередь отрисовки» — поток отрисовки занят
// прежним кадром или встроенным окном.
//
// 2.6.8 (22.11.2026): и что в это время шло — по меткам производительности
// (PerfMark): «главный поток: письмо: разбор HTML 420 мс; шло:
// синхронизация: папка Входящие».

import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;

import 'app_logger.dart';
import 'perf_mark.dart';

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

  /// Последняя смена состояния приложения (свёрнуто, развёрнуто).
  static DateTime? _lifecycleAt;
  // ignore: unused_field
  static AppLifecycleListener? _lifecycle;

  /// Подписаться на время кадров (после первого кадра, main.dart).
  static void start() {
    if (_started) return;
    _started = true;
    _windowStart = DateTime.now();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _lifecycleAt = DateTime.now());
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    final resumed = SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final changed = _lifecycleAt;
    for (final t in timings) {
      final total = t.totalSpan;
      // Кадр на смене состояния приложения — не подтормаживание.
      if (!resumed || (changed != null && now.difference(changed) < total + const Duration(seconds: 1))) continue;
      _frames++;
      if (total < _janky) continue;
      _jankyFrames++;
      final ms = total.inMilliseconds;
      if (ms > _worstMs) _worstMs = ms;
      if (total >= _slow && _logged < _perMinute) {
        _logged++;
        final w = windowOf(t, Timeline.now);
        final busy = PerfMark.describe(PerfMark.during(w.from, w.to));
        AppLogger.info('Медленный кадр: $ms мс (${phasesOf(t)})${busy.isEmpty ? '' : ' — $busy'}');
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

  /// Отрезок (часы Timeline, мкс), в котором искать участки для
  /// медленного кадра [t]: от чуть раньше начала кадра (главный поток мог
  /// быть занят ещё до сигнала кадра) до конца отрисовки. Часы кадра — те
  /// же, что у Timeline ([nowUs] — сейчас по ним); если нет (кадр «в
  /// будущем» или давнее 10 с) — последние полторы секунды перед отчётом
  /// (отчёт о кадрах приходит с задержкой до секунды).
  @visibleForTesting
  static ({int from, int to}) windowOf(FrameTiming t, int nowUs) {
    final start = t.timestampInMicroseconds(FramePhase.vsyncStart);
    final end = t.timestampInMicroseconds(FramePhase.rasterFinish);
    if (end > nowUs + 1000000 || nowUs - end > 10000000) {
      return (from: nowUs - t.totalSpan.inMicroseconds - 1500000, to: nowUs);
    }
    return (from: start - 100000, to: end);
  }

  /// Из чего сложилось время кадра: ожидание начала (главный поток занят),
  /// сборка, очередь отрисовки, отрисовка — в мс.
  static String phasesOf(FrameTiming t) {
    int ms(FramePhase a, FramePhase b) =>
        ((t.timestampInMicroseconds(b) - t.timestampInMicroseconds(a)) / 1000).round();
    return 'ожидание ${ms(FramePhase.vsyncStart, FramePhase.buildStart)}, '
        'сборка ${t.buildDuration.inMilliseconds}, '
        'очередь отрисовки ${ms(FramePhase.buildFinish, FramePhase.rasterStart)}, '
        'отрисовка ${t.rasterDuration.inMilliseconds}';
  }
}

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

//
// 2.7.2 (микрофризы 24.11.2026: «Новое сообщение» открылось, но ~1,5 с не
// реагировало на нажатия; в журнале — только «худший 223 мс» за минуту):
// - подробная строка — для кадров от [_detail] (100 мс), не от 250;
// - в строке — открытый экран и сколько он открыт («экран compose, 0,3 с»);
// - сторож главного потока: замирание, когда кадров нет вовсе (интерфейс
//   ничего не рисовал и не отвечал на касания), — «Главный поток занят»;
// - на Android — такой же сторож главного потока системы (встроенные окна
//   браузера, плагины): «Android: главный поток занят» — видно, чья это
//   задержка, приложения или системы.

import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io' show Platform;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, NavigatorObserver, PopupRoute, Route, WidgetsBinding;

import 'app_logger.dart';
import 'perf_mark.dart';

class JankMonitor {
  JankMonitor._();

  static const _detail = Duration(milliseconds: 100);
  static const _janky = Duration(milliseconds: 34); // два кадра при 60 Гц
  static const _perMinute = 5;

  /// Сторож главного потока: шаг и с какого опоздания писать.
  static const _tick = Duration(milliseconds: 250);
  static const _stall = Duration(milliseconds: 300);
  static Timer? _watch;
  static Stopwatch? _clock;
  static int _lastTickMs = 0;
  static int _stallsLogged = 0;
  static int _nativeTicks = 0;
  static const _native = MethodChannel('ogneliss/main_thread');

  /// Открытый экран (имя маршрута) и с какого времени — для строк журнала.
  static String? _screen;
  static DateTime? _screenAt;

  /// Наблюдатель за экранами для навигатора: у каждого навигатора — свой
  /// (общий и вложенный навигатор вкладок).
  static NavigatorObserver observer() => _ScreenObserver();

  static void _onScreen(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name;
    _screen = (name == null || name.isEmpty)
        ? (route is PopupRoute ? 'окно поверх экрана' : null) ?? _screen
        : (name.startsWith('/') ? name.split('/').where((p) => p.isNotEmpty && !p.startsWith(':')).take(2).join('/') : name);
    _screenAt = DateTime.now();
  }

  /// «экран compose, открыт 0,3 с назад» — или '' (экран неизвестен).
  @visibleForTesting
  static String screenNote([DateTime? now]) {
    final s = _screen, at = _screenAt;
    if (s == null || at == null) return '';
    final ms = (now ?? DateTime.now()).difference(at).inMilliseconds;
    final ago = ms < 10000 ? '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} с' : '${(ms / 1000).round()} с';
    return 'экран ${s.isEmpty ? '/' : s}, открыт $ago назад';
  }

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
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _lifecycleAt = DateTime.now();
      if (state == AppLifecycleState.resumed) {
        _startWatch();
      } else {
        _stopWatch();
      }
    });
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
        WidgetsBinding.instance.lifecycleState == null) {
      _startWatch();
    }
  }

  static void _startWatch() {
    if (_watch != null) return;
    final clock = _clock ??= (Stopwatch()..start());
    _lastTickMs = clock.elapsedMilliseconds;
    _watch = Timer.periodic(_tick, (_) => _onTick());
  }

  static void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  static void _onTick() {
    final clock = _clock;
    if (clock == null) return;
    final now = clock.elapsedMilliseconds;
    final late = now - _lastTickMs - _tick.inMilliseconds;
    _lastTickMs = now;
    final changed = _lifecycleAt;
    final settled = changed == null || DateTime.now().difference(changed) > Duration(milliseconds: late + 1000);
    if (late >= _stall.inMilliseconds && settled && _stallsLogged < _perMinute) {
      _stallsLogged++;
      final nowUs = Timeline.now;
      final busy = PerfMark.describe(PerfMark.during(nowUs - (late + 250) * 1000, nowUs));
      final where = screenNote();
      AppLogger.info('Главный поток занят $late мс${where.isEmpty ? '' : ' ($where)'}${busy.isEmpty ? '' : ' — $busy'}');
    }
    // Сторож Android — раз в 5 с: что он насчитал, пока мы не спрашивали.
    if (!kIsWeb && Platform.isAndroid && ++_nativeTicks % 20 == 0) unawaited(_takeNative());
  }

  static Future<void> _takeNative() async {
    try {
      final list = await _native.invokeListMethod<Object?>('take');
      for (final e in list ?? const <Object?>[]) {
        if (e is! List || e.length < 2) continue;
        final at = DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt());
        final ms = (e[1] as num).toInt();
        final t = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
            '${at.second.toString().padLeft(2, '0')}';
        AppLogger.info('Android: главный поток занят $ms мс (в $t)');
      }
    } catch (_) {
      // Старая сборка без сторожа или канал занят — не важно.
    }
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
      if (total >= _detail && _logged < _perMinute) {
        _logged++;
        final w = windowOf(t, Timeline.now);
        final busy = PerfMark.describe(PerfMark.during(w.from, w.to));
        final where = screenNote();
        AppLogger.info('Медленный кадр: $ms мс (${phasesOf(t)}${where.isEmpty ? '' : '; $where'})'
            '${busy.isEmpty ? '' : ' — $busy'}');
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
      _stallsLogged = 0;
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

/// Запоминает открытый экран для строк журнала ([JankMonitor.screenNote]).
class _ScreenObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => JankMonitor._onScreen(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => JankMonitor._onScreen(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => JankMonitor._onScreen(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => JankMonitor._onScreen(previousRoute);
}

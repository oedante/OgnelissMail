// integration_test/support/harness.dart
// Общее для интеграционных тестов на эмуляторе Android (задача «emulator»
// в .github/workflows/ci.yml; 1.9.x, просьба владельца 31.10.2026):
// приложение-обёртка с переводами и масштабом интерфейса (как MailApp),
// ожидания по условию с пределом времени (без пауз «на всякий случай»),
// касание с настоящим временем и строки замеров скорости.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/ui_zoom.dart';

/// Тесты окон браузера — только на Android (эмулятор в CI).
bool get onAndroid => !kIsWeb && Platform.isAndroid;

IntegrationTestWidgetsFlutterBinding ensureBinding() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Все кадры, которые просит фреймворк, — рисуются (окно письма ждёт кадров
  // само — _revealWhenStable, переходы экранов анимируются), и pump тоже
  // рисует кадр: после теста дерево виджетов снимается сразу, без
  // «анимация ещё идёт». Замеры скорости — [withAppFrames].
  b.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  return b;
}

/// Кадры — только по запросу фреймворка, как в приложении; pump лишь ждёт.
/// Для замеров скорости: лишние кадры от ожиданий теста не ложатся на
/// главный поток во время открытия письма или редактора.
Future<T> withAppFrames<T>(Future<T> Function() body) async {
  final b = IntegrationTestWidgetsFlutterBinding.instance;
  final was = b.framePolicy;
  b.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  try {
    return await body();
  } finally {
    b.framePolicy = was;
  }
}

/// Строки интерфейса (языки загружаются асинхронно — до первого кадра).
Future<AppLocalizations> loadStrings([String lang = 'ru']) => AppLocalizations.load(lang);

/// Масштаб интерфейса для окна письма и редактора ([UiZoom.current]) и
/// обёртки [testApp].
void setUiZoom(double zoom) => UiZoom.current = zoom;

/// Размер текста письма, который выбрал бы экран письма при системном
/// шрифте ×1 (MailHtmlView.textScaleOf): масштаб интерфейса текст письма не
/// уменьшает.
double mailTextScaleFor(double zoom) => (((1.0 / zoom).clamp(0.8, 3.0)) * 20).roundToDouble() / 20;

/// Логическая ширина экрана (без масштаба интерфейса).
double screenWidth(WidgetTester tester) => tester.view.physicalSize.width / tester.view.devicePixelRatio;

/// Приложение для теста: тема, переводы и масштаб интерфейса — как в
/// MailApp.builder (UiZoomBox + MediaQuery в единицах масштаба).
Widget testApp({required Widget home, double zoom = 1.0, GlobalKey<NavigatorState>? navigatorKey}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(1.0),
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return UiZoomBox(
        zoom: zoom,
        child: MediaQuery(data: UiZoom.scaleData(mq, zoom), child: child ?? const SizedBox.shrink()),
      );
    },
    home: home,
  );
}

/// Ждать, пока [done] не станет true; дольше [timeout] — тест падает с
/// объяснением [what].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 40),
}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > timeout) {
      throw TestFailure('Не дождались за ${timeout.inMilliseconds} мс: $what');
    }
    await tester.pump(step);
  }
}

/// Дождаться [future] (кадры идут своим чередом).
Future<T> waitFor<T>(
  WidgetTester tester,
  Future<T> future, {
  required String what,
  Duration timeout = const Duration(seconds: 20),
}) async {
  var done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  await pumpUntil(tester, () => done, what: what, timeout: timeout);
  if (error != null) Error.throwWithStackTrace(error!, stack ?? StackTrace.current);
  return value as T;
}

/// Повторять [read], пока [ok] не примет значение; последнее значение — в
/// сообщении об ошибке.
Future<T> pollUntil<T>(
  WidgetTester tester,
  Future<T> Function() read,
  bool Function(T value) ok, {
  required String what,
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final sw = Stopwatch()..start();
  while (true) {
    final v = await read();
    if (ok(v)) return v;
    if (sw.elapsed > timeout) {
      throw TestFailure('Не дождались за ${timeout.inMilliseconds} мс: $what (последнее значение: $v)');
    }
    await tester.pump(step);
  }
}

/// Ждать, пока [read] не перестанет меняться на [quiet].
Future<T> waitStable<T>(
  WidgetTester tester,
  T Function() read, {
  required String what,
  Duration quiet = const Duration(milliseconds: 2500),
  Duration timeout = const Duration(seconds: 20),
}) async {
  final sw = Stopwatch()..start();
  var last = read();
  var since = sw.elapsed;
  while (sw.elapsed - since < quiet) {
    if (sw.elapsed > timeout) {
      throw TestFailure('Не устоялось за ${timeout.inMilliseconds} мс: $what (последнее значение: $last)');
    }
    await tester.pump(const Duration(milliseconds: 50));
    final v = read();
    if (v != last) {
      last = v;
      since = sw.elapsed;
    }
  }
  return last;
}

/// Касание в точке экрана [at] (глобальные логические координаты).
///
/// Время касания — по часам кадров движка: это те же монотонные часы, что
/// SystemClock.uptimeMillis у Android, а окно браузера получает касание как
/// MotionEvent с этим временем. У синтетического касания по умолчанию время
/// 0, и нажатие длилось бы «0 мс тридцать лет назад».
Future<void> tapAtGlobal(WidgetTester tester, Offset at, {Duration hold = const Duration(milliseconds: 70)}) async {
  final t0 = SchedulerBinding.instance.currentSystemFrameTimeStamp;
  final g = await tester.createGesture();
  await g.down(at, timeStamp: t0);
  await tester.pump(hold);
  await g.up(timeStamp: t0 + hold);
  await tester.pump(const Duration(milliseconds: 16));
}

/// Медиана замеров (повторные открытия шумят меньше одиночного).
num median(List<num> xs) {
  final s = [...xs]..sort();
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

/// Замеры скорости: строка «OGN_PERF {json}» на замер — в вывод
/// `flutter test` (событие print) и в журнал Android (logcat, через корневую
/// зону: в зоне теста print перехватывается). Собирает их
/// tool/perf/perf_check.py.
abstract final class PerfLog {
  static final Map<String, Object?> _all = {};

  static void record(String name, num ms, {Map<String, Object?> extra = const {}}) {
    _emit({'name': name, 'ms': ms.round(), ...extra});
  }

  /// Сведения об устройстве и сборке (строка «_device»).
  static void device(WidgetTester tester) {
    _emit({
      'name': '_device',
      'info': {
        'os': Platform.operatingSystemVersion,
        'mode': kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release'),
        'screen':
            '${screenWidth(tester).toStringAsFixed(0)}×'
            '${(tester.view.physicalSize.height / tester.view.devicePixelRatio).toStringAsFixed(0)} dp',
        'dpr': tester.view.devicePixelRatio,
      },
    });
  }

  static void _emit(Map<String, Object?> obj) {
    final line = 'OGN_PERF ${jsonEncode(obj)}';
    // ignore: avoid_print
    print(line);
    Zone.root.print(line);
    _all[obj['name']! as String] = obj;
    final b = IntegrationTestWidgetsFlutterBinding.instance;
    b.reportData ??= <String, dynamic>{};
    b.reportData!['perf'] = Map<String, Object?>.of(_all);
  }
}

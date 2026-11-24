// Метки производительности (2.6.8, план «Ж», просьба владельца 22.11.2026):
// участки в главном потоке и фоновые, что попадает в журнал медленных
// кадров и в каком порядке; отрезок времени кадра для поиска участков.

import 'dart:async' show unawaited;
import 'dart:developer' show Timeline;
import 'dart:io' show sleep;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/logging/jank_monitor.dart';
import 'package:ogneliss/core/logging/perf_mark.dart';

void main() {
  setUp(PerfMark.reset);

  test('короткие участки в журнал не попадают, долгие — да', () {
    PerfMark.sync('быстро', () => 1 + 1);
    final v = PerfMark.sync('долго', () {
      sleep(const Duration(milliseconds: 12));
      return 42;
    });
    expect(v, 42);
    expect([for (final s in PerfMark.recent) s.name], ['долго']);
    expect(PerfMark.recent.single.main, isTrue);
  });

  test('во время кадра: сначала главный поток, потом фоновые; идущий фоновый — тоже', () async {
    final from = Timeline.now;
    final bg = PerfMark.begin('синхронизация: папка Входящие');
    PerfMark.sync('письмо: разбор HTML', () => sleep(const Duration(milliseconds: 20)));
    PerfMark.sync('лента: письма из базы', () => sleep(const Duration(milliseconds: 6)));
    final to = Timeline.now;

    final spans = PerfMark.during(from, to);
    expect([for (final s in spans) s.name], ['письмо: разбор HTML', 'лента: письма из базы', 'синхронизация: папка Входящие']);
    final line = PerfMark.describe(spans);
    expect(line, startsWith('главный поток: письмо: разбор HTML '));
    expect(line, contains('; шло: синхронизация: папка Входящие'));

    PerfMark.end(bg);
    PerfMark.end(bg); // второй раз — ничего
    expect(PerfMark.during(to + 1000000, to + 2000000), isEmpty, reason: 'кончились до отрезка');
  });

  test('run: участок и при ошибке закрывается', () async {
    await expectLater(
      PerfMark.run('синхронизация: список папок', () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        throw StateError('сбой');
      }),
      throwsStateError,
    );
    expect(PerfMark.recent.single.name, 'синхронизация: список папок');
    expect(PerfMark.recent.single.endUs, greaterThan(0));
  });

  test('незакрытый участок с пределом времени потом не попадает в журнал', () {
    PerfMark.begin('открытие письма', limit: const Duration(milliseconds: 5));
    sleep(const Duration(milliseconds: 10));
    final from = Timeline.now;
    expect(PerfMark.during(from, from + 1000), isEmpty);
    // Закрыт по пределу — и в списке последних как законченный.
    expect(PerfMark.recent.single.name, 'открытие письма');
  });

  test('ничего не отмечено — пустая строка', () {
    expect(PerfMark.describe(const []), '');
  });

  group('отрезок медленного кадра', () {
    FrameTiming frame(int start, int ms) => FrameTiming(
      vsyncStart: start,
      buildStart: start + 1000,
      buildFinish: start + 2000,
      rasterStart: start + 3000,
      rasterFinish: start + ms * 1000,
      rasterFinishWallTime: 0,
    );

    test('часы кадра совпадают с Timeline — отрезок кадра чуть шире начала', () {
      final w = JankMonitor.windowOf(frame(50000000, 800), 50900000);
      expect(w.from, 50000000 - 100000);
      expect(w.to, 50800000);
    });

    test('часы не совпадают — последние полторы секунды перед отчётом', () {
      final w = JankMonitor.windowOf(frame(5000, 800), 90000000000);
      expect(w.to, 90000000000);
      expect(w.from, 90000000000 - 800000 - 1500000);
    });
  });

  // 2.7.1 (микрофризы 24.11.2026): в строке о медленном кадре — открытый
  // экран и сколько он открыт; адреса и номера писем в имя не попадают.
  testWidgets('открытый экран — в строке журнала', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [JankMonitor.observer()],
      onGenerateRoute: (s) => MaterialPageRoute<void>(settings: s, builder: (_) => const SizedBox()),
      initialRoute: 'mail',
    ));
    expect(JankMonitor.screenNote(), startsWith('экран mail, открыт '));
    unawaited(nav.currentState!.pushNamed('compose'));
    await tester.pumpAndSettle();
    expect(JankMonitor.screenNote(), matches(RegExp(r'^экран compose, открыт \d+,\d с назад$')));
    // Через 15 с — целыми секундами.
    expect(JankMonitor.screenNote(DateTime.now().add(const Duration(seconds: 15))),
        matches(RegExp(r'^экран compose, открыт 1\d с назад$')));
    unawaited(nav.currentState!.pushNamed('/mail/:id/thread'));
    await tester.pumpAndSettle();
    expect(JankMonitor.screenNote(), startsWith('экран mail/thread, '));
    nav.currentState!.pop();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(JankMonitor.screenNote(), startsWith('экран mail, '));
  });
}

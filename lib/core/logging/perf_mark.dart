// lib/core/logging/perf_mark.dart
// Метки производительности (2.6.8, план «Ж», просьба владельца 22.11.2026).
//
// Крупные участки работы — этапы синхронизации, открытие письма, разбор
// HTML письма, строки ленты из базы, сверка писем IMAP — отмечаются:
// - в Timeline (dart:developer): видны в DevTools («Performance») у сборки
//   profile и при замерах на эмуляторе. В выпуске Timeline выключен, и
//   метка стоит два чтения часов;
// - в коротком списке последних участков: журнал медленных кадров
//   (JankMonitor) пишет, что шло, пока интерфейс стоял, например
//   «главный поток: письмо: разбор HTML 420 мс; шло: синхронизация: папка
//   Входящие». Раньше по журналу было видно только, что кадр ждал.
//
// Имена участков — без адресов и текста писем (журнал уходит в поддержку):
// этап и папка, как в строках синхронизации.

import 'dart:developer' show Timeline, TimelineTask;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Участок: [startUs]–[endUs] по часам Timeline (мкс); [endUs] == -1 —
/// ещё идёт. [main] — синхронный, держал главный поток.
class PerfSpan {
  const PerfSpan(this.name, this.startUs, this.endUs, {required this.main});

  final String name;
  final int startUs;
  final int endUs;
  final bool main;

  int durationUs(int nowUs) => (endUs < 0 ? nowUs : endUs) - startUs;
}

abstract final class PerfMark {
  /// Участки короче — в список для журнала не попадают (в Timeline — все).
  static const _keepUs = 4000;

  /// Сколько последних участков помнить: кадр приходит в JankMonitor с
  /// задержкой до секунды, за это время участков меньше.
  static const _keep = 64;

  static final List<PerfSpan> _done = <PerfSpan>[];
  static final Map<int, ({PerfSpan span, TimelineTask task, int? untilUs})> _open = {};
  static int _nextId = 0;

  /// Синхронный участок главного потока: разбор, сборка списка.
  static T sync<T>(String name, T Function() body) {
    final start = Timeline.now;
    Timeline.startSync(name);
    try {
      return body();
    } finally {
      Timeline.finishSync();
      _remember(PerfSpan(name, start, Timeline.now, main: true));
    }
  }

  /// Участок на несколько кадров (этап синхронизации, открытие письма).
  static Future<T> run<T>(String name, Future<T> Function() body) async {
    final id = begin(name);
    try {
      return await body();
    } finally {
      end(id);
    }
  }

  /// Начало участка без замыкания (открытие письма: начало и конец — в
  /// разных местах); вернуть номер в [end]. [limit] — участок, который так
  /// и не закрыли (ушли с экрана, не дождавшись), через это время
  /// считается законченным и в журнал больше не попадает.
  static int begin(String name, {Duration? limit}) {
    final id = ++_nextId;
    final task = TimelineTask()..start(name);
    final now = Timeline.now;
    _open[id] = (
      span: PerfSpan(name, now, -1, main: false),
      task: task,
      untilUs: limit == null ? null : now + limit.inMicroseconds,
    );
    return id;
  }

  /// Конец участка [begin]; второй раз — ничего.
  static void end(int id) => _end(id, Timeline.now);

  static void _end(int id, int atUs) {
    final o = _open.remove(id);
    if (o == null) return;
    o.task.finish();
    _remember(PerfSpan(o.span.name, o.span.startUs, atUs, main: false));
  }

  /// Отметка без длительности (этап открытия письма) — только в Timeline.
  static void instant(String name) => Timeline.instantSync(name);

  static void _remember(PerfSpan s) {
    if (s.endUs - s.startUs < _keepUs) return;
    _done.add(s);
    if (_done.length > _keep) _done.removeRange(0, _done.length - _keep);
  }

  /// Что шло в отрезке [fromUs]–[toUs] (часы Timeline): сначала участки
  /// главного потока, потом фоновые; внутри — по убыванию длительности,
  /// без повторов имён.
  static List<PerfSpan> during(int fromUs, int toUs) {
    final now = Timeline.now;
    for (final e in _open.entries.toList()) {
      final until = e.value.untilUs;
      if (until != null && now > until) _end(e.key, until);
    }
    final hit = <PerfSpan>[
      for (final s in _done)
        if (s.startUs <= toUs && s.endUs >= fromUs) s,
      for (final o in _open.values)
        if (o.span.startUs <= toUs) o.span,
    ]..sort((a, b) {
        if (a.main != b.main) return a.main ? -1 : 1;
        return b.durationUs(now).compareTo(a.durationUs(now));
      });
    final names = <String>{};
    return [for (final s in hit) if (names.add('${s.main}|${s.name}')) s];
  }

  /// Строка для журнала: «главный поток: A 420 мс; шло: B, C» — не больше
  /// трёх имён в каждой части; '' — ничего не отмечено.
  static String describe(List<PerfSpan> spans) {
    final now = Timeline.now;
    final main = [
      for (final s in spans.where((s) => s.main).take(3)) '${s.name} ${(s.durationUs(now) / 1000).round()} мс',
    ];
    final bg = [for (final s in spans.where((s) => !s.main).take(3)) s.name];
    return [
      if (main.isNotEmpty) 'главный поток: ${main.join(', ')}',
      if (bg.isNotEmpty) 'шло: ${bg.join(', ')}',
    ].join('; ');
  }

  @visibleForTesting
  static void reset() {
    _done.clear();
    _open.clear();
  }

  /// Участки в памяти (для тестов).
  @visibleForTesting
  static List<PerfSpan> get recent => List.unmodifiable(_done);
}

// lib/services/background/work_scheduler.dart
// Планировщик работы с приоритетами (1.5.9).
//
// Раньше у каждой фоновой работы был свой счётчик и своя пауза:
// синхронизация — предел 3 папки, докачка тел — пауза 4 с при открытии
// письма, а подготовка писем заранее и картинки — без пределов. Открытое
// письмо конкурировало с ними на равных: за соединение с сервером, базу,
// процессор и главный поток. Здесь — одна очередь с приоритетами:
//
//   open      — открытое письмо: тело, картинки, запрос EWS (не ограничено
//               паузой; предел — от лавины, а не для очереди);
//   visible   — видимое на экране: фото, превью;
//   sync      — синхронизация папок (было `_maxParallel = 3`);
//   prefetch  — докачка тел, подготовка свежих писем заранее;
//   idle      — обслуживание: оптимизация базы, очистка кэшей.
//
// Открыто письмо ([hold]) — на несколько секунд prefetch и idle не
// начинаются (начатое доделывается), синхронизация — не больше одной папки
// сразу. Освобождённое место сразу передаётся следующему ожидающему, без
// опроса таймером.

import 'dart:async';
import 'dart:collection';

enum WorkPriority { open, visible, sync, prefetch, idle }

class WorkScheduler {
  WorkScheduler._();

  static final instance = WorkScheduler._();

  static const Map<WorkPriority, int> _limits = {
    WorkPriority.open: 4,
    WorkPriority.visible: 3,
    WorkPriority.sync: 3,
    WorkPriority.prefetch: 1,
    WorkPriority.idle: 1,
  };

  final Map<WorkPriority, int> _running = {for (final p in WorkPriority.values) p: 0};
  final Map<WorkPriority, Queue<Completer<void>>> _waiting = {
    for (final p in WorkPriority.values) p: Queue<Completer<void>>(),
  };
  final List<Completer<void>> _holdWaiters = [];

  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _holdTimer;

  /// Открыто письмо: фон уступает ему место.
  bool get holding => DateTime.now().isBefore(_holdUntil);

  int _limit(WorkPriority p) {
    if (holding) {
      if (p == WorkPriority.prefetch || p == WorkPriority.idle) return 0;
      if (p == WorkPriority.sync) return 1;
    }
    return _limits[p]!;
  }

  /// Занять место (ждать, если свободных нет). Каждому [acquire] — ровно
  /// один [release].
  Future<void> acquire(WorkPriority p) {
    if (_running[p]! < _limit(p) && _waiting[p]!.isEmpty) {
      _running[p] = _running[p]! + 1;
      return Future<void>.value();
    }
    final c = Completer<void>();
    _waiting[p]!.add(c);
    return c.future;
  }

  void release(WorkPriority p) {
    final n = _running[p]! - 1;
    _running[p] = n < 0 ? 0 : n;
    _pump();
  }

  /// Выполнить [job] с местом приоритета [p].
  Future<T> run<T>(WorkPriority p, Future<T> Function() job) async {
    await acquire(p);
    try {
      return await job();
    } finally {
      release(p);
    }
  }

  /// Открыто письмо: [d] фоновая работа уступает ему (повторный вызов
  /// продлевает, а не сокращает паузу).
  void hold([Duration d = const Duration(seconds: 4)]) {
    final until = DateTime.now().add(d);
    if (!until.isAfter(_holdUntil)) return;
    _holdUntil = until;
    _holdTimer?.cancel();
    _holdTimer = Timer(d, _endHold);
  }

  /// Письмо показано и его работа закончена — пауза не нужна.
  void releaseHold() {
    if (!holding) return;
    _holdUntil = DateTime.now();
    _holdTimer?.cancel();
    _endHold();
  }

  void _endHold() {
    _holdTimer = null;
    if (holding) {
      // Пауза продлена другим письмом после запуска таймера.
      _holdTimer = Timer(_holdUntil.difference(DateTime.now()), _endHold);
      return;
    }
    final list = List<Completer<void>>.of(_holdWaiters);
    _holdWaiters.clear();
    for (final c in list) {
      if (!c.isCompleted) c.complete();
    }
    _pump();
  }

  /// Дождаться конца паузы (для длинных циклов докачки: между пачками).
  Future<void> whenNotHolding() {
    if (!holding) return Future<void>.value();
    final c = Completer<void>();
    _holdWaiters.add(c);
    return c.future;
  }

  void _pump() {
    for (final p in WorkPriority.values) {
      final q = _waiting[p]!;
      while (q.isNotEmpty && _running[p]! < _limit(p)) {
        _running[p] = _running[p]! + 1;
        q.removeFirst().complete();
      }
    }
  }
}

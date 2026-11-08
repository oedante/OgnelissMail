import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/logging/app_logger.dart';

/// Одна синхронизация за раз в изоляте.
///
/// Раньше вызов при идущей синхронизации молча возвращался: обновление
/// жестом гасло сразу и «не срабатывало», «Полная пересинхронизация» ничего
/// не делала, а при зависшей синхронизации не работало вообще ничего до
/// перезапуска. Потом второй вызов стал ждать идущую (индикатор крутится до
/// конца), а идущую дольше 20 минут — считать зависшей и запускать новую.
///
/// [fresh] (1.6.43, фоновая задача): идущая синхронизация могла начаться до
/// того, как система заморозила процесс, и висит на мёртвом запросе. Ждём её
/// не больше 20 секунд и затем делаем свой проход — фоновой задаче нужен
/// результат сейчас, пока система даёт процессу сеть.
///
/// [PassScope] (08.11.2026, вопрос владельца «как обновляется
/// при открытии приложения, не мешает ли один механизм другому»): плановая
/// проверка (таймер, пульс, задача WorkManager) пропускает ящики, которые
/// проверялись меньше их интервала назад, — с живым push это 30 минут.
/// Проверка при открытии и «потянуть вниз», пришедшие во время плановой,
/// ждали её и выходили — ящик так и оставался непроверенным. Теперь вызов,
/// которому нужна более полная проверка, чем идущая, после неё делает свой
/// проход.
class SinglePass {
  SinglePass({
    @visibleForTesting this.wait = const Duration(minutes: 5),
    @visibleForTesting this.freshWait = const Duration(seconds: 20),
    @visibleForTesting this.stuck = const Duration(minutes: 20),
  });

  final Duration wait;
  final Duration freshWait;
  final Duration stuck;

  Future<void>? _inFlight;
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0);
  PassScope _scope = PassScope.due;

  /// Идёт ли сейчас проход.
  bool get running => _inFlight != null;

  /// Сколько идёт текущий проход; null — не идёт.
  Duration? get runningFor => _inFlight == null ? null : DateTime.now().difference(_since);

  /// [needs] — какая проверка нужна вызову: идущий проход его устраивает,
  /// только если охватывает не меньше. [covers] — что охватывает этот проход.
  Future<void> run(Future<void> Function() body,
      {bool fresh = false, PassScope needs = PassScope.due, PassScope covers = PassScope.due}) async {
    while (true) {
      final running = _inFlight;
      if (running == null) break;
      final age = DateTime.now().difference(_since);
      if (age >= stuck) {
        AppLogger.warning('Синхронизация идёт ${age.inMinutes} мин — считаю зависшей, запускаю новую');
        break;
      }
      final covered = _scope.index >= needs.index;
      try {
        await running.timeout(fresh ? freshWait : wait);
      } catch (_) {}
      if (fresh) {
        AppLogger.info('Синхронизация: после идущей — свой проход');
        break;
      }
      if (covered) return;
      // Пока ждали, мог начаться другой проход (например, тоже по открытию
      // приложения) — подождать его, а не идти вторым рядом.
      final next = _inFlight;
      if (next == null || identical(next, running)) {
        AppLogger.info('Синхронизация: идущая проверка была плановой — проверяю всё сам');
        break;
      }
    }
    final done = Completer<void>();
    final mine = done.future;
    _inFlight = mine;
    _since = DateTime.now();
    _scope = covers;
    try {
      await body();
    } finally {
      if (identical(_inFlight, mine)) {
        _inFlight = null;
        _scope = PassScope.due;
      }
      done.complete();
    }
  }
}

/// Что охватывает проход синхронизации (по возрастанию).
enum PassScope {
  /// Только ящики, которым пора по их интервалу (таймер, пульс, WorkManager),
  /// или один ящик.
  due,

  /// Все ящики с автоматической проверкой, без пропуска «ещё не пора»
  /// (открытие приложения, сигнал сервера, фоновая задача iOS).
  scheduled,

  /// Все ящики, в том числе «только вручную» («потянуть вниз», «Проверить
  /// почту»).
  all,
}

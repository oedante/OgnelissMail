// lib/core/utils/work_isolate.dart
// Долгоживущие рабочие изоляты (1.5.9) вместо Isolate.run на каждый вызов.
//
// Isolate.run запускает новый изолят на каждую задачу: подготовка письма,
// санитайзер, разбор ответа EWS — каждый раз запуск изолята (единицы
// миллисекунд на Android) плюс его остановка. Здесь два изолята живут всё
// время работы приложения и принимают задачи очередью:
//  · [WorkIsolate.interactive] — то, чего человек ждёт сейчас: открытое
//    письмо, вложение, редактор;
//  · [WorkIsolate.background] — синхронизация и докачка: пачки писем,
//    поисковый индекс, разбор ответов сервера.
// Два изолята, а не один — чтобы пачка из сотен писем синхронизации не
// стояла в очереди перед открытым письмом (приоритет без вытеснения).
//
// Задача — замыкание без ссылок на объекты с сокетами, каналами платформы
// и Ref (те же правила, что у Isolate.run: изоляты одной группы, замыкание
// передаётся SendPort). Не удалось запустить изолят или передать задачу —
// задача выполняется через Isolate.run, а на вебе — на месте.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../logging/app_logger.dart';

class WorkIsolate {
  WorkIsolate._(this.name);

  final String name;

  static final interactive = WorkIsolate._('ogneliss-open');
  static final background = WorkIsolate._('ogneliss-bg');

  SendPort? _send;
  Isolate? _isolate;
  Future<SendPort?>? _starting;
  ReceivePort? _replies;
  ReceivePort? _exit;
  final Map<int, Completer<Object?>> _pending = {};
  int _seq = 0;

  /// Запуск не удался — дальше без рабочего изолята (Isolate.run).
  bool _unavailable = false;

  /// Запустить изолят заранее (в простое после старта), чтобы первое
  /// открытое письмо не платило за запуск.
  Future<void> warm() async {
    if (kIsWeb) return;
    await _port();
  }

  /// Выполнить [fn] в рабочем изоляте. Ошибка задачи приходит как
  /// [RemoteError] — как у Isolate.run.
  ///
  /// [timeout] (1.6.12): задача, которая не ответила за это время, считается
  /// зависшей — изолят перезапускается, ждущие задачи получают ошибку.
  /// Раньше одна «тяжёлая» задача (разбор огромного письма) занимала изолят
  /// навсегда, за ней вставала вся очередь, а с ней — синхронизация ящика:
  /// в журнале после FolderSync не было ни одного запроса часами.
  Future<R> run<R>(FutureOr<R> Function() fn, {Duration timeout = const Duration(seconds: 90)}) async {
    if (kIsWeb) return await fn();
    final port = _unavailable ? null : await _port();
    if (port == null) return Isolate.run(fn);
    final id = ++_seq;
    final done = Completer<Object?>();
    _pending[id] = done;
    try {
      port.send((id, fn));
    } catch (e) {
      // Замыкание не передаётся (захватило то, что нельзя передать) —
      // так же, как раньше, через Isolate.run.
      _pending.remove(id);
      AppLogger.debug('Рабочий изолят $name: задачу не передать ($e)');
      return Isolate.run(fn);
    }
    final r = await done.future.timeout(timeout, onTimeout: () {
      AppLogger.error('Рабочий изолят $name: задача не завершилась за ${timeout.inSeconds} с — изолят перезапущен');
      _restart();
      throw TimeoutException('рабочий изолят $name', timeout);
    });
    return r as R;
  }

  /// Остановить зависший изолят: следующая задача запустит новый.
  void _restart() {
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
    _onExit();
  }

  Future<SendPort?> _port() {
    final p = _send;
    if (p != null) return Future.value(p);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<SendPort?> _start() async {
    try {
      final replies = ReceivePort();
      final exit = ReceivePort();
      final first = Completer<SendPort>();
      replies.listen((msg) {
        if (msg is SendPort) {
          if (!first.isCompleted) first.complete(msg);
          return;
        }
        if (msg is (int, bool, Object?)) {
          final c = _pending.remove(msg.$1);
          if (c == null) return;
          if (msg.$2) {
            c.complete(msg.$3);
          } else {
            c.completeError(msg.$3 ?? RemoteError('ошибка задачи', ''));
          }
        }
      });
      exit.listen((_) => _onExit());
      _replies = replies;
      _exit = exit;
      _isolate = await Isolate.spawn(_main, replies.sendPort,
          debugName: name, onExit: exit.sendPort, errorsAreFatal: false);
      final port = await first.future.timeout(const Duration(seconds: 5));
      _send = port;
      return port;
    } catch (e) {
      AppLogger.warning('Рабочий изолят $name не запустился: $e — задачи через Isolate.run');
      _unavailable = true;
      _close();
      return null;
    }
  }

  /// Изолят завершился (система, ошибка вне задачи): ждущие задачи — с
  /// ошибкой, следующая задача запустит изолят заново.
  void _onExit() {
    final waiting = List<Completer<Object?>>.of(_pending.values);
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.completeError(RemoteError('рабочий изолят $name завершился', ''));
    }
    _close();
  }

  void _close() {
    _send = null;
    _replies?.close();
    _exit?.close();
    _replies = null;
    _exit = null;
  }

  static void _main(SendPort reply) {
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((msg) async {
      if (msg is! (int, Function)) return;
      final id = msg.$1;
      try {
        final r = await (msg.$2 as FutureOr<Object?> Function())();
        reply.send((id, true, r));
      } catch (e, st) {
        reply.send((id, false, RemoteError('$e', '$st')));
      }
    });
  }
}

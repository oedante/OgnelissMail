// Одна синхронизация за раз и «не довольствоваться неполной идущей»
// (08.11.2026, вопрос владельца «как обновляется при открытии приложения, не
// мешает ли один механизм другому»).
//
// Проверка при открытии и «потянуть вниз», пришедшие во время плановой
// проверки (таймер, пульс, WorkManager — ящики «ещё не пора» пропускаются),
// раньше ждали её и выходили: ящик оставался непроверенным.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/sync/single_pass.dart';

void main() {
  late SinglePass pass;
  late List<String> ran;

  setUp(() {
    pass = SinglePass(
      wait: const Duration(seconds: 2),
      freshWait: const Duration(milliseconds: 50),
      stuck: const Duration(minutes: 20),
    );
    ran = [];
  });

  /// Проход, который идёт, пока не отпустят [gate].
  Future<void> held(String name, Completer<void> gate, PassScope scope) => pass.run(() async {
        ran.add(name);
        await gate.future;
      }, needs: scope, covers: scope);

  Future<void> quick(String name, PassScope scope, {bool fresh = false}) =>
      pass.run(() async => ran.add(name), needs: scope, covers: scope, fresh: fresh);

  test('плановая во время плановой — ждёт идущую, своего прохода нет', () async {
    final gate = Completer<void>();
    final first = held('таймер', gate, PassScope.due);
    final second = quick('пульс', PassScope.due);
    gate.complete();
    await Future.wait([first, second]);
    expect(ran, ['таймер']);
  });

  test('открытие приложения во время плановой — после неё свой полный проход', () async {
    final gate = Completer<void>();
    final timer = held('таймер', gate, PassScope.due);
    final resume = quick('открытие', PassScope.scheduled);
    await pumpEventQueue();
    expect(ran, ['таймер'], reason: 'одновременно — не идут');
    gate.complete();
    await Future.wait([timer, resume]);
    expect(ran, ['таймер', 'открытие']);
  });

  test('«потянуть вниз» во время полной проверки — она его устраивает', () async {
    final gate = Completer<void>();
    final full = held('проверить всё', gate, PassScope.all);
    final pull = quick('потянуть', PassScope.all);
    gate.complete();
    await Future.wait([full, pull]);
    expect(ran, ['проверить всё']);
  });

  test('два вызова ждут плановую — второй не идёт рядом, а ждёт первый', () async {
    final gate = Completer<void>();
    final timer = held('таймер', gate, PassScope.due);
    final second = Completer<void>();
    final resume = held('открытие', second, PassScope.scheduled);
    final pull = quick('потянуть', PassScope.scheduled);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    expect(ran, ['таймер', 'открытие']);
    second.complete();
    await Future.wait([timer, resume, pull]);
    expect(ran, ['таймер', 'открытие'], reason: 'проход «открытие» уже охватил всё');
  });

  test('фоновая задача (fresh) ждёт идущую недолго и делает свой проход', () async {
    final gate = Completer<void>();
    final stuck = held('завис', gate, PassScope.all);
    await quick('задача', PassScope.due, fresh: true);
    expect(ran, ['завис', 'задача']);
    gate.complete();
    await stuck;
  });

  test('состояние: идёт / не идёт', () async {
    expect(pass.running, isFalse);
    final gate = Completer<void>();
    final f = held('x', gate, PassScope.due);
    expect(pass.running, isTrue);
    expect(pass.runningFor, isNotNull);
    gate.complete();
    await f;
    expect(pass.running, isFalse);
    expect(pass.runningFor, isNull);
  });
}

// Надёжность уведомлений (1.6.44): выключенная категория «Почта» на Android
// и учёт начатой работы для «доделать после сворачивания» на iPhone.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/finish_in_background.dart';
import 'package:ogneliss/core/platform/platform_diagnostics.dart';

void main() {
  group('Категория «Почта» выключена', () {
    test('все каналы писем с важностью 0 — выключена', () {
      expect(
          PlatformDiagnostics.mailChannelsOff({
            'channels': [
              {'id': 'email_default_sv', 'importance': 0},
              {'id': 'email_default_nn', 'importance': 0},
              {'id': 'meeting_reminders', 'importance': 4},
            ],
          }),
          isTrue);
    });

    test('хотя бы один канал писем включён — в порядке', () {
      expect(
          PlatformDiagnostics.mailChannelsOff({
            'channels': [
              {'id': 'email_default_sv', 'importance': 4},
              {'id': 'email_default_nn', 'importance': 0},
            ],
          }),
          isFalse);
    });

    test('каналов писем ещё нет (письма не приходили) — не тревожим', () {
      expect(
          PlatformDiagnostics.mailChannelsOff({
            'channels': [
              {'id': 'reminders', 'importance': 0},
            ],
          }),
          isFalse);
      expect(PlatformDiagnostics.mailChannelsOff(const {}), isFalse);
    });
  });

  group('Начатая работа', () {
    test('guard считает и отпускает работу, в том числе при ошибке', () async {
      expect(FinishInBackground.busy, isFalse);
      final gate = Completer<void>();
      final f = FinishInBackground.guard(() => gate.future);
      expect(FinishInBackground.busy, isTrue);
      expect(FinishInBackground.busyCount, 1);
      gate.complete();
      await f;
      expect(FinishInBackground.busy, isFalse);

      await expectLater(FinishInBackground.guard<void>(() async => throw StateError('x')), throwsStateError);
      expect(FinishInBackground.busyCount, 0);
    });

    test('guard возвращает результат работы', () async {
      expect(await FinishInBackground.guard(() async => 42), 42);
    });
  });
}

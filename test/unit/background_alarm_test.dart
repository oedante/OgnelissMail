// Будильник фоновой проверки почты (Android, 2.3.2). Требование владельца
// 11.11.2026: «для всех режимов (15, 30, час, по расписанию, пуш) проверки
// должны срабатывать вовремя, а не когда придётся». Журнал пользователя
// 10.11.2026: ящик «раз в 15 минут», телефон в глубоком сне — проверки в
// 16:05, 17:28 и 19:39.
//
// Здесь — расчёт для нативной части (SyncHeartbeat.kt): интервал будильника
// и срок ближайшего ящика.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/background/background_alarm.dart';
import 'package:ogneliss/services/background/background_service.dart';
import 'package:ogneliss/services/sync/sync_schedule.dart';

AccountModel acc(String id, SyncInterval interval, {bool active = true, DateTime? authFailedAt}) => AccountModel(
      id: id,
      type: AccountType.imap,
      email: '$id@example.com',
      displayName: id,
      username: '$id@example.com',
      syncInterval: interval,
      isActive: active,
      authFailedAt: authFailedAt,
      createdAt: DateTime(2026),
    );

void main() {
  final now = DateTime(2026, 11, 10, 16, 5);

  test('интервал проверки ящика: один расчёт для проверки и будильника', () {
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.minutes15)), 15);
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.minutes30)), 30);
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.hour1)), 60);
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.minutes5)), 5);
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.manual)), isNull);
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.push)), 15, reason: 'без живого push — как «раз в 15 минут»');
    expect(SyncSchedule.checkMinutes(acc('a', SyncInterval.push), pushOk: true), 30);
  });

  test('интервал будильника — наименьший среди ящиков; «Никогда» и «только вручную» — без будильника', () {
    final accounts = [acc('a', SyncInterval.hour1), acc('b', SyncInterval.minutes30), acc('c', SyncInterval.manual)];
    expect(BackgroundAlarm.minutesFor(globalInterval: 15, accounts: accounts), 30);
    expect(BackgroundAlarm.minutesFor(globalInterval: -1, accounts: accounts), 0, reason: '«Никогда»');
    expect(BackgroundAlarm.minutesFor(globalInterval: 15, accounts: [acc('c', SyncInterval.manual)]), 0);
    expect(BackgroundAlarm.minutesFor(globalInterval: 15, accounts: [acc('d', SyncInterval.minutes15, active: false)]), 0);
    expect(
        BackgroundAlarm.minutesFor(
            globalInterval: 15, accounts: [acc('e', SyncInterval.minutes15, authFailedAt: DateTime(2026, 11, 1))]),
        0,
        reason: 'ящик ждёт входа — его не проверяют');
    expect(BackgroundAlarm.minutesFor(globalInterval: 0, accounts: [acc('p', SyncInterval.push)]), 15,
        reason: 'служба «Мгновенно» остановлена системой — проверка раз в 15 минут');
  });

  test('срок ближайшего ящика: прошлая синхронизация + его интервал', () {
    final plan = BackgroundAlarm.plan(
      globalInterval: 15,
      accounts: [acc('a', SyncInterval.minutes15), acc('b', SyncInterval.hour1)],
      lastSync: {'a': now.subtract(const Duration(minutes: 5)), 'b': now.subtract(const Duration(minutes: 50))},
      now: now,
    );
    expect(plan.minutes, 15);
    expect(DateTime.fromMillisecondsSinceEpoch(plan.nextDueMs), now.add(const Duration(minutes: 10)),
        reason: 'оба ящика подойдут через 10 минут');
  });

  test('ящик, срок которого прошёл (проверка не удалась), ждёт следующей попытки, а не «сейчас»', () {
    final plan = BackgroundAlarm.plan(
      globalInterval: 15,
      accounts: [acc('a', SyncInterval.hour1)],
      lastSync: {'a': now.subtract(const Duration(hours: 3))},
      now: now,
    );
    expect(DateTime.fromMillisecondsSinceEpoch(plan.nextDueMs), now.add(const Duration(minutes: 15)),
        reason: 'повтор через 15 минут, а не через час');
    final fresh = BackgroundAlarm.plan(
      globalInterval: 15,
      accounts: [acc('n', SyncInterval.minutes30)],
      lastSync: const {},
      now: now,
    );
    expect(DateTime.fromMillisecondsSinceEpoch(fresh.nextDueMs), now.add(const Duration(minutes: 15)),
        reason: 'новый ящик, ещё не синхронизирован');
  });

  test('фоновые проверки выключены — срока нет', () {
    final plan = BackgroundAlarm.plan(
        globalInterval: -1, accounts: [acc('a', SyncInterval.minutes15)], lastSync: const {}, now: now);
    expect(plan.minutes, 0);
    expect(plan.nextDueMs, 0);
  });

  test('задача будильника: своё название в журнале, три минуты', () {
    final info = backgroundTaskInfo('alarm_check');
    expect(info.kind, 'будильник');
    expect(info.limit, const Duration(minutes: 3));
  });
}

// Самовосстановление (1.6.48): какие ящики «давно не обновлялись».
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/sync/stale_watchdog.dart';

AccountModel _acc(String id, {SyncInterval every = SyncInterval.minutes15, DateTime? authFailedAt}) => AccountModel(
      id: id,
      type: AccountType.activesync,
      email: '$id@corp.ru',
      displayName: id,
      username: id,
      createdAt: DateTime(2026),
      syncInterval: every,
      authFailedAt: authFailedAt,
    );

void main() {
  final now = DateTime(2026, 10, 19, 18, 0);
  DateTime? noPush(String _) => null;
  final old = now.subtract(const Duration(hours: 1));

  test('давний ящик — чинить, свежий — нет', () {
    final stale = StaleWatchdog.staleOf([
      (account: _acc('old'), last: old),
      (account: _acc('fresh'), last: now.subtract(const Duration(minutes: 3))),
    ], now: now, pushAlive: noPush);
    expect(stale.map((a) => a.id), ['old']);
  });

  test('отказ входа, «вручную» и ни разу не обновлявшийся — не трогаем', () {
    final stale = StaleWatchdog.staleOf([
      (account: _acc('auth', authFailedAt: now), last: old),
      (account: _acc('manual', every: SyncInterval.manual), last: old),
      (account: _acc('new'), last: null),
    ], now: now, pushAlive: noPush);
    expect(stale, isEmpty);
  });

  test('push на связи — не давний', () {
    final stale = StaleWatchdog.staleOf([
      (account: _acc('p', every: SyncInterval.push), last: old),
    ], now: now, pushAlive: (_) => now.subtract(const Duration(minutes: 1)));
    expect(stale, isEmpty);
  });
}

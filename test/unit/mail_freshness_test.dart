// «Обновлено …» под названием папки (1.6.47): свежесть почты на экране.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/sync/mail_freshness.dart';

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
  final now = DateTime(2026, 10, 19, 15, 40);
  DateTime? noPush(String _) => null;

  test('свежий ящик — время последней проверки, не «давно»', () {
    final f = MailFreshness.of([(account: _acc('a'), last: now.subtract(const Duration(minutes: 10)))],
        now: now, pushAlive: noPush);
    expect(f.at, now.subtract(const Duration(minutes: 10)));
    expect(f.stale, isFalse);
  });

  test('зависла проверка: больше двух интервалов — «давно»', () {
    final f = MailFreshness.of([(account: _acc('a'), last: now.subtract(const Duration(minutes: 40)))],
        now: now, pushAlive: noPush);
    expect(f.stale, isTrue);
  });

  test('push на связи — почта свежая «сейчас»', () {
    final f = MailFreshness.of(
      [(account: _acc('a', every: SyncInterval.push), last: now.subtract(const Duration(hours: 3)))],
      now: now,
      pushAlive: (_) => now.subtract(const Duration(minutes: 1)),
    );
    expect(f.at, now);
    expect(f.stale, isFalse);
  });

  test('несколько ящиков — по самому несвежему', () {
    final old = now.subtract(const Duration(minutes: 50));
    final f = MailFreshness.of([
      (account: _acc('a'), last: now),
      (account: _acc('b'), last: old),
    ], now: now, pushAlive: noPush);
    expect(f.at, old);
    expect(f.stale, isTrue);
  });

  test('«только вручную» не бывает давним и не тянет время назад', () {
    final f = MailFreshness.of([
      (account: _acc('a'), last: now.subtract(const Duration(minutes: 5))),
      (account: _acc('m', every: SyncInterval.manual), last: now.subtract(const Duration(days: 3))),
    ], now: now, pushAlive: noPush);
    expect(f.at, now.subtract(const Duration(minutes: 5)));
    expect(f.stale, isFalse);
  });

  test('общая проверка «Никогда» — не «давно»', () {
    final f = MailFreshness.of([(account: _acc('a'), last: now.subtract(const Duration(days: 1)))],
        now: now, pushAlive: noPush, autoSync: false);
    expect(f.stale, isFalse);
  });

  test('нужен вход — «давно», ещё не обновлялся — без времени', () {
    final f = MailFreshness.of([(account: _acc('a', authFailedAt: now), last: null)], now: now, pushAlive: noPush);
    expect(f.at, isNull);
    expect(f.stale, isTrue);
  });
}

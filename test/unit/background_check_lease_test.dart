// Одна фоновая проверка за раз (2.0.0, требование владельца 08.11.2026:
// «сигналы не должны мешать друг другу, накладываться»): плановая задача,
// сигнал сервера и пульс без службы (Android), «Обновление» и «Обработка»
// (iOS) без приложения в процессе не проверяют почту одновременно.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/services/background/background_service.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  const ttl = Duration(minutes: 4);

  test('вторая задача того же процесса не начинает проверку, пока идёт первая', () async {
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg_periodic'), isTrue);
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg_signal'), isFalse,
        reason: 'сигнал сервера пришёл во время плановой проверки');
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg_heartbeat'), isFalse);
    await releaseBackgroundCheck(db, owner: 'p1:bg_periodic');
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg_signal'), isTrue, reason: 'первая закончила');
  });

  test('аренда умершего процесса не держит проверку', () async {
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg_periodic'), isTrue);
    // Процесс выгрузили посреди проверки; новый процесс — другой номер.
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p2:bg_signal'), isTrue);
  });

  test('просроченная аренда освобождается', () async {
    expect(await acquireBackgroundCheck(db, const Duration(milliseconds: -1), owner: 'p1:a'), isTrue);
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:b'), isTrue);
  });

  test('аренда проверки не мешает арендам ящиков', () async {
    expect(await acquireBackgroundCheck(db, ttl, owner: 'p1:bg'), isTrue);
    expect(await db.tryAcquireSyncLease('acc1', 'p1:iso_main', ttl), isTrue);
  });

  test('ключ отметки «проверка была» совпадает с тем, что читает SyncHeartbeat.kt', () {
    expect(bgCheckDoneKey, 'bg_check_done_at');
    expect(bgCheckLeaseKey, '__bg_check__');
  });
}

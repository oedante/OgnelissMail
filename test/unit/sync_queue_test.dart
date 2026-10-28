// test/unit/sync_queue_test.dart
// Офлайн-очередь операций (SyncService.enqueueOperation): ошибка здесь —
// потерянные или задвоенные действия пользователя (TECH_DEBT_AUDIT, раздел 3).
// Повтор одной операции по одному письму схлопывается в одну запись с
// последним состоянием и прежним местом в очереди; у переноса сохраняется
// исходная папка; счётчик попыток сбрасывается.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/services/sync/sync_service.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    sync = container.read(syncServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<SyncQueueData>> rows() =>
      (db.select(db.syncQueue)..orderBy([(q) => OrderingTerm(expression: q.id)])).get();

  Map<String, dynamic> payloadOf(SyncQueueData r) => jsonDecode(r.payloadJson) as Map<String, dynamic>;

  test('повтор флага по одному письму — одна запись с последним состоянием', () async {
    for (final on in [true, false, true]) {
      await sync.enqueueOperation(accountId: 'a1', operationType: 'flag', targetId: 'm1', payload: {'flagged': on});
    }
    final r = await rows();
    expect(r, hasLength(1));
    expect(payloadOf(r.single)['flagged'], isTrue);
  });

  test('перенос дважды — исходная папка первой записи, конечная — последней', () async {
    await sync.enqueueOperation(
        accountId: 'a1', operationType: 'move', targetId: 'm1', payload: {'fromFolderId': 'inbox', 'toFolderId': 'A'});
    await sync.enqueueOperation(
        accountId: 'a1', operationType: 'move', targetId: 'm1', payload: {'fromFolderId': 'A', 'toFolderId': 'B'});
    final r = await rows();
    expect(r, hasLength(1));
    expect(payloadOf(r.single)['fromFolderId'], 'inbox');
    expect(payloadOf(r.single)['toFolderId'], 'B');
  });

  test('порядок «перенести → удалить» сохраняется при повторном переносе', () async {
    await sync.enqueueOperation(
        accountId: 'a1', operationType: 'move', targetId: 'm1', payload: {'fromFolderId': 'inbox', 'toFolderId': 'A'});
    await sync.enqueueOperation(accountId: 'a1', operationType: 'delete', targetId: 'm1');
    await sync.enqueueOperation(
        accountId: 'a1', operationType: 'move', targetId: 'm1', payload: {'fromFolderId': 'A', 'toFolderId': 'B'});
    final r = await rows();
    expect(r.map((e) => e.operationType).toList(), ['move', 'delete']);
  });

  test('разные письма, ящики и операции не схлопываются', () async {
    await sync.enqueueOperation(accountId: 'a1', operationType: 'mark_read', targetId: 'm1', payload: {'isRead': true});
    await sync.enqueueOperation(accountId: 'a1', operationType: 'mark_read', targetId: 'm2', payload: {'isRead': true});
    await sync.enqueueOperation(accountId: 'a2', operationType: 'mark_read', targetId: 'm1', payload: {'isRead': true});
    await sync.enqueueOperation(accountId: 'a1', operationType: 'flag', targetId: 'm1', payload: {'flagged': true});
    expect(await rows(), hasLength(4));
  });

  test('повтор сбрасывает счётчик попыток (новое состояние — новая попытка)', () async {
    await sync.enqueueOperation(accountId: 'a1', operationType: 'flag', targetId: 'm1', payload: {'flagged': true});
    final first = (await rows()).single;
    await (db.update(db.syncQueue)..where((q) => q.id.equals(first.id)))
        .write(const SyncQueueCompanion(retryCount: Value(5)));
    await sync.enqueueOperation(accountId: 'a1', operationType: 'flag', targetId: 'm1', payload: {'flagged': false});
    final r = (await rows()).single;
    expect(r.id, first.id, reason: 'та же запись — место в очереди сохранено');
    expect(r.retryCount, 0);
    expect(payloadOf(r)['flagged'], isFalse);
  });

  test('операция без данных — пустой объект, а не null', () async {
    await sync.enqueueOperation(accountId: 'a1', operationType: 'delete', targetId: 'm9');
    expect(payloadOf((await rows()).single), isEmpty);
  });
}

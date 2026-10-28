// lib/features/notes/providers/notes_provider.dart
// Провайдеры заметок: список (реактивный из БД) и операции CRUD.

import 'dart:async';

import 'package:drift/drift.dart' show Value, OrderingTerm, OrderingMode, InsertMode, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../settings/providers/account_groups_provider.dart';
import '../../../data/providers/database_provider.dart';
import '../../mail/providers/mail_providers.dart';
import '../../settings/providers/module_settings_provider.dart';
import '../../../services/mail/engine/mail_engine_service.dart';

/// Реактивный список заметок активного аккаунта (не удалённых).
final notesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  final account = ref.watch(activeAccountProvider);
  final sortByModified = ref.watch(moduleSettingsProvider).notesSortByModified;

  final query = db.select(db.notes)
    ..where((n) => n.isDeleted.equals(false))
    ..orderBy([(n) => OrderingTerm(
        expression: sortByModified ? n.modifiedAt : n.createdAt,
        mode: OrderingMode.desc)]);

  // Если аккаунт выбран — фильтруем по нему, иначе показываем все локальные.
  if (account != null) {
    // Группа задаёт область так же, как в почте и календаре. Заметки без
    // привязки к аккаунту (accountId == null) видны всегда: это личные записи
    // пользователя, а не почта конкретного ящика.
    final groupIds = ref.watch(activeGroupAccountIdsProvider);
    if (groupIds.isEmpty) {
      query.where((n) => n.accountId.equals(account.id) | n.accountId.isNull());
    } else {
      query.where((n) => n.accountId.isIn(groupIds) | n.accountId.isNull());
    }
  }
  return query.watch();
});

/// Сервис операций над заметками (CRUD с порядком «сначала БД, потом сервер»).
class NotesNotifier {
  final Ref _ref;
  NotesNotifier(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  /// Создать заметку. Сохраняем локально сразу (оптимистично),
  /// серверная синхронизация выполняется отдельно при наличии соединения.
  Future<String> create({required String title, required String body, String? accountId}) async {
    final now = DateTime.now().toUtc();
    final id = 'note_${now.millisecondsSinceEpoch}';
    await _db.into(_db.notes).insert(
          NotesCompanion.insert(
            id: id,
            accountId: Value(accountId),
            title: Value(title),
            body: Value(body),
            createdAt: now,
            modifiedAt: now,
            isLocallyModified: const Value(true),
          ),
          mode: InsertMode.insertOrReplace,
        );
    unawaited(_push(accountId)); // экран закрывается сразу, сеть — в фоне
    return id;
  }

  /// Выгрузка локальных правок заметок аккаунта (создание, изменение,
  /// удаление). Раньше на сервер уходило только создание, и созданная
  /// заметка после синхронизации появлялась второй раз. Без сети строки
  /// остаются «изменёнными» и уходят при следующей синхронизации.
  Future<void> _push(String? accountId) async {
    if (accountId == null) return;
    try {
      final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
      if (account == null) return;
      await _ref.read(mailEngineServiceProvider).pushPendingNotes(account);
    } catch (_) {/* повторится при синхронизации */}
  }

  /// Обновить заметку.
  Future<void> update(String id, {String? title, String? body}) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        body: body != null ? Value(body) : const Value.absent(),
        modifiedAt: Value(DateTime.now().toUtc()),
        isLocallyModified: const Value(true),
      ),
    );
    unawaited(getById(id).then((n) => _push(n?.accountId)));
  }

  /// Удалить заметку (мягко — помечаем удалённой для синхронизации,
  /// затем физически удаляем после успешной отправки на сервер).
  Future<void> delete(String id) async {
    // Узнаём serverId до пометки удаления — нужен для серверного удаления EAS.
    final note = await getById(id);
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        isLocallyModified: const Value(true),
        modifiedAt: Value(DateTime.now().toUtc()),
      ),
    );
    // Личная заметка без аккаунта — на сервер не уходит, удаляем сразу.
    if (note?.accountId == null) {
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
      return;
    }
    // Серверное удаление; без сети — при следующей синхронизации.
    unawaited(_push(note?.accountId));
  }

  /// Получить заметку по id.
  Future<Note?> getById(String id) {
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }
}

final notesNotifierProvider = Provider<NotesNotifier>((ref) => NotesNotifier(ref));

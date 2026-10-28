// lib/services/mail/folder_actions_service.dart
// Действия над папкой целиком: «пометить всё прочитанным», «очистить»
// (корзина, спам). Раньше в меню папок бокового меню эти пункты только
// закрывали шторку, а рабочие версии жили внутри экрана списка писем и
// брали лишь загруженные в список письма.
//
// Здесь письма берутся из базы по папке — все, а не первая страница.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import 'email_actions_service.dart';
import 'engine/mail_engine_service.dart';

final folderActionsProvider = Provider<FolderActionsService>((ref) => FolderActionsService(ref));

class FolderActionsService {
  final Ref _ref;
  FolderActionsService(this._ref);

  /// Пометить прочитанными все непрочитанные письма папки. Возвращает число писем.
  Future<int> markAllRead(AccountModel account, FolderModel folder) async {
    final db = _ref.read(databaseProvider);
    final rows = await (db.select(db.emails)
          ..where((e) =>
              e.accountId.equals(account.id) &
              e.folderId.equals(folder.id) &
              e.isRead.equals(false)))
        .map((r) => r.id)
        .get();
    if (rows.isEmpty) return 0;
    await _ref.read(emailActionsProvider).batchSetRead(account, rows, folder.id, true);
    return rows.length;
  }

  /// Безвозвратно удалить все письма папки (корзина, спам) на сервере и
  /// локально. Возвращает (удалено, всего).
  Future<(int, int)> emptyFolder(AccountModel account, FolderModel folder) async {
    final db = _ref.read(databaseProvider);
    final ids = await (db.select(db.emails)
          ..where((e) => e.accountId.equals(account.id) & e.folderId.equals(folder.id)))
        .map((r) => r.id)
        .get();
    if (ids.isEmpty) return (0, 0);
    var done = const <String>[];
    try {
      done = await _ref
          .read(mailEngineServiceProvider)
          .emptyTrash(account, ids, trashFolderId: folder.id);
    } catch (e) {
      AppLogger.warning('Очистка папки ${folder.displayName}: $e');
    }
    if (done.isNotEmpty) {
      for (var i = 0; i < done.length; i += 500) {
        final part = done.sublist(i, i + 500 > done.length ? done.length : i + 500);
        await (db.delete(db.emails)
              ..where((e) => e.accountId.equals(account.id) & e.id.isIn(part)))
            .go();
      }
    }
    return (done.length, ids.length);
  }
}

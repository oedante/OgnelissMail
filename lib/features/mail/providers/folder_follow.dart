// lib/features/mail/providers/folder_follow.dart
// Смена ящика, когда открыта папка (2.6.8, замечание владельца 22.11.2026:
// «если ты в почтовом ящике стоишь в какой-то папке и меняешь ящик, то
// письма не отображаются»). Выбранной оставалась папка прежнего ящика: в
// новом её нет — заголовок «Входящие», а лента пустая.
//
// Теперь — такая же папка нового ящика: системная — того же вида
// («Отправленные» → «Отправленные»), своя — с тем же названием. Нет такой —
// «домой»: «Входящие» или «Вся почта», как в «Открывать при запуске».

import '../../../data/models/folder_model.dart';

/// Куда перейти в новом ящике.
sealed class FolderFollow {
  const FolderFollow();
}

/// Папка нового ящика.
class FollowFolder extends FolderFollow {
  final String id;
  const FollowFolder(this.id);
  @override
  bool operator ==(Object other) => other is FollowFolder && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'FollowFolder($id)';
}

/// «Вся почта».
class FollowAllMail extends FolderFollow {
  const FollowAllMail();
  @override
  bool operator ==(Object other) => other is FollowAllMail;
  @override
  int get hashCode => 1;
}

/// Выбранная папка уже есть в новом ящике (тот же id: «INBOX» у IMAP) —
/// ничего не менять.
class FollowStay extends FolderFollow {
  const FollowStay();
  @override
  bool operator ==(Object other) => other is FollowStay;
  @override
  int get hashCode => 2;
}

/// Куда перейти: [selectedId] — папка, открытая в прежнем ящике; [old] —
/// она сама (null — не найдена); [target] — папки нового ящика;
/// [homeInbox] — «Открывать при запуске: Входящие».
FolderFollow followFolder({
  required String selectedId,
  required FolderModel? old,
  required List<FolderModel> target,
  required bool homeInbox,
}) {
  if (target.any((f) => f.id == selectedId && (old == null || f.type == old.type))) return const FollowStay();
  FolderModel? pick;
  if (old != null) {
    if (old.type != FolderType.custom) {
      final same = [for (final f in target) if (f.type == old.type) f];
      // Верхнего уровня — первой («Входящие/Архив 2019» после «Архива»).
      pick = same.where((f) => (f.parentId ?? '').isEmpty).firstOrNull ?? same.firstOrNull;
    } else {
      final name = old.displayName.trim().toLowerCase();
      pick = target
          .where((f) => f.type == FolderType.custom && f.displayName.trim().toLowerCase() == name)
          .firstOrNull;
    }
  }
  if (pick != null) return FollowFolder(pick.id);
  if (homeInbox) {
    final inbox = target.where((f) => f.type == FolderType.inbox).firstOrNull;
    if (inbox != null) return FollowFolder(inbox.id);
  }
  return const FollowAllMail();
}

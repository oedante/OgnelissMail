// lib/data/models/folder_model.dart

enum FolderType { inbox, sent, drafts, trash, junk, archive, outbox, custom }

class FolderModel {
  final String id;
  final String accountId;
  final String? parentId;
  final String displayName;
  final FolderType type;
  final String? serverPath;
  final int unreadCount;
  final int totalCount;
  final bool showInUnified;
  final bool isFavorite;
  final int sortOrder;
  final bool isSynced;
  final String? iconName;

  const FolderModel({
    required this.id, required this.accountId, this.parentId,
    required this.displayName, this.type = FolderType.custom,
    this.serverPath, this.unreadCount = 0, this.totalCount = 0,
    this.showInUnified = true, this.isFavorite = false,
    this.sortOrder = 0, this.isSynced = true, this.iconName,
  });

  bool get isSystem => type != FolderType.custom;

  /// Попадает ли папка во «Всю почту» по умолчанию: входящие, отправленные,
  /// архив и свои папки — да; черновики, исходящие, корзина, спам — нет.
  /// Одно правило для IMAP, EWS и ActiveSync.
  ///
  /// Отправленные во «Всей почте» с 06.10.2026: лента показывает переписку
  /// целиком, а не только входящую половину. Непрочитанными они не бывают,
  /// поэтому на счётчики не влияют (счётчики их и так исключают по типу).
  static bool unifiedByDefault(FolderType t) => !const {
        FolderType.drafts, FolderType.outbox,
        FolderType.trash, FolderType.junk,
      }.contains(t);
}

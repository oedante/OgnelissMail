// lib/features/mail/providers/folder_names.dart
// Имя папки для людей — по ТИПУ папки, а не по имени с сервера: сервер
// отдаёт «INBOX», «Sent», «Отправленные», «Trash», «Корзина», «Bin»… Одно
// и то же имя в панели папок, в заголовке ленты и при «Переместить»
// (1.10.5: у Gmail заголовок ленты был «INBOX», а в панели — «Входящие»).

import '../../../data/models/folder_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/special_folders.dart';

String localizedFolderName(FolderModel folder, AppLocalizations l10n) {
  switch (folder.type) {
    case FolderType.inbox:
      return l10n.inbox;
    case FolderType.sent:
      return l10n.tr('sent');
    case FolderType.drafts:
      return l10n.tr('drafts');
    case FolderType.trash:
      return l10n.tr('trash');
    // «Спам» и «Архив» — своим названием, только если у папки стандартное
    // имя на каком-нибудь языке: выбранная вручную «Старое» (1.7.2+106) так
    // и называется «Старое».
    case FolderType.junk:
      return SpecialFolders.typeByName(folder.displayName) == FolderType.junk ? l10n.tr('junk') : folder.displayName;
    case FolderType.archive:
      return SpecialFolders.typeByName(folder.displayName) == FolderType.archive
          ? l10n.tr('archive')
          : folder.displayName;
    case FolderType.outbox:
      return l10n.tr('outbox');
    case FolderType.custom:
      return folder.displayName; // пользовательская — как на сервере
  }
}

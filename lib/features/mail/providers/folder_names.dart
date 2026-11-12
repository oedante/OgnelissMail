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

/// Имя папки по её названию с сервера — когда самой папки под рукой нет:
/// плашка папки у письма в ленте «Вся почта» (2.3.2, замечание владельца
/// 11.11.2026: у писем Яндекса плашка «Sent», а рядом — «Входящие»).
/// Стандартные папки — на языке приложения, остальные — как на сервере.
String localizedFolderLabel(String name, AppLocalizations l10n) {
  final n = name.trim();
  final key = n.toLowerCase().replaceAll('ё', 'е');
  // У Gmail стандартные папки лежат в «[Gmail]/…».
  final leaf = key.contains('/') ? key.substring(key.lastIndexOf('/') + 1) : key;
  if (leaf == 'inbox' || leaf == 'входящие') return l10n.inbox;
  if (_sentNames.contains(leaf)) return l10n.tr('sent');
  if (_draftNames.contains(leaf)) return l10n.tr('drafts');
  if (_trashNames.contains(leaf)) return l10n.tr('trash');
  if (_outboxNames.contains(leaf)) return l10n.tr('outbox');
  switch (SpecialFolders.typeByName(n)) {
    case FolderType.junk:
      return l10n.tr('junk');
    case FolderType.archive:
      return l10n.tr('archive');
    default:
      return n;
  }
}

const _sentNames = {'sent', 'sent items', 'sent messages', 'sent mail', 'отправленные'};
const _draftNames = {'drafts', 'draft', 'черновики'};
const _trashNames = {'trash', 'deleted items', 'deleted messages', 'bin', 'корзина', 'удаленные'};
const _outboxNames = {'outbox', 'исходящие'};

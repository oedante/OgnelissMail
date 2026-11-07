// lib/features/mail/widgets/move_folder_picker.dart
// «Переместить в…» — выбор папки для одного письма: лента (свайп и карточка
// по удержанию), письмо (панель команд и «Ещё») и беседа (карточка письма).
// 1.15.0, замечание владельца 07.11.2026: в беседе и в самом письме кнопки
// «Переместить» не было. Раньше один и тот же выбор был написан в ленте и в
// письме по отдельности.

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/folder_icons.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../providers/folder_names.dart';
import '../providers/mail_providers.dart' show folderFromRow;

/// Папка, куда переместить [email]: карточка с папками ящика ЭТОГО письма
/// (между ящиками разных серверов письмо не переносится), без папки, где
/// оно лежит. null — выбор закрыли.
Future<String?> pickMoveFolder(BuildContext context, WidgetRef ref, EmailModel email) async {
  final db = ref.read(databaseProvider);
  final rows =
      await (db.select(db.folders)
            ..where((f) => f.accountId.equals(email.accountId))
            ..orderBy([(f) => OrderingTerm(expression: f.sortOrder)]))
          .get();
  if (!context.mounted) return null;
  final l10n = AppLocalizations.of(context);
  final folders = [for (final r in rows) folderFromRow(r)];
  final id = await showChoiceSheet<String>(
    context,
    title: l10n.tr('moveToDots'),
    entries: [
      for (final f in folders.where((f) => f.id != email.folderId))
        AppMenuEntry(value: f.id, label: localizedFolderName(f, l10n), icon: folderIconOf(f)),
    ],
  );
  return folders.any((f) => f.id == id) ? id : null;
}

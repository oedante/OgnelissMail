// lib/features/archive/archive_providers.dart
// Данные архива Ogneliss для экранов (1.7.3): папки для меню, счётчики,
// поиск. Всё перечитывается, когда в архив записали новое
// (ArchiveVaultState.revision).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/folder_icons.dart';
import '../../data/models/folder_model.dart';
import '../../l10n/app_localizations.dart';
import '../../services/archive/archive_db.dart';
import '../../services/archive/archive_vault.dart';
import '../../services/mail/special_folders.dart';

/// Номер записи в архив (ArchiveVault.touch). Списки ниже следят и за
/// ним: база после записи та же, а Riverpod 3 не будит зависимых, если
/// значение провайдера не изменилось, — меню и счётчики архива стояли до
/// перезапуска (1.8.0, проверка обновления экранов).
final archiveRevisionProvider = Provider<int>((ref) => ref.watch(archiveVaultProvider).value?.revision ?? 0);

/// Папки архива (все ящики).
final archiveFoldersProvider = FutureProvider<List<ArchiveFolder>>((ref) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null) return const [];
  return db.folders();
});

/// Ящики, чьи данные лежат в архиве.
final archiveAccountsProvider = FutureProvider<List<ArchiveAccountInfo>>((ref) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null) return const [];
  return db.accounts();
});

/// Ящик архива для ящика приложения (1.8.12, замечание 29.10.2026: в одном
/// архиве — ящики с разными папками, в меню — только выбранный). Тот же id,
/// а после объединения с копией с другого устройства — тот же адрес (копия
/// приходит под своим id, ArchiveDb.resolveAccount сводит её по адресу).
ArchiveAccountInfo? archiveAccountOf(List<ArchiveAccountInfo> all, {required String id, required String email}) {
  final e = email.trim().toLowerCase();
  return all.where((a) => a.id == id).firstOrNull ??
      (e.isEmpty ? null : all.where((a) => a.email.trim().toLowerCase() == e).firstOrNull);
}

/// Сколько всего в архиве.
final archiveStatsProvider = FutureProvider<ArchiveStats?>((ref) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null) return null;
  return db.stats();
});

/// Снимки настроек приложения в архиве (новые сверху).
final archiveSettingsSnapshotsProvider = FutureProvider<List<ArchiveSettingsSnapshot>>((ref) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null) return const [];
  return db.settingsSnapshots();
});

/// Сколько писем архива подходит под запрос поиска почты (строка «В архиве
/// Ogneliss: N» над результатами).
final archiveSearchCountProvider = FutureProvider.autoDispose.family<int, String>((ref, q) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null || q.trim().length < 2) return 0;
  try {
    return await db.searchCount(q);
  } catch (_) {
    return 0;
  }
});

/// Папка архива как папка ящика — для значка и названия.
FolderModel archiveFolderModel(ArchiveFolder f) => FolderModel(
      id: '${f.id}',
      accountId: f.accountId,
      displayName: f.name,
      type: FolderType.values.where((t) => t.name == f.type).firstOrNull ?? FolderType.custom,
    );

/// Название папки архива: системные папки — на языке интерфейса.
String archiveFolderLabel(ArchiveFolder f, AppLocalizations l10n) {
  final m = archiveFolderModel(f);
  switch (m.type) {
    case FolderType.inbox:
      return l10n.inbox;
    case FolderType.sent:
      return l10n.tr('sent');
    case FolderType.drafts:
      return l10n.tr('drafts');
    case FolderType.trash:
      return l10n.tr('trash');
    case FolderType.archive:
      return SpecialFolders.typeByName(f.name) == FolderType.archive ? l10n.tr('archive') : f.name;
    case FolderType.junk:
      return SpecialFolders.typeByName(f.name) == FolderType.junk ? l10n.tr('junk') : f.name;
    case FolderType.outbox:
      return l10n.tr('outbox');
    case FolderType.custom:
      return f.name;
  }
}

IconData archiveFolderIcon(ArchiveFolder f) => folderIconOf(archiveFolderModel(f));

/// Дерево папок архива: корни и дети по родителю, с числом писем в ветке.
class ArchiveFolderTree {
  final List<ArchiveFolder> roots;
  final Map<int, List<ArchiveFolder>> children;
  final Map<int, int> branchCount;
  const ArchiveFolderTree(this.roots, this.children, this.branchCount);

  static ArchiveFolderTree build(List<ArchiveFolder> all, String accountId) {
    final mine = [for (final f in all) if (f.accountId == accountId) f];
    final ids = {for (final f in mine) f.id};
    final children = <int, List<ArchiveFolder>>{};
    final roots = <ArchiveFolder>[];
    for (final f in mine) {
      final p = f.parentId;
      if (p != null && ids.contains(p)) {
        (children[p] ??= []).add(f);
      } else {
        roots.add(f);
      }
    }
    int rank(ArchiveFolder f) => switch (f.type) {
          'inbox' => 0,
          'sent' => 1,
          'archive' => 2,
          _ => 3,
        };
    int cmp(ArchiveFolder a, ArchiveFolder b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    roots.sort(cmp);
    for (final l in children.values) {
      l.sort(cmp);
    }
    final branch = <int, int>{};
    int count(ArchiveFolder f) =>
        branch[f.id] ??= f.count + (children[f.id] ?? const <ArchiveFolder>[]).fold<int>(0, (s, c) => s + count(c));
    for (final f in mine) {
      count(f);
    }
    return ArchiveFolderTree(roots, children, branch);
  }
}

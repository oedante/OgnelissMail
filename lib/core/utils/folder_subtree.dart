// lib/core/utils/folder_subtree.dart
// Папка и все её подпапки (1.8.0, проверка обновления экранов: подпапки
// удалённой папки оставались в базе и показывались в корне ящика до
// следующей синхронизации папок).

/// id папки [rootId] и всех её потомков: по родителю ([parentOf]) и — у
/// IMAP, где id — путь, — по началу пути («Работа/2026», «Работа.2026»).
Set<String> folderSubtreeIds(Map<String, String?> parentOf, String rootId) {
  final ids = <String>{rootId};
  var grew = true;
  while (grew) {
    grew = false;
    for (final e in parentOf.entries) {
      if (ids.contains(e.key)) continue;
      final p = e.value;
      if ((p != null && ids.contains(p)) || e.key.startsWith('$rootId/') || e.key.startsWith('$rootId.')) {
        ids.add(e.key);
        grew = true;
      }
    }
  }
  return ids;
}

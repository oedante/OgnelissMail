// lib/core/utils/reorder_index.dart
//
// Перетаскивание в списках — через ReorderableListView.onReorder (1.10.5):
// новое onReorderItem (Flutter 3.44+) нет во Flutter для ОС Аврора (3.41),
// а код должен собираться и там (docs/guides/AURORA.md). onReorder отдаёт
// место вставки до удаления перетаскиваемого — здесь оно пересчитывается в
// индекс после удаления (как у onReorderItem). Когда Flutter для «Авроры»
// догонит 3.44 — вернуть onReorderItem и убрать этот пересчёт.

/// Индекс, на который встаёт элемент [oldIndex], уже без него в списке.
int reorderTarget(int oldIndex, int newIndex) => newIndex > oldIndex ? newIndex - 1 : newIndex;

// lib/features/mail/folder_order.dart
// Вид дерева папок в боковом меню (1.6.10, просьба владельца 14.10.2026):
//  · свой порядок папок — по умолчанию системные папки в порядке ящика,
//    свои — по алфавиту; пользователь может расставить папки одного уровня
//    как ему удобно;
//  · «Не отображать несинхронизируемые папки» — выключенные в «Синхронизации
//    папок» папки не показываются в меню (если в них нет включённых подпапок).
// Это вид меню, а не данные ящика: хранится в настройках телефона, на
// сервере порядок папок не меняется.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/folder_model.dart';
import '../../data/providers/shared_prefs_provider.dart';

const _kOrder = 'drawer_folder_order_v1';
const _kHideUnsynced = 'drawer_hide_unsynced_v1';

/// Папки одного уровня в сохранённом порядке [saved] (id папок). Папок, которых
/// нет в сохранённом списке (новые), — после расставленных, в порядке
/// [defaults]. Пропавшие с сервера id пропускаются.
List<FolderModel> applyFolderOrder(List<FolderModel> defaults, List<String>? saved) {
  if (saved == null || saved.isEmpty) return defaults;
  final pos = <String, int>{for (var i = 0; i < saved.length; i++) saved[i]: i};
  final placed = [for (final f in defaults) if (pos.containsKey(f.id)) f]
    ..sort((a, b) => pos[a.id]!.compareTo(pos[b.id]!));
  return [...placed, for (final f in defaults) if (!pos.containsKey(f.id)) f];
}

/// Папки для меню: без несинхронизируемых, у которых нет синхронизируемых
/// подпапок (иначе подпапка осталась бы без родителя и ушла бы в корень).
List<FolderModel> withoutUnsynced(List<FolderModel> all) {
  final kids = <String, List<FolderModel>>{};
  for (final f in all) {
    final p = f.parentId;
    if (p != null && p != f.id) (kids[p] ??= []).add(f);
  }
  final keep = <String, bool>{};
  final visiting = <String>{};
  bool visible(FolderModel f) {
    final known = keep[f.id];
    if (known != null) return known;
    if (!visiting.add(f.id)) return f.isSynced; // цикл в parentId
    var v = f.isSynced;
    for (final c in kids[f.id] ?? const <FolderModel>[]) {
      if (visible(c)) v = true;
    }
    return keep[f.id] = v;
  }

  return [for (final f in all) if (visible(f)) f];
}

/// Сохранённый порядок: ключ «аккаунт|родитель» ('' — корень ящика) →
/// id папок по порядку.
class FolderOrderNotifier extends Notifier<Map<String, List<String>>> {
  static String key(String accountId, String? parentId) => '$accountId|${parentId ?? ''}';

  @override
  Map<String, List<String>> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_kOrder);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: [for (final v in e.value as List) '$v']};
    } catch (_) {
      return const {};
    }
  }

  List<String>? of(String accountId, String? parentId) => state[key(accountId, parentId)];

  Future<void> set(String accountId, String? parentId, List<String> ids) =>
      _save({...state, key(accountId, parentId): ids});

  /// «По умолчанию»: системные по порядку ящика, свои — по алфавиту.
  Future<void> reset(String accountId, String? parentId) =>
      _save({...state}..remove(key(accountId, parentId)));

  Future<void> _save(Map<String, List<String>> next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setString(_kOrder, jsonEncode(next));
  }
}

final folderOrderProvider =
    NotifierProvider<FolderOrderNotifier, Map<String, List<String>>>(FolderOrderNotifier.new);

/// Ящики, у которых несинхронизируемые папки скрыты в меню.
class HideUnsyncedFoldersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.read(sharedPrefsProvider).getStringList(_kHideUnsynced) ?? const []).toSet();

  Future<void> set(String accountId, bool hide) async {
    final next = {...state};
    hide ? next.add(accountId) : next.remove(accountId);
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(_kHideUnsynced, next.toList());
  }
}

final hideUnsyncedFoldersProvider =
    NotifierProvider<HideUnsyncedFoldersNotifier, Set<String>>(HideUnsyncedFoldersNotifier.new);

// lib/features/settings/providers/account_groups_provider.dart
//
// Группы аккаунтов: «Рабочие», «Личные» и любые другие.
//
// Зачем. Сейчас есть только два режима: один ящик или все сразу. Когда у
// человека свой рабочий ящик, пара делегированных и личная почта, ни один из
// режимов не подходит: в «одном» не видно всей рабочей картины, во «всех» —
// личное мешается с рабочим.
//
// Группа — это просто именованный набор идентификаторов аккаунтов. Отдельной
// таблицы не заводим: данных мало, меняются редко, и хранение в prefs
// переживает миграции схемы без дополнительной работы.
//
// ВАЖНО: выбранная группа должна действовать сквозь ВСЕ модули — почту,
// календарь, контакты, заметки, дашборд. Иначе выйдет рассогласование: письма
// отфильтрованы, а встречи и статистика показываются от всех аккаунтов, и
// человек делает выводы по смешанным данным.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

class AccountGroup {
  final String id;
  final String name;
  final List<String> accountIds;

  const AccountGroup({
    required this.id,
    required this.name,
    required this.accountIds,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'accounts': accountIds};

  factory AccountGroup.fromJson(Map<String, dynamic> j) => AccountGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        accountIds: (j['accounts'] as List?)?.cast<String>() ?? const [],
      );

  AccountGroup copyWith({String? name, List<String>? accountIds}) =>
      AccountGroup(
        id: id,
        name: name ?? this.name,
        accountIds: accountIds ?? this.accountIds,
      );
}

class AccountGroupsNotifier extends StateNotifier<List<AccountGroup>> {
  final SharedPreferences _prefs;

  AccountGroupsNotifier(this._prefs) : super(const []) {
    _load();
  }

  static const _key = 'account_groups';

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .map((e) => AccountGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Повреждённые данные не должны мешать запуску: просто считаем, что
      // групп нет — пользователь создаст заново.
      state = const [];
    }
  }

  Future<void> _save() async {
    await _prefs.setString(
        _key, jsonEncode(state.map((g) => g.toJson()).toList()));
  }

  Future<void> add(String name, List<String> accountIds) async {
    final g = AccountGroup(
      id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      accountIds: accountIds,
    );
    state = [...state, g];
    await _save();
  }

  Future<void> update(AccountGroup group) async {
    state = [
      for (final g in state) if (g.id == group.id) group else g,
    ];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((g) => g.id != id).toList();
    await _save();
  }

  /// Убрать удалённый аккаунт из всех групп: иначе группа будет ссылаться на
  /// несуществующий ящик и молча отфильтровывать всё.
  Future<void> forgetAccount(String accountId) async {
    var changed = false;
    final next = <AccountGroup>[];
    for (final g in state) {
      if (g.accountIds.contains(accountId)) {
        changed = true;
        next.add(g.copyWith(
            accountIds: g.accountIds.where((id) => id != accountId).toList()));
      } else {
        next.add(g);
      }
    }
    if (!changed) return;
    // Группы, оставшиеся без аккаунтов, удаляем: пустая группа показывала бы
    // пустой ящик без объяснения причины.
    state = next.where((g) => g.accountIds.isNotEmpty).toList();
    await _save();
  }
}

final accountGroupsProvider =
    StateNotifierProvider<AccountGroupsNotifier, List<AccountGroup>>(
        (ref) => AccountGroupsNotifier(ref.watch(sharedPrefsProvider)));

/// Идентификатор активной группы. null — режим без группировки (один аккаунт
/// или все сразу, как было раньше).
final activeGroupIdProvider = StateProvider<String?>((ref) => null);

/// Аккаунты активной группы. Пустой список означает «группа не выбрана» —
/// вызывающий код в этом случае работает как прежде.
///
/// Единая точка: все модули (почта, календарь, контакты, заметки, дашборд)
/// должны спрашивать именно её, иначе фильтрация разойдётся между разделами.
final activeGroupAccountIdsProvider = Provider<List<String>>((ref) {
  final id = ref.watch(activeGroupIdProvider);
  if (id == null) return const [];
  final group = ref
      .watch(accountGroupsProvider)
      .where((g) => g.id == id)
      .firstOrNull;
  return group?.accountIds ?? const [];
});

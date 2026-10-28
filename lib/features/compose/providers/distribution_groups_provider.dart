// lib/features/compose/providers/distribution_groups_provider.dart
// Группы рассылки (локальные, в SharedPreferences): именованные списки получателей
// для быстрой вставки в поле «Кому». Без миграции БД — хранится как JSON.

import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

class GroupMember {
  final String email;
  final String? name;
  const GroupMember({required this.email, this.name});
  Map<String, dynamic> toJson() => {'email': email, if (name != null) 'name': name};
  factory GroupMember.fromJson(Map<String, dynamic> j) =>
      GroupMember(email: j['email']?.toString() ?? '', name: j['name']?.toString());
}

class DistributionGroup {
  final String name;
  final List<GroupMember> members;
  const DistributionGroup({required this.name, required this.members});
  Map<String, dynamic> toJson() => {'name': name, 'members': members.map((m) => m.toJson()).toList()};
  factory DistributionGroup.fromJson(Map<String, dynamic> j) => DistributionGroup(
        name: j['name']?.toString() ?? '',
        members: ((j['members'] as List?) ?? [])
            .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

const _kGroupsKey = 'distribution_groups_v1';

class DistributionGroupsNotifier extends StateNotifier<List<DistributionGroup>> {
  final SharedPreferences _p;
  DistributionGroupsNotifier(this._p) : super(_load(_p));

  static List<DistributionGroup> _load(SharedPreferences p) {
    final raw = p.getString(_kGroupsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => DistributionGroup.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    await _p.setString(_kGroupsKey, jsonEncode(state.map((g) => g.toJson()).toList()));
  }

  /// Создать или заменить группу с данным именем.
  Future<void> saveGroup(String name, List<GroupMember> members) async {
    final n = name.trim();
    if (n.isEmpty || members.isEmpty) return;
    final others = state.where((g) => g.name.toLowerCase() != n.toLowerCase()).toList();
    state = [...others, DistributionGroup(name: n, members: members)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _persist();
  }

  Future<void> deleteGroup(String name) async {
    state = state.where((g) => g.name.toLowerCase() != name.toLowerCase()).toList();
    await _persist();
  }
}

final distributionGroupsProvider =
    StateNotifierProvider<DistributionGroupsNotifier, List<DistributionGroup>>((ref) {
  return DistributionGroupsNotifier(ref.watch(sharedPrefsProvider));
});

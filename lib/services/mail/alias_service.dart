// lib/services/mail/alias_service.dart
// Алиасы (псевдонимы) отправки:
// - Несколько адресов отправителя для одного аккаунта
// - Выбор при создании письма
// - Хранение в БД

import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';
import 'own_addresses.dart';

final aliasServiceProvider = StateNotifierProvider<AliasNotifier, Map<String, List<String>>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return AliasNotifier(prefs);
});

/// Map<accountId, List<aliasEmail>>
class AliasNotifier extends StateNotifier<Map<String, List<String>>> {
  final SharedPreferences _prefs;
  static const _key = 'email_aliases';

  AliasNotifier(this._prefs) : super({}) {
    _load();
  }

  void _load() {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        state = m.map((k, v) => MapEntry(k, (v as List).cast<String>()));
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode(state));
    // Алиасы — тоже «свои» адреса (антифишинг, свои письма, своё фото).
    OwnAddresses.refreshAliases();
  }

  /// Добавить алиас для аккаунта
  Future<void> addAlias(String accountId, String aliasEmail) async {
    final current = state[accountId] ?? [];
    if (!current.contains(aliasEmail)) {
      state = {...state, accountId: [...current, aliasEmail]};
      await _save();
    }
  }

  /// Удалить алиас
  Future<void> removeAlias(String accountId, String aliasEmail) async {
    final current = state[accountId] ?? [];
    state = {...state, accountId: current.where((e) => e != aliasEmail).toList()};
    await _save();
  }

  /// Получить все адреса отправки для аккаунта (основной + алиасы)
  List<String> getSenderAddresses(String accountId, String primaryEmail) {
    return [primaryEmail, ...(state[accountId] ?? [])];
  }
}

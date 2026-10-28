// lib/features/settings/providers/categories_provider.dart
// Пользовательские категории писем (для тегов/категорий и фильтров). Хранятся в
// SharedPreferences, редактируются в настройках, поддерживают экспорт/импорт.
// По умолчанию — стандартный набор, подходящий всем пользователям.

import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

/// Стандартные категории «из коробки» — нейтральные, для любых пользователей.
const List<String> defaultCategories = [
  'Работа',
  'Финансы',
  'Проекты',
  'Задачи',
  'Путешествия',
  'Покупки',
  'Личное',
  'Рассылки',
  'IT',
  'Важное',
];

class CategoriesNotifier extends StateNotifier<List<String>> {
  final SharedPreferences _p;
  static const _key = 'user_categories_v1';

  CategoriesNotifier(this._p) : super(_load(_p));

  static List<String> _load(SharedPreferences p) {
    final stored = p.getStringList(_key);
    if (stored == null || stored.isEmpty) return List.of(defaultCategories);
    return stored;
  }

  Future<void> _persist() async => _p.setStringList(_key, state);

  Future<void> add(String name) async {
    final n = name.trim();
    if (n.isEmpty || state.contains(n)) return;
    state = [...state, n];
    await _persist();
  }

  Future<void> remove(String name) async {
    if (!state.contains(name)) return;
    state = state.where((c) => c != name).toList();
    await _persist();
  }

  Future<void> reorder(List<String> ordered) async {
    state = ordered;
    await _persist();
  }

  Future<void> resetToDefault() async {
    state = List.of(defaultCategories);
    await _persist();
  }

  /// Заменить весь список (используется импортом).
  Future<void> setAll(List<String> categories) async {
    final clean = categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    if (clean.isEmpty) return;
    state = clean;
    await _persist();
  }

  /// Сериализация настроек категорий в JSON (для экспорта).
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'type': 'ogneliss_categories',
        'version': 1,
        'categories': state,
      });

  /// Разобрать JSON экспортированных настроек. Возвращает список или null.
  static List<String>? parseImport(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['categories'] is List) {
        return (data['categories'] as List).map((e) => e.toString()).toList();
      }
      if (data is List) return data.map((e) => e.toString()).toList();
    } catch (_) {}
    return null;
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, List<String>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CategoriesNotifier(prefs);
});

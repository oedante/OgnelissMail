// lib/features/settings/providers/categories_provider.dart
// Пользовательские категории писем (для тегов/категорий и фильтров). Хранятся в
// SharedPreferences, редактируются в настройках, поддерживают экспорт/импорт.
// По умолчанию — стандартный набор, подходящий всем пользователям.

import 'dart:convert';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/category_colors.dart';
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

// ── Цвета категорий (2.7.5, замечание владельца 27.11.2026: «теги и
// категории — одно и то же, и не реализованы категории по цветам») ──

/// Палитра категорий — цвета категорий Outlook (красная, оранжевая,
/// жёлтая, зелёная, синяя, фиолетовая и др.).
const List<Color> categoryPalette = [
  Color(0xFFE74856), // красная
  Color(0xFFF7630C), // оранжевая
  Color(0xFFC19C00), // жёлтая (тёмная — читается на светлом фоне)
  Color(0xFF16C60C), // зелёная
  Color(0xFF0078D4), // синяя
  Color(0xFF8764B8), // фиолетовая
  Color(0xFF00B7C3), // бирюзовая
  Color(0xFF8E562E), // коричневая
  Color(0xFFE3008C), // розовая
  Color(0xFF498205), // оливковая
  Color(0xFF515C6B), // серо-синяя
  Color(0xFF7A7574), // серая
];

/// Стандартные категории Outlook по названию цвета (русский и английский
/// Outlook) — сразу своим цветом.
const Map<String, int> _outlookPresets = {
  'красная категория': 0, 'red category': 0,
  'оранжевая категория': 1, 'orange category': 1,
  'желтая категория': 2, 'жёлтая категория': 2, 'yellow category': 2,
  'зеленая категория': 3, 'зелёная категория': 3, 'green category': 3,
  'синяя категория': 4, 'blue category': 4,
  'фиолетовая категория': 5, 'purple category': 5,
};

/// Цвет категории: выбранный пользователем, цвет из Outlook (главный
/// список категорий ящика Exchange), стандартный Outlook по названию, иначе —
/// постоянный цвет палитры по названию.
Color categoryColor(String name, Map<String, int> chosen) {
  final c = chosen[name];
  if (c != null) return Color(c);
  final server = CategoryColors.serverColor(name);
  if (server != null) return server;
  final preset = _outlookPresets[name.trim().toLowerCase()];
  if (preset != null) return categoryPalette[preset];
  var h = 0;
  for (final u in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return categoryPalette[h % categoryPalette.length];
}

/// Выбранные цвета категорий: название → ARGB.
class CategoryColorsNotifier extends StateNotifier<Map<String, int>> {
  final SharedPreferences _p;
  static const _key = 'category_colors_v1';

  CategoryColorsNotifier(this._p) : super(_load(_p));

  static Map<String, int> _load(SharedPreferences p) {
    try {
      final raw = p.getString(_key);
      if (raw == null) return const {};
      return {for (final e in (jsonDecode(raw) as Map).entries) '${e.key}': (e.value as num).toInt()};
    } catch (_) {
      return const {};
    }
  }

  Future<void> set(String name, Color color) async {
    state = {...state, name: color.toARGB32()};
    await _p.setString(_key, jsonEncode(state));
  }

  /// Вернуть цвет по умолчанию (из Outlook или палитры).
  Future<void> clear(String name) async {
    if (!state.containsKey(name)) return;
    state = {...state}..remove(name);
    await _p.setString(_key, jsonEncode(state));
  }
}

final categoryColorsProvider = StateNotifierProvider<CategoryColorsNotifier, Map<String, int>>(
  (ref) => CategoryColorsNotifier(ref.watch(sharedPrefsProvider)),
);


// lib/services/mail/search_history_service.dart
//
// История поисковых запросов.
//
// В рабочей переписке ищут одно и то же по многу раз: фамилию коллеги, номер
// договора, название узла. Набирать заново с телефона неудобно, поэтому
// последние запросы предлагаются сразу при открытии поиска.
//
// Хранится локально в prefs: это пользовательские данные, наружу не уходят.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';

class SearchHistoryService {
  final SharedPreferences _prefs;
  SearchHistoryService(this._prefs);

  static const _key = 'search_history';

  /// Сколько запросов помним. Больше десятка превращается в свалку, в которой
  /// искать дольше, чем набрать заново.
  static const _maxItems = 10;

  List<String> get items => _prefs.getStringList(_key) ?? const [];

  /// Добавить запрос: дубли поднимаются наверх, а не копятся.
  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty || q.length < 2) return;
    final list = [...items];
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > _maxItems) list.removeRange(_maxItems, list.length);
    await _prefs.setStringList(_key, list);
  }

  Future<void> remove(String query) async {
    final list = [...items]..removeWhere((e) => e == query);
    await _prefs.setStringList(_key, list);
  }

  Future<void> clear() async => _prefs.remove(_key);
}

/// Провайдер истории поиска.
final searchHistoryProvider = Provider<SearchHistoryService>((ref) {
  return SearchHistoryService(ref.read(sharedPrefsProvider));
});

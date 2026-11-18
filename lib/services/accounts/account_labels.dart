// lib/services/accounts/account_labels.dart
// Название ящика, которое задаёт сам пользователь (2.6.1, просьба владельца
// 16.11.2026): «Работа», «Семья», «Магазин». Задано — показывается вместо
// короткой подписи из адреса в уведомлениях, напоминаниях и на экране почты
// (строка под заголовком, метка ящика в «Вся почта», меню ящиков).
//
// Хранится в настройках приложения по id ящика, а не в базе: новой колонки
// и миграции не нужно, а фоновая проверка почты (отдельный изолят) читает те
// же настройки при каждом запуске. Не длиннее [maxLength] знаков (букв с
// диакритикой и эмодзи — по одному): в шапке уведомления места мало.

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';

abstract final class AccountLabels {
  /// Не больше стольких знаков.
  static const maxLength = 24;
  static const _prefix = 'account_label_';

  /// Название, как его сохраняем: без управляющих символов и лишних
  /// пробелов, не длиннее [maxLength]; пустое — null.
  static String? clean(String? raw) {
    if (raw == null) return null;
    final s = raw
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f-\u009f\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) return null;
    final c = s.characters;
    return c.length <= maxLength ? s : c.take(maxLength).toString().trimRight();
  }

  /// Все названия: id ящика → название.
  static Map<String, String> read(SharedPreferences prefs) {
    final out = <String, String>{};
    for (final k in prefs.getKeys()) {
      if (!k.startsWith(_prefix)) continue;
      final v = clean(prefs.getString(k));
      if (v != null) out[k.substring(_prefix.length)] = v;
    }
    return out;
  }

  static String? of(SharedPreferences prefs, String accountId) => clean(prefs.getString('$_prefix$accountId'));

  /// Названия сейчас — для меню, которые строятся без провайдеров
  /// (выбор ящика в календаре, контактах, задачах). Ведёт
  /// [AccountLabelsNotifier].
  static Map<String, String> current = const {};

  /// Сохранить; пустое — убрать название.
  static Future<void> write(SharedPreferences prefs, String accountId, String? label) async {
    final v = clean(label);
    if (v == null) {
      await prefs.remove('$_prefix$accountId');
    } else {
      await prefs.setString('$_prefix$accountId', v);
    }
  }
}

class AccountLabelsNotifier extends StateNotifier<Map<String, String>> {
  AccountLabelsNotifier(this._prefs) : super(AccountLabels.read(_prefs)) {
    AccountLabels.current = state;
  }
  final SharedPreferences _prefs;

  Future<void> set(String accountId, String? label) async {
    await AccountLabels.write(_prefs, accountId, label);
    state = AccountLabels.read(_prefs);
    AccountLabels.current = state;
  }
}

/// Названия ящиков для экранов (меняются сразу после правки).
final accountLabelsProvider = StateNotifierProvider<AccountLabelsNotifier, Map<String, String>>(
    (ref) => AccountLabelsNotifier(ref.watch(sharedPrefsProvider)));

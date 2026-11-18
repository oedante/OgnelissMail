// lib/services/mail/greeting_mode.dart
// Приветствие в начале письма — своё для каждого ящика (настраивается на
// экране «Подписи» аккаунта):
//   off      — без приветствия;
//   hello    — «Добрый день!»;
//   helloName — «Добрый день, Имя Отчество,» (по умолчанию);
//   custom   — своё приветствие из списка «Свои приветствия» (18.11.2026,
//              просьба пользователей через владельца) — с полями
//              {обращение}, {время_суток} и другими (mail_tags.dart).
// Раньше приветствие было всегда и зависело от времени суток («Добрый
// вечер» в письме, которое прочтут утром), а для контактов в виде
// «Фамилия, Имя» обращение было только по имени — неформально для
// деловой переписки.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/shared_prefs_provider.dart';

enum GreetingMode { off, hello, helloName, custom }

class GreetingModeNotifier extends Notifier<Map<String, GreetingMode>> {
  static const _prefix = 'greeting_mode_';

  @override
  Map<String, GreetingMode> build() {
    final prefs = ref.read(sharedPrefsProvider);
    return {
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)))
        k.substring(_prefix.length):
            GreetingMode.values[(prefs.getInt(k) ?? 2).clamp(0, GreetingMode.values.length - 1)],
    };
  }

  GreetingMode of(String? accountId) =>
      accountId == null ? GreetingMode.helloName : (state[accountId] ?? GreetingMode.helloName);

  Future<void> set(String accountId, GreetingMode mode) async {
    state = {...state, accountId: mode};
    await ref.read(sharedPrefsProvider).setInt('$_prefix$accountId', mode.index);
  }
}

final greetingModeProvider =
    NotifierProvider<GreetingModeNotifier, Map<String, GreetingMode>>(GreetingModeNotifier.new);

/// Своё приветствие: текст с полями {…} (одна строка).
class CustomGreeting {
  final String id;
  final String text;
  const CustomGreeting({required this.id, required this.text});

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
  static CustomGreeting? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    final text = '${j['text'] ?? ''}'.trim();
    return id.isEmpty || text.isEmpty ? null : CustomGreeting(id: id, text: text);
  }
}

/// Свои приветствия — общие для всех ящиков; у ящика с режимом
/// [GreetingMode.custom] выбрано одно из них. В письме кнопка
/// «Приветствие» предлагает все.
class CustomGreetingsState {
  final List<CustomGreeting> items;

  /// Ящик → id своего приветствия по умолчанию.
  final Map<String, String> chosen;
  const CustomGreetingsState({this.items = const [], this.chosen = const {}});

  /// Своё приветствие ящика: выбранное, иначе первое; null — списка нет.
  CustomGreeting? forAccount(String? accountId) {
    if (items.isEmpty) return null;
    final id = accountId == null ? null : chosen[accountId];
    return items.where((g) => g.id == id).firstOrNull ?? items.first;
  }

  CustomGreeting? byId(String? id) => id == null ? null : items.where((g) => g.id == id).firstOrNull;
}

class CustomGreetingsNotifier extends Notifier<CustomGreetingsState> {
  static const _listKey = 'custom_greetings';
  static const _chosenPrefix = 'greeting_custom_';

  @override
  CustomGreetingsState build() {
    final prefs = ref.read(sharedPrefsProvider);
    var items = <CustomGreeting>[];
    try {
      final raw = prefs.getString(_listKey);
      if (raw != null) {
        items = [
          for (final j in jsonDecode(raw) as List)
            if (CustomGreeting.fromJson(j) case final g?) g,
        ];
      }
    } catch (_) {}
    return CustomGreetingsState(items: items, chosen: {
      for (final k in prefs.getKeys().where((k) => k.startsWith(_chosenPrefix)))
        k.substring(_chosenPrefix.length): prefs.getString(k) ?? '',
    });
  }

  Future<void> _saveList(List<CustomGreeting> items) async {
    state = CustomGreetingsState(items: items, chosen: state.chosen);
    await ref.read(sharedPrefsProvider).setString(_listKey, jsonEncode([for (final g in items) g.toJson()]));
  }

  /// Добавить; вернёт новое приветствие.
  Future<CustomGreeting> add(String text) async {
    final g = CustomGreeting(id: 'g${DateTime.now().microsecondsSinceEpoch}', text: _oneLine(text));
    await _saveList([...state.items, g]);
    return g;
  }

  Future<void> update(String id, String text) => _saveList([
        for (final g in state.items) g.id == id ? CustomGreeting(id: id, text: _oneLine(text)) : g,
      ]);

  Future<void> remove(String id) => _saveList([for (final g in state.items) if (g.id != id) g]);

  /// Своё приветствие ящика по умолчанию.
  Future<void> choose(String accountId, String id) async {
    state = CustomGreetingsState(items: state.items, chosen: {...state.chosen, accountId: id});
    await ref.read(sharedPrefsProvider).setString('$_chosenPrefix$accountId', id);
  }

  /// Приветствие — одна строка в начале письма.
  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
}

final customGreetingsProvider =
    NotifierProvider<CustomGreetingsNotifier, CustomGreetingsState>(CustomGreetingsNotifier.new);

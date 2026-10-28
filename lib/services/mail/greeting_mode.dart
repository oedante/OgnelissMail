// lib/services/mail/greeting_mode.dart
// Приветствие в начале письма — своё для каждого ящика (настраивается на
// экране «Подписи» аккаунта):
//   off      — без приветствия;
//   hello    — «Добрый день!»;
//   helloName — «Добрый день, Имя Отчество,» (по умолчанию).
// Раньше приветствие было всегда и зависело от времени суток («Добрый
// вечер» в письме, которое прочтут утром), а для контактов в виде
// «Фамилия, Имя» обращение было только по имени — неформально для
// деловой переписки.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/shared_prefs_provider.dart';

enum GreetingMode { off, hello, helloName }

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

// lib/features/mail/providers/start_screen.dart
// Начальный экран (2.7.4, решение владельца 26.11.2026): «Почта», «Мой день»
// или «Сводка ящиков» — один из трёх. С него приложение открывается, на него
// ведёт «Назад» с других разделов и из ленты, с него «Назад» — выход.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/shared_prefs_provider.dart';
import '../../settings/providers/settings_provider.dart';

enum StartScreen { mail, myDay, board }

class StartScreenNotifier extends Notifier<StartScreen> {
  static const prefKey = 'start_screen';

  @override
  StartScreen build() {
    final name = ref.read(sharedPrefsProvider).getString(prefKey);
    return StartScreen.values.where((v) => v.name == name).firstOrNull ?? StartScreen.mail;
  }

  Future<void> set(StartScreen v) async {
    state = v;
    await ref.read(sharedPrefsProvider).setString(prefKey, v.name);
  }
}

final startScreenProvider = NotifierProvider<StartScreenNotifier, StartScreen>(StartScreenNotifier.new);

/// Адрес начального экрана; «Мой день», выключенный в «Профиле», — почта.
String startScreenRoute(StartScreen s, {required bool myDayOn}) => switch (s) {
      StartScreen.myDay when myDayOn => '/my-day',
      StartScreen.board => '/accounts',
      _ => '/mail',
    };

/// Адрес начального экрана сейчас.
final startRouteProvider = Provider<String>((ref) => startScreenRoute(
      ref.watch(startScreenProvider),
      myDayOn: ref.watch(settingsProvider.select((s) => s.myDay)),
    ));

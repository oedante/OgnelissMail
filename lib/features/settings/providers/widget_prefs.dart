// lib/features/settings/providers/widget_prefs.dart
// Фон виджетов на рабочем столе (1.6.49, по образцу привычных календарей:
// сетка и встречи прямо на обоях). 0 — обычный, 1 — полупрозрачный (видны
// обои), 2 — без фона (текст прямо на обоях; цвет текста — по теме
// телефона, поэтому подходит для однотонных обоев). Android-виджеты читают
// значение сами при отрисовке (FlutterSharedPreferences, «flutter.widget_bg»).

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/shared_prefs_provider.dart';

class WidgetBackgroundNotifier extends Notifier<int> {
  static const key = 'widget_bg';

  @override
  int build() => (ref.read(sharedPrefsProvider).getInt(key) ?? 0).clamp(0, 2).toInt();

  Future<void> set(int v) async {
    state = v.clamp(0, 2).toInt();
    await ref.read(sharedPrefsProvider).setInt(key, state);
    // Перерисовать виджеты сразу, не дожидаясь новых данных.
    try {
      await const MethodChannel('ogneliss/widget').invokeMethod<void>('refresh');
    } catch (_) {}
  }
}

final widgetBackgroundProvider = NotifierProvider<WidgetBackgroundNotifier, int>(WidgetBackgroundNotifier.new);

/// Тема виджетов (1.7.0, замечание владельца 20.10.2026: «приложение в
/// светлой теме, а виджет — в тёмной»): 0 — как у телефона, 1 — светлая,
/// 2 — тёмная. Android читает «flutter.widget_theme» сам (у каждой разметки
/// виджета есть светлый и тёмный вариант, tool/dev/widget_themes.py), iPhone —
/// из общего контейнера App Group (ключ «widget_theme», передаётся здесь).
class WidgetThemeNotifier extends Notifier<int> {
  static const key = 'widget_theme';

  @override
  int build() => (ref.read(sharedPrefsProvider).getInt(key) ?? 0).clamp(0, 2).toInt();

  Future<void> set(int v) async {
    state = v.clamp(0, 2).toInt();
    await ref.read(sharedPrefsProvider).setInt(key, state);
    await pushToIos(state);
    try {
      await const MethodChannel('ogneliss/widget').invokeMethod<void>('refresh');
    } catch (_) {}
  }

  /// iPhone: значение — в App Group (расширение виджетов не видит настроек
  /// приложения). Вызывается и при запуске — на случай переустановки.
  static Future<void> pushToIos(int v) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await const MethodChannel('ogneliss/widget').invokeMethod<void>('save', {'key': key, 'json': '$v'});
    } catch (_) {}
  }
}

final widgetThemeProvider = NotifierProvider<WidgetThemeNotifier, int>(WidgetThemeNotifier.new);

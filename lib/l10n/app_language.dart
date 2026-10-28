// lib/l10n/app_language.dart
// Язык приложения для служб без доступа к настройкам (фоновая работа,
// подписи по умолчанию, быстрый ответ, подсказки ввода).

import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

import 'languages.g.dart';

/// Выбранный в настройках язык (s_locale), иначе системный, если такой язык
/// в приложении есть, иначе английский — как SettingsNotifier при запуске.
String appLanguageOf(SharedPreferences prefs) {
  bool known(String c) => kAppLanguages.any((l) => l.code == c);
  final saved = prefs.getString('s_locale');
  if (saved != null && known(saved)) return saved;
  final system = PlatformDispatcher.instance.locale.languageCode;
  return known(system) ? system : 'en';
}

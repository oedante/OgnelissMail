// lib/services/translation/translation_prefs.dart
//
// Перевод писем (1.9.x): что запомнить между письмами — недавние языки
// перевода своего письма и последний выбор «заменить / оставить оба».
// Это не настройки (их нет в «Настройках»), а память выбора.

import 'package:shared_preferences/shared_preferences.dart';

import 'translation_languages.dart';
import 'translation_text.dart';

class TranslationMemory {
  TranslationMemory._();

  static const _recentKey = 'tr_recent_targets';
  static const _modeKey = 'tr_compose_mode';

  static List<String> recent(SharedPreferences p) => p.getStringList(_recentKey) ?? const [];

  static Future<void> rememberTarget(SharedPreferences p, String lang) =>
      p.setStringList(_recentKey, pushRecent(recent(p), lang));

  static ComposeTranslateMode mode(SharedPreferences p) =>
      ComposeTranslateMode.values.where((m) => m.name == p.getString(_modeKey)).firstOrNull ??
      ComposeTranslateMode.replace;

  static Future<void> setMode(SharedPreferences p, ComposeTranslateMode m) => p.setString(_modeKey, m.name);

  /// Показ перевода входящего письма (1.10.5, «Настройки → Перевод»):
  /// заменить текст (по умолчанию) или оставить оба — тема и текст.
  static const readModeKey = 'tr_read_mode';

  static ComposeTranslateMode readMode(SharedPreferences? p) =>
      ComposeTranslateMode.values.where((m) => m.name == p?.getString(readModeKey)).firstOrNull ??
      ComposeTranslateMode.replace;

  static Future<void> setReadMode(SharedPreferences p, ComposeTranslateMode m) => p.setString(readModeKey, m.name);
}

// lib/services/mail/smart_compose_service.dart
// Smart Compose — автодополнение текста при написании письма.
// Основано на:
// - Частых фразах из отправленных писем
// - Предустановленных корпоративных шаблонах
// - Контексте (время суток, получатель, тема)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_language.dart';
import '../../l10n/strings_store.dart' show StringsStore;

final smartComposeProvider = Provider<SmartComposeService>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return SmartComposeService(prefs);
});

class SmartComposeSuggestion {
  final String text;
  final double confidence;
  final String source; // 'template', 'learned', 'context'

  const SmartComposeSuggestion({
    required this.text,
    this.confidence = 0.5,
    this.source = 'template',
  });
}

class SmartComposeService {
  final SharedPreferences _prefs;
  static const _key = 'smart_compose_phrases';

  /// Выученные фразы пользователя
  final Map<String, int> _learnedPhrases = {};

  /// Предустановленные корпоративные фразы
  static const Map<String, List<String>> _templates = {
    'добрый': ['Добрый день!', 'Добрый день, коллеги!'],
    'доброе': ['Доброе утро!'],
    'здравст': ['Здравствуйте!', 'Здравствуйте, уважаемые коллеги!'],
    'прошу': ['Прошу рассмотреть и согласовать.', 'Прошу принять к сведению.', 'Прошу предоставить информацию.'],
    'направ': ['Направляю для рассмотрения.', 'Направляю для ознакомления.', 'Направляю для согласования.'],
    'с уваж': ['С уважением,'],
    'best r': ['Best regards,'],
    'thank': ['Thank you for your prompt response.', 'Thank you for the information.'],
    'please': ['Please find attached.', 'Please let me know if you have any questions.'],
    'в соот': ['В соответствии с поручением,', 'В соответствии с решением совещания,'],
    'по рез': ['По результатам рассмотрения,', 'По результатам совещания,'],
    'инфор': ['Информирую, что', 'Информирую о следующем:'],
    'согласов': ['Согласовано.', 'Согласовано без замечаний.'],
    'приним': ['Принято к исполнению.', 'Принято к сведению.', 'Принято в работу.'],
  };

  SmartComposeService(this._prefs) {
    _loadLearnedPhrases();
  }

  void _loadLearnedPhrases() {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _learnedPhrases.addAll(map.map((k, v) => MapEntry(k, v as int)));
      } catch (_) {}
    }
  }

  Future<void> _saveLearnedPhrases() async {
    await _prefs.setString(_key, jsonEncode(_learnedPhrases));
  }

  /// Получить подсказки для текущего ввода
  List<SmartComposeSuggestion> getSuggestions(String currentText, {int limit = 3}) {
    if (currentText.length < 3) return [];

    final lastLine = currentText.split('\n').last.trim().toLowerCase();
    if (lastLine.length < 3) return [];

    final suggestions = <SmartComposeSuggestion>[];

    // 1. Шаблонные фразы
    for (final entry in _templates.entries) {
      if (lastLine.startsWith(entry.key) || entry.key.startsWith(lastLine)) {
        for (final phrase in entry.value) {
          suggestions.add(SmartComposeSuggestion(
            text: phrase,
            confidence: 0.8,
            source: 'template',
          ));
        }
      }
    }

    // 2. Выученные фразы
    for (final entry in _learnedPhrases.entries) {
      // Строки подписи, выученные прежними версиями, не предлагаем.
      if (_contactLike.hasMatch(entry.key)) continue;
      if (entry.key.toLowerCase().startsWith(lastLine)) {
        suggestions.add(SmartComposeSuggestion(
          text: entry.key,
          confidence: (entry.value / 10).clamp(0.1, 0.95),
          source: 'learned',
        ));
      }
    }

    // 3. Контекстные (время суток): по-русски — «добр…», по-английски —
    // «good…» (раньше и на «good» предлагалось русское «Доброе утро!»).
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 0 : (hour < 18 ? 1 : 2);
    if (lastLine.startsWith('добр')) {
      suggestions.insert(0, SmartComposeSuggestion(
          text: const ['Доброе утро!', 'Добрый день!', 'Добрый вечер!'][part], confidence: 0.9, source: 'context'));
    } else if (lastLine.startsWith('good')) {
      suggestions.insert(0, SmartComposeSuggestion(
          text: const ['Good morning,', 'Good afternoon,', 'Good evening,'][part], confidence: 0.9, source: 'context'));
    }

    // 4. Завершение письма на языке приложения («Mit freundlichen Grüßen»,
    // «Cordialement,»…) — по первым буквам (1.7.3).
    final regards = StringsStore.get(appLanguageOf(_prefs), 'sigRegards')?.trim() ?? '';
    if (regards.length > lastLine.length && regards.toLowerCase().startsWith(lastLine)) {
      suggestions.add(SmartComposeSuggestion(text: regards, confidence: 0.85, source: 'template'));
    }

    // Сортируем по confidence и ограничиваем
    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Убираем дубли
    final seen = <String>{};
    return suggestions.where((s) => seen.add(s.text)).take(limit).toList();
  }

  /// Запомнить отправленную фразу для обучения
  void learnFromSentEmail(String body) {
    if (body.isEmpty) return;

    final lines = body.split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 10 && l.length < 200)
        .toList();

    for (final line in lines) {
      // Не запоминаем стандартные завершения письма.
      if (_regardsLike.hasMatch(line)) continue;
      // Контакты из подписи и служебные строки: адреса, телефоны, ссылки.
      if (_contactLike.hasMatch(line)) continue;

      _learnedPhrases[line] = (_learnedPhrases[line] ?? 0) + 1;
    }

    // Ограничиваем размер словаря
    if (_learnedPhrases.length > 500) {
      final sorted = _learnedPhrases.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _learnedPhrases.clear();
      _learnedPhrases.addEntries(sorted.take(300));
    }

    _saveLearnedPhrases();
  }

  static final _regardsLike = RegExp(
      r'^(С уважением|С наилучшими пожеланиями|Best regards|Kind regards|Regards|Sincerely|'
      r'Mit freundlichen Grüßen|Viele Grüße|Beste Grüße|Cordialement|Bien cordialement|Salutations)',
      caseSensitive: false);

  static final _contactLike = RegExp(
      r'@|https?://|www\.|(тел|tel|phone|моб|mob|факс|fax|e-?mail|skype)\b|\+?\d[\d\s()-]{6,}',
      caseSensitive: false);

  /// Очистить выученные фразы
  Future<void> clearLearned() async {
    _learnedPhrases.clear();
    await _prefs.remove(_key);
  }
}

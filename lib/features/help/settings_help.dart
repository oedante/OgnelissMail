// lib/features/help/settings_help.dart
// Справка по пункту настроек (просьба владельца 18.11.2026: «в настройках
// по долгому нажатию пункта выводить справку, что это и на что влияет, если
// у нас есть тексты в FAQ»).
//
// Долгое нажатие (на компьютере — правая кнопка мыши) на строку настроек и
// значок «?» открывают одну шторку: пояснение самой настройки (hint строки,
// help раздела) и ответы из «Вопросов и ответов» про неё. Какие ответы —
// задаёт [settingsFaq]: ключ строки НАЗВАНИЯ пункта → ключи вопросов
// (faq_content.dart). Строки настроек получают название уже переведённым,
// поэтому соответствие ищется по тексту названия на текущем языке.
//
// Новый вопрос про настройку — допишите его ключ сюда, к названию пункта.

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import '../../l10n/app_localizations.dart';
import 'faq_content.dart';

/// Ключ названия пункта настроек → вопросы про него.
const Map<String, List<String>> settingsFaq = {
  // Главный экран настроек — разделы.
  'accounts': ['settings_3', 'exchange_1'],
  'addAccount': ['settings_3'],
  'general': ['widgets_2', 'widgets_3'],
  'notifications': ['notify_1', 'notify_3', 'notify_4', 'notify_5'],
  'mailReadingSettings': ['mail_1', 'mail_2', 'mail_7', 'conv_1', 'mail_14'],
  'mailComposeSettings': ['drafts_5', 'drafts_6'],
  'mailFilesSettings': ['mail_10', 'mail_11', 'mail_12'],
  'translateSection': ['mail_15'],
  'templatesSignature': ['drafts_9'],
  'vipRulesTitle': ['contacts_1'],
  'calendar': ['calendar_4'],
  'pinLock': ['security_2', 'widgets_5'],
  'permissions': ['notify_1', 'notify_3'],
  'ognaArchive': ['archive_1', 'archive_6', 'archive_7'],
  'backupTitle': ['security_3'],
  'advancedSettings': ['settings_2'],
  'logsTitle': ['settings_2'],

  // Почта: лента, письмо, написание.
  'quickReplyBar': ['mail_1'],
  'mailBarOrder': ['mail_2'],
  'mailSwipePager': ['mail_7'],
  'threading': ['conv_1'],
  'readingPane': ['mail_14'],
  'undoSendWindow': ['drafts_5'],
  'photoSendSize': ['drafts_6', 'drafts_8'],
  'greetingSetting': ['drafts_9', 'drafts_11'],
  'customGreetingAdd': ['drafts_11'],
  'signatures': ['drafts_9'],
  'docPreviewSection': ['mail_10', 'mail_11'],
  'docPreview': ['mail_10', 'mail_11'],
  'translateAlwaysSetting': ['mail_15'],

  // Ящик.
  'folderSync': ['notify_2'],
  'addSharedMailbox': ['exchange_1'],
  'onlineArchive': ['exchange_2'],
  'specialArchiveFolder': ['mail_4'],
  'specialJunkFolder': ['mail_4'],

  // Календарь, уведомления, виджеты.
  'deviceCalendar': ['calendar_4'],
  'ntfTestAction': ['notify_4'],
  'quietHours': ['notify_5'],
  'focusMode': ['notify_5'],
  'widgetThemeTitle': ['widgets_2'],
  'widgetBgTitle': ['widgets_3'],

  // Архив Ogneliss.
  'archiveCopySave': ['archive_2', 'archive_6'],
  'archiveConnectTitle': ['archive_2', 'archive_5'],
  'archiveNewCode': ['archive_3'],
  'archiveAppRestore': ['archive_5'],
};

/// Ответы только для одной системы (про iPhone — не показывать на Android).
const Map<String, Set<TargetPlatform>> _onlyOn = {
  'notify_1': {TargetPlatform.iOS},
  'notify_3': {TargetPlatform.android},
  'widgets_3': {TargetPlatform.android},
};

abstract final class SettingsHelp {
  static String? _lang;
  static Map<String, List<FaqItem>> _byTitle = const {};
  static final Map<String, (FaqItem, String)> _items = {
    for (final s in faqSections)
      for (final it in s.items) it.key: (it, s.id),
  };

  /// Вопросы про пункт с названием [title] (на языке [l10n]).
  static List<FaqItem> faqFor(AppLocalizations l10n, String? title) {
    if (title == null || title.isEmpty) return const [];
    final lang = l10n.locale.languageCode;
    if (_lang != lang) {
      final map = <String, List<FaqItem>>{};
      for (final MapEntry(:key, :value) in settingsFaq.entries) {
        final list = map.putIfAbsent(l10n.tr(key), () => []);
        for (final k in value) {
          final it = _items[k]?.$1;
          if (it != null && !list.contains(it)) list.add(it);
        }
      }
      _byTitle = map;
      _lang = lang;
    }
    final platform = defaultTargetPlatform;
    return [
      for (final it in _byTitle[title.trim()] ?? const <FaqItem>[])
        if (_onlyOn[it.key]?.contains(platform) ?? true) it,
    ];
  }

  /// Раздел «Вопросов и ответов», где стоит вопрос (для кнопки «Вопросы и
  /// ответы» в шторке).
  static String? sectionOf(FaqItem it) => _items[it.key]?.$2;

  /// Есть ли что показать: пояснение или вопросы.
  static bool has(AppLocalizations l10n, String? title, String? hint) =>
      (hint != null && hint.isNotEmpty) || faqFor(l10n, title).isNotEmpty;

  /// Для тестов: язык сменился в тестовом окне без перезапуска.
  static void debugReset() => _lang = null;
}

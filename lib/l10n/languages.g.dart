// lib/l10n/languages.g.dart
// Создано tool/l10n/l10n.py gen по файлам assets/l10n/*.xml — не править
// вручную: добавили язык (файл) — запустите gen.

import 'strings_store.dart' show AppLanguage;

const kAppLanguages = <AppLanguage>[
  AppLanguage('ru', 'Русский', 'Russian', plural: ['one', 'few', 'many', 'other']),
  AppLanguage('en', 'English', 'English'),
  AppLanguage('de', 'Deutsch', 'German'),
  AppLanguage('fr', 'Français', 'French'),
  AppLanguage('ar', 'العربية', 'Arabic', rtl: true, machine: true, plural: ['zero', 'one', 'two', 'few', 'many', 'other']),
  AppLanguage('zh', '简体中文', 'Chinese (Simplified)', machine: true, plural: ['other']),
  AppLanguage('cs', 'Čeština', 'Czech', machine: true, plural: ['one', 'few', 'other']),
  AppLanguage('da', 'Dansk', 'Danish', machine: true),
  AppLanguage('nl', 'Nederlands', 'Dutch', machine: true),
  AppLanguage('fi', 'Suomi', 'Finnish', machine: true),
  AppLanguage('he', 'עברית', 'Hebrew', rtl: true, machine: true, plural: ['one', 'two', 'other']),
  AppLanguage('hi', 'हिन्दी', 'Hindi', machine: true),
  AppLanguage('hu', 'Magyar', 'Hungarian', machine: true),
  AppLanguage('id', 'Bahasa Indonesia', 'Indonesian', machine: true, plural: ['other']),
  AppLanguage('it', 'Italiano', 'Italian', machine: true),
  AppLanguage('ja', '日本語', 'Japanese', machine: true, plural: ['other']),
  AppLanguage('ko', '한국어', 'Korean', machine: true, plural: ['other']),
  AppLanguage('nb', 'Norsk bokmål', 'Norwegian', machine: true),
  AppLanguage('pl', 'Polski', 'Polish', machine: true, plural: ['one', 'few', 'many', 'other']),
  AppLanguage('pt', 'Português (Brasil)', 'Portuguese (Brazil)', machine: true),
  AppLanguage('ro', 'Română', 'Romanian', machine: true, plural: ['one', 'few', 'other']),
  AppLanguage('sk', 'Slovenčina', 'Slovak', machine: true, plural: ['one', 'few', 'other']),
  AppLanguage('es', 'Español', 'Spanish', machine: true),
  AppLanguage('sv', 'Svenska', 'Swedish', machine: true),
  AppLanguage('th', 'ไทย', 'Thai', machine: true, plural: ['other']),
  AppLanguage('tr', 'Türkçe', 'Turkish', machine: true),
  AppLanguage('vi', 'Tiếng Việt', 'Vietnamese', machine: true, plural: ['other']),
];

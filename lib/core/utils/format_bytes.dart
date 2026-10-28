// lib/core/utils/format_bytes.dart
// Размер файла для людей: «512 Б», «1.4 КБ», «8.4 МБ» — единицами языка
// приложения. Раньше функция жила в экране «Хранилище»; с 1.7.2+110 ею
// пользуются и вложения письма (плашки, строка размера, «Размер фото»), где
// прежде стояло «8.4 MB» по-английски.

import '../../l10n/app_localizations.dart';

String formatBytes(int bytes, AppLocalizations l10n) {
  if (bytes < 1024) return '$bytes ${l10n.tr('unitB')}';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ${l10n.tr('unitKB')}';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${l10n.tr('unitMB')}';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ${l10n.tr('unitGB')}';
}

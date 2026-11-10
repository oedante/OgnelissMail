// lib/widgets/navigation/phone_bar.dart
// Разделы нижней панели телефона (2.2.0, просьба пользователя 10.11.2026):
// маршрут, подпись, значок каждого и какой из них выбран. Порядок хранит
// phoneBarProvider (drawer_prefs.dart); панель строит MainShell, выбор мест —
// «Настройки → Общие → Нижняя панель».

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/app_icons.dart';
import '../../features/mail/providers/drawer_prefs.dart' show BarItem;
import '../../features/settings/providers/feature_flags_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';

/// Маршрут раздела (у «Меню» — нет: оно открывает меню ящиков и папок).
String? barRoute(BarItem i) => switch (i) {
      BarItem.mail => '/mail',
      BarItem.calendar => '/calendar',
      BarItem.contacts => '/contacts',
      BarItem.tasks => '/tasks',
      BarItem.myDay => '/my-day',
      BarItem.notes => '/notes',
      BarItem.assignments => '/assignments',
      BarItem.files => '/files',
      BarItem.menu => null,
    };

/// Подпись на панели.
String barLabel(BarItem i, AppLocalizations l10n) => switch (i) {
      BarItem.mail => l10n.mail,
      BarItem.calendar => l10n.calendarLabel,
      BarItem.contacts => l10n.contactsLabel,
      BarItem.tasks => l10n.tasksLabel,
      BarItem.myDay => l10n.tr('myDay'),
      BarItem.notes => l10n.tr('notes'),
      BarItem.assignments => l10n.tr('assignments'),
      BarItem.files => l10n.tr('attachments'),
      BarItem.menu => l10n.tr('barMenu'),
    };

/// Значок раздела (выбранный — с заливкой).
IconData barIcon(BarItem i) => switch (i) {
      BarItem.mail => AppIcons.mail,
      BarItem.calendar => AppIcons.calendar_today,
      BarItem.contacts => AppIcons.contacts,
      BarItem.tasks => AppIcons.check_box,
      BarItem.myDay => AppIcons.myDay,
      BarItem.notes => AppIcons.sticky_note_2,
      BarItem.assignments => AppIcons.assignment_ind,
      BarItem.files => AppIcons.folder_copy,
      BarItem.menu => AppIcons.account_circle,
    };

/// Раздел включён в «Профиле» (задачи, заметки, файлы, «Мой день»
/// отключаемые; остальные — всегда).
bool Function(BarItem) barAvailability(WidgetRef ref) {
  final flags = ref.watch(featureFlagsProvider);
  final myDay = ref.watch(settingsProvider.select((s) => s.myDay));
  return (i) => switch (i) {
        BarItem.tasks => flags.showTasksTab,
        BarItem.notes => flags.showNotes,
        BarItem.files => flags.showFileHub,
        BarItem.myDay => myDay,
        _ => true,
      };
}

/// Выбранное место: раздел текущего экрана; экран, открытый из меню (его
/// раздела на панели нет), — «Меню».
int barSelected(List<BarItem> items, String path) {
  for (var i = 0; i < items.length; i++) {
    final r = barRoute(items[i]);
    if (r != null && (path == r || path.startsWith('$r/'))) return i;
  }
  return items.indexOf(BarItem.menu);
}

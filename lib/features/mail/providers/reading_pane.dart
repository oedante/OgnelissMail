// lib/features/mail/providers/reading_pane.dart
//
// «Область чтения» на планшете и компьютере (1.12.x, просьба владельца
// 04.11.2026: «UI планшетов и десктопа с референсом как Outlook»): письмо
// справа от ленты (как раньше), снизу под лентой или скрыто — лента во всю
// ширину, письмо открывается отдельным экраном, как на телефоне. На узком
// окне и на телефоне панели нет при любом выборе.
//
// Вид окна, а не данные ящика — в SharedPreferences, как закрепление панели
// папок (drawer_prefs.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/adaptive_layout.dart' show PanePosition;
import '../../../widgets/ui/app_menu_button.dart' show AppMenuEntry;
import '../../../widgets/ui/action_sheet.dart' show showChoiceSheet;

class ReadingPaneNotifier extends Notifier<PanePosition> {
  static const _k = 'reading_pane';

  @override
  PanePosition build() {
    final v = ref.read(sharedPrefsProvider).getString(_k);
    return PanePosition.values.where((p) => p.name == v).firstOrNull ?? PanePosition.right;
  }

  Future<void> set(PanePosition p) async {
    state = p;
    await ref.read(sharedPrefsProvider).setString(_k, p.name);
  }
}

final readingPaneProvider = NotifierProvider<ReadingPaneNotifier, PanePosition>(ReadingPaneNotifier.new);

/// Подпись, пояснение и значок положения — для настроек и меню ленты.
({String label, String? hint, IconData icon}) readingPaneLabel(AppLocalizations l10n, PanePosition p) => switch (p) {
  PanePosition.right => (label: l10n.tr('readingPaneRight'), hint: null, icon: AppIcons.dock_to_right),
  PanePosition.bottom => (
    label: l10n.tr('readingPaneBottom'),
    hint: l10n.tr('readingPaneBottomHint'),
    icon: AppIcons.dock_to_bottom,
  ),
  PanePosition.hidden => (
    label: l10n.tr('readingPaneHidden'),
    hint: l10n.tr('readingPaneHiddenHint'),
    icon: AppIcons.right_panel_close,
  ),
};

/// Выбор области чтения карточкой (меню «⋮» ленты на широком окне — как
/// «Вид → Область чтения» в Outlook); текущее положение — с галочкой.
Future<void> pickReadingPane(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showChoiceSheet<PanePosition>(
    context,
    title: l10n.tr('readingPane'),
    selected: ref.read(readingPaneProvider),
    entries: [
      for (final p in PanePosition.values)
        AppMenuEntry(
          value: p,
          icon: readingPaneLabel(l10n, p).icon,
          label: readingPaneLabel(l10n, p).label,
          subtitle: readingPaneLabel(l10n, p).hint,
        ),
    ],
  );
  if (picked != null) await ref.read(readingPaneProvider.notifier).set(picked);
}

/// Спросили ли при первом запуске (2.3.0).
const readingPaneAskedKey = 'reading_pane_asked_v1';

/// Первый запуск на планшете и компьютере (2.3.0, решение владельца
/// 10.11.2026: «спрашивать при первом запуске»; замечание: «письмо
/// открывается на часть экрана, непонятная основная область»): как
/// открывать письма — рядом с лентой, под ней или на весь экран. Один раз и
/// только если вид ещё не выбирали; закрыли без выбора — как было (рядом).
/// Дальше — меню «⋮» ленты → «Область чтения».
Future<void> maybeAskReadingPane(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool(readingPaneAskedKey) == true || prefs.getString(ReadingPaneNotifier._k) != null) return;
  await prefs.setBool(readingPaneAskedKey, true);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final picked = await showChoiceSheet<PanePosition>(
    context,
    title: l10n.tr('readingPaneAskTitle'),
    subtitle: l10n.tr('readingPaneAskHint').replaceAll('{pane}', l10n.tr('readingPane')),
    entries: [
      for (final p in const [PanePosition.right, PanePosition.hidden, PanePosition.bottom])
        AppMenuEntry(
          value: p,
          icon: readingPaneLabel(l10n, p).icon,
          label: readingPaneLabel(l10n, p).label,
          subtitle: readingPaneLabel(l10n, p).hint,
        ),
    ],
  );
  if (picked != null) await ref.read(readingPaneProvider.notifier).set(picked);
}

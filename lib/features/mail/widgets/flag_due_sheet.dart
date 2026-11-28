// lib/features/mail/widgets/flag_due_sheet.dart
// «Флаг» — одной кнопкой со сроком (2.7.5, замечание владельца 28.11.2026:
// «флаг и срок флага можно объединить»): сегодня, завтра, на этой неделе,
// на следующей неделе, без даты; «Снять флажок» — если флажок стоит. Одно
// меню для экрана письма, карточки по удержанию в ленте и панели команд
// широкого экрана.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/control_service.dart' show ControlState;
import '../../../services/mail/flag_due.dart';
import '../../../widgets/ui/action_sheet.dart';

/// Выбор флажка: поставить со сроком [due] или снять ([flagged] = false).
typedef FlagChoice = ({bool flagged, FlagDue due});

/// Меню флажка письма; null — закрыли.
Future<FlagChoice?> pickFlagDue(BuildContext context, EmailModel email) async {
  final l10n = AppLocalizations.of(context);
  final own = email.controlState == ControlState.none;
  final hasDue = email.isFlagged && email.followUpAt != null && own;
  String? sub(FlagDue d) {
    final at = FlagDues.atFor(d);
    return at == null ? null : FlagDues.label(at, l10n);
  }

  final picked = await showActionSheet<String>(
    context,
    title: l10n.tr('flagDueTitle'),
    leading: const Icon(AppIcons.flag),
    items: [
      ActionSheetItem(icon: AppIcons.today, label: l10n.tr('flagToday'), value: 'today'),
      ActionSheetItem(icon: AppIcons.event, label: l10n.tr('flagTomorrow'), subtitle: sub(FlagDue.tomorrow), value: 'tomorrow'),
      ActionSheetItem(icon: AppIcons.date_range, label: l10n.tr('flagThisWeek'), subtitle: sub(FlagDue.thisWeek), value: 'week'),
      ActionSheetItem(icon: AppIcons.next_week, label: l10n.tr('flagNextWeek'), subtitle: sub(FlagDue.nextWeek), value: 'next'),
      ActionSheetItem(icon: AppIcons.flag, label: l10n.tr('flagNoDate'), value: 'none',
          checked: email.isFlagged && own && !hasDue),
      if (email.isFlagged) ActionSheetItem(icon: AppIcons.clear, label: l10n.tr('flagClear'), value: 'clear'),
    ],
  );
  return switch (picked) {
    null => null,
    'clear' => (flagged: false, due: FlagDue.none),
    'tomorrow' => (flagged: true, due: FlagDue.tomorrow),
    'week' => (flagged: true, due: FlagDue.thisWeek),
    'next' => (flagged: true, due: FlagDue.nextWeek),
    'none' => (flagged: true, due: FlagDue.none),
    _ => (flagged: true, due: FlagDue.today),
  };
}

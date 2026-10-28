// lib/features/calendar/widgets/reminder_list_editor.dart
// Список напоминаний встречи (1.7.2+110): «За 15 мин ×», «За 1 день ×»,
// «+ Добавить напоминание» — как в календарях Google и Samsung (скриншоты
// владельца 24.10.2026). Нажатие на напоминание — сменить время, «×» —
// убрать. Как хранится и что уходит на сервер — `EventReminders`.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/event_reminders.dart';
import '../../../widgets/common/app_sheet.dart';

/// «В момент начала», «За 15 мин», «За 2 ч», «За 1 дн.», «За 1 нед.».
String reminderLabel(int m, AppLocalizations l10n) {
  if (m < 0) return l10n.tr('noReminder');
  if (m == 0) return l10n.tr('reminderAtStart');
  if (m % 10080 == 0) return l10n.tr('reminderWeeksBefore').replaceAll('{n}', '${m ~/ 10080}');
  if (m % 1440 == 0) return l10n.tr('reminderDaysBefore').replaceAll('{n}', '${m ~/ 1440}');
  if (m >= 60 && m % 60 == 0) return l10n.tr('reminderHoursBefore').replaceAll('{n}', '${m ~/ 60}');
  return l10n.tr('reminderMinBefore').replaceAll('{n}', '$m');
}

/// Выбор времени напоминания: варианты [EventReminders.presets] без уже
/// выбранных ([exclude]); [current] — отмечено галочкой. null — передумали.
Future<int?> showReminderPicker(BuildContext context, {Set<int> exclude = const {}, int? current}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l10n.tr('reminder'), style: theme.textTheme.titleMedium)),
              for (final m in EventReminders.presets)
                if (m == current || !exclude.contains(m))
                  ListTile(
                    title: Text(reminderLabel(m, l10n)),
                    trailing: m == current ? Icon(AppIcons.check, color: theme.colorScheme.primary) : null,
                    onTap: () => Navigator.pop(ctx, m),
                  ),
            ],
          ),
        ),
      );
    },
  );
}

/// Напоминания строками. [value] — минуты по возрастанию; [note] — строка
/// под списком (например, что Exchange хранит одно напоминание).
class ReminderListEditor extends StatelessWidget {
  final List<int> value;
  final ValueChanged<List<int>> onChanged;
  final String? note;

  /// Отступ строк слева (в форме встречи строки идут без полей, в шторке —
  /// с полями шторки).
  final EdgeInsetsGeometry contentPadding;

  const ReminderListEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.note,
    this.contentPadding = EdgeInsets.zero,
  });

  Future<void> _add(BuildContext context) async {
    final m = await showReminderPicker(context, exclude: value.toSet());
    if (m == null) return;
    onChanged(EventReminders.normalize([...value, m]));
  }

  Future<void> _change(BuildContext context, int old) async {
    final m = await showReminderPicker(context, exclude: value.toSet(), current: old);
    if (m == null || m == old) return;
    onChanged(EventReminders.normalize([for (final x in value) if (x != old) x, m]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value.isEmpty)
          ListTile(
            contentPadding: contentPadding,
            leading: Icon(AppIcons.notifications_off, color: muted),
            title: Text(l10n.tr('noReminder'), style: TextStyle(color: muted)),
            onTap: () => _add(context),
          ),
        for (var i = 0; i < value.length; i++)
          ListTile(
            contentPadding: contentPadding,
            // Колокольчик — у первой строки, остальные — с той же линии.
            leading: i == 0 ? Icon(AppIcons.notifications, color: muted) : const SizedBox(width: Sizes.icon),
            title: Text(reminderLabel(value[i], l10n)),
            trailing: IconButton(
              tooltip: l10n.tr('delete'),
              icon: const Icon(AppIcons.close),
              onPressed: () => onChanged([for (final x in value) if (x != value[i]) x]),
            ),
            onTap: () => _change(context, value[i]),
          ),
        if (value.length < EventReminders.max)
          Padding(
            // Значок «+» — с линии текста строк (у TextButton.icon поле 12).
            padding: contentPadding.add(const EdgeInsets.only(left: Sizes.icon + Space.xs)),
            child: TextButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.tr('reminderAdd')),
            ),
          ),
        if (note != null && note!.isNotEmpty)
          Padding(
            padding: contentPadding.add(const EdgeInsets.only(left: Sizes.icon + Space.l, bottom: Space.s)),
            child: Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
      ],
    );
  }
}

/// Шторка с напоминаниями (карточка встречи): список и «Готово». null —
/// закрыли без изменений.
Future<List<int>?> showRemindersSheet(BuildContext context, {required List<int> initial, String? note}) {
  final l10n = AppLocalizations.of(context);
  var current = EventReminders.normalize(initial);
  return showAppSheet<List<int>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(title: Text(l10n.tr('reminders'), style: Theme.of(ctx).textTheme.titleMedium)),
              ReminderListEditor(
                value: current,
                onChanged: (v) => setLocal(() => current = v),
                note: note,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, current),
                    child: Text(l10n.tr('done')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

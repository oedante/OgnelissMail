// lib/features/mail/widgets/later_sheet.dart
// «Посмотреть позже»: компактное меню выбора срока (через 1 и 3 часа, завтра,
// послезавтра, на следующей неделе, без даты, своя дата и время на колёсиках)
// и применение к одному или нескольким письмам.

import '../../../widgets/ui/wheel_pickers.dart' show showWheelDateTimePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../../services/mail/later_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../providers/mail_providers.dart';

/// Выбор в меню: срок [at] (null — без даты) или [clear] — убрать из «Позже».
class LaterChoice {
  final DateTime? at;
  final bool clear;
  const LaterChoice(this.at, {this.clear = false});
}

/// Срок возврата коротко: «14:05», «чт, 09:00», «12 окт., 09:00».
String laterWhenLabel(DateTime at, AppLocalizations l10n, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final loc = l10n.localeCode;
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  final time = DateFormat('HH:mm', loc).format(at);
  if (diff == 0) return time;
  if (diff == 1) return '${l10n.tr('tomorrow').toLowerCase()}, $time';
  if (diff > 1 && diff < 7) return '${DateFormat('EEE', loc).format(at)}, $time';
  return '${DateFormat('d MMM', loc).format(at)}, $time';
}

IconData _iconFor(String key) => switch (key) {
      'laterIn1h' => AppIcons.more_time,
      'laterIn3h' => AppIcons.schedule,
      'laterTomorrow' => AppIcons.today,
      'laterDayAfter' => AppIcons.date_range,
      'laterNextWeek' => AppIcons.next_week,
      _ => AppIcons.hourglass_empty,
    };

/// Меню «Позже». [current] — уже отложенное письмо (появится «Убрать из
/// «Позже»» и текущий срок в заголовке).
Future<LaterChoice?> showLaterSheet(BuildContext context, {EmailModel? current}) {
  return showAppSheet<LaterChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _LaterSheet(current: current),
  );
}

class _LaterSheet extends StatelessWidget {
  final EmailModel? current;
  const _LaterSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    final waiting = current != null && current!.laterState == LaterState.waiting;

    Widget row(IconData icon, String label, String? trailing, VoidCallback onTap, {Color? color}) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: Sizes.tapTarget,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          leading: Icon(icon, color: color),
          title: Text(label, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
          trailing: trailing == null ? null : Text(trailing, style: muted),
          onTap: onTap,
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.tr('laterTitle'), style: theme.textTheme.titleMedium),
                if (waiting)
                  Text(
                    current!.remindAt == null
                        ? l10n.tr('laterNoDate')
                        : l10n.tr('laterUntil').replaceAll('{when}', laterWhenLabel(current!.remindAt!.toLocal(), l10n)),
                    style: muted,
                  ),
              ]),
            ),
            for (final o in LaterService.options(now))
              row(_iconFor(o.key), l10n.tr(o.key), o.at == null ? null : laterWhenLabel(o.at!, l10n, now: now),
                  () => Navigator.of(context).pop(LaterChoice(o.at))),
            row(AppIcons.edit_calendar, l10n.tr('laterPick'), null, () async {
              final at = await _pickDateTime(context, l10n, current?.remindAt?.toLocal());
              if (at != null && context.mounted) Navigator.of(context).pop(LaterChoice(at));
            }),
            if (current != null && current!.laterState != LaterState.none) ...[
              const Divider(height: Space.s),
              row(AppIcons.alarm_off, l10n.tr('laterClear'), null,
                  () => Navigator.of(context).pop(const LaterChoice(null, clear: true)),
                  color: theme.colorScheme.error),
            ],
          ],
        ),
      ),
    );
  }

  /// Дата и время — общими барабанами (wheel_pickers, 1.6.2: широкие
  /// строки), шаг — 5 минут.
  static Future<DateTime?> _pickDateTime(BuildContext context, AppLocalizations l10n, DateTime? initial) {
    final now = DateTime.now();
    final start = initial != null && initial.isAfter(now) ? initial : now.add(const Duration(hours: 1));
    return showWheelDateTimePicker(
      context,
      initial: start,
      first: DateTime(now.year, now.month, now.day, now.hour, now.minute),
      last: now.add(const Duration(days: 366)),
      title: l10n.tr('laterPick'),
      minuteInterval: 5,
    );
  }
}

/// Показать меню и отложить (или снять) письма. Возвращает выбор или null,
/// если меню закрыли.
Future<LaterChoice?> postponeEmails(BuildContext context, WidgetRef ref, List<EmailModel> emails) async {
  if (emails.isEmpty) return null;
  final choice = await showLaterSheet(context, current: emails.length == 1 ? emails.first : null);
  if (choice == null) return null;
  await applyLater(ref, emails, choice);
  return choice;
}

/// Применить выбор к письмам: база, уведомление о возврате, список.
Future<void> applyLater(WidgetRef ref, List<EmailModel> emails, LaterChoice choice) async {
  final actions = ref.read(emailActionsProvider);
  final notifier = ref.read(emailsProvider.notifier);
  final on = !choice.clear;
  for (final e in emails) {
    await actions.setLater(e.id, e.accountId, on: on, at: choice.at);
    notifier.applyLocalFlags(e.id,
        laterState: on ? LaterState.waiting : LaterState.none,
        remindAt: on ? choice.at : null,
        clearRemind: !on || choice.at == null);
  }
  ref.read(laterRevisionProvider.notifier).state++;
}

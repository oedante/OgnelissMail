// lib/features/mail/widgets/control_sheet.dart
// «На контроль» — одна функция вместо двух («На контроле» и «Напомнить,
// если нет ответа», 09.10.2026). Меню: без срока или со сроком (завтра,
// через 3 дня, через неделю, своя дата); не дождались к сроку — уведомление.
//   · Моё письмо — «Ждём ответа»: «Исполнено», когда ответят все из «Кому»
//     (копия не считается); в ленте круг заполняется по доле ответивших.
//   · Входящее — «Нужно ответить»: «Исполнено», когда отвечу я.

import '../../../widgets/ui/wheel_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/control_service.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../providers/mail_providers.dart';

/// Выбор в меню: поставить (со сроком [deadline] или без) или снять.
class ControlChoice {
  final DateTime? deadline;
  final bool clear;
  const ControlChoice({this.deadline, this.clear = false});
}

/// Своё ли письмо (для текста меню и начального состояния).
bool isMyEmail(WidgetRef ref, EmailModel e) {
  final acc = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
  if (acc == null) return false;
  final me = {acc.email.toLowerCase(), if ((acc.sharedMailboxEmail ?? '').isNotEmpty) acc.sharedMailboxEmail!.toLowerCase()};
  return me.contains(e.from.email.toLowerCase());
}

/// Срок коротко: «завтра», «пт, 16 окт.», «16 окт.».
String controlDeadlineLabel(DateTime d, AppLocalizations l10n) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return l10n.tr('today').toLowerCase();
  if (diff == 1) return l10n.tr('tomorrow').toLowerCase();
  if (diff > 1 && diff < 7) return DateFormat('EEE, d MMM', l10n.localeCode).format(d);
  return DateFormat('d MMM', l10n.localeCode).format(d);
}

Future<ControlChoice?> showControlSheet(BuildContext context, WidgetRef ref, EmailModel email) async {
  final l10n = AppLocalizations.of(context);
  final mine = isMyEmail(ref, email);
  final active = email.controlState != ControlState.none;
  final now = DateTime.now();
  // Срок — к концу рабочего дня (18:00): напоминание приходит вечером, когда
  // ясно, что ответа за день не было.
  DateTime at(int days) => DateTime(now.year, now.month, now.day + days, 18);
  final choice = await showActionSheet<String>(
    context,
    title: l10n.tr('controlSet'),
    subtitle: l10n.tr(mine ? 'controlHintMine' : 'controlHintIncoming'),
    leading: const Icon(AppIcons.task_alt),
    items: [
      ActionSheetItem(icon: AppIcons.task_alt, label: l10n.tr('controlNoDeadline'), value: 'none'),
      ActionSheetItem(
          icon: AppIcons.today,
          label: l10n.tr('controlDeadlineTomorrow'),
          subtitle: controlDeadlineLabel(at(1), l10n),
          value: '1'),
      ActionSheetItem(
          icon: AppIcons.date_range,
          label: l10n.tr('controlDeadline3'),
          subtitle: controlDeadlineLabel(at(3), l10n),
          value: '3'),
      ActionSheetItem(
          icon: AppIcons.next_week,
          label: l10n.tr('controlDeadline7'),
          subtitle: controlDeadlineLabel(at(7), l10n),
          value: '7'),
      ActionSheetItem(icon: AppIcons.edit_calendar, label: l10n.tr('controlPickDate'), value: 'pick'),
      if (active)
        ActionSheetItem(icon: AppIcons.close, label: l10n.tr('controlClear'), value: 'clear', destructive: true),
    ],
  );
  if (choice == null) return null;
  switch (choice) {
    case 'none':
      return const ControlChoice();
    case 'clear':
      return const ControlChoice(clear: true);
    case 'pick':
      if (!context.mounted) return null;
      final d = await showWheelDatePicker(context,
          initial: at(2), first: DateTime(now.year, now.month, now.day), last: now.add(const Duration(days: 365)));
      return d == null ? null : ControlChoice(deadline: DateTime(d.year, d.month, d.day, 18));
    default:
      return ControlChoice(deadline: at(int.parse(choice)));
  }
}

/// Применить выбор к письму. Возвращает новое состояние.
Future<int> applyControl(WidgetRef ref, EmailModel email, ControlChoice c) async {
  final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
  final next = c.clear
      ? ControlState.none
      : (ControlState.isActive(email.controlState)
          ? email.controlState
          : ControlService.initialFor(fromEmail: email.from.email, myEmail: acc == null ? '' : OwnAddresses.of(acc).join(','), to: [for (final a in email.to) a.email]));
  final db = ref.read(databaseProvider);
  await db.setControlState(email.id, email.accountId, next, deadline: c.deadline);
  if (!c.clear && c.deadline == null) await db.clearFollowUp(email.id, accountId: email.accountId);
  ref.read(emailsProvider.notifier).applyLocalFlags(email.id, controlState: next);
  ref.read(controlRevisionProvider.notifier).state++;
  return next;
}

// lib/features/settings/screens/notifications_settings_screen.dart
// Настройки уведомлений: включение, звук, вибрация, тихие часы.

import '../../../widgets/ui/wheel_pickers.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/quiet_hours_provider.dart';
import '../../../services/mail/focus_mode_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../../services/notifications/notification_service.dart' show notificationServiceProvider;
import '../../../services/push/push_wake_service.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../widgets/ui/app_radio_tile.dart';

/// Отступ вложенных строк — по тексту строк группы.
const _indent = Space.l + Sizes.icon + Space.l;

class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final qh = ref.watch(quietHoursProvider);
    final qhN = ref.read(quietHoursProvider.notifier);
    final notifier = ref.read(settingsProvider.notifier);
    final focus = ref.watch(focusModeProvider);
    final focusN = ref.read(focusModeProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('notifications')), actions: const [FaqButton(section: 'notify')])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('notifySectionMail')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.notifications,
              title: l10n.tr('notifyNewMail'),
              subtitle: l10n.tr('notifyNewMailDesc'),
              hint: l10n.tr('notifyNewMailHint'),
              value: settings.notificationsEnabled,
              onChanged: (v) => notifier.setNotificationsEnabled(v),
            ),
            SettingsSwitchItem(
              icon: AppIcons.volume_up,
              title: l10n.tr('sound'),
              value: settings.notificationSound,
              onChanged: settings.notificationsEnabled
                  ? (v) => notifier.setNotificationSound(v)
                  : null,
            ),
            SettingsSwitchItem(
              icon: AppIcons.vibration,
              title: l10n.tr('vibration'),
              value: settings.notificationVibration,
              onChanged: settings.notificationsEnabled
                  ? (v) => notifier.setNotificationVibration(v)
                  : null,
            ),
            // 1.6.45: проверить, что уведомления о почте доходят (тем же
            // каналом, звуком и вибрацией, что письмо).
            SettingsItem(
              icon: AppIcons.notifications_active,
              title: l10n.tr('ntfTestAction'),
              subtitle: l10n.tr('ntfTestHint'),
              onTap: () => unawaited(ref.read(notificationServiceProvider).showTestNotification()),
            ),
          ]),
          // Сигналы сервера (iPhone, 1.7.2): свёрнутое приложение просыпается
          // по пустому сигналу «проверь почту» с ogneliss.ru/push.
          if (PushWakeService.supported) ...[
            SettingsSectionTitle(l10n.tr('pushWakeTitle'), help: l10n.tr('pushWakeHelp')),
            SettingsGroup(children: [
              SettingsSwitchItem(
                icon: AppIcons.cloud_sync,
                title: l10n.tr('pushWakeSwitch'),
                subtitle: _pushWakeStatus(context, ref, l10n),
                value: ref.watch(pushWakePrefsProvider).enabled,
                onChanged: (v) => ref.read(pushWakePrefsProvider.notifier).setEnabled(v),
              ),
              if (ref.watch(pushWakePrefsProvider).enabled)
                for (final m in PushWakePrefsNotifier.intervals)
                  AppRadioTile<int>(
                    title: Text(l10n.tr('pushWakeEvery').replaceAll('{n}', '$m')),
                    value: m,
                    groupValue: ref.watch(pushWakePrefsProvider).interval,
                    onChanged: (v) => ref.read(pushWakePrefsProvider.notifier).setInterval(v ?? 15),
                  ),
            ]),
          ],
          SettingsSectionTitle(l10n.tr('quietHours')),
          SettingsGroup(children: [
          SettingsSwitchItem(
            icon: AppIcons.bedtime,
            title: l10n.tr('quietHours'),
            subtitle: l10n.tr('quietHoursDesc'),
            value: qh.enabled,
            onChanged: qhN.setEnabled,
          ),
          if (qh.enabled) ...[
            ListTile(
              contentPadding: const EdgeInsets.only(left: _indent, right: Space.l),
              title: Text(l10n.tr('fromTime')),
              trailing: Text(qh.start.format(context)),
              onTap: () async {
                final t = await showWheelTimePicker(context, initial: qh.start);
                if (t != null) unawaited(qhN.setStart(t));
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: _indent, right: Space.l),
              title: Text(l10n.tr('toTime')),
              trailing: Text(qh.end.format(context)),
              onTap: () async {
                final t = await showWheelTimePicker(context, initial: qh.end);
                if (t != null) unawaited(qhN.setEnd(t));
              },
            ),
            // Дни недели: чипы-переключатели. Ночной интервал относится к дню
            // НАЧАЛА (выбран Пт → тихой будет ночь с пятницы на субботу).
            Padding(
              padding: const EdgeInsets.only(left: _indent, right: Space.l, top: Space.xs, bottom: Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.tr('quietHoursDays'),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(_weekdayShort(d, l10n)),
                          selected: qh.days.contains(d),
                          onSelected: (on) {
                            final next = {...qh.days};
                            if (on) {
                              next.add(d);
                            } else {
                              next.remove(d);
                            }
                            qhN.setDays(next);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => qhN.setDays({1, 2, 3, 4, 5, 6, 7}),
                        child: Text(l10n.tr('everyDay')),
                      ),
                      TextButton(
                        onPressed: () => qhN.setDays({1, 2, 3, 4, 5}),
                        child: Text(l10n.tr('weekdays')),
                      ),
                      TextButton(
                        onPressed: () => qhN.setDays({6, 7}),
                        child: Text(l10n.tr('weekend')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          ]),
          // Режим фокуса — здесь же, рядом с тихими часами: раньше был
          // отдельной шторкой в общих настройках, и две похожие функции
          // «приглушить почту» жили в разных местах.
          SettingsSectionTitle(l10n.tr('focusMode')),
          SettingsGroup(children: [
          SettingsSwitchItem(
            icon: AppIcons.do_not_disturb_on,
            title: l10n.tr('focusMode'),
            subtitle: l10n.tr('focusModeDesc'),
            hint: l10n.tr('focusModeHint'),
            value: focus.isEnabled,
            onChanged: (v) => focusN.setEnabled(v),
          ),
          if (focus.isEnabled) ...[
            ListTile(
              contentPadding: const EdgeInsets.only(left: _indent, right: Space.l),
              title: Text(l10n.tr('deliveryTimes')),
              subtitle: Text(focus.deliveryTimes.join(', ')),
              trailing: const Icon(AppIcons.edit),
              onTap: () => _editDeliveryTimes(context, ref, focus.deliveryTimes),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: _indent, right: Space.l),
              title: Text(l10n.tr('disableOnWeekends')),
              value: focus.disableOnWeekends,
              onChanged: (v) => focusN.setDisableOnWeekends(v),
            ),
          ],
          ]),
          SettingsSectionTitle(l10n.tr('notifySectionImportant')),
          SettingsGroup(children: [
            SettingsItem(
              leading: const Icon(AppIcons.star, color: AppColors.brandAmber),
              title: l10n.tr('vipRulesTitle'),
              subtitle: l10n.tr('vipRulesDesc'),
              onTap: () => context.push('/vip-settings'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Время доставки в режиме фокуса: список, добавить, удалить.
Future<void> _editDeliveryTimes(BuildContext context, WidgetRef ref, List<String> current) async {
  final times = [...current]..sort();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final l10n = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(l10n.tr('deliveryTimes')),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in times)
              InputChip(
                label: Text(t),
                onDeleted: times.length > 1 ? () => setLocal(() => times.remove(t)) : null,
              ),
            ActionChip(
              avatar: const Icon(AppIcons.add, size: 18),
              label: Text(l10n.tr('add')),
              onPressed: () async {
                final picked = await showWheelTimePicker(ctx, initial: const TimeOfDay(hour: 12, minute: 0));
                if (picked == null) return;
                final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                if (!times.contains(v)) setLocal(() => (times..add(v)).sort());
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              ref.read(focusModeProvider.notifier).setDeliveryTimes(times);
              Navigator.pop(ctx);
            },
            child: Text(l10n.save),
          ),
        ],
      );
    }),
  );
}

/// Короткое название дня недели (1=Пн … 7=Вс) на языке интерфейса.
String _weekdayShort(int weekday, AppLocalizations l10n) {
  const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  return l10n.tr(keys[weekday - 1]);
}

/// Строка под переключателем сигналов: пояснение и состояние регистрации.
String _pushWakeStatus(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
  final st = ref.read(pushWakeServiceProvider).state();
  final parts = <String>[l10n.tr('pushWakeDesc')];
  if (!ref.read(pushWakePrefsProvider).enabled) return parts.first;
  if (st.lastError != null && !st.registered) {
    parts.add(l10n.tr('pushWakeStatusError').replaceAll('{e}', st.lastError!));
  } else if (st.registered && st.registeredAt != null) {
    parts.add(l10n.tr('pushWakeStatusOk').replaceAll('{when}', AppDateFormat.dayMonthTime(context, st.registeredAt!)));
    if (st.lastWake != null) {
      parts.add(l10n.tr('pushWakeStatusLast').replaceAll('{when}', AppDateFormat.dayMonthTime(context, st.lastWake!)));
    }
  } else {
    parts.add(l10n.tr('pushWakeStatusNone'));
  }
  return parts.join('\n');
}


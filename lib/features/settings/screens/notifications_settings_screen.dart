// lib/features/settings/screens/notifications_settings_screen.dart
// Настройки уведомлений: включение, звук, вибрация, тихие часы.

import '../../../widgets/ui/wheel_pickers.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
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
import '../../../services/notifications/notification_text.dart' show NotificationLines;
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/push/push_wake_service.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../widgets/ui/app_radio_tile.dart';

/// Отступ вложенных строк — по тексту строк группы.
const _indent = Space.l + Sizes.icon + Space.l;

/// Вид «как в мессенджерах» есть только на телефонах (Android, iPhone).
bool get _mobile =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

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
            // Как в мессенджерах (1.9.x, просьба владельца 31.10.2026): фото
            // или буква отправителя; на Android письма VIP — в «Беседах».
            if (_mobile) ...[
              SettingsSwitchItem(
                icon: AppIcons.account_circle,
                title: l10n.tr('notifyMessengerStyle'),
                subtitle: l10n.tr('notifyMessengerStyleDesc'),
                value: settings.notificationMessengerStyle,
                onChanged: settings.notificationsEnabled
                    ? (v) => notifier.setNotificationMessengerStyle(v)
                    : null,
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                SettingsSwitchItem(
                  icon: AppIcons.forum,
                  title: l10n.tr('notifyVipConversations'),
                  subtitle: l10n.tr('notifyVipConversationsDesc'),
                  value: settings.notificationVipConversations,
                  onChanged: settings.notificationsEnabled && settings.notificationMessengerStyle
                      ? (v) => notifier.setNotificationVipConversations(v)
                      : null,
                ),
            ],
            // Строк текста в уведомлении (1.10.3, просьба владельца
            // 02.11.2026) — отдельно для рабочих и личных ящиков.
            if (!kIsWeb) _NotificationLinesTile(enabled: settings.notificationsEnabled),
            // 1.6.45: проверить, что уведомления о почте доходят (тем же
            // каналом, звуком и вибрацией, что письмо).
            SettingsItem(
              icon: AppIcons.notifications_active,
              title: l10n.tr('ntfTestAction'),
              subtitle: l10n.tr('ntfTestHint'),
              onTap: () => unawaited(ref.read(notificationServiceProvider).showTestNotification()),
            ),
          ]),
          // Сигналы сервера (iPhone, 1.7.2; Android через FCM, 1.9.x):
          // свёрнутое приложение просыпается по пустому сигналу «проверь
          // почту» с ogneliss.ru/push.
          if (PushWakeService.supported) ...[
            if (PushWakeService.platformOs == PushWakeOs.android)
              SettingsSectionTitle(l10n.tr('pushWakeTitleAndroid'), help: l10n.tr('pushWakeHelpAndroid'))
            else
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
            // Android: через Google или UnifiedPush (1.10.x).
            if (PushWakeService.platformOs == PushWakeOs.android && ref.watch(pushWakePrefsProvider).enabled) ...[
              SettingsSectionTitle(l10n.tr('pushWakeVia'), help: l10n.tr('pushWakeViaHelp')),
              const SettingsGroup(children: [_PushTransportPicker()]),
            ],
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

/// Способ доставки сигналов на Android: Google (FCM) или распространитель
/// UnifiedPush (1.10.x, просьба владельца 01.11.2026).
class _PushTransportPicker extends ConsumerStatefulWidget {
  const _PushTransportPicker();

  @override
  ConsumerState<_PushTransportPicker> createState() => _PushTransportPickerState();
}

class _PushTransportPickerState extends ConsumerState<_PushTransportPicker> {
  late Future<List<UpDistributor>> _list = ref.read(pushWakeServiceProvider).upDistributors();
  bool _busy = false;

  Future<void> _use(PushWakeTransport t, {String? distributor}) async {
    setState(() => _busy = true);
    try {
      await ref.read(pushWakeServiceProvider).useTransport(t, distributor: distributor);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(pushWakeServiceProvider);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    return FutureBuilder<List<UpDistributor>>(
      future: _list,
      builder: (context, snap) {
        final list = snap.data ?? const <UpDistributor>[];
        final current = s.transport == PushWakeTransport.unifiedpush ? 'up:${s.upDistributor ?? ''}' : 'fcm';
        void pick(String? v) {
          if (v == null || _busy || v == current) return;
          if (v == 'fcm') {
            unawaited(_use(PushWakeTransport.fcm));
          } else {
            unawaited(_use(PushWakeTransport.unifiedpush, distributor: v.substring(3)));
          }
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (s.fcmAvailable)
            AppRadioTile<String>(
              title: Text(l10n.tr('pushWakeViaGoogle')),
              subtitle: Text(l10n.tr('pushWakeViaGoogleDesc'), style: muted),
              value: 'fcm',
              groupValue: current,
              onChanged: pick,
            ),
          for (final d in list)
            AppRadioTile<String>(
              title: Text(l10n.tr('pushWakeViaUp').replaceAll('{app}', d.name)),
              subtitle: Text(l10n.tr('pushWakeViaUpDesc'), style: muted),
              value: 'up:${d.id}',
              groupValue: current,
              onChanged: pick,
            ),
          if (snap.connectionState == ConnectionState.done && list.isEmpty)
            ListTile(
              leading: const Icon(AppIcons.info),
              title: Text(l10n.tr('pushWakeNoDistributor')),
              subtitle: Text(l10n.tr('pushWakeNoDistributorDesc'), style: muted),
              trailing: IconButton(
                tooltip: l10n.tr('refresh'),
                icon: const Icon(AppIcons.refresh),
                onPressed: () => setState(() => _list = s.upDistributors()),
              ),
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ]);
      },
    );
  }
}

/// «Строк текста в уведомлении»: рабочие и личные ящики — по ряду кнопок
/// (NotificationLines.options). Ящик рабочий или личный — по выбору в его
/// настройках (AccountModel.isWork).
class _NotificationLinesTile extends ConsumerStatefulWidget {
  final bool enabled;
  const _NotificationLinesTile({required this.enabled});

  @override
  ConsumerState<_NotificationLinesTile> createState() => _NotificationLinesTileState();
}

class _NotificationLinesTileState extends ConsumerState<_NotificationLinesTile> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = ref.watch(sharedPrefsProvider);
    Widget row(String label, bool work) {
      final v = NotificationLines.of(prefs, work: work);
      return Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Row(children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          SegmentedButton<int>(
            key: ValueKey('notifLines_${work ? 'work' : 'personal'}'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final n in NotificationLines.options) ButtonSegment<int>(value: n, label: Text('$n')),
            ],
            selected: {v},
            onSelectionChanged: widget.enabled
                ? (sel) {
                    unawaited(prefs.setInt(work ? NotificationLines.prefWork : NotificationLines.prefPersonal, sel.first));
                    setState(() {});
                  }
                : null,
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(AppIcons.notes, size: Sizes.icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.l),
            Expanded(child: Text(l10n.tr('notifyLinesTitle'), style: theme.textTheme.bodyLarge)),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: Sizes.icon + Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Space.xs),
                Text(l10n.tr('notifyLinesHint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                row(l10n.tr('groupPresetWork'), true),
                row(l10n.tr('groupPresetPersonal'), false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

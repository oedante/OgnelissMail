// lib/features/settings/screens/delivery_schedule_screen.dart
// «Расписание доставки» для ящиков в режиме «По расписанию»: рабочие часы и
// дни — мгновенная доставка (push), остальное время — проверка раз в 15,
// 30 или 60 минут. Одно расписание на все такие ящики (sync_schedule.dart).

import '../../../widgets/ui/wheel_pickers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart' show SyncInterval;
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../services/sync/imap_push_service.dart';
import '../../../services/sync/sync_schedule.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../providers/settings_provider.dart';

const _dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Расписание изменилось — экраны с его подписью перерисовываются.
final deliveryScheduleRevisionProvider = StateProvider<int>((ref) => 0);

/// «пн–пт», «каждый день», «выходные» или «пн, ср, пт».
String scheduleDaysLabel(Set<int> days, AppLocalizations l10n) {
  final d = days.toList()..sort();
  if (d.length == 7) return l10n.tr('everyDay').toLowerCase();
  if (d.isEmpty) return '—';
  if (d.length == 2 && d[0] == 6 && d[1] == 7) return l10n.tr('weekend').toLowerCase();
  // Подряд идущие дни — диапазоном.
  final contiguous = d.last - d.first + 1 == d.length;
  String n(int x) => l10n.tr(_dayKeys[x - 1]).toLowerCase();
  if (contiguous && d.length > 2) return '${n(d.first)}–${n(d.last)}';
  return d.map(n).join(', ');
}

class DeliveryScheduleScreen extends ConsumerStatefulWidget {
  const DeliveryScheduleScreen({super.key});

  @override
  ConsumerState<DeliveryScheduleScreen> createState() => _DeliveryScheduleScreenState();
}

class _DeliveryScheduleScreenState extends ConsumerState<DeliveryScheduleScreen> {
  Future<void> _save({int? start, int? end, Set<int>? days, int? off}) async {
    await SyncSchedule.save(ref.read(sharedPrefsProvider), start: start, end: end, days: days, off: off);
    if (!mounted) return;
    setState(() {});
    ref.read(deliveryScheduleRevisionProvider.notifier).state++;
    // Сразу применить: в рабочие часы — поднять push, вне — погасить.
    unawaited(ref.read(imapPushServiceProvider).ensureAlive(reason: 'расписание доставки'));
    final st = ref.read(settingsProvider);
    if (keepAliveNeeded(
        keepAliveSetting: st.backgroundKeepAlive,
        globalInterval: st.syncIntervalMinutes,
        accounts: ref.read(accountsProvider))) {
      unawaited(ref.read(foregroundSyncControllerProvider).start());
    }
  }

  Future<void> _pickTime(bool start) async {
    final m = start ? SyncSchedule.startMinutes : SyncSchedule.endMinutes;
    final t = await showWheelTimePicker(context, initial: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null) return;
    final v = t.hour * 60 + t.minute;
    await (start ? _save(start: v) : _save(end: v));
  }

  String _hm(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheduled = ref
        .watch(accountsProvider)
        .where((a) => a.isActive && a.syncInterval == SyncInterval.scheduled)
        .map((a) => a.email)
        .toList();
    final now = SyncSchedule.inWindow();
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('scheduleTitle')), actions: [
        HelpButton(text: l10n.tr('scheduleHelp'), title: l10n.tr('scheduleTitle')),
      ])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsIntro(now ? l10n.tr('scheduleNowPush') : l10n.tr('scheduleNowInterval')
              .replaceAll('{n}', '${SyncSchedule.offMinutes}')),

          SettingsSectionTitle(l10n.tr('scheduleWorkHours')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.wb_sunny,
              title: l10n.tr('fromTime'),
              trailing: Text(_hm(SyncSchedule.startMinutes)),
              onTap: () => _pickTime(true),
            ),
            SettingsItem(
              icon: AppIcons.bedtime,
              title: l10n.tr('toTime'),
              trailing: Text(_hm(SyncSchedule.endMinutes)),
              onTap: () => _pickTime(false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(l10n.tr(_dayKeys[d - 1])),
                      selected: SyncSchedule.days.contains(d),
                      onSelected: (on) {
                        final next = {...SyncSchedule.days};
                        on ? next.add(d) : next.remove(d);
                        unawaited(_save(days: next));
                      },
                    ),
                ],
              ),
            ),
          ]),

          SettingsSectionTitle(l10n.tr('scheduleOffHours')),
          SettingsGroup(children: [
            for (final m in const [15, 30, 60])
              AppRadioTile<int>(
                title: Text(m == 60 ? l10n.tr('checkHourly') : l10n.tr('checkEvery').replaceAll('{n}', '$m')),
                value: m,
                groupValue: SyncSchedule.offMinutes,
                onChanged: (v) => _save(off: v),
              ),
          ]),

          SettingsSectionTitle(l10n.tr('scheduleAccounts')),
          SettingsGroup(children: [
            if (scheduled.isEmpty)
              SettingsItem(icon: AppIcons.info, title: l10n.tr('scheduleNoAccounts'), onTap: null)
            else
              for (final e in scheduled) SettingsItem(icon: AppIcons.mail, title: e, onTap: null),
          ]),
        ],
      ),
    );
  }
}

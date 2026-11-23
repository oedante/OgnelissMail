// lib/features/settings/screens/sync_settings_screen.dart
// «Синхронизация» (замечание владельца 18.11.2026: «что в настройках лежит
// не там»): общий выключатель проверки почты, расписание и конфликты —
// в «Аккаунтах» на главном экране настроек, рядом с ящиками. Раньше были в
// «Дополнительно». Интервал и push — у каждого ящика (экран ящика →
// «Проверка почты»).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/background_service.dart';
import '../../../services/sync/imap_push_service.dart';
import '../../../services/sync/sync_schedule.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../providers/settings_provider.dart';
import 'delivery_schedule_screen.dart' show scheduleDaysLabel, deliveryScheduleRevisionProvider;

class SyncSettingsScreen extends ConsumerWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    ref.watch(deliveryScheduleRevisionProvider); // подпись «Расписания доставки»
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('sync')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            SettingsGroup(children: [
              // Интервал и push — у каждого аккаунта (экран аккаунта →
              // «Проверка почты»). Здесь — общий выключатель.
              SettingsSwitchItem(
                icon: AppIcons.sync,
                title: l10n.tr('autoSyncAll'),
                subtitle: l10n.tr('autoSyncAllDesc'),
                value: settings.syncIntervalMinutes >= 0,
                onChanged: (v) async {
                  await ref.read(settingsProvider.notifier).setSyncInterval(v ? 15 : -1);
                  await ref.read(backgroundServiceProvider).applySyncInterval();
                  final push = ref.read(imapPushServiceProvider);
                  if (v) {
                    await push.start();
                  } else {
                    await push.stopAll();
                  }
                },
              ),
              // «По расписанию»: рабочие часы — мгновенно, остальное — по интервалу.
              SettingsItem(
                icon: AppIcons.schedule,
                title: l10n.tr('scheduleTitle'),
                subtitle: '${SyncSchedule.windowLabel()} · ${scheduleDaysLabel(SyncSchedule.days, l10n)} · '
                    '${l10n.tr('scheduleOffShort').replaceAll('{n}', '${SyncSchedule.offMinutes}')}',
                onTap: () => context.push('/settings/delivery-schedule'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

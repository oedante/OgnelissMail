// lib/features/settings/screens/profile_settings_screen.dart
// Настройки функций ядра: вкладка «Задачи», окно отмены отправки,
// подтверждение адресатов, порог антифишинга. Профили «Базовый/Расширенный»
// убраны вместе с модулями, которые они включали (этап 1 плана).

import '../../../widgets/ui/wheel_pickers.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/feature_flags_provider.dart';
import '../providers/settings_provider.dart';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final f = ref.watch(featureFlagsProvider);
    final n = ref.read(featureFlagsProvider.notifier);
    final st = ref.watch(settingsProvider);
    final sn = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('profileFeatures')),
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('sections')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.check_box,
              title: l10n.tr('tasksTab'),
              value: f.showTasksTab,
              onChanged: n.setTasksTab,
            ),
            // Заметки и файловый хаб — отключаемые разделы (1.5.9).
            SettingsSwitchItem(
              icon: AppIcons.sticky_note_2,
              title: l10n.tr('notes'),
              subtitle: l10n.tr('notesSectionDesc'),
              value: f.showNotes,
              onChanged: n.setNotes,
            ),
            SettingsSwitchItem(
              icon: AppIcons.folder_copy,
              title: l10n.tr('fileHub'),
              subtitle: l10n.tr('fileHubSectionDesc'),
              value: f.showFileHub,
              onChanged: n.setFileHub,
            ),
            SettingsSwitchItem(
              icon: AppIcons.myDay,
              title: l10n.tr('myDay'),
              subtitle: l10n.tr('myDaySettingShort'),
              hint: l10n.tr('myDaySettingDesc'),
              value: st.myDay,
              onChanged: sn.setMyDay,
            ),
            SettingsSwitchItem(
              icon: AppIcons.task_alt,
              title: l10n.tr('controlFilter'),
              subtitle: l10n.tr('controlSettingDesc'),
              value: st.mailControl,
              onChanged: sn.setMailControl,
            ),
            SettingsSwitchItem(
              icon: AppIcons.notifications_active,
              title: l10n.tr('digestSetting'),
              subtitle: l10n.tr('digestSettingShort'),
              hint: l10n.tr('digestSettingDesc'),
              value: st.morningDigest,
              onChanged: (v) async {
                await sn.setMorningDigest(v);
                await ref.read(reminderSchedulerProvider).rescheduleAll();
              },
            ),
            if (st.morningDigest)
              SettingsItem(
                icon: AppIcons.schedule,
                title: l10n.tr('digestTime'),
                subtitle: _hhmm(st.morningDigestMinutes),
                onTap: () async {
                  final t = await showWheelTimePicker(context,
                      initial: TimeOfDay(hour: st.morningDigestMinutes ~/ 60, minute: st.morningDigestMinutes % 60));
                  if (t == null) return;
                  await sn.setMorningDigestMinutes(t.hour * 60 + t.minute);
                  await ref.read(reminderSchedulerProvider).rescheduleAll();
                },
              ),
          ]),
          // «Отправка» и «Антифишинг» перенесены в «Настройки почты».
        ],
      ),
    );
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

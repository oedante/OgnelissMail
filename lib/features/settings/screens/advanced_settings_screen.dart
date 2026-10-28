// lib/features/settings/screens/advanced_settings_screen.dart
// «Расширенные настройки» (1.8.0, решение владельца 26.10.2026: «часть …
// общих настроек вынести в разделы „Расширенные настройки“, а остальные
// разнести по категориям»). Здесь то, что нужно редко: общий выключатель
// синхронизации и расписание доставки, конфликты синхронизации, разрешения
// и работа в фоне, проверка сертификатов, защита данных при отправке,
// разделы приложения, журнал и сброс.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/background_service.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../services/security/remote_wipe_service.dart';
import '../../../services/sync/imap_push_service.dart';
import '../../../services/sync/sync_schedule.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../providers/settings_provider.dart';
import 'delivery_schedule_screen.dart' show scheduleDaysLabel, deliveryScheduleRevisionProvider;

class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    ref.watch(deliveryScheduleRevisionProvider); // подпись «Расписания доставки»

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('advancedSettings')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            // ── Синхронизация ──
            SettingsSectionTitle(l10n.tr('sync')),
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
              SettingsItem(
                icon: AppIcons.sync_problem,
                title: l10n.tr('syncConflicts'),
                subtitle: l10n.tr('syncConflictsDesc'),
                onTap: () => context.push('/settings/conflicts'),
              ),
            ]),

            // ── Работа в фоне ──
            SettingsSectionTitle(l10n.tr('sectionBackground')),
            SettingsGroup(children: [
              // «Работать в фоне», «Скрыть уведомление о работе в фоне» и
              // «Обновление в фоне» (iOS) — на экране «Разрешения».
              SettingsItem(
                icon: AppIcons.admin_panel_settings,
                title: l10n.tr('permissions'),
                // Замечено замораживание в фоне — подсказка прямо здесь.
                subtitle: ForegroundSyncController.frozenRecently(ref.read(sharedPrefsProvider))
                    ? '⚠ ${l10n.tr('bgFrozenTitle')}'
                    : l10n.tr('permissionsDesc'),
                onTap: () => context.push('/settings/permissions'),
              ),
            ]),

            // ── Безопасность ──
            SettingsSectionTitle(l10n.tr('security')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.verified_user,
                title: l10n.tr('connectionSecurity'),
                subtitle: l10n.tr('connectionSecurityDesc'),
                onTap: () => context.push('/settings/security'),
              ),
              SettingsItem(
                icon: AppIcons.shield,
                title: l10n.tr('dlpTitle'),
                subtitle: l10n.tr('dlpSettingsDesc'),
                onTap: () => context.push('/settings/dlp'),
              ),
            ]),

            // ── Приложение ──
            SettingsSectionTitle(l10n.tr('sectionApp')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.widgets,
                title: l10n.tr('profileFeatures'),
                subtitle: l10n.tr('profileFeaturesDesc'),
                onTap: () => context.push('/settings/profile'),
              ),
              SettingsItem(
                icon: AppIcons.bug_report,
                title: l10n.tr('logsTitle'),
                subtitle: l10n.tr('logsDesc'),
                onTap: () => context.push('/settings/logs'),
              ),
              // Необратимое — красным и отдельной строкой (с подтверждением).
              SettingsItem(
                icon: AppIcons.delete_forever,
                title: l10n.tr('resetApp'),
                color: theme.colorScheme.error,
                onTap: () => _showResetDialog(context, ref, l10n),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(AppIcons.warning, color: AppColors.errorText(ctx), size: 48),
        title: Text(l10n.tr('resetApp')),
        content: Text(l10n.tr('wipeWarning')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Полная очистка всех данных (как remote wipe) + сброс настроек
              await ref.read(remoteWipeProvider).wipeAll();
              await ref.read(settingsProvider.notifier).resetAll();
              if (context.mounted) context.go('/login');
            },
            child: Text(l10n.tr('resetApp'), style: TextStyle(color: AppColors.errorText(context))),
          ),
        ],
      ),
    );
  }
}

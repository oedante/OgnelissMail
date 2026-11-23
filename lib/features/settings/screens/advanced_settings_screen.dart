// lib/features/settings/screens/advanced_settings_screen.dart
// «Расширенные настройки» (1.8.0, решение владельца 26.10.2026: «часть …
// общих настроек вынести в разделы „Расширенные настройки“, а остальные
// разнести по категориям»). Здесь то, что нужно редко: разделы приложения,
// графика (Android), журнал и сброс. Синхронизация — в «Аккаунтах»
// (sync_settings_screen.dart, 18.11.2026).
//
// 2.7.0 (замечание владельца 22.11.2026: «не убирать без потери функций, а
// автоматизировать выбор того, в чём пользователь не разберётся»): сюда —
// ручной выбор того, что приложение выбирает само: проверка почты в фоне
// (сигналы сервера, «Работать в фоне») и беседы Android в уведомлениях.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/graphics_mode.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/remote_wipe_service.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../providers/settings_provider.dart';
import '../widgets/graphics_item.dart';
import 'background_delivery_screen.dart' show backgroundDeliveryAvailable;

class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('advancedSettings')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            // «Синхронизация» — на главном экране настроек, в «Аккаунтах»
            // (замечание владельца 18.11.2026: искали рядом с ящиками).

            // «Разрешения» — на главном экране, в «Конфиденциальности».

            // ── Синхронизация: проверка почты в фоне (выбирается сама) и
            // конфликты (решаются сами, 2.7.2 — из «Синхронизации») ──
            SettingsSectionTitle(l10n.tr('sync')),
            SettingsGroup(children: [
              if (backgroundDeliveryAvailable)
                SettingsItem(
                  key: const ValueKey('adv_bg_delivery'),
                  icon: AppIcons.cloud_sync,
                  title: l10n.tr('pushWakeTitleAndroid'),
                  subtitle: l10n.tr('bgDeliveryAutoShort'),
                  onTap: () => context.push('/settings/background-delivery'),
                ),
              SettingsItem(
                key: const ValueKey('adv_conflicts'),
                icon: AppIcons.sync_problem,
                title: l10n.tr('syncConflicts'),
                subtitle: l10n.tr('syncConflictsDesc'),
                onTap: () => context.push('/settings/conflicts'),
              ),
            ]),

            // ── Безопасность для администратора (2.7.2, из
            // «Конфиденциальности»): сертификаты серверов и защита данных —
            // настраивает организация (MDM) или администратор ──
            SettingsSectionTitle(l10n.tr('advancedSecurity')),
            SettingsGroup(children: [
              SettingsItem(
                key: const ValueKey('adv_conn_security'),
                icon: AppIcons.verified_user,
                title: l10n.tr('connectionSecurity'),
                subtitle: l10n.tr('connectionSecurityDesc'),
                onTap: () => context.push('/settings/security'),
              ),
              SettingsItem(
                key: const ValueKey('adv_dlp'),
                icon: AppIcons.shield,
                title: l10n.tr('dlpTitle'),
                subtitle: l10n.tr('dlpSettingsDesc'),
                onTap: () => context.push('/settings/dlp'),
              ),
            ]),

            // ── Беседы Android в уведомлениях (по умолчанию: VIP и письма
            // людей — беседами, рассылки — обычным видом) ──
            if (android && settings.notificationMessengerStyle) ...[
              SettingsSectionTitle(l10n.tr('notifications')),
              SettingsGroup(children: [
                SettingsSwitchItem(
                  icon: AppIcons.forum,
                  title: l10n.tr('notifyVipConversations'),
                  subtitle: l10n.tr('notifyVipConversationsDesc'),
                  value: settings.notificationVipConversations,
                  onChanged: settings.notificationsEnabled ? (v) => notifier.setNotificationVipConversations(v) : null,
                ),
                SettingsSwitchItem(
                  icon: AppIcons.forum,
                  title: l10n.tr('notifyPeopleConversations'),
                  subtitle: l10n.tr('notifyPeopleConversationsDesc'),
                  value: settings.notificationPeopleConversations || settings.notificationAllConversations,
                  onChanged: settings.notificationsEnabled && !settings.notificationAllConversations
                      ? (v) => notifier.setNotificationPeopleConversations(v)
                      : null,
                ),
                SettingsSwitchItem(
                  icon: AppIcons.forum,
                  title: l10n.tr('notifyAllConversations'),
                  subtitle: l10n.tr('notifyAllConversationsDesc'),
                  value: settings.notificationAllConversations,
                  onChanged: settings.notificationsEnabled ? (v) => notifier.setNotificationAllConversations(v) : null,
                ),
              ]),
            ],

            // ── Приложение ──
            SettingsSectionTitle(l10n.tr('sectionApp')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.widgets,
                title: l10n.tr('profileFeatures'),
                subtitle: l10n.tr('profileFeaturesDesc'),
                onTap: () => context.push('/settings/profile'),
              ),
              // Движок рисования (Android, 08.11.2026: чёрный экран на Huawei).
              if (GraphicsMode.supported) const GraphicsItem(),
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

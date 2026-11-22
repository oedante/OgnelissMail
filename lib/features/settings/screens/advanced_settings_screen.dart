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

            // «Разрешения», безопасность соединения и защита данных (DLP) —
            // на главном экране, в «Конфиденциальности» (перегруппировка
            // 08.11.2026): здесь они повторялись.

            // ── Проверка почты в фоне: само, вручную — здесь ──
            if (backgroundDeliveryAvailable) ...[
              SettingsSectionTitle(l10n.tr('sync')),
              SettingsGroup(children: [
                SettingsItem(
                  key: const ValueKey('adv_bg_delivery'),
                  icon: AppIcons.cloud_sync,
                  title: l10n.tr('pushWakeTitleAndroid'),
                  subtitle: l10n.tr('bgDeliveryAutoShort'),
                  onTap: () => context.push('/settings/background-delivery'),
                ),
              ]),
            ],

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

// lib/features/settings/screens/settings_screen.dart
// Главный экран настроек (1.8.0, решение владельца 26.10.2026): по
// категориям — аккаунты, основное (вид и язык, уведомления, специальные
// возможности), почта, разделы, защита, данные, справка; редкое —
// в «Расширенных настройках» (advanced_settings_screen.dart).

import '../../../core/utils/text_safe.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../widgets/common/hero_email_transition.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../mail/providers/mail_providers.dart';
import '../providers/settings_provider.dart';
import '../providers/feature_flags_provider.dart';
import '../../../services/security/pin_lock_service.dart';
import '../../../services/mail/focus_mode_service.dart';
import '../../../services/security/tracker_blocker.dart';
import 'tracker_settings_screen.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../settings_search.dart';
import '../../../core/theme/tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider);
    final settings = ref.watch(settingsProvider);
    final pinState = ref.watch(pinLockProvider);
    final focusState = ref.watch(focusModeProvider);
    final trackerState = ref.watch(trackerBlockerProvider);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        leading: IconButton(tooltip: l10n.tr('back'), icon: const Icon(AppIcons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text(l10n.settingsLabel),
        actions: [
          IconButton(
            tooltip: l10n.tr('settingsSearchHint'),
            icon: const Icon(AppIcons.search),
            onPressed: () => showSearch(context: context, delegate: SettingsSearchDelegate(l10n)),
          ),
        ],
      )),
      // На широком экране форма настроек в одну колонку во всю ширину читается
      // плохо — ограничиваем (для форм комфортнее уже, чем для текста письма).
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // ── Аккаунты: настройки ящика (подпись, адреса, синхронизация папок,
          // автоответ, правила, удаление) — на экране аккаунта.
          SettingsSectionTitle(l10n.tr('accounts')),
          SettingsGroup(children: [
            for (final a in accounts)
              SettingsItem(
                leading: HeroEmailAvatar(
                  emailId: 'settings/${a.id}',
                  radius: 20,
                  color: Color(a.colorValue),
                  initial: a.displayName.isNotEmpty ? initialOf(a.displayName) : '?',
                  hero: false,
                  email: a.email,
                  photo: a.avatarUrl,
                ),
                title: a.displayName,
                subtitle: a.email,
                subtitleOneLine: true,
                onTap: () => context.push('/settings/account/${Uri.encodeComponent(a.id)}'),
              ),
            SettingsItem(
              icon: AppIcons.manage_accounts,
              title: l10n.tr('accounts'),
              subtitle: l10n.tr('accountsManageSubtitle'),
              onTap: () => context.push('/settings/accounts'),
            ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('addAccount'),
              onTap: () => context.push('/login?mode=add'),
            ),
            // Сборка без Exchange (1.8.5): добавленные ящики Exchange скрыты.
            if (hiddenExchangeAccounts > 0)
              SettingsItem(
                icon: AppIcons.info,
                title: l10n.tr('exchangeHiddenTitle').replaceAll('{n}', '$hiddenExchangeAccounts'),
                subtitle: l10n.tr('exchangeHiddenDesc'),
                onTap: null,
              ),
            SettingsItem(
              icon: AppIcons.folder_shared,
              title: l10n.tr('accountGroups'),
              subtitle: l10n.tr('accountGroupsSubtitle'),
              onTap: () => context.push('/settings/groups'),
            ),
          ]),

          // ── Основное ──
          SettingsSectionTitle(l10n.tr('sectionGeneral')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.palette,
              title: l10n.tr('general'),
              subtitle: '${l10n.tr('appearance')}, ${l10n.tr('language')}',
              onTap: () => context.push('/settings/general'),
            ),
            // Уведомления, тихие часы, режим фокуса и VIP — на одном экране.
            SettingsItem(
              icon: AppIcons.notifications,
              title: l10n.tr('notifications'),
              subtitle: [
                settings.notificationsEnabled ? l10n.tr('enabled') : l10n.tr('disabled'),
                if (focusState.isEnabled) '${l10n.tr('focusMode')}: ${focusState.deliveryTimes.join(', ')}',
              ].join(' · '),
              onTap: () => context.push('/settings/notifications'),
            ),
            // Система замораживает приложение — «Разрешения» прямо здесь, с
            // подсказкой (обычно они в «Расширенных настройках»).
            if (ForegroundSyncController.frozenRecently(ref.read(sharedPrefsProvider)))
              SettingsItem(
                icon: AppIcons.admin_panel_settings,
                title: l10n.tr('permissions'),
                subtitle: '⚠ ${l10n.tr('bgFrozenTitle')}',
                onTap: () => context.push('/settings/permissions'),
              ),
            SettingsItem(
              icon: AppIcons.accessibility_new,
              title: l10n.tr('accessibility'),
              subtitle: l10n.tr('highContrast'),
              onTap: () => context.push('/settings/accessibility'),
            ),
          ]),

          // ── Почта ──
          SettingsSectionTitle(l10n.tr('sectionMail')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.mail,
              title: l10n.tr('emailSettings'),
              subtitle: l10n.tr('emailSettingsDesc'),
              onTap: () => context.push('/settings/mail'),
            ),
            SettingsItem(
              icon: AppIcons.swipe,
              title: l10n.tr('swipeSettings'),
              subtitle: l10n.tr('swipeHint'),
              onTap: () => context.push('/settings/swipes'),
            ),
            if (kRulesAndCategoriesEnabled)
            SettingsItem(
              icon: AppIcons.label,
              title: l10n.tr('categories'),
              subtitle: l10n.tr('categoriesDesc'),
              onTap: () => context.push('/settings/categories'),
            ),
            SettingsItem(
              icon: AppIcons.article,
              title: l10n.tr('templatesSignature'),
              subtitle: l10n.tr('templatesSignatureDesc'),
              onTap: () => context.push('/settings/templates'),
            ),
            // Правила на телефоне и VIP — тот же экран, что из «Уведомлений».
            SettingsItem(
              icon: AppIcons.rule,
              title: l10n.tr('vipRulesTitle'),
              subtitle: l10n.tr('vipRulesDesc'),
              onTap: () => context.push('/vip-settings'),
            ),
            if (kRulesAndCategoriesEnabled)
            SettingsItem(
              icon: AppIcons.rule,
              title: l10n.tr('automation'),
              subtitle: l10n.tr('automationDesc'),
              onTap: () => context.push('/settings/automation'),
            ),
          ]),

          // ── Разделы ──
          SettingsSectionTitle(l10n.tr('modules')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.calendar_today,
              title: l10n.tr('calendar'),
              subtitle: l10n.tr('calendarModuleDesc'),
              onTap: () => context.push('/settings/calendar'),
            ),
            SettingsItem(
              icon: AppIcons.contacts,
              title: l10n.contactsLabel,
              subtitle: l10n.tr('contactsModuleDesc'),
              onTap: () => context.push('/settings/contacts'),
            ),
            SettingsItem(
              icon: AppIcons.check_box,
              title: l10n.tasksLabel,
              subtitle: l10n.tr('tasksModuleDesc'),
              onTap: () => context.push('/settings/tasks'),
            ),
            if (ref.watch(featureFlagsProvider).showNotes)
              SettingsItem(
                icon: AppIcons.sticky_note_2,
                title: l10n.tr('notes'),
                subtitle: l10n.tr('mailModuleDesc'),
                onTap: () => context.push('/settings/notes'),
              ),
          ]),

          // ── Защита ──
          SettingsSectionTitle(l10n.tr('security')),
          SettingsGroup(children: [
            // Код при входе. Отпечаток или лицо — кнопкой на экране кода
            // (раньше — отдельная шторка с неактивной строкой «Биометрия»).
            SettingsSwitchItem(
              icon: AppIcons.pin,
              title: l10n.tr('pinLock'),
              subtitle: l10n.tr('pinLockDesc'),
              value: pinState.isPinSet,
              onChanged: (v) {
                if (v) {
                  _showSetPinDialog(context, ref, l10n);
                } else {
                  ref.read(pinLockProvider.notifier).removePin();
                }
              },
            ),
            SettingsItem(
              icon: AppIcons.visibility_off,
              title: l10n.tr('trackerBlocker'),
              subtitle: '${trackerState.totalBlocked} ${l10n.tr('trackersBlocked').toLowerCase()}',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrackerSettingsScreen())),
            ),
          ]),

          // ── Данные ──
          SettingsSectionTitle(l10n.tr('sectionData')),
          SettingsGroup(children: [
            // Архив Ogneliss (1.7.3): старая почта, встречи, задачи,
            // контакты и настройки — в зашифрованный архив на устройстве.
            SettingsItem(
              icon: AppIcons.inventory_2,
              title: l10n.tr('ognaArchive'),
              subtitle: l10n.tr('archiveSettingsDesc'),
              onTap: () => context.push('/settings/archive'),
            ),
            // Резервная копия ящиков и настроек — перенос на новый телефон.
            SettingsItem(
              icon: AppIcons.settings_backup_restore,
              title: l10n.tr('backupTitle'),
              subtitle: l10n.tr('backupDesc'),
              onTap: () => context.push('/settings/backup'),
            ),
            SettingsItem(
              icon: AppIcons.storage,
              title: l10n.tr('storage'),
              subtitle: l10n.tr('storageDesc'),
              onTap: () => context.push('/settings/storage'),
            ),
          ]),

          // ── Справка ──
          SettingsSectionTitle(l10n.tr('sectionHelp')),
          SettingsGroup(children: [
            // Вопросы и ответы по разделам приложения и настройкам (1.7.1).
            SettingsItem(
              icon: AppIcons.help,
              title: l10n.tr('faqTitle'),
              subtitle: l10n.tr('faqDesc'),
              onTap: () => context.push('/settings/faq'),
            ),
            SettingsItem(
              icon: AppIcons.info,
              title: l10n.tr('about'),
              subtitle: '${AppConstants.appName} v${AppConstants.appVersion}',
              onTap: () => context.push('/settings/about'),
            ),
          ]),

          // ── Расширенные настройки (1.8.0, решение владельца 26.10.2026):
          // синхронизация и фон, сертификаты, защита данных, разделы
          // приложения, журнал, сброс — то, что нужно редко.
          const SizedBox(height: Space.l),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.tune,
              title: l10n.tr('advancedSettings'),
              subtitle: l10n.tr('advancedSettingsDesc'),
              onTap: () => context.push('/settings/advanced'),
            ),
          ]),
        ],
      ),
      ),
    );
  }

  // ════════════════════════ SHEETS ════════════════════════

  void _showSetPinDialog(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('setPin')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          // Только цифры: экран блокировки вводит только цифры, и PIN с
          // буквами навсегда закрыл бы доступ к приложению.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          obscureText: true,
          decoration: InputDecoration(hintText: l10n.tr('pinHint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(onPressed: () {
            if (controller.text.length >= 4) {
              ref.read(pinLockProvider.notifier).setPin(controller.text);
              Navigator.of(ctx).pop();
              HapticFeedback.mediumImpact();
            }
          }, child: Text(l10n.save)),
        ],
      ),
    );
  }
}

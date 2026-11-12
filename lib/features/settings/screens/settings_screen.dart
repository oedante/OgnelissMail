// lib/features/settings/screens/settings_screen.dart
// Главный экран настроек (1.8.0, решение владельца 26.10.2026): по
// категориям — аккаунты, основное (вид и язык, уведомления, специальные
// возможности), почта, разделы, защита, данные, справка; редкое —
// в «Расширенных настройках» (advanced_settings_screen.dart).

import '../../../services/translation/translator.dart' show translationPlatformSupported;
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
import '../widgets/settings_split.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../settings_search.dart';
import '../../../core/theme/tokens.dart';
import '../widgets/managed_policy_section.dart';
import '../../../services/security/managed_config.dart';

class SettingsScreen extends ConsumerWidget {
  /// Список разделов слева в две колонки (компьютер, планшет —
  /// [SettingsSplitFrame]): строки без пояснений, выбранный раздел выделен,
  /// раздел открывается справа.
  final bool pane;

  /// Раздел, открытый справа ([currentSettingsSection]).
  final String selected;

  const SettingsScreen({super.key, this.pane = false, this.selected = '/settings'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider);
    final settings = ref.watch(settingsProvider);
    final pinState = ref.watch(pinLockProvider);
    final mdmPin = ref.watch(managedPolicyProvider.select((p) => p.requireAppLock));
    final focusState = ref.watch(focusModeProvider);
    final trackerState = ref.watch(trackerBlockerProvider);
    // Из списка раздел открывается с отметкой: в две колонки — справа
    // вместо открытого, без «Назад».
    void open(String location) => openSettingsSectionWith(
        GoRouter.of(context), Navigator.of(context, rootNavigator: true), location,
        split: pane);
    bool sel(String location) => pane && settingsSectionSelected(location, selected);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        leading: IconButton(
            tooltip: l10n.tr('back'),
            icon: const Icon(AppIcons.arrow_back),
            onPressed: () => pane ? closeSettings(context) : Navigator.of(context).pop()),
        title: Text(l10n.settingsLabel),
        actions: [
          IconButton(
            tooltip: l10n.tr('settingsSearchHint'),
            icon: const Icon(AppIcons.search),
            onPressed: () => showSearch(context: context, delegate: SettingsSearchDelegate(l10n, split: pane)),
          ),
        ],
      )),
      body: _list([
          // ── Управляется организацией (MDM, 1.10.5) — только если задано.
          const ManagedPolicySection(),
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
                selected: sel('/settings/account/${Uri.encodeComponent(a.id)}'),
              onTap: () => open('/settings/account/${Uri.encodeComponent(a.id)}'),
              ),
            SettingsItem(
              icon: AppIcons.manage_accounts,
              title: l10n.tr('accounts'),
              subtitle: l10n.tr('accountsManageSubtitle'),
              selected: sel('/settings/accounts'),
              onTap: () => open('/settings/accounts'),
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
            // Правила организации (MDM allowed_domains, план 08.11.2026 п. 1):
            // ящики чужих доменов скрыты, данные остаются.
            if (hiddenByPolicyAccounts.isNotEmpty)
              SettingsItem(
                icon: AppIcons.info,
                title: l10n.tr('policyHiddenTitle').replaceAll('{n}', '${hiddenByPolicyAccounts.length}'),
                subtitle: l10n.tr('policyHiddenDesc').replaceAll('{list}', hiddenByPolicyAccounts.join(', ')),
                onTap: null,
              ),
            SettingsItem(
              icon: AppIcons.folder_shared,
              title: l10n.tr('accountGroups'),
              subtitle: l10n.tr('accountGroupsSubtitle'),
              selected: sel('/settings/groups'),
              onTap: () => open('/settings/groups'),
            ),
          ]),

          // ── Вид и язык (перегруппировка, согласовано владельцем 08.11.2026) ──
          SettingsSectionTitle(l10n.tr('sectionLookLanguage')),
          SettingsGroup(children: [
            // «Оформление» (1.9.x): тема, цвета, скругление, плотность ленты.
            SettingsItem(
              icon: AppIcons.format_paint,
              title: l10n.tr('appearanceTitle'),
              subtitle: l10n.tr('appearanceDescFull'),
              selected: sel('/settings/appearance'),
              onTap: () => open('/settings/appearance'),
            ),
            SettingsItem(
              icon: AppIcons.palette,
              title: l10n.tr('general'),
              subtitle: l10n.tr('generalDesc'),
              selected: sel('/settings/general'),
              onTap: () => open('/settings/general'),
            ),
            SettingsItem(
              icon: AppIcons.accessibility_new,
              title: l10n.tr('accessibility'),
              subtitle: l10n.tr('highContrast'),
              selected: sel('/settings/accessibility'),
              onTap: () => open('/settings/accessibility'),
            ),
          ]),

          // ── Уведомления ──
          SettingsSectionTitle(l10n.tr('notifications')),
          SettingsGroup(children: [
            // Уведомления, тихие часы, режим фокуса и VIP — на одном экране.
            SettingsItem(
              icon: AppIcons.notifications,
              title: l10n.tr('notifications'),
              subtitle: [
                settings.notificationsEnabled ? l10n.tr('enabled') : l10n.tr('disabled'),
                if (focusState.isEnabled) '${l10n.tr('focusMode')}: ${focusState.deliveryTimes.join(', ')}',
              ].join(' · '),
              selected: sel('/settings/notifications'),
              onTap: () => open('/settings/notifications'),
            ),
          ]),

          // ── Почта ──
          SettingsSectionTitle(l10n.tr('sectionMail')),
          SettingsGroup(children: [
            // «Настройки почты» — пятью экранами (12.11.2026, замечание
            // владельца: раздел был слишком крупным).
            SettingsItem(
              icon: AppIcons.mail,
              title: l10n.tr('mailReadingSettings'),
              subtitle: l10n.tr('mailReadingSettingsDesc'),
              selected: sel('/settings/mail'),
              onTap: () => open('/settings/mail'),
            ),
            SettingsItem(
              icon: AppIcons.edit,
              title: l10n.tr('mailComposeSettings'),
              subtitle: l10n.tr('mailComposeSettingsDesc'),
              selected: sel('/settings/mail/compose'),
              onTap: () => open('/settings/mail/compose'),
            ),
            SettingsItem(
              icon: AppIcons.download,
              title: l10n.tr('mailFilesSettings'),
              subtitle: l10n.tr('mailFilesSettingsDesc'),
              selected: sel('/settings/mail/files'),
              onTap: () => open('/settings/mail/files'),
            ),
            if (translationPlatformSupported)
              SettingsItem(
                icon: AppIcons.translate,
                title: l10n.tr('translateSection'),
                subtitle: l10n.tr('mailTranslateSettingsDesc'),
                selected: sel('/settings/mail/translate'),
                onTap: () => open('/settings/mail/translate'),
              ),
            SettingsItem(
              icon: AppIcons.swipe,
              title: l10n.tr('swipeSettings'),
              subtitle: l10n.tr('swipeHint'),
              selected: sel('/settings/swipes'),
              onTap: () => open('/settings/swipes'),
            ),
            if (kRulesAndCategoriesEnabled)
            SettingsItem(
              icon: AppIcons.label,
              title: l10n.tr('categories'),
              subtitle: l10n.tr('categoriesDesc'),
              selected: sel('/settings/categories'),
              onTap: () => open('/settings/categories'),
            ),
            SettingsItem(
              icon: AppIcons.article,
              title: l10n.tr('templatesSignature'),
              subtitle: l10n.tr('templatesSignatureDesc'),
              selected: sel('/settings/templates'),
              onTap: () => open('/settings/templates'),
            ),
            // Правила на телефоне и VIP — тот же экран, что из «Уведомлений».
            SettingsItem(
              icon: AppIcons.rule,
              title: l10n.tr('vipRulesTitle'),
              subtitle: l10n.tr('vipRulesDesc'),
              selected: sel('/vip-settings'),
              onTap: () => open('/vip-settings'),
            ),
            if (kRulesAndCategoriesEnabled)
            SettingsItem(
              icon: AppIcons.rule,
              title: l10n.tr('automation'),
              subtitle: l10n.tr('automationDesc'),
              selected: sel('/settings/automation'),
              onTap: () => open('/settings/automation'),
            ),
          ]),

          // ── Разделы ──
          SettingsSectionTitle(l10n.tr('sectionModules')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.calendar_today,
              title: l10n.tr('calendar'),
              subtitle: l10n.tr('calendarModuleDesc'),
              selected: sel('/settings/calendar'),
              onTap: () => open('/settings/calendar'),
            ),
            SettingsItem(
              icon: AppIcons.contacts,
              title: l10n.contactsLabel,
              subtitle: l10n.tr('contactsModuleDesc'),
              selected: sel('/settings/contacts'),
              onTap: () => open('/settings/contacts'),
            ),
            SettingsItem(
              icon: AppIcons.check_box,
              title: l10n.tasksLabel,
              subtitle: l10n.tr('tasksModuleDesc'),
              selected: sel('/settings/tasks'),
              onTap: () => open('/settings/tasks'),
            ),
            if (ref.watch(featureFlagsProvider).showNotes)
              SettingsItem(
                icon: AppIcons.sticky_note_2,
                title: l10n.tr('notes'),
                subtitle: l10n.tr('mailModuleDesc'),
                selected: sel('/settings/notes'),
              onTap: () => open('/settings/notes'),
              ),
          ]),

          // ── Конфиденциальность: PIN, трекеры, безопасность соединения,
          // разрешения (перегруппировка 08.11.2026) ──
          SettingsSectionTitle(l10n.tr('sectionPrivacy')),
          SettingsGroup(children: [
            // Код при входе. Отпечаток или лицо — кнопкой на экране кода
            // (раньше — отдельная шторка с неактивной строкой «Биометрия»).
            SettingsSwitchItem(
              icon: AppIcons.pin,
              title: l10n.tr('pinLock'),
              // Код требует организация (MDM) — выключить нельзя.
              subtitle: mdmPin ? l10n.tr('mdmPinRequired') : l10n.tr('pinLockDesc'),
              value: pinState.isPinSet,
              onChanged: mdmPin && pinState.isPinSet ? null : (v) {
                if (v) {
                  _showSetPinDialog(context, ref, l10n);
                } else {
                  ref.read(pinLockProvider.notifier).removePin();
                }
              },
            ),
            SettingsItem(
              icon: AppIcons.phishing,
              title: l10n.tr('antiPhishing'),
              subtitle: l10n.tr('mailSafetySettingsDesc'),
              selected: sel('/settings/mail/safety'),
              onTap: () => open('/settings/mail/safety'),
            ),
            SettingsItem(
              icon: AppIcons.visibility_off,
              title: l10n.tr('trackerBlocker'),
              subtitle: '${trackerState.totalBlocked} ${l10n.tr('trackersBlocked').toLowerCase()}',
              selected: sel('/settings/trackers'),
              onTap: () => open('/settings/trackers'),
            ),
            SettingsItem(
              icon: AppIcons.verified_user,
              title: l10n.tr('connectionSecurity'),
              subtitle: l10n.tr('connectionSecurityDesc'),
              selected: sel('/settings/security'),
              onTap: () => open('/settings/security'),
            ),
            SettingsItem(
              icon: AppIcons.shield,
              title: l10n.tr('dlpTitle'),
              subtitle: l10n.tr('dlpSettingsDesc'),
              selected: sel('/settings/dlp'),
              onTap: () => open('/settings/dlp'),
            ),
            // Система замораживает приложение — подсказка прямо в строке.
            SettingsItem(
              icon: AppIcons.admin_panel_settings,
              title: l10n.tr('permissions'),
              subtitle: ForegroundSyncController.frozenRecently(ref.read(sharedPrefsProvider))
                  ? '⚠ ${l10n.tr('bgFrozenTitle')}'
                  : l10n.tr('permissionsDesc'),
              selected: sel('/settings/permissions'),
              onTap: () => open('/settings/permissions'),
            ),
          ]),

          // ── Данные и место ──
          SettingsSectionTitle(l10n.tr('sectionStorageData')),
          SettingsGroup(children: [
            // Архив Ogneliss (1.7.3): старая почта, встречи, задачи,
            // контакты и настройки — в зашифрованный архив на устройстве.
            SettingsItem(
              icon: AppIcons.inventory_2,
              title: l10n.tr('ognaArchive'),
              subtitle: l10n.tr('archiveSettingsDesc'),
              selected: sel('/settings/archive'),
              onTap: () => open('/settings/archive'),
            ),
            // Резервная копия ящиков и настроек — перенос на новый телефон.
            SettingsItem(
              icon: AppIcons.settings_backup_restore,
              title: l10n.tr('backupTitle'),
              subtitle: l10n.tr('backupDesc'),
              selected: sel('/settings/backup'),
              onTap: () => open('/settings/backup'),
            ),
            SettingsItem(
              icon: AppIcons.storage,
              title: l10n.tr('storage'),
              subtitle: l10n.tr('storageDesc'),
              selected: sel('/settings/storage'),
              onTap: () => open('/settings/storage'),
            ),
          ]),

          // ── Система и справка: синхронизация, фон, журнал (в «Расширенных»),
          // экспериментальное, вопросы и ответы, о приложении ──
          SettingsSectionTitle(l10n.tr('sectionSystemHelp')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.tune,
              title: l10n.tr('advancedSettings'),
              subtitle: l10n.tr('advancedSettingsDesc'),
              selected: sel('/settings/advanced'),
              onTap: () => open('/settings/advanced'),
            ),
            // Функции на пробе (1.10.3), по умолчанию выключены.
            SettingsItem(
              icon: AppIcons.science,
              title: l10n.tr('experimentalTitle'),
              subtitle: l10n.tr('experimentalDesc'),
              selected: sel('/settings/experimental'),
              onTap: () => open('/settings/experimental'),
            ),
            // Вопросы и ответы по разделам приложения и настройкам (1.7.1).
            SettingsItem(
              icon: AppIcons.help,
              title: l10n.tr('faqTitle'),
              subtitle: l10n.tr('faqDesc'),
              selected: sel('/settings/faq'),
              onTap: () => open('/settings/faq'),
            ),
            SettingsItem(
              icon: AppIcons.info,
              title: l10n.tr('about'),
              subtitle: '${AppConstants.appName} v${AppConstants.appVersion}',
              selected: sel('/settings/about'),
              onTap: () => open('/settings/about'),
            ),
          ]),

      ]),
    );
  }

  Widget _list(List<Widget> children) {
    const padding = EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl);
    if (pane) return SettingsNavList(child: _PaneList(padding: padding, children: children));
    // На широком экране форма настроек в одну колонку во всю ширину читается
    // плохо — ограничиваем (для форм комфортнее уже, чем для текста письма).
    return ReadableWidth(maxWidth: 720, child: ListView(padding: padding, children: children));
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

/// Список слева: место прокрутки общее для всех страниц настроек — выбор
/// раздела внизу списка не возвращает список к началу.
class _PaneList extends StatefulWidget {
  final EdgeInsets padding;
  final List<Widget> children;
  const _PaneList({required this.padding, required this.children});

  @override
  State<_PaneList> createState() => _PaneListState();
}

class _PaneListState extends State<_PaneList> {
  static double _offset = 0;
  late final ScrollController _c = ScrollController(initialScrollOffset: _offset);

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (_c.hasClients) _offset = _c.offset;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListView(controller: _c, padding: widget.padding, children: widget.children);
}

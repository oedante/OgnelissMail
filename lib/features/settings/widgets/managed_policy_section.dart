// lib/features/settings/widgets/managed_policy_section.dart
//
// «Управляется организацией» (MDM, 1.10.5): вверху настроек, если
// организация задала политику через систему управления устройствами. Что
// именно задано и как связаться с ИТ-поддержкой. Сами запреты действуют в
// местах действий (managed_config.dart).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/managed_config.dart';
import '../../../widgets/common/inline_notice.dart';
import '../../../widgets/ui/settings_group.dart';

class ManagedPolicySection extends ConsumerWidget {
  const ManagedPolicySection({super.key});

  /// Что задано политикой — строки для списка (значок и текст). Запрета
  /// снимков экрана iPhone не даёт — там его не показываем.
  static List<(IconData, String)> rules(ManagedPolicy p, AppLocalizations l10n, {bool ios = false}) => [
        if (p.hasAccount) (AppIcons.alternate_email, l10n.tr('mdmRuleAccount').replaceAll('{email}', p.accountEmail!)),
        if (p.allowedDomains.isNotEmpty)
          (AppIcons.domain, l10n.tr('mdmRuleDomains').replaceAll('{domains}', p.allowedDomains.join(', '))),
        if (p.requireAppLock) (AppIcons.pin, l10n.tr('mdmRuleAppLock').replaceAll('{n}', '${p.minPinLength}')),
        if (p.blockScreenshots && !ios) (AppIcons.screenshot_monitor, l10n.tr('mdmRuleScreenshots')),
        if (p.blockShare) (AppIcons.share, l10n.tr('mdmRuleShare')),
        if (p.blockOpenIn) (AppIcons.open_in_new_off, l10n.tr('mdmRuleOpenIn')),
        if (p.blockCopy) (AppIcons.content_copy, l10n.tr('mdmRuleCopy')),
        if (p.hideNotificationContent) (AppIcons.notifications_off, l10n.tr('mdmRuleNotifications')),
      ];

  /// Ссылка для контакта поддержки: адрес — письмо, телефон — звонок,
  /// ссылка — браузер; иначе — нет.
  static Uri? contactUri(String c) {
    final s = c.trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return Uri.tryParse(s);
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) return Uri(scheme: 'mailto', path: s);
    final digits = s.replaceAll(RegExp(r'[\s()\-]'), '');
    if (RegExp(r'^\+?\d{5,15}$').hasMatch(digits)) return Uri(scheme: 'tel', path: digits);
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(managedPolicyProvider);
    if (!p.isManaged) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final org = p.orgName;
    final contact = p.supportContact;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('mdmTitle')),
      SettingsGroup(children: [
        SettingsItem(
          key: const ValueKey('mdm_org'),
          icon: AppIcons.admin_panel_settings,
          title: org ?? l10n.tr('mdmTitle'),
          subtitle: l10n.tr('mdmDesc'),
          onTap: null,
        ),
        for (final (icon, text) in rules(p, l10n, ios: !kIsWeb && Platform.isIOS))
          SettingsItem(icon: icon, title: text, onTap: null),
        if (contact != null)
          SettingsItem(
            icon: AppIcons.support_agent,
            title: l10n.tr('mdmSupport'),
            subtitle: contact,
            onTap: () async {
              final uri = contactUri(contact);
              if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
              await Clipboard.setData(ClipboardData(text: contact));
              showInlineNotice(l10n.tr('copied'));
            },
          ),
      ]),
    ]);
  }
}

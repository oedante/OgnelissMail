// lib/features/settings/screens/vip_settings_screen.dart
// Управление VIP-оповещениями: VIP-отправители и VIP-слова в теме.
// Хранятся в FocusModeService (SharedPreferences). Влияют на приоритет
// уведомления о новом письме (канал email_vip, importance.max).

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../../mail/providers/mail_providers.dart' show activeAccountProvider, accountsProvider;
import '../../../services/mail/focus_mode_service.dart';
import '../../../services/rules/device_rules_service.dart' show deviceRulesProvider;
import 'device_rule_screen.dart' show openDeviceRule, deviceRuleSummary;
import '../widgets/server_filters_item.dart' show pickServerFiltersAccount;
import '../../../services/mail/server_filters.dart' show ServerFilters;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class VipSettingsScreen extends ConsumerWidget {
  const VipSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(focusModeProvider);
    final notifier = ref.read(focusModeProvider.notifier);
    final rules = ref.watch(deviceRulesProvider);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('vipRulesTitle')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, ref, v),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: 'export',
                  child: Text(l10n.tr('exportToClipboard'))),
              PopupMenuItem(
                  value: 'import',
                  child: Text(l10n.tr('importFromClipboard'))),
            ],
          ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
        children: [
          // ── VIP-отправители ── (пояснение — за «?»)
          SettingsSectionTitle(l10n.tr('vipSendersSection'), help: l10n.tr('vipHint')),
          SettingsGroup(children: [
            if (state.vipEmails.isEmpty)
              SettingsItem(icon: AppIcons.star, title: l10n.tr('noVipSenders'), onTap: null),
            for (final e in state.vipEmails)
              SettingsItem(
                leading: const Icon(AppIcons.star, fill: 1, color: AppColors.brandAmber),
                title: e,
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.close),
                  onPressed: () => notifier.removeVipEmail(e),
                ),
                onTap: null,
              ),
            // Из контактов и адресной книги организации (09.10.2026: раньше
            // адрес нужно было вводить целиком).
            SettingsItem(
              icon: AppIcons.person_add,
              title: l10n.tr('addVipSender'),
              trailing: const SizedBox.shrink(),
              onTap: () async {
                final picked = await showPeoplePicker(
                  context,
                  account: ref.read(activeAccountProvider) ?? ref.read(accountsProvider).firstOrNull,
                  exclude: state.vipEmails.toSet(),
                );
                for (final c in picked) {
                  if (c.email.trim().isNotEmpty) notifier.addVipEmail(c.email.trim().toLowerCase());
                }
              },
            ),
            SettingsItem(
              icon: AppIcons.edit,
              title: l10n.tr('vipEnterAddress'),
              trailing: const SizedBox.shrink(),
              onTap: () => _addDialog(
                context,
                title: l10n.tr('addVipSender'),
                hint: l10n.tr('vipEmailHint'),
                onAdd: (v) => notifier.addVipEmail(v.toLowerCase()),
              ),
            ),
          ]),

          // ── VIP-слова в теме ──
          SettingsSectionTitle(l10n.tr('vipKeywordsSection')),
          SettingsGroup(children: [
            if (state.vipKeywords.isEmpty)
              SettingsItem(icon: AppIcons.label, title: l10n.tr('noVipKeywords'), onTap: null),
            for (final k in state.vipKeywords)
              SettingsItem(
                icon: AppIcons.label_important,
                title: k,
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.close),
                  onPressed: () => notifier.removeVipKeyword(k),
                ),
                onTap: null,
              ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('addVipKeyword'),
              trailing: const SizedBox.shrink(),
              onTap: () => _addDialog(
                context,
                title: l10n.tr('addVipKeyword'),
                hint: l10n.tr('vipKeywordHint'),
                onAdd: (v) => notifier.addVipKeyword(v),
              ),
            ),
          ]),

          // ── Правила на телефоне (09.10.2026) ──
          SettingsSectionTitle(l10n.tr('rulesSection'),
              help: '${l10n.tr('rulesHint')}\n\n${l10n.tr('ruleHowItWorks')}'),
          SettingsGroup(children: [
            if (rules.isEmpty)
              SettingsItem(icon: AppIcons.rule, title: l10n.tr('noDeviceRules'), onTap: null),
            for (final r in rules)
              SettingsItem(
                icon: AppIcons.rule,
                color: r.enabled ? null : Theme.of(context).disabledColor,
                title: r.name.trim().isNotEmpty ? r.name.trim() : deviceRuleSummary(r, l10n).split(' → ').first,
                subtitle: deviceRuleSummary(r, l10n),
                trailing: Switch(
                  value: r.enabled,
                  onChanged: (_) => ref.read(deviceRulesProvider.notifier).toggle(r.id),
                ),
                onTap: () => openDeviceRule(context, initial: r),
              ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('ruleNew'),
              trailing: const SizedBox.shrink(),
              onTap: () => openDeviceRule(context),
            ),
          ]),

          // ── Фильтры на сервере — в настройках каждого ящика (1.7.3) ──
          // Раньше здесь были «Правила на сервере Exchange» и «Фильтры на
          // сервере IMAP» с переключателем ящиков; теперь у каждого ящика свои
          // (Настройки → ящик), отсюда — выбор ящика.
          if (ref.watch(accountsProvider).any(ServerFilters.applies)) ...[
            SettingsSectionTitle(l10n.tr('srvFiltersSection'), help: l10n.tr('srvFiltersSectionHelp')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.filter_list,
                title: l10n.tr('sieveTitle'),
                subtitle: l10n.tr('srvFiltersInAccount'),
                onTap: () => unawaited(pickServerFiltersAccount(
                    context, [for (final a in ref.read(accountsProvider)) if (ServerFilters.applies(a)) a])),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  void _addDialog(BuildContext context,
      {required String title,
      required String hint,
      required void Function(String) onAdd}) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) onAdd(v);
              Navigator.pop(ctx);
            },
            child: Text(l10n.tr('add')),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String action) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(focusModeProvider.notifier);

    if (action == 'export') {
      await Clipboard.setData(ClipboardData(text: notifier.exportVipJson()));
      showInlineNotice(l10n.tr('vipListsCopied'));
    } else if (action == 'import') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) {
        showInlineNotice(l10n.tr('clipboardEmpty'));
        return;
      }
      final n = await notifier.importVipJson(text);
      if (n > 0) {
        showInlineNotice(l10n.tr('importedEntriesN').replaceAll('{n}', '$n'));
      } else {
        showInlineError(l10n.tr('couldNotParseJson'));
      }
    }
  }
}

// lib/features/settings/widgets/server_filters_item.dart
// «Фильтры на сервере» в настройках ящика (1.7.3, замечание владельца
// 25.10.2026: раньше — один пункт в общих настройках с переключателем ящиков,
// у служб без ManageSieve бесконечная крутилка, у Exchange ActiveSync — ничего).
//
//  · IMAP с ManageSieve — фильтры Sieve этого ящика;
//  · Exchange — правила Exchange (EWS; у ActiveSync — EWS того же сервера,
//    если открыт) и «Восстановить удалённые»;
//  · Gmail, iCloud, Яндекс, Mail.ru, Outlook.com и другие службы без
//    фильтров по протоколу — шторка: где настроить фильтры в веб-почте и
//    переход к правилам на телефоне.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/ui/action_sheet.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart' show mailEngineServiceProvider;
import '../../../services/mail/server_filters.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/settings_group.dart';

/// Пункты для группы настроек ящика (пустой список — у ящика их нет).
List<Widget> serverFilterItems(BuildContext context, WidgetRef ref, AccountModel account) {
  if (!ServerFilters.applies(account)) return const [];
  final l10n = AppLocalizations.of(context);
  final q = '?accountId=${Uri.encodeQueryComponent(account.id)}';
  final kind = ServerFilters.kindOf(account);
  // false — сервер этого ящика ActiveSync не открывает EWS (проверено).
  final ews = kind == ServerFilterKind.exchange ? ref.read(mailEngineServiceProvider).ewsKnown(account) : null;
  return switch (kind) {
    ServerFilterKind.sieve => [
        SettingsItem(
          icon: AppIcons.filter_list,
          title: l10n.tr('sieveTitle'),
          subtitle: l10n.tr('srvFiltersSieveSub'),
          onTap: () => context.push('/settings/sieve$q'),
        ),
      ],
    ServerFilterKind.exchange => [
        SettingsItem(
          icon: AppIcons.filter_list,
          title: l10n.tr('sieveTitle'),
          subtitle: l10n.tr(ews == false ? 'srvFiltersEasNoEwsSub' : 'srvFiltersExchangeSub'),
          onTap: () => context.push('/settings/server-rules$q'),
        ),
        if (ews != false)
          SettingsItem(
            icon: AppIcons.restore,
            title: l10n.tr('srvRecoverTitle'),
            subtitle: l10n.tr('srvRecoverIntro'),
            onTap: () => context.push('/settings/recover-deleted$q'),
          ),
      ],
    ServerFilterKind.webOnly => [
        SettingsItem(
          icon: AppIcons.filter_list,
          title: l10n.tr('sieveTitle'),
          subtitle: l10n.tr('srvFiltersWebSub'),
          onTap: () => showWebOnlyFilters(context, account),
        ),
      ],
  };
}

/// Открыть фильтры на сервере ящика [account] (из общих настроек).
void openServerFilters(BuildContext context, AccountModel account) {
  final q = '?accountId=${Uri.encodeQueryComponent(account.id)}';
  switch (ServerFilters.kindOf(account)) {
    case ServerFilterKind.sieve:
      unawaited(context.push('/settings/sieve$q'));
    case ServerFilterKind.exchange:
      unawaited(context.push('/settings/server-rules$q'));
    case ServerFilterKind.webOnly:
      unawaited(showWebOnlyFilters(context, account));
  }
}

/// Служба без фильтров по протоколу: где их настроить и правила на телефоне.
Future<void> showWebOnlyFilters(BuildContext context, AccountModel account) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(AppIcons.filter_list, color: theme.colorScheme.primary),
              const SizedBox(width: Space.m),
              Expanded(child: Text(l10n.tr('sieveTitle'), style: theme.textTheme.titleMedium)),
            ]),
            const SizedBox(height: Space.m),
            Text(l10n.tr(ServerFilters.webHintKey(account)), style: theme.textTheme.bodyMedium),
            const SizedBox(height: Space.s),
            Text(l10n.tr('srvFiltersPhoneHint'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Space.l),
            Row(children: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.tr('close'))),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(AppIcons.rule, size: 18),
                label: Text(l10n.tr('srvFiltersPhoneRules')),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  unawaited(context.push('/vip-settings'));
                },
              ),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Выбрать ящик для фильтров на сервере (общие настройки, ящиков несколько).
Future<void> pickServerFiltersAccount(BuildContext context, List<AccountModel> accounts) async {
  if (accounts.isEmpty) return;
  if (accounts.length == 1) {
    openServerFilters(context, accounts.first);
    return;
  }
  final l10n = AppLocalizations.of(context);
  // Карточкой (1.8.8), как меню «⋮».
  final id = await showChoiceSheet<String>(
    context,
    title: l10n.tr('srvFiltersPickAccount'),
    entries: [
      for (final a in accounts)
        AppMenuEntry(
          value: a.id,
          label: a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email,
          subtitle: a.email,
          icon: AppIcons.mail,
          iconColor: Color(a.colorValue),
        ),
    ],
  );
  final picked = accounts.where((a) => a.id == id).firstOrNull;
  if (picked != null && context.mounted) openServerFilters(context, picked);
}

// lib/features/settings/screens/aliases_settings_screen.dart
// Адреса отправки: список адресов аккаунтов, выбор основного для исходящих.

import '../../../core/utils/text_safe.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../mail/providers/mail_providers.dart';
import '../providers/settings_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/help_hint.dart';

class AliasesSettingsScreen extends ConsumerWidget {
  const AliasesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final settings = ref.watch(settingsProvider);
    final activeId = settings.activeAccountId;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('sendingAddresses')), actions: [
        HelpButton(text: l10n.tr('aliasHint'), title: l10n.tr('sendingAddresses')),
      ])),
      body: accounts.isEmpty
          ? Center(child: Text(l10n.tr('noAccountsAdded')))
          : ListView(
              children: [
                ...accounts.map((a) => AppRadioTile<String>(
                      secondary: CircleAvatar(
                        backgroundColor: Color(a.colorValue),
                        child: Text(a.email.isNotEmpty ? initialOf(a.email) : '?',
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(a.email),
                      subtitle: Text(a.displayName),
                      value: a.id,
                      groupValue: activeId,
                      onChanged: (v) {
                        if (v != null) {
                          ref.read(settingsProvider.notifier).setActiveAccountId(v);
                        }
                      },
                    )),
              ],
            ),
    );
  }
}

// lib/core/security/account_ca_sync.dart
// Передать хранилищу ЦС адреса серверов ящиков — для ЦС Минцифры,
// включённого в настройках отдельного ящика (TrustedCaStore.trustsMincifryFor).

import '../../data/models/account_model.dart';
import 'trusted_ca_store.dart';

void syncCaAccounts(List<AccountModel> accounts) {
  TrustedCaStore.instance?.syncAccounts([
    for (final a in accounts)
      (
        id: a.id,
        email: a.email,
        oauth: a.isOAuth,
        hosts: {
          if (a.imapServer != null) a.imapServer!,
          if (a.smtpServer != null) a.smtpServer!,
          if (a.exchangeServer != null) a.exchangeServer!,
          if (a.ewsUrl != null) a.ewsUrl!,
        },
      ),
  ]);
}

// lib/services/mail/server_filters.dart
// Фильтры на сервере у каждого ящика (1.7.3, замечание владельца 25.10.2026:
// «настройка фильтрации сервера — в общих настройках, а не для каждого
// аккаунта отдельно, и не работает; EWS/EAS вообще нет»).
//
//  · IMAP с паролем — ManageSieve (Sieve), если почтовая служба его даёт.
//    У iCloud, Gmail, Яндекса, Mail.ru, Outlook.com, Yahoo, Рамблера, GMX и
//    Zoho его нет (порт 4190 закрыт — раньше экран ждал ответа и показывал
//    крутилку): там фильтры — только в веб-почте, приложение так и говорит.
//  · Exchange — правила Exchange через EWS. У ящика ActiveSync — через EWS
//    того же сервера, если сервер его открывает (у шлюзов, закрывающих EWS,
//    правила сервера по ActiveSync недоступны — экран это объясняет).
//  · Вход через аккаунт службы (OAuth: Gmail, Яндекс, Mail.ru, Outlook.com) —
//    тоже только веб-почта.

import '../../data/models/account_model.dart';

enum ServerFilterKind {
  /// ManageSieve (IMAP с паролем).
  sieve,

  /// Правила Exchange (EWS; у ActiveSync — EWS того же сервера).
  exchange,

  /// Только в веб-почте службы.
  webOnly,
}

abstract final class ServerFilters {
  /// Домен почты → служба без ManageSieve (ключ подсказки «где настроить»).
  static const _domains = <String, String>{
    'icloud.com': 'icloud',
    'me.com': 'icloud',
    'mac.com': 'icloud',
    'gmail.com': 'gmail',
    'googlemail.com': 'gmail',
    'ya.ru': 'yandex',
    'narod.ru': 'yandex',
    'mail.ru': 'mailru',
    'bk.ru': 'mailru',
    'list.ru': 'mailru',
    'inbox.ru': 'mailru',
    'internet.ru': 'mailru',
    'outlook.com': 'outlook',
    'outlook.ru': 'outlook',
    'hotmail.com': 'outlook',
    'live.com': 'outlook',
    'live.ru': 'outlook',
    'msn.com': 'outlook',
    'aol.com': 'yahoo',
    'ymail.com': 'yahoo',
    'rambler.ru': 'rambler',
    'lenta.ru': 'rambler',
    'ro.ru': 'rambler',
    'autorambler.ru': 'rambler',
    'myrambler.ru': 'rambler',
    'web.de': 'gmx',
    'zoho.com': 'zoho',
    'zohomail.com': 'zoho',
  };

  /// Начало домена → служба (yandex.ru/.com/.by…, yahoo.co.uk…, gmx.net/.de…).
  static const _domainPrefixes = <String, String>{
    'yandex.': 'yandex',
    'yahoo.': 'yahoo',
    'gmx.': 'gmx',
  };

  /// Сервер IMAP → служба (свой домен на Яндекс 360, Mail.ru для бизнеса,
  /// Google Workspace и т. п.).
  static const _hosts = <String, String>{
    'mail.me.com': 'icloud',
    'imap.gmail.com': 'gmail',
    'imap.googlemail.com': 'gmail',
    'imap.yandex': 'yandex',
    'imap.ya.ru': 'yandex',
    'imap.mail.ru': 'mailru',
    'outlook.office365.com': 'outlook',
    'imap-mail.outlook.com': 'outlook',
    'mail.yahoo.com': 'yahoo',
    'imap.aol.com': 'yahoo',
    'imap.rambler.ru': 'rambler',
    'imap.gmx': 'gmx',
    'imap.web.de': 'gmx',
    'imap.zoho': 'zoho',
  };

  /// Служба без ManageSieve по адресу и серверу ящика; null — не из списка.
  static String? knownWebOnly(String email, String? imapHost) {
    final domain = email.contains('@') ? email.split('@').last.trim().toLowerCase() : '';
    final byDomain = _domains[domain];
    if (byDomain != null) return byDomain;
    for (final e in _domainPrefixes.entries) {
      if (domain.startsWith(e.key)) return e.value;
    }
    final host = (imapHost ?? '').trim().toLowerCase();
    if (host.isNotEmpty) {
      for (final e in _hosts.entries) {
        if (host.contains(e.key)) return e.value;
      }
    }
    return null;
  }

  /// Ящики общего доступа и архив Exchange — без своего пункта: правила
  /// сервера относятся к основному ящику.
  static bool applies(AccountModel a) => a.isActive && a.parentAccountId == null && !a.isOnlineArchive;

  static ServerFilterKind kindOf(AccountModel a) {
    if (a.isMsExchange) return ServerFilterKind.exchange;
    if (a.isImap && !a.isOAuth && knownWebOnly(a.email, a.imapServer) == null) return ServerFilterKind.sieve;
    return ServerFilterKind.webOnly;
  }

  /// Ключ строки «где настроить фильтры» для [ServerFilterKind.webOnly].
  static String webHintKey(AccountModel a) {
    final known = knownWebOnly(a.email, a.imapServer);
    if (known != null) return 'srvFiltersWeb_$known';
    return switch (a.type) {
      AccountType.google => 'srvFiltersWeb_gmail',
      AccountType.yandex => 'srvFiltersWeb_yandex',
      AccountType.mailru => 'srvFiltersWeb_mailru',
      AccountType.outlook => 'srvFiltersWeb_outlook',
      AccountType.yahoo => 'srvFiltersWeb_yahoo',
      _ => 'srvFiltersWeb_other',
    };
  }
}

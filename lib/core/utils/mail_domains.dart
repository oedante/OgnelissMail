// lib/core/utils/mail_domains.dart
// Домены общедоступной почты (Gmail, Яндекс, Mail.ru, Outlook.com…).
//
// Адреса на них не говорят об организации: двое на gmail.com — не коллеги.
// Нужно контактам из переписки (такие адреса не ищутся в адресной книге
// организации) и приветствию («коллеги» — только для адресатов из доменов
// своей организации).

const kPublicMailDomains = <String>{
  'gmail.com', 'googlemail.com',
  'yandex.ru', 'ya.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua',
  'mail.ru', 'bk.ru', 'inbox.ru', 'list.ru', 'internet.ru', 'rambler.ru', 'lenta.ru', 'ro.ru',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com',
  'yahoo.com', 'aol.com', 'mail.com', 'gmx.com', 'gmx.net', 'gmx.de', 'web.de', 't-online.de',
  'icloud.com', 'me.com', 'mac.com',
  'proton.me', 'protonmail.com', 'zoho.com', 'tutanota.com', 'tuta.io',
  'orange.fr', 'free.fr', 'laposte.net', 'sfr.fr', 'yahoo.fr', 'ukr.net', 'i.ua', 'meta.ua',
};

/// Домен адреса в нижнем регистре ('' — не адрес).
String mailDomainOf(String email) {
  final e = email.trim().toLowerCase();
  final at = e.lastIndexOf('@');
  return at < 0 ? '' : e.substring(at + 1);
}

/// Домен общедоступной почты (gmail.com, yandex.ru…).
bool isPublicMailDomain(String domain) => kPublicMailDomains.contains(domain.trim().toLowerCase());

/// Один домен организации: совпадает или один — поддомен другого
/// («msk.corp.example» и «corp.example»).
bool sameOrgDomain(String a, String b) {
  final x = a.trim().toLowerCase(), y = b.trim().toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.endsWith('.$y') || y.endsWith('.$x');
}

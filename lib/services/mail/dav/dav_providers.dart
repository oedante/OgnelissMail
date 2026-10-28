// lib/services/mail/dav/dav_providers.dart
// Провайдеры календаря/контактов по CalDAV/CardDAV (Google, Яндекс, Mail.ru,
// Yahoo), у которых PIM не приходит по IMAP. Вход — DavCredentials.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../data/models/contact_model.dart';
import '../oauth/oauth_proxy_client.dart';
import 'dav_credentials.dart';
import 'dav_pim_service.dart';

final davPimServiceProvider = Provider<DavPimService>((ref) => DavPimService());

Future<String?> _auth(Ref ref, AccountModel account, {bool contacts = false}) => DavCredentials.authorization(
      account,
      ref.read(secureStorageProvider),
      proxy: ref.read(oauthProxyClientProvider),
      contacts: contacts,
    );

/// События календаря по CalDAV для аккаунта (пусто, если не поддерживается).
final davEventsProvider =
    FutureProvider.family<List<CalendarEventModel>, AccountModel>((ref, account) async {
  if (!DavPimService.isSupported(account)) return const [];
  final auth = await _auth(ref, account);
  if (auth == null) return const [];
  return ref.read(davPimServiceProvider).fetchEvents(account, auth);
});

/// Контакты по CardDAV для аккаунта (пусто, если не поддерживается).
final davContactsProvider =
    FutureProvider.family<List<ContactModel>, AccountModel>((ref, account) async {
  if (!DavPimService.isSupported(account)) return const [];
  final auth = await _auth(ref, account, contacts: true);
  if (auth == null) return const [];
  return ref.read(davPimServiceProvider).fetchContacts(account, auth);
});

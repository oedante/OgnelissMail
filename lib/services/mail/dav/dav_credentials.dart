// lib/services/mail/dav/dav_credentials.dart
// Заголовок Authorization для CalDAV/CardDAV — одна точка для фоновой
// синхронизации и экранов.
//
// Порядок:
//   1. Пароль приложения для календаря, если пользователь его ввёл
//      (Настройки → Аккаунты → «Календарь и контакты»). Mail.ru и Yahoo
//      пускают в календарь только так; для Яндекса — запасной путь.
//   2. OAuth-токен: Google — «Bearer», Яндекс — «OAuth» (так в документации
//      Яндекс 360 для caldav.yandex.ru).
//   3. Аккаунт по паролю (IMAP): пароль ящика. У Mail.ru пароль внешнего
//      приложения общий для почты и календаря; у Яндекса пароли приложений
//      раздельные — тогда нужен п. 1.
//
// Контакты (CardDAV, 1.7.2+110): у Яндекса пароль приложения «Контакты»
// отдельный от «Календаря» — для контактов сначала берётся он
// ([contactsPassword]), иначе — как для календаря.

import 'dart:convert';

import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../oauth/oauth_proxy_client.dart';
import 'dav_pim_service.dart';

class DavCredentials {
  static String _key(String accountId) => 'davpw_$accountId';
  static String _contactsKey(String accountId) => 'davpw_contacts_$accountId';

  /// Отдельный пароль приложения для контактов (Яндекс, 1.7.2+110).
  static Future<String?> contactsPassword(SecureStorageService s, String accountId) async {
    final v = await s.read(_contactsKey(accountId));
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> saveContactsPassword(SecureStorageService s, String accountId, String? pw) async {
    if (pw == null || pw.trim().isEmpty) {
      await s.delete(_contactsKey(accountId));
    } else {
      await s.write(_contactsKey(accountId), pw.trim());
    }
    DavPimService.clearPause(accountId);
  }

  static Future<String?> appPassword(SecureStorageService s, String accountId) async {
    final v = await s.read(_key(accountId));
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> saveAppPassword(SecureStorageService s, String accountId, String? pw) async {
    if (pw == null || pw.trim().isEmpty) {
      await s.delete(_key(accountId));
    } else {
      await s.write(_key(accountId), pw.trim());
    }
    DavPimService.clearPause(accountId);
  }

  static String _basic(String user, String pw) =>
      'Basic ${base64.encode(utf8.encode('$user:$pw'))}';

  /// null — войти нечем (нет токена и пароля). [contacts] — для CardDAV:
  /// сначала отдельный пароль контактов, если он задан.
  static Future<String?> authorization(
    AccountModel account,
    SecureStorageService storage, {
    OAuthProxyClient? proxy,
    bool contacts = false,
  }) async {
    final provider = DavPimService.providerOf(account);
    if (provider == null) return null;
    final login = account.email;

    if (contacts) {
      final cpw = await contactsPassword(storage, account.id);
      if (cpw != null) return _basic(login, cpw);
    }

    final appPw = await appPassword(storage, account.id);
    if (appPw != null) return _basic(login, appPw);

    if (account.isOAuth) {
      if (provider != 'google' && provider != 'yandex') return null;
      String? token;
      if (proxy != null && proxy.isEnabled) {
        token = (await proxy.getAccessToken(account.id))?.accessToken;
      }
      token ??= await storage.getAccessToken(account.id);
      if (token == null || token.isEmpty) return null;
      return provider == 'yandex' ? 'OAuth $token' : 'Bearer $token';
    }

    final pw = await storage.getAccountPassword(account.id);
    if (pw == null || pw.isEmpty) return null;
    return _basic(account.username.isNotEmpty ? account.username : login, pw);
  }
}

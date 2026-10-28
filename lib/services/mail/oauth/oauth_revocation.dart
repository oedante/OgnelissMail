// lib/services/mail/oauth/oauth_revocation.dart
// Отзыв OAuth-доступа при удалении аккаунта.
//
// Раньше при удалении ящика токены только стирались с телефона, а выданный
// приложению доступ оставался действующим у провайдера (Google показывал
// «Ogneliss Mail имеет доступ к почте» и после удаления). Теперь:
//  · вход через прокси — прокси расшифровывает refresh-токен и отзывает его
//    у провайдера (Google);
//  · прямой вход Google — отзыв на oauth2.googleapis.com/revoke.
// У Microsoft, Яндекса, Mail.ru и Yahoo публичного отзыва нет: токены
// удаляются с телефона и истекают сами. Пользователь может отключить
// приложение в настройках безопасности своего аккаунта.

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import 'oauth_proxy_client.dart';

class OAuthRevocation {
  OAuthRevocation._();

  static bool _isGoogle(AccountModel a) {
    if (a.type == AccountType.google) return true;
    final d = a.email.split('@').last.toLowerCase();
    return d == 'gmail.com' || d == 'googlemail.com';
  }

  /// Вызывать ДО удаления токенов из хранилища. Не бросает исключений и не
  /// ждёт дольше ~10 секунд: удаление аккаунта не должно зависеть от сети.
  static Future<void> revoke(AccountModel account, SecureStorageService storage) async {
    if (!account.usesOAuthTokens) return;
    try {
      // Токен Google читаем заранее: прокси стирает свои данные сразу.
      final googleToken = _isGoogle(account)
          ? (await storage.getRefreshToken(account.id)) ?? (await storage.getAccessToken(account.id))
          : null;
      await Future.wait([
        OAuthProxyClient(storage).revoke(account.id),
        if (googleToken != null && googleToken.isNotEmpty)
          http
              .post(Uri.parse('https://oauth2.googleapis.com/revoke'),
                  headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: {'token': googleToken})
              .then((r) => AppLogger.info('OAuth: доступ Google отозван (HTTP ${r.statusCode})')),
      ]).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.debug('OAuth: отзыв доступа не выполнен: $e');
    }
  }
}

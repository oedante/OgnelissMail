// lib/services/mail/oauth/proxy_pkce.dart
// Отказ службы при входе (OAuthProviderError). Имя файла — от прежнего
// обмена кода с сервером входа (PKCE между приложением и сервером); сервер
// входа снят в 2.5.5, вход — напрямую у служб (direct_oauth.dart).

import 'package:flutter/services.dart' show PlatformException;

import '../../../l10n/app_localizations.dart';

/// Отказ провайдера при входе (код из OAuth: access_denied, invalid_scope…).
class OAuthProviderError implements Exception {
  final String code;
  /// Подробность от сервера входа: код провайдера при неудачном обмене кода
  /// на токены (invalid_client, invalid_grant, AADSTS7000215…).
  final String? detail;
  const OAuthProviderError(this.code, [this.detail]);

  /// Google не пускает в приложение новых пользователей (2.5.4): у
  /// непроверенного приложения кончился лимит в 100 человек. Код ставит
  /// [OAuthProviderError.of] по ответу самого Google.
  static const userCap = 'user_cap';

  /// Отказ с учётом подробности: Google ответил про лимит пользователей или
  /// непроверенное приложение — [userCap]. Остальное — как пришло.
  factory OAuthProviderError.of(String code, String? detail, {String? provider}) =>
      provider == 'google' && looksLikeUserCap(detail) ? OAuthProviderError(userCap, detail) : OAuthProviderError(code, detail);

  /// Подробность отказа Google говорит о лимите пользователей или о том, что
  /// приложение не проверено.
  static bool looksLikeUserCap(String? detail) =>
      detail != null &&
      RegExp(r'user[\s_-]?cap|unverified|not\s+(been\s+)?verified|verification\s+process', caseSensitive: false)
          .hasMatch(detail);

  /// Отменил сам пользователь — сообщать об ошибке не нужно.
  bool get cancelled => code == 'access_denied';

  /// Окно входа закрыто без ответа (flutter_web_auth_2: CANCELED — «назад»
  /// или крестик в браузере входа) — та же отмена, что access_denied
  /// (2.2.0, журнал владельца 10.11.2026: отмена «Войти снова» показывалась
  /// строкой ошибки «PlatformException(CANCELED…)»).
  static bool isUserCancel(Object e) => e is PlatformException && e.code == 'CANCELED';

  /// Текст для пользователя на языке интерфейса.
  String localizedMessage(AppLocalizations l10n) => switch (code) {
        'access_denied' => l10n.tr('oauthCancelled'),
        userCap => l10n.tr('oauthGoogleUserCap'),
        'invalid_scope' => l10n.tr('oauthInvalidScope'),
        'token_exchange' => l10n.tr('oauthTokenExchange').replaceAll('{code}', detail ?? '?'),
        _ => l10n.tr('oauthProviderDenied').replaceAll('{code}', code),
      };

  /// Для журнала; пользователю — [localizedMessage].
  @override
  String toString() => 'OAuthProviderError($code${detail == null ? '' : ' $detail'})';
}

// lib/services/mail/oauth/cross_platform_oauth.dart
// Единая точка OAuth для ВСЕХ платформ:
//   • Android / iOS / macOS — flutter_appauth (системный браузер, кастомная схема);
//   • Windows / Linux       — loopback HTTP-сервер на 127.0.0.1 + системный браузер;
//   • Web                   — popup + callback-страница (postMessage).
// Desktop/Web используют единый OAuthHelper движка (code-flow + PKCE).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'oauth_service.dart';
// Платформенная реализация desktop/web подгружается по условию компиляции.
import 'oauth_flow_native.dart' if (dart.library.html) 'oauth_flow_web.dart' as flow;
import 'oauth_proxy_flow.dart';
import 'direct_oauth.dart';

class CrossPlatformOAuthService {
  final OAuthService _appAuth; // мобильные/macOS
  /// Строки на языке интерфейса (страница возврата в браузере).
  final AppLocalizations Function() _l10n;
  CrossPlatformOAuthService(this._appAuth, this._l10n);

  /// Конфигурация провайдера (clientId/secret/scopes) для desktop/web флоу.
  ({me.OAuthProvider provider, String clientId, String? clientSecret})? _cfg(String name) {
    switch (name) {
      case 'google':
        return (provider: me.OAuthProvider.google, clientId: AppConstants.googleClientId, clientSecret: null);
      case 'yandex':
        return (provider: me.OAuthProvider.yandex, clientId: AppConstants.yandexClientId, clientSecret: null);
      case 'mailru':
        return (provider: me.OAuthProvider.mailru, clientId: AppConstants.mailruClientId, clientSecret: AppConstants.mailruClientSecret);
      default:
        return null;
    }
  }

  /// Универсальная авторизация по имени провайдера ('google'|'yandex'|'mailru'|
  /// 'yahoo'|'microsoft'|'exchange'). [loginHint] — адрес ящика: при «Войти
  /// снова» и при входе по адресу (1.8.0) — служба подставит его сама.
  Future<OAuthResult> authenticate(String providerName, {String? loginHint}) async {
    // 1.6.2: вход без сервера входа — если в сборке задан публичный клиент
    // провайдера для этой платформы (Google, Microsoft). Exchange Online без
    // него — через сервер входа 1.8.11 (провайдер exchange); прежний сервер
    // токенов ActiveSync/EWS не выдаёт.
    final direct = kIsWeb ? null : DirectOAuth.clientFor(providerName);
    if (direct != null) return DirectOAuth.authenticate(direct, loginHint: loginHint);
    if (providerName == 'exchange' && (kIsWeb || !OAuthProxyFlow.isEnabled || !await OAuthProxyFlow.offers('exchange'))) {
      throw const OAuthNotConfiguredException();
    }

    // Иначе — корпоративный прокси (если задан OAUTH_PROXY_URL).
    // Единый клиент типа «веб» на все платформы, client_secret остаётся на сервере.
    if (!kIsWeb && OAuthProxyFlow.isEnabled) {
      return OAuthProxyFlow.authenticate(providerName, loginHint: loginHint);
    }

    // Легаси-путь (сборка без прокси): mobile/macOS — flutter_appauth.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      switch (providerName) {
        case 'google':
          return _appAuth.authenticateGoogle();
        case 'yandex':
          return _appAuth.authenticateYandex();
        case 'mailru':
          return _appAuth.authenticateMailru();
        case 'yahoo':
          return _appAuth.authenticateYahoo();
      }
    }
    // Desktop (Windows/Linux) и Web — единый флоу через движок.
    final cfg = _cfg(providerName);
    if (cfg == null) {
      throw AuthException(
        userMessage: 'OAuth-провайдер «$providerName» не поддерживается на этой платформе',
        messageKey: 'oauthProviderUnsupported',
        messageArgs: {'provider': providerName},
      );
    }
    AppLogger.info('OAuth ($providerName): ${kIsWeb ? "web" : "desktop"}-флоу'
        '${(!kIsWeb && AppConstants.oauthProxyBaseUrl.isNotEmpty) ? " (через прокси)" : ""}');
    final me.OAuthToken? token;
    final l10n = _l10n();
    final doneTitle = l10n.tr('oauthDoneTitle');
    final doneText = l10n.tr('oauthDoneText');
    if (!kIsWeb && AppConstants.oauthProxyBaseUrl.isNotEmpty) {
      // Через корпоративный прокси (секреты на сервере, refresh без повторного входа)
      token = await flow.runOAuthViaProxy(
        proxyBaseUrl: AppConstants.oauthProxyBaseUrl,
        provider: providerName,
        doneTitle: doneTitle,
        doneText: doneText,
      );
    } else {
      token = await flow.runOAuth(
        provider: cfg.provider,
        clientId: cfg.clientId,
        clientSecret: cfg.clientSecret,
        doneTitle: doneTitle,
        doneText: doneText,
      );
    }
    if (token == null) {
      throw AuthException(
        userMessage: 'OAuth ($providerName): токен не получен',
        messageKey: 'oauthNoToken',
        messageArgs: {'provider': providerName, 'details': ''},
      );
    }
    return OAuthResult(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken,
      expiry: token.expiresIn != null
          ? DateTime.now().add(Duration(seconds: token.expiresIn!))
          : null,
    );
  }
}

final crossPlatformOAuthProvider = Provider<CrossPlatformOAuthService>((ref) {
  final appAuth = ref.watch(oauthServiceProvider);
  return CrossPlatformOAuthService(
      appAuth, () => AppLocalizations(ref.read(settingsProvider).locale));
});

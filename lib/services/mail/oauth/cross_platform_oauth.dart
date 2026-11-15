// lib/services/mail/oauth/cross_platform_oauth.dart
// Единая точка входа OAuth для всех платформ.
//
// С 2.5.5 (решение владельца 15.11.2026) вход и обновление токенов идут
// напрямую у службы: приложение — публичный клиент с PKCE
// (direct_oauth.dart): телефон и Mac — своя схема приложения, Windows и
// Linux — loopback 127.0.0.1. Токены не проходят через серверы разработчика.
//
// Исключение — Яндекс на Windows и Linux: у Яндекса нет входа для таких
// приложений без веб-клиента, поэтому там — сервер входа Ogneliss
// (oauth_proxy_flow.dart), только для Яндекса. Ключей Google и Microsoft на
// сервере нет.
//
// Клиента службы для этой платформы в сборке нет (config/dart_defines.json:
// GOOGLE_*_CLIENT_ID, MS_CLIENT_ID) или сервер входа выключен — вход через
// службу недоступен: экран входа предлагает пароль приложения
// ([CrossPlatformOAuthService.available]).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../security/managed_config.dart' show ManagedPolicy;
import 'direct_oauth.dart';
import 'oauth_proxy_flow.dart';
import 'oauth_service.dart';

class CrossPlatformOAuthService {
  const CrossPlatformOAuthService();

  /// Яндекс на Windows и Linux — через сервер входа (если он задан при
  /// сборке и организация не запретила внешние службы).
  static bool yandexViaServer(String providerName) =>
      providerName == 'yandex' &&
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux) &&
      OAuthProxyFlow.isEnabled &&
      !ManagedPolicy.current.blockExternalServices;

  /// Вход через службу ('google' | 'microsoft' | 'exchange' | 'yandex')
  /// возможен на этой платформе. Нет — экран входа предлагает пароль
  /// приложения.
  bool available(String providerName) =>
      (!kIsWeb && DirectOAuth.clientFor(providerName) != null) || yandexViaServer(providerName);

  /// Вход у службы [providerName]. [loginHint] — адрес ящика: при «Войти
  /// снова» и при входе по адресу служба подставит его сама.
  Future<OAuthResult> authenticate(String providerName, {String? loginHint}) async {
    final direct = kIsWeb ? null : DirectOAuth.clientFor(providerName);
    if (direct != null) return DirectOAuth.authenticate(direct, loginHint: loginHint);
    if (yandexViaServer(providerName)) {
      AppLogger.info('OAuth (yandex): Windows/Linux — через сервер входа');
      return OAuthProxyFlow.authenticate(providerName, loginHint: loginHint);
    }
    throw const OAuthNotConfiguredException();
  }
}

final crossPlatformOAuthProvider = Provider<CrossPlatformOAuthService>((ref) => const CrossPlatformOAuthService());

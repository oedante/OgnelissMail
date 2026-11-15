// lib/services/mail/oauth/cross_platform_oauth.dart
// Единая точка входа OAuth для всех платформ.
//
// С 2.5.5 (решение владельца 15.11.2026) сервера входа Ogneliss нет: вход и
// обновление токенов — только напрямую у службы, приложение — публичный
// клиент с PKCE (direct_oauth.dart): телефон и Mac — своя схема приложения,
// Windows и Linux — loopback 127.0.0.1. Токены не проходят ни через какой
// сервер разработчика.
//
// Клиента службы для этой платформы в сборке нет (config/dart_defines.json:
// GOOGLE_*_CLIENT_ID, MS_CLIENT_ID; Яндекс на Windows и Linux) — вход через
// службу недоступен: экран входа предлагает пароль приложения
// ([CrossPlatformOAuthService.available]).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import 'oauth_service.dart';
import 'direct_oauth.dart';

class CrossPlatformOAuthService {
  const CrossPlatformOAuthService();

  /// Вход через службу ('google' | 'microsoft' | 'exchange' | 'yandex')
  /// возможен на этой платформе: в сборке есть её публичный клиент. Нет —
  /// экран входа предлагает пароль приложения.
  bool available(String providerName) => !kIsWeb && DirectOAuth.clientFor(providerName) != null;

  /// Вход у службы [providerName]. [loginHint] — адрес ящика: при «Войти
  /// снова» и при входе по адресу служба подставит его сама.
  Future<OAuthResult> authenticate(String providerName, {String? loginHint}) async {
    final direct = kIsWeb ? null : DirectOAuth.clientFor(providerName);
    if (direct == null) throw const OAuthNotConfiguredException();
    return DirectOAuth.authenticate(direct, loginHint: loginHint);
  }
}

final crossPlatformOAuthProvider = Provider<CrossPlatformOAuthService>((ref) => const CrossPlatformOAuthService());

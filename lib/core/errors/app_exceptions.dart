// lib/core/errors/app_exceptions.dart
// Типизированные исключения.

import '../../l10n/app_localizations.dart';

abstract class AppException implements Exception {
  /// Запасной текст (логи, toString и места без доступа к локализации).
  final String userMessage;
  final String? technicalMessage;
  final String? code;
  final dynamic originalError;

  /// Ключ строки в assets/l10n/<код>.xml. Если задан, текст для пользователя —
  /// на языке интерфейса: см. [localizedMessage].
  final String? messageKey;

  /// Значения подстановок `{имя}` в строке [messageKey].
  final Map<String, String>? messageArgs;
  const AppException({
    required this.userMessage,
    this.technicalMessage,
    this.code,
    this.originalError,
    this.messageKey,
    this.messageArgs,
  });

  /// Текст ошибки на языке интерфейса (или [userMessage], если ключа нет).
  String localizedMessage(AppLocalizations l10n) {
    final key = messageKey;
    if (key == null) return userMessage;
    var text = l10n.tr(key);
    messageArgs?.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }

  @override
  String toString() => 'AppException($code): $userMessage';
}

class NetworkException extends AppException {
  const NetworkException({String? userMessage, super.technicalMessage, super.code = 'NETWORK', String? messageKey})
      : super(
          userMessage: userMessage ?? 'Ошибка сети',
          messageKey: messageKey ?? (userMessage == null ? 'errNetwork' : null),
        );
}

class NoConnectionException extends NetworkException {
  const NoConnectionException({super.technicalMessage})
      : super(userMessage: 'Нет подключения к интернету', messageKey: 'errNoConnection', code: 'NO_CONNECTION');
}

class ConnectionTimeoutException extends NetworkException {
  const ConnectionTimeoutException({super.technicalMessage})
      : super(userMessage: 'Превышено время ожидания', messageKey: 'errTimeout', code: 'TIMEOUT');
}

class AuthException extends AppException {
  const AuthException({
    String? userMessage,
    super.technicalMessage,
    super.code = 'AUTH',
    String? messageKey,
    super.messageArgs,
  })
      : super(
          userMessage: userMessage ?? 'Ошибка авторизации',
          messageKey: messageKey ?? (userMessage == null ? 'authFailed' : null),
        );
}

class InvalidCredentialsException extends AuthException {
  const InvalidCredentialsException({super.technicalMessage})
      : super(userMessage: 'Неверные учётные данные', messageKey: 'errInvalidCredentials', code: 'INVALID_CREDENTIALS');
}

class OAuthUnsupportedPlatformException extends AuthException {
  const OAuthUnsupportedPlatformException()
      : super(
          userMessage: 'OAuth-вход доступен только на Android и iOS. На компьютере используйте Exchange или IMAP/SMTP с паролем.',
          messageKey: 'errOAuthUnsupported',
          code: 'OAUTH_UNSUPPORTED',
        );
}

/// OAuth-ключ (clientId) ещё не зарегистрирован для этого провайдера/платформы.
class OAuthNotConfiguredException extends AuthException {
  const OAuthNotConfiguredException()
      : super(
          userMessage: 'Вход через этот сервис в этой сборке приложения не настроен. Добавьте ящик по паролю приложения (IMAP/SMTP).',
          messageKey: 'errOAuthNotConfigured',
          code: 'OAUTH_NOT_CONFIGURED',
        );
}

class AccountAlreadyExistsException extends AuthException {
  final String? email;
  const AccountAlreadyExistsException({this.email})
      : super(
          userMessage: email != null
              ? 'Аккаунт $email уже добавлен.'
              : 'Такой аккаунт уже добавлен.',
          messageKey: email != null ? 'errAccountExistsEmail' : 'errAccountExists',
          code: 'ACCOUNT_EXISTS',
        );

  @override
  String localizedMessage(AppLocalizations l10n) {
    final e = email;
    return e != null
        ? l10n.tr('errAccountExistsEmail').replaceAll('{email}', e)
        : l10n.tr('errAccountExists');
  }
}

class ExchangeException extends AppException {
  const ExchangeException({String? userMessage, super.technicalMessage, super.code = 'EXCHANGE', String? messageKey})
      : super(
          userMessage: userMessage ?? 'Ошибка Exchange',
          messageKey: messageKey ?? (userMessage == null ? 'errExchange' : null),
        );
}

class ServerUnavailableException extends ExchangeException {
  const ServerUnavailableException({super.technicalMessage})
      : super(userMessage: 'Сервер временно недоступен', messageKey: 'errServerUnavailable', code: 'SERVER_UNAVAILABLE');
}

class RecallException extends AppException {
  const RecallException({String? userMessage, super.technicalMessage, super.code = 'RECALL', super.originalError})
      : super(
          userMessage: userMessage ?? 'Не удалось отозвать',
          messageKey: userMessage == null ? 'recallFailed' : null,
        );
}

/// Push (EAS Ping, IMAP IDLE) получил отказ во входе и остановился. Повторять
/// вход в цикле нельзя — это путь к блокировке учётной записи. Подписчик
/// проверяет вход обычной синхронизацией (она пометит аккаунт «требуется
/// вход», если пароль действительно неверен) и при успехе включает push снова.
class PushAuthFailure extends AuthException {
  const PushAuthFailure() : super(technicalMessage: 'push: отказ во входе', code: 'PUSH_AUTH');
}

/// Похожа ли ошибка на отказ во входе (а не на сетевой сбой). Различать важно:
/// таймаут — не повод помечать аккаунт «требуется вход», а повтор входа с
/// неверным паролем — путь к блокировке учётной записи.
///
/// 403 — НЕ ошибка входа: перед Exchange бывает анти-бот-защита, отвечающая
/// 403 на отдельные запросы; 403 самого Exchange (EAS запрещён ящику)
/// повторный ввод пароля тоже не исправит.
bool looksLikeAuthError(Object e) {
  if (e is PushAuthFailure) return true;
  // Обновление OAuth-токена: ошибкой входа считается только отозванный вход.
  // Сбой прокси или сети — нет: иначе ящик помечался бы «требуется вход»
  // из-за неполадки сервера, а повторный вход всё равно не помог бы.
  if (e is OAuthRefreshFailure) return e.needsSignIn;
  final s = e.toString().toLowerCase();
  if (RegExp(r'\b401\b').hasMatch(s)) return true;
  return s.contains('unauthorized') ||
      s.contains('authentication failed') ||
      s.contains('invalid credentials') ||
      s.contains('invalid_credentials') ||
      s.contains('logon failure') ||
      s.contains('account is locked') ||
      s.contains('authenticationfailed') ||
      // IMAP: «[AUTHENTICATIONFAILED]», у Яндекса и Mail.ru — «LOGIN failed»,
      // у Gmail по XOAUTH2 — «Invalid credentials».
      s.contains('login failed');
}


/// Не удалось обновить OAuth-токен.
///
/// [needsSignIn] — вход отозван или истёк (invalid_grant, нечитаемый вход на
/// прокси): поможет только «Войти снова». Иначе — сбой прокси, его настройки
/// или сети: повторный вход не нужен, нужна пауза и исправление сервера.
class OAuthRefreshFailure implements Exception {
  final bool needsSignIn;
  final bool temporary;
  final String reason;
  const OAuthRefreshFailure(this.reason, {this.needsSignIn = false, this.temporary = false});

  @override
  String toString() => needsSignIn
      ? 'Вход отозван — нужен повторный вход: $reason'
      : 'Не удалось обновить OAuth-токен: $reason';
}

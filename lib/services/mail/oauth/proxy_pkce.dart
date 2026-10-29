// lib/services/mail/oauth/proxy_pkce.dart
// PKCE между приложением и OAuth-прокси.
//
// Прокси возвращает результат входа в приложение по адресу своей схемы
// (com.ogneliss.mail://oauth) или на loopback. Свою схему может
// зарегистрировать любое приложение на устройстве, поэтому токены в адресе —
// это риск их перехвата. Теперь приложение посылает на /login хеш случайного
// секрета (cc), прокси возвращает только одноразовый код (oc), а токены
// выдаёт по POST /exchange тому, кто предъявит сам секрет (cv).
// Ответ старого прокси (токены в адресе, без кода) отклоняется.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../l10n/app_localizations.dart';

/// Отказ провайдера при входе (код из OAuth: access_denied, invalid_scope…).
class OAuthProviderError implements Exception {
  final String code;
  /// Подробность от сервера входа: код провайдера при неудачном обмене кода
  /// на токены (invalid_client, invalid_grant, AADSTS7000215…).
  final String? detail;
  const OAuthProviderError(this.code, [this.detail]);

  /// Отменил сам пользователь — сообщать об ошибке не нужно.
  bool get cancelled => code == 'access_denied';

  /// Текст для пользователя на языке интерфейса.
  String localizedMessage(AppLocalizations l10n) => switch (code) {
        'access_denied' => l10n.tr('oauthCancelled'),
        'invalid_scope' => l10n.tr('oauthInvalidScope'),
        'token_exchange' => l10n.tr('oauthTokenExchange').replaceAll('{code}', detail ?? '?'),
        _ => l10n.tr('oauthProviderDenied').replaceAll('{code}', code),
      };

  /// Для журнала; пользователю — [localizedMessage].
  @override
  String toString() => 'OAuthProviderError($code${detail == null ? '' : ' $detail'})';
}

class ProxyPkce {
  final String verifier;
  final String challenge;
  ProxyPkce._(this.verifier, this.challenge);

  factory ProxyPkce.generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final v = base64Url.encode(bytes).replaceAll('=', '');
    final c = base64Url.encode(sha256.convert(ascii.encode(v)).bytes).replaceAll('=', '');
    return ProxyPkce._(v, c);
  }

  /// Параметры возврата → {at, exp, rt, provider}. Если пришёл одноразовый
  /// код — обменивает его у прокси; иначе возвращает параметры как есть.
  Future<Map<String, String>> resolve(String proxyBase, Map<String, String> params) async {
    // Ошибка провайдера, которую прокси вернул в приложение.
    final err = params['error'];
    if (err != null && err.isNotEmpty) throw OAuthProviderError(err, params['desc']);
    final oc = params['oc'];
    // Токены прямо в адресе возврата не принимаются: адрес схемы приложения
    // может подставить любое приложение на устройстве (вход в чужой ящик).
    // Прокси с PKCE всегда возвращает только одноразовый код.
    if (oc == null || oc.isEmpty) {
      throw const AuthException(
          userMessage: 'OAuth (прокси): ответ без одноразового кода отклонён — '
              'обновите сервер входа',
          messageKey: 'oauthProxyNoCode');
    }
    final base = proxyBase.replaceAll(RegExp(r'/+$'), '');
    final resp = await http
        .post(
          Uri.parse('$base/exchange'),
          headers: {
            'x-api-key': AppConstants.oauthProxyApiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'oc': oc, 'cv': verifier}),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      // Тело не пишем в журнал и в текст ошибки: там может быть токен.
      throw AuthException(
        userMessage: 'OAuth (прокси): обмен кода не удался, HTTP ${resp.statusCode}',
        messageKey: 'oauthProxyExchangeFailed',
        messageArgs: {'status': '${resp.statusCode}'},
      );
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return {
      'at': (m['access_token'] ?? '').toString(),
      'exp': (m['expires_at'] ?? '').toString(),
      if ((m['rt'] ?? '').toString().isNotEmpty) 'rt': m['rt'].toString(),
      'provider': (m['provider'] ?? params['provider'] ?? '').toString(),
      if ((m['email'] ?? '').toString().isNotEmpty) 'email': m['email'].toString(),
      if ((m['name'] ?? '').toString().isNotEmpty) 'name': m['name'].toString(),
      // Exchange Online: дано согласие и на Microsoft Graph (сервер входа 1.8.11).
      if (m['graph'] == true) 'graph': '1',
    };
  }
}

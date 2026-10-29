// lib/services/mail/oauth/oauth_proxy_flow.dart
// Единый OAuth-флоу ЧЕРЕЗ КОРПОРАТИВНЫЙ ПРОКСИ для всех нативных платформ.
//
// Зачем: прокси — единственный OAuth-клиент (тип «веб» в консолях провайдеров),
// поэтому client_secret никогда не попадает в приложение, а редирект у всех
// провайдеров один: <BASE_URL>/callback. Приложению прокси возвращает только
// access-токен и зашифрованный refresh-blob.
//
// Поток:
//   app → <BASE_URL>/oauth/<provider>/login?redirect=<куда вернуть>
//   прокси → провайдер → прокси /callback (обмен кода на токены)
//   прокси → redirect?at=..&exp=..&rt=..&provider=..
//
// Куда возвращать (зависит от платформы, ограничение flutter_web_auth_2):
//   Android/iOS/macOS → своя схема  com.ogneliss.mail://oauth
//   Windows/Linux     → loopback    http://localhost:<порт>/   (плагин поднимает
//                       локальный сервер; порт фиксированный — иначе не поймать)
// Оба варианта прокси уже разрешает (ALLOWED_REDIRECTS + localhost/127.0.0.1).
//
// ВАЖНО про десктоп: flutter_web_auth_2 5.x по умолчанию открывает ВСТРОЕННЫЙ
// webview (useWebview: true). Google такие запросы отклоняет (disallowed_useragent),
// поэтому на Windows/Linux принудительно useWebview: false → системный браузер
// + локальный сервер на порту из callbackUrlScheme.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart' as errors;
import '../../../core/logging/app_logger.dart';
import 'oauth_service.dart' show OAuthResult;
import 'proxy_pkce.dart';

/// Фиксированный порт для loopback-редиректа на десктопе.
/// Выбран из динамического диапазона, чтобы не конфликтовать с типовыми сервисами.
const int kDesktopOAuthPort = 43823;

/// Своя схема приложения (совпадает с ios/Runner/Info.plist и AndroidManifest).
const String kAppScheme = 'com.ogneliss.mail';

class OAuthProxyFlow {
  /// Прокси настроен? (сборка с --dart-define=OAUTH_PROXY_URL=...)
  static bool get isEnabled => AppConstants.oauthProxyBaseUrl.trim().isNotEmpty;

  /// Адрес, куда прокси вернёт результат, и схема для перехвата.
  static ({String redirect, String callbackScheme}) _target() {
    if (Platform.isWindows || Platform.isLinux) {
      // flutter_web_auth_2 на десктопе требует именно http://localhost:{port}
      const url = 'http://localhost:$kDesktopOAuthPort/';
      return (redirect: url, callbackScheme: url);
    }
    return (redirect: '$kAppScheme://oauth', callbackScheme: kAppScheme);
  }

  /// Адрес для подстановки на странице входа: только похожий на адрес
  /// почты (прокси проверяет его ещё раз).
  static String? hintParam(String? loginHint) {
    final h = (loginHint ?? '').trim();
    if (h.length > 254 || !RegExp(r'^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$').hasMatch(h)) return null;
    return h;
  }

  /// Службы, которые подставляют адрес почты на своей странице входа.
  static const _hintProviders = {'google', 'microsoft', 'exchange', 'yandex'};

  /// Сервер входа умеет входить через [provider] (у него заданы клиент и
  /// секрет): Exchange Online — с сервера входа 1.8.11. Прежний сервер его не
  /// знает — тогда браузер показал бы «unknown provider». Нет связи — true:
  /// ошибку покажет сам вход.
  static Future<bool> offers(String provider) async {
    final base = AppConstants.oauthProxyBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('$base/healthz'));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return true;
      final m = jsonDecode(body);
      final c = m is Map && m['config'] is Map ? (m['config'] as Map)[provider] : null;
      return c is Map && c['clientId'] == true && c['clientSecret'] == true;
    } catch (e) {
      AppLogger.info('OAuth: сервер входа не ответил на /healthz ($e)');
      return true;
    } finally {
      client.close(force: true);
    }
  }

  /// Адрес страницы входа службы (1.8.0). Сервер входа отвечает на
  /// /oauth/<служба>/login переадресацией (302) на страницу службы со своими
  /// client_id и state; приложение берёт этот адрес, не переходя по нему, и
  /// само дописывает login_hint. Так адрес почты уходит только службе, у
  /// которой человек входит, — на сервер входа он не попадает (политика
  /// конфиденциальности, раздел 6.1). Не вышло — null: обычный путь, адрес
  /// вводится на странице службы.
  static Future<String?> _providerUrl(String loginUrl) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(loginUrl));
      req.followRedirects = false;
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain<void>();
      final loc = resp.headers.value(HttpHeaders.locationHeader);
      if (resp.isRedirect && loc != null && loc.startsWith('https://')) return loc;
      return null;
    } catch (e) {
      AppLogger.info('OAuth: адрес страницы входа не получен ($e) — без подстановки адреса');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// [url] страницы входа службы + login_hint. Microsoft с подсказкой не
  /// нужен выбор учётной записи (с prompt=select_account подсказка не
  /// действует).
  @visibleForTesting
  static String withHint(String url, String provider, String hint) {
    var out = url;
    if (provider == 'microsoft' || provider == 'exchange') {
      out = out
          .replaceFirst(RegExp(r'&prompt=select_account(?=&|$)'), '')
          .replaceFirst(RegExp(r'\?prompt=select_account&'), '?')
          .replaceFirst(RegExp(r'\?prompt=select_account$'), '');
    }
    return '$out${out.contains('?') ? '&' : '?'}login_hint=${Uri.encodeQueryComponent(hint)}';
  }

  /// Авторизация через прокси. Возвращает токены или бросает исключение.
  /// [loginHint] — адрес почты: Google, Microsoft и Яндекс подставят его на
  /// странице входа (1.8.0).
  static Future<OAuthResult> authenticate(String provider, {String? loginHint}) async {
    final base = AppConstants.oauthProxyBaseUrl.replaceAll(RegExp(r'/+$'), '');
    // Без ключа прокси не выдаст токены (POST /exchange отвечает 401), а
    // пользователь увидел бы это только после входа у провайдера. Ключ
    // задаётся при сборке: config/dart_defines.json → OAUTH_PROXY_KEY.
    if (AppConstants.oauthProxyApiKey.isEmpty) {
      AppLogger.error('OAuth ($provider): сборка без OAUTH_PROXY_KEY — вход через прокси невозможен');
      throw errors.AuthException(
        userMessage: 'OAuth ($provider): приложение собрано без ключа OAuth-прокси '
            '(OAUTH_PROXY_KEY). Обратитесь к администратору.',
        messageKey: 'oauthNoProxyKey',
        messageArgs: {'provider': provider},
      );
    }
    final t = _target();
    final pkce = ProxyPkce.generate();
    final loginUrl = '$base/oauth/$provider/login'
        '?redirect=${Uri.encodeComponent(t.redirect)}&cc=${pkce.challenge}';
    var url = loginUrl;
    final hint = hintParam(loginHint);
    if (hint != null && _hintProviders.contains(provider)) {
      final direct = await _providerUrl(loginUrl);
      if (direct != null) {
        url = withHint(direct, provider, hint);
        AppLogger.info('OAuth ($provider): адрес почты подставлен на странице входа службы');
      }
    }

    AppLogger.info('OAuth ($provider): через прокси, возврат на ${t.redirect}');

    final String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: t.callbackScheme,
        options: const FlutterWebAuth2Options(
          // Системный браузер вместо встроенного webview: провайдеры (в частности
          // Google) блокируют OAuth в embedded webview. На мобильных это и так
          // Custom Tabs / ASWebAuthenticationSession.
          useWebview: false,
          timeout: 300,
        ),
      );
    } catch (e) {
      // Браузер закрыт без возврата в приложение. Частая причина — провайдер
      // показал свою ошибку (например, адрес возврата прокси
      // <BASE_URL>/callback не зарегистрирован в консоли Microsoft/Mail.ru)
      // и в приложение ничего не вернулось.
      AppLogger.warning('OAuth ($provider): браузер закрыт без ответа от прокси — $e. '
          'Если провайдер показал ошибку redirect_uri, в его консоли нужно указать '
          '${AppConstants.oauthProxyBaseUrl.replaceAll(RegExp(r'/+$'), '')}/callback');
      rethrow;
    }
    final q = Uri.parse(resultUrl).queryParameters;
    if ((q['error'] ?? '').isNotEmpty) {
      AppLogger.warning('OAuth ($provider): провайдер вернул ошибку ${q['error']}${(q['desc'] ?? '').isEmpty ? '' : ' (${q['desc']})'}');
    }

    final p = await pkce.resolve(base, Uri.parse(resultUrl).queryParameters);
    final at = p['at'];
    if (at == null || at.isEmpty) {
      final err = p['error'];
      final details = err != null ? ' ($err)' : '';
      throw errors.AuthException(
        userMessage: 'OAuth ($provider): токен не получен$details',
        messageKey: 'oauthNoToken',
        messageArgs: {'provider': provider, 'details': details},
      );
    }

    // exp — метка времени в мс; переводим в дату истечения.
    final expMs = int.tryParse(p['exp'] ?? '') ?? 0;
    final expiry = expMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(expMs)
        : DateTime.now().add(const Duration(hours: 1));

    AppLogger.info('OAuth ($provider): токен получен, действует до $expiry');

    return OAuthResult(
      accessToken: at,
      refreshToken: p['rt'], // зашифрованный blob; расшифровывает только прокси
      expiry: expiry,
      // Если прокси сообщает адрес — берём; иначе его запросит вход.
      email: (p['email'] ?? '').isNotEmpty ? p['email'] : null,
      displayName: (p['name'] ?? '').isNotEmpty ? p['name'] : null,
      graphConsent: p['graph'] == '1',
    );
  }
}

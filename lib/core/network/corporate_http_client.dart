// lib/core/network/corporate_http_client.dart
// Возвращает http.Client, доверяющий сертификату корпоративного корпоративного центра
// (*.example.com подписаны внутренним центром, которого нет в корнях BoringSSL).
// На вебе сертификатами управляет браузер — там обычный клиент.

import 'package:http/http.dart' as http;

import 'corporate_http_client_io.dart'
    if (dart.library.html) 'corporate_http_client_web.dart' as impl;

/// Клиент для подключения к корпоративным серверам (Exchange/EAS/EWS).
/// На мобильных/десктопе доверяет самоподписанным сертификатам `*.example.com`.
/// [compat] — режим совместимости со шлюзом для конкретного ящика
/// (null — значение по умолчанию приложения).
http.Client createCorporateHttpClient({bool? compat}) => impl.createCorporateHttpClient(compat: compat);

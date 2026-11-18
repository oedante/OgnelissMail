// lib/core/network/native_android_http_client.dart
// http.Client поверх сетевого стека Android (канал ogneliss/native_http,
// плагин пакета packages/ogneliss_native_http). TLS-рукопожатие — как у
// обычных Android-приложений, а не как у Dart VM: анти-бот шлюз перед
// Exchange различает их по отпечатку TLS и пропускает только первых.
// Плагин регистрируется во всех движках, в том числе в фоновом движке
// WorkManager. Где канала нет (тесты, не Android) — запрос не отправляется.


import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mail_engine/mail_engine.dart' show NetProxy;

import '../logging/app_logger.dart';

import '../security/client_cert_store.dart' show ClientCertStore;
import '../security/trusted_ca_store.dart';
import 'certificate_pinning_bridge.dart';

class NativeAndroidHttpClient extends http.BaseClient {
  static const _ch = MethodChannel('ogneliss/native_http');
  final http.Client _fallback;
  bool _noChannel = false;

  /// [nativeAll] — режим «Совместимость со шлюзом»: все запросы через
  /// Android. false — только к серверам с сертификатом устройства (KeyChain),
  /// остальные — [_fallback] (TLS приложения).
  NativeAndroidHttpClient(this._fallback, {this.nativeAll = true});

  final bool nativeAll;

  static final _certNoted = <String>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final host = request.url.host;
    // Сертификат устройства (Android KeyChain, 2.6.5): ключ не извлекается,
    // TLS с ним — только через сетевой стек Android.
    final alias = ClientCertStore.instance?.aliasFor(host);
    if (alias == null) {
      // Без сертификата устройства: не в режиме совместимости — обычным
      // путём; сертификат-файл (mTLS) предъявляет TLS Dart — тоже.
      if (!nativeAll) return _fallback.send(request);
      if (NetProxy.contextFor(host) != null) {
        if (_certNoted.add(host)) {
          AppLogger.info('Режим совместимости: $host — с сертификатом клиента, через TLS приложения');
        }
        return _fallback.send(request);
      }
    } else if (_certNoted.add('keychain:$host')) {
      AppLogger.info('$host — с сертификатом устройства, через сетевой стек Android');
    }
    if (_noChannel) {
      throw http.ClientException(
          'Режим совместимости со шлюзом: системный сетевой стек недоступен', request.url);
    }
    final body = await request.finalize().toBytes();
    // Сертификаты, принятые пользователем по отпечатку для этого хоста, и
    // доверенные домены — проверку сертификата делает Kotlin, синхронно.
    final svc = CertificatePinningBridge.instance;
    final trust = svc?.nativeTrustFor(request.url.host);
    Map<String, dynamic>? res;
    try {
      res = await _ch.invokeMapMethod<String, dynamic>('send', {
        'method': request.method,
        if (alias != null) 'clientAlias': alias,
        'url': request.url.toString(),
        'headers': Map<String, String>.from(request.headers),
        'body': body,
        // Ping держит соединение до ~15 мин; дальше ограничивает вызывающий.
        'timeoutMs': 20 * 60 * 1000,
        'trustedSha256': trust?.fingerprints ?? const <String>[],
        'acceptAny': trust?.acceptAny ?? false,
        // Закрепление администратора: сверяется и после успешной системной
        // проверки (решение владельца 08.11.2026). Пусто — правил нет.
        'strictSha256': trust?.strict ?? const <String>[],
        'strict': trust?.strict != null,
        'extraCas': TrustedCaStore.instance?.extraForNativeHost(request.url.host) ?? const <Uint8List>[],
        // Организация запретила доверять сертификатам самому (MDM): без
        // установленных на устройство пользователем.
        'systemOnly': !(TrustedCaStore.instance?.userTrustAllowed ?? true),
      });
    } on MissingPluginException {
      // Канала нет (тесты, старая сборка без плагина). На dart:io НЕ
      // переключаемся: шлюз ответит 403 и продлит блокировку адреса —
      // это помешало бы и основному приложению. Запрос не отправляется.
      _noChannel = true;
      throw http.ClientException(
          'Режим совместимости со шлюзом: системный сетевой стек недоступен '
          '— запрос не отправлен',
          request.url);
    } on PlatformException catch (e) {
      final d = e.details;
      if (e.code == 'CERT' && d is Map && svc != null) {
        // Запоминаем отказ — экран входа предложит доверять сертификату.
        svc.evaluateDer(
          der: (d['der'] as Uint8List?) ?? Uint8List(0),
          subject: d['subject'] as String? ?? '',
          issuer: d['issuer'] as String? ?? '',
          validFrom: DateTime.fromMillisecondsSinceEpoch((d['notBefore'] as num?)?.toInt() ?? 0),
          validTo: DateTime.fromMillisecondsSinceEpoch((d['notAfter'] as num?)?.toInt() ?? 0),
          host: request.url.host,
          port: request.url.hasPort ? request.url.port : 443,
        );
      }
      throw http.ClientException(e.message ?? e.code, request.url);
    }
    if (res == null) throw http.ClientException('нет ответа', request.url);
    final bytes = res['body'] as Uint8List? ?? Uint8List(0);
    final headers = <String, String>{
      for (final e in ((res['headers'] as Map?) ?? const {}).entries)
        (e.key as String).toLowerCase(): e.value as String,
    };
    // iPhone (1.6.17): параметры соединения от NSURLSession — протокол, TLS,
    // новое/повторное соединение. Движок пишет их в журнал (x-ogneliss-net).
    final net = res['net'];
    if (net is String && net.isNotEmpty) headers['x-ogneliss-net'] = net;
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      res['status'] as int,
      contentLength: bytes.length,
      headers: headers,
      request: request,
      reasonPhrase: res['reason'] as String?,
    );
  }

  @override
  void close() => _fallback.close();
}

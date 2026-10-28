// lib/services/mail/ews/ntlm_client.dart
// Полная реализация NTLMv2 аутентификации для Exchange.
// 3-step handshake: Negotiate → Challenge → Authenticate
// Поддержка: NTLMv2, Unicode, target info, timestamp, client challenge.

import '../../../core/network/certificate_pinning_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' hide Digest;
import 'package:pointycastle/export.dart';
import 'package:mail_engine/mail_engine.dart' show EasEngine;

import '../../../core/logging/app_logger.dart';

class NtlmClient {
  final String username;
  final String password;
  final String domain;

  /// Пул HTTP-клиентов, у каждого РОВНО одно соединение.
  ///
  /// NTLM аутентифицирует TCP-соединение, а не запрос: Type 1 и Type 3 обязаны
  /// уйти по одному и тому же соединению. Раньше один HttpClient обслуживал
  /// все параллельные запросы (синхронизация идёт в 3 потока), и Type 3 мог
  /// уйти по ЧУЖОМУ соединению из пула — сервер отвечал 401, запрос падал
  /// «случайно», а повторы приближали блокировку учётной записи. Теперь
  /// каждый запрос берёт клиент в монопольное пользование.
  final List<HttpClient> _idle = [];
  static const _maxIdle = 4;

  /// Схема, которую принял сервер в прошлый раз (NTLM / Negotiate / Basic).
  String? _scheme;

  /// Extended Protection for Authentication (EPA). После CVE-2024-21410
  /// Microsoft рекомендует на Exchange режим «Required»: NTLM без привязки к
  /// TLS-каналу (MsvAvChannelBindings) получает 401. Привязку добавляем НЕ
  /// сразу: за обратным прокси с расшифровкой TLS (WAF) она указывала бы на
  /// сертификат прокси, и сервер в режиме «Accept» отверг бы вход, который
  /// без привязки проходит. Поэтому — только после 401 и один раз на клиента.
  bool _useCbt = false;
  bool _cbtTried = false;
  X509Certificate? _serverCert;

  NtlmClient({
    required String username,
    required this.password,
    required String domain,
  })  : username = _splitUser(username, domain).$1,
        domain = _splitUser(username, domain).$2,
        _bearerSource = null;

  /// Exchange Online (Microsoft 365) по OAuth (1.6.2): вместо NTLM — токен
  /// Bearer; после 401 — новый токен и один повтор.
  NtlmClient.bearer(Future<String?> Function({bool force}) source)
      : username = '',
        password = '',
        domain = '',
        _bearerSource = source;

  final Future<String?> Function({bool force})? _bearerSource;
  String? _bearerToken;

  Future<HttpClientResponse> _withBearer(HttpClient c, Uri uri, Map<String, String> headers,
      List<int> body, Duration timeout) async {
    final src = _bearerSource!;
    _bearerToken ??= await src();
    var r = await _send(c, uri, headers, body, 'Bearer ${_bearerToken ?? ''}', timeout);
    if (r.statusCode != 401) return r;
    await r.drain<void>();
    final fresh = await src(force: true);
    if (fresh == null || fresh.isEmpty || fresh == _bearerToken) {
      return _send(c, uri, headers, body, 'Bearer ${_bearerToken ?? ''}', timeout);
    }
    _bearerToken = fresh;
    AppLogger.info('EWS: 401 с токеном OAuth — токен обновлён, повтор');
    r = await _send(c, uri, headers, body, 'Bearer $fresh', timeout);
    return r;
  }

  /// «DOMAIN\user» → (user, DOMAIN). UPN «user@corp.ru» оставляем как есть —
  /// NTLMv2 принимает его с пустым доменом.
  static (String, String) _splitUser(String user, String domain) {
    final i = user.indexOf('\\');
    if (i > 0) return (user.substring(i + 1), user.substring(0, i));
    return (user, domain);
  }

  static HttpClient _createHttpClient() {
    final client = HttpClient();
    // Делегируем проверку сертификата в политику пиннинга (как глобальный HttpOverrides).
    // По умолчанию (до инициализации) — строгая системная проверка.
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final svc = CertificatePinningBridge.instance;
      if (svc == null) return false;
      return svc.evaluate(cert, host, port);
    };
    client.connectionTimeout = const Duration(seconds: 30);
    client.maxConnectionsPerHost = 1;
    client.idleTimeout = const Duration(seconds: 50);
    return client;
  }

  HttpClient _borrow() => _idle.isNotEmpty ? _idle.removeLast() : _createHttpClient();

  void _release(HttpClient c, {bool broken = false}) {
    if (broken || _idle.length >= _maxIdle) {
      c.close(force: broken);
    } else {
      _idle.add(c);
    }
  }

  /// Закрыть все соединения (смена пароля, выход из аккаунта).
  void close() {
    for (final c in _idle) {
      c.close(force: true);
    }
    _idle.clear();
  }

  String get _basic =>
      'Basic ${base64.encode(utf8.encode('${domain.isNotEmpty && !username.contains('@') ? '$domain\\' : ''}$username:$password'))}';

  /// Выбрать схему по заголовкам WWW-Authenticate: NTLM, иначе Negotiate
  /// (IIS принимает в нём «голый» NTLMSSP-токен), иначе Basic.
  static String? _pickScheme(List<String>? www) {
    if (www == null) return null;
    final all = www.expand((v) => v.split(',')).map((v) => v.trim().toLowerCase()).toList();
    if (all.any((v) => v == 'ntlm' || v.startsWith('ntlm '))) return 'NTLM';
    if (all.any((v) => v == 'negotiate' || v.startsWith('negotiate '))) return 'Negotiate';
    if (all.any((v) => v.startsWith('basic'))) return 'Basic';
    return null;
  }

  static String? _tokenFor(List<String>? www, String scheme) {
    for (final v in www ?? const <String>[]) {
      for (final part in v.split(',')) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('${scheme.toLowerCase()} ')) {
          return t.substring(scheme.length + 1).trim();
        }
      }
    }
    return null;
  }

  Future<HttpClientResponse> _send(HttpClient c, Uri uri, Map<String, String> headers,
      List<int> body, String? auth, Duration timeout) async {
    final request = await c.openUrl('POST', uri).timeout(timeout);
    request.persistentConnection = true;
    headers.forEach((k, v) => request.headers.set(k, v));
    if (auth != null) request.headers.set('Authorization', auth);
    request.contentLength = body.length;
    if (body.isNotEmpty) request.add(body);
    return request.close().timeout(timeout);
  }

  /// Пройти аутентификацию на соединении клиента [c] и выполнить запрос.
  /// Возвращает ответ на запрос С ТЕЛОМ (тело ещё не прочитано).
  /// Пауза после отказа анти-бот шлюза (1.6.17), общая с движком почты:
  /// ключ «ews:<хост>». Пока она идёт, запрос не отправляется — повторы через
  /// сетевой стек Dart шлюз ServicePipe засчитывает как бота и держит
  /// блокировку. Отказ шлюза — 403 со страницей HTML вместо ответа Exchange.
  Future<HttpClientResponse> _authenticated(HttpClient c, Uri uri,
      Map<String, String> headers, List<int> body, Duration timeout) async {
    final key = 'ews:${uri.host}';
    final left = EasEngine.wafPauseMinutesLeft(key);
    if (left > 0) {
      throw HttpException('EWS ${uri.host}: шлюз недавно отклонил запросы — пауза ещё $left мин', uri: uri);
    }
    final r = await _authenticatedAny(c, uri, headers, body, timeout);
    if (r.statusCode == 403 && (r.headers.contentType?.mimeType ?? '') == 'text/html') {
      EasEngine.markWafBlocked(key);
      AppLogger.warning('EWS ${uri.host}: 403 от шлюза перед Exchange — запросы приостановлены на 15 мин');
    }
    return r;
  }

  Future<HttpClientResponse> _authenticatedAny(HttpClient c, Uri uri,
      Map<String, String> headers, List<int> body, Duration timeout) async {
    if (_bearerSource != null) return _withBearer(c, uri, headers, body, timeout);
    final r = await _authenticatedOnce(c, uri, headers, body, timeout, cbt: _useCbt);
    if (r.statusCode == 401 && !_useCbt && !_cbtTried && _scheme != 'Basic' && _serverCert != null) {
      _cbtTried = true;
      await r.drain<void>();
      AppLogger.info('NTLM: 401 — повтор с привязкой к TLS-каналу (Extended Protection)');
      final r2 = await _authenticatedOnce(c, uri, headers, body, timeout, cbt: true);
      if (r2.statusCode != 401) {
        _useCbt = true;
        AppLogger.info('NTLM: сервер требует Extended Protection — привязка включена');
      }
      return r2;
    }
    return r;
  }

  Future<HttpClientResponse> _authenticatedOnce(HttpClient c, Uri uri,
      Map<String, String> headers, List<int> body, Duration timeout, {required bool cbt}) async {
    // Сервер уже принимал Basic — сразу с ним (без лишнего круга).
    if (_scheme == 'Basic') {
      final r = await _send(c, uri, headers, body, _basic, timeout);
      if (r.statusCode != 401) return r;
      final www = r.headers['www-authenticate'];
      await r.drain<void>();
      _scheme = _pickScheme(www);
      if (_scheme == 'Basic' || _scheme == null) {
        return _send(c, uri, headers, body, _basic, timeout);
      }
    }

    // ── Шаг 1: Type 1 (Negotiate) — без тела: письмо с вложениями не
    // гоняем по сети дважды, сервер всё равно ответит 401 с вызовом.
    final scheme = _scheme ?? 'NTLM';
    var r = await _send(c, uri, headers, const [], '$scheme ${base64.encode(_buildType1Message())}', timeout);
    if (r.statusCode != 401) {
      // 403 на согласование — отказ шлюза или сервера: запрос с телом получит
      // то же самое, лишний POST только продлил бы блокировку (1.6.17).
      if (r.statusCode == 403) return r;
      // Аутентификация не потребовалась (например, её снял обратный прокси) —
      // повторяем запрос уже с телом.
      await r.drain<void>();
      return _send(c, uri, headers, body, null, timeout);
    }
    final www = r.headers['www-authenticate'];
    _serverCert = r.certificate ?? _serverCert;
    await r.drain<void>();

    var token = _tokenFor(www, scheme);
    if (token == null || token.isEmpty) {
      // Сервер не понял нашу схему. Смотрим, что он предлагает.
      final offered = _pickScheme(www);
      if (offered == 'Basic') {
        _scheme = 'Basic';
        AppLogger.info('EWS: сервер принимает только Basic — переключаемся');
        return _send(c, uri, headers, body, _basic, timeout);
      }
      if (offered != null && offered != scheme) {
        r = await _send(c, uri, headers, const [], '$offered ${base64.encode(_buildType1Message())}', timeout);
        final www2 = r.headers['www-authenticate'];
        await r.drain<void>();
        token = _tokenFor(www2, offered);
        if (r.statusCode == 401 && token != null && token.isNotEmpty) {
          _scheme = offered;
          return _send(c, uri, headers, body,
              '$offered ${base64.encode(_buildType3Message(_parseType2Message(base64.decode(token)), cbt: cbt))}', timeout);
        }
      }
      throw const HttpException('NTLM: сервер не прислал вызов (WWW-Authenticate)');
    }

    _scheme = scheme;
    // ── Шаг 3: Type 3 (Authenticate) по тому же соединению, уже с телом.
    final challenge = _parseType2Message(base64.decode(token));
    return _send(c, uri, headers, body, '$scheme ${base64.encode(_buildType3Message(challenge, cbt: cbt))}', timeout);
  }

  /// HTTP POST с NTLM-аутентификацией (с откатом на Negotiate/Basic).
  Future<NtlmResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    int timeoutSeconds = 30,
  }) async {
    final bodyBytes = utf8.encode(body);
    final c = _borrow();
    var broken = false;
    try {
      final response = await _authenticated(c, uri, headers, bodyBytes, Duration(seconds: timeoutSeconds));
      final b = await response
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(Duration(seconds: timeoutSeconds));
      return NtlmResponse(statusCode: response.statusCode, body: b, headers: _extractHeaders(response));
    } catch (e, stack) {
      broken = true;
      AppLogger.error('NTLM request failed', e, stack);
      rethrow;
    } finally {
      _release(c, broken: broken);
    }
  }

  /// POST с NTLM, возвращающий ПОТОК тела ответа (не собирая его целиком).
  ///
  /// Нужен для EWS Streaming Notifications (`GetStreamingEvents`): сервер
  /// держит HTTP-соединение открытым до `ConnectionTimeout` и отправляет
  /// SOAP-конверты по мере появления событий. Собирать тело целиком нельзя —
  /// иначе мы получили бы уведомления только после закрытия соединения.
  ///
  /// Таймаут применяется только к УСТАНОВКЕ соединения; чтение потока не
  /// ограничивается по времени (это и есть длительное ожидание событий).
  /// Вызывающий обязан подписаться на поток и отменить подписку при остановке.
  /// Для потока берётся отдельный клиент — он закрывается вместе с потоком.
  Future<NtlmStreamedResponse> postStreaming(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    int connectTimeoutSeconds = 30,
  }) async {
    final c = _createHttpClient();
    try {
      final response = await _authenticated(
          c, uri, headers, utf8.encode(body), Duration(seconds: connectTimeoutSeconds));
      // close() без force даёт текущему ответу дочитаться, затем закрывает.
      c.close();
      return NtlmStreamedResponse(
        statusCode: response.statusCode,
        stream: response.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)),
      );
    } catch (_) {
      c.close(force: true);
      rethrow;
    }
  }

  // ════════════════════════ TYPE 1 (NEGOTIATE) ════════════════════════

  Uint8List _buildType1Message() {
    final buf = BytesBuilder();

    // Signature: "NTLMSSP\0"
    buf.add(utf8.encode('NTLMSSP'));
    buf.addByte(0);

    // Type: 1 (Negotiate)
    buf.add(_uint32LE(1));

    // Flags: Unicode | OEM | Request Target | NTLM | Always Sign |
    //        Extended Session Security | 128-bit | 56-bit.
    // Раньше здесь стояло 0x8897: в нём НЕ было флага NTLM (0x200), зато
    // были «анонимный вход» (0x800), LM_KEY и SIGN — часть серверов на такое
    // согласование отвечала отказом.
    const flags = 0x00000001 | // NEGOTIATE_UNICODE
        0x00000002 | // NEGOTIATE_OEM
        0x00000004 | // REQUEST_TARGET
        0x00000200 | // NEGOTIATE_NTLM
        0x00008000 | // ALWAYS_SIGN
        0x00080000 | // EXTENDED_SESSIONSECURITY
        0x20000000 | // NEGOTIATE_128
        0x80000000; // NEGOTIATE_56
    buf.add(_uint32LE(flags));

    // Domain: empty (len=0, offset=0)
    buf.add(_uint16LE(0)); // DomainLen
    buf.add(_uint16LE(0)); // DomainMaxLen
    buf.add(_uint32LE(0)); // DomainOffset

    // Workstation: empty
    buf.add(_uint16LE(0));
    buf.add(_uint16LE(0));
    buf.add(_uint32LE(0));

    return Uint8List.fromList(buf.toBytes());
  }

  // ════════════════════════ TYPE 2 (CHALLENGE) PARSE ════════════════════════

  _NtlmChallenge _parseType2Message(Uint8List data) {
    // Validate signature
    final sig = utf8.decode(data.sublist(0, 7));
    if (sig != 'NTLMSSP') throw Exception('NTLM: Invalid Type 2 signature');

    final type = _readUint32LE(data, 8);
    if (type != 2) throw Exception('NTLM: Expected Type 2, got $type');

    // Target name
    final targetNameLen = _readUint16LE(data, 12);
    final targetNameOffset = _readUint32LE(data, 16);
    final targetName = targetNameLen > 0 && targetNameOffset + targetNameLen <= data.length
        ? _readUnicodeString(data, targetNameOffset, targetNameLen)
        : '';

    // Flags
    final flags = _readUint32LE(data, 20);

    // Server challenge (8 bytes)
    final serverChallenge = Uint8List.fromList(data.sublist(24, 32));

    // Target info (if present)
    Uint8List? targetInfo;
    if (data.length >= 48) {
      final targetInfoLen = _readUint16LE(data, 40);
      final targetInfoOffset = _readUint32LE(data, 44);
      if (targetInfoLen > 0 && targetInfoOffset + targetInfoLen <= data.length) {
        targetInfo = Uint8List.fromList(data.sublist(targetInfoOffset, targetInfoOffset + targetInfoLen));
      }
    }

    return _NtlmChallenge(
      serverChallenge: serverChallenge,
      targetName: targetName,
      flags: flags,
      targetInfo: targetInfo,
    );
  }

  // ════════════════════════ TYPE 3 (AUTHENTICATE) ════════════════════════

  Uint8List _buildType3Message(_NtlmChallenge challenge, {bool cbt = false}) {
    final cert = _serverCert;
    final info = (cbt && cert != null && challenge.targetInfo != null)
        ? withChannelBindings(challenge.targetInfo!, channelBindingsHash(cert.der))
        : challenge.targetInfo;
    // NTLMv2 computation
    // Identity: НЕ повышаем регистр домена — только username.toUpperCase()
    final usernameUnicode = _toUnicode(username.toUpperCase());
    final domainIdentityUnicode = _toUnicode(domain);
    final passwordUnicode = _toUnicode(password);

    // Step 1: NT Hash = MD4(unicode(password))
    final ntHash = _md4(passwordUnicode);

    // Step 2: NTLMv2 Hash = HMAC_MD5(NT Hash, unicode(upper(username) + domain))
    final identity = Uint8List.fromList([...usernameUnicode, ...domainIdentityUnicode]);
    final ntlmv2Hash = _hmacMd5(ntHash, identity);

    // Step 3: Client challenge (8 random bytes)
    final clientChallenge = _randomBytes(8);

    // Step 4: Timestamp (Windows FILETIME). По MS-NLMP 3.1.5.1.2 клиент
    // берёт время сервера (MsvAvTimestamp), если тот его прислал: при
    // расхождении часов устройства и контроллера домена иначе возможен отказ.
    final timestamp = _avTimestamp(info) ?? _windowsTimestamp();

    // Step 5: Build blob
    final blob = _buildNtlmv2Blob(clientChallenge, timestamp, info);

    // Step 6: NTProofStr = HMAC_MD5(NTLMv2Hash, serverChallenge + blob)
    final concat = Uint8List.fromList([...challenge.serverChallenge, ...blob]);
    final ntProofStr = _hmacMd5(ntlmv2Hash, concat);

    // Step 7: NT Response = NTProofStr + Blob
    final ntResponse = Uint8List.fromList([...ntProofStr, ...blob]);

    // Step 8: LM Response (для NTLMv2: HMAC_MD5(NTLMv2Hash, serverChallenge + clientChallenge) + clientChallenge)
    final lmConcat = Uint8List.fromList([...challenge.serverChallenge, ...clientChallenge]);
    final lmProof = _hmacMd5(ntlmv2Hash, lmConcat);
    final lmResponse = Uint8List.fromList([...lmProof, ...clientChallenge]);

    // Build Type 3 message
    final domainBytes = _toUnicode(domain);
    final userBytes = _toUnicode(username);
    final workstationBytes = _toUnicode('WORKSTATION');

    // Заголовок Type 3: подпись 8 + тип 4 + шесть дескрипторов по 8 + флаги 4
    // = 64 байта. Блок Version (ещё 8) не пишется, поэтому и флаг
    // NEGOTIATE_VERSION ниже снимается. Прежде смещения считались от 72 —
    // сервер читал ответы LM/NT со сдвигом на 8 байт и отвечал 401.
    const headerLen = 64;
    const lmOffset = headerLen;
    final ntOffset = lmOffset + lmResponse.length;
    final domainOffset = ntOffset + ntResponse.length;
    final userOffset = domainOffset + domainBytes.length;
    final workstationOffset = userOffset + userBytes.length;

    final buf = BytesBuilder();

    // Signature
    buf.add(utf8.encode('NTLMSSP'));
    buf.addByte(0);

    // Type: 3
    buf.add(_uint32LE(3));

    // LM Response
    buf.add(_uint16LE(lmResponse.length));
    buf.add(_uint16LE(lmResponse.length));
    buf.add(_uint32LE(lmOffset));

    // NT Response
    buf.add(_uint16LE(ntResponse.length));
    buf.add(_uint16LE(ntResponse.length));
    buf.add(_uint32LE(ntOffset));

    // Domain
    buf.add(_uint16LE(domainBytes.length));
    buf.add(_uint16LE(domainBytes.length));
    buf.add(_uint32LE(domainOffset));

    // User
    buf.add(_uint16LE(userBytes.length));
    buf.add(_uint16LE(userBytes.length));
    buf.add(_uint32LE(userOffset));

    // Workstation
    buf.add(_uint16LE(workstationBytes.length));
    buf.add(_uint16LE(workstationBytes.length));
    buf.add(_uint32LE(workstationOffset));

    // Encrypted random session key (empty)
    buf.add(_uint16LE(0));
    buf.add(_uint16LE(0));
    buf.add(_uint32LE(workstationOffset + workstationBytes.length));

    // Flags: отвечаем согласованными флагами, но без обмена ключом, подписи и
    // шифрования — сессионный ключ мы не передаём, а заявленный KEY_EXCH без
    // ключа часть серверов отвергает.
    const dropped = 0x40000000 | // KEY_EXCH
        0x00000010 | // SIGN
        0x00000020 | // SEAL
        0x00000080 | // LM_KEY
        0x00000800 | // ANONYMOUS
        0x02000000; // VERSION — блок Version не передаём
    buf.add(_uint32LE(challenge.flags & ~dropped));

    // Payload
    buf.add(lmResponse);
    buf.add(ntResponse);
    buf.add(domainBytes);
    buf.add(userBytes);
    buf.add(workstationBytes);

    return Uint8List.fromList(buf.toBytes());
  }

  // ════════════════════════ NTLMv2 BLOB ════════════════════════

  Uint8List _buildNtlmv2Blob(Uint8List clientChallenge, Uint8List timestamp, Uint8List? targetInfo) {
    final buf = BytesBuilder();
    buf.add(_uint32LE(0x00000101)); // Blob signature
    buf.add(_uint32LE(0x00000000)); // Reserved
    buf.add(timestamp);             // Timestamp (8 bytes)
    buf.add(clientChallenge);       // Client challenge (8 bytes)
    buf.add(_uint32LE(0x00000000)); // Reserved
    if (targetInfo != null) {
      buf.add(targetInfo);          // Target info
    }
    buf.add(_uint32LE(0x00000000)); // End padding
    return Uint8List.fromList(buf.toBytes());
  }

  // ════════════════════════ EPA: CHANNEL BINDINGS ════════════════════════

  /// MD5 структуры gss_channel_bindings_struct с данными приложения
  /// «tls-server-end-point:» + хэш сертификата сервера (RFC 5929, MS-NLMP
  /// 3.1.5.1.2). Хэш — алгоритмом подписи сертификата, но не слабее SHA-256.
  static Uint8List channelBindingsHash(Uint8List certDer) {
    final certHash = _certHash(certDer);
    final app = [...ascii.encode('tls-server-end-point:'), ...certHash];
    final b = BytesBuilder();
    Uint8List u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
    b
      ..add(u32(0)) // initiator_addrtype
      ..add(u32(0)) // initiator_address.length
      ..add(u32(0)) // acceptor_addrtype
      ..add(u32(0)) // acceptor_address.length
      ..add(u32(app.length))
      ..add(app);
    return Uint8List.fromList(md5.convert(b.toBytes()).bytes);
  }

  static List<int> _certHash(Uint8List der) {
    final oid = _signatureAlgorithmOid(der);
    // sha384WithRSA, ecdsa-with-SHA384
    if (oid == '2a864886f70d01010c' || oid == '2a8648ce3d040303') return sha384.convert(der).bytes;
    // sha512WithRSA, ecdsa-with-SHA512
    if (oid == '2a864886f70d01010d' || oid == '2a8648ce3d040304') return sha512.convert(der).bytes;
    return sha256.convert(der).bytes; // MD5, SHA-1 и SHA-256 → SHA-256
  }

  /// OID алгоритма подписи (hex) — второй элемент Certificate ::= SEQUENCE.
  static String? _signatureAlgorithmOid(Uint8List d) {
    try {
      (int, int) hdr(int p) {
        // → (начало содержимого, длина)
        var len = d[p + 1];
        var off = p + 2;
        if (len & 0x80 != 0) {
          final n = len & 0x7f;
          len = 0;
          for (var i = 0; i < n; i++) {
            len = (len << 8) | d[off + i];
          }
          off += n;
        }
        return (off, len);
      }

      final (certStart, _) = hdr(0); // Certificate
      final (tbsStart, tbsLen) = hdr(certStart); // tbsCertificate
      final algPos = tbsStart + tbsLen; // signatureAlgorithm SEQUENCE
      final (algStart, _) = hdr(algPos);
      if (d[algStart] != 0x06) return null; // OBJECT IDENTIFIER
      final (oidStart, oidLen) = hdr(algStart);
      return d
          .sublist(oidStart, oidStart + oidLen)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      return null;
    }
  }

  /// TargetInfo с парой MsvAvChannelBindings (AvId 0x000A) перед MsvAvEOL.
  static Uint8List withChannelBindings(Uint8List info, Uint8List cbtHash) {
    final out = BytesBuilder();
    var p = 0;
    while (p + 4 <= info.length) {
      final id = info[p] | (info[p + 1] << 8);
      final len = info[p + 2] | (info[p + 3] << 8);
      if (id == 0) break; // EOL
      if (id != 0x000A) out.add(info.sublist(p, p + 4 + len)); // старую привязку заменяем
      p += 4 + len;
    }
    out
      ..add([0x0A, 0x00, 0x10, 0x00])
      ..add(cbtHash)
      ..add([0, 0, 0, 0]); // MsvAvEOL
    return Uint8List.fromList(out.toBytes());
  }

  // ════════════════════════ CRYPTO ════════════════════════

  Uint8List _md4(Uint8List data) {
    final d = MD4Digest();
    final out = Uint8List(d.digestSize);
    d.update(data, 0, data.length);
    d.doFinal(out, 0);
    return out;
  }

  Uint8List _hmacMd5(Uint8List key, Uint8List data) {
    final hmac = Hmac(md5, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  // ════════════════════════ HELPERS ════════════════════════

  Uint8List _toUnicode(String str) {
    final buf = BytesBuilder();
    for (final codeUnit in str.codeUnits) {
      buf.addByte(codeUnit & 0xFF);
      buf.addByte((codeUnit >> 8) & 0xFF);
    }
    return Uint8List.fromList(buf.toBytes());
  }

  String _readUnicodeString(Uint8List data, int offset, int length) {
    final chars = <int>[];
    for (int i = 0; i < length; i += 2) {
      if (offset + i + 1 >= data.length) break;
      chars.add(data[offset + i] | (data[offset + i + 1] << 8));
    }
    return String.fromCharCodes(chars);
  }

  Uint8List _uint16LE(int value) => Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
  Uint8List _uint32LE(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  int _readUint16LE(Uint8List data, int offset) => data[offset] | (data[offset + 1] << 8);
  int _readUint32LE(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24);

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  /// MsvAvTimestamp (AvId 7) из TargetInfo сервера.
  Uint8List? _avTimestamp(Uint8List? info) {
    if (info == null) return null;
    var p = 0;
    while (p + 4 <= info.length) {
      final id = _readUint16LE(info, p);
      final len = _readUint16LE(info, p + 2);
      if (id == 0) break; // MsvAvEOL
      if (id == 7 && len == 8 && p + 12 <= info.length) {
        return Uint8List.fromList(info.sublist(p + 4, p + 12));
      }
      p += 4 + len;
    }
    return null;
  }

  /// Windows FILETIME: 100-nanosecond intervals since January 1, 1601
  Uint8List _windowsTimestamp() {
    final now = DateTime.now().toUtc();
    // Difference between 1601-01-01 and 1970-01-01 in 100ns intervals
    const epoch1601 = 116444736000000000;
    final microseconds = now.microsecondsSinceEpoch;
    final filetime = microseconds * 10 + epoch1601;

    final buf = Uint8List(8);
    buf.buffer.asByteData().setUint64(0, filetime, Endian.little);
    return buf;
  }

  Map<String, String> _extractHeaders(HttpClientResponse response) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return headers;
  }
}

class NtlmResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const NtlmResponse({required this.statusCode, required this.body, this.headers = const {}});
}

/// Ответ с НЕсобранным телом — для долгоживущих соединений
/// (EWS Streaming Notifications).
class NtlmStreamedResponse {
  final int statusCode;
  final Stream<String> stream;

  const NtlmStreamedResponse({required this.statusCode, required this.stream});
}

class _NtlmChallenge {
  final Uint8List serverChallenge;
  final String targetName;
  final int flags;
  final Uint8List? targetInfo;

  const _NtlmChallenge({
    required this.serverChallenge,
    required this.targetName,
    required this.flags,
    this.targetInfo,
  });
}

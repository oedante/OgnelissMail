// lib/src/transport/eas_engine.dart
// EAS (Exchange ActiveSync) движок — УНИВЕРСАЛЬНЫЙ, боевое ядро.
//
// Request Line: по умолчанию EAS 16.1 + Base64 command line (MS-ASHTTP),
// с автоматическим fallback на 14.1 + plain query-string при неуспехе.
// Полное подробное логирование каждого HTTP-обмена через DebugLog.
//
// Реализовано: connect (OPTIONS + Autodiscover) + Provisioning (PolicyKey + политики).
// Sync/SendMail/CRUD на WBXML — шаг 2 (порт sync-классов из приложения).

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../debug_log.dart';
import '../mail_engine.dart';
import '../models/models.dart';
import 'autodiscover.dart';
import 'wbxml_codec.dart';

/// Коды команд EAS (MS-ASHTTP) для Base64 command line.
const Map<String, int> easCommandCodes = {
  'Sync': 0, 'SendMail': 1, 'SmartForward': 2, 'SmartReply': 3, 'GetAttachment': 4,
  'FolderSync': 9, 'FolderCreate': 10, 'FolderDelete': 11, 'FolderUpdate': 12,
  'MoveItems': 13, 'GetItemEstimate': 14, 'MeetingResponse': 15, 'Search': 16,
  'Settings': 17, 'Ping': 18, 'ItemOperations': 19, 'Provision': 20,
  'ResolveRecipients': 21, 'ValidateCert': 22, 'Find': 23,
};

/// Шлюз перед Exchange не пропустил большой запрос (письмо с вложениями):
/// страница блокировки шлюза в ответ на SendMail с телом от
/// [EasEngine.bigBodyBytes]. Журнал владельца 25.10.2026 (1.7.2+113): письмо
/// с фото — 403 от шлюза ServicePipe семь раз подряд, а письмо без
/// вложений через минуту ушло. Похоже на ограничение размера запроса у
/// шлюза: повтор того же письма не поможет, нужно уменьшить вложения.
class GatewaySizeRejected implements Exception {
  /// Размер письма (MIME), байт.
  final int bytes;
  const GatewaySizeRejected(this.bytes);

  @override
  String toString() => 'EAS SendMail: шлюз организации не пропустил письмо '
      '${(bytes / 1048576).toStringAsFixed(1)} МБ (HTTP 403, письмо не отправлено)';
}

class EasEngine implements MailEngine {
  final DebugLog log;
  final http.Client _http;
  EasEngine({DebugLog? logger, http.Client? httpClient})
      : log = logger ?? DebugLog(),
        _http = httpClient ?? http.Client();

  static const _t = 'EAS';

  AccountConfig? _cfg;
  String? _resolvedHost;

  /// Адрес EWS, найденный при Autodiscover (для гибридного режима).
  String? _companionEwsUrl;
  String? _easUrl;
  /// Все cookie сервера (name→value), а не только X-BackEndCookie. Анти-бот
  /// шлюз (ServicePipe, заголовок X-SP-CRID) ставит свой cookie на ответ
  /// OPTIONS и требует его на POST — без него Provision получал 403 «If you
  /// are not a bot», хотя OPTIONS с тем же клиентом проходил (журнал iPhone
  /// 17.10.2026). Штатная Почта iPhone несёт все cookie автоматически
  /// (cookie jar NSURLSession); движок (чистый Dart, запросы независимы)
  /// должен вести их сам.
  final Map<String, String> _cookieJar = {};
  String? _policyKey;

  /// Сервер ответил на Provision «политики нет» (Status 2): ключ не нужен.
  bool _noPolicy = false;
  String _protocolVersion = '16.1'; // боевой дефолт; fallback на 14.1
  bool _useBase64 = true; // 16.1 Base64; при fallback → false (14.1 query)
  List<String> _protocolVersions = [];
  List<String> _serverCommands = [];
  SecurityPolicy? _policy;

  @override
  MailTransportKind get kind => MailTransportKind.eas;

  @override
  Capabilities get capabilities => const Capabilities(
        mail: true, calendar: true, contacts: true, tasks: true, notes: true,
        push: true, policies: true,
      );

  @override
  SecurityPolicy? get policy => _policy;

  /// Обработчик команды удалённого стирания (устанавливает приложение).
  /// Вызывается после того, как получение команды подтверждено серверу.
  /// Раньше команда только записывалась в журнал: данные оставались на
  /// устройстве, а сервер бесконечно показывал «стирание ожидается».
  static void Function(String email, RemoteWipeKind kind)? remoteWipeHandler;

  RemoteWipeKind? _remoteWipe;
  RemoteWipeKind? get remoteWipe => _remoteWipe;

  String _authUser(AccountConfig cfg) {
    if (cfg.domain != null && cfg.domain!.isNotEmpty) {
      final user = cfg.email.contains('@') ? cfg.email.split('@').first : cfg.email;
      return '${cfg.domain}\\$user';
    }
    return cfg.email;
  }

  String _basicAuth(AccountConfig cfg) =>
      'Basic ${base64.encode(utf8.encode('${_authUser(cfg)}:${cfg.password ?? ''}'))}';

  /// Токен Exchange Online (Microsoft 365, 1.6.2): вход по OAuth — заголовок
  /// Bearer вместо Basic. Обычный Exchange — как раньше.
  String? _bearer;

  String _authHeader(AccountConfig cfg) => cfg.authKind == AuthKind.oauth2
      ? 'Bearer ${_bearer ?? cfg.oauthAccessToken ?? ''}'
      : _basicAuth(cfg);

  /// Взять у приложения действующий токен ([force] — сервер отверг прежний).
  /// true — токен сменился, запрос стоит повторить.
  Future<bool> _takeBearer(AccountConfig cfg, {required bool force}) async {
    final src = cfg.oauthTokenSource;
    if (cfg.authKind != AuthKind.oauth2 || src == null) return false;
    try {
      final t = await src(force: force);
      if (t == null || t.isEmpty || t == (_bearer ?? cfg.oauthAccessToken)) return false;
      _bearer = t;
      return true;
    } catch (e) {
      log.warn(_t, 'Токен OAuth не обновлён: $e');
      return false;
    }
  }

  String get _deviceId {
    if (_cfg?.deviceId != null && _cfg!.deviceId!.isNotEmpty) return _cfg!.deviceId!;
    final bytes = utf8.encode(_cfg?.email ?? 'device');
    final sb = StringBuffer();
    for (final b in bytes.take(12)) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final hex = sb.toString().toUpperCase();
    return 'OGNL${hex.padRight(24, '0').substring(0, 24)}';
  }

  String get _deviceType => _cfg?.deviceType ?? 'Android';

  // ─────────────────── СЕАНС МЕЖДУ ЗАПУСКАМИ ───────────────────
  // Фоновая проверка (WorkManager, раз в 15 минут) каждый раз начинала с
  // нуля: OPTIONS и двухшаговый Provision — три запроса и 10–12 секунд
  // работы радио на каждую проверку (журнал 10.10.2026). Адрес, версия
  // протокола и PolicyKey не меняются неделями — их сохраняет приложение
  // ([loadSession]/[saveSession]), и подключение сразу идёт к делу. Если
  // политика устарела или администратор запросил стирание, сервер ответит
  // 449/Status 140–144 — и Provision выполнится как обычно.

  /// Прочитать сохранённый сеанс (JSON) по адресу ящика.
  static String? Function(String email)? loadSession;

  /// Сохранить (или удалить — null) сеанс ящика.
  static void Function(String email, String? data)? saveSession;

  /// Сеанс старше — полное подключение (политики обновляются хотя бы так).
  static const sessionMaxAge = Duration(hours: 12);

  void _storeSession(AccountConfig cfg) {
    final save = saveSession;
    if (save == null || _easUrl == null || _policyKey == null || _policyKey!.isEmpty) return;
    try {
      save(cfg.email, jsonEncode({
        'v': 1,
        'server': cfg.exchangeServer ?? '',
        'device': _deviceId,
        'url': _easUrl,
        'host': _resolvedHost,
        'proto': _protocolVersion,
        'b64': _useBase64,
        'versions': _protocolVersions,
        'cmds': _serverCommands,
        'key': _policyKey,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (e) {
      log.debug(_t, 'Сеанс не сохранён: $e');
    }
  }

  /// Сеанс восстановлен из сохранённого и ещё не подтверждён ответом сервера.
  bool _fromSession = false;

  /// Сохранённый сеанс больше не годится (неверный пароль, адрес не
  /// отвечает, ящик переехал): следующее подключение — полное, с OPTIONS,
  /// Provision и перебором адресов. Раньше устаревший сеанс жил до 12 часов.
  void _dropSession(AccountConfig cfg, String why) {
    _fromSession = false;
    log.warn(_t, 'Сохранённый сеанс сброшен ($why) — следующее подключение полное');
    try {
      saveSession?.call(cfg.email, null);
    } catch (_) {}
  }

  /// Восстановить сеанс без OPTIONS и Provision. true — можно работать.
  bool _restoreSession(AccountConfig cfg) {
    final load = loadSession;
    if (load == null) return false;
    try {
      final raw = load(cfg.email);
      if (raw == null || raw.isEmpty) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['v'] != 1) return false;
      if ((m['server'] ?? '') != (cfg.exchangeServer ?? '')) return false;
      if (m['device'] != _deviceId) return false;
      final at = DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(at) > sessionMaxAge) return false;
      final url = m['url'] as String?;
      final key = m['key'] as String?;
      if (url == null || key == null || key.isEmpty) return false;
      final host = Uri.parse(url).host;
      if (wafPauseMinutesLeft(host) > 0) return false;
      _easUrl = url;
      _resolvedHost = (m['host'] as String?) ?? host;
      _protocolVersion = (m['proto'] as String?) ?? _protocolVersion;
      _useBase64 = m['b64'] == true;
      _protocolVersions = ((m['versions'] as List?) ?? const []).cast<String>();
      _serverCommands = ((m['cmds'] as List?) ?? const []).cast<String>();
      _policyKey = key;
      _fromSession = true;
      log.info(_t, 'Сеанс восстановлен: $host, протокол $_protocolVersion — без OPTIONS и Provision');
      return true;
    } catch (e) {
      log.debug(_t, 'Сохранённый сеанс не прочитан: $e');
      return false;
    }
  }

  @override
  Future<ConnectResult> connect(AccountConfig cfg) async {
    _cfg = cfg;
    if (cfg.authKind == AuthKind.oauth2) await _takeBearer(cfg, force: false);
    var auth = _authHeader(cfg);
    log.info(_t, 'Подключение для ${cfg.email} '
        '(${cfg.authKind == AuthKind.oauth2 ? 'OAuth' : 'логин: ${_authUser(cfg)}'})');

    if (_restoreSession(cfg)) {
      return ConnectResult(
        success: true, transport: MailTransportKind.eas,
        resolvedHost: _resolvedHost, capabilities: capabilities, policy: null,
        log: [log.dump()],
      );
    }

    final urls = <String>[];
    if (cfg.exchangeServer != null && cfg.exchangeServer!.isNotEmpty) {
      final h = cleanServer(cfg.exchangeServer!);
      if (h != cfg.exchangeServer) log.warn(_t, 'Адрес сервера исправлен: «${cfg.exchangeServer}» → «$h»');
      urls.add(h.startsWith('http') ? h : 'https://$h/Microsoft-Server-ActiveSync');
    } else {
      log.info(_t, 'Сервер не задан — Autodiscover по домену email');
      final ad = await Autodiscover.discover(
          email: cfg.email, authHeader: auth, userAgent: cfg.userAgent, httpClient: _http);
      for (final l in ad.log) {
        log.debug(_t, l);
      }
      if (ad.easUrl != null) urls.add(ad.easUrl!);
      // Гибридный режим: Autodiscover отдаёт и адрес EWS. Раньше он
      // отбрасывался — и функции, которых нет в EAS (автоответы, занятость
      // коллег, категории Outlook, серверные правила, отзыв письма), были
      // недоступны для EAS-аккаунтов. Теперь запоминаем и возвращаем наружу.
      if (ad.ewsUrl != null && ad.ewsUrl!.isNotEmpty) {
        _companionEwsUrl = ad.ewsUrl;
        log.info(_t, 'Гибрид: попутно найден EWS ${ad.ewsUrl}');
      }
      final domain = cfg.email.contains('@') ? cfg.email.split('@').last : '';
      if (domain.isNotEmpty) {
        urls.add('https://mail.$domain/Microsoft-Server-ActiveSync');
        urls.add('https://$domain/Microsoft-Server-ActiveSync');
      }
    }
    if (urls.isEmpty) {
      return ConnectResult(success: false, error: 'EAS: сервер не определён', log: [log.dump()]);
    }

    var reauthed = false;
    for (var ui = 0; ui < urls.length; ui++) {
      final u = urls[ui];
      final url = Uri.parse(u);
      final pause = wafPauseMinutesLeft(url.host);
      if (pause > 0) {
        log.warn(_t, '${url.host}: шлюз недавно заблокировал запросы — пауза ещё $pause мин.');
        return ConnectResult(
          success: false,
          error: 'EAS 403: шлюз организации заблокировал запросы к ${url.host}. '
              'Повтор не раньше чем через $pause мин (частые попытки продлевают блокировку).',
          log: [log.dump()],
        );
      }
      log.info(_t, 'OPTIONS пробник → ${url.host}');
      try {
        final sw = Stopwatch()..start();
        final reqHeaders = {'Authorization': auth, 'User-Agent': cfg.userAgent, ...?cfg.extraHeaders};
        log.httpRequest(_t, 'OPTIONS', url, reqHeaders, null);
        final streamed = await _http
            .send(http.Request('OPTIONS', url)..headers.addAll(reqHeaders))
            .timeout(const Duration(seconds: 20));
        final respBody = await streamed.stream.toBytes();
        sw.stop();
        log.httpResponse(_t, streamed.statusCode, streamed.headers, respBody, sw.elapsed);
        final status = streamed.statusCode;
        final headers = streamed.headers;
        // Параметры соединения от сетевого стека iPhone (1.6.17): протокол
        // (h2 / http/1.1), версия TLS, повторное соединение — для сравнения с
        // Почтой iPhone. На Android и в консоли заголовка нет.
        final net = headers['x-ogneliss-net'];
        if (net != null) log.info(_t, 'OPTIONS: соединение $net');

        if (status == 200) {
          _resolvedHost = url.host;
          _easUrl = u;
          _protocolVersions = (headers['ms-asprotocolversions'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
          _serverCommands = (headers['ms-asprotocolcommands'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
          // Выбираем версию: 16.1 если сервер поддерживает, иначе максимум доступной.
          // Plain-query командная строка — как в проверенном рабочем PowerShell на
          // cloudmail-sbt и как у Почты iPhone (журналы Exchange). Base64 —
          // только по явному cfg.easBase64Override (консоль).
          if (_protocolVersions.contains('16.1')) {
            _protocolVersion = '16.1'; _useBase64 = false;
          } else if (_protocolVersions.contains('16.0')) {
            _protocolVersion = '16.0'; _useBase64 = false;
          } else if (_protocolVersions.contains('14.1')) {
            _protocolVersion = '14.1'; _useBase64 = false;
          } else if (_protocolVersions.contains('14.0')) {
            // Exchange 2010 без пакетов обновления (аудит 07.10.2026, E6):
            // раньше оставалась версия по умолчанию 16.1, которой сервер не
            // знает, и все команды получали отказ.
            _protocolVersion = '14.0'; _useBase64 = false;
          } else if (_protocolVersions.isNotEmpty) {
            // Только 12.x и старше (Exchange 2007): Provision и SendMail там
            // устроены иначе, движок их не поддерживает. Ясная ошибка вместо
            // отказов всех команд; у Exchange 2007 есть EWS — вход через него.
            final list = _protocolVersions.join(', ');
            log.error(_t, 'Сервер поддерживает только ActiveSync $list — нужна версия 14.0 или новее');
            return ConnectResult(
              success: false,
              error: 'EAS: сервер поддерживает только ActiveSync $list (Exchange 2007 или старше) — '
                  'подключите ящик как Exchange (EWS)',
              log: [log.dump()],
            );
          }
          if (cfg.easBase64Override != null) {
            _useBase64 = cfg.easBase64Override!;
            log.info(_t, 'Форма командной строки задана явно: '
                '${_useBase64 ? "Base64 (как Почта iPhone)" : "plain-query"}');
          }
          // Все cookie (X-BackEndCookie для балансировки + cookie анти-бот
          // шлюза): без cookie шлюза POST-команды получали 403 (журнал 17.10).
          _absorbCookies(headers['set-cookie']);
          if (_cookieJar.isNotEmpty) {
            log.debug(_t, 'Cookie сервера сохранены (${_cookieJar.keys.join(", ")})');
          }
          log.info(_t, 'OPTIONS OK на ${url.host}. Версии: ${_protocolVersions.join(",")}');
          log.info(_t, 'Выбран протокол $_protocolVersion, Base64 RequestLine=$_useBase64, команд сервера: ${_serverCommands.length}');

          final provOk = await _provision(cfg);
          // 1.6.16: автоматическая вторая попытка другой формой команды
          // (plain-query ↔ Base64) убрана — в 1.6.14 доказано, что шлюз режет
          // обе формы одинаково, а лишний POST только продлевал блокировку
          // адреса. Форму можно задать явно (cfg.easBase64Override, консоль).
          if (!provOk && _lastWasWaf) {
            // OPTIONS прошёл, а POST-команды режет шлюз перед Exchange
            // (ServicePipe/WAF): Sync и SendMail будут получать тот же 403.
            // Раньше ящик всё равно добавлялся и висел пустым («Нет писем»).
            log.error(_t, 'Provision отклонён шлюзом (HTTP 403) — команды EAS не проходят. '
                'Повтор не раньше чем через 15 мин; с этой сети/адреса шлюз, вероятно, '
                'блокирует клиента целиком (проверьте мобильную сеть или VPN).');
            return ConnectResult(
              success: false,
              error: 'EAS 403: шлюз организации (анти-бот) отклоняет команды ActiveSync с этого '
                  'адреса. Попробуйте через 15 минут из другой сети (мобильный интернет, VPN) '
                  'или попросите ИТ добавить адрес/клиента в исключения шлюза.',
              log: [log.dump()],
            );
          }
          if (!provOk && (_lastStatus == 0 || _lastStatus >= 500)) {
            // Временный сбой: подключение — в следующий раз, без работы
            // «вслепую» без ключа политики.
            return ConnectResult(
                success: false, error: 'EAS: сервер временно недоступен (HTTP $_lastStatus)', log: [log.dump()]);
          }
          if (!provOk) {
            log.warn(_t, 'Provisioning не завершён — сервер отклонит Sync/SendMail (449).');
          } else {
            _storeSession(cfg);
          }
          return ConnectResult(
            success: true, transport: MailTransportKind.eas,
            resolvedHost: url.host, capabilities: capabilities, policy: _policy,
            companionEwsUrl: _companionEwsUrl, log: [log.dump()],
          );
        } else if (status == 401 && !reauthed && await _takeBearer(cfg, force: true)) {
          // Токен OAuth истёк между проверкой и запросом — новый и повтор.
          reauthed = true;
          auth = _authHeader(cfg);
          log.info(_t, '401 с токеном OAuth — токен обновлён, повтор');
          ui--;
          continue;
        } else if (status == 401) {
          log.error(_t, '401 Unauthorized — неверный логин/пароль или нужен DOMAIN\\user');
          return ConnectResult(success: false, error: '401 Unauthorized', log: [log.dump()]);
        } else if (status == 403) {
          log.warn(_t, '403 Forbidden — блокировка по User-Agent/политике или нет VPN. Следующий URL.');
        } else {
          log.warn(_t, 'HTTP $status — следующий URL.');
        }
      } catch (e) {
        log.warn(_t, 'Ошибка/таймаут на ${url.host}: $e. Следующий URL.');
      }
    }
    return ConnectResult(success: false, error: 'EAS: ни один URL не ответил 200', log: [log.dump()]);
  }

  // ─────────────────── PROVISIONING ───────────────────

  Future<bool> _provision(AccountConfig cfg) async {
    if (_remoteWipe != null) return false;
    var ok = await _provisionAttempt(cfg);
    if (_remoteWipe != null) return false;
    // Откат: если на 16.x ключ не выдан — пробуем 14.1 (там DeviceInformation не нужен).
    // Но не после блокировки шлюзом: это лишние запросы, ответ будет тот же.
    // И не после временного сбоя (обрыв, таймаут, 5xx шлюза): смена версии
    // протокола для того же устройства сбрасывает на Exchange состояние
    // синхронизации всех папок (FolderSync Status 9, Sync Status 3), сервер
    // выдаёт письмам новые ServerId — и письма в ленте задваивались
    // (журнал 13.10.2026: фоновая проверка получила 502 на Provision 16.1,
    // перешла на 14.1, а приложение затем вернулось на 16.1).
    final transient = _lastStatus == 0 || (_lastStatus >= 500 && _lastStatus != 501);
    if (!ok && transient) {
      log.warn(_t, 'Provision: временный сбой (HTTP $_lastStatus) — версия протокола не меняется.');
    }
    final knows141 = _protocolVersions.isEmpty || _protocolVersions.contains('14.1');
    if (!ok && !transient && !_lastWasWaf && !_noPolicy && _protocolVersion != '14.1' && knows141) {
      log.warn(_t, 'Provision на $_protocolVersion не дал ключ — пробуем 14.1.');
      _protocolVersion = '14.1';
      // Форму командной строки, заданную явно, при откате сохраняем.
      _useBase64 = cfg.easBase64Override ?? false;
      ok = await _provisionAttempt(cfg);
    }
    return ok;
  }

  Future<bool> _provisionAttempt(AccountConfig cfg) async {
    try {
      log.info(_t, 'Provision шаг 1 (proto $_protocolVersion): запрос политик...');
      final r1 = await _easCommand(cfg, 'Provision', _buildProvision(cfg), policyKeyHeader: '0');
      if (r1 == null) { log.error(_t, 'Provision шаг 1: нет валидного ответа'); return false; }

      if (log.verbose) log.wbxml(_t, 'Provision-ответ 1', wbxmlTree(r1.root));
      final wipeDevice = r1.root.findChild('RemoteWipe') != null;
      final wipeAccount = r1.root.findChild('AccountOnlyRemoteWipe') != null;
      if (wipeDevice || wipeAccount) {
        final kind = wipeDevice ? RemoteWipeKind.device : RemoteWipeKind.account;
        log.error(_t, 'Сервер запросил удалённое стирание (${kind.name})');
        // Подтверждаем получение до стирания: после него учётных данных
        // уже не будет. Status 1 — стирание принято к исполнению.
        try {
          await _easCommandOnce(cfg, 'Provision', _buildWipeAck(kind),
              policyKeyHeader: '0', timeout: const Duration(seconds: 30));
        } catch (e) {
          log.warn(_t, 'Подтверждение стирания не отправлено: $e');
        }
        _remoteWipe = kind;
        try {
          saveSession?.call(cfg.email, null);
        } catch (_) {}
        try {
          remoteWipeHandler?.call(cfg.email, kind);
        } catch (e) {
          log.error(_t, 'Обработчик стирания: $e');
        }
        return false;
      }
      // Верхнеуровневый статус Provision.
      final topStatus = r1.root.childText('Status');
      if (topStatus != null && topStatus != '1') {
        log.error(_t, 'Provision: верхнеуровневый Status=$topStatus (ожидался 1) — политика не выдана');
        return false;
      }
      final policy1 = r1.root.findChild('Policies')?.findChild('Policy');
      final tempKey = policy1?.childText('PolicyKey');
      final status = policy1?.childText('Status');
      log.info(_t, 'Provision шаг 1: topStatus=$topStatus, policyStatus=$status, tempPolicyKey=$tempKey');
      // Status 2 — «для этого клиента политики нет» (MS-ASPROV): ключ не
      // нужен, команды идут с PolicyKey 0. Раньше это считалось неудачей:
      // в журнале — ложное «Provisioning не завершён», движок переходил на
      // 14.1 и не сохранял сеанс (аудит 07.10.2026, E8). Бывает у серверов
      // не от Microsoft; у Exchange политика по умолчанию есть всегда.
      if (status == '2' && (tempKey == null || tempKey.isEmpty)) {
        _noPolicy = true;
        _policyKey = '0';
        log.info(_t, 'Provision: политики для устройства на сервере нет (Status 2) — работаем без ключа');
        return true;
      }

      final doc = policy1?.findChild('Data')?.findChild('EASProvisionDoc');
      if (doc != null) {
        _policy = SecurityPolicy(
          devicePasswordEnabled: doc.childText('DevicePasswordEnabled') == '1',
          minPasswordLength: int.tryParse(doc.childText('MinDevicePasswordLength') ?? ''),
          maxInactivitySeconds: int.tryParse(doc.childText('MaxInactivityTimeDeviceLock') ?? ''),
          requireDeviceEncryption: doc.childText('RequireDeviceEncryption') == '1' ||
              doc.childText('DeviceEncryptionEnabled') == '1',
          allowRemoteWipe: true,
          policyKey: tempKey,
          // Лимит вложений от сервера: если задан, приложение не даст
          // прикрепить файл больше — иначе отправка упадёт уже на сервере.
          maxAttachmentSize: int.tryParse(doc.childText('MaxAttachmentSize') ?? ''),
          // Отсутствие элемента = значение Exchange по умолчанию.
          allowSimplePassword: doc.childText('AllowSimpleDevicePassword') != '0',
          alphanumericRequired: doc.childText('AlphanumericDevicePasswordRequired') == '1',
          maxFailedAttempts: int.tryParse(doc.childText('MaxDevicePasswordFailedAttempts') ?? ''),
          passwordExpirationDays: int.tryParse(doc.childText('DevicePasswordExpiration') ?? ''),
          allowCamera: doc.childText('AllowCamera') != '0',
        );
        log.info(_t, 'Политики: пароль=${_policy!.devicePasswordEnabled}, '
            'минДлина=${_policy!.minPasswordLength}, шифрование=${_policy!.requireDeviceEncryption}, '
            'таймаутБлокировки=${_policy!.maxInactivitySeconds}с, '
            'максВложение=${_policy!.maxAttachmentSize ?? "не задан"}, '
            'простойPIN=${_policy!.allowSimplePassword}, буквы=${_policy!.alphanumericRequired}, '
            'попыток=${_policy!.maxFailedAttempts ?? "-"}, срокПароля=${_policy!.passwordExpirationDays ?? "-"}, '
            'камера=${_policy!.allowCamera}');
      } else {
        log.debug(_t, 'EASProvisionDoc отсутствует в ответе (политики не заданы)');
      }

      if (tempKey == null || tempKey.isEmpty) {
        log.error(_t, 'Provision: PolicyKey не получен');
        return false;
      }

      log.info(_t, 'Provision шаг 2: подтверждение принятия политик...');
      final r2 = await _easCommand(cfg, 'Provision', _buildProvision(cfg, policyKey: tempKey, accept: true), policyKeyHeader: tempKey);
      if (r2 == null) { log.error(_t, 'Provision шаг 2: нет ответа'); return false; }
      if (log.verbose) log.wbxml(_t, 'Provision-ответ 2', wbxmlTree(r2.root));
      final status2 = r2.root.findChild('Policies')?.findChild('Policy')?.childText('Status');
      if (status2 != null && status2 != '1') {
        // Подтверждение не принято (например, 5 — не тот ключ): работаем с
        // временным ключом, сервер при необходимости попросит Provision
        // снова (449), — но в журнале это видно (аудит, E8).
        log.warn(_t, 'Provision шаг 2: Status=$status2 (ожидался 1)');
      }
      final finalKey = r2.root.findChild('Policies')?.findChild('Policy')?.childText('PolicyKey');
      _policyKey = (finalKey != null && finalKey.isNotEmpty) ? finalKey : tempKey;
      log.info(_t, 'Provisioning завершён. Финальный PolicyKey=$_policyKey');
      return true;
    } catch (e) {
      log.error(_t, 'Provision исключение: $e');
      return false;
    }
  }

  WbxmlDocument _buildWipeAck(RemoteWipeKind kind) {
    final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
    final w = root.addChild(
        kind == RemoteWipeKind.account ? 'AccountOnlyRemoteWipe' : 'RemoteWipe',
        namespace: 'Provision');
    w.addChild('Status', namespace: 'Provision', text: '1');
    return WbxmlDocument(root: root);
  }

  WbxmlDocument _buildProvision(AccountConfig cfg, {String? policyKey, bool accept = false}) {
    final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
    // Шаг 1 (без policyKey): EAS 16.1 требует DeviceInformation до Policies.
    // В 14.0 этого элемента в Provision ещё нет — сервер отверг бы запрос.
    if (!accept && policyKey == null && _protocolVersion != '14.0') {
      final devInfo = root.addChild('DeviceInformation', namespace: 'Settings');
      final set = devInfo.addChild('Set', namespace: 'Settings');
      set.addChild('Model', namespace: 'Settings', text: cfg.deviceModel);
      set.addChild('FriendlyName', namespace: 'Settings', text: cfg.deviceFriendlyName);
      set.addChild('OS', namespace: 'Settings', text: cfg.deviceOs);
      set.addChild('OSLanguage', namespace: 'Settings', text: cfg.deviceLanguage);
      set.addChild('UserAgent', namespace: 'Settings', text: cfg.userAgent);
    }
    final policies = root.addChild('Policies', namespace: 'Provision');
    final policy = policies.addChild('Policy', namespace: 'Provision');
    policy.addChild('PolicyType', namespace: 'Provision', text: 'MS-EAS-Provisioning-WBXML');
    if (policyKey != null) {
      policy.addChild('PolicyKey', namespace: 'Provision', text: policyKey);
      policy.addChild('Status', namespace: 'Provision', text: '1');
    }
    return WbxmlDocument(root: root);
  }

  // ─────────────────── Cookie jar ───────────────────

  /// Запомнить cookie из ответа (заголовок Set-Cookie). Разбирает несколько
  /// cookie в одной строке с учётом запятых внутри дат (Expires=...; разбиваем
  /// только там, где запятая → перед «имя=»).
  void _absorbCookies(String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return;
    for (final piece in splitSetCookie(setCookie)) {
      final nv = piece.split(';').first.trim();
      final eq = nv.indexOf('=');
      if (eq <= 0) continue;
      final name = nv.substring(0, eq).trim();
      final value = nv.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      // Удаление: сервер гасит cookie пустым значением — убираем из банки.
      if (value.isEmpty) {
        _cookieJar.remove(name);
      } else {
        _cookieJar[name] = value;
      }
    }
  }

  /// Заголовок Cookie из всех накопленных cookie (или null, если их нет).
  String? get _cookieHeader =>
      _cookieJar.isEmpty ? null : _cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Разбить значение Set-Cookie на отдельные cookie. Несколько cookie в одном
  /// заголовке склеены «, », но запятые есть и внутри (Expires=Wed, 09-...).
  /// Делим по запятой, за которой идёт «имя=» (начало следующего cookie).
  static List<String> splitSetCookie(String header) {
    final out = <String>[];
    final re = RegExp(r'[A-Za-z0-9!#\$%&' r"'" r'*+\-.^_`|~]+=');
    var start = 0;
    for (var i = 0; i < header.length; i++) {
      if (header[i] != ',') continue;
      var j = i + 1;
      while (j < header.length && header[j] == ' ') {
        j++;
      }
      final m = re.matchAsPrefix(header, j);
      if (m != null) {
        out.add(header.substring(start, i).trim());
        start = j;
      }
    }
    final last = header.substring(start).trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  // ─────────────────── HTTP/Request-Line ───────────────────

  String _base64CommandLine(String cmd, String ver) => easBase64CommandLine(
        cmd: cmd, ver: ver, deviceId: _deviceId, deviceType: _deviceType, policyKey: _policyKey);

  /// base64url без паддинга — Base64 command line (MS-ASHTTP §2.2.1.1.1.1), как
  /// шлёт штатная Почта iPhone/Outlook (один непрозрачный токен вместо
  /// ?Cmd=..&User=..&DeviceId=..&DeviceType=..):
  /// [Ver*10:1][Cmd:1][Locale:2 LE][DevIdLen:1][DevId][PKLen:1][PK:0|4 LE][DevTypeLen:1][DevType]
  static String easBase64CommandLine({
    required String cmd, required String ver,
    required String deviceId, required String deviceType, String? policyKey}) {
    final bytes = <int>[];
    final v = (double.tryParse(ver) ?? 16.1);
    bytes.add((v * 10).round() & 0xFF);
    bytes.add((easCommandCodes[cmd] ?? 0) & 0xFF);
    bytes.add(0x09); bytes.add(0x04); // Locale en-US LE
    final dev = utf8.encode(deviceId);
    bytes.add(dev.length & 0xFF); bytes.addAll(dev);
    final pk = int.tryParse(policyKey ?? '');
    if (pk != null && pk != 0) {
      bytes.add(4);
      bytes.add(pk & 0xFF); bytes.add((pk >> 8) & 0xFF);
      bytes.add((pk >> 16) & 0xFF); bytes.add((pk >> 24) & 0xFF);
    } else {
      bytes.add(0);
    }
    final dt = utf8.encode(deviceType);
    bytes.add(dt.length & 0xFF); bytes.addAll(dt);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  int _lastStatus = 0;

  /// Последний ответ — страница блокировки шлюза (403 + HTML), а не Exchange.
  bool _lastWasWaf = false;

  /// Та же страница блокировки, но в ответ на большой запрос (тело от
  /// [bigBodyBytes]): похоже на ограничение размера у шлюза, а не на
  /// блокировку адреса — паузу на хост не ставим (1.7.2+114).
  bool _lastWasWafBig = false;

  /// С какого размера тела запроса 403 от шлюза считаем отказом по размеру.
  /// Письмо без вложений (текст, цитата, подпись) обычно меньше.
  static const bigBodyBytes = 256 * 1024;

  static String _size(int n) => n >= 1048576
      ? '${(n / 1048576).toStringAsFixed(1)} МБ'
      : '${(n / 1024).toStringAsFixed(0)} КБ';

  /// Хосты, где шлюз уже заблокировал команды: пауза для ВСЕХ экземпляров
  /// движка. Повторные попытки в эти минуты анти-бот засчитывает как атаку и
  /// продлевает блокировку адреса — по журналам так и было: июньский
  /// проверочный движок проходил, а после десятков повторов 403 стал
  /// получать даже EWS, который раньше доходил до IIS (401).
  static final Map<String, DateTime> _wafPauseUntil = {};
  static const _wafPause = Duration(minutes: 15);

  /// Минут до конца паузы после блокировки шлюзом (0 — паузы нет).
  static int wafPauseMinutesLeft(String host) {
    final until = _wafPauseUntil[host.toLowerCase()];
    if (until == null) return 0;
    final left = until.difference(DateTime.now());
    return left.isNegative ? 0 : left.inMinutes + 1;
  }

  /// Отметить блокировку шлюзом для произвольного ключа (1.6.16): EWS ведёт
  /// свою паузу по ключу «ews:<хост>». Раньше EWS паузу не соблюдал: в журнале
  /// iPhone 17.10.2026 — 71 POST к EWS за полчаса, местами раз в секунду, все
  /// 403. Для анти-бота это атака, адрес оставался в блокировке.
  static void markWafBlocked(String key) =>
      _wafPauseUntil[key.toLowerCase()] = DateTime.now().add(_wafPause);

  /// Адрес сервера из поля ввода (1.6.16): без пробелов внутри и по краям
  /// (автозамена на iPhone вставляла «cloud mail.…» — запросы уходили на
  /// несуществующий хост), без хвостового «/». Хост — в нижнем регистре.
  static String cleanServer(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http')) s = s.toLowerCase();
    return s;
  }
  int get lastStatus => _lastStatus;

  /// Последнюю команду не пропустил шлюз перед Exchange из-за размера
  /// запроса (1.7.2+114): черновик или письмо с большими файлами.
  bool get lastWasGatewaySize => _lastWasWafBig;

  /// Сетевая причина последней неудачи без HTTP-ответа (имя сервера не
  /// найдено, обрыв, нет сети), 1.6.40: раньше пользователь видел только
  /// «нет ответа (HTTP 0)», а «сервер не найден (DNS)» терялось в журнале.
  String? get lastNetError => _lastNetError;
  String? _lastNetError;

  /// Сервер перегружен или ограничивает клиента (503, 500 с Retry-After,
  /// X-MS-ASThrottle): до этого момента команды не отправляются. Раньше
  /// синхронизация повторяла запросы сразу — Exchange продлевал ограничение,
  /// а пользователь видел только «нет писем».
  DateTime? _busyUntil;
  DateTime? get busyUntil =>
      _busyUntil != null && _busyUntil!.isAfter(DateTime.now()) ? _busyUntil : null;

  /// 503 на Ping без X-MS-ASThrottle — это шлюз перед Exchange не держит
  /// долгий запрос, а не перегрузка сервера: пауза только для Ping. Раньше
  /// такой ответ на 2 минуты останавливал ВСЕ команды — синхронизацию,
  /// отправку из очереди, отметки «прочитано» («Sync пропущен: сервер просил
  /// подождать» 42 раза за ночь в журнале).
  DateTime? _pingBusyUntil;
  DateTime? get pingBusyUntil =>
      _pingBusyUntil != null && _pingBusyUntil!.isAfter(DateTime.now()) ? _pingBusyUntil : null;

  /// Пауза из Retry-After в секундах (так отвечает Exchange); без
  /// заголовка или в другом формате — [fallback].
  static Duration? retryAfter(Map<String, String> headers, {Duration? fallback}) {
    final sec = int.tryParse(headers['retry-after']?.trim() ?? '');
    if (sec != null && sec >= 0) return Duration(seconds: sec);
    return fallback;
  }

  // Ограничение темпа после 403 от шлюза (см. _easCommand).
  DateTime? _slowUntil;
  DateTime? _lastRequestAt;
  Future<void> _pace() async {
    final now = DateTime.now();
    final slow = _slowUntil;
    final last = _lastRequestAt;
    if (slow != null && now.isBefore(slow) && last != null) {
      // Слот резервируется ДО ожидания: команды идут параллельно (Sync,
      // докачка вложений, Ping) и иначе дождались бы одного момента вместе.
      final earliest = last.add(const Duration(milliseconds: 1500));
      final slot = earliest.isAfter(now) ? earliest : now;
      _lastRequestAt = slot;
      final wait = slot.difference(now);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      return;
    }
    _lastRequestAt = now;
  }
  bool _lastWasChallenge = false;
  bool get lastWasChallenge => _lastWasChallenge;

  Uri _commandUri(AccountConfig cfg, String cmd, String ver, bool b64) {
    final base = _easUrl ?? 'https://$_resolvedHost/Microsoft-Server-ActiveSync';
    if (b64) {
      return Uri.parse('$base?${_base64CommandLine(cmd, ver)}');
    }
    final user = Uri.encodeComponent(_authUser(cfg));
    if (cfg.appleMailProfile) {
      // Порядок Почты iOS: Cmd последним (журнал ящика Exchange для iPhone:
      // «?User=user@domain&DeviceId=NSQK…&DeviceType=iPhone&Cmd=SendMail»).
      return Uri.parse('$base?User=$user&DeviceId=$_deviceId&DeviceType=$_deviceType&Cmd=$cmd');
    }
    return Uri.parse('$base?Cmd=$cmd&User=$user&DeviceId=$_deviceId&DeviceType=$_deviceType');
  }

  /// Выполнить EAS-команду с подробным логированием. При неуспехе на Base64 16.1
  /// один раз пробуем fallback 14.1 + plain query. Предпочитаемая версия НЕ
  /// деградирует навсегда — сохраняется только та, что дала 200.
  Future<WbxmlDocument?> _easCommand(
    AccountConfig cfg, String cmd, WbxmlDocument body,
    {required String policyKeyHeader, Duration timeout = const Duration(seconds: 30)}) async {
    var r = await _easCommandOnce(cfg, cmd, body, policyKeyHeader: policyKeyHeader, timeout: timeout);
    // Шлюз перед Exchange (nginx + ServicePipe) отвечает 403 на серию частых
    // запросов: по журналу другого клиента — после 5–10 команд подряд с
    // интервалом меньше секунды, причём в эти же секунды блокируется и
    // Provision (политики не получаются, отправка не работает). Поэтому:
    // пауза 5 с, один повтор, а следующую минуту команды идут не чаще
    // раза в 1,5 с (см. _pace). Ping не повторяем — у него свой цикл.
    if (r == null && _lastStatus == 403 && !_lastWasWaf && cmd != 'Ping') {
      log.warn(_t, '$cmd → 403 от шлюза (частые запросы?) — повтор через 5 с, темп снижен на минуту');
      _slowUntil = DateTime.now().add(const Duration(seconds: 60));
      await Future<void>.delayed(const Duration(seconds: 5));
      r = await _easCommandOnce(cfg, cmd, body, policyKeyHeader: policyKeyHeader, timeout: timeout);
    }
    // Политика устройства устарела или сброшена администратором: сервер
    // отвечает HTTP 449 либо Status 142–144 внутри ответа. Раньше движок
    // только писал это в журнал, и до перезапуска приложения все команды
    // аккаунта молча возвращали пусто. Теперь — повторный Provision и один
    // повтор команды с новым PolicyKey.
    if (cmd != 'Provision' && (_lastStatus == 449 || _needsProvision(r))) {
      log.warn(_t, '$cmd: сервер требует повторный Provision — выполняем');
      if (await _provision(cfg)) {
        _storeSession(cfg);
        r = await _easCommandOnce(cfg, cmd, body,
            policyKeyHeader: _policyKey ?? '0', timeout: timeout);
      }
    }
    return r;
  }

  // 140 — администратор запросил удалённое стирание: команда Provision
  // получит RemoteWipe (раньше 140 только писался в журнал).
  static const _provisionStatuses = {'140', '142', '143', '144'};
  bool _needsProvision(WbxmlDocument? r) {
    if (r == null) return false;
    final top = r.root.childText('Status');
    if (top != null && _provisionStatuses.contains(top)) return true;
    final col = r.root.findChild('Collections')?.findChild('Collection');
    final cs = col?.childText('Status');
    return cs != null && _provisionStatuses.contains(cs);
  }

  Future<WbxmlDocument?> _easCommandOnce(
    AccountConfig cfg, String cmd, WbxmlDocument body,
    {required String policyKeyHeader, required Duration timeout}) async {
    final preferredVer = _protocolVersion;
    final preferredB64 = _useBase64;
    _lastWasChallenge = false;
    // Сбрасываем код прошлой команды: при сетевой ошибке (нет связи, DNS,
    // таймаут) он не обновляется, и вызывающий видел бы «200» от
    // предыдущего успешного запроса — Ping без связи крутился бы без пауз.
    _lastStatus = 0;
    _lastNetError = null;
    _lastWasWaf = false;
    _lastWasWafBig = false;
    final attempts = <(String, bool)>[(preferredVer, preferredB64)];
    // Ping без отката на 14.1: иначе оборванный прокси Ping повторяется
    // внутри того же вызова и время ожидания удваивается (см. push-цикл).
    if (preferredB64 && cmd != 'Ping') attempts.add(('14.1', false));

    final busy = busyUntil ?? (cmd == 'Ping' ? pingBusyUntil : null);
    if (busy != null) {
      _lastStatus = 503;
      log.warn(_t, '$cmd пропущен: сервер просил подождать до ${busy.toIso8601String()}');
      return null;
    }
    var redirected = false;
    var bearerRetried = false;
    for (var i = 0; i < attempts.length; i++) {
      final (ver, b64) = attempts[i];
      final url = _commandUri(cfg, cmd, ver, b64);
      final bytes = WbxmlEncoder().encode(body);
      final headers = cfg.appleMailProfile
          // Профиль «Почта iPhone» (1.6.17): только заголовки ActiveSync.
          // Accept, Accept-Language (язык системы) и Accept-Encoding добавит
          // NSURLSession сам — как у системного клиента. Раньше уходил
          // Accept-Language «en-US,en;q=0.9» и на русском iPhone.
          ? <String, String>{
              'Content-Type': 'application/vnd.ms-sync.wbxml',
              'Authorization': _authHeader(cfg),
              'User-Agent': cfg.userAgent,
              'MS-ASProtocolVersion': ver,
              'X-MS-PolicyKey': policyKeyHeader,
              if (_cookieHeader != null) 'Cookie': _cookieHeader!,
              ...?cfg.extraHeaders,
            }
          : <String, String>{
              'Authorization': _authHeader(cfg),
              'Content-Type': 'application/vnd.ms-sync.wbxml',
              'Accept': '*/*',
              'Accept-Language': 'en-US,en;q=0.9',
              'Accept-Encoding': 'gzip, deflate',
              'MS-ASProtocolVersion': ver,
              'X-MS-PolicyKey': policyKeyHeader,
              'User-Agent': cfg.userAgent,
              if (_cookieHeader != null) 'Cookie': _cookieHeader!,
              ...?cfg.extraHeaders,
            };
      // Размер тела — для больших запросов (письмо с вложениями): по нему
      // видно, что именно не пропустил шлюз.
      log.info(_t, '$cmd (proto $ver, Base64=$b64${bytes.length >= 64 * 1024 ? ', тело ${_size(bytes.length)}' : ''})');
      log.httpRequest(_t, 'POST', url, headers, bytes);
      try {
        await _pace();
        final sw = Stopwatch()..start();
        final resp = await _http.post(url, headers: headers, body: bytes).timeout(timeout);
        sw.stop();
        _lastStatus = resp.statusCode;
        _lastNetError = null;
        log.httpResponse(_t, resp.statusCode, resp.headers, resp.bodyBytes, sw.elapsed);
        final net = resp.headers['x-ogneliss-net'];
        if (net != null && (resp.statusCode != 200 || cmd == 'Provision')) {
          log.info(_t, '$cmd: соединение $net');
        }
        // Exchange Online: токен истёк за время работы движка (живёт час) —
        // берём новый и повторяем ту же команду (один раз).
        if (resp.statusCode == 401 && !bearerRetried && await _takeBearer(cfg, force: true)) {
          bearerRetried = true;
          log.info(_t, '$cmd → 401: токен OAuth обновлён, повтор');
          i--;
          continue;
        }
        if (_fromSession) {
          // Первый ответ после восстановленного сеанса: 200 — сеанс годен;
          // 401/403/404/451 — пароль сменили, доступ закрыли или адрес
          // устарел: сохранённый сеанс больше не используем.
          if (resp.statusCode == 200 || resp.statusCode == 449) {
            _fromSession = false;
          } else if (const {401, 403, 404, 451}.contains(resp.statusCode)) {
            _dropSession(cfg, 'HTTP ${resp.statusCode}');
          }
        }
        // Обновляем cookie (X-BackEndCookie меняется при переключении узла;
        // анти-бот шлюз может обновить свой): храним все.
        _absorbCookies(resp.headers['set-cookie']);

        final ct = (resp.headers['content-type'] ?? '').toLowerCase();
        final body = resp.bodyBytes;
        final looksWbxml = body.isNotEmpty && body[0] == 0x03;
        final looksHtml = ct.contains('text/html') || (body.isNotEmpty && body[0] == 0x3c);

        // Анти-бот ServicePipe отдаёт 200 + HTML с JS-челленджем вместо данных.
        if (resp.statusCode == 200 && looksHtml && !looksWbxml) {
          _lastWasChallenge = true;
          log.error(_t, '$cmd → 200, но тело = HTML JS-челлендж анти-бота (ServicePipe, X-SP-CRID). '
              'Это НЕ ответ Exchange. Скриптовый клиент не может выполнить JS-проверку из этой сети. '
              'Нужен корпоративный VPN/сеть или allowlist у IT.');
          return null; // не пытаемся 14.1 — будет тот же челлендж
        }
        if (resp.statusCode == 200 && looksWbxml) {
          _lastWasChallenge = false;
          _protocolVersion = ver; _useBase64 = b64; // сохраняем рабочую версию
          try {
            return await decodeWbxmlAsync(Uint8List.fromList(body));
          } catch (e) {
            log.error(_t, '$cmd: ошибка декодирования WBXML: $e');
            return null;
          }
        }
        if (resp.statusCode == 200 && body.isEmpty) {
          _lastWasChallenge = false;
          _protocolVersion = ver; _useBase64 = b64;
          log.info(_t, '$cmd → 200 с пустым телом');
          return null; // пустой 200 (например, успешный SendMail)
        }
        if (resp.statusCode == 403 && looksHtml && bytes.length >= bigBodyBytes) {
          // Большой запрос (письмо с вложениями): мелкие команды в это же
          // время проходят — это не блокировка адреса, паузу не ставим.
          _lastWasWaf = true;
          _lastWasWafBig = true;
          final text = utf8.decode(body, allowMalformed: true)
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          log.error(_t, '$cmd → 403 от шлюза перед Exchange на запрос ${_size(bytes.length)}: похоже на '
              'ограничение размера запроса у шлюза (ответ не от Exchange). Страница шлюза: '
              '${text.length > 300 ? text.substring(0, 300) : text}');
          _protocolVersion = preferredVer; _useBase64 = preferredB64;
          return null;
        }
        if (resp.statusCode == 403 && looksHtml) {
          _lastWasWaf = true;
          _wafPauseUntil[url.host.toLowerCase()] = DateTime.now().add(_wafPause);
          // Текст страницы блокировки целиком: в ней дата, адрес и номер
          // запроса — по ним ИТ найдёт причину в журнале шлюза.
          final text = utf8.decode(body, allowMalformed: true)
              .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          log.error(_t, '$cmd → 403 от шлюза перед Exchange (ответ не от Exchange). '
              'UA «${cfg.userAgent}». Страница шлюза: ${text.length > 600 ? text.substring(0, 600) : text}');
          log.warn(_t, 'Запросы к ${url.host} приостановлены на ${_wafPause.inMinutes} мин, '
              'чтобы не продлевать блокировку повторами.');
          _protocolVersion = preferredVer; _useBase64 = preferredB64;
          return null; // без отката на 14.1: шлюз ответит так же
        } else if (resp.statusCode == 403) {
          log.warn(_t, '$cmd → 403 (Exchange): доступ запрещён.');
        } else if (resp.statusCode == 449) {
          log.warn(_t, '$cmd → 449: требуется Provisioning (нет/просрочен PolicyKey)');
        } else if (resp.statusCode == 451 && !redirected) {
          // Ящик переехал на другой сервер (MS-ASHTTP 451): новый адрес в
          // X-MS-Location — запоминаем и повторяем команду там.
          final loc = resp.headers['x-ms-location']?.trim() ?? '';
          final to = Uri.tryParse(loc);
          if (to != null && to.scheme == 'https' && to.host.isNotEmpty) {
            _easUrl = to.replace(query: '').toString().replaceAll(RegExp(r'\?$'), '');
            _resolvedHost = to.host;
            redirected = true;
            log.warn(_t, '$cmd → 451: ящик на другом сервере, новый адрес ${to.host}');
            i--; // та же версия протокола — на новом адресе
            continue;
          }
          log.warn(_t, '$cmd → 451 без X-MS-Location');
        } else if (resp.statusCode == 503 ||
            (resp.statusCode == 500 && resp.headers['retry-after'] != null)) {
          final throttled = resp.headers.containsKey('x-ms-asthrottle');
          var wait = retryAfter(resp.headers,
                  fallback: Duration(minutes: throttled ? 5 : 2))!;
          if (wait > const Duration(minutes: 30)) wait = const Duration(minutes: 30);
          if (cmd == 'Ping' && !throttled) {
            if (wait > const Duration(minutes: 2)) wait = const Duration(minutes: 2);
            _pingBusyUntil = DateTime.now().add(wait);
          } else {
            _busyUntil = DateTime.now().add(wait);
          }
          log.warn(_t, '$cmd → ${resp.statusCode}${throttled ? ' (ограничение ActiveSync: ${resp.headers['x-ms-asthrottle']})' : ''}: '
              'сервер занят, повтор не раньше чем через ${wait.inSeconds} с');
          _protocolVersion = preferredVer; _useBase64 = preferredB64;
          return null; // откат на 14.1 бессмыслен — сервер просил подождать
        }
        log.warn(_t, '$cmd → HTTP ${resp.statusCode} на proto $ver.${b64 ? " Пробуем 14.1." : ""}');
      } catch (e) {
        _lastNetError = '$e';
        // Ping свёрнутого приложения iOS: система замораживает запрос, и он
        // падает по тайм-ауту или с «соединение потеряно» при пробуждении —
        // это ожидаемо, не предупреждение (журнал iPhone 20.10.2026).
        if (cmd == 'Ping' && (quietPingErrors?.call() ?? false)) {
          log.debug(_t, '$cmd прерван (приложение свёрнуто): $e');
        } else {
          log.warn(_t, '$cmd ошибка на proto $ver: $e.${b64 ? " Пробуем 14.1." : ""}');
        }
        // Адрес из сохранённого сеанса не отвечает — в следующий раз
        // подключение полное (с перебором адресов и Autodiscover).
        if (_fromSession && cmd != 'Ping') _dropSession(cfg, '$e');
      }
    }
    // Возвращаем предпочитаемую версию (не деградируем).
    _protocolVersion = preferredVer; _useBase64 = preferredB64;
    return null;
  }

  // ─────────────────── FolderSync / Sync / SendMail ───────────────────

  final Map<String, String> _syncKeys = {}; // collectionId → syncKey
  final Map<String, String> _pimSyncKeys = {}; // PIM collectionId → syncKey
  bool _lastPimMoreAvailable = false;
  /// Сервер сообщил, что у последнего syncPim есть продолжение (MoreAvailable).
  bool get lastPimMoreAvailable => _lastPimMoreAvailable;
  final List<MailFolder> _folders = [];
  String _folderSyncKey = '0';

  static const _easFolderTypeToTok = {
    1: MailFolderType.user, // user-created (generic)
    2: MailFolderType.inbox, 3: MailFolderType.drafts, 4: MailFolderType.trash,
    5: MailFolderType.sent, 6: MailFolderType.outbox, 12: MailFolderType.user,
    18: MailFolderType.user,
    // PIM
    7: MailFolderType.tasks, 8: MailFolderType.calendar, 9: MailFolderType.contacts,
    10: MailFolderType.notes, 11: MailFolderType.journal,
    13: MailFolderType.calendar, 14: MailFolderType.contacts,
    15: MailFolderType.tasks, 16: MailFolderType.journal, 17: MailFolderType.notes,
  };

  @override
  Future<List<MailFolder>> listFolders() => _listFolders(allowReset: true);

  /// Иерархия папок и её SyncKey — для сохранения между запусками. Раньше
  /// каждый запуск начинался с FolderSync «0» (полный список заново).
  String exportFolderState() => jsonEncode({
        'key': _folderSyncKey,
        'folders': [
          for (final f in _folders)
            {'id': f.id, 'name': f.displayName, 'type': f.type.name, 'parent': f.parentId},
        ],
      });

  /// Восстановить сохранённую иерархию (до первого FolderSync).
  void importFolderState(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final key = m['key'] as String? ?? '0';
      final list = (m['folders'] as List? ?? const [])
          .whereType<Map>()
          .map((f) => MailFolder(
                id: f['id'] as String,
                displayName: (f['name'] as String?) ?? '',
                type: MailFolderType.values.firstWhere((t) => t.name == f['type'],
                    orElse: () => MailFolderType.user),
                parentId: f['parent'] as String?,
              ))
          .toList();
      if (key == '0' || list.isEmpty || _folderSyncKey != '0') return;
      _folderSyncKey = key;
      _folders
        ..clear()
        ..addAll(list);
    } catch (_) {}
  }

  /// Забыть SyncKey PIM-папки: следующий syncPim перечитает её целиком.
  void resetPimSyncKey(String folderId) => _pimSyncKeys.remove(folderId);

  /// Время последнего успешного FolderSync. Иерархия папок меняется редко,
  /// а за один проход синхронизации список запрашивали 4 раза (почта,
  /// календарь, контакты, задачи) — повтор в пределах минуты не нужен.
  DateTime? _foldersAt;

  Future<List<MailFolder>> _listFolders({required bool allowReset}) async {
    final cfg = _cfg!;
    final fullSync = _folderSyncKey == '0';
    if (!fullSync && _folders.isNotEmpty && _foldersAt != null &&
        DateTime.now().difference(_foldersAt!) < const Duration(seconds: 60)) {
      return _folders;
    }
    final root = WbxmlElement(name: 'FolderSync', namespace: 'FolderHierarchy');
    root.addChild('SyncKey', namespace: 'FolderHierarchy', text: _folderSyncKey);
    final resp = await _easCommand(cfg, 'FolderSync', WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'FolderSync: нет ответа');
      return _folders;
    }
    if (log.verbose) log.wbxml(_t, 'FolderSync-ответ', wbxmlTree(resp.root));
    final status = resp.root.childText('Status');
    // Status 9 — ключ иерархии отклонён: запрашиваем список папок заново.
    if (status == '9' && allowReset) {
      log.warn(_t, 'FolderSync: SyncKey отклонён (Status 9) — полный запрос');
      _folderSyncKey = '0';
      return _listFolders(allowReset: false);
    }
    // Полный список (ключ 0) приходит целиком — старый кэш нужно заменить,
    // иначе при повторной инициализации папки задваивались.
    if (fullSync) _folders.clear();
    _folderSyncKey = resp.root.childText('SyncKey') ?? _folderSyncKey;
    final changes = resp.root.findChild('Changes');
    if (changes != null) {
      for (final add in [...changes.findChildren('Add'), ...changes.findChildren('Update')]) {
        final serverId = add.childText('ServerId');
        final name = add.childText('DisplayName') ?? '';
        final typeStr = add.childText('Type');
        final typeNum = int.tryParse(typeStr ?? '') ?? -1;
        if (typeNum == 19) continue; // RecipientInfo — служебная, пропускаем
        final type = _easFolderTypeToTok[typeNum] ?? MailFolderType.user;
        if (serverId != null) {
          // Update (переименование/перенос) заменяет запись, Add добавляет.
          _folders.removeWhere((f) => f.id == serverId);
          _folders.add(MailFolder(id: serverId, displayName: name, type: type,
              parentId: add.childText('ParentId')));
        }
      }
      for (final del in changes.findChildren('Delete')) {
        final serverId = del.childText('ServerId');
        if (serverId != null) _folders.removeWhere((f) => f.id == serverId);
      }
    }
    log.info(_t, 'FolderSync: папок ${_folders.length}, syncKey=$_folderSyncKey');
    _foldersAt = DateTime.now();
    return _folders;
  }

  // ──────────────── Управление папками на сервере (MS-ASCMD) ────────────────
  // Используются ТОЛЬКО теги code page 7 (FolderHierarchy), уже описанные в
  // wbxml_codec: SyncKey/ParentId/DisplayName/Type/ServerId/Status/FolderCreate/
  // FolderUpdate/FolderDelete. Ничего не реконструируется по памяти.
  //
  // ВАЖНО: после любой из операций сервер выдаёт новый folder SyncKey — он
  // сохраняется, иначе последующий FolderSync вернёт ошибку рассинхрона.
  // ⚠ Требует проверки на реальном EAS-аккаунте (я не мог выполнить запрос).

  /// Тип папки для FolderCreate: 12 = user-created mail folder (MS-ASCMD).
  static const int easUserMailFolderType = 12;

  /// Создать папку на сервере. Возвращает ServerId созданной папки или null.
  Future<String?> createFolderRemote(String displayName,
      {String parentId = '0', int type = easUserMailFolderType}) async {
    final cfg = _cfg;
    if (cfg == null) return null;
    final root = WbxmlElement(name: 'FolderCreate', namespace: 'FolderHierarchy');
    root.addChild('SyncKey', namespace: 'FolderHierarchy', text: _folderSyncKey);
    root.addChild('ParentId', namespace: 'FolderHierarchy', text: parentId);
    root.addChild('DisplayName', namespace: 'FolderHierarchy', text: displayName);
    root.addChild('Type', namespace: 'FolderHierarchy', text: '$type');
    final resp = await _easCommand(cfg, 'FolderCreate', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'FolderCreate: нет ответа');
      return null;
    }
    final status = resp.root.childText('Status');
    _folderSyncKey = resp.root.childText('SyncKey') ?? _folderSyncKey;
    if (status != '1') {
      log.error(_t, 'FolderCreate: Status=$status');
      return null;
    }
    final serverId = resp.root.childText('ServerId');
    if (serverId != null) {
      _folders.add(MailFolder(
          id: serverId, displayName: displayName,
          type: _easFolderTypeToTok[type] ?? MailFolderType.user,
          parentId: parentId));
    }
    log.info(_t, 'FolderCreate: "$displayName" → $serverId, syncKey=$_folderSyncKey');
    return serverId;
  }

  /// Переименовать/переместить папку. true — успех.
  Future<bool> updateFolderRemote(String serverId, String displayName,
      {String parentId = '0'}) async {
    final cfg = _cfg;
    if (cfg == null) return false;
    final root = WbxmlElement(name: 'FolderUpdate', namespace: 'FolderHierarchy');
    root.addChild('SyncKey', namespace: 'FolderHierarchy', text: _folderSyncKey);
    root.addChild('ServerId', namespace: 'FolderHierarchy', text: serverId);
    root.addChild('ParentId', namespace: 'FolderHierarchy', text: parentId);
    root.addChild('DisplayName', namespace: 'FolderHierarchy', text: displayName);
    final resp = await _easCommand(cfg, 'FolderUpdate', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'FolderUpdate: нет ответа');
      return false;
    }
    final status = resp.root.childText('Status');
    _folderSyncKey = resp.root.childText('SyncKey') ?? _folderSyncKey;
    if (status != '1') {
      log.error(_t, 'FolderUpdate: Status=$status');
      return false;
    }
    final i = _folders.indexWhere((f) => f.id == serverId);
    if (i >= 0) {
      _folders[i] = MailFolder(
          id: serverId, displayName: displayName,
          type: _folders[i].type, parentId: parentId);
    }
    log.info(_t, 'FolderUpdate: $serverId → "$displayName", syncKey=$_folderSyncKey');
    return true;
  }

  /// Список папок на сервере изменился (Sync ответил Status 12 или 8) —
  /// приложению нужно перечитать иерархию. Флаг сбрасывается при чтении.
  bool _hierarchyChanged = false;
  bool takeHierarchyChanged() {
    final v = _hierarchyChanged;
    _hierarchyChanged = false;
    return v;
  }

  /// Удалить папку на сервере. true — успех (в том числе если её там уже
  /// нет: Status 4 — удалили в Outlook раньше, 1.6.12).
  Future<bool> deleteFolderRemote(String serverId) async {
    final cfg = _cfg;
    if (cfg == null) return false;
    final root = WbxmlElement(name: 'FolderDelete', namespace: 'FolderHierarchy');
    root.addChild('SyncKey', namespace: 'FolderHierarchy', text: _folderSyncKey);
    root.addChild('ServerId', namespace: 'FolderHierarchy', text: serverId);
    final resp = await _easCommand(cfg, 'FolderDelete', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'FolderDelete: нет ответа');
      return false;
    }
    final status = resp.root.childText('Status');
    _folderSyncKey = resp.root.childText('SyncKey') ?? _folderSyncKey;
    if (status == '4') {
      log.warn(_t, 'FolderDelete: папки $serverId на сервере уже нет (Status 4) — убираем у себя');
      _folders.removeWhere((f) => f.id == serverId);
      _foldersAt = null;
      return true;
    }
    if (status != '1') {
      log.error(_t, 'FolderDelete: Status=$status');
      return false;
    }
    _folders.removeWhere((f) => f.id == serverId);
    log.info(_t, 'FolderDelete: $serverId удалена, syncKey=$_folderSyncKey');
    return true;
  }

  // ──────────── GAL: разрешение получателей (ResolveRecipients, cp10) ────────────
  // Теги code page 10 (ResolveRecipients) сверены с [MS-ASWBXML] 2.1.2.1.11.
  // ⚠ Требует прогона на реальном EAS-аккаунте.

  /// Поиск в глобальной адресной книге по строке (имя/адрес).
  /// Возвращает пары (отображаемое имя, email).
  Future<List<({String displayName, String email})>> resolveRecipients(
      String query, {int maxResults = 20}) async {
    final cfg = _cfg;
    if (cfg == null || query.trim().isEmpty) return const [];
    final root = WbxmlElement(name: 'ResolveRecipients', namespace: 'ResolveRecipients');
    root.addChild('To', namespace: 'ResolveRecipients', text: query);
    final opts = root.addChild('Options', namespace: 'ResolveRecipients');
    opts.addChild('MaxAmbiguousRecipients', namespace: 'ResolveRecipients', text: '$maxResults');

    final resp = await _easCommand(cfg, 'ResolveRecipients',
        WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'ResolveRecipients: нет ответа');
      return const [];
    }
    final out = <({String displayName, String email})>[];
    for (final response in resp.root.findChildren('Response')) {
      for (final rec in response.findChildren('Recipient')) {
        final name = rec.childText('DisplayName') ?? '';
        final email = rec.childText('EmailAddress') ?? '';
        if (email.isNotEmpty) out.add((displayName: name, email: email));
      }
    }
    log.info(_t, 'ResolveRecipients: "$query" → ${out.length}');
    return out;
  }

  /// Поиск в адресной книге организации (GAL) по началу имени/фамилии/адреса
  /// — команда Search, Store=GAL. В отличие от ResolveRecipients находит и
  /// по части строки, и возвращает должность, отдел, телефоны.
  Future<List<EasGalEntry>> searchGal(String query, {int maxResults = 30, bool withPictures = false}) async {
    final cfg = _cfg;
    if (cfg == null || query.trim().length < 2) return const [];
    final root = WbxmlElement(name: 'Search', namespace: 'Search');
    final store = root.addChild('Store', namespace: 'Search');
    store.addChild('Name', namespace: 'Search', text: 'GAL');
    store.addChild('Query', namespace: 'Search', text: query.trim());
    final opts = store.addChild('Options', namespace: 'Search');
    opts.addChild('Range', namespace: 'Search', text: '0-${maxResults - 1}');
    // Фото сотрудников (AS 14.1+): до 100 КБ, не больше 10 штук на запрос.
    if (withPictures && (double.tryParse(_protocolVersion) ?? 0) >= 14.1) {
      final pic = opts.addChild('Picture', namespace: 'Search');
      pic.addChild('MaxSize', namespace: 'Search', text: '102400');
      pic.addChild('MaxPictures', namespace: 'Search', text: '${maxResults.clamp(1, 10)}');
    }
    final resp = await _easCommand(cfg, 'Search', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) return const [];
    final st = resp.root.findChild('Response')?.findChild('Store') ??
        resp.root.findChild('Store');
    final out = <EasGalEntry>[];
    for (final r in st?.findChildren('Result') ?? const <WbxmlElement>[]) {
      final p = r.findChild('Properties');
      final email = p?.childText('EmailAddress');
      if (p == null || email == null || email.isEmpty) continue;
      out.add(EasGalEntry(
        email: email,
        displayName: p.childText('DisplayName') ?? email,
        firstName: p.childText('FirstName'),
        lastName: p.childText('LastName'),
        title: p.childText('Title'),
        company: p.childText('Company'),
        office: p.childText('Office'),
        phone: p.childText('Phone'),
        mobilePhone: p.childText('MobilePhone'),
        // gal:Picture → Status 1 и Data (JPEG в base64).
        picture: _galPicture(p.findChild('Picture')),
      ));
    }
    log.info(_t, 'GAL: "$query" → ${out.length}');
    return out;
  }

  static String? _galPicture(WbxmlElement? pic) {
    if (pic == null || pic.childText('Status') != '1') return null;
    final data = pic.findChild('Data');
    if (data == null) return null;
    final t = data.text?.trim();
    if (t != null && t.isNotEmpty) return t;
    final bytes = data.opaqueData;
    return (bytes == null || bytes.isEmpty) ? null : base64.encode(bytes);
  }

  /// Занятость сотрудников (ResolveRecipients + Availability, AS 14+).
  /// Возвращает email → строка MergedFreeBusy: по символу на каждые 30 минут
  /// интервала (0 свободен, 1 под вопросом, 2 занят, 3 нет на месте,
  /// 4 работает в другом месте, ? — нет данных).
  Future<Map<String, String>> freeBusy(List<String> emails,
      {required DateTime startUtc, required DateTime endUtc}) async {
    final cfg = _cfg;
    if (cfg == null || emails.isEmpty) return const {};
    String fmt(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}.000Z';
    final root = WbxmlElement(name: 'ResolveRecipients', namespace: 'ResolveRecipients');
    for (final e in emails) {
      root.addChild('To', namespace: 'ResolveRecipients', text: e);
    }
    final opts = root.addChild('Options', namespace: 'ResolveRecipients');
    final av = opts.addChild('Availability', namespace: 'ResolveRecipients');
    av.addChild('StartTime', namespace: 'ResolveRecipients', text: fmt(startUtc));
    av.addChild('EndTime', namespace: 'ResolveRecipients', text: fmt(endUtc));
    final resp = await _easCommand(cfg, 'ResolveRecipients', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) return const {};
    final out = <String, String>{};
    for (final response in resp.root.findChildren('Response')) {
      final to = response.childText('To') ?? '';
      for (final rec in response.findChildren('Recipient')) {
        final fb = rec.findChild('Availability')?.childText('MergedFreeBusy');
        final email = (rec.childText('EmailAddress') ?? to).toLowerCase();
        if (fb != null && email.isNotEmpty) out[email] = fb;
      }
    }
    log.info(_t, 'Занятость: ${out.length} из ${emails.length}');
    return out;
  }

  // ──────────── Автоответ «Нет на месте» (Settings → Oof, cp18) ────────────

  /// Текущий автоответ. null — сервер не ответил или не поддерживает.
  Future<EasOof?> getOof() async {
    final cfg = _cfg;
    if (cfg == null) return null;
    final root = WbxmlElement(name: 'Settings', namespace: 'Settings');
    root
        .addChild('Oof', namespace: 'Settings')
        .addChild('Get', namespace: 'Settings')
        .addChild('BodyType', namespace: 'Settings', text: 'Text');
    final resp = await _easCommand(cfg, 'Settings', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    final oof = resp?.root.findChild('Oof');
    final get = oof?.findChild('Get');
    if (get == null) {
      log.warn(_t, 'Oof Get: нет данных (Status ${oof?.childText('Status') ?? resp?.root.childText('Status')})');
      return null;
    }
    String? internal;
    String? external;
    var externalOn = false;
    for (final m in get.findChildren('OofMessage')) {
      final enabled = m.childText('Enabled') == '1';
      final text = m.childText('ReplyMessage');
      if (m.findChild('AppliesToInternal') != null) {
        internal = text;
      } else if (m.findChild('AppliesToExternalKnown') != null ||
          m.findChild('AppliesToExternalUnknown') != null) {
        external ??= text;
        externalOn = externalOn || enabled;
      }
    }
    return EasOof(
      state: int.tryParse(get.childText('OofState') ?? '') ?? 0,
      start: DateTime.tryParse(get.childText('StartTime') ?? ''),
      end: DateTime.tryParse(get.childText('EndTime') ?? ''),
      internalReply: internal,
      externalReply: external,
      externalEnabled: externalOn,
    );
  }

  /// Кто владелец ящика на самом деле (Settings → UserInformation): основной
  /// SMTP-адрес, все адреса ящика и отображаемое имя. Вход часто идёт под
  /// другим адресом или логином («i.petrov@acmegrp.example», а ящик —
  /// «i.petrov@acmegroup.example»), и без этого свои письма выглядели чужими.
  /// null — сервер не ответил.
  Future<EasUserInfo?> getUserInformation() async {
    final cfg = _cfg;
    if (cfg == null) return null;
    final root = WbxmlElement(name: 'Settings', namespace: 'Settings');
    root.addChild('UserInformation', namespace: 'Settings').addChild('Get', namespace: 'Settings');
    final resp = await _easCommand(cfg, 'Settings', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    final get = resp?.root.findChild('UserInformation')?.findChild('Get');
    if (get == null) {
      log.warn(_t, 'UserInformation: нет данных');
      return null;
    }
    final addresses = <String>[];
    String? primary;
    String? name;
    void collect(WbxmlElement? emails) {
      if (emails == null) return;
      for (final c in emails.children) {
        final v = c.text?.trim().toLowerCase();
        if (v == null || !v.contains('@')) continue;
        if (c.name == 'PrimarySmtpAddress') primary ??= v;
        if (!addresses.contains(v)) addresses.add(v);
      }
    }
    // 14.1+: Accounts/Account/{UserDisplayName, EmailAddresses}; 12–14.0 —
    // сразу EmailAddresses.
    final accounts = get.findChild('Accounts');
    if (accounts != null) {
      for (final acc in accounts.findChildren('Account')) {
        name ??= acc.childText('UserDisplayName')?.trim();
        collect(acc.findChild('EmailAddresses'));
      }
    }
    collect(get.findChild('EmailAddresses'));
    log.info(_t, 'UserInformation: адресов ${addresses.length}${name != null ? ', имя есть' : ''}');
    return EasUserInfo(displayName: (name ?? '').isEmpty ? null : name, primary: primary, addresses: addresses);
  }

  /// Включить/выключить автоответ. [state]: 0 выкл., 1 вкл., 2 по расписанию.
  Future<bool> setOof(EasOof oof) async {
    final cfg = _cfg;
    if (cfg == null) return false;
    String fmt(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}.000Z';
    final root = WbxmlElement(name: 'Settings', namespace: 'Settings');
    final set = root.addChild('Oof', namespace: 'Settings').addChild('Set', namespace: 'Settings');
    set.addChild('OofState', namespace: 'Settings', text: '${oof.state}');
    if (oof.state == 2 && oof.start != null && oof.end != null) {
      set.addChild('StartTime', namespace: 'Settings', text: fmt(oof.start!));
      set.addChild('EndTime', namespace: 'Settings', text: fmt(oof.end!));
    }
    void msg(String appliesTo, bool enabled, String? text) {
      final m = set.addChild('OofMessage', namespace: 'Settings');
      m.addChild(appliesTo, namespace: 'Settings');
      m.addChild('Enabled', namespace: 'Settings', text: enabled ? '1' : '0');
      if (enabled) {
        m.addChild('ReplyMessage', namespace: 'Settings', text: text ?? '');
        m.addChild('BodyType', namespace: 'Settings', text: 'Text');
      }
    }
    final on = oof.state != 0;
    msg('AppliesToInternal', on, oof.internalReply);
    final ext = on && oof.externalEnabled;
    msg('AppliesToExternalKnown', ext, oof.externalReply ?? oof.internalReply);
    msg('AppliesToExternalUnknown', ext, oof.externalReply ?? oof.internalReply);
    final resp = await _easCommand(cfg, 'Settings', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    final st = resp?.root.findChild('Oof')?.childText('Status') ?? resp?.root.childText('Status');
    final ok = resp != null && (st == null || st == '1');
    log.info(_t, 'Oof Set: ${ok ? 'успех' : 'Status $st'}');
    return ok;
  }

  // ──────────── Категории письма (Sync Change, Email:Categories) ────────────

  /// Заменить категории письма на сервере (видны в Outlook и OWA).
  Future<void> setEmailCategories(MessageRef ref, List<String> categories) async {
    final cfg = _cfg!;
    final serverId = ref.serverId ?? ref.id;
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: _syncKeys[ref.folderId] ?? '0');
    collection.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    final change = collection
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Change', namespace: 'AirSync');
    change.addChild('ServerId', namespace: 'AirSync', text: serverId);
    final cats = change
        .addChild('ApplicationData', namespace: 'AirSync')
        .addChild('Categories', namespace: 'Email');
    for (final c in categories) {
      cats.addChild('Category', namespace: 'Email', text: c);
    }
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    // Status 8 у элемента — письмо уже удалено на сервере: менять нечего.
    _checkSyncCommand(resp, 'Change', serverId, ref.folderId, okItemStatuses: const {'1', '8'});
  }

  // ──────────── Серверный поиск почты (Search, cp15) ────────────
  // Теги code page 15 (Search) сверены с [MS-ASWBXML] 2.1.2.1.16.
  // Class берётся из AirSync (cp0). ⚠ Требует прогона на EAS-аккаунте.

  /// Серверный поиск писем по свободному тексту во всём ящике.
  /// Возвращает найденные письма (ServerId + основные поля из Properties).
  Future<List<EasSearchHit>> searchMailbox(String query, {int limit = 25}) async {
    final cfg = _cfg;
    if (cfg == null || query.trim().isEmpty) return const [];
    final root = WbxmlElement(name: 'Search', namespace: 'Search');
    final store = root.addChild('Store', namespace: 'Search');
    store.addChild('Name', namespace: 'Search', text: 'Mailbox');
    final q = store.addChild('Query', namespace: 'Search');
    final and = q.addChild('And', namespace: 'Search');
    and.addChild('Class', namespace: 'AirSync', text: 'Email');
    and.addChild('FreeText', namespace: 'Search', text: query);
    final opts = store.addChild('Options', namespace: 'Search');
    opts.addChild('Range', namespace: 'Search', text: '0-${limit - 1}');
    opts.addChild('DeepTraversal', namespace: 'Search');
    opts.addChild('RebuildResults', namespace: 'Search');

    final resp = await _easCommand(cfg, 'Search',
        WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      log.error(_t, 'Search: нет ответа');
      return const [];
    }
    final status = resp.root.childText('Status');
    if (status != null && status != '1') {
      log.warn(_t, 'Search: Status=$status');
    }
    final out = <EasSearchHit>[];
    final store2 = resp.root.findChild('Response')?.findChild('Store') ??
        resp.root.findChild('Store');
    if (store2 != null) {
      for (final result in store2.findChildren('Result')) {
        final serverId = result.childText('LongId') ?? result.childText('ServerId');
        final props = result.findChild('Properties');
        if (serverId == null || props == null) continue;
        out.add(EasSearchHit(
          serverId: serverId,
          collectionId: result.childText('CollectionId'),
          subject: props.childText('Subject'),
          from: props.childText('From'),
          dateReceived: props.childText('DateReceived'),
          preview: props.childText('Preview'),
        ));
      }
    }
    log.info(_t, 'Search: "$query" → ${out.length}');
    return out;
  }

  // ──────────── Ответ на приглашение-встречу (MeetingResponse, cp8) ────────────
  // Теги code page 8 сверены с [MS-ASWBXML] 2.1.2.1.9.
  // userResponse: 1 = принять, 2 = под вопросом, 3 = отклонить.
  // ⚠ Требует прогона на реальном EAS-аккаунте.

  /// Ответить на приглашение. Возвращает CalendarId созданного/обновлённого
  /// события (пустая строка — успех без CalendarId) и отправил ли сервер
  /// ответ организатору сам; null — ошибка.
  ///
  /// [notifyOrganizer] = false — «Не отправлять ответ» (как в Outlook): встреча
  /// меняется только в календаре. [comment] — текст ответа, [proposedStart]
  /// и [proposedEnd] — «Предложить новое время» (ActiveSync 16+).
  Future<({String calendarId, bool sent, bool proposed})?> meetingResponse({
    required String collectionId,
    required String requestId,
    required int userResponse,
    bool notifyOrganizer = true,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
  }) async {
    final cfg = _cfg;
    if (cfg == null) return null;
    // С протокола 16.0 сервер сам отправляет ответ организатору, если в
    // запросе есть SendResponse. Без него встреча менялась только у нас в
    // календаре, а организатор ответа не получал. До 16.0 ответ отправляет
    // клиент письмом (см. mail_engine_service, iMIP).
    final canSend = notifyOrganizer && (double.tryParse(_protocolVersion) ?? 0) >= 16;
    String iso(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}.000Z';

    WbxmlDocument build({required bool sendResponse, required bool withProposal}) {
      final root = WbxmlElement(name: 'MeetingResponse', namespace: 'MeetingResponse');
      final req = root.addChild('Request', namespace: 'MeetingResponse');
      req.addChild('UserResponse', namespace: 'MeetingResponse', text: '$userResponse');
      req.addChild('CollectionId', namespace: 'MeetingResponse', text: collectionId);
      req.addChild('RequestId', namespace: 'MeetingResponse', text: requestId);
      if (sendResponse) {
        final sr = req.addChild('SendResponse', namespace: 'MeetingResponse');
        final text = (comment ?? '').trim();
        if (text.isNotEmpty) {
          final body = sr.addChild('Body', namespace: 'AirSyncBase');
          body.addChild('Type', namespace: 'AirSyncBase', text: '1');
          body.addChild('Data', namespace: 'AirSyncBase', text: text);
        }
        if (withProposal && proposedStart != null && proposedEnd != null) {
          sr.addChild('ProposedStartTime', namespace: 'MeetingResponse', text: iso(proposedStart));
          sr.addChild('ProposedEndTime', namespace: 'MeetingResponse', text: iso(proposedEnd));
        }
      }
      return WbxmlDocument(root: root);
    }

    String? statusOf(WbxmlDocument? r) =>
        r == null ? null : ((r.root.findChild('Result') ?? r.root).childText('Status') ?? r.root.childText('Status'));
    var sent = canSend;
    var proposed = canSend && proposedStart != null && proposedEnd != null && userResponse != 1;
    var resp = await _easCommand(cfg, 'MeetingResponse',
        build(sendResponse: sent, withProposal: proposed), policyKeyHeader: _policyKey ?? '0');
    if (proposed && statusOf(resp) != '1') {
      // Сервер не принял предложенное время — ответ без него (время
      // вызывающий допишет в текст).
      log.warn(_t, 'MeetingResponse с новым временем: Status=${statusOf(resp)} — повтор без него');
      proposed = false;
      resp = await _easCommand(cfg, 'MeetingResponse',
          build(sendResponse: sent, withProposal: false), policyKeyHeader: _policyKey ?? '0');
    }
    if (sent && statusOf(resp) != '1') {
      // Сервер не принял SendResponse — отвечаем без него (как раньше).
      log.warn(_t, 'MeetingResponse с SendResponse: Status=${statusOf(resp)} — повтор без него');
      sent = false;
      resp = await _easCommand(cfg, 'MeetingResponse',
          build(sendResponse: false, withProposal: false), policyKeyHeader: _policyKey ?? '0');
    }
    if (resp == null) {
      log.error(_t, 'MeetingResponse: нет ответа');
      return null;
    }
    final result = resp.root.findChild('Result') ?? resp.root;
    final status = statusOf(resp);
    if (status != '1') {
      log.error(_t, 'MeetingResponse: Status=$status');
      return null;
    }
    if (notifyOrganizer && !sent) {
      log.warn(_t, 'MeetingResponse: ответ в календаре сохранён, организатору сервер его не отправлял');
    }
    final calendarId = result.childText('CalendarId') ?? '';
    log.info(_t, 'MeetingResponse: ответ $userResponse, отправлен сервером: $sent, calendarId=$calendarId');
    return (calendarId: calendarId, sent: sent, proposed: proposed);
  }

  /// Сколько изменений ждёт в почтовых папках — ОДНИМ запросом на все
  /// (GetItemEstimate, [MS-ASCMD] 2.2.1.9). [syncKeys]: папка → SyncKey.
  /// Ответ: папка → число изменений; null — оценки нет (ключ не задан,
  /// ошибка, старый протокол): такую папку синхронизируем как обычно.
  ///
  /// Раньше каждый проход отправлял Sync в каждую из ~40 папок, даже когда
  /// изменений нет нигде: десятки запросов подряд (журнал 05.10).
  Future<Map<String, int?>> estimateMailChanges(Map<String, String> syncKeys) =>
      estimateChanges({for (final e in syncKeys.entries) e.key: (key: e.value, dataClass: 'Email')});

  /// То же для любых папок: папка → (SyncKey, класс: Email, Calendar,
  /// Contacts, Tasks, Notes). Фильтр по дате — как в Sync этой папки, иначе
  /// сервер оценивает другой набор и отвечает ошибкой.
  Future<Map<String, int?>> estimateChanges(
      Map<String, ({String key, String dataClass})> folders) async {
    final out = <String, int?>{for (final f in folders.keys) f: null};
    final cfg = _cfg;
    if (cfg == null) return out;
    final ver = double.tryParse(_protocolVersion) ?? 0;
    if (ver < 14) return out; // в 12.x другой порядок элементов — не рискуем
    final ready = [
      for (final e in folders.entries)
        if (e.value.key.isNotEmpty && e.value.key != '0') e.key,
    ];
    for (var i = 0; i < ready.length; i += 40) {
      final part = ready.sublist(i, i + 40 > ready.length ? ready.length : i + 40);
      final root = WbxmlElement(name: 'GetItemEstimate', namespace: 'GetItemEstimate');
      final cols = root.addChild('Collections', namespace: 'GetItemEstimate');
      for (final f in part) {
        final info = folders[f]!;
        final c = cols.addChild('Collection', namespace: 'GetItemEstimate');
        c.addChild('SyncKey', namespace: 'AirSync', text: info.key);
        c.addChild('CollectionId', namespace: 'GetItemEstimate', text: f);
        final o = c.addChild('Options', namespace: 'AirSync');
        final filter = switch (info.dataClass) {
          'Email' => '${cfg.mailFilterType}',
          'Calendar' => '6',
          _ => '0',
        };
        o.addChild('FilterType', namespace: 'AirSync', text: filter);
        o.addChild('Class', namespace: 'AirSync', text: info.dataClass);
      }
      final resp = await _easCommand(cfg, 'GetItemEstimate', WbxmlDocument(root: root),
          policyKeyHeader: _policyKey ?? '0');
      if (resp == null) {
        log.warn(_t, 'GetItemEstimate: нет ответа (HTTP $_lastStatus) — синхронизируем все папки');
        continue;
      }
      var withChanges = 0, unknown = 0;
      for (final r in resp.root.findChildren('Response')) {
        final col = r.findChild('Collection');
        final id = col?.childText('CollectionId');
        if (id == null || !out.containsKey(id)) continue;
        if (r.childText('Status') != '1') { unknown++; continue; } // 2/3/4 — оценки нет
        final est = int.tryParse(col?.childText('Estimate') ?? '');
        out[id] = est;
        if (est != null && est > 0) withChanges++;
      }
      log.info(_t, 'GetItemEstimate: папок ${part.length}, с изменениями $withChanges'
          '${unknown > 0 ? ', без оценки $unknown' : ''}');
    }
    return out;
  }

  @override
  Future<SyncResult> syncFolder(String folderId, {SyncState? since}) =>
      _syncFolder(folderId, since: since, allowReset: true);

  Future<SyncResult> _syncFolder(String folderId,
      {SyncState? since, required bool allowReset}) async {
    final cfg = _cfg!;
    // Шаг A: первичный Sync с SyncKey=0 (инициализация коллекции).
    var key = since?.token ?? _syncKeys[folderId] ?? '0';
    if (key == '0') {
      final init = _buildEmailSync(folderId, '0', initial: true);
      final r0 = await _easCommand(cfg, 'Sync', init, policyKeyHeader: _policyKey ?? '0');
      if (r0 == null) { log.error(_t, 'Sync init: нет ответа'); return const SyncResult(); }
      final col0 = r0.root.findChild('Collections')?.findChild('Collection');
      key = col0?.childText('SyncKey') ?? '0';
      _syncKeys[folderId] = key;
      log.info(_t, 'Sync init: новый SyncKey=$key');
      if (key == '0') return const SyncResult();
    }

    // Шаг B: запрашиваем изменения (GetChanges, WindowSize).
    final body = _buildEmailSync(folderId, key, initial: false);
    // 45 с: обычный ответ — меньше 4 с (порция до 0,5 МБ). Обрыв на шлюзе
    // раньше держал папку полторы минуты, а следующие папки и очередь ждали.
    final resp = await _easCommand(cfg, 'Sync', body,
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(seconds: 45));
    if (resp == null) {
      // Пустой ответ 200 в EAS — штатное «изменений нет»; ошибкой это не является.
      if (_lastStatus == 200) {
        log.info(_t, 'Sync: изменений нет');
        return SyncResult(newState: SyncState(key));
      }
      log.error(_t, 'Sync: нет ответа (HTTP $_lastStatus)');
      return const SyncResult();
    }
    // Дерево — только для подробного журнала: строить его на каждом ответе
    // (1–1,5 МБ при пересинхронизации) значило занимать главный поток.
    if (log.verbose) log.wbxml(_t, 'Sync-ответ', wbxmlTree(resp.root));

    final col = resp.root.findChild('Collections')?.findChild('Collection');
    final status = col?.childText('Status') ?? resp.root.childText('Status');
    // Status 3 — сервер не знает наш SyncKey (сброс устройства на сервере,
    // восстановление ящика, ключ из старой установки). Без обработки папка
    // «застывала» навсегда: каждый синк получал ту же ошибку. Начинаем
    // коллекцию заново — сервер пришлёт письма как новые, а дубли отсеет
    // слияние по id на стороне приложения.
    if (status == '3' && allowReset) {
      log.warn(_t, 'Sync: SyncKey отклонён (Status 3) — переинициализация папки $folderId');
      _syncKeys[folderId] = '0';
      _mailReinit.add(folderId);
      return _syncFolder(folderId, since: const SyncState('0'), allowReset: false);
    }
    if (status == '12') {
      log.warn(_t, 'Sync: иерархия папок изменилась (Status 12) — нужен FolderSync');
      _folderSyncKey = '0';
      _foldersAt = null;
      _hierarchyChanged = true;
    }
    // Status 8 у коллекции — папки на сервере нет (удалили в Outlook, 1.6.12):
    // приложение обновит список папок и уберёт её, а не будет каждый проход
    // запрашивать несуществующую папку.
    if (status == '8') {
      log.warn(_t, 'Sync: папки $folderId на сервере нет (Status 8) — обновим список папок');
      _foldersAt = null;
      _hierarchyChanged = true;
      return const SyncResult();
    }
    if (status != null && status != '1' && status != '3') {
      log.error(_t, 'Sync: Status=$status для папки $folderId');
    }

    final newKey = col?.childText('SyncKey') ?? key;
    _syncKeys[folderId] = newKey;
    final commands = col?.findChild('Commands');
    final added = <MailMessage>[];
    final deleted = <MessageRef>[];
    final flagChanges = <MailFlagChange>[];
    if (commands != null) {
      for (final add in commands.findChildren('Add')) {
        final m = _parseEmail(add, folderId);
        if (m != null) added.add(m);
      }
      // Change: сервер присылает ТОЛЬКО изменённые свойства (обычно Read и
      // Flag) — прочитали или пометили письмо в Outlook на компьютере.
      // Раньше Change игнорировался, и такие изменения до телефона не доходили.
      for (final ch in commands.findChildren('Change')) {
        final sid = ch.childText('ServerId');
        final app = ch.findChild('ApplicationData');
        if (sid == null || app == null) continue;
        final readTxt = app.childText('Read');
        final flagEl = app.findChild('Flag');
        // В кодеке токен 0x3B страницы Email назван 'FlagStatus' (в спецификации — Status).
        final flagged = flagEl == null
            ? null
            : (flagEl.childText('FlagStatus') ?? flagEl.childText('Status')) == '2';
        if (readTxt == null && flagged == null) continue;
        flagChanges.add(MailFlagChange(
          id: sid,
          folderId: folderId,
          read: readTxt == null ? null : readTxt == '1',
          flagged: flagged,
        ));
      }
      // Delete / SoftDelete: письмо удалено на сервере или с другого устройства
      // либо вышло за окно синхронизации. Раньше оставалось в приложении навсегда.
      for (final del in [...commands.findChildren('Delete'), ...commands.findChildren('SoftDelete')]) {
        final sid = del.childText('ServerId');
        if (sid != null) deleted.add(MessageRef(id: sid, folderId: folderId, serverId: sid));
      }
    }
    final more = col?.findChild('MoreAvailable') != null;
    log.info(_t, 'Sync: новых ${added.length}, изменено ${flagChanges.length}, '
        'удалено ${deleted.length}, MoreAvailable=$more, SyncKey=$newKey');
    return SyncResult(
      added: added,
      deleted: deleted,
      flagChanges: flagChanges,
      newState: SyncState(newKey),
      moreAvailable: more,
    );
  }

  WbxmlDocument _buildEmailSync(String collectionId, String syncKey, {required bool initial}) {
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collections = root.addChild('Collections', namespace: 'AirSync');
    final collection = collections.addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: syncKey);
    collection.addChild('CollectionId', namespace: 'AirSync', text: collectionId);
    if (!initial) {
      collection.addChild('DeletesAsMoves', namespace: 'AirSync', text: '1');
      collection.addChild('GetChanges', namespace: 'AirSync', text: '1');
      // 50 писем за раунд: тело урезано до TruncationSize (8 КБ по умолчанию),
      // порция ~0,5 МБ. При 25 первичная загрузка ящика растягивалась на
      // десятки раундов и выглядела как «синхронизация не работает».
      collection.addChild('WindowSize', namespace: 'AirSync', text: '50');
      final options = collection.addChild('Options', namespace: 'AirSync');
      options.addChild('FilterType', namespace: 'AirSync',
          text: '${_cfg?.mailFilterType ?? 2}'); // окно синхронизации (из настроек)
      options.addChild('Class', namespace: 'AirSync', text: 'Email');
      final bp = options.addChild('BodyPreference', namespace: 'AirSyncBase');
      bp.addChild('Type', namespace: 'AirSyncBase',
          text: '${_cfg?.bodyType ?? 1}'); // 1=plain, 2=HTML
      // TruncationSize режет тело до N байт (экономия трафика).
      // 0 = заголовки без тела ("только заголовки").
      bp.addChild('TruncationSize', namespace: 'AirSyncBase',
          text: '${_cfg?.bodyTruncationBytes ?? 8192}');
    }
    return WbxmlDocument(root: root);
  }

  // ──────────────────── PIM (Calendar/Contacts/Tasks/Notes) ────────────────────

  /// Команды PIM-папок — по одной: синхронизация календаря и сохранение
  /// встречи (или задачи, контакта) одновременно отправляли серверу один и
  /// тот же SyncKey папки — Exchange отвечал Status 3, и папка перечитывалась
  /// заново.
  Future<void>? _pimTail;
  Future<T> _pimLocked<T>(Future<T> Function() action) async {
    final previous = _pimTail;
    final gate = Completer<void>();
    _pimTail = gate.future;
    try {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      return await action();
    } finally {
      gate.complete();
      if (identical(_pimTail, gate.future)) _pimTail = null;
    }
  }

  @override
  Future<List<PimItem>> syncPim(String folderId,
          {required String dataClass, SyncState? since}) =>
      _pimLocked(() => _syncPim(folderId, dataClass: dataClass, since: since, allowReset: true));

  Future<List<PimItem>> _syncPim(String folderId,
      {required String dataClass, SyncState? since, required bool allowReset}) async {
    final cfg = _cfg!;
    _lastPimMoreAvailable = false;
    var key = since?.token ?? _pimSyncKeys[folderId] ?? '0';
    if (key == '0') {
      key = await _pimInitKey(cfg, folderId, dataClass);
      _pimSyncKeys[folderId] = key;
      if (key == '0') return const [];
    }
    final body = _buildPimSync(folderId, key, dataClass, initial: false);
    final resp = await _easCommand(cfg, 'Sync', body, policyKeyHeader: _policyKey ?? '0');
    if (resp == null) return const [];
    final col = resp.root.findChild('Collections')?.findChild('Collection');
    // Status 3 — ключ отклонён (сброс партнёрства, ключ из прошлой установки):
    // начинаем коллекцию заново, иначе календарь/контакты «застывали».
    if ((col?.childText('Status') ?? resp.root.childText('Status')) == '3' && allowReset) {
      log.warn(_t, 'syncPim($dataClass): SyncKey отклонён (Status 3) — переинициализация');
      _pimSyncKeys[folderId] = '0';
      _pimReinit.add(folderId);
      return _syncPim(folderId, dataClass: dataClass, since: const SyncState('0'), allowReset: false);
    }
    final colStatus = col?.childText('Status') ?? resp.root.childText('Status');
    if (colStatus != null && colStatus != '1') {
      log.warn(_t, 'syncPim($dataClass) folder=$folderId: Status $colStatus');
    }
    final newKey = col?.childText('SyncKey') ?? key;
    _pimSyncKeys[folderId] = newKey;
    final items = <PimItem>[];
    final commands = col?.findChild('Commands');
    if (commands != null) {
      for (final el in [...commands.findChildren('Add'), ...commands.findChildren('Change')]) {
        final sid = el.childText('ServerId');
        final appData = el.findChild('ApplicationData');
        if (sid != null && appData != null) {
          items.add(PimItem(
            serverId: sid,
            fields: _flattenAppData(appData),
            recurrence: dataClass == 'Calendar' ? _recurrenceOf(appData) : null,
            exceptions: dataClass == 'Calendar' ? _exceptionsOf(appData) : const [],
            attendees: dataClass == 'Calendar' ? _attendeesOf(appData) : const [],
          ));
        }
      }
      for (final del in commands.findChildren('Delete')) {
        final sid = del.childText('ServerId');
        if (sid != null) items.add(PimItem(serverId: sid, deleted: true));
      }
    }
    _lastPimMoreAvailable = col?.findChild('MoreAvailable') != null;
    log.info(_t, 'syncPim($dataClass) folder=$folderId: ${items.length} элементов, '
        'MoreAvailable=$_lastPimMoreAvailable, SyncKey=$newKey');
    return items;
  }

  /// Первичный Sync коллекции PIM (SyncKey 0 → новый ключ). Если сервер
  /// отверг его целиком (Status без Collections) — повтор без Supported:
  /// Exchange в AS 16.x отклонял первичную синхронизацию календаря с перечнем
  /// Supported, и календарь оставался пустым при работающих контактах.
  Future<String> _pimInitKey(AccountConfig cfg, String folderId, String dataClass) async {
    for (final withSupported in [true, false]) {
      final init = _buildPimSync(folderId, '0', dataClass,
          initial: true, withSupported: withSupported);
      final r0 = await _easCommand(cfg, 'Sync', init, policyKeyHeader: _policyKey ?? '0');
      if (r0 == null) return '0';
      final col0 = r0.root.findChild('Collections')?.findChild('Collection');
      final key = col0?.childText('SyncKey') ?? '0';
      if (key != '0') {
        if (!withSupported) _pimNoSupported.add(folderId);
        return key;
      }
      final st = col0?.childText('Status') ?? r0.root.childText('Status');
      final retry = withSupported && _supportedPimFields.containsKey(dataClass);
      log.warn(_t, 'syncPim($dataClass) folder=$folderId: первичный Sync отклонён '
          '(Status ${st ?? '?'}${retry ? ', повтор без Supported' : ''})');
      if (!retry) break;
    }
    return '0';
  }

  /// Папки, синхронизация которых начата без Supported (см. _pimInitKey).
  final Set<String> _pimNoSupported = {};

  WbxmlDocument _buildPimSync(String collectionId, String syncKey, String dataClass,
      {required bool initial, bool withSupported = true}) {
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: syncKey);
    collection.addChild('CollectionId', namespace: 'AirSync', text: collectionId);
    // Supported (только в первичном Sync, только Calendar/Contacts): перечень
    // свойств, которыми управляет приложение. Остальные сервер «призрачно»
    // хранит: изменение встречи из приложения не сотрёт участников, повторение
    // и прочее, чего приложение не передаёт. Без Supported Change заменял бы
    // элемент целиком, и всё неотправленное удалялось.
    final supported = initial && withSupported ? _supportedPimFields[dataClass] : null;
    if (supported != null) {
      final sup = collection.addChild('Supported', namespace: 'AirSync');
      for (final f in supported) {
        sup.addChild(f, namespace: dataClass);
      }
    }
    if (!initial) {
      collection.addChild('GetChanges', namespace: 'AirSync', text: '1');
      collection.addChild('WindowSize', namespace: 'AirSync', text: '100');
      final options = collection.addChild('Options', namespace: 'AirSync');
      // Календарь — события за 3 месяца назад и все будущие (FilterType 6);
      // остальное — без фильтра по дате.
      options.addChild('FilterType', namespace: 'AirSync',
          text: dataClass == 'Calendar' ? '6' : '0');
      options.addChild('Class', namespace: 'AirSync', text: dataClass);
      final bp = options.addChild('BodyPreference', namespace: 'AirSyncBase');
      bp.addChild('Type', namespace: 'AirSyncBase', text: '1');
      bp.addChild('TruncationSize', namespace: 'AirSyncBase', text: '32768');
    }
    return WbxmlDocument(root: root);
  }

  /// Свойства, которые приложение пишет в Calendar/Contacts (см. Supported).
  static const _supportedPimFields = <String, List<String>>{
    // Location сюда не входит: в AS 16 он в другом пространстве имён, а
    // «призрачное» место встречи всё равно обновляется, когда мы его передаём.
    'Calendar': ['TimeZone', 'AllDayEvent', 'EndTime', 'Subject', 'StartTime'],
    'Contacts': [
      'CompanyName', 'Department', 'Email1Address', 'FirstName', 'JobTitle',
      'LastName', 'MiddleName', 'MobilePhoneNumber', 'BusinessPhoneNumber',
    ],
  };

  /// Поддеревья, которые не должны попадать в «плоские» имена: у исключений
  /// повторения и участников свои StartTime/Subject/Email, и они перекрывали бы
  /// поля самого элемента.
  static const _nestedOnly = {'Exceptions', 'Attendees', 'Recurrence', 'Recurrences'};

  /// Плоская карта полей ApplicationData: имя тега → текст (и вложенные с префиксом).
  Map<String, String> _flattenAppData(WbxmlElement appData) {
    final map = <String, String>{};
    void walk(WbxmlElement e, String prefix, bool flat) {
      for (final c in e.children) {
        final key = prefix.isEmpty ? c.name : '$prefix.${c.name}';
        final t = c.text;
        if (t != null && t.isNotEmpty) {
          if (flat) map.putIfAbsent(c.name, () => t); // плоско по имени
          map[key] = t; // и с префиксом (Body.Data и т.п.)
        }
        if (c.children.isNotEmpty) walk(c, key, flat && !_nestedOnly.contains(c.name));
      }
    }
    walk(appData, '', true);
    return map;
  }

  /// Правило повторения календарного элемента: ключи без префикса
  /// «Recurrence_» (Type, Interval, Until, Occurrences, DayOfWeek, ...).
  Map<String, String>? _recurrenceOf(WbxmlElement appData) {
    final r = appData.findChild('Recurrence');
    if (r == null) return null;
    return {
      for (final c in r.children)
        if (c.text != null && c.text!.isNotEmpty)
          c.name.replaceFirst('Recurrence_', ''): c.text!,
    };
  }

  /// Участники встречи.
  List<Map<String, String>> _attendeesOf(WbxmlElement appData) => [
        for (final a in appData.findChild('Attendees')?.findChildren('Attendee') ?? const <WbxmlElement>[])
          {
            for (final c in a.children)
              if (c.text != null && c.text!.isNotEmpty) c.name.replaceFirst('Attendee_', ''): c.text!,
          },
      ];

  /// Исключения повторения: удалённые и изменённые вхождения.
  List<Map<String, String>> _exceptionsOf(WbxmlElement appData) {
    final ex = appData.findChild('Exceptions');
    if (ex == null) return const [];
    return [
      for (final e in ex.findChildren('Exception'))
        {
          for (final c in e.children)
            if (c.text != null && c.text!.isNotEmpty)
              (c.name == 'Exception_IsDeleted'
                  ? 'Deleted'
                  : c.name == 'Exception_StartTime'
                      ? 'ExceptionStartTime'
                      : c.name): c.text!,
          // Место встречи в AS 16 — AirSyncBase:Location/DisplayName.
          if (e.findChild('Location')?.childText('DisplayName') != null)
            'Location': e.findChild('Location')!.childText('DisplayName')!,
        },
    ];
  }

  /// Сервер отверг встречу с именем пояса в TimeZone (Status 6) — дальше в
  /// этом сеансе пояс уходит только смещением (как до 1.6.2).
  bool _tzNamesRejected = false;

  /// TIME_ZONE_INFORMATION без StandardName/DaylightName (байты 4–83, 88–167).
  static String? _stripTzNames(String? tz) {
    if (tz == null) return null;
    try {
      final b = Uint8List.fromList(base64.decode(tz));
      if (b.length != 172) return tz;
      b.fillRange(4, 84, 0);
      b.fillRange(88, 168, 0);
      return base64.encode(b);
    } catch (_) {
      return tz;
    }
  }

  static bool _hasTzName(String? tz) => tz != null && _stripTzNames(tz) != tz;

  /// Создать (serverId==null) или изменить PIM-элемент. Возвращает serverId.
  /// [fields] — значения в пространстве имён dataClass; [body] — текст тела.
  ///
  /// 1.6.4: встреча, отвергнутая сервером (Status 6 — «ошибка преобразования»)
  /// с именем пояса в TimeZone, повторяется один раз без имени; в журнал —
  /// состав запроса (имена полей и длины, без текста).
  Future<String?> upsertPim(String folderId,
      {required String dataClass,
      String? serverId,
      required Map<String, String?> fields,
      String? body,
      List<({String email, String? name, bool required})> attendees = const [],
      List<String>? categories,
      Map<String, String>? recurrence,
      List<({String name, String? contentType, Uint8List bytes})> attachments = const []}) => _pimLocked(() async {
    var atts = attachments;
    Future<String?> once(Map<String, String?> f) => _upsertPimOnce(folderId,
        dataClass: dataClass, serverId: serverId, fields: f, body: body,
        attendees: attendees, categories: categories, recurrence: recurrence, attachments: atts);
    // Вложения встречи (AS 16, 1.6.12): сервер отказал из-за них — встреча
    // важнее, создаём без вложений.
    Future<String?> withoutAttachmentsOn6(Map<String, String?> f) async {
      try {
        return await once(f);
      } on PimItemStatusError catch (e) {
        if (e.status != '6' || atts.isEmpty) rethrow;
        log.warn(_t, 'upsertPim($dataClass): Status 6 с вложениями — повтор без них');
        atts = const [];
        return once(f);
      }
    }
    final isCalendar = dataClass == 'Calendar';
    var f = fields;
    if (isCalendar && _tzNamesRejected && fields['TimeZone'] != null) {
      f = {...fields, 'TimeZone': _stripTzNames(fields['TimeZone'])};
    }
    try {
      return await withoutAttachmentsOn6(f);
    } on PimItemStatusError catch (e) {
      // Status 7 — конфликт: элемент изменился на сервере после нашего ключа,
      // и сервер (правило по умолчанию «побеждает сервер») правку не принял.
      // Правку сделал человек на телефоне — повторяем с правилом «побеждает
      // клиент» (Options/Conflict 0). Раньше правка контакта висела в
      // очереди и отвергалась при каждом повторе (журнал 20.10.2026).
      if (e.status == '7' && serverId != null && !_clientWins) {
        log.info(_t, 'upsertPim($dataClass): конфликт с сервером — правка с телефона заменяет серверную');
        _clientWins = true;
        try {
          return await once(f);
        } finally {
          _clientWins = false;
        }
      }
      if (e.status == '6' && isCalendar && !_tzNamesRejected && _hasTzName(f['TimeZone'])) {
        log.warn(_t, 'upsertPim(Calendar): Status 6 с именем пояса в TimeZone — повтор без имени');
        _tzNamesRejected = true;
        f = {...f, 'TimeZone': _stripTzNames(f['TimeZone'])};
        try {
          return await once(f);
        } on PimItemStatusError catch (e2) {
          if (e2.status != '6') rethrow;
        }
      } else if (e.status != '6') {
        rethrow;
      }
      // Параметры собрания, которых сервер может не знать, — повтор без них.
      if (isCalendar && (f.containsKey('DisallowNewTimeProposal') || f.containsKey('ResponseRequested'))) {
        log.warn(_t, 'upsertPim(Calendar): Status 6 — повтор без параметров собрания');
        return once({...f}..remove('DisallowNewTimeProposal')..remove('ResponseRequested'));
      }
      rethrow;
    }
  });

  /// Повтор правки после конфликта (Status 7) — с правилом «побеждает клиент».
  bool _clientWins = false;

  Future<String?> _upsertPimOnce(String folderId,
      {required String dataClass,
      String? serverId,
      required Map<String, String?> fields,
      String? body,
      List<({String email, String? name, bool required})> attendees = const [],
      List<String>? categories,
      Map<String, String>? recurrence,
      List<({String name, String? contentType, Uint8List bytes})> attachments = const []}) async {
    final cfg = _cfg!;
    var key = _pimSyncKeys[folderId] ?? '0';
    if (key == '0') {
      key = await _pimInitKey(cfg, folderId, dataClass);
      _pimSyncKeys[folderId] = key;
      if (key == '0') return null;
    }
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: key);
    collection.addChild('CollectionId', namespace: 'AirSync', text: folderId);
    // Без GetChanges=0 сервер вернул бы заодно чужие изменения папки и сдвинул
    // ключ — эти изменения мы бы потеряли (ответ разбирается только на ServerId).
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    if (_clientWins) {
      // Повтор после конфликта (Status 7): правка с телефона важнее (MS-ASCMD
      // Options/Conflict: 0 — объект клиента заменяет серверный).
      collection
          .addChild('Options', namespace: 'AirSync')
          .addChild('Conflict', namespace: 'AirSync', text: '0');
    }
    final commands = collection.addChild('Commands', namespace: 'AirSync');
    final clientId = 'c${DateTime.now().millisecondsSinceEpoch}';
    if (serverId != null && _pimNoSupported.contains(folderId)) {
      // Коллекция начата без Supported: Change заменит элемент целиком, и
      // поля, которых приложение не передаёт (например, участники), сервер сотрёт.
      log.warn(_t, 'upsertPim($dataClass): папка $folderId синхронизирована без Supported — '
          'изменение заменит элемент целиком');
    }
    final cmd = commands.addChild(serverId == null ? 'Add' : 'Change', namespace: 'AirSync');
    if (serverId == null) {
      cmd.addChild('ClientId', namespace: 'AirSync', text: clientId);
    } else {
      cmd.addChild('ServerId', namespace: 'AirSync', text: serverId);
    }
    final appData = cmd.addChild('ApplicationData', namespace: 'AirSync');
    final isCalendar = dataClass == 'Calendar';
    final as16 = _protocolVersion.startsWith('16');
    void addBody() {
      if (body == null) return;
      final b = appData.addChild('Body', namespace: 'AirSyncBase');
      b.addChild('Type', namespace: 'AirSyncBase', text: '1');
      b.addChild('Data', namespace: 'AirSyncBase', text: body);
    }
    if (dataClass == 'Notes') {
      // MS-ASNOTE: порядок схемы — Body, Subject, MessageClass. Раньше тело
      // шло после темы и без MessageClass, и Exchange отвечал на каждую
      // новую заметку Status 6 (ошибка преобразования) — выгрузка заметок
      // повторялась при каждой синхронизации ящика.
      addBody();
      final subject = fields['Subject'];
      if (subject != null) appData.addChild('Subject', namespace: 'Notes', text: subject);
      appData.addChild('MessageClass', namespace: 'Notes', text: fields['MessageClass'] ?? 'IPM.StickyNote');
    } else if (!isCalendar) {
      // «Пространство:Имя» — поле другого пространства имён ActiveSync
      // (Contacts2:ManagerName у контакта, 1.6.49); иначе — пространство
      // класса данных.
      fields.forEach((k, v) {
        if (v == null) return;
        final i = k.indexOf(':');
        appData.addChild(i > 0 ? k.substring(i + 1) : k, namespace: i > 0 ? k.substring(0, i) : dataClass, text: v);
      });
      addBody();
    } else {
      // Календарь — в порядке схемы MS-ASCAL (Exchange проверяет порядок
      // строже, чем для контактов и задач).
      final f = Map<String, String?>.of(fields);
      // Часовой пояс: до AS 16 обязателен при создании. Время передаём в UTC,
      // поэтому пояс — UTC (172 нулевых байта TIME_ZONE_INFORMATION).
      f.putIfAbsent('TimeZone', () => base64.encode(List<int>.filled(172, 0)));
      void put(String k) {
        final v = f[k];
        if (v != null) appData.addChild(k, namespace: 'Calendar', text: v);
      }
      put('TimeZone');
      put('AllDayEvent');
      addBody();
      put('BusyStatus');
      put('EndTime');
      final loc = f['Location'];
      if (loc != null) {
        // В AS 16 место встречи — AirSyncBase:Location/DisplayName; старый
        // Calendar:Location сервер отвергает (Status 6).
        if (as16) {
          appData
              .addChild('Location', namespace: 'AirSyncBase')
              .addChild('DisplayName', namespace: 'AirSyncBase', text: loc);
        } else {
          appData.addChild('Location', namespace: 'Calendar', text: loc);
        }
      }
      put('Reminder');
      put('Sensitivity');
      put('Subject');
      put('StartTime');
      if (attendees.isNotEmpty) {
        // Встреча (а не личное событие): MeetingStatus 1, затем участники.
        appData.addChild('MeetingStatus', namespace: 'Calendar', text: '1');
        final at = appData.addChild('Attendees', namespace: 'Calendar');
        for (final a in attendees) {
          final el = at.addChild('Attendee', namespace: 'Calendar');
          el.addChild('Attendee_Email', namespace: 'Calendar', text: a.email);
          el.addChild('Attendee_Name', namespace: 'Calendar',
              text: (a.name == null || a.name!.isEmpty) ? a.email : a.name);
          el.addChild('Attendee_Type', namespace: 'Calendar', text: a.required ? '1' : '2');
        }
      }
      // Категории (цвет встречи в Outlook) — после участников, до
      // повторения (порядок схемы MS-ASCAL). Пустой список при изменении
      // снимает категории.
      if (categories != null && (categories.isNotEmpty || serverId != null)) {
        final cats = appData.addChild('Categories', namespace: 'Calendar');
        for (final c in categories) {
          cats.addChild('Category', namespace: 'Calendar', text: c);
        }
      }
      if (recurrence != null && recurrence.isNotEmpty) {
        final r = appData.addChild('Recurrence', namespace: 'Calendar');
        for (final k in const ['Type', 'Occurrences', 'Interval', 'WeekOfMonth', 'DayOfWeek',
            'MonthOfYear', 'Until', 'DayOfMonth']) {
          final v = recurrence[k];
          if (v != null) r.addChild('Recurrence_$k', namespace: 'Calendar', text: v);
        }
      }
      // Параметры собрания (1.6.7) — после повторения, по схеме MS-ASCAL.
      put('DisallowNewTimeProposal');
      put('ResponseRequested');
      // Вложения встречи (MS-ASAIRS Add, только AS 16; 1.6.12): файлы письма,
      // из которого создана встреча, — как «Создать собрание» из письма в
      // Outlook. Порядок: ClientId, Content, ContentType, DisplayName, Method.
      if (as16 && attachments.isNotEmpty) {
        final list = appData.addChild('Attachments', namespace: 'AirSyncBase');
        for (var i = 0; i < attachments.length; i++) {
          final a = attachments[i];
          final add = list.addChild('Add', namespace: 'AirSyncBase');
          add.addChild('ClientId', namespace: 'AirSyncBase', text: '${clientId}a$i');
          add.addChild('Content', namespace: 'AirSyncBase', opaqueData: a.bytes);
          final ct = a.contentType;
          if (ct != null && ct.isNotEmpty) add.addChild('ContentType', namespace: 'AirSyncBase', text: ct);
          add.addChild('DisplayName', namespace: 'AirSyncBase', text: a.name);
          add.addChild('Method', namespace: 'AirSyncBase', text: '1');
        }
      }
    }
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      throw StateError('EAS Sync/${serverId == null ? 'Add' : 'Change'} ($dataClass): '
          'нет ответа (HTTP $_lastStatus)');
    }
    final col = resp.root.findChild('Collections')?.findChild('Collection');
    final newKey = col?.childText('SyncKey');
    if (newKey != null) _pimSyncKeys[folderId] = newKey;
    final colStatus = col?.childText('Status') ?? resp.root.childText('Status');
    if (colStatus == '3') _pimSyncKeys[folderId] = '0';
    if (colStatus != null && colStatus != '1') {
      throw StateError('EAS Sync ($dataClass): Status=$colStatus');
    }
    final r = col?.findChild('Responses')?.findChild(serverId == null ? 'Add' : 'Change');
    final itemStatus = r?.childText('Status');
    if (itemStatus != null && itemStatus != '1') {
      log.warn(_t, 'upsertPim($dataClass): Status=$itemStatus; запрос: ${_shapeOf(appData)}');
      throw PimItemStatusError(itemStatus, 'EAS Sync ($dataClass) элемент: Status=$itemStatus');
    }
    final newServerId = r?.childText('ServerId');
    log.info(_t, 'upsertPim($dataClass): serverId=${newServerId ?? serverId}, SyncKey=$newKey');
    return newServerId ?? serverId;
  }

  /// Состав ApplicationData для журнала: имена полей, числа — как есть,
  /// остальное — длиной (текст встречи и адреса в журнал не попадают).
  static String _shapeOf(WbxmlElement e) {
    if (e.children.isEmpty) {
      final t = e.text ?? '';
      if (t.isEmpty) return e.name;
      return RegExp(r'^\d{1,10}$').hasMatch(t) ? '${e.name}=$t' : '${e.name}(${t.length})';
    }
    return '${e.name}{${e.children.map(_shapeOf).join(', ')}}';
  }

  /// Удалить PIM-элемент (окончательно, без переноса в корзину).
  ///
  /// [dataClass] — класс папки (Calendar, Contacts, Tasks, Notes): нужен,
  /// если ключа синхронизации папки ещё нет. Команду Delete с ключом 0 сервер
  /// не принимает — сначала ключ, как при создании элемента (аудит
  /// 07.10.2026, E11).
  Future<void> deletePim(String folderId, String serverId, {String? dataClass}) => _pimLocked(() async {
    final cfg = _cfg!;
    var key = _pimSyncKeys[folderId] ?? '0';
    if (key == '0' && dataClass != null) {
      key = await _pimInitKey(cfg, folderId, dataClass);
      _pimSyncKeys[folderId] = key;
    }
    if (key == '0') {
      log.warn(_t, 'deletePim: нет ключа синхронизации папки $folderId — удаление не отправлено');
      return;
    }
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: key);
    collection.addChild('CollectionId', namespace: 'AirSync', text: folderId);
    collection.addChild('DeletesAsMoves', namespace: 'AirSync', text: '0');
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    final del = collection
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Delete', namespace: 'AirSync');
    del.addChild('ServerId', namespace: 'AirSync', text: serverId);
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
    final newKey = resp?.root.findChild('Collections')?.findChild('Collection')?.childText('SyncKey');
    if (newKey != null) _pimSyncKeys[folderId] = newKey;
    log.info(_t, 'deletePim: serverId=$serverId, SyncKey=$newKey');
  });

  MailMessage? _parseEmail(WbxmlElement add, String folderId) {
    final serverId = add.childText('ServerId');
    if (serverId == null) return null;
    final appData = add.findChild('ApplicationData');
    if (appData == null) {
      return MailMessage(id: serverId, folderId: folderId, serverId: serverId, from: const MailAddress(''));
    }
    final fromRaw = appData.childText('From') ?? '';
    final subject = appData.childText('Subject') ?? '';
    final dateStr = appData.childText('DateReceived');
    final read = appData.childText('Read') == '1';
    String? bodyPlain, bodyHtml, preview;
    final bodyEl = appData.findChild('Body');
    var truncated = false;
    if (bodyEl != null) {
      final type = int.tryParse(bodyEl.childText('Type') ?? '1') ?? 1;
      final data = bodyEl.childText('Data');
      if (type == 2) { bodyHtml = data; } else { bodyPlain = _decodeNumericEntities(data); }
      truncated = bodyEl.childText('Truncated') == '1';
    }
    // Своё превью из тела — с переносами строк (1.6.31: настройка «строк в
    // ленте»); превью сервера (одной строкой) — если тела нет.
    preview = _makePreview(bodyPlain ?? bodyHtml) ?? _decodeNumericEntities(appData.childText('Preview'));
    // Тело обрезано сервером (TruncationSize). Раньше обрезок сохранялся как
    // полное тело, и экран письма не догружал остальное: длинные письма
    // читались до середины, а у HTML ломалась разметка. Теперь обрезок идёт
    // только в превью, а полное тело экран письма запросит при открытии
    // (ItemOperations/Fetch).
    if (truncated) {
      bodyPlain = null;
      bodyHtml = null;
    }
    final flag = appData.findChild('Flag');
    // Токен 0x3B страницы Email в кодеке назван 'FlagStatus' (в спецификации
    // MS-ASWBXML — Status). Раньше читался 'Status', и флаг с сервера не
    // распознавался никогда.
    final isFlagged = (flag?.childText('FlagStatus') ?? flag?.childText('Status')) == '2';
    // Вложения (AirSyncBase:Attachments). Раньше список не разбирался вовсе:
    // у письма была скрепка, но открыть или переслать вложения было нельзя.
    // FileReference — ключ для скачивания через ItemOperations/Fetch.
    final attsEl = appData.findChild('Attachments');
    final attachments = _attachmentsOf(appData);
    final hasAtt = attachments.any((a) => !a.isInline) ||
        (attsEl != null && attachments.isEmpty);
    // Приглашение на встречу: время, место и организатор приходят в
    // Email:MeetingRequest, а тело у таких писем часто пустое — прежде экран
    // письма показывал пустую карточку.
    MeetingInfo? meeting;
    final mr = appData.findChild('MeetingRequest');
    if (mr != null) {
      final loc = mr.childText('Location') ?? mr.findChild('Location')?.childText('DisplayName');
      meeting = MeetingInfo(
        start: _parseEasDate(mr.childText('StartTime')),
        end: _parseEasDate(mr.childText('EndTime')),
        allDay: mr.childText('AllDayEvent') == '1',
        location: (loc == null || loc.trim().isEmpty) ? null : loc.trim(),
        organizer: mr.childText('Organizer'),
        responseRequested: mr.childText('ResponseRequested') == '1',
        uid: uidFromGlobalObjId(mr.childText('GlobalObjId')) ?? mr.childText('UID'),
        isOccurrence: isOccurrenceGlobalObjId(mr.childText('GlobalObjId')),
        proposedStart: _parseEasDate(mr.childText('ProposedStartTime')),
        proposedEnd: _parseEasDate(mr.childText('ProposedEndTime')),
        disallowNewTime: mr.childText('DisallowNewTimeProposal') == '1',
      );
    }
    return MailMessage(
      id: serverId, folderId: folderId, serverId: serverId,
      from: _parseAddr(fromRaw),
      // Получатели. Без них не работали «Ответить всем» и отбор писем, где
      // пользователь только в копии.
      to: _parseAddrList(appData.childText('To')),
      cc: _parseAddrList(appData.childText('Cc')),
      replyTo: _parseAddrList(appData.childText('ReplyTo')),
      subject: subject,
      preview: preview, bodyPlain: bodyPlain, bodyHtml: bodyHtml,
      date: _parseEasDate(dateStr), isRead: read, isFlagged: isFlagged,
      hasAttachments: hasAtt,
      attachments: attachments,
      conversationId: _conversationIdOf(appData),
      meeting: meeting,
      messageClass: appData.childText('MessageClass'),
    );
  }

  static Uint8List? _goid(String? b64) {
    if (b64 == null || b64.trim().isEmpty) return null;
    try {
      final b = base64.decode(b64.trim());
      return b.length < 40 ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// UID встречи по GlobalObjId ([MS-OXCICAL] 2.1.3.1.1.20.26): встреча из
  /// iCalendar хранит исходный UID после метки «vCal-Uid», остальные — это
  /// GlobalObjId в hex без даты вхождения. По такому UID Exchange находит
  /// встречу, когда ответ приходит письмом.
  static String? uidFromGlobalObjId(String? b64) {
    final b = _goid(b64);
    if (b == null) return null;
    final size = b[36] | (b[37] << 8) | (b[38] << 16) | (b[39] << 24);
    if (size >= 12 && b.length >= 40 + size) {
      final data = b.sublist(40, 40 + size);
      if (ascii.decode(data.sublist(0, 8), allowInvalid: true) == 'vCal-Uid') {
        var end = data.length;
        while (end > 12 && data[end - 1] == 0) {
          end--;
        }
        return utf8.decode(data.sublist(12, end), allowMalformed: true);
      }
    }
    final clean = Uint8List.fromList(b)..fillRange(16, 20, 0);
    return clean.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  /// В GlobalObjId есть дата вхождения — приглашение на одно вхождение серии.
  static bool isOccurrenceGlobalObjId(String? b64) {
    final b = _goid(b64);
    return b != null && (b[16] | b[17] | b[18] | b[19]) != 0;
  }

  /// Email2:ConversationId — непрозрачные байты (EAS 14+); в текст через
  /// base64. Раньше не читался: беседы у ActiveSync не собирались.
  static String? _conversationIdOf(WbxmlElement appData) {
    final el = appData.findChild('ConversationId');
    if (el == null) return null;
    final raw = el.opaqueData;
    if (raw != null && raw.isNotEmpty) return 'eas:${base64Url.encode(raw)}';
    final t = el.text?.trim();
    return (t == null || t.isEmpty) ? null : 'eas:$t';
  }

  /// Короткое превью из тела: без тегов, стилей и лишних пробелов.
  /// «&#1084;» → «м». Exchange оставляет числовые сущности и в текстовом
  /// (не HTML) теле письма.
  static String? _decodeNumericEntities(String? s) {
    if (s == null || !s.contains('&#')) return s;
    return s.replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]{1,6});'), (m) {
      final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isNotEmpty ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
  }

  /// Превью из тела письма: строки сохраняются (абзацы, <br>, строки
  /// таблиц — переносом), пробелы внутри строки — одним, пустые строки
  /// убираются (1.6.31). Не длиннее 300 символов.
  static String? _makePreview(String? body) {
    if (body == null || body.isEmpty) return null;
    final head = body.length > 60000 ? body.substring(0, 60000) : body;
    final isHtml = head.contains('<');
    var t = isHtml
        ? head
            .replaceAll(RegExp(r'<(style|script|head|title)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
            .replaceAll(RegExp(r'</(p|div|li|tr|h[1-6]|blockquote|table|ul|ol)\s*>', caseSensitive: false), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
        : head;
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
    t = _decodeNumericEntities(t) ?? t;
    final lines = <String>[];
    var len = 0;
    for (final raw in t.split(RegExp(r'\r\n|\r|\n'))) {
      final l = raw.replaceAll(RegExp(r'[ \t\u00A0\u200B]+'), ' ').trim();
      if (l.isEmpty) continue;
      lines.add(l);
      len += l.length + 1;
      if (len >= 300) break;
    }
    if (lines.isEmpty) return null;
    var out = lines.join('\n');
    if (out.length > 300) {
      var end = 300;
      final c = out.codeUnitAt(end - 1);
      if (c >= 0xD800 && c <= 0xDBFF) end--; // не рвать эмодзи
      out = '${out.substring(0, end)}…';
    }
    return out;
  }

  /// Список адресов EAS: `"Иванов, Иван" <a@b.ru>, c@d.ru`. Запятая может
  /// стоять внутри кавычек (формат «Фамилия, Имя»), поэтому делим вручную.
  List<MailAddress> _parseAddrList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final out = <MailAddress>[];
    final buf = StringBuffer();
    var inQuotes = false;
    var inAngle = false;
    void flush() {
      final part = buf.toString().trim();
      buf.clear();
      if (part.isEmpty) return;
      final a = _parseAddr(part);
      if (a.email.contains('@')) out.add(a);
    }
    for (final ch in raw.split('')) {
      if (ch == '"') inQuotes = !inQuotes;
      if (!inQuotes && ch == '<') inAngle = true;
      if (!inQuotes && ch == '>') inAngle = false;
      if ((ch == ',' || ch == ';') && !inQuotes && !inAngle) {
        flush();
      } else {
        buf.write(ch);
      }
    }
    flush();
    return out;
  }

  /// Скачать вложение по FileReference (ItemOperations/Fetch).
  ///
  /// Ответ — `Properties/Data`: либо opaque-байты, либо base64-строка.
  /// Таймаут увеличен: 30 секунд не хватает на десятки мегабайт по мобильной сети.
  Future<Uint8List> fetchAttachment(String fileReference) async {
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
    fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
    fetch.addChild('FileReference', namespace: 'AirSyncBase', text: fileReference);
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 3));
    if (resp == null) {
      throw StateError('EAS: вложение не получено (HTTP $_lastStatus)');
    }
    final f = resp.root.findChild('Response')?.findChild('Fetch');
    final status = f?.childText('Status') ?? resp.root.childText('Status');
    if (status != null && status != '1') {
      throw StateError('EAS: ItemOperations Fetch Status=$status');
    }
    final props = f?.findChild('Properties');
    final dataEl = props?.findChild('Data') ?? props?.findChild('Body')?.findChild('Data');
    final opaque = dataEl?.opaqueData;
    if (opaque != null && opaque.isNotEmpty) return opaque;
    final text = dataEl?.text;
    if (text != null && text.isNotEmpty) {
      return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
    }
    throw StateError('EAS: в ответе нет данных вложения');
  }

  /// Несколько вложений одним запросом ItemOperations (1.5.6): картинки
  /// подписи письма — их бывает пять-десять — раньше шли запросом на каждую,
  /// а шлюз перед Exchange режет частые запросы. Ключ — FileReference;
  /// чего нет в ответе — сервер не отдал. null — сервер ответил, но не на
  /// пачку (нет ни одного Fetch в ответе): тогда — по одному.
  Future<Map<String, Uint8List>?> fetchAttachments(List<String> fileReferences) async {
    if (fileReferences.isEmpty) return const {};
    if (fileReferences.length == 1) {
      return {fileReferences.first: await fetchAttachment(fileReferences.first)};
    }
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    for (final ref in fileReferences) {
      final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
      fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
      fetch.addChild('FileReference', namespace: 'AirSyncBase', text: ref);
    }
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 3));
    if (resp == null) {
      throw StateError('EAS: вложения не получены (HTTP $_lastStatus)');
    }
    final out = <String, Uint8List>{};
    final fetches = resp.root.findChild('Response')?.findChildren('Fetch') ?? const <WbxmlElement>[];
    if (fetches.isEmpty) return null;
    for (var i = 0; i < fetches.length; i++) {
      final f = fetches[i];
      if ((f.childText('Status') ?? '1') != '1') continue;
      // Ответы идут в порядке запросов; FileReference сервер обычно повторяет.
      final ref = f.childText('FileReference') ?? (i < fileReferences.length ? fileReferences[i] : null);
      if (ref == null) continue;
      final props = f.findChild('Properties');
      final dataEl = props?.findChild('Data') ?? props?.findChild('Body')?.findChild('Data');
      final opaque = dataEl?.opaqueData;
      if (opaque != null && opaque.isNotEmpty) {
        out[ref] = opaque;
        continue;
      }
      final text = dataEl?.text;
      if (text != null && text.isNotEmpty) {
        try {
          out[ref] = base64.decode(text.replaceAll(RegExp(r'\s'), ''));
        } catch (_) {}
      }
    }
    return out;
  }

  /// Тексты нескольких писем одним запросом ItemOperations (1.5.6, «Письма
  /// на телефоне»): раньше — запрос на письмо, 300 писем докачивались минутами,
  /// и шлюз мог счесть это частыми запросами. Ключ — ServerId; чего нет в
  /// ответе — сервер не отдал (удалено, ошибка). null — сервер ответил, но
  /// не на пачку (нет ни одного Fetch в ответе): тогда — по одному.
  Future<Map<String, ({String? bodyPlain, String? bodyHtml})>?> fetchBodies(List<MessageRef> refs) async {
    if (refs.isEmpty) return const {};
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    for (final ref in refs) {
      final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
      fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
      fetch.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
      fetch.addChild('ServerId', namespace: 'AirSync', text: ref.serverId ?? ref.id);
      final opts = fetch.addChild('Options', namespace: 'ItemOperations');
      final bp = opts.addChild('BodyPreference', namespace: 'AirSyncBase');
      bp.addChild('Type', namespace: 'AirSyncBase', text: '${_cfg?.bodyType ?? 1}');
    }
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 2));
    if (resp == null) {
      throw StateError('EAS: тексты писем не получены (HTTP $_lastStatus)');
    }
    if (log.verbose) log.wbxml(_t, 'ItemOperations-ответ', wbxmlTree(resp.root));
    final out = <String, ({String? bodyPlain, String? bodyHtml})>{};
    final fetches = resp.root.findChild('Response')?.findChildren('Fetch') ?? const <WbxmlElement>[];
    if (fetches.isEmpty) return null;
    for (var i = 0; i < fetches.length; i++) {
      final f = fetches[i];
      if ((f.childText('Status') ?? '1') != '1') continue;
      final sid = f.childText('ServerId') ?? (i < refs.length ? (refs[i].serverId ?? refs[i].id) : null);
      if (sid == null) continue;
      final bodyEl = f.findChild('Properties')?.findChild('Body');
      final data = bodyEl?.findChild('Data')?.text;
      if (data == null) continue;
      out[sid] = bodyEl?.childText('Type') == '2'
          ? (bodyPlain: null, bodyHtml: data)
          : (bodyPlain: data, bodyHtml: null);
    }
    return out;
  }

  MailAddress _parseAddr(String raw) {
    final m = RegExp(r'(.*)<(.+)>').firstMatch(raw);
    if (m != null) return MailAddress(m.group(2)!.trim(), m.group(1)!.trim().replaceAll('"', ''));
    return MailAddress(raw.trim());
  }

  /// Дата ActiveSync: «2026-10-05T10:00:00.000Z» или компактная
  /// «20261005T100000Z» (в приглашениях Email:StartTime/EndTime).
  DateTime? _parseEasDate(String? s) {
    if (s == null) return null;
    final v = s.trim();
    final d = DateTime.tryParse(v);
    if (d != null) return d;
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$').firstMatch(v);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  }

  @override
  Future<void> send(OutgoingMessage message) async {
    final cfg = _cfg!;
    final mime = _buildMime(cfg, message);
    var mimeBytes = Uint8List.fromList(utf8.encode(mime));
    final transform = message.mimeTransform;
    if (transform != null) mimeBytes = await transform(mimeBytes);
    log.info(_t, 'SendMail: письмо ${_size(mimeBytes.length)}, вложений ${message.attachments.length}');
    final root = WbxmlElement(name: 'SendMail', namespace: 'ComposeMail');
    root.addChild('ClientId', namespace: 'ComposeMail', text: _clientId('snd', message));
    root.addChild('SaveInSentItems', namespace: 'ComposeMail');
    root.addChild('MIME', namespace: 'ComposeMail', opaqueData: mimeBytes);
    // Таймаут больше обычного: письмо с вложениями уходит одним запросом.
    final resp = await _easCommand(cfg, 'SendMail', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 3));
    // Честная проверка: успех только при реальном WBXML-ответе/пустом 200.
    if (_lastWasChallenge) {
      log.error(_t, 'SendMail: заблокировано анти-ботом WAF (ServicePipe) — письмо НЕ отправлено.');
      throw Exception('EAS SendMail: блокировка анти-бота WAF (письмо не отправлено)');
    }
    if (_lastWasWafBig) {
      log.error(_t, 'SendMail: шлюз не пропустил письмо ${_size(mimeBytes.length)} — НЕ отправлено. '
          'Повтор того же письма не поможет: уменьшите вложения.');
      throw GatewaySizeRejected(mimeBytes.length);
    }
    if (_lastStatus != 200) {
      log.error(_t, 'SendMail: НЕ отправлено (HTTP $_lastStatus). См. лог.');
      throw Exception('EAS SendMail: HTTP $_lastStatus (письмо не отправлено)');
    }
    if (resp == null) {
      log.info(_t, 'SendMail: HTTP 200 без тела — успех');
      return;
    }
    final status = resp.root.childText('Status');
    if (status == '118') {
      // Письмо с этим ClientId сервер уже отправил (повтор после обрыва).
      log.info(_t, 'SendMail: Status 118 — уже отправлено ранее, повтор не нужен');
      return;
    }
    if (status != null && status != '1') {
      log.error(_t, 'SendMail: Status=$status (ошибка)');
      throw Exception('EAS SendMail Status=$status');
    }
    log.info(_t, 'SendMail: успех');
  }

  /// ClientId команды отправки: постоянный, если приложение его передало
  /// (повтор той же записи очереди), иначе уникальный. Не длиннее 40
  /// символов (ограничение MS-ASCMD).
  static String _clientId(String prefix, OutgoingMessage m) {
    final id = m.clientId;
    if (id == null || id.isEmpty) return '$prefix${DateTime.now().millisecondsSinceEpoch}';
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final v = '$prefix$clean';
    return v.length > 40 ? v.substring(0, 40) : v;
  }

  /// Переслать письмо силами сервера (SmartForward): оригинальные вложения
  /// Exchange прикладывает сам — устройство их не скачивает и не загружает.
  /// Раньше пересылка шла через отдельный старый стек ActiveSync со своим
  /// PolicyKey; теперь — тем же подключением, что и синхронизация.
  Future<void> smartForward({
    required String folderId,
    required String itemId,
    required OutgoingMessage message,
  }) async {
    // Подписанное/зашифрованное письмо сервер дополнять не должен.
    if (message.mimeTransform != null) return send(message);
    final cfg = _cfg!;
    final mime = _buildMime(cfg, message);
    final root = WbxmlElement(name: 'SmartForward', namespace: 'ComposeMail');
    // Порядок по схеме MS-ASCMD: ClientId, Source, SaveInSentItems, Mime —
    // строгие серверы отвечают InvalidXML на другой порядок.
    root.addChild('ClientId', namespace: 'ComposeMail', text: _clientId('fwd', message));
    final src = root.addChild('Source', namespace: 'ComposeMail');
    src.addChild('FolderId', namespace: 'ComposeMail', text: folderId);
    src.addChild('ItemId', namespace: 'ComposeMail', text: itemId);
    root.addChild('SaveInSentItems', namespace: 'ComposeMail');
    root.addChild('MIME', namespace: 'ComposeMail', opaqueData: Uint8List.fromList(utf8.encode(mime)));
    final resp = await _easCommand(cfg, 'SmartForward', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 3));
    if (_lastWasChallenge || _lastStatus != 200) {
      throw Exception('EAS SmartForward: HTTP $_lastStatus (письмо не отправлено)');
    }
    final status = resp?.root.childText('Status');
    if (status == '118') {
      log.info(_t, 'SmartForward: Status 118 — уже отправлено ранее');
      return;
    }
    if (status != null && status != '1') {
      throw Exception('EAS SmartForward Status=$status');
    }
    log.info(_t, 'SmartForward: успех');
  }

  /// Ответ силами сервера (SmartReply): исходное письмо (и его вложения)
  /// не скачивается и не отправляется заново — сервер сам добавляет цитату
  /// к [message]. Экономит трафик на длинных переписках.
  Future<void> smartReply({
    required String folderId,
    required String itemId,
    required OutgoingMessage message,
  }) async {
    // Подписанное/зашифрованное письмо сервер дополнять не должен.
    if (message.mimeTransform != null) return send(message);
    final cfg = _cfg!;
    final mime = _buildMime(cfg, message);
    final root = WbxmlElement(name: 'SmartReply', namespace: 'ComposeMail');
    root.addChild('ClientId', namespace: 'ComposeMail', text: _clientId('rpl', message));
    final src = root.addChild('Source', namespace: 'ComposeMail');
    src.addChild('FolderId', namespace: 'ComposeMail', text: folderId);
    src.addChild('ItemId', namespace: 'ComposeMail', text: itemId);
    root.addChild('SaveInSentItems', namespace: 'ComposeMail');
    root.addChild('MIME', namespace: 'ComposeMail', opaqueData: Uint8List.fromList(utf8.encode(mime)));
    final resp = await _easCommand(cfg, 'SmartReply', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 3));
    if (_lastWasChallenge || _lastStatus != 200) {
      throw Exception('EAS SmartReply: HTTP $_lastStatus (письмо не отправлено)');
    }
    final status = resp?.root.childText('Status');
    if (status == '118') {
      log.info(_t, 'SmartReply: Status 118 — уже отправлено ранее');
      return;
    }
    if (status != null && status != '1') {
      throw Exception('EAS SmartReply Status=$status');
    }
    log.info(_t, 'SmartReply: успех');
  }

  /// Direct Push (Ping): сервер держит запрос до [heartbeatSeconds] и отвечает
  /// раньше, если в папках появились изменения.
  ///  · status 1 — время ожидания истекло, изменений нет (норма);
  ///  · status 2 — изменения в [changed];
  ///  · status 5 — сервер просит другой интервал ([heartbeat]);
  ///  · status 7 — нужна синхронизация иерархии папок;
  ///  · status 8 — ошибка (сеть/сервер).
  /// Сбой сети при Ping сейчас ожидаем (приложение свёрнуто, iOS
  /// замораживает запросы): пишется в журнал как DEBUG, а не WARN.
  bool Function()? quietPingErrors;

  Future<({int status, List<String> changed, int? heartbeat})> ping(
      List<String> folderIds, {int heartbeatSeconds = 480}) async {
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'Ping', namespace: 'Ping');
    root.addChild('HeartbeatInterval', namespace: 'Ping', text: '$heartbeatSeconds');
    final folders = root.addChild('Folders', namespace: 'Ping');
    for (final id in folderIds) {
      final f = folders.addChild('Folder', namespace: 'Ping');
      f.addChild('Id', namespace: 'Ping', text: id);
      f.addChild('Class', namespace: 'Ping', text: 'Email');
    }
    final resp = await _easCommand(cfg, 'Ping', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0',
        timeout: Duration(seconds: heartbeatSeconds + 60));
    if (resp == null) {
      // Пустой 200 — «изменений нет»; блокировка WAF или сбой сети — ошибка.
      final ok = _lastStatus == 200 && !_lastWasChallenge;
      return (status: ok ? 1 : 8, changed: const <String>[], heartbeat: null);
    }
    final status = int.tryParse(resp.root.childText('Status') ?? '') ?? 8;
    final changed = <String>[];
    for (final f in resp.root.findChild('Folders')?.findChildren('Folder') ?? const <WbxmlElement>[]) {
      final id = f.text ?? f.childText('Id');
      if (id != null && id.isNotEmpty) changed.add(id);
    }
    final hb = int.tryParse(resp.root.childText('HeartbeatInterval') ?? '');
    return (status: status, changed: changed, heartbeat: hb);
  }

  /// MIME исходящего письма для SendMail/SmartForward/SmartReply.
  ///
  /// По RFC 5322/2045: строки через CRLF, не длиннее 998 символов (base64
  /// режется по 76), не-ASCII в заголовках — только encoded-words (RFC 2047).
  /// Раньше тело шло одной строкой base64 (письма с длинным текстом сервер
  /// мог отвергнуть), а получатели «Скрытая копия» не попадали в письмо вовсе.
  String _buildMime(AccountConfig cfg, OutgoingMessage m) {
    const crlf = '\r\n';
    String enc(String v) {
      final ascii = v.codeUnits.every((c) => c >= 0x20 && c < 0x7F);
      return ascii ? v : '=?UTF-8?B?${base64.encode(utf8.encode(v))}?=';
    }
    String addr(MailAddress x) {
      final n = x.name;
      if (n == null || n.isEmpty) return x.email;
      final ascii = n.codeUnits.every((c) => c >= 0x20 && c < 0x7F);
      final quoted = ascii ? '"${n.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"' : enc(n);
      return '$quoted <${x.email}>';
    }
    String fmt(List<MailAddress> a) => a.map(addr).join(', ');
    String b64Lines(List<int> bytes) {
      final b = base64.encode(bytes);
      final out = StringBuffer();
      for (var i = 0; i < b.length; i += 76) {
        out.write(b.substring(i, i + 76 > b.length ? b.length : i + 76));
        out.write(crlf);
      }
      return out.toString();
    }
    String rfcDate(DateTime d) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      String two(int v) => v.toString().padLeft(2, '0');
      final u = d.toUtc();
      return '${days[u.weekday - 1]}, ${two(u.day)} ${months[u.month - 1]} ${u.year} '
          '${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
    }

    final atts = m.attachments.where((a) => a.bytes != null && a.bytes!.isNotEmpty).toList();
    final domain = cfg.email.contains('@') ? cfg.email.split('@').last : 'localhost';
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final buf = StringBuffer();
    void h(String line) => buf.write('$line$crlf');

    // Отправитель — владелец ящика или адрес «от имени» (1.6.27): Exchange
    // ActiveSync берёт From из MIME и проверяет права «Отправить как/от имени».
    final from = m.from;
    h('From: ${from == null ? cfg.email : addr(from)}');
    h('To: ${fmt(m.to)}');
    if (m.cc.isNotEmpty) h('Cc: ${fmt(m.cc)}');
    // Exchange рассылает и по Bcc из MIME, а сам заголовок из копий удаляет.
    if (m.bcc.isNotEmpty) h('Bcc: ${fmt(m.bcc)}');
    h('Subject: ${enc(m.subject)}');
    h('Date: ${rfcDate(DateTime.now())}');
    h('Message-ID: <ogn.$stamp@$domain>');
    final reply = m.inReplyTo?.trim();
    if (reply != null && reply.isNotEmpty) {
      // Цепочка «References родителя + его Message-ID»: In-Reply-To —
      // последний id, References — вся цепочка (первый и последние 19).
      var ids = RegExp(r'<[^<>\s]+>').allMatches(reply).map((x) => x.group(0)!).toList();
      if (ids.isEmpty) ids = [reply.startsWith('<') ? reply : '<$reply>'];
      final seen = <String>{};
      ids = [for (final i in ids) if (seen.add(i)) i];
      if (ids.length > 20) ids = [ids.first, ...ids.sublist(ids.length - 19)];
      h('In-Reply-To: ${ids.last}');
      h('References: ${ids.join(' ')}');
    }
    switch (m.importance.toLowerCase()) {
      case 'high':
        h('Importance: High');
        h('X-Priority: 1');
        break;
      case 'low':
        h('Importance: Low');
        h('X-Priority: 5');
        break;
    }
    // «Confidential|dsp|no-forward» — пометка Outlook и гриф в MIME
    // (приложение: MailLabel в mail_classification.dart).
    final label = m.sensitivity.split('|');
    switch (label.first.trim().toLowerCase()) {
      case 'personal':
        h('Sensitivity: Personal');
        break;
      case 'private':
        h('Sensitivity: Private');
        break;
      case 'confidential':
        h('Sensitivity: Company-Confidential');
        break;
    }
    String token(int i) => label.length > i ? label[i].replaceAll(RegExp(r'[^A-Za-z,\-]'), '') : '';
    if (token(1).isNotEmpty) h('X-Ogneliss-Classification: ${token(1)}');
    if (token(2).isNotEmpty) h('X-Ogneliss-Handling: ${token(2)}');
    h('MIME-Version: 1.0');

    final isHtml = m.bodyHtml != null;
    final bodyBytes = utf8.encode(m.bodyHtml ?? m.bodyPlain ?? '');
    final bodyType = isHtml ? 'text/html; charset=UTF-8' : 'text/plain; charset=UTF-8';

    // Текст письма; с iCalendar — multipart/alternative «текст + календарь»
    // (iMIP, RFC 6047): так ответ на приглашение узнают Exchange и Outlook.
    void writeBody() {
      final ics = m.calendar;
      if (ics == null || ics.isEmpty) {
        h('Content-Type: $bodyType');
        h('Content-Transfer-Encoding: base64');
        h('');
        buf.write(b64Lines(bodyBytes));
        return;
      }
      final alt = '----ogneliss_alt_$stamp';
      h('Content-Type: multipart/alternative; boundary="$alt"');
      h('');
      h('--$alt');
      h('Content-Type: $bodyType');
      h('Content-Transfer-Encoding: base64');
      h('');
      buf.write(b64Lines(bodyBytes));
      h('--$alt');
      h('Content-Type: text/calendar; method=${m.calendarMethod}; charset=UTF-8');
      h('Content-Transfer-Encoding: base64');
      h('');
      buf.write(b64Lines(utf8.encode(ics)));
      h('--$alt--');
    }

    if (atts.isEmpty) {
      writeBody();
      return buf.toString();
    }

    final boundary = '----ogneliss_$stamp';
    h('Content-Type: multipart/mixed; boundary="$boundary"');
    h('');
    h('--$boundary');
    writeBody();
    for (final a in atts) {
      h('--$boundary');
      final ct = (a.contentType?.isNotEmpty ?? false) ? a.contentType! : 'application/octet-stream';
      final name = enc(a.name).replaceAll('"', '');
      h('Content-Type: $ct; name="$name"');
      h('Content-Transfer-Encoding: base64');
      h('Content-Disposition: attachment; filename="$name"');
      h('');
      buf.write(b64Lines(a.bytes!));
    }
    h('--$boundary--');
    return buf.toString();
  }

  /// Псевдопапка писем из серверного поиска (тело — по LongId).
  static const searchFolderId = 'search';

  @override
  Future<MailMessage> fetchMessage(MessageRef ref) async {
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
    fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
    if (ref.folderId == searchFolderId) {
      // Письмо из серверного поиска: у него LongId, а не ServerId папки.
      fetch.addChild('LongId', namespace: 'Search', text: ref.serverId ?? ref.id);
    } else {
      fetch.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
      fetch.addChild('ServerId', namespace: 'AirSync', text: ref.serverId ?? ref.id);
    }
    final opts = fetch.addChild('Options', namespace: 'ItemOperations');
    final bp = opts.addChild('BodyPreference', namespace: 'AirSyncBase');
    bp.addChild('Type', namespace: 'AirSyncBase', text: '${_cfg?.bodyType ?? 1}');
    // TruncationSize не указываем — хотим ПОЛНОЕ тело.
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      return MailMessage(id: ref.id, folderId: ref.folderId, serverId: ref.serverId, from: const MailAddress(''));
    }
    if (log.verbose) log.wbxml(_t, 'ItemOperations-ответ', wbxmlTree(resp.root));
    final props = resp.root.findChild('Response')?.findChild('Fetch')?.findChild('Properties');
    String? bodyPlain, bodyHtml;
    if (props != null) {
      final bodyEl = props.findChild('Body');
      final data = bodyEl?.findChild('Data')?.text;
      final typeStr = bodyEl?.childText('Type');
      if (data != null) {
        if (typeStr == '2') {
          bodyHtml = data;
        } else {
          bodyPlain = data;
        }
      }
    }
    // Вложения (1.7.2+111): черновик, добавленный с телефона, Sync клиенту
    // не возвращает — список его файлов берётся отсюда.
    final attachments = props == null ? const <MailAttachment>[] : _attachmentsOf(props);
    return MailMessage(
      id: ref.id,
      folderId: ref.folderId,
      serverId: ref.serverId,
      from: const MailAddress(''),
      subject: props?.childText('Subject') ?? '',
      bodyPlain: bodyPlain,
      bodyHtml: bodyHtml,
      attachments: attachments,
      hasAttachments: attachments.any((a) => !a.isInline),
    );
  }

  /// Заголовки письма из начала MIME (ItemOperations Fetch, тип тела 4,
  /// первые 16 КБ): List-Unsubscribe, List-Id, Authentication-Results.
  /// ActiveSync сам эти заголовки не отдаёт. Ключи — в нижнем регистре;
  /// повторяющиеся заголовки склеиваются через «; ».
  Future<Map<String, String>> fetchHeaders(MessageRef ref) async {
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
    fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
    fetch.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
    fetch.addChild('ServerId', namespace: 'AirSync', text: ref.serverId ?? ref.id);
    final opts = fetch.addChild('Options', namespace: 'ItemOperations');
    final bp = opts.addChild('BodyPreference', namespace: 'AirSyncBase');
    bp.addChild('Type', namespace: 'AirSyncBase', text: '4');
    bp.addChild('TruncationSize', namespace: 'AirSyncBase', text: '16384');
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    final data = resp?.root
        .findChild('Response')
        ?.findChild('Fetch')
        ?.findChild('Properties')
        ?.findChild('Body')
        ?.findChild('Data')
        ?.text;
    return parseMimeHeaders(data ?? '');
  }

  /// Письмо целиком в MIME (ItemOperations Fetch, тип тела 4) — для
  /// проверки подписи S/MIME: подпись считается по исходным байтам письма,
  /// разобранное сервером тело для этого не годится.
  Future<Uint8List?> fetchMime(MessageRef ref) async {
    final cfg = _cfg!;
    final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
    final fetch = root.addChild('Fetch', namespace: 'ItemOperations');
    fetch.addChild('Store', namespace: 'ItemOperations', text: 'Mailbox');
    fetch.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
    fetch.addChild('ServerId', namespace: 'AirSync', text: ref.serverId ?? ref.id);
    final opts = fetch.addChild('Options', namespace: 'ItemOperations');
    final bp = opts.addChild('BodyPreference', namespace: 'AirSyncBase');
    bp.addChild('Type', namespace: 'AirSyncBase', text: '4');
    final resp = await _easCommand(cfg, 'ItemOperations', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0', timeout: const Duration(minutes: 2));
    final data = resp?.root
        .findChild('Response')
        ?.findChild('Fetch')
        ?.findChild('Properties')
        ?.findChild('Body')
        ?.findChild('Data');
    final opaque = data?.opaqueData;
    if (opaque != null && opaque.isNotEmpty) return opaque;
    final text = data?.text;
    if (text == null || text.isEmpty) return null;
    return Uint8List.fromList(utf8.encode(text));
  }

  /// Разбор блока заголовков MIME (до первой пустой строки), со склейкой
  /// перенесённых строк.
  static Map<String, String> parseMimeHeaders(String mime) {
    final out = <String, String>{};
    final end = mime.indexOf(RegExp(r'\r?\n\r?\n'));
    final head = end < 0 ? mime : mime.substring(0, end);
    final lines = head.split(RegExp(r'\r?\n'));
    String? name;
    final value = StringBuffer();
    void flush() {
      if (name == null) return;
      final k = name.toLowerCase();
      final v = value.toString().trim();
      out[k] = out.containsKey(k) ? '${out[k]}; $v' : v;
    }
    for (final l in lines) {
      if (l.startsWith(' ') || l.startsWith('\t')) {
        value.write(' ${l.trim()}');
        continue;
      }
      final i = l.indexOf(':');
      if (i <= 0) continue;
      flush();
      name = l.substring(0, i).trim();
      value
        ..clear()
        ..write(l.substring(i + 1).trim());
    }
    flush();
    return out;
  }

  @override
  Future<void> applyFlags(MessageRef ref, {bool? read, bool? flagged, bool strict = false}) async {
    final cfg = _cfg!;
    final serverId = ref.serverId ?? ref.id;
    final key = _syncKeys[ref.folderId] ?? '0';
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: key);
    collection.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
    // GetChanges=0 обязателен: по умолчанию сервер вместе с ответом на наше
    // изменение прислал бы НОВЫЕ письма и сдвинул SyncKey — а этот ответ
    // разбирается только на предмет статуса, и письма пропали бы навсегда.
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    final change = collection
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Change', namespace: 'AirSync');
    change.addChild('ServerId', namespace: 'AirSync', text: serverId);
    final appData = change.addChild('ApplicationData', namespace: 'AirSync');
    if (read != null) {
      appData.addChild('Read', namespace: 'Email', text: read ? '1' : '0');
    }
    if (flagged != null) {
      final flag = appData.addChild('Flag', namespace: 'Email');
      if (flagged) {
        flag.addChild('FlagStatus', namespace: 'Email', text: '2');
        flag.addChild('FlagType', namespace: 'Email', text: 'Flag for follow up');
      }
      // Снять флаг — пустой <Flag/> (MS-ASEMAIL). Status=0 сервер не принимает.
    }
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    // Status 8 у элемента — письмо уже удалено на сервере: менять нечего.
    // [strict] — письмо найдено поиском (Find): 8 значит «изменение не дошло».
    _checkSyncCommand(resp, 'Change', serverId, ref.folderId,
        okItemStatuses: strict ? const {'1'} : const {'1', '8'});
  }

  /// Есть ли у почтовой папки SyncKey (папка синхронизировалась): изменения
  /// командой Sync без него невозможны.
  bool hasMailSyncKey(String folderId) => (_syncKeys[folderId] ?? '0') != '0';

  /// Папки, которые сервер заставил загрузить заново (Sync Status 3): у их
  /// писем новые ServerId, прежние строки приложение должно сопоставить
  /// или убрать.
  final Set<String> _mailReinit = {};

  /// Была ли папка загружена заново с прошлого вызова (флаг сбрасывается).
  bool takeMailReinit(String folderId) => _mailReinit.remove(folderId);

  /// То же для календаря и контактов (1.6.2): после Status 3 у элементов
  /// новые ServerId — прежние строки приложения стали дублями (замечание
  /// 13.10.2026: встречи в календаре по два раза).
  final Set<String> _pimReinit = {};
  bool takePimReinit(String folderId) => _pimReinit.remove(folderId);

  /// Find (ActiveSync 16.1) недоступен на этом сервере — не повторяем.
  bool _findUnsupported = false;

  /// Поиск писем в папке командой Find (ActiveSync 16.1). В отличие от
  /// Search, Find возвращает ServerId — по нему письмо можно изменить
  /// (прочитано, флаг) командой Sync, даже если оно старше окна
  /// синхронизации. null — команда не поддерживается или не прошла.
  /// Теги — кодовая страница 25 (Find) из спецификации MS-ASWBXML.
  Future<List<EasFindHit>?> findInFolder(String collectionId, String freeText, {int limit = 50}) async {
    final cfg = _cfg;
    if (cfg == null || _findUnsupported || freeText.trim().isEmpty) return null;
    if ((double.tryParse(_protocolVersion) ?? 0) < 16.1) return null;
    final root = WbxmlElement(name: 'Find', namespace: 'Find');
    final rnd = Random.secure();
    String hex(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    root.addChild('SearchId', namespace: 'Find',
        text: '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}');
    final crit = root
        .addChild('ExecuteSearch', namespace: 'Find')
        .addChild('MailBoxSearchCriterion', namespace: 'Find');
    final q = crit.addChild('Query', namespace: 'Find');
    q.addChild('Class', namespace: 'AirSync', text: 'Email');
    q.addChild('CollectionId', namespace: 'AirSync', text: collectionId);
    q.addChild('FreeText', namespace: 'Find', text: freeText);
    final o = crit.addChild('Options', namespace: 'Find');
    o.addChild('Range', namespace: 'Find', text: '0-${limit - 1}');
    final resp = await _easCommand(cfg, 'Find', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      // 400/501 — команды нет на сервере (или шлюз её не пропускает).
      if (_lastStatus == 400 || _lastStatus == 501 || _lastStatus == 404) _findUnsupported = true;
      log.warn(_t, 'Find: нет ответа (HTTP $_lastStatus)');
      return null;
    }
    if (log.verbose) log.wbxml(_t, 'Find-ответ', wbxmlTree(resp.root));
    final status = resp.root.childText('Status');
    final response = resp.root.findChild('Response');
    final inner = response?.childText('Status');
    if ((status != null && status != '1') || (inner != null && inner != '1')) {
      log.warn(_t, 'Find: Status=${status ?? inner}');
      if (status == '2') _findUnsupported = true; // неверный запрос — не повторяем
      return null;
    }
    final out = <EasFindHit>[];
    for (final r in response?.findChildren('Result') ?? const <WbxmlElement>[]) {
      final sid = r.childText('ServerId');
      final props = r.findChild('Properties');
      if (sid == null || props == null) continue;
      out.add(EasFindHit(
        serverId: sid,
        collectionId: r.childText('CollectionId') ?? collectionId,
        subject: props.childText('Subject'),
        from: props.childText('From'),
        dateReceived: props.childText('DateReceived'),
      ));
    }
    log.info(_t, 'Find в папке $collectionId: ${out.length}');
    return out;
  }

  /// Вложения письма (AirSyncBase:Attachments) из ApplicationData или
  /// Properties. FileReference — ключ для скачивания (ItemOperations/Fetch).
  static List<MailAttachment> _attachmentsOf(WbxmlElement data) {
    final attachments = <MailAttachment>[];
    final attsEl = data.findChild('Attachments');
    if (attsEl == null) return attachments;
    for (final a in attsEl.findChildren('Attachment')) {
      final ref = a.childText('FileReference');
      if (ref == null || ref.isEmpty) continue;
      var name = a.childText('DisplayName') ?? 'attachment';
      // Method 5 — вложенное письмо: имя — его тема, без расширения.
      // Добавляем .eml, чтобы оно открывалось письмом, а не «файлом».
      final embedded = a.childText('Method') == '5';
      if (embedded && !name.toLowerCase().endsWith('.eml')) name = '$name.eml';
      attachments.add(MailAttachment(
        id: ref,
        name: name,
        contentType: embedded ? 'message/rfc822' : null,
        size: int.tryParse(a.childText('EstimatedDataSize') ?? ''),
        serverFileReference: ref,
        isInline: a.childText('IsInline') == '1',
        contentId: a.childText('ContentId'),
      ));
    }
    return attachments;
  }

  /// Черновик в серверные «Черновики» (MS-ASCMD: Add письма в папку
  /// черновиков — только ActiveSync 16). Команда идёт в той же цепочке
  /// SyncKey, что и синхронизация папки (GetChanges=0 — чужие изменения не
  /// забираем). Возвращает ServerId или null (протокол ниже 16, папка ещё
  /// не синхронизировалась, отказ сервера). [attachments] — файлы черновика
  /// (MS-ASAIRS Add, 1.7.2+111): как у встреч, ClientId, Content,
  /// ContentType, DisplayName, Method.
  Future<String?> addDraft(
    String folderId, {
    required List<MailAddress> to,
    List<MailAddress> cc = const [],
    List<MailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
  }) async {
    if (!_protocolVersion.startsWith('16')) return null;
    final key = _syncKeys[folderId] ?? '0';
    if (key == '0') return null;
    final cfg = _cfg!;
    String list(List<MailAddress> a) => a
        .map((m) => (m.name != null && m.name!.isNotEmpty)
            ? '"${m.name!.replaceAll('"', '')}" <${m.email}>'
            : m.email)
        .join(', ');
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: key);
    collection.addChild('CollectionId', namespace: 'AirSync', text: folderId);
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    final clientId = 'd${DateTime.now().millisecondsSinceEpoch}';
    final add = collection
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Add', namespace: 'AirSync');
    add.addChild('ClientId', namespace: 'AirSync', text: clientId);
    final app = add.addChild('ApplicationData', namespace: 'AirSync');
    if (to.isNotEmpty) app.addChild('To', namespace: 'Email', text: list(to));
    if (cc.isNotEmpty) app.addChild('Cc', namespace: 'Email', text: list(cc));
    app.addChild('Subject', namespace: 'Email', text: subject);
    final body = app.addChild('Body', namespace: 'AirSyncBase');
    body.addChild('Type', namespace: 'AirSyncBase', text: '2');
    body.addChild('Data', namespace: 'AirSyncBase', text: bodyHtml);
    if (bcc.isNotEmpty) app.addChild('Bcc', namespace: 'Email2', text: list(bcc));
    final files = attachments.where((a) => a.bytes.isNotEmpty).toList();
    if (files.isNotEmpty) {
      final atts = app.addChild('Attachments', namespace: 'AirSyncBase');
      for (var i = 0; i < files.length; i++) {
        final a = files[i];
        final part = atts.addChild('Add', namespace: 'AirSyncBase');
        part.addChild('ClientId', namespace: 'AirSyncBase', text: '${clientId}a$i');
        part.addChild('Content', namespace: 'AirSyncBase', opaqueData: a.bytes);
        final ct = a.contentType;
        if (ct != null && ct.isNotEmpty) part.addChild('ContentType', namespace: 'AirSyncBase', text: ct);
        part.addChild('DisplayName', namespace: 'AirSyncBase', text: a.name);
        part.addChild('Method', namespace: 'AirSyncBase', text: '1');
      }
    }
    // С файлами запрос большой — таймаут как у отправки письма.
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0',
        timeout: files.isEmpty ? const Duration(seconds: 30) : const Duration(minutes: 3));
    if (resp == null) {
      // С файлами без ответа сервера — ошибка, а не «не умеет»: черновик
      // остаётся на телефоне и выгружается позже.
      if (files.isNotEmpty) throw StateError('EAS Sync/Add черновика: нет ответа (HTTP $_lastStatus)');
      return null;
    }
    final col = resp.root.findChild('Collections')?.findChild('Collection');
    final newKey = col?.childText('SyncKey');
    if (newKey != null) _syncKeys[folderId] = newKey;
    final status = col?.childText('Status') ?? resp.root.childText('Status');
    if (status == '3') {
      _syncKeys[folderId] = '0';
      return null;
    }
    for (final r in col?.findChild('Responses')?.findChildren('Add') ?? const <WbxmlElement>[]) {
      if (r.childText('ClientId') != clientId) continue;
      final st = r.childText('Status');
      if (st != null && st != '1') {
        log.warn(_t, 'addDraft: Status=$st');
        return null;
      }
      return r.childText('ServerId');
    }
    return null;
  }

  /// Проверить ответ на Sync с командами (Change/Delete) и сохранить новый
  /// SyncKey. Раньше статус не проверялся: отказ сервера выглядел как успех,
  /// операция удалялась из офлайн-очереди и терялась.
  void _checkSyncCommand(WbxmlDocument? resp, String cmd, String serverId, String folderId,
      {Set<String> okItemStatuses = const {'1'}}) {
    if (resp == null) {
      throw StateError('EAS Sync/$cmd: нет ответа (HTTP $_lastStatus)');
    }
    final col = resp.root.findChild('Collections')?.findChild('Collection');
    final newKey = col?.childText('SyncKey');
    if (newKey != null) _syncKeys[folderId] = newKey;
    final status = col?.childText('Status') ?? resp.root.childText('Status');
    if (status == '3') {
      // Ключ устарел — следующий syncFolder переинициализирует коллекцию.
      _syncKeys[folderId] = '0';
      throw StateError('EAS Sync/$cmd: SyncKey отклонён (Status 3)');
    }
    if (status != null && status != '1') {
      throw StateError('EAS Sync/$cmd: Status=$status');
    }
    // Статус конкретного элемента приходит в Responses, только если он не 1.
    for (final r in col?.findChild('Responses')?.findChildren(cmd) ?? const <WbxmlElement>[]) {
      if (r.childText('ServerId') != serverId) continue;
      final st = r.childText('Status');
      if (st != null && !okItemStatuses.contains(st)) {
        throw StateError('EAS Sync/$cmd $serverId: Status=$st');
      }
    }
  }

  /// Подставить SyncKey папки, сохранённый приложением между запусками.
  /// Без этого после перезапуска операции (прочитано/флаг/удаление) уходили
  /// с ключом «0», и сервер отвергал их до первой синхронизации папки.
  void seedMailSyncKey(String folderId, String key) {
    final cur = _syncKeys[folderId];
    if (cur == null || cur == '0') _syncKeys[folderId] = key;
  }

  /// Вернуть SyncKey папки к подтверждённому значению безусловно: порция,
  /// полученная с новым ключом, не сохранилась у приложения, и операции над
  /// письмами не должны уходить с ключом, который сервер уже считает
  /// доставленным.
  void restoreMailSyncKey(String folderId, String key) => _syncKeys[folderId] = key;

  @override
  Future<void> move(MessageRef ref, String toFolderId) async {
    final cfg = _cfg!;
    _lastMoveDstId = null;
    final serverId = ref.serverId ?? ref.id;
    final root = WbxmlElement(name: 'MoveItems', namespace: 'Move');
    final mv = root.addChild('Move', namespace: 'Move');
    mv.addChild('SrcMsgId', namespace: 'Move', text: serverId);
    mv.addChild('SrcFldId', namespace: 'Move', text: ref.folderId);
    mv.addChild('DstFldId', namespace: 'Move', text: toFolderId);
    final resp = await _easCommand(cfg, 'MoveItems', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    if (resp == null) {
      throw StateError('EAS MoveItems: нет ответа (HTTP $_lastStatus)');
    }
    final status = resp.root.findChild('Response')?.childText('Status');
    _lastMoveDstId = resp.root.findChild('Response')?.childText('DstMsgId');
    log.info(_t, 'MoveItems: Status=$status, DstMsgId=$_lastMoveDstId');
    // 3 — успешно перемещено (MS-ASCMD). 1 — письма (или исходной папки) на
    // сервере уже нет: его переместили или удалили раньше — в Outlook, из
    // уведомления, другим устройством; 4 — папки совпадают. Повторять
    // бессмысленно: операция висела в «Ожидают отправки» с «Status=1»
    // (замечание 17.10.2026). Следующая синхронизация папок покажет, где
    // письмо на самом деле. Остальное — отказ: бросаем, операция остаётся в
    // очереди.
    if (status == '1' || status == '4') {
      log.warn(_t, 'MoveItems: Status=$status — письма $serverId в папке ${ref.folderId} уже нет '
          '(перемещено или удалено раньше) — считаем выполненным');
      _lastMoveDstId = null;
      return;
    }
    if (status != '3') {
      // Status 5 (по MS-ASCMD — «элемент занят или перемещается») Exchange
      // отвечает и на письмо, которое переносить уже нечего: операция висела
      // в «Ожидают отправки» и повторялась с тем же ответом (журнал
      // 20.10.2026: четыре удалённых письма, «Status=5» каждые пару минут).
      //  · в «Удалённые» — удаляем командой Sync Delete (DeletesAsMoves: тот же
      //    перенос в «Удалённые»); письма нет — Status 8, цель достигнута;
      //  · в другую папку — спрашиваем сервер, есть ли письмо в исходной
      //    папке (Sync Fetch): нет — считаем выполненным, есть — ошибка.
      final from = _folderName(ref.folderId), to = _folderName(toFolderId);
      log.warn(_t, 'MoveItems: Status=$status (письмо …${_tail(serverId)}, $from → $to)');
      final trash = _folders.where((f) => f.type == MailFolderType.trash).map((f) => f.id).firstOrNull;
      if (status != null && toFolderId == trash) {
        log.info(_t, 'MoveItems: удаляем командой Sync Delete (в «Удалённые»)');
        await delete(ref);
        _lastMoveDstId = null;
        return;
      }
      if (await _existsInFolder(ref.folderId, serverId) == false) {
        log.warn(_t, 'MoveItems: письма в папке «$from» на сервере уже нет — считаем выполненным');
        _lastMoveDstId = null;
        return;
      }
      throw StateError('EAS MoveItems: Status=$status');
    }
  }

  String _folderName(String id) =>
      _folders.where((f) => f.id == id).map((f) => f.displayName).firstOrNull ?? id;

  static String _tail(String s) => s.length <= 6 ? s : s.substring(s.length - 6);

  /// Есть ли письмо [serverId] в папке [folderId] на сервере (Sync с
  /// командой Fetch, без чужих изменений). null — узнать не удалось (нет
  /// ключа папки, ошибка сервера).
  Future<bool?> _existsInFolder(String folderId, String serverId) async {
    final key = _syncKeys[folderId];
    if (key == null || key == '0') return null;
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final c = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    c.addChild('SyncKey', namespace: 'AirSync', text: key);
    c.addChild('CollectionId', namespace: 'AirSync', text: folderId);
    c.addChild('GetChanges', namespace: 'AirSync', text: '0');
    c
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Fetch', namespace: 'AirSync')
        .addChild('ServerId', namespace: 'AirSync', text: serverId);
    try {
      final resp = await _easCommand(_cfg!, 'Sync', WbxmlDocument(root: root), policyKeyHeader: _policyKey ?? '0');
      if (resp == null) return null;
      final col = resp.root.findChild('Collections')?.findChild('Collection');
      final newKey = col?.childText('SyncKey');
      if (newKey != null) _syncKeys[folderId] = newKey;
      final st = col?.childText('Status') ?? resp.root.childText('Status');
      if (st == '3') _syncKeys[folderId] = '0';
      if (st != null && st != '1') return null;
      for (final r in col?.findChild('Responses')?.findChildren('Fetch') ?? const <WbxmlElement>[]) {
        if (r.childText('ServerId') != serverId) continue;
        final s = r.childText('Status');
        if (s == '8') return false;
        if (s == '1') return true;
      }
      // Письмо пришло в ответе (Responses/Fetch со Status 1) — есть.
      return col?.findChild('Responses') != null ? true : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(MessageRef ref) async {
    final cfg = _cfg!;
    final serverId = ref.serverId ?? ref.id;
    final key = _syncKeys[ref.folderId] ?? '0';
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    final collection = root
        .addChild('Collections', namespace: 'AirSync')
        .addChild('Collection', namespace: 'AirSync');
    collection.addChild('SyncKey', namespace: 'AirSync', text: key);
    collection.addChild('CollectionId', namespace: 'AirSync', text: ref.folderId);
    collection.addChild('DeletesAsMoves', namespace: 'AirSync', text: '1');
    collection.addChild('GetChanges', namespace: 'AirSync', text: '0');
    final del = collection
        .addChild('Commands', namespace: 'AirSync')
        .addChild('Delete', namespace: 'AirSync');
    del.addChild('ServerId', namespace: 'AirSync', text: serverId);
    final resp = await _easCommand(cfg, 'Sync', WbxmlDocument(root: root),
        policyKeyHeader: _policyKey ?? '0');
    // Status 8 — «объект не найден»: письмо уже удалено (например, в Outlook) —
    // цель достигнута, это не ошибка.
    _checkSyncCommand(resp, 'Delete', serverId, ref.folderId, okItemStatuses: const {'1', '8'});
  }

  @override
  Future<void> dispose() async {
    try { _http.close(); } catch (_) {}
  }

  // Диагностика
  List<String> get protocolVersions => _protocolVersions;
  List<String> get serverCommands => _serverCommands;
  String? get resolvedHost => _resolvedHost;
  String? get easUrl => _easUrl;
  /// Для диагностики: cookie сервера, которые несёт движок.
  String? get backEndCookie => _cookieHeader;
  String? get policyKey => _policyKey;
  String get protocolVersion => _protocolVersion;
  bool get useBase64 => _useBase64;
  String? _lastMoveDstId;
  /// Новый ServerId письма после MoveItems: в EAS у перемещённого письма он
  /// меняется (папка входит в идентификатор).
  String? get lastMoveDstId => _lastMoveDstId;

  String? pimSyncKeyFor(String folderId) => _pimSyncKeys[folderId];

  /// Подставить SyncKey PIM-папки (из общего хранилища).
  void restorePimSyncKey(String folderId, String key) => _pimSyncKeys[folderId] = key;
  String? mailSyncKeyFor(String folderId) => _syncKeys[folderId];
}

/// Результат серверного поиска EAS (Search, cp15). Основные поля письма из
/// `Properties`; полное тело догружается отдельно при открытии.
class EasSearchHit {
  final String serverId;
  final String? collectionId;
  final String? subject;
  final String? from;
  final String? dateReceived;
  final String? preview;

  const EasSearchHit({
    required this.serverId,
    this.collectionId,
    this.subject,
    this.from,
    this.dateReceived,
    this.preview,
  });
}

/// Результат Find: письмо с ServerId папки (в отличие от LongId у Search).
class EasFindHit {
  final String serverId;
  final String collectionId;
  final String? subject;
  final String? from;
  final String? dateReceived;
  const EasFindHit({
    required this.serverId,
    required this.collectionId,
    this.subject,
    this.from,
    this.dateReceived,
  });
}

/// Запись адресной книги организации (GAL).
class EasGalEntry {
  final String email;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? title;
  final String? company;
  final String? office;
  final String? phone;
  final String? mobilePhone;
  /// Фото (JPEG в base64), если запрошено и есть в адресной книге.
  final String? picture;
  const EasGalEntry({
    required this.email,
    required this.displayName,
    this.firstName,
    this.lastName,
    this.title,
    this.company,
    this.office,
    this.phone,
    this.mobilePhone,
    this.picture,
  });
}

/// Владелец ящика по данным сервера (Settings → UserInformation).
class EasUserInfo {
  final String? displayName;
  final String? primary;
  final List<String> addresses;
  const EasUserInfo({this.displayName, this.primary, this.addresses = const []});
}

/// Автоответ «Нет на месте» (Settings → Oof).
class EasOof {
  /// 0 — выключен, 1 — включён, 2 — по расписанию [start]…[end].
  final int state;
  final DateTime? start;
  final DateTime? end;
  final String? internalReply;
  final String? externalReply;
  final bool externalEnabled;
  const EasOof({
    required this.state,
    this.start,
    this.end,
    this.internalReply,
    this.externalReply,
    this.externalEnabled = false,
  });
}

/// Сервер отверг элемент PIM (Sync/Add или Change), [status] — код MS-ASCMD.
/// Текст сообщения прежний — его разбирает приложение (mail_engine_service).
class PimItemStatusError extends StateError {
  PimItemStatusError(this.status, String message) : super(message);
  final String status;
}

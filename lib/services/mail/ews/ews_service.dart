// lib/services/mail/ews/ews_service.dart
// Exchange Web Services — полная реализация:
// - NTLM-аутентификация через NtlmClient
// - Поддержка fetchMode (headers/partial/full)
// - Retry с exponential backoff (3 попытки)
// - Rate limiting на auth
// - Дедупликация одновременных запросов
// - HTML-санитизация ответов
// - Lazy-загрузка вложений
// - Все операции: folders, emails, send, move, delete, flag, recall, search, contacts, calendar

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';
import 'package:xml/xml.dart';

import 'ews_directory_extras.dart';
import 'ews_mail_tips.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/security/security_utils.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../core/security/html_sanitizer.dart';
import '../../../core/utils/isolate_runner.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/task_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/models/free_busy_view.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../features/settings/providers/settings_provider.dart';
import 'ews_xml_builder.dart';
import '../../rules/auto_rules_service.dart';
import 'ews_xml_parser.dart';
import '../imap/imap_service.dart' show ImapService;
import '../../security/mail_classification.dart' show MailLabel;
import '../../security/smime_mime.dart' show SmimeMime;
import 'ntlm_client.dart';
import '../oauth/oauth_service.dart' show OAuthService;
import 'dart:convert';
import 'package:collection/collection.dart';

/// Провайдер EWS-сервиса
final ewsServiceProvider = Provider<EwsService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return EwsService(secureStorage: secureStorage);
});

class EwsService {
  final SecureStorageService secureStorage;
  final Map<String, NtlmClient> _clients = {};
  final Map<String, String> _ewsUrls = {};
  final RequestDeduplicator _dedup = RequestDeduplicator();

  static const int _maxRetries = 3;

  EwsService({required this.secureStorage});

  // ════════════════════════ SOAP REQUEST ════════════════════════

  /// Выполнить SOAP-запрос с retry, rate limiting, таймаутами
  /// Public wrapper for delta sync and other services
  Future<XmlDocument> rawSoapRequest(AccountModel account, String soapBody) =>
      _soapRequest(account, soapBody);

  /// [idempotent] = false для команд, повтор которых нельзя считать
  /// безопасным: отправка (CreateItem SendAndSaveCopy, SendItem, ForwardItem),
  /// ответ на приглашение, создание черновика и вложений. Если такой запрос
  /// не дождался ответа (таймаут, обрыв), сервер мог его уже выполнить —
  /// повтор дал бы получателю дубль письма. Ошибку отдаём наверх, очередь
  /// отправки переводит письмо в «не отправлено». Перегрузка сервера
  /// (ErrorServerBusy, 503) — запрос не выполнен, повтор безопасен и для них.
  Future<XmlDocument> _soapRequest(
    AccountModel account,
    String soapBody, {
    int timeoutSeconds = 30,
    bool idempotent = true,
  }) async {
    // Rate limit
    if (!SecurityUtils.isAuthAllowed(account.email)) {
      final remaining = SecurityUtils.getLockoutRemainingSeconds(account.email);
      throw AuthException(
        userMessage: 'Слишком много попыток. Повторите через ${(remaining / 60).ceil()} мин.',
      );
    }

    Exception? lastError;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          // Exponential backoff
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
          AppLogger.debug('EWS retry $attempt/$_maxRetries');
        }

        final client = await _getClient(account);
        final url = await _getEwsUrl(account);
        final envelope = EwsXmlBuilder.wrapInEnvelope(soapBody);

        final response = await client.post(
          Uri.parse(url),
          headers: {'Content-Type': 'text/xml; charset=utf-8', 'Accept': 'text/xml'},
          body: envelope,
          timeoutSeconds: timeoutSeconds,
        ).timeout(Duration(seconds: timeoutSeconds + 5));

        if (response.statusCode == 401) {
          SecurityUtils.recordFailedAttempt(account.email);
          _clients.remove(account.id)?.close();
          throw const InvalidCredentialsException();
        }

        // EWS сообщает об ошибках запроса SOAP-ошибкой с HTTP 500. Раньше
        // любая 500 трижды повторялась с паузами, а затем терялся сам текст
        // ошибки («Ошибка Exchange (500)»). Теперь: перегрузка сервера
        // (ErrorServerBusy) — ждём, сколько просит сервер, и повторяем;
        // остальное — сразу понятная ошибка без бессмысленных повторов.
        if (response.statusCode == 500 && response.body.contains('Fault')) {
          final busy = response.body.contains('ErrorServerBusy');
          if (busy && attempt < _maxRetries) {
            final ms = int.tryParse(RegExp(r'BackOffMilliseconds[^>]*>\s*(\d+)')
                        .firstMatch(response.body)
                        ?.group(1) ??
                    '') ??
                5000;
            AppLogger.warning('EWS: сервер перегружен, пауза $msмс');
            await Future<void>.delayed(Duration(milliseconds: ms.clamp(500, 60000)));
            lastError = const ServerUnavailableException(technicalMessage: 'ErrorServerBusy');
            continue;
          }
          final fault = RegExp(r'<(?:\w+:)?faultstring[^>]*>([\s\S]*?)</(?:\w+:)?faultstring>')
                  .firstMatch(response.body)
                  ?.group(1)
                  ?.trim() ??
              RegExp(r'ResponseCode>(\w+)<').firstMatch(response.body)?.group(1) ??
              'SOAP Fault';
          throw ExchangeException(userMessage: 'Exchange: $fault');
        }

        if (response.statusCode == 503 && attempt < _maxRetries) {
          lastError = const ServerUnavailableException();
          continue;
        }

        // 502/504 от прокси — запрос мог дойти до Exchange: неидемпотентное
        // не повторяем.
        if (response.statusCode >= 500 && attempt < _maxRetries && idempotent) {
          lastError = ServerUnavailableException(technicalMessage: 'HTTP ${response.statusCode}');
          continue;
        }

        if (response.statusCode != 200) {
          throw ExchangeException(userMessage: 'Ошибка Exchange (${response.statusCode})');
        }

        // Успех — сброс rate limit
        SecurityUtils.resetAttempts(account.email);

        final xmlDoc = await EwsXmlParser.parseResponseAsync(response.body);

        // Проверяем SOAP Fault
        final faults = xmlDoc.findAllElements('Fault');
        if (faults.isNotEmpty) {
          final faultStr = faults.first.findElements('faultstring').firstOrNull?.innerText ?? 'SOAP Fault';
          throw ExchangeException(userMessage: 'Exchange: $faultStr');
        }

        return xmlDoc;
      } on InvalidCredentialsException {
        rethrow;
      } on ExchangeException {
        rethrow;
      } on SocketException catch (e) {
        if (attempt == _maxRetries || !idempotent) throw NoConnectionException(technicalMessage: '$e');
        lastError = e;
      } on TimeoutException catch (e) {
        if (attempt == _maxRetries || !idempotent) throw ConnectionTimeoutException(technicalMessage: '$e');
        lastError = e;
      } catch (e) {
        if (attempt == _maxRetries || !idempotent) rethrow;
        lastError = e is Exception ? e : Exception('$e');
      }
    }

    throw lastError ?? const NetworkException(userMessage: 'Неизвестная ошибка');
  }

  // ════════════════════════ ПОДКЛЮЧЕНИЕ ════════════════════════

  Future<NtlmClient> _getClient(AccountModel account) async {
    if (_clients.containsKey(account.id)) return _clients[account.id]!;

    // Общий ящик своего пароля не имеет: вход под учётной записью основного
    // аккаунта (её логин уже скопирован в общий ящик при добавлении). Раньше
    // пароль искался по id общего ящика — и вход не выполнялся никогда.
    final credId = account.isSharedMailbox && (account.parentAccountId ?? '').isNotEmpty
        ? account.parentAccountId!
        : account.id;
    // Exchange Online по OAuth (1.6.2): токен вместо пароля. Общий ящик —
    // токеном основного аккаунта.
    if (account.isExchangeOnlineOAuth) {
      final owner = credId == account.id ? account : account.copyWith(id: credId);
      final oauth = OAuthService(secureStorage);
      final client = NtlmClient.bearer(({bool force = false}) => oauth.validAccessToken(owner, force: force));
      _clients[account.id] = client;
      return client;
    }
    final password = await secureStorage.getAccountPassword(credId);
    if (password == null || password.isEmpty) {
      throw const InvalidCredentialsException(technicalMessage: 'Password not found');
    }

    final client = NtlmClient(
      // Имя пользователя могли не заполнить (вход по адресу) — тогда UPN.
      username: account.username.trim().isNotEmpty ? account.username.trim() : account.email,
      password: password,
      domain: account.domain ?? AppConstants.defaultDomain,
    );

    _clients[account.id] = client;
    return client;
  }

  /// Адрес EWS: сохранённый ewsUrl → сервер из настроек (имя хоста или
  /// полный URL) → Autodiscover → mail.<домен>. Раньше при пустом сервере
  /// получался адрес «https:///EWS/Exchange.asmx», а введённый целиком URL
  /// («https://mail.corp.ru/EWS/Exchange.asmx») превращался в
  /// «https://https://...».
  Future<String> _getEwsUrl(AccountModel account) async {
    final cached = _ewsUrls[account.id];
    if (cached != null) return cached;

    String? url;
    final saved = account.ewsUrl?.trim() ?? '';
    final server = (account.exchangeServer ?? '').trim();
    if (saved.isNotEmpty) {
      url = saved;
    } else if (server.isNotEmpty) {
      url = ewsUrlFromServer(server);
    } else {
      final password = await secureStorage.getAccountPassword(account.id) ?? '';
      try {
        url = await autodiscover(
          account.email,
          account.username.trim().isNotEmpty ? account.username.trim() : account.email,
          password,
          account.domain ?? AppConstants.defaultDomain,
        );
      } catch (_) {}
      if (url == null || url.isEmpty || url.contains('https:///')) {
        url = 'https://mail.${account.email.split('@').last}${AppConstants.ewsPath}';
      }
    }

    _ewsUrls[account.id] = url;
    return url;
  }

  /// «mail.corp.ru», «mail.corp.ru/», «https://mail.corp.ru» или полный
  /// адрес EWS → полный адрес EWS.
  static String ewsUrlFromServer(String server) {
    var s = server.trim();
    if (s.toLowerCase().contains('/ews/')) {
      // Только HTTPS: по http:// пароль домена ушёл бы открытым текстом.
      s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
      return 'https://$s';
    }
    s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return 'https://$s${AppConstants.ewsPath}';
  }

  /// Тест подключения
  /// Получить настройки автоответа (Out of Office) с сервера.
  Future<OofSettings?> getOofSettings(AccountModel account) async {
    try {
      final body = EwsXmlBuilder.buildGetOofSettings(account.email);
      final doc = await _soapRequest(account, body, timeoutSeconds: 20);
      final stateEl = doc.findAllElements('OofState').firstOrNull;
      final state = stateEl?.innerText ?? 'Disabled';
      String? internal;
      String? external;
      final intReply = doc.findAllElements('InternalReply').firstOrNull;
      if (intReply != null) internal = intReply.findElements('Message').firstOrNull?.innerText;
      final extReply = doc.findAllElements('ExternalReply').firstOrNull;
      if (extReply != null) external = extReply.findElements('Message').firstOrNull?.innerText;
      final duration = doc.findAllElements('Duration').firstOrNull;
      final audience = doc.findAllElements('ExternalAudience').firstOrNull?.innerText ?? 'None';
      return OofSettings(
        enabled: state != 'Disabled',
        internalReply: _oofPlain(internal ?? ''),
        externalReply: _oofPlain(external ?? ''),
        scheduled: state == 'Scheduled',
        start: DateTime.tryParse(duration?.findAllElements('StartTime').firstOrNull?.innerText ?? '')?.toLocal(),
        end: DateTime.tryParse(duration?.findAllElements('EndTime').firstOrNull?.innerText ?? '')?.toLocal(),
        externalOn: audience != 'None',
      );
    } catch (e) {
      AppLogger.warning('EWS getOofSettings: $e');
      return null;
    }
  }

  /// Текст автоответа из Outlook бывает HTML — в поле показываем текстом.
  static String _oofPlain(String s) {
    if (!s.contains('<')) return s.trim();
    return s
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Установить настройки автоответа (Out of Office) на сервере.
  Future<bool> setOofSettings(AccountModel account, {
    required bool enabled,
    DateTime? startTime,
    DateTime? endTime,
    String? internalReply,
    String? externalReply,
    bool sendToExternal = false,
  }) async {
    try {
      final body = EwsXmlBuilder.buildSetOofSettings(
        email: account.email,
        enabled: enabled,
        startTime: startTime,
        endTime: endTime,
        internalReply: internalReply,
        externalReply: externalReply,
        sendToExternal: sendToExternal,
      );
      await _soapRequest(account, body, timeoutSeconds: 20);
      AppLogger.info('EWS setOofSettings: автоответ ${enabled ? 'включён' : 'выключен'}');
      return true;
    } catch (e) {
      AppLogger.error('EWS setOofSettings: $e');
      return false;
    }
  }

  Future<bool> testConnection(AccountModel account) async {
    try {
      // GetFolder inbox — минимальный валидный EWS-запрос
      final body = EwsXmlBuilder.buildGetFolder('inbox');
      final doc = await _soapRequest(account, body, timeoutSeconds: 15);
      // Успех, если в ответе есть GetFolderResponse без ошибок
      final hasResponse = doc.findAllElements('GetFolderResponseMessage').isNotEmpty ||
          doc.findAllElements('RootFolder').isNotEmpty ||
          doc.findAllElements('Folder').isNotEmpty;
      if (!hasResponse) {
        AppLogger.warning('EWS test: ответ получен, но без ожидаемых элементов');
      }
      return true;
    } on InvalidCredentialsException {
      AppLogger.error('EWS test: неверные учётные данные (401)');
      rethrow;
    } catch (e) {
      AppLogger.error('EWS test failed', e);
      return false;
    }
  }

  /// Autodiscover. Если задан server (введён пользователем) — используем его в приоритете.
  Future<String?> autodiscover(String email, String username, String password, String domain, {String? server}) async {
    final client = NtlmClient(username: username, password: password, domain: domain);
    final emailDomain = email.split('@').last;
    var preferredServer = (server != null && server.isNotEmpty) ? server : AppConstants.defaultExchangeServer;
    preferredServer = preferredServer
        .trim()
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .split('/')
        .first;

    // 1) Прямой EWS на введённом сервере (быстрый путь — без autodiscover)
    final directEwsUrl = preferredServer.isNotEmpty
        ? 'https://$preferredServer${AppConstants.ewsPath}'
        : 'https://mail.$emailDomain${AppConstants.ewsPath}';

    final urls = [
      if (preferredServer.isNotEmpty) 'https://$preferredServer${AppConstants.autodiscoverPath}',
      'https://$emailDomain/autodiscover/autodiscover.xml',
      'https://autodiscover.$emailDomain/autodiscover/autodiscover.xml',
    ];

    final body = EwsXmlBuilder.buildAutodiscoverRequest(email);

    for (final url in urls) {
      try {
        final response = await client.post(Uri.parse(url), headers: {'Content-Type': 'text/xml; charset=utf-8'}, body: body, timeoutSeconds: 8);
        if (response.statusCode == 200) {
          final xmlDoc = EwsXmlParser.parseResponse(response.body);
          final ewsUrl = EwsXmlParser.parseAutodiscoverResponse(xmlDoc);
          if (ewsUrl != null && ewsUrl.isNotEmpty) return ewsUrl;
        }
      } catch (_) {
        continue;
      }
    }

    // Fallback — прямой EWS на введённом сервере
    return directEwsUrl;
  }

  // ════════════════════ СЕРВЕРНЫЕ ПРАВИЛА (INBOX RULES) ════════════════════

  /// Прочитать серверные правила: возвращает `[{id, name, enabled, priority}]`.
  /// Полный разбор условий/действий не нужен — на клиенте правило хранится в
  /// своей модели, серверная копия опознаётся по RuleId.
  Future<List<Map<String, dynamic>>> getInboxRules(AccountModel account) async {
    try {
      final doc = await _soapRequest(account, EwsXmlBuilder.buildGetInboxRules());
      final out = <Map<String, dynamic>>[];
      for (final r in doc.findAllElements('Rule')) {
        final id = r.findElements('RuleId').firstOrNull?.innerText.trim();
        if (id == null || id.isEmpty) continue;
        out.add({
          'id': id,
          'name': r.findElements('DisplayName').firstOrNull?.innerText ?? '',
          'enabled': (r.findElements('IsEnabled').firstOrNull?.innerText ?? 'true') == 'true',
          'priority': int.tryParse(r.findElements('Priority').firstOrNull?.innerText ?? '') ?? 1,
        });
      }
      return out;
    } catch (e) {
      AppLogger.warning('EWS GetInboxRules: $e');
      return const [];
    }
  }

  /// Создать серверное правило из клиентской модели. Возвращает RuleId или null.
  /// EWS не возвращает RuleId при Create, поэтому после создания перечитываем
  /// список и находим правило по имени (имена уникализируются на стороне UI).
  Future<String?> createInboxRule(AccountModel account, AutoRule rule) async {
    if (!rule.isServerCompatible) return null;
    try {
      await _soapRequest(
        account,
        EwsXmlBuilder.buildUpdateInboxRules(
          operation: 'Create',
          displayName: rule.name,
          priority: rule.priority <= 0 ? 1 : rule.priority,
          isEnabled: rule.isEnabled,
          conditionsXml: _ruleConditionsXml(rule),
          actionsXml: _ruleActionsXml(rule),
        ),
      );
      final rules = await getInboxRules(account);
      final match = rules.where((r) => r['name'] == rule.name).toList();
      return match.isEmpty ? null : match.last['id'] as String;
    } catch (e) {
      AppLogger.warning('EWS CreateInboxRule: $e');
      return null;
    }
  }

  /// Обновить серверное правило (нужен `rule.serverRuleId`). true — успех.
  Future<bool> updateInboxRule(AccountModel account, AutoRule rule) async {
    final id = rule.serverRuleId;
    if (id == null || id.isEmpty || !rule.isServerCompatible) return false;
    try {
      await _soapRequest(
        account,
        EwsXmlBuilder.buildUpdateInboxRules(
          operation: 'Set',
          ruleId: id,
          displayName: rule.name,
          priority: rule.priority <= 0 ? 1 : rule.priority,
          isEnabled: rule.isEnabled,
          conditionsXml: _ruleConditionsXml(rule),
          actionsXml: _ruleActionsXml(rule),
        ),
      );
      return true;
    } catch (e) {
      AppLogger.warning('EWS SetInboxRule: $e');
      return false;
    }
  }

  /// Удалить серверное правило по RuleId. true — успех (или уже отсутствует).
  Future<bool> deleteInboxRule(AccountModel account, String ruleId) async {
    if (ruleId.isEmpty) return true;
    try {
      await _soapRequest(account,
          EwsXmlBuilder.buildUpdateInboxRules(operation: 'Delete', ruleId: ruleId));
      return true;
    } catch (e) {
      AppLogger.warning('EWS DeleteInboxRule: $e');
      return false;
    }
  }

  /// Условия правила → EWS XML. Элементы — строго в порядке types.xsd
  /// (RulePredicatesType): ContainsBodyStrings, ContainsSenderStrings,
  /// ContainsSubjectStrings, FromAddresses, HasAttachments, Importance,
  /// WithinSizeRange. Раньше порядок следовал порядку условий в правиле —
  /// и сервер отвергал правило по схеме.
  String _ruleConditionsXml(AutoRule rule) {
    final senderContains = <String>[];
    final fromAddresses = <String>[];
    final subjectValues = <String>[];
    final bodyValues = <String>[];
    var attachments = false;
    var high = false;
    var minSize = 0;
    for (final c in rule.conditions) {
      switch (c.type) {
        case RuleConditionType.senderContains:
          if (c.value.isNotEmpty) senderContains.add(c.value);
          break;
        case RuleConditionType.senderEquals:
          if (c.value.isNotEmpty) fromAddresses.add(c.value);
          break;
        case RuleConditionType.subjectContains:
          if (c.value.isNotEmpty) subjectValues.add(c.value);
          break;
        case RuleConditionType.bodyContains:
          if (c.value.isNotEmpty) bodyValues.add(c.value);
          break;
        case RuleConditionType.priorityHigh:
          high = true;
          break;
        case RuleConditionType.hasAttachments:
          attachments = true;
          break;
        case RuleConditionType.sizeGreaterThan:
          final n = int.tryParse(c.value) ?? 0;
          if (n > minSize) minSize = n;
          break;
        case RuleConditionType.recipientCount:
          break; // нет в EWS — сюда не попадёт (isServerCompatible это отсекает)
      }
    }
    String strings(String tag, List<String> v) =>
        v.isEmpty ? '' : '          <t:$tag>${v.map(EwsXmlBuilder.ruleStringItem).join()}</t:$tag>\n';
    final b = StringBuffer()
      ..write(strings('ContainsBodyStrings', bodyValues))
      ..write(strings('ContainsSenderStrings', senderContains))
      ..write(strings('ContainsSubjectStrings', subjectValues));
    if (fromAddresses.isNotEmpty) {
      b.write('          <t:FromAddresses>');
      for (final v in fromAddresses) {
        b.write('<t:Address><t:EmailAddress>${_escapeXmlLocal(v)}</t:EmailAddress></t:Address>');
      }
      b.write('</t:FromAddresses>\n');
    }
    if (attachments) b.write('          <t:HasAttachments>true</t:HasAttachments>\n');
    if (high) b.write('          <t:Importance>High</t:Importance>\n');
    if (minSize > 0) {
      // Размер — в килобайтах (MinimumSize, xs:int).
      b.write('          <t:WithinSizeRange><t:MinimumSize>$minSize</t:MinimumSize></t:WithinSizeRange>\n');
    }
    return b.toString();
  }

  /// Действия правила → EWS XML в порядке types.xsd (RuleActionsType):
  /// AssignCategories, Delete, ForwardToRecipients, MarkAsRead, MoveToFolder,
  /// StopProcessingRules. «Удалить» — элемент Delete (DeleteMessage в схеме
  /// нет — правило с ним не создавалось).
  String _ruleActionsXml(AutoRule rule) {
    final categories = <String>[];
    final forwards = <String>[];
    var delete = false;
    var markRead = false;
    String? moveTo;
    for (final a in rule.actions) {
      switch (a.type) {
        case RuleActionType.moveTo:
        case RuleActionType.moveToFolder:
          if (a.value.isNotEmpty) moveTo ??= a.value;
          break;
        case RuleActionType.markAsRead:
          markRead = true;
          break;
        case RuleActionType.setCategory:
          if (a.value.isNotEmpty) categories.add(a.value);
          break;
        case RuleActionType.forwardTo:
          if (a.value.isNotEmpty) forwards.add(a.value);
          break;
        case RuleActionType.delete:
          delete = true;
          break;
        default:
          break; // прочие действия — только клиентские (isServerCompatible отсекает)
      }
    }
    final b = StringBuffer();
    if (categories.isNotEmpty) {
      b.write('          <t:AssignCategories>'
          '${categories.map(EwsXmlBuilder.ruleStringItem).join()}</t:AssignCategories>\n');
    }
    if (delete) b.write('          <t:Delete>true</t:Delete>\n');
    if (forwards.isNotEmpty) {
      b.write('          <t:ForwardToRecipients>');
      for (final f in forwards) {
        b.write('<t:Address><t:EmailAddress>${_escapeXmlLocal(f)}</t:EmailAddress></t:Address>');
      }
      b.write('</t:ForwardToRecipients>\n');
    }
    if (markRead) b.write('          <t:MarkAsRead>true</t:MarkAsRead>\n');
    if (moveTo != null) {
      b.write('          <t:MoveToFolder>${EwsXmlBuilder.ruleFolderId(moveTo)}</t:MoveToFolder>\n');
    }
    if (rule.stopProcessing) {
      b.write('          <t:StopProcessingRules>true</t:StopProcessingRules>\n');
    }
    return b.toString();
  }

  static String _escapeXmlLocal(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ════════════════════ УВЕДОМЛЕНИЯ (PUSH) ════════════════════

  /// Подписаться на события папок (streaming). Возвращает SubscriptionId.
  ///
  /// EWS Streaming Notifications — аналог IMAP IDLE / EAS Ping для Exchange
  /// Web Services: сервер сам сообщает об изменениях, опрос не нужен.
  Future<String?> subscribeStreaming(AccountModel account, List<String> folderIds) async {
    if (folderIds.isEmpty) return null;
    try {
      final doc = await _soapRequest(
          account, EwsXmlBuilder.buildSubscribeStreaming(folderIds));
      final id = doc.findAllElements('SubscriptionId').firstOrNull?.innerText.trim();
      if (id == null || id.isEmpty) {
        AppLogger.warning('EWS Subscribe: сервер не вернул SubscriptionId');
        return null;
      }
      AppLogger.info('EWS Subscribe: подписка на ${folderIds.length} папок');
      return id;
    } catch (e) {
      AppLogger.warning('EWS Subscribe: $e');
      return null;
    }
  }

  /// Снять подписку (best-effort — при остановке push).
  Future<void> unsubscribe(AccountModel account, String subscriptionId) async {
    try {
      await _soapRequest(account, EwsXmlBuilder.buildUnsubscribe(subscriptionId));
    } catch (e) {
      AppLogger.debug('EWS Unsubscribe: $e');
    }
  }

  /// Поток идентификаторов папок, в которых произошли изменения.
  ///
  /// Держит одно долгоживущее соединение `GetStreamingEvents`
  /// (`connectionTimeoutMinutes`, максимум 30 по протоколу). Сервер шлёт
  /// последовательность SOAP-конвертов: их приходится собирать из чанков и
  /// разбирать по мере поступления — поэтому используется потоковый POST.
  /// Поток завершается, когда сервер закрывает соединение (это нормально —
  /// вызывающий переподписывается).
  Stream<Set<String>> streamNotifications(
    AccountModel account,
    String subscriptionId, {
    int connectionTimeoutMinutes = 30,
  }) async* {
    final client = await _getClient(account);
    final url = await _getEwsUrl(account);
    final envelope = EwsXmlBuilder.wrapInEnvelope(
        EwsXmlBuilder.buildGetStreamingEvents(subscriptionId,
            connectionTimeoutMinutes: connectionTimeoutMinutes));

    final resp = await client.postStreaming(
      Uri.parse(url),
      headers: {'Content-Type': 'text/xml; charset=utf-8', 'Accept': 'text/xml'},
      body: envelope,
    );
    if (resp.statusCode != 200) {
      AppLogger.warning('EWS GetStreamingEvents: HTTP ${resp.statusCode}');
      return;
    }

    // Ответ — поток из нескольких SOAP-конвертов подряд. Накапливаем чанки и
    // выделяем каждый ЗАВЕРШЁННЫЙ конверт (префикс namespace может быть любым).
    final endTag = RegExp(r'</(?:\w+:)?Envelope>');
    var buf = '';
    // Сторож: Exchange присылает в соединение служебные события не реже раза
    // в несколько минут. Тишина дольше 5 минут — соединение оборвалось без
    // закрытия (смена сети, NAT, прокси): завершаем поток, вызывающий
    // переподпишется. Раньше такой поток «висел» до перезапуска приложения,
    // и новые письма не приходили.
    final guarded = resp.stream.timeout(const Duration(minutes: 5), onTimeout: (sink) {
      AppLogger.info('EWS push: тишина 5 мин — переподключение');
      sink.close();
    });
    await for (final chunk in guarded) {
      buf += chunk;
      var m = endTag.firstMatch(buf);
      while (m != null) {
        final piece = buf.substring(0, m.end);
        buf = buf.substring(m.end);
        final folders = _parseNotificationFolders(piece);
        if (folders.isNotEmpty) yield folders;
        m = endTag.firstMatch(buf);
      }
    }
  }

  /// Достаёт из конверта уведомления идентификаторы затронутых папок.
  /// StatusEvent (keep-alive) и ConnectionStatus игнорируются.
  Set<String> _parseNotificationFolders(String envelopeXml) {
    try {
      final doc = EwsXmlParser.parseResponse(envelopeXml);
      final result = <String>{};
      for (final n in doc.findAllElements('Notification')) {
        for (final ev in n.childElements) {
          if (ev.name.local == 'StatusEvent') continue; // keep-alive
          final fid = ev.findElements('ParentFolderId').firstOrNull
              ?.getAttribute('Id');
          if (fid != null && fid.isNotEmpty) result.add(fid);
        }
      }
      return result;
    } catch (e) {
      AppLogger.debug('EWS notification parse: $e');
      return const {};
    }
  }

  // ════════════════════════ ПАПКИ ════════════════════════

  /// Получить папки (дедуплицированный запрос)
  /// Установить серверные категории Outlook (item:Categories).
  Future<bool> setCategories(AccountModel account, {required String itemId, required List<String> categories}) async {
    final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildSetCategories(itemId, categories));
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Создать папку на сервере. Возвращает true при успехе (id подтянется синком).
  Future<bool> createFolder(AccountModel account, String displayName, {String parentId = 'msgfolderroot'}) async {
    final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildCreateFolder(displayName, parentId: parentId));
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Переименовать папку на сервере.
  Future<bool> renameFolder(AccountModel account, {required String folderId, required String newName}) async {
    final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildRenameFolder(folderId, newName));
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Переместить папку (в другую или в корень ящика).
  Future<bool> moveFolder(AccountModel account, {required String folderId, String toParentId = 'msgfolderroot'}) async {
    final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildMoveFolder(folderId, toParentId: toParentId));
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Удалить папку на сервере (в «Удалённые»).
  Future<bool> deleteFolder(AccountModel account, {required String folderId}) async {
    final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildDeleteFolder(folderId));
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Занятость участников (EWS MergedFreeBusy). Времена в UTC.
  Future<FreeBusyView> getFreeBusy(AccountModel account,
      {required List<String> emails, required DateTime startLocal, required DateTime endLocal,
      int intervalMinutes = 30}) async {
    final strings = await getFreeBusyStrings(account,
        emails: emails, startLocal: startLocal, endLocal: endLocal, intervalMinutes: intervalMinutes);
    // Объединённый вид по всем участникам. Сервер отдаёт <MergedFreeBusy> на
    // КАЖДОГО участника; раньше бралась строка только первого (1.6.49).
    final merged = FreeBusyView.mergeStrings(strings.values);
    return FreeBusyView(
      startLocal: startLocal,
      intervalMinutes: intervalMinutes,
      statuses: merged.isEmpty ? const [] : FreeBusyView.parseMerged(merged),
    );
  }

  /// Занятость каждого участника отдельно: адрес (нижний регистр) → строка
  /// статусов по интервалам. Ответы сервера — в порядке запроса.
  Future<Map<String, String>> getFreeBusyStrings(AccountModel account,
      {required List<String> emails, required DateTime startLocal, required DateTime endLocal,
      int intervalMinutes = 30}) async {
    if (emails.isEmpty) return const {};
    final body = EwsXmlBuilder.buildGetUserAvailability(emails, startLocal.toUtc(), endLocal.toUtc(), intervalMinutes);
    final doc = await _soapRequest(account, body);
    final responses =
        doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'FreeBusyResponse').toList();
    final out = <String, String>{};
    for (var i = 0; i < responses.length && i < emails.length; i++) {
      final merged = responses[i]
              .descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'MergedFreeBusy')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      if (merged.isNotEmpty) out[emails[i].trim().toLowerCase()] = merged;
    }
    return out;
  }

  Future<List<FolderModel>> getFolders(AccountModel account) async {
    return _dedup.deduplicate('getFolders_${account.id}', () async {
      // Архив Exchange (1.6.49) — папки под корнем архива; во «Всю почту»
      // они не входят (и уведомлений о «новых» старых письмах не дают).
      final archive = account.isOnlineArchive;
      final body = EwsXmlBuilder.buildFindFolder(
          sharedMailbox: account.sharedMailboxEmail, root: archive ? 'archivemsgfolderroot' : 'msgfolderroot');
      final xmlDoc = await _soapRequest(account, body);
      final folders = EwsXmlParser.parseFolders(xmlDoc, account.id);
      if (!archive) {
        // Типы стандартных папок — по id от сервера, на любом языке ящика
        // (1.7.2+107); не получилось — по названиям, как раньше.
        final byId = await _systemFolderIds(account);
        return byId == null ? folders : EwsXmlParser.applyDistinguished(folders, byId);
      }
      return [
        for (final f in folders)
          FolderModel(
            id: f.id,
            accountId: f.accountId,
            parentId: f.parentId,
            displayName: f.displayName,
            type: f.type,
            serverPath: f.serverPath,
            unreadCount: f.unreadCount,
            totalCount: f.totalCount,
            showInUnified: false,
            isFavorite: f.isFavorite,
            sortOrder: f.sortOrder,
            // Синхронизируются входящие и отправленные архива, остальное —
            // по выбору («Синхронизация папок»): архив бывает большим.
            isSynced: f.type == FolderType.inbox || f.type == FolderType.sent,
            iconName: f.iconName,
          ),
      ];
    });
  }

  /// Стандартные папки ящика: id → тип (1.7.2+107). Id стандартных папок у
  /// ящика не меняются — запрос один раз за запуск приложения на ящик.
  /// null — сервер не ответил (типы останутся по названиям).
  final Map<String, Map<String, FolderType>> _systemIds = {};

  Future<Map<String, FolderType>?> _systemFolderIds(AccountModel account) async {
    final cached = _systemIds[account.id];
    if (cached != null) return cached;
    final names = EwsXmlParser.distinguishedTypes.keys.toList();
    try {
      final doc = await _soapRequest(
          account,
          // Общий ящик — с его адресом, как и FindFolder в getFolders.
          EwsDirectoryExtras.buildGetDistinguishedFolders(names, mailbox: account.sharedMailboxEmail),
          timeoutSeconds: 20);
      final ids = EwsDirectoryExtras.parseFolderIds(doc);
      final out = <String, FolderType>{};
      for (var i = 0; i < names.length && i < ids.length; i++) {
        final id = ids[i];
        if (id != null) out[id] = EwsXmlParser.distinguishedTypes[names[i]]!;
      }
      if (out.isEmpty) return null;
      _systemIds[account.id] = out;
      AppLogger.info('EWS: стандартные папки по id — ${out.length} из ${names.length}');
      return out;
    } on InvalidCredentialsException {
      rethrow;
    } catch (e) {
      AppLogger.warning('EWS: стандартные папки не получены ($e) — типы по названиям');
      return null;
    }
  }

  /// Открывается ли стандартная папка [distinguished] ящика [mailbox]
  /// (1.6.49: проверка доступа к общему ящику — почта, календарь). Нет
  /// доступа — false; сбой связи — исключение.
  Future<bool> canOpenFolder(AccountModel account, String distinguished, {String? mailbox}) async {
    try {
      final doc = await _soapRequest(
          account, EwsDirectoryExtras.buildGetDistinguishedFolder(distinguished, mailbox: mailbox),
          timeoutSeconds: 20);
      return EwsDirectoryExtras.parseFolderId(doc) != null;
    } on InvalidCredentialsException {
      rethrow;
    } on ServerUnavailableException {
      rethrow;
    } on ExchangeException {
      return false;
    }
  }

  // ════════════════════════ ПИСЬМА ════════════════════════

  /// Получить письма с учётом fetchMode
  Future<List<EmailModel>> getEmails(
    AccountModel account, {
    required String folderId,
    int offset = 0,
    int count = 50,
    EmailFetchMode fetchMode = EmailFetchMode.noAttachments,
  }) async {
    return _dedup.deduplicate('getEmails_${account.id}_${folderId}_$offset', () async {
      // Общий (делегированный) ящик: запрос должен адресоваться ЕГО папке,
      // иначе вернутся письма собственного ящика. Механизм уже был
      // (buildFindItemDelegated), но синхронизация им не пользовалась —
      // добавленный общий ящик просто не наполнялся письмами.
      final shared = account.sharedMailboxEmail;
      final body = (shared != null && shared.isNotEmpty)
          ? EwsXmlBuilder.buildFindItemDelegated(
              delegateEmail: shared,
              folderId: folderId,
              offset: offset,
              maxCount: count,
            )
          : EwsXmlBuilder.buildFindItem(
              folderId: folderId,
              offset: offset,
              maxCount: count,
            );

      final xmlDoc = await _soapRequest(account, body, timeoutSeconds: AppConstants.ewsTimeoutSeconds);
      final emails = EwsXmlParser.parseEmails(xmlDoc, account.id, folderId);

      // Санитизация HTML — пачкой в отдельном изоляте (разбор DOM сотни писем
      // на главном изоляте подвешивал интерфейс во время синхронизации).
      final cleaned = await MailBodyProcessor.sanitizeAll([for (final e in emails) e.bodyHtml]);
      return [
        for (var i = 0; i < emails.length; i++)
          cleaned[i] == null ? emails[i] : emails[i].copyWith(bodyHtml: cleaned[i]),
      ];
    });
  }

  /// Получить детали письма (полное тело + вложения metadata)
  Future<EmailModel> getEmailDetail(AccountModel account, {required String emailId}) async {
    return _dedup.deduplicate('getDetail_${account.id}_$emailId', () async {
      final body = EwsXmlBuilder.buildGetItem(emailId);
      final xmlDoc = await _soapRequest(account, body);
      var email = EwsXmlParser.parseEmailDetail(xmlDoc, account.id);

      // Санитизация HTML — со стилями письма (1.5.9, см. sanitizeAll).
      if (email.bodyHtml != null) {
        email = email.copyWith(
            bodyHtml: await MailBodyProcessor.heavy(email.bodyHtml!, HtmlSanitizer.sanitizeKeepingStyles));
      }

      return email;
    });
  }

  /// Отправить письмо
  Future<String> sendEmail(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    bool isHtml = true,
    String? inReplyTo,
    bool saveSentCopy = true,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    /// S/MIME: обработка готового письма (подпись, шифрование) — тогда письмо
    /// собирается здесь и уходит в Exchange готовым (MimeContent).
    Future<Uint8List> Function(Uint8List mime)? mimeTransform,
    /// «Отправить как / от имени» (адрес отправки, 1.6.27): элемент From;
    /// копия — в свои «Отправленные». Для общего ящика — его адрес.
    EmailAddress? from,
  }) async {
    final fromAddr = from?.email;
    final sanitizedBody =
        isHtml ? await MailBodyProcessor.heavy(bodyHtml, SecurityUtils.sanitizeHtml) : bodyHtml;
    final withBytes = attachments.where((a) => a.bytes.isNotEmpty).toList();

    if (mimeTransform != null) {
      final shared = account.sharedMailboxEmail;
      final message = ImapService.buildOutgoingMessage(
        fromName: from == null ? account.displayName : (from.displayName ?? ''),
        fromEmail: (shared != null && shared.isNotEmpty) ? shared : (fromAddr ?? account.email),
        to: to,
        cc: cc,
        subject: subject,
        bodyHtml: sanitizedBody,
        inReplyTo: inReplyTo,
        attachments: withBytes,
        importance: importance,
        sensitivity: sensitivity,
      );
      var raw = Uint8List.fromList(utf8.encode(message.renderMessage()));
      raw = SmimeMime.withoutHeaders(raw, const {'bcc'});
      raw = await mimeTransform(raw);
      final xmlDoc = await _soapRequest(
          account,
          EwsXmlBuilder.buildCreateItemFromMime(
            mimeBase64: base64.encode(raw),
            bcc: bcc,
            encrypted: MailLabel.decode(sensitivity).smimeEncrypt,
            saveSentCopy: saveSentCopy,
            sharedMailbox: shared,
          ),
          timeoutSeconds: withBytes.isEmpty ? 30 : 300,
          idempotent: false);
      _ensureSuccess(xmlDoc, 'send');
      return EwsXmlParser.parseCreateItemResponse(xmlDoc) ?? '';
    }

    // Без вложений — одним запросом (SendAndSaveCopy).
    if (withBytes.isEmpty) {
      // Для общего ящика копия должна лечь в ЕГО «Отправленные», иначе
      // коллеги не увидят, что письмо уже ушло, и напишут повторно.
      final body = EwsXmlBuilder.buildCreateAndSendItem(
        sharedMailbox: account.sharedMailboxEmail,
        fromAddress: fromAddr,
        to: to, cc: cc, bcc: bcc,
        subject: subject,
        bodyContent: sanitizedBody,
        isHtml: isHtml,
        inReplyTo: inReplyTo,
        saveSentCopy: saveSentCopy,
        importance: importance,
        sensitivity: sensitivity,
      );
      final xmlDoc = await _soapRequest(account, body, idempotent: false);
      // Отказ сервера (получатель не найден, превышен размер, нет прав на
      // отправку от имени) приходит HTTP 200 с ResponseClass="Error". Раньше
      // это считалось успехом, и неотправленное письмо пропадало из очереди.
      _ensureSuccess(xmlDoc, 'send');
      return EwsXmlParser.parseCreateItemResponse(xmlDoc) ?? '';
    }

    // С вложениями EWS требует поток: черновик → CreateAttachment → SendItem.
    final draftDoc = await _soapRequest(
        account,
        EwsXmlBuilder.buildCreateDraft(
          to: to, cc: cc, bcc: bcc, subject: subject,
          bodyContent: sanitizedBody, isHtml: isHtml, inReplyTo: inReplyTo,
          importance: importance,
          sensitivity: sensitivity,
          sharedMailbox: account.sharedMailboxEmail,
          fromAddress: fromAddr,
        ),
        idempotent: false);
    final itemEl = draftDoc.findAllElements('ItemId').firstOrNull;
    final itemId = itemEl?.getAttribute('Id');
    var changeKey = itemEl?.getAttribute('ChangeKey');
    if (itemId == null || changeKey == null) {
      throw Exception('EWS: не удалось создать черновик для вложений');
    }

    final encoded = [
      for (final a in withBytes)
        (name: a.name, contentType: a.contentType, base64: base64.encode(a.bytes)),
    ];
    // Вложения уходят одним запросом: на мобильной сети 20+ МБ за 30 секунд
    // (обычный таймаут) не успевали — отправка падала по таймауту.
    final attDoc = await _soapRequest(
        account, EwsXmlBuilder.buildCreateAttachments(itemId, changeKey, encoded),
        timeoutSeconds: 300, idempotent: false);
    _ensureSuccess(attDoc, 'attach');
    final rootCk = attDoc.findAllElements('AttachmentId').firstOrNull?.getAttribute('RootItemChangeKey');
    if (rootCk != null) changeKey = rootCk;

    _ensureSuccess(
        await _soapRequest(
            account,
            EwsXmlBuilder.buildSendItem(itemId, changeKey,
                saveSentCopy: saveSentCopy, sharedMailbox: account.sharedMailboxEmail),
            idempotent: false),
        'send');
    return itemId;
  }

  /// Исходный MIME письма (GetItem IncludeMimeContent) — для проверки
  /// подписи S/MIME. null — сервер не отдал.
  Future<Uint8List?> getMimeContent(AccountModel account, String itemId) async {
    final doc = await _soapRequest(account, EwsXmlBuilder.buildGetItemMime(itemId), timeoutSeconds: 120);
    _ensureSuccess(doc, 'mime');
    final b64 = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'MimeContent')
        .firstOrNull
        ?.innerText;
    if (b64 == null || b64.trim().isEmpty) return null;
    return base64.decode(b64.replaceAll(RegExp(r'\s'), ''));
  }

  /// Проверить ответ операции: ResponseClass="Error" во ВСЕХ сообщениях
  /// ответа — исключение с текстом сервера. Частичный успех (часть
  /// элементов пакета обработана) ошибкой не считается.
  void _ensureSuccess(XmlDocument doc, String op, {bool okIfNotFound = false}) {
    final msgs = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.endsWith('ResponseMessage') && e.getAttribute('ResponseClass') != null)
        .toList();
    if (msgs.isEmpty) return;
    if (msgs.any((m) => m.getAttribute('ResponseClass') != 'Error')) return;
    final first = msgs.first;
    final code = first.findElements('ResponseCode').firstOrNull?.innerText.trim() ?? '';
    if (okIfNotFound && code == 'ErrorItemNotFound') return;
    final text = first.findElements('MessageText').firstOrNull?.innerText.trim() ?? code;
    AppLogger.warning('EWS $op: $code $text');
    throw ExchangeException(userMessage: 'Exchange: $text', technicalMessage: '$op: $code');
  }

  /// Пометить прочитанным
  Future<void> markAsRead(AccountModel account, {required String emailId, required bool isRead}) async {
    final body = EwsXmlBuilder.buildUpdateItemReadState(emailId, isRead);
    _ensureSuccess(await _soapRequest(account, body), 'markAsRead');
  }

  /// Отправить уведомление о прочтении (read receipt) как обычное письмо-подтверждение
  Future<void> sendReadReceipt(
    AccountModel account, {
    required String originalMessageId,
    required String toEmail,
    required String subject,
  }) async {
    final receiptSubject = 'Прочитано: $subject';
    final receiptBody = '<p>Ваше сообщение было прочитано получателем '
        '${account.email}.</p>'
        '<p style="color:#888;font-size:12px;">In-Reply-To: $originalMessageId</p>';
    await sendEmail(
      account,
      to: [EmailAddress(email: toEmail)],
      subject: receiptSubject,
      bodyHtml: receiptBody,
      isHtml: true,
      inReplyTo: originalMessageId,
      saveSentCopy: false,
    );
  }

  /// Важность письма на сервере (High / Normal / Low).
  Future<void> setImportance(AccountModel account, {required String emailId, required String importance}) async {
    final body = EwsXmlBuilder.buildUpdateItemImportance(emailId, importance);
    _ensureSuccess(await _soapRequest(account, body), 'importance');
  }

  /// Пометить флагом
  Future<void> flagEmail(AccountModel account, {required String emailId, required bool isFlagged}) async {
    final body = EwsXmlBuilder.buildUpdateItemFlag(emailId, isFlagged);
    _ensureSuccess(await _soapRequest(account, body), 'flag');
  }

  /// Переместить
  /// Переместить письмо. Возвращает НОВЫЙ ItemId: в Exchange у перемещённого
  /// элемента идентификатор меняется, и действия по старому id после
  /// переноса (например, удаление) сервер считал бы «не найдено».
  Future<String?> moveEmail(AccountModel account, {required String emailId, required String targetFolderId}) async {
    final body = EwsXmlBuilder.buildMoveItem(emailId, targetFolderId);
    final doc = await _soapRequest(account, body);
    _ensureSuccess(doc, 'move');
    final id = doc.findAllElements('ItemId').firstOrNull?.getAttribute('Id');
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Удалить
  Future<void> deleteEmail(AccountModel account, {required String emailId, bool hardDelete = false}) async {
    final body = EwsXmlBuilder.buildDeleteItem(emailId, hardDelete: hardDelete);
    // Письма уже нет на сервере (удалили с другого устройства) — цель
    // достигнута, иначе офлайн-очередь повторяла бы операцию бесконечно.
    _ensureSuccess(await _soapRequest(account, body), 'delete', okIfNotFound: true);
  }

  /// Ответ на приглашение-встречу. response: 'accept'|'tentative'|'decline'.
  /// [send] = false — «Не отправлять ответ», [comment] — текст ответа,
  /// [proposedStart]/[proposedEnd] — «Предложить новое время» (для «Под
  /// вопросом» и «Отклонить», как в Outlook). Результат: успех и принял ли
  /// сервер предложенное время.
  Future<({bool ok, bool proposed})> respondToMeeting(
    AccountModel account, {
    required String itemId,
    required String response,
    bool send = true,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
  }) async {
    String element;
    switch (response) {
      case 'accept': element = 'AcceptItem'; break;
      case 'tentative': element = 'TentativelyAcceptItem'; break;
      default: element = 'DeclineItem';
    }
    final propose = send && response != 'accept' && proposedStart != null && proposedEnd != null;
    Future<XmlDocument> run(bool withProposal) => _soapRequest(
        account,
        EwsXmlBuilder.buildMeetingResponse(itemId, element,
            send: send,
            comment: comment,
            proposedStart: withProposal ? proposedStart : null,
            proposedEnd: withProposal ? proposedEnd : null),
        idempotent: false);

    XmlDocument doc;
    var proposed = propose;
    try {
      doc = await run(propose);
      if (propose && !EwsXmlParser.parseResponseSuccess(doc)) {
        proposed = false;
        doc = await run(false);
      }
    } catch (e) {
      // ProposedStart/End — схема Exchange 2013: старый сервер отвергает
      // запрос целиком. Время уже есть в тексте ответа — повторяем без него.
      if (!propose) rethrow;
      AppLogger.warning('EWS: предложение нового времени не принято ($e) — ответ без него');
      proposed = false;
      doc = await run(false);
    }
    final ok = EwsXmlParser.parseResponseSuccess(doc);
    if (ok && !send) {
      // «Не отправлять ответ»: встреча в календаре отмечена, неотправленный
      // ответ остался в «Черновиках» — убираем его.
      for (final id in doc.findAllElements('ItemId').map((e) => e.getAttribute('Id')).whereType<String>().where((id) => id != itemId).toSet()) {
        try {
          await _soapRequest(account, EwsXmlBuilder.buildDeleteItem(id, hardDelete: true));
        } catch (e) {
          AppLogger.debug('EWS: черновик ответа на приглашение не удалён: $e');
        }
      }
    }
    return (ok: ok, proposed: proposed);
  }

  /// Поиск
  /// Поиск. Без папки — по ВСЕМ почтовым папкам ящика, включая свои
  /// (FindItem не обходит подпапки сам — список папок берётся FindFolder
  /// Deep и передаётся целиком, частями по 100).
  Future<List<EmailModel>> searchEmails(AccountModel account, {required String query, String? folderId, int maxResults = 50}) async {
    if (folderId != null) {
      final body = EwsXmlBuilder.buildSearchItems(
          query: query, folderId: folderId, maxResults: maxResults,
          sharedMailbox: account.sharedMailboxEmail);
      final xmlDoc = await _soapRequest(account, body);
      return EwsXmlParser.parseEmails(xmlDoc, account.id, folderId);
    }
    List<String> ids;
    try {
      ids = await _mailFolderIds(account);
    } catch (e) {
      AppLogger.debug('EWS поиск: список папок не получен — основные папки ($e)');
      ids = const [];
    }
    if (ids.isEmpty) {
      final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildSearchItems(
          query: query, maxResults: maxResults, sharedMailbox: account.sharedMailboxEmail));
      return EwsXmlParser.parseEmails(xmlDoc, account.id, 'search');
    }
    final out = <EmailModel>[];
    for (var i = 0; i < ids.length; i += 100) {
      final part = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final xmlDoc = await _soapRequest(account, EwsXmlBuilder.buildSearchItems(
          query: query, maxResults: maxResults, folderIds: part));
      out.addAll(EwsXmlParser.parseEmails(xmlDoc, account.id, 'search'));
    }
    out.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return out.length > maxResults ? out.sublist(0, maxResults) : out;
  }

  /// Почтовые папки ящика (FolderClass IPF.Note), кэш на 10 минут.
  final Map<String, ({DateTime at, List<String> ids})> _mailFolderCache = {};
  Future<List<String>> _mailFolderIds(AccountModel account) async {
    final c = _mailFolderCache[account.id];
    if (c != null && DateTime.now().difference(c.at) < const Duration(minutes: 10)) return c.ids;
    // Поиск в архиве Exchange (1.6.49) — по папкам архива.
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildFindFolder(
            sharedMailbox: account.sharedMailboxEmail,
            root: account.isOnlineArchive ? 'archivemsgfolderroot' : 'msgfolderroot'));
    final ids = <String>[];
    for (final f in doc.findAllElements('Folder')) {
      final cls = f.findElements('FolderClass').firstOrNull?.innerText ?? '';
      if (cls.isNotEmpty && !cls.startsWith('IPF.Note')) continue;
      final id = f.findElements('FolderId').firstOrNull?.getAttribute('Id');
      if (id != null) ids.add(id);
    }
    _mailFolderCache[account.id] = (at: DateTime.now(), ids: ids);
    return ids;
  }

  // ════════════════════════ КОНТАКТЫ ════════════════════════

  /// Поиск в GAL
  /// Подсказки Exchange для адресатов (MailTips, 1.6.49): автоответ,
  /// переполненный ящик, большая рассылка.
  Future<List<MailTip>> getMailTips(AccountModel account,
      {required String sender, required List<String> recipients}) async {
    final doc = await _soapRequest(account, EwsMailTips.buildRequest(sender, recipients), timeoutSeconds: 15);
    return EwsMailTips.parse(doc);
  }

  // ─────────── Каталог: фото, переговорные, архив (1.6.49) ───────────

  /// Фото человека в высоком качестве (Exchange 2013+); null — фото нет.
  Future<Uint8List?> getUserPhoto(AccountModel account, String email,
      {String size = EwsDirectoryExtras.photoSize}) async {
    final doc = await _soapRequest(account, EwsDirectoryExtras.buildGetUserPhoto(email, size: size),
        timeoutSeconds: 20);
    return EwsDirectoryExtras.parseUserPhoto(doc);
  }

  /// Списки переговорных организации (здания, этажи).
  Future<List<DirectoryRoom>> getRoomLists(AccountModel account) async =>
      EwsDirectoryExtras.parseRoomLists(
          await _soapRequest(account, EwsDirectoryExtras.buildGetRoomLists(), timeoutSeconds: 20));

  /// Переговорные одного списка.
  Future<List<DirectoryRoom>> getRooms(AccountModel account, String roomListEmail) async =>
      EwsDirectoryExtras.parseRooms(
          await _soapRequest(account, EwsDirectoryExtras.buildGetRooms(roomListEmail), timeoutSeconds: 20));

  /// Id корня архива Exchange ящика (или общего ящика [mailbox]); null —
  /// архива нет.
  Future<String?> archiveRootId(AccountModel account, {String? mailbox}) async =>
      EwsDirectoryExtras.parseFolderId(await _soapRequest(
          account, EwsDirectoryExtras.buildGetDistinguishedFolder('archivemsgfolderroot', mailbox: mailbox),
          timeoutSeconds: 20));

  /// Участники группы рассылки организации.
  Future<List<ContactModel>> expandDl(AccountModel account, String email) async {
    final doc = await _soapRequest(account, EwsXmlBuilder.buildExpandDl(email));
    return EwsXmlParser.parseExpandDl(doc, account.id);
  }

  Future<List<ContactModel>> resolveNames(AccountModel account,
      {required String query, int maxResults = 20, bool directoryOnly = false}) async {
    final body = EwsXmlBuilder.buildResolveNames(query, directoryOnly: directoryOnly);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseResolveNames(xmlDoc, account.id);
  }

  // ════════════════════════ КАЛЕНДАРЬ ════════════════════════

  /// Получить события
  Future<List<CalendarEventModel>> getCalendarEvents(AccountModel account, {required DateTime startDate, required DateTime endDate}) async {
    final body = EwsXmlBuilder.buildFindCalendarItems(
        startDate: startDate, endDate: endDate,
        sharedMailbox: account.sharedMailboxEmail);
    final xmlDoc = await _soapRequest(account, body);
    final found = EwsXmlParser.parseCalendarEvents(xmlDoc, account.id);
    if (found.isEmpty) return found;
    // Описание и участники — GetItem пачками по 50 (FindItem их не отдаёт).
    // Ошибка дозагрузки не мешает: остаются события без подробностей.
    final full = <String, CalendarEventModel>{};
    for (var i = 0; i < found.length; i += 50) {
      final part = found.sublist(i, i + 50 > found.length ? found.length : i + 50);
      try {
        final doc = await _soapRequest(
            account, EwsXmlBuilder.buildGetCalendarItems([for (final e in part) e.id]));
        for (final e in EwsXmlParser.parseCalendarEvents(doc, account.id)) {
          full[e.id] = e;
        }
      } catch (e) {
        AppLogger.debug('EWS GetItem (календарь): $e');
        break;
      }
    }
    return [for (final e in found) full[e.id] ?? e];
  }

  /// Создать событие
  Future<String> createCalendarEvent(AccountModel account, {required CalendarEventModel event, String? category}) async {
    final body = EwsXmlBuilder.buildCreateCalendarItem(event, sharedMailbox: account.sharedMailboxEmail, category: category);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseCreateItemResponse(xmlDoc) ?? '';
  }

  /// Текущий ChangeKey элемента (для UpdateItem).
  Future<String?> getChangeKey(AccountModel account, String itemId) async {
    final doc = await _soapRequest(account, EwsXmlBuilder.buildGetItemIdOnly(itemId));
    return doc.findAllElements('ItemId').firstOrNull?.getAttribute('ChangeKey');
  }

  /// Обновить событие (нужны itemId и changeKey)
  Future<bool> updateCalendarEvent(AccountModel account, {
    required String itemId, required String changeKey, required CalendarEventModel event, String? category,
    String sendTo = 'SendToAllAndSaveCopy'}) async {
    final body = EwsXmlBuilder.buildUpdateCalendarItem(itemId, changeKey, event, category: category, sendTo: sendTo);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  /// Сохранить черновик в «Черновиках» (CreateItem SaveOnly) — его видно
  /// в Outlook. Возвращает ItemId. [attachments] — файлы черновика
  /// (1.7.2+111): CreateAttachment одним запросом, как у отправки. Файлы не
  /// приложились — созданный черновик удаляется (иначе при повторной
  /// выгрузке на сервере осталась бы копия без файлов).
  Future<String?> saveDraft(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
  }) async {
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildCreateDraft(
            to: to, cc: cc, bcc: bcc, subject: subject, bodyContent: bodyHtml, isHtml: true,
            sharedMailbox: account.sharedMailboxEmail),
        idempotent: false);
    _ensureSuccess(doc, 'draft');
    final itemEl = doc.findAllElements('ItemId').firstOrNull;
    final itemId = itemEl?.getAttribute('Id');
    final changeKey = itemEl?.getAttribute('ChangeKey');
    final files = attachments.where((a) => a.bytes.isNotEmpty).toList();
    if (files.isEmpty || itemId == null) return itemId;
    try {
      if (changeKey == null) throw StateError('EWS: у черновика нет ChangeKey');
      final attDoc = await _soapRequest(
          account,
          EwsXmlBuilder.buildCreateAttachments(itemId, changeKey, [
            for (final a in files) (name: a.name, contentType: a.contentType, base64: base64.encode(a.bytes)),
          ]),
          timeoutSeconds: 300,
          idempotent: false);
      _ensureSuccess(attDoc, 'attach');
    } catch (e) {
      try {
        await _soapRequest(account, EwsXmlBuilder.buildDeleteItem(itemId, hardDelete: true));
      } catch (_) {}
      rethrow;
    }
    return itemId;
  }

  /// Встреча в календаре по началу и теме (1.6.7) — ItemId для EWS у ящиков
  /// ActiveSync, где у встречи свой ServerId. CalendarView разворачивает
  /// серии: у вхождения — свой ItemId. null — не найдена.
  Future<String?> findCalendarItemId(AccountModel account,
      {required DateTime start, required DateTime end, required String subject}) async {
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildFindCalendarItems(
            startDate: start.subtract(const Duration(minutes: 1)),
            endDate: end.add(const Duration(minutes: 1)),
            sharedMailbox: account.sharedMailboxEmail));
    final found = EwsXmlParser.parseCalendarEvents(doc, account.id);
    final subj = subject.trim().toLowerCase();
    bool sameStart(CalendarEventModel e) => e.startTime.toUtc().difference(start.toUtc()).inSeconds.abs() <= 60;
    return found.where((e) => sameStart(e) && e.title.trim().toLowerCase() == subj).firstOrNull?.id ??
        found.where(sameStart).where((_) => found.where(sameStart).length == 1).firstOrNull?.id;
  }

  /// Главный элемент серии по её вхождению (1.6.7). null — элемент не
  /// из серии (или сервер не ответил).
  Future<({String id, String changeKey, DateTime start, DateTime end})?> getRecurringMaster(
      AccountModel account, String occurrenceId) async {
    final XmlDocument doc;
    try {
      doc = await _soapRequest(account, EwsXmlBuilder.buildGetRecurringMaster(occurrenceId));
    } catch (_) {
      return null;
    }
    if (!EwsXmlParser.parseResponseSuccess(doc)) return null;
    if (doc.findAllElements('CalendarItemType').firstOrNull?.innerText != 'RecurringMaster') return null;
    final idEl = doc.findAllElements('ItemId').firstOrNull;
    final s = DateTime.tryParse(doc.findAllElements('Start').firstOrNull?.innerText ?? '');
    final e = DateTime.tryParse(doc.findAllElements('End').firstOrNull?.innerText ?? '');
    final id = idEl?.getAttribute('Id');
    if (id == null || s == null || e == null) return null;
    return (id: id, changeKey: idEl!.getAttribute('ChangeKey') ?? '', start: s, end: e);
  }

  /// Переслать приглашение на встречу (ForwardItem над элементом календаря):
  /// Exchange отправляет получателям приглашение и сообщает организатору.
  Future<bool> forwardCalendarItem(AccountModel account,
      {required String itemId, required List<EmailAddress> to, String note = ''}) async {
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildForwardItem(
            referenceItemId: itemId,
            to: to,
            bodyContent: note.trim().isEmpty ? '' : '<p>${const HtmlEscape().convert(note.trim()).replaceAll('\n', '<br>')}</p>',
            sharedMailbox: account.sharedMailboxEmail),
        idempotent: false);
    return EwsXmlParser.parseResponseSuccess(doc);
  }

  /// Удалить событие календаря. [series] — всю серию вхождения (1.6.7).
  Future<bool> deleteCalendarEvent(AccountModel account, {required String itemId, bool series = false}) async {
    final body = EwsXmlBuilder.buildDeleteItem(itemId, hardDelete: false, calendar: true, seriesOf: series);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  // ════════════════════════ КОНТАКТЫ ════════════════════════

  /// Получить личные контакты из папки Contacts (с пагинацией).
  Future<List<ContactModel>> getContacts(AccountModel account, {int offset = 0, int maxResults = 200}) async {
    final body = EwsXmlBuilder.buildFindContacts(
        offset: offset, maxResults: maxResults,
        sharedMailbox: account.sharedMailboxEmail);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseContacts(xmlDoc, account.id);
  }

  /// Создать контакт.
  Future<String> createContact(AccountModel account, {required ContactModel contact}) async {
    final body = EwsXmlBuilder.buildCreateContact(contact, sharedMailbox: account.sharedMailboxEmail);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseCreateItemResponse(xmlDoc) ?? '';
  }

  /// Удалить контакт.
  Future<bool> deleteContact(AccountModel account, {required String itemId}) async {
    final body = EwsXmlBuilder.buildDeleteItem(itemId, hardDelete: false);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  // ════════════════════════ ЗАМЕТКИ (NOTES) ════════════════════════

  /// Получить заметки из папки Notes.
  Future<List<Map<String, String>>> getNotes(AccountModel account, {int offset = 0, int maxResults = 200}) async {
    final body = EwsXmlBuilder.buildFindNotes(offset: offset, maxResults: maxResults);
    final xmlDoc = await _soapRequest(account, body);
    final found = EwsXmlParser.parseNotes(xmlDoc);
    // Текст заметок — GetItem пачками (FindItem тело не возвращает: заметки
    // EWS приходили пустыми).
    final full = <String, Map<String, String>>{};
    final ids = [for (final n in found) if ((n['serverId'] ?? '').isNotEmpty) n['serverId']!];
    for (var i = 0; i < ids.length; i += 50) {
      final part = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      try {
        final doc = await _soapRequest(account, EwsXmlBuilder.buildGetCalendarItems(part));
        for (final n in EwsXmlParser.parseNotes(doc)) {
          full[n['serverId'] ?? ''] = n;
        }
      } catch (e) {
        AppLogger.debug('EWS GetItem (заметки): $e');
        break;
      }
    }
    return [for (final n in found) full[n['serverId']] ?? n];
  }

  /// Изменить заметку (тема и текст). Раньше правка заметки EWS оставалась
  /// только на устройстве.
  Future<bool> updateNote(AccountModel account,
      {required String itemId, required String title, required String body}) async {
    final ck = await getChangeKey(account, itemId);
    if (ck == null) return false;
    final doc = await _soapRequest(account, EwsXmlBuilder.buildUpdateNote(itemId, ck, title, body));
    return EwsXmlParser.parseResponseSuccess(doc);
  }

  /// Создать заметку. Возвращает ItemId или пустую строку.
  Future<String> createNote(AccountModel account, {required String title, required String body}) async {
    final reqBody = EwsXmlBuilder.buildCreateNote(title, body);
    final xmlDoc = await _soapRequest(account, reqBody);
    return EwsXmlParser.parseCreateItemResponse(xmlDoc) ?? '';
  }

  /// Удалить заметку.
  Future<bool> deleteNote(AccountModel account, {required String itemId}) async {
    final body = EwsXmlBuilder.buildDeleteItem(itemId, hardDelete: false);
    final xmlDoc = await _soapRequest(account, body);
    return EwsXmlParser.parseResponseSuccess(xmlDoc);
  }

  // ════════════════════════ ЗАДАЧИ ════════════════════════

  /// Задачи ящика (раньше у EWS задач не было вовсе). Тело — GetItem пачками.
  Future<List<TaskModel>> getTasks(AccountModel account) async {
    final doc = await _soapRequest(account,
        EwsXmlBuilder.buildFindTasks(sharedMailbox: account.sharedMailboxEmail));
    final ids = <String>[];
    for (final t in doc.findAllElements('Task')) {
      final id = t.findElements('ItemId').firstOrNull?.getAttribute('Id');
      if (id != null) ids.add(id);
    }
    final full = <XmlElement>[];
    for (var i = 0; i < ids.length; i += 50) {
      final part = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      try {
        final d = await _soapRequest(account, EwsXmlBuilder.buildGetCalendarItems(part));
        full.addAll(d.findAllElements('Task'));
      } catch (e) {
        AppLogger.debug('EWS GetItem (задачи): $e');
        full
          ..clear()
          ..addAll(doc.findAllElements('Task'));
        break;
      }
    }
    final source = full.isEmpty ? doc.findAllElements('Task') : full;
    String? text(XmlElement e, String name) {
      final v = e.findElements(name).firstOrNull?.innerText.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return [
      for (final t in source)
        if (t.findElements('ItemId').firstOrNull?.getAttribute('Id') case final id?)
          TaskModel(
            id: id,
            accountId: account.id,
            title: text(t, 'Subject') ?? '',
            description: text(t, 'Body'),
            status: switch (text(t, 'Status')) {
              'Completed' => TaskStatus.completed,
              'InProgress' => TaskStatus.inProgress,
              _ => TaskStatus.pending,
            },
            priority: switch (text(t, 'Importance')) {
              'High' => TaskPriority.high,
              'Low' => TaskPriority.low,
              _ => TaskPriority.normal,
            },
            createdAt: DateTime.tryParse(text(t, 'DateTimeCreated') ?? '')?.toLocal() ?? DateTime.now(),
            dueDate: DateTime.tryParse(text(t, 'DueDate') ?? '')?.toLocal(),
            completedAt: DateTime.tryParse(text(t, 'CompleteDate') ?? '')?.toLocal(),
          ),
    ];
  }

  static String _importance(TaskPriority p) => switch (p) {
        TaskPriority.high || TaskPriority.urgent => 'High',
        TaskPriority.low => 'Low',
        _ => 'Normal',
      };

  /// Создать задачу. Возвращает ItemId.
  Future<String?> createTask(AccountModel account, TaskModel t) async {
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildCreateTask(
          title: t.title,
          body: t.description,
          importance: _importance(t.priority),
          dueDate: t.dueDate,
          completed: t.status == TaskStatus.completed,
          sharedMailbox: account.sharedMailboxEmail,
        ),
        idempotent: false);
    _ensureSuccess(doc, 'task');
    return doc.findAllElements('ItemId').firstOrNull?.getAttribute('Id');
  }

  /// Изменить задачу (по актуальному ChangeKey).
  Future<bool> updateTask(AccountModel account, TaskModel t) async {
    final ck = await getChangeKey(account, t.id);
    if (ck == null) return false;
    final doc = await _soapRequest(
        account,
        EwsXmlBuilder.buildUpdateTask(t.id, ck,
            title: t.title,
            body: t.description,
            importance: _importance(t.priority),
            dueDate: t.dueDate,
            completed: t.status == TaskStatus.completed));
    return EwsXmlParser.parseResponseSuccess(doc);
  }

  /// Удалить задачу (в «Удалённые»).
  Future<bool> deleteTask(AccountModel account, {required String itemId}) async {
    final doc = await _soapRequest(account, EwsXmlBuilder.buildDeleteItem(itemId));
    return EwsXmlParser.parseResponseSuccess(doc);
  }

  // ════════════════════════ ВЛОЖЕНИЯ ════════════════════════

  /// Скачать вложение (байты)
  Future<Uint8List> getAttachment(AccountModel account, {required String attachmentId}) async {
    final body = EwsXmlBuilder.buildGetAttachment(attachmentId);
    // Большие вложения по мобильной сети — не меньше 5 минут.
    final xmlDoc = await _soapRequest(account, body,
        timeoutSeconds: AppConstants.ewsTimeoutSeconds < 300 ? 300 : AppConstants.ewsTimeoutSeconds);
    return EwsXmlParser.parseAttachmentContent(xmlDoc);
  }

  // ════════════════════════ CLEANUP ════════════════════════

  void clearClientCache(String accountId) {
    _clients.remove(accountId)?.close();
    _ewsUrls.remove(accountId);
    _systemIds.remove(accountId);
  }

  void clearAllCaches() {
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
    _ewsUrls.clear();
    _systemIds.clear();
    _dedup.clear();
  }

  /// Пересылка НА СЕРВЕРЕ: вложения не скачиваются на устройство.
  /// Exchange сам берёт их из исходного письма по ReferenceItemId.
  Future<bool> forwardOnServer(
    AccountModel account, {
    required String referenceItemId,
    String? referenceChangeKey,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String bodyHtml,
    String? newSubject,
    bool saveSentCopy = true,
  }) =>
      _smartResponse(account,
          reply: false,
          referenceItemId: referenceItemId,
          referenceChangeKey: referenceChangeKey,
          to: to,
          cc: cc,
          bcc: bcc,
          bodyHtml: bodyHtml,
          newSubject: newSubject,
          saveSentCopy: saveSentCopy);

  /// Ответ силами сервера (ReplyToItem): исходное письмо с шапкой Outlook
  /// и встроенными картинками добавляет Exchange (1.5.12). Получателей
  /// выбирает сервер — как Outlook для «Ответить» / «Ответить всем».
  Future<bool> replyOnServer(
    AccountModel account, {
    required String referenceItemId,
    bool all = false,
    required String bodyHtml,
    String? newSubject,
  }) =>
      _smartResponse(account,
          reply: true,
          all: all,
          referenceItemId: referenceItemId,
          to: const [],
          bodyHtml: bodyHtml,
          newSubject: newSubject);

  Future<bool> _smartResponse(
    AccountModel account, {
    required bool reply,
    bool all = false,
    required String referenceItemId,
    String? referenceChangeKey,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String bodyHtml,
    String? newSubject,
    bool saveSentCopy = true,
  }) async {
    final what = reply ? (all ? 'ReplyAllToItem' : 'ReplyToItem') : 'ForwardItem';
    try {
      final body = reply
          ? EwsXmlBuilder.buildReplyToItem(
              sharedMailbox: account.sharedMailboxEmail,
              referenceItemId: referenceItemId,
              referenceChangeKey: referenceChangeKey,
              all: all,
              bodyContent: bodyHtml,
              saveSentCopy: saveSentCopy,
              newSubject: newSubject,
            )
          : EwsXmlBuilder.buildForwardItem(
        sharedMailbox: account.sharedMailboxEmail,
        referenceItemId: referenceItemId,
        referenceChangeKey: referenceChangeKey,
        to: to,
        cc: cc,
        bcc: bcc,
        bodyContent: bodyHtml,
        saveSentCopy: saveSentCopy,
        newSubject: newSubject,
      );
      final doc = await _soapRequest(account, body,
          timeoutSeconds: AppConstants.ewsTimeoutSeconds, idempotent: false);

      // Успех — ResponseClass="Success" у CreateItemResponseMessage.
      final ok = doc
          .findAllElements('CreateItemResponseMessage')
          .any((e) => e.getAttribute('ResponseClass') == 'Success');
      AppLogger.info('EWS $what: ${ok ? "успех" : "ошибка"}');
      return ok;
    } catch (e, st) {
      AppLogger.error('EWS $what error', e, st);
      return false;
    }
  }

  /// Главный список категорий ящика: имя и номер цвета Outlook (0–24, −1 —
  /// без цвета). null — список не получен (EWS закрыт, ошибка).
  Future<List<({String name, int color})>?> getCategoryList(AccountModel account) async {
    try {
      final doc = await _soapRequest(
          account, EwsXmlBuilder.buildGetCategoryList(sharedMailbox: account.sharedMailboxEmail),
          timeoutSeconds: 20);
      final data = doc.findAllElements('XmlData').firstOrNull?.innerText.trim();
      if (data == null || data.isEmpty) return null;
      return parseCategoryListXml(utf8.decode(base64.decode(data), allowMalformed: true));
    } catch (e) {
      AppLogger.debug('EWS CategoryList: $e');
      return null;
    }
  }

  /// Разбор XML главного списка категорий Outlook
  /// (`<categories><category name="…" color="7" …/></categories>`).
  static List<({String name, int color})> parseCategoryListXml(String xml) {
    final s = xml.startsWith('\uFEFF') ? xml.substring(1) : xml;
    final out = <({String name, int color})>[];
    for (final c in XmlDocument.parse(s).findAllElements('category')) {
      final name = c.getAttribute('name')?.trim() ?? '';
      final color = int.tryParse(c.getAttribute('color') ?? '') ?? -1;
      if (name.isNotEmpty) out.add((name: name, color: color));
    }
    return out;
  }

  /// Импорт HTML-подписи со старого Exchange (on-prem) через GetUserConfiguration
  /// (скрытый словарь OWA.UserOptions → ключ signaturehtml).
  Future<String?> getOwaSignatureHtml(AccountModel account) async {
    try {
      final doc = await _soapRequest(
          account, EwsXmlBuilder.buildGetUserConfiguration(),
          timeoutSeconds: 20);
      for (final entry in doc.findAllElements('DictionaryEntry')) {
        final keyEl = entry.findElements('DictionaryKey');
        if (keyEl.isEmpty) continue;
        final keyVal = keyEl.first.findAllElements('Value').isNotEmpty
            ? keyEl.first.findAllElements('Value').first.innerText
            : '';
        if (keyVal.toLowerCase() == 'signaturehtml') {
          final valEl = entry.findElements('DictionaryValue');
          if (valEl.isNotEmpty && valEl.first.findAllElements('Value').isNotEmpty) {
            final html = valEl.first.findAllElements('Value').first.innerText;
            return html.trim().isEmpty ? null : html;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Настройки автоответа (Out of Office).
class OofSettings {
  final bool enabled;
  final String internalReply;
  final String externalReply;
  /// По расписанию: с [start] по [end] (сервер включит и выключит сам).
  final bool scheduled;
  final DateTime? start;
  final DateTime? end;
  /// Отвечать и внешним адресатам.
  final bool externalOn;
  const OofSettings({
    required this.enabled,
    this.internalReply = '',
    this.externalReply = '',
    this.scheduled = false,
    this.start,
    this.end,
    this.externalOn = false,
  });
}

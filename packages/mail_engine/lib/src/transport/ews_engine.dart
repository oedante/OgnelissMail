// lib/src/transport/ews_engine.dart
// EWS (Exchange Web Services) — только ПРОБНОЕ подключение при входе:
// connect() делает SOAP-пробник (GetFolder inbox) по явному серверу или по
// EWS URL из Autodiscover. Рабочий стек EWS — в приложении
// (lib/services/mail/ews: NTLMv2 с привязкой к каналу, OAuth, все операции).
// Аудит 07.10.2026, п. 3.2: пробник входит по Basic; сервер, где EWS
// принимает только NTLM, а ActiveSync — Basic, подключится по ActiveSync.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../debug_log.dart';
import '../mail_engine.dart';
import '../models/models.dart';
import 'autodiscover.dart';
import 'eas_engine.dart' show EasEngine;

class EwsEngine implements MailEngine {
  final DebugLog log;
  final http.Client _http;
  EwsEngine({DebugLog? logger, http.Client? httpClient})
      : log = logger ?? DebugLog(),
        _http = httpClient ?? http.Client();
  static const _t = 'EWS';

  AccountConfig? _cfg;
  String? _endpoint;

  @override
  MailTransportKind get kind => MailTransportKind.ews;

  @override
  Capabilities get capabilities => const Capabilities(
        mail: true, calendar: true, contacts: true, tasks: true, notes: true, policies: false,
      );

  @override
  SecurityPolicy? get policy => null;


  String _authUser(AccountConfig cfg) {
    if (cfg.domain != null && cfg.domain!.isNotEmpty) {
      final user = cfg.email.contains('@') ? cfg.email.split('@').first : cfg.email;
      return '${cfg.domain}\\$user';
    }
    return cfg.email;
  }

  String _basicAuth(AccountConfig cfg) =>
      'Basic ${base64.encode(utf8.encode('${_authUser(cfg)}:${cfg.password ?? ''}'))}';

  /// Exchange Online по OAuth (1.6.2) — Bearer, как у EasEngine.
  String? _bearer;

  String _authHeader(AccountConfig cfg) => cfg.authKind == AuthKind.oauth2
      ? 'Bearer ${_bearer ?? cfg.oauthAccessToken ?? ''}'
      : _basicAuth(cfg);

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

  static const _getFolderInbox = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
  xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
  <soap:Header><t:RequestServerVersion Version="Exchange2016"/></soap:Header>
  <soap:Body>
    <m:GetFolder><m:FolderShape><t:BaseShape>IdOnly</t:BaseShape></m:FolderShape>
      <m:FolderIds><t:DistinguishedFolderId Id="inbox"/></m:FolderIds>
    </m:GetFolder>
  </soap:Body>
</soap:Envelope>''';

  @override
  Future<ConnectResult> connect(AccountConfig cfg) async {
    _cfg = cfg;
    if (cfg.authKind == AuthKind.oauth2) await _takeBearer(cfg, force: false);
    final auth = _authHeader(cfg);

    // Определяем EWS endpoint.
    final endpoints = <String>[];
    if (cfg.exchangeServer != null && cfg.exchangeServer!.isNotEmpty) {
      final h = EasEngine.cleanServer(cfg.exchangeServer!);
      endpoints.add(h.startsWith('http') ? h : 'https://$h/EWS/Exchange.asmx');
    } else {
      log.info(_t, 'EWS: сервер не задан — пробуем Autodiscover...');
      final ad = await Autodiscover.discover(
          email: cfg.email, authHeader: auth, userAgent: cfg.userAgent, httpClient: _http);
      for (final l in ad.log) { log.debug(_t, l); }
      if (ad.ewsUrl != null) endpoints.add(ad.ewsUrl!);
      final domain = cfg.email.contains('@') ? cfg.email.split('@').last : '';
      if (domain.isNotEmpty) endpoints.add('https://mail.$domain/EWS/Exchange.asmx');
    }
    if (endpoints.isEmpty) {
      return ConnectResult(success: false, error: 'EWS: не удалось определить endpoint', log: [log.dump()]);
    }

    for (final ep in endpoints) {
      final url = Uri.parse(ep);
      // Шлюз недавно отверг EWS с этого клиента — не повторяем (повторы анти-бот
      // засчитывает как атаку и продлевает блокировку адреса).
      final wafKey = 'ews:${url.host}';
      final left = EasEngine.wafPauseMinutesLeft(wafKey);
      if (left > 0) {
        log.warn(_t, 'EWS ${url.host}: шлюз недавно отклонил запросы — пауза ещё $left мин, пропуск.');
        continue;
      }
      log.info(_t, 'EWS GetFolder → $url');
      final h = {
        'Authorization': auth,
        'Content-Type': 'text/xml; charset=utf-8',
        'User-Agent': cfg.userAgent,
        ...?cfg.extraHeaders,
      };
      log.httpRequest(_t, 'POST', url, h, _getFolderInbox.codeUnits);
      try {
        final sw = Stopwatch()..start();
        final resp = await _http.post(url, headers: h, body: _getFolderInbox).timeout(const Duration(seconds: 20));
        sw.stop();
        log.httpResponse(_t, resp.statusCode, resp.headers, resp.bodyBytes, sw.elapsed);
        if (resp.statusCode == 200 && resp.body.contains('NoError')) {
          _endpoint = ep;
          log.info(_t, 'EWS доступен OK');
          return ConnectResult(
            success: true, transport: MailTransportKind.ews,
            resolvedHost: url.host, capabilities: capabilities, log: [log.dump()],
          );
        }
        final ct = (resp.headers['content-type'] ?? '').toLowerCase();
        if (resp.statusCode == 200 && ct.contains('text/html')) {
          log.warn(_t, 'EWS → 200, но тело = HTML JS-челлендж анти-бота (ServicePipe). Не настоящий ответ EWS.');
        }
        if (resp.statusCode == 403) {
          final body = resp.bodyBytes;
          final html = ct.contains('text/html') || (body.isNotEmpty && body[0] == 0x3c);
          if (html) {
            // Страница анти-бот шлюза (не ответ IIS): пауза для EWS этого хоста.
            EasEngine.markWafBlocked(wafKey);
            log.warn(_t, 'EWS → 403 от шлюза перед Exchange — EWS к ${url.host} приостановлен на 15 мин.');
          } else {
            log.info(_t, 'EWS → 403 Forbidden (часто EWS закрыт политикой → используйте EAS)');
          }
        }
      } catch (e) {
        log.info(_t, 'EWS $ep → $e');
      }
    }
    return ConnectResult(success: false, error: 'EWS недоступен', log: [log.dump()]);
  }

  // ─────────────────── FindFolder / FindItem / GetItem / SendItem ───────────────────

  static const _nsT = 'http://schemas.microsoft.com/exchange/services/2006/types';
  static const _nsM = 'http://schemas.microsoft.com/exchange/services/2006/messages';

  String _wrap(String body) => '<?xml version="1.0" encoding="utf-8"?>'
      '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" '
      'xmlns:t="$_nsT" xmlns:m="$_nsM">'
      '<soap:Header><t:RequestServerVersion Version="Exchange2013_SP1"/></soap:Header>'
      '<soap:Body>$body</soap:Body></soap:Envelope>';

  Future<String?> _soap(String body, {bool retried = false}) async {
    final cfg = _cfg!;
    final url = Uri.parse(_endpoint!);
    final headers = {
      'Authorization': _authHeader(cfg),
      'Content-Type': 'text/xml; charset=utf-8',
      'User-Agent': cfg.userAgent,
      ...?cfg.extraHeaders,
    };
    final full = _wrap(body);
    log.httpRequest(_t, 'POST', url, headers, full.codeUnits);
    try {
      final sw = Stopwatch()..start();
      final resp = await _http.post(url, headers: headers, body: full).timeout(const Duration(seconds: 30));
      sw.stop();
      log.httpResponse(_t, resp.statusCode, resp.headers, resp.bodyBytes, sw.elapsed);
      if (resp.statusCode == 200) return resp.body;
      // Токен Exchange Online истёк — новый и один повтор.
      if (resp.statusCode == 401 && !retried && await _takeBearer(cfg, force: true)) {
        return await _soap(body, retried: true);
      }
      log.error(_t, 'EWS SOAP HTTP ${resp.statusCode}');
      return null;
    } catch (e) {
      log.error(_t, 'EWS SOAP ошибка: $e');
      return null;
    }
  }

  @override
  Future<List<MailFolder>> listFolders() async {
    // Inbox + стандартные PIM-папки Exchange (id = distinguished-имя, его
    // использует syncPim для DistinguishedFolderId).
    return const [
      MailFolder(id: 'inbox', displayName: 'Входящие', type: MailFolderType.inbox),
      MailFolder(id: 'Calendar', displayName: 'Календарь', type: MailFolderType.calendar),
      MailFolder(id: 'Contacts', displayName: 'Контакты', type: MailFolderType.contacts),
      MailFolder(id: 'Tasks', displayName: 'Задачи', type: MailFolderType.tasks),
      MailFolder(id: 'Notes', displayName: 'Заметки', type: MailFolderType.notes),
    ];
  }

  @override
  Future<SyncResult> syncFolder(String folderId, {SyncState? since}) async {
    final fid = folderId.isEmpty ? 'inbox' : folderId;
    final dist = const {'inbox','drafts','sentitems','deleteditems','outbox','junkemail'}.contains(fid.toLowerCase());
    final ref = dist
        ? '<t:DistinguishedFolderId Id="$fid"/>'
        : '<t:FolderId Id="$fid"/>';
    final body = '<m:FindItem Traversal="Shallow">'
        '<m:ItemShape><t:BaseShape>Default</t:BaseShape>'
        '<t:AdditionalProperties>'
        '<t:FieldURI FieldURI="item:Subject"/>'
        '<t:FieldURI FieldURI="item:DateTimeReceived"/>'
        '<t:FieldURI FieldURI="message:From"/>'
        '<t:FieldURI FieldURI="message:IsRead"/>'
        '</t:AdditionalProperties></m:ItemShape>'
        '<m:IndexedPageItemView MaxEntriesReturned="20" Offset="0" BasePoint="Beginning"/>'
        '<m:SortOrder><t:FieldOrder Order="Descending">'
        '<t:FieldURI FieldURI="item:DateTimeReceived"/></t:FieldOrder></m:SortOrder>'
        '<m:ParentFolderIds>$ref</m:ParentFolderIds></m:FindItem>';
    final xml = await _soap(body);
    if (xml == null) return const SyncResult();
    final doc = XmlDocument.parse(xml);
    final added = <MailMessage>[];
    for (final msg in doc.findAllElements('Message', namespace: _nsT)) {
      added.add(_parseEwsMessage(msg, fid));
    }
    // Иногда сообщения как t:Message без namespace-резолва — фолбэк по локальному имени.
    if (added.isEmpty) {
      for (final msg in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Message')) {
        added.add(_parseEwsMessage(msg, fid));
      }
    }
    log.info(_t, 'EWS FindItem: получено ${added.length} писем из $fid');
    return SyncResult(added: added);
  }

  MailMessage _parseEwsMessage(XmlElement msg, String folderId) {
    String? local(String n) => msg.descendants.whereType<XmlElement>()
        .firstWhere((e) => e.name.local == n, orElse: () => XmlElement(XmlName('x'))).innerText;
    final itemId = msg.descendants.whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'ItemId', orElse: () => XmlElement(XmlName('x')))
        .getAttribute('Id') ?? '';
    final subject = local('Subject') ?? '';
    final isRead = (local('IsRead') ?? 'false') == 'true';
    final date = DateTime.tryParse(local('DateTimeReceived') ?? '');
    // From → Mailbox → EmailAddress/Name
    String fromEmail = '', fromName = '';
    final fromEl = msg.descendants.whereType<XmlElement>().where((e) => e.name.local == 'From').firstOrNull;
    if (fromEl != null) {
      fromEmail = fromEl.descendants.whereType<XmlElement>()
          .firstWhere((e) => e.name.local == 'EmailAddress', orElse: () => XmlElement(XmlName('x'))).innerText;
      fromName = fromEl.descendants.whereType<XmlElement>()
          .firstWhere((e) => e.name.local == 'Name', orElse: () => XmlElement(XmlName('x'))).innerText;
    }
    return MailMessage(
      id: itemId, folderId: folderId, serverId: itemId,
      from: MailAddress(fromEmail, fromName), subject: subject,
      date: date, isRead: isRead,
    );
  }

  @override
  Future<MailMessage> fetchMessage(MessageRef ref) async {
    final body = '<m:GetItem><m:ItemShape>'
        '<t:BaseShape>Default</t:BaseShape><t:BodyType>Text</t:BodyType>'
        '<t:AdditionalProperties><t:FieldURI FieldURI="item:Body"/></t:AdditionalProperties>'
        '</m:ItemShape><m:ItemIds><t:ItemId Id="${ref.serverId ?? ref.id}"/></m:ItemIds></m:GetItem>';
    final xml = await _soap(body);
    String? bodyText;
    if (xml != null) {
      final doc = XmlDocument.parse(xml);
      bodyText = doc.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'Body').firstOrNull?.innerText;
    }
    return MailMessage(id: ref.id, folderId: ref.folderId, serverId: ref.serverId,
        from: const MailAddress(''), bodyPlain: bodyText);
  }

  @override
  Future<void> send(OutgoingMessage message) async {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final toXml = message.to.map((a) =>
        '<t:Mailbox><t:EmailAddress>${esc(a.email)}</t:EmailAddress></t:Mailbox>').join();
    final ccXml = message.cc.isEmpty ? '' :
        '<t:CcRecipients>${message.cc.map((a) => '<t:Mailbox><t:EmailAddress>${esc(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:CcRecipients>';
    final isHtml = message.bodyHtml != null;
    final bodyContent = esc(message.bodyHtml ?? message.bodyPlain ?? '');
    // Порядок элементов важен для схемы EWS: Subject, Body, ToRecipients/CcRecipients.
    final messageFields =
        '<t:Subject>${esc(message.subject)}</t:Subject>'
        '<t:Body BodyType="${isHtml ? 'HTML' : 'Text'}">$bodyContent</t:Body>'
        '<t:ToRecipients>$toXml</t:ToRecipients>$ccXml';

    final withBytes = message.attachments
        .where((a) => a.bytes != null && a.bytes!.isNotEmpty)
        .toList();

    // Без вложений — отправка одним запросом (SendAndSaveCopy).
    if (withBytes.isEmpty) {
      final body = '<m:CreateItem MessageDisposition="SendAndSaveCopy">'
          '<m:SavedItemFolderId><t:DistinguishedFolderId Id="sentitems"/></m:SavedItemFolderId>'
          '<m:Items><t:Message>$messageFields</t:Message></m:Items></m:CreateItem>';
      _checkSend(await _soap(body));
      log.info(_t, 'EWS send: успех');
      return;
    }

    // С вложениями EWS не поддерживает единый SendAndSaveCopy — канонический поток:
    // 1) сохранить черновик, 2) прикрепить файлы, 3) отправить черновик.
    // 1) Черновик.
    final draftBody = '<m:CreateItem MessageDisposition="SaveOnly">'
        '<m:SavedItemFolderId><t:DistinguishedFolderId Id="drafts"/></m:SavedItemFolderId>'
        '<m:Items><t:Message>$messageFields</t:Message></m:Items></m:CreateItem>';
    final draftXml = await _soap(draftBody);
    _checkSend(draftXml);
    final idm = RegExp(r'ItemId Id="([^"]*)" ChangeKey="([^"]*)"').firstMatch(draftXml!);
    if (idm == null) throw Exception('EWS send: не удалось получить ItemId черновика');
    final itemId = idm.group(1)!;
    var changeKey = idm.group(2)!;

    // 2) Вложения одним CreateAttachment.
    final attXml = withBytes.map((a) =>
        '<t:FileAttachment>'
        '<t:Name>${esc(a.name)}</t:Name>'
        '${(a.contentType != null && a.contentType!.isNotEmpty) ? '<t:ContentType>${esc(a.contentType!)}</t:ContentType>' : ''}'
        '<t:IsInline>false</t:IsInline>'
        '<t:Content>${base64.encode(a.bytes!)}</t:Content>'
        '</t:FileAttachment>').join();
    final createAttBody = '<m:CreateAttachment>'
        '<m:ParentItemId Id="$itemId" ChangeKey="$changeKey"/>'
        '<m:Attachments>$attXml</m:Attachments>'
        '</m:CreateAttachment>';
    final attRespXml = await _soap(createAttBody);
    _checkSend(attRespXml);
    // После добавления вложений ChangeKey родителя меняется.
    final rootCk = RegExp(r'RootItemChangeKey="([^"]*)"').firstMatch(attRespXml ?? '');
    if (rootCk != null) changeKey = rootCk.group(1)!;

    // 3) Отправить черновик (с сохранением в Отправленные).
    final sendBody = '<m:SendItem SaveItemToFolder="true">'
        '<m:ItemIds><t:ItemId Id="$itemId" ChangeKey="$changeKey"/></m:ItemIds>'
        '<m:SavedItemFolderId><t:DistinguishedFolderId Id="sentitems"/></m:SavedItemFolderId>'
        '</m:SendItem>';
    _checkSend(await _soap(sendBody));
    log.info(_t, 'EWS send с вложениями (${withBytes.length}): успех');
  }

  /// Проверка ответа EWS на успех; иначе бросает с текстом ошибки.
  void _checkSend(String? xml) {
    if (xml == null) throw Exception('EWS send: нет ответа');
    if (xml.contains('NoError') || xml.contains('ResponseClass="Success"')) return;
    final err = RegExp(r'<m:MessageText>(.*?)</m:MessageText>').firstMatch(xml)?.group(1)
        ?? RegExp(r'ResponseCode>(.*?)<').firstMatch(xml)?.group(1) ?? 'неизвестная ошибка';
    log.error(_t, 'EWS send ошибка: $err');
    throw Exception('EWS send: $err');
  }

  @override
  Future<void> applyFlags(MessageRef ref, {bool? read, bool? flagged}) async {
    final updates = StringBuffer();
    if (read != null) {
      updates.write('<t:SetItemField>'
          '<t:FieldURI FieldURI="message:IsRead"/>'
          '<t:Message><t:IsRead>${read ? 'true' : 'false'}</t:IsRead></t:Message>'
          '</t:SetItemField>');
    }
    if (flagged != null) {
      updates.write('<t:SetItemField>'
          '<t:FieldURI FieldURI="item:Flag"/>'
          '<t:Item><t:Flag><t:FlagStatus>${flagged ? 'Flagged' : 'NotFlagged'}</t:FlagStatus></t:Flag></t:Item>'
          '</t:SetItemField>');
    }
    if (updates.isEmpty) return;
    final body = '<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite">'
        '<m:ItemChanges><t:ItemChange>'
        '<t:ItemId Id="${_xmlEsc(ref.id)}"/>'
        '<t:Updates>$updates</t:Updates>'
        '</t:ItemChange></m:ItemChanges></m:UpdateItem>';
    _checkAction(await _soap(body), 'applyFlags');
  }

  @override
  Future<void> move(MessageRef ref, String toFolderId) async {
    const dist = {'inbox', 'drafts', 'sentitems', 'deleteditems', 'outbox', 'junkemail', 'archive'};
    final to = dist.contains(toFolderId.toLowerCase())
        ? '<t:DistinguishedFolderId Id="${toFolderId.toLowerCase()}"/>'
        : '<t:FolderId Id="${_xmlEsc(toFolderId)}"/>';
    final body = '<m:MoveItem>'
        '<m:ToFolderId>$to</m:ToFolderId>'
        '<m:ItemIds><t:ItemId Id="${_xmlEsc(ref.id)}"/></m:ItemIds>'
        '</m:MoveItem>';
    _checkAction(await _soap(body), 'move');
  }

  @override
  Future<void> delete(MessageRef ref) async {
    final body = '<m:DeleteItem DeleteType="MoveToDeletedItems">'
        '<m:ItemIds><t:ItemId Id="${_xmlEsc(ref.id)}"/></m:ItemIds>'
        '</m:DeleteItem>';
    _checkAction(await _soap(body), 'delete');
  }

  String _xmlEsc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  void _checkAction(String? xml, String action) {
    if (xml == null) throw Exception('EWS $action: нет ответа');
    if (xml.contains('NoError') || xml.contains('ResponseClass="Success"')) {
      log.info(_t, 'EWS $action: успех');
      return;
    }
    final err = RegExp(r'<m:MessageText>(.*?)</m:MessageText>').firstMatch(xml)?.group(1) ??
        RegExp(r'ResponseCode>(.*?)<').firstMatch(xml)?.group(1) ?? 'неизвестная ошибка';
    log.error(_t, 'EWS $action ошибка: $err');
    throw Exception('EWS $action: $err');
  }
  @override
  Future<void> dispose() async {
    try { _http.close(); } catch (_) {}
  }

  @override
  Future<List<PimItem>> syncPim(String folderId,
      {required String dataClass, SyncState? since}) async {
    if (_endpoint == null) return const [];
    // dataClass → distinguished folder + имя элемента EWS
    const distMap = {'Calendar': 'calendar', 'Contacts': 'contacts', 'Tasks': 'tasks', 'Notes': 'notes'};
    const elemMap = {'Calendar': 'CalendarItem', 'Contacts': 'Contact', 'Tasks': 'Task', 'Notes': 'Message'};
    final useDist = folderId.isEmpty || folderId.toLowerCase() == dataClass.toLowerCase();
    final ref = (useDist && distMap[dataClass] != null)
        ? '<t:DistinguishedFolderId Id="${distMap[dataClass]}"/>'
        : '<t:FolderId Id="$folderId"/>';
    final body = '<m:FindItem Traversal="Shallow">'
        '<m:ItemShape><t:BaseShape>AllProperties</t:BaseShape></m:ItemShape>'
        '<m:IndexedPageItemView MaxEntriesReturned="100" Offset="0" BasePoint="Beginning"/>'
        '<m:ParentFolderIds>$ref</m:ParentFolderIds></m:FindItem>';
    final xml = await _soap(body);
    if (xml == null) return const [];

    final doc = XmlDocument.parse(xml);
    final elemName = elemMap[dataClass] ?? 'Item';
    final items = <PimItem>[];
    for (final el in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == elemName)) {
      final pim = _parseEwsPim(el, dataClass);
      if (pim != null) items.add(pim);
    }
    log.info(_t, 'EWS syncPim($dataClass) folder=$folderId: ${items.length} элементов');
    return items;
  }

  PimItem? _parseEwsPim(XmlElement el, String dataClass) {
    // ServerId из <t:ItemId Id="..."/>
    final idEl = el.descendants.whereType<XmlElement>()
        .where((e) => e.name.local == 'ItemId').firstOrNull;
    final serverId = idEl?.getAttribute('Id');
    if (serverId == null) return null;

    String? local(String n) {
      final e = el.descendants.whereType<XmlElement>().where((e) => e.name.local == n).firstOrNull;
      return e?.innerText.trim();
    }

    // Значение <t:Entry Key="..."> внутри контейнера (EmailAddresses/PhoneNumbers)
    String? entryByKey(String container, String key) {
      final c = el.descendants.whereType<XmlElement>().where((e) => e.name.local == container).firstOrNull;
      if (c == null) return null;
      for (final entry in c.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Entry')) {
        if (entry.getAttribute('Key') == key) {
          final t = entry.innerText.trim();
          return t.isEmpty ? null : t;
        }
      }
      return null;
    }

    final f = <String, String>{};
    void put(String k, String? v) { if (v != null && v.isNotEmpty) f[k] = v; }

    switch (dataClass) {
      case 'Calendar':
        put('Subject', local('Subject'));
        put('StartTime', local('Start'));
        put('EndTime', local('End'));
        put('Location', local('Location'));
        put('Data', local('Body'));
        put('AllDayEvent', local('IsAllDayEvent') == 'true' ? '1' : '0');
        // Organizer → Mailbox → EmailAddress
        final org = el.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Organizer').firstOrNull;
        final orgEmail = org?.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 'EmailAddress').firstOrNull?.innerText.trim();
        put('Organizer_Email', orgEmail);
        break;
      case 'Contacts':
        put('FirstName', local('GivenName'));
        put('LastName', local('Surname'));
        put('MiddleName', local('MiddleName'));
        put('FileAs', local('FileAs'));
        put('CompanyName', local('CompanyName'));
        put('JobTitle', local('JobTitle'));
        put('Department', local('Department'));
        put('Email1Address', entryByKey('EmailAddresses', 'EmailAddress1'));
        put('BusinessPhoneNumber', entryByKey('PhoneNumbers', 'BusinessPhone'));
        put('MobilePhoneNumber', entryByKey('PhoneNumbers', 'MobilePhone'));
        break;
      case 'Tasks':
        put('Subject', local('Subject'));
        final complete = local('IsComplete') == 'true' || local('Status') == 'Completed';
        put('Complete', complete ? '1' : '0');
        final imp = local('Importance'); // Low/Normal/High
        put('Importance', imp == 'High' ? '2' : (imp == 'Low' ? '0' : '1'));
        put('DueDate', local('DueDate'));
        put('DateCompleted', local('CompleteDate'));
        break;
      case 'Notes':
        put('Subject', local('Subject'));
        put('Data', local('Body'));
        put('LastModifiedDate', local('LastModifiedTime'));
        break;
    }
    return PimItem(serverId: serverId, fields: f);
  }

  String? get endpoint => _endpoint;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

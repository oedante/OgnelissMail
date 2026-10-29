// lib/services/mail/ews/ews_xml_builder.dart
// Полный EWS SOAP XML Builder — ВСЕ операции:
// FindFolder, GetFolder, FindItem, GetItem, CreateItem (Send),
// UpdateItem (Read, Flag), MoveItem, DeleteItem, SyncFolderItems,
// ResolveNames, GetAttachment, CreateAttachment,
// FindCalendarItem, CreateCalendarItem,
// Autodiscover, GetOofSettings, SetOofSettings.

import '../../security/mail_classification.dart' show MailLabel;

class EwsXmlBuilder {
  static const _nsTypes = 'http://schemas.microsoft.com/exchange/services/2006/types';
  static const _nsMessages = 'http://schemas.microsoft.com/exchange/services/2006/messages';
  static const _nsSoap = 'http://schemas.xmlsoap.org/soap/envelope/';

  /// Обернуть в SOAP Envelope
  static String wrapInEnvelope(String body) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="$_nsSoap"
               xmlns:t="$_nsTypes"
               xmlns:m="$_nsMessages">
  <soap:Header>
    <t:RequestServerVersion Version="Exchange2013_SP1"/>
  </soap:Header>
  <soap:Body>
    $body
  </soap:Body>
</soap:Envelope>''';
  }

  // ════════════════════ NOTIFICATIONS (PUSH) ════════════════════

  /// Subscribe (StreamingSubscriptionRequest) — подписка на события папок.
  /// Возвращает SubscriptionId, который затем используется в GetStreamingEvents.
  /// Отслеживаем появление письма, перемещение, удаление и изменение (флаги).
  static String buildSubscribeStreaming(List<String> folderIds) {
    final ids = folderIds
        .map((id) => '      <t:FolderId Id="${_escapeXml(id)}"/>')
        .join('\n');
    return '''<m:Subscribe>
  <m:StreamingSubscriptionRequest>
    <t:FolderIds>
$ids
    </t:FolderIds>
    <t:EventTypes>
      <t:EventType>NewMailEvent</t:EventType>
      <t:EventType>CreatedEvent</t:EventType>
      <t:EventType>ModifiedEvent</t:EventType>
      <t:EventType>MovedEvent</t:EventType>
      <t:EventType>DeletedEvent</t:EventType>
    </t:EventTypes>
  </m:StreamingSubscriptionRequest>
</m:Subscribe>''';
  }

  /// GetStreamingEvents — держит соединение открытым до connectionTimeout
  /// минут (допустимо 1..30) и присылает события по мере поступления.
  static String buildGetStreamingEvents(String subscriptionId,
      {int connectionTimeoutMinutes = 30}) {
    return '''<m:GetStreamingEvents>
  <m:SubscriptionIds>
    <t:SubscriptionId>${_escapeXml(subscriptionId)}</t:SubscriptionId>
  </m:SubscriptionIds>
  <m:ConnectionTimeout>$connectionTimeoutMinutes</m:ConnectionTimeout>
</m:GetStreamingEvents>''';
  }

  /// Unsubscribe — снять подписку (при остановке push).
  static String buildUnsubscribe(String subscriptionId) {
    return '''<m:Unsubscribe>
  <m:SubscriptionId>${_escapeXml(subscriptionId)}</m:SubscriptionId>
</m:Unsubscribe>''';
  }

  // ════════════════════ INBOX RULES (СЕРВЕРНЫЕ ПРАВИЛА) ════════════════════

  /// GetInboxRules — прочитать серверные правила ящика.
  static String buildGetInboxRules() => '<m:GetInboxRules/>';

  /// UpdateInboxRules с одной операцией. [operation] = 'Create' | 'Set' | 'Delete'.
  /// Для Create передаётся `<t:Rule>` без RuleId; для Set — с RuleId; для Delete —
  /// только RuleId. Порядок дочерних элементов Rule СТРОГИЙ (MS-OXWSMSG):
  /// DisplayName, Priority, IsEnabled, Conditions, Actions.
  static String buildUpdateInboxRules({
    required String operation,
    String? ruleId,
    String? displayName,
    int priority = 1,
    bool isEnabled = true,
    String conditionsXml = '',
    String actionsXml = '',
  }) {
    final buf = StringBuffer('<m:UpdateInboxRules>\n');
    buf.write('  <m:RemoveOutlookRuleBlob>true</m:RemoveOutlookRuleBlob>\n');
    buf.write('  <m:Operations>\n');
    switch (operation) {
      case 'Delete':
        buf.write('    <t:DeleteRuleOperation>\n');
        buf.write('      <t:RuleId>${_escapeXml(ruleId ?? '')}</t:RuleId>\n');
        buf.write('    </t:DeleteRuleOperation>\n');
        break;
      case 'Set':
        buf.write('    <t:SetRuleOperation>\n');
        buf.write('      <t:Rule>\n');
        buf.write('        <t:RuleId>${_escapeXml(ruleId ?? '')}</t:RuleId>\n');
        buf.write(_ruleInner(displayName, priority, isEnabled, conditionsXml, actionsXml));
        buf.write('      </t:Rule>\n');
        buf.write('    </t:SetRuleOperation>\n');
        break;
      default: // Create
        buf.write('    <t:CreateRuleOperation>\n');
        buf.write('      <t:Rule>\n');
        buf.write(_ruleInner(displayName, priority, isEnabled, conditionsXml, actionsXml));
        buf.write('      </t:Rule>\n');
        buf.write('    </t:CreateRuleOperation>\n');
    }
    buf.write('  </m:Operations>\n');
    buf.write('</m:UpdateInboxRules>');
    return buf.toString();
  }

  static String _ruleInner(
      String? displayName, int priority, bool isEnabled, String conditionsXml, String actionsXml) {
    final b = StringBuffer();
    b.write('        <t:DisplayName>${_escapeXml(displayName ?? 'Rule')}</t:DisplayName>\n');
    b.write('        <t:Priority>$priority</t:Priority>\n');
    b.write('        <t:IsEnabled>$isEnabled</t:IsEnabled>\n');
    b.write('        <t:Conditions>\n$conditionsXml        </t:Conditions>\n');
    b.write('        <t:Actions>\n$actionsXml        </t:Actions>\n');
    return b.toString();
  }

  /// Экранирование одного значения-строки в `<t:String>`.
  static String ruleStringItem(String v) => '<t:String>${_escapeXml(v)}</t:String>';

  /// FolderId с адресацией к ОБЩЕМУ (делегированному) ящику.
  ///
  /// Ключевой момент поддержки общих ящиков: стандартный
  /// `<t:DistinguishedFolderId Id="inbox"/>` всегда обращается к ящику того,
  /// чьи учётные данные использованы. Чтобы получить папку ЧУЖОГО ящика, внутрь
  /// нужно вложить `<t:Mailbox><t:EmailAddress>…</t:EmailAddress></t:Mailbox>`.
  /// Так работают и общие ящики подразделений, и делегированный доступ к ящику
  /// руководителя — отдельный пароль при этом не нужен, права выданы на сервере.
  ///
  /// [sharedMailbox] == null → обычное поведение (свой ящик).
  static String folderIdFor(String folderId, {String? sharedMailbox}) {
    final shared = sharedMailbox?.trim() ?? '';
    if (shared.isEmpty) {
      return _isDistinguished(folderId)
          ? '<t:DistinguishedFolderId Id="$folderId"/>'
          : '<t:FolderId Id="${_escapeXml(folderId)}"/>';
    }
    final mailbox =
        '<t:Mailbox><t:EmailAddress>${_escapeXml(shared)}</t:EmailAddress></t:Mailbox>';
    // Для нестандартных папок общего ящика Id уже содержит привязку к ящику,
    // поэтому Mailbox добавляется только к well-known папкам.
    return _isDistinguished(folderId)
        ? '<t:DistinguishedFolderId Id="$folderId">$mailbox</t:DistinguishedFolderId>'
        : '<t:FolderId Id="${_escapeXml(folderId)}"/>';
  }

  /// Заголовки грифа (X-Ogneliss-*) для CreateItem: именованные свойства
  /// InternetHeaders Exchange кладёт в заголовки отправляемого письма.
  /// По схеме ExtendedProperty идёт после InReplyTo и до ToRecipients.
  static String labelHeadersXml(String sensitivity) => MailLabel.decode(sensitivity)
      .headers
      .entries
      .map((h) => '<t:ExtendedProperty><t:ExtendedFieldURI DistinguishedPropertySetId="InternetHeaders" '
          'PropertyName="${h.key}" PropertyType="String"/><t:Value>${_escapeXml(h.value)}</t:Value></t:ExtendedProperty>')
      .join();

  /// FolderId для действия перемещения/копирования.
  static String ruleFolderId(String folderId) => _isDistinguished(folderId)
      ? '<t:DistinguishedFolderId Id="$folderId"/>'
      : '<t:FolderId Id="${_escapeXml(folderId)}"/>';

  // ════════════════════════ FOLDERS ════════════════════════

  /// FindFolder — получить все папки
  /// Список папок. Для общего ящика корень адресуется его почтовому ящику,
  /// иначе вернулись бы собственные папки пользователя.
  /// [root] — корень обхода: ящик (msgfolderroot) или архив Exchange
  /// (archivemsgfolderroot, 1.6.49).
  static String buildFindFolder({String? sharedMailbox, String root = 'msgfolderroot'}) {
    return '''<m:FindFolder Traversal="Deep">
  <m:FolderShape>
    <t:BaseShape>Default</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="folder:UnreadCount"/>
      <t:FieldURI FieldURI="folder:TotalCount"/>
      <t:FieldURI FieldURI="folder:ParentFolderId"/>
      <t:FieldURI FieldURI="folder:FolderClass"/>
      <t:ExtendedFieldURI PropertyTag="0x3613" PropertyType="String"/>
    </t:AdditionalProperties>
  </m:FolderShape>
  <m:ParentFolderIds>
    ${folderIdFor(root, sharedMailbox: sharedMailbox)}
  </m:ParentFolderIds>
</m:FindFolder>''';
  }

  // ════════════════════════ УПРАВЛЕНИЕ ПАПКАМИ ════════════════════════

  /// CreateFolder — создать папку под родителем (по умолчанию корень ящика).
  static String buildCreateFolder(String displayName, {String parentId = 'msgfolderroot'}) {
    final parentRef = _isDistinguished(parentId)
        ? '<t:DistinguishedFolderId Id="$parentId"/>'
        : '<t:FolderId Id="${_escapeXml(parentId)}"/>';
    return '''<m:CreateFolder>
  <m:ParentFolderId>
    $parentRef
  </m:ParentFolderId>
  <m:Folders>
    <t:Folder>
      <t:DisplayName>${_escapeXml(displayName)}</t:DisplayName>
    </t:Folder>
  </m:Folders>
</m:CreateFolder>''';
  }

  /// UpdateFolder — переименовать папку (сменить DisplayName).
  static String buildRenameFolder(String folderId, String newName) {
    return '''<m:UpdateFolder>
  <m:FolderChanges>
    <t:FolderChange>
      <t:FolderId Id="${_escapeXml(folderId)}"/>
      <t:Updates>
        <t:SetFolderField>
          <t:FieldURI FieldURI="folder:DisplayName"/>
          <t:Folder><t:DisplayName>${_escapeXml(newName)}</t:DisplayName></t:Folder>
        </t:SetFolderField>
      </t:Updates>
    </t:FolderChange>
  </m:FolderChanges>
</m:UpdateFolder>''';
  }

  /// MoveFolder — переместить папку в другую (или в корень ящика).
  static String buildMoveFolder(String folderId, {String toParentId = 'msgfolderroot'}) {
    final to = _isDistinguished(toParentId)
        ? '<t:DistinguishedFolderId Id="$toParentId"/>'
        : '<t:FolderId Id="${_escapeXml(toParentId)}"/>';
    return '''<m:MoveFolder>
  <m:ToFolderId>
    $to
  </m:ToFolderId>
  <m:FolderIds>
    <t:FolderId Id="${_escapeXml(folderId)}"/>
  </m:FolderIds>
</m:MoveFolder>''';
  }

  /// DeleteFolder — удалить папку (по умолчанию в «Удалённые»).
  static String buildDeleteFolder(String folderId, {String deleteType = 'MoveToDeletedItems'}) {
    return '''<m:DeleteFolder DeleteType="$deleteType">
  <m:FolderIds>
    <t:FolderId Id="${_escapeXml(folderId)}"/>
  </m:FolderIds>
</m:DeleteFolder>''';
  }

  // ════════════════════════ ЗАНЯТОСТЬ (FREE/BUSY) ════════════════════════

  /// GetUserAvailability (MergedFreeBusy). Времена — в UTC (таймзона с нулевым
  /// смещением, без переходов). Возвращает строку статусов по интервалам:
  /// 0=свободен, 1=под вопросом, 2=занят, 3=нет на месте, 4=нет данных.
  static String buildGetUserAvailability(
      List<String> emails, DateTime startUtc, DateTime endUtc, int intervalMinutes) {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
        'T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';
    final mailboxes = emails.map((e) => '''    <t:MailboxData>
      <t:Email><t:Address>${_escapeXml(e)}</t:Address></t:Email>
      <t:AttendeeType>Required</t:AttendeeType>
      <t:ExcludeConflicts>false</t:ExcludeConflicts>
    </t:MailboxData>''').join('\n');
    return '''<m:GetUserAvailabilityRequest>
  <t:TimeZone>
    <t:Bias>0</t:Bias>
    <t:StandardTime><t:Bias>0</t:Bias><t:Time>00:00:00</t:Time><t:DayOrder>0</t:DayOrder><t:Month>0</t:Month><t:DayOfWeek>Sunday</t:DayOfWeek></t:StandardTime>
    <t:DaylightTime><t:Bias>0</t:Bias><t:Time>00:00:00</t:Time><t:DayOrder>0</t:DayOrder><t:Month>0</t:Month><t:DayOfWeek>Sunday</t:DayOfWeek></t:DaylightTime>
  </t:TimeZone>
  <m:MailboxDataArray>
$mailboxes
  </m:MailboxDataArray>
  <t:FreeBusyViewOptions>
    <t:TimeWindow>
      <t:StartTime>${fmt(startUtc)}</t:StartTime>
      <t:EndTime>${fmt(endUtc)}</t:EndTime>
    </t:TimeWindow>
    <t:MergedFreeBusyIntervalInMinutes>$intervalMinutes</t:MergedFreeBusyIntervalInMinutes>
    <t:RequestedView>MergedOnly</t:RequestedView>
  </t:FreeBusyViewOptions>
</m:GetUserAvailabilityRequest>''';
  }

  /// GetFolder — получить одну папку
  static String buildGetFolder(String folderId) {
    final folderRef = _isDistinguished(folderId)
        ? '<t:DistinguishedFolderId Id="$folderId"/>'
        : '<t:FolderId Id="$folderId"/>';

    return '''<m:GetFolder>
  <m:FolderShape>
    <t:BaseShape>AllProperties</t:BaseShape>
  </m:FolderShape>
  <m:FolderIds>
    $folderRef
  </m:FolderIds>
</m:GetFolder>''';
  }

  // ════════════════════════ EMAILS ════════════════════════

  /// FindItem — поиск писем в папке с пагинацией
  /// Письма папки, полученные раньше [before], — только идентификаторы,
  /// самые старые первыми (архив Ogneliss: письма старше периода
  /// синхронизации на устройстве не лежат, 29.10.2026). Порядок элементов —
  /// по схеме: вид страницы, Restriction, SortOrder, ParentFolderIds.
  static String buildFindItemIdsBefore({
    required String folderId,
    required DateTime before,
    int offset = 0,
    int maxCount = 100,
  }) {
    final folderRef = _isDistinguished(folderId)
        ? '<t:DistinguishedFolderId Id="$folderId"/>'
        : '<t:FolderId Id="$folderId"/>';
    final at = before.toUtc().toIso8601String().split('.').first;
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxCount" Offset="$offset" BasePoint="Beginning"/>
  <m:Restriction>
    <t:IsLessThan>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
      <t:FieldURIOrConstant>
        <t:Constant Value="${at}Z"/>
      </t:FieldURIOrConstant>
    </t:IsLessThan>
  </m:Restriction>
  <m:SortOrder>
    <t:FieldOrder Order="Ascending">
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    $folderRef
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  static String buildFindItem({
    required String folderId,
    int offset = 0,
    int maxCount = 50,
    String sortBy = 'DateTimeReceived',
    bool descending = true,
  }) {
    final folderRef = _isDistinguished(folderId)
        ? '<t:DistinguishedFolderId Id="$folderId"/>'
        : '<t:FolderId Id="$folderId"/>';

    // Получатели (To/Cc), тело и вложения FindItem не отдаёт — запрос с ними
    // сервер отвергает целиком (ErrorInvalidPropertyRequest). Они приходят
    // при открытии письма (GetItem).
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>Default</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:Subject"/>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
      <t:FieldURI FieldURI="item:HasAttachments"/>
      <t:FieldURI FieldURI="item:Importance"/>
      <t:FieldURI FieldURI="item:Size"/>
      <t:FieldURI FieldURI="item:Categories"/>
      <t:FieldURI FieldURI="item:ConversationId"/>
      <t:FieldURI FieldURI="item:Flag"/>
      <t:FieldURI FieldURI="item:Preview"/>
      <t:FieldURI FieldURI="message:From"/>
      <t:FieldURI FieldURI="message:IsRead"/>
      <t:FieldURI FieldURI="message:InternetMessageId"/>
      <t:FieldURI FieldURI="message:References"/>
      <t:FieldURI FieldURI="message:IsReadReceiptRequested"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxCount" Offset="$offset" BasePoint="Beginning"/>
  <m:SortOrder>
    <t:FieldOrder Order="${descending ? 'Descending' : 'Ascending'}">
      <t:FieldURI FieldURI="item:$sortBy"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    $folderRef
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  /// GetItem — получить полное тело письма
  static String buildGetItem(String itemId) {
    return '''<m:GetItem>
  <m:ItemShape>
    <t:BaseShape>AllProperties</t:BaseShape>
    <t:BodyType>HTML</t:BodyType>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:Attachments"/>
      <t:FieldURI FieldURI="item:Body"/>
      <t:FieldURI FieldURI="item:TextBody"/>
      <t:FieldURI FieldURI="message:ReplyTo"/>
      <t:FieldURI FieldURI="item:InternetMessageHeaders"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:ItemIds>
    <t:ItemId Id="$itemId"/>
  </m:ItemIds>
</m:GetItem>''';
  }

  /// GetItem только с идентификатором — узнать актуальный ChangeKey.
  static String buildGetItemIdOnly(String itemId) =>
      '<m:GetItem><m:ItemShape><t:BaseShape>IdOnly</t:BaseShape></m:ItemShape>'
      '<m:ItemIds><t:ItemId Id="${_escapeXml(itemId)}"/></m:ItemIds></m:GetItem>';

  /// Встречи целиком (описание, участники, организатор) — GetItem пачкой.
  /// FindItem этих свойств не возвращает: события EWS приходили без
  /// описания и без участников.
  static String buildGetCalendarItems(List<String> ids) {
    final idsXml = ids.map((id) => '<t:ItemId Id="${_escapeXml(id)}"/>').join();
    return '<m:GetItem><m:ItemShape><t:BaseShape>AllProperties</t:BaseShape>'
        '<t:BodyType>Text</t:BodyType></m:ItemShape>'
        '<m:ItemIds>$idsXml</m:ItemIds></m:GetItem>';
  }

  /// Серверный поиск (FindItem с QueryString)
  ///
  /// Без папки ищем в основных папках сразу: FindItem не умеет обходить
  /// подпапки (Deep — только у FindFolder), а поиск Shallow по корню ящика
  /// («msgfolderroot») ничего не находил — писем в самом корне нет.
  static String buildSearchItems({required String query, String? folderId, int maxResults = 50,
      String? sharedMailbox, List<String>? folderIds}) {
    final folderRef = folderId != null
        ? folderIdFor(folderId, sharedMailbox: sharedMailbox)
        : (folderIds != null && folderIds.isNotEmpty)
            ? [for (final f in folderIds) '<t:FolderId Id="${_escapeXml(f)}"/>'].join()
            : [
            for (final f in const ['inbox', 'sentitems', 'drafts', 'deleteditems', 'junkemail'])
              folderIdFor(f, sharedMailbox: sharedMailbox),
          ].join();

    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>Default</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:Subject"/>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
      <t:FieldURI FieldURI="item:Preview"/>
      <t:FieldURI FieldURI="message:From"/>
      <t:FieldURI FieldURI="message:IsRead"/>
      <t:FieldURI FieldURI="item:HasAttachments"/>
      <t:FieldURI FieldURI="item:Flag"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxResults" Offset="0" BasePoint="Beginning"/>
  <m:SortOrder>
    <t:FieldOrder Order="Descending">
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    $folderRef
  </m:ParentFolderIds>
  <m:QueryString>${_escapeXml(query)}</m:QueryString>
</m:FindItem>''';
  }

  // ════════════════════════ CREATE / SEND ════════════════════════

  /// CreateItem — отправить письмо
  static String buildCreateAndSendItem({
    required List to,
    List cc = const [],
    List bcc = const [],
    required String subject,
    required String bodyContent,
    bool isHtml = true,
    String? inReplyTo,
    bool saveSentCopy = true,
    /// Адрес общего ящика: копия отправленного должна лечь в его папку
    /// «Отправленные», а не в собственную — иначе коллеги не увидят, что
    /// письмо от имени общего ящика уже ушло.
    String? sharedMailbox,
    String importance = 'Normal',
    String sensitivity = 'Normal',
    /// «Отправить как / от имени» (1.6.27): From без смены папки копии.
    String? fromAddress,
  }) {
    // По схеме EWS (EmailAddressType) Name идёт ПЕРЕД EmailAddress; в
    // обратном порядке сервер отвергал письмо (ErrorSchemaValidation), как
    // только у получателя было имя.
    final toXml = to.map((a) => '<t:Mailbox>${a.displayName != null && a.displayName!.isNotEmpty ? '<t:Name>${_escapeXml(a.displayName!)}</t:Name>' : ''}<t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join();
    final ccXml = cc.isEmpty ? '' : '<t:CcRecipients>${cc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:CcRecipients>';
    final bccXml = bcc.isEmpty ? '' : '<t:BccRecipients>${bcc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:BccRecipients>';
    final bodyType = isHtml ? 'HTML' : 'Text';

    String replyXml = '';
    if (inReplyTo != null) {
      // Message-ID содержит угловые скобки — без экранирования XML ломался.
      replyXml = '<t:InReplyTo>${_escapeXml(_lastMsgId(inReplyTo))}</t:InReplyTo>';
    }

    return '''<m:CreateItem MessageDisposition="SendAndSaveCopy">
  ${saveSentCopy ? '<m:SavedItemFolderId>${folderIdFor('sentitems', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>' : ''}
  <m:Items>
    <t:Message>
      <t:Subject>${_escapeXml(subject)}</t:Subject>
      ${MailLabel.decode(sensitivity).outlook != 'Normal' ? '<t:Sensitivity>${MailLabel.decode(sensitivity).outlook}</t:Sensitivity>' : ''}
      <t:Body BodyType="$bodyType">${_cdata(bodyContent)}</t:Body>
      ${importance != 'Normal' ? '<t:Importance>$importance</t:Importance>' : ''}
      $replyXml
      ${labelHeadersXml(sensitivity)}
      <t:ToRecipients>$toXml</t:ToRecipients>
      $ccXml
      $bccXml
      ${_fromXml(sharedMailbox ?? fromAddress)}
    </t:Message>
  </m:Items>
</m:CreateItem>''';
  }

  /// GetItem с исходным MIME письма (для проверки подписи S/MIME).
  static String buildGetItemMime(String itemId) => '''<m:GetItem>
  <m:ItemShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:IncludeMimeContent>true</t:IncludeMimeContent>
  </m:ItemShape>
  <m:ItemIds><t:ItemId Id="${_escapeXml(itemId)}"/></m:ItemIds>
</m:GetItem>''';

  /// CreateItem из готового письма (MimeContent) — для S/MIME: подписанное
  /// или зашифрованное письмо Exchange отправляет как есть. Получатели «Кому»
  /// и «Копия» — из заголовков письма; скрытая копия передаётся отдельно
  /// (заголовка Bcc в письме нет).
  static String buildCreateItemFromMime({
    required String mimeBase64,
    List bcc = const [],
    bool encrypted = false,
    bool saveSentCopy = true,
    String? sharedMailbox,
  }) {
    final bccXml = bcc.isEmpty ? '' : '<t:BccRecipients>${bcc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:BccRecipients>';
    final cls = encrypted ? 'IPM.Note.SMIME' : 'IPM.Note.SMIME.MultipartSigned';
    return '''<m:CreateItem MessageDisposition="SendAndSaveCopy">
  ${saveSentCopy ? '<m:SavedItemFolderId>${folderIdFor('sentitems', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>' : ''}
  <m:Items>
    <t:Message>
      <t:MimeContent CharacterSet="UTF-8">$mimeBase64</t:MimeContent>
      <t:ItemClass>$cls</t:ItemClass>
      $bccXml
    </t:Message>
  </m:Items>
</m:CreateItem>''';
  }

  /// Message-ID родителя из цепочки (InReplyTo в EWS — один id).
  static String _lastMsgId(String chain) {
    final ids = RegExp(r'<[^<>\s]+>').allMatches(chain).map((m) => m.group(0)!).toList();
    return ids.isEmpty ? chain.trim() : ids.last;
  }

  /// Отправитель — общий ящик (From после получателей, по types.xsd).
  /// Без него письмо из общего ящика уходило от имени самого пользователя.
  static String _fromXml(String? mailbox) => (mailbox == null || mailbox.isEmpty)
      ? ''
      : '<t:From><t:Mailbox><t:EmailAddress>${_escapeXml(mailbox)}</t:EmailAddress></t:Mailbox></t:From>';

  /// CreateItem + ForwardItem — ПЕРЕСЫЛКА НА СТОРОНЕ СЕРВЕРА.
  ///
  /// Клиент отправляет только текст и получателей. Оригинальные вложения к
  /// письму прикрепляет сам Exchange, взяв их из исходного сообщения по
  /// ReferenceItemId, — байты не скачиваются на устройство и не отправляются
  /// обратно. Для писем с тяжёлыми файлами это разница между «мгновенно» и
  /// «выкачать и залить десятки мегабайт по мобильной сети».
  ///
  /// ChangeKey желателен: сервер сверяет версию элемента. Если его нет —
  /// отправляем только Id (большинство серверов принимает).
  static String buildForwardItem({
    required String referenceItemId,
    String? referenceChangeKey,
    required List to,
    List cc = const [],
    List bcc = const [],
    required String bodyContent,
    bool isHtml = true,
    bool saveSentCopy = true,
    String? sharedMailbox,
    String? newSubject,
  }) =>
      _buildSmartResponse('ForwardItem',
          referenceItemId: referenceItemId,
          referenceChangeKey: referenceChangeKey,
          to: to,
          cc: cc,
          bcc: bcc,
          bodyContent: bodyContent,
          isHtml: isHtml,
          saveSentCopy: saveSentCopy,
          sharedMailbox: sharedMailbox,
          newSubject: newSubject);

  /// Ответ силами сервера (ReplyToItem), как ответ из Outlook: шапку
  /// «От / Отправлено / Кому / Тема» и исходное письмо со встроенными
  /// картинками добавляет Exchange, цепочка (In-Reply-To, ConversationIndex)
  /// и отметка «Отвечено» у оригинала — тоже. Получателей выбирает сервер
  /// (ReplyTo/отправитель, при [all] — и остальные, без себя): переданные
  /// явно он ДОБАВЛЯЕТ к своим, а не заменяет. Поэтому серверный ответ
  /// используется, только когда получатели на экране не менялись.
  static String buildReplyToItem({
    required String referenceItemId,
    String? referenceChangeKey,
    bool all = false,
    List to = const [],
    List cc = const [],
    List bcc = const [],
    required String bodyContent,
    bool isHtml = true,
    bool saveSentCopy = true,
    String? sharedMailbox,
    String? newSubject,
  }) =>
      _buildSmartResponse(all ? 'ReplyAllToItem' : 'ReplyToItem',
          referenceItemId: referenceItemId,
          referenceChangeKey: referenceChangeKey,
          to: to,
          cc: cc,
          bcc: bcc,
          bodyContent: bodyContent,
          isHtml: isHtml,
          saveSentCopy: saveSentCopy,
          sharedMailbox: sharedMailbox,
          newSubject: newSubject);

  static String _buildSmartResponse(
    String element, {
    required String referenceItemId,
    String? referenceChangeKey,
    required List to,
    List cc = const [],
    List bcc = const [],
    required String bodyContent,
    bool isHtml = true,
    bool saveSentCopy = true,
    /// Адрес общего ящика: копия отправленного должна лечь в его папку
    /// «Отправленные», а не в собственную — иначе коллеги не увидят, что
    /// письмо от имени общего ящика уже ушло.
    String? sharedMailbox,
    String? newSubject,
  }) {
    final toXml = to
        .map((a) =>
            '<t:Mailbox>${a.displayName != null && a.displayName!.isNotEmpty ? '<t:Name>${_escapeXml(a.displayName!)}</t:Name>' : ''}'
            '<t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>')
        .join();
    final ccXml = cc.isEmpty
        ? ''
        : '<t:CcRecipients>${cc.map((a) => '<t:Mailbox>${a.displayName != null && a.displayName!.isNotEmpty ? '<t:Name>${_escapeXml(a.displayName!)}</t:Name>' : ''}<t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:CcRecipients>';
    final bccXml = bcc.isEmpty
        ? ''
        : '<t:BccRecipients>${bcc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:BccRecipients>';

    final refAttrs = referenceChangeKey != null && referenceChangeKey.isNotEmpty
        ? 'Id="${_escapeXml(referenceItemId)}" ChangeKey="${_escapeXml(referenceChangeKey)}"'
        : 'Id="${_escapeXml(referenceItemId)}"';

    // Порядок по types.xsd (SmartResponseType): Subject, ToRecipients,
    // CcRecipients, BccRecipients, ReferenceItemId и ПОСЛЕДНИМ NewBodyContent
    // (он добавлен расширением типа). Раньше NewBodyContent шёл вторым —
    // сервер отвергал запрос по схеме, и пересылка всегда откатывалась на
    // скачивание и повторную загрузку вложений.
    return '''<m:CreateItem MessageDisposition="SendAndSaveCopy">
  ${saveSentCopy ? '<m:SavedItemFolderId>${folderIdFor('sentitems', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>' : ''}
  <m:Items>
    <t:$element>
      ${newSubject != null ? '<t:Subject>${_escapeXml(newSubject)}</t:Subject>' : ''}
      ${to.isEmpty ? '' : '<t:ToRecipients>$toXml</t:ToRecipients>'}
      $ccXml
      $bccXml
      ${_fromXml(sharedMailbox)}
      <t:ReferenceItemId $refAttrs/>
      <t:NewBodyContent BodyType="${isHtml ? 'HTML' : 'Text'}">${_cdata(bodyContent)}</t:NewBodyContent>
    </t:$element>
  </m:Items>
</m:CreateItem>''';
  }

  // ════════════════════════ UPDATE ════════════════════════

  /// UpdateItem — пометить прочитанным
  static String buildUpdateItemReadState(String itemId, bool isRead) {
    return '''<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AutoResolve">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="$itemId"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="message:IsRead"/>
          <t:Message>
            <t:IsRead>${isRead ? 'true' : 'false'}</t:IsRead>
          </t:Message>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''';
  }

  /// UpdateItem — флаг
  /// Черновик (SaveOnly) в «Черновиках» — 1-й шаг отправки с вложениями.
  static String buildCreateDraft({
    required List to,
    List cc = const [],
    List bcc = const [],
    required String subject,
    required String bodyContent,
    bool isHtml = true,
    String? inReplyTo,
    String importance = 'Normal',
    String sensitivity = 'Normal',
    String? sharedMailbox,
    String? fromAddress,
  }) {
    final toXml = to.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join();
    final ccXml = cc.isEmpty ? '' : '<t:CcRecipients>${cc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:CcRecipients>';
    final bccXml = bcc.isEmpty ? '' : '<t:BccRecipients>${bcc.map((a) => '<t:Mailbox><t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox>').join()}</t:BccRecipients>';
    final bodyType = isHtml ? 'HTML' : 'Text';
    final replyXml = inReplyTo != null ? '<t:InReplyTo>${_escapeXml(_lastMsgId(inReplyTo))}</t:InReplyTo>' : '';
    return '''<m:CreateItem MessageDisposition="SaveOnly">
  <m:SavedItemFolderId>${folderIdFor('drafts', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>
  <m:Items>
    <t:Message>
      <t:Subject>${_escapeXml(subject)}</t:Subject>
      ${MailLabel.decode(sensitivity).outlook != 'Normal' ? '<t:Sensitivity>${MailLabel.decode(sensitivity).outlook}</t:Sensitivity>' : ''}
      <t:Body BodyType="$bodyType">${_cdata(bodyContent)}</t:Body>
      ${importance != 'Normal' ? '<t:Importance>$importance</t:Importance>' : ''}
      $replyXml
      <t:ToRecipients>$toXml</t:ToRecipients>
      $ccXml
      $bccXml
      ${_fromXml(sharedMailbox ?? fromAddress)}
    </t:Message>
  </m:Items>
</m:CreateItem>''';
  }

  /// Прикрепить файлы к черновику (CreateAttachment). base64 — уже закодированное тело.
  static String buildCreateAttachments(
      String itemId, String changeKey, List<({String name, String? contentType, String base64})> attachments) {
    final atts = attachments
        .map((a) => '<t:FileAttachment>'
            '<t:Name>${_escapeXml(a.name)}</t:Name>'
            '${(a.contentType != null && a.contentType!.isNotEmpty) ? '<t:ContentType>${_escapeXml(a.contentType!)}</t:ContentType>' : ''}'
            '<t:IsInline>false</t:IsInline>'
            '<t:Content>${a.base64}</t:Content>'
            '</t:FileAttachment>')
        .join();
    return '''<m:CreateAttachment>
  <m:ParentItemId Id="$itemId" ChangeKey="$changeKey"/>
  <m:Attachments>$atts</m:Attachments>
</m:CreateAttachment>''';
  }

  /// Отправить черновик (SendItem) — 3-й шаг.
  static String buildSendItem(String itemId, String changeKey,
      {bool saveSentCopy = true, String? sharedMailbox}) {
    return '''<m:SendItem SaveItemToFolder="${saveSentCopy ? 'true' : 'false'}">
  <m:ItemIds><t:ItemId Id="$itemId" ChangeKey="$changeKey"/></m:ItemIds>
  ${saveSentCopy ? '<m:SavedItemFolderId>${folderIdFor('sentitems', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>' : ''}
</m:SendItem>''';
  }

  /// UpdateItem: серверные категории Outlook (item:Categories). Пустой список —
  /// очищает категории (DeleteItemField).
  static String buildSetCategories(String itemId, List<String> categories) {
    final String updateField;
    if (categories.isEmpty) {
      updateField = '''<t:DeleteItemField>
          <t:FieldURI FieldURI="item:Categories"/>
        </t:DeleteItemField>''';
    } else {
      final strings = categories
          .map((c) => '<t:String>${_escapeXml(c)}</t:String>')
          .join('\n              ');
      updateField = '''<t:SetItemField>
          <t:FieldURI FieldURI="item:Categories"/>
          <t:Message>
            <t:Categories>
              $strings
            </t:Categories>
          </t:Message>
        </t:SetItemField>''';
    }
    return '''<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AutoResolve">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="$itemId"/>
      <t:Updates>
        $updateField
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''';
  }

  /// Важность письма (High / Normal / Low).
  static String buildUpdateItemImportance(String itemId, String importance) {
    return '''<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${_escapeXml(itemId)}"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Importance"/>
          <t:Message><t:Importance>$importance</t:Importance></t:Message>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''';
  }

  static String buildUpdateItemFlag(String itemId, bool isFlagged) {
    final flagStatus = isFlagged ? 'Flagged' : 'NotFlagged';
    return '''<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AutoResolve">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="$itemId"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Flag"/>
          <t:Message>
            <t:Flag>
              <t:FlagStatus>$flagStatus</t:FlagStatus>
            </t:Flag>
          </t:Message>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''';
  }

  // ════════════════════════ MOVE / DELETE ════════════════════════

  static String buildMoveItem(String itemId, String targetFolderId) {
    final folderRef = _isDistinguished(targetFolderId)
        ? '<t:DistinguishedFolderId Id="$targetFolderId"/>'
        : '<t:FolderId Id="$targetFolderId"/>';

    return '''<m:MoveItem>
  <m:ToFolderId>$folderRef</m:ToFolderId>
  <m:ItemIds>
    <t:ItemId Id="$itemId"/>
  </m:ItemIds>
</m:MoveItem>''';
  }

  /// [calendar] — удаление встречи: SendMeetingCancellations обязателен для
  /// элементов календаря. Без него Exchange отвергал запрос, а участники не
  /// получали отмену; теперь отмена рассылается (SendToAllAndSaveCopy), если
  /// пользователь — организатор, иначе сервер просто удаляет встречу.
  /// [seriesOf] (1.6.7): удалить всю серию, к которой относится вхождение
  /// [itemId] (RecurringMasterItemId), а не только его.
  static String buildDeleteItem(String itemId, {bool hardDelete = false, bool calendar = false, bool seriesOf = false}) {
    final deleteType = hardDelete ? 'HardDelete' : 'MoveToDeletedItems';
    final cancel = calendar ? ' SendMeetingCancellations="SendToAllAndSaveCopy"' : '';
    final id = seriesOf
        ? '<t:RecurringMasterItemId OccurrenceId="${_escapeXml(itemId)}"/>'
        : '<t:ItemId Id="${_escapeXml(itemId)}"/>';
    return '''<m:DeleteItem DeleteType="$deleteType"$cancel>
  <m:ItemIds>
    $id
  </m:ItemIds>
</m:DeleteItem>''';
  }

  /// Главный элемент серии по её вхождению: ItemId, начало и конец (1.6.7).
  static String buildGetRecurringMaster(String occurrenceId) =>
      '<m:GetItem><m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties>'
      '<t:FieldURI FieldURI="calendar:Start"/><t:FieldURI FieldURI="calendar:End"/>'
      '<t:FieldURI FieldURI="calendar:CalendarItemType"/>'
      '</t:AdditionalProperties></m:ItemShape>'
      '<m:ItemIds><t:RecurringMasterItemId OccurrenceId="${_escapeXml(occurrenceId)}"/></m:ItemIds></m:GetItem>';

  // ════════════════════════ ATTACHMENTS ════════════════════════

  static String buildGetAttachment(String attachmentId) {
    // IncludeMimeContent — чтобы вложенное ПИСЬМО (ItemAttachment, у него
    // нет Content) можно было открыть как .eml.
    return '''<m:GetAttachment>
  <m:AttachmentShape><t:IncludeMimeContent>true</t:IncludeMimeContent></m:AttachmentShape>
  <m:AttachmentIds>
    <t:AttachmentId Id="${_escapeXml(attachmentId)}"/>
  </m:AttachmentIds>
</m:GetAttachment>''';
  }

  // ════════════════════════ CONTACTS ════════════════════════

  /// Раскрыть группу рассылки (ExpandDL).
  static String buildExpandDl(String email) {
    return '''<m:ExpandDL>
  <m:Mailbox><t:EmailAddress>${_escapeXml(email)}</t:EmailAddress></m:Mailbox>
</m:ExpandDL>''';
  }

  /// [directoryOnly] — только адресная книга организации, без личных
  /// контактов (сверка коллег, 1.8.0+118): иначе вместе с записью из
  /// адресной книги может прийти и старая копия из «Контактов».
  static String buildResolveNames(String query, {bool directoryOnly = false}) {
    final scope = directoryOnly ? 'ActiveDirectory' : 'ActiveDirectoryContacts';
    return '''<m:ResolveNames SearchScope="$scope" ReturnFullContactData="true">
  <m:UnresolvedEntry>${_escapeXml(query)}</m:UnresolvedEntry>
</m:ResolveNames>''';
  }

  // ════════════════════════ CALENDAR ════════════════════════

  /// Формат времени события для EWS. Обычное — абсолютный UTC. «Весь день» —
  /// полночь UTC той же календарной даты (иначе день уезжает в дальних зонах).
  static String _fmtEventDt(DateTime t, bool allDay) {
    if (allDay) {
      final d = t.toLocal();
      return DateTime.utc(d.year, d.month, d.day).toIso8601String();
    }
    return t.toUtc().toIso8601String();
  }

  /// События календаря. Для общего ящика адресуем ЕГО календарь: иначе в
  /// делегированном ящике показывались бы собственные встречи пользователя.
  static String buildFindCalendarItems({
    required DateTime startDate,
    required DateTime endDate,
    String? sharedMailbox,
  }) {
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>AllProperties</t:BaseShape>
  </m:ItemShape>
  <m:CalendarView StartDate="${startDate.toUtc().toIso8601String()}" EndDate="${endDate.toUtc().toIso8601String()}"/>
  <m:ParentFolderIds>
    ${folderIdFor('calendar', sharedMailbox: sharedMailbox)}
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  /// Создание события. Для общего ящика — в ЕГО календарь, иначе встреча
  /// появилась бы у пользователя, а коллеги её не увидели бы.
  /// Важность встречи для EWS (EventPriority: low, normal, high).
  static String _eventImportance(dynamic event) {
    final p = event.priority;
    final i = p is int ? p : (p as Enum).index;
    return i == 0 ? 'Low' : (i == 2 ? 'High' : 'Normal');
  }

  /// Флажок собрания модели (по умолчанию — true: так у сервера).
  static bool _meetingFlag(dynamic event, String name) {
    try {
      return switch (name) {
        'responseRequested' => event.responseRequested as bool,
        _ => event.allowNewTimeProposal as bool,
      };
    } catch (_) {
      return true;
    }
  }

  static String buildCreateCalendarItem(dynamic event, {String? sharedMailbox, String? category}) {
    // 1.6.4: приватность, цвет (категорией Outlook) и важность — раньше не
    // передавались. Порядок по types.xsd (ItemType): Subject, Sensitivity,
    // Body, Categories, Importance, затем напоминание.
    final importance = _eventImportance(event);
    // Собрание (1.6.7): «Запросить ответы» (CalendarItem после Location) и
    // «Разрешить предлагать новое время» (после Recurrence) — types.xsd.
    final isMeeting = (event.attendees as List).isNotEmpty;
    final responseXml = isMeeting && !_meetingFlag(event, 'responseRequested')
        ? '\n      <t:IsResponseRequested>false</t:IsResponseRequested>' : '';
    final proposalXml = isMeeting && !_meetingFlag(event, 'allowNewTimeProposal')
        ? '\n      <t:AllowNewTimeProposal>false</t:AllowNewTimeProposal>' : '';
    final extraHead = event.isPrivate == true ? '\n      <t:Sensitivity>Private</t:Sensitivity>' : '';
    final extraBody = '${category == null ? '' : '\n      <t:Categories><t:String>${_escapeXml(category)}</t:String></t:Categories>'}'
        '${importance == 'Normal' ? '' : '\n      <t:Importance>$importance</t:Importance>'}';
    // Участники: без них SendMeetingInvitations ничего не рассылал — встреча
    // с участниками создавалась только у организатора.
    String attendeesXml(bool required) {
      final list = [
        for (final a in (event.attendees as List))
          if (a.isRequired == required && (a.email as String).isNotEmpty) a,
      ];
      if (list.isEmpty) return '';
      final tag = required ? 'RequiredAttendees' : 'OptionalAttendees';
      final items = list
          .map((a) {
            final name = (a.displayName as String?)?.trim() ?? '';
            return '<t:Attendee><t:Mailbox>${name.isEmpty ? '' : '<t:Name>${_escapeXml(name)}</t:Name>'}'
                '<t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox></t:Attendee>';
          })
          .join();
      return '\n      <t:$tag>$items</t:$tag>';
    }

    final reminders = (event.reminders as List);
    final reminderXml = reminders.isEmpty
        ? '\n      <t:ReminderIsSet>false</t:ReminderIsSet>'
        : '\n      <t:ReminderIsSet>true</t:ReminderIsSet>'
            '\n      <t:ReminderMinutesBeforeStart>${reminders.first.minutesBefore}</t:ReminderMinutesBeforeStart>';

    return '''<m:CreateItem SendMeetingInvitations="SendToAllAndSaveCopy">
  <m:SavedItemFolderId>
    ${folderIdFor('calendar', sharedMailbox: sharedMailbox)}
  </m:SavedItemFolderId>
  <m:Items>
    <t:CalendarItem>
      <t:Subject>${_escapeXml(event.title ?? '')}</t:Subject>$extraHead
      <t:Body BodyType="Text">${_escapeXml(event.description ?? '')}</t:Body>$extraBody$reminderXml
      <t:Start>${_fmtEventDt(event.startTime, event.isAllDay == true)}</t:Start>
      <t:End>${_fmtEventDt(event.endTime, event.isAllDay == true)}</t:End>
      <t:IsAllDayEvent>${event.isAllDay ? 'true' : 'false'}</t:IsAllDayEvent>
      <t:LegacyFreeBusyStatus>Busy</t:LegacyFreeBusyStatus>
      <t:Location>${_escapeXml(event.location ?? '')}</t:Location>$responseXml${attendeesXml(true)}${attendeesXml(false)}${_recurrenceXml(event.recurrence.index as int, event.startTime as DateTime)}$proposalXml
    </t:CalendarItem>
  </m:Items>
</m:CreateItem>''';
  }

  /// Повторение встречи (RecurrenceType: none, daily, weekly, biweekly,
  /// monthly, yearly) — без даты окончания, от дня начала.
  static String _recurrenceXml(int type, DateTime start) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
    final l = start.toLocal();
    final day = days[l.weekday - 1];
    String pattern;
    switch (type) {
      case 1:
        pattern = '<t:DailyRecurrence><t:Interval>1</t:Interval></t:DailyRecurrence>';
        break;
      case 2:
      case 3:
        pattern = '<t:WeeklyRecurrence><t:Interval>${type == 3 ? 2 : 1}</t:Interval>'
            '<t:DaysOfWeek>$day</t:DaysOfWeek></t:WeeklyRecurrence>';
        break;
      case 4:
        pattern = '<t:AbsoluteMonthlyRecurrence><t:Interval>1</t:Interval>'
            '<t:DayOfMonth>${l.day}</t:DayOfMonth></t:AbsoluteMonthlyRecurrence>';
        break;
      case 5:
        pattern = '<t:AbsoluteYearlyRecurrence><t:DayOfMonth>${l.day}</t:DayOfMonth>'
            '<t:Month>${months[l.month - 1]}</t:Month></t:AbsoluteYearlyRecurrence>';
        break;
      default:
        return '';
    }
    final startDate = '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
    return '\n      <t:Recurrence>$pattern<t:NoEndRecurrence><t:StartDate>$startDate</t:StartDate></t:NoEndRecurrence></t:Recurrence>';
  }

  // ════════════════════════ КОНТАКТЫ ════════════════════════

  /// Найти все контакты в папке Contacts (с пагинацией).
  /// Контакты. Для общего ящика — его адресная книга, а не своя.
  static String buildFindContacts({
    int offset = 0,
    int maxResults = 200,
    String? sharedMailbox,
  }) {
    // Отчество и инициалы — явно: FindItem не всегда отдаёт их в AllProperties.
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>AllProperties</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="contacts:MiddleName"/>
      <t:FieldURI FieldURI="contacts:Initials"/>
      <t:FieldURI FieldURI="contacts:Manager"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxResults" Offset="$offset" BasePoint="Beginning"/>
  <m:ParentFolderIds>
    ${folderIdFor('contacts', sharedMailbox: sharedMailbox)}
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  /// Создать контакт.
  /// Создание контакта. Для общего ящика — в его адресную книгу.
  /// Контакт в порядке элементов types.xsd (ContactItemType): FileAs,
  /// DisplayName, GivenName, MiddleName, CompanyName, EmailAddresses,
  /// PhoneNumbers, Department, JobTitle, OfficeLocation, Surname. Раньше
  /// Surname стоял третьим (сервер отвергал запрос по схеме), а телефон
  /// брался из несуществующего поля модели.
  static String buildCreateContact(dynamic contact, {String? sharedMailbox}) {
    String? str(String? Function() f) {
      try {
        final v = f()?.trim();
        return (v == null || v.isEmpty) ? null : v;
      } catch (_) {
        return null;
      }
    }

    final display = str(() => contact.displayName as String?);
    final given = str(() => contact.firstName as String?);
    final middle = str(() => contact.middleName as String?);
    final surname = str(() => contact.lastName as String?);
    final company = str(() => contact.company as String?);
    final email = str(() => contact.email as String?);
    final work = str(() => contact.phoneWork as String?);
    final mobile = str(() => contact.phoneMobile as String?);
    final dept = str(() => contact.department as String?);
    final title = str(() => contact.jobTitle as String?);
    final office = str(() => contact.office as String?);
    String el(String name, String? v) => v == null ? '' : '<t:$name>${_escapeXml(v)}</t:$name>';
    final phones = [
      if (work != null) '<t:Entry Key="BusinessPhone">${_escapeXml(work)}</t:Entry>',
      if (mobile != null) '<t:Entry Key="MobilePhone">${_escapeXml(mobile)}</t:Entry>',
    ];
    final emailXml = email == null
        ? ''
        : '<t:EmailAddresses><t:Entry Key="EmailAddress1">${_escapeXml(email)}</t:Entry></t:EmailAddresses>';
    final phonesXml = phones.isEmpty ? '' : '<t:PhoneNumbers>${phones.join()}</t:PhoneNumbers>';
    return '<m:CreateItem>'
        '<m:SavedItemFolderId>${folderIdFor('contacts', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>'
        '<m:Items><t:Contact>'
        '${el('FileAs', display)}${el('DisplayName', display)}${el('GivenName', given)}'
        '${el('MiddleName', middle)}${el('CompanyName', company)}$emailXml$phonesXml'
        '${el('Department', dept)}${el('JobTitle', title)}${el('OfficeLocation', office)}'
        '${el('Surname', surname)}'
        '</t:Contact></m:Items></m:CreateItem>';
  }


  /// Обновить событие календаря (по itemId + changeKey).
  /// [sendTo] (1.6.7): SendToAllAndSaveCopy — обновление всем участникам,
  /// SendToChangedAndSaveCopy — только добавленным и удалённым, как
  /// «Отправить обновление» в Outlook.
  static String buildUpdateCalendarItem(String itemId, String changeKey, dynamic event,
      {String? category, String sendTo = 'SendToAllAndSaveCopy'}) {
    // Участники (1.5.12): раньше менялись только тема, время, место и текст —
    // добавленный при изменении встречи участник приглашения не получал,
    // удалённый — отмены. Список заменяется целиком; Exchange сам рассылает
    // приглашения новым и отмены убранным. Пустой список не трогаем: у
    // встречи, загруженной без участников, иначе ушла бы отмена всем.
    final attendees = [for (final a in (event.attendees as List)) if ((a.email as String).isNotEmpty) a];
    String attendeesUpdate(bool required) {
      final list = [for (final a in attendees) if (a.isRequired == required) a];
      final field = required ? 'calendar:RequiredAttendees' : 'calendar:OptionalAttendees';
      final tag = required ? 'RequiredAttendees' : 'OptionalAttendees';
      if (list.isEmpty) {
        return '\n        <t:DeleteItemField><t:FieldURI FieldURI="$field"/></t:DeleteItemField>';
      }
      final items = list.map((a) {
        final name = (a.displayName as String?)?.trim() ?? '';
        return '<t:Attendee><t:Mailbox>${name.isEmpty ? '' : '<t:Name>${_escapeXml(name)}</t:Name>'}'
            '<t:EmailAddress>${_escapeXml(a.email)}</t:EmailAddress></t:Mailbox></t:Attendee>';
      }).join();
      return '\n        <t:SetItemField><t:FieldURI FieldURI="$field"/>'
          '<t:CalendarItem><t:$tag>$items</t:$tag></t:CalendarItem></t:SetItemField>';
    }
    final attendeesXml = attendees.isEmpty ? '' : '${attendeesUpdate(true)}${attendeesUpdate(false)}';
    // 1.6.4: приватность, важность и цвет (категория Outlook).
    final categoriesXml = category == null
        ? '\n        <t:DeleteItemField><t:FieldURI FieldURI="item:Categories"/></t:DeleteItemField>'
        : '\n        <t:SetItemField><t:FieldURI FieldURI="item:Categories"/>'
            '<t:CalendarItem><t:Categories><t:String>${_escapeXml(category)}</t:String></t:Categories></t:CalendarItem>'
            '</t:SetItemField>';
    final extraXml = '\n        <t:SetItemField><t:FieldURI FieldURI="item:Sensitivity"/>'
        '<t:CalendarItem><t:Sensitivity>${event.isPrivate == true ? 'Private' : 'Normal'}</t:Sensitivity></t:CalendarItem>'
        '</t:SetItemField>'
        '\n        <t:SetItemField><t:FieldURI FieldURI="item:Importance"/>'
        '<t:CalendarItem><t:Importance>${_eventImportance(event)}</t:Importance></t:CalendarItem>'
        '</t:SetItemField>$categoriesXml';
    return '''<m:UpdateItem ConflictResolution="AutoResolve" SendMeetingInvitationsOrCancellations="$sendTo">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${_escapeXml(itemId)}" ChangeKey="${_escapeXml(changeKey)}"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Subject"/>
          <t:CalendarItem><t:Subject>${_escapeXml(event.title ?? '')}</t:Subject></t:CalendarItem>
        </t:SetItemField>
        <t:SetItemField>
          <t:FieldURI FieldURI="calendar:Start"/>
          <t:CalendarItem><t:Start>${_fmtEventDt(event.startTime, event.isAllDay == true)}</t:Start></t:CalendarItem>
        </t:SetItemField>
        <t:SetItemField>
          <t:FieldURI FieldURI="calendar:End"/>
          <t:CalendarItem><t:End>${_fmtEventDt(event.endTime, event.isAllDay == true)}</t:End></t:CalendarItem>
        </t:SetItemField>
        <t:SetItemField>
          <t:FieldURI FieldURI="calendar:Location"/>
          <t:CalendarItem><t:Location>${_escapeXml(event.location ?? '')}</t:Location></t:CalendarItem>
        </t:SetItemField>
        <t:SetItemField>
          <t:FieldURI FieldURI="calendar:IsAllDayEvent"/>
          <t:CalendarItem><t:IsAllDayEvent>${event.isAllDay == true ? 'true' : 'false'}</t:IsAllDayEvent></t:CalendarItem>
        </t:SetItemField>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Body"/>
          <t:CalendarItem><t:Body BodyType="Text">${_escapeXml(event.description ?? '')}</t:Body></t:CalendarItem>
        </t:SetItemField>$extraXml$attendeesXml
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''';
  }

  // ════════════════════════ ЗАМЕТКИ (NOTES) ════════════════════════

  // ════════════════════════ ЗАДАЧИ (TASKS) ════════════════════════

  /// Задачи папки «Задачи».
  static String buildFindTasks({int maxResults = 300, String? sharedMailbox}) =>
      '<m:FindItem Traversal="Shallow"><m:ItemShape><t:BaseShape>AllProperties</t:BaseShape></m:ItemShape>'
      '<m:IndexedPageItemView MaxEntriesReturned="$maxResults" Offset="0" BasePoint="Beginning"/>'
      '<m:ParentFolderIds>${folderIdFor('tasks', sharedMailbox: sharedMailbox)}</m:ParentFolderIds>'
      '</m:FindItem>';

  static String _taskStatus(bool completed) => completed ? 'Completed' : 'NotStarted';

  /// Новая задача. Порядок по types.xsd: Subject, Body, Importance (ItemType),
  /// затем DueDate и Status (TaskType).
  static String buildCreateTask({
    required String title,
    String? body,
    String importance = 'Normal',
    DateTime? dueDate,
    bool completed = false,
    String? sharedMailbox,
  }) =>
      '<m:CreateItem>'
      '<m:SavedItemFolderId>${folderIdFor('tasks', sharedMailbox: sharedMailbox)}</m:SavedItemFolderId>'
      '<m:Items><t:Task>'
      '<t:Subject>${_escapeXml(title)}</t:Subject>'
      '${body == null || body.isEmpty ? '' : '<t:Body BodyType="Text">${_escapeXml(body)}</t:Body>'}'
      '<t:Importance>$importance</t:Importance>'
      '${dueDate == null ? '' : '<t:DueDate>${dueDate.toUtc().toIso8601String()}</t:DueDate>'}'
      '<t:Status>${_taskStatus(completed)}</t:Status>'
      '</t:Task></m:Items></m:CreateItem>';

  /// Изменить задачу: тема, текст, важность, срок, состояние.
  static String buildUpdateTask(
    String itemId,
    String changeKey, {
    required String title,
    String? body,
    String importance = 'Normal',
    DateTime? dueDate,
    bool completed = false,
  }) {
    String set(String uri, String inner) =>
        '<t:SetItemField><t:FieldURI FieldURI="$uri"/><t:Task>$inner</t:Task></t:SetItemField>';
    return '<m:UpdateItem ConflictResolution="AlwaysOverwrite">'
        '<m:ItemChanges><t:ItemChange>'
        '<t:ItemId Id="${_escapeXml(itemId)}" ChangeKey="${_escapeXml(changeKey)}"/>'
        '<t:Updates>'
        '${set('item:Subject', '<t:Subject>${_escapeXml(title)}</t:Subject>')}'
        '${set('item:Body', '<t:Body BodyType="Text">${_escapeXml(body ?? '')}</t:Body>')}'
        '${set('item:Importance', '<t:Importance>$importance</t:Importance>')}'
        '${dueDate == null ? '<t:DeleteItemField><t:FieldURI FieldURI="task:DueDate"/></t:DeleteItemField>' : set('task:DueDate', '<t:DueDate>${dueDate.toUtc().toIso8601String()}</t:DueDate>')}'
        '${set('task:Status', '<t:Status>${_taskStatus(completed)}</t:Status>')}'
        '</t:Updates></t:ItemChange></m:ItemChanges></m:UpdateItem>';
  }

  /// UpdateItem заметки: тема и текст.
  static String buildUpdateNote(String itemId, String changeKey, String title, String body) =>
      '<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite">'
      '<m:ItemChanges><t:ItemChange>'
      '<t:ItemId Id="${_escapeXml(itemId)}" ChangeKey="${_escapeXml(changeKey)}"/>'
      '<t:Updates>'
      '<t:SetItemField><t:FieldURI FieldURI="item:Subject"/>'
      '<t:Message><t:Subject>${_escapeXml(title)}</t:Subject></t:Message></t:SetItemField>'
      '<t:SetItemField><t:FieldURI FieldURI="item:Body"/>'
      '<t:Message><t:Body BodyType="Text">${_escapeXml(body)}</t:Body></t:Message></t:SetItemField>'
      '</t:Updates></t:ItemChange></m:ItemChanges></m:UpdateItem>';

  /// Найти заметки в папке Notes (IPM.StickyNote).
  static String buildFindNotes({int offset = 0, int maxResults = 200}) {
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>AllProperties</t:BaseShape>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxResults" Offset="$offset" BasePoint="Beginning"/>
  <m:ParentFolderIds>
    <t:DistinguishedFolderId Id="notes"/>
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  /// Создать заметку (PostItem с темой и телом).
  static String buildCreateNote(String title, String body) {
    return '''<m:CreateItem MessageDisposition="SaveOnly">
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="notes"/>
  </m:SavedItemFolderId>
  <m:Items>
    <t:Message>
      <t:ItemClass>IPM.StickyNote</t:ItemClass>
      <t:Subject>${_escapeXml(title)}</t:Subject>
      <t:Body BodyType="Text">${_escapeXml(body)}</t:Body>
    </t:Message>
  </m:Items>
</m:CreateItem>''';
  }

  // ════════════════════════ OOF (AUTO RESPONDER) ════════════════════════

  static String buildGetOofSettings(String email) {
    return '''<m:GetUserOofSettingsRequest>
  <t:Mailbox>
    <t:Address>$email</t:Address>
  </t:Mailbox>
</m:GetUserOofSettingsRequest>''';
  }

  static String buildSetOofSettings({
    required String email,
    required bool enabled,
    DateTime? startTime,
    DateTime? endTime,
    String? internalReply,
    String? externalReply,
    bool sendToExternal = false,
  }) {
    // «Scheduled» требует Duration; без дат — просто «Enabled». Раньше
    // включение без дат всегда шло как Scheduled — и сервер его отвергал.
    final scheduled = startTime != null && endTime != null;
    final state = !enabled ? 'Disabled' : (scheduled ? 'Scheduled' : 'Enabled');
    final externalAudience = sendToExternal ? 'All' : 'None';

    return '''<m:SetUserOofSettingsRequest>
  <t:Mailbox>
    <t:Address>${_escapeXml(email)}</t:Address>
  </t:Mailbox>
  <t:UserOofSettings>
    <t:OofState>$state</t:OofState>
    <t:ExternalAudience>$externalAudience</t:ExternalAudience>
    ${startTime != null && endTime != null ? '''
    <t:Duration>
      <t:StartTime>${startTime.toUtc().toIso8601String()}</t:StartTime>
      <t:EndTime>${endTime.toUtc().toIso8601String()}</t:EndTime>
    </t:Duration>''' : ''}
    ${internalReply != null ? '<t:InternalReply><t:Message>${_cdata(internalReply)}</t:Message></t:InternalReply>' : ''}
    ${externalReply != null ? '<t:ExternalReply><t:Message>${_cdata(externalReply)}</t:Message></t:ExternalReply>' : ''}
  </t:UserOofSettings>
</m:SetUserOofSettingsRequest>''';
  }

  // ════════════════════════ SHARED MAILBOX ════════════════════════

  /// FindItem в чужом ящике (delegated). Папка — через [folderIdFor]
  /// (1.6.49): у папок общего ящика из FindFolder настоящие Id, а прежний
  /// DistinguishedFolderId с таким Id не проходит проверку схемы — письма
  /// общего ящика не загружались.
  static String buildFindItemDelegated({
    required String delegateEmail,
    required String folderId,
    int offset = 0,
    int maxCount = 50,
  }) {
    return '''<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>Default</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:Subject"/>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
      <t:FieldURI FieldURI="item:Preview"/>
      <t:FieldURI FieldURI="message:From"/>
      <t:FieldURI FieldURI="message:IsRead"/>
      <t:FieldURI FieldURI="item:HasAttachments"/>
      <t:FieldURI FieldURI="item:Flag"/>
      <t:FieldURI FieldURI="item:ConversationId"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="$maxCount" Offset="$offset" BasePoint="Beginning"/>
  <m:SortOrder>
    <t:FieldOrder Order="Descending">
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    ${folderIdFor(folderId, sharedMailbox: delegateEmail)}
  </m:ParentFolderIds>
</m:FindItem>''';
  }

  // ═══════════════ ОТВЕТ НА ПРИГЛАШЕНИЕ ═══════════════
  /// element: 'AcceptItem' | 'TentativelyAcceptItem' | 'DeclineItem'.
  /// Ответ на приглашение (AcceptItem / TentativelyAcceptItem / DeclineItem)
  /// с вариантами Outlook (1.5.12):
  ///  · [send] = false — «Не отправлять ответ»: SaveOnly, встреча меняется в
  ///    календаре, черновик ответа вызывающий удаляет;
  ///  · [comment] — «Изменить ответ перед отправкой»;
  ///  · [proposedStart]/[proposedEnd] — «Предложить новое время» (Exchange
  ///    2013+; старый сервер отвергнет схему — вызывающий повторит без них).
  /// Порядок по types.xsd: Body до ReferenceItemId, ProposedStart/End — после.
  static String buildMeetingResponse(
    String itemId,
    String element, {
    bool send = true,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
  }) {
    final text = (comment ?? '').trim();
    final body = text.isEmpty ? '' : '<t:Body BodyType="Text">${_escapeXml(text)}</t:Body>';
    final proposal = proposedStart != null && proposedEnd != null
        ? '<t:ProposedStart>${proposedStart.toUtc().toIso8601String()}</t:ProposedStart>'
            '<t:ProposedEnd>${proposedEnd.toUtc().toIso8601String()}</t:ProposedEnd>'
        : '';
    return '''<m:CreateItem MessageDisposition="${send ? 'SendAndSaveCopy' : 'SaveOnly'}">
  <m:Items>
    <t:$element>
      $body
      <t:ReferenceItemId Id="${_escapeXml(itemId)}"/>
      $proposal
    </t:$element>
  </m:Items>
</m:CreateItem>''';
  }

  // ════════════════════════ AUTODISCOVER ════════════════════════

  static String buildAutodiscoverRequest(String email) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
  <Request>
    <EMailAddress>$email</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a</AcceptableResponseSchema>
  </Request>
</Autodiscover>''';
  }

  // ════════════════════════ HELPERS ════════════════════════

  /// Стандартное имя папки EWS (DistinguishedFolderId), а не реальный FolderId.
  /// Единый список для построителя запросов и дельта-синхронизации.
  static bool isDistinguished(String folderId) => _isDistinguished(folderId);

  static bool _isDistinguished(String folderId) {
    const ids = {'msgfolderroot', 'root', 'inbox', 'sentitems', 'drafts', 'deleteditems', 'junkemail', 'outbox', 'archivemsgfolderroot', 'calendar', 'contacts', 'tasks', 'notes', 'searchfolders'};
    return ids.contains(folderId.toLowerCase());
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Безопасно обернуть содержимое в CDATA: разбиваем последовательность ']]>',
  /// которая иначе преждевременно закрыла бы CDATA-секцию и сломала XML.
  static String _cdata(String content) {
    final safe = content.replaceAll(']]>', ']]]]><![CDATA[>');
    return '<![CDATA[$safe]]>';
  }

  /// Главный список категорий ящика (имена и цвета Outlook) — скрытая
  /// настройка CategoryList в папке «Календарь», XML в XmlData (1.6.5).
  static String buildGetCategoryList({String? sharedMailbox}) {
    return '''<m:GetUserConfiguration>
      <m:UserConfigurationName Name="CategoryList">
        ${folderIdFor('calendar', sharedMailbox: sharedMailbox)}
      </m:UserConfigurationName>
      <m:UserConfigurationProperties>XmlData</m:UserConfigurationProperties>
    </m:GetUserConfiguration>''';
  }

  /// Запрос скрытой конфигурации OWA (для импорта подписи со старого Exchange).
  static String buildGetUserConfiguration() {
    return '''<m:GetUserConfiguration>
      <m:UserConfigurationName Name="OWA.UserOptions">
        <t:DistinguishedFolderId Id="root" />
      </m:UserConfigurationName>
      <m:UserConfigurationProperties>All</m:UserConfigurationProperties>
    </m:GetUserConfiguration>''';
  }
}

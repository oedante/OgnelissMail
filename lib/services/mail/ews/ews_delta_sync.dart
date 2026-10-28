// lib/services/mail/ews/ews_delta_sync.dart
// Delta-синхронизация EWS через SyncFolderItems.
// Вместо полной перезагрузки получаем только изменения (Create/Update/Delete).
// Экономит трафик и время на 90%+ при повторных синхронизациях.

import 'ews_xml_builder.dart';
import 'ews_xml_parser.dart';
import 'package:xml/xml.dart';
import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import 'ews_service.dart';

class EwsDeltaSync {
  final EwsService _ews;

  EwsDeltaSync(this._ews);

  /// Delta-синхронизация папки через SyncFolderItems
  /// [syncState] — null для первой синхронизации, строка для последующих
  /// Возвращает (новый syncState, created, updated, deletedIds)
  Future<EwsDeltaSyncResult> syncFolder({
    required AccountModel account,
    required String folderId,
    String? syncState,
    int maxChanges = 100,
    bool idOnly = false,
  }) async {
    try {
      AppLogger.info('EWS DeltaSync: folder=$folderId, hasState=${syncState != null}');

      final soapBody = _buildSyncFolderItemsRequest(
        folderId: folderId,
        syncState: syncState,
        maxChanges: maxChanges,
        idOnly: idOnly,
      );

      // rawSoapRequest сам заворачивает тело в SOAP-конверт. Раньше здесь
      // конверт добавлялся ещё раз — сервер получал конверт в конверте,
      // отвечал ошибкой, и delta-синхронизация НИ РАЗУ не срабатывала:
      // каждый синк откатывался на полную перезагрузку FindItem.
      final xmlDoc = await _ews.rawSoapRequest(account, soapBody);

      return _parseResponse(xmlDoc, account.id, folderId);
    } catch (e, stack) {
      AppLogger.error('EWS DeltaSync error', e, stack);
      rethrow;
    }
  }

  String _buildSyncFolderItemsRequest({
    required String folderId,
    String? syncState,
    required int maxChanges,
    bool idOnly = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('<m:SyncFolderItems>');
    buf.writeln('  <m:ItemShape>');
    if (idOnly) {
      // Только идентификаторы — быстро «перемотать» курсор большой папки,
      // не скачивая старые письма (см. sync_service, первая синхронизация).
      buf.writeln('    <t:BaseShape>IdOnly</t:BaseShape>');
      buf.writeln('  </m:ItemShape>');
      return _tail(buf, folderId, syncState, maxChanges);
    }
    buf.writeln('    <t:BaseShape>Default</t:BaseShape>');
    buf.writeln('    <t:AdditionalProperties>');
    buf.writeln('      <t:FieldURI FieldURI="item:Subject"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:DateTimeReceived"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:HasAttachments"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:Importance"/>');
    buf.writeln('      <t:FieldURI FieldURI="message:From"/>');
    // ToRecipients/CcRecipients здесь недопустимы (как и в FindItem) —
    // приходят при открытии письма.
    buf.writeln('      <t:FieldURI FieldURI="message:InternetMessageId"/>');
    buf.writeln('      <t:FieldURI FieldURI="message:IsRead"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:Flag"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:ConversationId"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:Preview"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:Categories"/>');
    buf.writeln('      <t:FieldURI FieldURI="item:Size"/>');
    buf.writeln('    </t:AdditionalProperties>');
    buf.writeln('  </m:ItemShape>');
    return _tail(buf, folderId, syncState, maxChanges);
  }

  String _tail(StringBuffer buf, String folderId, String? syncState, int maxChanges) {
    buf.writeln('  <m:SyncFolderId>');

    // Используем DistinguishedFolderId для стандартных папок
    if (_isDistinguished(folderId)) {
      buf.writeln('    <t:DistinguishedFolderId Id="$folderId"/>');
    } else {
      buf.writeln('    <t:FolderId Id="$folderId"/>');
    }

    buf.writeln('  </m:SyncFolderId>');

    if (syncState != null) {
      buf.writeln('  <m:SyncState>$syncState</m:SyncState>');
    }

    buf.writeln('  <m:MaxChangesReturned>$maxChanges</m:MaxChangesReturned>');
    buf.writeln('</m:SyncFolderItems>');

    return buf.toString();
  }

  bool _isDistinguished(String folderId) => EwsXmlBuilder.isDistinguished(folderId);

  EwsDeltaSyncResult _parseResponse(XmlDocument doc, String accountId, String folderId) {
    final responseMessage = doc.findAllElements('SyncFolderItemsResponseMessage').firstOrNull;
    if (responseMessage == null) {
      return const EwsDeltaSyncResult(syncState: null);
    }

    final responseClass = responseMessage.getAttribute('ResponseClass');
    if (responseClass != 'Success') {
      final errorCode = responseMessage.findElements('MessageText').firstOrNull?.innerText;
      AppLogger.warning('EWS DeltaSync: $responseClass — $errorCode');
      return EwsDeltaSyncResult(syncState: null, error: errorCode);
    }

    final syncState = responseMessage.findElements('SyncState').firstOrNull?.innerText;
    final includesLastItem = responseMessage.findElements('IncludesLastItemInRange').firstOrNull?.innerText == 'true';

    final changes = responseMessage.findElements('Changes').firstOrNull;
    if (changes == null) {
      return EwsDeltaSyncResult(syncState: syncState, includesLastItem: true);
    }

    final created = <EmailModel>[];
    final updated = <EmailModel>[];
    final deletedIds = <String>[];

    // Create
    for (final create in changes.findElements('Create')) {
      final message = EwsXmlParser.mailItems(create, deep: false).firstOrNull;
      if (message != null) {
        final email = _parseMessage(message, accountId, folderId);
        if (email != null) created.add(email);
      }
    }

    // Update
    for (final update in changes.findElements('Update')) {
      final message = EwsXmlParser.mailItems(update, deep: false).firstOrNull;
      if (message != null) {
        final email = _parseMessage(message, accountId, folderId);
        if (email != null) updated.add(email);
      }
    }

    // Delete
    for (final delete in changes.findElements('Delete')) {
      final itemId = delete.findElements('ItemId').firstOrNull?.getAttribute('Id');
      if (itemId != null) deletedIds.add(itemId);
    }

    // ReadFlagChange — только смена «прочитано». Раньше из неё делалась
    // «пустая» модель письма (без темы и отправителя) и сохранялась поверх
    // настоящей: письмо, прочитанное в Outlook, теряло тему и адрес.
    final readChanges = <String, bool>{};
    for (final readFlag in changes.findElements('ReadFlagChange')) {
      final itemId = readFlag.findElements('ItemId').firstOrNull?.getAttribute('Id');
      final isRead = readFlag.findElements('IsRead').firstOrNull?.innerText == 'true';
      if (itemId != null) readChanges[itemId] = isRead;
    }

    AppLogger.info('EWS DeltaSync: +${created.length} ~${updated.length} -${deletedIds.length} last=$includesLastItem');

    return EwsDeltaSyncResult(
      syncState: syncState,
      created: created,
      updated: updated,
      deletedIds: deletedIds,
      readChanges: readChanges,
      includesLastItem: includesLastItem,
    );
  }

  EmailModel? _parseMessage(XmlElement message, String accountId, String folderId) {
    try {
      final itemId = message.findElements('ItemId').firstOrNull?.getAttribute('Id');
      if (itemId == null) return null;

      final subject = message.findElements('Subject').firstOrNull?.innerText ?? '';
      final dateReceived = message.findElements('DateTimeReceived').firstOrNull?.innerText;
      final isRead = message.findElements('IsRead').firstOrNull?.innerText == 'true';
      final hasAttachments = message.findElements('HasAttachments').firstOrNull?.innerText == 'true';
      final importance = message.findElements('Importance').firstOrNull?.innerText;
      final preview = message.findElements('Preview').firstOrNull?.innerText;
      final size = int.tryParse(message.findElements('Size').firstOrNull?.innerText ?? '');
      final conversationId = message.findElements('ConversationId').firstOrNull?.getAttribute('Id');
      final internetMessageId = message.findElements('InternetMessageId').firstOrNull?.innerText;

      // From
      final fromMailbox = message.findElements('From').firstOrNull?.findElements('Mailbox').firstOrNull;
      final fromEmail = fromMailbox?.findElements('EmailAddress').firstOrNull?.innerText ?? '';
      final fromName = fromMailbox?.findElements('Name').firstOrNull?.innerText;

      // To
      final toAddresses = <EmailAddress>[];
      final toRecipients = message.findElements('ToRecipients').firstOrNull;
      if (toRecipients != null) {
        for (final mailbox in toRecipients.findElements('Mailbox')) {
          toAddresses.add(EmailAddress(
            email: mailbox.findElements('EmailAddress').firstOrNull?.innerText ?? '',
            displayName: mailbox.findElements('Name').firstOrNull?.innerText,
          ));
        }
      }

      // Flag
      final flagStatus = message.findElements('Flag').firstOrNull?.findElements('FlagStatus').firstOrNull?.innerText;
      final isFlagged = flagStatus == 'Flagged';

      // Priority
      EmailPriority priority;
      switch (importance) {
        case 'High': priority = EmailPriority.high; break;
        case 'Low': priority = EmailPriority.low; break;
        default: priority = EmailPriority.normal;
      }

      // Categories
      final categories = <String>[];
      final catsEl = message.findElements('Categories').firstOrNull;
      if (catsEl != null) {
        for (final cat in catsEl.findElements('String')) {
          categories.add(cat.innerText);
        }
      }

      return EmailModel(
        id: itemId,
        accountId: accountId,
        folderId: folderId,
        conversationId: conversationId,
        internetMessageId: internetMessageId,
        from: EmailAddress(email: fromEmail, displayName: fromName),
        to: toAddresses,
        subject: subject,
        bodyPreview: preview,
        receivedAt: dateReceived != null ? DateTime.tryParse(dateReceived) ?? DateTime.now() : DateTime.now(),
        isRead: isRead,
        isFlagged: isFlagged,
        hasAttachments: hasAttachments,
        priority: priority,
        categories: categories,
        size: size,
      );
    } catch (e) {
      AppLogger.warning('EWS DeltaSync: parse message error: $e');
      return null;
    }
  }
}

class EwsDeltaSyncResult {
  final String? syncState;
  final List<EmailModel> created;
  final List<EmailModel> updated;
  final List<String> deletedIds;
  /// id письма → прочитано ли (ReadFlagChange).
  final Map<String, bool> readChanges;
  final bool includesLastItem;
  final String? error;

  const EwsDeltaSyncResult({
    this.syncState,
    this.created = const [],
    this.updated = const [],
    this.deletedIds = const [],
    this.readChanges = const {},
    this.includesLastItem = true,
    this.error,
  });

  int get totalChanges => created.length + updated.length + deletedIds.length + readChanges.length;
  bool get hasChanges => totalChanges > 0;
}

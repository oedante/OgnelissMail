// lib/services/mail/ews/ews_xml_parser.dart
// Полный парсер EWS SOAP XML ответов:
// FindFolder, FindItem, GetItem, CreateItem, UpdateItem,
// MoveItem, DeleteItem, ResolveNames, GetAttachment,
// FindCalendarItems, Autodiscover, SyncFolderItems.

import '../../../core/utils/category_colors.dart';
import '../unsubscribe_service.dart' show encodeListUnsubscribe;
import '../../security/mail_classification.dart' show MailLabel;
import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/calendar_event_model.dart';

class EwsXmlParser {
  /// Как [parseResponse], но крупный ответ (письма с телами, синхронизация
  /// сотен элементов) разбирается в отдельном изоляте: регулярные выражения
  /// и построение DOM по мегабайтам XML на главном изоляте дёргали интерфейс.
  static Future<XmlDocument> parseResponseAsync(String body) =>
      MailBodyProcessor.heavy(body, parseResponse, background: true);

  /// Разобрать ответ EWS, нормализовав namespace-префиксы.
  ///
  /// Пакет `xml` матчит элементы по qualifiedName, поэтому `<t:Message>`
  /// не находится через `findAllElements('Message')`. Exchange всегда
  /// возвращает теги с префиксами (t:, m:, s:). Убираем префиксы из имён
  /// тегов и xmlns-объявлений, чтобы весь парсинг работал по простым именам.
  static XmlDocument parseResponse(String body) {
    // Правим только сами теги, не текст между ними (1.6.18): раньше замены шли
    // по всему ответу, и в тексте письма строка вида « ключ:значение=…»
    // теряла «ключ:», а в HTML-теле пропадали атрибуты xmlns.
    //    ВАЖНО: в Dart replaceAll трактует '$1' как ЛИТЕРАЛ (не backreference!),
    //    поэтому только replaceAllMapped с m[1]. Раньше был replaceAll(..., r'$1'),
    //    из-за чего вместо '<' вставлялся текст '$1' и XML ломался.
    final s = body.replaceAllMapped(_tag, (m) {
      var t = m[0]!;
      // 1. xmlns:PREFIX="..." и xmlns="..." — чтобы после снятия префиксов
      //    документ не ссылался на неопределённые пространства имён.
      t = t.replaceAll(_xmlnsAttr, '');
      // 2. Префикс имени тега: <t:Foo> → <Foo>, </m:Bar> → </Bar>.
      t = t.replaceFirstMapped(_tagPrefix, (x) => x[1]!);
      // 3. Префиксы атрибутов вида t:Id="..." (редко, но встречается).
      return t.replaceAllMapped(_attrPrefix, (x) => '${x[1]}${x[2]}');
    });
    return XmlDocument.parse(s);
  }

  static final _tag = RegExp(r'<[^<>]*>');
  static final _xmlnsAttr = RegExp(r'\sxmlns(:\w+)?="[^"]*"');
  static final _tagPrefix = RegExp(r'^(</?)\w+:');
  static final _attrPrefix = RegExp(r'(\s)\w+:(\w+=)');

  // ════════════════════════ FOLDERS ════════════════════════

  static List<FolderModel> parseFolders(XmlDocument doc, String accountId) {
    final folders = <FolderModel>[];

    for (final folderEl in doc.findAllElements('Folder')) {
      final folder = _parseFolder(folderEl, accountId);
      if (folder != null) folders.add(folder);
    }

    for (final folderEl in doc.findAllElements('CalendarFolder')) {
      final folder = _parseFolder(folderEl, accountId, overrideType: FolderType.custom);
      if (folder != null) folders.add(folder);
    }

    for (final folderEl in doc.findAllElements('ContactsFolder')) {
      final folder = _parseFolder(folderEl, accountId, overrideType: FolderType.custom);
      if (folder != null) folders.add(folder);
    }

    for (final folderEl in doc.findAllElements('TasksFolder')) {
      final folder = _parseFolder(folderEl, accountId, overrideType: FolderType.custom);
      if (folder != null) folders.add(folder);
    }

    AppLogger.info('EWS parsed ${folders.length} folders');
    return folders;
  }

  static FolderModel? _parseFolder(XmlElement el, String accountId, {FolderType? overrideType}) {
    final id = el.findElements('FolderId').firstOrNull?.getAttribute('Id');
    final displayName = el.findElements('DisplayName').firstOrNull?.innerText;
    if (id == null || displayName == null) return null;

    final parentId = el.findElements('ParentFolderId').firstOrNull?.getAttribute('Id');
    final unreadCount = int.tryParse(el.findElements('UnreadCount').firstOrNull?.innerText ?? '0') ?? 0;
    final totalCount = int.tryParse(el.findElements('TotalCount').firstOrNull?.innerText ?? '0') ?? 0;
    final folderClass = el.findElements('FolderClass').firstOrNull?.innerText ?? '';

    final type = overrideType ?? _mapFolderClass(displayName, folderClass);

    return FolderModel(
      id: id,
      accountId: accountId,
      parentId: parentId,
      displayName: displayName,
      type: type,
      serverPath: id,
      unreadCount: unreadCount,
      totalCount: totalCount,
      showInUnified: FolderModel.unifiedByDefault(type),
      isSynced: true,
      sortOrder: _folderSortOrder(type),
    );
  }

  static FolderType _mapFolderClass(String name, String folderClass) {
    final lower = name.toLowerCase();
    if (lower == 'inbox' || lower == 'входящие') return FolderType.inbox;
    if (lower == 'sent items' || lower == 'отправленные') return FolderType.sent;
    if (lower == 'drafts' || lower == 'черновики') return FolderType.drafts;
    if (lower == 'deleted items' || lower == 'удалённые' || lower == 'удаленные') return FolderType.trash;
    if (lower == 'outbox' || lower == 'исходящие') return FolderType.outbox;
    // «Спам» и «Архив» — по названию на разных языках и только верхнего
    // уровня, с ручным выбором в настройках ящика: SpecialFolders при
    // сохранении списка (1.7.2+106). Здесь раньше были два языка, и
    // подпапка «Входящие/Архив» тоже становилась архивом.
    return FolderType.custom;
  }

  /// Стандартные имена Exchange → типы папок (1.7.2+107).
  static const distinguishedTypes = <String, FolderType>{
    'inbox': FolderType.inbox,
    'sentitems': FolderType.sent,
    'drafts': FolderType.drafts,
    'deleteditems': FolderType.trash,
    'junkemail': FolderType.junk,
    'outbox': FolderType.outbox,
  };

  /// Типы папок по стандартным папкам ящика ([byId]: id папки → тип; 1.7.2+107).
  ///
  /// Раньше EWS узнавал «Входящие», «Отправленные», «Черновики»,
  /// «Удалённые», «Исходящие» только по русским и английским названиям: у
  /// ящика на немецком («Posteingang») или французском («Boîte de
  /// réception») это были обычные папки — без «Входящих» не работали «Вся
  /// почта», уведомления и многое другое. Теперь тип — по id стандартной
  /// папки, который сообщает сервер (GetFolder с DistinguishedFolderId), на
  /// любом языке. Папка, чей тип дан только по названию, при известной
  /// стандартной папке того же типа становится обычной (подпапка
  /// «Входящие» внутри проекта). Ни один id не совпал — список как был (на
  /// случай, если сервер отдаёт id в другом виде).
  static List<FolderModel> applyDistinguished(List<FolderModel> folders, Map<String, FolderType> byId) {
    if (byId.isEmpty || !folders.any((f) => byId.containsKey(f.id))) return folders;
    final known = byId.values.toSet();
    return [for (final f in folders) _distinguished(f, byId[f.id], known)];
  }

  static FolderModel _distinguished(FolderModel f, FolderType? t, Set<FolderType> known) {
    if (t != null) return f.type == t ? f : _retyped(f, t);
    return known.contains(f.type) ? _retyped(f, FolderType.custom) : f;
  }

  static FolderModel _retyped(FolderModel f, FolderType t) => FolderModel(
        id: f.id,
        accountId: f.accountId,
        parentId: f.parentId,
        displayName: f.displayName,
        type: t,
        serverPath: f.serverPath,
        unreadCount: f.unreadCount,
        totalCount: f.totalCount,
        showInUnified: FolderModel.unifiedByDefault(t),
        isFavorite: f.isFavorite,
        sortOrder: _folderSortOrder(t),
        isSynced: f.isSynced,
        iconName: f.iconName,
      );

  static int _folderSortOrder(FolderType type) {
    switch (type) {
      case FolderType.inbox: return 0;
      case FolderType.drafts: return 1;
      case FolderType.sent: return 2;
      case FolderType.outbox: return 3;
      case FolderType.archive: return 4;
      case FolderType.junk: return 5;
      case FolderType.trash: return 6;
      case FolderType.custom: return 10;
    }
  }

  // ════════════════════════ EMAILS (FindItem) ════════════════════════

  /// Почтовые элементы EWS. Приглашения, ответы и отмены встреч приходят
  /// не как Message, а своими элементами — раньше разбирался только
  /// Message, и такие письма в ящике не появлялись вовсе.
  static const mailItemTags = {
    'Message',
    'MeetingRequest',
    'MeetingResponse',
    'MeetingCancellation',
    'MeetingMessage',
    'PostItem',
  };

  /// Почтовые элементы внутри [parent]: прямые дети или (deep) все потомки.
  static Iterable<XmlElement> mailItems(XmlNode parent, {bool deep = true}) =>
      (deep ? parent.descendants : parent.children)
          .whereType<XmlElement>()
          .where((e) => mailItemTags.contains(e.name.local));

  static List<EmailModel> parseEmails(XmlDocument doc, String accountId, String folderId) {
    final emails = <EmailModel>[];

    for (final msg in mailItems(doc)) {
      final email = _parseEmailFromFindItem(msg, accountId, folderId);
      if (email != null) emails.add(email);
    }

    return emails;
  }

  static EmailModel? _parseEmailFromFindItem(XmlElement msg, String accountId, String folderId) {
    final itemId = msg.findElements('ItemId').firstOrNull?.getAttribute('Id');
    if (itemId == null) return null;

    final subject = msg.findElements('Subject').firstOrNull?.innerText ?? '';
    final dateReceived = msg.findElements('DateTimeReceived').firstOrNull?.innerText;
    final dateSent = msg.findElements('DateTimeSent').firstOrNull?.innerText;
    final isRead = msg.findElements('IsRead').firstOrNull?.innerText == 'true';
    final hasAttachments = msg.findElements('HasAttachments').firstOrNull?.innerText == 'true';
    final importance = msg.findElements('Importance').firstOrNull?.innerText;
    final size = int.tryParse(msg.findElements('Size').firstOrNull?.innerText ?? '');
    final sensitivity = msg.findElements('Sensitivity').firstOrNull?.innerText;
    final preview = msg.findElements('Preview').firstOrNull?.innerText;
    final conversationId = msg.findElements('ConversationId').firstOrNull?.getAttribute('Id');
    final internetMessageId = msg.findElements('InternetMessageId').firstOrNull?.innerText;
    final referencesStr = msg.findElements('References').firstOrNull?.innerText;
    final readReceipt = msg.findElements('IsReadReceiptRequested').firstOrNull?.innerText == 'true';

    // From
    final fromMailbox = msg.findElements('From').firstOrNull?.findElements('Mailbox').firstOrNull;
    final from = _parseMailbox(fromMailbox);

    // To
    final toList = <EmailAddress>[];
    final toRecipients = msg.findElements('ToRecipients').firstOrNull;
    if (toRecipients != null) {
      for (final mb in toRecipients.findElements('Mailbox')) {
        toList.add(_parseMailbox(mb));
      }
    }

    // Cc
    final ccList = <EmailAddress>[];
    final ccRecipients = msg.findElements('CcRecipients').firstOrNull;
    if (ccRecipients != null) {
      for (final mb in ccRecipients.findElements('Mailbox')) {
        ccList.add(_parseMailbox(mb));
      }
    }

    // Bcc — есть только у своих писем (черновики, отправленные): без него
    // черновик из Outlook открывался без скрытой копии (1.7.2+111).
    final bccList = <EmailAddress>[
      for (final mb in msg.findElements('BccRecipients').firstOrNull?.findElements('Mailbox') ??
          const <XmlElement>[])
        _parseMailbox(mb),
    ];

    // Flag
    final flagStatus = msg.findElements('Flag').firstOrNull?.findElements('FlagStatus').firstOrNull?.innerText;
    final isFlagged = flagStatus == 'Flagged';

    // Categories
    final categories = <String>[];
    final catsEl = msg.findElements('Categories').firstOrNull;
    if (catsEl != null) {
      for (final cat in catsEl.findElements('String')) {
        if (cat.innerText.isNotEmpty) categories.add(cat.innerText);
      }
    }

    // Priority
    EmailPriority priority;
    switch (importance) {
      case 'High': priority = EmailPriority.high; break;
      case 'Low': priority = EmailPriority.low; break;
      default: priority = EmailPriority.normal;
    }

    return EmailModel(
      id: itemId,
      accountId: accountId,
      folderId: folderId,
      conversationId: conversationId,
      internetMessageId: internetMessageId,
      references: referencesStr?.split(' ').where((s) => s.isNotEmpty).toList(),
      from: from,
      to: toList,
      cc: ccList,
      bcc: bccList,
      subject: subject,
      bodyPreview: preview,
      receivedAt: dateReceived != null ? (DateTime.tryParse(dateReceived)?.toUtc() ?? DateTime.now().toUtc()) : DateTime.now().toUtc(),
      sentAt: dateSent != null ? DateTime.tryParse(dateSent)?.toUtc() : null,
      isRead: isRead,
      isFlagged: isFlagged,
      hasAttachments: hasAttachments,
      priority: priority,
      categories: categories,
      size: size,
      sensitivity: sensitivity,
      readReceiptRequested: readReceipt,
    );
  }

  // ════════════════════════ EMAIL DETAIL (GetItem) ════════════════════════

  static EmailModel parseEmailDetail(XmlDocument doc, String accountId) {
    final msg = mailItems(doc).firstOrNull;
    if (msg == null) throw Exception('No Message element in GetItem response');

    final base = _parseEmailFromFindItem(msg, accountId, 'detail');
    if (base == null) throw Exception('Failed to parse email');

    // Body
    final bodyEl = msg.findElements('Body').firstOrNull;
    String? bodyHtml;
    String? bodyPlain;
    if (bodyEl != null) {
      final bodyType = bodyEl.getAttribute('BodyType');
      final content = bodyEl.innerText;
      if (bodyType == 'HTML') {
        bodyHtml = content;
      } else {
        bodyPlain = content;
      }
    }

    // TextBody (plain text fallback)
    final textBody = msg.findElements('TextBody').firstOrNull?.innerText;
    bodyPlain ??= textBody;

    // Attachments
    final attachments = <EmailAttachment>[];
    final attachmentsEl = msg.findElements('Attachments').firstOrNull;
    if (attachmentsEl != null) {
      for (final fileAtt in attachmentsEl.findElements('FileAttachment')) {
        final attId = fileAtt.findElements('AttachmentId').firstOrNull?.getAttribute('Id');
        final name = fileAtt.findElements('Name').firstOrNull?.innerText;
        final contentType = fileAtt.findElements('ContentType').firstOrNull?.innerText;
        final attSize = int.tryParse(fileAtt.findElements('Size').firstOrNull?.innerText ?? '0') ?? 0;
        final isInline = fileAtt.findElements('IsInline').firstOrNull?.innerText == 'true';
        // Content-ID — для подстановки встроенных картинок (cid:) в тело.
        final contentId = fileAtt.findElements('ContentId').firstOrNull?.innerText;

        if (attId != null && name != null) {
          attachments.add(EmailAttachment(
            id: attId,
            name: name,
            mimeType: contentType ?? 'application/octet-stream',
            size: attSize,
            isInline: isInline,
            contentId: EmailAttachment.normalizeCid(contentId),
          ));
        }
      }
      // Вложенное письмо (Outlook «Вложить элемент»): у него нет файла, только
      // тема как имя. Прежде такие вложения не показывались вовсе — у письма
      // была скрепка, а вложений не было. Скачивается как MimeContent
      // (GetAttachment с IncludeMimeContent) и открывается письмом.
      for (final itemAtt in attachmentsEl.findElements('ItemAttachment')) {
        final attId = itemAtt.findElements('AttachmentId').firstOrNull?.getAttribute('Id');
        if (attId == null) continue;
        final rawName = (itemAtt.findElements('Name').firstOrNull?.innerText ?? '').trim();
        final base = (rawName.isEmpty ? 'message' : rawName).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
        final name = base.toLowerCase().endsWith('.eml') ? base : '$base.eml';
        attachments.add(EmailAttachment(
          id: attId,
          name: name,
          mimeType: 'message/rfc822',
          size: int.tryParse(itemAtt.findElements('Size').firstOrNull?.innerText ?? '0') ?? 0,
          isInline: false,
        ));
      }
    }

    // ReplyTo (запрашивается в GetItem; раньше не читался — ответ всегда
    // уходил отправителю, даже когда письмо просило отвечать на другой адрес).
    final replyTo = <EmailAddress>[
      for (final mb in msg.findElements('ReplyTo').firstOrNull?.findElements('Mailbox') ?? const <XmlElement>[])
        _parseMailbox(mb),
    ].where((a) => a.email.isNotEmpty).toList();

    // IsReplied / IsForwarded. EWS отдаёт IconIndex именем (IconIndexType:
    // «MailReplied», «MailForwarded»), а не числом MAPI (261/262), как
    // сравнивалось раньше — отметки «отвечено/переслано» с сервера не
    // появлялись никогда (1.6.18). Числа оставлены на всякий случай.
    final icon = msg.findElements('IconIndex').firstOrNull?.innerText.trim();
    final isReplied = icon == 'MailReplied' || icon == '261';
    final isForwarded = icon == 'MailForwarded' || icon == '262';

    // Authentication-Results (SPF/DKIM/DMARC) из заголовков — сигнал для антифишинга
    // на Exchange (InternetMessageHeaders запрашиваются в GetItem).
    String? authResults;
    for (final h in msg.findAllElements('InternetMessageHeader')) {
      if (h.getAttribute('HeaderName')?.toLowerCase() == 'authentication-results') {
        authResults = h.innerText.trim();
        break;
      }
    }
    if (authResults == null) {
      for (final h in msg.findAllElements('InternetMessageHeader')) {
        if (h.getAttribute('HeaderName')?.toLowerCase() == 'received-spf') {
          authResults = 'spf=${h.innerText.trim()}';
          break;
        }
      }
    }

    // Рассылка: List-Unsubscribe / List-Unsubscribe-Post / List-Id.
    String? header(String name) {
      for (final h in msg.findAllElements('InternetMessageHeader')) {
        if (h.getAttribute('HeaderName')?.toLowerCase() == name) return h.innerText.trim();
      }
      return null;
    }
    final listUnsubscribe = encodeListUnsubscribe(
      unsubscribe: header('list-unsubscribe'),
      post: header('list-unsubscribe-post'),
      listId: header('list-id'),
    );

    // Гриф в MIME (X-Ogneliss-*): заголовки приходят только в GetItem.
    final label = MailLabel.fromHeaders(
      sensitivity: base.sensitivity,
      classification: header('x-ogneliss-classification'),
      handling: header('x-ogneliss-handling'),
    );

    return base.copyWith(
      bodyHtml: bodyHtml,
      bodyPlain: bodyPlain,
      attachments: attachments,
      replyTo: replyTo,
      isReplied: isReplied,
      isForwarded: isForwarded,
      authResults: authResults,
      listUnsubscribe: listUnsubscribe,
      sensitivity: label,
    );
  }

  // ════════════════════════ ATTACHMENT ════════════════════════

  static Uint8List parseAttachmentContent(XmlDocument doc) {
    // FileAttachment → Content; вложенное письмо (ItemAttachment) → MimeContent.
    final content = doc.findAllElements('Content').firstOrNull?.innerText ??
        doc.findAllElements('MimeContent').firstOrNull?.innerText;
    if (content == null) {
      final code = doc.findAllElements('ResponseCode').firstOrNull?.innerText;
      throw Exception('EWS: вложение не получено${code != null ? ' ($code)' : ''}');
    }
    return base64.decode(content.replaceAll(RegExp(r'\s'), ''));
  }

  // ════════════════════════ CONTACTS (ResolveNames) ════════════════════════

  /// Отчество из поля «Инициалы», если там записано слово целиком
  /// («Владимирович»), а не инициалы («В.», «Ю.В.»).
  static String? patronymicFromInitials(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 4 || t.contains('.') || t.contains(' ')) return null;
    return RegExp(r'^[A-Za-zА-Яа-яЁё-]+$').hasMatch(t) ? t : null;
  }

  static List<ContactModel> parseResolveNames(XmlDocument doc, String accountId) {
    final contacts = <ContactModel>[];

    for (final resolution in doc.findAllElements('Resolution')) {
      final mailbox = resolution.findElements('Mailbox').firstOrNull;
      final contact = resolution.findElements('Contact').firstOrNull;

      final email = mailbox?.findElements('EmailAddress').firstOrNull?.innerText ?? '';
      final name = mailbox?.findElements('Name').firstOrNull?.innerText ?? email;
      final mailboxType = mailbox?.findElements('MailboxType').firstOrNull?.innerText ?? '';

      if (email.isEmpty) continue;

      String? firstName, lastName, middleName, company, department, jobTitle, phoneWork, phoneMobile, office, city, manager;

      if (contact != null) {
        firstName = contact.findElements('GivenName').firstOrNull?.innerText;
        lastName = contact.findElements('Surname').firstOrNull?.innerText;
        middleName = contact.findElements('MiddleName').firstOrNull?.innerText ??
            patronymicFromInitials(contact.findElements('Initials').firstOrNull?.innerText);
        company = contact.findElements('CompanyName').firstOrNull?.innerText;
        department = contact.findElements('Department').firstOrNull?.innerText;
        jobTitle = contact.findElements('JobTitle').firstOrNull?.innerText;
        office = contact.findElements('OfficeLocation').firstOrNull?.innerText;
        manager = contact.findElements('Manager').firstOrNull?.innerText;
        city = contact.findElements('BusinessAddressCity').firstOrNull?.innerText
            ?? contact.findElements('City').firstOrNull?.innerText;

        // Phones
        final phones = contact.findElements('PhoneNumbers').firstOrNull;
        if (phones != null) {
          for (final entry in phones.findElements('Entry')) {
            final key = entry.getAttribute('Key');
            if (key == 'BusinessPhone') phoneWork = entry.innerText;
            if (key == 'MobilePhone') phoneMobile = entry.innerText;
          }
        }
      }

      contacts.add(ContactModel(
        id: 'gal_${email.hashCode}',
        accountId: accountId,
        email: email,
        displayName: name.isNotEmpty ? name : email,
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        manager: (manager ?? '').trim().isEmpty ? null : manager!.trim(),
        company: company,
        department: department,
        jobTitle: jobTitle,
        phoneWork: phoneWork,
        phoneMobile: phoneMobile,
        office: office,
        city: city,
        source: ContactSource.exchangeGal,
        isGroup: mailboxType == 'PublicDL' || mailboxType == 'PrivateDL',
      ));
    }

    return contacts;
  }

  /// Участники группы рассылки (ExpandDL). Вложенные группы помечены isGroup.
  static List<ContactModel> parseExpandDl(XmlDocument doc, String accountId) {
    final out = <ContactModel>[];
    for (final exp in doc.findAllElements('DLExpansion')) {
      for (final m in exp.findElements('Mailbox')) {
        final email = m.findElements('EmailAddress').firstOrNull?.innerText.trim() ?? '';
        if (email.isEmpty) continue;
        final name = m.findElements('Name').firstOrNull?.innerText.trim() ?? '';
        final type = m.findElements('MailboxType').firstOrNull?.innerText ?? '';
        out.add(ContactModel(
          id: 'dl_${email.toLowerCase().hashCode}',
          accountId: accountId,
          email: email,
          displayName: name.isNotEmpty ? name : email,
          source: ContactSource.exchangeGal,
          isGroup: type == 'PublicDL' || type == 'PrivateDL',
        ));
      }
    }
    return out;
  }

  /// Разобрать контакты из FindItem по папке Contacts (личные контакты).
  static List<ContactModel> parseContacts(XmlDocument doc, String accountId) {
    final contacts = <ContactModel>[];
    for (final c in doc.findAllElements('t:Contact').isEmpty
        ? doc.findAllElements('Contact')
        : doc.findAllElements('t:Contact')) {
      final itemId = c.findElements('ItemId').firstOrNull?.getAttribute('Id')
          ?? c.findElements('t:ItemId').firstOrNull?.getAttribute('Id');
      String findText(String tag) =>
          c.findElements(tag).firstOrNull?.innerText
          ?? c.findElements('t:$tag').firstOrNull?.innerText
          ?? '';

      final displayName = findText('DisplayName');
      final firstName = findText('GivenName');
      final lastName = findText('Surname');
      // Отчество: MiddleName контакта или CompleteName/MiddleName; в AD
      // российских организаций его иногда кладут в «Инициалы» целиком.
      // Раньше не читалось — в списке было «Фамилия Имя» без отчества.
      final completeName = c.findElements('CompleteName').firstOrNull
          ?? c.findElements('t:CompleteName').firstOrNull;
      String middleName = findText('MiddleName');
      if (middleName.isEmpty && completeName != null) {
        middleName = completeName.findElements('MiddleName').firstOrNull?.innerText
            ?? completeName.findElements('t:MiddleName').firstOrNull?.innerText
            ?? '';
      }
      if (middleName.isEmpty) middleName = patronymicFromInitials(findText('Initials')) ?? '';
      final company = findText('CompanyName');
      final jobTitle = findText('JobTitle');
      final department = findText('Department');
      final manager = findText('Manager');
      final office = findText('OfficeLocation');

      // Email
      String email = '';
      final emailsEl = c.findElements('EmailAddresses').firstOrNull
          ?? c.findElements('t:EmailAddresses').firstOrNull;
      if (emailsEl != null) {
        final entry = emailsEl.findElements('Entry').firstOrNull
            ?? emailsEl.findElements('t:Entry').firstOrNull;
        email = entry?.innerText ?? '';
        // EWS возвращает в формате "Name (SMTP:addr)" — извлекаем адрес
        final m = RegExp(r'[\w.\-]+@[\w.\-]+').firstMatch(email);
        if (m != null) email = m.group(0)!;
      }

      // Phones
      String? phoneWork, phoneMobile;
      final phonesEl = c.findElements('PhoneNumbers').firstOrNull
          ?? c.findElements('t:PhoneNumbers').firstOrNull;
      if (phonesEl != null) {
        for (final entry in [...phonesEl.findElements('Entry'), ...phonesEl.findElements('t:Entry')]) {
          final key = entry.getAttribute('Key');
          if (key == 'BusinessPhone') phoneWork = entry.innerText;
          if (key == 'MobilePhone') phoneMobile = entry.innerText;
        }
      }

      if (displayName.isEmpty && email.isEmpty) continue;

      contacts.add(ContactModel(
        // id — сам ItemId: по нему контакт удаляется на сервере и с ним
        // совпадает id контакта, созданного в приложении. Раньше был хеш
        // ('ews_<число>'): удаление на сервере не работало, созданный в
        // приложении контакт после синка задваивался.
        id: itemId ?? 'ews_${(displayName + email).hashCode}',
        accountId: accountId,
        email: email,
        displayName: displayName.isNotEmpty ? displayName : email,
        firstName: firstName.isEmpty ? null : firstName,
        lastName: lastName.isEmpty ? null : lastName,
        middleName: middleName.trim().isEmpty ? null : middleName.trim(),
        company: company.isEmpty ? null : company,
        jobTitle: jobTitle.isEmpty ? null : jobTitle,
        department: department.isEmpty ? null : department,
        manager: manager.trim().isEmpty ? null : manager.trim(),
        office: office.trim().isEmpty ? null : office.trim(),
        phoneWork: phoneWork,
        phoneMobile: phoneMobile,
        source: ContactSource.exchangeGal,
      ));
    }
    return contacts;
  }

  /// Разобрать заметки из FindItem по папке Notes (IPM.StickyNote).
  /// Возвращает список Map с полями id/title/body для сохранения в БД.
  static List<Map<String, String>> parseNotes(XmlDocument doc) {
    final notes = <Map<String, String>>[];
    // Заметки приходят как Message/Note items
    final items = [
      ...doc.findAllElements('t:Message'),
      ...doc.findAllElements('Message'),
      ...doc.findAllElements('t:Note'),
      ...doc.findAllElements('Note'),
    ];
    for (final item in items) {
      final itemClass = item.findElements('ItemClass').firstOrNull?.innerText
          ?? item.findElements('t:ItemClass').firstOrNull?.innerText
          ?? '';
      // Берём только заметки
      if (!itemClass.toLowerCase().contains('stickynote') && itemClass.isNotEmpty) {
        continue;
      }
      final itemId = item.findElements('ItemId').firstOrNull?.getAttribute('Id')
          ?? item.findElements('t:ItemId').firstOrNull?.getAttribute('Id');
      final subject = item.findElements('Subject').firstOrNull?.innerText
          ?? item.findElements('t:Subject').firstOrNull?.innerText
          ?? '';
      final body = item.findElements('Body').firstOrNull?.innerText
          ?? item.findElements('t:Body').firstOrNull?.innerText
          ?? '';
      if (itemId == null && subject.isEmpty && body.isEmpty) continue;
      notes.add({
        'serverId': itemId ?? '',
        'title': subject,
        'body': body,
      });
    }
    return notes;
  }

  // ════════════════════════ CALENDAR ════════════════════════

  static List<CalendarEventModel> parseCalendarEvents(XmlDocument doc, String accountId) {
    final events = <CalendarEventModel>[];

    for (final item in doc.findAllElements('CalendarItem')) {
      final event = _parseCalendarItem(item, accountId);
      if (event != null) events.add(event);
    }

    return events;
  }

  static CalendarEventModel? _parseCalendarItem(XmlElement item, String accountId) {
    final itemId = item.findElements('ItemId').firstOrNull?.getAttribute('Id');
    if (itemId == null) return null;

    final subject = item.findElements('Subject').firstOrNull?.innerText ?? '';
    final location = item.findElements('Location').firstOrNull?.innerText;
    final startStr = item.findElements('Start').firstOrNull?.innerText;
    final endStr = item.findElements('End').firstOrNull?.innerText;
    final isAllDay = item.findElements('IsAllDayEvent').firstOrNull?.innerText == 'true';
    final body = item.findElements('Body').firstOrNull?.innerText;
    final sensitivity = item.findElements('Sensitivity').firstOrNull?.innerText;
    final showAs = item.findElements('LegacyFreeBusyStatus').firstOrNull?.innerText;
    final organizerMb = item.findElements('Organizer').firstOrNull?.findElements('Mailbox').firstOrNull;
    final organizerEmail = organizerMb?.findElements('EmailAddress').firstOrNull?.innerText;
    final onlineMeeting = item.findElements('OnlineMeetingExternalLink').firstOrNull?.innerText;
    final categories = [
      for (final c in item.findElements('Categories').firstOrNull?.findElements('String') ?? const <XmlElement>[])
        c.innerText,
    ];

    // Attendees
    final attendees = <EventAttendee>[];
    for (final required in item.findElements('RequiredAttendees')) {
      for (final att in required.findElements('Attendee')) {
        final mb = att.findElements('Mailbox').firstOrNull;
        if (mb != null) {
          attendees.add(EventAttendee(
            email: mb.findElements('EmailAddress').firstOrNull?.innerText ?? '',
            displayName: mb.findElements('Name').firstOrNull?.innerText,
            isRequired: true,
            response: EventAttendee.responseFromEws(att.findElements('ResponseType').firstOrNull?.innerText),
          ));
        }
      }
    }
    for (final optional in item.findElements('OptionalAttendees')) {
      for (final att in optional.findElements('Attendee')) {
        final mb = att.findElements('Mailbox').firstOrNull;
        if (mb != null) {
          attendees.add(EventAttendee(
            email: mb.findElements('EmailAddress').firstOrNull?.innerText ?? '',
            displayName: mb.findElements('Name').firstOrNull?.innerText,
            isRequired: false,
            response: EventAttendee.responseFromEws(att.findElements('ResponseType').firstOrNull?.innerText),
          ));
        }
      }
    }

    // Recurrence
    RecurrenceType recurrence = RecurrenceType.none;
    final recEl = item.findElements('Recurrence').firstOrNull;
    if (recEl != null) {
      if (recEl.findElements('DailyRecurrence').isNotEmpty) {
        recurrence = RecurrenceType.daily;
      } else if (recEl.findElements('WeeklyRecurrence').isNotEmpty) {
        recurrence = RecurrenceType.weekly;
      } else if (recEl.findElements('AbsoluteMonthlyRecurrence').isNotEmpty) {
        recurrence = RecurrenceType.monthly;
      } else if (recEl.findElements('AbsoluteYearlyRecurrence').isNotEmpty) {
        recurrence = RecurrenceType.yearly;
      }
    }

    // Reminder
    // ReminderIsSet=false — напоминание выключено, хотя минуты сервер всё
    // равно присылает (по умолчанию 15).
    final reminderSet = item.findElements('ReminderIsSet').firstOrNull?.innerText != 'false';
    final reminderStr = item.findElements('ReminderMinutesBeforeStart').firstOrNull?.innerText;
    final reminderMinutes = reminderSet ? int.tryParse(reminderStr ?? '') : null;

    // EWS возвращает время в UTC (суффикс Z). Храним в БД в UTC,
    // Событие с временем: EWS отдаёт UTC ('Z') → храним абсолютный момент, а
    // конвертация в локальное — при отображении (.toLocal()).
    // Событие «весь день»: EWS отдаёт полночь в поясе организатора в UTC
    // (для UTC+5 — 19:00Z накануне). Раньше бралась дата UTC как есть, и в
    // восточных поясах событие съезжало на день назад. Округляем к ближайшей
    // полуночи UTC и строим ЛОКАЛЬНУЮ полночь этой даты (плавающая дата).
    final DateTime startTime;
    final DateTime endTime;
    if (isAllDay) {
      final sd = (startStr != null ? DateTime.tryParse(startStr) : null)?.toUtc() ?? DateTime.now().toUtc();
      final ed = (endStr != null ? DateTime.tryParse(endStr) : null)?.toUtc() ?? sd.add(const Duration(days: 1));
      DateTime day(DateTime u) => u.hour >= 12
          ? DateTime(u.year, u.month, u.day + 1)
          : DateTime(u.year, u.month, u.day);
      startTime = day(sd);
      final e = day(ed);
      endTime = e.isAfter(startTime) ? e : DateTime(startTime.year, startTime.month, startTime.day + 1);
    } else {
      startTime = startStr != null
          ? (DateTime.tryParse(startStr)?.toUtc() ?? DateTime.now().toUtc())
          : DateTime.now().toUtc();
      endTime = endStr != null
          ? (DateTime.tryParse(endStr)?.toUtc() ?? startTime.add(const Duration(hours: 1)))
          : startTime.add(const Duration(hours: 1));
    }

    return CalendarEventModel(
      id: itemId,
      accountId: accountId,
      title: subject,
      description: body,
      location: location,
      onlineMeetingUrl: onlineMeeting,
      startTime: startTime,
      endTime: endTime,
      isAllDay: isAllDay,
      attendees: attendees,
      organizerEmail: organizerEmail,
      recurrence: recurrence,
      isPrivate: sensitivity == 'Private',
      colorValue: CategoryColors.valueOf(categories),
      showAs: _parseShowAs(showAs),
      reminders: reminderMinutes != null ? [EventReminder(minutesBefore: reminderMinutes)] : [],
      createdAt: DateTime.now(),
    );
  }

  static ShowAs _parseShowAs(String? value) {
    switch (value) {
      case 'Free': return ShowAs.free;
      case 'Tentative': return ShowAs.tentative;
      case 'Busy': return ShowAs.busy;
      case 'OOF': return ShowAs.outOfOffice;
      default: return ShowAs.busy;
    }
  }

  // ════════════════════════ CREATE ITEM RESPONSE ════════════════════════

  static String? parseCreateItemResponse(XmlDocument doc) {
    final responseMsg = doc.findAllElements('CreateItemResponseMessage').firstOrNull;
    if (responseMsg == null) return null;

    final responseClass = responseMsg.getAttribute('ResponseClass');
    if (responseClass != 'Success') {
      final error = responseMsg.findElements('MessageText').firstOrNull?.innerText;
      AppLogger.warning('CreateItem: $responseClass — $error');
      return null;
    }

    return responseMsg.findElements('ItemId').firstOrNull?.getAttribute('Id');
  }

  /// Проверить общий успех ответа
  static bool parseResponseSuccess(XmlDocument doc) {
    final msgs = doc.findAllElements('ResponseMessage');
    for (final msg in msgs) {
      if (msg.getAttribute('ResponseClass') == 'Error') return false;
    }
    // Также проверяем специфичные
    for (final name in ['CreateItemResponseMessage', 'UpdateItemResponseMessage',
        'MoveItemResponseMessage', 'DeleteItemResponseMessage']) {
      final msg = doc.findAllElements(name).firstOrNull;
      if (msg != null && msg.getAttribute('ResponseClass') != 'Success') return false;
    }
    return true;
  }

  // ════════════════════════ AUTODISCOVER ════════════════════════

  static String? parseAutodiscoverResponse(XmlDocument doc) {
    // Ищем EwsUrl или InternalUrl
    for (final protocol in doc.findAllElements('Protocol')) {
      final type = protocol.findElements('Type').firstOrNull?.innerText;
      if (type == 'EXCH' || type == 'EXPR') {
        final ewsUrl = protocol.findElements('EwsUrl').firstOrNull?.innerText;
        if (ewsUrl != null && ewsUrl.isNotEmpty) return ewsUrl;

        final asUrl = protocol.findElements('ASUrl').firstOrNull?.innerText;
        if (asUrl != null && asUrl.isNotEmpty) return asUrl;
      }
    }

    // Fallback: ищем любой EwsUrl
    final ewsUrl = doc.findAllElements('EwsUrl').firstOrNull?.innerText;
    return ewsUrl;
  }

  // ════════════════════════ HELPER ════════════════════════

  static EmailAddress _parseMailbox(XmlElement? el) {
    if (el == null) return const EmailAddress(email: '');
    final email = el.findElements('EmailAddress').firstOrNull?.innerText ?? '';
    final name = el.findElements('Name').firstOrNull?.innerText;
    return EmailAddress(email: email, displayName: name);
  }
}

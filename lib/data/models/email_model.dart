// lib/data/models/email_model.dart

import '../../core/utils/text_safe.dart';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' show MailCodec;

/// «=?UTF-8?B?…?=» (RFC 2047) → текст. Имена вложений IMAP, сохранённые до
/// исправления, раскодируются при чтении.
String? decodeMimeWords(String? v) {
  if (v == null || !v.contains('=?')) return v;
  try {
    final d = MailCodec.decodeHeader(v.trim());
    return (d == null || d.isEmpty) ? v : d;
  } catch (_) {
    return v;
  }
}

enum EmailPriority { low, normal, high }
enum EmailStatus { draft, queued, sending, delivered }

class EmailAddress {
  final String email;
  final String? displayName;
  const EmailAddress({required this.email, this.displayName});

  String get label => displayName ?? email;

  Map<String, dynamic> toMap() => {'email': email, 'displayName': displayName};
  factory EmailAddress.fromMap(Map<String, dynamic> m) =>
      // «name» — так адресатов пишет черновик.
      EmailAddress(email: m['email'] ?? '', displayName: m['displayName'] ?? m['name']);
}

class EmailAttachment {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String? localPath;
  final bool isInline;

  /// Content-ID встроенной части (без угловых скобок): на неё ссылается тело
  /// письма как `cid:…` — картинки в подписи и тексте писем Outlook.
  final String? contentId;

  const EmailAttachment({required this.id, required this.name, this.mimeType = '', this.size = 0, this.localPath, this.isInline = false, this.contentId});

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get category {
    final lower = mimeType.toLowerCase();
    if (lower.contains('pdf')) return 'pdf';
    if (lower.contains('image')) return 'image';
    if (lower.contains('word') || lower.contains('document')) return 'document';
    if (lower.contains('excel') || lower.contains('spreadsheet')) return 'spreadsheet';
    if (lower.contains('presentation') || lower.contains('powerpoint')) return 'presentation';
    if (lower.contains('zip') || lower.contains('rar')) return 'archive';
    return 'other';
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'mimeType': mimeType, 'size': size, 'localPath': localPath, 'isInline': isInline, if (contentId != null) 'contentId': contentId};
  factory EmailAttachment.fromMap(Map<String, dynamic> m) => EmailAttachment(
    id: m['id'] ?? '', name: decodeMimeWords(m['name'] as String?) ?? 'file', mimeType: m['mimeType'] ?? '',
    size: m['size'] ?? 0, localPath: m['localPath'], isInline: m['isInline'] ?? false,
    contentId: m['contentId'] as String?,
  );

  /// Запасная картинка Outlook для старых версий Word/Outlook (VML:
  /// image001.wmz, .emz, .wmf, .emf). В HTML на неё ссылается `cid:` в
  /// условном комментарии рядом с обычной PNG/JPEG той же картинки; WebView
  /// её не показывает, человеку она не нужна ни в тексте, ни в списке файлов.
  bool get isVmlPreview {
    final n = name.toLowerCase();
    final m = mimeType.toLowerCase();
    return n.endsWith('.wmz') ||
        n.endsWith('.emz') ||
        n.endsWith('.wmf') ||
        n.endsWith('.emf') ||
        m.contains('x-wmf') ||
        m.contains('x-emf') ||
        m.contains('x-ms-wmz') ||
        m.contains('x-ms-emz');
  }

  /// Content-ID в виде, в котором его ищет тело письма: без <>, нижний регистр.
  static String? normalizeCid(String? raw) {
    if (raw == null) return null;
    var c = raw.trim();
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    return c.isEmpty ? null : c.toLowerCase();
  }
}

class EmailModel {
  final String id;
  final String accountId;
  final String folderId;
  final String? folderName;
  final String? conversationId;
  final String? parentId;
  final String? internetMessageId;
  final List<String>? references;
  final EmailAddress from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;

  /// Reply-To: куда отвечать (рассылки, ящики поддержки, «от имени»).
  /// Пусто — отвечать отправителю.
  final List<EmailAddress> replyTo;
  final String subject;
  final String? bodyPlain;
  final String? bodyHtml;
  final String? authResults; // Authentication-Results/Received-SPF (антифишинг)
  /// Рассылка: JSON {"u": List-Unsubscribe, "p": List-Unsubscribe-Post, "id": List-Id}.
  final String? listUnsubscribe;
  final String? bodyPreview;
  final List<EmailAttachment> attachments;
  final DateTime receivedAt;
  final DateTime? sentAt;
  final bool isRead;
  final bool isFlagged;
  final bool isDraft;
  final bool isReplied;
  final bool isForwarded;
  final bool hasAttachments;
  final EmailPriority priority;
  final EmailStatus status;
  final List<String> tags;
  final List<String> categories;
  final String? classification;
  final String? sensitivity; // Normal/Personal/Private/Confidential
  final double? sentimentScore;
  final String? aiCategory;
  final String? aiRecommendation;
  final DateTime? extractedDeadline;
  final int? size;
  final bool readReceiptRequested;
  final bool isLocallyModified;
  final DateTime? cachedAt;
  final DateTime? remindAt; // снуз: когда напомнить о письме
  /// Приглашение на встречу (JSON: start, end, allDay, location, organizer,
  /// responseRequested, class). null — обычное письмо.
  final String? meetingJson;

  /// «На контроле»: 0 — нет, 1 — жду ответа, 2 — должен ответить,
  /// 3 — исполнено (см. emails.control_state).
  final int controlState;

  /// «Посмотреть позже»: 0 — нет, 1 — отложено (до [remindAt] или без даты),
  /// 2 — вернулось (см. emails.later_state).
  final int laterState;

  /// «На контроле»: кто из «Кому» уже ответил (адреса через запятую).
  final String? controlReplied;

  /// Срок контроля: не ответили к этому времени — уведомление.
  final DateTime? followUpAt;

  const EmailModel({
    required this.id, required this.accountId, required this.folderId,
    this.folderName, this.conversationId, this.parentId, this.internetMessageId,
    this.references, required this.from, required this.to,
    this.cc = const [], this.bcc = const [], this.replyTo = const [], required this.subject,
    this.bodyPlain, this.bodyHtml, this.bodyPreview, this.authResults, this.listUnsubscribe,
    this.attachments = const [], required this.receivedAt, this.sentAt,
    this.isRead = false, this.isFlagged = false, this.isDraft = false,
    this.isReplied = false, this.isForwarded = false, this.hasAttachments = false,
    this.priority = EmailPriority.normal, this.status = EmailStatus.delivered,
    this.tags = const [], this.categories = const [],
    this.classification, this.sensitivity, this.sentimentScore, this.aiCategory,
    this.aiRecommendation, this.extractedDeadline, this.size,
    this.readReceiptRequested = false, this.isLocallyModified = false, this.cachedAt,
    this.remindAt, this.meetingJson, this.controlState = 0, this.laterState = 0,
    this.controlReplied, this.followUpAt,
  });

  /// Превью для ленты, уведомлений и карточек: без сущностей HTML и
  /// невидимых символов рассылок (27.10.2026). Сохранённое превью целиком из
  /// них (письма, полученные раньше) — из текста письма, если он есть.
  String get preview {
    final p = previewKeepingLines(bodyPreview);
    if (p != null) return fixUtf16(p);
    return fixUtf16(previewKeepingLines(bodyPlain) ?? '');
  }

  /// true, если наш адрес — только в копии (Cc), но не в основных получателях (To).
  /// Используется для снижения критичности письма и набора действий (FYI).
  bool isCcRecipient(String myEmail) {
    final me = myEmail.toLowerCase().trim();
    if (me.isEmpty) return false;
    final inTo = to.any((a) => a.email.toLowerCase().trim() == me);
    final inCc = cc.any((a) => a.email.toLowerCase().trim() == me);
    return inCc && !inTo;
  }
  bool get isHighPriority => priority == EmailPriority.high;

  /// Данные приглашения на встречу, если письмо — приглашение.
  EmailMeeting? get meeting => EmailMeeting.parse(meetingJson);
  int get recipientCount => to.length + cc.length + bcc.length;

  EmailModel copyWith({
    String? id, String? accountId, String? folderId, String? folderName,
    String? conversationId, String? parentId, String? internetMessageId,
    List<String>? references, EmailAddress? from, List<EmailAddress>? to,
    List<EmailAddress>? cc, List<EmailAddress>? bcc, List<EmailAddress>? replyTo, String? subject,
    String? bodyPlain, String? bodyHtml, String? bodyPreview, String? authResults, String? listUnsubscribe,
    List<EmailAttachment>? attachments, DateTime? receivedAt, DateTime? sentAt,
    bool? isRead, bool? isFlagged, bool? isDraft, bool? isReplied, bool? isForwarded,
    bool? hasAttachments, EmailPriority? priority, EmailStatus? status, String? sensitivity,
    List<String>? tags, List<String>? categories, String? classification,
    double? sentimentScore, String? aiCategory, String? aiRecommendation,
    DateTime? extractedDeadline, int? size, bool? readReceiptRequested,
    bool? isLocallyModified, DateTime? cachedAt, DateTime? remindAt, String? meetingJson,
    int? controlState, int? laterState, String? controlReplied, DateTime? followUpAt,
    bool clearBody = false, bool clearReminder = false, bool clearControl = false,
  }) {
    return EmailModel(
      id: id ?? this.id, accountId: accountId ?? this.accountId,
      folderId: folderId ?? this.folderId, folderName: folderName ?? this.folderName,
      conversationId: conversationId ?? this.conversationId,
      parentId: parentId ?? this.parentId,
      internetMessageId: internetMessageId ?? this.internetMessageId,
      references: references ?? this.references, from: from ?? this.from,
      to: to ?? this.to, cc: cc ?? this.cc, bcc: bcc ?? this.bcc, replyTo: replyTo ?? this.replyTo,
      subject: subject ?? this.subject,
      bodyPlain: clearBody ? null : (bodyPlain ?? this.bodyPlain),
      bodyHtml: clearBody ? null : (bodyHtml ?? this.bodyHtml),
      bodyPreview: bodyPreview ?? this.bodyPreview,
      authResults: authResults ?? this.authResults,
      listUnsubscribe: listUnsubscribe ?? this.listUnsubscribe,
      attachments: attachments ?? this.attachments, receivedAt: receivedAt ?? this.receivedAt,
      sentAt: sentAt ?? this.sentAt, isRead: isRead ?? this.isRead,
      isFlagged: isFlagged ?? this.isFlagged, isDraft: isDraft ?? this.isDraft,
      isReplied: isReplied ?? this.isReplied, isForwarded: isForwarded ?? this.isForwarded,
      hasAttachments: hasAttachments ?? this.hasAttachments, priority: priority ?? this.priority,
      status: status ?? this.status, tags: tags ?? this.tags,
      categories: categories ?? this.categories, classification: classification ?? this.classification,
      sensitivity: sensitivity ?? this.sensitivity,
      sentimentScore: sentimentScore ?? this.sentimentScore,
      aiCategory: aiCategory ?? this.aiCategory, aiRecommendation: aiRecommendation ?? this.aiRecommendation,
      extractedDeadline: extractedDeadline ?? this.extractedDeadline,
      size: size ?? this.size, readReceiptRequested: readReceiptRequested ?? this.readReceiptRequested,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      cachedAt: cachedAt ?? this.cachedAt,
      remindAt: clearReminder ? null : (remindAt ?? this.remindAt),
      meetingJson: meetingJson ?? this.meetingJson,
      controlState: controlState ?? this.controlState,
      laterState: laterState ?? this.laterState,
      controlReplied: clearControl ? null : (controlReplied ?? this.controlReplied),
      followUpAt: clearControl ? null : (followUpAt ?? this.followUpAt),
    );
  }
}


/// Приглашение на встречу из письма (ActiveSync MeetingRequest).
class EmailMeeting {
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? location;
  final String? organizer;
  final bool responseRequested;
  /// Класс сообщения Exchange: IPM.Schedule.Meeting.Request / .Canceled / …
  final String? messageClass;
  /// UID встречи (iCalendar) — для ответа письмом, когда сервер ActiveSync
  /// (до 16.0) сам ответ организатору не отправляет.
  final String? uid;
  /// Приглашение на одно вхождение серии.
  final bool isOccurrence;

  /// Ответ участника с предложением нового времени (1.6.7).
  final DateTime? proposedStart;
  final DateTime? proposedEnd;

  /// Организатор запретил предлагать новое время.
  final bool disallowNewTime;
  const EmailMeeting({this.start, this.end, this.allDay = false, this.location,
      this.organizer, this.responseRequested = false, this.messageClass, this.uid,
      this.isOccurrence = false, this.proposedStart, this.proposedEnd, this.disallowNewTime = false});

  bool get isCanceled => (messageClass ?? '').toLowerCase().contains('canceled');
  bool get isRequest => !isCanceled && !(messageClass ?? '').toLowerCase().contains('resp.');

  /// Ответ участника на собрание: 1 — принял, 2 — под вопросом, 3 —
  /// отклонил; 0 — не ответ (IPM.Schedule.Meeting.Resp.Pos / Tent / Neg).
  int get responseKind {
    final c = (messageClass ?? '').toLowerCase();
    if (c.contains('resp.pos')) return 1;
    if (c.contains('resp.tent')) return 2;
    if (c.contains('resp.neg')) return 3;
    return 0;
  }

  bool get hasProposal => proposedStart != null && proposedEnd != null;

  static EmailMeeting? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      DateTime? d(String k) => m[k] is String ? DateTime.tryParse(m[k] as String)?.toLocal() : null;
      return EmailMeeting(
        start: d('start'),
        end: d('end'),
        allDay: m['allDay'] == true,
        location: m['location'] as String?,
        organizer: m['organizer'] as String?,
        responseRequested: m['responseRequested'] == true,
        messageClass: m['class'] as String?,
        uid: m['uid'] as String?,
        isOccurrence: m['occurrence'] == true,
        proposedStart: d('propStart'),
        proposedEnd: d('propEnd'),
        disallowNewTime: m['noNewTime'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

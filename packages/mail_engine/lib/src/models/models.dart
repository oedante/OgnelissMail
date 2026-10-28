import 'dart:typed_data';

// lib/src/models/models.dart
// Нормализованные модели, единые для всех транспортов (EAS/EWS/IMAP).
// Каждый движок маппит свой формат (WBXML / SOAP / MIME) в эти типы.

/// Транспорт (как клиент говорит с сервером).
enum MailTransportKind { eas, ews, imapSmtp }

/// Способ аутентификации (НЕ протокол — это ортогонально транспорту).
enum AuthKind { basic, oauth2, appPassword }

/// Что умеет конкретный транспорт/аккаунт.
class Capabilities {
  final bool mail;
  final bool calendar;
  final bool contacts;
  final bool tasks;
  final bool notes;
  final bool push; // EAS Ping / IMAP IDLE
  final bool policies; // EAS Provision
  const Capabilities({
    this.mail = true,
    this.calendar = false,
    this.contacts = false,
    this.tasks = false,
    this.notes = false,
    this.push = false,
    this.policies = false,
  });
}

/// Команда удалённого стирания от сервера Exchange (EAS Provision).
/// [device] — стереть все данные приложения (RemoteWipe);
/// [account] — только данные этого ящика (AccountOnlyRemoteWipe, EAS 16.1).
enum RemoteWipeKind { device, account }

/// Нормализованная политика безопасности (из EAS Provision; иначе null).
class SecurityPolicy {
  final bool devicePasswordEnabled;
  final int? minPasswordLength;
  final int? maxInactivitySeconds;
  final bool requireDeviceEncryption;
  final bool allowRemoteWipe;
  final String? policyKey;

  /// Максимальный размер вложения, разрешённый политикой сервера (байты).
  /// EAS отдаёт его в EASProvisionDoc/MaxAttachmentSize; null — сервер лимит
  /// не сообщил, применяется значение по умолчанию приложения.
  final int? maxAttachmentSize;

  /// AllowSimpleDevicePassword: разрешены простые PIN вроде 1111 или 1234.
  /// По умолчанию в Exchange — да.
  final bool allowSimplePassword;

  /// AlphanumericDevicePasswordRequired: нужен пароль с буквами, не PIN.
  final bool alphanumericRequired;

  /// MaxDevicePasswordFailedAttempts: после стольких ошибок — стирание.
  final int? maxFailedAttempts;

  /// DevicePasswordExpiration: срок действия пароля, дней (0/null — без срока).
  final int? passwordExpirationDays;

  /// AllowCamera: камера разрешена.
  final bool allowCamera;

  const SecurityPolicy({
    this.devicePasswordEnabled = false,
    this.minPasswordLength,
    this.maxInactivitySeconds,
    this.requireDeviceEncryption = false,
    this.allowRemoteWipe = false,
    this.policyKey,
    this.maxAttachmentSize,
    this.allowSimplePassword = true,
    this.alphanumericRequired = false,
    this.maxFailedAttempts,
    this.passwordExpirationDays,
    this.allowCamera = true,
  });
}

/// Конфигурация аккаунта на входе в движок.
class AccountConfig {
  final String email;
  final String? password; // для basic/appPassword
  final String? oauthAccessToken; // для oauth2
  final String? oauthRefreshToken;
  /// Действующий токен OAuth (Exchange Online по EAS/EWS, 1.6.2): движок
  /// просит его при подключении и после ответа 401 ([force] — токен уже
  /// отвергнут сервером, нужен новый). Обновляет токен приложение.
  final Future<String?> Function({bool force})? oauthTokenSource;
  final AuthKind authKind;
  final String? domain; // Exchange: msk
  final String? exchangeServer; // если известен заранее
  final String? imapHost;
  final int imapPort;
  final bool imapSsl;
  final String? smtpHost;
  final int smtpPort;
  final MailTransportKind? forceTransport; // null = автоопределение
  final String userAgent;

  const AccountConfig({
    required this.email,
    this.password,
    this.oauthAccessToken,
    this.oauthRefreshToken,
    this.oauthTokenSource,
    this.authKind = AuthKind.basic,
    this.domain,
    this.exchangeServer,
    this.imapHost,
    this.imapPort = 993,
    this.imapSsl = true,
    this.smtpHost,
    this.smtpPort = 465,
    this.forceTransport,
    // Нейтральный ФОЛБЭК (движок — чистый Dart, без доступа к device_info).
    // Приложение передаёт честный UA из реальных системных данных
    // (см. DeviceUserAgent в lib/): Ogneliss/<ver> (<ОС> <верс.>; <модель>).
    // Не имитируем чужое устройство.
    this.userAgent = 'Ogneliss-Android/1.0.0',
    this.deviceType = 'Android',
    this.deviceModel = 'Android',
    this.deviceOs = 'Android',
    this.deviceFriendlyName = 'Mail',
    this.deviceLanguage = 'en-us',
    this.deviceId,
    this.extraHeaders,
    this.bodyType = 1,
    this.bodyTruncationBytes = 8192,
    this.mailFilterType = 2,
    this.easBase64Override,
    this.appleMailProfile = false,
  });

  /// Форма командной строки EAS (MS-ASHTTP): null — авто (plain-query),
  /// true — Base64-команда (форма из MS-ASHTTP, её использовали Windows Phone),
  /// false — plain-query. Почта iPhone, по журналам Exchange, шлёт обычный
  /// plain-query (`?User=…&DeviceId=…&DeviceType=iPhone&Cmd=…`), а не Base64;
  /// проверка 1.6.14 показала, что шлюз ServicePipe режет обе формы одинаково.
  /// Оставлено для ручного выбора в консоли (connect_test --base64/--no-base64).
  final bool? easBase64Override;

  /// Профиль запросов «как Почта iPhone» (1.6.17), для iPhone в режиме
  /// совместимости со шлюзом:
  ///  * командная строка в порядке Почты iOS — `?User=…&DeviceId=…&DeviceType=…&Cmd=…`
  ///    (журнал почтового ящика Exchange для Apple-iPhone8C4/1505.302; у
  ///    Android-клиентов и у нас раньше Cmd шёл первым);
  ///  * в запросе только заголовки ActiveSync (Authorization, Content-Type,
  ///    MS-ASProtocolVersion, X-MS-PolicyKey, User-Agent, cookie сервера), а
  ///    Accept, Accept-Language и Accept-Encoding ставит сетевой стек системы —
  ///    как у любого системного клиента. Раньше уходил Accept-Language
  ///    «en-US,en;q=0.9» (формат браузера) даже на русском iPhone;
  ///  * только ActiveSync: Почта iPhone не обращается к EWS, а каждый POST к EWS,
  ///    отвергнутый шлюзом, — лишний «бот-сигнал» с того же адреса.
  final bool appleMailProfile;

  /// Тип тела письма при синхронизации: 1=plain text, 2=HTML.
  final int bodyType;
  /// Усечение тела письма в байтах (экономия трафика). 0 = только заголовки.
  final int bodyTruncationBytes;
  /// EAS FilterType окна синхронизации почты:
  /// 0=всё, 1=1д, 2=3д, 3=1нед, 4=2нед, 5=1мес, 6=3мес, 7=6мес.
  final int mailFilterType;

  /// EAS DeviceType (как у NINE — «Android»).
  final String deviceType;
  /// Provision → DeviceInformation (EAS 16): Model, OS, FriendlyName. На
  /// iPhone — как у Почты iOS («iPhone15C2», «iOS 18.1 22B83», «iPhone»):
  /// раньше всегда «Android», и сервер видел Android при UA iPhone.
  final String deviceModel;
  final String deviceOs;
  final String deviceFriendlyName;
  /// Provision → OSLanguage: на iPhone — язык системы, как у Почты iOS («ru-RU»).
  final String deviceLanguage;
  /// EAS DeviceId; если null — генерируется из email.
  final String? deviceId;
  /// Доп. заголовки для EAS/EWS (например, секрет для allowlist у IT).
  final Map<String, String>? extraHeaders;
}
extension AccountConfigCopy on AccountConfig {
  AccountConfig withUserAgent(String ua) => AccountConfig(
        email: email, password: password, oauthAccessToken: oauthAccessToken,
        oauthRefreshToken: oauthRefreshToken, oauthTokenSource: oauthTokenSource,
        authKind: authKind, domain: domain,
        exchangeServer: exchangeServer, imapHost: imapHost, imapPort: imapPort,
        imapSsl: imapSsl, smtpHost: smtpHost, smtpPort: smtpPort,
        forceTransport: forceTransport, userAgent: ua, deviceType: deviceType, deviceId: deviceId,
        deviceModel: deviceModel, deviceOs: deviceOs, deviceFriendlyName: deviceFriendlyName,
        deviceLanguage: deviceLanguage,
        extraHeaders: extraHeaders, bodyType: bodyType, bodyTruncationBytes: bodyTruncationBytes,
        mailFilterType: mailFilterType, easBase64Override: easBase64Override,
        appleMailProfile: appleMailProfile,
      );
}

/// Результат подключения: какой транспорт выбран, возможности, политика.
class ConnectResult {
  final bool success;
  final MailTransportKind? transport;
  final String? resolvedHost;
  final Capabilities capabilities;
  final SecurityPolicy? policy;
  final String? error;
  final List<String> log;

  /// Адрес EWS, обнаруженный ПОПУТНО при подключении по EAS (гибридный режим).
  ///
  /// Почта, календарь и контакты идут по EAS: он даёт Direct Push и экономит
  /// батарею. Но в EAS нет автоответов (OOF), занятости коллег, категорий
  /// Outlook, серверных правил и отзыва письма — их выполняет EWS по этому
  /// адресу. null означает, что Autodiscover EWS не отдал: расширенные функции
  /// будут недоступны, всё остальное работает как прежде.
  final String? companionEwsUrl;

  const ConnectResult({
    required this.success,
    this.transport,
    this.resolvedHost,
    this.capabilities = const Capabilities(),
    this.policy,
    this.error,
    this.companionEwsUrl,
    this.log = const [],
  });
}

/// Папка.
class MailFolder {
  final String id;
  final String displayName;
  final MailFolderType type;
  final String? parentId;
  const MailFolder({
    required this.id,
    required this.displayName,
    this.type = MailFolderType.user,
    this.parentId,
  });
}

enum MailFolderType { inbox, sent, drafts, trash, junk, outbox, archive, user, calendar, contacts, tasks, notes, journal }

/// Адрес.
class MailAddress {
  final String email;
  final String? name;
  const MailAddress(this.email, [this.name]);
  @override
  String toString() => name != null && name!.isNotEmpty ? '$name <$email>' : email;
}

/// Ссылка на сообщение (для операций). Хранит достаточно, чтобы любой
/// транспорт нашёл письмо: EAS — serverId+collectionId, IMAP — uid+folder.
class MessageRef {
  final String id;
  final String folderId;
  final String? serverId; // EAS
  final int? uid; // IMAP
  const MessageRef({required this.id, required this.folderId, this.serverId, this.uid});
}

/// Нормализованное сообщение.
class MailMessage {
  final String id;
  final String folderId;
  final String? serverId;
  final int? uid;
  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final String subject;
  final String? preview;
  final String? bodyPlain;
  final String? bodyHtml;
  final DateTime? date;
  final bool isRead;
  final bool isFlagged;
  final bool hasAttachments;
  final List<MailAttachment> attachments;

  /// Идентификатор беседы сервера (EAS 14+: Email2:ConversationId, base64).
  /// По нему письма одной переписки собираются в цепочку.
  final String? conversationId;

  /// Приглашение на встречу (ActiveSync Email:MeetingRequest). null — обычное письмо.
  final MeetingInfo? meeting;

  /// Класс сообщения Exchange (IPM.Note, IPM.Schedule.Meeting.Request,
  /// …Canceled, …Resp.Pos и т.п.).
  final String? messageClass;

  /// Message-ID из заголовков письма. У ActiveSync в Sync его нет — null
  /// (раньше сюда подставлялся ServerId вида «5:12», и он уходил в
  /// In-Reply-To ответов как будто Message-ID).
  final String? internetMessageId;

  /// Reply-To письма (EAS Email:ReplyTo, IMAP заголовок Reply-To).
  final List<MailAddress> replyTo;
  const MailMessage({
    required this.id,
    required this.folderId,
    this.serverId,
    this.uid,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.subject = '',
    this.preview,
    this.bodyPlain,
    this.bodyHtml,
    this.date,
    this.isRead = false,
    this.isFlagged = false,
    this.hasAttachments = false,
    this.attachments = const [],
    this.conversationId,
    this.internetMessageId,
    this.meeting,
    this.messageClass,
    this.replyTo = const [],
  });
}

/// Данные приглашения на встречу из письма.
class MeetingInfo {
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? location;
  final String? organizer;
  final bool responseRequested;

  /// UID встречи для iCalendar (из EAS GlobalObjId): нужен, чтобы ответ
  /// письмом (iMIP) лёг на ту же встречу у организатора.
  final String? uid;

  /// Приглашение на одно вхождение серии (в GlobalObjId есть дата).
  final bool isOccurrence;

  /// Ответ участника с предложением нового времени (1.6.7, MS-ASEMAIL
  /// MeetingRequest/ProposedStartTime, ProposedEndTime).
  final DateTime? proposedStart;
  final DateTime? proposedEnd;

  /// Организатор запретил предлагать новое время.
  final bool disallowNewTime;
  const MeetingInfo({this.start, this.end, this.allDay = false, this.location,
      this.organizer, this.responseRequested = false, this.uid, this.isOccurrence = false,
      this.proposedStart, this.proposedEnd, this.disallowNewTime = false});

  Map<String, dynamic> toMap() => {
        if (start != null) 'start': start!.toUtc().toIso8601String(),
        if (end != null) 'end': end!.toUtc().toIso8601String(),
        'allDay': allDay,
        if (location != null) 'location': location,
        if (organizer != null) 'organizer': organizer,
        'responseRequested': responseRequested,
        if (uid != null) 'uid': uid,
        if (isOccurrence) 'occurrence': true,
        if (proposedStart != null) 'propStart': proposedStart!.toUtc().toIso8601String(),
        if (proposedEnd != null) 'propEnd': proposedEnd!.toUtc().toIso8601String(),
        if (disallowNewTime) 'noNewTime': true,
      };
}

class MailAttachment {
  final String id;
  final String name;
  final String? contentType;
  final int? size;
  final String? partNumber; // IMAP
  final String? serverFileReference; // EAS
  final Uint8List? bytes; // Содержимое для ИСХОДЯЩИХ вложений (при отправке)
  /// Встроенное в тело (картинка подписи и т.п.), а не «настоящее» вложение.
  final bool isInline;
  /// Content-ID для встроенных картинок (cid:...).
  final String? contentId;
  const MailAttachment({
    required this.id,
    required this.name,
    this.contentType,
    this.size,
    this.partNumber,
    this.serverFileReference,
    this.bytes,
    this.isInline = false,
    this.contentId,
  });
}

/// Состояние синхронизации папки (opaque-токен; каждый транспорт трактует сам:
/// EAS — SyncKey, IMAP — UIDVALIDITY:lastUID, EWS — syncState).
class SyncState {
  final String token;
  const SyncState(this.token);
}

/// Обобщённый элемент PIM (календарь/контакты/задачи/заметки):
/// serverId + плоская карта полей (имя тега → текст) из ApplicationData.
class PimItem {
  final String serverId;
  final Map<String, String> fields;
  final bool deleted;
  /// Правило повторения (календарь): Type, Interval, Until, Occurrences,
  /// DayOfWeek, DayOfMonth, WeekOfMonth, MonthOfYear. null — не повторяется.
  final Map<String, String>? recurrence;
  /// Исключения повторения: ExceptionStartTime, Deleted, а также изменённые
  /// Subject/StartTime/EndTime/Location.
  final List<Map<String, String>> exceptions;
  /// Участники встречи: Email, Name, Type (1 — обязательный, 2 — необязательный).
  final List<Map<String, String>> attendees;
  const PimItem({
    required this.serverId,
    this.fields = const {},
    this.deleted = false,
    this.recurrence,
    this.exceptions = const [],
    this.attendees = const [],
  });
  String? f(String name) => fields[name];
}

/// Изменение флагов письма, пришедшее с сервера (прочитано/флаг поменяли
/// на другом устройстве). Сервер присылает ТОЛЬКО изменённые свойства, поэтому
/// это не полноценное сообщение: записывать его как письмо целиком нельзя —
/// затёрлись бы тема, отправитель и тело.
class MailFlagChange {
  final String id;
  final String folderId;
  final bool? read;
  final bool? flagged;
  const MailFlagChange({required this.id, required this.folderId, this.read, this.flagged});
}

/// Результат синхронизации папки.
class SyncResult {
  final List<MailMessage> added;
  final List<MessageRef> deleted;
  final List<MailMessage> changed;
  /// Изменения флагов (EAS Sync/Change). См. [MailFlagChange].
  final List<MailFlagChange> flagChanges;
  final SyncState? newState;
  final bool moreAvailable;
  const SyncResult({
    this.added = const [],
    this.deleted = const [],
    this.changed = const [],
    this.flagChanges = const [],
    this.newState,
    this.moreAvailable = false,
  });
}

/// Исходящее письмо.
class OutgoingMessage {
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final String? bodyPlain;
  final String? bodyHtml;

  /// Вложения исходящего письма. У каждого должен быть заполнен `bytes` —
  /// содержимое читается на стороне приложения и передаётся в движок.
  /// Используется всеми транспортами: EWS (CreateAttachment), SMTP и EAS
  /// (multipart/mixed в MIME).
  final List<MailAttachment> attachments;

  /// Message-ID письма, на которое отвечаем (In-Reply-To/References) —
  /// без него ответ у получателя не попадает в цепочку.
  final String? inReplyTo;

  /// Важность: 'High' / 'Normal' / 'Low'.
  final String importance;

  /// Конфиденциальность: 'Normal' / 'Personal' / 'Private' / 'Confidential'.
  final String sensitivity;

  /// Постоянный идентификатор отправки (например, id записи очереди). EAS
  /// передаёт его как ClientId: Exchange помнит недавние ClientId и на
  /// повтор отвечает Status 118, а не отправляет письмо второй раз. Без него
  /// повтор после обрыва связи (сервер принял, ответ не дошёл) давал дубль.
  final String? clientId;

  /// Последняя обработка готового MIME перед отправкой (S/MIME: подпись и
  /// шифрование — ключи у приложения, не у движка). null — как есть.
  /// С ней письмо уходит только целиком (SendMail): SmartReply/SmartForward
  /// дописывают оригинал на сервере, а подписанное письмо менять нельзя.
  final Future<Uint8List> Function(Uint8List mime)? mimeTransform;

  /// iCalendar для ответа на приглашение письмом (iMIP, RFC 6047): уходит
  /// альтернативной частью text/calendar рядом с текстом — так Exchange и
  /// Outlook узнают в письме ответ на встречу.
  final String? calendar;

  /// METHOD части [calendar]: REPLY, COUNTER.
  final String calendarMethod;

  /// Отправитель, если не владелец ящика (1.6.27): «Отправить как» /
  /// «Отправить от имени» — общий ящик отдела, ящик руководителя у
  /// секретаря, диспетчерская. Права выдаёт администратор Exchange; без них
  /// сервер письмо отклонит. null — от владельца ящика.
  final MailAddress? from;

  const OutgoingMessage({
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.bodyPlain,
    this.bodyHtml,
    this.attachments = const [],
    this.inReplyTo,
    this.importance = 'Normal',
    this.sensitivity = 'Normal',
    this.clientId,
    this.mimeTransform,
    this.calendar,
    this.calendarMethod = 'REPLY',
    this.from,
  });
}

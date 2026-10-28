// lib/data/database/app_database.dart
// SQLite-база данных через Drift.
// ИНДЕКСЫ на все поисковые поля для быстрой пагинации.
// Таблицы: accounts, emails, folders, contacts, calendar_events, tasks,
// sync_queue, audit_log, signatures, notes, assignments + сателлиты
// (participants/events/proposals/votes/meetings/reports).
// WAL-режим, foreign keys, автоочистка.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as s3;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/security/secure_storage_service.dart';

part 'app_database.g.dart';

/// Сортировка списка писем.
enum MailSort { dateNewest, dateOldest, senderAZ, subjectAZ, sizeLargest, sizeSmallest }

/// Фильтр списка писем — выполняется в SQL. Раньше фильтры применялись в
/// памяти к уже загруженному «окну» из последних 30–200 писем: фильтр
/// «Непрочитанные» не находил непрочитанное 300-е письмо, а при пустом окне
/// список не прокручивался и следующая страница не загружалась.
class EmailListFilter {
  final bool unread;
  final bool flagged;
  /// «На контроле» (активные и исполненные).
  final bool control;
  /// «Посмотреть позже»: отложенные и вернувшиеся; порядок — вернувшиеся,
  /// затем по сроку возврата, без даты — в конце.
  final bool later;
  final bool attachments;
  final bool vip;

  /// VIP-отправители и слова в теме (Настройки → VIP), в нижнем регистре.
  final List<String> vipEmails;
  final List<String> vipKeywords;
  final DateTime? since;
  final String? tag;
  /// Адресовано лично (адрес пользователя в «Кому»), в нижнем регистре.
  final String? toMe;
  /// Папки, не входящие в сводную ленту: аккаунт → id папок (корзина, спам,
  /// черновики, исходящие). id папки уникален только внутри аккаунта.
  final Map<String, List<String>> excludedFolders;

  const EmailListFilter({
    this.unread = false,
    this.flagged = false,
    this.control = false,
    this.later = false,
    this.attachments = false,
    this.vip = false,
    this.vipEmails = const [],
    this.vipKeywords = const [],
    this.since,
    this.tag,
    this.toMe,
    this.excludedFolders = const {},
  });
}

// ════════════════════════ ТАБЛИЦЫ ════════════════════════

/// Аккаунты
class Accounts extends Table {
  TextColumn get id => text()();
  IntColumn get type => integer()();
  TextColumn get email => text()();
  TextColumn get displayName => text()();
  TextColumn get username => text()();
  TextColumn get domain => text().nullable()();
  TextColumn get exchangeServer => text().nullable()();
  IntColumn get exchangeAuthMethod => integer().nullable()();
  TextColumn get ewsUrl => text().nullable()();
  TextColumn get imapServer => text().nullable()();
  IntColumn get imapPort => integer().nullable()();
  IntColumn get imapEncryption => integer().nullable()();
  TextColumn get smtpServer => text().nullable()();
  IntColumn get smtpPort => integer().nullable()();
  IntColumn get smtpEncryption => integer().nullable()();
  IntColumn get syncInterval => integer().withDefault(const Constant(0))();
  BoolColumn get syncOnlyWifi => boolean().withDefault(const Constant(false))();
  IntColumn get syncDays => integer().withDefault(const Constant(365))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Когда сервер отверг учётные данные (401/403) ПОСЛЕ успешного подключения.
  /// Такое бывает при смене пароля по политике, блокировке учётной записи или
  /// отзыве токена. null — проблем нет. Нужно, чтобы не «долбить» сервер
  /// неверным паролем (риск блокировки) и чтобы сообщить пользователю.
  DateTimeColumn get authFailedAt => dateTime().nullable()();

  /// Адрес общего или делегированного ящика.
  ///
  /// Если задан, аккаунт работает НЕ со своим ящиком: учётные данные берутся
  /// от основной записи (пароль у общего ящика обычно отсутствует), а запросы
  /// EWS адресуются другому почтовому ящику. Так устроены общие ящики
  /// подразделений и делегированный доступ к ящику руководителя.
  TextColumn get sharedMailboxEmail => text().nullable()();

  /// Идентификатор основного аккаунта, чьи учётные данные используются для
  /// доступа к общему ящику.
  TextColumn get parentAccountId => text().nullable()();
  // Тип аккаунта: 'work' / 'personal'; null — по типу подключения. v16.
  TextColumn get accountKind => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFFFFC928))();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get signatureId => text().nullable()();
  TextColumn get certificatePath => text().nullable()();
  // Настройки загрузки: 0=full, 1=noAttachments, 2=headersOnly, 3=partial500k, 4=partial100k, 5=partial50k
  IntColumn get fetchMode => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Письма
class Emails extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get folderId => text()();
  TextColumn get folderName => text().nullable()();
  TextColumn get conversationId => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get internetMessageId => text().nullable()();
  TextColumn get referencesStr => text().nullable()();
  TextColumn get fromEmail => text()();
  TextColumn get fromName => text().nullable()();
  TextColumn get toRecipients => text()();
  TextColumn get ccJson => text().nullable()();
  TextColumn get bccJson => text().nullable()();
  TextColumn get replyToEmail => text().nullable()();
  TextColumn get subject => text()();
  TextColumn get bodyPlain => text().nullable()();
  TextColumn get bodyHtml => text().nullable()();
  TextColumn get bodyPreview => text().nullable()();
  // Заголовки аутентификации отправителя (Authentication-Results / Received-SPF)
  // — для локальной проверки SPF/DKIM/DMARC в антифишинге.
  TextColumn get authResults => text().nullable()();
  // Приглашение на встречу (JSON, см. EmailMeeting). v16.
  TextColumn get meetingJson => text().nullable()();
  /// Время напоминания «вернуться к письму» (снуз). null = нет напоминания.
  DateTimeColumn get remindAt => dateTime().nullable()();

  /// Напоминание «нет ответа»: момент, когда нужно проверить, ответили ли на
  /// НАШЕ отправленное письмо. Ставится пользователем явно — поэтому таких
  /// строк единицы, и проверка не нагружает систему.
  DateTimeColumn get followUpAt => dateTime().nullable()();

  /// «На контроле» (08.10.2026): 0 — нет; 1 — жду ответа (моё письмо);
  /// 2 — должен ответить (входящее); 3 — исполнено (ответ пришёл или я
  /// ответил). Ставит и снимает пользователь; приложение только переводит
  /// 1/2 → 3. Таких писем единицы — проверка не перебирает базу.
  IntColumn get controlState => integer().withDefault(const Constant(0))();
  /// «Посмотреть позже» (08.10.2026): 0 — нет; 1 — отложено (до [remindAt]
  /// или без даты, если remindAt пуст); 2 — вернулось (срок наступил: письмо
  /// снова непрочитанное, пришло уведомление) — до открытия письма.
  IntColumn get laterState => integer().withDefault(const Constant(0))();
  /// Рассылка (09.10.2026): заголовки List-Unsubscribe, List-Unsubscribe-Post
  /// и List-Id одной строкой JSON {"u": …, "p": …, "id": …}. null — не
  /// рассылка или сервер заголовков не дал (ActiveSync).
  TextColumn get listUnsubscribe => text().nullable()();
  /// «На контроле», моё письмо нескольким адресатам (09.10.2026): кто из
  /// «Кому» уже ответил — адреса через запятую (копия не считается).
  TextColumn get controlReplied => text().nullable()();
  TextColumn get attachmentsJson => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isFlagged => boolean().withDefault(const Constant(false))();
  BoolColumn get isDraft => boolean().withDefault(const Constant(false))();
  BoolColumn get isReplied => boolean().withDefault(const Constant(false))();
  BoolColumn get isForwarded => boolean().withDefault(const Constant(false))();
  BoolColumn get hasAttachments => boolean().withDefault(const Constant(false))();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  IntColumn get status => integer().withDefault(const Constant(3))();
  TextColumn get tagsStr => text().nullable()();
  TextColumn get categoriesStr => text().nullable()();
  TextColumn get classification => text().nullable()();
  TextColumn get sensitivity => text().nullable()(); // Normal/Personal/Private/Confidential
  RealColumn get sentimentScore => real().nullable()();
  TextColumn get aiCategory => text().nullable()();
  TextColumn get aiRecommendation => text().nullable()();
  DateTimeColumn get extractedDeadline => dateTime().nullable()();
  IntColumn get size => integer().nullable()();
  BoolColumn get readReceiptRequested => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocallyModified => boolean().withDefault(const Constant(false))();
  // Какая часть письма загружена: 0=headers, 1=partial, 2=bodyNoAttach, 3=full
  IntColumn get loadedLevel => integer().withDefault(const Constant(0))();
  DateTimeColumn get cachedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id, accountId};
}

/// Папки
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get parentId => text().nullable()();
  TextColumn get displayName => text()();
  IntColumn get type => integer().withDefault(const Constant(7))();
  TextColumn get serverPath => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get totalCount => integer().withDefault(const Constant(0))();
  BoolColumn get showInUnified => boolean().withDefault(const Constant(true))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  TextColumn get iconName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id, accountId};
}

/// Контакты
class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().nullable()();
  TextColumn get email => text()();
  TextColumn get additionalEmails => text().nullable()();
  TextColumn get displayName => text()();
  TextColumn get firstName => text().nullable()();
  TextColumn get middleName => text().nullable()();
  TextColumn get lastName => text().nullable()();
  TextColumn get jobTitle => text().nullable()();
  TextColumn get department => text().nullable()();
  TextColumn get company => text().nullable()();
  TextColumn get phoneWork => text().nullable()();
  TextColumn get phoneMobile => text().nullable()();
  TextColumn get phoneExtension => text().nullable()();
  TextColumn get office => text().nullable()();
  /// Руководитель (как в карточке Outlook): имя из адресной книги.
  TextColumn get manager => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get avatarPath => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get source => integer().withDefault(const Constant(1))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isVip => boolean().withDefault(const Constant(false))();
  IntColumn get interactionCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastInteraction => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get birthday => dateTime().nullable()();

  /// Коллеги (1.8.0+118): когда контакт сверялся с адресной книгой
  /// организации и что оттуда пришло — JSON `DirectoryOrg` (компания, отдел,
  /// должность, кабинет, руководитель, рабочий телефон). При синхронизации с
  /// сервером эти поля главнее копии в личных контактах, которая сама не
  /// обновляется (`lib/services/contacts/colleague_directory.dart`).
  DateTimeColumn get dirCheckedAt => dateTime().nullable()();
  TextColumn get dirOrg => text().nullable()();

  // Ключ — пара (id, аккаунт): ServerId у разных EAS-ящиков совпадают
  // («2:15»), и с ключом только по id контакт одного ящика затирал контакт
  // другого (миграция v18).
  @override
  Set<Column> get primaryKey => {id, accountId};
}

/// Календарь
class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get calendarId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get onlineMeetingUrl => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get attendeesJson => text().nullable()();
  TextColumn get organizerEmail => text().nullable()();
  IntColumn get recurrence => integer().withDefault(const Constant(0))();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  IntColumn get showAs => integer().withDefault(const Constant(2))();
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();
  TextColumn get remindersJson => text().nullable()();
  TextColumn get linkedEmailId => text().nullable()();
  BoolColumn get isCancelled => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocallyModified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id, accountId};
}

/// Задачи
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  TextColumn get assigneeEmail => text().nullable()();
  TextColumn get assigneeName => text().nullable()();
  TextColumn get linkedEmailId => text().nullable()();
  TextColumn get linkedEmailSubject => text().nullable()();
  TextColumn get tagsStr => text().nullable()();
  TextColumn get subtasksJson => text().nullable()();
  TextColumn get commentsJson => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  IntColumn get recurrenceDays => integer().nullable()();
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get isFlagged => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocallyModified => boolean().withDefault(const Constant(false))();
  /// Когда напомнить (v20). Отдельно от срока: «сдать отчёт в пятницу,
  /// напомнить в четверг в 10:00». ActiveSync — Tasks:ReminderTime.
  DateTimeColumn get reminderAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id, accountId};
}

/// Очередь офлайн-операций
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get operationType => text()();
  TextColumn get targetId => text()();
  TextColumn get payloadJson => text()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
}

/// Аудит
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get details => text().nullable()();
  TextColumn get ipAddress => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
}

/// Подписи (хранятся в БД, а не в SharedPreferences)
class Signatures extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get htmlContent => text()();
  TextColumn get plainContent => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get useForNewEmails => boolean().withDefault(const Constant(true))();
  BoolColumn get useForReplies => boolean().withDefault(const Constant(true))();
  BoolColumn get useForForwards => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Заметки (Notes) — синхронизируются с Exchange (EAS/EWS), как в эталоне.
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get categoriesStr => text().nullable()();
  IntColumn get colorValue => integer().nullable()();
  TextColumn get serverId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  BoolColumn get isLocallyModified => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ════════════════ ПОРУЧЕНИЯ (Assignments) — задача-ветка от письма ════════════════
// Событийный журнал (event sourcing) поверх почты: каждое действие — событие в
// AssignmentEvents, письма — единственный транспорт (Exchange EWS/EAS + IMAP,
// без выделенного сервера). Проекция (Assignments/Proposals/Votes/...) строится
// локально из журнала — так же, как каждый участник строит свою копию из треда.

/// Поручение: карточка задачи с несколькими ответственными.
class Assignments extends Table {
  TextColumn get id => text()(); // UUID = X-App-Task-Id в письмах
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get sourceEmailId => text().nullable()(); // письмо-основание
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get kind => integer().withDefault(const Constant(0))(); // 0 once,1 permanent,2 cyclic
  TextColumn get recurrenceRule => text().nullable()(); // rrule (как у CalendarEvents)
  IntColumn get status => integer().withDefault(const Constant(0))();
  // 0 draft,1 open,2 in_progress,3 review,4 done,5 closed,6 cancelled
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get ownerEmail => text()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get nextCheckpointAt => dateTime().nullable()(); // для permanent
  TextColumn get parentAssignmentId => text().nullable()(); // инстанс цикличной ← шаблон
  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();
  BoolColumn get autoDecideEnabled => boolean().withDefault(const Constant(true))();
  // true: система авто-фиксирует решение по большинству, когда все ответили;
  // владелец в любой момент может override — это разрешение, а не режим.
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Участники поручения и их роли.
class AssignmentParticipants extends Table {
  TextColumn get assignmentId => text().references(Assignments, #id)();
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  IntColumn get role => integer()(); // 0 owner,1 responsible,2 participant,3 observer
  IntColumn get inviteStatus => integer().withDefault(const Constant(0))(); // 0 pending,1 accepted,2 declined
  BoolColumn get isOurClient => boolean().nullable()(); // null = неизвестно (нет нашего клиента)

  @override
  Set<Column> get primaryKey => {assignmentId, email};
}

/// Журнал событий — источник истины. Проекция строится сверху него.
class AssignmentEvents extends Table {
  TextColumn get id => text()(); // UUID = X-App-Event-Id, ключ идемпотентности
  TextColumn get assignmentId => text().references(Assignments, #id)();
  TextColumn get type => text()();
  // message | meeting | proposal | vote | decision | status_change | report |
  // assignment_created | participant_added | checkpoint
  TextColumn get authorEmail => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get payloadJson => text()();
  TextColumn get refId => text().nullable()(); // напр. proposalId для vote/decision
  TextColumn get sourceEmailId => text().nullable()(); // письмо-носитель (аудит/ИБ)
  IntColumn get direction => integer()(); // 0 outgoing,1 incoming
  IntColumn get deliveryStatus => integer().withDefault(const Constant(0))(); // 0 pending,1 sent,2 failed
  // Результат проверки S/MIME-подписи: 0 unsigned, 1 valid, 2 invalid.
  IntColumn get signatureState => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Предложения ответственных (проекция над AssignmentEvents).
class AssignmentProposals extends Table {
  TextColumn get id => text()(); // = id породившего события
  TextColumn get assignmentId => text().references(Assignments, #id)();
  TextColumn get authorEmail => text()();
  /// Текст предложения. Имя `body`, а не `text`: `text()` — метод самого
  /// Drift-класса Table, и одноимённый геттер вызывал бы сам себя.
  TextColumn get body => text()();
  TextColumn get attachmentsJson => text().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))(); // 0 open,1 accepted,2 rejected,3 withdrawn
  TextColumn get decidedBy => text().nullable()();
  IntColumn get decisionMethod => integer().nullable()(); // 0 majority,1 owner_override
  DateTimeColumn get decidedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Голоса участников по предложениям (upsert — последний голос побеждает).
class AssignmentVotes extends Table {
  TextColumn get proposalId => text().references(AssignmentProposals, #id)();
  TextColumn get voterEmail => text()();
  IntColumn get value => integer()(); // 0 support,1 reject,2 abstain
  TextColumn get comment => text().nullable()();
  DateTimeColumn get votedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {proposalId, voterEmail};
}

/// Встречи/селекторы/митинги в рамках поручения (связь с CalendarEvents).
class AssignmentMeetings extends Table {
  TextColumn get id => text()(); // = id события
  TextColumn get assignmentId => text().references(Assignments, #id)();
  TextColumn get calendarEventId => text().nullable()();
  IntColumn get subtype => integer()(); // 0 селектор,1 совещание,2 митинг,3 звонок
  TextColumn get dialIn => text().nullable()();
  TextColumn get link => text().nullable()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime().nullable()();
  TextColumn get minutes => text().nullable()(); // протокол/итоги
  TextColumn get createdBy => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Итоговый отчёт поручения (рассматривали/приняли/отклонили/реализовали).
class AssignmentReports extends Table {
  TextColumn get assignmentId => text().references(Assignments, #id)();
  TextColumn get consideredJson => text()();
  TextColumn get acceptedJson => text()();
  TextColumn get rejectedJson => text()();
  TextColumn get doneJson => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get compiledAt => dateTime()();
  TextColumn get compiledBy => text()();
  TextColumn get exportPath => text().nullable()(); // путь к сгенерированному .docx

  @override
  Set<Column> get primaryKey => {assignmentId};
}

// ════════════════════════ БАЗА ДАННЫХ ════════════════════════

@DriftDatabase(tables: [
  Accounts,
  Emails,
  Folders,
  Contacts,
  CalendarEvents,
  Tasks,
  SyncQueue,
  AuditLog,
  Signatures,
  Notes,
  Assignments,
  AssignmentParticipants,
  AssignmentEvents,
  AssignmentProposals,
  AssignmentVotes,
  AssignmentMeetings,
  AssignmentReports,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Для тестов: база в памяти или во временном файле (NativeDatabase).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Создаём индексы для быстрой пагинации
        await _createIndexes(m);
        await _createFts();
        await _createAssignmentIndexes(m);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Шаги идемпотентны (столбец/таблица добавляются, только если их ещё
        // нет) и идут строго по возрастанию версии. Раньше шаги 12–14 стояли в
        // обратном порядке, пересоздание схемы (v<4) оставляло следующие шаги
        // добавлять уже существующие столбцы, а перенос таблицы accounts (v11)
        // падал на установках со схемой ≤10: drift копирует ВСЕ столбцы
        // текущего класса, а трёх новых в старой таблице ещё нет. После
        // обновления такая база не открывалась.
        if (from < 4) {
          // Очень старая схема: пересоздаём целиком по текущему описанию —
          // это и есть актуальная версия, дальнейшие шаги не нужны.
          await _recreateSchema(m);
          await _createAssignmentIndexes(m);
          return;
        }
        if (from < 5) {
          await m.createTable(notes); // CREATE TABLE IF NOT EXISTS
        }
        if (from < 6) {
          // Подсистема «Поручения» (событийный журнал над почтой)
          await m.createTable(assignments);
          await m.createTable(assignmentParticipants);
          await m.createTable(assignmentEvents);
          await m.createTable(assignmentProposals);
          await m.createTable(assignmentVotes);
          await m.createTable(assignmentMeetings);
          await m.createTable(assignmentReports);
          await _createAssignmentIndexes(m);
        }
        if (from < 7) {
          await _addColumnIfMissing(m, assignmentEvents, assignmentEvents.signatureState);
        }
        if (from < 8) {
          await _addColumnIfMissing(m, emails, emails.authResults);
        }
        if (from < 9) {
          await _addColumnIfMissing(m, emails, emails.remindAt);
        }
        if (from < 10) {
          await _addColumnIfMissing(m, emails, emails.sensitivity);
        }
        if (from < 11) {
          // Убраны pop3Server/pop3Port. Сначала добавляем столбцы, которых в
          // старой таблице нет (их добавляли шаги 12–14), затем пересоздаём
          // таблицу — тогда перенос данных находит все столбцы.
          await _addColumnIfMissing(m, accounts, accounts.authFailedAt);
          await _addColumnIfMissing(m, accounts, accounts.sharedMailboxEmail);
          await _addColumnIfMissing(m, accounts, accounts.parentAccountId);
          await m.alterTable(TableMigration(accounts));
        }
        if (from < 12) {
          await _addColumnIfMissing(m, emails, emails.followUpAt);
        }
        if (from < 13) {
          await _addColumnIfMissing(m, accounts, accounts.authFailedAt);
        }
        if (from < 14) {
          await _addColumnIfMissing(m, accounts, accounts.sharedMailboxEmail);
          await _addColumnIfMissing(m, accounts, accounts.parentAccountId);
        }
        if (from < 15) {
          // Новые индексы (follow-up, поиск беседы по Message-ID, счётчик
          // непрочитанных по папке) — CREATE INDEX IF NOT EXISTS.
          await _createIndexes(m);
          // Поисковый индекс нового формата (rowid = хеш аккаунт+письмо,
          // столбец аккаунта) — пересоздаём и заполняем из писем.
          await customStatement('DROP TABLE IF EXISTS emails_fts');
          await _createFts();
          await rebuildFts();
        }
        if (from < 16) {
          // Приглашения на встречу и тип аккаунта (рабочий/личный).
          await _addColumnIfMissing(m, emails, emails.meetingJson);
          await _addColumnIfMissing(m, accounts, accounts.accountKind);
        }
        if (from < 17) {
          // Период синхронизации: настройки в приложении не было, у всех
          // стояло умолчание 30 дней. Новое умолчание — год (05.10.2026).
          await customStatement('UPDATE accounts SET sync_days = 365 WHERE sync_days = 30');
          // Проверка почты у каждого ящика своя. Раньше поле не использовалось:
          // у всех стояло «15 минут», а push работал всегда — сохраняем это
          // поведение как «Мгновенно».
          await customStatement('UPDATE accounts SET sync_interval = 0 WHERE sync_interval = 2');
        }
        if (from < 18) {
          // Контакты: ключ (id, аккаунт) — перенос таблицы с новым ключом.
          await m.alterTable(TableMigration(contacts));
          // Заметки с сервера: id «eas_<аккаунт>:<ServerId>» вместо хеша
          // ServerId без аккаунта (у двух EAS-ящиков заметки затирались).
          for (final p in const ['eas', 'ews']) {
            await customStatement(
                "UPDATE OR REPLACE notes SET id = '${p}_' || account_id || ':' || server_id "
                "WHERE id LIKE '$p\\_%' ESCAPE '\\' "
                'AND account_id IS NOT NULL AND server_id IS NOT NULL');
          }
        }
        if (from < 19) {
          // Отправленные теперь во «Всей почте» (FolderModel.unifiedByDefault).
          // Список папок перезаписывается при каждой синхронизации, но до неё
          // лента осталась бы прежней. 1 = FolderType.sent.
          await customStatement('UPDATE folders SET show_in_unified = 1 WHERE type = 1');
        }
        if (from < 20) {
          // Напоминание задачи отдельно от срока (раздел «Напоминания», 07.10.2026).
          await _addColumnIfMissing(m, tasks, tasks.reminderAt);
        }
        if (from < 21) {
          // Руководитель в карточке контакта (как в Outlook, 08.10.2026).
          await _addColumnIfMissing(m, contacts, contacts.manager);
        }
        if (from < 22) {
          // «На контроле» (08.10.2026).
          await _addColumnIfMissing(m, emails, emails.controlState);
          await customStatement('CREATE INDEX IF NOT EXISTS idx_emails_control '
              'ON emails (control_state) WHERE control_state > 0');
        }
        if (from < 23) {
          // «Посмотреть позже» (08.10.2026). Прежние «Напомнить» (remindAt)
          // становятся отложенными письмами с датой.
          await _addColumnIfMissing(m, emails, emails.laterState);
          await customStatement('UPDATE emails SET later_state = 1 WHERE remind_at IS NOT NULL');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_emails_later '
              'ON emails (later_state, remind_at) WHERE later_state > 0');
        }
        if (from < 24) {
          // «Отписаться от рассылки» (09.10.2026).
          await _addColumnIfMissing(m, emails, emails.listUnsubscribe);
        }
        if (from < 25) {
          // «На контроле» объединён с «Напомнить, если нет ответа» (09.10.2026):
          // срок напоминания — срок контроля; кто из адресатов ответил.
          await _addColumnIfMissing(m, emails, emails.controlReplied);
          await customStatement(
              'UPDATE emails SET control_state = 1 WHERE follow_up_at IS NOT NULL AND control_state = 0');
        }
        if (from < 26) {
          // Контакты коллег сверяются с адресной книгой организации (27.10.2026).
          await _addColumnIfMissing(m, contacts, contacts.dirCheckedAt);
          await _addColumnIfMissing(m, contacts, contacts.dirOrg);
        }
      },
      beforeOpen: (details) async {
        // Включаем foreign keys
        await customStatement('PRAGMA foreign_keys = ON');
        // WAL для производительности (параллельное чтение/запись)
        await customStatement('PRAGMA journal_mode = WAL');
        // Кеш страниц SQLite — 8 МБ (был 4 МБ): с 1.5.5 тексты писем хранятся
        // на телефоне, база выросла, а страницы SQLCipher при каждом чтении из
        // файла расшифровываются заново (аудит 11.10.2026).
        await customStatement('PRAGMA cache_size = -8000');
        // Временные таблицы сортировок и GROUP BY — в памяти, не во флеше.
        await customStatement('PRAGMA temp_store = MEMORY');
        // Синхронный режим NORMAL (баланс скорости и надёжности)
        await customStatement('PRAGMA synchronous = NORMAL');
        // Аренда синхронизации аккаунта — общая для всех изолятов (фоновая
        // задача WorkManager открывает свою копию базы).
        await customStatement(
            'CREATE TABLE IF NOT EXISTS sync_lease ('
            'account_id TEXT PRIMARY KEY, owner TEXT NOT NULL, expires_at INTEGER NOT NULL)');
        // 1.6.12: этап, на котором сейчас синхронизация ящика, — чтобы при
        // «уже идёт в другом процессе» в журнале было видно, где она стоит.
        try {
          final cols = await customSelect('PRAGMA table_info(sync_lease)').get();
          final names = {for (final c in cols) c.data['name'] as String};
          if (!names.contains('stage')) {
            await customStatement('ALTER TABLE sync_lease ADD COLUMN stage TEXT');
          }
          if (!names.contains('stage_at')) {
            await customStatement('ALTER TABLE sync_lease ADD COLUMN stage_at INTEGER');
          }
        } catch (_) {}
        // Письма по папке без ящика: «Исходящие» (строка «Отправка через N с»
        // в ленте перечитывает их при каждом изменении писем) и служебные
        // папки. Без индекса каждый раз просматривалась вся таблица писем —
        // во время синхронизации несколько раз в секунду (аудит 11.10.2026).
        // IF NOT EXISTS — после первого создания ничего не стоит.
        try {
          await customStatement('CREATE INDEX IF NOT EXISTS idx_emails_folder ON emails(folder_id)');
          // «Все ящики» (письма нескольких ящиков по дате): без индекса по дате
          // SQLite читал и сортировал всю таблицу писем при каждом обновлении
          // ленты; с ним — читает по порядку до заполнения окна.
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_emails_date ON emails(received_at DESC, id DESC)');
          // Письма отправителя в ящике (проверка «первый контакт» при открытии
          // письма внешнего отправителя): без индекса для нового отправителя
          // просматривались все письма ящика (1.5.9). Создаётся один раз.
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_emails_sender ON emails(account_id, from_email)');
        } catch (_) {}
      },
    );
  }

  /// Взять «аренду» синхронизации аккаунта. Синхронизацию может запустить и
  /// приложение, и фоновая задача WorkManager (отдельный изолят со своим
  /// подключением к базе). Без общей блокировки они синхронизировали один
  /// ящик одновременно: двойные уведомления, «database is locked», гонка
  /// SyncKey ActiveSync. SQLite сериализует запись между подключениями,
  /// поэтому вставка-с-условием атомарна и между изолятами.
  ///
  /// 1.6.4: владелец — «p<pid>:<изолят>». Аренда, взятая другим процессом
  /// (приложение было закрыто или обновлено, а аренда ещё не истекла),
  /// забирается сразу: на Android у приложения один процесс, и прежний уже
  /// мёртв. Раньше ящик ждал до 4 минут, а Ping в это время крутился
  /// вхолостую (журнал 13.10.2026).
  Future<bool> tryAcquireSyncLease(String accountId, String owner, Duration ttl) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final colon = owner.indexOf(':');
    final proc = owner.startsWith('p') && colon > 0 ? owner.substring(0, colon + 1) : '';
    await customStatement(
      'INSERT INTO sync_lease (account_id, owner, expires_at) VALUES (?, ?, ?) '
      'ON CONFLICT(account_id) DO UPDATE SET owner = excluded.owner, expires_at = excluded.expires_at '
      'WHERE sync_lease.expires_at < ? OR sync_lease.owner = excluded.owner'
      '${proc.isEmpty ? '' : ' OR substr(sync_lease.owner, 1, ?) <> ?'}',
      [accountId, owner, now + ttl.inMilliseconds, now, if (proc.isNotEmpty) ...[proc.length, proc]],
    );
    final rows = await customSelect('SELECT owner FROM sync_lease WHERE account_id = ?',
        variables: [Variable.withString(accountId)]).get();
    return rows.isNotEmpty && rows.first.data['owner'] == owner;
  }

  Future<void> releaseSyncLease(String accountId, String owner) => customStatement(
      'DELETE FROM sync_lease WHERE account_id = ? AND owner = ?', [accountId, owner]);

  /// Отметить этап синхронизации у своей аренды (1.6.12, для журнала).
  Future<void> setSyncLeaseStage(String accountId, String owner, String stage) => customStatement(
      'UPDATE sync_lease SET stage = ?, stage_at = ? WHERE account_id = ? AND owner = ?',
      [stage, DateTime.now().millisecondsSinceEpoch, accountId, owner]);

  /// Кто держит аренду ящика и на каком этапе (для журнала при пропуске).
  Future<({String owner, String? stage, DateTime? stageAt, DateTime expiresAt})?> syncLeaseInfo(
      String accountId) async {
    final rows = await customSelect('SELECT * FROM sync_lease WHERE account_id = ?',
        variables: [Variable.withString(accountId)]).get();
    if (rows.isEmpty) return null;
    final r = rows.first.data;
    final at = r['stage_at'];
    return (
      owner: r['owner'] as String,
      stage: r['stage'] as String?,
      stageAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(r['expires_at'] as int),
    );
  }

  /// Создать индексы для быстрых запросов
  /// Полнотекстовый поиск FTS5: виртуальная таблица + триггеры синхронизации.
  /// Индексирует тему, отправителя, превью тела И текст вложений (OCR/извлечённый).
  Future<void> _createFts() async {
    // FTS5 виртуальная таблица. content='' — внешнее хранилище (rowid = ссылка).
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS emails_fts USING fts5(
        email_id UNINDEXED,
        account_id UNINDEXED,
        subject,
        from_text,
        body,
        attachments_text,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');
  }

  /// Переиндексировать письмо в FTS (вызывается при сохранении/обновлении).
  /// [attachmentsText] — извлечённый текст вложений (OCR/PDF/Word) для поиска.
  /// rowid записи поискового индекса — стабильный 53-битный хеш пары
  /// (аккаунт, письмо). Удаление и замена по rowid — точечные. Раньше
  /// запись искалась по столбцу email_id, который FTS5 не индексирует: каждое
  /// сохранение письма просматривало весь индекс, и синхронизация замедлялась
  /// по мере роста ящика.
  static int ftsRowId(String accountId, String emailId) {
    // Два 32-битных FNV-1a с разными началами → 53 бита: укладывается и в
    // целые JavaScript (веб-сборка), и в rowid SQLite.
    final bytes = utf8.encode('$accountId|$emailId');
    int fnv(int seed) {
      var h = seed;
      for (final c in bytes) {
        h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
      }
      return h;
    }
    final hi = fnv(0x811c9dc5) & 0x1FFFFF; // 21 бит
    final lo = fnv(0x050c5d1f); // 32 бита
    return hi * 0x100000000 + lo;
  }

  Future<void> indexEmailFts({
    required String emailId,
    String? accountId,
    required String subject,
    required String fromText,
    required String body,
    String attachmentsText = '',
  }) async {
    if (accountId == null) {
      await customStatement('DELETE FROM emails_fts WHERE email_id = ?', [emailId]);
      await customStatement(
        'INSERT INTO emails_fts(email_id, subject, from_text, body, attachments_text) VALUES (?, ?, ?, ?, ?)',
        [emailId, subject, fromText, body, attachmentsText],
      );
      return;
    }
    final rowId = ftsRowId(accountId, emailId);
    await customStatement('DELETE FROM emails_fts WHERE rowid = ?', [rowId]);
    await customStatement(
      'INSERT INTO emails_fts(rowid, email_id, account_id, subject, from_text, body, attachments_text) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [rowId, emailId, accountId, subject, fromText, body, attachmentsText],
    );
  }

  Future<void> removeEmailFts(String emailId, {String? accountId}) async {
    if (accountId != null) {
      await customStatement('DELETE FROM emails_fts WHERE rowid = ?', [ftsRowId(accountId, emailId)]);
    } else {
      await customStatement('DELETE FROM emails_fts WHERE email_id = ?', [emailId]);
    }
  }

  /// Пересобрать поисковый индекс из таблицы писем (миграция на v15:
  /// новый формат с rowid и аккаунтом).
  Future<void> rebuildFts() async {
    await customStatement('DELETE FROM emails_fts');
    // Постранично по rowid, а не LIMIT/OFFSET: OFFSET заново проходит все
    // пропущенные строки, и на 50 000 писем пересборка шла O(n²). Индекс
    // только что очищен — построчный DELETE в indexEmailFts не нужен.
    var lastRowId = 0;
    const page = 500;
    while (true) {
      final rows = await customSelect(
        'SELECT rowid AS rid, id, account_id, subject, from_name, from_email, body_plain, body_preview '
        'FROM emails WHERE rowid > ? ORDER BY rowid LIMIT ?',
        variables: [Variable.withInt(lastRowId), Variable.withInt(page)],
      ).get();
      if (rows.isEmpty) break;
      await transaction(() async {
        for (final r in rows) {
          final d = r.data;
          final id = d['id'] as String;
          final acc = d['account_id'] as String;
          await customStatement(
            'INSERT OR REPLACE INTO emails_fts(rowid, email_id, account_id, subject, from_text, body, attachments_text) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              ftsRowId(acc, id), id, acc,
              (d['subject'] as String?) ?? '',
              '${d['from_name'] ?? ''} ${d['from_email'] ?? ''}',
              (d['body_plain'] as String?) ?? (d['body_preview'] as String?) ?? '',
              '',
            ],
          );
        }
      });
      lastRowId = rows.last.data['rid'] as int;
    }
  }

  /// Условие «письмо папки, которое можно убрать только с телефона»:
  /// черновики, исходящие и письма с неотправленными на сервер правками не
  /// трогаются.
  Expression<bool> _localDropWhere(String accountId, List<String> folderIds) =>
      emails.accountId.equals(accountId) &
      emails.folderId.isIn(folderIds) &
      emails.isDraft.equals(false) &
      emails.isLocallyModified.equals(false);

  static List<String> _droppable(List<String> folderIds) =>
      folderIds.where((f) => f != 'drafts' && f != 'outbox').toList();

  /// Сколько писем [deleteLocalFolderEmails] уберёт с телефона.
  Future<int> countLocalFolderEmails(String accountId, List<String> folderIds) async {
    final ids = _droppable(folderIds);
    if (ids.isEmpty) return 0;
    final cnt = emails.id.count();
    final q = selectOnly(emails)
      ..addColumns([cnt])
      ..where(_localDropWhere(accountId, ids));
    return (await q.getSingle()).read(cnt) ?? 0;
  }

  /// Письма папок — только с телефона (1.5.9, выключение папки в
  /// «Синхронизации папок»; 1.5.10 — «Очистить от несинхронизируемых
  /// писем»): на сервере всё остаётся. Черновики, исходящие и письма с
  /// неотправленными на сервер правками не трогаются. Возвращает число
  /// удалённых писем.
  ///
  /// Порциями по [batch] писем, каждая — своей короткой записью (1.5.10):
  /// раньше всё удалялось одной транзакцией — на десятках тысяч писем база
  /// была занята записью секунды, и синхронизация, отметки «прочитано» и
  /// лента ждали. Между порциями — пауза в цикл событий; [onProgress] —
  /// сколько уже удалено.
  Future<int> deleteLocalFolderEmails(String accountId, List<String> folderIds,
      {void Function(int removed)? onProgress, int batch = 500}) async {
    final ids = _droppable(folderIds);
    if (ids.isEmpty) return 0;
    var n = 0;
    while (true) {
      final q = selectOnly(emails)
        ..addColumns([emails.id])
        ..where(_localDropWhere(accountId, ids))
        ..limit(batch);
      final part = await q.map((r) => r.read(emails.id)!).get();
      if (part.isEmpty) break;
      final removed =
          await (delete(emails)..where((e) => e.accountId.equals(accountId) & e.id.isIn(part))).go();
      n += removed;
      onProgress?.call(n);
      // Ничего не удалилось (письма поменялись между выборкой и удалением)
      // — не крутиться.
      if (removed == 0) break;
      await Future<void>.delayed(Duration.zero);
    }
    if (n > 0) {
      try {
        await pruneOrphanFts();
      } catch (_) {}
    }
    return n;
  }

  /// Удаляет из FTS-индекса записи, которым уже нет письма в `emails`.
  /// Вызывается автоочисткой и при «Оптимизировать хранилище».
  /// Разово (1.6.1): дубли писем ActiveSync, оставшиеся от сброса
  /// синхронизации на сервере (письмо пришло заново с новым ServerId, а
  /// строка с прежним осталась). Дубль — то же письмо в той же папке: тот же
  /// отправитель, тема, время получения и размер. Остаётся строка, которую
  /// синхронизация обновляла последней (её id сервер знает); локальные
  /// отметки («Позже», «На контроле», «Нет ответа», теги, «отвечено»)
  /// переносятся на неё, если у неё своих нет. Возвращает число убранных.
  Future<int> removeEasDuplicates(Iterable<String> accountIds) async {
    final accs = accountIds.toList();
    if (accs.isEmpty) return 0;
    final rows = await customSelect(
      'SELECT e.rowid AS r, e.account_id AS a, e.folder_id AS f, e.from_email AS fe, e.subject AS s, '
      'e.received_at AS t, e.size AS z, e.cached_at AS c, e.later_state AS ls, e.remind_at AS ra, '
      'e.control_state AS cs, e.control_replied AS cr, e.follow_up_at AS fu, e.tags_str AS tg, '
      'e.is_replied AS ir, e.is_forwarded AS iw, e.is_locally_modified AS lm '
      'FROM emails e JOIN (SELECT account_id, folder_id, lower(from_email) AS fe, subject, received_at, '
      'IFNULL(size, -1) AS z FROM emails WHERE account_id IN (${List.filled(accs.length, '?').join(', ')}) '
      'GROUP BY 1, 2, 3, 4, 5, 6 HAVING count(*) > 1) g '
      'ON e.account_id = g.account_id AND e.folder_id = g.folder_id AND lower(e.from_email) = g.fe '
      'AND e.subject = g.subject AND e.received_at = g.received_at AND IFNULL(e.size, -1) = g.z',
      variables: [for (final a in accs) Variable.withString(a)],
      readsFrom: {emails},
    ).get();
    if (rows.isEmpty) return 0;
    final groups = <String, List<QueryRow>>{};
    for (final r in rows) {
      final k = '${r.data['a']}|${r.data['f']}|${(r.data['fe'] as String).toLowerCase()}|'
          '${r.data['s']}|${r.data['t']}|${r.data['z']}';
      (groups[k] ??= []).add(r);
    }
    var removed = 0;
    await transaction(() async {
      for (final g in groups.values) {
        if (g.length < 2) continue;
        g.sort((x, y) {
          final c = ((y.data['c'] as int?) ?? 0).compareTo((x.data['c'] as int?) ?? 0);
          return c != 0 ? c : (y.data['r'] as int).compareTo(x.data['r'] as int);
        });
        final keep = g.first;
        Object? pick(String col, bool Function(Object? v) empty) {
          if (!empty(keep.data[col])) return keep.data[col];
          for (final x in g.skip(1)) {
            if (!empty(x.data[col])) return x.data[col];
          }
          return keep.data[col];
        }

        bool zero(Object? v) => v == null || v == 0;
        bool blank(Object? v) => v == null || (v is String && v.isEmpty);
        await customStatement(
          'UPDATE emails SET later_state = ?, remind_at = ?, control_state = ?, control_replied = ?, '
          'follow_up_at = ?, tags_str = ?, is_replied = ?, is_forwarded = ? WHERE rowid = ?',
          [
            pick('ls', zero), pick('ra', blank), pick('cs', zero), pick('cr', blank),
            pick('fu', blank), pick('tg', blank), pick('ir', zero), pick('iw', zero), keep.data['r'],
          ],
        );
        final drop = [for (final x in g.skip(1)) if (x.data['lm'] != 1) x.data['r'] as int];
        if (drop.isEmpty) continue;
        removed += await customUpdate('DELETE FROM emails WHERE rowid IN (${drop.join(', ')})');
      }
    });
    if (removed > 0) notifyUpdates({TableUpdate.onTable(emails, kind: UpdateKind.delete)});
    return removed;
  }

  Future<int> pruneOrphanFts() async {
    return customUpdate(
      'DELETE FROM emails_fts WHERE NOT EXISTS (SELECT 1 FROM emails e '
      'WHERE e.id = emails_fts.email_id '
      'AND (emails_fts.account_id IS NULL OR e.account_id = emails_fts.account_id))',
      updates: {},
    );
  }

  /// Полнотекстовый поиск через FTS5. Возвращает письма по релевантности.
  /// При ошибке FTS откатывается на LIKE-поиск.
  Future<List<Email>> searchEmailsFts({
    required String accountId,
    required String query,
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      // Префиксный матч: каждое слово + '*'
      final ftsQuery = trimmed
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map((w) => '${w.replaceAll('"', '')}*')
          .join(' ');
      // Шаг 1: получаем id писем по релевантности из FTS
      final idRows = await customSelect(
        '''SELECT f.email_id AS eid FROM emails_fts f
           WHERE f.emails_fts MATCH ? AND f.account_id = ?
           ORDER BY rank
           LIMIT ?''',
        variables: [Variable.withString(ftsQuery), Variable.withString(accountId), Variable.withInt(limit)],
        readsFrom: {emails},
      ).get();
      final ids = idRows.map((r) => r.data['eid'] as String).toList();
      if (ids.isNotEmpty) {
        // Шаг 2: загружаем письма через типобезопасный Drift-запрос
        final rows = await (select(emails)
              ..where((e) => e.id.isIn(ids) & e.accountId.equals(accountId)))
            .get();
        // Сохраняем порядок релевантности из FTS
        final byId = {for (final e in rows) e.id: e};
        return [for (final id in ids) if (byId[id] != null) byId[id]!];
      }
    } catch (e) {
      // FTS недоступен/ошибка синтаксиса — откат на LIKE ниже
    }
    return searchEmails(accountId: accountId, query: query, limit: limit);
  }

  /// Добавить столбец, если его ещё нет (повторный запуск шага безопасен).
  Future<void> _addColumnIfMissing(Migrator m, TableInfo table, GeneratedColumn column) async {
    final cols = await customSelect('PRAGMA table_info("${table.actualTableName}")').get();
    final exists = cols.any((r) => r.data['name'] == column.name);
    if (!exists) await m.addColumn(table, column);
  }

  Future<void> _createIndexes(Migrator m) async {
    // Напоминание «нет ответа» — раньше индекс создавался только миграцией,
    // и на новых установках его не было.
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_followup '
        'ON emails (follow_up_at) WHERE follow_up_at IS NOT NULL');
    // «На контроле»: частичный индекс — строк единицы.
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_control '
        'ON emails (control_state) WHERE control_state > 0');
    // «Посмотреть позже»: частичный индекс, сортировка по сроку возврата.
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_later '
        'ON emails (later_state, remind_at) WHERE later_state > 0');
    // Поиск письма-корня беседы по Message-ID (заголовки References).
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_message_id '
        'ON emails(internet_message_id)');
    // Непрочитанные по папке (счётчики в панели папок и сводный счётчик).
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_folder_unread '
        'ON emails(account_id, folder_id) WHERE is_read = 0');
    // Индексы писем — критичны для пагинации
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_account_folder_date '
        'ON emails(account_id, folder_id, received_at DESC)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_conversation '
        'ON emails(conversation_id, received_at ASC)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_account_date '
        'ON emails(account_id, received_at DESC)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_unread '
        'ON emails(account_id, is_read) WHERE is_read = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_flagged '
        'ON emails(account_id, is_flagged) WHERE is_flagged = 1');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_tags '
        'ON emails(tags_str)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_search '
        'ON emails(subject, from_email, from_name)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_emails_sender '
        'ON emails(account_id, from_email)');

    // Индексы папок
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_folders_account '
        'ON folders(account_id)');

    // Индексы контактов
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_contacts_email '
        'ON contacts(email)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_contacts_name '
        'ON contacts(display_name)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_contacts_interaction '
        'ON contacts(interaction_count DESC)');

    // Индексы календаря
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_calendar_account_date '
        'ON calendar_events(account_id, start_time)');

    // Индексы задач
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_account_status '
        'ON tasks(account_id, status, due_date)');

    // Индексы очереди синхронизации
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_account '
        'ON sync_queue(account_id, priority DESC, created_at ASC)');
  }

  /// Индексы подсистемы «Поручения» (Assignments).
  Future<void> _createAssignmentIndexes(Migrator m) async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignments_account_status '
        'ON assignments(account_id, status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignments_parent '
        'ON assignments(parent_assignment_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_participants_email '
        'ON assignment_participants(email)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_events_assignment '
        'ON assignment_events(assignment_id, created_at ASC)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_events_pending '
        'ON assignment_events(delivery_status) WHERE delivery_status = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_proposals_assignment '
        'ON assignment_proposals(assignment_id, status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_votes_proposal '
        'ON assignment_votes(proposal_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assignment_meetings_assignment '
        'ON assignment_meetings(assignment_id)');
  }

  /// Пересоздание схемы при несовместимой старой БД (миграция v3→v4).
  /// Старые БД могли не иметь колонок type/sort_order — таблицы пересоздаются.
  /// Локальные данные — кеш сервера, восстанавливаются синхронизацией.
  Future<void> _recreateSchema(Migrator m) async {
    const tables = [
      'accounts', 'emails', 'folders', 'contacts', 'calendar_events',
      'tasks', 'signatures', 'sync_queue', 'audit_log',
    ];
    for (final t in tables) {
      try { await customStatement('DROP TABLE IF EXISTS $t'); } catch (_) {}
    }
    try { await customStatement('DROP TABLE IF EXISTS emails_fts'); } catch (_) {}
    await m.createAll();
    await _createIndexes(m);
    await _createFts();
  }

  // ════════════════════════ ПАГИНАЦИЯ ПИСЕМ ════════════════════════

  void _applyListFilter(_EmailListQuery q, EmailListFilter? f) {
    if (f == null) return;
    if (f.unread) q.where((e) => e.isRead.equals(false));
    if (f.flagged) q.where((e) => e.isFlagged.equals(true));
    if (f.control) q.where((e) => e.controlState.isBiggerThanValue(0));
    if (f.later) {
      q.where((e) => e.laterState.isBiggerThanValue(0));
      // Порядок списка заменяется: срок возврата важнее даты получения.
      q.orderBy([
        (e) => OrderingTerm(expression: e.laterState, mode: OrderingMode.desc),
        (e) => OrderingTerm(expression: e.remindAt, nulls: NullsOrder.last),
        (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
        (e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc),
      ]);
    }
    if (f.attachments) q.where((e) => e.hasAttachments.equals(true));
    // VIP — отправитель из списка VIP, слово из списка в теме или высокая
    // важность (как FocusModeNotifier.isVip). Раньше список VIP здесь не
    // учитывался, и фильтр показывал пустую ленту (замечание 11.10.2026).
    if (f.vip) {
      q.where((e) {
        Expression<bool> c = e.priority.equals(0);
        if (f.vipEmails.isNotEmpty) c = c | e.fromEmail.lower().isIn(f.vipEmails);
        for (final k in f.vipKeywords) {
          if (k.isNotEmpty) c = c | e.subject.lower().like('%$k%');
        }
        return c;
      });
    }
    if (f.since != null) q.where((e) => e.receivedAt.isBiggerOrEqualValue(f.since!));
    final tag = f.tag;
    if (tag != null && tag.isNotEmpty) {
      // Грубый отбор в SQL; точное совпадение тега проверяется в памяти.
      q.where((e) => e.tagsStr.like('%$tag%'));
    }
    final me = f.toMe;
    if (me != null && me.isNotEmpty) {
      q.where((e) => e.toRecipients.lower().like('%"email":"$me"%'));
    }
    f.excludedFolders.forEach((acc, ids) {
      if (ids.isEmpty) return;
      q.where((e) => (e.accountId.equals(acc) & e.folderId.isIn(ids)).not());
    });
  }

  /// Получить страницу писем из папки (пагинация)
  // Сортировка списка писем.
  List<OrderClauseGenerator<$EmailsTable>> _emailOrder(MailSort sort) {
    switch (sort) {
      case MailSort.dateOldest:
        return [(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.asc)];
      case MailSort.senderAZ:
        return [
          (e) => OrderingTerm(expression: e.fromName, mode: OrderingMode.asc),
          (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
        ];
      case MailSort.subjectAZ:
        return [
          (e) => OrderingTerm(expression: e.subject, mode: OrderingMode.asc),
          (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
        ];
      case MailSort.sizeLargest:
        return [
          (e) => OrderingTerm(expression: e.size, mode: OrderingMode.desc),
          (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
        ];
      case MailSort.sizeSmallest:
        return [
          (e) => OrderingTerm(expression: e.size, mode: OrderingMode.asc),
          (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
        ];
      case MailSort.dateNewest:
        // Второй ключ — id: при одинаковой дате порядок стабилен, строки не
        // «прыгают» при каждом обновлении списка.
        return [
          (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
          (e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc),
        ];
    }
  }

  /// Построение запроса писем папки. Вынесено, чтобы ОДИН и тот же запрос отдавал
  /// и разовый результат (`.get()`), и живой поток (`.watch()`). Поток нужен для
  /// offline-first: список подписан на БД и обновляется сам — при фоновой
  /// синхронизации, локальных действиях и разборе офлайн-очереди, не дожидаясь сети.
  _EmailListQuery _emailsPageQuery({
    required String accountId,
    required String folderId,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
    bool withLocalDrafts = false,
  }) {
    // Папка «Черновики» показывает и черновики, сохранённые приложением
    // (folder_id 'drafts'): у них нет серверной папки, и раньше их не было
    // видно нигде — продолжить сохранённое письмо было невозможно.
    // Условие «ИЛИ черновики» — только для папки черновиков: в общем запросе
    // оно лишало SQLite индекса по дате — каждое обновление ленты читало и
    // сортировало ВСЕ письма папки вместе с текстами (аудит 11.10.2026).
    final q = _EmailListQuery(emails)..where((e) => e.accountId.equals(accountId));
    if (withLocalDrafts) {
      q.where((e) => e.folderId.isIn([folderId, 'drafts']));
    } else {
      q.where((e) => e.folderId.equals(folderId));
    }
    q
      ..orderBy(_emailOrder(sortBy))
      ..limit(limit, offset: offset);
    _applyListFilter(q, filter);
    return q;
  }

  /// Папка — «Черновики» ящика (в ней же показываются черновики приложения).
  Future<bool> _isDraftsFolder(String accountId, String folderId) async {
    final f = await (select(folders)
          ..where((x) => x.id.equals(folderId) & x.accountId.equals(accountId))
          ..limit(1))
        .getSingleOrNull();
    return f?.type == 2; // FolderType.drafts
  }

  Future<List<Email>> getEmailsPage({
    required String accountId,
    required String folderId,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
  }) async {
    return _emailsPageQuery(
      accountId: accountId, folderId: folderId,
      limit: limit, offset: offset, sortBy: sortBy,
      withLocalDrafts: await _isDraftsFolder(accountId, folderId),
    ).full(this).get();
  }

  /// Живой поток писем папки — переизлучается при любом изменении таблицы.
  Stream<List<Email>> watchEmailsPage({
    required String accountId,
    required String folderId,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
  }) async* {
    final drafts = await _isDraftsFolder(accountId, folderId);
    yield* _emailsPageQuery(
      accountId: accountId, folderId: folderId,
      limit: limit, offset: offset, sortBy: sortBy, filter: filter,
      withLocalDrafts: drafts,
    ).watchLight(this);
  }

  /// Получить все письма аккаунта для Unified Inbox (пагинация, без спама)
  /// Получить письмо по id из локальной БД (с телом, если оно сохранено).
  /// Письмо по id. [accountId] обязателен везде, где он известен: id
  /// уникален только в паре с аккаунтом (у двух ящиков ActiveSync бывают
  /// одинаковые «5:12»), и без него getSingleOrNull падал с «Too many elements».
  Future<Email?> getEmailById(String emailId, {String? accountId}) async {
    final q = select(emails)..where((e) => e.id.equals(emailId));
    if (accountId != null) q.where((e) => e.accountId.equals(accountId));
    q.limit(1);
    return (await q.get()).firstOrNull;
  }

  /// Папка письма не исключена из «Всей почты» (`folders.show_in_unified`).
  /// Раньше колонка заполнялась, но не читалась: отправленные IMAP/EWS и
  /// виртуальные папки Gmail («Вся почта», «Важные») попадали в общую ленту.
  /// Письмо без строки папки показывается.
  ///
  /// Папки, выключенные в «Синхронизации папок», — тоже не во «Всей почте»
  /// (1.5.9): человек решил их не загружать, а письма, полученные раньше
  /// (или найденные поиском на сервере), всё равно показывались в общей
  /// ленте.
  static const _inUnifiedFolder = CustomExpression<bool>(
      'NOT EXISTS (SELECT 1 FROM folders uf WHERE uf.id = emails.folder_id '
      'AND uf.account_id = emails.account_id AND (uf.show_in_unified = 0 OR uf.is_synced = 0))');

  _EmailListQuery _unifiedInboxQuery({
    required String accountId,
    required int limit,
    required int offset,
    List<String> excludeFolderNames = const [
      'Junk Email', 'Спам', 'junk', 'Нежелательная почта', 'Spam',
      'Trash', 'Корзина', 'Deleted Items', 'Удалённые', 'Удаленные', 'Bin',
      'Drafts', 'Черновики', 'Junk',
    ],
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
  }) {
    // Папки-идентификаторы корзины/спама/черновиков (IMAP/EWS варианты)
    const excludeFolderIds = [
      'trash', 'spam', 'junk', 'deleted', 'drafts', 'bin',
    ];
    final q = _EmailListQuery(emails)
      ..where((e) => e.accountId.equals(accountId))
      // NULL в имени папки — не повод прятать письмо (NOT IN с NULL даёт NULL).
      ..where((e) => e.folderName.isNull() | e.folderName.isNotIn(excludeFolderNames))
      ..where((e) => e.folderId.lower().isNotIn(excludeFolderIds))
      ..where((_) => _inUnifiedFolder)
      ..orderBy(_emailOrder(sortBy))
      ..limit(limit, offset: offset);
    _applyListFilter(q, filter);
    return q;
  }

  Future<List<Email>> getUnifiedInboxPage({
    required String accountId,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
  }) {
    return _unifiedInboxQuery(
      accountId: accountId, limit: limit, offset: offset, sortBy: sortBy,
    ).full(this).get();
  }

  /// Живой поток «Всей почты» аккаунта.
  Stream<List<Email>> watchUnifiedInboxPage({
    required String accountId,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
  }) {
    return _unifiedInboxQuery(
      accountId: accountId, limit: limit, offset: offset, sortBy: sortBy, filter: filter,
    ).watchLight(this);
  }

  /// Получить все письма ВСЕХ аккаунтов для Unified All (пагинация)
  _EmailListQuery _allAccountsQuery({
    required List<String> accountIds,
    required int limit,
    required int offset,
    List<String> excludeFolderNames = const [
      'Junk Email', 'Спам', 'junk', 'Нежелательная почта', 'Spam',
      'Trash', 'Корзина', 'Deleted Items', 'Удалённые', 'Удаленные', 'Bin',
      'Drafts', 'Черновики', 'Junk',
    ],
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
  }) {
    // «Хаб аккаунтов»: все письма всех аккаунтов, кроме Спама и Корзины
    // (по именам и по служебным folderId — IMAP/EWS варианты).
    const excludeFolderIds = [
      'trash', 'spam', 'junk', 'deleted', 'drafts', 'bin',
    ];
    // «+» перед столбцом — подсказка SQLite не брать индекс по ящику: с ним
    // при нескольких ящиках он читал ВСЕ их письма и сортировал по дате при
    // каждом обновлении ленты; без него идёт по индексу даты (idx_emails_date)
    // и останавливается, набрав окно (аудит 11.10.2026, проверено EXPLAIN
    // QUERY PLAN).
    String lit(String v) => "'${v.replaceAll("'", "''")}'";
    final accountsIn = CustomExpression<bool>(
        accountIds.isEmpty ? '0' : '+emails.account_id IN (${accountIds.map(lit).join(', ')})');
    final q = _EmailListQuery(emails)
      ..where((_) => accountsIn)
      // NULL в имени папки — не повод прятать письмо (NOT IN с NULL даёт NULL).
      ..where((e) => e.folderName.isNull() | e.folderName.isNotIn(excludeFolderNames))
      ..where((e) => e.folderId.lower().isNotIn(excludeFolderIds))
      ..where((_) => _inUnifiedFolder)
      ..orderBy(_emailOrder(sortBy))
      ..limit(limit, offset: offset);
    _applyListFilter(q, filter);
    return q;
  }

  Future<List<Email>> getAllAccountsUnifiedPage({
    required List<String> accountIds,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
  }) {
    return _allAccountsQuery(
      accountIds: accountIds, limit: limit, offset: offset, sortBy: sortBy,
    ).full(this).get();
  }

  /// Живой поток «Всей почты» всех аккаунтов.
  Stream<List<Email>> watchAllAccountsUnifiedPage({
    required List<String> accountIds,
    required int limit,
    required int offset,
    MailSort sortBy = MailSort.dateNewest,
    EmailListFilter? filter,
  }) {
    return _allAccountsQuery(
      accountIds: accountIds, limit: limit, offset: offset, sortBy: sortBy, filter: filter,
    ).watchLight(this);
  }

  /// Получить беседу (все письма с одним conversationId)
  Future<List<Email>> getConversation({
    required String conversationId,
    required String accountId,
  }) async {
    return dedupCopies(await (select(emails)
          ..where((e) => e.conversationId.equals(conversationId))
          ..where((e) => e.accountId.equals(accountId))
          ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.asc)]))
        .get());
  }

  /// Одно письмо — одна строка беседы. У Gmail письмо лежит и во
  /// «Входящих», и во «Всей почте» (и в папках ярлыков) — в беседе оно
  /// показывалось дважды (замечание 09.10.2026). Склеиваем по Message-ID;
  /// из копий оставляем ту, что не в служебной папке Gmail.
  static List<Email> dedupCopies(List<Email> rows) {
    bool virtualFolder(Email e) {
      final f = '${e.folderId} ${e.folderName ?? ''}'.toLowerCase();
      return f.contains('[gmail]') ||
          f.contains('[google mail]') ||
          f.contains('all mail') ||
          f.contains('вся почта') ||
          f.contains('important') ||
          f.contains('важные') ||
          f.contains('starred') ||
          f.contains('помеченные');
    }

    final byMid = <String, int>{};
    final out = <Email>[];
    for (final e in rows) {
      final raw = e.internetMessageId?.trim().toLowerCase() ?? '';
      if (raw.isEmpty || !raw.contains('@')) {
        out.add(e);
        continue;
      }
      final mid = '${e.accountId}|$raw';
      final i = byMid[mid];
      if (i == null) {
        byMid[mid] = out.length;
        out.add(e);
      } else if (virtualFolder(out[i]) && !virtualFolder(e)) {
        out[i] = e;
      }
    }
    return out;
  }

  /// Письма без тел (HTML и текст) — для всего, что тексты не показывает:
  /// слияние при синхронизации, «Мой день», виджет, задачи, карточка
  /// человека. Длинный текст лежит в страницах переполнения, и выборка
  /// строк целиком расшифровывала и копировала его без нужды.
  /// Строки без тел НЕЛЬЗЯ записывать обратно целиком (replace,
  /// insertOrReplace): тела в базе обнулятся. Только update нужных полей.
  Selectable<Email> emailsLight(
    Expression<bool> Function($EmailsTable e) where, {
    List<OrderingTerm> Function($EmailsTable e)? orderBy,
    int? limit,
    int? offset,
  }) {
    final q = _EmailListQuery(emails)..where(where);
    if (orderBy != null) q.orderBy([for (final o in orderBy(emails)) (_) => o]);
    if (limit != null) q.limit(limit, offset: offset);
    return q.light(this);
  }

  /// Беседа как поток, без тел писем: экран беседы обновляется при прочтении,
  /// удалении и новых письмах без перезагрузки. Раньше поток читал тексты
  /// всех писем цепочки (в длинной беседе — мегабайты) при каждом изменении
  /// таблицы писем, то есть во время синхронизации — несколько раз в секунду.
  /// Карточкам беседы нужны шапка и превью; превью, которого нет в строке,
  /// даёт [previewsFromBody]. Строки без тел обратно в базу не записывать.
  Stream<List<Email>> watchConversationLight({
    required String conversationId,
    required String accountId,
  }) {
    final q = _EmailListQuery(emails)
      ..where((e) => e.conversationId.equals(conversationId) & e.accountId.equals(accountId))
      ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)]);
    return q.watchLight(this).map(dedupCopies);
  }

  /// Превью из сохранённого текста письма — начало text/plain одной строкой,
  /// не длиннее 200 символов (SQL: substr считает символы, эмодзи не рвёт).
  static const previewFromPlainSql =
      "substr(trim(replace(replace(replace(substr(body_plain, 1, 600), char(13), ' '), "
      "char(10), ' '), char(9), ' ')), 1, 200)";

  /// Превью для писем, у которых его нет в строке (IMAP при синхронизации
  /// получает только заголовки, превью появляется из текста): только начало
  /// текста, а не весь текст в главный поток. id → превью; пустые не входят.
  Future<Map<String, String>> previewsFromBody(String accountId, List<String> ids) async {
    final out = <String, String>{};
    for (var i = 0; i < ids.length; i += 400) {
      final part = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final rows = await customSelect(
        'SELECT id, $previewFromPlainSql AS p FROM emails '
        'WHERE account_id = ? AND id IN (${List.filled(part.length, '?').join(', ')}) '
        'AND body_plain IS NOT NULL',
        variables: [Variable.withString(accountId), for (final id in part) Variable.withString(id)],
        readsFrom: {emails},
      ).get();
      for (final r in rows) {
        final p = r.read<String?>('p');
        if (p != null && p.isNotEmpty) out[r.read<String>('id')] = p;
      }
    }
    return out;
  }

  /// Разово (1.6.31): источники превью с переносами — начало сохранённого
  /// текста или HTML письма, порциями по rowid.
  Future<List<({int rowid, String? plain, String? html, String? preview})>> previewSources(
      int afterRowid, int limit) async {
    final rows = await customSelect(
      'SELECT rowid AS r, substr(body_plain, 1, 4000) AS p, substr(body_html, 1, 60000) AS h, '
      'body_preview AS v FROM emails WHERE rowid > ? AND (body_plain IS NOT NULL OR body_html IS NOT NULL) '
      'ORDER BY rowid LIMIT ?',
      variables: [Variable.withInt(afterRowid), Variable.withInt(limit)],
      readsFrom: {emails},
    ).get();
    return [
      for (final r in rows)
        (
          rowid: r.read<int>('r'),
          plain: r.read<String?>('p'),
          html: r.read<String?>('h'),
          preview: r.read<String?>('v'),
        ),
    ];
  }

  /// Записать превью по rowid без оповещения списков на каждую строку.
  Future<void> setPreviewsByRowid(Map<int, String> previews) async {
    if (previews.isEmpty) return;
    await transaction(() async {
      for (final e in previews.entries) {
        await customUpdate('UPDATE emails SET body_preview = ? WHERE rowid = ?',
            variables: [Variable.withString(e.value), Variable.withInt(e.key)]);
      }
    });
  }

  /// Разово (1.5.9): превью из сохранённого текста для писем, у которых его
  /// нет. Лента с 1.5.8 читает строки без тел, а у писем IMAP превью в строке
  /// не было — оно бралось из текста, и лента IMAP осталась без превью.
  /// Порциями по [chunk] строк и без оповещения списков на каждую порцию:
  /// база не занята надолго. Возвращает число обработанных строк.
  Future<int> fillMissingPreviews({int chunk = 400}) async {
    var total = 0;
    var last = 0;
    while (true) {
      final done = await transaction(() async {
        final m = await customSelect(
          'SELECT max(r) AS m FROM (SELECT rowid AS r FROM emails '
          'WHERE rowid > ? AND body_preview IS NULL AND body_plain IS NOT NULL '
          'ORDER BY rowid LIMIT ?)',
          variables: [Variable.withInt(last), Variable.withInt(chunk)],
        ).getSingle();
        final upTo = m.read<int?>('m');
        if (upTo == null) return true;
        // Пустой результат — пустая строка, а не NULL: строка не попадёт в
        // следующую порцию.
        final n = await customUpdate(
          "UPDATE emails SET body_preview = COALESCE($previewFromPlainSql, '') "
          'WHERE rowid > ? AND rowid <= ? AND body_preview IS NULL AND body_plain IS NOT NULL',
          variables: [Variable.withInt(last), Variable.withInt(upTo)],
        );
        total += n;
        last = upTo;
        return false;
      });
      if (done) break;
      // Синхронизации и действиям пользователя — окно между порциями.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (total > 0) notifyUpdates({TableUpdate.onTable(emails, kind: UpdateKind.update)});
    return total;
  }

  /// Уровень «текст на телефоне и в поисковом индексе» (как у
  /// OfflineStoreService). Текст, сохранённый при открытии письма, остаётся
  /// на уровне 0 — его доиндексирует OfflineStoreService.
  static const levelIndexed = 2;

  /// Разово (1.5.9): письма с текстом не на уровне 2, чей текст уже в поисковом
  /// индексе (ActiveSync присылает тексты при синхронизации, и они сразу
  /// индексируются), получают уровень [levelIndexed]. Остальные — тексты,
  /// сохранённые при открытии письма и предзагрузкой: в индекс они не
  /// попадали, и письмо не находилось по словам из текста; они остаются на
  /// уровне 0 и индексируются в фоне. Признак «в индексе» — текст в индексе
  /// длиннее превью (300 символов). Возвращает (помечено, осталось).
  Future<({int marked, int left})> markIndexedBodies({int chunk = 500}) async {
    final hasBody = await hasBodySql();
    var last = 0;
    var marked = 0;
    var left = 0;
    while (true) {
      final rows = await customSelect(
        'SELECT rowid AS r, id, account_id FROM emails '
        'WHERE rowid > ? AND loaded_level <> $levelIndexed AND $hasBody ORDER BY rowid LIMIT ?',
        variables: [Variable.withInt(last), Variable.withInt(chunk)],
        readsFrom: {emails},
      ).get();
      if (rows.isEmpty) break;
      last = rows.last.read<int>('r');
      final keyOf = <int, ({String acc, String id})>{
        for (final r in rows)
          ftsRowId(r.read<String>('account_id'), r.read<String>('id')):
              (acc: r.read<String>('account_id'), id: r.read<String>('id')),
      };
      var found = const <QueryRow>[];
      try {
        found = await customSelect(
          'SELECT rowid AS f FROM emails_fts WHERE rowid IN (${keyOf.keys.join(', ')}) AND length(body) >= 300',
        ).get();
      } catch (_) {/* поискового индекса нет — всё остаётся на уровне 0 */}
      final byAcc = <String, List<String>>{};
      for (final f in found) {
        final k = keyOf[f.read<int>('f')];
        if (k != null) (byAcc[k.acc] ??= []).add(k.id);
      }
      for (final e in byAcc.entries) {
        await customUpdate(
          'UPDATE emails SET loaded_level = $levelIndexed WHERE account_id = ? AND loaded_level <> $levelIndexed '
          'AND id IN (${List.filled(e.value.length, '?').join(', ')})',
          variables: [Variable.withString(e.key), for (final id in e.value) Variable.withString(id)],
        );
        marked += e.value.length;
      }
      left += rows.length - found.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return (marked: marked, left: left);
  }

  /// Число писем в беседах (по всем папкам аккаунта, включая «Отправленные»).
  /// Ключ — «аккаунт|беседа»; в ответе только беседы из двух и более писем.
  Future<Map<String, int>> conversationSizes(Set<String> conversationIds) async {
    final out = <String, int>{};
    final ids = conversationIds.toList();
    // SQLite ограничивает число параметров запроса — идём порциями.
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final marks = List.filled(part.length, '?').join(',');
      final rows = await customSelect(
        // Копии одного письма (Gmail: «Входящие» и «Вся почта») — одно письмо.
        "SELECT account_id, conversation_id, COUNT(DISTINCT COALESCE(NULLIF(internet_message_id, ''), id)) AS cnt FROM emails "
        'WHERE conversation_id IN ($marks) '
        'GROUP BY account_id, conversation_id HAVING cnt > 1',
        variables: [for (final id in part) Variable.withString(id)],
        readsFrom: {emails},
      ).get();
      for (final r in rows) {
        out['${r.data['account_id']}|${r.data['conversation_id']}'] = r.data['cnt'] as int;
      }
    }
    return out;
  }

  /// Сводка бесед для строки свёрнутой беседы: число писем, непрочитанных
  /// и отметка «На контроле» любого письма беседы (важнее: «нужно ответить»,
  /// «жду ответа», затем «исполнено»). Только беседы из 2+ писем.
  Future<Map<String, ({int count, int unread, int control, String? replied, String? to})>> conversationStats(
      Set<String> conversationIds) async {
    final out = <String, ({int count, int unread, int control, String? replied, String? to})>{};
    final ids = conversationIds.toList();
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final marks = List.filled(part.length, '?').join(',');
      final rows = await customSelect(
        'SELECT account_id, conversation_id, COUNT(*) AS cnt, '
        'SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS unread, '
        'MAX(CASE control_state WHEN 2 THEN 4 WHEN 1 THEN 3 WHEN 3 THEN 2 ELSE 0 END) AS ctl, '
        'MAX(CASE WHEN control_state = 1 THEN control_replied END) AS replied, '
        'MAX(CASE WHEN control_state = 1 THEN to_recipients END) AS rcpt '
        'FROM emails WHERE conversation_id IN ($marks) '
        'GROUP BY account_id, conversation_id HAVING cnt > 1',
        variables: [for (final id in part) Variable.withString(id)],
        readsFrom: {emails},
      ).get();
      for (final r in rows) {
        final rank = (r.data['ctl'] as int?) ?? 0;
        out['${r.data['account_id']}|${r.data['conversation_id']}'] = (
          count: r.data['cnt'] as int,
          unread: (r.data['unread'] as int?) ?? 0,
          control: switch (rank) { 4 => 2, 3 => 1, 2 => 3, _ => 0 },
          replied: r.data['replied'] as String?,
          to: r.data['rcpt'] as String?,
        );
      }
    }
    return out;
  }

  /// Письма беседы для действий над свёрнутой строкой (1.7.2): на контроле
  /// ([controlled]) и/или непрочитанные ([unread]).
  Future<List<({String id, String folderId})>> conversationMembers(String accountId, String conversationId,
      {bool controlled = false, bool unread = false}) async {
    final q = select(emails)
      ..where((e) => e.accountId.equals(accountId) & e.conversationId.equals(conversationId));
    if (controlled) q.where((e) => e.controlState.isBiggerThanValue(0));
    if (unread) q.where((e) => e.isRead.equals(false));
    final rows = await q.get();
    return [for (final r in rows) (id: r.id, folderId: r.folderId)];
  }

  /// Письма от одного отправителя (группировка беседы «по отправителю», И1)
  Future<List<Email>> getEmailsBySender({
    required String accountId,
    required String fromEmail,
    int limit = 50,
  }) async {
    return (select(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.fromEmail.lower().equals(fromEmail.toLowerCase()))
          ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.asc)])
          ..limit(limit))
        .get();
  }

  // ─────────── Тексты писем на телефоне (1.5.6) ───────────

  /// Что умеет SQLite этой сборки: octet_length (длина поля без чтения
  /// самого текста, SQLite 3.43+) и функции JSON. Проверяется один раз.
  bool? _octetLength;
  bool? _jsonFns;

  Future<void> _probeSqlCaps() async {
    if (_octetLength != null && _jsonFns != null) return;
    try {
      await customSelect("SELECT octet_length('x') AS n").getSingle();
      _octetLength = true;
    } catch (_) {
      _octetLength = false;
    }
    try {
      await customSelect("SELECT json_valid('[]') AS n").getSingle();
      _jsonFns = true;
    } catch (_) {
      _jsonFns = false;
    }
  }

  /// SQL-условие «у письма есть текст» (колонки таблицы emails без
  /// префикса). С octet_length SQLite берёт длину из заголовка записи и
  /// не читает сам текст: прежнее «body_html = ''» читало и расшифровывало
  /// тексты всех писем ящика при каждом проходе «Писем на телефоне».
  /// Корректно после [hasBodySql] (или любого запроса ниже).
  String get hasBodyExpr => _octetLength == true
      ? '(COALESCE(octet_length(body_html),0) > 0 OR COALESCE(octet_length(body_plain),0) > 0)'
      : "(COALESCE(body_html,'') <> '' OR COALESCE(body_plain,'') <> '')";

  /// [hasBodyExpr] после проверки возможностей SQLite.
  Future<String> hasBodySql() async {
    await _probeSqlCaps();
    return hasBodyExpr;
  }

  /// Байты текста письма на телефоне (HTML и простой текст).
  String get _textBytesExpr => _octetLength == true
      ? '(COALESCE(octet_length(body_html),0) + COALESCE(octet_length(body_plain),0))'
      : "(LENGTH(CAST(COALESCE(body_html,'') AS BLOB)) + LENGTH(CAST(COALESCE(body_plain,'') AS BLOB)))";

  /// Размер вложений по списку письма (attachments_json).
  String get _attachBytesExpr => _jsonFns == true
      ? "(SELECT COALESCE(SUM(CAST(json_extract(j.value, '\$.size') AS INTEGER)), 0) "
          "FROM json_each(CASE WHEN json_valid(attachments_json) THEN attachments_json ELSE '[]' END) j)"
      : '0';

  /// Размер письма: с сервера, а если сервер его не сообщил (ActiveSync
  /// размер письма не передаёт) — текст на телефоне плюс вложения по
  /// списку. Раньше у писем ActiveSync размер был пуст, и «Удалить тяжёлые
  /// письма» не находило ничего.
  String get _sizeExpr => '(CASE WHEN COALESCE(size,0) > 0 THEN size ELSE $_textBytesExpr + $_attachBytesExpr END)';

  /// Письма аккаунта на телефоне: сколько их, сколько с текстом и сколько
  /// места занимает текст. Раньше суммировался размер с сервера (`size`),
  /// а ActiveSync его не сообщает — «Размер ящика» показывал 0 Б при
  /// тысячах писем с текстом на телефоне (замечание 11.10.2026).
  Future<({int count, int bytes, int withText})> mailboxStats(String accountId) async {
    await _probeSqlCaps();
    final r = await customSelect(
      'SELECT COUNT(*) AS c, COALESCE(SUM($_textBytesExpr), 0) AS b, '
      'COALESCE(SUM(CASE WHEN $hasBodyExpr THEN 1 ELSE 0 END), 0) AS t '
      'FROM emails WHERE account_id = ?',
      variables: [Variable.withString(accountId)],
      readsFrom: {emails},
    ).getSingle();
    return (
      count: (r.data['c'] as int?) ?? 0,
      bytes: (r.data['b'] as int?) ?? 0,
      withText: (r.data['t'] as int?) ?? 0,
    );
  }

  /// Колонки, которые можно записать [storeBodiesQuietly].
  static const _quietColumns = {
    'body_html', 'body_plain', 'body_preview', 'loaded_level', 'cached_at', 'attachments_json',
    'auth_results', 'list_unsubscribe',
  };

  /// Тексты писем — в базу без оповещения открытых списков (1.5.6). Лента
  /// тел не показывает, а каждое изменение таблицы писем заставляло её
  /// перечитывать сотни строк: «Письма на телефоне» пишут тексты пачками
  /// каждые пару секунд — лента и открытие письма подтормаживали, процессор
  /// был занят. [rows]: id письма → колонка (как в SQL) → значение (дата —
  /// секунды Unix, как хранит drift).
  Future<void> storeBodiesQuietly(String accountId, Map<String, Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      rows.forEach((id, cols) {
        final sets = <String>[];
        final args = <Object?>[];
        cols.forEach((c, v) {
          if (!_quietColumns.contains(c)) return;
          sets.add('$c = ?');
          args.add(v);
        });
        if (sets.isEmpty) return;
        args
          ..add(id)
          ..add(accountId);
        b.customStatement('UPDATE emails SET ${sets.join(', ')} WHERE id = ? AND account_id = ?', args);
      });
    });
  }

  /// Поисковый индекс для пачки писем — одной транзакцией (раньше — по два
  /// запроса к базе на письмо).
  Future<void> indexEmailFtsBatch(
      String accountId, List<({String emailId, String subject, String fromText, String body})> items) async {
    if (items.isEmpty) return;
    await batch((b) {
      for (final i in items) {
        final rowId = ftsRowId(accountId, i.emailId);
        b.customStatement('DELETE FROM emails_fts WHERE rowid = ?', [rowId]);
        b.customStatement(
          'INSERT INTO emails_fts(rowid, email_id, account_id, subject, from_text, body, attachments_text) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [rowId, i.emailId, accountId, i.subject, i.fromText, i.body, ''],
        );
      }
    });
  }

  /// Письма беседы без тел (лента беседы под письмом показывает только
  /// шапки и превью): раньше тела всех писем цепочки копировались из базы в
  /// главный поток прямо во время перехода на экран письма.
  Future<List<Email>> getConversationLight({
    required String conversationId,
    required String accountId,
  }) async {
    final q = _EmailListQuery(emails)
      ..where((e) => e.conversationId.equals(conversationId) & e.accountId.equals(accountId))
      ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.asc)]);
    final rows = dedupCopies(await q.getLight(this));
    // Превью, которого нет в строке (IMAP), — из начала текста.
    final need = [for (final r in rows) if ((r.bodyPreview ?? '').trim().isEmpty) r.id];
    if (need.isEmpty) return rows;
    final p = await previewsFromBody(accountId, need);
    if (p.isEmpty) return rows;
    return [for (final r in rows) p[r.id] == null ? r : r.copyWith(bodyPreview: Value(p[r.id]))];
  }

  String _cleanupWhere(String accountId, int? olderThanEpochSec, int? largerThanBytes, List<Variable> vars) {
    final where = StringBuffer('account_id = ?');
    vars.add(Variable.withString(accountId));
    // Не трогаем несохранённые локальные (черновики/исходящие).
    where.write(" AND folder_id NOT IN ('drafts', 'outbox')");
    if (olderThanEpochSec != null) {
      where.write(' AND received_at < ?');
      vars.add(Variable.withInt(olderThanEpochSec));
    }
    if (largerThanBytes != null) {
      where.write(' AND $_sizeExpr >= ?');
      vars.add(Variable.withInt(largerThanBytes));
    }
    return where.toString();
  }

  /// Статистика кандидатов на очистку (старше даты и/или не меньше размера).
  Future<({int count, int bytes})> cleanupStats(String accountId,
      {int? olderThanEpochSec, int? largerThanBytes}) async {
    await _probeSqlCaps();
    final vars = <Variable>[];
    final where = _cleanupWhere(accountId, olderThanEpochSec, largerThanBytes, vars);
    final r = await customSelect(
      'SELECT COUNT(*) as c, COALESCE(SUM($_sizeExpr),0) as b FROM emails WHERE $where',
      variables: vars,
      readsFrom: {emails},
    ).getSingle();
    return (count: (r.data['c'] as int?) ?? 0, bytes: (r.data['b'] as int?) ?? 0);
  }

  /// ID и папка кандидатов на очистку (для удаления).
  Future<List<({String id, String folderId})>> cleanupCandidates(String accountId,
      {int? olderThanEpochSec, int? largerThanBytes, int limit = 5000}) async {
    await _probeSqlCaps();
    final vars = <Variable>[];
    final where = _cleanupWhere(accountId, olderThanEpochSec, largerThanBytes, vars);
    final rows = await customSelect(
      'SELECT id, folder_id FROM emails WHERE $where LIMIT $limit',
      variables: vars,
      readsFrom: {emails},
    ).get();
    return rows
        .map((r) => (id: r.data['id'] as String, folderId: r.data['folder_id'] as String))
        .toList();
  }

  // ════════════════════ СЧЁТЧИКИ НЕПРОЧИТАННЫХ ════════════════════
  //
  // Одно определение для значка на вкладке «Почта», строки «Вся почта» в
  // меню и счётчика в списке ящиков: непрочитанные письма, которые видны во
  // «Всей почте». Раньше значок брал число из строки аккаунта, которое
  // обновлялось только в конце синхронизации (прочитанное в приложении
  // не уменьшало его до следующей синхронизации), учитывал архив и
  // виртуальные папки Gmail («Вся почта», «Важные» — одно письмо считалось
  // два-три раза) и не совпадал ни с одним числом на экране.
  //
  // Не считаются: черновики, исходящие, корзина, спам, отправленные (типы
  // 1, 2, 3, 4, 6), папки, исключённые из «Всей почты», и повторы одного
  // письма под несколькими ярлыками (ключ — аккаунт + Message-ID).

  static const _unifiedUnreadWhere =
      'e.is_read = 0 AND e.is_draft = 0 '
      'AND NOT EXISTS (SELECT 1 FROM folders f WHERE f.account_id = e.account_id '
      'AND f.id = e.folder_id AND (f.show_in_unified = 0 OR f.is_synced = 0 OR f.type IN (1, 2, 3, 4, 6))) '
      "AND LOWER(e.folder_id) NOT IN ('trash', 'spam', 'junk', 'deleted', 'drafts', 'bin') "
      "AND (e.folder_name IS NULL OR e.folder_name NOT IN ('Junk Email', 'Спам', 'junk', "
      "'Нежелательная почта', 'Spam', 'Trash', 'Корзина', 'Deleted Items', 'Удалённые', "
      "'Удаленные', 'Bin', 'Drafts', 'Черновики', 'Junk'))";

  /// Ключ письма для подсчёта без повторов: Message-ID, если он есть, иначе id.
  static const _unreadKey =
      "COUNT(DISTINCT e.account_id || '|' || "
      "CASE WHEN INSTR(COALESCE(e.internet_message_id, ''), '@') > 0 "
      "THEN TRIM(e.internet_message_id) ELSE '#' || e.id END)";

  /// Непрочитанные «Всей почты» аккаунта (для строки аккаунта и сводки).
  Future<int> countUnread(String accountId) async {
    final result = await customSelect(
      'SELECT $_unreadKey AS c FROM emails e WHERE e.account_id = ? AND $_unifiedUnreadWhere',
      variables: [Variable.withString(accountId)],
      readsFrom: {emails, folders},
    ).getSingle();
    return result.data['c'] as int? ?? 0;
  }

  /// Живой счётчик непрочитанных «Всей почты» по набору аккаунтов — для
  /// значка на вкладке «Почта» и строк «Вся почта» / «Все аккаунты» в меню.
  /// Переизлучается при любом изменении писем или папок.
  Stream<int> watchUnifiedUnreadCount(List<String> accountIds) {
    if (accountIds.isEmpty) return Stream.value(0);
    final marks = List.filled(accountIds.length, '?').join(', ');
    return customSelect(
      'SELECT $_unreadKey AS c FROM emails e '
      'WHERE e.account_id IN ($marks) AND $_unifiedUnreadWhere',
      variables: [for (final id in accountIds) Variable.withString(id)],
      readsFrom: {emails, folders},
    ).watchSingle().map((r) => r.data['c'] as int? ?? 0);
  }

  /// Живые непрочитанные по папкам аккаунта (folder_id → число) — для дерева
  /// папок. Считается по базе, а не по числу с сервера: прочитанное в
  /// приложении сразу уменьшает счётчик, как и в списке писем.
  Stream<Map<String, int>> watchFolderUnread(String accountId) {
    return customSelect(
      'SELECT folder_id, COUNT(*) AS c FROM emails '
      'WHERE account_id = ? AND is_read = 0 GROUP BY folder_id',
      variables: [Variable.withString(accountId)],
      readsFrom: {emails},
    ).watch().map((rows) => {
          for (final r in rows) r.data['folder_id'] as String: r.data['c'] as int? ?? 0,
        });
  }

  /// Суммарный размер payload'ов в очереди (байты). Вложения хранятся в
  /// очереди как base64 внутри `payloadJson`, поэтому при длительном офлайне
  /// база может заметно вырасти — этот размер контролируется перед постановкой
  /// нового письма.
  Future<int> queuePayloadBytes() async {
    final rows = await (select(syncQueue)).get();
    var total = 0;
    for (final r in rows) {
      total += r.payloadJson.length;
    }
    return total;
  }

  /// Число операций, ожидающих отправки (офлайн-очередь). Реактивно — чтобы
  /// индикатор в шапке обновлялся сам по мере обработки очереди.
  Stream<int> watchQueueCount() {
    final q = selectOnly(syncQueue)..addColumns([syncQueue.id.count()]);
    return q.map((row) => row.read(syncQueue.id.count()) ?? 0).watchSingle();
  }

  /// Письма, по которым наступило время проверить ответ (follow-up).
  ///
  /// Нагрузка минимальна: строк с `follow_up_at` единицы (флаг ставится
  /// пользователем вручную), и по этому полю есть частичный индекс
  /// `idx_emails_followup`.
  Future<List<Email>> dueFollowUps(DateTime now, {int limit = 50}) {
    return (select(emails)
          ..where((e) => e.followUpAt.isNotNull())
          ..where((e) => e.followUpAt.isSmallerOrEqualValue(now))
          ..limit(limit))
        .get();
  }

  /// Пришёл ли ответ на наше письмо: в той же цепочке есть более позднее
  /// сообщение НЕ от нас. Один запрос по индексу `idx_emails_conversation`.
  ///
  /// Если у письма нет conversationId (сервер не отдал), считаем, что ответа
  /// нет — лучше лишний раз напомнить, чем молча пропустить.
  Future<bool> hasReplyInConversation({
    required String accountId,
    required String? conversationId,
    required DateTime after,
    required String myEmail,
  }) async {
    if (conversationId == null || conversationId.isEmpty) return false;
    final row = await (select(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.conversationId.equals(conversationId))
          ..where((e) => e.receivedAt.isBiggerThanValue(after))
          ..where((e) => e.fromEmail.lower().isIn(_mine(myEmail)).not())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  // ── «На контроле» ──

  /// Письма «На контроле» (активные и исполненные), сначала старые.
  Future<List<Email>> controlledEmails({List<String>? accountIds, bool activeOnly = false}) {
    final q = select(emails)
      ..where((e) => activeOnly
          ? e.controlState.isIn(const [1, 2])
          : e.controlState.isBiggerThanValue(0));
    if (accountIds != null) q.where((e) => e.accountId.isIn(accountIds));
    q.orderBy([(e) => OrderingTerm(expression: e.receivedAt)]);
    return q.get();
  }

  // ── «Посмотреть позже» ──

  /// Отложенные и вернувшиеся письма в порядке списка «Позже».
  Future<List<Email>> laterEmails({List<String>? accountIds}) {
    final q = select(emails)..where((e) => e.laterState.isBiggerThanValue(0));
    if (accountIds != null) q.where((e) => e.accountId.isIn(accountIds));
    q.orderBy([
      (e) => OrderingTerm(expression: e.laterState, mode: OrderingMode.desc),
      (e) => OrderingTerm(expression: e.remindAt, nulls: NullsOrder.last),
      (e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc),
    ]);
    return q.get();
  }

  /// Отложенные письма, срок которых наступил.
  Future<List<Email>> dueLaterEmails(DateTime now) => (select(emails)
        ..where((e) => e.laterState.equals(1))
        ..where((e) => e.remindAt.isNotNull())
        ..where((e) => e.remindAt.isSmallerOrEqualValue(now)))
      .get();

  /// Отложить (state 1, [remindAt] — срок или null «без даты»), вернуть
  /// (state 2) или снять (state 0).
  Future<void> setLaterState(String emailId, String accountId, int state, {DateTime? remindAt}) async {
    await (update(emails)..where((e) => e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(EmailsCompanion(laterState: Value(state), remindAt: Value(remindAt)));
  }

  /// Отметка «На контроле». Снятие (0) убирает и срок, и список ответивших.
  Future<void> setControlState(String emailId, String accountId, int state, {DateTime? deadline}) async {
    await (update(emails)..where((e) => e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(EmailsCompanion(
          controlState: Value(state),
          followUpAt: state == 0 || state == 3 ? const Value(null) : (deadline == null ? const Value.absent() : Value(deadline)),
          controlReplied: state == 0 ? const Value(null) : const Value.absent(),
        ));
  }

  /// Кто из «Кому» уже ответил (адреса через запятую).
  Future<void> setControlReplied(String emailId, String accountId, String? replied) async {
    await (update(emails)..where((e) => e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(EmailsCompanion(controlReplied: Value(replied)));
  }

  /// Адреса авторов ответов на письмо (кроме меня): по беседе и по
  /// заголовкам References.
  Future<Set<String>> repliersTo({
    required String accountId,
    required String? conversationId,
    required String? messageId,
    required DateTime after,
    required String myEmail,
  }) async {
    final me = _mine(myEmail);
    final out = <String>{};
    if (conversationId != null && conversationId.isNotEmpty) {
      final rows = await (selectOnly(emails, distinct: true)
            ..addColumns([emails.fromEmail])
            ..where(emails.accountId.equals(accountId) &
                emails.conversationId.equals(conversationId) &
                emails.receivedAt.isBiggerThanValue(after) &
                emails.fromEmail.lower().isIn(me).not()))
          .map((r) => r.read(emails.fromEmail))
          .get();
      out.addAll(rows.whereType<String>().map((e) => e.toLowerCase()));
    }
    final mid = (messageId ?? '').trim().replaceAll('<', '').replaceAll('>', '');
    if (mid.contains('@')) {
      final rows = await (selectOnly(emails, distinct: true)
            ..addColumns([emails.fromEmail])
            ..where(emails.accountId.equals(accountId) &
                emails.receivedAt.isBiggerThanValue(after) &
                emails.referencesStr.like('%$mid%') &
                emails.fromEmail.lower().isIn(me).not()))
          .map((r) => r.read(emails.fromEmail))
          .get();
      out.addAll(rows.whereType<String>().map((e) => e.toLowerCase()));
    }
    return out;
  }

  /// Свои адреса: [myEmail] — один адрес или несколько через запятую.
  static List<String> _mine(String myEmail) =>
      {for (final p in myEmail.split(',')) if (p.trim().isNotEmpty) p.trim().toLowerCase()}.toList();

  /// Ответил ли я в беседе после письма (для «должен ответить»).
  Future<bool> hasMyReplyInConversation({
    required String accountId,
    required String? conversationId,
    required DateTime after,
    required String myEmail,
  }) async {
    if (conversationId == null || conversationId.isEmpty || myEmail.isEmpty) return false;
    final row = await (select(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.conversationId.equals(conversationId))
          ..where((e) => e.receivedAt.isBiggerThanValue(after))
          ..where((e) => e.fromEmail.lower().isIn(_mine(myEmail)))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Письма-ответы по заголовкам: References/In-Reply-To содержат
  /// Message-ID письма (когда сервер не отдал conversationId). [fromMe] —
  /// true: ответы от меня, false: от других.
  Future<bool> hasReplyByMessageId({
    required String accountId,
    required String messageId,
    required DateTime after,
    required String myEmail,
    required bool fromMe,
  }) async {
    final mid = messageId.trim().replaceAll('<', '').replaceAll('>', '');
    if (!mid.contains('@')) return false;
    final me = _mine(myEmail);
    final row = await (select(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.receivedAt.isBiggerThanValue(after))
          ..where((e) => e.referencesStr.like('%$mid%'))
          ..where((e) => fromMe ? e.fromEmail.lower().isIn(me) : e.fromEmail.lower().isIn(me).not())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Снять пометку follow-up (ответ пришёл либо пользователь отменил).
  Future<void> clearFollowUp(String emailId, {String? accountId}) async {
    await (update(emails)
          ..where((e) => accountId == null
              ? e.id.equals(emailId)
              : e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(const EmailsCompanion(followUpAt: Value(null)));
  }

  /// Поставить напоминание «нет ответа» на письмо.
  Future<void> setFollowUp(String emailId, DateTime when, {String? accountId}) async {
    await (update(emails)
          ..where((e) => accountId == null
              ? e.id.equals(emailId)
              : e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(EmailsCompanion(followUpAt: Value(when)));
  }

  /// Подсчитать письма с флагом (для блока «Требуют внимания» на дашборде).
  Future<int> countFlagged(String accountId) async {
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM emails WHERE account_id = ? AND is_flagged = 1',
      variables: [Variable.withString(accountId)],
    ).getSingle();
    return result.data['c'] as int? ?? 0;
  }

  /// Подсчитать письма с наступившим напоминанием (снуз): remind_at <= now.
  Future<int> countRemindersDue(String accountId) async {
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM emails WHERE account_id = ? AND remind_at IS NOT NULL AND remind_at <= ?',
      variables: [
        Variable.withString(accountId),
        Variable.withDateTime(DateTime.now()),
      ],
    ).getSingle();
    return result.data['c'] as int? ?? 0;
  }

  /// Подсчитать общее количество писем в папке
  /// Id папки заданного типа (FolderType.index) в КОНКРЕТНОМ аккаунте.
  /// Не через foldersProvider: тот держит папки только активного аккаунта,
  /// а в сводной ленте письма бывают из любого ящика.
  Future<String?> folderIdOfType(String accountId, int type) async {
    final rows = await (select(folders)
          ..where((f) => f.accountId.equals(accountId) & f.type.equals(type))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first.id;
  }

  Future<int> countEmailsInFolder(String accountId, String folderId) async {
    final result = await customSelect(
      'SELECT COUNT(*) as c FROM emails WHERE account_id = ? AND folder_id = ?',
      variables: [Variable.withString(accountId), Variable.withString(folderId)],
    ).getSingle();
    return result.data['c'] as int? ?? 0;
  }

  /// Полнотекстовый поиск по письмам
  Future<List<Email>> searchEmails({
    required String accountId,
    required String query,
    int limit = 50,
  }) async {
    // SQLite LIKE и lower() не различают регистр только у латиницы:
    // «отчёт» не находил «Отчёт». Ищем варианты написания запроса: как
    // введён, строчными, с заглавной и прописными.
    final q = query.trim();
    final variants = <String>{
      q,
      q.toLowerCase(),
      q.toUpperCase(),
      if (q.isNotEmpty) q[0].toUpperCase() + q.substring(1).toLowerCase(),
    }.map((v) => '%$v%').toList();
    return (select(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) {
            Expression<bool> any(GeneratedColumn<String> c) =>
                variants.map((p) => c.like(p)).reduce((a, b) => a | b);
            return any(e.subject) | any(e.fromName) | any(e.fromEmail) | any(e.bodyPreview);
          })
          ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }

  // ════════════════════════ АВТООЧИСТКА ════════════════════════

  /// Удалить старые кешированные письма (> syncDays)
  Future<int> cleanupOldEmails(String accountId, int keepDays) async {
    // 0 и меньше — «хранить всё» (так же понимает синхронизация). Раньше
    // срез становился «сейчас», и автоочистка удаляла ВСЮ почту аккаунта,
    // кроме помеченной флажком.
    if (keepDays <= 0) return 0;
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    return (delete(emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.receivedAt.isSmallerThanValue(cutoff))
          ..where((e) => e.isFlagged.equals(false))
          ..where((e) => e.isLocallyModified.equals(false))
          // Черновики и неотправленные — не кэш: раньше автоочистка удаляла
          // старые черновики приложения вместе с письмами.
          ..where((e) => e.isDraft.equals(false))
          ..where((e) => e.folderId.isNotIn(const ['drafts', 'outbox'])))
        .go();
  }

  /// Удалить старые аудит-логи (> 90 дней)
  Future<int> cleanupAuditLog() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    return (delete(auditLog)
          ..where((a) => a.timestamp.isSmallerThanValue(cutoff)))
        .go();
  }

  /// Вакуум БД (сжатие после удалений)
  Future<void> vacuum() async {
    await customStatement('VACUUM');
  }

  /// Доля свободных страниц файла базы (0…1): после удалений SQLite не
  /// уменьшает файл, свободные страницы переиспользуются. VACUUM нужен, только
  /// когда их много — он переписывает весь файл (с текстами писем — десятки и
  /// сотни мегабайт) и стоит заметного заряда.
  Future<({double ratio, int freeBytes})> freeSpace() async {
    final free = (await customSelect('PRAGMA freelist_count').getSingle()).data.values.first as int? ?? 0;
    final pages = (await customSelect('PRAGMA page_count').getSingle()).data.values.first as int? ?? 0;
    final size = (await customSelect('PRAGMA page_size').getSingle()).data.values.first as int? ?? 4096;
    return (ratio: pages == 0 ? 0.0 : free / pages, freeBytes: free * size);
  }

  /// Статистика для планировщика запросов SQLite (дёшево, раз в сутки).
  Future<void> optimize() async {
    await customStatement('PRAGMA optimize');
  }

  // ───────────── Тексты писем — в конец строки таблицы (1.5.8) ─────────────
  //
  // SQLite хранит строку таблицы подряд, столбец за столбцом; длинный текст
  // письма не помещается в страницу и уходит в цепочку страниц переполнения.
  // Чтобы прочитать столбец ПОСЛЕ текста (дата, «прочитано», флажок, папка
  // ящика…), SQLite проходит всю цепочку — а SQLCipher ещё и расшифровывает
  // каждую страницу. У писем тексты стояли в середине строки, и с 1.5.5
  // (тексты хранятся на телефоне) любой запрос ленты и счётчиков читал
  // тексты писем целиком: на проверке — в 10 раз медленнее (аудит
  // 11.10.2026). Разовая перестановка: тексты — последними столбцами.
  // drift обращается к столбцам по именам, порядок в файле ему не важен;
  // новые столбцы (ALTER TABLE) добавляются в конец — это не мешает.

  static const _bodyColumns = ['body_plain', 'body_html'];

  /// Тексты писем уже в конце строки.
  Future<bool> bodiesAtEnd() async {
    final cols = await customSelect('PRAGMA table_info(emails)').get();
    final names = [for (final r in cols) r.data['name'] as String];
    if (names.isEmpty) return true;
    final tail = names.sublist(names.length - _bodyColumns.length);
    return _bodyColumns.every(tail.contains);
  }

  /// Разделить список определений CREATE TABLE по запятым верхнего уровня
  /// (запятые в скобках CHECK и в кавычках не делят).
  static List<String> splitColumnDefs(String inner) {
    final out = <String>[];
    var depth = 0;
    String? quote;
    var start = 0;
    for (var i = 0; i < inner.length; i++) {
      final ch = inner[i];
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        quote = ch;
      } else if (ch == '[') {
        quote = ']';
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      } else if (ch == ',' && depth == 0) {
        out.add(inner.substring(start, i).trim());
        start = i + 1;
      }
    }
    final last = inner.substring(start).trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  /// Имя столбца в начале определения (без кавычек); null — это ограничение
  /// таблицы (PRIMARY KEY, UNIQUE, CHECK, FOREIGN KEY, CONSTRAINT).
  static String? columnNameOf(String def) {
    final up = def.toUpperCase();
    for (final k in const ['PRIMARY KEY', 'UNIQUE', 'CHECK', 'FOREIGN KEY', 'CONSTRAINT']) {
      if (up.startsWith(k)) return null;
    }
    final m = RegExp(r'^\s*(?:"([^"]+)"|`([^`]+)`|\[([^\]]+)\]|([A-Za-z_][A-Za-z0-9_]*))').firstMatch(def);
    if (m == null) return null;
    return m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4);
  }

  /// Новый CREATE TABLE с текстами в конце; null — разобрать не удалось.
  static String? reorderedCreateSql(String createSql, String newName) {
    final open = createSql.indexOf('(');
    final close = createSql.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final defs = splitColumnDefs(createSql.substring(open + 1, close));
    final columns = <String>[];
    final bodies = <String>[];
    final constraints = <String>[];
    for (final d in defs) {
      final n = columnNameOf(d);
      if (n == null) {
        constraints.add(d);
      } else if (_bodyColumns.contains(n.toLowerCase())) {
        bodies.add(d);
      } else {
        columns.add(d);
      }
    }
    if (bodies.length != _bodyColumns.length || columns.isEmpty) return null;
    return 'CREATE TABLE "$newName" (${[...columns, ...bodies, ...constraints].join(', ')})';
  }

  /// Переставить столбцы (один раз; данные копируются в одной транзакции —
  /// при любой ошибке таблица остаётся прежней). Возвращает true, если
  /// перестановка выполнена сейчас.
  Future<bool> moveBodiesToEnd() async {
    if (await bodiesAtEnd()) return false;
    final create = (await customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'emails'")
        .getSingle())
        .data['sql'] as String?;
    if (create == null) return false;
    final newSql = reorderedCreateSql(create, 'emails_reorder');
    if (newSql == null) return false;
    final names = [
      for (final r in await customSelect('PRAGMA table_info(emails)').get()) r.data['name'] as String,
    ];
    final ordered = [
      ...names.where((n) => !_bodyColumns.contains(n)),
      ..._bodyColumns.where(names.contains),
    ];
    final cols = ordered.map((c) => '"$c"').join(', ');
    final indexes = [
      for (final r in await customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'emails' AND sql IS NOT NULL")
          .get())
        r.data['sql'] as String,
    ];
    await customStatement('PRAGMA foreign_keys = OFF');
    try {
      await transaction(() async {
        await customStatement('DROP TABLE IF EXISTS emails_reorder');
        await customStatement(newSql);
        await customStatement('INSERT INTO emails_reorder ($cols) SELECT $cols FROM emails');
        await customStatement('DROP TABLE emails');
        await customStatement('ALTER TABLE emails_reorder RENAME TO emails');
        for (final i in indexes) {
          await customStatement(i);
        }
      });
    } finally {
      await customStatement('PRAGMA foreign_keys = ON');
    }
    notifyUpdates({TableUpdate.onTable(emails)});
    return true;
  }
}

/// Соединений только для чтения (drift readPool). 0 — как до 1.5.9.
const int _dbReadPool = 1;

/// Открытие соединения с БД
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // На компьютере база — в AppData (Application Support), а не в «Документах»:
    // «Документы» часто синхронизируются OneDrive, и облачный клиент
    // блокирует/копирует файл SQLite и его WAL прямо во время записи —
    // отсюда ошибки «database is locked» и битые копии. На телефоне
    // getApplicationDocumentsDirectory — приватная папка приложения.
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final dbFolder = isDesktop
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    await dbFolder.create(recursive: true);
    final file = File(p.join(dbFolder.path, 'ogneliss.db'));

    // ── Шифрование локальной БД (SQLite3 Multiple Ciphers) ──
    // Библиотеку с шифрованием подключает build-хук пакета sqlite3
    // (pubspec.yaml → hooks: user_defines: sqlite3: source: sqlite3mc) на
    // всех нативных платформах, включая Windows. Раньше ключ отправлялся в
    // обычный SQLite, который PRAGMA key молча игнорирует, — база лежала
    // открытым текстом.
    //
    // Ключ не прочитался (хранилище ключей не готово: старт устройства до
    // разблокировки, фоновая задача, сбой Keystore) — базу НЕ трогаем и
    // открытие прерываем. Раньше рабочая база в этом случае откладывалась в
    // сторону и создавалась пустая: пропадали очередь неотправленных писем,
    // локальные черновики и задачи. Теперь фоновая задача завершится ошибкой
    // и повторится позже, а приложение покажет причину.
    // В сторону база уходит только если ключ прочитан, но не подходит
    // (SQLITE_NOTADB) — см. DbEncryption.prepare.
    String? key;
    if (!kIsWeb) {
      try {
        key = await DbEncryption.getOrCreateKey();
      } catch (e) {
        throw DbKeyUnavailableException(e);
      }
      key = DbEncryption.prepare(file, key);
      DbEncryption.cleanupMovedAside(file);
    }
    final dbKey = key;

    return NativeDatabase.createInBackground(
      file,
      logStatements: false,
      // Отдельное соединение для чтения (1.5.9). Раньше все запросы шли через
      // один изолят по очереди: открытие письма (строка письма, папки) ждало,
      // пока синхронизация допишет свою транзакцию. База в режиме WAL
      // (beforeOpen), поэтому чтение и запись идут параллельно; setup с ключом
      // выполняется и для соединения чтения. Откатить — поставить 0.
      readPool: _dbReadPool,
      setup: (rawDb) {
        if (dbKey != null && dbKey.isNotEmpty) {
          rawDb.execute("PRAGMA key = '${dbKey.replaceAll("'", "''")}';");
        }
        // Ждать до 5 с, если базу держит другое подключение (фоновая
        // синхронизация), вместо мгновенной ошибки «database is locked».
        rawDb.execute('PRAGMA busy_timeout = 5000;');
      },
    );
  });
}

/// Управление ключом шифрования БД.
/// Хранилище ключей не отдало ключ шифрования базы. Повторить позже —
/// база цела.
class DbKeyUnavailableException implements Exception {
  final Object cause;
  const DbKeyUnavailableException(this.cause);
  @override
  String toString() =>
      'Защищённое хранилище ключей устройства сейчас недоступно, поэтому '
      'зашифрованную почту открыть нельзя. Данные не потеряны. Разблокируйте '
      'устройство и перезапустите приложение. ($cause)';
}

class DbEncryption {
  /// Подготовить файл БД к открытию с ключом [key]. Возвращает ключ, с
  /// которым открывать, или null — открывать без шифрования.
  ///
  ///  · библиотека без шифрования (сборка без sqlite3mc) → null;
  ///  · база ещё открытым текстом (обновление со старой версии) → шифруем
  ///    её на месте (PRAGMA rekey); копия на время операции, при сбое —
  ///    откат, база остаётся рабочей, попытка повторится при запуске;
  ///  · зашифрованная база не открывается этим ключом (ключ утерян, например
  ///    после переустановки ОС) → файл откладывается в сторону, создаётся
  ///    новый: почта, календарь и контакты заново придут с сервера.
  static String? prepare(File file, String key) {
    // Базу может одновременно открывать фоновый процесс синхронизации
    // (WorkManager): подготовку выполняем под файловой блокировкой, чтобы
    // перевод в зашифрованный вид не шёл в двух местах сразу.
    RandomAccessFile? lock;
    try {
      lock = File('${file.path}.lock').openSync(mode: FileMode.write);
      lock.lockSync(FileLock.blockingExclusive);
    } catch (_) {
      lock = null;
    }
    try {
      return _prepareLocked(file, key);
    } finally {
      try {
        lock?.unlockSync();
        lock?.closeSync();
      } catch (_) {}
    }
  }

  static String? _prepareLocked(File file, String key) {
    final k = key.replaceAll("'", "''");
    // Есть ли шифрование в загруженной библиотеке.
    try {
      final probe = s3.sqlite3.openInMemory();
      try {
        if (probe.select('PRAGMA cipher').isEmpty) return null;
      } finally {
        probe.close();
      }
    } catch (_) {
      return null;
    }
    if (!file.existsSync()) return key;

    if (file.lengthSync() == 0) return key; // пустой файл — создастся заново
    if (_isPlaintext(file)) {
      final backup = File('${file.path}.plain-backup');
      try {
        // Перенести журнал WAL в основной файл и выключить WAL: шифровать
        // базу в режиме WAL библиотека не умеет.
        final db = s3.sqlite3.open(file.path);
        try {
          db.execute('PRAGMA busy_timeout = 5000');
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          final mode = db.select('PRAGMA journal_mode = DELETE');
          // База занята другим соединением — переход из WAL не выполнен;
          // шифруем при следующем запуске.
          if (mode.isEmpty || '${mode.first.values.first}'.toLowerCase() != 'delete') {
            return null;
          }
        } finally {
          db.close();
        }
        file.copySync(backup.path);
        final db2 = s3.sqlite3.open(file.path);
        try {
          db2.execute("PRAGMA rekey = '$k'");
        } finally {
          db2.close();
        }
        // Контроль: база открывается с ключом новым соединением.
        final db3 = s3.sqlite3.open(file.path);
        try {
          db3.execute("PRAGMA key = '$k'");
          db3.select('SELECT count(*) FROM sqlite_master');
        } finally {
          db3.close();
        }
        backup.deleteSync();
        return key;
      } catch (e) {
        // Откат: оставляем базу открытым текстом, приложение работает.
        try {
          if (backup.existsSync()) {
            backup.copySync(file.path);
            backup.deleteSync(); // открытая копия не должна оставаться на диске
          }
        } catch (_) {}
        return null;
      }
    }

    // Зашифрована: проверяем, что ключ подходит.
    return _verifyOrMoveAside(file, key, k);
  }

  static bool _isPlaintext(File file) {
    try {
      final raf = file.openSync();
      try {
        return String.fromCharCodes(raf.readSync(15)) == 'SQLite format 3';
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return true; // не смогли прочитать — не трогаем
    }
  }

  /// Отложенные копии нечитаемой базы хранятся неделю — на случай, если
  /// ключ найдётся, — затем удаляются (раньше копились навсегда).
  static void cleanupMovedAside(File file, {Duration keep = const Duration(days: 7)}) {
    try {
      final dir = file.parent;
      final prefix = '${p.basename(file.path)}.unreadable-';
      final cutoff = DateTime.now().subtract(keep);
      for (final f in dir.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (!name.startsWith(prefix)) continue;
        final stamp = int.tryParse(name.substring(prefix.length).split('-').first);
        if (stamp != null && DateTime.fromMillisecondsSinceEpoch(stamp).isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  static void _moveAside(File file) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      try {
        if (f.existsSync()) f.renameSync('${file.path}.unreadable-$stamp$suffix');
      } catch (_) {}
    }
  }

  static String _verifyOrMoveAside(File file, String key, String k) {
    try {
      final db = s3.sqlite3.open(file.path);
      try {
        db.execute("PRAGMA key = '$k'");
        db.execute('PRAGMA busy_timeout = 5000');
        db.select('SELECT count(*) FROM sqlite_master');
      } finally {
        db.close();
      }
      return key;
    } on s3.SqliteException catch (e) {
      // В сторону — ТОЛЬКО если ключ действительно не подходит
      // (SQLITE_NOTADB = 26). «Занято» или сбой ввода-вывода — не повод
      // откладывать рабочую базу.
      if (e.resultCode == 26) _moveAside(file);
      return key;
    } catch (_) {
      return key;
    }
  }

  static const _keyName = 'db_encryption_key_v1';
  static final _storage = SecureStorageService();

  /// Получить существующий ключ или создать новый (256 бит, hex).
  static Future<String> getOrCreateKey() async {
    // Хранилище ключей при старте устройства иногда отвечает ошибкой —
    // несколько попыток, прежде чем считать ключ недоступным.
    String? existing;
    for (var attempt = 0;; attempt++) {
      try {
        existing = await _storage.read(_keyName);
        break;
      } catch (_) {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (existing != null && existing.isNotEmpty) return existing;
    // Генерируем 32 случайных байта -> hex (64 символа)
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(_keyName, key);
    return key;
  }
}

/// Запрос списка писем: одни и те же условия, порядок и окно — для полного
/// результата (`full`, с текстами) и для живого списка (`watchLight`).
///
/// Живой список раньше выбирал строки целиком — вместе с HTML и текстом
/// писем, — и при КАЖДОМ изменении таблицы писем (синхронизация, отметка
/// «прочитано», загрузка текста) окно в сотни писем с телами по десяткам
/// килобайт читалось из базы, копировалось в основной поток и разбиралось
/// там (декодирование текста), хотя списку тела не нужны. Отсюда — подвисания
/// ленты, особенно теперь, когда письма хранятся целиком («Письма на
/// телефоне»). `watchLight` выбирает все колонки, кроме тел.
class _EmailListQuery {
  final $EmailsTable t;
  _EmailListQuery(this.t);

  Expression<bool>? _where;
  List<OrderingTerm> _order = const [];
  int? _limit;
  int? _offset;

  void where(Expression<bool> Function($EmailsTable e) f) {
    final p = f(t);
    _where = _where == null ? p : _where! & p;
  }

  void orderBy(List<OrderClauseGenerator<$EmailsTable>> terms) {
    _order = [for (final g in terms) g(t)];
  }

  void limit(int limit, {int? offset}) {
    _limit = limit;
    _offset = offset;
  }

  SimpleSelectStatement<$EmailsTable, Email> full(AppDatabase db) {
    final q = db.select(t);
    final w = _where;
    if (w != null) q.where((_) => w);
    if (_order.isNotEmpty) q.orderBy([for (final o in _order) (_) => o]);
    if (_limit != null) q.limit(_limit!, offset: _offset);
    return q;
  }

  /// Колонки без тел письма (HTML и текст).
  List<GeneratedColumn> get _lightColumns => [
        for (final c in t.$columns)
          if (c.$name != t.bodyHtml.$name && c.$name != t.bodyPlain.$name) c,
      ];

  /// Выборка всех колонок, кроме тел: строки [Email] с bodyHtml и
  /// bodyPlain = null.
  Selectable<Email> light(AppDatabase db) {
    final q = db.selectOnly(t)..addColumns(_lightColumns);
    final w = _where;
    if (w != null) q.where(w);
    if (_order.isNotEmpty) q.orderBy(_order);
    if (_limit != null) q.limit(_limit!, offset: _offset);
    // Колонки таблицы в выборке названы «emails.<колонка>» — как при
    // join; map() с тем же префиксом собирает строку, тела остаются null.
    return q.map((r) => t.map(r.rawData.data, tablePrefix: t.aliasedName));
  }

  /// То же, что [watchLight], одним запросом.
  Future<List<Email>> getLight(AppDatabase db) => light(db).get();

  Stream<List<Email>> watchLight(AppDatabase db) => light(db).watch();
}

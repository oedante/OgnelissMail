// lib/data/models/account_model.dart

// outlook — в КОНЦЕ: тип хранится в базе по номеру.
enum AccountType { exchange, activesync, corporate, google, yandex, yahoo, mailru, imap, outlook }
enum ExchangeAuthMethod { ntlm, basic, bearer }
enum EncryptionType { none, ssl, starttls }
/// Порядок не менять: в базе хранится индекс. [scheduled] — «По расписанию»
/// (push в рабочие часы, иначе по интервалу; см. sync_schedule.dart).
enum SyncInterval { push, minutes5, minutes15, minutes30, hour1, manual, scheduled }

class AccountModel {
  final String id;
  final AccountType type;
  final String email;
  final String displayName;
  final String username;
  final String? domain;
  final String? exchangeServer;
  final ExchangeAuthMethod? exchangeAuthMethod;
  final String? ewsUrl;
  final String? imapServer;
  final int? imapPort;
  final EncryptionType? imapEncryption;
  final String? smtpServer;
  final int? smtpPort;
  final EncryptionType? smtpEncryption;
  final SyncInterval syncInterval;
  final bool syncOnlyWifi;
  final int syncDays;
  final bool isActive;

  /// Момент, когда сервер отверг учётные данные после успешного подключения
  /// (смена пароля, блокировка, отзыв токена). null — проблем нет.
  final DateTime? authFailedAt;

  /// Адрес общего или делегированного ящика. Если задан, запросы адресуются
  /// не своему ящику, а этому — с учётными данными основного аккаунта.
  final String? sharedMailboxEmail;

  /// Аккаунт, чьи учётные данные используются для доступа к общему ящику.
  final String? parentAccountId;

  /// Выбор пользователя «рабочий / личный»: 'work', 'personal' или null —
  /// определить по типу подключения (см. [isWork]).
  final String? accountKind;

  /// Рабочий ящик: предупреждения о внешних отправителях, политики. Личный
  /// (Gmail, Яндекс, Mail.ru…) — без них: «внешний» там каждый второй.
  bool get isWork => accountKind == null ? isMsExchange : accountKind == 'work';

  /// Это общий (делегированный) ящик, а не собственный.
  bool get isSharedMailbox =>
      sharedMailboxEmail != null && sharedMailboxEmail!.isNotEmpty;

  /// Архив Exchange (online archive) ящика [parentAccountId] — отдельным
  /// ящиком (1.6.49): id «archive_<id основного>», запросы по EWS к корню
  /// архива с учётными данными основного; только почта.
  bool get isOnlineArchive => id.startsWith('archive_');
  final bool isPrimary;
  final int colorValue;
  final String? avatarUrl;
  final String? signatureId;
  final String? certificatePath;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiry;
  final DateTime createdAt;
  final DateTime? lastSyncAt;
  final int unreadCount;

  const AccountModel({
    required this.id,
    required this.type,
    required this.email,
    required this.displayName,
    required this.username,
    this.domain,
    this.exchangeServer,
    this.exchangeAuthMethod,
    this.ewsUrl,
    this.imapServer,
    this.imapPort,
    this.imapEncryption,
    this.smtpServer,
    this.smtpPort,
    this.smtpEncryption,
    this.syncInterval = SyncInterval.push,
    this.syncOnlyWifi = false,
    this.syncDays = 365,
    this.isActive = true,
    this.authFailedAt,
    this.sharedMailboxEmail,
    this.parentAccountId,
    this.accountKind,
    this.isPrimary = false,
    this.colorValue = 0xFF1D4F91,
    this.avatarUrl,
    this.signatureId,
    this.certificatePath,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiry,
    required this.createdAt,
    this.lastSyncAt,
    this.unreadCount = 0,
  });

  bool get isExchange => type == AccountType.exchange;
  bool get isActiveSync => type == AccountType.activesync;
  /// Любой ящик Microsoft Exchange — по EWS, ActiveSync или корпоративный.
  /// Для функций, которые есть у Exchange независимо от протокола
  /// (адресная книга, автоответ, категории, режим совместимости со шлюзом).
  bool get isMsExchange => isExchange || isActiveSync || isCorporate;
  bool get isCorporate => type == AccountType.corporate;
  /// Использует ActiveSync-транспорт (EAS) как ОСНОВНОЙ: тип activesync, либо
  /// corporate без EWS URL.
  ///
  /// Важно: тип `activesync` остаётся EAS даже когда у аккаунта заполнен
  /// `ewsUrl` — в гибридном режиме этот адрес используется только для
  /// дополнительных операций, а почта/календарь/контакты идут по EAS
  /// (Direct Push, экономия батареи).
  bool get usesEas => type == AccountType.activesync || (type == AccountType.corporate && (ewsUrl == null || ewsUrl!.isEmpty));
  /// Использует EWS как ОСНОВНОЙ транспорт: exchange, либо corporate с EWS URL.
  bool get usesEws => type == AccountType.exchange || (type == AccountType.corporate && ewsUrl != null && ewsUrl!.isNotEmpty);

  /// Доступны ли операции через EWS — как основным транспортом, так и
  /// «спутником» при работе по EAS (гибридный режим).
  ///
  /// В EAS нет автоответов (OOF), занятости коллег, категорий Outlook,
  /// серверных правил и отзыва письма. Если Autodiscover отдал адрес EWS,
  /// эти функции работают и для EAS-аккаунта.
  bool get hasEwsExtras => usesEws || (ewsUrl != null && ewsUrl!.isNotEmpty);
  bool get isOAuth => type == AccountType.google || type == AccountType.yandex || type == AccountType.yahoo || type == AccountType.mailru || type == AccountType.outlook;
  /// Exchange Online (Microsoft 365) по OAuth: ActiveSync и EWS с токеном
  /// вместо пароля (1.6.2).
  bool get isExchangeOnlineOAuth => isMsExchange && exchangeAuthMethod == ExchangeAuthMethod.bearer;
  /// Ящик входит по токенам OAuth (их нужно обновлять).
  bool get usesOAuthTokens => isOAuth || isExchangeOnlineOAuth;
  bool get isImap => type == AccountType.imap;
  bool get needsTokenRefresh => tokenExpiry != null && DateTime.now().isAfter(tokenExpiry!.subtract(const Duration(minutes: 5)));

  AccountModel copyWith({
    String? id, AccountType? type, String? email, String? displayName, String? username,
    String? domain, String? exchangeServer, ExchangeAuthMethod? exchangeAuthMethod,
    String? ewsUrl, String? imapServer, int? imapPort, EncryptionType? imapEncryption,
    String? smtpServer, int? smtpPort, EncryptionType? smtpEncryption,
    SyncInterval? syncInterval, bool? syncOnlyWifi, int? syncDays,
    bool? isActive, bool? isPrimary, int? colorValue, String? avatarUrl,
    String? signatureId, String? certificatePath,
    String? accessToken, String? refreshToken, DateTime? tokenExpiry,
    DateTime? createdAt, DateTime? lastSyncAt, int? unreadCount,
    DateTime? authFailedAt, String? sharedMailboxEmail, String? parentAccountId,
    String? accountKind, bool clearAccountKind = false,
  }) {
    return AccountModel(
      id: id ?? this.id, type: type ?? this.type, email: email ?? this.email,
      displayName: displayName ?? this.displayName, username: username ?? this.username,
      domain: domain ?? this.domain, exchangeServer: exchangeServer ?? this.exchangeServer,
      exchangeAuthMethod: exchangeAuthMethod ?? this.exchangeAuthMethod,
      ewsUrl: ewsUrl ?? this.ewsUrl, imapServer: imapServer ?? this.imapServer,
      imapPort: imapPort ?? this.imapPort, imapEncryption: imapEncryption ?? this.imapEncryption,
      smtpServer: smtpServer ?? this.smtpServer, smtpPort: smtpPort ?? this.smtpPort,
      smtpEncryption: smtpEncryption ?? this.smtpEncryption,
      syncInterval: syncInterval ?? this.syncInterval, syncOnlyWifi: syncOnlyWifi ?? this.syncOnlyWifi,
      syncDays: syncDays ?? this.syncDays, isActive: isActive ?? this.isActive,
      isPrimary: isPrimary ?? this.isPrimary, colorValue: colorValue ?? this.colorValue,
      avatarUrl: avatarUrl ?? this.avatarUrl, signatureId: signatureId ?? this.signatureId,
      certificatePath: certificatePath ?? this.certificatePath,
      accessToken: accessToken ?? this.accessToken, refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
      createdAt: createdAt ?? this.createdAt, lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      unreadCount: unreadCount ?? this.unreadCount,
      // Прежде эти поля в копию не попадали: после любой правки аккаунта общий
      // ящик переставал быть общим, а пометка «требуется вход» пропадала.
      authFailedAt: authFailedAt ?? this.authFailedAt,
      sharedMailboxEmail: sharedMailboxEmail ?? this.sharedMailboxEmail,
      parentAccountId: parentAccountId ?? this.parentAccountId,
      accountKind: clearAccountKind ? null : (accountKind ?? this.accountKind),
    );
  }
}

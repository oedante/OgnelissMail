// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exchangeServerMeta = const VerificationMeta(
    'exchangeServer',
  );
  @override
  late final GeneratedColumn<String> exchangeServer = GeneratedColumn<String>(
    'exchange_server',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exchangeAuthMethodMeta =
      const VerificationMeta('exchangeAuthMethod');
  @override
  late final GeneratedColumn<int> exchangeAuthMethod = GeneratedColumn<int>(
    'exchange_auth_method',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ewsUrlMeta = const VerificationMeta('ewsUrl');
  @override
  late final GeneratedColumn<String> ewsUrl = GeneratedColumn<String>(
    'ews_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imapServerMeta = const VerificationMeta(
    'imapServer',
  );
  @override
  late final GeneratedColumn<String> imapServer = GeneratedColumn<String>(
    'imap_server',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imapPortMeta = const VerificationMeta(
    'imapPort',
  );
  @override
  late final GeneratedColumn<int> imapPort = GeneratedColumn<int>(
    'imap_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imapEncryptionMeta = const VerificationMeta(
    'imapEncryption',
  );
  @override
  late final GeneratedColumn<int> imapEncryption = GeneratedColumn<int>(
    'imap_encryption',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smtpServerMeta = const VerificationMeta(
    'smtpServer',
  );
  @override
  late final GeneratedColumn<String> smtpServer = GeneratedColumn<String>(
    'smtp_server',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smtpPortMeta = const VerificationMeta(
    'smtpPort',
  );
  @override
  late final GeneratedColumn<int> smtpPort = GeneratedColumn<int>(
    'smtp_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smtpEncryptionMeta = const VerificationMeta(
    'smtpEncryption',
  );
  @override
  late final GeneratedColumn<int> smtpEncryption = GeneratedColumn<int>(
    'smtp_encryption',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncIntervalMeta = const VerificationMeta(
    'syncInterval',
  );
  @override
  late final GeneratedColumn<int> syncInterval = GeneratedColumn<int>(
    'sync_interval',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _syncOnlyWifiMeta = const VerificationMeta(
    'syncOnlyWifi',
  );
  @override
  late final GeneratedColumn<bool> syncOnlyWifi = GeneratedColumn<bool>(
    'sync_only_wifi',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_only_wifi" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncDaysMeta = const VerificationMeta(
    'syncDays',
  );
  @override
  late final GeneratedColumn<int> syncDays = GeneratedColumn<int>(
    'sync_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(365),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _authFailedAtMeta = const VerificationMeta(
    'authFailedAt',
  );
  @override
  late final GeneratedColumn<DateTime> authFailedAt = GeneratedColumn<DateTime>(
    'auth_failed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharedMailboxEmailMeta =
      const VerificationMeta('sharedMailboxEmail');
  @override
  late final GeneratedColumn<String> sharedMailboxEmail =
      GeneratedColumn<String>(
        'shared_mailbox_email',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _parentAccountIdMeta = const VerificationMeta(
    'parentAccountId',
  );
  @override
  late final GeneratedColumn<String> parentAccountId = GeneratedColumn<String>(
    'parent_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountKindMeta = const VerificationMeta(
    'accountKind',
  );
  @override
  late final GeneratedColumn<String> accountKind = GeneratedColumn<String>(
    'account_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFFFFC928),
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signatureIdMeta = const VerificationMeta(
    'signatureId',
  );
  @override
  late final GeneratedColumn<String> signatureId = GeneratedColumn<String>(
    'signature_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _certificatePathMeta = const VerificationMeta(
    'certificatePath',
  );
  @override
  late final GeneratedColumn<String> certificatePath = GeneratedColumn<String>(
    'certificate_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchModeMeta = const VerificationMeta(
    'fetchMode',
  );
  @override
  late final GeneratedColumn<int> fetchMode = GeneratedColumn<int>(
    'fetch_mode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    email,
    displayName,
    username,
    domain,
    exchangeServer,
    exchangeAuthMethod,
    ewsUrl,
    imapServer,
    imapPort,
    imapEncryption,
    smtpServer,
    smtpPort,
    smtpEncryption,
    syncInterval,
    syncOnlyWifi,
    syncDays,
    isActive,
    authFailedAt,
    sharedMailboxEmail,
    parentAccountId,
    accountKind,
    isPrimary,
    colorValue,
    avatarUrl,
    signatureId,
    certificatePath,
    fetchMode,
    createdAt,
    lastSyncAt,
    unreadCount,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    }
    if (data.containsKey('exchange_server')) {
      context.handle(
        _exchangeServerMeta,
        exchangeServer.isAcceptableOrUnknown(
          data['exchange_server']!,
          _exchangeServerMeta,
        ),
      );
    }
    if (data.containsKey('exchange_auth_method')) {
      context.handle(
        _exchangeAuthMethodMeta,
        exchangeAuthMethod.isAcceptableOrUnknown(
          data['exchange_auth_method']!,
          _exchangeAuthMethodMeta,
        ),
      );
    }
    if (data.containsKey('ews_url')) {
      context.handle(
        _ewsUrlMeta,
        ewsUrl.isAcceptableOrUnknown(data['ews_url']!, _ewsUrlMeta),
      );
    }
    if (data.containsKey('imap_server')) {
      context.handle(
        _imapServerMeta,
        imapServer.isAcceptableOrUnknown(data['imap_server']!, _imapServerMeta),
      );
    }
    if (data.containsKey('imap_port')) {
      context.handle(
        _imapPortMeta,
        imapPort.isAcceptableOrUnknown(data['imap_port']!, _imapPortMeta),
      );
    }
    if (data.containsKey('imap_encryption')) {
      context.handle(
        _imapEncryptionMeta,
        imapEncryption.isAcceptableOrUnknown(
          data['imap_encryption']!,
          _imapEncryptionMeta,
        ),
      );
    }
    if (data.containsKey('smtp_server')) {
      context.handle(
        _smtpServerMeta,
        smtpServer.isAcceptableOrUnknown(data['smtp_server']!, _smtpServerMeta),
      );
    }
    if (data.containsKey('smtp_port')) {
      context.handle(
        _smtpPortMeta,
        smtpPort.isAcceptableOrUnknown(data['smtp_port']!, _smtpPortMeta),
      );
    }
    if (data.containsKey('smtp_encryption')) {
      context.handle(
        _smtpEncryptionMeta,
        smtpEncryption.isAcceptableOrUnknown(
          data['smtp_encryption']!,
          _smtpEncryptionMeta,
        ),
      );
    }
    if (data.containsKey('sync_interval')) {
      context.handle(
        _syncIntervalMeta,
        syncInterval.isAcceptableOrUnknown(
          data['sync_interval']!,
          _syncIntervalMeta,
        ),
      );
    }
    if (data.containsKey('sync_only_wifi')) {
      context.handle(
        _syncOnlyWifiMeta,
        syncOnlyWifi.isAcceptableOrUnknown(
          data['sync_only_wifi']!,
          _syncOnlyWifiMeta,
        ),
      );
    }
    if (data.containsKey('sync_days')) {
      context.handle(
        _syncDaysMeta,
        syncDays.isAcceptableOrUnknown(data['sync_days']!, _syncDaysMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('auth_failed_at')) {
      context.handle(
        _authFailedAtMeta,
        authFailedAt.isAcceptableOrUnknown(
          data['auth_failed_at']!,
          _authFailedAtMeta,
        ),
      );
    }
    if (data.containsKey('shared_mailbox_email')) {
      context.handle(
        _sharedMailboxEmailMeta,
        sharedMailboxEmail.isAcceptableOrUnknown(
          data['shared_mailbox_email']!,
          _sharedMailboxEmailMeta,
        ),
      );
    }
    if (data.containsKey('parent_account_id')) {
      context.handle(
        _parentAccountIdMeta,
        parentAccountId.isAcceptableOrUnknown(
          data['parent_account_id']!,
          _parentAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('account_kind')) {
      context.handle(
        _accountKindMeta,
        accountKind.isAcceptableOrUnknown(
          data['account_kind']!,
          _accountKindMeta,
        ),
      );
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('signature_id')) {
      context.handle(
        _signatureIdMeta,
        signatureId.isAcceptableOrUnknown(
          data['signature_id']!,
          _signatureIdMeta,
        ),
      );
    }
    if (data.containsKey('certificate_path')) {
      context.handle(
        _certificatePathMeta,
        certificatePath.isAcceptableOrUnknown(
          data['certificate_path']!,
          _certificatePathMeta,
        ),
      );
    }
    if (data.containsKey('fetch_mode')) {
      context.handle(
        _fetchModeMeta,
        fetchMode.isAcceptableOrUnknown(data['fetch_mode']!, _fetchModeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      ),
      exchangeServer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_server'],
      ),
      exchangeAuthMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exchange_auth_method'],
      ),
      ewsUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ews_url'],
      ),
      imapServer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}imap_server'],
      ),
      imapPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imap_port'],
      ),
      imapEncryption: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imap_encryption'],
      ),
      smtpServer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smtp_server'],
      ),
      smtpPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}smtp_port'],
      ),
      smtpEncryption: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}smtp_encryption'],
      ),
      syncInterval: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_interval'],
      )!,
      syncOnlyWifi: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_only_wifi'],
      )!,
      syncDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_days'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      authFailedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}auth_failed_at'],
      ),
      sharedMailboxEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shared_mailbox_email'],
      ),
      parentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_account_id'],
      ),
      accountKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_kind'],
      ),
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      signatureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature_id'],
      ),
      certificatePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}certificate_path'],
      ),
      fetchMode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetch_mode'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final String id;
  final int type;
  final String email;
  final String displayName;
  final String username;
  final String? domain;
  final String? exchangeServer;
  final int? exchangeAuthMethod;
  final String? ewsUrl;
  final String? imapServer;
  final int? imapPort;
  final int? imapEncryption;
  final String? smtpServer;
  final int? smtpPort;
  final int? smtpEncryption;
  final int syncInterval;
  final bool syncOnlyWifi;
  final int syncDays;
  final bool isActive;

  /// Когда сервер отверг учётные данные (401/403) ПОСЛЕ успешного подключения.
  /// Такое бывает при смене пароля по политике, блокировке учётной записи или
  /// отзыве токена. null — проблем нет. Нужно, чтобы не «долбить» сервер
  /// неверным паролем (риск блокировки) и чтобы сообщить пользователю.
  final DateTime? authFailedAt;

  /// Адрес общего или делегированного ящика.
  ///
  /// Если задан, аккаунт работает НЕ со своим ящиком: учётные данные берутся
  /// от основной записи (пароль у общего ящика обычно отсутствует), а запросы
  /// EWS адресуются другому почтовому ящику. Так устроены общие ящики
  /// подразделений и делегированный доступ к ящику руководителя.
  final String? sharedMailboxEmail;

  /// Идентификатор основного аккаунта, чьи учётные данные используются для
  /// доступа к общему ящику.
  final String? parentAccountId;
  final String? accountKind;
  final bool isPrimary;
  final int colorValue;
  final String? avatarUrl;
  final String? signatureId;
  final String? certificatePath;
  final int fetchMode;
  final DateTime createdAt;
  final DateTime? lastSyncAt;
  final int unreadCount;
  final int sortOrder;
  const Account({
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
    required this.syncInterval,
    required this.syncOnlyWifi,
    required this.syncDays,
    required this.isActive,
    this.authFailedAt,
    this.sharedMailboxEmail,
    this.parentAccountId,
    this.accountKind,
    required this.isPrimary,
    required this.colorValue,
    this.avatarUrl,
    this.signatureId,
    this.certificatePath,
    required this.fetchMode,
    required this.createdAt,
    this.lastSyncAt,
    required this.unreadCount,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<int>(type);
    map['email'] = Variable<String>(email);
    map['display_name'] = Variable<String>(displayName);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || domain != null) {
      map['domain'] = Variable<String>(domain);
    }
    if (!nullToAbsent || exchangeServer != null) {
      map['exchange_server'] = Variable<String>(exchangeServer);
    }
    if (!nullToAbsent || exchangeAuthMethod != null) {
      map['exchange_auth_method'] = Variable<int>(exchangeAuthMethod);
    }
    if (!nullToAbsent || ewsUrl != null) {
      map['ews_url'] = Variable<String>(ewsUrl);
    }
    if (!nullToAbsent || imapServer != null) {
      map['imap_server'] = Variable<String>(imapServer);
    }
    if (!nullToAbsent || imapPort != null) {
      map['imap_port'] = Variable<int>(imapPort);
    }
    if (!nullToAbsent || imapEncryption != null) {
      map['imap_encryption'] = Variable<int>(imapEncryption);
    }
    if (!nullToAbsent || smtpServer != null) {
      map['smtp_server'] = Variable<String>(smtpServer);
    }
    if (!nullToAbsent || smtpPort != null) {
      map['smtp_port'] = Variable<int>(smtpPort);
    }
    if (!nullToAbsent || smtpEncryption != null) {
      map['smtp_encryption'] = Variable<int>(smtpEncryption);
    }
    map['sync_interval'] = Variable<int>(syncInterval);
    map['sync_only_wifi'] = Variable<bool>(syncOnlyWifi);
    map['sync_days'] = Variable<int>(syncDays);
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || authFailedAt != null) {
      map['auth_failed_at'] = Variable<DateTime>(authFailedAt);
    }
    if (!nullToAbsent || sharedMailboxEmail != null) {
      map['shared_mailbox_email'] = Variable<String>(sharedMailboxEmail);
    }
    if (!nullToAbsent || parentAccountId != null) {
      map['parent_account_id'] = Variable<String>(parentAccountId);
    }
    if (!nullToAbsent || accountKind != null) {
      map['account_kind'] = Variable<String>(accountKind);
    }
    map['is_primary'] = Variable<bool>(isPrimary);
    map['color_value'] = Variable<int>(colorValue);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || signatureId != null) {
      map['signature_id'] = Variable<String>(signatureId);
    }
    if (!nullToAbsent || certificatePath != null) {
      map['certificate_path'] = Variable<String>(certificatePath);
    }
    map['fetch_mode'] = Variable<int>(fetchMode);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      type: Value(type),
      email: Value(email),
      displayName: Value(displayName),
      username: Value(username),
      domain: domain == null && nullToAbsent
          ? const Value.absent()
          : Value(domain),
      exchangeServer: exchangeServer == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeServer),
      exchangeAuthMethod: exchangeAuthMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeAuthMethod),
      ewsUrl: ewsUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(ewsUrl),
      imapServer: imapServer == null && nullToAbsent
          ? const Value.absent()
          : Value(imapServer),
      imapPort: imapPort == null && nullToAbsent
          ? const Value.absent()
          : Value(imapPort),
      imapEncryption: imapEncryption == null && nullToAbsent
          ? const Value.absent()
          : Value(imapEncryption),
      smtpServer: smtpServer == null && nullToAbsent
          ? const Value.absent()
          : Value(smtpServer),
      smtpPort: smtpPort == null && nullToAbsent
          ? const Value.absent()
          : Value(smtpPort),
      smtpEncryption: smtpEncryption == null && nullToAbsent
          ? const Value.absent()
          : Value(smtpEncryption),
      syncInterval: Value(syncInterval),
      syncOnlyWifi: Value(syncOnlyWifi),
      syncDays: Value(syncDays),
      isActive: Value(isActive),
      authFailedAt: authFailedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(authFailedAt),
      sharedMailboxEmail: sharedMailboxEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(sharedMailboxEmail),
      parentAccountId: parentAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentAccountId),
      accountKind: accountKind == null && nullToAbsent
          ? const Value.absent()
          : Value(accountKind),
      isPrimary: Value(isPrimary),
      colorValue: Value(colorValue),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      signatureId: signatureId == null && nullToAbsent
          ? const Value.absent()
          : Value(signatureId),
      certificatePath: certificatePath == null && nullToAbsent
          ? const Value.absent()
          : Value(certificatePath),
      fetchMode: Value(fetchMode),
      createdAt: Value(createdAt),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      unreadCount: Value(unreadCount),
      sortOrder: Value(sortOrder),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<int>(json['type']),
      email: serializer.fromJson<String>(json['email']),
      displayName: serializer.fromJson<String>(json['displayName']),
      username: serializer.fromJson<String>(json['username']),
      domain: serializer.fromJson<String?>(json['domain']),
      exchangeServer: serializer.fromJson<String?>(json['exchangeServer']),
      exchangeAuthMethod: serializer.fromJson<int?>(json['exchangeAuthMethod']),
      ewsUrl: serializer.fromJson<String?>(json['ewsUrl']),
      imapServer: serializer.fromJson<String?>(json['imapServer']),
      imapPort: serializer.fromJson<int?>(json['imapPort']),
      imapEncryption: serializer.fromJson<int?>(json['imapEncryption']),
      smtpServer: serializer.fromJson<String?>(json['smtpServer']),
      smtpPort: serializer.fromJson<int?>(json['smtpPort']),
      smtpEncryption: serializer.fromJson<int?>(json['smtpEncryption']),
      syncInterval: serializer.fromJson<int>(json['syncInterval']),
      syncOnlyWifi: serializer.fromJson<bool>(json['syncOnlyWifi']),
      syncDays: serializer.fromJson<int>(json['syncDays']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      authFailedAt: serializer.fromJson<DateTime?>(json['authFailedAt']),
      sharedMailboxEmail: serializer.fromJson<String?>(
        json['sharedMailboxEmail'],
      ),
      parentAccountId: serializer.fromJson<String?>(json['parentAccountId']),
      accountKind: serializer.fromJson<String?>(json['accountKind']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      signatureId: serializer.fromJson<String?>(json['signatureId']),
      certificatePath: serializer.fromJson<String?>(json['certificatePath']),
      fetchMode: serializer.fromJson<int>(json['fetchMode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<int>(type),
      'email': serializer.toJson<String>(email),
      'displayName': serializer.toJson<String>(displayName),
      'username': serializer.toJson<String>(username),
      'domain': serializer.toJson<String?>(domain),
      'exchangeServer': serializer.toJson<String?>(exchangeServer),
      'exchangeAuthMethod': serializer.toJson<int?>(exchangeAuthMethod),
      'ewsUrl': serializer.toJson<String?>(ewsUrl),
      'imapServer': serializer.toJson<String?>(imapServer),
      'imapPort': serializer.toJson<int?>(imapPort),
      'imapEncryption': serializer.toJson<int?>(imapEncryption),
      'smtpServer': serializer.toJson<String?>(smtpServer),
      'smtpPort': serializer.toJson<int?>(smtpPort),
      'smtpEncryption': serializer.toJson<int?>(smtpEncryption),
      'syncInterval': serializer.toJson<int>(syncInterval),
      'syncOnlyWifi': serializer.toJson<bool>(syncOnlyWifi),
      'syncDays': serializer.toJson<int>(syncDays),
      'isActive': serializer.toJson<bool>(isActive),
      'authFailedAt': serializer.toJson<DateTime?>(authFailedAt),
      'sharedMailboxEmail': serializer.toJson<String?>(sharedMailboxEmail),
      'parentAccountId': serializer.toJson<String?>(parentAccountId),
      'accountKind': serializer.toJson<String?>(accountKind),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'colorValue': serializer.toJson<int>(colorValue),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'signatureId': serializer.toJson<String?>(signatureId),
      'certificatePath': serializer.toJson<String?>(certificatePath),
      'fetchMode': serializer.toJson<int>(fetchMode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Account copyWith({
    String? id,
    int? type,
    String? email,
    String? displayName,
    String? username,
    Value<String?> domain = const Value.absent(),
    Value<String?> exchangeServer = const Value.absent(),
    Value<int?> exchangeAuthMethod = const Value.absent(),
    Value<String?> ewsUrl = const Value.absent(),
    Value<String?> imapServer = const Value.absent(),
    Value<int?> imapPort = const Value.absent(),
    Value<int?> imapEncryption = const Value.absent(),
    Value<String?> smtpServer = const Value.absent(),
    Value<int?> smtpPort = const Value.absent(),
    Value<int?> smtpEncryption = const Value.absent(),
    int? syncInterval,
    bool? syncOnlyWifi,
    int? syncDays,
    bool? isActive,
    Value<DateTime?> authFailedAt = const Value.absent(),
    Value<String?> sharedMailboxEmail = const Value.absent(),
    Value<String?> parentAccountId = const Value.absent(),
    Value<String?> accountKind = const Value.absent(),
    bool? isPrimary,
    int? colorValue,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> signatureId = const Value.absent(),
    Value<String?> certificatePath = const Value.absent(),
    int? fetchMode,
    DateTime? createdAt,
    Value<DateTime?> lastSyncAt = const Value.absent(),
    int? unreadCount,
    int? sortOrder,
  }) => Account(
    id: id ?? this.id,
    type: type ?? this.type,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    domain: domain.present ? domain.value : this.domain,
    exchangeServer: exchangeServer.present
        ? exchangeServer.value
        : this.exchangeServer,
    exchangeAuthMethod: exchangeAuthMethod.present
        ? exchangeAuthMethod.value
        : this.exchangeAuthMethod,
    ewsUrl: ewsUrl.present ? ewsUrl.value : this.ewsUrl,
    imapServer: imapServer.present ? imapServer.value : this.imapServer,
    imapPort: imapPort.present ? imapPort.value : this.imapPort,
    imapEncryption: imapEncryption.present
        ? imapEncryption.value
        : this.imapEncryption,
    smtpServer: smtpServer.present ? smtpServer.value : this.smtpServer,
    smtpPort: smtpPort.present ? smtpPort.value : this.smtpPort,
    smtpEncryption: smtpEncryption.present
        ? smtpEncryption.value
        : this.smtpEncryption,
    syncInterval: syncInterval ?? this.syncInterval,
    syncOnlyWifi: syncOnlyWifi ?? this.syncOnlyWifi,
    syncDays: syncDays ?? this.syncDays,
    isActive: isActive ?? this.isActive,
    authFailedAt: authFailedAt.present ? authFailedAt.value : this.authFailedAt,
    sharedMailboxEmail: sharedMailboxEmail.present
        ? sharedMailboxEmail.value
        : this.sharedMailboxEmail,
    parentAccountId: parentAccountId.present
        ? parentAccountId.value
        : this.parentAccountId,
    accountKind: accountKind.present ? accountKind.value : this.accountKind,
    isPrimary: isPrimary ?? this.isPrimary,
    colorValue: colorValue ?? this.colorValue,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    signatureId: signatureId.present ? signatureId.value : this.signatureId,
    certificatePath: certificatePath.present
        ? certificatePath.value
        : this.certificatePath,
    fetchMode: fetchMode ?? this.fetchMode,
    createdAt: createdAt ?? this.createdAt,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    unreadCount: unreadCount ?? this.unreadCount,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      email: data.email.present ? data.email.value : this.email,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      username: data.username.present ? data.username.value : this.username,
      domain: data.domain.present ? data.domain.value : this.domain,
      exchangeServer: data.exchangeServer.present
          ? data.exchangeServer.value
          : this.exchangeServer,
      exchangeAuthMethod: data.exchangeAuthMethod.present
          ? data.exchangeAuthMethod.value
          : this.exchangeAuthMethod,
      ewsUrl: data.ewsUrl.present ? data.ewsUrl.value : this.ewsUrl,
      imapServer: data.imapServer.present
          ? data.imapServer.value
          : this.imapServer,
      imapPort: data.imapPort.present ? data.imapPort.value : this.imapPort,
      imapEncryption: data.imapEncryption.present
          ? data.imapEncryption.value
          : this.imapEncryption,
      smtpServer: data.smtpServer.present
          ? data.smtpServer.value
          : this.smtpServer,
      smtpPort: data.smtpPort.present ? data.smtpPort.value : this.smtpPort,
      smtpEncryption: data.smtpEncryption.present
          ? data.smtpEncryption.value
          : this.smtpEncryption,
      syncInterval: data.syncInterval.present
          ? data.syncInterval.value
          : this.syncInterval,
      syncOnlyWifi: data.syncOnlyWifi.present
          ? data.syncOnlyWifi.value
          : this.syncOnlyWifi,
      syncDays: data.syncDays.present ? data.syncDays.value : this.syncDays,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      authFailedAt: data.authFailedAt.present
          ? data.authFailedAt.value
          : this.authFailedAt,
      sharedMailboxEmail: data.sharedMailboxEmail.present
          ? data.sharedMailboxEmail.value
          : this.sharedMailboxEmail,
      parentAccountId: data.parentAccountId.present
          ? data.parentAccountId.value
          : this.parentAccountId,
      accountKind: data.accountKind.present
          ? data.accountKind.value
          : this.accountKind,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      signatureId: data.signatureId.present
          ? data.signatureId.value
          : this.signatureId,
      certificatePath: data.certificatePath.present
          ? data.certificatePath.value
          : this.certificatePath,
      fetchMode: data.fetchMode.present ? data.fetchMode.value : this.fetchMode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('domain: $domain, ')
          ..write('exchangeServer: $exchangeServer, ')
          ..write('exchangeAuthMethod: $exchangeAuthMethod, ')
          ..write('ewsUrl: $ewsUrl, ')
          ..write('imapServer: $imapServer, ')
          ..write('imapPort: $imapPort, ')
          ..write('imapEncryption: $imapEncryption, ')
          ..write('smtpServer: $smtpServer, ')
          ..write('smtpPort: $smtpPort, ')
          ..write('smtpEncryption: $smtpEncryption, ')
          ..write('syncInterval: $syncInterval, ')
          ..write('syncOnlyWifi: $syncOnlyWifi, ')
          ..write('syncDays: $syncDays, ')
          ..write('isActive: $isActive, ')
          ..write('authFailedAt: $authFailedAt, ')
          ..write('sharedMailboxEmail: $sharedMailboxEmail, ')
          ..write('parentAccountId: $parentAccountId, ')
          ..write('accountKind: $accountKind, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('colorValue: $colorValue, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('signatureId: $signatureId, ')
          ..write('certificatePath: $certificatePath, ')
          ..write('fetchMode: $fetchMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    email,
    displayName,
    username,
    domain,
    exchangeServer,
    exchangeAuthMethod,
    ewsUrl,
    imapServer,
    imapPort,
    imapEncryption,
    smtpServer,
    smtpPort,
    smtpEncryption,
    syncInterval,
    syncOnlyWifi,
    syncDays,
    isActive,
    authFailedAt,
    sharedMailboxEmail,
    parentAccountId,
    accountKind,
    isPrimary,
    colorValue,
    avatarUrl,
    signatureId,
    certificatePath,
    fetchMode,
    createdAt,
    lastSyncAt,
    unreadCount,
    sortOrder,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.type == this.type &&
          other.email == this.email &&
          other.displayName == this.displayName &&
          other.username == this.username &&
          other.domain == this.domain &&
          other.exchangeServer == this.exchangeServer &&
          other.exchangeAuthMethod == this.exchangeAuthMethod &&
          other.ewsUrl == this.ewsUrl &&
          other.imapServer == this.imapServer &&
          other.imapPort == this.imapPort &&
          other.imapEncryption == this.imapEncryption &&
          other.smtpServer == this.smtpServer &&
          other.smtpPort == this.smtpPort &&
          other.smtpEncryption == this.smtpEncryption &&
          other.syncInterval == this.syncInterval &&
          other.syncOnlyWifi == this.syncOnlyWifi &&
          other.syncDays == this.syncDays &&
          other.isActive == this.isActive &&
          other.authFailedAt == this.authFailedAt &&
          other.sharedMailboxEmail == this.sharedMailboxEmail &&
          other.parentAccountId == this.parentAccountId &&
          other.accountKind == this.accountKind &&
          other.isPrimary == this.isPrimary &&
          other.colorValue == this.colorValue &&
          other.avatarUrl == this.avatarUrl &&
          other.signatureId == this.signatureId &&
          other.certificatePath == this.certificatePath &&
          other.fetchMode == this.fetchMode &&
          other.createdAt == this.createdAt &&
          other.lastSyncAt == this.lastSyncAt &&
          other.unreadCount == this.unreadCount &&
          other.sortOrder == this.sortOrder);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<int> type;
  final Value<String> email;
  final Value<String> displayName;
  final Value<String> username;
  final Value<String?> domain;
  final Value<String?> exchangeServer;
  final Value<int?> exchangeAuthMethod;
  final Value<String?> ewsUrl;
  final Value<String?> imapServer;
  final Value<int?> imapPort;
  final Value<int?> imapEncryption;
  final Value<String?> smtpServer;
  final Value<int?> smtpPort;
  final Value<int?> smtpEncryption;
  final Value<int> syncInterval;
  final Value<bool> syncOnlyWifi;
  final Value<int> syncDays;
  final Value<bool> isActive;
  final Value<DateTime?> authFailedAt;
  final Value<String?> sharedMailboxEmail;
  final Value<String?> parentAccountId;
  final Value<String?> accountKind;
  final Value<bool> isPrimary;
  final Value<int> colorValue;
  final Value<String?> avatarUrl;
  final Value<String?> signatureId;
  final Value<String?> certificatePath;
  final Value<int> fetchMode;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastSyncAt;
  final Value<int> unreadCount;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.email = const Value.absent(),
    this.displayName = const Value.absent(),
    this.username = const Value.absent(),
    this.domain = const Value.absent(),
    this.exchangeServer = const Value.absent(),
    this.exchangeAuthMethod = const Value.absent(),
    this.ewsUrl = const Value.absent(),
    this.imapServer = const Value.absent(),
    this.imapPort = const Value.absent(),
    this.imapEncryption = const Value.absent(),
    this.smtpServer = const Value.absent(),
    this.smtpPort = const Value.absent(),
    this.smtpEncryption = const Value.absent(),
    this.syncInterval = const Value.absent(),
    this.syncOnlyWifi = const Value.absent(),
    this.syncDays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.authFailedAt = const Value.absent(),
    this.sharedMailboxEmail = const Value.absent(),
    this.parentAccountId = const Value.absent(),
    this.accountKind = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.signatureId = const Value.absent(),
    this.certificatePath = const Value.absent(),
    this.fetchMode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required int type,
    required String email,
    required String displayName,
    required String username,
    this.domain = const Value.absent(),
    this.exchangeServer = const Value.absent(),
    this.exchangeAuthMethod = const Value.absent(),
    this.ewsUrl = const Value.absent(),
    this.imapServer = const Value.absent(),
    this.imapPort = const Value.absent(),
    this.imapEncryption = const Value.absent(),
    this.smtpServer = const Value.absent(),
    this.smtpPort = const Value.absent(),
    this.smtpEncryption = const Value.absent(),
    this.syncInterval = const Value.absent(),
    this.syncOnlyWifi = const Value.absent(),
    this.syncDays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.authFailedAt = const Value.absent(),
    this.sharedMailboxEmail = const Value.absent(),
    this.parentAccountId = const Value.absent(),
    this.accountKind = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.signatureId = const Value.absent(),
    this.certificatePath = const Value.absent(),
    this.fetchMode = const Value.absent(),
    required DateTime createdAt,
    this.lastSyncAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       email = Value(email),
       displayName = Value(displayName),
       username = Value(username),
       createdAt = Value(createdAt);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<int>? type,
    Expression<String>? email,
    Expression<String>? displayName,
    Expression<String>? username,
    Expression<String>? domain,
    Expression<String>? exchangeServer,
    Expression<int>? exchangeAuthMethod,
    Expression<String>? ewsUrl,
    Expression<String>? imapServer,
    Expression<int>? imapPort,
    Expression<int>? imapEncryption,
    Expression<String>? smtpServer,
    Expression<int>? smtpPort,
    Expression<int>? smtpEncryption,
    Expression<int>? syncInterval,
    Expression<bool>? syncOnlyWifi,
    Expression<int>? syncDays,
    Expression<bool>? isActive,
    Expression<DateTime>? authFailedAt,
    Expression<String>? sharedMailboxEmail,
    Expression<String>? parentAccountId,
    Expression<String>? accountKind,
    Expression<bool>? isPrimary,
    Expression<int>? colorValue,
    Expression<String>? avatarUrl,
    Expression<String>? signatureId,
    Expression<String>? certificatePath,
    Expression<int>? fetchMode,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSyncAt,
    Expression<int>? unreadCount,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (email != null) 'email': email,
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (domain != null) 'domain': domain,
      if (exchangeServer != null) 'exchange_server': exchangeServer,
      if (exchangeAuthMethod != null)
        'exchange_auth_method': exchangeAuthMethod,
      if (ewsUrl != null) 'ews_url': ewsUrl,
      if (imapServer != null) 'imap_server': imapServer,
      if (imapPort != null) 'imap_port': imapPort,
      if (imapEncryption != null) 'imap_encryption': imapEncryption,
      if (smtpServer != null) 'smtp_server': smtpServer,
      if (smtpPort != null) 'smtp_port': smtpPort,
      if (smtpEncryption != null) 'smtp_encryption': smtpEncryption,
      if (syncInterval != null) 'sync_interval': syncInterval,
      if (syncOnlyWifi != null) 'sync_only_wifi': syncOnlyWifi,
      if (syncDays != null) 'sync_days': syncDays,
      if (isActive != null) 'is_active': isActive,
      if (authFailedAt != null) 'auth_failed_at': authFailedAt,
      if (sharedMailboxEmail != null)
        'shared_mailbox_email': sharedMailboxEmail,
      if (parentAccountId != null) 'parent_account_id': parentAccountId,
      if (accountKind != null) 'account_kind': accountKind,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (colorValue != null) 'color_value': colorValue,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (signatureId != null) 'signature_id': signatureId,
      if (certificatePath != null) 'certificate_path': certificatePath,
      if (fetchMode != null) 'fetch_mode': fetchMode,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<int>? type,
    Value<String>? email,
    Value<String>? displayName,
    Value<String>? username,
    Value<String?>? domain,
    Value<String?>? exchangeServer,
    Value<int?>? exchangeAuthMethod,
    Value<String?>? ewsUrl,
    Value<String?>? imapServer,
    Value<int?>? imapPort,
    Value<int?>? imapEncryption,
    Value<String?>? smtpServer,
    Value<int?>? smtpPort,
    Value<int?>? smtpEncryption,
    Value<int>? syncInterval,
    Value<bool>? syncOnlyWifi,
    Value<int>? syncDays,
    Value<bool>? isActive,
    Value<DateTime?>? authFailedAt,
    Value<String?>? sharedMailboxEmail,
    Value<String?>? parentAccountId,
    Value<String?>? accountKind,
    Value<bool>? isPrimary,
    Value<int>? colorValue,
    Value<String?>? avatarUrl,
    Value<String?>? signatureId,
    Value<String?>? certificatePath,
    Value<int>? fetchMode,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastSyncAt,
    Value<int>? unreadCount,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      domain: domain ?? this.domain,
      exchangeServer: exchangeServer ?? this.exchangeServer,
      exchangeAuthMethod: exchangeAuthMethod ?? this.exchangeAuthMethod,
      ewsUrl: ewsUrl ?? this.ewsUrl,
      imapServer: imapServer ?? this.imapServer,
      imapPort: imapPort ?? this.imapPort,
      imapEncryption: imapEncryption ?? this.imapEncryption,
      smtpServer: smtpServer ?? this.smtpServer,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpEncryption: smtpEncryption ?? this.smtpEncryption,
      syncInterval: syncInterval ?? this.syncInterval,
      syncOnlyWifi: syncOnlyWifi ?? this.syncOnlyWifi,
      syncDays: syncDays ?? this.syncDays,
      isActive: isActive ?? this.isActive,
      authFailedAt: authFailedAt ?? this.authFailedAt,
      sharedMailboxEmail: sharedMailboxEmail ?? this.sharedMailboxEmail,
      parentAccountId: parentAccountId ?? this.parentAccountId,
      accountKind: accountKind ?? this.accountKind,
      isPrimary: isPrimary ?? this.isPrimary,
      colorValue: colorValue ?? this.colorValue,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      signatureId: signatureId ?? this.signatureId,
      certificatePath: certificatePath ?? this.certificatePath,
      fetchMode: fetchMode ?? this.fetchMode,
      createdAt: createdAt ?? this.createdAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      unreadCount: unreadCount ?? this.unreadCount,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (exchangeServer.present) {
      map['exchange_server'] = Variable<String>(exchangeServer.value);
    }
    if (exchangeAuthMethod.present) {
      map['exchange_auth_method'] = Variable<int>(exchangeAuthMethod.value);
    }
    if (ewsUrl.present) {
      map['ews_url'] = Variable<String>(ewsUrl.value);
    }
    if (imapServer.present) {
      map['imap_server'] = Variable<String>(imapServer.value);
    }
    if (imapPort.present) {
      map['imap_port'] = Variable<int>(imapPort.value);
    }
    if (imapEncryption.present) {
      map['imap_encryption'] = Variable<int>(imapEncryption.value);
    }
    if (smtpServer.present) {
      map['smtp_server'] = Variable<String>(smtpServer.value);
    }
    if (smtpPort.present) {
      map['smtp_port'] = Variable<int>(smtpPort.value);
    }
    if (smtpEncryption.present) {
      map['smtp_encryption'] = Variable<int>(smtpEncryption.value);
    }
    if (syncInterval.present) {
      map['sync_interval'] = Variable<int>(syncInterval.value);
    }
    if (syncOnlyWifi.present) {
      map['sync_only_wifi'] = Variable<bool>(syncOnlyWifi.value);
    }
    if (syncDays.present) {
      map['sync_days'] = Variable<int>(syncDays.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (authFailedAt.present) {
      map['auth_failed_at'] = Variable<DateTime>(authFailedAt.value);
    }
    if (sharedMailboxEmail.present) {
      map['shared_mailbox_email'] = Variable<String>(sharedMailboxEmail.value);
    }
    if (parentAccountId.present) {
      map['parent_account_id'] = Variable<String>(parentAccountId.value);
    }
    if (accountKind.present) {
      map['account_kind'] = Variable<String>(accountKind.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (signatureId.present) {
      map['signature_id'] = Variable<String>(signatureId.value);
    }
    if (certificatePath.present) {
      map['certificate_path'] = Variable<String>(certificatePath.value);
    }
    if (fetchMode.present) {
      map['fetch_mode'] = Variable<int>(fetchMode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('domain: $domain, ')
          ..write('exchangeServer: $exchangeServer, ')
          ..write('exchangeAuthMethod: $exchangeAuthMethod, ')
          ..write('ewsUrl: $ewsUrl, ')
          ..write('imapServer: $imapServer, ')
          ..write('imapPort: $imapPort, ')
          ..write('imapEncryption: $imapEncryption, ')
          ..write('smtpServer: $smtpServer, ')
          ..write('smtpPort: $smtpPort, ')
          ..write('smtpEncryption: $smtpEncryption, ')
          ..write('syncInterval: $syncInterval, ')
          ..write('syncOnlyWifi: $syncOnlyWifi, ')
          ..write('syncDays: $syncDays, ')
          ..write('isActive: $isActive, ')
          ..write('authFailedAt: $authFailedAt, ')
          ..write('sharedMailboxEmail: $sharedMailboxEmail, ')
          ..write('parentAccountId: $parentAccountId, ')
          ..write('accountKind: $accountKind, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('colorValue: $colorValue, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('signatureId: $signatureId, ')
          ..write('certificatePath: $certificatePath, ')
          ..write('fetchMode: $fetchMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EmailsTable extends Emails with TableInfo<$EmailsTable, Email> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderNameMeta = const VerificationMeta(
    'folderName',
  );
  @override
  late final GeneratedColumn<String> folderName = GeneratedColumn<String>(
    'folder_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _internetMessageIdMeta = const VerificationMeta(
    'internetMessageId',
  );
  @override
  late final GeneratedColumn<String> internetMessageId =
      GeneratedColumn<String>(
        'internet_message_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _referencesStrMeta = const VerificationMeta(
    'referencesStr',
  );
  @override
  late final GeneratedColumn<String> referencesStr = GeneratedColumn<String>(
    'references_str',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromEmailMeta = const VerificationMeta(
    'fromEmail',
  );
  @override
  late final GeneratedColumn<String> fromEmail = GeneratedColumn<String>(
    'from_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromNameMeta = const VerificationMeta(
    'fromName',
  );
  @override
  late final GeneratedColumn<String> fromName = GeneratedColumn<String>(
    'from_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toRecipientsMeta = const VerificationMeta(
    'toRecipients',
  );
  @override
  late final GeneratedColumn<String> toRecipients = GeneratedColumn<String>(
    'to_recipients',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ccJsonMeta = const VerificationMeta('ccJson');
  @override
  late final GeneratedColumn<String> ccJson = GeneratedColumn<String>(
    'cc_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bccJsonMeta = const VerificationMeta(
    'bccJson',
  );
  @override
  late final GeneratedColumn<String> bccJson = GeneratedColumn<String>(
    'bcc_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToEmailMeta = const VerificationMeta(
    'replyToEmail',
  );
  @override
  late final GeneratedColumn<String> replyToEmail = GeneratedColumn<String>(
    'reply_to_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyPlainMeta = const VerificationMeta(
    'bodyPlain',
  );
  @override
  late final GeneratedColumn<String> bodyPlain = GeneratedColumn<String>(
    'body_plain',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyHtmlMeta = const VerificationMeta(
    'bodyHtml',
  );
  @override
  late final GeneratedColumn<String> bodyHtml = GeneratedColumn<String>(
    'body_html',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyPreviewMeta = const VerificationMeta(
    'bodyPreview',
  );
  @override
  late final GeneratedColumn<String> bodyPreview = GeneratedColumn<String>(
    'body_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authResultsMeta = const VerificationMeta(
    'authResults',
  );
  @override
  late final GeneratedColumn<String> authResults = GeneratedColumn<String>(
    'auth_results',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meetingJsonMeta = const VerificationMeta(
    'meetingJson',
  );
  @override
  late final GeneratedColumn<String> meetingJson = GeneratedColumn<String>(
    'meeting_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
    'remind_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _followUpAtMeta = const VerificationMeta(
    'followUpAt',
  );
  @override
  late final GeneratedColumn<DateTime> followUpAt = GeneratedColumn<DateTime>(
    'follow_up_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _controlStateMeta = const VerificationMeta(
    'controlState',
  );
  @override
  late final GeneratedColumn<int> controlState = GeneratedColumn<int>(
    'control_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _laterStateMeta = const VerificationMeta(
    'laterState',
  );
  @override
  late final GeneratedColumn<int> laterState = GeneratedColumn<int>(
    'later_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _listUnsubscribeMeta = const VerificationMeta(
    'listUnsubscribe',
  );
  @override
  late final GeneratedColumn<String> listUnsubscribe = GeneratedColumn<String>(
    'list_unsubscribe',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _controlRepliedMeta = const VerificationMeta(
    'controlReplied',
  );
  @override
  late final GeneratedColumn<String> controlReplied = GeneratedColumn<String>(
    'control_replied',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isFlaggedMeta = const VerificationMeta(
    'isFlagged',
  );
  @override
  late final GeneratedColumn<bool> isFlagged = GeneratedColumn<bool>(
    'is_flagged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_flagged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDraftMeta = const VerificationMeta(
    'isDraft',
  );
  @override
  late final GeneratedColumn<bool> isDraft = GeneratedColumn<bool>(
    'is_draft',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_draft" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isRepliedMeta = const VerificationMeta(
    'isReplied',
  );
  @override
  late final GeneratedColumn<bool> isReplied = GeneratedColumn<bool>(
    'is_replied',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_replied" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isForwardedMeta = const VerificationMeta(
    'isForwarded',
  );
  @override
  late final GeneratedColumn<bool> isForwarded = GeneratedColumn<bool>(
    'is_forwarded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_forwarded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasAttachmentsMeta = const VerificationMeta(
    'hasAttachments',
  );
  @override
  late final GeneratedColumn<bool> hasAttachments = GeneratedColumn<bool>(
    'has_attachments',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_attachments" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3),
  );
  static const VerificationMeta _tagsStrMeta = const VerificationMeta(
    'tagsStr',
  );
  @override
  late final GeneratedColumn<String> tagsStr = GeneratedColumn<String>(
    'tags_str',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoriesStrMeta = const VerificationMeta(
    'categoriesStr',
  );
  @override
  late final GeneratedColumn<String> categoriesStr = GeneratedColumn<String>(
    'categories_str',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationMeta = const VerificationMeta(
    'classification',
  );
  @override
  late final GeneratedColumn<String> classification = GeneratedColumn<String>(
    'classification',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sensitivityMeta = const VerificationMeta(
    'sensitivity',
  );
  @override
  late final GeneratedColumn<String> sensitivity = GeneratedColumn<String>(
    'sensitivity',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sentimentScoreMeta = const VerificationMeta(
    'sentimentScore',
  );
  @override
  late final GeneratedColumn<double> sentimentScore = GeneratedColumn<double>(
    'sentiment_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiCategoryMeta = const VerificationMeta(
    'aiCategory',
  );
  @override
  late final GeneratedColumn<String> aiCategory = GeneratedColumn<String>(
    'ai_category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiRecommendationMeta = const VerificationMeta(
    'aiRecommendation',
  );
  @override
  late final GeneratedColumn<String> aiRecommendation = GeneratedColumn<String>(
    'ai_recommendation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractedDeadlineMeta = const VerificationMeta(
    'extractedDeadline',
  );
  @override
  late final GeneratedColumn<DateTime> extractedDeadline =
      GeneratedColumn<DateTime>(
        'extracted_deadline',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readReceiptRequestedMeta =
      const VerificationMeta('readReceiptRequested');
  @override
  late final GeneratedColumn<bool> readReceiptRequested = GeneratedColumn<bool>(
    'read_receipt_requested',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read_receipt_requested" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isLocallyModifiedMeta = const VerificationMeta(
    'isLocallyModified',
  );
  @override
  late final GeneratedColumn<bool> isLocallyModified = GeneratedColumn<bool>(
    'is_locally_modified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_locally_modified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _loadedLevelMeta = const VerificationMeta(
    'loadedLevel',
  );
  @override
  late final GeneratedColumn<int> loadedLevel = GeneratedColumn<int>(
    'loaded_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    folderId,
    folderName,
    conversationId,
    parentId,
    internetMessageId,
    referencesStr,
    fromEmail,
    fromName,
    toRecipients,
    ccJson,
    bccJson,
    replyToEmail,
    subject,
    bodyPlain,
    bodyHtml,
    bodyPreview,
    authResults,
    meetingJson,
    remindAt,
    followUpAt,
    controlState,
    laterState,
    listUnsubscribe,
    controlReplied,
    attachmentsJson,
    receivedAt,
    sentAt,
    isRead,
    isFlagged,
    isDraft,
    isReplied,
    isForwarded,
    hasAttachments,
    priority,
    status,
    tagsStr,
    categoriesStr,
    classification,
    sensitivity,
    sentimentScore,
    aiCategory,
    aiRecommendation,
    extractedDeadline,
    size,
    readReceiptRequested,
    isLocallyModified,
    loadedLevel,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emails';
  @override
  VerificationContext validateIntegrity(
    Insertable<Email> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('folder_name')) {
      context.handle(
        _folderNameMeta,
        folderName.isAcceptableOrUnknown(data['folder_name']!, _folderNameMeta),
      );
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('internet_message_id')) {
      context.handle(
        _internetMessageIdMeta,
        internetMessageId.isAcceptableOrUnknown(
          data['internet_message_id']!,
          _internetMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('references_str')) {
      context.handle(
        _referencesStrMeta,
        referencesStr.isAcceptableOrUnknown(
          data['references_str']!,
          _referencesStrMeta,
        ),
      );
    }
    if (data.containsKey('from_email')) {
      context.handle(
        _fromEmailMeta,
        fromEmail.isAcceptableOrUnknown(data['from_email']!, _fromEmailMeta),
      );
    } else if (isInserting) {
      context.missing(_fromEmailMeta);
    }
    if (data.containsKey('from_name')) {
      context.handle(
        _fromNameMeta,
        fromName.isAcceptableOrUnknown(data['from_name']!, _fromNameMeta),
      );
    }
    if (data.containsKey('to_recipients')) {
      context.handle(
        _toRecipientsMeta,
        toRecipients.isAcceptableOrUnknown(
          data['to_recipients']!,
          _toRecipientsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_toRecipientsMeta);
    }
    if (data.containsKey('cc_json')) {
      context.handle(
        _ccJsonMeta,
        ccJson.isAcceptableOrUnknown(data['cc_json']!, _ccJsonMeta),
      );
    }
    if (data.containsKey('bcc_json')) {
      context.handle(
        _bccJsonMeta,
        bccJson.isAcceptableOrUnknown(data['bcc_json']!, _bccJsonMeta),
      );
    }
    if (data.containsKey('reply_to_email')) {
      context.handle(
        _replyToEmailMeta,
        replyToEmail.isAcceptableOrUnknown(
          data['reply_to_email']!,
          _replyToEmailMeta,
        ),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('body_plain')) {
      context.handle(
        _bodyPlainMeta,
        bodyPlain.isAcceptableOrUnknown(data['body_plain']!, _bodyPlainMeta),
      );
    }
    if (data.containsKey('body_html')) {
      context.handle(
        _bodyHtmlMeta,
        bodyHtml.isAcceptableOrUnknown(data['body_html']!, _bodyHtmlMeta),
      );
    }
    if (data.containsKey('body_preview')) {
      context.handle(
        _bodyPreviewMeta,
        bodyPreview.isAcceptableOrUnknown(
          data['body_preview']!,
          _bodyPreviewMeta,
        ),
      );
    }
    if (data.containsKey('auth_results')) {
      context.handle(
        _authResultsMeta,
        authResults.isAcceptableOrUnknown(
          data['auth_results']!,
          _authResultsMeta,
        ),
      );
    }
    if (data.containsKey('meeting_json')) {
      context.handle(
        _meetingJsonMeta,
        meetingJson.isAcceptableOrUnknown(
          data['meeting_json']!,
          _meetingJsonMeta,
        ),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    }
    if (data.containsKey('follow_up_at')) {
      context.handle(
        _followUpAtMeta,
        followUpAt.isAcceptableOrUnknown(
          data['follow_up_at']!,
          _followUpAtMeta,
        ),
      );
    }
    if (data.containsKey('control_state')) {
      context.handle(
        _controlStateMeta,
        controlState.isAcceptableOrUnknown(
          data['control_state']!,
          _controlStateMeta,
        ),
      );
    }
    if (data.containsKey('later_state')) {
      context.handle(
        _laterStateMeta,
        laterState.isAcceptableOrUnknown(data['later_state']!, _laterStateMeta),
      );
    }
    if (data.containsKey('list_unsubscribe')) {
      context.handle(
        _listUnsubscribeMeta,
        listUnsubscribe.isAcceptableOrUnknown(
          data['list_unsubscribe']!,
          _listUnsubscribeMeta,
        ),
      );
    }
    if (data.containsKey('control_replied')) {
      context.handle(
        _controlRepliedMeta,
        controlReplied.isAcceptableOrUnknown(
          data['control_replied']!,
          _controlRepliedMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('is_flagged')) {
      context.handle(
        _isFlaggedMeta,
        isFlagged.isAcceptableOrUnknown(data['is_flagged']!, _isFlaggedMeta),
      );
    }
    if (data.containsKey('is_draft')) {
      context.handle(
        _isDraftMeta,
        isDraft.isAcceptableOrUnknown(data['is_draft']!, _isDraftMeta),
      );
    }
    if (data.containsKey('is_replied')) {
      context.handle(
        _isRepliedMeta,
        isReplied.isAcceptableOrUnknown(data['is_replied']!, _isRepliedMeta),
      );
    }
    if (data.containsKey('is_forwarded')) {
      context.handle(
        _isForwardedMeta,
        isForwarded.isAcceptableOrUnknown(
          data['is_forwarded']!,
          _isForwardedMeta,
        ),
      );
    }
    if (data.containsKey('has_attachments')) {
      context.handle(
        _hasAttachmentsMeta,
        hasAttachments.isAcceptableOrUnknown(
          data['has_attachments']!,
          _hasAttachmentsMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('tags_str')) {
      context.handle(
        _tagsStrMeta,
        tagsStr.isAcceptableOrUnknown(data['tags_str']!, _tagsStrMeta),
      );
    }
    if (data.containsKey('categories_str')) {
      context.handle(
        _categoriesStrMeta,
        categoriesStr.isAcceptableOrUnknown(
          data['categories_str']!,
          _categoriesStrMeta,
        ),
      );
    }
    if (data.containsKey('classification')) {
      context.handle(
        _classificationMeta,
        classification.isAcceptableOrUnknown(
          data['classification']!,
          _classificationMeta,
        ),
      );
    }
    if (data.containsKey('sensitivity')) {
      context.handle(
        _sensitivityMeta,
        sensitivity.isAcceptableOrUnknown(
          data['sensitivity']!,
          _sensitivityMeta,
        ),
      );
    }
    if (data.containsKey('sentiment_score')) {
      context.handle(
        _sentimentScoreMeta,
        sentimentScore.isAcceptableOrUnknown(
          data['sentiment_score']!,
          _sentimentScoreMeta,
        ),
      );
    }
    if (data.containsKey('ai_category')) {
      context.handle(
        _aiCategoryMeta,
        aiCategory.isAcceptableOrUnknown(data['ai_category']!, _aiCategoryMeta),
      );
    }
    if (data.containsKey('ai_recommendation')) {
      context.handle(
        _aiRecommendationMeta,
        aiRecommendation.isAcceptableOrUnknown(
          data['ai_recommendation']!,
          _aiRecommendationMeta,
        ),
      );
    }
    if (data.containsKey('extracted_deadline')) {
      context.handle(
        _extractedDeadlineMeta,
        extractedDeadline.isAcceptableOrUnknown(
          data['extracted_deadline']!,
          _extractedDeadlineMeta,
        ),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('read_receipt_requested')) {
      context.handle(
        _readReceiptRequestedMeta,
        readReceiptRequested.isAcceptableOrUnknown(
          data['read_receipt_requested']!,
          _readReceiptRequestedMeta,
        ),
      );
    }
    if (data.containsKey('is_locally_modified')) {
      context.handle(
        _isLocallyModifiedMeta,
        isLocallyModified.isAcceptableOrUnknown(
          data['is_locally_modified']!,
          _isLocallyModifiedMeta,
        ),
      );
    }
    if (data.containsKey('loaded_level')) {
      context.handle(
        _loadedLevelMeta,
        loadedLevel.isAcceptableOrUnknown(
          data['loaded_level']!,
          _loadedLevelMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, accountId};
  @override
  Email map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Email(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      )!,
      folderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_name'],
      ),
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      internetMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}internet_message_id'],
      ),
      referencesStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}references_str'],
      ),
      fromEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_email'],
      )!,
      fromName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_name'],
      ),
      toRecipients: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_recipients'],
      )!,
      ccJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cc_json'],
      ),
      bccJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bcc_json'],
      ),
      replyToEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_email'],
      ),
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      bodyPlain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain'],
      ),
      bodyHtml: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_html'],
      ),
      bodyPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_preview'],
      ),
      authResults: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_results'],
      ),
      meetingJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meeting_json'],
      ),
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remind_at'],
      ),
      followUpAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}follow_up_at'],
      ),
      controlState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}control_state'],
      )!,
      laterState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}later_state'],
      )!,
      listUnsubscribe: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_unsubscribe'],
      ),
      controlReplied: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}control_replied'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      isFlagged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_flagged'],
      )!,
      isDraft: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_draft'],
      )!,
      isReplied: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_replied'],
      )!,
      isForwarded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_forwarded'],
      )!,
      hasAttachments: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_attachments'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      tagsStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_str'],
      ),
      categoriesStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}categories_str'],
      ),
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      ),
      sensitivity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sensitivity'],
      ),
      sentimentScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sentiment_score'],
      ),
      aiCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_category'],
      ),
      aiRecommendation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_recommendation'],
      ),
      extractedDeadline: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}extracted_deadline'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      ),
      readReceiptRequested: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read_receipt_requested'],
      )!,
      isLocallyModified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_locally_modified'],
      )!,
      loadedLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}loaded_level'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      ),
    );
  }

  @override
  $EmailsTable createAlias(String alias) {
    return $EmailsTable(attachedDatabase, alias);
  }
}

class Email extends DataClass implements Insertable<Email> {
  final String id;
  final String accountId;
  final String folderId;
  final String? folderName;
  final String? conversationId;
  final String? parentId;
  final String? internetMessageId;
  final String? referencesStr;
  final String fromEmail;
  final String? fromName;
  final String toRecipients;
  final String? ccJson;
  final String? bccJson;
  final String? replyToEmail;
  final String subject;
  final String? bodyPlain;
  final String? bodyHtml;
  final String? bodyPreview;
  final String? authResults;
  final String? meetingJson;

  /// Время напоминания «вернуться к письму» (снуз). null = нет напоминания.
  final DateTime? remindAt;

  /// Напоминание «нет ответа»: момент, когда нужно проверить, ответили ли на
  /// НАШЕ отправленное письмо. Ставится пользователем явно — поэтому таких
  /// строк единицы, и проверка не нагружает систему.
  final DateTime? followUpAt;

  /// «На контроле» (08.10.2026): 0 — нет; 1 — жду ответа (моё письмо);
  /// 2 — должен ответить (входящее); 3 — исполнено (ответ пришёл или я
  /// ответил). Ставит и снимает пользователь; приложение только переводит
  /// 1/2 → 3. Таких писем единицы — проверка не перебирает базу.
  final int controlState;

  /// «Посмотреть позже» (08.10.2026): 0 — нет; 1 — отложено (до [remindAt]
  /// или без даты, если remindAt пуст); 2 — вернулось (срок наступил: письмо
  /// снова непрочитанное, пришло уведомление) — до открытия письма.
  final int laterState;

  /// Рассылка (09.10.2026): заголовки List-Unsubscribe, List-Unsubscribe-Post
  /// и List-Id одной строкой JSON {"u": …, "p": …, "id": …}. null — не
  /// рассылка или сервер заголовков не дал (ActiveSync).
  final String? listUnsubscribe;

  /// «На контроле», моё письмо нескольким адресатам (09.10.2026): кто из
  /// «Кому» уже ответил — адреса через запятую (копия не считается).
  final String? controlReplied;
  final String? attachmentsJson;
  final DateTime receivedAt;
  final DateTime? sentAt;
  final bool isRead;
  final bool isFlagged;
  final bool isDraft;
  final bool isReplied;
  final bool isForwarded;
  final bool hasAttachments;
  final int priority;
  final int status;
  final String? tagsStr;
  final String? categoriesStr;
  final String? classification;
  final String? sensitivity;
  final double? sentimentScore;
  final String? aiCategory;
  final String? aiRecommendation;
  final DateTime? extractedDeadline;
  final int? size;
  final bool readReceiptRequested;
  final bool isLocallyModified;
  final int loadedLevel;
  final DateTime? cachedAt;
  const Email({
    required this.id,
    required this.accountId,
    required this.folderId,
    this.folderName,
    this.conversationId,
    this.parentId,
    this.internetMessageId,
    this.referencesStr,
    required this.fromEmail,
    this.fromName,
    required this.toRecipients,
    this.ccJson,
    this.bccJson,
    this.replyToEmail,
    required this.subject,
    this.bodyPlain,
    this.bodyHtml,
    this.bodyPreview,
    this.authResults,
    this.meetingJson,
    this.remindAt,
    this.followUpAt,
    required this.controlState,
    required this.laterState,
    this.listUnsubscribe,
    this.controlReplied,
    this.attachmentsJson,
    required this.receivedAt,
    this.sentAt,
    required this.isRead,
    required this.isFlagged,
    required this.isDraft,
    required this.isReplied,
    required this.isForwarded,
    required this.hasAttachments,
    required this.priority,
    required this.status,
    this.tagsStr,
    this.categoriesStr,
    this.classification,
    this.sensitivity,
    this.sentimentScore,
    this.aiCategory,
    this.aiRecommendation,
    this.extractedDeadline,
    this.size,
    required this.readReceiptRequested,
    required this.isLocallyModified,
    required this.loadedLevel,
    this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['folder_id'] = Variable<String>(folderId);
    if (!nullToAbsent || folderName != null) {
      map['folder_name'] = Variable<String>(folderName);
    }
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<String>(conversationId);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || internetMessageId != null) {
      map['internet_message_id'] = Variable<String>(internetMessageId);
    }
    if (!nullToAbsent || referencesStr != null) {
      map['references_str'] = Variable<String>(referencesStr);
    }
    map['from_email'] = Variable<String>(fromEmail);
    if (!nullToAbsent || fromName != null) {
      map['from_name'] = Variable<String>(fromName);
    }
    map['to_recipients'] = Variable<String>(toRecipients);
    if (!nullToAbsent || ccJson != null) {
      map['cc_json'] = Variable<String>(ccJson);
    }
    if (!nullToAbsent || bccJson != null) {
      map['bcc_json'] = Variable<String>(bccJson);
    }
    if (!nullToAbsent || replyToEmail != null) {
      map['reply_to_email'] = Variable<String>(replyToEmail);
    }
    map['subject'] = Variable<String>(subject);
    if (!nullToAbsent || bodyPlain != null) {
      map['body_plain'] = Variable<String>(bodyPlain);
    }
    if (!nullToAbsent || bodyHtml != null) {
      map['body_html'] = Variable<String>(bodyHtml);
    }
    if (!nullToAbsent || bodyPreview != null) {
      map['body_preview'] = Variable<String>(bodyPreview);
    }
    if (!nullToAbsent || authResults != null) {
      map['auth_results'] = Variable<String>(authResults);
    }
    if (!nullToAbsent || meetingJson != null) {
      map['meeting_json'] = Variable<String>(meetingJson);
    }
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<DateTime>(remindAt);
    }
    if (!nullToAbsent || followUpAt != null) {
      map['follow_up_at'] = Variable<DateTime>(followUpAt);
    }
    map['control_state'] = Variable<int>(controlState);
    map['later_state'] = Variable<int>(laterState);
    if (!nullToAbsent || listUnsubscribe != null) {
      map['list_unsubscribe'] = Variable<String>(listUnsubscribe);
    }
    if (!nullToAbsent || controlReplied != null) {
      map['control_replied'] = Variable<String>(controlReplied);
    }
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    map['received_at'] = Variable<DateTime>(receivedAt);
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    map['is_read'] = Variable<bool>(isRead);
    map['is_flagged'] = Variable<bool>(isFlagged);
    map['is_draft'] = Variable<bool>(isDraft);
    map['is_replied'] = Variable<bool>(isReplied);
    map['is_forwarded'] = Variable<bool>(isForwarded);
    map['has_attachments'] = Variable<bool>(hasAttachments);
    map['priority'] = Variable<int>(priority);
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || tagsStr != null) {
      map['tags_str'] = Variable<String>(tagsStr);
    }
    if (!nullToAbsent || categoriesStr != null) {
      map['categories_str'] = Variable<String>(categoriesStr);
    }
    if (!nullToAbsent || classification != null) {
      map['classification'] = Variable<String>(classification);
    }
    if (!nullToAbsent || sensitivity != null) {
      map['sensitivity'] = Variable<String>(sensitivity);
    }
    if (!nullToAbsent || sentimentScore != null) {
      map['sentiment_score'] = Variable<double>(sentimentScore);
    }
    if (!nullToAbsent || aiCategory != null) {
      map['ai_category'] = Variable<String>(aiCategory);
    }
    if (!nullToAbsent || aiRecommendation != null) {
      map['ai_recommendation'] = Variable<String>(aiRecommendation);
    }
    if (!nullToAbsent || extractedDeadline != null) {
      map['extracted_deadline'] = Variable<DateTime>(extractedDeadline);
    }
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<int>(size);
    }
    map['read_receipt_requested'] = Variable<bool>(readReceiptRequested);
    map['is_locally_modified'] = Variable<bool>(isLocallyModified);
    map['loaded_level'] = Variable<int>(loadedLevel);
    if (!nullToAbsent || cachedAt != null) {
      map['cached_at'] = Variable<DateTime>(cachedAt);
    }
    return map;
  }

  EmailsCompanion toCompanion(bool nullToAbsent) {
    return EmailsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      folderId: Value(folderId),
      folderName: folderName == null && nullToAbsent
          ? const Value.absent()
          : Value(folderName),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      internetMessageId: internetMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(internetMessageId),
      referencesStr: referencesStr == null && nullToAbsent
          ? const Value.absent()
          : Value(referencesStr),
      fromEmail: Value(fromEmail),
      fromName: fromName == null && nullToAbsent
          ? const Value.absent()
          : Value(fromName),
      toRecipients: Value(toRecipients),
      ccJson: ccJson == null && nullToAbsent
          ? const Value.absent()
          : Value(ccJson),
      bccJson: bccJson == null && nullToAbsent
          ? const Value.absent()
          : Value(bccJson),
      replyToEmail: replyToEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToEmail),
      subject: Value(subject),
      bodyPlain: bodyPlain == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyPlain),
      bodyHtml: bodyHtml == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyHtml),
      bodyPreview: bodyPreview == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyPreview),
      authResults: authResults == null && nullToAbsent
          ? const Value.absent()
          : Value(authResults),
      meetingJson: meetingJson == null && nullToAbsent
          ? const Value.absent()
          : Value(meetingJson),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      followUpAt: followUpAt == null && nullToAbsent
          ? const Value.absent()
          : Value(followUpAt),
      controlState: Value(controlState),
      laterState: Value(laterState),
      listUnsubscribe: listUnsubscribe == null && nullToAbsent
          ? const Value.absent()
          : Value(listUnsubscribe),
      controlReplied: controlReplied == null && nullToAbsent
          ? const Value.absent()
          : Value(controlReplied),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
      receivedAt: Value(receivedAt),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
      isRead: Value(isRead),
      isFlagged: Value(isFlagged),
      isDraft: Value(isDraft),
      isReplied: Value(isReplied),
      isForwarded: Value(isForwarded),
      hasAttachments: Value(hasAttachments),
      priority: Value(priority),
      status: Value(status),
      tagsStr: tagsStr == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsStr),
      categoriesStr: categoriesStr == null && nullToAbsent
          ? const Value.absent()
          : Value(categoriesStr),
      classification: classification == null && nullToAbsent
          ? const Value.absent()
          : Value(classification),
      sensitivity: sensitivity == null && nullToAbsent
          ? const Value.absent()
          : Value(sensitivity),
      sentimentScore: sentimentScore == null && nullToAbsent
          ? const Value.absent()
          : Value(sentimentScore),
      aiCategory: aiCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(aiCategory),
      aiRecommendation: aiRecommendation == null && nullToAbsent
          ? const Value.absent()
          : Value(aiRecommendation),
      extractedDeadline: extractedDeadline == null && nullToAbsent
          ? const Value.absent()
          : Value(extractedDeadline),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      readReceiptRequested: Value(readReceiptRequested),
      isLocallyModified: Value(isLocallyModified),
      loadedLevel: Value(loadedLevel),
      cachedAt: cachedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cachedAt),
    );
  }

  factory Email.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Email(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      folderId: serializer.fromJson<String>(json['folderId']),
      folderName: serializer.fromJson<String?>(json['folderName']),
      conversationId: serializer.fromJson<String?>(json['conversationId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      internetMessageId: serializer.fromJson<String?>(
        json['internetMessageId'],
      ),
      referencesStr: serializer.fromJson<String?>(json['referencesStr']),
      fromEmail: serializer.fromJson<String>(json['fromEmail']),
      fromName: serializer.fromJson<String?>(json['fromName']),
      toRecipients: serializer.fromJson<String>(json['toRecipients']),
      ccJson: serializer.fromJson<String?>(json['ccJson']),
      bccJson: serializer.fromJson<String?>(json['bccJson']),
      replyToEmail: serializer.fromJson<String?>(json['replyToEmail']),
      subject: serializer.fromJson<String>(json['subject']),
      bodyPlain: serializer.fromJson<String?>(json['bodyPlain']),
      bodyHtml: serializer.fromJson<String?>(json['bodyHtml']),
      bodyPreview: serializer.fromJson<String?>(json['bodyPreview']),
      authResults: serializer.fromJson<String?>(json['authResults']),
      meetingJson: serializer.fromJson<String?>(json['meetingJson']),
      remindAt: serializer.fromJson<DateTime?>(json['remindAt']),
      followUpAt: serializer.fromJson<DateTime?>(json['followUpAt']),
      controlState: serializer.fromJson<int>(json['controlState']),
      laterState: serializer.fromJson<int>(json['laterState']),
      listUnsubscribe: serializer.fromJson<String?>(json['listUnsubscribe']),
      controlReplied: serializer.fromJson<String?>(json['controlReplied']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      isFlagged: serializer.fromJson<bool>(json['isFlagged']),
      isDraft: serializer.fromJson<bool>(json['isDraft']),
      isReplied: serializer.fromJson<bool>(json['isReplied']),
      isForwarded: serializer.fromJson<bool>(json['isForwarded']),
      hasAttachments: serializer.fromJson<bool>(json['hasAttachments']),
      priority: serializer.fromJson<int>(json['priority']),
      status: serializer.fromJson<int>(json['status']),
      tagsStr: serializer.fromJson<String?>(json['tagsStr']),
      categoriesStr: serializer.fromJson<String?>(json['categoriesStr']),
      classification: serializer.fromJson<String?>(json['classification']),
      sensitivity: serializer.fromJson<String?>(json['sensitivity']),
      sentimentScore: serializer.fromJson<double?>(json['sentimentScore']),
      aiCategory: serializer.fromJson<String?>(json['aiCategory']),
      aiRecommendation: serializer.fromJson<String?>(json['aiRecommendation']),
      extractedDeadline: serializer.fromJson<DateTime?>(
        json['extractedDeadline'],
      ),
      size: serializer.fromJson<int?>(json['size']),
      readReceiptRequested: serializer.fromJson<bool>(
        json['readReceiptRequested'],
      ),
      isLocallyModified: serializer.fromJson<bool>(json['isLocallyModified']),
      loadedLevel: serializer.fromJson<int>(json['loadedLevel']),
      cachedAt: serializer.fromJson<DateTime?>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'folderId': serializer.toJson<String>(folderId),
      'folderName': serializer.toJson<String?>(folderName),
      'conversationId': serializer.toJson<String?>(conversationId),
      'parentId': serializer.toJson<String?>(parentId),
      'internetMessageId': serializer.toJson<String?>(internetMessageId),
      'referencesStr': serializer.toJson<String?>(referencesStr),
      'fromEmail': serializer.toJson<String>(fromEmail),
      'fromName': serializer.toJson<String?>(fromName),
      'toRecipients': serializer.toJson<String>(toRecipients),
      'ccJson': serializer.toJson<String?>(ccJson),
      'bccJson': serializer.toJson<String?>(bccJson),
      'replyToEmail': serializer.toJson<String?>(replyToEmail),
      'subject': serializer.toJson<String>(subject),
      'bodyPlain': serializer.toJson<String?>(bodyPlain),
      'bodyHtml': serializer.toJson<String?>(bodyHtml),
      'bodyPreview': serializer.toJson<String?>(bodyPreview),
      'authResults': serializer.toJson<String?>(authResults),
      'meetingJson': serializer.toJson<String?>(meetingJson),
      'remindAt': serializer.toJson<DateTime?>(remindAt),
      'followUpAt': serializer.toJson<DateTime?>(followUpAt),
      'controlState': serializer.toJson<int>(controlState),
      'laterState': serializer.toJson<int>(laterState),
      'listUnsubscribe': serializer.toJson<String?>(listUnsubscribe),
      'controlReplied': serializer.toJson<String?>(controlReplied),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
      'isRead': serializer.toJson<bool>(isRead),
      'isFlagged': serializer.toJson<bool>(isFlagged),
      'isDraft': serializer.toJson<bool>(isDraft),
      'isReplied': serializer.toJson<bool>(isReplied),
      'isForwarded': serializer.toJson<bool>(isForwarded),
      'hasAttachments': serializer.toJson<bool>(hasAttachments),
      'priority': serializer.toJson<int>(priority),
      'status': serializer.toJson<int>(status),
      'tagsStr': serializer.toJson<String?>(tagsStr),
      'categoriesStr': serializer.toJson<String?>(categoriesStr),
      'classification': serializer.toJson<String?>(classification),
      'sensitivity': serializer.toJson<String?>(sensitivity),
      'sentimentScore': serializer.toJson<double?>(sentimentScore),
      'aiCategory': serializer.toJson<String?>(aiCategory),
      'aiRecommendation': serializer.toJson<String?>(aiRecommendation),
      'extractedDeadline': serializer.toJson<DateTime?>(extractedDeadline),
      'size': serializer.toJson<int?>(size),
      'readReceiptRequested': serializer.toJson<bool>(readReceiptRequested),
      'isLocallyModified': serializer.toJson<bool>(isLocallyModified),
      'loadedLevel': serializer.toJson<int>(loadedLevel),
      'cachedAt': serializer.toJson<DateTime?>(cachedAt),
    };
  }

  Email copyWith({
    String? id,
    String? accountId,
    String? folderId,
    Value<String?> folderName = const Value.absent(),
    Value<String?> conversationId = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<String?> internetMessageId = const Value.absent(),
    Value<String?> referencesStr = const Value.absent(),
    String? fromEmail,
    Value<String?> fromName = const Value.absent(),
    String? toRecipients,
    Value<String?> ccJson = const Value.absent(),
    Value<String?> bccJson = const Value.absent(),
    Value<String?> replyToEmail = const Value.absent(),
    String? subject,
    Value<String?> bodyPlain = const Value.absent(),
    Value<String?> bodyHtml = const Value.absent(),
    Value<String?> bodyPreview = const Value.absent(),
    Value<String?> authResults = const Value.absent(),
    Value<String?> meetingJson = const Value.absent(),
    Value<DateTime?> remindAt = const Value.absent(),
    Value<DateTime?> followUpAt = const Value.absent(),
    int? controlState,
    int? laterState,
    Value<String?> listUnsubscribe = const Value.absent(),
    Value<String?> controlReplied = const Value.absent(),
    Value<String?> attachmentsJson = const Value.absent(),
    DateTime? receivedAt,
    Value<DateTime?> sentAt = const Value.absent(),
    bool? isRead,
    bool? isFlagged,
    bool? isDraft,
    bool? isReplied,
    bool? isForwarded,
    bool? hasAttachments,
    int? priority,
    int? status,
    Value<String?> tagsStr = const Value.absent(),
    Value<String?> categoriesStr = const Value.absent(),
    Value<String?> classification = const Value.absent(),
    Value<String?> sensitivity = const Value.absent(),
    Value<double?> sentimentScore = const Value.absent(),
    Value<String?> aiCategory = const Value.absent(),
    Value<String?> aiRecommendation = const Value.absent(),
    Value<DateTime?> extractedDeadline = const Value.absent(),
    Value<int?> size = const Value.absent(),
    bool? readReceiptRequested,
    bool? isLocallyModified,
    int? loadedLevel,
    Value<DateTime?> cachedAt = const Value.absent(),
  }) => Email(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    folderId: folderId ?? this.folderId,
    folderName: folderName.present ? folderName.value : this.folderName,
    conversationId: conversationId.present
        ? conversationId.value
        : this.conversationId,
    parentId: parentId.present ? parentId.value : this.parentId,
    internetMessageId: internetMessageId.present
        ? internetMessageId.value
        : this.internetMessageId,
    referencesStr: referencesStr.present
        ? referencesStr.value
        : this.referencesStr,
    fromEmail: fromEmail ?? this.fromEmail,
    fromName: fromName.present ? fromName.value : this.fromName,
    toRecipients: toRecipients ?? this.toRecipients,
    ccJson: ccJson.present ? ccJson.value : this.ccJson,
    bccJson: bccJson.present ? bccJson.value : this.bccJson,
    replyToEmail: replyToEmail.present ? replyToEmail.value : this.replyToEmail,
    subject: subject ?? this.subject,
    bodyPlain: bodyPlain.present ? bodyPlain.value : this.bodyPlain,
    bodyHtml: bodyHtml.present ? bodyHtml.value : this.bodyHtml,
    bodyPreview: bodyPreview.present ? bodyPreview.value : this.bodyPreview,
    authResults: authResults.present ? authResults.value : this.authResults,
    meetingJson: meetingJson.present ? meetingJson.value : this.meetingJson,
    remindAt: remindAt.present ? remindAt.value : this.remindAt,
    followUpAt: followUpAt.present ? followUpAt.value : this.followUpAt,
    controlState: controlState ?? this.controlState,
    laterState: laterState ?? this.laterState,
    listUnsubscribe: listUnsubscribe.present
        ? listUnsubscribe.value
        : this.listUnsubscribe,
    controlReplied: controlReplied.present
        ? controlReplied.value
        : this.controlReplied,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
    receivedAt: receivedAt ?? this.receivedAt,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
    isRead: isRead ?? this.isRead,
    isFlagged: isFlagged ?? this.isFlagged,
    isDraft: isDraft ?? this.isDraft,
    isReplied: isReplied ?? this.isReplied,
    isForwarded: isForwarded ?? this.isForwarded,
    hasAttachments: hasAttachments ?? this.hasAttachments,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    tagsStr: tagsStr.present ? tagsStr.value : this.tagsStr,
    categoriesStr: categoriesStr.present
        ? categoriesStr.value
        : this.categoriesStr,
    classification: classification.present
        ? classification.value
        : this.classification,
    sensitivity: sensitivity.present ? sensitivity.value : this.sensitivity,
    sentimentScore: sentimentScore.present
        ? sentimentScore.value
        : this.sentimentScore,
    aiCategory: aiCategory.present ? aiCategory.value : this.aiCategory,
    aiRecommendation: aiRecommendation.present
        ? aiRecommendation.value
        : this.aiRecommendation,
    extractedDeadline: extractedDeadline.present
        ? extractedDeadline.value
        : this.extractedDeadline,
    size: size.present ? size.value : this.size,
    readReceiptRequested: readReceiptRequested ?? this.readReceiptRequested,
    isLocallyModified: isLocallyModified ?? this.isLocallyModified,
    loadedLevel: loadedLevel ?? this.loadedLevel,
    cachedAt: cachedAt.present ? cachedAt.value : this.cachedAt,
  );
  Email copyWithCompanion(EmailsCompanion data) {
    return Email(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      folderName: data.folderName.present
          ? data.folderName.value
          : this.folderName,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      internetMessageId: data.internetMessageId.present
          ? data.internetMessageId.value
          : this.internetMessageId,
      referencesStr: data.referencesStr.present
          ? data.referencesStr.value
          : this.referencesStr,
      fromEmail: data.fromEmail.present ? data.fromEmail.value : this.fromEmail,
      fromName: data.fromName.present ? data.fromName.value : this.fromName,
      toRecipients: data.toRecipients.present
          ? data.toRecipients.value
          : this.toRecipients,
      ccJson: data.ccJson.present ? data.ccJson.value : this.ccJson,
      bccJson: data.bccJson.present ? data.bccJson.value : this.bccJson,
      replyToEmail: data.replyToEmail.present
          ? data.replyToEmail.value
          : this.replyToEmail,
      subject: data.subject.present ? data.subject.value : this.subject,
      bodyPlain: data.bodyPlain.present ? data.bodyPlain.value : this.bodyPlain,
      bodyHtml: data.bodyHtml.present ? data.bodyHtml.value : this.bodyHtml,
      bodyPreview: data.bodyPreview.present
          ? data.bodyPreview.value
          : this.bodyPreview,
      authResults: data.authResults.present
          ? data.authResults.value
          : this.authResults,
      meetingJson: data.meetingJson.present
          ? data.meetingJson.value
          : this.meetingJson,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      followUpAt: data.followUpAt.present
          ? data.followUpAt.value
          : this.followUpAt,
      controlState: data.controlState.present
          ? data.controlState.value
          : this.controlState,
      laterState: data.laterState.present
          ? data.laterState.value
          : this.laterState,
      listUnsubscribe: data.listUnsubscribe.present
          ? data.listUnsubscribe.value
          : this.listUnsubscribe,
      controlReplied: data.controlReplied.present
          ? data.controlReplied.value
          : this.controlReplied,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      isFlagged: data.isFlagged.present ? data.isFlagged.value : this.isFlagged,
      isDraft: data.isDraft.present ? data.isDraft.value : this.isDraft,
      isReplied: data.isReplied.present ? data.isReplied.value : this.isReplied,
      isForwarded: data.isForwarded.present
          ? data.isForwarded.value
          : this.isForwarded,
      hasAttachments: data.hasAttachments.present
          ? data.hasAttachments.value
          : this.hasAttachments,
      priority: data.priority.present ? data.priority.value : this.priority,
      status: data.status.present ? data.status.value : this.status,
      tagsStr: data.tagsStr.present ? data.tagsStr.value : this.tagsStr,
      categoriesStr: data.categoriesStr.present
          ? data.categoriesStr.value
          : this.categoriesStr,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      sensitivity: data.sensitivity.present
          ? data.sensitivity.value
          : this.sensitivity,
      sentimentScore: data.sentimentScore.present
          ? data.sentimentScore.value
          : this.sentimentScore,
      aiCategory: data.aiCategory.present
          ? data.aiCategory.value
          : this.aiCategory,
      aiRecommendation: data.aiRecommendation.present
          ? data.aiRecommendation.value
          : this.aiRecommendation,
      extractedDeadline: data.extractedDeadline.present
          ? data.extractedDeadline.value
          : this.extractedDeadline,
      size: data.size.present ? data.size.value : this.size,
      readReceiptRequested: data.readReceiptRequested.present
          ? data.readReceiptRequested.value
          : this.readReceiptRequested,
      isLocallyModified: data.isLocallyModified.present
          ? data.isLocallyModified.value
          : this.isLocallyModified,
      loadedLevel: data.loadedLevel.present
          ? data.loadedLevel.value
          : this.loadedLevel,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Email(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('folderId: $folderId, ')
          ..write('folderName: $folderName, ')
          ..write('conversationId: $conversationId, ')
          ..write('parentId: $parentId, ')
          ..write('internetMessageId: $internetMessageId, ')
          ..write('referencesStr: $referencesStr, ')
          ..write('fromEmail: $fromEmail, ')
          ..write('fromName: $fromName, ')
          ..write('toRecipients: $toRecipients, ')
          ..write('ccJson: $ccJson, ')
          ..write('bccJson: $bccJson, ')
          ..write('replyToEmail: $replyToEmail, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('bodyHtml: $bodyHtml, ')
          ..write('bodyPreview: $bodyPreview, ')
          ..write('authResults: $authResults, ')
          ..write('meetingJson: $meetingJson, ')
          ..write('remindAt: $remindAt, ')
          ..write('followUpAt: $followUpAt, ')
          ..write('controlState: $controlState, ')
          ..write('laterState: $laterState, ')
          ..write('listUnsubscribe: $listUnsubscribe, ')
          ..write('controlReplied: $controlReplied, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('isRead: $isRead, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isDraft: $isDraft, ')
          ..write('isReplied: $isReplied, ')
          ..write('isForwarded: $isForwarded, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('tagsStr: $tagsStr, ')
          ..write('categoriesStr: $categoriesStr, ')
          ..write('classification: $classification, ')
          ..write('sensitivity: $sensitivity, ')
          ..write('sentimentScore: $sentimentScore, ')
          ..write('aiCategory: $aiCategory, ')
          ..write('aiRecommendation: $aiRecommendation, ')
          ..write('extractedDeadline: $extractedDeadline, ')
          ..write('size: $size, ')
          ..write('readReceiptRequested: $readReceiptRequested, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('loadedLevel: $loadedLevel, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    accountId,
    folderId,
    folderName,
    conversationId,
    parentId,
    internetMessageId,
    referencesStr,
    fromEmail,
    fromName,
    toRecipients,
    ccJson,
    bccJson,
    replyToEmail,
    subject,
    bodyPlain,
    bodyHtml,
    bodyPreview,
    authResults,
    meetingJson,
    remindAt,
    followUpAt,
    controlState,
    laterState,
    listUnsubscribe,
    controlReplied,
    attachmentsJson,
    receivedAt,
    sentAt,
    isRead,
    isFlagged,
    isDraft,
    isReplied,
    isForwarded,
    hasAttachments,
    priority,
    status,
    tagsStr,
    categoriesStr,
    classification,
    sensitivity,
    sentimentScore,
    aiCategory,
    aiRecommendation,
    extractedDeadline,
    size,
    readReceiptRequested,
    isLocallyModified,
    loadedLevel,
    cachedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Email &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.folderId == this.folderId &&
          other.folderName == this.folderName &&
          other.conversationId == this.conversationId &&
          other.parentId == this.parentId &&
          other.internetMessageId == this.internetMessageId &&
          other.referencesStr == this.referencesStr &&
          other.fromEmail == this.fromEmail &&
          other.fromName == this.fromName &&
          other.toRecipients == this.toRecipients &&
          other.ccJson == this.ccJson &&
          other.bccJson == this.bccJson &&
          other.replyToEmail == this.replyToEmail &&
          other.subject == this.subject &&
          other.bodyPlain == this.bodyPlain &&
          other.bodyHtml == this.bodyHtml &&
          other.bodyPreview == this.bodyPreview &&
          other.authResults == this.authResults &&
          other.meetingJson == this.meetingJson &&
          other.remindAt == this.remindAt &&
          other.followUpAt == this.followUpAt &&
          other.controlState == this.controlState &&
          other.laterState == this.laterState &&
          other.listUnsubscribe == this.listUnsubscribe &&
          other.controlReplied == this.controlReplied &&
          other.attachmentsJson == this.attachmentsJson &&
          other.receivedAt == this.receivedAt &&
          other.sentAt == this.sentAt &&
          other.isRead == this.isRead &&
          other.isFlagged == this.isFlagged &&
          other.isDraft == this.isDraft &&
          other.isReplied == this.isReplied &&
          other.isForwarded == this.isForwarded &&
          other.hasAttachments == this.hasAttachments &&
          other.priority == this.priority &&
          other.status == this.status &&
          other.tagsStr == this.tagsStr &&
          other.categoriesStr == this.categoriesStr &&
          other.classification == this.classification &&
          other.sensitivity == this.sensitivity &&
          other.sentimentScore == this.sentimentScore &&
          other.aiCategory == this.aiCategory &&
          other.aiRecommendation == this.aiRecommendation &&
          other.extractedDeadline == this.extractedDeadline &&
          other.size == this.size &&
          other.readReceiptRequested == this.readReceiptRequested &&
          other.isLocallyModified == this.isLocallyModified &&
          other.loadedLevel == this.loadedLevel &&
          other.cachedAt == this.cachedAt);
}

class EmailsCompanion extends UpdateCompanion<Email> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> folderId;
  final Value<String?> folderName;
  final Value<String?> conversationId;
  final Value<String?> parentId;
  final Value<String?> internetMessageId;
  final Value<String?> referencesStr;
  final Value<String> fromEmail;
  final Value<String?> fromName;
  final Value<String> toRecipients;
  final Value<String?> ccJson;
  final Value<String?> bccJson;
  final Value<String?> replyToEmail;
  final Value<String> subject;
  final Value<String?> bodyPlain;
  final Value<String?> bodyHtml;
  final Value<String?> bodyPreview;
  final Value<String?> authResults;
  final Value<String?> meetingJson;
  final Value<DateTime?> remindAt;
  final Value<DateTime?> followUpAt;
  final Value<int> controlState;
  final Value<int> laterState;
  final Value<String?> listUnsubscribe;
  final Value<String?> controlReplied;
  final Value<String?> attachmentsJson;
  final Value<DateTime> receivedAt;
  final Value<DateTime?> sentAt;
  final Value<bool> isRead;
  final Value<bool> isFlagged;
  final Value<bool> isDraft;
  final Value<bool> isReplied;
  final Value<bool> isForwarded;
  final Value<bool> hasAttachments;
  final Value<int> priority;
  final Value<int> status;
  final Value<String?> tagsStr;
  final Value<String?> categoriesStr;
  final Value<String?> classification;
  final Value<String?> sensitivity;
  final Value<double?> sentimentScore;
  final Value<String?> aiCategory;
  final Value<String?> aiRecommendation;
  final Value<DateTime?> extractedDeadline;
  final Value<int?> size;
  final Value<bool> readReceiptRequested;
  final Value<bool> isLocallyModified;
  final Value<int> loadedLevel;
  final Value<DateTime?> cachedAt;
  final Value<int> rowid;
  const EmailsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.folderName = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.internetMessageId = const Value.absent(),
    this.referencesStr = const Value.absent(),
    this.fromEmail = const Value.absent(),
    this.fromName = const Value.absent(),
    this.toRecipients = const Value.absent(),
    this.ccJson = const Value.absent(),
    this.bccJson = const Value.absent(),
    this.replyToEmail = const Value.absent(),
    this.subject = const Value.absent(),
    this.bodyPlain = const Value.absent(),
    this.bodyHtml = const Value.absent(),
    this.bodyPreview = const Value.absent(),
    this.authResults = const Value.absent(),
    this.meetingJson = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.followUpAt = const Value.absent(),
    this.controlState = const Value.absent(),
    this.laterState = const Value.absent(),
    this.listUnsubscribe = const Value.absent(),
    this.controlReplied = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isDraft = const Value.absent(),
    this.isReplied = const Value.absent(),
    this.isForwarded = const Value.absent(),
    this.hasAttachments = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.tagsStr = const Value.absent(),
    this.categoriesStr = const Value.absent(),
    this.classification = const Value.absent(),
    this.sensitivity = const Value.absent(),
    this.sentimentScore = const Value.absent(),
    this.aiCategory = const Value.absent(),
    this.aiRecommendation = const Value.absent(),
    this.extractedDeadline = const Value.absent(),
    this.size = const Value.absent(),
    this.readReceiptRequested = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.loadedLevel = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmailsCompanion.insert({
    required String id,
    required String accountId,
    required String folderId,
    this.folderName = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.internetMessageId = const Value.absent(),
    this.referencesStr = const Value.absent(),
    required String fromEmail,
    this.fromName = const Value.absent(),
    required String toRecipients,
    this.ccJson = const Value.absent(),
    this.bccJson = const Value.absent(),
    this.replyToEmail = const Value.absent(),
    required String subject,
    this.bodyPlain = const Value.absent(),
    this.bodyHtml = const Value.absent(),
    this.bodyPreview = const Value.absent(),
    this.authResults = const Value.absent(),
    this.meetingJson = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.followUpAt = const Value.absent(),
    this.controlState = const Value.absent(),
    this.laterState = const Value.absent(),
    this.listUnsubscribe = const Value.absent(),
    this.controlReplied = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    required DateTime receivedAt,
    this.sentAt = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isDraft = const Value.absent(),
    this.isReplied = const Value.absent(),
    this.isForwarded = const Value.absent(),
    this.hasAttachments = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.tagsStr = const Value.absent(),
    this.categoriesStr = const Value.absent(),
    this.classification = const Value.absent(),
    this.sensitivity = const Value.absent(),
    this.sentimentScore = const Value.absent(),
    this.aiCategory = const Value.absent(),
    this.aiRecommendation = const Value.absent(),
    this.extractedDeadline = const Value.absent(),
    this.size = const Value.absent(),
    this.readReceiptRequested = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.loadedLevel = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       folderId = Value(folderId),
       fromEmail = Value(fromEmail),
       toRecipients = Value(toRecipients),
       subject = Value(subject),
       receivedAt = Value(receivedAt);
  static Insertable<Email> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? folderId,
    Expression<String>? folderName,
    Expression<String>? conversationId,
    Expression<String>? parentId,
    Expression<String>? internetMessageId,
    Expression<String>? referencesStr,
    Expression<String>? fromEmail,
    Expression<String>? fromName,
    Expression<String>? toRecipients,
    Expression<String>? ccJson,
    Expression<String>? bccJson,
    Expression<String>? replyToEmail,
    Expression<String>? subject,
    Expression<String>? bodyPlain,
    Expression<String>? bodyHtml,
    Expression<String>? bodyPreview,
    Expression<String>? authResults,
    Expression<String>? meetingJson,
    Expression<DateTime>? remindAt,
    Expression<DateTime>? followUpAt,
    Expression<int>? controlState,
    Expression<int>? laterState,
    Expression<String>? listUnsubscribe,
    Expression<String>? controlReplied,
    Expression<String>? attachmentsJson,
    Expression<DateTime>? receivedAt,
    Expression<DateTime>? sentAt,
    Expression<bool>? isRead,
    Expression<bool>? isFlagged,
    Expression<bool>? isDraft,
    Expression<bool>? isReplied,
    Expression<bool>? isForwarded,
    Expression<bool>? hasAttachments,
    Expression<int>? priority,
    Expression<int>? status,
    Expression<String>? tagsStr,
    Expression<String>? categoriesStr,
    Expression<String>? classification,
    Expression<String>? sensitivity,
    Expression<double>? sentimentScore,
    Expression<String>? aiCategory,
    Expression<String>? aiRecommendation,
    Expression<DateTime>? extractedDeadline,
    Expression<int>? size,
    Expression<bool>? readReceiptRequested,
    Expression<bool>? isLocallyModified,
    Expression<int>? loadedLevel,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (folderId != null) 'folder_id': folderId,
      if (folderName != null) 'folder_name': folderName,
      if (conversationId != null) 'conversation_id': conversationId,
      if (parentId != null) 'parent_id': parentId,
      if (internetMessageId != null) 'internet_message_id': internetMessageId,
      if (referencesStr != null) 'references_str': referencesStr,
      if (fromEmail != null) 'from_email': fromEmail,
      if (fromName != null) 'from_name': fromName,
      if (toRecipients != null) 'to_recipients': toRecipients,
      if (ccJson != null) 'cc_json': ccJson,
      if (bccJson != null) 'bcc_json': bccJson,
      if (replyToEmail != null) 'reply_to_email': replyToEmail,
      if (subject != null) 'subject': subject,
      if (bodyPlain != null) 'body_plain': bodyPlain,
      if (bodyHtml != null) 'body_html': bodyHtml,
      if (bodyPreview != null) 'body_preview': bodyPreview,
      if (authResults != null) 'auth_results': authResults,
      if (meetingJson != null) 'meeting_json': meetingJson,
      if (remindAt != null) 'remind_at': remindAt,
      if (followUpAt != null) 'follow_up_at': followUpAt,
      if (controlState != null) 'control_state': controlState,
      if (laterState != null) 'later_state': laterState,
      if (listUnsubscribe != null) 'list_unsubscribe': listUnsubscribe,
      if (controlReplied != null) 'control_replied': controlReplied,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (receivedAt != null) 'received_at': receivedAt,
      if (sentAt != null) 'sent_at': sentAt,
      if (isRead != null) 'is_read': isRead,
      if (isFlagged != null) 'is_flagged': isFlagged,
      if (isDraft != null) 'is_draft': isDraft,
      if (isReplied != null) 'is_replied': isReplied,
      if (isForwarded != null) 'is_forwarded': isForwarded,
      if (hasAttachments != null) 'has_attachments': hasAttachments,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (tagsStr != null) 'tags_str': tagsStr,
      if (categoriesStr != null) 'categories_str': categoriesStr,
      if (classification != null) 'classification': classification,
      if (sensitivity != null) 'sensitivity': sensitivity,
      if (sentimentScore != null) 'sentiment_score': sentimentScore,
      if (aiCategory != null) 'ai_category': aiCategory,
      if (aiRecommendation != null) 'ai_recommendation': aiRecommendation,
      if (extractedDeadline != null) 'extracted_deadline': extractedDeadline,
      if (size != null) 'size': size,
      if (readReceiptRequested != null)
        'read_receipt_requested': readReceiptRequested,
      if (isLocallyModified != null) 'is_locally_modified': isLocallyModified,
      if (loadedLevel != null) 'loaded_level': loadedLevel,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmailsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? folderId,
    Value<String?>? folderName,
    Value<String?>? conversationId,
    Value<String?>? parentId,
    Value<String?>? internetMessageId,
    Value<String?>? referencesStr,
    Value<String>? fromEmail,
    Value<String?>? fromName,
    Value<String>? toRecipients,
    Value<String?>? ccJson,
    Value<String?>? bccJson,
    Value<String?>? replyToEmail,
    Value<String>? subject,
    Value<String?>? bodyPlain,
    Value<String?>? bodyHtml,
    Value<String?>? bodyPreview,
    Value<String?>? authResults,
    Value<String?>? meetingJson,
    Value<DateTime?>? remindAt,
    Value<DateTime?>? followUpAt,
    Value<int>? controlState,
    Value<int>? laterState,
    Value<String?>? listUnsubscribe,
    Value<String?>? controlReplied,
    Value<String?>? attachmentsJson,
    Value<DateTime>? receivedAt,
    Value<DateTime?>? sentAt,
    Value<bool>? isRead,
    Value<bool>? isFlagged,
    Value<bool>? isDraft,
    Value<bool>? isReplied,
    Value<bool>? isForwarded,
    Value<bool>? hasAttachments,
    Value<int>? priority,
    Value<int>? status,
    Value<String?>? tagsStr,
    Value<String?>? categoriesStr,
    Value<String?>? classification,
    Value<String?>? sensitivity,
    Value<double?>? sentimentScore,
    Value<String?>? aiCategory,
    Value<String?>? aiRecommendation,
    Value<DateTime?>? extractedDeadline,
    Value<int?>? size,
    Value<bool>? readReceiptRequested,
    Value<bool>? isLocallyModified,
    Value<int>? loadedLevel,
    Value<DateTime?>? cachedAt,
    Value<int>? rowid,
  }) {
    return EmailsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      folderId: folderId ?? this.folderId,
      folderName: folderName ?? this.folderName,
      conversationId: conversationId ?? this.conversationId,
      parentId: parentId ?? this.parentId,
      internetMessageId: internetMessageId ?? this.internetMessageId,
      referencesStr: referencesStr ?? this.referencesStr,
      fromEmail: fromEmail ?? this.fromEmail,
      fromName: fromName ?? this.fromName,
      toRecipients: toRecipients ?? this.toRecipients,
      ccJson: ccJson ?? this.ccJson,
      bccJson: bccJson ?? this.bccJson,
      replyToEmail: replyToEmail ?? this.replyToEmail,
      subject: subject ?? this.subject,
      bodyPlain: bodyPlain ?? this.bodyPlain,
      bodyHtml: bodyHtml ?? this.bodyHtml,
      bodyPreview: bodyPreview ?? this.bodyPreview,
      authResults: authResults ?? this.authResults,
      meetingJson: meetingJson ?? this.meetingJson,
      remindAt: remindAt ?? this.remindAt,
      followUpAt: followUpAt ?? this.followUpAt,
      controlState: controlState ?? this.controlState,
      laterState: laterState ?? this.laterState,
      listUnsubscribe: listUnsubscribe ?? this.listUnsubscribe,
      controlReplied: controlReplied ?? this.controlReplied,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      receivedAt: receivedAt ?? this.receivedAt,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      isFlagged: isFlagged ?? this.isFlagged,
      isDraft: isDraft ?? this.isDraft,
      isReplied: isReplied ?? this.isReplied,
      isForwarded: isForwarded ?? this.isForwarded,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      tagsStr: tagsStr ?? this.tagsStr,
      categoriesStr: categoriesStr ?? this.categoriesStr,
      classification: classification ?? this.classification,
      sensitivity: sensitivity ?? this.sensitivity,
      sentimentScore: sentimentScore ?? this.sentimentScore,
      aiCategory: aiCategory ?? this.aiCategory,
      aiRecommendation: aiRecommendation ?? this.aiRecommendation,
      extractedDeadline: extractedDeadline ?? this.extractedDeadline,
      size: size ?? this.size,
      readReceiptRequested: readReceiptRequested ?? this.readReceiptRequested,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      loadedLevel: loadedLevel ?? this.loadedLevel,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (folderName.present) {
      map['folder_name'] = Variable<String>(folderName.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (internetMessageId.present) {
      map['internet_message_id'] = Variable<String>(internetMessageId.value);
    }
    if (referencesStr.present) {
      map['references_str'] = Variable<String>(referencesStr.value);
    }
    if (fromEmail.present) {
      map['from_email'] = Variable<String>(fromEmail.value);
    }
    if (fromName.present) {
      map['from_name'] = Variable<String>(fromName.value);
    }
    if (toRecipients.present) {
      map['to_recipients'] = Variable<String>(toRecipients.value);
    }
    if (ccJson.present) {
      map['cc_json'] = Variable<String>(ccJson.value);
    }
    if (bccJson.present) {
      map['bcc_json'] = Variable<String>(bccJson.value);
    }
    if (replyToEmail.present) {
      map['reply_to_email'] = Variable<String>(replyToEmail.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (bodyPlain.present) {
      map['body_plain'] = Variable<String>(bodyPlain.value);
    }
    if (bodyHtml.present) {
      map['body_html'] = Variable<String>(bodyHtml.value);
    }
    if (bodyPreview.present) {
      map['body_preview'] = Variable<String>(bodyPreview.value);
    }
    if (authResults.present) {
      map['auth_results'] = Variable<String>(authResults.value);
    }
    if (meetingJson.present) {
      map['meeting_json'] = Variable<String>(meetingJson.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (followUpAt.present) {
      map['follow_up_at'] = Variable<DateTime>(followUpAt.value);
    }
    if (controlState.present) {
      map['control_state'] = Variable<int>(controlState.value);
    }
    if (laterState.present) {
      map['later_state'] = Variable<int>(laterState.value);
    }
    if (listUnsubscribe.present) {
      map['list_unsubscribe'] = Variable<String>(listUnsubscribe.value);
    }
    if (controlReplied.present) {
      map['control_replied'] = Variable<String>(controlReplied.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (isFlagged.present) {
      map['is_flagged'] = Variable<bool>(isFlagged.value);
    }
    if (isDraft.present) {
      map['is_draft'] = Variable<bool>(isDraft.value);
    }
    if (isReplied.present) {
      map['is_replied'] = Variable<bool>(isReplied.value);
    }
    if (isForwarded.present) {
      map['is_forwarded'] = Variable<bool>(isForwarded.value);
    }
    if (hasAttachments.present) {
      map['has_attachments'] = Variable<bool>(hasAttachments.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (tagsStr.present) {
      map['tags_str'] = Variable<String>(tagsStr.value);
    }
    if (categoriesStr.present) {
      map['categories_str'] = Variable<String>(categoriesStr.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (sensitivity.present) {
      map['sensitivity'] = Variable<String>(sensitivity.value);
    }
    if (sentimentScore.present) {
      map['sentiment_score'] = Variable<double>(sentimentScore.value);
    }
    if (aiCategory.present) {
      map['ai_category'] = Variable<String>(aiCategory.value);
    }
    if (aiRecommendation.present) {
      map['ai_recommendation'] = Variable<String>(aiRecommendation.value);
    }
    if (extractedDeadline.present) {
      map['extracted_deadline'] = Variable<DateTime>(extractedDeadline.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (readReceiptRequested.present) {
      map['read_receipt_requested'] = Variable<bool>(
        readReceiptRequested.value,
      );
    }
    if (isLocallyModified.present) {
      map['is_locally_modified'] = Variable<bool>(isLocallyModified.value);
    }
    if (loadedLevel.present) {
      map['loaded_level'] = Variable<int>(loadedLevel.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmailsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('folderId: $folderId, ')
          ..write('folderName: $folderName, ')
          ..write('conversationId: $conversationId, ')
          ..write('parentId: $parentId, ')
          ..write('internetMessageId: $internetMessageId, ')
          ..write('referencesStr: $referencesStr, ')
          ..write('fromEmail: $fromEmail, ')
          ..write('fromName: $fromName, ')
          ..write('toRecipients: $toRecipients, ')
          ..write('ccJson: $ccJson, ')
          ..write('bccJson: $bccJson, ')
          ..write('replyToEmail: $replyToEmail, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('bodyHtml: $bodyHtml, ')
          ..write('bodyPreview: $bodyPreview, ')
          ..write('authResults: $authResults, ')
          ..write('meetingJson: $meetingJson, ')
          ..write('remindAt: $remindAt, ')
          ..write('followUpAt: $followUpAt, ')
          ..write('controlState: $controlState, ')
          ..write('laterState: $laterState, ')
          ..write('listUnsubscribe: $listUnsubscribe, ')
          ..write('controlReplied: $controlReplied, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('isRead: $isRead, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isDraft: $isDraft, ')
          ..write('isReplied: $isReplied, ')
          ..write('isForwarded: $isForwarded, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('tagsStr: $tagsStr, ')
          ..write('categoriesStr: $categoriesStr, ')
          ..write('classification: $classification, ')
          ..write('sensitivity: $sensitivity, ')
          ..write('sentimentScore: $sentimentScore, ')
          ..write('aiCategory: $aiCategory, ')
          ..write('aiRecommendation: $aiRecommendation, ')
          ..write('extractedDeadline: $extractedDeadline, ')
          ..write('size: $size, ')
          ..write('readReceiptRequested: $readReceiptRequested, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('loadedLevel: $loadedLevel, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(7),
  );
  static const VerificationMeta _serverPathMeta = const VerificationMeta(
    'serverPath',
  );
  @override
  late final GeneratedColumn<String> serverPath = GeneratedColumn<String>(
    'server_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalCountMeta = const VerificationMeta(
    'totalCount',
  );
  @override
  late final GeneratedColumn<int> totalCount = GeneratedColumn<int>(
    'total_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _showInUnifiedMeta = const VerificationMeta(
    'showInUnified',
  );
  @override
  late final GeneratedColumn<bool> showInUnified = GeneratedColumn<bool>(
    'show_in_unified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_in_unified" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _iconNameMeta = const VerificationMeta(
    'iconName',
  );
  @override
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
    'icon_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    parentId,
    displayName,
    type,
    serverPath,
    unreadCount,
    totalCount,
    showInUnified,
    isFavorite,
    sortOrder,
    isSynced,
    iconName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('server_path')) {
      context.handle(
        _serverPathMeta,
        serverPath.isAcceptableOrUnknown(data['server_path']!, _serverPathMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('total_count')) {
      context.handle(
        _totalCountMeta,
        totalCount.isAcceptableOrUnknown(data['total_count']!, _totalCountMeta),
      );
    }
    if (data.containsKey('show_in_unified')) {
      context.handle(
        _showInUnifiedMeta,
        showInUnified.isAcceptableOrUnknown(
          data['show_in_unified']!,
          _showInUnifiedMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    if (data.containsKey('icon_name')) {
      context.handle(
        _iconNameMeta,
        iconName.isAcceptableOrUnknown(data['icon_name']!, _iconNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, accountId};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      serverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_path'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      totalCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_count'],
      )!,
      showInUnified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_in_unified'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      iconName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_name'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final String id;
  final String accountId;
  final String? parentId;
  final String displayName;
  final int type;
  final String? serverPath;
  final int unreadCount;
  final int totalCount;
  final bool showInUnified;
  final bool isFavorite;
  final int sortOrder;
  final bool isSynced;
  final String? iconName;
  const Folder({
    required this.id,
    required this.accountId,
    this.parentId,
    required this.displayName,
    required this.type,
    this.serverPath,
    required this.unreadCount,
    required this.totalCount,
    required this.showInUnified,
    required this.isFavorite,
    required this.sortOrder,
    required this.isSynced,
    this.iconName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['display_name'] = Variable<String>(displayName);
    map['type'] = Variable<int>(type);
    if (!nullToAbsent || serverPath != null) {
      map['server_path'] = Variable<String>(serverPath);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['total_count'] = Variable<int>(totalCount);
    map['show_in_unified'] = Variable<bool>(showInUnified);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_synced'] = Variable<bool>(isSynced);
    if (!nullToAbsent || iconName != null) {
      map['icon_name'] = Variable<String>(iconName);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      accountId: Value(accountId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      displayName: Value(displayName),
      type: Value(type),
      serverPath: serverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(serverPath),
      unreadCount: Value(unreadCount),
      totalCount: Value(totalCount),
      showInUnified: Value(showInUnified),
      isFavorite: Value(isFavorite),
      sortOrder: Value(sortOrder),
      isSynced: Value(isSynced),
      iconName: iconName == null && nullToAbsent
          ? const Value.absent()
          : Value(iconName),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      type: serializer.fromJson<int>(json['type']),
      serverPath: serializer.fromJson<String?>(json['serverPath']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      totalCount: serializer.fromJson<int>(json['totalCount']),
      showInUnified: serializer.fromJson<bool>(json['showInUnified']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      iconName: serializer.fromJson<String?>(json['iconName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'parentId': serializer.toJson<String?>(parentId),
      'displayName': serializer.toJson<String>(displayName),
      'type': serializer.toJson<int>(type),
      'serverPath': serializer.toJson<String?>(serverPath),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'totalCount': serializer.toJson<int>(totalCount),
      'showInUnified': serializer.toJson<bool>(showInUnified),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isSynced': serializer.toJson<bool>(isSynced),
      'iconName': serializer.toJson<String?>(iconName),
    };
  }

  Folder copyWith({
    String? id,
    String? accountId,
    Value<String?> parentId = const Value.absent(),
    String? displayName,
    int? type,
    Value<String?> serverPath = const Value.absent(),
    int? unreadCount,
    int? totalCount,
    bool? showInUnified,
    bool? isFavorite,
    int? sortOrder,
    bool? isSynced,
    Value<String?> iconName = const Value.absent(),
  }) => Folder(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    parentId: parentId.present ? parentId.value : this.parentId,
    displayName: displayName ?? this.displayName,
    type: type ?? this.type,
    serverPath: serverPath.present ? serverPath.value : this.serverPath,
    unreadCount: unreadCount ?? this.unreadCount,
    totalCount: totalCount ?? this.totalCount,
    showInUnified: showInUnified ?? this.showInUnified,
    isFavorite: isFavorite ?? this.isFavorite,
    sortOrder: sortOrder ?? this.sortOrder,
    isSynced: isSynced ?? this.isSynced,
    iconName: iconName.present ? iconName.value : this.iconName,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      type: data.type.present ? data.type.value : this.type,
      serverPath: data.serverPath.present
          ? data.serverPath.value
          : this.serverPath,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      totalCount: data.totalCount.present
          ? data.totalCount.value
          : this.totalCount,
      showInUnified: data.showInUnified.present
          ? data.showInUnified.value
          : this.showInUnified,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      iconName: data.iconName.present ? data.iconName.value : this.iconName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('parentId: $parentId, ')
          ..write('displayName: $displayName, ')
          ..write('type: $type, ')
          ..write('serverPath: $serverPath, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('totalCount: $totalCount, ')
          ..write('showInUnified: $showInUnified, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isSynced: $isSynced, ')
          ..write('iconName: $iconName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    parentId,
    displayName,
    type,
    serverPath,
    unreadCount,
    totalCount,
    showInUnified,
    isFavorite,
    sortOrder,
    isSynced,
    iconName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.parentId == this.parentId &&
          other.displayName == this.displayName &&
          other.type == this.type &&
          other.serverPath == this.serverPath &&
          other.unreadCount == this.unreadCount &&
          other.totalCount == this.totalCount &&
          other.showInUnified == this.showInUnified &&
          other.isFavorite == this.isFavorite &&
          other.sortOrder == this.sortOrder &&
          other.isSynced == this.isSynced &&
          other.iconName == this.iconName);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String?> parentId;
  final Value<String> displayName;
  final Value<int> type;
  final Value<String?> serverPath;
  final Value<int> unreadCount;
  final Value<int> totalCount;
  final Value<bool> showInUnified;
  final Value<bool> isFavorite;
  final Value<int> sortOrder;
  final Value<bool> isSynced;
  final Value<String?> iconName;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.type = const Value.absent(),
    this.serverPath = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.totalCount = const Value.absent(),
    this.showInUnified = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.iconName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    required String accountId,
    this.parentId = const Value.absent(),
    required String displayName,
    this.type = const Value.absent(),
    this.serverPath = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.totalCount = const Value.absent(),
    this.showInUnified = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.iconName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       displayName = Value(displayName);
  static Insertable<Folder> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? parentId,
    Expression<String>? displayName,
    Expression<int>? type,
    Expression<String>? serverPath,
    Expression<int>? unreadCount,
    Expression<int>? totalCount,
    Expression<bool>? showInUnified,
    Expression<bool>? isFavorite,
    Expression<int>? sortOrder,
    Expression<bool>? isSynced,
    Expression<String>? iconName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (parentId != null) 'parent_id': parentId,
      if (displayName != null) 'display_name': displayName,
      if (type != null) 'type': type,
      if (serverPath != null) 'server_path': serverPath,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (totalCount != null) 'total_count': totalCount,
      if (showInUnified != null) 'show_in_unified': showInUnified,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isSynced != null) 'is_synced': isSynced,
      if (iconName != null) 'icon_name': iconName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String?>? parentId,
    Value<String>? displayName,
    Value<int>? type,
    Value<String?>? serverPath,
    Value<int>? unreadCount,
    Value<int>? totalCount,
    Value<bool>? showInUnified,
    Value<bool>? isFavorite,
    Value<int>? sortOrder,
    Value<bool>? isSynced,
    Value<String?>? iconName,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      parentId: parentId ?? this.parentId,
      displayName: displayName ?? this.displayName,
      type: type ?? this.type,
      serverPath: serverPath ?? this.serverPath,
      unreadCount: unreadCount ?? this.unreadCount,
      totalCount: totalCount ?? this.totalCount,
      showInUnified: showInUnified ?? this.showInUnified,
      isFavorite: isFavorite ?? this.isFavorite,
      sortOrder: sortOrder ?? this.sortOrder,
      isSynced: isSynced ?? this.isSynced,
      iconName: iconName ?? this.iconName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (serverPath.present) {
      map['server_path'] = Variable<String>(serverPath.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (totalCount.present) {
      map['total_count'] = Variable<int>(totalCount.value);
    }
    if (showInUnified.present) {
      map['show_in_unified'] = Variable<bool>(showInUnified.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (iconName.present) {
      map['icon_name'] = Variable<String>(iconName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('parentId: $parentId, ')
          ..write('displayName: $displayName, ')
          ..write('type: $type, ')
          ..write('serverPath: $serverPath, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('totalCount: $totalCount, ')
          ..write('showInUnified: $showInUnified, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isSynced: $isSynced, ')
          ..write('iconName: $iconName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _additionalEmailsMeta = const VerificationMeta(
    'additionalEmails',
  );
  @override
  late final GeneratedColumn<String> additionalEmails = GeneratedColumn<String>(
    'additional_emails',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _middleNameMeta = const VerificationMeta(
    'middleName',
  );
  @override
  late final GeneratedColumn<String> middleName = GeneratedColumn<String>(
    'middle_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jobTitleMeta = const VerificationMeta(
    'jobTitle',
  );
  @override
  late final GeneratedColumn<String> jobTitle = GeneratedColumn<String>(
    'job_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _departmentMeta = const VerificationMeta(
    'department',
  );
  @override
  late final GeneratedColumn<String> department = GeneratedColumn<String>(
    'department',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _companyMeta = const VerificationMeta(
    'company',
  );
  @override
  late final GeneratedColumn<String> company = GeneratedColumn<String>(
    'company',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneWorkMeta = const VerificationMeta(
    'phoneWork',
  );
  @override
  late final GeneratedColumn<String> phoneWork = GeneratedColumn<String>(
    'phone_work',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMobileMeta = const VerificationMeta(
    'phoneMobile',
  );
  @override
  late final GeneratedColumn<String> phoneMobile = GeneratedColumn<String>(
    'phone_mobile',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneExtensionMeta = const VerificationMeta(
    'phoneExtension',
  );
  @override
  late final GeneratedColumn<String> phoneExtension = GeneratedColumn<String>(
    'phone_extension',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _officeMeta = const VerificationMeta('office');
  @override
  late final GeneratedColumn<String> office = GeneratedColumn<String>(
    'office',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _managerMeta = const VerificationMeta(
    'manager',
  );
  @override
  late final GeneratedColumn<String> manager = GeneratedColumn<String>(
    'manager',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  @override
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
    'city',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<int> source = GeneratedColumn<int>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isVipMeta = const VerificationMeta('isVip');
  @override
  late final GeneratedColumn<bool> isVip = GeneratedColumn<bool>(
    'is_vip',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_vip" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _interactionCountMeta = const VerificationMeta(
    'interactionCount',
  );
  @override
  late final GeneratedColumn<int> interactionCount = GeneratedColumn<int>(
    'interaction_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastInteractionMeta = const VerificationMeta(
    'lastInteraction',
  );
  @override
  late final GeneratedColumn<DateTime> lastInteraction =
      GeneratedColumn<DateTime>(
        'last_interaction',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthdayMeta = const VerificationMeta(
    'birthday',
  );
  @override
  late final GeneratedColumn<DateTime> birthday = GeneratedColumn<DateTime>(
    'birthday',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirCheckedAtMeta = const VerificationMeta(
    'dirCheckedAt',
  );
  @override
  late final GeneratedColumn<DateTime> dirCheckedAt = GeneratedColumn<DateTime>(
    'dir_checked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirOrgMeta = const VerificationMeta('dirOrg');
  @override
  late final GeneratedColumn<String> dirOrg = GeneratedColumn<String>(
    'dir_org',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    email,
    additionalEmails,
    displayName,
    firstName,
    middleName,
    lastName,
    jobTitle,
    department,
    company,
    phoneWork,
    phoneMobile,
    phoneExtension,
    office,
    manager,
    city,
    avatarPath,
    avatarUrl,
    source,
    isFavorite,
    isVip,
    interactionCount,
    lastInteraction,
    notes,
    birthday,
    dirCheckedAt,
    dirOrg,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Contact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('additional_emails')) {
      context.handle(
        _additionalEmailsMeta,
        additionalEmails.isAcceptableOrUnknown(
          data['additional_emails']!,
          _additionalEmailsMeta,
        ),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    }
    if (data.containsKey('middle_name')) {
      context.handle(
        _middleNameMeta,
        middleName.isAcceptableOrUnknown(data['middle_name']!, _middleNameMeta),
      );
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('job_title')) {
      context.handle(
        _jobTitleMeta,
        jobTitle.isAcceptableOrUnknown(data['job_title']!, _jobTitleMeta),
      );
    }
    if (data.containsKey('department')) {
      context.handle(
        _departmentMeta,
        department.isAcceptableOrUnknown(data['department']!, _departmentMeta),
      );
    }
    if (data.containsKey('company')) {
      context.handle(
        _companyMeta,
        company.isAcceptableOrUnknown(data['company']!, _companyMeta),
      );
    }
    if (data.containsKey('phone_work')) {
      context.handle(
        _phoneWorkMeta,
        phoneWork.isAcceptableOrUnknown(data['phone_work']!, _phoneWorkMeta),
      );
    }
    if (data.containsKey('phone_mobile')) {
      context.handle(
        _phoneMobileMeta,
        phoneMobile.isAcceptableOrUnknown(
          data['phone_mobile']!,
          _phoneMobileMeta,
        ),
      );
    }
    if (data.containsKey('phone_extension')) {
      context.handle(
        _phoneExtensionMeta,
        phoneExtension.isAcceptableOrUnknown(
          data['phone_extension']!,
          _phoneExtensionMeta,
        ),
      );
    }
    if (data.containsKey('office')) {
      context.handle(
        _officeMeta,
        office.isAcceptableOrUnknown(data['office']!, _officeMeta),
      );
    }
    if (data.containsKey('manager')) {
      context.handle(
        _managerMeta,
        manager.isAcceptableOrUnknown(data['manager']!, _managerMeta),
      );
    }
    if (data.containsKey('city')) {
      context.handle(
        _cityMeta,
        city.isAcceptableOrUnknown(data['city']!, _cityMeta),
      );
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('is_vip')) {
      context.handle(
        _isVipMeta,
        isVip.isAcceptableOrUnknown(data['is_vip']!, _isVipMeta),
      );
    }
    if (data.containsKey('interaction_count')) {
      context.handle(
        _interactionCountMeta,
        interactionCount.isAcceptableOrUnknown(
          data['interaction_count']!,
          _interactionCountMeta,
        ),
      );
    }
    if (data.containsKey('last_interaction')) {
      context.handle(
        _lastInteractionMeta,
        lastInteraction.isAcceptableOrUnknown(
          data['last_interaction']!,
          _lastInteractionMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('birthday')) {
      context.handle(
        _birthdayMeta,
        birthday.isAcceptableOrUnknown(data['birthday']!, _birthdayMeta),
      );
    }
    if (data.containsKey('dir_checked_at')) {
      context.handle(
        _dirCheckedAtMeta,
        dirCheckedAt.isAcceptableOrUnknown(
          data['dir_checked_at']!,
          _dirCheckedAtMeta,
        ),
      );
    }
    if (data.containsKey('dir_org')) {
      context.handle(
        _dirOrgMeta,
        dirOrg.isAcceptableOrUnknown(data['dir_org']!, _dirOrgMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, accountId};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      additionalEmails: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}additional_emails'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      ),
      middleName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}middle_name'],
      ),
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      jobTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_title'],
      ),
      department: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}department'],
      ),
      company: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company'],
      ),
      phoneWork: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_work'],
      ),
      phoneMobile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_mobile'],
      ),
      phoneExtension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_extension'],
      ),
      office: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}office'],
      ),
      manager: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manager'],
      ),
      city: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city'],
      ),
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      isVip: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_vip'],
      )!,
      interactionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interaction_count'],
      )!,
      lastInteraction: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_interaction'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      birthday: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birthday'],
      ),
      dirCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dir_checked_at'],
      ),
      dirOrg: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dir_org'],
      ),
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }
}

class Contact extends DataClass implements Insertable<Contact> {
  final String id;
  final String? accountId;
  final String email;
  final String? additionalEmails;
  final String displayName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? jobTitle;
  final String? department;
  final String? company;
  final String? phoneWork;
  final String? phoneMobile;
  final String? phoneExtension;
  final String? office;

  /// Руководитель (как в карточке Outlook): имя из адресной книги.
  final String? manager;
  final String? city;
  final String? avatarPath;
  final String? avatarUrl;
  final int source;
  final bool isFavorite;
  final bool isVip;
  final int interactionCount;
  final DateTime? lastInteraction;
  final String? notes;
  final DateTime? birthday;

  /// Коллеги (1.8.0+118): когда контакт сверялся с адресной книгой
  /// организации и что оттуда пришло — JSON `DirectoryOrg` (компания, отдел,
  /// должность, кабинет, руководитель, рабочий телефон). При синхронизации с
  /// сервером эти поля главнее копии в личных контактах, которая сама не
  /// обновляется (`lib/services/contacts/colleague_directory.dart`).
  final DateTime? dirCheckedAt;
  final String? dirOrg;
  const Contact({
    required this.id,
    this.accountId,
    required this.email,
    this.additionalEmails,
    required this.displayName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.jobTitle,
    this.department,
    this.company,
    this.phoneWork,
    this.phoneMobile,
    this.phoneExtension,
    this.office,
    this.manager,
    this.city,
    this.avatarPath,
    this.avatarUrl,
    required this.source,
    required this.isFavorite,
    required this.isVip,
    required this.interactionCount,
    this.lastInteraction,
    this.notes,
    this.birthday,
    this.dirCheckedAt,
    this.dirOrg,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || additionalEmails != null) {
      map['additional_emails'] = Variable<String>(additionalEmails);
    }
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || firstName != null) {
      map['first_name'] = Variable<String>(firstName);
    }
    if (!nullToAbsent || middleName != null) {
      map['middle_name'] = Variable<String>(middleName);
    }
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || jobTitle != null) {
      map['job_title'] = Variable<String>(jobTitle);
    }
    if (!nullToAbsent || department != null) {
      map['department'] = Variable<String>(department);
    }
    if (!nullToAbsent || company != null) {
      map['company'] = Variable<String>(company);
    }
    if (!nullToAbsent || phoneWork != null) {
      map['phone_work'] = Variable<String>(phoneWork);
    }
    if (!nullToAbsent || phoneMobile != null) {
      map['phone_mobile'] = Variable<String>(phoneMobile);
    }
    if (!nullToAbsent || phoneExtension != null) {
      map['phone_extension'] = Variable<String>(phoneExtension);
    }
    if (!nullToAbsent || office != null) {
      map['office'] = Variable<String>(office);
    }
    if (!nullToAbsent || manager != null) {
      map['manager'] = Variable<String>(manager);
    }
    if (!nullToAbsent || city != null) {
      map['city'] = Variable<String>(city);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['source'] = Variable<int>(source);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_vip'] = Variable<bool>(isVip);
    map['interaction_count'] = Variable<int>(interactionCount);
    if (!nullToAbsent || lastInteraction != null) {
      map['last_interaction'] = Variable<DateTime>(lastInteraction);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || birthday != null) {
      map['birthday'] = Variable<DateTime>(birthday);
    }
    if (!nullToAbsent || dirCheckedAt != null) {
      map['dir_checked_at'] = Variable<DateTime>(dirCheckedAt);
    }
    if (!nullToAbsent || dirOrg != null) {
      map['dir_org'] = Variable<String>(dirOrg);
    }
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      email: Value(email),
      additionalEmails: additionalEmails == null && nullToAbsent
          ? const Value.absent()
          : Value(additionalEmails),
      displayName: Value(displayName),
      firstName: firstName == null && nullToAbsent
          ? const Value.absent()
          : Value(firstName),
      middleName: middleName == null && nullToAbsent
          ? const Value.absent()
          : Value(middleName),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      jobTitle: jobTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(jobTitle),
      department: department == null && nullToAbsent
          ? const Value.absent()
          : Value(department),
      company: company == null && nullToAbsent
          ? const Value.absent()
          : Value(company),
      phoneWork: phoneWork == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneWork),
      phoneMobile: phoneMobile == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneMobile),
      phoneExtension: phoneExtension == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneExtension),
      office: office == null && nullToAbsent
          ? const Value.absent()
          : Value(office),
      manager: manager == null && nullToAbsent
          ? const Value.absent()
          : Value(manager),
      city: city == null && nullToAbsent ? const Value.absent() : Value(city),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      source: Value(source),
      isFavorite: Value(isFavorite),
      isVip: Value(isVip),
      interactionCount: Value(interactionCount),
      lastInteraction: lastInteraction == null && nullToAbsent
          ? const Value.absent()
          : Value(lastInteraction),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      birthday: birthday == null && nullToAbsent
          ? const Value.absent()
          : Value(birthday),
      dirCheckedAt: dirCheckedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dirCheckedAt),
      dirOrg: dirOrg == null && nullToAbsent
          ? const Value.absent()
          : Value(dirOrg),
    );
  }

  factory Contact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Contact(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      email: serializer.fromJson<String>(json['email']),
      additionalEmails: serializer.fromJson<String?>(json['additionalEmails']),
      displayName: serializer.fromJson<String>(json['displayName']),
      firstName: serializer.fromJson<String?>(json['firstName']),
      middleName: serializer.fromJson<String?>(json['middleName']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      jobTitle: serializer.fromJson<String?>(json['jobTitle']),
      department: serializer.fromJson<String?>(json['department']),
      company: serializer.fromJson<String?>(json['company']),
      phoneWork: serializer.fromJson<String?>(json['phoneWork']),
      phoneMobile: serializer.fromJson<String?>(json['phoneMobile']),
      phoneExtension: serializer.fromJson<String?>(json['phoneExtension']),
      office: serializer.fromJson<String?>(json['office']),
      manager: serializer.fromJson<String?>(json['manager']),
      city: serializer.fromJson<String?>(json['city']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      source: serializer.fromJson<int>(json['source']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isVip: serializer.fromJson<bool>(json['isVip']),
      interactionCount: serializer.fromJson<int>(json['interactionCount']),
      lastInteraction: serializer.fromJson<DateTime?>(json['lastInteraction']),
      notes: serializer.fromJson<String?>(json['notes']),
      birthday: serializer.fromJson<DateTime?>(json['birthday']),
      dirCheckedAt: serializer.fromJson<DateTime?>(json['dirCheckedAt']),
      dirOrg: serializer.fromJson<String?>(json['dirOrg']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'email': serializer.toJson<String>(email),
      'additionalEmails': serializer.toJson<String?>(additionalEmails),
      'displayName': serializer.toJson<String>(displayName),
      'firstName': serializer.toJson<String?>(firstName),
      'middleName': serializer.toJson<String?>(middleName),
      'lastName': serializer.toJson<String?>(lastName),
      'jobTitle': serializer.toJson<String?>(jobTitle),
      'department': serializer.toJson<String?>(department),
      'company': serializer.toJson<String?>(company),
      'phoneWork': serializer.toJson<String?>(phoneWork),
      'phoneMobile': serializer.toJson<String?>(phoneMobile),
      'phoneExtension': serializer.toJson<String?>(phoneExtension),
      'office': serializer.toJson<String?>(office),
      'manager': serializer.toJson<String?>(manager),
      'city': serializer.toJson<String?>(city),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'source': serializer.toJson<int>(source),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isVip': serializer.toJson<bool>(isVip),
      'interactionCount': serializer.toJson<int>(interactionCount),
      'lastInteraction': serializer.toJson<DateTime?>(lastInteraction),
      'notes': serializer.toJson<String?>(notes),
      'birthday': serializer.toJson<DateTime?>(birthday),
      'dirCheckedAt': serializer.toJson<DateTime?>(dirCheckedAt),
      'dirOrg': serializer.toJson<String?>(dirOrg),
    };
  }

  Contact copyWith({
    String? id,
    Value<String?> accountId = const Value.absent(),
    String? email,
    Value<String?> additionalEmails = const Value.absent(),
    String? displayName,
    Value<String?> firstName = const Value.absent(),
    Value<String?> middleName = const Value.absent(),
    Value<String?> lastName = const Value.absent(),
    Value<String?> jobTitle = const Value.absent(),
    Value<String?> department = const Value.absent(),
    Value<String?> company = const Value.absent(),
    Value<String?> phoneWork = const Value.absent(),
    Value<String?> phoneMobile = const Value.absent(),
    Value<String?> phoneExtension = const Value.absent(),
    Value<String?> office = const Value.absent(),
    Value<String?> manager = const Value.absent(),
    Value<String?> city = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    int? source,
    bool? isFavorite,
    bool? isVip,
    int? interactionCount,
    Value<DateTime?> lastInteraction = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> birthday = const Value.absent(),
    Value<DateTime?> dirCheckedAt = const Value.absent(),
    Value<String?> dirOrg = const Value.absent(),
  }) => Contact(
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    email: email ?? this.email,
    additionalEmails: additionalEmails.present
        ? additionalEmails.value
        : this.additionalEmails,
    displayName: displayName ?? this.displayName,
    firstName: firstName.present ? firstName.value : this.firstName,
    middleName: middleName.present ? middleName.value : this.middleName,
    lastName: lastName.present ? lastName.value : this.lastName,
    jobTitle: jobTitle.present ? jobTitle.value : this.jobTitle,
    department: department.present ? department.value : this.department,
    company: company.present ? company.value : this.company,
    phoneWork: phoneWork.present ? phoneWork.value : this.phoneWork,
    phoneMobile: phoneMobile.present ? phoneMobile.value : this.phoneMobile,
    phoneExtension: phoneExtension.present
        ? phoneExtension.value
        : this.phoneExtension,
    office: office.present ? office.value : this.office,
    manager: manager.present ? manager.value : this.manager,
    city: city.present ? city.value : this.city,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    source: source ?? this.source,
    isFavorite: isFavorite ?? this.isFavorite,
    isVip: isVip ?? this.isVip,
    interactionCount: interactionCount ?? this.interactionCount,
    lastInteraction: lastInteraction.present
        ? lastInteraction.value
        : this.lastInteraction,
    notes: notes.present ? notes.value : this.notes,
    birthday: birthday.present ? birthday.value : this.birthday,
    dirCheckedAt: dirCheckedAt.present ? dirCheckedAt.value : this.dirCheckedAt,
    dirOrg: dirOrg.present ? dirOrg.value : this.dirOrg,
  );
  Contact copyWithCompanion(ContactsCompanion data) {
    return Contact(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      email: data.email.present ? data.email.value : this.email,
      additionalEmails: data.additionalEmails.present
          ? data.additionalEmails.value
          : this.additionalEmails,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      middleName: data.middleName.present
          ? data.middleName.value
          : this.middleName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      jobTitle: data.jobTitle.present ? data.jobTitle.value : this.jobTitle,
      department: data.department.present
          ? data.department.value
          : this.department,
      company: data.company.present ? data.company.value : this.company,
      phoneWork: data.phoneWork.present ? data.phoneWork.value : this.phoneWork,
      phoneMobile: data.phoneMobile.present
          ? data.phoneMobile.value
          : this.phoneMobile,
      phoneExtension: data.phoneExtension.present
          ? data.phoneExtension.value
          : this.phoneExtension,
      office: data.office.present ? data.office.value : this.office,
      manager: data.manager.present ? data.manager.value : this.manager,
      city: data.city.present ? data.city.value : this.city,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      source: data.source.present ? data.source.value : this.source,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      isVip: data.isVip.present ? data.isVip.value : this.isVip,
      interactionCount: data.interactionCount.present
          ? data.interactionCount.value
          : this.interactionCount,
      lastInteraction: data.lastInteraction.present
          ? data.lastInteraction.value
          : this.lastInteraction,
      notes: data.notes.present ? data.notes.value : this.notes,
      birthday: data.birthday.present ? data.birthday.value : this.birthday,
      dirCheckedAt: data.dirCheckedAt.present
          ? data.dirCheckedAt.value
          : this.dirCheckedAt,
      dirOrg: data.dirOrg.present ? data.dirOrg.value : this.dirOrg,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Contact(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('email: $email, ')
          ..write('additionalEmails: $additionalEmails, ')
          ..write('displayName: $displayName, ')
          ..write('firstName: $firstName, ')
          ..write('middleName: $middleName, ')
          ..write('lastName: $lastName, ')
          ..write('jobTitle: $jobTitle, ')
          ..write('department: $department, ')
          ..write('company: $company, ')
          ..write('phoneWork: $phoneWork, ')
          ..write('phoneMobile: $phoneMobile, ')
          ..write('phoneExtension: $phoneExtension, ')
          ..write('office: $office, ')
          ..write('manager: $manager, ')
          ..write('city: $city, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('source: $source, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isVip: $isVip, ')
          ..write('interactionCount: $interactionCount, ')
          ..write('lastInteraction: $lastInteraction, ')
          ..write('notes: $notes, ')
          ..write('birthday: $birthday, ')
          ..write('dirCheckedAt: $dirCheckedAt, ')
          ..write('dirOrg: $dirOrg')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    accountId,
    email,
    additionalEmails,
    displayName,
    firstName,
    middleName,
    lastName,
    jobTitle,
    department,
    company,
    phoneWork,
    phoneMobile,
    phoneExtension,
    office,
    manager,
    city,
    avatarPath,
    avatarUrl,
    source,
    isFavorite,
    isVip,
    interactionCount,
    lastInteraction,
    notes,
    birthday,
    dirCheckedAt,
    dirOrg,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Contact &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.email == this.email &&
          other.additionalEmails == this.additionalEmails &&
          other.displayName == this.displayName &&
          other.firstName == this.firstName &&
          other.middleName == this.middleName &&
          other.lastName == this.lastName &&
          other.jobTitle == this.jobTitle &&
          other.department == this.department &&
          other.company == this.company &&
          other.phoneWork == this.phoneWork &&
          other.phoneMobile == this.phoneMobile &&
          other.phoneExtension == this.phoneExtension &&
          other.office == this.office &&
          other.manager == this.manager &&
          other.city == this.city &&
          other.avatarPath == this.avatarPath &&
          other.avatarUrl == this.avatarUrl &&
          other.source == this.source &&
          other.isFavorite == this.isFavorite &&
          other.isVip == this.isVip &&
          other.interactionCount == this.interactionCount &&
          other.lastInteraction == this.lastInteraction &&
          other.notes == this.notes &&
          other.birthday == this.birthday &&
          other.dirCheckedAt == this.dirCheckedAt &&
          other.dirOrg == this.dirOrg);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<String> id;
  final Value<String?> accountId;
  final Value<String> email;
  final Value<String?> additionalEmails;
  final Value<String> displayName;
  final Value<String?> firstName;
  final Value<String?> middleName;
  final Value<String?> lastName;
  final Value<String?> jobTitle;
  final Value<String?> department;
  final Value<String?> company;
  final Value<String?> phoneWork;
  final Value<String?> phoneMobile;
  final Value<String?> phoneExtension;
  final Value<String?> office;
  final Value<String?> manager;
  final Value<String?> city;
  final Value<String?> avatarPath;
  final Value<String?> avatarUrl;
  final Value<int> source;
  final Value<bool> isFavorite;
  final Value<bool> isVip;
  final Value<int> interactionCount;
  final Value<DateTime?> lastInteraction;
  final Value<String?> notes;
  final Value<DateTime?> birthday;
  final Value<DateTime?> dirCheckedAt;
  final Value<String?> dirOrg;
  final Value<int> rowid;
  const ContactsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.email = const Value.absent(),
    this.additionalEmails = const Value.absent(),
    this.displayName = const Value.absent(),
    this.firstName = const Value.absent(),
    this.middleName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.jobTitle = const Value.absent(),
    this.department = const Value.absent(),
    this.company = const Value.absent(),
    this.phoneWork = const Value.absent(),
    this.phoneMobile = const Value.absent(),
    this.phoneExtension = const Value.absent(),
    this.office = const Value.absent(),
    this.manager = const Value.absent(),
    this.city = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.source = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isVip = const Value.absent(),
    this.interactionCount = const Value.absent(),
    this.lastInteraction = const Value.absent(),
    this.notes = const Value.absent(),
    this.birthday = const Value.absent(),
    this.dirCheckedAt = const Value.absent(),
    this.dirOrg = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactsCompanion.insert({
    required String id,
    this.accountId = const Value.absent(),
    required String email,
    this.additionalEmails = const Value.absent(),
    required String displayName,
    this.firstName = const Value.absent(),
    this.middleName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.jobTitle = const Value.absent(),
    this.department = const Value.absent(),
    this.company = const Value.absent(),
    this.phoneWork = const Value.absent(),
    this.phoneMobile = const Value.absent(),
    this.phoneExtension = const Value.absent(),
    this.office = const Value.absent(),
    this.manager = const Value.absent(),
    this.city = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.source = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isVip = const Value.absent(),
    this.interactionCount = const Value.absent(),
    this.lastInteraction = const Value.absent(),
    this.notes = const Value.absent(),
    this.birthday = const Value.absent(),
    this.dirCheckedAt = const Value.absent(),
    this.dirOrg = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       email = Value(email),
       displayName = Value(displayName);
  static Insertable<Contact> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? email,
    Expression<String>? additionalEmails,
    Expression<String>? displayName,
    Expression<String>? firstName,
    Expression<String>? middleName,
    Expression<String>? lastName,
    Expression<String>? jobTitle,
    Expression<String>? department,
    Expression<String>? company,
    Expression<String>? phoneWork,
    Expression<String>? phoneMobile,
    Expression<String>? phoneExtension,
    Expression<String>? office,
    Expression<String>? manager,
    Expression<String>? city,
    Expression<String>? avatarPath,
    Expression<String>? avatarUrl,
    Expression<int>? source,
    Expression<bool>? isFavorite,
    Expression<bool>? isVip,
    Expression<int>? interactionCount,
    Expression<DateTime>? lastInteraction,
    Expression<String>? notes,
    Expression<DateTime>? birthday,
    Expression<DateTime>? dirCheckedAt,
    Expression<String>? dirOrg,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (email != null) 'email': email,
      if (additionalEmails != null) 'additional_emails': additionalEmails,
      if (displayName != null) 'display_name': displayName,
      if (firstName != null) 'first_name': firstName,
      if (middleName != null) 'middle_name': middleName,
      if (lastName != null) 'last_name': lastName,
      if (jobTitle != null) 'job_title': jobTitle,
      if (department != null) 'department': department,
      if (company != null) 'company': company,
      if (phoneWork != null) 'phone_work': phoneWork,
      if (phoneMobile != null) 'phone_mobile': phoneMobile,
      if (phoneExtension != null) 'phone_extension': phoneExtension,
      if (office != null) 'office': office,
      if (manager != null) 'manager': manager,
      if (city != null) 'city': city,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (source != null) 'source': source,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isVip != null) 'is_vip': isVip,
      if (interactionCount != null) 'interaction_count': interactionCount,
      if (lastInteraction != null) 'last_interaction': lastInteraction,
      if (notes != null) 'notes': notes,
      if (birthday != null) 'birthday': birthday,
      if (dirCheckedAt != null) 'dir_checked_at': dirCheckedAt,
      if (dirOrg != null) 'dir_org': dirOrg,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactsCompanion copyWith({
    Value<String>? id,
    Value<String?>? accountId,
    Value<String>? email,
    Value<String?>? additionalEmails,
    Value<String>? displayName,
    Value<String?>? firstName,
    Value<String?>? middleName,
    Value<String?>? lastName,
    Value<String?>? jobTitle,
    Value<String?>? department,
    Value<String?>? company,
    Value<String?>? phoneWork,
    Value<String?>? phoneMobile,
    Value<String?>? phoneExtension,
    Value<String?>? office,
    Value<String?>? manager,
    Value<String?>? city,
    Value<String?>? avatarPath,
    Value<String?>? avatarUrl,
    Value<int>? source,
    Value<bool>? isFavorite,
    Value<bool>? isVip,
    Value<int>? interactionCount,
    Value<DateTime?>? lastInteraction,
    Value<String?>? notes,
    Value<DateTime?>? birthday,
    Value<DateTime?>? dirCheckedAt,
    Value<String?>? dirOrg,
    Value<int>? rowid,
  }) {
    return ContactsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      email: email ?? this.email,
      additionalEmails: additionalEmails ?? this.additionalEmails,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      jobTitle: jobTitle ?? this.jobTitle,
      department: department ?? this.department,
      company: company ?? this.company,
      phoneWork: phoneWork ?? this.phoneWork,
      phoneMobile: phoneMobile ?? this.phoneMobile,
      phoneExtension: phoneExtension ?? this.phoneExtension,
      office: office ?? this.office,
      manager: manager ?? this.manager,
      city: city ?? this.city,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,
      isVip: isVip ?? this.isVip,
      interactionCount: interactionCount ?? this.interactionCount,
      lastInteraction: lastInteraction ?? this.lastInteraction,
      notes: notes ?? this.notes,
      birthday: birthday ?? this.birthday,
      dirCheckedAt: dirCheckedAt ?? this.dirCheckedAt,
      dirOrg: dirOrg ?? this.dirOrg,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (additionalEmails.present) {
      map['additional_emails'] = Variable<String>(additionalEmails.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (middleName.present) {
      map['middle_name'] = Variable<String>(middleName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (jobTitle.present) {
      map['job_title'] = Variable<String>(jobTitle.value);
    }
    if (department.present) {
      map['department'] = Variable<String>(department.value);
    }
    if (company.present) {
      map['company'] = Variable<String>(company.value);
    }
    if (phoneWork.present) {
      map['phone_work'] = Variable<String>(phoneWork.value);
    }
    if (phoneMobile.present) {
      map['phone_mobile'] = Variable<String>(phoneMobile.value);
    }
    if (phoneExtension.present) {
      map['phone_extension'] = Variable<String>(phoneExtension.value);
    }
    if (office.present) {
      map['office'] = Variable<String>(office.value);
    }
    if (manager.present) {
      map['manager'] = Variable<String>(manager.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (source.present) {
      map['source'] = Variable<int>(source.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isVip.present) {
      map['is_vip'] = Variable<bool>(isVip.value);
    }
    if (interactionCount.present) {
      map['interaction_count'] = Variable<int>(interactionCount.value);
    }
    if (lastInteraction.present) {
      map['last_interaction'] = Variable<DateTime>(lastInteraction.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (birthday.present) {
      map['birthday'] = Variable<DateTime>(birthday.value);
    }
    if (dirCheckedAt.present) {
      map['dir_checked_at'] = Variable<DateTime>(dirCheckedAt.value);
    }
    if (dirOrg.present) {
      map['dir_org'] = Variable<String>(dirOrg.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('email: $email, ')
          ..write('additionalEmails: $additionalEmails, ')
          ..write('displayName: $displayName, ')
          ..write('firstName: $firstName, ')
          ..write('middleName: $middleName, ')
          ..write('lastName: $lastName, ')
          ..write('jobTitle: $jobTitle, ')
          ..write('department: $department, ')
          ..write('company: $company, ')
          ..write('phoneWork: $phoneWork, ')
          ..write('phoneMobile: $phoneMobile, ')
          ..write('phoneExtension: $phoneExtension, ')
          ..write('office: $office, ')
          ..write('manager: $manager, ')
          ..write('city: $city, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('source: $source, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isVip: $isVip, ')
          ..write('interactionCount: $interactionCount, ')
          ..write('lastInteraction: $lastInteraction, ')
          ..write('notes: $notes, ')
          ..write('birthday: $birthday, ')
          ..write('dirCheckedAt: $dirCheckedAt, ')
          ..write('dirOrg: $dirOrg, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarEventsTable extends CalendarEvents
    with TableInfo<$CalendarEventsTable, CalendarEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _calendarIdMeta = const VerificationMeta(
    'calendarId',
  );
  @override
  late final GeneratedColumn<String> calendarId = GeneratedColumn<String>(
    'calendar_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onlineMeetingUrlMeta = const VerificationMeta(
    'onlineMeetingUrl',
  );
  @override
  late final GeneratedColumn<String> onlineMeetingUrl = GeneratedColumn<String>(
    'online_meeting_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isAllDayMeta = const VerificationMeta(
    'isAllDay',
  );
  @override
  late final GeneratedColumn<bool> isAllDay = GeneratedColumn<bool>(
    'is_all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _attendeesJsonMeta = const VerificationMeta(
    'attendeesJson',
  );
  @override
  late final GeneratedColumn<String> attendeesJson = GeneratedColumn<String>(
    'attendees_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _organizerEmailMeta = const VerificationMeta(
    'organizerEmail',
  );
  @override
  late final GeneratedColumn<String> organizerEmail = GeneratedColumn<String>(
    'organizer_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recurrenceMeta = const VerificationMeta(
    'recurrence',
  );
  @override
  late final GeneratedColumn<int> recurrence = GeneratedColumn<int>(
    'recurrence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _showAsMeta = const VerificationMeta('showAs');
  @override
  late final GeneratedColumn<int> showAs = GeneratedColumn<int>(
    'show_as',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPrivateMeta = const VerificationMeta(
    'isPrivate',
  );
  @override
  late final GeneratedColumn<bool> isPrivate = GeneratedColumn<bool>(
    'is_private',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_private" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _remindersJsonMeta = const VerificationMeta(
    'remindersJson',
  );
  @override
  late final GeneratedColumn<String> remindersJson = GeneratedColumn<String>(
    'reminders_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkedEmailIdMeta = const VerificationMeta(
    'linkedEmailId',
  );
  @override
  late final GeneratedColumn<String> linkedEmailId = GeneratedColumn<String>(
    'linked_email_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCancelledMeta = const VerificationMeta(
    'isCancelled',
  );
  @override
  late final GeneratedColumn<bool> isCancelled = GeneratedColumn<bool>(
    'is_cancelled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_cancelled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isLocallyModifiedMeta = const VerificationMeta(
    'isLocallyModified',
  );
  @override
  late final GeneratedColumn<bool> isLocallyModified = GeneratedColumn<bool>(
    'is_locally_modified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_locally_modified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    calendarId,
    title,
    description,
    location,
    onlineMeetingUrl,
    startTime,
    endTime,
    isAllDay,
    attendeesJson,
    organizerEmail,
    recurrence,
    priority,
    showAs,
    colorValue,
    isPrivate,
    remindersJson,
    linkedEmailId,
    isCancelled,
    isLocallyModified,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('calendar_id')) {
      context.handle(
        _calendarIdMeta,
        calendarId.isAcceptableOrUnknown(data['calendar_id']!, _calendarIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('online_meeting_url')) {
      context.handle(
        _onlineMeetingUrlMeta,
        onlineMeetingUrl.isAcceptableOrUnknown(
          data['online_meeting_url']!,
          _onlineMeetingUrlMeta,
        ),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('is_all_day')) {
      context.handle(
        _isAllDayMeta,
        isAllDay.isAcceptableOrUnknown(data['is_all_day']!, _isAllDayMeta),
      );
    }
    if (data.containsKey('attendees_json')) {
      context.handle(
        _attendeesJsonMeta,
        attendeesJson.isAcceptableOrUnknown(
          data['attendees_json']!,
          _attendeesJsonMeta,
        ),
      );
    }
    if (data.containsKey('organizer_email')) {
      context.handle(
        _organizerEmailMeta,
        organizerEmail.isAcceptableOrUnknown(
          data['organizer_email']!,
          _organizerEmailMeta,
        ),
      );
    }
    if (data.containsKey('recurrence')) {
      context.handle(
        _recurrenceMeta,
        recurrence.isAcceptableOrUnknown(data['recurrence']!, _recurrenceMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('show_as')) {
      context.handle(
        _showAsMeta,
        showAs.isAcceptableOrUnknown(data['show_as']!, _showAsMeta),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('is_private')) {
      context.handle(
        _isPrivateMeta,
        isPrivate.isAcceptableOrUnknown(data['is_private']!, _isPrivateMeta),
      );
    }
    if (data.containsKey('reminders_json')) {
      context.handle(
        _remindersJsonMeta,
        remindersJson.isAcceptableOrUnknown(
          data['reminders_json']!,
          _remindersJsonMeta,
        ),
      );
    }
    if (data.containsKey('linked_email_id')) {
      context.handle(
        _linkedEmailIdMeta,
        linkedEmailId.isAcceptableOrUnknown(
          data['linked_email_id']!,
          _linkedEmailIdMeta,
        ),
      );
    }
    if (data.containsKey('is_cancelled')) {
      context.handle(
        _isCancelledMeta,
        isCancelled.isAcceptableOrUnknown(
          data['is_cancelled']!,
          _isCancelledMeta,
        ),
      );
    }
    if (data.containsKey('is_locally_modified')) {
      context.handle(
        _isLocallyModifiedMeta,
        isLocallyModified.isAcceptableOrUnknown(
          data['is_locally_modified']!,
          _isLocallyModifiedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, accountId};
  @override
  CalendarEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      calendarId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calendar_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      onlineMeetingUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}online_meeting_url'],
      ),
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      )!,
      isAllDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_all_day'],
      )!,
      attendeesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attendees_json'],
      ),
      organizerEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organizer_email'],
      ),
      recurrence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recurrence'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      showAs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}show_as'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      ),
      isPrivate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_private'],
      )!,
      remindersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminders_json'],
      ),
      linkedEmailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_email_id'],
      ),
      isCancelled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_cancelled'],
      )!,
      isLocallyModified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_locally_modified'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $CalendarEventsTable createAlias(String alias) {
    return $CalendarEventsTable(attachedDatabase, alias);
  }
}

class CalendarEvent extends DataClass implements Insertable<CalendarEvent> {
  final String id;
  final String accountId;
  final String? calendarId;
  final String title;
  final String? description;
  final String? location;
  final String? onlineMeetingUrl;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? attendeesJson;
  final String? organizerEmail;
  final int recurrence;
  final int priority;
  final int showAs;
  final int? colorValue;
  final bool isPrivate;
  final String? remindersJson;
  final String? linkedEmailId;
  final bool isCancelled;
  final bool isLocallyModified;
  final DateTime createdAt;
  final DateTime? updatedAt;
  const CalendarEvent({
    required this.id,
    required this.accountId,
    this.calendarId,
    required this.title,
    this.description,
    this.location,
    this.onlineMeetingUrl,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    this.attendeesJson,
    this.organizerEmail,
    required this.recurrence,
    required this.priority,
    required this.showAs,
    this.colorValue,
    required this.isPrivate,
    this.remindersJson,
    this.linkedEmailId,
    required this.isCancelled,
    required this.isLocallyModified,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || calendarId != null) {
      map['calendar_id'] = Variable<String>(calendarId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || onlineMeetingUrl != null) {
      map['online_meeting_url'] = Variable<String>(onlineMeetingUrl);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    map['end_time'] = Variable<DateTime>(endTime);
    map['is_all_day'] = Variable<bool>(isAllDay);
    if (!nullToAbsent || attendeesJson != null) {
      map['attendees_json'] = Variable<String>(attendeesJson);
    }
    if (!nullToAbsent || organizerEmail != null) {
      map['organizer_email'] = Variable<String>(organizerEmail);
    }
    map['recurrence'] = Variable<int>(recurrence);
    map['priority'] = Variable<int>(priority);
    map['show_as'] = Variable<int>(showAs);
    if (!nullToAbsent || colorValue != null) {
      map['color_value'] = Variable<int>(colorValue);
    }
    map['is_private'] = Variable<bool>(isPrivate);
    if (!nullToAbsent || remindersJson != null) {
      map['reminders_json'] = Variable<String>(remindersJson);
    }
    if (!nullToAbsent || linkedEmailId != null) {
      map['linked_email_id'] = Variable<String>(linkedEmailId);
    }
    map['is_cancelled'] = Variable<bool>(isCancelled);
    map['is_locally_modified'] = Variable<bool>(isLocallyModified);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CalendarEventsCompanion toCompanion(bool nullToAbsent) {
    return CalendarEventsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      calendarId: calendarId == null && nullToAbsent
          ? const Value.absent()
          : Value(calendarId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      onlineMeetingUrl: onlineMeetingUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(onlineMeetingUrl),
      startTime: Value(startTime),
      endTime: Value(endTime),
      isAllDay: Value(isAllDay),
      attendeesJson: attendeesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attendeesJson),
      organizerEmail: organizerEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(organizerEmail),
      recurrence: Value(recurrence),
      priority: Value(priority),
      showAs: Value(showAs),
      colorValue: colorValue == null && nullToAbsent
          ? const Value.absent()
          : Value(colorValue),
      isPrivate: Value(isPrivate),
      remindersJson: remindersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(remindersJson),
      linkedEmailId: linkedEmailId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedEmailId),
      isCancelled: Value(isCancelled),
      isLocallyModified: Value(isLocallyModified),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CalendarEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarEvent(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      calendarId: serializer.fromJson<String?>(json['calendarId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      location: serializer.fromJson<String?>(json['location']),
      onlineMeetingUrl: serializer.fromJson<String?>(json['onlineMeetingUrl']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime>(json['endTime']),
      isAllDay: serializer.fromJson<bool>(json['isAllDay']),
      attendeesJson: serializer.fromJson<String?>(json['attendeesJson']),
      organizerEmail: serializer.fromJson<String?>(json['organizerEmail']),
      recurrence: serializer.fromJson<int>(json['recurrence']),
      priority: serializer.fromJson<int>(json['priority']),
      showAs: serializer.fromJson<int>(json['showAs']),
      colorValue: serializer.fromJson<int?>(json['colorValue']),
      isPrivate: serializer.fromJson<bool>(json['isPrivate']),
      remindersJson: serializer.fromJson<String?>(json['remindersJson']),
      linkedEmailId: serializer.fromJson<String?>(json['linkedEmailId']),
      isCancelled: serializer.fromJson<bool>(json['isCancelled']),
      isLocallyModified: serializer.fromJson<bool>(json['isLocallyModified']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'calendarId': serializer.toJson<String?>(calendarId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'location': serializer.toJson<String?>(location),
      'onlineMeetingUrl': serializer.toJson<String?>(onlineMeetingUrl),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime>(endTime),
      'isAllDay': serializer.toJson<bool>(isAllDay),
      'attendeesJson': serializer.toJson<String?>(attendeesJson),
      'organizerEmail': serializer.toJson<String?>(organizerEmail),
      'recurrence': serializer.toJson<int>(recurrence),
      'priority': serializer.toJson<int>(priority),
      'showAs': serializer.toJson<int>(showAs),
      'colorValue': serializer.toJson<int?>(colorValue),
      'isPrivate': serializer.toJson<bool>(isPrivate),
      'remindersJson': serializer.toJson<String?>(remindersJson),
      'linkedEmailId': serializer.toJson<String?>(linkedEmailId),
      'isCancelled': serializer.toJson<bool>(isCancelled),
      'isLocallyModified': serializer.toJson<bool>(isLocallyModified),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CalendarEvent copyWith({
    String? id,
    String? accountId,
    Value<String?> calendarId = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> onlineMeetingUrl = const Value.absent(),
    DateTime? startTime,
    DateTime? endTime,
    bool? isAllDay,
    Value<String?> attendeesJson = const Value.absent(),
    Value<String?> organizerEmail = const Value.absent(),
    int? recurrence,
    int? priority,
    int? showAs,
    Value<int?> colorValue = const Value.absent(),
    bool? isPrivate,
    Value<String?> remindersJson = const Value.absent(),
    Value<String?> linkedEmailId = const Value.absent(),
    bool? isCancelled,
    bool? isLocallyModified,
    DateTime? createdAt,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => CalendarEvent(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    calendarId: calendarId.present ? calendarId.value : this.calendarId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    location: location.present ? location.value : this.location,
    onlineMeetingUrl: onlineMeetingUrl.present
        ? onlineMeetingUrl.value
        : this.onlineMeetingUrl,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    isAllDay: isAllDay ?? this.isAllDay,
    attendeesJson: attendeesJson.present
        ? attendeesJson.value
        : this.attendeesJson,
    organizerEmail: organizerEmail.present
        ? organizerEmail.value
        : this.organizerEmail,
    recurrence: recurrence ?? this.recurrence,
    priority: priority ?? this.priority,
    showAs: showAs ?? this.showAs,
    colorValue: colorValue.present ? colorValue.value : this.colorValue,
    isPrivate: isPrivate ?? this.isPrivate,
    remindersJson: remindersJson.present
        ? remindersJson.value
        : this.remindersJson,
    linkedEmailId: linkedEmailId.present
        ? linkedEmailId.value
        : this.linkedEmailId,
    isCancelled: isCancelled ?? this.isCancelled,
    isLocallyModified: isLocallyModified ?? this.isLocallyModified,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  CalendarEvent copyWithCompanion(CalendarEventsCompanion data) {
    return CalendarEvent(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      calendarId: data.calendarId.present
          ? data.calendarId.value
          : this.calendarId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      location: data.location.present ? data.location.value : this.location,
      onlineMeetingUrl: data.onlineMeetingUrl.present
          ? data.onlineMeetingUrl.value
          : this.onlineMeetingUrl,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      isAllDay: data.isAllDay.present ? data.isAllDay.value : this.isAllDay,
      attendeesJson: data.attendeesJson.present
          ? data.attendeesJson.value
          : this.attendeesJson,
      organizerEmail: data.organizerEmail.present
          ? data.organizerEmail.value
          : this.organizerEmail,
      recurrence: data.recurrence.present
          ? data.recurrence.value
          : this.recurrence,
      priority: data.priority.present ? data.priority.value : this.priority,
      showAs: data.showAs.present ? data.showAs.value : this.showAs,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      isPrivate: data.isPrivate.present ? data.isPrivate.value : this.isPrivate,
      remindersJson: data.remindersJson.present
          ? data.remindersJson.value
          : this.remindersJson,
      linkedEmailId: data.linkedEmailId.present
          ? data.linkedEmailId.value
          : this.linkedEmailId,
      isCancelled: data.isCancelled.present
          ? data.isCancelled.value
          : this.isCancelled,
      isLocallyModified: data.isLocallyModified.present
          ? data.isLocallyModified.value
          : this.isLocallyModified,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEvent(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('calendarId: $calendarId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('onlineMeetingUrl: $onlineMeetingUrl, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('attendeesJson: $attendeesJson, ')
          ..write('organizerEmail: $organizerEmail, ')
          ..write('recurrence: $recurrence, ')
          ..write('priority: $priority, ')
          ..write('showAs: $showAs, ')
          ..write('colorValue: $colorValue, ')
          ..write('isPrivate: $isPrivate, ')
          ..write('remindersJson: $remindersJson, ')
          ..write('linkedEmailId: $linkedEmailId, ')
          ..write('isCancelled: $isCancelled, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    accountId,
    calendarId,
    title,
    description,
    location,
    onlineMeetingUrl,
    startTime,
    endTime,
    isAllDay,
    attendeesJson,
    organizerEmail,
    recurrence,
    priority,
    showAs,
    colorValue,
    isPrivate,
    remindersJson,
    linkedEmailId,
    isCancelled,
    isLocallyModified,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarEvent &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.calendarId == this.calendarId &&
          other.title == this.title &&
          other.description == this.description &&
          other.location == this.location &&
          other.onlineMeetingUrl == this.onlineMeetingUrl &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.isAllDay == this.isAllDay &&
          other.attendeesJson == this.attendeesJson &&
          other.organizerEmail == this.organizerEmail &&
          other.recurrence == this.recurrence &&
          other.priority == this.priority &&
          other.showAs == this.showAs &&
          other.colorValue == this.colorValue &&
          other.isPrivate == this.isPrivate &&
          other.remindersJson == this.remindersJson &&
          other.linkedEmailId == this.linkedEmailId &&
          other.isCancelled == this.isCancelled &&
          other.isLocallyModified == this.isLocallyModified &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CalendarEventsCompanion extends UpdateCompanion<CalendarEvent> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String?> calendarId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> location;
  final Value<String?> onlineMeetingUrl;
  final Value<DateTime> startTime;
  final Value<DateTime> endTime;
  final Value<bool> isAllDay;
  final Value<String?> attendeesJson;
  final Value<String?> organizerEmail;
  final Value<int> recurrence;
  final Value<int> priority;
  final Value<int> showAs;
  final Value<int?> colorValue;
  final Value<bool> isPrivate;
  final Value<String?> remindersJson;
  final Value<String?> linkedEmailId;
  final Value<bool> isCancelled;
  final Value<bool> isLocallyModified;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const CalendarEventsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.calendarId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.onlineMeetingUrl = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.attendeesJson = const Value.absent(),
    this.organizerEmail = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.priority = const Value.absent(),
    this.showAs = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isPrivate = const Value.absent(),
    this.remindersJson = const Value.absent(),
    this.linkedEmailId = const Value.absent(),
    this.isCancelled = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarEventsCompanion.insert({
    required String id,
    required String accountId,
    this.calendarId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.onlineMeetingUrl = const Value.absent(),
    required DateTime startTime,
    required DateTime endTime,
    this.isAllDay = const Value.absent(),
    this.attendeesJson = const Value.absent(),
    this.organizerEmail = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.priority = const Value.absent(),
    this.showAs = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isPrivate = const Value.absent(),
    this.remindersJson = const Value.absent(),
    this.linkedEmailId = const Value.absent(),
    this.isCancelled = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    required DateTime createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       title = Value(title),
       startTime = Value(startTime),
       endTime = Value(endTime),
       createdAt = Value(createdAt);
  static Insertable<CalendarEvent> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? calendarId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? location,
    Expression<String>? onlineMeetingUrl,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<bool>? isAllDay,
    Expression<String>? attendeesJson,
    Expression<String>? organizerEmail,
    Expression<int>? recurrence,
    Expression<int>? priority,
    Expression<int>? showAs,
    Expression<int>? colorValue,
    Expression<bool>? isPrivate,
    Expression<String>? remindersJson,
    Expression<String>? linkedEmailId,
    Expression<bool>? isCancelled,
    Expression<bool>? isLocallyModified,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (calendarId != null) 'calendar_id': calendarId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (onlineMeetingUrl != null) 'online_meeting_url': onlineMeetingUrl,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (isAllDay != null) 'is_all_day': isAllDay,
      if (attendeesJson != null) 'attendees_json': attendeesJson,
      if (organizerEmail != null) 'organizer_email': organizerEmail,
      if (recurrence != null) 'recurrence': recurrence,
      if (priority != null) 'priority': priority,
      if (showAs != null) 'show_as': showAs,
      if (colorValue != null) 'color_value': colorValue,
      if (isPrivate != null) 'is_private': isPrivate,
      if (remindersJson != null) 'reminders_json': remindersJson,
      if (linkedEmailId != null) 'linked_email_id': linkedEmailId,
      if (isCancelled != null) 'is_cancelled': isCancelled,
      if (isLocallyModified != null) 'is_locally_modified': isLocallyModified,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String?>? calendarId,
    Value<String>? title,
    Value<String?>? description,
    Value<String?>? location,
    Value<String?>? onlineMeetingUrl,
    Value<DateTime>? startTime,
    Value<DateTime>? endTime,
    Value<bool>? isAllDay,
    Value<String?>? attendeesJson,
    Value<String?>? organizerEmail,
    Value<int>? recurrence,
    Value<int>? priority,
    Value<int>? showAs,
    Value<int?>? colorValue,
    Value<bool>? isPrivate,
    Value<String?>? remindersJson,
    Value<String?>? linkedEmailId,
    Value<bool>? isCancelled,
    Value<bool>? isLocallyModified,
    Value<DateTime>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return CalendarEventsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      onlineMeetingUrl: onlineMeetingUrl ?? this.onlineMeetingUrl,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      attendeesJson: attendeesJson ?? this.attendeesJson,
      organizerEmail: organizerEmail ?? this.organizerEmail,
      recurrence: recurrence ?? this.recurrence,
      priority: priority ?? this.priority,
      showAs: showAs ?? this.showAs,
      colorValue: colorValue ?? this.colorValue,
      isPrivate: isPrivate ?? this.isPrivate,
      remindersJson: remindersJson ?? this.remindersJson,
      linkedEmailId: linkedEmailId ?? this.linkedEmailId,
      isCancelled: isCancelled ?? this.isCancelled,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (calendarId.present) {
      map['calendar_id'] = Variable<String>(calendarId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (onlineMeetingUrl.present) {
      map['online_meeting_url'] = Variable<String>(onlineMeetingUrl.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (isAllDay.present) {
      map['is_all_day'] = Variable<bool>(isAllDay.value);
    }
    if (attendeesJson.present) {
      map['attendees_json'] = Variable<String>(attendeesJson.value);
    }
    if (organizerEmail.present) {
      map['organizer_email'] = Variable<String>(organizerEmail.value);
    }
    if (recurrence.present) {
      map['recurrence'] = Variable<int>(recurrence.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (showAs.present) {
      map['show_as'] = Variable<int>(showAs.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isPrivate.present) {
      map['is_private'] = Variable<bool>(isPrivate.value);
    }
    if (remindersJson.present) {
      map['reminders_json'] = Variable<String>(remindersJson.value);
    }
    if (linkedEmailId.present) {
      map['linked_email_id'] = Variable<String>(linkedEmailId.value);
    }
    if (isCancelled.present) {
      map['is_cancelled'] = Variable<bool>(isCancelled.value);
    }
    if (isLocallyModified.present) {
      map['is_locally_modified'] = Variable<bool>(isLocallyModified.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEventsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('calendarId: $calendarId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('onlineMeetingUrl: $onlineMeetingUrl, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('attendeesJson: $attendeesJson, ')
          ..write('organizerEmail: $organizerEmail, ')
          ..write('recurrence: $recurrence, ')
          ..write('priority: $priority, ')
          ..write('showAs: $showAs, ')
          ..write('colorValue: $colorValue, ')
          ..write('isPrivate: $isPrivate, ')
          ..write('remindersJson: $remindersJson, ')
          ..write('linkedEmailId: $linkedEmailId, ')
          ..write('isCancelled: $isCancelled, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<int> progress = GeneratedColumn<int>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _assigneeEmailMeta = const VerificationMeta(
    'assigneeEmail',
  );
  @override
  late final GeneratedColumn<String> assigneeEmail = GeneratedColumn<String>(
    'assignee_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assigneeNameMeta = const VerificationMeta(
    'assigneeName',
  );
  @override
  late final GeneratedColumn<String> assigneeName = GeneratedColumn<String>(
    'assignee_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkedEmailIdMeta = const VerificationMeta(
    'linkedEmailId',
  );
  @override
  late final GeneratedColumn<String> linkedEmailId = GeneratedColumn<String>(
    'linked_email_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkedEmailSubjectMeta =
      const VerificationMeta('linkedEmailSubject');
  @override
  late final GeneratedColumn<String> linkedEmailSubject =
      GeneratedColumn<String>(
        'linked_email_subject',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _tagsStrMeta = const VerificationMeta(
    'tagsStr',
  );
  @override
  late final GeneratedColumn<String> tagsStr = GeneratedColumn<String>(
    'tags_str',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtasksJsonMeta = const VerificationMeta(
    'subtasksJson',
  );
  @override
  late final GeneratedColumn<String> subtasksJson = GeneratedColumn<String>(
    'subtasks_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commentsJsonMeta = const VerificationMeta(
    'commentsJson',
  );
  @override
  late final GeneratedColumn<String> commentsJson = GeneratedColumn<String>(
    'comments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isRecurringMeta = const VerificationMeta(
    'isRecurring',
  );
  @override
  late final GeneratedColumn<bool> isRecurring = GeneratedColumn<bool>(
    'is_recurring',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_recurring" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _recurrenceDaysMeta = const VerificationMeta(
    'recurrenceDays',
  );
  @override
  late final GeneratedColumn<int> recurrenceDays = GeneratedColumn<int>(
    'recurrence_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFlaggedMeta = const VerificationMeta(
    'isFlagged',
  );
  @override
  late final GeneratedColumn<bool> isFlagged = GeneratedColumn<bool>(
    'is_flagged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_flagged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isLocallyModifiedMeta = const VerificationMeta(
    'isLocallyModified',
  );
  @override
  late final GeneratedColumn<bool> isLocallyModified = GeneratedColumn<bool>(
    'is_locally_modified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_locally_modified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reminderAtMeta = const VerificationMeta(
    'reminderAt',
  );
  @override
  late final GeneratedColumn<DateTime> reminderAt = GeneratedColumn<DateTime>(
    'reminder_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    title,
    description,
    status,
    priority,
    createdAt,
    dueDate,
    completedAt,
    progress,
    assigneeEmail,
    assigneeName,
    linkedEmailId,
    linkedEmailSubject,
    tagsStr,
    subtasksJson,
    commentsJson,
    isRecurring,
    recurrenceDays,
    colorValue,
    isFlagged,
    isLocallyModified,
    reminderAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('assignee_email')) {
      context.handle(
        _assigneeEmailMeta,
        assigneeEmail.isAcceptableOrUnknown(
          data['assignee_email']!,
          _assigneeEmailMeta,
        ),
      );
    }
    if (data.containsKey('assignee_name')) {
      context.handle(
        _assigneeNameMeta,
        assigneeName.isAcceptableOrUnknown(
          data['assignee_name']!,
          _assigneeNameMeta,
        ),
      );
    }
    if (data.containsKey('linked_email_id')) {
      context.handle(
        _linkedEmailIdMeta,
        linkedEmailId.isAcceptableOrUnknown(
          data['linked_email_id']!,
          _linkedEmailIdMeta,
        ),
      );
    }
    if (data.containsKey('linked_email_subject')) {
      context.handle(
        _linkedEmailSubjectMeta,
        linkedEmailSubject.isAcceptableOrUnknown(
          data['linked_email_subject']!,
          _linkedEmailSubjectMeta,
        ),
      );
    }
    if (data.containsKey('tags_str')) {
      context.handle(
        _tagsStrMeta,
        tagsStr.isAcceptableOrUnknown(data['tags_str']!, _tagsStrMeta),
      );
    }
    if (data.containsKey('subtasks_json')) {
      context.handle(
        _subtasksJsonMeta,
        subtasksJson.isAcceptableOrUnknown(
          data['subtasks_json']!,
          _subtasksJsonMeta,
        ),
      );
    }
    if (data.containsKey('comments_json')) {
      context.handle(
        _commentsJsonMeta,
        commentsJson.isAcceptableOrUnknown(
          data['comments_json']!,
          _commentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('is_recurring')) {
      context.handle(
        _isRecurringMeta,
        isRecurring.isAcceptableOrUnknown(
          data['is_recurring']!,
          _isRecurringMeta,
        ),
      );
    }
    if (data.containsKey('recurrence_days')) {
      context.handle(
        _recurrenceDaysMeta,
        recurrenceDays.isAcceptableOrUnknown(
          data['recurrence_days']!,
          _recurrenceDaysMeta,
        ),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('is_flagged')) {
      context.handle(
        _isFlaggedMeta,
        isFlagged.isAcceptableOrUnknown(data['is_flagged']!, _isFlaggedMeta),
      );
    }
    if (data.containsKey('is_locally_modified')) {
      context.handle(
        _isLocallyModifiedMeta,
        isLocallyModified.isAcceptableOrUnknown(
          data['is_locally_modified']!,
          _isLocallyModifiedMeta,
        ),
      );
    }
    if (data.containsKey('reminder_at')) {
      context.handle(
        _reminderAtMeta,
        reminderAt.isAcceptableOrUnknown(data['reminder_at']!, _reminderAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, accountId};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}progress'],
      )!,
      assigneeEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignee_email'],
      ),
      assigneeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignee_name'],
      ),
      linkedEmailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_email_id'],
      ),
      linkedEmailSubject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_email_subject'],
      ),
      tagsStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_str'],
      ),
      subtasksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtasks_json'],
      ),
      commentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comments_json'],
      ),
      isRecurring: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_recurring'],
      )!,
      recurrenceDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recurrence_days'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      ),
      isFlagged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_flagged'],
      )!,
      isLocallyModified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_locally_modified'],
      )!,
      reminderAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reminder_at'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String accountId;
  final String title;
  final String? description;
  final int status;
  final int priority;
  final DateTime createdAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final int progress;
  final String? assigneeEmail;
  final String? assigneeName;
  final String? linkedEmailId;
  final String? linkedEmailSubject;
  final String? tagsStr;
  final String? subtasksJson;
  final String? commentsJson;
  final bool isRecurring;
  final int? recurrenceDays;
  final int? colorValue;
  final bool isFlagged;
  final bool isLocallyModified;

  /// Когда напомнить (v20). Отдельно от срока: «сдать отчёт в пятницу,
  /// напомнить в четверг в 10:00». ActiveSync — Tasks:ReminderTime.
  final DateTime? reminderAt;
  const Task({
    required this.id,
    required this.accountId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.dueDate,
    this.completedAt,
    required this.progress,
    this.assigneeEmail,
    this.assigneeName,
    this.linkedEmailId,
    this.linkedEmailSubject,
    this.tagsStr,
    this.subtasksJson,
    this.commentsJson,
    required this.isRecurring,
    this.recurrenceDays,
    this.colorValue,
    required this.isFlagged,
    required this.isLocallyModified,
    this.reminderAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<int>(status);
    map['priority'] = Variable<int>(priority);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['progress'] = Variable<int>(progress);
    if (!nullToAbsent || assigneeEmail != null) {
      map['assignee_email'] = Variable<String>(assigneeEmail);
    }
    if (!nullToAbsent || assigneeName != null) {
      map['assignee_name'] = Variable<String>(assigneeName);
    }
    if (!nullToAbsent || linkedEmailId != null) {
      map['linked_email_id'] = Variable<String>(linkedEmailId);
    }
    if (!nullToAbsent || linkedEmailSubject != null) {
      map['linked_email_subject'] = Variable<String>(linkedEmailSubject);
    }
    if (!nullToAbsent || tagsStr != null) {
      map['tags_str'] = Variable<String>(tagsStr);
    }
    if (!nullToAbsent || subtasksJson != null) {
      map['subtasks_json'] = Variable<String>(subtasksJson);
    }
    if (!nullToAbsent || commentsJson != null) {
      map['comments_json'] = Variable<String>(commentsJson);
    }
    map['is_recurring'] = Variable<bool>(isRecurring);
    if (!nullToAbsent || recurrenceDays != null) {
      map['recurrence_days'] = Variable<int>(recurrenceDays);
    }
    if (!nullToAbsent || colorValue != null) {
      map['color_value'] = Variable<int>(colorValue);
    }
    map['is_flagged'] = Variable<bool>(isFlagged);
    map['is_locally_modified'] = Variable<bool>(isLocallyModified);
    if (!nullToAbsent || reminderAt != null) {
      map['reminder_at'] = Variable<DateTime>(reminderAt);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      accountId: Value(accountId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      priority: Value(priority),
      createdAt: Value(createdAt),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      progress: Value(progress),
      assigneeEmail: assigneeEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(assigneeEmail),
      assigneeName: assigneeName == null && nullToAbsent
          ? const Value.absent()
          : Value(assigneeName),
      linkedEmailId: linkedEmailId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedEmailId),
      linkedEmailSubject: linkedEmailSubject == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedEmailSubject),
      tagsStr: tagsStr == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsStr),
      subtasksJson: subtasksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(subtasksJson),
      commentsJson: commentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(commentsJson),
      isRecurring: Value(isRecurring),
      recurrenceDays: recurrenceDays == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceDays),
      colorValue: colorValue == null && nullToAbsent
          ? const Value.absent()
          : Value(colorValue),
      isFlagged: Value(isFlagged),
      isLocallyModified: Value(isLocallyModified),
      reminderAt: reminderAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderAt),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<int>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      progress: serializer.fromJson<int>(json['progress']),
      assigneeEmail: serializer.fromJson<String?>(json['assigneeEmail']),
      assigneeName: serializer.fromJson<String?>(json['assigneeName']),
      linkedEmailId: serializer.fromJson<String?>(json['linkedEmailId']),
      linkedEmailSubject: serializer.fromJson<String?>(
        json['linkedEmailSubject'],
      ),
      tagsStr: serializer.fromJson<String?>(json['tagsStr']),
      subtasksJson: serializer.fromJson<String?>(json['subtasksJson']),
      commentsJson: serializer.fromJson<String?>(json['commentsJson']),
      isRecurring: serializer.fromJson<bool>(json['isRecurring']),
      recurrenceDays: serializer.fromJson<int?>(json['recurrenceDays']),
      colorValue: serializer.fromJson<int?>(json['colorValue']),
      isFlagged: serializer.fromJson<bool>(json['isFlagged']),
      isLocallyModified: serializer.fromJson<bool>(json['isLocallyModified']),
      reminderAt: serializer.fromJson<DateTime?>(json['reminderAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<int>(status),
      'priority': serializer.toJson<int>(priority),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'progress': serializer.toJson<int>(progress),
      'assigneeEmail': serializer.toJson<String?>(assigneeEmail),
      'assigneeName': serializer.toJson<String?>(assigneeName),
      'linkedEmailId': serializer.toJson<String?>(linkedEmailId),
      'linkedEmailSubject': serializer.toJson<String?>(linkedEmailSubject),
      'tagsStr': serializer.toJson<String?>(tagsStr),
      'subtasksJson': serializer.toJson<String?>(subtasksJson),
      'commentsJson': serializer.toJson<String?>(commentsJson),
      'isRecurring': serializer.toJson<bool>(isRecurring),
      'recurrenceDays': serializer.toJson<int?>(recurrenceDays),
      'colorValue': serializer.toJson<int?>(colorValue),
      'isFlagged': serializer.toJson<bool>(isFlagged),
      'isLocallyModified': serializer.toJson<bool>(isLocallyModified),
      'reminderAt': serializer.toJson<DateTime?>(reminderAt),
    };
  }

  Task copyWith({
    String? id,
    String? accountId,
    String? title,
    Value<String?> description = const Value.absent(),
    int? status,
    int? priority,
    DateTime? createdAt,
    Value<DateTime?> dueDate = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    int? progress,
    Value<String?> assigneeEmail = const Value.absent(),
    Value<String?> assigneeName = const Value.absent(),
    Value<String?> linkedEmailId = const Value.absent(),
    Value<String?> linkedEmailSubject = const Value.absent(),
    Value<String?> tagsStr = const Value.absent(),
    Value<String?> subtasksJson = const Value.absent(),
    Value<String?> commentsJson = const Value.absent(),
    bool? isRecurring,
    Value<int?> recurrenceDays = const Value.absent(),
    Value<int?> colorValue = const Value.absent(),
    bool? isFlagged,
    bool? isLocallyModified,
    Value<DateTime?> reminderAt = const Value.absent(),
  }) => Task(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    createdAt: createdAt ?? this.createdAt,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    progress: progress ?? this.progress,
    assigneeEmail: assigneeEmail.present
        ? assigneeEmail.value
        : this.assigneeEmail,
    assigneeName: assigneeName.present ? assigneeName.value : this.assigneeName,
    linkedEmailId: linkedEmailId.present
        ? linkedEmailId.value
        : this.linkedEmailId,
    linkedEmailSubject: linkedEmailSubject.present
        ? linkedEmailSubject.value
        : this.linkedEmailSubject,
    tagsStr: tagsStr.present ? tagsStr.value : this.tagsStr,
    subtasksJson: subtasksJson.present ? subtasksJson.value : this.subtasksJson,
    commentsJson: commentsJson.present ? commentsJson.value : this.commentsJson,
    isRecurring: isRecurring ?? this.isRecurring,
    recurrenceDays: recurrenceDays.present
        ? recurrenceDays.value
        : this.recurrenceDays,
    colorValue: colorValue.present ? colorValue.value : this.colorValue,
    isFlagged: isFlagged ?? this.isFlagged,
    isLocallyModified: isLocallyModified ?? this.isLocallyModified,
    reminderAt: reminderAt.present ? reminderAt.value : this.reminderAt,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      progress: data.progress.present ? data.progress.value : this.progress,
      assigneeEmail: data.assigneeEmail.present
          ? data.assigneeEmail.value
          : this.assigneeEmail,
      assigneeName: data.assigneeName.present
          ? data.assigneeName.value
          : this.assigneeName,
      linkedEmailId: data.linkedEmailId.present
          ? data.linkedEmailId.value
          : this.linkedEmailId,
      linkedEmailSubject: data.linkedEmailSubject.present
          ? data.linkedEmailSubject.value
          : this.linkedEmailSubject,
      tagsStr: data.tagsStr.present ? data.tagsStr.value : this.tagsStr,
      subtasksJson: data.subtasksJson.present
          ? data.subtasksJson.value
          : this.subtasksJson,
      commentsJson: data.commentsJson.present
          ? data.commentsJson.value
          : this.commentsJson,
      isRecurring: data.isRecurring.present
          ? data.isRecurring.value
          : this.isRecurring,
      recurrenceDays: data.recurrenceDays.present
          ? data.recurrenceDays.value
          : this.recurrenceDays,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      isFlagged: data.isFlagged.present ? data.isFlagged.value : this.isFlagged,
      isLocallyModified: data.isLocallyModified.present
          ? data.isLocallyModified.value
          : this.isLocallyModified,
      reminderAt: data.reminderAt.present
          ? data.reminderAt.value
          : this.reminderAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('createdAt: $createdAt, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('progress: $progress, ')
          ..write('assigneeEmail: $assigneeEmail, ')
          ..write('assigneeName: $assigneeName, ')
          ..write('linkedEmailId: $linkedEmailId, ')
          ..write('linkedEmailSubject: $linkedEmailSubject, ')
          ..write('tagsStr: $tagsStr, ')
          ..write('subtasksJson: $subtasksJson, ')
          ..write('commentsJson: $commentsJson, ')
          ..write('isRecurring: $isRecurring, ')
          ..write('recurrenceDays: $recurrenceDays, ')
          ..write('colorValue: $colorValue, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('reminderAt: $reminderAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    accountId,
    title,
    description,
    status,
    priority,
    createdAt,
    dueDate,
    completedAt,
    progress,
    assigneeEmail,
    assigneeName,
    linkedEmailId,
    linkedEmailSubject,
    tagsStr,
    subtasksJson,
    commentsJson,
    isRecurring,
    recurrenceDays,
    colorValue,
    isFlagged,
    isLocallyModified,
    reminderAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.createdAt == this.createdAt &&
          other.dueDate == this.dueDate &&
          other.completedAt == this.completedAt &&
          other.progress == this.progress &&
          other.assigneeEmail == this.assigneeEmail &&
          other.assigneeName == this.assigneeName &&
          other.linkedEmailId == this.linkedEmailId &&
          other.linkedEmailSubject == this.linkedEmailSubject &&
          other.tagsStr == this.tagsStr &&
          other.subtasksJson == this.subtasksJson &&
          other.commentsJson == this.commentsJson &&
          other.isRecurring == this.isRecurring &&
          other.recurrenceDays == this.recurrenceDays &&
          other.colorValue == this.colorValue &&
          other.isFlagged == this.isFlagged &&
          other.isLocallyModified == this.isLocallyModified &&
          other.reminderAt == this.reminderAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> title;
  final Value<String?> description;
  final Value<int> status;
  final Value<int> priority;
  final Value<DateTime> createdAt;
  final Value<DateTime?> dueDate;
  final Value<DateTime?> completedAt;
  final Value<int> progress;
  final Value<String?> assigneeEmail;
  final Value<String?> assigneeName;
  final Value<String?> linkedEmailId;
  final Value<String?> linkedEmailSubject;
  final Value<String?> tagsStr;
  final Value<String?> subtasksJson;
  final Value<String?> commentsJson;
  final Value<bool> isRecurring;
  final Value<int?> recurrenceDays;
  final Value<int?> colorValue;
  final Value<bool> isFlagged;
  final Value<bool> isLocallyModified;
  final Value<DateTime?> reminderAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.progress = const Value.absent(),
    this.assigneeEmail = const Value.absent(),
    this.assigneeName = const Value.absent(),
    this.linkedEmailId = const Value.absent(),
    this.linkedEmailSubject = const Value.absent(),
    this.tagsStr = const Value.absent(),
    this.subtasksJson = const Value.absent(),
    this.commentsJson = const Value.absent(),
    this.isRecurring = const Value.absent(),
    this.recurrenceDays = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.reminderAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String accountId,
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    required DateTime createdAt,
    this.dueDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.progress = const Value.absent(),
    this.assigneeEmail = const Value.absent(),
    this.assigneeName = const Value.absent(),
    this.linkedEmailId = const Value.absent(),
    this.linkedEmailSubject = const Value.absent(),
    this.tagsStr = const Value.absent(),
    this.subtasksJson = const Value.absent(),
    this.commentsJson = const Value.absent(),
    this.isRecurring = const Value.absent(),
    this.recurrenceDays = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.reminderAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<int>? status,
    Expression<int>? priority,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? dueDate,
    Expression<DateTime>? completedAt,
    Expression<int>? progress,
    Expression<String>? assigneeEmail,
    Expression<String>? assigneeName,
    Expression<String>? linkedEmailId,
    Expression<String>? linkedEmailSubject,
    Expression<String>? tagsStr,
    Expression<String>? subtasksJson,
    Expression<String>? commentsJson,
    Expression<bool>? isRecurring,
    Expression<int>? recurrenceDays,
    Expression<int>? colorValue,
    Expression<bool>? isFlagged,
    Expression<bool>? isLocallyModified,
    Expression<DateTime>? reminderAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (createdAt != null) 'created_at': createdAt,
      if (dueDate != null) 'due_date': dueDate,
      if (completedAt != null) 'completed_at': completedAt,
      if (progress != null) 'progress': progress,
      if (assigneeEmail != null) 'assignee_email': assigneeEmail,
      if (assigneeName != null) 'assignee_name': assigneeName,
      if (linkedEmailId != null) 'linked_email_id': linkedEmailId,
      if (linkedEmailSubject != null)
        'linked_email_subject': linkedEmailSubject,
      if (tagsStr != null) 'tags_str': tagsStr,
      if (subtasksJson != null) 'subtasks_json': subtasksJson,
      if (commentsJson != null) 'comments_json': commentsJson,
      if (isRecurring != null) 'is_recurring': isRecurring,
      if (recurrenceDays != null) 'recurrence_days': recurrenceDays,
      if (colorValue != null) 'color_value': colorValue,
      if (isFlagged != null) 'is_flagged': isFlagged,
      if (isLocallyModified != null) 'is_locally_modified': isLocallyModified,
      if (reminderAt != null) 'reminder_at': reminderAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? title,
    Value<String?>? description,
    Value<int>? status,
    Value<int>? priority,
    Value<DateTime>? createdAt,
    Value<DateTime?>? dueDate,
    Value<DateTime?>? completedAt,
    Value<int>? progress,
    Value<String?>? assigneeEmail,
    Value<String?>? assigneeName,
    Value<String?>? linkedEmailId,
    Value<String?>? linkedEmailSubject,
    Value<String?>? tagsStr,
    Value<String?>? subtasksJson,
    Value<String?>? commentsJson,
    Value<bool>? isRecurring,
    Value<int?>? recurrenceDays,
    Value<int?>? colorValue,
    Value<bool>? isFlagged,
    Value<bool>? isLocallyModified,
    Value<DateTime?>? reminderAt,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      progress: progress ?? this.progress,
      assigneeEmail: assigneeEmail ?? this.assigneeEmail,
      assigneeName: assigneeName ?? this.assigneeName,
      linkedEmailId: linkedEmailId ?? this.linkedEmailId,
      linkedEmailSubject: linkedEmailSubject ?? this.linkedEmailSubject,
      tagsStr: tagsStr ?? this.tagsStr,
      subtasksJson: subtasksJson ?? this.subtasksJson,
      commentsJson: commentsJson ?? this.commentsJson,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceDays: recurrenceDays ?? this.recurrenceDays,
      colorValue: colorValue ?? this.colorValue,
      isFlagged: isFlagged ?? this.isFlagged,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      reminderAt: reminderAt ?? this.reminderAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (progress.present) {
      map['progress'] = Variable<int>(progress.value);
    }
    if (assigneeEmail.present) {
      map['assignee_email'] = Variable<String>(assigneeEmail.value);
    }
    if (assigneeName.present) {
      map['assignee_name'] = Variable<String>(assigneeName.value);
    }
    if (linkedEmailId.present) {
      map['linked_email_id'] = Variable<String>(linkedEmailId.value);
    }
    if (linkedEmailSubject.present) {
      map['linked_email_subject'] = Variable<String>(linkedEmailSubject.value);
    }
    if (tagsStr.present) {
      map['tags_str'] = Variable<String>(tagsStr.value);
    }
    if (subtasksJson.present) {
      map['subtasks_json'] = Variable<String>(subtasksJson.value);
    }
    if (commentsJson.present) {
      map['comments_json'] = Variable<String>(commentsJson.value);
    }
    if (isRecurring.present) {
      map['is_recurring'] = Variable<bool>(isRecurring.value);
    }
    if (recurrenceDays.present) {
      map['recurrence_days'] = Variable<int>(recurrenceDays.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isFlagged.present) {
      map['is_flagged'] = Variable<bool>(isFlagged.value);
    }
    if (isLocallyModified.present) {
      map['is_locally_modified'] = Variable<bool>(isLocallyModified.value);
    }
    if (reminderAt.present) {
      map['reminder_at'] = Variable<DateTime>(reminderAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('createdAt: $createdAt, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('progress: $progress, ')
          ..write('assigneeEmail: $assigneeEmail, ')
          ..write('assigneeName: $assigneeName, ')
          ..write('linkedEmailId: $linkedEmailId, ')
          ..write('linkedEmailSubject: $linkedEmailSubject, ')
          ..write('tagsStr: $tagsStr, ')
          ..write('subtasksJson: $subtasksJson, ')
          ..write('commentsJson: $commentsJson, ')
          ..write('isRecurring: $isRecurring, ')
          ..write('recurrenceDays: $recurrenceDays, ')
          ..write('colorValue: $colorValue, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('reminderAt: $reminderAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    operationType,
    targetId,
    payloadJson,
    priority,
    retryCount,
    createdAt,
    lastAttemptAt,
    errorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  final int id;
  final String accountId;
  final String operationType;
  final String targetId;
  final String payloadJson;
  final int priority;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? errorMessage;
  const SyncQueueData({
    required this.id,
    required this.accountId,
    required this.operationType,
    required this.targetId,
    required this.payloadJson,
    required this.priority,
    required this.retryCount,
    required this.createdAt,
    this.lastAttemptAt,
    this.errorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['operation_type'] = Variable<String>(operationType);
    map['target_id'] = Variable<String>(targetId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['priority'] = Variable<int>(priority);
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      accountId: Value(accountId),
      operationType: Value(operationType),
      targetId: Value(targetId),
      payloadJson: Value(payloadJson),
      priority: Value(priority),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
    );
  }

  factory SyncQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      targetId: serializer.fromJson<String>(json['targetId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      priority: serializer.fromJson<int>(json['priority']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<String>(accountId),
      'operationType': serializer.toJson<String>(operationType),
      'targetId': serializer.toJson<String>(targetId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'priority': serializer.toJson<int>(priority),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  SyncQueueData copyWith({
    int? id,
    String? accountId,
    String? operationType,
    String? targetId,
    String? payloadJson,
    int? priority,
    int? retryCount,
    DateTime? createdAt,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
  }) => SyncQueueData(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    operationType: operationType ?? this.operationType,
    targetId: targetId ?? this.targetId,
    payloadJson: payloadJson ?? this.payloadJson,
    priority: priority ?? this.priority,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
  );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      priority: data.priority.present ? data.priority.value : this.priority,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('operationType: $operationType, ')
          ..write('targetId: $targetId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('priority: $priority, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    operationType,
    targetId,
    payloadJson,
    priority,
    retryCount,
    createdAt,
    lastAttemptAt,
    errorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.operationType == this.operationType &&
          other.targetId == this.targetId &&
          other.payloadJson == this.payloadJson &&
          other.priority == this.priority &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.errorMessage == this.errorMessage);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> operationType;
  final Value<String> targetId;
  final Value<String> payloadJson;
  final Value<int> priority;
  final Value<int> retryCount;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> errorMessage;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.priority = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String operationType,
    required String targetId,
    required String payloadJson,
    this.priority = const Value.absent(),
    this.retryCount = const Value.absent(),
    required DateTime createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
  }) : accountId = Value(accountId),
       operationType = Value(operationType),
       targetId = Value(targetId),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<SyncQueueData> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? operationType,
    Expression<String>? targetId,
    Expression<String>? payloadJson,
    Expression<int>? priority,
    Expression<int>? retryCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? errorMessage,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (operationType != null) 'operation_type': operationType,
      if (targetId != null) 'target_id': targetId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (priority != null) 'priority': priority,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (errorMessage != null) 'error_message': errorMessage,
    });
  }

  SyncQueueCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? operationType,
    Value<String>? targetId,
    Value<String>? payloadJson,
    Value<int>? priority,
    Value<int>? retryCount,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? errorMessage,
  }) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      operationType: operationType ?? this.operationType,
      targetId: targetId ?? this.targetId,
      payloadJson: payloadJson ?? this.payloadJson,
      priority: priority ?? this.priority,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('operationType: $operationType, ')
          ..write('targetId: $targetId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('priority: $priority, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }
}

class $AuditLogTable extends AuditLog
    with TableInfo<$AuditLogTable, AuditLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailsMeta = const VerificationMeta(
    'details',
  );
  @override
  late final GeneratedColumn<String> details = GeneratedColumn<String>(
    'details',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ipAddressMeta = const VerificationMeta(
    'ipAddress',
  );
  @override
  late final GeneratedColumn<String> ipAddress = GeneratedColumn<String>(
    'ip_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    action,
    details,
    ipAddress,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('details')) {
      context.handle(
        _detailsMeta,
        details.isAcceptableOrUnknown(data['details']!, _detailsMeta),
      );
    }
    if (data.containsKey('ip_address')) {
      context.handle(
        _ipAddressMeta,
        ipAddress.isAcceptableOrUnknown(data['ip_address']!, _ipAddressMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditLogData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      details: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details'],
      ),
      ipAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ip_address'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $AuditLogTable createAlias(String alias) {
    return $AuditLogTable(attachedDatabase, alias);
  }
}

class AuditLogData extends DataClass implements Insertable<AuditLogData> {
  final int id;
  final String? accountId;
  final String action;
  final String? details;
  final String? ipAddress;
  final DateTime timestamp;
  const AuditLogData({
    required this.id,
    this.accountId,
    required this.action,
    this.details,
    this.ipAddress,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || details != null) {
      map['details'] = Variable<String>(details);
    }
    if (!nullToAbsent || ipAddress != null) {
      map['ip_address'] = Variable<String>(ipAddress);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  AuditLogCompanion toCompanion(bool nullToAbsent) {
    return AuditLogCompanion(
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      action: Value(action),
      details: details == null && nullToAbsent
          ? const Value.absent()
          : Value(details),
      ipAddress: ipAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(ipAddress),
      timestamp: Value(timestamp),
    );
  }

  factory AuditLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditLogData(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      action: serializer.fromJson<String>(json['action']),
      details: serializer.fromJson<String?>(json['details']),
      ipAddress: serializer.fromJson<String?>(json['ipAddress']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'action': serializer.toJson<String>(action),
      'details': serializer.toJson<String?>(details),
      'ipAddress': serializer.toJson<String?>(ipAddress),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  AuditLogData copyWith({
    int? id,
    Value<String?> accountId = const Value.absent(),
    String? action,
    Value<String?> details = const Value.absent(),
    Value<String?> ipAddress = const Value.absent(),
    DateTime? timestamp,
  }) => AuditLogData(
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    action: action ?? this.action,
    details: details.present ? details.value : this.details,
    ipAddress: ipAddress.present ? ipAddress.value : this.ipAddress,
    timestamp: timestamp ?? this.timestamp,
  );
  AuditLogData copyWithCompanion(AuditLogCompanion data) {
    return AuditLogData(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      action: data.action.present ? data.action.value : this.action,
      details: data.details.present ? data.details.value : this.details,
      ipAddress: data.ipAddress.present ? data.ipAddress.value : this.ipAddress,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogData(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('action: $action, ')
          ..write('details: $details, ')
          ..write('ipAddress: $ipAddress, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountId, action, details, ipAddress, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditLogData &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.action == this.action &&
          other.details == this.details &&
          other.ipAddress == this.ipAddress &&
          other.timestamp == this.timestamp);
}

class AuditLogCompanion extends UpdateCompanion<AuditLogData> {
  final Value<int> id;
  final Value<String?> accountId;
  final Value<String> action;
  final Value<String?> details;
  final Value<String?> ipAddress;
  final Value<DateTime> timestamp;
  const AuditLogCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.action = const Value.absent(),
    this.details = const Value.absent(),
    this.ipAddress = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  AuditLogCompanion.insert({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    required String action,
    this.details = const Value.absent(),
    this.ipAddress = const Value.absent(),
    required DateTime timestamp,
  }) : action = Value(action),
       timestamp = Value(timestamp);
  static Insertable<AuditLogData> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? action,
    Expression<String>? details,
    Expression<String>? ipAddress,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (action != null) 'action': action,
      if (details != null) 'details': details,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  AuditLogCompanion copyWith({
    Value<int>? id,
    Value<String?>? accountId,
    Value<String>? action,
    Value<String?>? details,
    Value<String?>? ipAddress,
    Value<DateTime>? timestamp,
  }) {
    return AuditLogCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      action: action ?? this.action,
      details: details ?? this.details,
      ipAddress: ipAddress ?? this.ipAddress,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (details.present) {
      map['details'] = Variable<String>(details.value);
    }
    if (ipAddress.present) {
      map['ip_address'] = Variable<String>(ipAddress.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('action: $action, ')
          ..write('details: $details, ')
          ..write('ipAddress: $ipAddress, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $SignaturesTable extends Signatures
    with TableInfo<$SignaturesTable, Signature> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignaturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _htmlContentMeta = const VerificationMeta(
    'htmlContent',
  );
  @override
  late final GeneratedColumn<String> htmlContent = GeneratedColumn<String>(
    'html_content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plainContentMeta = const VerificationMeta(
    'plainContent',
  );
  @override
  late final GeneratedColumn<String> plainContent = GeneratedColumn<String>(
    'plain_content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _useForNewEmailsMeta = const VerificationMeta(
    'useForNewEmails',
  );
  @override
  late final GeneratedColumn<bool> useForNewEmails = GeneratedColumn<bool>(
    'use_for_new_emails',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_for_new_emails" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _useForRepliesMeta = const VerificationMeta(
    'useForReplies',
  );
  @override
  late final GeneratedColumn<bool> useForReplies = GeneratedColumn<bool>(
    'use_for_replies',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_for_replies" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _useForForwardsMeta = const VerificationMeta(
    'useForForwards',
  );
  @override
  late final GeneratedColumn<bool> useForForwards = GeneratedColumn<bool>(
    'use_for_forwards',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_for_forwards" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    name,
    htmlContent,
    plainContent,
    isDefault,
    useForNewEmails,
    useForReplies,
    useForForwards,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signatures';
  @override
  VerificationContext validateIntegrity(
    Insertable<Signature> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('html_content')) {
      context.handle(
        _htmlContentMeta,
        htmlContent.isAcceptableOrUnknown(
          data['html_content']!,
          _htmlContentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_htmlContentMeta);
    }
    if (data.containsKey('plain_content')) {
      context.handle(
        _plainContentMeta,
        plainContent.isAcceptableOrUnknown(
          data['plain_content']!,
          _plainContentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plainContentMeta);
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('use_for_new_emails')) {
      context.handle(
        _useForNewEmailsMeta,
        useForNewEmails.isAcceptableOrUnknown(
          data['use_for_new_emails']!,
          _useForNewEmailsMeta,
        ),
      );
    }
    if (data.containsKey('use_for_replies')) {
      context.handle(
        _useForRepliesMeta,
        useForReplies.isAcceptableOrUnknown(
          data['use_for_replies']!,
          _useForRepliesMeta,
        ),
      );
    }
    if (data.containsKey('use_for_forwards')) {
      context.handle(
        _useForForwardsMeta,
        useForForwards.isAcceptableOrUnknown(
          data['use_for_forwards']!,
          _useForForwardsMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Signature map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Signature(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      htmlContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}html_content'],
      )!,
      plainContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plain_content'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      useForNewEmails: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_for_new_emails'],
      )!,
      useForReplies: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_for_replies'],
      )!,
      useForForwards: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_for_forwards'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $SignaturesTable createAlias(String alias) {
    return $SignaturesTable(attachedDatabase, alias);
  }
}

class Signature extends DataClass implements Insertable<Signature> {
  final String id;
  final String? accountId;
  final String name;
  final String htmlContent;
  final String plainContent;
  final bool isDefault;
  final bool useForNewEmails;
  final bool useForReplies;
  final bool useForForwards;
  final int sortOrder;
  const Signature({
    required this.id,
    this.accountId,
    required this.name,
    required this.htmlContent,
    required this.plainContent,
    required this.isDefault,
    required this.useForNewEmails,
    required this.useForReplies,
    required this.useForForwards,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['name'] = Variable<String>(name);
    map['html_content'] = Variable<String>(htmlContent);
    map['plain_content'] = Variable<String>(plainContent);
    map['is_default'] = Variable<bool>(isDefault);
    map['use_for_new_emails'] = Variable<bool>(useForNewEmails);
    map['use_for_replies'] = Variable<bool>(useForReplies);
    map['use_for_forwards'] = Variable<bool>(useForForwards);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SignaturesCompanion toCompanion(bool nullToAbsent) {
    return SignaturesCompanion(
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      name: Value(name),
      htmlContent: Value(htmlContent),
      plainContent: Value(plainContent),
      isDefault: Value(isDefault),
      useForNewEmails: Value(useForNewEmails),
      useForReplies: Value(useForReplies),
      useForForwards: Value(useForForwards),
      sortOrder: Value(sortOrder),
    );
  }

  factory Signature.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Signature(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      name: serializer.fromJson<String>(json['name']),
      htmlContent: serializer.fromJson<String>(json['htmlContent']),
      plainContent: serializer.fromJson<String>(json['plainContent']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      useForNewEmails: serializer.fromJson<bool>(json['useForNewEmails']),
      useForReplies: serializer.fromJson<bool>(json['useForReplies']),
      useForForwards: serializer.fromJson<bool>(json['useForForwards']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'name': serializer.toJson<String>(name),
      'htmlContent': serializer.toJson<String>(htmlContent),
      'plainContent': serializer.toJson<String>(plainContent),
      'isDefault': serializer.toJson<bool>(isDefault),
      'useForNewEmails': serializer.toJson<bool>(useForNewEmails),
      'useForReplies': serializer.toJson<bool>(useForReplies),
      'useForForwards': serializer.toJson<bool>(useForForwards),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Signature copyWith({
    String? id,
    Value<String?> accountId = const Value.absent(),
    String? name,
    String? htmlContent,
    String? plainContent,
    bool? isDefault,
    bool? useForNewEmails,
    bool? useForReplies,
    bool? useForForwards,
    int? sortOrder,
  }) => Signature(
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    name: name ?? this.name,
    htmlContent: htmlContent ?? this.htmlContent,
    plainContent: plainContent ?? this.plainContent,
    isDefault: isDefault ?? this.isDefault,
    useForNewEmails: useForNewEmails ?? this.useForNewEmails,
    useForReplies: useForReplies ?? this.useForReplies,
    useForForwards: useForForwards ?? this.useForForwards,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Signature copyWithCompanion(SignaturesCompanion data) {
    return Signature(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      name: data.name.present ? data.name.value : this.name,
      htmlContent: data.htmlContent.present
          ? data.htmlContent.value
          : this.htmlContent,
      plainContent: data.plainContent.present
          ? data.plainContent.value
          : this.plainContent,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      useForNewEmails: data.useForNewEmails.present
          ? data.useForNewEmails.value
          : this.useForNewEmails,
      useForReplies: data.useForReplies.present
          ? data.useForReplies.value
          : this.useForReplies,
      useForForwards: data.useForForwards.present
          ? data.useForForwards.value
          : this.useForForwards,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Signature(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('name: $name, ')
          ..write('htmlContent: $htmlContent, ')
          ..write('plainContent: $plainContent, ')
          ..write('isDefault: $isDefault, ')
          ..write('useForNewEmails: $useForNewEmails, ')
          ..write('useForReplies: $useForReplies, ')
          ..write('useForForwards: $useForForwards, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    name,
    htmlContent,
    plainContent,
    isDefault,
    useForNewEmails,
    useForReplies,
    useForForwards,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Signature &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.name == this.name &&
          other.htmlContent == this.htmlContent &&
          other.plainContent == this.plainContent &&
          other.isDefault == this.isDefault &&
          other.useForNewEmails == this.useForNewEmails &&
          other.useForReplies == this.useForReplies &&
          other.useForForwards == this.useForForwards &&
          other.sortOrder == this.sortOrder);
}

class SignaturesCompanion extends UpdateCompanion<Signature> {
  final Value<String> id;
  final Value<String?> accountId;
  final Value<String> name;
  final Value<String> htmlContent;
  final Value<String> plainContent;
  final Value<bool> isDefault;
  final Value<bool> useForNewEmails;
  final Value<bool> useForReplies;
  final Value<bool> useForForwards;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SignaturesCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.name = const Value.absent(),
    this.htmlContent = const Value.absent(),
    this.plainContent = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.useForNewEmails = const Value.absent(),
    this.useForReplies = const Value.absent(),
    this.useForForwards = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignaturesCompanion.insert({
    required String id,
    this.accountId = const Value.absent(),
    required String name,
    required String htmlContent,
    required String plainContent,
    this.isDefault = const Value.absent(),
    this.useForNewEmails = const Value.absent(),
    this.useForReplies = const Value.absent(),
    this.useForForwards = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       htmlContent = Value(htmlContent),
       plainContent = Value(plainContent);
  static Insertable<Signature> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? name,
    Expression<String>? htmlContent,
    Expression<String>? plainContent,
    Expression<bool>? isDefault,
    Expression<bool>? useForNewEmails,
    Expression<bool>? useForReplies,
    Expression<bool>? useForForwards,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (name != null) 'name': name,
      if (htmlContent != null) 'html_content': htmlContent,
      if (plainContent != null) 'plain_content': plainContent,
      if (isDefault != null) 'is_default': isDefault,
      if (useForNewEmails != null) 'use_for_new_emails': useForNewEmails,
      if (useForReplies != null) 'use_for_replies': useForReplies,
      if (useForForwards != null) 'use_for_forwards': useForForwards,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignaturesCompanion copyWith({
    Value<String>? id,
    Value<String?>? accountId,
    Value<String>? name,
    Value<String>? htmlContent,
    Value<String>? plainContent,
    Value<bool>? isDefault,
    Value<bool>? useForNewEmails,
    Value<bool>? useForReplies,
    Value<bool>? useForForwards,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return SignaturesCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      htmlContent: htmlContent ?? this.htmlContent,
      plainContent: plainContent ?? this.plainContent,
      isDefault: isDefault ?? this.isDefault,
      useForNewEmails: useForNewEmails ?? this.useForNewEmails,
      useForReplies: useForReplies ?? this.useForReplies,
      useForForwards: useForForwards ?? this.useForForwards,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (htmlContent.present) {
      map['html_content'] = Variable<String>(htmlContent.value);
    }
    if (plainContent.present) {
      map['plain_content'] = Variable<String>(plainContent.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (useForNewEmails.present) {
      map['use_for_new_emails'] = Variable<bool>(useForNewEmails.value);
    }
    if (useForReplies.present) {
      map['use_for_replies'] = Variable<bool>(useForReplies.value);
    }
    if (useForForwards.present) {
      map['use_for_forwards'] = Variable<bool>(useForForwards.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignaturesCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('name: $name, ')
          ..write('htmlContent: $htmlContent, ')
          ..write('plainContent: $plainContent, ')
          ..write('isDefault: $isDefault, ')
          ..write('useForNewEmails: $useForNewEmails, ')
          ..write('useForReplies: $useForReplies, ')
          ..write('useForForwards: $useForForwards, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _categoriesStrMeta = const VerificationMeta(
    'categoriesStr',
  );
  @override
  late final GeneratedColumn<String> categoriesStr = GeneratedColumn<String>(
    'categories_str',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isLocallyModifiedMeta = const VerificationMeta(
    'isLocallyModified',
  );
  @override
  late final GeneratedColumn<bool> isLocallyModified = GeneratedColumn<bool>(
    'is_locally_modified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_locally_modified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    title,
    body,
    categoriesStr,
    colorValue,
    serverId,
    createdAt,
    modifiedAt,
    isLocallyModified,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('categories_str')) {
      context.handle(
        _categoriesStrMeta,
        categoriesStr.isAcceptableOrUnknown(
          data['categories_str']!,
          _categoriesStrMeta,
        ),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('is_locally_modified')) {
      context.handle(
        _isLocallyModifiedMeta,
        isLocallyModified.isAcceptableOrUnknown(
          data['is_locally_modified']!,
          _isLocallyModifiedMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      categoriesStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}categories_str'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      ),
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      isLocallyModified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_locally_modified'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final String id;
  final String? accountId;
  final String title;
  final String body;
  final String? categoriesStr;
  final int? colorValue;
  final String? serverId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isLocallyModified;
  final bool isDeleted;
  const Note({
    required this.id,
    this.accountId,
    required this.title,
    required this.body,
    this.categoriesStr,
    this.colorValue,
    this.serverId,
    required this.createdAt,
    required this.modifiedAt,
    required this.isLocallyModified,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || categoriesStr != null) {
      map['categories_str'] = Variable<String>(categoriesStr);
    }
    if (!nullToAbsent || colorValue != null) {
      map['color_value'] = Variable<int>(colorValue);
    }
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['is_locally_modified'] = Variable<bool>(isLocallyModified);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      title: Value(title),
      body: Value(body),
      categoriesStr: categoriesStr == null && nullToAbsent
          ? const Value.absent()
          : Value(categoriesStr),
      colorValue: colorValue == null && nullToAbsent
          ? const Value.absent()
          : Value(colorValue),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      isLocallyModified: Value(isLocallyModified),
      isDeleted: Value(isDeleted),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      categoriesStr: serializer.fromJson<String?>(json['categoriesStr']),
      colorValue: serializer.fromJson<int?>(json['colorValue']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      isLocallyModified: serializer.fromJson<bool>(json['isLocallyModified']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'categoriesStr': serializer.toJson<String?>(categoriesStr),
      'colorValue': serializer.toJson<int?>(colorValue),
      'serverId': serializer.toJson<String?>(serverId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'isLocallyModified': serializer.toJson<bool>(isLocallyModified),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Note copyWith({
    String? id,
    Value<String?> accountId = const Value.absent(),
    String? title,
    String? body,
    Value<String?> categoriesStr = const Value.absent(),
    Value<int?> colorValue = const Value.absent(),
    Value<String?> serverId = const Value.absent(),
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isLocallyModified,
    bool? isDeleted,
  }) => Note(
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    title: title ?? this.title,
    body: body ?? this.body,
    categoriesStr: categoriesStr.present
        ? categoriesStr.value
        : this.categoriesStr,
    colorValue: colorValue.present ? colorValue.value : this.colorValue,
    serverId: serverId.present ? serverId.value : this.serverId,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    isLocallyModified: isLocallyModified ?? this.isLocallyModified,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      categoriesStr: data.categoriesStr.present
          ? data.categoriesStr.value
          : this.categoriesStr,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      isLocallyModified: data.isLocallyModified.present
          ? data.isLocallyModified.value
          : this.isLocallyModified,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('categoriesStr: $categoriesStr, ')
          ..write('colorValue: $colorValue, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    title,
    body,
    categoriesStr,
    colorValue,
    serverId,
    createdAt,
    modifiedAt,
    isLocallyModified,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.title == this.title &&
          other.body == this.body &&
          other.categoriesStr == this.categoriesStr &&
          other.colorValue == this.colorValue &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.isLocallyModified == this.isLocallyModified &&
          other.isDeleted == this.isDeleted);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String?> accountId;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> categoriesStr;
  final Value<int?> colorValue;
  final Value<String?> serverId;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<bool> isLocallyModified;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.categoriesStr = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.isLocallyModified = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    this.accountId = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.categoriesStr = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.serverId = const Value.absent(),
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.isLocallyModified = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? categoriesStr,
    Expression<int>? colorValue,
    Expression<String>? serverId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<bool>? isLocallyModified,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (categoriesStr != null) 'categories_str': categoriesStr,
      if (colorValue != null) 'color_value': colorValue,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (isLocallyModified != null) 'is_locally_modified': isLocallyModified,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String?>? accountId,
    Value<String>? title,
    Value<String>? body,
    Value<String?>? categoriesStr,
    Value<int?>? colorValue,
    Value<String?>? serverId,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<bool>? isLocallyModified,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      title: title ?? this.title,
      body: body ?? this.body,
      categoriesStr: categoriesStr ?? this.categoriesStr,
      colorValue: colorValue ?? this.colorValue,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (categoriesStr.present) {
      map['categories_str'] = Variable<String>(categoriesStr.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (isLocallyModified.present) {
      map['is_locally_modified'] = Variable<bool>(isLocallyModified.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('categoriesStr: $categoriesStr, ')
          ..write('colorValue: $colorValue, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('isLocallyModified: $isLocallyModified, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentsTable extends Assignments
    with TableInfo<$AssignmentsTable, Assignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _sourceEmailIdMeta = const VerificationMeta(
    'sourceEmailId',
  );
  @override
  late final GeneratedColumn<String> sourceEmailId = GeneratedColumn<String>(
    'source_email_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recurrenceRuleMeta = const VerificationMeta(
    'recurrenceRule',
  );
  @override
  late final GeneratedColumn<String> recurrenceRule = GeneratedColumn<String>(
    'recurrence_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _ownerEmailMeta = const VerificationMeta(
    'ownerEmail',
  );
  @override
  late final GeneratedColumn<String> ownerEmail = GeneratedColumn<String>(
    'owner_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextCheckpointAtMeta = const VerificationMeta(
    'nextCheckpointAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextCheckpointAt =
      GeneratedColumn<DateTime>(
        'next_checkpoint_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _parentAssignmentIdMeta =
      const VerificationMeta('parentAssignmentId');
  @override
  late final GeneratedColumn<String> parentAssignmentId =
      GeneratedColumn<String>(
        'parent_assignment_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isTemplateMeta = const VerificationMeta(
    'isTemplate',
  );
  @override
  late final GeneratedColumn<bool> isTemplate = GeneratedColumn<bool>(
    'is_template',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_template" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _autoDecideEnabledMeta = const VerificationMeta(
    'autoDecideEnabled',
  );
  @override
  late final GeneratedColumn<bool> autoDecideEnabled = GeneratedColumn<bool>(
    'auto_decide_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_decide_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    sourceEmailId,
    title,
    description,
    kind,
    recurrenceRule,
    status,
    priority,
    ownerEmail,
    dueAt,
    nextCheckpointAt,
    parentAssignmentId,
    isTemplate,
    autoDecideEnabled,
    createdAt,
    updatedAt,
    isArchived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Assignment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('source_email_id')) {
      context.handle(
        _sourceEmailIdMeta,
        sourceEmailId.isAcceptableOrUnknown(
          data['source_email_id']!,
          _sourceEmailIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('recurrence_rule')) {
      context.handle(
        _recurrenceRuleMeta,
        recurrenceRule.isAcceptableOrUnknown(
          data['recurrence_rule']!,
          _recurrenceRuleMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('owner_email')) {
      context.handle(
        _ownerEmailMeta,
        ownerEmail.isAcceptableOrUnknown(data['owner_email']!, _ownerEmailMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerEmailMeta);
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('next_checkpoint_at')) {
      context.handle(
        _nextCheckpointAtMeta,
        nextCheckpointAt.isAcceptableOrUnknown(
          data['next_checkpoint_at']!,
          _nextCheckpointAtMeta,
        ),
      );
    }
    if (data.containsKey('parent_assignment_id')) {
      context.handle(
        _parentAssignmentIdMeta,
        parentAssignmentId.isAcceptableOrUnknown(
          data['parent_assignment_id']!,
          _parentAssignmentIdMeta,
        ),
      );
    }
    if (data.containsKey('is_template')) {
      context.handle(
        _isTemplateMeta,
        isTemplate.isAcceptableOrUnknown(data['is_template']!, _isTemplateMeta),
      );
    }
    if (data.containsKey('auto_decide_enabled')) {
      context.handle(
        _autoDecideEnabledMeta,
        autoDecideEnabled.isAcceptableOrUnknown(
          data['auto_decide_enabled']!,
          _autoDecideEnabledMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Assignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Assignment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      sourceEmailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_email_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      recurrenceRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_rule'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      ownerEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_email'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      nextCheckpointAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_checkpoint_at'],
      ),
      parentAssignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_assignment_id'],
      ),
      isTemplate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_template'],
      )!,
      autoDecideEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_decide_enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  $AssignmentsTable createAlias(String alias) {
    return $AssignmentsTable(attachedDatabase, alias);
  }
}

class Assignment extends DataClass implements Insertable<Assignment> {
  final String id;
  final String accountId;
  final String? sourceEmailId;
  final String title;
  final String? description;
  final int kind;
  final String? recurrenceRule;
  final int status;
  final int priority;
  final String ownerEmail;
  final DateTime? dueAt;
  final DateTime? nextCheckpointAt;
  final String? parentAssignmentId;
  final bool isTemplate;
  final bool autoDecideEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  const Assignment({
    required this.id,
    required this.accountId,
    this.sourceEmailId,
    required this.title,
    this.description,
    required this.kind,
    this.recurrenceRule,
    required this.status,
    required this.priority,
    required this.ownerEmail,
    this.dueAt,
    this.nextCheckpointAt,
    this.parentAssignmentId,
    required this.isTemplate,
    required this.autoDecideEnabled,
    required this.createdAt,
    required this.updatedAt,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || sourceEmailId != null) {
      map['source_email_id'] = Variable<String>(sourceEmailId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['kind'] = Variable<int>(kind);
    if (!nullToAbsent || recurrenceRule != null) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule);
    }
    map['status'] = Variable<int>(status);
    map['priority'] = Variable<int>(priority);
    map['owner_email'] = Variable<String>(ownerEmail);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    if (!nullToAbsent || nextCheckpointAt != null) {
      map['next_checkpoint_at'] = Variable<DateTime>(nextCheckpointAt);
    }
    if (!nullToAbsent || parentAssignmentId != null) {
      map['parent_assignment_id'] = Variable<String>(parentAssignmentId);
    }
    map['is_template'] = Variable<bool>(isTemplate);
    map['auto_decide_enabled'] = Variable<bool>(autoDecideEnabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  AssignmentsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      sourceEmailId: sourceEmailId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceEmailId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      kind: Value(kind),
      recurrenceRule: recurrenceRule == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceRule),
      status: Value(status),
      priority: Value(priority),
      ownerEmail: Value(ownerEmail),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      nextCheckpointAt: nextCheckpointAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextCheckpointAt),
      parentAssignmentId: parentAssignmentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentAssignmentId),
      isTemplate: Value(isTemplate),
      autoDecideEnabled: Value(autoDecideEnabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isArchived: Value(isArchived),
    );
  }

  factory Assignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Assignment(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      sourceEmailId: serializer.fromJson<String?>(json['sourceEmailId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      kind: serializer.fromJson<int>(json['kind']),
      recurrenceRule: serializer.fromJson<String?>(json['recurrenceRule']),
      status: serializer.fromJson<int>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      ownerEmail: serializer.fromJson<String>(json['ownerEmail']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      nextCheckpointAt: serializer.fromJson<DateTime?>(
        json['nextCheckpointAt'],
      ),
      parentAssignmentId: serializer.fromJson<String?>(
        json['parentAssignmentId'],
      ),
      isTemplate: serializer.fromJson<bool>(json['isTemplate']),
      autoDecideEnabled: serializer.fromJson<bool>(json['autoDecideEnabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'sourceEmailId': serializer.toJson<String?>(sourceEmailId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'kind': serializer.toJson<int>(kind),
      'recurrenceRule': serializer.toJson<String?>(recurrenceRule),
      'status': serializer.toJson<int>(status),
      'priority': serializer.toJson<int>(priority),
      'ownerEmail': serializer.toJson<String>(ownerEmail),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'nextCheckpointAt': serializer.toJson<DateTime?>(nextCheckpointAt),
      'parentAssignmentId': serializer.toJson<String?>(parentAssignmentId),
      'isTemplate': serializer.toJson<bool>(isTemplate),
      'autoDecideEnabled': serializer.toJson<bool>(autoDecideEnabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isArchived': serializer.toJson<bool>(isArchived),
    };
  }

  Assignment copyWith({
    String? id,
    String? accountId,
    Value<String?> sourceEmailId = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    int? kind,
    Value<String?> recurrenceRule = const Value.absent(),
    int? status,
    int? priority,
    String? ownerEmail,
    Value<DateTime?> dueAt = const Value.absent(),
    Value<DateTime?> nextCheckpointAt = const Value.absent(),
    Value<String?> parentAssignmentId = const Value.absent(),
    bool? isTemplate,
    bool? autoDecideEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
  }) => Assignment(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    sourceEmailId: sourceEmailId.present
        ? sourceEmailId.value
        : this.sourceEmailId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    kind: kind ?? this.kind,
    recurrenceRule: recurrenceRule.present
        ? recurrenceRule.value
        : this.recurrenceRule,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    nextCheckpointAt: nextCheckpointAt.present
        ? nextCheckpointAt.value
        : this.nextCheckpointAt,
    parentAssignmentId: parentAssignmentId.present
        ? parentAssignmentId.value
        : this.parentAssignmentId,
    isTemplate: isTemplate ?? this.isTemplate,
    autoDecideEnabled: autoDecideEnabled ?? this.autoDecideEnabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isArchived: isArchived ?? this.isArchived,
  );
  Assignment copyWithCompanion(AssignmentsCompanion data) {
    return Assignment(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      sourceEmailId: data.sourceEmailId.present
          ? data.sourceEmailId.value
          : this.sourceEmailId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      kind: data.kind.present ? data.kind.value : this.kind,
      recurrenceRule: data.recurrenceRule.present
          ? data.recurrenceRule.value
          : this.recurrenceRule,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      ownerEmail: data.ownerEmail.present
          ? data.ownerEmail.value
          : this.ownerEmail,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      nextCheckpointAt: data.nextCheckpointAt.present
          ? data.nextCheckpointAt.value
          : this.nextCheckpointAt,
      parentAssignmentId: data.parentAssignmentId.present
          ? data.parentAssignmentId.value
          : this.parentAssignmentId,
      isTemplate: data.isTemplate.present
          ? data.isTemplate.value
          : this.isTemplate,
      autoDecideEnabled: data.autoDecideEnabled.present
          ? data.autoDecideEnabled.value
          : this.autoDecideEnabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Assignment(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('sourceEmailId: $sourceEmailId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('kind: $kind, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('ownerEmail: $ownerEmail, ')
          ..write('dueAt: $dueAt, ')
          ..write('nextCheckpointAt: $nextCheckpointAt, ')
          ..write('parentAssignmentId: $parentAssignmentId, ')
          ..write('isTemplate: $isTemplate, ')
          ..write('autoDecideEnabled: $autoDecideEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    sourceEmailId,
    title,
    description,
    kind,
    recurrenceRule,
    status,
    priority,
    ownerEmail,
    dueAt,
    nextCheckpointAt,
    parentAssignmentId,
    isTemplate,
    autoDecideEnabled,
    createdAt,
    updatedAt,
    isArchived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Assignment &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.sourceEmailId == this.sourceEmailId &&
          other.title == this.title &&
          other.description == this.description &&
          other.kind == this.kind &&
          other.recurrenceRule == this.recurrenceRule &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.ownerEmail == this.ownerEmail &&
          other.dueAt == this.dueAt &&
          other.nextCheckpointAt == this.nextCheckpointAt &&
          other.parentAssignmentId == this.parentAssignmentId &&
          other.isTemplate == this.isTemplate &&
          other.autoDecideEnabled == this.autoDecideEnabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isArchived == this.isArchived);
}

class AssignmentsCompanion extends UpdateCompanion<Assignment> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String?> sourceEmailId;
  final Value<String> title;
  final Value<String?> description;
  final Value<int> kind;
  final Value<String?> recurrenceRule;
  final Value<int> status;
  final Value<int> priority;
  final Value<String> ownerEmail;
  final Value<DateTime?> dueAt;
  final Value<DateTime?> nextCheckpointAt;
  final Value<String?> parentAssignmentId;
  final Value<bool> isTemplate;
  final Value<bool> autoDecideEnabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isArchived;
  final Value<int> rowid;
  const AssignmentsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.sourceEmailId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.kind = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.ownerEmail = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.nextCheckpointAt = const Value.absent(),
    this.parentAssignmentId = const Value.absent(),
    this.isTemplate = const Value.absent(),
    this.autoDecideEnabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentsCompanion.insert({
    required String id,
    required String accountId,
    this.sourceEmailId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.kind = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    required String ownerEmail,
    this.dueAt = const Value.absent(),
    this.nextCheckpointAt = const Value.absent(),
    this.parentAssignmentId = const Value.absent(),
    this.isTemplate = const Value.absent(),
    this.autoDecideEnabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       title = Value(title),
       ownerEmail = Value(ownerEmail),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Assignment> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? sourceEmailId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<int>? kind,
    Expression<String>? recurrenceRule,
    Expression<int>? status,
    Expression<int>? priority,
    Expression<String>? ownerEmail,
    Expression<DateTime>? dueAt,
    Expression<DateTime>? nextCheckpointAt,
    Expression<String>? parentAssignmentId,
    Expression<bool>? isTemplate,
    Expression<bool>? autoDecideEnabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isArchived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (sourceEmailId != null) 'source_email_id': sourceEmailId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (kind != null) 'kind': kind,
      if (recurrenceRule != null) 'recurrence_rule': recurrenceRule,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (ownerEmail != null) 'owner_email': ownerEmail,
      if (dueAt != null) 'due_at': dueAt,
      if (nextCheckpointAt != null) 'next_checkpoint_at': nextCheckpointAt,
      if (parentAssignmentId != null)
        'parent_assignment_id': parentAssignmentId,
      if (isTemplate != null) 'is_template': isTemplate,
      if (autoDecideEnabled != null) 'auto_decide_enabled': autoDecideEnabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isArchived != null) 'is_archived': isArchived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String?>? sourceEmailId,
    Value<String>? title,
    Value<String?>? description,
    Value<int>? kind,
    Value<String?>? recurrenceRule,
    Value<int>? status,
    Value<int>? priority,
    Value<String>? ownerEmail,
    Value<DateTime?>? dueAt,
    Value<DateTime?>? nextCheckpointAt,
    Value<String?>? parentAssignmentId,
    Value<bool>? isTemplate,
    Value<bool>? autoDecideEnabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isArchived,
    Value<int>? rowid,
  }) {
    return AssignmentsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      sourceEmailId: sourceEmailId ?? this.sourceEmailId,
      title: title ?? this.title,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      dueAt: dueAt ?? this.dueAt,
      nextCheckpointAt: nextCheckpointAt ?? this.nextCheckpointAt,
      parentAssignmentId: parentAssignmentId ?? this.parentAssignmentId,
      isTemplate: isTemplate ?? this.isTemplate,
      autoDecideEnabled: autoDecideEnabled ?? this.autoDecideEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (sourceEmailId.present) {
      map['source_email_id'] = Variable<String>(sourceEmailId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (recurrenceRule.present) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (ownerEmail.present) {
      map['owner_email'] = Variable<String>(ownerEmail.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (nextCheckpointAt.present) {
      map['next_checkpoint_at'] = Variable<DateTime>(nextCheckpointAt.value);
    }
    if (parentAssignmentId.present) {
      map['parent_assignment_id'] = Variable<String>(parentAssignmentId.value);
    }
    if (isTemplate.present) {
      map['is_template'] = Variable<bool>(isTemplate.value);
    }
    if (autoDecideEnabled.present) {
      map['auto_decide_enabled'] = Variable<bool>(autoDecideEnabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('sourceEmailId: $sourceEmailId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('kind: $kind, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('ownerEmail: $ownerEmail, ')
          ..write('dueAt: $dueAt, ')
          ..write('nextCheckpointAt: $nextCheckpointAt, ')
          ..write('parentAssignmentId: $parentAssignmentId, ')
          ..write('isTemplate: $isTemplate, ')
          ..write('autoDecideEnabled: $autoDecideEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentParticipantsTable extends AssignmentParticipants
    with TableInfo<$AssignmentParticipantsTable, AssignmentParticipant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentParticipantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignments (id)',
    ),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inviteStatusMeta = const VerificationMeta(
    'inviteStatus',
  );
  @override
  late final GeneratedColumn<int> inviteStatus = GeneratedColumn<int>(
    'invite_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isOurClientMeta = const VerificationMeta(
    'isOurClient',
  );
  @override
  late final GeneratedColumn<bool> isOurClient = GeneratedColumn<bool>(
    'is_our_client',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_our_client" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    assignmentId,
    email,
    displayName,
    role,
    inviteStatus,
    isOurClient,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_participants';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentParticipant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('invite_status')) {
      context.handle(
        _inviteStatusMeta,
        inviteStatus.isAcceptableOrUnknown(
          data['invite_status']!,
          _inviteStatusMeta,
        ),
      );
    }
    if (data.containsKey('is_our_client')) {
      context.handle(
        _isOurClientMeta,
        isOurClient.isAcceptableOrUnknown(
          data['is_our_client']!,
          _isOurClientMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assignmentId, email};
  @override
  AssignmentParticipant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentParticipant(
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
      inviteStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}invite_status'],
      )!,
      isOurClient: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_our_client'],
      ),
    );
  }

  @override
  $AssignmentParticipantsTable createAlias(String alias) {
    return $AssignmentParticipantsTable(attachedDatabase, alias);
  }
}

class AssignmentParticipant extends DataClass
    implements Insertable<AssignmentParticipant> {
  final String assignmentId;
  final String email;
  final String? displayName;
  final int role;
  final int inviteStatus;
  final bool? isOurClient;
  const AssignmentParticipant({
    required this.assignmentId,
    required this.email,
    this.displayName,
    required this.role,
    required this.inviteStatus,
    this.isOurClient,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['assignment_id'] = Variable<String>(assignmentId);
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['role'] = Variable<int>(role);
    map['invite_status'] = Variable<int>(inviteStatus);
    if (!nullToAbsent || isOurClient != null) {
      map['is_our_client'] = Variable<bool>(isOurClient);
    }
    return map;
  }

  AssignmentParticipantsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentParticipantsCompanion(
      assignmentId: Value(assignmentId),
      email: Value(email),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      role: Value(role),
      inviteStatus: Value(inviteStatus),
      isOurClient: isOurClient == null && nullToAbsent
          ? const Value.absent()
          : Value(isOurClient),
    );
  }

  factory AssignmentParticipant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentParticipant(
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      email: serializer.fromJson<String>(json['email']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      role: serializer.fromJson<int>(json['role']),
      inviteStatus: serializer.fromJson<int>(json['inviteStatus']),
      isOurClient: serializer.fromJson<bool?>(json['isOurClient']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assignmentId': serializer.toJson<String>(assignmentId),
      'email': serializer.toJson<String>(email),
      'displayName': serializer.toJson<String?>(displayName),
      'role': serializer.toJson<int>(role),
      'inviteStatus': serializer.toJson<int>(inviteStatus),
      'isOurClient': serializer.toJson<bool?>(isOurClient),
    };
  }

  AssignmentParticipant copyWith({
    String? assignmentId,
    String? email,
    Value<String?> displayName = const Value.absent(),
    int? role,
    int? inviteStatus,
    Value<bool?> isOurClient = const Value.absent(),
  }) => AssignmentParticipant(
    assignmentId: assignmentId ?? this.assignmentId,
    email: email ?? this.email,
    displayName: displayName.present ? displayName.value : this.displayName,
    role: role ?? this.role,
    inviteStatus: inviteStatus ?? this.inviteStatus,
    isOurClient: isOurClient.present ? isOurClient.value : this.isOurClient,
  );
  AssignmentParticipant copyWithCompanion(
    AssignmentParticipantsCompanion data,
  ) {
    return AssignmentParticipant(
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      email: data.email.present ? data.email.value : this.email,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      role: data.role.present ? data.role.value : this.role,
      inviteStatus: data.inviteStatus.present
          ? data.inviteStatus.value
          : this.inviteStatus,
      isOurClient: data.isOurClient.present
          ? data.isOurClient.value
          : this.isOurClient,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentParticipant(')
          ..write('assignmentId: $assignmentId, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('inviteStatus: $inviteStatus, ')
          ..write('isOurClient: $isOurClient')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assignmentId,
    email,
    displayName,
    role,
    inviteStatus,
    isOurClient,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentParticipant &&
          other.assignmentId == this.assignmentId &&
          other.email == this.email &&
          other.displayName == this.displayName &&
          other.role == this.role &&
          other.inviteStatus == this.inviteStatus &&
          other.isOurClient == this.isOurClient);
}

class AssignmentParticipantsCompanion
    extends UpdateCompanion<AssignmentParticipant> {
  final Value<String> assignmentId;
  final Value<String> email;
  final Value<String?> displayName;
  final Value<int> role;
  final Value<int> inviteStatus;
  final Value<bool?> isOurClient;
  final Value<int> rowid;
  const AssignmentParticipantsCompanion({
    this.assignmentId = const Value.absent(),
    this.email = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.inviteStatus = const Value.absent(),
    this.isOurClient = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentParticipantsCompanion.insert({
    required String assignmentId,
    required String email,
    this.displayName = const Value.absent(),
    required int role,
    this.inviteStatus = const Value.absent(),
    this.isOurClient = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assignmentId = Value(assignmentId),
       email = Value(email),
       role = Value(role);
  static Insertable<AssignmentParticipant> custom({
    Expression<String>? assignmentId,
    Expression<String>? email,
    Expression<String>? displayName,
    Expression<int>? role,
    Expression<int>? inviteStatus,
    Expression<bool>? isOurClient,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (email != null) 'email': email,
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (inviteStatus != null) 'invite_status': inviteStatus,
      if (isOurClient != null) 'is_our_client': isOurClient,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentParticipantsCompanion copyWith({
    Value<String>? assignmentId,
    Value<String>? email,
    Value<String?>? displayName,
    Value<int>? role,
    Value<int>? inviteStatus,
    Value<bool?>? isOurClient,
    Value<int>? rowid,
  }) {
    return AssignmentParticipantsCompanion(
      assignmentId: assignmentId ?? this.assignmentId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      inviteStatus: inviteStatus ?? this.inviteStatus,
      isOurClient: isOurClient ?? this.isOurClient,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (inviteStatus.present) {
      map['invite_status'] = Variable<int>(inviteStatus.value);
    }
    if (isOurClient.present) {
      map['is_our_client'] = Variable<bool>(isOurClient.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentParticipantsCompanion(')
          ..write('assignmentId: $assignmentId, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('inviteStatus: $inviteStatus, ')
          ..write('isOurClient: $isOurClient, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentEventsTable extends AssignmentEvents
    with TableInfo<$AssignmentEventsTable, AssignmentEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignments (id)',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorEmailMeta = const VerificationMeta(
    'authorEmail',
  );
  @override
  late final GeneratedColumn<String> authorEmail = GeneratedColumn<String>(
    'author_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceEmailIdMeta = const VerificationMeta(
    'sourceEmailId',
  );
  @override
  late final GeneratedColumn<String> sourceEmailId = GeneratedColumn<String>(
    'source_email_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<int> direction = GeneratedColumn<int>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveryStatusMeta = const VerificationMeta(
    'deliveryStatus',
  );
  @override
  late final GeneratedColumn<int> deliveryStatus = GeneratedColumn<int>(
    'delivery_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _signatureStateMeta = const VerificationMeta(
    'signatureState',
  );
  @override
  late final GeneratedColumn<int> signatureState = GeneratedColumn<int>(
    'signature_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assignmentId,
    type,
    authorEmail,
    createdAt,
    payloadJson,
    refId,
    sourceEmailId,
    direction,
    deliveryStatus,
    signatureState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('author_email')) {
      context.handle(
        _authorEmailMeta,
        authorEmail.isAcceptableOrUnknown(
          data['author_email']!,
          _authorEmailMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorEmailMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('source_email_id')) {
      context.handle(
        _sourceEmailIdMeta,
        sourceEmailId.isAcceptableOrUnknown(
          data['source_email_id']!,
          _sourceEmailIdMeta,
        ),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('delivery_status')) {
      context.handle(
        _deliveryStatusMeta,
        deliveryStatus.isAcceptableOrUnknown(
          data['delivery_status']!,
          _deliveryStatusMeta,
        ),
      );
    }
    if (data.containsKey('signature_state')) {
      context.handle(
        _signatureStateMeta,
        signatureState.isAcceptableOrUnknown(
          data['signature_state']!,
          _signatureStateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssignmentEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      authorEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_email'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      sourceEmailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_email_id'],
      ),
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}direction'],
      )!,
      deliveryStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivery_status'],
      )!,
      signatureState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}signature_state'],
      )!,
    );
  }

  @override
  $AssignmentEventsTable createAlias(String alias) {
    return $AssignmentEventsTable(attachedDatabase, alias);
  }
}

class AssignmentEvent extends DataClass implements Insertable<AssignmentEvent> {
  final String id;
  final String assignmentId;
  final String type;
  final String authorEmail;
  final DateTime createdAt;
  final String payloadJson;
  final String? refId;
  final String? sourceEmailId;
  final int direction;
  final int deliveryStatus;
  final int signatureState;
  const AssignmentEvent({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.authorEmail,
    required this.createdAt,
    required this.payloadJson,
    this.refId,
    this.sourceEmailId,
    required this.direction,
    required this.deliveryStatus,
    required this.signatureState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    map['type'] = Variable<String>(type);
    map['author_email'] = Variable<String>(authorEmail);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    if (!nullToAbsent || sourceEmailId != null) {
      map['source_email_id'] = Variable<String>(sourceEmailId);
    }
    map['direction'] = Variable<int>(direction);
    map['delivery_status'] = Variable<int>(deliveryStatus);
    map['signature_state'] = Variable<int>(signatureState);
    return map;
  }

  AssignmentEventsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentEventsCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      type: Value(type),
      authorEmail: Value(authorEmail),
      createdAt: Value(createdAt),
      payloadJson: Value(payloadJson),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      sourceEmailId: sourceEmailId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceEmailId),
      direction: Value(direction),
      deliveryStatus: Value(deliveryStatus),
      signatureState: Value(signatureState),
    );
  }

  factory AssignmentEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentEvent(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      type: serializer.fromJson<String>(json['type']),
      authorEmail: serializer.fromJson<String>(json['authorEmail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      refId: serializer.fromJson<String?>(json['refId']),
      sourceEmailId: serializer.fromJson<String?>(json['sourceEmailId']),
      direction: serializer.fromJson<int>(json['direction']),
      deliveryStatus: serializer.fromJson<int>(json['deliveryStatus']),
      signatureState: serializer.fromJson<int>(json['signatureState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'type': serializer.toJson<String>(type),
      'authorEmail': serializer.toJson<String>(authorEmail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'refId': serializer.toJson<String?>(refId),
      'sourceEmailId': serializer.toJson<String?>(sourceEmailId),
      'direction': serializer.toJson<int>(direction),
      'deliveryStatus': serializer.toJson<int>(deliveryStatus),
      'signatureState': serializer.toJson<int>(signatureState),
    };
  }

  AssignmentEvent copyWith({
    String? id,
    String? assignmentId,
    String? type,
    String? authorEmail,
    DateTime? createdAt,
    String? payloadJson,
    Value<String?> refId = const Value.absent(),
    Value<String?> sourceEmailId = const Value.absent(),
    int? direction,
    int? deliveryStatus,
    int? signatureState,
  }) => AssignmentEvent(
    id: id ?? this.id,
    assignmentId: assignmentId ?? this.assignmentId,
    type: type ?? this.type,
    authorEmail: authorEmail ?? this.authorEmail,
    createdAt: createdAt ?? this.createdAt,
    payloadJson: payloadJson ?? this.payloadJson,
    refId: refId.present ? refId.value : this.refId,
    sourceEmailId: sourceEmailId.present
        ? sourceEmailId.value
        : this.sourceEmailId,
    direction: direction ?? this.direction,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    signatureState: signatureState ?? this.signatureState,
  );
  AssignmentEvent copyWithCompanion(AssignmentEventsCompanion data) {
    return AssignmentEvent(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      type: data.type.present ? data.type.value : this.type,
      authorEmail: data.authorEmail.present
          ? data.authorEmail.value
          : this.authorEmail,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      refId: data.refId.present ? data.refId.value : this.refId,
      sourceEmailId: data.sourceEmailId.present
          ? data.sourceEmailId.value
          : this.sourceEmailId,
      direction: data.direction.present ? data.direction.value : this.direction,
      deliveryStatus: data.deliveryStatus.present
          ? data.deliveryStatus.value
          : this.deliveryStatus,
      signatureState: data.signatureState.present
          ? data.signatureState.value
          : this.signatureState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentEvent(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('type: $type, ')
          ..write('authorEmail: $authorEmail, ')
          ..write('createdAt: $createdAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('refId: $refId, ')
          ..write('sourceEmailId: $sourceEmailId, ')
          ..write('direction: $direction, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('signatureState: $signatureState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assignmentId,
    type,
    authorEmail,
    createdAt,
    payloadJson,
    refId,
    sourceEmailId,
    direction,
    deliveryStatus,
    signatureState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentEvent &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.type == this.type &&
          other.authorEmail == this.authorEmail &&
          other.createdAt == this.createdAt &&
          other.payloadJson == this.payloadJson &&
          other.refId == this.refId &&
          other.sourceEmailId == this.sourceEmailId &&
          other.direction == this.direction &&
          other.deliveryStatus == this.deliveryStatus &&
          other.signatureState == this.signatureState);
}

class AssignmentEventsCompanion extends UpdateCompanion<AssignmentEvent> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String> type;
  final Value<String> authorEmail;
  final Value<DateTime> createdAt;
  final Value<String> payloadJson;
  final Value<String?> refId;
  final Value<String?> sourceEmailId;
  final Value<int> direction;
  final Value<int> deliveryStatus;
  final Value<int> signatureState;
  final Value<int> rowid;
  const AssignmentEventsCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.type = const Value.absent(),
    this.authorEmail = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.refId = const Value.absent(),
    this.sourceEmailId = const Value.absent(),
    this.direction = const Value.absent(),
    this.deliveryStatus = const Value.absent(),
    this.signatureState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentEventsCompanion.insert({
    required String id,
    required String assignmentId,
    required String type,
    required String authorEmail,
    required DateTime createdAt,
    required String payloadJson,
    this.refId = const Value.absent(),
    this.sourceEmailId = const Value.absent(),
    required int direction,
    this.deliveryStatus = const Value.absent(),
    this.signatureState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assignmentId = Value(assignmentId),
       type = Value(type),
       authorEmail = Value(authorEmail),
       createdAt = Value(createdAt),
       payloadJson = Value(payloadJson),
       direction = Value(direction);
  static Insertable<AssignmentEvent> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? type,
    Expression<String>? authorEmail,
    Expression<DateTime>? createdAt,
    Expression<String>? payloadJson,
    Expression<String>? refId,
    Expression<String>? sourceEmailId,
    Expression<int>? direction,
    Expression<int>? deliveryStatus,
    Expression<int>? signatureState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (type != null) 'type': type,
      if (authorEmail != null) 'author_email': authorEmail,
      if (createdAt != null) 'created_at': createdAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (refId != null) 'ref_id': refId,
      if (sourceEmailId != null) 'source_email_id': sourceEmailId,
      if (direction != null) 'direction': direction,
      if (deliveryStatus != null) 'delivery_status': deliveryStatus,
      if (signatureState != null) 'signature_state': signatureState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? assignmentId,
    Value<String>? type,
    Value<String>? authorEmail,
    Value<DateTime>? createdAt,
    Value<String>? payloadJson,
    Value<String?>? refId,
    Value<String?>? sourceEmailId,
    Value<int>? direction,
    Value<int>? deliveryStatus,
    Value<int>? signatureState,
    Value<int>? rowid,
  }) {
    return AssignmentEventsCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      type: type ?? this.type,
      authorEmail: authorEmail ?? this.authorEmail,
      createdAt: createdAt ?? this.createdAt,
      payloadJson: payloadJson ?? this.payloadJson,
      refId: refId ?? this.refId,
      sourceEmailId: sourceEmailId ?? this.sourceEmailId,
      direction: direction ?? this.direction,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      signatureState: signatureState ?? this.signatureState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (authorEmail.present) {
      map['author_email'] = Variable<String>(authorEmail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (sourceEmailId.present) {
      map['source_email_id'] = Variable<String>(sourceEmailId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<int>(direction.value);
    }
    if (deliveryStatus.present) {
      map['delivery_status'] = Variable<int>(deliveryStatus.value);
    }
    if (signatureState.present) {
      map['signature_state'] = Variable<int>(signatureState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentEventsCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('type: $type, ')
          ..write('authorEmail: $authorEmail, ')
          ..write('createdAt: $createdAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('refId: $refId, ')
          ..write('sourceEmailId: $sourceEmailId, ')
          ..write('direction: $direction, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('signatureState: $signatureState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentProposalsTable extends AssignmentProposals
    with TableInfo<$AssignmentProposalsTable, AssignmentProposal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentProposalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignments (id)',
    ),
  );
  static const VerificationMeta _authorEmailMeta = const VerificationMeta(
    'authorEmail',
  );
  @override
  late final GeneratedColumn<String> authorEmail = GeneratedColumn<String>(
    'author_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _decidedByMeta = const VerificationMeta(
    'decidedBy',
  );
  @override
  late final GeneratedColumn<String> decidedBy = GeneratedColumn<String>(
    'decided_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _decisionMethodMeta = const VerificationMeta(
    'decisionMethod',
  );
  @override
  late final GeneratedColumn<int> decisionMethod = GeneratedColumn<int>(
    'decision_method',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _decidedAtMeta = const VerificationMeta(
    'decidedAt',
  );
  @override
  late final GeneratedColumn<DateTime> decidedAt = GeneratedColumn<DateTime>(
    'decided_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assignmentId,
    authorEmail,
    body,
    attachmentsJson,
    status,
    decidedBy,
    decisionMethod,
    decidedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_proposals';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentProposal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('author_email')) {
      context.handle(
        _authorEmailMeta,
        authorEmail.isAcceptableOrUnknown(
          data['author_email']!,
          _authorEmailMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorEmailMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('decided_by')) {
      context.handle(
        _decidedByMeta,
        decidedBy.isAcceptableOrUnknown(data['decided_by']!, _decidedByMeta),
      );
    }
    if (data.containsKey('decision_method')) {
      context.handle(
        _decisionMethodMeta,
        decisionMethod.isAcceptableOrUnknown(
          data['decision_method']!,
          _decisionMethodMeta,
        ),
      );
    }
    if (data.containsKey('decided_at')) {
      context.handle(
        _decidedAtMeta,
        decidedAt.isAcceptableOrUnknown(data['decided_at']!, _decidedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssignmentProposal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentProposal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      authorEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_email'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      decidedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decided_by'],
      ),
      decisionMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decision_method'],
      ),
      decidedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}decided_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AssignmentProposalsTable createAlias(String alias) {
    return $AssignmentProposalsTable(attachedDatabase, alias);
  }
}

class AssignmentProposal extends DataClass
    implements Insertable<AssignmentProposal> {
  final String id;
  final String assignmentId;
  final String authorEmail;

  /// Текст предложения. Имя `body`, а не `text`: `text()` — метод самого
  /// Drift-класса Table, и одноимённый геттер вызывал бы сам себя.
  final String body;
  final String? attachmentsJson;
  final int status;
  final String? decidedBy;
  final int? decisionMethod;
  final DateTime? decidedAt;
  final DateTime createdAt;
  const AssignmentProposal({
    required this.id,
    required this.assignmentId,
    required this.authorEmail,
    required this.body,
    this.attachmentsJson,
    required this.status,
    this.decidedBy,
    this.decisionMethod,
    this.decidedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    map['author_email'] = Variable<String>(authorEmail);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || decidedBy != null) {
      map['decided_by'] = Variable<String>(decidedBy);
    }
    if (!nullToAbsent || decisionMethod != null) {
      map['decision_method'] = Variable<int>(decisionMethod);
    }
    if (!nullToAbsent || decidedAt != null) {
      map['decided_at'] = Variable<DateTime>(decidedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AssignmentProposalsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentProposalsCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      authorEmail: Value(authorEmail),
      body: Value(body),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
      status: Value(status),
      decidedBy: decidedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(decidedBy),
      decisionMethod: decisionMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(decisionMethod),
      decidedAt: decidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(decidedAt),
      createdAt: Value(createdAt),
    );
  }

  factory AssignmentProposal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentProposal(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      authorEmail: serializer.fromJson<String>(json['authorEmail']),
      body: serializer.fromJson<String>(json['body']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
      status: serializer.fromJson<int>(json['status']),
      decidedBy: serializer.fromJson<String?>(json['decidedBy']),
      decisionMethod: serializer.fromJson<int?>(json['decisionMethod']),
      decidedAt: serializer.fromJson<DateTime?>(json['decidedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'authorEmail': serializer.toJson<String>(authorEmail),
      'body': serializer.toJson<String>(body),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
      'status': serializer.toJson<int>(status),
      'decidedBy': serializer.toJson<String?>(decidedBy),
      'decisionMethod': serializer.toJson<int?>(decisionMethod),
      'decidedAt': serializer.toJson<DateTime?>(decidedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AssignmentProposal copyWith({
    String? id,
    String? assignmentId,
    String? authorEmail,
    String? body,
    Value<String?> attachmentsJson = const Value.absent(),
    int? status,
    Value<String?> decidedBy = const Value.absent(),
    Value<int?> decisionMethod = const Value.absent(),
    Value<DateTime?> decidedAt = const Value.absent(),
    DateTime? createdAt,
  }) => AssignmentProposal(
    id: id ?? this.id,
    assignmentId: assignmentId ?? this.assignmentId,
    authorEmail: authorEmail ?? this.authorEmail,
    body: body ?? this.body,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
    status: status ?? this.status,
    decidedBy: decidedBy.present ? decidedBy.value : this.decidedBy,
    decisionMethod: decisionMethod.present
        ? decisionMethod.value
        : this.decisionMethod,
    decidedAt: decidedAt.present ? decidedAt.value : this.decidedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  AssignmentProposal copyWithCompanion(AssignmentProposalsCompanion data) {
    return AssignmentProposal(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      authorEmail: data.authorEmail.present
          ? data.authorEmail.value
          : this.authorEmail,
      body: data.body.present ? data.body.value : this.body,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      status: data.status.present ? data.status.value : this.status,
      decidedBy: data.decidedBy.present ? data.decidedBy.value : this.decidedBy,
      decisionMethod: data.decisionMethod.present
          ? data.decisionMethod.value
          : this.decisionMethod,
      decidedAt: data.decidedAt.present ? data.decidedAt.value : this.decidedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentProposal(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('authorEmail: $authorEmail, ')
          ..write('body: $body, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('status: $status, ')
          ..write('decidedBy: $decidedBy, ')
          ..write('decisionMethod: $decisionMethod, ')
          ..write('decidedAt: $decidedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assignmentId,
    authorEmail,
    body,
    attachmentsJson,
    status,
    decidedBy,
    decisionMethod,
    decidedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentProposal &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.authorEmail == this.authorEmail &&
          other.body == this.body &&
          other.attachmentsJson == this.attachmentsJson &&
          other.status == this.status &&
          other.decidedBy == this.decidedBy &&
          other.decisionMethod == this.decisionMethod &&
          other.decidedAt == this.decidedAt &&
          other.createdAt == this.createdAt);
}

class AssignmentProposalsCompanion extends UpdateCompanion<AssignmentProposal> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String> authorEmail;
  final Value<String> body;
  final Value<String?> attachmentsJson;
  final Value<int> status;
  final Value<String?> decidedBy;
  final Value<int?> decisionMethod;
  final Value<DateTime?> decidedAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AssignmentProposalsCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.authorEmail = const Value.absent(),
    this.body = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.decidedBy = const Value.absent(),
    this.decisionMethod = const Value.absent(),
    this.decidedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentProposalsCompanion.insert({
    required String id,
    required String assignmentId,
    required String authorEmail,
    required String body,
    this.attachmentsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.decidedBy = const Value.absent(),
    this.decisionMethod = const Value.absent(),
    this.decidedAt = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assignmentId = Value(assignmentId),
       authorEmail = Value(authorEmail),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<AssignmentProposal> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? authorEmail,
    Expression<String>? body,
    Expression<String>? attachmentsJson,
    Expression<int>? status,
    Expression<String>? decidedBy,
    Expression<int>? decisionMethod,
    Expression<DateTime>? decidedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (authorEmail != null) 'author_email': authorEmail,
      if (body != null) 'body': body,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (status != null) 'status': status,
      if (decidedBy != null) 'decided_by': decidedBy,
      if (decisionMethod != null) 'decision_method': decisionMethod,
      if (decidedAt != null) 'decided_at': decidedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentProposalsCompanion copyWith({
    Value<String>? id,
    Value<String>? assignmentId,
    Value<String>? authorEmail,
    Value<String>? body,
    Value<String?>? attachmentsJson,
    Value<int>? status,
    Value<String?>? decidedBy,
    Value<int?>? decisionMethod,
    Value<DateTime?>? decidedAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AssignmentProposalsCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      authorEmail: authorEmail ?? this.authorEmail,
      body: body ?? this.body,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      status: status ?? this.status,
      decidedBy: decidedBy ?? this.decidedBy,
      decisionMethod: decisionMethod ?? this.decisionMethod,
      decidedAt: decidedAt ?? this.decidedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (authorEmail.present) {
      map['author_email'] = Variable<String>(authorEmail.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (decidedBy.present) {
      map['decided_by'] = Variable<String>(decidedBy.value);
    }
    if (decisionMethod.present) {
      map['decision_method'] = Variable<int>(decisionMethod.value);
    }
    if (decidedAt.present) {
      map['decided_at'] = Variable<DateTime>(decidedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentProposalsCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('authorEmail: $authorEmail, ')
          ..write('body: $body, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('status: $status, ')
          ..write('decidedBy: $decidedBy, ')
          ..write('decisionMethod: $decisionMethod, ')
          ..write('decidedAt: $decidedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentVotesTable extends AssignmentVotes
    with TableInfo<$AssignmentVotesTable, AssignmentVote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentVotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _proposalIdMeta = const VerificationMeta(
    'proposalId',
  );
  @override
  late final GeneratedColumn<String> proposalId = GeneratedColumn<String>(
    'proposal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignment_proposals (id)',
    ),
  );
  static const VerificationMeta _voterEmailMeta = const VerificationMeta(
    'voterEmail',
  );
  @override
  late final GeneratedColumn<String> voterEmail = GeneratedColumn<String>(
    'voter_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commentMeta = const VerificationMeta(
    'comment',
  );
  @override
  late final GeneratedColumn<String> comment = GeneratedColumn<String>(
    'comment',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _votedAtMeta = const VerificationMeta(
    'votedAt',
  );
  @override
  late final GeneratedColumn<DateTime> votedAt = GeneratedColumn<DateTime>(
    'voted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    proposalId,
    voterEmail,
    value,
    comment,
    votedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_votes';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentVote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('proposal_id')) {
      context.handle(
        _proposalIdMeta,
        proposalId.isAcceptableOrUnknown(data['proposal_id']!, _proposalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_proposalIdMeta);
    }
    if (data.containsKey('voter_email')) {
      context.handle(
        _voterEmailMeta,
        voterEmail.isAcceptableOrUnknown(data['voter_email']!, _voterEmailMeta),
      );
    } else if (isInserting) {
      context.missing(_voterEmailMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('comment')) {
      context.handle(
        _commentMeta,
        comment.isAcceptableOrUnknown(data['comment']!, _commentMeta),
      );
    }
    if (data.containsKey('voted_at')) {
      context.handle(
        _votedAtMeta,
        votedAt.isAcceptableOrUnknown(data['voted_at']!, _votedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_votedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {proposalId, voterEmail};
  @override
  AssignmentVote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentVote(
      proposalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposal_id'],
      )!,
      voterEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voter_email'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
      comment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comment'],
      ),
      votedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}voted_at'],
      )!,
    );
  }

  @override
  $AssignmentVotesTable createAlias(String alias) {
    return $AssignmentVotesTable(attachedDatabase, alias);
  }
}

class AssignmentVote extends DataClass implements Insertable<AssignmentVote> {
  final String proposalId;
  final String voterEmail;
  final int value;
  final String? comment;
  final DateTime votedAt;
  const AssignmentVote({
    required this.proposalId,
    required this.voterEmail,
    required this.value,
    this.comment,
    required this.votedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['proposal_id'] = Variable<String>(proposalId);
    map['voter_email'] = Variable<String>(voterEmail);
    map['value'] = Variable<int>(value);
    if (!nullToAbsent || comment != null) {
      map['comment'] = Variable<String>(comment);
    }
    map['voted_at'] = Variable<DateTime>(votedAt);
    return map;
  }

  AssignmentVotesCompanion toCompanion(bool nullToAbsent) {
    return AssignmentVotesCompanion(
      proposalId: Value(proposalId),
      voterEmail: Value(voterEmail),
      value: Value(value),
      comment: comment == null && nullToAbsent
          ? const Value.absent()
          : Value(comment),
      votedAt: Value(votedAt),
    );
  }

  factory AssignmentVote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentVote(
      proposalId: serializer.fromJson<String>(json['proposalId']),
      voterEmail: serializer.fromJson<String>(json['voterEmail']),
      value: serializer.fromJson<int>(json['value']),
      comment: serializer.fromJson<String?>(json['comment']),
      votedAt: serializer.fromJson<DateTime>(json['votedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'proposalId': serializer.toJson<String>(proposalId),
      'voterEmail': serializer.toJson<String>(voterEmail),
      'value': serializer.toJson<int>(value),
      'comment': serializer.toJson<String?>(comment),
      'votedAt': serializer.toJson<DateTime>(votedAt),
    };
  }

  AssignmentVote copyWith({
    String? proposalId,
    String? voterEmail,
    int? value,
    Value<String?> comment = const Value.absent(),
    DateTime? votedAt,
  }) => AssignmentVote(
    proposalId: proposalId ?? this.proposalId,
    voterEmail: voterEmail ?? this.voterEmail,
    value: value ?? this.value,
    comment: comment.present ? comment.value : this.comment,
    votedAt: votedAt ?? this.votedAt,
  );
  AssignmentVote copyWithCompanion(AssignmentVotesCompanion data) {
    return AssignmentVote(
      proposalId: data.proposalId.present
          ? data.proposalId.value
          : this.proposalId,
      voterEmail: data.voterEmail.present
          ? data.voterEmail.value
          : this.voterEmail,
      value: data.value.present ? data.value.value : this.value,
      comment: data.comment.present ? data.comment.value : this.comment,
      votedAt: data.votedAt.present ? data.votedAt.value : this.votedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentVote(')
          ..write('proposalId: $proposalId, ')
          ..write('voterEmail: $voterEmail, ')
          ..write('value: $value, ')
          ..write('comment: $comment, ')
          ..write('votedAt: $votedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(proposalId, voterEmail, value, comment, votedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentVote &&
          other.proposalId == this.proposalId &&
          other.voterEmail == this.voterEmail &&
          other.value == this.value &&
          other.comment == this.comment &&
          other.votedAt == this.votedAt);
}

class AssignmentVotesCompanion extends UpdateCompanion<AssignmentVote> {
  final Value<String> proposalId;
  final Value<String> voterEmail;
  final Value<int> value;
  final Value<String?> comment;
  final Value<DateTime> votedAt;
  final Value<int> rowid;
  const AssignmentVotesCompanion({
    this.proposalId = const Value.absent(),
    this.voterEmail = const Value.absent(),
    this.value = const Value.absent(),
    this.comment = const Value.absent(),
    this.votedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentVotesCompanion.insert({
    required String proposalId,
    required String voterEmail,
    required int value,
    this.comment = const Value.absent(),
    required DateTime votedAt,
    this.rowid = const Value.absent(),
  }) : proposalId = Value(proposalId),
       voterEmail = Value(voterEmail),
       value = Value(value),
       votedAt = Value(votedAt);
  static Insertable<AssignmentVote> custom({
    Expression<String>? proposalId,
    Expression<String>? voterEmail,
    Expression<int>? value,
    Expression<String>? comment,
    Expression<DateTime>? votedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (proposalId != null) 'proposal_id': proposalId,
      if (voterEmail != null) 'voter_email': voterEmail,
      if (value != null) 'value': value,
      if (comment != null) 'comment': comment,
      if (votedAt != null) 'voted_at': votedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentVotesCompanion copyWith({
    Value<String>? proposalId,
    Value<String>? voterEmail,
    Value<int>? value,
    Value<String?>? comment,
    Value<DateTime>? votedAt,
    Value<int>? rowid,
  }) {
    return AssignmentVotesCompanion(
      proposalId: proposalId ?? this.proposalId,
      voterEmail: voterEmail ?? this.voterEmail,
      value: value ?? this.value,
      comment: comment ?? this.comment,
      votedAt: votedAt ?? this.votedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (proposalId.present) {
      map['proposal_id'] = Variable<String>(proposalId.value);
    }
    if (voterEmail.present) {
      map['voter_email'] = Variable<String>(voterEmail.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (comment.present) {
      map['comment'] = Variable<String>(comment.value);
    }
    if (votedAt.present) {
      map['voted_at'] = Variable<DateTime>(votedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentVotesCompanion(')
          ..write('proposalId: $proposalId, ')
          ..write('voterEmail: $voterEmail, ')
          ..write('value: $value, ')
          ..write('comment: $comment, ')
          ..write('votedAt: $votedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentMeetingsTable extends AssignmentMeetings
    with TableInfo<$AssignmentMeetingsTable, AssignmentMeeting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentMeetingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignments (id)',
    ),
  );
  static const VerificationMeta _calendarEventIdMeta = const VerificationMeta(
    'calendarEventId',
  );
  @override
  late final GeneratedColumn<String> calendarEventId = GeneratedColumn<String>(
    'calendar_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtypeMeta = const VerificationMeta(
    'subtype',
  );
  @override
  late final GeneratedColumn<int> subtype = GeneratedColumn<int>(
    'subtype',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dialInMeta = const VerificationMeta('dialIn');
  @override
  late final GeneratedColumn<String> dialIn = GeneratedColumn<String>(
    'dial_in',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkMeta = const VerificationMeta('link');
  @override
  late final GeneratedColumn<String> link = GeneratedColumn<String>(
    'link',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<DateTime> endAt = GeneratedColumn<DateTime>(
    'end_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minutesMeta = const VerificationMeta(
    'minutes',
  );
  @override
  late final GeneratedColumn<String> minutes = GeneratedColumn<String>(
    'minutes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assignmentId,
    calendarEventId,
    subtype,
    dialIn,
    link,
    startAt,
    endAt,
    minutes,
    createdBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_meetings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentMeeting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('calendar_event_id')) {
      context.handle(
        _calendarEventIdMeta,
        calendarEventId.isAcceptableOrUnknown(
          data['calendar_event_id']!,
          _calendarEventIdMeta,
        ),
      );
    }
    if (data.containsKey('subtype')) {
      context.handle(
        _subtypeMeta,
        subtype.isAcceptableOrUnknown(data['subtype']!, _subtypeMeta),
      );
    } else if (isInserting) {
      context.missing(_subtypeMeta);
    }
    if (data.containsKey('dial_in')) {
      context.handle(
        _dialInMeta,
        dialIn.isAcceptableOrUnknown(data['dial_in']!, _dialInMeta),
      );
    }
    if (data.containsKey('link')) {
      context.handle(
        _linkMeta,
        link.isAcceptableOrUnknown(data['link']!, _linkMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    }
    if (data.containsKey('minutes')) {
      context.handle(
        _minutesMeta,
        minutes.isAcceptableOrUnknown(data['minutes']!, _minutesMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssignmentMeeting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentMeeting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      calendarEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calendar_event_id'],
      ),
      subtype: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtype'],
      )!,
      dialIn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dial_in'],
      ),
      link: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link'],
      ),
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      )!,
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_at'],
      ),
      minutes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}minutes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
    );
  }

  @override
  $AssignmentMeetingsTable createAlias(String alias) {
    return $AssignmentMeetingsTable(attachedDatabase, alias);
  }
}

class AssignmentMeeting extends DataClass
    implements Insertable<AssignmentMeeting> {
  final String id;
  final String assignmentId;
  final String? calendarEventId;
  final int subtype;
  final String? dialIn;
  final String? link;
  final DateTime startAt;
  final DateTime? endAt;
  final String? minutes;
  final String createdBy;
  const AssignmentMeeting({
    required this.id,
    required this.assignmentId,
    this.calendarEventId,
    required this.subtype,
    this.dialIn,
    this.link,
    required this.startAt,
    this.endAt,
    this.minutes,
    required this.createdBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    if (!nullToAbsent || calendarEventId != null) {
      map['calendar_event_id'] = Variable<String>(calendarEventId);
    }
    map['subtype'] = Variable<int>(subtype);
    if (!nullToAbsent || dialIn != null) {
      map['dial_in'] = Variable<String>(dialIn);
    }
    if (!nullToAbsent || link != null) {
      map['link'] = Variable<String>(link);
    }
    map['start_at'] = Variable<DateTime>(startAt);
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<DateTime>(endAt);
    }
    if (!nullToAbsent || minutes != null) {
      map['minutes'] = Variable<String>(minutes);
    }
    map['created_by'] = Variable<String>(createdBy);
    return map;
  }

  AssignmentMeetingsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentMeetingsCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      calendarEventId: calendarEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(calendarEventId),
      subtype: Value(subtype),
      dialIn: dialIn == null && nullToAbsent
          ? const Value.absent()
          : Value(dialIn),
      link: link == null && nullToAbsent ? const Value.absent() : Value(link),
      startAt: Value(startAt),
      endAt: endAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endAt),
      minutes: minutes == null && nullToAbsent
          ? const Value.absent()
          : Value(minutes),
      createdBy: Value(createdBy),
    );
  }

  factory AssignmentMeeting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentMeeting(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      calendarEventId: serializer.fromJson<String?>(json['calendarEventId']),
      subtype: serializer.fromJson<int>(json['subtype']),
      dialIn: serializer.fromJson<String?>(json['dialIn']),
      link: serializer.fromJson<String?>(json['link']),
      startAt: serializer.fromJson<DateTime>(json['startAt']),
      endAt: serializer.fromJson<DateTime?>(json['endAt']),
      minutes: serializer.fromJson<String?>(json['minutes']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'calendarEventId': serializer.toJson<String?>(calendarEventId),
      'subtype': serializer.toJson<int>(subtype),
      'dialIn': serializer.toJson<String?>(dialIn),
      'link': serializer.toJson<String?>(link),
      'startAt': serializer.toJson<DateTime>(startAt),
      'endAt': serializer.toJson<DateTime?>(endAt),
      'minutes': serializer.toJson<String?>(minutes),
      'createdBy': serializer.toJson<String>(createdBy),
    };
  }

  AssignmentMeeting copyWith({
    String? id,
    String? assignmentId,
    Value<String?> calendarEventId = const Value.absent(),
    int? subtype,
    Value<String?> dialIn = const Value.absent(),
    Value<String?> link = const Value.absent(),
    DateTime? startAt,
    Value<DateTime?> endAt = const Value.absent(),
    Value<String?> minutes = const Value.absent(),
    String? createdBy,
  }) => AssignmentMeeting(
    id: id ?? this.id,
    assignmentId: assignmentId ?? this.assignmentId,
    calendarEventId: calendarEventId.present
        ? calendarEventId.value
        : this.calendarEventId,
    subtype: subtype ?? this.subtype,
    dialIn: dialIn.present ? dialIn.value : this.dialIn,
    link: link.present ? link.value : this.link,
    startAt: startAt ?? this.startAt,
    endAt: endAt.present ? endAt.value : this.endAt,
    minutes: minutes.present ? minutes.value : this.minutes,
    createdBy: createdBy ?? this.createdBy,
  );
  AssignmentMeeting copyWithCompanion(AssignmentMeetingsCompanion data) {
    return AssignmentMeeting(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      calendarEventId: data.calendarEventId.present
          ? data.calendarEventId.value
          : this.calendarEventId,
      subtype: data.subtype.present ? data.subtype.value : this.subtype,
      dialIn: data.dialIn.present ? data.dialIn.value : this.dialIn,
      link: data.link.present ? data.link.value : this.link,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      minutes: data.minutes.present ? data.minutes.value : this.minutes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentMeeting(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('calendarEventId: $calendarEventId, ')
          ..write('subtype: $subtype, ')
          ..write('dialIn: $dialIn, ')
          ..write('link: $link, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('minutes: $minutes, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assignmentId,
    calendarEventId,
    subtype,
    dialIn,
    link,
    startAt,
    endAt,
    minutes,
    createdBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentMeeting &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.calendarEventId == this.calendarEventId &&
          other.subtype == this.subtype &&
          other.dialIn == this.dialIn &&
          other.link == this.link &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.minutes == this.minutes &&
          other.createdBy == this.createdBy);
}

class AssignmentMeetingsCompanion extends UpdateCompanion<AssignmentMeeting> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String?> calendarEventId;
  final Value<int> subtype;
  final Value<String?> dialIn;
  final Value<String?> link;
  final Value<DateTime> startAt;
  final Value<DateTime?> endAt;
  final Value<String?> minutes;
  final Value<String> createdBy;
  final Value<int> rowid;
  const AssignmentMeetingsCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.calendarEventId = const Value.absent(),
    this.subtype = const Value.absent(),
    this.dialIn = const Value.absent(),
    this.link = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.minutes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentMeetingsCompanion.insert({
    required String id,
    required String assignmentId,
    this.calendarEventId = const Value.absent(),
    required int subtype,
    this.dialIn = const Value.absent(),
    this.link = const Value.absent(),
    required DateTime startAt,
    this.endAt = const Value.absent(),
    this.minutes = const Value.absent(),
    required String createdBy,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assignmentId = Value(assignmentId),
       subtype = Value(subtype),
       startAt = Value(startAt),
       createdBy = Value(createdBy);
  static Insertable<AssignmentMeeting> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? calendarEventId,
    Expression<int>? subtype,
    Expression<String>? dialIn,
    Expression<String>? link,
    Expression<DateTime>? startAt,
    Expression<DateTime>? endAt,
    Expression<String>? minutes,
    Expression<String>? createdBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (calendarEventId != null) 'calendar_event_id': calendarEventId,
      if (subtype != null) 'subtype': subtype,
      if (dialIn != null) 'dial_in': dialIn,
      if (link != null) 'link': link,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (minutes != null) 'minutes': minutes,
      if (createdBy != null) 'created_by': createdBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentMeetingsCompanion copyWith({
    Value<String>? id,
    Value<String>? assignmentId,
    Value<String?>? calendarEventId,
    Value<int>? subtype,
    Value<String?>? dialIn,
    Value<String?>? link,
    Value<DateTime>? startAt,
    Value<DateTime?>? endAt,
    Value<String?>? minutes,
    Value<String>? createdBy,
    Value<int>? rowid,
  }) {
    return AssignmentMeetingsCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      subtype: subtype ?? this.subtype,
      dialIn: dialIn ?? this.dialIn,
      link: link ?? this.link,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      minutes: minutes ?? this.minutes,
      createdBy: createdBy ?? this.createdBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (calendarEventId.present) {
      map['calendar_event_id'] = Variable<String>(calendarEventId.value);
    }
    if (subtype.present) {
      map['subtype'] = Variable<int>(subtype.value);
    }
    if (dialIn.present) {
      map['dial_in'] = Variable<String>(dialIn.value);
    }
    if (link.present) {
      map['link'] = Variable<String>(link.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<DateTime>(endAt.value);
    }
    if (minutes.present) {
      map['minutes'] = Variable<String>(minutes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentMeetingsCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('calendarEventId: $calendarEventId, ')
          ..write('subtype: $subtype, ')
          ..write('dialIn: $dialIn, ')
          ..write('link: $link, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('minutes: $minutes, ')
          ..write('createdBy: $createdBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentReportsTable extends AssignmentReports
    with TableInfo<$AssignmentReportsTable, AssignmentReport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentReportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assignments (id)',
    ),
  );
  static const VerificationMeta _consideredJsonMeta = const VerificationMeta(
    'consideredJson',
  );
  @override
  late final GeneratedColumn<String> consideredJson = GeneratedColumn<String>(
    'considered_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedJsonMeta = const VerificationMeta(
    'acceptedJson',
  );
  @override
  late final GeneratedColumn<String> acceptedJson = GeneratedColumn<String>(
    'accepted_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rejectedJsonMeta = const VerificationMeta(
    'rejectedJson',
  );
  @override
  late final GeneratedColumn<String> rejectedJson = GeneratedColumn<String>(
    'rejected_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneJsonMeta = const VerificationMeta(
    'doneJson',
  );
  @override
  late final GeneratedColumn<String> doneJson = GeneratedColumn<String>(
    'done_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _compiledAtMeta = const VerificationMeta(
    'compiledAt',
  );
  @override
  late final GeneratedColumn<DateTime> compiledAt = GeneratedColumn<DateTime>(
    'compiled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _compiledByMeta = const VerificationMeta(
    'compiledBy',
  );
  @override
  late final GeneratedColumn<String> compiledBy = GeneratedColumn<String>(
    'compiled_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exportPathMeta = const VerificationMeta(
    'exportPath',
  );
  @override
  late final GeneratedColumn<String> exportPath = GeneratedColumn<String>(
    'export_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assignmentId,
    consideredJson,
    acceptedJson,
    rejectedJson,
    doneJson,
    notes,
    compiledAt,
    compiledBy,
    exportPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignment_reports';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssignmentReport> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('considered_json')) {
      context.handle(
        _consideredJsonMeta,
        consideredJson.isAcceptableOrUnknown(
          data['considered_json']!,
          _consideredJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_consideredJsonMeta);
    }
    if (data.containsKey('accepted_json')) {
      context.handle(
        _acceptedJsonMeta,
        acceptedJson.isAcceptableOrUnknown(
          data['accepted_json']!,
          _acceptedJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acceptedJsonMeta);
    }
    if (data.containsKey('rejected_json')) {
      context.handle(
        _rejectedJsonMeta,
        rejectedJson.isAcceptableOrUnknown(
          data['rejected_json']!,
          _rejectedJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rejectedJsonMeta);
    }
    if (data.containsKey('done_json')) {
      context.handle(
        _doneJsonMeta,
        doneJson.isAcceptableOrUnknown(data['done_json']!, _doneJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_doneJsonMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('compiled_at')) {
      context.handle(
        _compiledAtMeta,
        compiledAt.isAcceptableOrUnknown(data['compiled_at']!, _compiledAtMeta),
      );
    } else if (isInserting) {
      context.missing(_compiledAtMeta);
    }
    if (data.containsKey('compiled_by')) {
      context.handle(
        _compiledByMeta,
        compiledBy.isAcceptableOrUnknown(data['compiled_by']!, _compiledByMeta),
      );
    } else if (isInserting) {
      context.missing(_compiledByMeta);
    }
    if (data.containsKey('export_path')) {
      context.handle(
        _exportPathMeta,
        exportPath.isAcceptableOrUnknown(data['export_path']!, _exportPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assignmentId};
  @override
  AssignmentReport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssignmentReport(
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      consideredJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}considered_json'],
      )!,
      acceptedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accepted_json'],
      )!,
      rejectedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejected_json'],
      )!,
      doneJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}done_json'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      compiledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}compiled_at'],
      )!,
      compiledBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}compiled_by'],
      )!,
      exportPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}export_path'],
      ),
    );
  }

  @override
  $AssignmentReportsTable createAlias(String alias) {
    return $AssignmentReportsTable(attachedDatabase, alias);
  }
}

class AssignmentReport extends DataClass
    implements Insertable<AssignmentReport> {
  final String assignmentId;
  final String consideredJson;
  final String acceptedJson;
  final String rejectedJson;
  final String doneJson;
  final String? notes;
  final DateTime compiledAt;
  final String compiledBy;
  final String? exportPath;
  const AssignmentReport({
    required this.assignmentId,
    required this.consideredJson,
    required this.acceptedJson,
    required this.rejectedJson,
    required this.doneJson,
    this.notes,
    required this.compiledAt,
    required this.compiledBy,
    this.exportPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['assignment_id'] = Variable<String>(assignmentId);
    map['considered_json'] = Variable<String>(consideredJson);
    map['accepted_json'] = Variable<String>(acceptedJson);
    map['rejected_json'] = Variable<String>(rejectedJson);
    map['done_json'] = Variable<String>(doneJson);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['compiled_at'] = Variable<DateTime>(compiledAt);
    map['compiled_by'] = Variable<String>(compiledBy);
    if (!nullToAbsent || exportPath != null) {
      map['export_path'] = Variable<String>(exportPath);
    }
    return map;
  }

  AssignmentReportsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentReportsCompanion(
      assignmentId: Value(assignmentId),
      consideredJson: Value(consideredJson),
      acceptedJson: Value(acceptedJson),
      rejectedJson: Value(rejectedJson),
      doneJson: Value(doneJson),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      compiledAt: Value(compiledAt),
      compiledBy: Value(compiledBy),
      exportPath: exportPath == null && nullToAbsent
          ? const Value.absent()
          : Value(exportPath),
    );
  }

  factory AssignmentReport.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssignmentReport(
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      consideredJson: serializer.fromJson<String>(json['consideredJson']),
      acceptedJson: serializer.fromJson<String>(json['acceptedJson']),
      rejectedJson: serializer.fromJson<String>(json['rejectedJson']),
      doneJson: serializer.fromJson<String>(json['doneJson']),
      notes: serializer.fromJson<String?>(json['notes']),
      compiledAt: serializer.fromJson<DateTime>(json['compiledAt']),
      compiledBy: serializer.fromJson<String>(json['compiledBy']),
      exportPath: serializer.fromJson<String?>(json['exportPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assignmentId': serializer.toJson<String>(assignmentId),
      'consideredJson': serializer.toJson<String>(consideredJson),
      'acceptedJson': serializer.toJson<String>(acceptedJson),
      'rejectedJson': serializer.toJson<String>(rejectedJson),
      'doneJson': serializer.toJson<String>(doneJson),
      'notes': serializer.toJson<String?>(notes),
      'compiledAt': serializer.toJson<DateTime>(compiledAt),
      'compiledBy': serializer.toJson<String>(compiledBy),
      'exportPath': serializer.toJson<String?>(exportPath),
    };
  }

  AssignmentReport copyWith({
    String? assignmentId,
    String? consideredJson,
    String? acceptedJson,
    String? rejectedJson,
    String? doneJson,
    Value<String?> notes = const Value.absent(),
    DateTime? compiledAt,
    String? compiledBy,
    Value<String?> exportPath = const Value.absent(),
  }) => AssignmentReport(
    assignmentId: assignmentId ?? this.assignmentId,
    consideredJson: consideredJson ?? this.consideredJson,
    acceptedJson: acceptedJson ?? this.acceptedJson,
    rejectedJson: rejectedJson ?? this.rejectedJson,
    doneJson: doneJson ?? this.doneJson,
    notes: notes.present ? notes.value : this.notes,
    compiledAt: compiledAt ?? this.compiledAt,
    compiledBy: compiledBy ?? this.compiledBy,
    exportPath: exportPath.present ? exportPath.value : this.exportPath,
  );
  AssignmentReport copyWithCompanion(AssignmentReportsCompanion data) {
    return AssignmentReport(
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      consideredJson: data.consideredJson.present
          ? data.consideredJson.value
          : this.consideredJson,
      acceptedJson: data.acceptedJson.present
          ? data.acceptedJson.value
          : this.acceptedJson,
      rejectedJson: data.rejectedJson.present
          ? data.rejectedJson.value
          : this.rejectedJson,
      doneJson: data.doneJson.present ? data.doneJson.value : this.doneJson,
      notes: data.notes.present ? data.notes.value : this.notes,
      compiledAt: data.compiledAt.present
          ? data.compiledAt.value
          : this.compiledAt,
      compiledBy: data.compiledBy.present
          ? data.compiledBy.value
          : this.compiledBy,
      exportPath: data.exportPath.present
          ? data.exportPath.value
          : this.exportPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentReport(')
          ..write('assignmentId: $assignmentId, ')
          ..write('consideredJson: $consideredJson, ')
          ..write('acceptedJson: $acceptedJson, ')
          ..write('rejectedJson: $rejectedJson, ')
          ..write('doneJson: $doneJson, ')
          ..write('notes: $notes, ')
          ..write('compiledAt: $compiledAt, ')
          ..write('compiledBy: $compiledBy, ')
          ..write('exportPath: $exportPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assignmentId,
    consideredJson,
    acceptedJson,
    rejectedJson,
    doneJson,
    notes,
    compiledAt,
    compiledBy,
    exportPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssignmentReport &&
          other.assignmentId == this.assignmentId &&
          other.consideredJson == this.consideredJson &&
          other.acceptedJson == this.acceptedJson &&
          other.rejectedJson == this.rejectedJson &&
          other.doneJson == this.doneJson &&
          other.notes == this.notes &&
          other.compiledAt == this.compiledAt &&
          other.compiledBy == this.compiledBy &&
          other.exportPath == this.exportPath);
}

class AssignmentReportsCompanion extends UpdateCompanion<AssignmentReport> {
  final Value<String> assignmentId;
  final Value<String> consideredJson;
  final Value<String> acceptedJson;
  final Value<String> rejectedJson;
  final Value<String> doneJson;
  final Value<String?> notes;
  final Value<DateTime> compiledAt;
  final Value<String> compiledBy;
  final Value<String?> exportPath;
  final Value<int> rowid;
  const AssignmentReportsCompanion({
    this.assignmentId = const Value.absent(),
    this.consideredJson = const Value.absent(),
    this.acceptedJson = const Value.absent(),
    this.rejectedJson = const Value.absent(),
    this.doneJson = const Value.absent(),
    this.notes = const Value.absent(),
    this.compiledAt = const Value.absent(),
    this.compiledBy = const Value.absent(),
    this.exportPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentReportsCompanion.insert({
    required String assignmentId,
    required String consideredJson,
    required String acceptedJson,
    required String rejectedJson,
    required String doneJson,
    this.notes = const Value.absent(),
    required DateTime compiledAt,
    required String compiledBy,
    this.exportPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assignmentId = Value(assignmentId),
       consideredJson = Value(consideredJson),
       acceptedJson = Value(acceptedJson),
       rejectedJson = Value(rejectedJson),
       doneJson = Value(doneJson),
       compiledAt = Value(compiledAt),
       compiledBy = Value(compiledBy);
  static Insertable<AssignmentReport> custom({
    Expression<String>? assignmentId,
    Expression<String>? consideredJson,
    Expression<String>? acceptedJson,
    Expression<String>? rejectedJson,
    Expression<String>? doneJson,
    Expression<String>? notes,
    Expression<DateTime>? compiledAt,
    Expression<String>? compiledBy,
    Expression<String>? exportPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (consideredJson != null) 'considered_json': consideredJson,
      if (acceptedJson != null) 'accepted_json': acceptedJson,
      if (rejectedJson != null) 'rejected_json': rejectedJson,
      if (doneJson != null) 'done_json': doneJson,
      if (notes != null) 'notes': notes,
      if (compiledAt != null) 'compiled_at': compiledAt,
      if (compiledBy != null) 'compiled_by': compiledBy,
      if (exportPath != null) 'export_path': exportPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentReportsCompanion copyWith({
    Value<String>? assignmentId,
    Value<String>? consideredJson,
    Value<String>? acceptedJson,
    Value<String>? rejectedJson,
    Value<String>? doneJson,
    Value<String?>? notes,
    Value<DateTime>? compiledAt,
    Value<String>? compiledBy,
    Value<String?>? exportPath,
    Value<int>? rowid,
  }) {
    return AssignmentReportsCompanion(
      assignmentId: assignmentId ?? this.assignmentId,
      consideredJson: consideredJson ?? this.consideredJson,
      acceptedJson: acceptedJson ?? this.acceptedJson,
      rejectedJson: rejectedJson ?? this.rejectedJson,
      doneJson: doneJson ?? this.doneJson,
      notes: notes ?? this.notes,
      compiledAt: compiledAt ?? this.compiledAt,
      compiledBy: compiledBy ?? this.compiledBy,
      exportPath: exportPath ?? this.exportPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (consideredJson.present) {
      map['considered_json'] = Variable<String>(consideredJson.value);
    }
    if (acceptedJson.present) {
      map['accepted_json'] = Variable<String>(acceptedJson.value);
    }
    if (rejectedJson.present) {
      map['rejected_json'] = Variable<String>(rejectedJson.value);
    }
    if (doneJson.present) {
      map['done_json'] = Variable<String>(doneJson.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (compiledAt.present) {
      map['compiled_at'] = Variable<DateTime>(compiledAt.value);
    }
    if (compiledBy.present) {
      map['compiled_by'] = Variable<String>(compiledBy.value);
    }
    if (exportPath.present) {
      map['export_path'] = Variable<String>(exportPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentReportsCompanion(')
          ..write('assignmentId: $assignmentId, ')
          ..write('consideredJson: $consideredJson, ')
          ..write('acceptedJson: $acceptedJson, ')
          ..write('rejectedJson: $rejectedJson, ')
          ..write('doneJson: $doneJson, ')
          ..write('notes: $notes, ')
          ..write('compiledAt: $compiledAt, ')
          ..write('compiledBy: $compiledBy, ')
          ..write('exportPath: $exportPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $EmailsTable emails = $EmailsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $CalendarEventsTable calendarEvents = $CalendarEventsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $AuditLogTable auditLog = $AuditLogTable(this);
  late final $SignaturesTable signatures = $SignaturesTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $AssignmentsTable assignments = $AssignmentsTable(this);
  late final $AssignmentParticipantsTable assignmentParticipants =
      $AssignmentParticipantsTable(this);
  late final $AssignmentEventsTable assignmentEvents = $AssignmentEventsTable(
    this,
  );
  late final $AssignmentProposalsTable assignmentProposals =
      $AssignmentProposalsTable(this);
  late final $AssignmentVotesTable assignmentVotes = $AssignmentVotesTable(
    this,
  );
  late final $AssignmentMeetingsTable assignmentMeetings =
      $AssignmentMeetingsTable(this);
  late final $AssignmentReportsTable assignmentReports =
      $AssignmentReportsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    emails,
    folders,
    contacts,
    calendarEvents,
    tasks,
    syncQueue,
    auditLog,
    signatures,
    notes,
    assignments,
    assignmentParticipants,
    assignmentEvents,
    assignmentProposals,
    assignmentVotes,
    assignmentMeetings,
    assignmentReports,
  ];
}

typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required int type,
      required String email,
      required String displayName,
      required String username,
      Value<String?> domain,
      Value<String?> exchangeServer,
      Value<int?> exchangeAuthMethod,
      Value<String?> ewsUrl,
      Value<String?> imapServer,
      Value<int?> imapPort,
      Value<int?> imapEncryption,
      Value<String?> smtpServer,
      Value<int?> smtpPort,
      Value<int?> smtpEncryption,
      Value<int> syncInterval,
      Value<bool> syncOnlyWifi,
      Value<int> syncDays,
      Value<bool> isActive,
      Value<DateTime?> authFailedAt,
      Value<String?> sharedMailboxEmail,
      Value<String?> parentAccountId,
      Value<String?> accountKind,
      Value<bool> isPrimary,
      Value<int> colorValue,
      Value<String?> avatarUrl,
      Value<String?> signatureId,
      Value<String?> certificatePath,
      Value<int> fetchMode,
      required DateTime createdAt,
      Value<DateTime?> lastSyncAt,
      Value<int> unreadCount,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<int> type,
      Value<String> email,
      Value<String> displayName,
      Value<String> username,
      Value<String?> domain,
      Value<String?> exchangeServer,
      Value<int?> exchangeAuthMethod,
      Value<String?> ewsUrl,
      Value<String?> imapServer,
      Value<int?> imapPort,
      Value<int?> imapEncryption,
      Value<String?> smtpServer,
      Value<int?> smtpPort,
      Value<int?> smtpEncryption,
      Value<int> syncInterval,
      Value<bool> syncOnlyWifi,
      Value<int> syncDays,
      Value<bool> isActive,
      Value<DateTime?> authFailedAt,
      Value<String?> sharedMailboxEmail,
      Value<String?> parentAccountId,
      Value<String?> accountKind,
      Value<bool> isPrimary,
      Value<int> colorValue,
      Value<String?> avatarUrl,
      Value<String?> signatureId,
      Value<String?> certificatePath,
      Value<int> fetchMode,
      Value<DateTime> createdAt,
      Value<DateTime?> lastSyncAt,
      Value<int> unreadCount,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$AccountsTableReferences
    extends BaseReferences<_$AppDatabase, $AccountsTable, Account> {
  $$AccountsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EmailsTable, List<Email>> _emailsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.emails,
    aliasName: 'accounts__id__emails__account_id',
  );

  $$EmailsTableProcessedTableManager get emailsRefs {
    final manager = $$EmailsTableTableManager(
      $_db,
      $_db.emails,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_emailsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FoldersTable, List<Folder>> _foldersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.folders,
    aliasName: 'accounts__id__folders__account_id',
  );

  $$FoldersTableProcessedTableManager get foldersRefs {
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_foldersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CalendarEventsTable, List<CalendarEvent>>
  _calendarEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.calendarEvents,
    aliasName: 'accounts__id__calendar_events__account_id',
  );

  $$CalendarEventsTableProcessedTableManager get calendarEventsRefs {
    final manager = $$CalendarEventsTableTableManager(
      $_db,
      $_db.calendarEvents,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_calendarEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<Task>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: 'accounts__id__tasks__account_id',
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssignmentsTable, List<Assignment>>
  _assignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assignments,
    aliasName: 'accounts__id__assignments__account_id',
  );

  $$AssignmentsTableProcessedTableManager get assignmentsRefs {
    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assignmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangeServer => $composableBuilder(
    column: $table.exchangeServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exchangeAuthMethod => $composableBuilder(
    column: $table.exchangeAuthMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ewsUrl => $composableBuilder(
    column: $table.ewsUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imapServer => $composableBuilder(
    column: $table.imapServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imapPort => $composableBuilder(
    column: $table.imapPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imapEncryption => $composableBuilder(
    column: $table.imapEncryption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get smtpPort => $composableBuilder(
    column: $table.smtpPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get smtpEncryption => $composableBuilder(
    column: $table.smtpEncryption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncInterval => $composableBuilder(
    column: $table.syncInterval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get syncOnlyWifi => $composableBuilder(
    column: $table.syncOnlyWifi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncDays => $composableBuilder(
    column: $table.syncDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get authFailedAt => $composableBuilder(
    column: $table.authFailedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sharedMailboxEmail => $composableBuilder(
    column: $table.sharedMailboxEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentAccountId => $composableBuilder(
    column: $table.parentAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountKind => $composableBuilder(
    column: $table.accountKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signatureId => $composableBuilder(
    column: $table.signatureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get certificatePath => $composableBuilder(
    column: $table.certificatePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchMode => $composableBuilder(
    column: $table.fetchMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> emailsRefs(
    Expression<bool> Function($$EmailsTableFilterComposer f) f,
  ) {
    final $$EmailsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emails,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmailsTableFilterComposer(
            $db: $db,
            $table: $db.emails,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> foldersRefs(
    Expression<bool> Function($$FoldersTableFilterComposer f) f,
  ) {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> calendarEventsRefs(
    Expression<bool> Function($$CalendarEventsTableFilterComposer f) f,
  ) {
    final $$CalendarEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.calendarEvents,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarEventsTableFilterComposer(
            $db: $db,
            $table: $db.calendarEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assignmentsRefs(
    Expression<bool> Function($$AssignmentsTableFilterComposer f) f,
  ) {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangeServer => $composableBuilder(
    column: $table.exchangeServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exchangeAuthMethod => $composableBuilder(
    column: $table.exchangeAuthMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ewsUrl => $composableBuilder(
    column: $table.ewsUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imapServer => $composableBuilder(
    column: $table.imapServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imapPort => $composableBuilder(
    column: $table.imapPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imapEncryption => $composableBuilder(
    column: $table.imapEncryption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get smtpPort => $composableBuilder(
    column: $table.smtpPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get smtpEncryption => $composableBuilder(
    column: $table.smtpEncryption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncInterval => $composableBuilder(
    column: $table.syncInterval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get syncOnlyWifi => $composableBuilder(
    column: $table.syncOnlyWifi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncDays => $composableBuilder(
    column: $table.syncDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get authFailedAt => $composableBuilder(
    column: $table.authFailedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sharedMailboxEmail => $composableBuilder(
    column: $table.sharedMailboxEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentAccountId => $composableBuilder(
    column: $table.parentAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountKind => $composableBuilder(
    column: $table.accountKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signatureId => $composableBuilder(
    column: $table.signatureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get certificatePath => $composableBuilder(
    column: $table.certificatePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchMode => $composableBuilder(
    column: $table.fetchMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get exchangeServer => $composableBuilder(
    column: $table.exchangeServer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get exchangeAuthMethod => $composableBuilder(
    column: $table.exchangeAuthMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ewsUrl =>
      $composableBuilder(column: $table.ewsUrl, builder: (column) => column);

  GeneratedColumn<String> get imapServer => $composableBuilder(
    column: $table.imapServer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get imapPort =>
      $composableBuilder(column: $table.imapPort, builder: (column) => column);

  GeneratedColumn<int> get imapEncryption => $composableBuilder(
    column: $table.imapEncryption,
    builder: (column) => column,
  );

  GeneratedColumn<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get smtpPort =>
      $composableBuilder(column: $table.smtpPort, builder: (column) => column);

  GeneratedColumn<int> get smtpEncryption => $composableBuilder(
    column: $table.smtpEncryption,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncInterval => $composableBuilder(
    column: $table.syncInterval,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get syncOnlyWifi => $composableBuilder(
    column: $table.syncOnlyWifi,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncDays =>
      $composableBuilder(column: $table.syncDays, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get authFailedAt => $composableBuilder(
    column: $table.authFailedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sharedMailboxEmail => $composableBuilder(
    column: $table.sharedMailboxEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentAccountId => $composableBuilder(
    column: $table.parentAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountKind => $composableBuilder(
    column: $table.accountKind,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get signatureId => $composableBuilder(
    column: $table.signatureId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get certificatePath => $composableBuilder(
    column: $table.certificatePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchMode =>
      $composableBuilder(column: $table.fetchMode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> emailsRefs<T extends Object>(
    Expression<T> Function($$EmailsTableAnnotationComposer a) f,
  ) {
    final $$EmailsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.emails,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmailsTableAnnotationComposer(
            $db: $db,
            $table: $db.emails,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> foldersRefs<T extends Object>(
    Expression<T> Function($$FoldersTableAnnotationComposer a) f,
  ) {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> calendarEventsRefs<T extends Object>(
    Expression<T> Function($$CalendarEventsTableAnnotationComposer a) f,
  ) {
    final $$CalendarEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.calendarEvents,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.calendarEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> assignmentsRefs<T extends Object>(
    Expression<T> Function($$AssignmentsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, $$AccountsTableReferences),
          Account,
          PrefetchHooks Function({
            bool emailsRefs,
            bool foldersRefs,
            bool calendarEventsRefs,
            bool tasksRefs,
            bool assignmentsRefs,
          })
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String?> domain = const Value.absent(),
                Value<String?> exchangeServer = const Value.absent(),
                Value<int?> exchangeAuthMethod = const Value.absent(),
                Value<String?> ewsUrl = const Value.absent(),
                Value<String?> imapServer = const Value.absent(),
                Value<int?> imapPort = const Value.absent(),
                Value<int?> imapEncryption = const Value.absent(),
                Value<String?> smtpServer = const Value.absent(),
                Value<int?> smtpPort = const Value.absent(),
                Value<int?> smtpEncryption = const Value.absent(),
                Value<int> syncInterval = const Value.absent(),
                Value<bool> syncOnlyWifi = const Value.absent(),
                Value<int> syncDays = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime?> authFailedAt = const Value.absent(),
                Value<String?> sharedMailboxEmail = const Value.absent(),
                Value<String?> parentAccountId = const Value.absent(),
                Value<String?> accountKind = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> signatureId = const Value.absent(),
                Value<String?> certificatePath = const Value.absent(),
                Value<int> fetchMode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                type: type,
                email: email,
                displayName: displayName,
                username: username,
                domain: domain,
                exchangeServer: exchangeServer,
                exchangeAuthMethod: exchangeAuthMethod,
                ewsUrl: ewsUrl,
                imapServer: imapServer,
                imapPort: imapPort,
                imapEncryption: imapEncryption,
                smtpServer: smtpServer,
                smtpPort: smtpPort,
                smtpEncryption: smtpEncryption,
                syncInterval: syncInterval,
                syncOnlyWifi: syncOnlyWifi,
                syncDays: syncDays,
                isActive: isActive,
                authFailedAt: authFailedAt,
                sharedMailboxEmail: sharedMailboxEmail,
                parentAccountId: parentAccountId,
                accountKind: accountKind,
                isPrimary: isPrimary,
                colorValue: colorValue,
                avatarUrl: avatarUrl,
                signatureId: signatureId,
                certificatePath: certificatePath,
                fetchMode: fetchMode,
                createdAt: createdAt,
                lastSyncAt: lastSyncAt,
                unreadCount: unreadCount,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int type,
                required String email,
                required String displayName,
                required String username,
                Value<String?> domain = const Value.absent(),
                Value<String?> exchangeServer = const Value.absent(),
                Value<int?> exchangeAuthMethod = const Value.absent(),
                Value<String?> ewsUrl = const Value.absent(),
                Value<String?> imapServer = const Value.absent(),
                Value<int?> imapPort = const Value.absent(),
                Value<int?> imapEncryption = const Value.absent(),
                Value<String?> smtpServer = const Value.absent(),
                Value<int?> smtpPort = const Value.absent(),
                Value<int?> smtpEncryption = const Value.absent(),
                Value<int> syncInterval = const Value.absent(),
                Value<bool> syncOnlyWifi = const Value.absent(),
                Value<int> syncDays = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime?> authFailedAt = const Value.absent(),
                Value<String?> sharedMailboxEmail = const Value.absent(),
                Value<String?> parentAccountId = const Value.absent(),
                Value<String?> accountKind = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> signatureId = const Value.absent(),
                Value<String?> certificatePath = const Value.absent(),
                Value<int> fetchMode = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                type: type,
                email: email,
                displayName: displayName,
                username: username,
                domain: domain,
                exchangeServer: exchangeServer,
                exchangeAuthMethod: exchangeAuthMethod,
                ewsUrl: ewsUrl,
                imapServer: imapServer,
                imapPort: imapPort,
                imapEncryption: imapEncryption,
                smtpServer: smtpServer,
                smtpPort: smtpPort,
                smtpEncryption: smtpEncryption,
                syncInterval: syncInterval,
                syncOnlyWifi: syncOnlyWifi,
                syncDays: syncDays,
                isActive: isActive,
                authFailedAt: authFailedAt,
                sharedMailboxEmail: sharedMailboxEmail,
                parentAccountId: parentAccountId,
                accountKind: accountKind,
                isPrimary: isPrimary,
                colorValue: colorValue,
                avatarUrl: avatarUrl,
                signatureId: signatureId,
                certificatePath: certificatePath,
                fetchMode: fetchMode,
                createdAt: createdAt,
                lastSyncAt: lastSyncAt,
                unreadCount: unreadCount,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTable, Account>(table),
                  $$AccountsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                emailsRefs = false,
                foldersRefs = false,
                calendarEventsRefs = false,
                tasksRefs = false,
                assignmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (emailsRefs) db.emails,
                    if (foldersRefs) db.folders,
                    if (calendarEventsRefs) db.calendarEvents,
                    if (tasksRefs) db.tasks,
                    if (assignmentsRefs) db.assignments,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (emailsRefs)
                        await $_getPrefetchedDataByColumns<
                          Account,
                          $AccountsTable,
                          Email,
                          $EmailsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._emailsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).emailsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (foldersRefs)
                        await $_getPrefetchedDataByColumns<
                          Account,
                          $AccountsTable,
                          Folder,
                          $FoldersTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._foldersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).foldersRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (calendarEventsRefs)
                        await $_getPrefetchedDataByColumns<
                          Account,
                          $AccountsTable,
                          CalendarEvent,
                          $CalendarEventsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._calendarEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).calendarEventsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedDataByColumns<
                          Account,
                          $AccountsTable,
                          Task,
                          $TasksTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).tasksRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (assignmentsRefs)
                        await $_getPrefetchedDataByColumns<
                          Account,
                          $AccountsTable,
                          Assignment,
                          $AssignmentsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._assignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, $$AccountsTableReferences),
      Account,
      PrefetchHooks Function({
        bool emailsRefs,
        bool foldersRefs,
        bool calendarEventsRefs,
        bool tasksRefs,
        bool assignmentsRefs,
      })
    >;
typedef $$EmailsTableCreateCompanionBuilder =
    EmailsCompanion Function({
      required String id,
      required String accountId,
      required String folderId,
      Value<String?> folderName,
      Value<String?> conversationId,
      Value<String?> parentId,
      Value<String?> internetMessageId,
      Value<String?> referencesStr,
      required String fromEmail,
      Value<String?> fromName,
      required String toRecipients,
      Value<String?> ccJson,
      Value<String?> bccJson,
      Value<String?> replyToEmail,
      required String subject,
      Value<String?> bodyPlain,
      Value<String?> bodyHtml,
      Value<String?> bodyPreview,
      Value<String?> authResults,
      Value<String?> meetingJson,
      Value<DateTime?> remindAt,
      Value<DateTime?> followUpAt,
      Value<int> controlState,
      Value<int> laterState,
      Value<String?> listUnsubscribe,
      Value<String?> controlReplied,
      Value<String?> attachmentsJson,
      required DateTime receivedAt,
      Value<DateTime?> sentAt,
      Value<bool> isRead,
      Value<bool> isFlagged,
      Value<bool> isDraft,
      Value<bool> isReplied,
      Value<bool> isForwarded,
      Value<bool> hasAttachments,
      Value<int> priority,
      Value<int> status,
      Value<String?> tagsStr,
      Value<String?> categoriesStr,
      Value<String?> classification,
      Value<String?> sensitivity,
      Value<double?> sentimentScore,
      Value<String?> aiCategory,
      Value<String?> aiRecommendation,
      Value<DateTime?> extractedDeadline,
      Value<int?> size,
      Value<bool> readReceiptRequested,
      Value<bool> isLocallyModified,
      Value<int> loadedLevel,
      Value<DateTime?> cachedAt,
      Value<int> rowid,
    });
typedef $$EmailsTableUpdateCompanionBuilder =
    EmailsCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String> folderId,
      Value<String?> folderName,
      Value<String?> conversationId,
      Value<String?> parentId,
      Value<String?> internetMessageId,
      Value<String?> referencesStr,
      Value<String> fromEmail,
      Value<String?> fromName,
      Value<String> toRecipients,
      Value<String?> ccJson,
      Value<String?> bccJson,
      Value<String?> replyToEmail,
      Value<String> subject,
      Value<String?> bodyPlain,
      Value<String?> bodyHtml,
      Value<String?> bodyPreview,
      Value<String?> authResults,
      Value<String?> meetingJson,
      Value<DateTime?> remindAt,
      Value<DateTime?> followUpAt,
      Value<int> controlState,
      Value<int> laterState,
      Value<String?> listUnsubscribe,
      Value<String?> controlReplied,
      Value<String?> attachmentsJson,
      Value<DateTime> receivedAt,
      Value<DateTime?> sentAt,
      Value<bool> isRead,
      Value<bool> isFlagged,
      Value<bool> isDraft,
      Value<bool> isReplied,
      Value<bool> isForwarded,
      Value<bool> hasAttachments,
      Value<int> priority,
      Value<int> status,
      Value<String?> tagsStr,
      Value<String?> categoriesStr,
      Value<String?> classification,
      Value<String?> sensitivity,
      Value<double?> sentimentScore,
      Value<String?> aiCategory,
      Value<String?> aiRecommendation,
      Value<DateTime?> extractedDeadline,
      Value<int?> size,
      Value<bool> readReceiptRequested,
      Value<bool> isLocallyModified,
      Value<int> loadedLevel,
      Value<DateTime?> cachedAt,
      Value<int> rowid,
    });

final class $$EmailsTableReferences
    extends BaseReferences<_$AppDatabase, $EmailsTable, Email> {
  $$EmailsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('emails__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EmailsTableFilterComposer
    extends Composer<_$AppDatabase, $EmailsTable> {
  $$EmailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderName => $composableBuilder(
    column: $table.folderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get internetMessageId => $composableBuilder(
    column: $table.internetMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referencesStr => $composableBuilder(
    column: $table.referencesStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromEmail => $composableBuilder(
    column: $table.fromEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromName => $composableBuilder(
    column: $table.fromName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toRecipients => $composableBuilder(
    column: $table.toRecipients,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ccJson => $composableBuilder(
    column: $table.ccJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bccJson => $composableBuilder(
    column: $table.bccJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToEmail => $composableBuilder(
    column: $table.replyToEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyHtml => $composableBuilder(
    column: $table.bodyHtml,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPreview => $composableBuilder(
    column: $table.bodyPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authResults => $composableBuilder(
    column: $table.authResults,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meetingJson => $composableBuilder(
    column: $table.meetingJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get followUpAt => $composableBuilder(
    column: $table.followUpAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get controlState => $composableBuilder(
    column: $table.controlState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get laterState => $composableBuilder(
    column: $table.laterState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get controlReplied => $composableBuilder(
    column: $table.controlReplied,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDraft => $composableBuilder(
    column: $table.isDraft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isReplied => $composableBuilder(
    column: $table.isReplied,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isForwarded => $composableBuilder(
    column: $table.isForwarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsStr => $composableBuilder(
    column: $table.tagsStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sensitivity => $composableBuilder(
    column: $table.sensitivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sentimentScore => $composableBuilder(
    column: $table.sentimentScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiCategory => $composableBuilder(
    column: $table.aiCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiRecommendation => $composableBuilder(
    column: $table.aiRecommendation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get extractedDeadline => $composableBuilder(
    column: $table.extractedDeadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get readReceiptRequested => $composableBuilder(
    column: $table.readReceiptRequested,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loadedLevel => $composableBuilder(
    column: $table.loadedLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmailsTableOrderingComposer
    extends Composer<_$AppDatabase, $EmailsTable> {
  $$EmailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderName => $composableBuilder(
    column: $table.folderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get internetMessageId => $composableBuilder(
    column: $table.internetMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referencesStr => $composableBuilder(
    column: $table.referencesStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromEmail => $composableBuilder(
    column: $table.fromEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromName => $composableBuilder(
    column: $table.fromName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toRecipients => $composableBuilder(
    column: $table.toRecipients,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ccJson => $composableBuilder(
    column: $table.ccJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bccJson => $composableBuilder(
    column: $table.bccJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToEmail => $composableBuilder(
    column: $table.replyToEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyHtml => $composableBuilder(
    column: $table.bodyHtml,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPreview => $composableBuilder(
    column: $table.bodyPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authResults => $composableBuilder(
    column: $table.authResults,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meetingJson => $composableBuilder(
    column: $table.meetingJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get followUpAt => $composableBuilder(
    column: $table.followUpAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get controlState => $composableBuilder(
    column: $table.controlState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get laterState => $composableBuilder(
    column: $table.laterState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get controlReplied => $composableBuilder(
    column: $table.controlReplied,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDraft => $composableBuilder(
    column: $table.isDraft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isReplied => $composableBuilder(
    column: $table.isReplied,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isForwarded => $composableBuilder(
    column: $table.isForwarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsStr => $composableBuilder(
    column: $table.tagsStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sensitivity => $composableBuilder(
    column: $table.sensitivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sentimentScore => $composableBuilder(
    column: $table.sentimentScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiCategory => $composableBuilder(
    column: $table.aiCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiRecommendation => $composableBuilder(
    column: $table.aiRecommendation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get extractedDeadline => $composableBuilder(
    column: $table.extractedDeadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get readReceiptRequested => $composableBuilder(
    column: $table.readReceiptRequested,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loadedLevel => $composableBuilder(
    column: $table.loadedLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmailsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmailsTable> {
  $$EmailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get folderName => $composableBuilder(
    column: $table.folderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get internetMessageId => $composableBuilder(
    column: $table.internetMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referencesStr => $composableBuilder(
    column: $table.referencesStr,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fromEmail =>
      $composableBuilder(column: $table.fromEmail, builder: (column) => column);

  GeneratedColumn<String> get fromName =>
      $composableBuilder(column: $table.fromName, builder: (column) => column);

  GeneratedColumn<String> get toRecipients => $composableBuilder(
    column: $table.toRecipients,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ccJson =>
      $composableBuilder(column: $table.ccJson, builder: (column) => column);

  GeneratedColumn<String> get bccJson =>
      $composableBuilder(column: $table.bccJson, builder: (column) => column);

  GeneratedColumn<String> get replyToEmail => $composableBuilder(
    column: $table.replyToEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get bodyPlain =>
      $composableBuilder(column: $table.bodyPlain, builder: (column) => column);

  GeneratedColumn<String> get bodyHtml =>
      $composableBuilder(column: $table.bodyHtml, builder: (column) => column);

  GeneratedColumn<String> get bodyPreview => $composableBuilder(
    column: $table.bodyPreview,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authResults => $composableBuilder(
    column: $table.authResults,
    builder: (column) => column,
  );

  GeneratedColumn<String> get meetingJson => $composableBuilder(
    column: $table.meetingJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<DateTime> get followUpAt => $composableBuilder(
    column: $table.followUpAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get controlState => $composableBuilder(
    column: $table.controlState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get laterState => $composableBuilder(
    column: $table.laterState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => column,
  );

  GeneratedColumn<String> get controlReplied => $composableBuilder(
    column: $table.controlReplied,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<bool> get isFlagged =>
      $composableBuilder(column: $table.isFlagged, builder: (column) => column);

  GeneratedColumn<bool> get isDraft =>
      $composableBuilder(column: $table.isDraft, builder: (column) => column);

  GeneratedColumn<bool> get isReplied =>
      $composableBuilder(column: $table.isReplied, builder: (column) => column);

  GeneratedColumn<bool> get isForwarded => $composableBuilder(
    column: $table.isForwarded,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get tagsStr =>
      $composableBuilder(column: $table.tagsStr, builder: (column) => column);

  GeneratedColumn<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => column,
  );

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sensitivity => $composableBuilder(
    column: $table.sensitivity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get sentimentScore => $composableBuilder(
    column: $table.sentimentScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiCategory => $composableBuilder(
    column: $table.aiCategory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiRecommendation => $composableBuilder(
    column: $table.aiRecommendation,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get extractedDeadline => $composableBuilder(
    column: $table.extractedDeadline,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<bool> get readReceiptRequested => $composableBuilder(
    column: $table.readReceiptRequested,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get loadedLevel => $composableBuilder(
    column: $table.loadedLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmailsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmailsTable,
          Email,
          $$EmailsTableFilterComposer,
          $$EmailsTableOrderingComposer,
          $$EmailsTableAnnotationComposer,
          $$EmailsTableCreateCompanionBuilder,
          $$EmailsTableUpdateCompanionBuilder,
          (Email, $$EmailsTableReferences),
          Email,
          PrefetchHooks Function({bool accountId})
        > {
  $$EmailsTableTableManager(_$AppDatabase db, $EmailsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmailsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmailsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> folderId = const Value.absent(),
                Value<String?> folderName = const Value.absent(),
                Value<String?> conversationId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> internetMessageId = const Value.absent(),
                Value<String?> referencesStr = const Value.absent(),
                Value<String> fromEmail = const Value.absent(),
                Value<String?> fromName = const Value.absent(),
                Value<String> toRecipients = const Value.absent(),
                Value<String?> ccJson = const Value.absent(),
                Value<String?> bccJson = const Value.absent(),
                Value<String?> replyToEmail = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String?> bodyPlain = const Value.absent(),
                Value<String?> bodyHtml = const Value.absent(),
                Value<String?> bodyPreview = const Value.absent(),
                Value<String?> authResults = const Value.absent(),
                Value<String?> meetingJson = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<DateTime?> followUpAt = const Value.absent(),
                Value<int> controlState = const Value.absent(),
                Value<int> laterState = const Value.absent(),
                Value<String?> listUnsubscribe = const Value.absent(),
                Value<String?> controlReplied = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isDraft = const Value.absent(),
                Value<bool> isReplied = const Value.absent(),
                Value<bool> isForwarded = const Value.absent(),
                Value<bool> hasAttachments = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> tagsStr = const Value.absent(),
                Value<String?> categoriesStr = const Value.absent(),
                Value<String?> classification = const Value.absent(),
                Value<String?> sensitivity = const Value.absent(),
                Value<double?> sentimentScore = const Value.absent(),
                Value<String?> aiCategory = const Value.absent(),
                Value<String?> aiRecommendation = const Value.absent(),
                Value<DateTime?> extractedDeadline = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<bool> readReceiptRequested = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<int> loadedLevel = const Value.absent(),
                Value<DateTime?> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmailsCompanion(
                id: id,
                accountId: accountId,
                folderId: folderId,
                folderName: folderName,
                conversationId: conversationId,
                parentId: parentId,
                internetMessageId: internetMessageId,
                referencesStr: referencesStr,
                fromEmail: fromEmail,
                fromName: fromName,
                toRecipients: toRecipients,
                ccJson: ccJson,
                bccJson: bccJson,
                replyToEmail: replyToEmail,
                subject: subject,
                bodyPlain: bodyPlain,
                bodyHtml: bodyHtml,
                bodyPreview: bodyPreview,
                authResults: authResults,
                meetingJson: meetingJson,
                remindAt: remindAt,
                followUpAt: followUpAt,
                controlState: controlState,
                laterState: laterState,
                listUnsubscribe: listUnsubscribe,
                controlReplied: controlReplied,
                attachmentsJson: attachmentsJson,
                receivedAt: receivedAt,
                sentAt: sentAt,
                isRead: isRead,
                isFlagged: isFlagged,
                isDraft: isDraft,
                isReplied: isReplied,
                isForwarded: isForwarded,
                hasAttachments: hasAttachments,
                priority: priority,
                status: status,
                tagsStr: tagsStr,
                categoriesStr: categoriesStr,
                classification: classification,
                sensitivity: sensitivity,
                sentimentScore: sentimentScore,
                aiCategory: aiCategory,
                aiRecommendation: aiRecommendation,
                extractedDeadline: extractedDeadline,
                size: size,
                readReceiptRequested: readReceiptRequested,
                isLocallyModified: isLocallyModified,
                loadedLevel: loadedLevel,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String folderId,
                Value<String?> folderName = const Value.absent(),
                Value<String?> conversationId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> internetMessageId = const Value.absent(),
                Value<String?> referencesStr = const Value.absent(),
                required String fromEmail,
                Value<String?> fromName = const Value.absent(),
                required String toRecipients,
                Value<String?> ccJson = const Value.absent(),
                Value<String?> bccJson = const Value.absent(),
                Value<String?> replyToEmail = const Value.absent(),
                required String subject,
                Value<String?> bodyPlain = const Value.absent(),
                Value<String?> bodyHtml = const Value.absent(),
                Value<String?> bodyPreview = const Value.absent(),
                Value<String?> authResults = const Value.absent(),
                Value<String?> meetingJson = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<DateTime?> followUpAt = const Value.absent(),
                Value<int> controlState = const Value.absent(),
                Value<int> laterState = const Value.absent(),
                Value<String?> listUnsubscribe = const Value.absent(),
                Value<String?> controlReplied = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                required DateTime receivedAt,
                Value<DateTime?> sentAt = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isDraft = const Value.absent(),
                Value<bool> isReplied = const Value.absent(),
                Value<bool> isForwarded = const Value.absent(),
                Value<bool> hasAttachments = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> tagsStr = const Value.absent(),
                Value<String?> categoriesStr = const Value.absent(),
                Value<String?> classification = const Value.absent(),
                Value<String?> sensitivity = const Value.absent(),
                Value<double?> sentimentScore = const Value.absent(),
                Value<String?> aiCategory = const Value.absent(),
                Value<String?> aiRecommendation = const Value.absent(),
                Value<DateTime?> extractedDeadline = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<bool> readReceiptRequested = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<int> loadedLevel = const Value.absent(),
                Value<DateTime?> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmailsCompanion.insert(
                id: id,
                accountId: accountId,
                folderId: folderId,
                folderName: folderName,
                conversationId: conversationId,
                parentId: parentId,
                internetMessageId: internetMessageId,
                referencesStr: referencesStr,
                fromEmail: fromEmail,
                fromName: fromName,
                toRecipients: toRecipients,
                ccJson: ccJson,
                bccJson: bccJson,
                replyToEmail: replyToEmail,
                subject: subject,
                bodyPlain: bodyPlain,
                bodyHtml: bodyHtml,
                bodyPreview: bodyPreview,
                authResults: authResults,
                meetingJson: meetingJson,
                remindAt: remindAt,
                followUpAt: followUpAt,
                controlState: controlState,
                laterState: laterState,
                listUnsubscribe: listUnsubscribe,
                controlReplied: controlReplied,
                attachmentsJson: attachmentsJson,
                receivedAt: receivedAt,
                sentAt: sentAt,
                isRead: isRead,
                isFlagged: isFlagged,
                isDraft: isDraft,
                isReplied: isReplied,
                isForwarded: isForwarded,
                hasAttachments: hasAttachments,
                priority: priority,
                status: status,
                tagsStr: tagsStr,
                categoriesStr: categoriesStr,
                classification: classification,
                sensitivity: sensitivity,
                sentimentScore: sentimentScore,
                aiCategory: aiCategory,
                aiRecommendation: aiRecommendation,
                extractedDeadline: extractedDeadline,
                size: size,
                readReceiptRequested: readReceiptRequested,
                isLocallyModified: isLocallyModified,
                loadedLevel: loadedLevel,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EmailsTable, Email>(table),
                  $$EmailsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$EmailsTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$EmailsTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EmailsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmailsTable,
      Email,
      $$EmailsTableFilterComposer,
      $$EmailsTableOrderingComposer,
      $$EmailsTableAnnotationComposer,
      $$EmailsTableCreateCompanionBuilder,
      $$EmailsTableUpdateCompanionBuilder,
      (Email, $$EmailsTableReferences),
      Email,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      required String id,
      required String accountId,
      Value<String?> parentId,
      required String displayName,
      Value<int> type,
      Value<String?> serverPath,
      Value<int> unreadCount,
      Value<int> totalCount,
      Value<bool> showInUnified,
      Value<bool> isFavorite,
      Value<int> sortOrder,
      Value<bool> isSynced,
      Value<String?> iconName,
      Value<int> rowid,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String?> parentId,
      Value<String> displayName,
      Value<int> type,
      Value<String?> serverPath,
      Value<int> unreadCount,
      Value<int> totalCount,
      Value<bool> showInUnified,
      Value<bool> isFavorite,
      Value<int> sortOrder,
      Value<bool> isSynced,
      Value<String?> iconName,
      Value<int> rowid,
    });

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, Folder> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('folders__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverPath => $composableBuilder(
    column: $table.serverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showInUnified => $composableBuilder(
    column: $table.showInUnified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverPath => $composableBuilder(
    column: $table.serverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showInUnified => $composableBuilder(
    column: $table.showInUnified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get serverPath => $composableBuilder(
    column: $table.serverPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showInUnified => $composableBuilder(
    column: $table.showInUnified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<String> get iconName =>
      $composableBuilder(column: $table.iconName, builder: (column) => column);

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, $$FoldersTableReferences),
          Folder,
          PrefetchHooks Function({bool accountId})
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<String?> serverPath = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> totalCount = const Value.absent(),
                Value<bool> showInUnified = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<String?> iconName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                accountId: accountId,
                parentId: parentId,
                displayName: displayName,
                type: type,
                serverPath: serverPath,
                unreadCount: unreadCount,
                totalCount: totalCount,
                showInUnified: showInUnified,
                isFavorite: isFavorite,
                sortOrder: sortOrder,
                isSynced: isSynced,
                iconName: iconName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                Value<String?> parentId = const Value.absent(),
                required String displayName,
                Value<int> type = const Value.absent(),
                Value<String?> serverPath = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> totalCount = const Value.absent(),
                Value<bool> showInUnified = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<String?> iconName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                accountId: accountId,
                parentId: parentId,
                displayName: displayName,
                type: type,
                serverPath: serverPath,
                unreadCount: unreadCount,
                totalCount: totalCount,
                showInUnified: showInUnified,
                isFavorite: isFavorite,
                sortOrder: sortOrder,
                isSynced: isSynced,
                iconName: iconName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, Folder>(table),
                  $$FoldersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$FoldersTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$FoldersTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, $$FoldersTableReferences),
      Folder,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$ContactsTableCreateCompanionBuilder =
    ContactsCompanion Function({
      required String id,
      Value<String?> accountId,
      required String email,
      Value<String?> additionalEmails,
      required String displayName,
      Value<String?> firstName,
      Value<String?> middleName,
      Value<String?> lastName,
      Value<String?> jobTitle,
      Value<String?> department,
      Value<String?> company,
      Value<String?> phoneWork,
      Value<String?> phoneMobile,
      Value<String?> phoneExtension,
      Value<String?> office,
      Value<String?> manager,
      Value<String?> city,
      Value<String?> avatarPath,
      Value<String?> avatarUrl,
      Value<int> source,
      Value<bool> isFavorite,
      Value<bool> isVip,
      Value<int> interactionCount,
      Value<DateTime?> lastInteraction,
      Value<String?> notes,
      Value<DateTime?> birthday,
      Value<DateTime?> dirCheckedAt,
      Value<String?> dirOrg,
      Value<int> rowid,
    });
typedef $$ContactsTableUpdateCompanionBuilder =
    ContactsCompanion Function({
      Value<String> id,
      Value<String?> accountId,
      Value<String> email,
      Value<String?> additionalEmails,
      Value<String> displayName,
      Value<String?> firstName,
      Value<String?> middleName,
      Value<String?> lastName,
      Value<String?> jobTitle,
      Value<String?> department,
      Value<String?> company,
      Value<String?> phoneWork,
      Value<String?> phoneMobile,
      Value<String?> phoneExtension,
      Value<String?> office,
      Value<String?> manager,
      Value<String?> city,
      Value<String?> avatarPath,
      Value<String?> avatarUrl,
      Value<int> source,
      Value<bool> isFavorite,
      Value<bool> isVip,
      Value<int> interactionCount,
      Value<DateTime?> lastInteraction,
      Value<String?> notes,
      Value<DateTime?> birthday,
      Value<DateTime?> dirCheckedAt,
      Value<String?> dirOrg,
      Value<int> rowid,
    });

class $$ContactsTableFilterComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get additionalEmails => $composableBuilder(
    column: $table.additionalEmails,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobTitle => $composableBuilder(
    column: $table.jobTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get company => $composableBuilder(
    column: $table.company,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneWork => $composableBuilder(
    column: $table.phoneWork,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneMobile => $composableBuilder(
    column: $table.phoneMobile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneExtension => $composableBuilder(
    column: $table.phoneExtension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get office => $composableBuilder(
    column: $table.office,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manager => $composableBuilder(
    column: $table.manager,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get city => $composableBuilder(
    column: $table.city,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interactionCount => $composableBuilder(
    column: $table.interactionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastInteraction => $composableBuilder(
    column: $table.lastInteraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dirCheckedAt => $composableBuilder(
    column: $table.dirCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dirOrg => $composableBuilder(
    column: $table.dirOrg,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get additionalEmails => $composableBuilder(
    column: $table.additionalEmails,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobTitle => $composableBuilder(
    column: $table.jobTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get company => $composableBuilder(
    column: $table.company,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneWork => $composableBuilder(
    column: $table.phoneWork,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneMobile => $composableBuilder(
    column: $table.phoneMobile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneExtension => $composableBuilder(
    column: $table.phoneExtension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get office => $composableBuilder(
    column: $table.office,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manager => $composableBuilder(
    column: $table.manager,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get city => $composableBuilder(
    column: $table.city,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interactionCount => $composableBuilder(
    column: $table.interactionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastInteraction => $composableBuilder(
    column: $table.lastInteraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dirCheckedAt => $composableBuilder(
    column: $table.dirCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dirOrg => $composableBuilder(
    column: $table.dirOrg,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get additionalEmails => $composableBuilder(
    column: $table.additionalEmails,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get middleName => $composableBuilder(
    column: $table.middleName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get jobTitle =>
      $composableBuilder(column: $table.jobTitle, builder: (column) => column);

  GeneratedColumn<String> get department => $composableBuilder(
    column: $table.department,
    builder: (column) => column,
  );

  GeneratedColumn<String> get company =>
      $composableBuilder(column: $table.company, builder: (column) => column);

  GeneratedColumn<String> get phoneWork =>
      $composableBuilder(column: $table.phoneWork, builder: (column) => column);

  GeneratedColumn<String> get phoneMobile => $composableBuilder(
    column: $table.phoneMobile,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phoneExtension => $composableBuilder(
    column: $table.phoneExtension,
    builder: (column) => column,
  );

  GeneratedColumn<String> get office =>
      $composableBuilder(column: $table.office, builder: (column) => column);

  GeneratedColumn<String> get manager =>
      $composableBuilder(column: $table.manager, builder: (column) => column);

  GeneratedColumn<String> get city =>
      $composableBuilder(column: $table.city, builder: (column) => column);

  GeneratedColumn<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<int> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isVip =>
      $composableBuilder(column: $table.isVip, builder: (column) => column);

  GeneratedColumn<int> get interactionCount => $composableBuilder(
    column: $table.interactionCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastInteraction => $composableBuilder(
    column: $table.lastInteraction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get birthday =>
      $composableBuilder(column: $table.birthday, builder: (column) => column);

  GeneratedColumn<DateTime> get dirCheckedAt => $composableBuilder(
    column: $table.dirCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dirOrg =>
      $composableBuilder(column: $table.dirOrg, builder: (column) => column);
}

class $$ContactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContactsTable,
          Contact,
          $$ContactsTableFilterComposer,
          $$ContactsTableOrderingComposer,
          $$ContactsTableAnnotationComposer,
          $$ContactsTableCreateCompanionBuilder,
          $$ContactsTableUpdateCompanionBuilder,
          (Contact, BaseReferences<_$AppDatabase, $ContactsTable, Contact>),
          Contact,
          PrefetchHooks Function()
        > {
  $$ContactsTableTableManager(_$AppDatabase db, $ContactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String?> additionalEmails = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> firstName = const Value.absent(),
                Value<String?> middleName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> jobTitle = const Value.absent(),
                Value<String?> department = const Value.absent(),
                Value<String?> company = const Value.absent(),
                Value<String?> phoneWork = const Value.absent(),
                Value<String?> phoneMobile = const Value.absent(),
                Value<String?> phoneExtension = const Value.absent(),
                Value<String?> office = const Value.absent(),
                Value<String?> manager = const Value.absent(),
                Value<String?> city = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> source = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
                Value<int> interactionCount = const Value.absent(),
                Value<DateTime?> lastInteraction = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> birthday = const Value.absent(),
                Value<DateTime?> dirCheckedAt = const Value.absent(),
                Value<String?> dirOrg = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion(
                id: id,
                accountId: accountId,
                email: email,
                additionalEmails: additionalEmails,
                displayName: displayName,
                firstName: firstName,
                middleName: middleName,
                lastName: lastName,
                jobTitle: jobTitle,
                department: department,
                company: company,
                phoneWork: phoneWork,
                phoneMobile: phoneMobile,
                phoneExtension: phoneExtension,
                office: office,
                manager: manager,
                city: city,
                avatarPath: avatarPath,
                avatarUrl: avatarUrl,
                source: source,
                isFavorite: isFavorite,
                isVip: isVip,
                interactionCount: interactionCount,
                lastInteraction: lastInteraction,
                notes: notes,
                birthday: birthday,
                dirCheckedAt: dirCheckedAt,
                dirOrg: dirOrg,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> accountId = const Value.absent(),
                required String email,
                Value<String?> additionalEmails = const Value.absent(),
                required String displayName,
                Value<String?> firstName = const Value.absent(),
                Value<String?> middleName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> jobTitle = const Value.absent(),
                Value<String?> department = const Value.absent(),
                Value<String?> company = const Value.absent(),
                Value<String?> phoneWork = const Value.absent(),
                Value<String?> phoneMobile = const Value.absent(),
                Value<String?> phoneExtension = const Value.absent(),
                Value<String?> office = const Value.absent(),
                Value<String?> manager = const Value.absent(),
                Value<String?> city = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> source = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
                Value<int> interactionCount = const Value.absent(),
                Value<DateTime?> lastInteraction = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> birthday = const Value.absent(),
                Value<DateTime?> dirCheckedAt = const Value.absent(),
                Value<String?> dirOrg = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion.insert(
                id: id,
                accountId: accountId,
                email: email,
                additionalEmails: additionalEmails,
                displayName: displayName,
                firstName: firstName,
                middleName: middleName,
                lastName: lastName,
                jobTitle: jobTitle,
                department: department,
                company: company,
                phoneWork: phoneWork,
                phoneMobile: phoneMobile,
                phoneExtension: phoneExtension,
                office: office,
                manager: manager,
                city: city,
                avatarPath: avatarPath,
                avatarUrl: avatarUrl,
                source: source,
                isFavorite: isFavorite,
                isVip: isVip,
                interactionCount: interactionCount,
                lastInteraction: lastInteraction,
                notes: notes,
                birthday: birthday,
                dirCheckedAt: dirCheckedAt,
                dirOrg: dirOrg,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ContactsTable, Contact>(table),
                  BaseReferences<_$AppDatabase, $ContactsTable, Contact>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContactsTable,
      Contact,
      $$ContactsTableFilterComposer,
      $$ContactsTableOrderingComposer,
      $$ContactsTableAnnotationComposer,
      $$ContactsTableCreateCompanionBuilder,
      $$ContactsTableUpdateCompanionBuilder,
      (Contact, BaseReferences<_$AppDatabase, $ContactsTable, Contact>),
      Contact,
      PrefetchHooks Function()
    >;
typedef $$CalendarEventsTableCreateCompanionBuilder =
    CalendarEventsCompanion Function({
      required String id,
      required String accountId,
      Value<String?> calendarId,
      required String title,
      Value<String?> description,
      Value<String?> location,
      Value<String?> onlineMeetingUrl,
      required DateTime startTime,
      required DateTime endTime,
      Value<bool> isAllDay,
      Value<String?> attendeesJson,
      Value<String?> organizerEmail,
      Value<int> recurrence,
      Value<int> priority,
      Value<int> showAs,
      Value<int?> colorValue,
      Value<bool> isPrivate,
      Value<String?> remindersJson,
      Value<String?> linkedEmailId,
      Value<bool> isCancelled,
      Value<bool> isLocallyModified,
      required DateTime createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$CalendarEventsTableUpdateCompanionBuilder =
    CalendarEventsCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String?> calendarId,
      Value<String> title,
      Value<String?> description,
      Value<String?> location,
      Value<String?> onlineMeetingUrl,
      Value<DateTime> startTime,
      Value<DateTime> endTime,
      Value<bool> isAllDay,
      Value<String?> attendeesJson,
      Value<String?> organizerEmail,
      Value<int> recurrence,
      Value<int> priority,
      Value<int> showAs,
      Value<int?> colorValue,
      Value<bool> isPrivate,
      Value<String?> remindersJson,
      Value<String?> linkedEmailId,
      Value<bool> isCancelled,
      Value<bool> isLocallyModified,
      Value<DateTime> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

final class $$CalendarEventsTableReferences
    extends BaseReferences<_$AppDatabase, $CalendarEventsTable, CalendarEvent> {
  $$CalendarEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('calendar_events__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CalendarEventsTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get onlineMeetingUrl => $composableBuilder(
    column: $table.onlineMeetingUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attendeesJson => $composableBuilder(
    column: $table.attendeesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizerEmail => $composableBuilder(
    column: $table.organizerEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get showAs => $composableBuilder(
    column: $table.showAs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrivate => $composableBuilder(
    column: $table.isPrivate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remindersJson => $composableBuilder(
    column: $table.remindersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCancelled => $composableBuilder(
    column: $table.isCancelled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get onlineMeetingUrl => $composableBuilder(
    column: $table.onlineMeetingUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attendeesJson => $composableBuilder(
    column: $table.attendeesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizerEmail => $composableBuilder(
    column: $table.organizerEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get showAs => $composableBuilder(
    column: $table.showAs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrivate => $composableBuilder(
    column: $table.isPrivate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remindersJson => $composableBuilder(
    column: $table.remindersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCancelled => $composableBuilder(
    column: $table.isCancelled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get onlineMeetingUrl => $composableBuilder(
    column: $table.onlineMeetingUrl,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<bool> get isAllDay =>
      $composableBuilder(column: $table.isAllDay, builder: (column) => column);

  GeneratedColumn<String> get attendeesJson => $composableBuilder(
    column: $table.attendeesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get organizerEmail => $composableBuilder(
    column: $table.organizerEmail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get showAs =>
      $composableBuilder(column: $table.showAs, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPrivate =>
      $composableBuilder(column: $table.isPrivate, builder: (column) => column);

  GeneratedColumn<String> get remindersJson => $composableBuilder(
    column: $table.remindersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCancelled => $composableBuilder(
    column: $table.isCancelled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CalendarEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarEventsTable,
          CalendarEvent,
          $$CalendarEventsTableFilterComposer,
          $$CalendarEventsTableOrderingComposer,
          $$CalendarEventsTableAnnotationComposer,
          $$CalendarEventsTableCreateCompanionBuilder,
          $$CalendarEventsTableUpdateCompanionBuilder,
          (CalendarEvent, $$CalendarEventsTableReferences),
          CalendarEvent,
          PrefetchHooks Function({bool accountId})
        > {
  $$CalendarEventsTableTableManager(
    _$AppDatabase db,
    $CalendarEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> calendarId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> onlineMeetingUrl = const Value.absent(),
                Value<DateTime> startTime = const Value.absent(),
                Value<DateTime> endTime = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<String?> attendeesJson = const Value.absent(),
                Value<String?> organizerEmail = const Value.absent(),
                Value<int> recurrence = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> showAs = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> isPrivate = const Value.absent(),
                Value<String?> remindersJson = const Value.absent(),
                Value<String?> linkedEmailId = const Value.absent(),
                Value<bool> isCancelled = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarEventsCompanion(
                id: id,
                accountId: accountId,
                calendarId: calendarId,
                title: title,
                description: description,
                location: location,
                onlineMeetingUrl: onlineMeetingUrl,
                startTime: startTime,
                endTime: endTime,
                isAllDay: isAllDay,
                attendeesJson: attendeesJson,
                organizerEmail: organizerEmail,
                recurrence: recurrence,
                priority: priority,
                showAs: showAs,
                colorValue: colorValue,
                isPrivate: isPrivate,
                remindersJson: remindersJson,
                linkedEmailId: linkedEmailId,
                isCancelled: isCancelled,
                isLocallyModified: isLocallyModified,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                Value<String?> calendarId = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> onlineMeetingUrl = const Value.absent(),
                required DateTime startTime,
                required DateTime endTime,
                Value<bool> isAllDay = const Value.absent(),
                Value<String?> attendeesJson = const Value.absent(),
                Value<String?> organizerEmail = const Value.absent(),
                Value<int> recurrence = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> showAs = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> isPrivate = const Value.absent(),
                Value<String?> remindersJson = const Value.absent(),
                Value<String?> linkedEmailId = const Value.absent(),
                Value<bool> isCancelled = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarEventsCompanion.insert(
                id: id,
                accountId: accountId,
                calendarId: calendarId,
                title: title,
                description: description,
                location: location,
                onlineMeetingUrl: onlineMeetingUrl,
                startTime: startTime,
                endTime: endTime,
                isAllDay: isAllDay,
                attendeesJson: attendeesJson,
                organizerEmail: organizerEmail,
                recurrence: recurrence,
                priority: priority,
                showAs: showAs,
                colorValue: colorValue,
                isPrivate: isPrivate,
                remindersJson: remindersJson,
                linkedEmailId: linkedEmailId,
                isCancelled: isCancelled,
                isLocallyModified: isLocallyModified,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CalendarEventsTable, CalendarEvent>(table),
                  $$CalendarEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$CalendarEventsTableReferences
                                    ._accountIdTable(db),
                                referencedColumn:
                                    $$CalendarEventsTableReferences
                                        ._accountIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CalendarEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarEventsTable,
      CalendarEvent,
      $$CalendarEventsTableFilterComposer,
      $$CalendarEventsTableOrderingComposer,
      $$CalendarEventsTableAnnotationComposer,
      $$CalendarEventsTableCreateCompanionBuilder,
      $$CalendarEventsTableUpdateCompanionBuilder,
      (CalendarEvent, $$CalendarEventsTableReferences),
      CalendarEvent,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String accountId,
      required String title,
      Value<String?> description,
      Value<int> status,
      Value<int> priority,
      required DateTime createdAt,
      Value<DateTime?> dueDate,
      Value<DateTime?> completedAt,
      Value<int> progress,
      Value<String?> assigneeEmail,
      Value<String?> assigneeName,
      Value<String?> linkedEmailId,
      Value<String?> linkedEmailSubject,
      Value<String?> tagsStr,
      Value<String?> subtasksJson,
      Value<String?> commentsJson,
      Value<bool> isRecurring,
      Value<int?> recurrenceDays,
      Value<int?> colorValue,
      Value<bool> isFlagged,
      Value<bool> isLocallyModified,
      Value<DateTime?> reminderAt,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String> title,
      Value<String?> description,
      Value<int> status,
      Value<int> priority,
      Value<DateTime> createdAt,
      Value<DateTime?> dueDate,
      Value<DateTime?> completedAt,
      Value<int> progress,
      Value<String?> assigneeEmail,
      Value<String?> assigneeName,
      Value<String?> linkedEmailId,
      Value<String?> linkedEmailSubject,
      Value<String?> tagsStr,
      Value<String?> subtasksJson,
      Value<String?> commentsJson,
      Value<bool> isRecurring,
      Value<int?> recurrenceDays,
      Value<int?> colorValue,
      Value<bool> isFlagged,
      Value<bool> isLocallyModified,
      Value<DateTime?> reminderAt,
      Value<int> rowid,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('tasks__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assigneeEmail => $composableBuilder(
    column: $table.assigneeEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assigneeName => $composableBuilder(
    column: $table.assigneeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedEmailSubject => $composableBuilder(
    column: $table.linkedEmailSubject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsStr => $composableBuilder(
    column: $table.tagsStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtasksJson => $composableBuilder(
    column: $table.subtasksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRecurring => $composableBuilder(
    column: $table.isRecurring,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recurrenceDays => $composableBuilder(
    column: $table.recurrenceDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assigneeEmail => $composableBuilder(
    column: $table.assigneeEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assigneeName => $composableBuilder(
    column: $table.assigneeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedEmailSubject => $composableBuilder(
    column: $table.linkedEmailSubject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsStr => $composableBuilder(
    column: $table.tagsStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtasksJson => $composableBuilder(
    column: $table.subtasksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRecurring => $composableBuilder(
    column: $table.isRecurring,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recurrenceDays => $composableBuilder(
    column: $table.recurrenceDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get assigneeEmail => $composableBuilder(
    column: $table.assigneeEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assigneeName => $composableBuilder(
    column: $table.assigneeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedEmailId => $composableBuilder(
    column: $table.linkedEmailId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedEmailSubject => $composableBuilder(
    column: $table.linkedEmailSubject,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagsStr =>
      $composableBuilder(column: $table.tagsStr, builder: (column) => column);

  GeneratedColumn<String> get subtasksJson => $composableBuilder(
    column: $table.subtasksJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRecurring => $composableBuilder(
    column: $table.isRecurring,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recurrenceDays => $composableBuilder(
    column: $table.recurrenceDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFlagged =>
      $composableBuilder(column: $table.isFlagged, builder: (column) => column);

  GeneratedColumn<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reminderAt => $composableBuilder(
    column: $table.reminderAt,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({bool accountId})
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> progress = const Value.absent(),
                Value<String?> assigneeEmail = const Value.absent(),
                Value<String?> assigneeName = const Value.absent(),
                Value<String?> linkedEmailId = const Value.absent(),
                Value<String?> linkedEmailSubject = const Value.absent(),
                Value<String?> tagsStr = const Value.absent(),
                Value<String?> subtasksJson = const Value.absent(),
                Value<String?> commentsJson = const Value.absent(),
                Value<bool> isRecurring = const Value.absent(),
                Value<int?> recurrenceDays = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<DateTime?> reminderAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                accountId: accountId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                createdAt: createdAt,
                dueDate: dueDate,
                completedAt: completedAt,
                progress: progress,
                assigneeEmail: assigneeEmail,
                assigneeName: assigneeName,
                linkedEmailId: linkedEmailId,
                linkedEmailSubject: linkedEmailSubject,
                tagsStr: tagsStr,
                subtasksJson: subtasksJson,
                commentsJson: commentsJson,
                isRecurring: isRecurring,
                recurrenceDays: recurrenceDays,
                colorValue: colorValue,
                isFlagged: isFlagged,
                isLocallyModified: isLocallyModified,
                reminderAt: reminderAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> progress = const Value.absent(),
                Value<String?> assigneeEmail = const Value.absent(),
                Value<String?> assigneeName = const Value.absent(),
                Value<String?> linkedEmailId = const Value.absent(),
                Value<String?> linkedEmailSubject = const Value.absent(),
                Value<String?> tagsStr = const Value.absent(),
                Value<String?> subtasksJson = const Value.absent(),
                Value<String?> commentsJson = const Value.absent(),
                Value<bool> isRecurring = const Value.absent(),
                Value<int?> recurrenceDays = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<DateTime?> reminderAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                accountId: accountId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                createdAt: createdAt,
                dueDate: dueDate,
                completedAt: completedAt,
                progress: progress,
                assigneeEmail: assigneeEmail,
                assigneeName: assigneeName,
                linkedEmailId: linkedEmailId,
                linkedEmailSubject: linkedEmailSubject,
                tagsStr: tagsStr,
                subtasksJson: subtasksJson,
                commentsJson: commentsJson,
                isRecurring: isRecurring,
                recurrenceDays: recurrenceDays,
                colorValue: colorValue,
                isFlagged: isFlagged,
                isLocallyModified: isLocallyModified,
                reminderAt: reminderAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, Task>(table),
                  $$TasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$TasksTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$TasksTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$SyncQueueTableCreateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<int> id,
      required String accountId,
      required String operationType,
      required String targetId,
      required String payloadJson,
      Value<int> priority,
      Value<int> retryCount,
      required DateTime createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> errorMessage,
    });
typedef $$SyncQueueTableUpdateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<int> id,
      Value<String> accountId,
      Value<String> operationType,
      Value<String> targetId,
      Value<String> payloadJson,
      Value<int> priority,
      Value<int> retryCount,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> errorMessage,
    });

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );
}

class $$SyncQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueTable,
          SyncQueueData,
          $$SyncQueueTableFilterComposer,
          $$SyncQueueTableOrderingComposer,
          $$SyncQueueTableAnnotationComposer,
          $$SyncQueueTableCreateCompanionBuilder,
          $$SyncQueueTableUpdateCompanionBuilder,
          (
            SyncQueueData,
            BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
          ),
          SyncQueueData,
          PrefetchHooks Function()
        > {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
              }) => SyncQueueCompanion(
                id: id,
                accountId: accountId,
                operationType: operationType,
                targetId: targetId,
                payloadJson: payloadJson,
                priority: priority,
                retryCount: retryCount,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                errorMessage: errorMessage,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String operationType,
                required String targetId,
                required String payloadJson,
                Value<int> priority = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
              }) => SyncQueueCompanion.insert(
                id: id,
                accountId: accountId,
                operationType: operationType,
                targetId: targetId,
                payloadJson: payloadJson,
                priority: priority,
                retryCount: retryCount,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                errorMessage: errorMessage,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncQueueTable, SyncQueueData>(table),
                  BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueTable,
      SyncQueueData,
      $$SyncQueueTableFilterComposer,
      $$SyncQueueTableOrderingComposer,
      $$SyncQueueTableAnnotationComposer,
      $$SyncQueueTableCreateCompanionBuilder,
      $$SyncQueueTableUpdateCompanionBuilder,
      (
        SyncQueueData,
        BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
      ),
      SyncQueueData,
      PrefetchHooks Function()
    >;
typedef $$AuditLogTableCreateCompanionBuilder =
    AuditLogCompanion Function({
      Value<int> id,
      Value<String?> accountId,
      required String action,
      Value<String?> details,
      Value<String?> ipAddress,
      required DateTime timestamp,
    });
typedef $$AuditLogTableUpdateCompanionBuilder =
    AuditLogCompanion Function({
      Value<int> id,
      Value<String?> accountId,
      Value<String> action,
      Value<String?> details,
      Value<String?> ipAddress,
      Value<DateTime> timestamp,
    });

class $$AuditLogTableFilterComposer
    extends Composer<_$AppDatabase, $AuditLogTable> {
  $$AuditLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ipAddress => $composableBuilder(
    column: $table.ipAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditLogTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditLogTable> {
  $$AuditLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ipAddress => $composableBuilder(
    column: $table.ipAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditLogTable> {
  $$AuditLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get details =>
      $composableBuilder(column: $table.details, builder: (column) => column);

  GeneratedColumn<String> get ipAddress =>
      $composableBuilder(column: $table.ipAddress, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$AuditLogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditLogTable,
          AuditLogData,
          $$AuditLogTableFilterComposer,
          $$AuditLogTableOrderingComposer,
          $$AuditLogTableAnnotationComposer,
          $$AuditLogTableCreateCompanionBuilder,
          $$AuditLogTableUpdateCompanionBuilder,
          (
            AuditLogData,
            BaseReferences<_$AppDatabase, $AuditLogTable, AuditLogData>,
          ),
          AuditLogData,
          PrefetchHooks Function()
        > {
  $$AuditLogTableTableManager(_$AppDatabase db, $AuditLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> details = const Value.absent(),
                Value<String?> ipAddress = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => AuditLogCompanion(
                id: id,
                accountId: accountId,
                action: action,
                details: details,
                ipAddress: ipAddress,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                required String action,
                Value<String?> details = const Value.absent(),
                Value<String?> ipAddress = const Value.absent(),
                required DateTime timestamp,
              }) => AuditLogCompanion.insert(
                id: id,
                accountId: accountId,
                action: action,
                details: details,
                ipAddress: ipAddress,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AuditLogTable, AuditLogData>(table),
                  BaseReferences<_$AppDatabase, $AuditLogTable, AuditLogData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditLogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditLogTable,
      AuditLogData,
      $$AuditLogTableFilterComposer,
      $$AuditLogTableOrderingComposer,
      $$AuditLogTableAnnotationComposer,
      $$AuditLogTableCreateCompanionBuilder,
      $$AuditLogTableUpdateCompanionBuilder,
      (
        AuditLogData,
        BaseReferences<_$AppDatabase, $AuditLogTable, AuditLogData>,
      ),
      AuditLogData,
      PrefetchHooks Function()
    >;
typedef $$SignaturesTableCreateCompanionBuilder =
    SignaturesCompanion Function({
      required String id,
      Value<String?> accountId,
      required String name,
      required String htmlContent,
      required String plainContent,
      Value<bool> isDefault,
      Value<bool> useForNewEmails,
      Value<bool> useForReplies,
      Value<bool> useForForwards,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$SignaturesTableUpdateCompanionBuilder =
    SignaturesCompanion Function({
      Value<String> id,
      Value<String?> accountId,
      Value<String> name,
      Value<String> htmlContent,
      Value<String> plainContent,
      Value<bool> isDefault,
      Value<bool> useForNewEmails,
      Value<bool> useForReplies,
      Value<bool> useForForwards,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$SignaturesTableFilterComposer
    extends Composer<_$AppDatabase, $SignaturesTable> {
  $$SignaturesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get htmlContent => $composableBuilder(
    column: $table.htmlContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plainContent => $composableBuilder(
    column: $table.plainContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useForNewEmails => $composableBuilder(
    column: $table.useForNewEmails,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useForReplies => $composableBuilder(
    column: $table.useForReplies,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useForForwards => $composableBuilder(
    column: $table.useForForwards,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignaturesTableOrderingComposer
    extends Composer<_$AppDatabase, $SignaturesTable> {
  $$SignaturesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get htmlContent => $composableBuilder(
    column: $table.htmlContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plainContent => $composableBuilder(
    column: $table.plainContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useForNewEmails => $composableBuilder(
    column: $table.useForNewEmails,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useForReplies => $composableBuilder(
    column: $table.useForReplies,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useForForwards => $composableBuilder(
    column: $table.useForForwards,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignaturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SignaturesTable> {
  $$SignaturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get htmlContent => $composableBuilder(
    column: $table.htmlContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plainContent => $composableBuilder(
    column: $table.plainContent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get useForNewEmails => $composableBuilder(
    column: $table.useForNewEmails,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get useForReplies => $composableBuilder(
    column: $table.useForReplies,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get useForForwards => $composableBuilder(
    column: $table.useForForwards,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$SignaturesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SignaturesTable,
          Signature,
          $$SignaturesTableFilterComposer,
          $$SignaturesTableOrderingComposer,
          $$SignaturesTableAnnotationComposer,
          $$SignaturesTableCreateCompanionBuilder,
          $$SignaturesTableUpdateCompanionBuilder,
          (
            Signature,
            BaseReferences<_$AppDatabase, $SignaturesTable, Signature>,
          ),
          Signature,
          PrefetchHooks Function()
        > {
  $$SignaturesTableTableManager(_$AppDatabase db, $SignaturesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignaturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignaturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignaturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> htmlContent = const Value.absent(),
                Value<String> plainContent = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> useForNewEmails = const Value.absent(),
                Value<bool> useForReplies = const Value.absent(),
                Value<bool> useForForwards = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignaturesCompanion(
                id: id,
                accountId: accountId,
                name: name,
                htmlContent: htmlContent,
                plainContent: plainContent,
                isDefault: isDefault,
                useForNewEmails: useForNewEmails,
                useForReplies: useForReplies,
                useForForwards: useForForwards,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> accountId = const Value.absent(),
                required String name,
                required String htmlContent,
                required String plainContent,
                Value<bool> isDefault = const Value.absent(),
                Value<bool> useForNewEmails = const Value.absent(),
                Value<bool> useForReplies = const Value.absent(),
                Value<bool> useForForwards = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignaturesCompanion.insert(
                id: id,
                accountId: accountId,
                name: name,
                htmlContent: htmlContent,
                plainContent: plainContent,
                isDefault: isDefault,
                useForNewEmails: useForNewEmails,
                useForReplies: useForReplies,
                useForForwards: useForForwards,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SignaturesTable, Signature>(table),
                  BaseReferences<_$AppDatabase, $SignaturesTable, Signature>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignaturesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SignaturesTable,
      Signature,
      $$SignaturesTableFilterComposer,
      $$SignaturesTableOrderingComposer,
      $$SignaturesTableAnnotationComposer,
      $$SignaturesTableCreateCompanionBuilder,
      $$SignaturesTableUpdateCompanionBuilder,
      (Signature, BaseReferences<_$AppDatabase, $SignaturesTable, Signature>),
      Signature,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      Value<String?> accountId,
      Value<String> title,
      Value<String> body,
      Value<String?> categoriesStr,
      Value<int?> colorValue,
      Value<String?> serverId,
      required DateTime createdAt,
      required DateTime modifiedAt,
      Value<bool> isLocallyModified,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String?> accountId,
      Value<String> title,
      Value<String> body,
      Value<String?> categoriesStr,
      Value<int?> colorValue,
      Value<String?> serverId,
      Value<DateTime> createdAt,
      Value<DateTime> modifiedAt,
      Value<bool> isLocallyModified,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get categoriesStr => $composableBuilder(
    column: $table.categoriesStr,
    builder: (column) => column,
  );

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isLocallyModified => $composableBuilder(
    column: $table.isLocallyModified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
          Note,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> categoriesStr = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<bool> isLocallyModified = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                accountId: accountId,
                title: title,
                body: body,
                categoriesStr: categoriesStr,
                colorValue: colorValue,
                serverId: serverId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                isLocallyModified: isLocallyModified,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> accountId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> categoriesStr = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                required DateTime createdAt,
                required DateTime modifiedAt,
                Value<bool> isLocallyModified = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                accountId: accountId,
                title: title,
                body: body,
                categoriesStr: categoriesStr,
                colorValue: colorValue,
                serverId: serverId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                isLocallyModified: isLocallyModified,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotesTable, Note>(table),
                  BaseReferences<_$AppDatabase, $NotesTable, Note>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
      Note,
      PrefetchHooks Function()
    >;
typedef $$AssignmentsTableCreateCompanionBuilder =
    AssignmentsCompanion Function({
      required String id,
      required String accountId,
      Value<String?> sourceEmailId,
      required String title,
      Value<String?> description,
      Value<int> kind,
      Value<String?> recurrenceRule,
      Value<int> status,
      Value<int> priority,
      required String ownerEmail,
      Value<DateTime?> dueAt,
      Value<DateTime?> nextCheckpointAt,
      Value<String?> parentAssignmentId,
      Value<bool> isTemplate,
      Value<bool> autoDecideEnabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isArchived,
      Value<int> rowid,
    });
typedef $$AssignmentsTableUpdateCompanionBuilder =
    AssignmentsCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String?> sourceEmailId,
      Value<String> title,
      Value<String?> description,
      Value<int> kind,
      Value<String?> recurrenceRule,
      Value<int> status,
      Value<int> priority,
      Value<String> ownerEmail,
      Value<DateTime?> dueAt,
      Value<DateTime?> nextCheckpointAt,
      Value<String?> parentAssignmentId,
      Value<bool> isTemplate,
      Value<bool> autoDecideEnabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isArchived,
      Value<int> rowid,
    });

final class $$AssignmentsTableReferences
    extends BaseReferences<_$AppDatabase, $AssignmentsTable, Assignment> {
  $$AssignmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('assignments__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $AssignmentParticipantsTable,
    List<AssignmentParticipant>
  >
  _assignmentParticipantsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.assignmentParticipants,
        aliasName: 'assignments__id__assignment_participants__assignment_id',
      );

  $$AssignmentParticipantsTableProcessedTableManager
  get assignmentParticipantsRefs {
    final manager = $$AssignmentParticipantsTableTableManager(
      $_db,
      $_db.assignmentParticipants,
    ).filter((f) => f.assignmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentParticipantsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssignmentEventsTable, List<AssignmentEvent>>
  _assignmentEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assignmentEvents,
    aliasName: 'assignments__id__assignment_events__assignment_id',
  );

  $$AssignmentEventsTableProcessedTableManager get assignmentEventsRefs {
    final manager = $$AssignmentEventsTableTableManager(
      $_db,
      $_db.assignmentEvents,
    ).filter((f) => f.assignmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $AssignmentProposalsTable,
    List<AssignmentProposal>
  >
  _assignmentProposalsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.assignmentProposals,
        aliasName: 'assignments__id__assignment_proposals__assignment_id',
      );

  $$AssignmentProposalsTableProcessedTableManager get assignmentProposalsRefs {
    final manager = $$AssignmentProposalsTableTableManager(
      $_db,
      $_db.assignmentProposals,
    ).filter((f) => f.assignmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentProposalsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssignmentMeetingsTable, List<AssignmentMeeting>>
  _assignmentMeetingsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.assignmentMeetings,
        aliasName: 'assignments__id__assignment_meetings__assignment_id',
      );

  $$AssignmentMeetingsTableProcessedTableManager get assignmentMeetingsRefs {
    final manager = $$AssignmentMeetingsTableTableManager(
      $_db,
      $_db.assignmentMeetings,
    ).filter((f) => f.assignmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentMeetingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssignmentReportsTable, List<AssignmentReport>>
  _assignmentReportsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.assignmentReports,
        aliasName: 'assignments__id__assignment_reports__assignment_id',
      );

  $$AssignmentReportsTableProcessedTableManager get assignmentReportsRefs {
    final manager = $$AssignmentReportsTableTableManager(
      $_db,
      $_db.assignmentReports,
    ).filter((f) => f.assignmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentReportsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AssignmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextCheckpointAt => $composableBuilder(
    column: $table.nextCheckpointAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentAssignmentId => $composableBuilder(
    column: $table.parentAssignmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTemplate => $composableBuilder(
    column: $table.isTemplate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoDecideEnabled => $composableBuilder(
    column: $table.autoDecideEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> assignmentParticipantsRefs(
    Expression<bool> Function($$AssignmentParticipantsTableFilterComposer f) f,
  ) {
    final $$AssignmentParticipantsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assignmentParticipants,
          getReferencedColumn: (t) => t.assignmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentParticipantsTableFilterComposer(
                $db: $db,
                $table: $db.assignmentParticipants,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> assignmentEventsRefs(
    Expression<bool> Function($$AssignmentEventsTableFilterComposer f) f,
  ) {
    final $$AssignmentEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentEvents,
      getReferencedColumn: (t) => t.assignmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentEventsTableFilterComposer(
            $db: $db,
            $table: $db.assignmentEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assignmentProposalsRefs(
    Expression<bool> Function($$AssignmentProposalsTableFilterComposer f) f,
  ) {
    final $$AssignmentProposalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentProposals,
      getReferencedColumn: (t) => t.assignmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentProposalsTableFilterComposer(
            $db: $db,
            $table: $db.assignmentProposals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assignmentMeetingsRefs(
    Expression<bool> Function($$AssignmentMeetingsTableFilterComposer f) f,
  ) {
    final $$AssignmentMeetingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentMeetings,
      getReferencedColumn: (t) => t.assignmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentMeetingsTableFilterComposer(
            $db: $db,
            $table: $db.assignmentMeetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assignmentReportsRefs(
    Expression<bool> Function($$AssignmentReportsTableFilterComposer f) f,
  ) {
    final $$AssignmentReportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentReports,
      getReferencedColumn: (t) => t.assignmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentReportsTableFilterComposer(
            $db: $db,
            $table: $db.assignmentReports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssignmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextCheckpointAt => $composableBuilder(
    column: $table.nextCheckpointAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentAssignmentId => $composableBuilder(
    column: $table.parentAssignmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTemplate => $composableBuilder(
    column: $table.isTemplate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoDecideEnabled => $composableBuilder(
    column: $table.autoDecideEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get recurrenceRule => $composableBuilder(
    column: $table.recurrenceRule,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get ownerEmail => $composableBuilder(
    column: $table.ownerEmail,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextCheckpointAt => $composableBuilder(
    column: $table.nextCheckpointAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentAssignmentId => $composableBuilder(
    column: $table.parentAssignmentId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isTemplate => $composableBuilder(
    column: $table.isTemplate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoDecideEnabled => $composableBuilder(
    column: $table.autoDecideEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> assignmentParticipantsRefs<T extends Object>(
    Expression<T> Function($$AssignmentParticipantsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentParticipantsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assignmentParticipants,
          getReferencedColumn: (t) => t.assignmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentParticipantsTableAnnotationComposer(
                $db: $db,
                $table: $db.assignmentParticipants,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> assignmentEventsRefs<T extends Object>(
    Expression<T> Function($$AssignmentEventsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentEvents,
      getReferencedColumn: (t) => t.assignmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignmentEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> assignmentProposalsRefs<T extends Object>(
    Expression<T> Function($$AssignmentProposalsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentProposalsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assignmentProposals,
          getReferencedColumn: (t) => t.assignmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentProposalsTableAnnotationComposer(
                $db: $db,
                $table: $db.assignmentProposals,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> assignmentMeetingsRefs<T extends Object>(
    Expression<T> Function($$AssignmentMeetingsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentMeetingsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assignmentMeetings,
          getReferencedColumn: (t) => t.assignmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentMeetingsTableAnnotationComposer(
                $db: $db,
                $table: $db.assignmentMeetings,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> assignmentReportsRefs<T extends Object>(
    Expression<T> Function($$AssignmentReportsTableAnnotationComposer a) f,
  ) {
    final $$AssignmentReportsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assignmentReports,
          getReferencedColumn: (t) => t.assignmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentReportsTableAnnotationComposer(
                $db: $db,
                $table: $db.assignmentReports,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$AssignmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentsTable,
          Assignment,
          $$AssignmentsTableFilterComposer,
          $$AssignmentsTableOrderingComposer,
          $$AssignmentsTableAnnotationComposer,
          $$AssignmentsTableCreateCompanionBuilder,
          $$AssignmentsTableUpdateCompanionBuilder,
          (Assignment, $$AssignmentsTableReferences),
          Assignment,
          PrefetchHooks Function({
            bool accountId,
            bool assignmentParticipantsRefs,
            bool assignmentEventsRefs,
            bool assignmentProposalsRefs,
            bool assignmentMeetingsRefs,
            bool assignmentReportsRefs,
          })
        > {
  $$AssignmentsTableTableManager(_$AppDatabase db, $AssignmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> sourceEmailId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> ownerEmail = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<DateTime?> nextCheckpointAt = const Value.absent(),
                Value<String?> parentAssignmentId = const Value.absent(),
                Value<bool> isTemplate = const Value.absent(),
                Value<bool> autoDecideEnabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentsCompanion(
                id: id,
                accountId: accountId,
                sourceEmailId: sourceEmailId,
                title: title,
                description: description,
                kind: kind,
                recurrenceRule: recurrenceRule,
                status: status,
                priority: priority,
                ownerEmail: ownerEmail,
                dueAt: dueAt,
                nextCheckpointAt: nextCheckpointAt,
                parentAssignmentId: parentAssignmentId,
                isTemplate: isTemplate,
                autoDecideEnabled: autoDecideEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isArchived: isArchived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                Value<String?> sourceEmailId = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<String?> recurrenceRule = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                required String ownerEmail,
                Value<DateTime?> dueAt = const Value.absent(),
                Value<DateTime?> nextCheckpointAt = const Value.absent(),
                Value<String?> parentAssignmentId = const Value.absent(),
                Value<bool> isTemplate = const Value.absent(),
                Value<bool> autoDecideEnabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentsCompanion.insert(
                id: id,
                accountId: accountId,
                sourceEmailId: sourceEmailId,
                title: title,
                description: description,
                kind: kind,
                recurrenceRule: recurrenceRule,
                status: status,
                priority: priority,
                ownerEmail: ownerEmail,
                dueAt: dueAt,
                nextCheckpointAt: nextCheckpointAt,
                parentAssignmentId: parentAssignmentId,
                isTemplate: isTemplate,
                autoDecideEnabled: autoDecideEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isArchived: isArchived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentsTable, Assignment>(table),
                  $$AssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                accountId = false,
                assignmentParticipantsRefs = false,
                assignmentEventsRefs = false,
                assignmentProposalsRefs = false,
                assignmentMeetingsRefs = false,
                assignmentReportsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (assignmentParticipantsRefs) db.assignmentParticipants,
                    if (assignmentEventsRefs) db.assignmentEvents,
                    if (assignmentProposalsRefs) db.assignmentProposals,
                    if (assignmentMeetingsRefs) db.assignmentMeetings,
                    if (assignmentReportsRefs) db.assignmentReports,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (accountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.accountId,
                                    referencedTable:
                                        $$AssignmentsTableReferences
                                            ._accountIdTable(db),
                                    referencedColumn:
                                        $$AssignmentsTableReferences
                                            ._accountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (assignmentParticipantsRefs)
                        await $_getPrefetchedDataByColumns<
                          Assignment,
                          $AssignmentsTable,
                          AssignmentParticipant,
                          $AssignmentParticipantsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentsTableReferences
                              ._assignmentParticipantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentParticipantsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'assignment_id',
                          typedResults: items,
                        ),
                      if (assignmentEventsRefs)
                        await $_getPrefetchedDataByColumns<
                          Assignment,
                          $AssignmentsTable,
                          AssignmentEvent,
                          $AssignmentEventsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentsTableReferences
                              ._assignmentEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentEventsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'assignment_id',
                          typedResults: items,
                        ),
                      if (assignmentProposalsRefs)
                        await $_getPrefetchedDataByColumns<
                          Assignment,
                          $AssignmentsTable,
                          AssignmentProposal,
                          $AssignmentProposalsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentsTableReferences
                              ._assignmentProposalsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentProposalsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'assignment_id',
                          typedResults: items,
                        ),
                      if (assignmentMeetingsRefs)
                        await $_getPrefetchedDataByColumns<
                          Assignment,
                          $AssignmentsTable,
                          AssignmentMeeting,
                          $AssignmentMeetingsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentsTableReferences
                              ._assignmentMeetingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentMeetingsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'assignment_id',
                          typedResults: items,
                        ),
                      if (assignmentReportsRefs)
                        await $_getPrefetchedDataByColumns<
                          Assignment,
                          $AssignmentsTable,
                          AssignmentReport,
                          $AssignmentReportsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentsTableReferences
                              ._assignmentReportsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentReportsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'assignment_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentsTable,
      Assignment,
      $$AssignmentsTableFilterComposer,
      $$AssignmentsTableOrderingComposer,
      $$AssignmentsTableAnnotationComposer,
      $$AssignmentsTableCreateCompanionBuilder,
      $$AssignmentsTableUpdateCompanionBuilder,
      (Assignment, $$AssignmentsTableReferences),
      Assignment,
      PrefetchHooks Function({
        bool accountId,
        bool assignmentParticipantsRefs,
        bool assignmentEventsRefs,
        bool assignmentProposalsRefs,
        bool assignmentMeetingsRefs,
        bool assignmentReportsRefs,
      })
    >;
typedef $$AssignmentParticipantsTableCreateCompanionBuilder =
    AssignmentParticipantsCompanion Function({
      required String assignmentId,
      required String email,
      Value<String?> displayName,
      required int role,
      Value<int> inviteStatus,
      Value<bool?> isOurClient,
      Value<int> rowid,
    });
typedef $$AssignmentParticipantsTableUpdateCompanionBuilder =
    AssignmentParticipantsCompanion Function({
      Value<String> assignmentId,
      Value<String> email,
      Value<String?> displayName,
      Value<int> role,
      Value<int> inviteStatus,
      Value<bool?> isOurClient,
      Value<int> rowid,
    });

final class $$AssignmentParticipantsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AssignmentParticipantsTable,
          AssignmentParticipant
        > {
  $$AssignmentParticipantsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentsTable _assignmentIdTable(_$AppDatabase db) => db
      .assignments
      .createAlias('assignment_participants__assignment_id__assignments__id');

  $$AssignmentsTableProcessedTableManager get assignmentId {
    final $_column = $_itemColumn<String>('assignment_id')!;

    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssignmentParticipantsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentParticipantsTable> {
  $$AssignmentParticipantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inviteStatus => $composableBuilder(
    column: $table.inviteStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOurClient => $composableBuilder(
    column: $table.isOurClient,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentsTableFilterComposer get assignmentId {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentParticipantsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentParticipantsTable> {
  $$AssignmentParticipantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inviteStatus => $composableBuilder(
    column: $table.inviteStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOurClient => $composableBuilder(
    column: $table.isOurClient,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentsTableOrderingComposer get assignmentId {
    final $$AssignmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentParticipantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentParticipantsTable> {
  $$AssignmentParticipantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get inviteStatus => $composableBuilder(
    column: $table.inviteStatus,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOurClient => $composableBuilder(
    column: $table.isOurClient,
    builder: (column) => column,
  );

  $$AssignmentsTableAnnotationComposer get assignmentId {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentParticipantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentParticipantsTable,
          AssignmentParticipant,
          $$AssignmentParticipantsTableFilterComposer,
          $$AssignmentParticipantsTableOrderingComposer,
          $$AssignmentParticipantsTableAnnotationComposer,
          $$AssignmentParticipantsTableCreateCompanionBuilder,
          $$AssignmentParticipantsTableUpdateCompanionBuilder,
          (AssignmentParticipant, $$AssignmentParticipantsTableReferences),
          AssignmentParticipant,
          PrefetchHooks Function({bool assignmentId})
        > {
  $$AssignmentParticipantsTableTableManager(
    _$AppDatabase db,
    $AssignmentParticipantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentParticipantsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AssignmentParticipantsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AssignmentParticipantsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assignmentId = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<int> inviteStatus = const Value.absent(),
                Value<bool?> isOurClient = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentParticipantsCompanion(
                assignmentId: assignmentId,
                email: email,
                displayName: displayName,
                role: role,
                inviteStatus: inviteStatus,
                isOurClient: isOurClient,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assignmentId,
                required String email,
                Value<String?> displayName = const Value.absent(),
                required int role,
                Value<int> inviteStatus = const Value.absent(),
                Value<bool?> isOurClient = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentParticipantsCompanion.insert(
                assignmentId: assignmentId,
                email: email,
                displayName: displayName,
                role: role,
                inviteStatus: inviteStatus,
                isOurClient: isOurClient,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $AssignmentParticipantsTable,
                    AssignmentParticipant
                  >(table),
                  $$AssignmentParticipantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assignmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assignmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assignmentId,
                                referencedTable:
                                    $$AssignmentParticipantsTableReferences
                                        ._assignmentIdTable(db),
                                referencedColumn:
                                    $$AssignmentParticipantsTableReferences
                                        ._assignmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssignmentParticipantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentParticipantsTable,
      AssignmentParticipant,
      $$AssignmentParticipantsTableFilterComposer,
      $$AssignmentParticipantsTableOrderingComposer,
      $$AssignmentParticipantsTableAnnotationComposer,
      $$AssignmentParticipantsTableCreateCompanionBuilder,
      $$AssignmentParticipantsTableUpdateCompanionBuilder,
      (AssignmentParticipant, $$AssignmentParticipantsTableReferences),
      AssignmentParticipant,
      PrefetchHooks Function({bool assignmentId})
    >;
typedef $$AssignmentEventsTableCreateCompanionBuilder =
    AssignmentEventsCompanion Function({
      required String id,
      required String assignmentId,
      required String type,
      required String authorEmail,
      required DateTime createdAt,
      required String payloadJson,
      Value<String?> refId,
      Value<String?> sourceEmailId,
      required int direction,
      Value<int> deliveryStatus,
      Value<int> signatureState,
      Value<int> rowid,
    });
typedef $$AssignmentEventsTableUpdateCompanionBuilder =
    AssignmentEventsCompanion Function({
      Value<String> id,
      Value<String> assignmentId,
      Value<String> type,
      Value<String> authorEmail,
      Value<DateTime> createdAt,
      Value<String> payloadJson,
      Value<String?> refId,
      Value<String?> sourceEmailId,
      Value<int> direction,
      Value<int> deliveryStatus,
      Value<int> signatureState,
      Value<int> rowid,
    });

final class $$AssignmentEventsTableReferences
    extends
        BaseReferences<_$AppDatabase, $AssignmentEventsTable, AssignmentEvent> {
  $$AssignmentEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentsTable _assignmentIdTable(_$AppDatabase db) => db
      .assignments
      .createAlias('assignment_events__assignment_id__assignments__id');

  $$AssignmentsTableProcessedTableManager get assignmentId {
    final $_column = $_itemColumn<String>('assignment_id')!;

    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssignmentEventsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentEventsTable> {
  $$AssignmentEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get signatureState => $composableBuilder(
    column: $table.signatureState,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentsTableFilterComposer get assignmentId {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentEventsTable> {
  $$AssignmentEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get signatureState => $composableBuilder(
    column: $table.signatureState,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentsTableOrderingComposer get assignmentId {
    final $$AssignmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentEventsTable> {
  $$AssignmentEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get sourceEmailId => $composableBuilder(
    column: $table.sourceEmailId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<int> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get signatureState => $composableBuilder(
    column: $table.signatureState,
    builder: (column) => column,
  );

  $$AssignmentsTableAnnotationComposer get assignmentId {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentEventsTable,
          AssignmentEvent,
          $$AssignmentEventsTableFilterComposer,
          $$AssignmentEventsTableOrderingComposer,
          $$AssignmentEventsTableAnnotationComposer,
          $$AssignmentEventsTableCreateCompanionBuilder,
          $$AssignmentEventsTableUpdateCompanionBuilder,
          (AssignmentEvent, $$AssignmentEventsTableReferences),
          AssignmentEvent,
          PrefetchHooks Function({bool assignmentId})
        > {
  $$AssignmentEventsTableTableManager(
    _$AppDatabase db,
    $AssignmentEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assignmentId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> authorEmail = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<String?> sourceEmailId = const Value.absent(),
                Value<int> direction = const Value.absent(),
                Value<int> deliveryStatus = const Value.absent(),
                Value<int> signatureState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentEventsCompanion(
                id: id,
                assignmentId: assignmentId,
                type: type,
                authorEmail: authorEmail,
                createdAt: createdAt,
                payloadJson: payloadJson,
                refId: refId,
                sourceEmailId: sourceEmailId,
                direction: direction,
                deliveryStatus: deliveryStatus,
                signatureState: signatureState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assignmentId,
                required String type,
                required String authorEmail,
                required DateTime createdAt,
                required String payloadJson,
                Value<String?> refId = const Value.absent(),
                Value<String?> sourceEmailId = const Value.absent(),
                required int direction,
                Value<int> deliveryStatus = const Value.absent(),
                Value<int> signatureState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentEventsCompanion.insert(
                id: id,
                assignmentId: assignmentId,
                type: type,
                authorEmail: authorEmail,
                createdAt: createdAt,
                payloadJson: payloadJson,
                refId: refId,
                sourceEmailId: sourceEmailId,
                direction: direction,
                deliveryStatus: deliveryStatus,
                signatureState: signatureState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentEventsTable, AssignmentEvent>(table),
                  $$AssignmentEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assignmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assignmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assignmentId,
                                referencedTable:
                                    $$AssignmentEventsTableReferences
                                        ._assignmentIdTable(db),
                                referencedColumn:
                                    $$AssignmentEventsTableReferences
                                        ._assignmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssignmentEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentEventsTable,
      AssignmentEvent,
      $$AssignmentEventsTableFilterComposer,
      $$AssignmentEventsTableOrderingComposer,
      $$AssignmentEventsTableAnnotationComposer,
      $$AssignmentEventsTableCreateCompanionBuilder,
      $$AssignmentEventsTableUpdateCompanionBuilder,
      (AssignmentEvent, $$AssignmentEventsTableReferences),
      AssignmentEvent,
      PrefetchHooks Function({bool assignmentId})
    >;
typedef $$AssignmentProposalsTableCreateCompanionBuilder =
    AssignmentProposalsCompanion Function({
      required String id,
      required String assignmentId,
      required String authorEmail,
      required String body,
      Value<String?> attachmentsJson,
      Value<int> status,
      Value<String?> decidedBy,
      Value<int?> decisionMethod,
      Value<DateTime?> decidedAt,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$AssignmentProposalsTableUpdateCompanionBuilder =
    AssignmentProposalsCompanion Function({
      Value<String> id,
      Value<String> assignmentId,
      Value<String> authorEmail,
      Value<String> body,
      Value<String?> attachmentsJson,
      Value<int> status,
      Value<String?> decidedBy,
      Value<int?> decisionMethod,
      Value<DateTime?> decidedAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AssignmentProposalsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AssignmentProposalsTable,
          AssignmentProposal
        > {
  $$AssignmentProposalsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentsTable _assignmentIdTable(_$AppDatabase db) => db
      .assignments
      .createAlias('assignment_proposals__assignment_id__assignments__id');

  $$AssignmentsTableProcessedTableManager get assignmentId {
    final $_column = $_itemColumn<String>('assignment_id')!;

    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AssignmentVotesTable, List<AssignmentVote>>
  _assignmentVotesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assignmentVotes,
    aliasName: 'assignment_proposals__id__assignment_votes__proposal_id',
  );

  $$AssignmentVotesTableProcessedTableManager get assignmentVotesRefs {
    final manager = $$AssignmentVotesTableTableManager(
      $_db,
      $_db.assignmentVotes,
    ).filter((f) => f.proposalId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assignmentVotesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AssignmentProposalsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentProposalsTable> {
  $$AssignmentProposalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decidedBy => $composableBuilder(
    column: $table.decidedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decisionMethod => $composableBuilder(
    column: $table.decisionMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get decidedAt => $composableBuilder(
    column: $table.decidedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentsTableFilterComposer get assignmentId {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> assignmentVotesRefs(
    Expression<bool> Function($$AssignmentVotesTableFilterComposer f) f,
  ) {
    final $$AssignmentVotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentVotes,
      getReferencedColumn: (t) => t.proposalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentVotesTableFilterComposer(
            $db: $db,
            $table: $db.assignmentVotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssignmentProposalsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentProposalsTable> {
  $$AssignmentProposalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decidedBy => $composableBuilder(
    column: $table.decidedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decisionMethod => $composableBuilder(
    column: $table.decisionMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get decidedAt => $composableBuilder(
    column: $table.decidedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentsTableOrderingComposer get assignmentId {
    final $$AssignmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentProposalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentProposalsTable> {
  $$AssignmentProposalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get authorEmail => $composableBuilder(
    column: $table.authorEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get decidedBy =>
      $composableBuilder(column: $table.decidedBy, builder: (column) => column);

  GeneratedColumn<int> get decisionMethod => $composableBuilder(
    column: $table.decisionMethod,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get decidedAt =>
      $composableBuilder(column: $table.decidedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$AssignmentsTableAnnotationComposer get assignmentId {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> assignmentVotesRefs<T extends Object>(
    Expression<T> Function($$AssignmentVotesTableAnnotationComposer a) f,
  ) {
    final $$AssignmentVotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assignmentVotes,
      getReferencedColumn: (t) => t.proposalId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentVotesTableAnnotationComposer(
            $db: $db,
            $table: $db.assignmentVotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssignmentProposalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentProposalsTable,
          AssignmentProposal,
          $$AssignmentProposalsTableFilterComposer,
          $$AssignmentProposalsTableOrderingComposer,
          $$AssignmentProposalsTableAnnotationComposer,
          $$AssignmentProposalsTableCreateCompanionBuilder,
          $$AssignmentProposalsTableUpdateCompanionBuilder,
          (AssignmentProposal, $$AssignmentProposalsTableReferences),
          AssignmentProposal,
          PrefetchHooks Function({bool assignmentId, bool assignmentVotesRefs})
        > {
  $$AssignmentProposalsTableTableManager(
    _$AppDatabase db,
    $AssignmentProposalsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentProposalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentProposalsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AssignmentProposalsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assignmentId = const Value.absent(),
                Value<String> authorEmail = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> decidedBy = const Value.absent(),
                Value<int?> decisionMethod = const Value.absent(),
                Value<DateTime?> decidedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentProposalsCompanion(
                id: id,
                assignmentId: assignmentId,
                authorEmail: authorEmail,
                body: body,
                attachmentsJson: attachmentsJson,
                status: status,
                decidedBy: decidedBy,
                decisionMethod: decisionMethod,
                decidedAt: decidedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assignmentId,
                required String authorEmail,
                required String body,
                Value<String?> attachmentsJson = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> decidedBy = const Value.absent(),
                Value<int?> decisionMethod = const Value.absent(),
                Value<DateTime?> decidedAt = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AssignmentProposalsCompanion.insert(
                id: id,
                assignmentId: assignmentId,
                authorEmail: authorEmail,
                body: body,
                attachmentsJson: attachmentsJson,
                status: status,
                decidedBy: decidedBy,
                decisionMethod: decisionMethod,
                decidedAt: decidedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentProposalsTable, AssignmentProposal>(
                    table,
                  ),
                  $$AssignmentProposalsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({assignmentId = false, assignmentVotesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (assignmentVotesRefs) db.assignmentVotes,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (assignmentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.assignmentId,
                                    referencedTable:
                                        $$AssignmentProposalsTableReferences
                                            ._assignmentIdTable(db),
                                    referencedColumn:
                                        $$AssignmentProposalsTableReferences
                                            ._assignmentIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (assignmentVotesRefs)
                        await $_getPrefetchedDataByColumns<
                          AssignmentProposal,
                          $AssignmentProposalsTable,
                          AssignmentVote,
                          $AssignmentVotesTable
                        >(
                          currentTable: table,
                          referencedTable: $$AssignmentProposalsTableReferences
                              ._assignmentVotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssignmentProposalsTableReferences(
                                db,
                                table,
                                p0,
                              ).assignmentVotesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'proposal_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AssignmentProposalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentProposalsTable,
      AssignmentProposal,
      $$AssignmentProposalsTableFilterComposer,
      $$AssignmentProposalsTableOrderingComposer,
      $$AssignmentProposalsTableAnnotationComposer,
      $$AssignmentProposalsTableCreateCompanionBuilder,
      $$AssignmentProposalsTableUpdateCompanionBuilder,
      (AssignmentProposal, $$AssignmentProposalsTableReferences),
      AssignmentProposal,
      PrefetchHooks Function({bool assignmentId, bool assignmentVotesRefs})
    >;
typedef $$AssignmentVotesTableCreateCompanionBuilder =
    AssignmentVotesCompanion Function({
      required String proposalId,
      required String voterEmail,
      required int value,
      Value<String?> comment,
      required DateTime votedAt,
      Value<int> rowid,
    });
typedef $$AssignmentVotesTableUpdateCompanionBuilder =
    AssignmentVotesCompanion Function({
      Value<String> proposalId,
      Value<String> voterEmail,
      Value<int> value,
      Value<String?> comment,
      Value<DateTime> votedAt,
      Value<int> rowid,
    });

final class $$AssignmentVotesTableReferences
    extends
        BaseReferences<_$AppDatabase, $AssignmentVotesTable, AssignmentVote> {
  $$AssignmentVotesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentProposalsTable _proposalIdTable(_$AppDatabase db) => db
      .assignmentProposals
      .createAlias('assignment_votes__proposal_id__assignment_proposals__id');

  $$AssignmentProposalsTableProcessedTableManager get proposalId {
    final $_column = $_itemColumn<String>('proposal_id')!;

    final manager = $$AssignmentProposalsTableTableManager(
      $_db,
      $_db.assignmentProposals,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_proposalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssignmentVotesTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentVotesTable> {
  $$AssignmentVotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get voterEmail => $composableBuilder(
    column: $table.voterEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get votedAt => $composableBuilder(
    column: $table.votedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentProposalsTableFilterComposer get proposalId {
    final $$AssignmentProposalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.proposalId,
      referencedTable: $db.assignmentProposals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentProposalsTableFilterComposer(
            $db: $db,
            $table: $db.assignmentProposals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentVotesTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentVotesTable> {
  $$AssignmentVotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get voterEmail => $composableBuilder(
    column: $table.voterEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get votedAt => $composableBuilder(
    column: $table.votedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentProposalsTableOrderingComposer get proposalId {
    final $$AssignmentProposalsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.proposalId,
          referencedTable: $db.assignmentProposals,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentProposalsTableOrderingComposer(
                $db: $db,
                $table: $db.assignmentProposals,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$AssignmentVotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentVotesTable> {
  $$AssignmentVotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get voterEmail => $composableBuilder(
    column: $table.voterEmail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get comment =>
      $composableBuilder(column: $table.comment, builder: (column) => column);

  GeneratedColumn<DateTime> get votedAt =>
      $composableBuilder(column: $table.votedAt, builder: (column) => column);

  $$AssignmentProposalsTableAnnotationComposer get proposalId {
    final $$AssignmentProposalsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.proposalId,
          referencedTable: $db.assignmentProposals,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssignmentProposalsTableAnnotationComposer(
                $db: $db,
                $table: $db.assignmentProposals,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$AssignmentVotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentVotesTable,
          AssignmentVote,
          $$AssignmentVotesTableFilterComposer,
          $$AssignmentVotesTableOrderingComposer,
          $$AssignmentVotesTableAnnotationComposer,
          $$AssignmentVotesTableCreateCompanionBuilder,
          $$AssignmentVotesTableUpdateCompanionBuilder,
          (AssignmentVote, $$AssignmentVotesTableReferences),
          AssignmentVote,
          PrefetchHooks Function({bool proposalId})
        > {
  $$AssignmentVotesTableTableManager(
    _$AppDatabase db,
    $AssignmentVotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentVotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentVotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentVotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> proposalId = const Value.absent(),
                Value<String> voterEmail = const Value.absent(),
                Value<int> value = const Value.absent(),
                Value<String?> comment = const Value.absent(),
                Value<DateTime> votedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentVotesCompanion(
                proposalId: proposalId,
                voterEmail: voterEmail,
                value: value,
                comment: comment,
                votedAt: votedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String proposalId,
                required String voterEmail,
                required int value,
                Value<String?> comment = const Value.absent(),
                required DateTime votedAt,
                Value<int> rowid = const Value.absent(),
              }) => AssignmentVotesCompanion.insert(
                proposalId: proposalId,
                voterEmail: voterEmail,
                value: value,
                comment: comment,
                votedAt: votedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentVotesTable, AssignmentVote>(table),
                  $$AssignmentVotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({proposalId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (proposalId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.proposalId,
                                referencedTable:
                                    $$AssignmentVotesTableReferences
                                        ._proposalIdTable(db),
                                referencedColumn:
                                    $$AssignmentVotesTableReferences
                                        ._proposalIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssignmentVotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentVotesTable,
      AssignmentVote,
      $$AssignmentVotesTableFilterComposer,
      $$AssignmentVotesTableOrderingComposer,
      $$AssignmentVotesTableAnnotationComposer,
      $$AssignmentVotesTableCreateCompanionBuilder,
      $$AssignmentVotesTableUpdateCompanionBuilder,
      (AssignmentVote, $$AssignmentVotesTableReferences),
      AssignmentVote,
      PrefetchHooks Function({bool proposalId})
    >;
typedef $$AssignmentMeetingsTableCreateCompanionBuilder =
    AssignmentMeetingsCompanion Function({
      required String id,
      required String assignmentId,
      Value<String?> calendarEventId,
      required int subtype,
      Value<String?> dialIn,
      Value<String?> link,
      required DateTime startAt,
      Value<DateTime?> endAt,
      Value<String?> minutes,
      required String createdBy,
      Value<int> rowid,
    });
typedef $$AssignmentMeetingsTableUpdateCompanionBuilder =
    AssignmentMeetingsCompanion Function({
      Value<String> id,
      Value<String> assignmentId,
      Value<String?> calendarEventId,
      Value<int> subtype,
      Value<String?> dialIn,
      Value<String?> link,
      Value<DateTime> startAt,
      Value<DateTime?> endAt,
      Value<String?> minutes,
      Value<String> createdBy,
      Value<int> rowid,
    });

final class $$AssignmentMeetingsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AssignmentMeetingsTable,
          AssignmentMeeting
        > {
  $$AssignmentMeetingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentsTable _assignmentIdTable(_$AppDatabase db) => db
      .assignments
      .createAlias('assignment_meetings__assignment_id__assignments__id');

  $$AssignmentsTableProcessedTableManager get assignmentId {
    final $_column = $_itemColumn<String>('assignment_id')!;

    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssignmentMeetingsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentMeetingsTable> {
  $$AssignmentMeetingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get calendarEventId => $composableBuilder(
    column: $table.calendarEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtype => $composableBuilder(
    column: $table.subtype,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dialIn => $composableBuilder(
    column: $table.dialIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get link => $composableBuilder(
    column: $table.link,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentsTableFilterComposer get assignmentId {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentMeetingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentMeetingsTable> {
  $$AssignmentMeetingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get calendarEventId => $composableBuilder(
    column: $table.calendarEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtype => $composableBuilder(
    column: $table.subtype,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dialIn => $composableBuilder(
    column: $table.dialIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get link => $composableBuilder(
    column: $table.link,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentsTableOrderingComposer get assignmentId {
    final $$AssignmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentMeetingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentMeetingsTable> {
  $$AssignmentMeetingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get calendarEventId => $composableBuilder(
    column: $table.calendarEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtype =>
      $composableBuilder(column: $table.subtype, builder: (column) => column);

  GeneratedColumn<String> get dialIn =>
      $composableBuilder(column: $table.dialIn, builder: (column) => column);

  GeneratedColumn<String> get link =>
      $composableBuilder(column: $table.link, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<String> get minutes =>
      $composableBuilder(column: $table.minutes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  $$AssignmentsTableAnnotationComposer get assignmentId {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentMeetingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentMeetingsTable,
          AssignmentMeeting,
          $$AssignmentMeetingsTableFilterComposer,
          $$AssignmentMeetingsTableOrderingComposer,
          $$AssignmentMeetingsTableAnnotationComposer,
          $$AssignmentMeetingsTableCreateCompanionBuilder,
          $$AssignmentMeetingsTableUpdateCompanionBuilder,
          (AssignmentMeeting, $$AssignmentMeetingsTableReferences),
          AssignmentMeeting,
          PrefetchHooks Function({bool assignmentId})
        > {
  $$AssignmentMeetingsTableTableManager(
    _$AppDatabase db,
    $AssignmentMeetingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentMeetingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentMeetingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentMeetingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assignmentId = const Value.absent(),
                Value<String?> calendarEventId = const Value.absent(),
                Value<int> subtype = const Value.absent(),
                Value<String?> dialIn = const Value.absent(),
                Value<String?> link = const Value.absent(),
                Value<DateTime> startAt = const Value.absent(),
                Value<DateTime?> endAt = const Value.absent(),
                Value<String?> minutes = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentMeetingsCompanion(
                id: id,
                assignmentId: assignmentId,
                calendarEventId: calendarEventId,
                subtype: subtype,
                dialIn: dialIn,
                link: link,
                startAt: startAt,
                endAt: endAt,
                minutes: minutes,
                createdBy: createdBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assignmentId,
                Value<String?> calendarEventId = const Value.absent(),
                required int subtype,
                Value<String?> dialIn = const Value.absent(),
                Value<String?> link = const Value.absent(),
                required DateTime startAt,
                Value<DateTime?> endAt = const Value.absent(),
                Value<String?> minutes = const Value.absent(),
                required String createdBy,
                Value<int> rowid = const Value.absent(),
              }) => AssignmentMeetingsCompanion.insert(
                id: id,
                assignmentId: assignmentId,
                calendarEventId: calendarEventId,
                subtype: subtype,
                dialIn: dialIn,
                link: link,
                startAt: startAt,
                endAt: endAt,
                minutes: minutes,
                createdBy: createdBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentMeetingsTable, AssignmentMeeting>(
                    table,
                  ),
                  $$AssignmentMeetingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assignmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assignmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assignmentId,
                                referencedTable:
                                    $$AssignmentMeetingsTableReferences
                                        ._assignmentIdTable(db),
                                referencedColumn:
                                    $$AssignmentMeetingsTableReferences
                                        ._assignmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssignmentMeetingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentMeetingsTable,
      AssignmentMeeting,
      $$AssignmentMeetingsTableFilterComposer,
      $$AssignmentMeetingsTableOrderingComposer,
      $$AssignmentMeetingsTableAnnotationComposer,
      $$AssignmentMeetingsTableCreateCompanionBuilder,
      $$AssignmentMeetingsTableUpdateCompanionBuilder,
      (AssignmentMeeting, $$AssignmentMeetingsTableReferences),
      AssignmentMeeting,
      PrefetchHooks Function({bool assignmentId})
    >;
typedef $$AssignmentReportsTableCreateCompanionBuilder =
    AssignmentReportsCompanion Function({
      required String assignmentId,
      required String consideredJson,
      required String acceptedJson,
      required String rejectedJson,
      required String doneJson,
      Value<String?> notes,
      required DateTime compiledAt,
      required String compiledBy,
      Value<String?> exportPath,
      Value<int> rowid,
    });
typedef $$AssignmentReportsTableUpdateCompanionBuilder =
    AssignmentReportsCompanion Function({
      Value<String> assignmentId,
      Value<String> consideredJson,
      Value<String> acceptedJson,
      Value<String> rejectedJson,
      Value<String> doneJson,
      Value<String?> notes,
      Value<DateTime> compiledAt,
      Value<String> compiledBy,
      Value<String?> exportPath,
      Value<int> rowid,
    });

final class $$AssignmentReportsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AssignmentReportsTable,
          AssignmentReport
        > {
  $$AssignmentReportsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssignmentsTable _assignmentIdTable(_$AppDatabase db) => db
      .assignments
      .createAlias('assignment_reports__assignment_id__assignments__id');

  $$AssignmentsTableProcessedTableManager get assignmentId {
    final $_column = $_itemColumn<String>('assignment_id')!;

    final manager = $$AssignmentsTableTableManager(
      $_db,
      $_db.assignments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assignmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssignmentReportsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentReportsTable> {
  $$AssignmentReportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get consideredJson => $composableBuilder(
    column: $table.consideredJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acceptedJson => $composableBuilder(
    column: $table.acceptedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectedJson => $composableBuilder(
    column: $table.rejectedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doneJson => $composableBuilder(
    column: $table.doneJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get compiledAt => $composableBuilder(
    column: $table.compiledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get compiledBy => $composableBuilder(
    column: $table.compiledBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exportPath => $composableBuilder(
    column: $table.exportPath,
    builder: (column) => ColumnFilters(column),
  );

  $$AssignmentsTableFilterComposer get assignmentId {
    final $$AssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentReportsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentReportsTable> {
  $$AssignmentReportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get consideredJson => $composableBuilder(
    column: $table.consideredJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acceptedJson => $composableBuilder(
    column: $table.acceptedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectedJson => $composableBuilder(
    column: $table.rejectedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doneJson => $composableBuilder(
    column: $table.doneJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get compiledAt => $composableBuilder(
    column: $table.compiledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get compiledBy => $composableBuilder(
    column: $table.compiledBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exportPath => $composableBuilder(
    column: $table.exportPath,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssignmentsTableOrderingComposer get assignmentId {
    final $$AssignmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentReportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentReportsTable> {
  $$AssignmentReportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get consideredJson => $composableBuilder(
    column: $table.consideredJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acceptedJson => $composableBuilder(
    column: $table.acceptedJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rejectedJson => $composableBuilder(
    column: $table.rejectedJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get doneJson =>
      $composableBuilder(column: $table.doneJson, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get compiledAt => $composableBuilder(
    column: $table.compiledAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get compiledBy => $composableBuilder(
    column: $table.compiledBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exportPath => $composableBuilder(
    column: $table.exportPath,
    builder: (column) => column,
  );

  $$AssignmentsTableAnnotationComposer get assignmentId {
    final $$AssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assignmentId,
      referencedTable: $db.assignments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssignmentReportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssignmentReportsTable,
          AssignmentReport,
          $$AssignmentReportsTableFilterComposer,
          $$AssignmentReportsTableOrderingComposer,
          $$AssignmentReportsTableAnnotationComposer,
          $$AssignmentReportsTableCreateCompanionBuilder,
          $$AssignmentReportsTableUpdateCompanionBuilder,
          (AssignmentReport, $$AssignmentReportsTableReferences),
          AssignmentReport,
          PrefetchHooks Function({bool assignmentId})
        > {
  $$AssignmentReportsTableTableManager(
    _$AppDatabase db,
    $AssignmentReportsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentReportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentReportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentReportsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assignmentId = const Value.absent(),
                Value<String> consideredJson = const Value.absent(),
                Value<String> acceptedJson = const Value.absent(),
                Value<String> rejectedJson = const Value.absent(),
                Value<String> doneJson = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> compiledAt = const Value.absent(),
                Value<String> compiledBy = const Value.absent(),
                Value<String?> exportPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentReportsCompanion(
                assignmentId: assignmentId,
                consideredJson: consideredJson,
                acceptedJson: acceptedJson,
                rejectedJson: rejectedJson,
                doneJson: doneJson,
                notes: notes,
                compiledAt: compiledAt,
                compiledBy: compiledBy,
                exportPath: exportPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assignmentId,
                required String consideredJson,
                required String acceptedJson,
                required String rejectedJson,
                required String doneJson,
                Value<String?> notes = const Value.absent(),
                required DateTime compiledAt,
                required String compiledBy,
                Value<String?> exportPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssignmentReportsCompanion.insert(
                assignmentId: assignmentId,
                consideredJson: consideredJson,
                acceptedJson: acceptedJson,
                rejectedJson: rejectedJson,
                doneJson: doneJson,
                notes: notes,
                compiledAt: compiledAt,
                compiledBy: compiledBy,
                exportPath: exportPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssignmentReportsTable, AssignmentReport>(table),
                  $$AssignmentReportsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assignmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assignmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assignmentId,
                                referencedTable:
                                    $$AssignmentReportsTableReferences
                                        ._assignmentIdTable(db),
                                referencedColumn:
                                    $$AssignmentReportsTableReferences
                                        ._assignmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssignmentReportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssignmentReportsTable,
      AssignmentReport,
      $$AssignmentReportsTableFilterComposer,
      $$AssignmentReportsTableOrderingComposer,
      $$AssignmentReportsTableAnnotationComposer,
      $$AssignmentReportsTableCreateCompanionBuilder,
      $$AssignmentReportsTableUpdateCompanionBuilder,
      (AssignmentReport, $$AssignmentReportsTableReferences),
      AssignmentReport,
      PrefetchHooks Function({bool assignmentId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$EmailsTableTableManager get emails =>
      $$EmailsTableTableManager(_db, _db.emails);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(_db, _db.calendarEvents);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$AuditLogTableTableManager get auditLog =>
      $$AuditLogTableTableManager(_db, _db.auditLog);
  $$SignaturesTableTableManager get signatures =>
      $$SignaturesTableTableManager(_db, _db.signatures);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$AssignmentsTableTableManager get assignments =>
      $$AssignmentsTableTableManager(_db, _db.assignments);
  $$AssignmentParticipantsTableTableManager get assignmentParticipants =>
      $$AssignmentParticipantsTableTableManager(
        _db,
        _db.assignmentParticipants,
      );
  $$AssignmentEventsTableTableManager get assignmentEvents =>
      $$AssignmentEventsTableTableManager(_db, _db.assignmentEvents);
  $$AssignmentProposalsTableTableManager get assignmentProposals =>
      $$AssignmentProposalsTableTableManager(_db, _db.assignmentProposals);
  $$AssignmentVotesTableTableManager get assignmentVotes =>
      $$AssignmentVotesTableTableManager(_db, _db.assignmentVotes);
  $$AssignmentMeetingsTableTableManager get assignmentMeetings =>
      $$AssignmentMeetingsTableTableManager(_db, _db.assignmentMeetings);
  $$AssignmentReportsTableTableManager get assignmentReports =>
      $$AssignmentReportsTableTableManager(_db, _db.assignmentReports);
}

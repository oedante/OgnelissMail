// lib/services/archive/archive_db.dart
// База архива Ogneliss (.ogna), 1.7.3 — docs/plan/ARCHIVE_IDEA.md.
//
// Отдельный файл SQLite, зашифрованный своим ключом (SQLite3 Multiple
// Ciphers, как основная база). Схема — открытая и простая, без генерации
// кода drift (запросы — SQL): архив можно прочитать и без приложения, зная
// ключ.
//
//  · accounts    — ящики, из которых пришли данные (в одном архиве — данные
//                  нескольких ящиков, решение владельца);
//  · folders     — папки как в ящике: путь «Входящие/Проекты/2024» и
//                  родитель — структура папок сохраняется;
//  · messages    — письма целиком: адресаты, тело (HTML и текст), отметки;
//  · attachments — вложения (сами файлы — BLOB), в том числе картинки в
//                  тексте (cid:);
//  · messages_fts — поиск (FTS5): тема, люди, текст, имена файлов;
//  · events, tasks, contacts — встречи, задачи и свои контакты: основные
//                  поля для показа и строка базы приложения целиком (JSON) —
//                  чтобы ничего не потерять и позже уметь вернуть.

import 'dart:convert';

import 'package:drift/drift.dart';

abstract final class ArchiveSchema {
  static const version = 1;

  static const create = <String>[
    'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)',
    'CREATE TABLE IF NOT EXISTS accounts ('
        'id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT, type TEXT, color INTEGER)',
    'CREATE TABLE IF NOT EXISTS folders ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, '
        'path TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'parent_id INTEGER REFERENCES folders(id), '
        'type TEXT NOT NULL DEFAULT \'custom\', '
        'UNIQUE(account_id, path))',
    'CREATE TABLE IF NOT EXISTS messages ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, '
        'folder_id INTEGER NOT NULL REFERENCES folders(id), '
        'source_id TEXT, '
        'message_id TEXT, '
        'conversation_id TEXT, '
        'subject TEXT NOT NULL DEFAULT \'\', '
        'from_name TEXT, '
        'from_email TEXT NOT NULL DEFAULT \'\', '
        'to_json TEXT, cc_json TEXT, bcc_json TEXT, reply_to_json TEXT, '
        'date INTEGER NOT NULL, '
        'is_read INTEGER NOT NULL DEFAULT 1, '
        'is_flagged INTEGER NOT NULL DEFAULT 0, '
        'importance INTEGER NOT NULL DEFAULT 1, '
        'has_attachments INTEGER NOT NULL DEFAULT 0, '
        'body_html TEXT, body_text TEXT, preview TEXT, '
        'size INTEGER, '
        'archived_at INTEGER NOT NULL)',
    'CREATE INDEX IF NOT EXISTS messages_folder_date ON messages(folder_id, date DESC)',
    'CREATE INDEX IF NOT EXISTS messages_source ON messages(account_id, message_id)',
    'CREATE TABLE IF NOT EXISTS attachments ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE, '
        'name TEXT NOT NULL, mime TEXT, size INTEGER NOT NULL DEFAULT 0, '
        'content_id TEXT, is_inline INTEGER NOT NULL DEFAULT 0, '
        'data BLOB)',
    'CREATE INDEX IF NOT EXISTS attachments_message ON attachments(message_id)',
    'CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5('
        "subject, people, body, files, tokenize = 'unicode61 remove_diacritics 2')",
    'CREATE TABLE IF NOT EXISTS events ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, source_id TEXT NOT NULL, '
        'title TEXT NOT NULL DEFAULT \'\', location TEXT, '
        'start INTEGER NOT NULL, end INTEGER NOT NULL, all_day INTEGER NOT NULL DEFAULT 0, '
        'organizer TEXT, data_json TEXT, archived_at INTEGER NOT NULL, '
        'UNIQUE(account_id, source_id))',
    'CREATE INDEX IF NOT EXISTS events_start ON events(start DESC)',
    'CREATE TABLE IF NOT EXISTS tasks ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, source_id TEXT NOT NULL, '
        'title TEXT NOT NULL DEFAULT \'\', due INTEGER, completed_at INTEGER, '
        'data_json TEXT, archived_at INTEGER NOT NULL, '
        'UNIQUE(account_id, source_id))',
    'CREATE TABLE IF NOT EXISTS contacts ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, source_id TEXT NOT NULL, '
        'name TEXT NOT NULL DEFAULT \'\', email TEXT, company TEXT, phone TEXT, '
        'data_json TEXT, archived_at INTEGER NOT NULL, '
        'UNIQUE(account_id, source_id))',
    // Настройки приложения (замечание владельца 25.10.2026): ящики,
    // настройки, подписи, заметки — снимок для быстрого восстановления на
    // устройстве. data — JSON резервной копии (BackupService.collect),
    // сжатый gzip.
    'CREATE TABLE IF NOT EXISTS app_settings ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'created INTEGER NOT NULL, app TEXT, device TEXT, '
        'accounts INTEGER NOT NULL DEFAULT 0, secrets INTEGER NOT NULL DEFAULT 0, '
        'data BLOB NOT NULL)',
  ];
}

/// Снимок настроек приложения в архиве.
class ArchiveSettingsSnapshot {
  final int id;
  final DateTime created;
  final String app;
  final String device;
  final int accounts;
  final bool secrets;
  const ArchiveSettingsSnapshot(this.id, this.created, this.app, this.device, this.accounts, this.secrets);
}

/// Адресат письма в архиве.
typedef ArchivePerson = ({String name, String email});

class ArchiveAccountInfo {
  final String id;
  final String email;
  final String name;

  /// Писем этого ящика в архиве.
  final int messages;
  const ArchiveAccountInfo(this.id, this.email, this.name, {this.messages = 0});
  String get label => name.trim().isNotEmpty ? name.trim() : email;
}

/// Итог объединения архива с копией (.ogna с другого устройства).
class ArchiveMergeReport {
  /// Добавлено писем; уже были в архиве (не повторялись).
  final int messages;
  final int skipped;
  final int events;
  final int tasks;
  final int contacts;

  /// Снимков настроек приложения добавлено.
  final int settings;

  const ArchiveMergeReport({
    this.messages = 0,
    this.skipped = 0,
    this.events = 0,
    this.tasks = 0,
    this.contacts = 0,
    this.settings = 0,
  });

  int get added => messages + events + tasks + contacts;
}

class ArchiveFolder {
  final int id;
  final String accountId;
  final String path;
  final String name;
  final int? parentId;
  final String type;
  final int count;
  const ArchiveFolder({
    required this.id,
    required this.accountId,
    required this.path,
    required this.name,
    required this.parentId,
    required this.type,
    required this.count,
  });
}

/// Строка списка писем.
class ArchiveMessageHead {
  final int id;
  final int folderId;
  final String accountId;
  final String subject;
  final String fromName;
  final String fromEmail;
  final DateTime date;
  final bool isRead;
  final bool hasAttachments;
  final String preview;

  /// Путь папки (в результатах поиска).
  final String folderPath;

  const ArchiveMessageHead({
    required this.id,
    required this.folderId,
    required this.accountId,
    required this.subject,
    required this.fromName,
    required this.fromEmail,
    required this.date,
    required this.isRead,
    required this.hasAttachments,
    required this.preview,
    this.folderPath = '',
  });

  String get fromLabel => fromName.trim().isNotEmpty ? fromName.trim() : fromEmail;

  static ArchiveMessageHead fromRow(QueryRow r) => ArchiveMessageHead(
        id: r.read<int>('id'),
        folderId: r.read<int>('folder_id'),
        accountId: r.read<String>('account_id'),
        subject: r.read<String>('subject'),
        fromName: r.readNullable<String>('from_name') ?? '',
        fromEmail: r.read<String>('from_email'),
        date: DateTime.fromMillisecondsSinceEpoch(r.read<int>('date')),
        isRead: r.read<int>('is_read') != 0,
        hasAttachments: r.read<int>('has_attachments') != 0,
        preview: r.readNullable<String>('preview') ?? '',
        folderPath: r.data.containsKey('folder_path') ? (r.readNullable<String>('folder_path') ?? '') : '',
      );
}

class ArchiveAttachmentInfo {
  final int id;
  final String name;
  final String mime;
  final int size;
  final String? contentId;
  final bool isInline;
  const ArchiveAttachmentInfo(this.id, this.name, this.mime, this.size, this.contentId, this.isInline);
}

/// Письмо целиком.
class ArchiveMessage {
  final ArchiveMessageHead head;
  final List<ArchivePerson> to;
  final List<ArchivePerson> cc;
  final List<ArchivePerson> bcc;
  final String? messageId;
  final String? bodyHtml;
  final String? bodyText;
  final bool isFlagged;
  final int importance;
  final DateTime archivedAt;
  final List<ArchiveAttachmentInfo> attachments;
  const ArchiveMessage({
    required this.head,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.messageId,
    required this.bodyHtml,
    required this.bodyText,
    required this.isFlagged,
    required this.importance,
    required this.archivedAt,
    required this.attachments,
  });
}

/// Вложение для записи в архив.
class ArchiveAttachmentInput {
  final String name;
  final String mime;
  final String? contentId;
  final bool isInline;
  final Uint8List bytes;
  const ArchiveAttachmentInput({
    required this.name,
    required this.mime,
    required this.bytes,
    this.contentId,
    this.isInline = false,
  });
}

/// Письмо для записи в архив.
class ArchiveMessageInput {
  final String accountId;

  /// Папки от корня ящика до папки письма: (название, тип).
  final List<({String name, String type})> folderChain;
  final String sourceId;
  final String? messageId;
  final String? conversationId;
  final String subject;
  final String fromName;
  final String fromEmail;
  final List<ArchivePerson> to;
  final List<ArchivePerson> cc;
  final List<ArchivePerson> bcc;
  final List<ArchivePerson> replyTo;
  final DateTime date;
  final bool isRead;
  final bool isFlagged;
  final int importance;
  final String? bodyHtml;
  final String? bodyText;
  final String? preview;
  final int? size;
  final List<ArchiveAttachmentInput> attachments;

  /// Текст для поиска (тело без разметки).
  final String searchText;

  const ArchiveMessageInput({
    required this.accountId,
    required this.folderChain,
    required this.sourceId,
    required this.subject,
    required this.fromName,
    required this.fromEmail,
    required this.date,
    this.messageId,
    this.conversationId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.replyTo = const [],
    this.isRead = true,
    this.isFlagged = false,
    this.importance = 1,
    this.bodyHtml,
    this.bodyText,
    this.preview,
    this.size,
    this.attachments = const [],
    this.searchText = '',
  });
}

class ArchiveStats {
  final int messages;
  final int attachments;
  final int attachmentBytes;
  final int events;
  final int tasks;
  final int contacts;
  final DateTime? oldest;
  final DateTime? newest;
  const ArchiveStats({
    this.messages = 0,
    this.attachments = 0,
    this.attachmentBytes = 0,
    this.events = 0,
    this.tasks = 0,
    this.contacts = 0,
    this.oldest,
    this.newest,
  });
}

/// Встреча, задача или контакт в архиве — для списка.
class ArchiveItem {
  final int id;
  final String accountId;
  final String title;
  final String subtitle;
  final DateTime? at;
  final String? dataJson;
  const ArchiveItem(this.id, this.accountId, this.title, this.subtitle, this.at, this.dataJson);
}

class ArchiveDb extends GeneratedDatabase {
  ArchiveDb(super.e);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => ArchiveSchema.version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final s in ArchiveSchema.create) {
            await customStatement(s);
          }
          await setMeta('format', 'ogna');
          await setMeta('schema', '${ArchiveSchema.version}');
          await setMeta('created', '${DateTime.now().millisecondsSinceEpoch}');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ── служебное ──

  Future<void> setMeta(String key, String value) => customStatement(
      'INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value]);

  Future<String?> meta(String key) async {
    final r = await customSelect('SELECT value FROM meta WHERE key = ?', variables: [Variable.withString(key)])
        .getSingleOrNull();
    return r?.readNullable<String>('value');
  }

  /// База открывается этим ключом (иначе SQLite отвечает «not a database»).
  Future<void> check() => customSelect('SELECT count(*) AS n FROM sqlite_master').getSingle();

  // ── ящики и папки ──

  Future<void> upsertAccount(String id, String email, String name, String type, int color) => customStatement(
      'INSERT INTO accounts(id, email, name, type, color) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET email = excluded.email, name = excluded.name, '
      'type = excluded.type, color = excluded.color',
      [id, email, name, type, color]);

  /// Ящик архива для ящика приложения: тот же id — он; иначе ящик с тем же
  /// адресом (архив подключён или объединён с копией с другого устройства,
  /// где у ящика другой id) — его id, данные одного ящика не раздваиваются
  /// на две ветки; иначе — новый ящик архива с этим id.
  Future<String> resolveAccount(String id, String email, String name, String type, int color) async {
    final same = await customSelect('SELECT id FROM accounts WHERE id = ?', variables: [Variable.withString(id)])
        .getSingleOrNull();
    final addr = email.trim();
    if (same == null && addr.isNotEmpty) {
      final byEmail = await customSelect('SELECT id FROM accounts WHERE lower(email) = lower(?) ORDER BY id LIMIT 1',
          variables: [Variable.withString(addr)]).getSingleOrNull();
      if (byEmail != null) {
        final existing = byEmail.read<String>('id');
        await customStatement(
            'UPDATE accounts SET name = ?, type = ?, color = ? WHERE id = ?', [name, type, color, existing]);
        return existing;
      }
    }
    await upsertAccount(id, email, name, type, color);
    return id;
  }

  Future<List<ArchiveAccountInfo>> accounts() async {
    final rows = await customSelect('SELECT a.id, a.email, a.name, '
            '(SELECT count(*) FROM messages m WHERE m.account_id = a.id) AS n FROM accounts a ORDER BY a.email')
        .get();
    return [
      for (final r in rows)
        ArchiveAccountInfo(r.read<String>('id'), r.read<String>('email'), r.readNullable<String>('name') ?? '',
            messages: r.read<int>('n')),
    ];
  }

  /// Папка по цепочке от корня (создаётся вместе с родителями).
  Future<int> ensureFolder(String accountId, List<({String name, String type})> chain) async {
    int? parent;
    final path = <String>[];
    var id = 0;
    for (final (i, f) in chain.indexed) {
      // «/» в названии папки — делитель пути: заменяем похожим знаком.
      final name = f.name.replaceAll('/', '∕').trim().isEmpty ? '—' : f.name.replaceAll('/', '∕');
      path.add(name);
      final p = path.join('/');
      final row = await customSelect('SELECT id FROM folders WHERE account_id = ? AND path = ?',
          variables: [Variable.withString(accountId), Variable.withString(p)]).getSingleOrNull();
      if (row != null) {
        id = row.read<int>('id');
      } else {
        id = await customInsert(
          'INSERT INTO folders(account_id, path, name, parent_id, type) VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(accountId),
            Variable.withString(p),
            Variable.withString(name),
            Variable<int>(parent),
            Variable.withString(i == chain.length - 1 ? f.type : (f.type == 'custom' ? 'custom' : f.type)),
          ],
        );
      }
      parent = id;
    }
    return id;
  }

  Future<List<ArchiveFolder>> folders() async {
    final rows = await customSelect(
      'SELECT f.id, f.account_id, f.path, f.name, f.parent_id, f.type, '
      '(SELECT count(*) FROM messages m WHERE m.folder_id = f.id) AS n '
      'FROM folders f ORDER BY f.account_id, f.path',
    ).get();
    return [
      for (final r in rows)
        ArchiveFolder(
          id: r.read<int>('id'),
          accountId: r.read<String>('account_id'),
          path: r.read<String>('path'),
          name: r.read<String>('name'),
          parentId: r.readNullable<int>('parent_id'),
          type: r.read<String>('type'),
          count: r.read<int>('n'),
        ),
    ];
  }

  // ── письма ──

  static String _people(List<ArchivePerson> l) =>
      jsonEncode([for (final p in l) {'name': p.name, 'email': p.email}]);

  static List<ArchivePerson> _peopleOf(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).cast<Map<String, dynamic>>())
          (name: (m['name'] as String?) ?? '', email: (m['email'] as String?) ?? ''),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Письмо уже в архиве (та же папка и тот же Message-ID или id в ящике).
  Future<bool> hasMessage(String accountId, int folderId, String sourceId, String? messageId) async {
    final mid = (messageId ?? '').trim();
    final r = await customSelect(
      'SELECT id FROM messages WHERE account_id = ? AND folder_id = ? AND '
      '(source_id = ? OR (? <> \'\' AND message_id = ?)) LIMIT 1',
      variables: [
        Variable.withString(accountId),
        Variable.withInt(folderId),
        Variable.withString(sourceId),
        Variable.withString(mid),
        Variable.withString(mid),
      ],
    ).getSingleOrNull();
    return r != null;
  }

  /// Записать письмо с вложениями и поисковой строкой (одной транзакцией).
  /// Возвращает id в архиве; письмо уже было — его id без повторной записи.
  Future<int> addMessage(ArchiveMessageInput m) => transaction(() async {
        final folderId = await ensureFolder(m.accountId, m.folderChain);
        final mid = (m.messageId ?? '').trim();
        final existing = await customSelect(
          'SELECT id FROM messages WHERE account_id = ? AND folder_id = ? AND '
          '(source_id = ? OR (? <> \'\' AND message_id = ?)) LIMIT 1',
          variables: [
            Variable.withString(m.accountId),
            Variable.withInt(folderId),
            Variable.withString(m.sourceId),
            Variable.withString(mid),
            Variable.withString(mid),
          ],
        ).getSingleOrNull();
        if (existing != null) return existing.read<int>('id');
        final id = await customInsert(
          'INSERT INTO messages(account_id, folder_id, source_id, message_id, conversation_id, subject, '
          'from_name, from_email, to_json, cc_json, bcc_json, reply_to_json, date, is_read, is_flagged, '
          'importance, has_attachments, body_html, body_text, preview, size, archived_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(m.accountId),
            Variable.withInt(folderId),
            Variable.withString(m.sourceId),
            Variable<String>(mid.isEmpty ? null : mid),
            Variable<String>(m.conversationId),
            Variable.withString(m.subject),
            Variable.withString(m.fromName),
            Variable.withString(m.fromEmail),
            Variable.withString(_people(m.to)),
            Variable.withString(_people(m.cc)),
            Variable.withString(_people(m.bcc)),
            Variable.withString(_people(m.replyTo)),
            Variable.withInt(m.date.millisecondsSinceEpoch),
            Variable.withInt(m.isRead ? 1 : 0),
            Variable.withInt(m.isFlagged ? 1 : 0),
            Variable.withInt(m.importance),
            Variable.withInt(m.attachments.any((a) => !a.isInline) ? 1 : 0),
            Variable<String>(m.bodyHtml),
            Variable<String>(m.bodyText),
            Variable<String>(m.preview),
            Variable<int>(m.size),
            Variable.withInt(DateTime.now().millisecondsSinceEpoch),
          ],
        );
        for (final a in m.attachments) {
          await customInsert(
            'INSERT INTO attachments(message_id, name, mime, size, content_id, is_inline, data) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            variables: [
              Variable.withInt(id),
              Variable.withString(a.name),
              Variable.withString(a.mime),
              Variable.withInt(a.bytes.length),
              Variable<String>(a.contentId),
              Variable.withInt(a.isInline ? 1 : 0),
              Variable.withBlob(a.bytes),
            ],
          );
        }
        final people = [
          '${m.fromName} ${m.fromEmail}',
          for (final p in [...m.to, ...m.cc]) '${p.name} ${p.email}',
        ].join(' ');
        await customInsert(
          'INSERT INTO messages_fts(rowid, subject, people, body, files) VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(id),
            Variable.withString(m.subject),
            Variable.withString(people),
            Variable.withString(m.searchText),
            Variable.withString([for (final a in m.attachments) if (!a.isInline) a.name].join(' ')),
          ],
        );
        return id;
      });

  static const _headCols = 'm.id, m.folder_id, m.account_id, m.subject, m.from_name, m.from_email, '
      'm.date, m.is_read, m.has_attachments, m.preview';

  Future<List<ArchiveMessageHead>> messages(int folderId, {int limit = 100, int offset = 0}) async {
    final rows = await customSelect(
      'SELECT $_headCols FROM messages m WHERE m.folder_id = ? ORDER BY m.date DESC LIMIT ? OFFSET ?',
      variables: [Variable.withInt(folderId), Variable.withInt(limit), Variable.withInt(offset)],
    ).get();
    return [for (final r in rows) ArchiveMessageHead.fromRow(r)];
  }

  /// Запрос FTS5: каждое слово — префиксом, в кавычках (знаки в словах не
  /// ломают разбор).
  static String ftsQuery(String q) => q
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll('"', ''))
      .where((w) => w.isNotEmpty)
      .map((w) => '"$w"*')
      .join(' ');

  /// Поиск по архиву: новые сверху.
  Future<List<ArchiveMessageHead>> search(String query, {int limit = 200}) async {
    final q = ftsQuery(query);
    if (q.isEmpty) return const [];
    final rows = await customSelect(
      'SELECT $_headCols, f.path AS folder_path FROM messages_fts '
      'JOIN messages m ON m.id = messages_fts.rowid '
      'JOIN folders f ON f.id = m.folder_id '
      'WHERE messages_fts MATCH ? ORDER BY m.date DESC LIMIT ?',
      variables: [Variable.withString(q), Variable.withInt(limit)],
    ).get();
    return [for (final r in rows) ArchiveMessageHead.fromRow(r)];
  }

  /// Сколько писем нашлось (для строки «В архиве: N» в поиске почты).
  Future<int> searchCount(String query) async {
    final q = ftsQuery(query);
    if (q.isEmpty) return 0;
    final r = await customSelect('SELECT count(*) AS n FROM messages_fts WHERE messages_fts MATCH ?',
        variables: [Variable.withString(q)]).getSingle();
    return r.read<int>('n');
  }

  Future<ArchiveMessage?> message(int id) async {
    final r = await customSelect(
      'SELECT m.*, f.path AS folder_path FROM messages m JOIN folders f ON f.id = m.folder_id WHERE m.id = ?',
      variables: [Variable.withInt(id)],
    ).getSingleOrNull();
    if (r == null) return null;
    final atts = await customSelect(
      'SELECT id, name, mime, size, content_id, is_inline FROM attachments WHERE message_id = ? ORDER BY id',
      variables: [Variable.withInt(id)],
    ).get();
    return ArchiveMessage(
      head: ArchiveMessageHead.fromRow(r),
      to: _peopleOf(r.readNullable<String>('to_json')),
      cc: _peopleOf(r.readNullable<String>('cc_json')),
      bcc: _peopleOf(r.readNullable<String>('bcc_json')),
      messageId: r.readNullable<String>('message_id'),
      bodyHtml: r.readNullable<String>('body_html'),
      bodyText: r.readNullable<String>('body_text'),
      isFlagged: r.read<int>('is_flagged') != 0,
      importance: r.read<int>('importance'),
      archivedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('archived_at')),
      attachments: [
        for (final a in atts)
          ArchiveAttachmentInfo(
            a.read<int>('id'),
            a.read<String>('name'),
            a.readNullable<String>('mime') ?? '',
            a.read<int>('size'),
            a.readNullable<String>('content_id'),
            a.read<int>('is_inline') != 0,
          ),
      ],
    );
  }

  Future<Uint8List?> attachmentData(int attachmentId) async {
    final r = await customSelect('SELECT data FROM attachments WHERE id = ?',
        variables: [Variable.withInt(attachmentId)]).getSingleOrNull();
    return r?.readNullable<Uint8List>('data');
  }

  Future<void> setRead(int id, bool read) =>
      customStatement('UPDATE messages SET is_read = ? WHERE id = ?', [read ? 1 : 0, id]);

  /// Удалить письмо из архива (вместе с вложениями и поисковой строкой).
  Future<void> deleteMessage(int id) => transaction(() async {
        await customStatement('DELETE FROM messages_fts WHERE rowid = ?', [id]);
        await customStatement('DELETE FROM attachments WHERE message_id = ?', [id]);
        await customStatement('DELETE FROM messages WHERE id = ?', [id]);
      });

  // ── встречи, задачи, контакты ──

  Future<void> upsertEvent({
    required String accountId,
    required String sourceId,
    required String title,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    String? location,
    String? organizer,
    String? dataJson,
  }) =>
      customStatement(
        'INSERT INTO events(account_id, source_id, title, location, start, end, all_day, organizer, data_json, archived_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(account_id, source_id) DO UPDATE SET title = excluded.title, location = excluded.location, '
        'start = excluded.start, end = excluded.end, all_day = excluded.all_day, organizer = excluded.organizer, '
        'data_json = excluded.data_json',
        [
          accountId,
          sourceId,
          title,
          location,
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
          allDay ? 1 : 0,
          organizer,
          dataJson,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

  Future<void> upsertTask({
    required String accountId,
    required String sourceId,
    required String title,
    DateTime? due,
    DateTime? completedAt,
    String? dataJson,
  }) =>
      customStatement(
        'INSERT INTO tasks(account_id, source_id, title, due, completed_at, data_json, archived_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(account_id, source_id) DO UPDATE SET title = excluded.title, due = excluded.due, '
        'completed_at = excluded.completed_at, data_json = excluded.data_json',
        [
          accountId,
          sourceId,
          title,
          due?.millisecondsSinceEpoch,
          completedAt?.millisecondsSinceEpoch,
          dataJson,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

  Future<void> upsertContact({
    required String accountId,
    required String sourceId,
    required String name,
    String? email,
    String? company,
    String? phone,
    String? dataJson,
  }) =>
      customStatement(
        'INSERT INTO contacts(account_id, source_id, name, email, company, phone, data_json, archived_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(account_id, source_id) DO UPDATE SET name = excluded.name, email = excluded.email, '
        'company = excluded.company, phone = excluded.phone, data_json = excluded.data_json, '
        'archived_at = excluded.archived_at',
        [accountId, sourceId, name, email, company, phone, dataJson, DateTime.now().millisecondsSinceEpoch],
      );

  Future<List<ArchiveItem>> events({int limit = 500}) async {
    final rows = await customSelect(
      'SELECT id, account_id, title, location, start, data_json FROM events ORDER BY start DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    return [
      for (final r in rows)
        ArchiveItem(
          r.read<int>('id'),
          r.read<String>('account_id'),
          r.read<String>('title'),
          r.readNullable<String>('location') ?? '',
          DateTime.fromMillisecondsSinceEpoch(r.read<int>('start')),
          r.readNullable<String>('data_json'),
        ),
    ];
  }

  Future<List<ArchiveItem>> tasks({int limit = 500}) async {
    final rows = await customSelect(
      'SELECT id, account_id, title, due, completed_at, data_json FROM tasks '
      'ORDER BY coalesce(completed_at, due, archived_at) DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    return [
      for (final r in rows)
        ArchiveItem(
          r.read<int>('id'),
          r.read<String>('account_id'),
          r.read<String>('title'),
          '',
          r.readNullable<int>('completed_at') == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(r.read<int>('completed_at')),
          r.readNullable<String>('data_json'),
        ),
    ];
  }

  Future<List<ArchiveItem>> contacts({int limit = 2000}) async {
    final rows = await customSelect(
      'SELECT id, account_id, name, email, company, data_json FROM contacts ORDER BY name LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    return [
      for (final r in rows)
        ArchiveItem(
          r.read<int>('id'),
          r.read<String>('account_id'),
          r.read<String>('name'),
          [r.readNullable<String>('email') ?? '', r.readNullable<String>('company') ?? '']
              .where((s) => s.isNotEmpty)
              .join(' · '),
          null,
          r.readNullable<String>('data_json'),
        ),
    ];
  }

  // ── настройки приложения ──

  /// Сколько снимков настроек хранить (старые удаляются).
  static const keepSettings = 5;

  Future<void> saveSettings({
    required Uint8List data,
    required String app,
    required String device,
    required int accounts,
    required bool secrets,
  }) =>
      transaction(() async {
        await customInsert(
          'INSERT INTO app_settings(created, app, device, accounts, secrets, data) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(DateTime.now().millisecondsSinceEpoch),
            Variable.withString(app),
            Variable.withString(device),
            Variable.withInt(accounts),
            Variable.withInt(secrets ? 1 : 0),
            Variable.withBlob(data),
          ],
        );
        await customStatement(
          'DELETE FROM app_settings WHERE id NOT IN (SELECT id FROM app_settings ORDER BY created DESC LIMIT ?)',
          [keepSettings],
        );
      });

  Future<List<ArchiveSettingsSnapshot>> settingsSnapshots() async {
    final rows = await customSelect(
            'SELECT id, created, app, device, accounts, secrets FROM app_settings ORDER BY created DESC')
        .get();
    return [
      for (final r in rows)
        ArchiveSettingsSnapshot(
          r.read<int>('id'),
          DateTime.fromMillisecondsSinceEpoch(r.read<int>('created')),
          r.readNullable<String>('app') ?? '',
          r.readNullable<String>('device') ?? '',
          r.read<int>('accounts'),
          r.read<int>('secrets') != 0,
        ),
    ];
  }

  Future<Uint8List?> settingsData(int id) async {
    final r = await customSelect('SELECT data FROM app_settings WHERE id = ?', variables: [Variable.withInt(id)])
        .getSingleOrNull();
    return r?.readNullable<Uint8List>('data');
  }

  // ── объединение с копией ──

  /// Добавить в этот архив всё, чего в нём нет, из архива [src] — копии
  /// (.ogna) с другого устройства или сохранённой раньше (28.10.2026: один
  /// архив на нескольких устройствах). Ящики сводятся по адресу, папки — по
  /// пути, письмо, которое уже есть (та же папка и тот же Message-ID или id
  /// на сервере), не повторяется; встречи, задачи и контакты — по id в
  /// ящике; снимки настроек — по дате. Письма — пачками по [batch], одна
  /// транзакция на пачку: прерванное объединение можно просто повторить.
  Future<ArchiveMergeReport> mergeFrom(ArchiveDb src,
      {int batch = 50, void Function(int done, int total)? onProgress}) async {
    // Ящики.
    final accounts = <String, String>{};
    for (final r in await src.customSelect('SELECT id, email, name, type, color FROM accounts').get()) {
      final id = r.read<String>('id');
      accounts[id] = await resolveAccount(id, r.read<String>('email'), r.readNullable<String>('name') ?? '',
          r.readNullable<String>('type') ?? '', r.readNullable<int>('color') ?? 0);
    }
    String acc(String id) => accounts[id] ?? id;

    // Папки: путь родителя короче — родители раньше детей.
    final folders = <int, int>{};
    final srcFolders = await src
        .customSelect('SELECT id, account_id, path, name, parent_id, type FROM folders ORDER BY length(path), id')
        .get();
    await transaction(() async {
      for (final f in srcFolders) {
        final account = acc(f.read<String>('account_id'));
        final path = f.read<String>('path');
        final existing = await customSelect('SELECT id FROM folders WHERE account_id = ? AND path = ?',
            variables: [Variable.withString(account), Variable.withString(path)]).getSingleOrNull();
        if (existing != null) {
          folders[f.read<int>('id')] = existing.read<int>('id');
          continue;
        }
        final parent = f.readNullable<int>('parent_id');
        folders[f.read<int>('id')] = await customInsert(
          'INSERT INTO folders(account_id, path, name, parent_id, type) VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(account),
            Variable.withString(path),
            Variable.withString(f.read<String>('name')),
            Variable<int>(parent == null ? null : folders[parent]),
            Variable.withString(f.read<String>('type')),
          ],
        );
      }
    });

    // Письма.
    final ids = [for (final r in await src.customSelect('SELECT id FROM messages ORDER BY id').get()) r.read<int>('id')];
    var added = 0, skipped = 0;
    onProgress?.call(0, ids.length);
    for (var i = 0; i < ids.length; i += batch) {
      final part = ids.sublist(i, i + batch > ids.length ? ids.length : i + batch);
      await transaction(() async {
        for (final id in part) {
          final m = await src.customSelect('SELECT * FROM messages WHERE id = ?', variables: [Variable.withInt(id)])
              .getSingleOrNull();
          if (m == null) continue;
          final folder = folders[m.read<int>('folder_id')];
          if (folder == null) {
            skipped++;
            continue;
          }
          final account = acc(m.read<String>('account_id'));
          final sourceId = m.readNullable<String>('source_id') ?? '';
          final mid = (m.readNullable<String>('message_id') ?? '').trim();
          final dup = await customSelect(
            'SELECT id FROM messages WHERE account_id = ? AND folder_id = ? AND '
            '((? <> \'\' AND source_id = ?) OR (? <> \'\' AND message_id = ?)) LIMIT 1',
            variables: [
              Variable.withString(account),
              Variable.withInt(folder),
              Variable.withString(sourceId),
              Variable.withString(sourceId),
              Variable.withString(mid),
              Variable.withString(mid),
            ],
          ).getSingleOrNull();
          if (dup != null) {
            skipped++;
            continue;
          }
          final newId = await customInsert(
            'INSERT INTO messages(account_id, folder_id, source_id, message_id, conversation_id, subject, '
            'from_name, from_email, to_json, cc_json, bcc_json, reply_to_json, date, is_read, is_flagged, '
            'importance, has_attachments, body_html, body_text, preview, size, archived_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            variables: [
              Variable.withString(account),
              Variable.withInt(folder),
              Variable<String>(m.readNullable<String>('source_id')),
              Variable<String>(mid.isEmpty ? null : mid),
              Variable<String>(m.readNullable<String>('conversation_id')),
              Variable.withString(m.read<String>('subject')),
              Variable<String>(m.readNullable<String>('from_name')),
              Variable.withString(m.read<String>('from_email')),
              Variable<String>(m.readNullable<String>('to_json')),
              Variable<String>(m.readNullable<String>('cc_json')),
              Variable<String>(m.readNullable<String>('bcc_json')),
              Variable<String>(m.readNullable<String>('reply_to_json')),
              Variable.withInt(m.read<int>('date')),
              Variable.withInt(m.read<int>('is_read')),
              Variable.withInt(m.read<int>('is_flagged')),
              Variable.withInt(m.read<int>('importance')),
              Variable.withInt(m.read<int>('has_attachments')),
              Variable<String>(m.readNullable<String>('body_html')),
              Variable<String>(m.readNullable<String>('body_text')),
              Variable<String>(m.readNullable<String>('preview')),
              Variable<int>(m.readNullable<int>('size')),
              Variable.withInt(m.read<int>('archived_at')),
            ],
          );
          for (final a in await src.customSelect(
              'SELECT name, mime, size, content_id, is_inline, data FROM attachments WHERE message_id = ? ORDER BY id',
              variables: [Variable.withInt(id)]).get()) {
            await customInsert(
              'INSERT INTO attachments(message_id, name, mime, size, content_id, is_inline, data) '
              'VALUES (?, ?, ?, ?, ?, ?, ?)',
              variables: [
                Variable.withInt(newId),
                Variable.withString(a.read<String>('name')),
                Variable<String>(a.readNullable<String>('mime')),
                Variable.withInt(a.read<int>('size')),
                Variable<String>(a.readNullable<String>('content_id')),
                Variable.withInt(a.read<int>('is_inline')),
                Variable<Uint8List>(a.readNullable<Uint8List>('data')),
              ],
            );
          }
          final fts = await src.customSelect('SELECT subject, people, body, files FROM messages_fts WHERE rowid = ?',
              variables: [Variable.withInt(id)]).getSingleOrNull();
          await customInsert(
            'INSERT INTO messages_fts(rowid, subject, people, body, files) VALUES (?, ?, ?, ?, ?)',
            variables: [
              Variable.withInt(newId),
              Variable.withString(fts?.readNullable<String>('subject') ?? m.read<String>('subject')),
              Variable.withString(fts?.readNullable<String>('people') ?? ''),
              Variable.withString(fts?.readNullable<String>('body') ?? ''),
              Variable.withString(fts?.readNullable<String>('files') ?? ''),
            ],
          );
          added++;
        }
      });
      onProgress?.call(i + part.length, ids.length);
    }

    // Встречи, задачи, контакты: по ящику и id в ящике.
    Future<int> items(String table, List<String> cols) async {
      var n = 0;
      final rows = await src.customSelect('SELECT account_id, source_id, ${cols.join(', ')} FROM $table').get();
      await transaction(() async {
        for (final r in rows) {
          final account = acc(r.read<String>('account_id'));
          final sourceId = r.read<String>('source_id');
          final has = await customSelect('SELECT id FROM $table WHERE account_id = ? AND source_id = ?',
              variables: [Variable.withString(account), Variable.withString(sourceId)]).getSingleOrNull();
          if (has != null) continue;
          await customInsert(
            'INSERT INTO $table(account_id, source_id, ${cols.join(', ')}) '
            'VALUES (?, ?, ${List.filled(cols.length, '?').join(', ')})',
            variables: [
              Variable.withString(account),
              Variable.withString(sourceId),
              for (final c in cols) _variable(r.data[c]),
            ],
          );
          n++;
        }
      });
      return n;
    }

    final events = await items(
        'events', const ['title', 'location', 'start', 'end', 'all_day', 'organizer', 'data_json', 'archived_at']);
    final tasks = await items('tasks', const ['title', 'due', 'completed_at', 'data_json', 'archived_at']);
    final contacts =
        await items('contacts', const ['name', 'email', 'company', 'phone', 'data_json', 'archived_at']);

    // Снимки настроек приложения: каких нет (по дате и устройству), затем
    // — только последние [keepSettings].
    var settings = 0;
    final snaps = await src.customSelect('SELECT created, app, device, accounts, secrets, data FROM app_settings').get();
    await transaction(() async {
      for (final r in snaps) {
        final has = await customSelect('SELECT id FROM app_settings WHERE created = ? AND coalesce(device, \'\') = ?',
            variables: [
              Variable.withInt(r.read<int>('created')),
              Variable.withString(r.readNullable<String>('device') ?? ''),
            ]).getSingleOrNull();
        if (has != null) continue;
        await customInsert(
          'INSERT INTO app_settings(created, app, device, accounts, secrets, data) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(r.read<int>('created')),
            Variable<String>(r.readNullable<String>('app')),
            Variable<String>(r.readNullable<String>('device')),
            Variable.withInt(r.read<int>('accounts')),
            Variable.withInt(r.read<int>('secrets')),
            Variable.withBlob(r.read<Uint8List>('data')),
          ],
        );
        settings++;
      }
      await customStatement(
        'DELETE FROM app_settings WHERE id NOT IN (SELECT id FROM app_settings ORDER BY created DESC LIMIT ?)',
        [keepSettings],
      );
    });

    return ArchiveMergeReport(
      messages: added,
      skipped: skipped,
      events: events,
      tasks: tasks,
      contacts: contacts,
      settings: settings,
    );
  }

  static Variable<Object> _variable(Object? v) => switch (v) {
        null => const Variable(null),
        final int i => Variable.withInt(i),
        final double d => Variable.withReal(d),
        final String t => Variable.withString(t),
        final Uint8List b => Variable.withBlob(b),
        _ => Variable.withString('$v'),
      };

  Future<ArchiveStats> stats() async {
    Future<int> count(String sql) async => (await customSelect(sql).getSingle()).read<int>('n');
    final m = await customSelect('SELECT count(*) AS n, min(date) AS lo, max(date) AS hi FROM messages').getSingle();
    final a = await customSelect('SELECT count(*) AS n, coalesce(sum(size), 0) AS b FROM attachments').getSingle();
    final lo = m.readNullable<int>('lo');
    final hi = m.readNullable<int>('hi');
    return ArchiveStats(
      messages: m.read<int>('n'),
      attachments: a.read<int>('n'),
      attachmentBytes: a.read<int>('b'),
      events: await count('SELECT count(*) AS n FROM events'),
      tasks: await count('SELECT count(*) AS n FROM tasks'),
      contacts: await count('SELECT count(*) AS n FROM contacts'),
      oldest: lo == null ? null : DateTime.fromMillisecondsSinceEpoch(lo),
      newest: hi == null ? null : DateTime.fromMillisecondsSinceEpoch(hi),
    );
  }
}

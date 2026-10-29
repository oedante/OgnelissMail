// lib/services/archive/archive_runner.dart
// Архивация в архив Ogneliss (1.7.3): по расписанию, кнопкой «Архивировать
// сейчас» и одним письмом («В архив Ogneliss» у письма).
//
// Письмо архивируется целиком: адресаты, текст с оформлением, вложения и
// картинки в тексте — с телефона, недостающее с сервера; папка — с путём от
// корня ящика (структура папок сохраняется). Только когда копия записана в
// архив, исходное письмо уходит в «Удалённые» на сервере (если так
// настроено). Не скачалось вложение или текст — письмо пропускается и
// остаётся в ящике до следующего раза.
//
// Встречи (закончившиеся, без повторения), выполненные задачи и свои
// контакты кладутся в архив копией: на сервере они остаются — удаление
// встречи организатором рассылает отмену участникам.
//
// Архивируется то, что есть на телефоне: письма в периоде синхронизации
// ящика (Настройки ящика → «Период»). Старше — только на сервере; чтобы
// заархивировать их, период увеличивают («Вся почта»).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/security/mail_body_processor.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider, emailModelFromRow;
import '../mail/attachment_cache_service.dart' show attachmentCacheProvider;
import '../mail/draft_sync_service.dart' show draftSyncServiceProvider;
import '../mail/email_actions_service.dart' show emailActionsProvider;
import '../mail/eml_reader.dart';
import '../mail/engine/mail_engine_service.dart';
import '../mail/ews/ews_service.dart' show ewsServiceProvider;
import '../mail/imap/imap_service.dart' show imapServiceProvider;
import 'archive_app_settings.dart';
import 'archive_db.dart';
import 'archive_settings.dart';
import 'archive_vault.dart';

/// Итог архивации.
class ArchiveRunResult {
  final DateTime at;
  final bool manual;
  final int mails;
  final int deleted;
  final int failed;
  final int events;
  final int tasks;
  final int contacts;
  final bool cancelled;

  /// Почему не выполнено (ключ строки): archiveLocked, archiveNoNetwork,
  /// archiveWaitWifi.
  final String? errorKey;

  const ArchiveRunResult({
    required this.at,
    this.manual = false,
    this.mails = 0,
    this.deleted = 0,
    this.failed = 0,
    this.events = 0,
    this.tasks = 0,
    this.contacts = 0,
    this.cancelled = false,
    this.errorKey,
  });

  bool get nothing => mails == 0 && events == 0 && tasks == 0 && contacts == 0 && failed == 0;

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'manual': manual,
        'mails': mails,
        'deleted': deleted,
        'failed': failed,
        'events': events,
        'tasks': tasks,
        'contacts': contacts,
        'cancelled': cancelled,
        if (errorKey != null) 'error': errorKey,
      };

  static ArchiveRunResult? fromJson(Object? j) {
    if (j is! Map) return null;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ArchiveRunResult(
      at: DateTime.fromMillisecondsSinceEpoch(n('at')),
      manual: j['manual'] == true,
      mails: n('mails'),
      deleted: n('deleted'),
      failed: n('failed'),
      events: n('events'),
      tasks: n('tasks'),
      contacts: n('contacts'),
      cancelled: j['cancelled'] == true,
      errorKey: j['error'] as String?,
    );
  }
}

class ArchiveRunState {
  final bool running;
  final bool cancelling;
  final int done;
  final int total;
  final int failed;

  /// Что сейчас: mail, events, tasks, contacts.
  final String stage;
  final ArchiveRunResult? last;

  const ArchiveRunState({
    this.running = false,
    this.cancelling = false,
    this.done = 0,
    this.total = 0,
    this.failed = 0,
    this.stage = '',
    this.last,
  });

  double? get progress => total <= 0 ? null : (done / total).clamp(0, 1).toDouble();

  ArchiveRunState copyWith({
    bool? running,
    bool? cancelling,
    int? done,
    int? total,
    int? failed,
    String? stage,
    ArchiveRunResult? last,
  }) =>
      ArchiveRunState(
        running: running ?? this.running,
        cancelling: cancelling ?? this.cancelling,
        done: done ?? this.done,
        total: total ?? this.total,
        failed: failed ?? this.failed,
        stage: stage ?? this.stage,
        last: last ?? this.last,
      );
}

final archiveRunnerProvider = NotifierProvider<ArchiveRunner, ArchiveRunState>(ArchiveRunner.new);

class ArchiveRunner extends Notifier<ArchiveRunState> {
  static const _kLast = 'ogna_last_result';

  bool _cancel = false;
  DateTime? _lastAutoCheck;

  @override
  ArchiveRunState build() {
    ArchiveRunResult? last;
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_kLast);
      if (raw != null) last = ArchiveRunResult.fromJson(jsonDecode(raw));
    } catch (_) {}
    return ArchiveRunState(last: last);
  }

  void cancel() {
    if (!state.running) return;
    _cancel = true;
    state = state.copyWith(cancelling: true);
  }

  /// По расписанию: при запуске и при возврате в приложение (не чаще раза в
  /// 15 минут проверка, сама архивация — раз в N дней).
  Future<void> maybeAutoRun() async {
    final now = DateTime.now();
    if (_lastAutoCheck != null && now.difference(_lastAutoCheck!) < const Duration(minutes: 15)) return;
    _lastAutoCheck = now;
    final s = ref.read(archiveSettingsProvider);
    if (!s.due(now) || state.running) return;
    final vault = await ref.read(archiveVaultProvider.future);
    if (!vault.isOpen) return;
    final net = ref.read(connectivityServiceProvider);
    if (!net.isConnected) return;
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (s.wifiOnly && mobile && !net.isWifi) return;
    AppLogger.info('Архив Ogneliss: архивация по расписанию');
    await run(manual: false);
  }

  ArchiveDb? get _adb => ref.read(archiveVaultProvider.notifier).db;

  /// Архивировать по правилам: письма старше [months] месяцев (null — из
  /// настроек, 0 — все письма), встречи, задачи и контакты — по настройкам.
  Future<ArchiveRunResult> run({bool manual = true, int? months}) async {
    if (state.running) return state.last ?? ArchiveRunResult(at: DateTime.now(), manual: manual);
    final s = ref.read(archiveSettingsProvider);
    final now = DateTime.now();
    if (_adb == null) {
      return _finish(ArchiveRunResult(at: now, manual: manual, errorKey: 'archiveLocked'), record: false);
    }
    _cancel = false;
    state = state.copyWith(running: true, cancelling: false, done: 0, total: 0, failed: 0, stage: 'mail');
    final m = months ?? s.months;
    final cutoff = m <= 0 ? now.add(const Duration(days: 1)) : ArchiveSettings(months: m).cutoff(now);
    final accounts = [
      for (final a in ref.read(accountsProvider))
        if (a.isActive && !a.isOnlineArchive && !s.skipAccounts.contains(a.id)) a,
    ];
    var mails = 0, deleted = 0, failed = 0, events = 0, tasks = 0, contacts = 0;
    String? error;
    try {
      if (s.mail) {
        if (!ref.read(connectivityServiceProvider).isConnected) {
          error = 'archiveNoNetwork';
        } else {
          // Папки ящиков — в архив сразу, даже пустые: структура как в
          // ящике видна с первой архивации (замечание 29.10.2026).
          await _mirrorFolders(accounts);
          final r = await _mail(accounts, cutoff, s, now);
          mails = r.archived;
          deleted = r.deleted;
          failed = r.failed;
          if (!_cancel) {
            final r2 = await _serverMail(accounts, cutoff, s, now);
            mails += r2.archived;
            deleted += r2.deleted;
            failed += r2.failed;
          }
        }
      }
      if (s.events && !_cancel) {
        state = state.copyWith(stage: 'events');
        events = await _events(accounts, cutoff);
      }
      if (s.tasks && !_cancel) {
        state = state.copyWith(stage: 'tasks');
        tasks = await _tasks(accounts, cutoff);
      }
      if (s.contacts && !_cancel) {
        state = state.copyWith(stage: 'contacts');
        contacts = await _contacts(accounts);
      }
      if (s.appSettings && !_cancel) {
        state = state.copyWith(stage: 'settings');
        await saveAppSettings();
      }
    } catch (e, st) {
      AppLogger.error('Архив Ogneliss: архивация прервана', e, st);
      error ??= 'archiveFailed';
    }
    final result = ArchiveRunResult(
      at: now,
      manual: manual,
      mails: mails,
      deleted: deleted,
      failed: failed,
      events: events,
      tasks: tasks,
      contacts: contacts,
      cancelled: _cancel,
      errorKey: error,
    );
    AppLogger.info('Архив Ogneliss: писем $mails (удалено с сервера $deleted, не удалось $failed), '
        'встреч $events, задач $tasks, контактов $contacts${_cancel ? ', остановлено' : ''}');
    // Расписание сдвигается и после ручной архивации — как в Outlook.
    if (error == null || mails > 0) await ref.read(archiveSettingsProvider.notifier).markRun(now);
    return _finish(result);
  }

  Future<ArchiveRunResult> _finish(ArchiveRunResult r, {bool record = true}) async {
    _cancel = false;
    state = ArchiveRunState(last: r);
    ref.read(archiveVaultProvider.notifier).touch();
    if (record) {
      try {
        await ref.read(sharedPrefsProvider).setString(_kLast, jsonEncode(r.toJson()));
      } catch (_) {}
    }
    return r;
  }

  // ── письма ──

  Future<({int archived, int deleted, int failed})> _mail(
      List<AccountModel> accounts, DateTime cutoff, ArchiveSettings s, DateTime now) async {
    final db = ref.read(databaseProvider);
    // Сначала — список кандидатов (только id): тексты писем читаются по
    // одному, тысячи писем не держатся в памяти.
    final plan = <({AccountModel account, String id})>[];
    final folderInfo = <String, Map<String, Folder>>{};
    for (final a in accounts) {
      final folders = await (db.select(db.folders)..where((f) => f.accountId.equals(a.id))).get();
      final byId = {for (final f in folders) f.id: f};
      folderInfo[a.id] = byId;
      final q = db.selectOnly(db.emails)
        ..addColumns([db.emails.id, db.emails.folderId])
        ..where(db.emails.accountId.equals(a.id) &
            db.emails.receivedAt.isSmallerThanValue(cutoff) &
            db.emails.isDraft.equals(false))
        ..orderBy([OrderingTerm.asc(db.emails.receivedAt)]);
      for (final r in await q.get()) {
        final f = byId[r.read(db.emails.folderId)];
        final t = f == null ? null : _type(f.type);
        if (t == null || !ArchiveRules.mailFolders.contains(t)) continue;
        plan.add((account: a, id: r.read(db.emails.id)!));
      }
    }
    state = state.copyWith(total: plan.length, done: 0);
    var archived = 0, deleted = 0, failed = 0;
    for (final (i, item) in plan.indexed) {
      if (_cancel) break;
      final row = await (db.select(db.emails)
            ..where((e) => e.id.equals(item.id) & e.accountId.equals(item.account.id)))
          .getSingleOrNull();
      if (row != null) {
        final folder = folderInfo[item.account.id]?[row.folderId];
        final ok = ArchiveRules.mailEligible(row,
            folderType: folder == null ? null : _type(folder.type),
            cutoff: cutoff,
            includeFlagged: s.includeFlagged,
            now: now);
        if (ok) {
          final r = await _archiveOne(item.account, row, folderInfo[item.account.id]!, delete: s.deleteFromServer);
          if (r.archived) archived++;
          if (r.deleted) deleted++;
          if (!r.archived) failed++;
        }
      }
      state = state.copyWith(done: i + 1, failed: failed);
      // Ленте и анимациям — свой кадр между письмами.
      await Future<void>.delayed(Duration.zero);
    }
    return (archived: archived, deleted: deleted, failed: failed);
  }

  /// Папки ящика, из которых архивируется почта, — с цепочкой от корня;
  /// внутри корзины, спама, черновиков и исходящих — нет.
  static List<({Folder folder, List<({String name, String type})> chain})> mailFoldersOf(List<Folder> folders) {
    final byId = {for (final f in folders) f.id: f};
    final out = <({Folder folder, List<({String name, String type})> chain})>[];
    for (final f in folders) {
      final t = _type(f.type);
      if (t == null || !ArchiveRules.mailFolders.contains(t) || !f.isSynced) continue;
      final chain = folderChain(f.id, byId);
      final excluded = {FolderType.trash, FolderType.junk, FolderType.drafts, FolderType.outbox}.map((e) => e.name).toSet();
      if (chain.any((c) => excluded.contains(c.type))) continue;
      out.add((folder: f, chain: chain));
    }
    return out;
  }

  Future<void> _mirrorFolders(List<AccountModel> accounts) async {
    final adb = _adb;
    if (adb == null) return;
    final db = ref.read(databaseProvider);
    for (final a in accounts) {
      final folders = await (db.select(db.folders)..where((f) => f.accountId.equals(a.id))).get();
      final list = mailFoldersOf(folders);
      if (list.isEmpty) continue;
      final acc = await _archiveAccount(adb, a);
      for (final f in list) {
        await adb.ensureFolder(acc, f.chain);
      }
    }
  }

  /// Письма старше срока, которых нет на устройстве, — прямо с сервера
  /// (29.10.2026: «в архив ничего не попадает»). Устройство хранит почту за
  /// период синхронизации ящика (по умолчанию год); всё, что старше, раньше
  /// архивация не видела. IMAP — поиск BEFORE и письмо целиком (MIME);
  /// Exchange по EWS — FindItem по дате и MIME. ActiveSync — нет: в нём нет
  /// запроса «письма до даты», которые потом можно удалить; для него
  /// архивируется то, что на устройстве (период «Вся почта» — вся почта).
  Future<({int archived, int deleted, int failed})> _serverMail(
      List<AccountModel> accounts, DateTime cutoff, ArchiveSettings s, DateTime now) async {
    final adb = _adb;
    var archived = 0, deleted = 0, failed = 0;
    if (adb == null) return (archived: 0, deleted: 0, failed: 0);
    final db = ref.read(databaseProvider);
    for (final a in accounts) {
      if (_cancel) break;
      if (a.usesEas || (a.isMsExchange && !a.usesEws)) continue;
      // «Вся почта» — всё уже на устройстве и заархивировано выше.
      if (a.syncDays <= 0) continue;
      final window = now.subtract(Duration(days: a.syncDays));
      final before = cutoff.isBefore(window) ? cutoff : window;
      final folders = await (db.select(db.folders)..where((f) => f.accountId.equals(a.id))).get();
      final acc = await _archiveAccount(adb, a);
      for (final f in mailFoldersOf(folders)) {
        if (_cancel) break;
        List<String> ids;
        try {
          ids = a.usesEws
              ? await ref.read(ewsServiceProvider).itemIdsBefore(a, folderId: f.folder.id, before: before)
              : [
                  for (final u in await ref.read(imapServiceProvider).uidsBefore(a, folderId: f.folder.id, before: before))
                    '${f.folder.id}:$u',
                ];
        } catch (e) {
          // Сервер не отвечает — остальные папки этого ящика не пробуем
          // (на медленной сети каждая попытка — десятки секунд).
          AppLogger.warning('Архив: старые письма папки «${f.folder.displayName}» с сервера не получены: $e');
          break;
        }
        if (ids.isEmpty) continue;
        AppLogger.info('Архив: «${f.folder.displayName}» — с сервера писем старше периода: ${ids.length}');
        final folderId = await adb.ensureFolder(acc, f.chain);
        state = state.copyWith(total: state.total + ids.length);
        for (final id in ids) {
          if (_cancel) break;
          var ok = await adb.hasMessage(acc, folderId, id, null);
          if (!ok) {
            ok = await _archiveServerMessage(adb, a, acc, f.chain, f.folder.id, id);
            if (ok) archived++;
          }
          if (!ok) {
            failed++;
          } else if (s.deleteFromServer && await _deleteOnServer(a, f.folder.id, id)) {
            deleted++;
          }
          state = state.copyWith(done: state.done + 1, failed: state.failed + (ok ? 0 : 1));
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    return (archived: archived, deleted: deleted, failed: failed);
  }

  Future<bool> _archiveServerMessage(ArchiveDb adb, AccountModel a, String archiveAccount,
      List<({String name, String type})> chain, String folderId, String id) async {
    try {
      final raw = a.usesEws
          ? await ref.read(ewsServiceProvider).getMimeContent(a, id).timeout(const Duration(minutes: 3))
          : await ref
              .read(imapServiceProvider)
              .fetchRawMessage(a, folderId: folderId, uid: int.parse(id.substring(id.lastIndexOf(':') + 1)))
              .timeout(const Duration(minutes: 3));
      if (raw == null || raw.isEmpty) return false;
      await adb.addMessage(
          await inputFromMime(raw, accountId: archiveAccount, folderChain: chain, sourceId: id));
      return true;
    } catch (e) {
      AppLogger.warning('Архив: письмо с сервера не заархивировано: $e');
      return false;
    }
  }

  Future<bool> _deleteOnServer(AccountModel a, String folderId, String id) async {
    try {
      if (a.usesEws) {
        await ref.read(ewsServiceProvider).deleteEmail(a, emailId: id);
      } else {
        await ref.read(imapServiceProvider).deleteEmail(a, folderId: folderId, uid: id.substring(id.lastIndexOf(':') + 1));
      }
      return true;
    } catch (e) {
      AppLogger.warning('Архив: письмо на сервере не удалено (копия в архиве есть): $e');
      return false;
    }
  }

  /// Письмо целиком (MIME) — в запись архива: тело, адресаты, вложения и
  /// картинки в тексте (cid:), Message-ID и важность из заголовков.
  static Future<ArchiveMessageInput> inputFromMime(Uint8List raw,
      {required String accountId,
      required List<({String name, String type})> folderChain,
      required String sourceId}) async {
    final m = await EmlReader.parseAsync(raw);
    final head = mimeHeaders(raw);
    final html = (m.html ?? '').trim().isEmpty ? null : m.html;
    final plain = (m.plain ?? '').trim().isEmpty ? null : m.plain;
    final search = plain ??
        (html == null ? '' : await MailBodyProcessor.heavy(html, MailBodyProcessor.htmlToPlain, background: true));
    final from = m.from.firstOrNull;
    final files = <ArchiveAttachmentInput>[
      for (final a in m.attachments) ArchiveAttachmentInput(name: a.name, mime: a.contentType, bytes: a.bytes),
      for (final e in m.inlineImages.entries)
        if (e.value.startsWith('data:') && e.value.contains(';base64,'))
          ArchiveAttachmentInput(
            name: e.key,
            mime: e.value.substring(5, e.value.indexOf(';')),
            bytes: base64Decode(e.value.substring(e.value.indexOf(',') + 1)),
            contentId: e.key,
            isInline: true,
          ),
    ];
    final previewSource = (search ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return ArchiveMessageInput(
      accountId: accountId,
      folderChain: folderChain,
      sourceId: sourceId,
      messageId: head['message-id'],
      subject: m.subject,
      fromName: from?.name ?? '',
      fromEmail: from?.email ?? '',
      to: [for (final a in m.to) (name: a.name, email: a.email)],
      cc: [for (final a in m.cc) (name: a.name, email: a.email)],
      date: m.date ?? DateTime.now(),
      importance: importanceOf(head),
      bodyHtml: html,
      bodyText: plain,
      preview: previewSource.length > 200 ? previewSource.substring(0, 200) : previewSource,
      size: raw.length,
      attachments: files,
      searchText: search ?? '',
    );
  }

  /// Заголовки письма (до первой пустой строки), имена — строчными;
  /// перенесённые строки склеиваются.
  static Map<String, String> mimeHeaders(Uint8List raw) {
    final text = latin1.decode(raw.length > 65536 ? raw.sublist(0, 65536) : raw, allowInvalid: true);
    final end = text.indexOf(RegExp(r'\r?\n\r?\n'));
    final out = <String, String>{};
    String? name;
    for (final line in (end < 0 ? text : text.substring(0, end)).split(RegExp(r'\r?\n'))) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (name != null) out[name] = '${out[name]} ${line.trim()}';
        continue;
      }
      final i = line.indexOf(':');
      if (i <= 0) continue;
      name = line.substring(0, i).trim().toLowerCase();
      out.putIfAbsent(name, () => line.substring(i + 1).trim());
    }
    return out;
  }

  /// Важность: Importance или X-Priority; 0 — низкая, 1 — обычная, 2 — высокая.
  static int importanceOf(Map<String, String> head) {
    final imp = (head['importance'] ?? '').toLowerCase();
    if (imp.startsWith('high')) return 2;
    if (imp.startsWith('low')) return 0;
    final p = int.tryParse((head['x-priority'] ?? '').trim().split(' ').first);
    if (p != null && p <= 2) return 2;
    if (p != null && p >= 4) return 0;
    return 1;
  }

  static FolderType? _type(int index) => index >= 0 && index < FolderType.values.length ? FolderType.values[index] : null;

  /// Письма, выбранные человеком («В архив Ogneliss»): без проверки возраста
  /// и папки. Исходные — в «Удалённые», если так настроено.
  Future<({int archived, int failed})> archiveEmails(AccountModel account, List<Email> rows) async {
    if (_adb == null) return (archived: 0, failed: rows.length);
    final db = ref.read(databaseProvider);
    final folders = {
      for (final f in await (db.select(db.folders)..where((f) => f.accountId.equals(account.id))).get()) f.id: f,
    };
    final s = ref.read(archiveSettingsProvider);
    var archived = 0, failed = 0;
    for (final row in rows) {
      if (!ArchiveRules.mailEligible(row,
          folderType: null, cutoff: DateTime.now(), includeFlagged: true, now: DateTime.now(), manual: true)) {
        failed++;
        continue;
      }
      final r = await _archiveOne(account, row, folders, delete: s.deleteFromServer);
      r.archived ? archived++ : failed++;
    }
    ref.read(archiveVaultProvider.notifier).touch();
    return (archived: archived, failed: failed);
  }

  /// Одно письмо в архив. archived — копия в архиве; deleted — исходное
  /// отправлено в «Удалённые».
  Future<({bool archived, bool deleted})> _archiveOne(
      AccountModel account, Email row, Map<String, Folder> folders,
      {required bool delete}) async {
    final adb = _adb;
    if (adb == null) return (archived: false, deleted: false);
    try {
      // Текст, адресаты и список файлов — если на телефоне их нет (письмо
      // старое или крупное), с сервера.
      final full = await ref.read(draftSyncServiceProvider).completeServerDraft(account, row);
      if (!full.complete) {
        AppLogger.debug('Архив: письмо ${row.id} не догружено — пропуск');
        return (archived: false, deleted: false);
      }
      final r = full.row;
      final m = emailModelFromRow(r);
      final files = await _attachments(account, m);
      if (files == null) return (archived: false, deleted: false);

      final html = (r.bodyHtml ?? '').trim().isEmpty ? null : r.bodyHtml;
      final plain = (r.bodyPlain ?? '').trim().isEmpty ? null : r.bodyPlain;
      final search = plain ??
          (html == null ? '' : await MailBodyProcessor.heavy(html, MailBodyProcessor.htmlToPlain, background: true));
      ArchivePerson person(EmailAddress a) => (name: a.displayName ?? '', email: a.email);
      final accountId = await _archiveAccount(adb, account);
      await adb.addMessage(ArchiveMessageInput(
        accountId: accountId,
        folderChain: folderChain(r.folderId, folders),
        sourceId: r.id,
        messageId: r.internetMessageId,
        conversationId: r.conversationId,
        subject: r.subject,
        fromName: r.fromName ?? '',
        fromEmail: r.fromEmail,
        to: [for (final a in m.to) person(a)],
        cc: [for (final a in m.cc) person(a)],
        bcc: [for (final a in m.bcc) person(a)],
        replyTo: [for (final a in m.replyTo) person(a)],
        date: r.receivedAt,
        isRead: r.isRead,
        isFlagged: r.isFlagged,
        importance: r.priority,
        bodyHtml: html,
        bodyText: plain,
        preview: r.bodyPreview,
        size: r.size,
        attachments: files,
        searchText: search ?? '',
      ));
      if (!delete) return (archived: true, deleted: false);
      await ref.read(emailActionsProvider).delete(account, r.id, r.folderId);
      return (archived: true, deleted: true);
    } catch (e) {
      AppLogger.warning('Архив: письмо ${row.id} не заархивировано: $e');
      return (archived: false, deleted: false);
    }
  }

  /// Файлы письма: с телефона (кэш вложений), недостающие — с сервера.
  /// null — что-то не скачалось (письмо в этот раз не архивируется).
  Future<List<ArchiveAttachmentInput>?> _attachments(AccountModel account, EmailModel m) async {
    final list = [for (final a in m.attachments) if (!a.isVmlPreview && a.id.isNotEmpty) a];
    if (list.isEmpty) return const [];
    final cache = ref.read(attachmentCacheProvider);
    await cache.ensureLoaded();
    final bytes = <String, Uint8List>{};
    for (final a in list) {
      try {
        final p = await cache.get(MailEngineService.attachmentCacheKey(account.id, m.id, a.id));
        if (p != null) bytes[a.id] = await File(p).readAsBytes();
      } catch (_) {}
    }
    final missing = [for (final a in list) if (!bytes.containsKey(a.id)) a.id];
    if (missing.isNotEmpty) {
      try {
        bytes.addAll(await ref
            .read(mailEngineServiceProvider)
            .getAttachmentsBytes(account, missing, emailId: m.id)
            .timeout(const Duration(minutes: 3)));
      } catch (e) {
        AppLogger.debug('Архив: вложения письма ${m.id}: $e');
      }
    }
    if (list.any((a) => !bytes.containsKey(a.id))) {
      AppLogger.info('Архив: не скачались вложения письма ${m.id} — письмо остаётся в ящике');
      return null;
    }
    return [
      for (final a in list)
        ArchiveAttachmentInput(
          name: a.name,
          mime: a.mimeType,
          contentId: a.contentId,
          isInline: a.isInline,
          bytes: bytes[a.id]!,
        ),
    ];
  }

  /// Папки от корня ящика до [folderId]: (название, тип).
  static List<({String name, String type})> folderChain(String folderId, Map<String, Folder> folders) {
    final chain = <({String name, String type})>[];
    var id = folderId;
    final seen = <String>{};
    while (seen.add(id)) {
      final f = folders[id];
      if (f == null) break;
      chain.insert(0, (name: f.displayName, type: (_type(f.type) ?? FolderType.custom).name));
      final parent = f.parentId;
      if (parent == null || parent.isEmpty) break;
      id = parent;
    }
    if (chain.isEmpty) chain.add((name: folderId, type: FolderType.custom.name));
    return chain;
  }

  /// Снимок настроек приложения — в архив (при архивации и кнопкой).
  Future<bool> saveAppSettings() async {
    final adb = _adb;
    if (adb == null) return false;
    try {
      await ArchiveAppSettings.save(
        archive: adb,
        db: ref.read(databaseProvider),
        prefs: ref.read(sharedPrefsProvider),
        secure: ref.read(secureStorageProvider),
        withSecrets: ref.read(archiveSettingsProvider).appSettingsSecrets,
      );
      ref.read(archiveVaultProvider.notifier).touch();
      return true;
    } catch (e) {
      AppLogger.warning('Архив Ogneliss: настройки не сохранены: $e');
      return false;
    }
  }

  // ── встречи, задачи, контакты ──

  /// Ящик в архиве для ящика [a]. Архив, подключённый или объединённый с
  /// копией с другого устройства, знает этот же ящик под другим id — данные
  /// пишутся в него (по адресу), а не второй веткой с тем же адресом.
  final Map<String, String> _accountIds = {};
  ArchiveDb? _accountIdsDb;
  Future<String> _archiveAccount(ArchiveDb adb, AccountModel a) async {
    if (!identical(adb, _accountIdsDb)) {
      // Другой архив (подключён, создан заново, переоткрыт) — заново.
      _accountIds.clear();
      _accountIdsDb = adb;
    }
    final known = _accountIds[a.id];
    if (known != null) return known;
    final id = await adb.resolveAccount(a.id, a.email, a.displayName, a.type.name, a.colorValue);
    return _accountIds[a.id] = id;
  }

  Future<int> _events(List<AccountModel> accounts, DateTime cutoff) async {
    final adb = _adb;
    if (adb == null) return 0;
    final db = ref.read(databaseProvider);
    var n = 0;
    for (final a in accounts) {
      final rows = await (db.select(db.calendarEvents)
            ..where((e) => e.accountId.equals(a.id) & e.endTime.isSmallerThanValue(cutoff) & e.recurrence.equals(0)))
          .get();
      if (rows.isEmpty) continue;
      final accountId = await _archiveAccount(adb, a);
      for (final e in rows) {
        if (_cancel) return n;
        await adb.upsertEvent(
          accountId: accountId,
          sourceId: e.id,
          title: e.title,
          location: e.location,
          start: e.startTime,
          end: e.endTime,
          allDay: e.isAllDay,
          organizer: e.organizerEmail,
          dataJson: jsonEncode(e.toJson()),
        );
        n++;
      }
    }
    return n;
  }

  Future<int> _tasks(List<AccountModel> accounts, DateTime cutoff) async {
    final adb = _adb;
    if (adb == null) return 0;
    final db = ref.read(databaseProvider);
    var n = 0;
    for (final a in accounts) {
      // Выполненные и отменённые (TaskStatus.completed = 2, cancelled = 3).
      final rows = await (db.select(db.tasks)..where((t) => t.accountId.equals(a.id) & t.status.isIn(const [2, 3])))
          .get();
      for (final t in rows) {
        if (_cancel) return n;
        if (!(t.completedAt ?? t.createdAt).isBefore(cutoff)) continue;
        final accountId = await _archiveAccount(adb, a);
        await adb.upsertTask(
          accountId: accountId,
          sourceId: t.id,
          title: t.title,
          due: t.dueDate,
          completedAt: t.completedAt,
          dataJson: jsonEncode(t.toJson()),
        );
        n++;
      }
    }
    return n;
  }

  Future<int> _contacts(List<AccountModel> accounts) async {
    final adb = _adb;
    if (adb == null) return 0;
    final db = ref.read(databaseProvider);
    final byId = {for (final a in accounts) a.id: a};
    // Свои контакты (ContactSource.personal = 1): снимок на дату архивации.
    final rows = await (db.select(db.contacts)..where((c) => c.source.equals(1))).get();
    var n = 0;
    for (final c in rows) {
      if (_cancel) return n;
      final acc = c.accountId ?? '';
      final owner = byId[acc];
      if (acc.isNotEmpty && owner == null) continue;
      await adb.upsertContact(
        accountId: owner == null ? 'device' : await _archiveAccount(adb, owner),
        sourceId: c.id,
        name: c.displayName,
        email: c.email,
        company: c.company,
        phone: c.phoneMobile ?? c.phoneWork,
        dataJson: jsonEncode(c.toJson()),
      );
      n++;
    }
    return n;
  }
}

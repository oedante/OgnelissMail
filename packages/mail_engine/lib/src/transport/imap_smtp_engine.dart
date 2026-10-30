// lib/src/transport/imap_smtp_engine.dart
// IMAP/SMTP на enough_mail (Basic и XOAUTH2) — ЗАГОТОВКА, приложением не
// используется: рабочий стек — lib/services/mail/imap (ImapService +
// OAuthService). Аудит 07.10.2026: UID-команды исправлены (P1); нет
// обновления токена и переподключения (P2), синхронизации по UIDVALIDITY,
// вложений и копии в «Отправленные» (P3), SMTP-хост угадывается (P4). Не
// подключать к приложению без доработки.
// enough_mail импортируется с префиксом em, чтобы не конфликтовать с нашими моделями.

import 'package:enough_mail/enough_mail.dart' as em;

import 'tolerant_smtp_client.dart';

import '../debug_log.dart';
import '../mail_engine.dart';
import '../models/models.dart';

class ImapSmtpEngine implements MailEngine {
  final DebugLog log;
  ImapSmtpEngine({DebugLog? logger}) : log = logger ?? DebugLog();
  static const _t = 'IMAP';

  em.ImapClient? _imap;
  AccountConfig? _cfg;

  @override
  MailTransportKind get kind => MailTransportKind.imapSmtp;

  @override
  Capabilities get capabilities => const Capabilities(mail: true, push: true);

  @override
  SecurityPolicy? get policy => null;

  @override
  Future<ConnectResult> connect(AccountConfig cfg) async {
    _cfg = cfg;
    try {
      final host = cfg.imapHost;
      if (host == null || host.isEmpty) {
        return ConnectResult(success: false, error: 'IMAP host не задан', log: [log.dump()]);
      }
      log.info(_t, 'IMAP → $host:${cfg.imapPort} (SSL=${cfg.imapSsl})');
      final client = em.ImapClient(isLogEnabled: false);
      await client.connectToServer(host, cfg.imapPort, isSecure: cfg.imapSsl);

      if (cfg.authKind == AuthKind.oauth2) {
        final token = cfg.oauthAccessToken;
        if (token == null) {
          return ConnectResult(success: false, error: 'Нет OAuth-токена', log: [log.dump()]);
        }
        await client.authenticateWithOAuth2(cfg.email, token);
        log.info(_t, 'IMAP OAuth2 (XOAUTH2) OK');
      } else {
        await client.login(cfg.email, cfg.password ?? '');
        log.info(_t, 'IMAP Basic (login) OK');
      }

      final boxes = await client.listMailboxes(recursive: true);
      log.info(_t, 'IMAP: ${boxes.length} ящиков');
      _imap = client;
      return ConnectResult(
        success: true,
        transport: MailTransportKind.imapSmtp,
        resolvedHost: host,
        capabilities: capabilities,
        log: [log.dump()],
      );
    } catch (e) {
      log.info(_t, 'IMAP ошибка: $e');
      return ConnectResult(success: false, error: '$e', log: [log.dump()]);
    }
  }

  @override
  Future<List<MailFolder>> listFolders() async {
    final client = _imap;
    if (client == null) return [];
    final boxes = await client.listMailboxes(recursive: true);
    // Контейнеры с \Noselect (у Gmail — [Gmail]) открыть нельзя.
    return boxes.where((b) => !b.flags.contains(em.MailboxFlag.noSelect)).map((b) {
      MailFolderType type = MailFolderType.user;
      if (b.isInbox) {
        type = MailFolderType.inbox;
      } else if (b.isSent) {
        type = MailFolderType.sent;
      } else if (b.isDrafts) {
        type = MailFolderType.drafts;
      } else if (b.isTrash) {
        type = MailFolderType.trash;
      } else if (b.isJunk) {
        type = MailFolderType.junk;
      }
      return MailFolder(id: b.encodedPath, displayName: b.name, type: type);
    }).toList();
  }

  @override
  Future<SyncResult> syncFolder(String folderId, {SyncState? since}) async {
    final client = _imap;
    if (client == null) return const SyncResult();
    final box = await client.selectMailboxByPath(folderId);
    final total = box.messagesExists;
    if (total == 0) return SyncResult(newState: SyncState('${box.uidValidity}:0'));

    final from = total > 30 ? total - 29 : 1;
    final sequence = em.MessageSequence.fromRange(from, total);
    em.FetchImapResult fetched;
    try {
      fetched = await client.fetchMessages(sequence, '(FLAGS ENVELOPE RFC822.SIZE BODYSTRUCTURE)');
    } catch (e) {
      log.warn(_t, 'Расширенный FETCH не прошёл, упрощаю: $e');
      fetched = await client.fetchMessages(sequence, '(FLAGS ENVELOPE RFC822.SIZE)');
    }
    final messages = fetched.messages;
    final added = messages.map((m) => _toMessage(m, folderId)).toList();
    final lastUid = messages.isNotEmpty ? (messages.last.uid ?? 0) : 0;
    return SyncResult(added: added, newState: SyncState('${box.uidValidity}:$lastUid'));
  }

  MailMessage _toMessage(em.MimeMessage m, String folderId) {
    final env = m.envelope;
    final fromList = env?.from;
    final fromAddr = (fromList != null && fromList.isNotEmpty)
        ? MailAddress(fromList.first.email, fromList.first.personalName)
        : const MailAddress('');
    return MailMessage(
      id: '$folderId:${m.uid ?? m.sequenceId ?? 0}',
      folderId: folderId,
      uid: m.uid,
      from: fromAddr,
      to: (env?.to ?? []).map((a) => MailAddress(a.email, a.personalName)).toList(),
      cc: (env?.cc ?? []).map((a) => MailAddress(a.email, a.personalName)).toList(),
      replyTo: (env?.replyTo ?? []).map((a) => MailAddress(a.email, a.personalName)).toList(),
      subject: env?.subject ?? '',
      date: env?.date,
      isRead: m.flags?.contains(em.MessageFlags.seen) ?? false,
      isFlagged: m.flags?.contains(em.MessageFlags.flagged) ?? false,
    );
  }

  @override
  Future<MailMessage> fetchMessage(MessageRef ref) async {
    final client = _imap;
    if (client == null) throw StateError('IMAP не подключён');
    await client.selectMailboxByPath(ref.folderId);
    final uid = ref.uid ?? int.tryParse(ref.id.split(':').last) ?? 0;
    final seq = em.MessageSequence.fromId(uid, isUid: true);
    final fetched = await client.uidFetchMessages(seq, '(FLAGS ENVELOPE BODY[] RFC822.SIZE)');
    final m = fetched.messages.isNotEmpty ? fetched.messages.first : em.MimeMessage();
    return MailMessage(
      id: ref.id,
      folderId: ref.folderId,
      uid: uid,
      from: MailAddress(m.fromEmail ?? ''),
      subject: m.decodeSubject() ?? '',
      bodyPlain: m.decodeTextPlainPart(),
      bodyHtml: m.decodeTextHtmlPart(),
    );
  }

  @override
  Future<void> send(OutgoingMessage message) async {
    final cfg = _cfg!;
    final builder = em.MessageBuilder.prepareMultipartAlternativeMessage()
      ..from = [
        message.from == null
            ? em.MailAddress(cfg.email, cfg.email)
            : em.MailAddress(message.from!.name ?? '', message.from!.email)
      ]
      ..to = message.to.map((a) => em.MailAddress(a.name ?? '', a.email)).toList()
      ..subject = message.subject;
    if (message.cc.isNotEmpty) {
      builder.cc = message.cc.map((a) => em.MailAddress(a.name ?? '', a.email)).toList();
    }
    if (message.bcc.isNotEmpty) {
      builder.bcc = message.bcc.map((a) => em.MailAddress(a.name ?? '', a.email)).toList();
    }
    final plain = message.bodyPlain ??
        (message.bodyHtml ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final html = message.bodyHtml ?? '<p>${plain.replaceAll("\n", "<br>")}</p>';
    builder.addTextHtml(html);
    builder.addTextPlain(plain);
    final mime = builder.buildMimeMessage();

    final smtpHost = cfg.smtpHost ?? cfg.imapHost!.replaceFirst('imap', 'smtp');
    final useSSL = cfg.smtpPort == 465;
    log.info(_t, 'SMTP -> $smtpHost:${cfg.smtpPort} (SSL=$useSSL)');
    final smtp = TolerantSmtpClient('mailengine', isLogEnabled: false);
    await smtp.connectToServer(smtpHost, cfg.smtpPort, isSecure: useSSL);
    await smtp.ehlo();
    if (!useSSL) await smtp.startTls();
    if (cfg.authKind == AuthKind.oauth2) {
      await smtp.authenticate(cfg.email, cfg.oauthAccessToken ?? '', em.AuthMechanism.xoauth2);
    } else {
      await smtp.authenticate(cfg.email, cfg.password ?? '', em.AuthMechanism.plain);
    }
    await smtp.sendMessage(mime);
    log.info(_t, 'SMTP: письмо отправлено');
    try { await smtp.disconnect(); } catch (_) {}
  }

  @override
  Future<void> applyFlags(MessageRef ref, {bool? read, bool? flagged}) async {
    final client = _imap;
    if (client == null) return;
    await client.selectMailboxByPath(ref.folderId);
    final uid = ref.uid ?? int.tryParse(ref.id.split(':').last) ?? 0;
    final seq = em.MessageSequence.fromId(uid, isUid: true);
    if (read != null) {
      // UID-команды: обычные store/move работают по порядковым номерам —
      // UID 5023 в папке из 300 писем дал бы ошибку, а малый UID пометил бы
      // ЧУЖОЕ письмо.
      await client.uidStore(seq, [r'\Seen'],
          action: read ? em.StoreAction.add : em.StoreAction.remove, silent: true);
    }
    if (flagged != null) {
      await client.uidStore(seq, [r'\Flagged'],
          action: flagged ? em.StoreAction.add : em.StoreAction.remove, silent: true);
    }
  }

  @override
  Future<void> move(MessageRef ref, String toFolderId) async {
    final client = _imap;
    if (client == null) return;
    await client.selectMailboxByPath(ref.folderId);
    final uid = ref.uid ?? int.tryParse(ref.id.split(':').last) ?? 0;
    final seq = em.MessageSequence.fromId(uid, isUid: true);
    if (client.serverInfo.supportsMove) {
      await client.uidMove(seq, targetMailboxPath: toFolderId);
    } else {
      await client.uidCopy(seq, targetMailboxPath: toFolderId);
      await client.uidStore(seq, [r'\Deleted'], action: em.StoreAction.add, silent: true);
      if (client.serverInfo.supportsUidPlus) await client.uidExpunge(seq);
    }
  }

  @override
  Future<void> delete(MessageRef ref) async {
    final client = _imap;
    if (client == null) return;
    await client.selectMailboxByPath(ref.folderId);
    final uid = ref.uid ?? int.tryParse(ref.id.split(':').last) ?? 0;
    final seq = em.MessageSequence.fromId(uid, isUid: true);
    await client.uidStore(seq, [r'\Deleted'], action: em.StoreAction.add, silent: true);
    // Полный EXPUNGE стёр бы все помеченные письма папки, не только это.
    if (client.serverInfo.supportsUidPlus) await client.uidExpunge(seq);
  }

  @override
  Future<void> dispose() async {
    try { await _imap?.disconnect(); } catch (_) {}
    _imap = null;
  }

  @override
  Future<List<PimItem>> syncPim(String folderId,
      {required String dataClass, SyncState? since}) async {
    // У протокола IMAP нет PIM (календарь/контакты/задачи передаются отдельными
    // протоколами CalDAV/CardDAV, не входящими в этот движок). Поэтому корректный
    // результат — пустой список, а не ошибка: почта работает, PIM просто отсутствует.
    return const [];
  }
}

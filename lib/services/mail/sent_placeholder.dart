// lib/services/mail/sent_placeholder.dart
//
// Отправленное письмо — сразу в беседе, с текстом (1.7.1 — для быстрого
// ответа; 2.6.8 — и для письма из редактора).
//
// Замечание владельца 21.11.2026: «карточки в беседах иногда новые верхние
// письма отображают пустыми, а потом подгружают. Часто если только
// отправил». Копия в «Отправленных» приходит с сервера через несколько
// секунд и у IMAP — только заголовками (текст догружается позже и пишется в
// базу без оповещения списков). Поэтому:
// - временная строка «qr_…» в «Отправленных» с беседой исходного письма и
//   текстом — для быстрого ответа и для ответа из редактора;
// - когда пришла серверная копия, строка убирается, а её превью
//   переходит в серверную копию, если у той текста ещё нет
//   ([SentPlaceholder.dropReplaced]).

import 'dart:convert' show jsonEncode;

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/mail_body_processor.dart';
import '../../core/utils/text_safe.dart' show cutSafe, previewOf;
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart' show FolderType;

class SentPlaceholder {
  SentPlaceholder._();

  /// Префикс id временных строк (письма только на устройстве).
  static const prefix = 'qr_';

  /// Сколько живёт временная строка, если серверная копия так и не пришла.
  static const ttl = Duration(minutes: 30);

  /// Беседа письма, на которое отвечают, по его Message-ID; нет — null.
  static Future<String?> conversationOf(AppDatabase db, String accountId, String? inReplyTo) async {
    // Бывает цепочкой «References родителя + его Message-ID» — берём
    // последний (письмо, на которое отвечают).
    final parts = (inReplyTo ?? '').trim().split(RegExp(r'\s+')).where((p) => p.contains('@')).toList();
    if (parts.isEmpty) return null;
    final id = parts.last.replaceAll(RegExp(r'^<|>$'), '');
    final r = await db.customSelect(
      'SELECT conversation_id AS c FROM emails WHERE account_id = ? AND internet_message_id IN (?, ?) '
      "AND conversation_id IS NOT NULL AND conversation_id != '' LIMIT 1",
      variables: [Variable.withString(accountId), Variable.withString(id), Variable.withString('<$id>')],
      readsFrom: {db.emails},
    ).getSingleOrNull();
    return r?.read<String?>('c');
  }

  /// Превью из HTML письма: начало нового текста (цитата — ниже).
  static String previewFromHtml(String html) =>
      previewOf(MailBodyProcessor.htmlToPlain(cutSafe(html, 60000))) ?? '';

  /// Временная строка отправленного письма в «Отправленных» беседы
  /// [conversationId]. Без папки «Отправленные» — ничего.
  static Future<void> insert(
    AppDatabase db,
    AccountModel account, {
    required String? conversationId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    required String subject,
    required String html,
    String? text,
    bool hasAttachments = false,
  }) async {
    try {
      final sent = await (db.select(db.folders)
            ..where((f) => f.accountId.equals(account.id) & f.type.equals(FolderType.sent.index))
            ..limit(1))
          .getSingleOrNull();
      if (sent == null) return;
      final now = DateTime.now();
      List<Map<String, String?>> addrs(List<EmailAddress> l) =>
          [for (final a in l) {'email': a.email, 'displayName': a.displayName}];
      final t = (text ?? '').trim();
      final preview = t.isNotEmpty ? (t.length > 200 ? cutSafe(t, 200) : t) : previewFromHtml(html);
      await db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
            id: '$prefix${now.microsecondsSinceEpoch}',
            accountId: account.id,
            folderId: sent.id,
            folderName: Value(sent.displayName),
            conversationId: Value(conversationId),
            fromEmail: account.sharedMailboxEmail?.isNotEmpty == true ? account.sharedMailboxEmail! : account.email,
            fromName: Value(account.displayName),
            toRecipients: jsonEncode(addrs(to)),
            ccJson: Value(cc.isEmpty ? null : jsonEncode(addrs(cc))),
            subject: subject,
            bodyHtml: Value(html),
            bodyPreview: Value(preview),
            hasAttachments: Value(hasAttachments),
            receivedAt: now,
            sentAt: Value(now),
            isRead: const Value(true),
            loadedLevel: const Value(3),
            cachedAt: Value(now),
          ));
    } catch (e) {
      AppLogger.debug('Отправленное письмо в беседе: $e');
    }
  }

  /// Убрать временные строки, для которых пришла серверная копия (то же
  /// письмо в той же папке: тема и время), и в любом случае через [ttl].
  /// Превью временной строки переходит в серверную копию, если у той его
  /// ещё нет: карточка беседы не пустеет, пока текст догружается.
  /// Возвращает, сколько временных строк осталось.
  static Future<int> dropReplaced(AppDatabase db, String accountId, {DateTime? now}) async {
    final rows = await db.customSelect(
      'SELECT id, folder_id, subject, received_at, body_preview FROM emails '
      "WHERE account_id = ? AND id LIKE 'qr\\_%' ESCAPE '\\'",
      variables: [Variable.withString(accountId)],
      readsFrom: {db.emails},
    ).get();
    var left = 0;
    final t = now ?? DateTime.now();
    for (final r in rows) {
      final id = r.read<String>('id');
      final at = r.read<DateTime>('received_at');
      var drop = t.difference(at) > ttl;
      if (!drop) {
        final real = await db.customSelect(
          "SELECT id, body_preview FROM emails WHERE account_id = ? AND folder_id = ? AND id NOT LIKE 'qr\\_%' ESCAPE '\\' "
          'AND lower(subject) = lower(?) AND received_at >= ? ORDER BY received_at ASC LIMIT 1',
          variables: [
            Variable.withString(accountId),
            Variable.withString(r.read<String>('folder_id')),
            Variable.withString(r.read<String>('subject')),
            Variable.withDateTime(at.subtract(const Duration(minutes: 5))),
          ],
          readsFrom: {db.emails},
        ).getSingleOrNull();
        if (real != null) {
          drop = true;
          final mine = (r.read<String?>('body_preview') ?? '').trim();
          if (mine.isNotEmpty && (real.read<String?>('body_preview') ?? '').trim().isEmpty) {
            await db.customUpdate(
              "UPDATE emails SET body_preview = ? WHERE account_id = ? AND id = ? AND (body_preview IS NULL OR body_preview = '')",
              variables: [Variable.withString(mine), Variable.withString(accountId), Variable.withString(real.read<String>('id'))],
              updates: {db.emails},
              updateKind: UpdateKind.update,
            );
          }
        }
      }
      if (drop) {
        await (db.delete(db.emails)..where((e) => e.id.equals(id) & e.accountId.equals(accountId))).go();
      } else {
        left++;
      }
    }
    return left;
  }
}

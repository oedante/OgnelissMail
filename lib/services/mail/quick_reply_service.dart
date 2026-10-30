// lib/services/mail/quick_reply_service.dart
// Быстрый ответ письмом без редактора (1.6.49): из уведомления и из строки
// «Ответить…» внизу письма (как поле ввода в Telegram). Письмо, а не «СМС»
// (09.10.2026): приветствие, текст отдельным абзацем, подпись ящика для
// ответов. Через очередь отправки: без связи ответ уйдёт позже, а не
// пропадёт. Цепочка — References исходного письма и его Message-ID.

import 'dart:convert' show HtmlEscape, jsonEncode;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/subject_prefix.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;

import '../../data/database/app_database.dart' show Email, EmailsCompanion;
import '../../data/models/account_model.dart';
import '../../data/models/folder_model.dart' show FolderType;
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import 'offline_send_service.dart';
import 'signature_service.dart' show SignatureService;
import '../../core/utils/greeting_helper.dart';
import '../../l10n/strings_store.dart' show StringsStore;
import 'greeting_history.dart';
import 'greeting_mode.dart';
import 'own_addresses.dart';

class QuickReplyService {
  QuickReplyService(this._ref);
  final Ref _ref;

  /// Отправить ответ. true — ушёл сразу, false — в очереди (нет сети).
  /// Ошибка — исключение.
  Future<bool> send({
    required AccountModel account,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    required String subject,
    required String text,
    String? originalEmailId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final db = _ref.read(databaseProvider);
    Email? parent;
    if (originalEmailId != null) {
      try {
        parent = await db.getEmailById(originalEmailId, accountId: account.id);
      } catch (_) {}
    }
    final greeting = await _greeting(account, to, parent, prefs);
    final signature = await SignatureService.replySignatureHtml(db, prefs, account) ??
        const HtmlEscape().convert(account.displayName);
    final body = const HtmlEscape().convert(text.trim()).replaceAll('\n', '<br>');
    final html = '<html><body>'
        '${greeting.isEmpty ? '' : '<div>${const HtmlEscape().convert(greeting)}</div><div><br></div>'}'
        '<div>$body</div><div><br></div>'
        '<div>$signature</div>'
        '</body></html>';
    // Цепочка «References родителя + его Message-ID» (1.8.13), как у ответа
    // из редактора: с одним Message-ID родителя ответ в длинной переписке
    // уходил в отдельную беседу — и у нас, и у получателей.
    String? messageId;
    final mid = parent?.internetMessageId?.trim();
    if (mid != null && mid.contains('@')) {
      final refs = parent?.referencesStr?.trim() ?? '';
      messageId = refs.isEmpty ? mid : '$refs $mid';
    }
    final sent = await _ref.read(offlineSendProvider).sendOrQueue(
          accountId: account.id,
          to: to,
          cc: cc,
          subject: SubjectPrefix.reply(subject),
          bodyHtml: html,
          inReplyTo: messageId,
        );
    AppLogger.info(sent ? 'Быстрый ответ отправлен' : 'Быстрый ответ — в очереди (нет сети)');
    if (sent) {
      await _showInConversation(account, originalEmailId,
          to: to, cc: cc, subject: SubjectPrefix.reply(subject), html: html, text: text.trim());
    }
    return sent;
  }

  /// Ответ — сразу в беседе (1.7.1, замечание владельца 20.10.2026: «не
  /// засчитывается — надо перезаходить в переписку»): копия в «Отправленных»
  /// приходит с сервера через несколько секунд, а до тех пор — временная
  /// строка «qr_…» в «Отправленных» с беседой исходного письма. Её убирает
  /// SyncService.dropQuickReplyPlaceholders, когда пришла серверная копия.
  /// Исходное письмо — «Отвечено».
  Future<void> _showInConversation(AccountModel account, String? originalEmailId,
      {required List<EmailAddress> to,
      required List<EmailAddress> cc,
      required String subject,
      required String html,
      required String text}) async {
    try {
      final db = _ref.read(databaseProvider);
      final orig = originalEmailId == null ? null : await db.getEmailById(originalEmailId, accountId: account.id);
      if (orig != null) {
        await (db.update(db.emails)
              ..where((e) => e.id.equals(orig.id) & e.accountId.equals(account.id)))
            .write(const EmailsCompanion(isReplied: Value(true)));
      }
      final sent = await (db.select(db.folders)
            ..where((f) => f.accountId.equals(account.id) & f.type.equals(FolderType.sent.index))
            ..limit(1))
          .getSingleOrNull();
      if (sent == null) return;
      final sentId = sent.id;
      final now = DateTime.now();
      List<Map<String, String?>> addrs(List<EmailAddress> l) =>
          [for (final a in l) {'email': a.email, 'displayName': a.displayName}];
      await db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
            id: 'qr_${now.microsecondsSinceEpoch}',
            accountId: account.id,
            folderId: sentId,
            folderName: Value(sent.displayName),
            conversationId: Value(orig?.conversationId),
            fromEmail: account.sharedMailboxEmail?.isNotEmpty == true ? account.sharedMailboxEmail! : account.email,
            fromName: Value(account.displayName),
            toRecipients: jsonEncode(addrs(to)),
            ccJson: Value(cc.isEmpty ? null : jsonEncode(addrs(cc))),
            subject: subject,
            bodyHtml: Value(html),
            bodyPreview: Value(text.length > 200 ? text.substring(0, 200) : text),
            receivedAt: now,
            sentAt: Value(now),
            isRead: const Value(true),
            loadedLevel: const Value(3),
            cachedAt: Value(now),
          ));
    } catch (e) {
      AppLogger.debug('Быстрый ответ в беседе: $e');
    }
  }

  /// Приветствие быстрого ответа — как в редакторе письма (1.7.3): по
  /// настройке ящика (нет, «Добрый день!», «Добрый день, Имя Отчество,»),
  /// в переписке, где вы уже писали, — короткое «Имя Отчество,»; на языке
  /// приложения или адресата. '' — без приветствия.
  Future<String> _greeting(AccountModel account, List<EmailAddress> to, Email? parent, SharedPreferences prefs) async {
    final mode = _ref.read(greetingModeProvider.notifier).of(account.id);
    if (mode == GreetingMode.off) return '';
    GreetingSet build() => GreetingHelper.variants(
          names: [for (final a in to) a.displayName ?? ''],
          emails: [for (final a in to) a.email],
          appLang: SignatureService.appLanguage(prefs),
          ownDomains: OwnAddresses.domains(account),
        );
    var set = build();
    if (!StringsStore.isLoaded(set.lang)) {
      await StringsStore.ensure(set.lang);
      set = build();
    }
    if (mode == GreetingMode.hello) return set.hello;
    final wrote = parent != null && await GreetingHistory.wroteBefore(_ref.read(databaseProvider), account, parent);
    return set.text(wrote ? GreetingVariant.short : GreetingVariant.full);
  }
}

final quickReplyServiceProvider = Provider<QuickReplyService>((ref) => QuickReplyService(ref));

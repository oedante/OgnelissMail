// lib/services/calendar/meeting_prep.dart
// «Подготовиться к совещанию» (сценарий из docs/plan/IDEAS_LIVING_MAIL.md,
// раздел 5; 10.10.2026): в карточке встречи — письма по её теме с
// участниками за 30 дней и вложения из них. Раньше перед совещанием письма
// приходилось искать вручную по каждому участнику.
//
// Всё локально, один ограниченный запрос к базе (письма ящика встречи за
// 30 дней с той же темой переписки или из той же беседы, не больше 400) и
// отбор в памяти. С 1.6.12 — тема как у бесед, а не отдельные слова темы. Выключатель — «Настройки → Календарь → День и календарь» (`meeting_prep_on`).

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider, emailModelFromRow;

/// Письмо-кандидат: только то, что нужно для оценки (без тела).
class PrepCandidate {
  final String id;
  final String accountId;
  final String fromEmail;
  final String fromName;
  final String subject;
  final DateTime receivedAt;
  final List<String> recipients;
  final List<EmailAttachment> attachments;
  final String? conversationId;

  const PrepCandidate({
    required this.id,
    required this.accountId,
    required this.fromEmail,
    this.fromName = '',
    required this.subject,
    required this.receivedAt,
    this.recipients = const [],
    this.attachments = const [],
    this.conversationId,
  });
}

/// Итог для карточки встречи.
class MeetingPrepResult {
  final List<PrepCandidate> mails;
  /// Вложения из этих писем (без встроенных картинок), с письмом-источником.
  final List<({EmailAttachment file, PrepCandidate mail})> files;
  const MeetingPrepResult(this.mails, this.files);
  bool get isEmpty => mails.isEmpty;
}

class MeetingPrep {
  MeetingPrep._();

  static const prefKey = 'meeting_prep_on';
  static const window = Duration(days: 30);

  /// Приставки ответа и пересылки, а также служебные приставки приглашений
  /// Outlook («Приглашение:», «Обновлено:», «Принято:» …).
  static final _prefix = RegExp(
      r'^\s*((re|fw|fwd|aw|wg|tr|отв|пересл|ответ)\s*(\[\d+\])?\s*:'
      r'|(приглашение|обновлено|обновленное приглашение|отменено|принято|отклонено|под вопросом|предварительно'
      r'|invitation|updated invitation|canceled|cancelled|accepted|declined|tentative'
      r'|einladung|aktualisiert|abgesagt|angenommen|abgelehnt|mit vorbehalt'
      r'|invitation mise à jour|annulé|accepté|refusé|provisoire)\s*:\s*)+',
      caseSensitive: false);
  static final _split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Тема переписки, как при группировке бесед (1.6.12, замечание
  /// 16.10.2026: письма подбирались по отдельным словам темы, и в «К
  /// встрече» попадало много лишнего): без «RE:/FW:» и приставок
  /// приглашений, без регистра, лишних пробелов и знаков по краям.
  static String topicKey(String subject) {
    var t = subject;
    for (var i = 0; i < 5; i++) {
      final next = t.replaceFirst(_prefix, '');
      if (next == t) break;
      t = next;
    }
    return t
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true), '');
  }

  /// Тема переписки та же, что у встречи.
  static bool sameTopic(String subject, String key) => key.isNotEmpty && topicKey(subject) == key;

  /// Слово темы для предварительного отбора в базе (самое длинное).
  static String? probeWord(String key) {
    final words = [for (final w in key.split(_split)) if (w.length >= 3) w]
      ..sort((a, b) => b.length.compareTo(a.length));
    return words.isEmpty ? null : words.first;
  }

  /// Письма к встрече: та же тема переписки или та же беседа (по
  /// идентификатору беседы сервера), новые сверху.
  static List<PrepCandidate> rank(List<PrepCandidate> all,
      {required String key, Set<String> conversations = const {}, int limit = 8}) {
    final out = [
      for (final c in all)
        if (sameTopic(c.subject, key) ||
            (c.conversationId != null && conversations.contains(c.conversationId)))
          c,
    ]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return out.take(limit).toList();
  }

  /// Вложения из писем (до [limit]), без встроенных картинок и повторов.
  static List<({EmailAttachment file, PrepCandidate mail})> files(List<PrepCandidate> mails, {int limit = 8}) {
    final out = <({EmailAttachment file, PrepCandidate mail})>[];
    final names = <String>{};
    for (final m in mails) {
      for (final a in m.attachments) {
        if (a.isInline && a.mimeType.toLowerCase().startsWith('image/')) continue;
        if (a.isInline && a.mimeType.isEmpty && RegExp(r'\.(png|jpe?g|gif|bmp)$', caseSensitive: false).hasMatch(a.name)) continue;
        if (a.name.trim().isEmpty) continue;
        if (!names.add(a.name.toLowerCase())) continue;
        out.add((file: a, mail: m));
        if (out.length >= limit) return out;
      }
    }
    return out;
  }
}

/// Письма к встрече (ключ — id встречи и ящик). Пусто, если функция
/// выключена или подходящих писем нет.
final meetingPrepProvider =
    FutureProvider.autoDispose.family<MeetingPrepResult, CalendarEvent>((ref, e) async {
  const empty = MeetingPrepResult([], []);
  if (ref.read(sharedPrefsProvider).getBool(MeetingPrep.prefKey) == false) return empty;
  final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
  if (account == null) return empty;
  final key = MeetingPrep.topicKey(e.title);
  final db = ref.read(databaseProvider);

  // Беседа письма, из которого создана встреча, — тоже к встрече.
  final conversations = <String>{};
  final linked = e.linkedEmailId;
  if (linked != null && linked.isNotEmpty) {
    final row = await (db.select(db.emails)
          ..where((m) => m.accountId.equals(account.id) & m.id.equals(linked)))
        .getSingleOrNull();
    final conv = row?.conversationId;
    if (conv != null && conv.isNotEmpty) conversations.add(conv);
  }
  final word = MeetingPrep.probeWord(key);
  if (word == null && conversations.isEmpty) return empty;

  final since = DateTime.now().subtract(MeetingPrep.window);
  Expression<bool> cond = const Constant(false);
  if (word != null) cond = cond | db.emails.subject.lower().like('%$word%');
  if (conversations.isNotEmpty) cond = cond | db.emails.conversationId.isIn(conversations);
  final rows = await (db.select(db.emails)
        ..where((m) =>
            m.accountId.equals(account.id) &
            m.receivedAt.isBiggerOrEqualValue(since) &
            m.isDraft.equals(false) &
            m.meetingJson.isNull())
        ..where((_) => cond)
        ..orderBy([(m) => OrderingTerm(expression: m.receivedAt, mode: OrderingMode.desc)])
        ..limit(400))
      .get();
  // Корзина и спам — не к встрече.
  final skip = {
    await db.folderIdOfType(account.id, FolderType.trash.index),
    await db.folderIdOfType(account.id, FolderType.junk.index),
  }..remove(null);
  final candidates = <PrepCandidate>[];
  for (final r in rows) {
    if (skip.contains(r.folderId) || r.id == e.linkedEmailId) continue;
    final m = emailModelFromRow(r);
    candidates.add(PrepCandidate(
      id: m.id,
      accountId: m.accountId,
      fromEmail: m.from.email,
      fromName: m.from.label,
      subject: m.subject,
      receivedAt: m.receivedAt,
      recipients: [for (final a in [...m.to, ...m.cc]) a.email],
      attachments: m.attachments,
      conversationId: r.conversationId,
    ));
  }
  // Беседы найденных по теме писем — тоже (тему в ответе могли изменить).
  for (final c in candidates) {
    if (MeetingPrep.sameTopic(c.subject, key) && c.conversationId != null) conversations.add(c.conversationId!);
  }
  final ranked = MeetingPrep.rank(candidates, key: key, conversations: conversations);
  return MeetingPrepResult(ranked, MeetingPrep.files(ranked));
});

// lib/services/mail/control_service.dart
// «На контроле»: письма, которые пользователь сам отметил, — «жду ответа»
// (моё письмо) и «должен ответить» (входящее). При синхронизации проверяется,
// пришёл ли ответ или ответил ли я; тогда отметка становится «Исполнено».
// Снимает её пользователь.
//
// Нагрузка: письма выбираются по частичному индексу idx_emails_control (их
// единицы), на каждое — один-два запроса по беседе (idx_emails_conversation)
// или по заголовкам References, если сервер не дал беседу.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart';

class ControlState {
  static const none = 0;
  static const awaitingReply = 1;
  static const mustReply = 2;
  static const done = 3;

  static bool isActive(int s) => s == awaitingReply || s == mustReply;
}

class ControlService {
  /// Адресаты «Кому» письма без меня (копия не считается) — в нижнем регистре.
  /// [myEmail] — адрес ящика или несколько через запятую (все адреса
  /// владельца: адрес входа, основной с сервера, алиасы — own_addresses.dart).
  static Set<String> mineOf(String myEmail) =>
      {for (final p in myEmail.split(',')) if (p.trim().isNotEmpty) p.trim().toLowerCase()};

  static List<String> toRecipients(String? toJson, String myEmail) {
    if (toJson == null || toJson.isEmpty) return const [];
    final mine = mineOf(myEmail);
    try {
      return {
        for (final m in (jsonDecode(toJson) as List).whereType<Map>())
          if ((m['email'] ?? '').toString().trim().isNotEmpty &&
              !mine.contains((m['email'] as String).trim().toLowerCase()))
            (m['email'] as String).trim().toLowerCase(),
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Ответившие из «Кому»: сохранённая строка → множество адресов.
  static Set<String> repliedSet(String? saved) =>
      {for (final a in (saved ?? '').split(',')) if (a.trim().isNotEmpty) a.trim().toLowerCase()};

  /// Доля ответивших (0…1) для круга в ленте; null — один адресат или не
  /// «жду ответа».
  static ({int replied, int total})? progress(
      {required int state, required List<String> to, required String? replied}) {
    if (state != ControlState.awaitingReply || to.length < 2) return null;
    final r = repliedSet(replied);
    return (replied: to.where(r.contains).length, total: to.length);
  }

  /// Проверить активные отметки. [accountEmails] — адрес каждого ящика.
  /// Возвращает число писем, ставших «Исполнено».
  ///
  /// «Жду ответа» (моё письмо): исполнено, когда ответили все из «Кому»
  /// (копия не считается); одному адресату — любой ответ в беседе (ответить
  /// может и коллега из группы рассылки). Промежуточно сохраняется, кто уже
  /// ответил, — в ленте круг заполняется по доле.
  /// «Нужно ответить» (входящее): исполнено, когда ответил я.
  static Future<int> check(AppDatabase db, Map<String, String> accountEmails) async {
    var done = 0;
    var changed = 0;
    try {
      final list = await db.controlledEmails(activeOnly: true);
      for (final e in list) {
        final me = accountEmails[e.accountId] ?? '';
        if (me.isEmpty) continue;
        final mid = e.internetMessageId;
        bool resolved;
        if (e.controlState == ControlState.awaitingReply) {
          final repliers = await db.repliersTo(
              accountId: e.accountId,
              conversationId: e.conversationId,
              messageId: mid,
              after: e.receivedAt,
              myEmail: me);
          final to = toRecipients(e.toRecipients, me);
          if (to.length < 2) {
            resolved = repliers.isNotEmpty;
          } else {
            final replied = to.where(repliers.contains).toList();
            resolved = replied.length == to.length;
            final saved = replied.isEmpty ? null : replied.join(',');
            if (!resolved && saved != e.controlReplied) {
              await db.setControlReplied(e.id, e.accountId, saved);
              changed++;
            }
            if (resolved) await db.setControlReplied(e.id, e.accountId, replied.join(','));
          }
        } else {
          resolved = e.isReplied ||
              await db.hasMyReplyInConversation(
                  accountId: e.accountId, conversationId: e.conversationId, after: e.receivedAt, myEmail: me) ||
              (mid != null &&
                  await db.hasReplyByMessageId(
                      accountId: e.accountId, messageId: mid, after: e.receivedAt, myEmail: me, fromMe: true));
        }
        if (resolved) {
          await db.setControlState(e.id, e.accountId, ControlState.done);
          done++;
        }
      }
      if (done > 0) AppLogger.info('На контроле: исполнено $done');
      if (changed > 0) AppLogger.info('На контроле: ответили не все — обновлено писем: $changed');
    } catch (err) {
      AppLogger.warning('На контроле — проверка: $err');
    }
    lastChanges = done + changed;
    return done;
  }

  /// Сколько отметок изменила последняя проверка (лента перечитывает их).
  static int lastChanges = 0;

  /// Состояние при постановке на контроль: своё письмо — «жду ответа»;
  /// чужое, где я в «Кому», — «должен ответить»; чужое, где я только в
  /// копии, — тоже «жду ответа»: отвечать должны адресаты, а я жду
  /// (замечание 10.10.2026). [to] — адреса «Кому»; null — не проверять.
  static int initialFor({required String fromEmail, required String myEmail, List<String>? to}) {
    final mine = mineOf(myEmail);
    if (mine.contains(fromEmail.trim().toLowerCase())) return ControlState.awaitingReply;
    if (to != null && to.isNotEmpty && !to.any((a) => mine.contains(a.trim().toLowerCase()))) {
      return ControlState.awaitingReply;
    }
    return ControlState.mustReply;
  }

  // ── «На контроле» при отправке ──
  //
  // Id отправленного письма заранее неизвестен (его даёт сервер). Окно
  // письма запоминает тему, первого адресата и время; когда письмо
  // появляется в «Отправленных», оно получает отметку «жду ответа».

  static const _pendingKey = 'control_pending_v1';

  static Future<void> addPending({
    required String accountId,
    required String subject,
    required String firstTo,
    DateTime? notBefore,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = _readPending(p);
      list.add({
        'a': accountId,
        's': _norm(subject),
        't': firstTo.trim().toLowerCase(),
        'at': (notBefore ?? DateTime.now()).millisecondsSinceEpoch,
      });
      await p.setString(_pendingKey, jsonEncode(list));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> _readPending(SharedPreferences p) {
    try {
      final raw = p.getString(_pendingKey);
      if (raw == null) return [];
      final now = DateTime.now().millisecondsSinceEpoch;
      // Старше трёх дней от планового времени — уже не найдётся.
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => now - (e['at'] as int) < const Duration(days: 3).inMilliseconds)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Новые письма папки «Отправленные»: совпавшие с отправленными «на
  /// контроле» получают отметку «жду ответа».
  static Future<void> matchSent(AppDatabase db, String accountId, List<EmailModel> sent) async {
    if (sent.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = _readPending(p);
      if (!list.any((e) => e['a'] == accountId)) return;
      var changed = false;
      for (final m in sent) {
        final subj = _norm(m.subject);
        final to = m.to.isEmpty ? '' : m.to.first.email.trim().toLowerCase();
        final i = list.indexWhere((e) =>
            e['a'] == accountId &&
            e['s'] == subj &&
            e['t'] == to &&
            m.receivedAt.millisecondsSinceEpoch >= (e['at'] as int) - const Duration(minutes: 5).inMilliseconds);
        if (i < 0) continue;
        await db.setControlState(m.id, accountId, ControlState.awaitingReply);
        list.removeAt(i);
        changed = true;
      }
      if (changed) await p.setString(_pendingKey, jsonEncode(list));
    } catch (err) {
      AppLogger.debug('На контроле — отправленные: $err');
    }
  }
}

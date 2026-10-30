// lib/services/mail/thread_linker.dart
// Беседы IMAP по ссылкам на письма (1.8.13, замечание владельца 29.10.2026:
// «не всегда складываются темы»).
//
// Беседа письма IMAP — первый Message-ID из References (imapConversationId).
// Этого мало, когда цепочка рвётся:
//  · Outlook и Exchange пишут в References только родителя, а не всю
//    цепочку: ответ из Outlook на третье письмо переписки получал «беседой»
//    второе письмо и уходил в отдельную строку ленты;
//  · часть программ ставит только In-Reply-To;
//  · начало переписки не загружено (старше периода синхронизации), а ответы
//    ссылаются на разные письма середины.
// Теперь письмо встаёт в беседу любого известного письма, на которое
// ссылается (References и In-Reply-To), а беседы, которые оно связало,
// сливаются в одну. Ответ без заголовков цепочки (веб-формы, часть
// телефонов) — по теме без «RE:/FW:» и собеседнику в пределах 30 дней.
// Собеседник — не я: свои адреса ящика (OwnAddresses, с алиасами iCloud,
// Gmail и Яндекса) в сравнении не участвуют. Иначе любые два письма на мой
// адрес «совпадали» бы, а с неузнанным алиасом — наоборот, не совпадало бы
// ничего.

import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/subject_prefix.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import 'own_addresses.dart';

/// Письмо для раскладки по беседам — только то, что нужно для связей.
class ThreadMsg {
  final String id;
  final String? messageId;

  /// References и In-Reply-To по порядку: от начала переписки к родителю.
  final List<String> refs;

  /// Беседа по заголовкам (imapConversationId).
  final String? conv;
  final String subject;
  final DateTime at;

  /// Отправитель в нижнем регистре.
  final String from;

  /// Все участники (отправитель, «Кому», «Копия») в нижнем регистре.
  final Set<String> people;

  const ThreadMsg({
    required this.id,
    required this.messageId,
    required this.refs,
    required this.conv,
    required this.subject,
    required this.at,
    required this.from,
    required this.people,
  });

  factory ThreadMsg.of(EmailModel e) => ThreadMsg(
        id: e.id,
        messageId: e.internetMessageId?.trim(),
        refs: [for (final r in e.references ?? const <String>[]) if (r.trim().isNotEmpty) r.trim()],
        conv: e.conversationId,
        subject: e.subject,
        at: e.receivedAt,
        from: e.from.email.trim().toLowerCase(),
        people: {
          for (final a in [e.from, ...e.to, ...e.cc])
            if (a.email.trim().isNotEmpty) a.email.trim().toLowerCase(),
        },
      );

  /// Ответ или пересылка по теме («RE:», «FW:», «Ответ:», «AW:»…).
  bool get isReplyBySubject => SubjectPrefix.strip(subject) != subject.trim();

  /// Тема без префиксов ответа — ключ для писем без заголовков цепочки.
  String get topic => SubjectPrefix.strip(subject).toLowerCase();
}

/// Результат раскладки: беседа каждого нового письма и беседы в базе,
/// которые нужно переименовать (слить) — старое имя → новое.
class ThreadPlan {
  final Map<String, String> conv;
  final Map<String, String> merge;
  const ThreadPlan(this.conv, this.merge);
}

class ThreadLinker {
  ThreadLinker._();

  /// Окно поиска беседы по теме: ответ без заголовков — не позже месяца.
  static const topicWindow = Duration(days: 30);

  /// Писем без заголовков цепочки, для которых за один проход ищется
  /// беседа по теме (первая загрузка ящика — тысячи писем).
  static const maxTopicLookups = 40;

  /// Раскладка касается ящиков, беседы которых считает приложение (IMAP,
  /// Gmail, Яндекс, Mail.ru…). У Exchange беседу задаёт сервер.
  static bool appliesTo(AccountModel a) => !a.usesEas && !a.usesEws && !a.isExchange;

  /// Беседы новых писем по ссылкам. [known] — Message-ID → беседа писем,
  /// уже лежащих в базе; [childConv] — беседы писем базы, начатые id
  /// нового письма (ответ пришёл раньше письма, на которое отвечает).
  /// Письма разбираются от старых к новым: родитель из того же пакета
  /// известен раньше ответа.
  static ThreadPlan plan(
    List<ThreadMsg> incoming, {
    Map<String, String> known = const {},
    Set<String> childConv = const {},
  }) {
    final byMid = <String, String>{...known};
    final out = <String, String>{};
    final merge = <String, String>{};

    // Беседа с учётом уже назначенных слияний (цепочка a→b→c).
    String resolve(String c) {
      var cur = c;
      for (var i = 0; i < 16; i++) {
        final next = merge[cur];
        if (next == null || next == cur) return cur;
        cur = next;
      }
      return cur;
    }

    final list = [...incoming]..sort((a, b) => a.at.compareTo(b.at));
    for (final m in list) {
      // Ссылки — по порядку, от начала переписки: первая известная —
      // самая ранняя беседа.
      final linked = <String>[];
      for (final r in m.refs) {
        final c = byMid[r];
        if (c != null) linked.add(resolve(c));
      }
      final own = m.messageId;
      // Ответ, пришедший раньше этого письма, начал беседу его id.
      final startedByMe = own != null && childConv.contains(own) ? own : null;
      final base = m.conv ?? own ?? m.id;
      final target = linked.isNotEmpty ? linked.first : resolve(base);
      for (final c in {...linked, resolve(base), if (startedByMe != null) resolve(startedByMe)}) {
        if (c != target) merge[c] = target;
      }
      out[m.id] = target;
      if (own != null && own.isNotEmpty) byMid[own] = target;
    }
    // Слияния, назначенные позже, — и для уже разложенных писем пакета.
    return ThreadPlan({for (final e in out.entries) e.key: resolve(e.value)},
        {for (final e in merge.entries) if (resolve(e.value) != e.key) e.key: resolve(e.value)});
  }

  /// Подходит ли [c] к письму [m] без заголовков цепочки: та же тема и
  /// общий собеседник — не я. [own] — свои адреса ящика.
  static bool sameTopicPeer(ThreadMsg m, ThreadMsg c, Set<String> own) {
    if (m.topic.isEmpty || m.topic != c.topic) return false;
    if (c.at.isAfter(m.at.add(const Duration(days: 1))) || m.at.difference(c.at) > topicWindow) return false;
    final mMine = own.contains(m.from);
    final cMine = own.contains(c.from);
    final mPeople = m.people.difference(own);
    final cPeople = c.people.difference(own);
    // Чужое письмо: автор участвовал в найденном письме.
    if (!mMine) return cPeople.contains(m.from);
    // Мой ответ: автору найденного письма или тем же людям, что мое прежнее.
    if (!cMine) return mPeople.contains(c.from);
    return mPeople.intersection(cPeople).isNotEmpty;
  }

  /// Разложить новые письма ящика по беседам (перед записью в базу) и
  /// слить в базе беседы, которые они связали. Возвращает письма с
  /// беседой; ошибка — письма как были (беседа по заголовкам).
  static Future<List<EmailModel>> link(AppDatabase db, AccountModel account, List<EmailModel> emails) async {
    if (emails.isEmpty || !appliesTo(account)) return emails;
    try {
      final msgs = [for (final e in emails) ThreadMsg.of(e)];
      final refs = <String>{for (final m in msgs) ...m.refs};
      final mids = <String>{for (final m in msgs) if ((m.messageId ?? '').isNotEmpty) m.messageId!};
      final known = await _convByMessageId(db, account.id, refs);
      final childConv = await _existingConv(db, account.id, mids);
      var plan = ThreadLinker.plan(msgs, known: known, childConv: childConv);

      // Ответы без заголовков цепочки — по теме и собеседнику. Письмо со
      // ссылками на письма, которых в базе ещё нет, ждёт их: исходное
      // загрузится позже (история, «Отправленные» после «Входящих») и
      // соберёт беседу по ссылкам. По теме такой ответ прилип бы к прежней
      // переписке с тем же человеком и той же темой, а исходное письмо
      // осталось бы одно.
      final own = OwnAddresses.of(account);
      final orphans = [
        for (final m in msgs)
          if (m.isReplyBySubject && m.refs.isEmpty) m,
      ]..sort((a, b) => b.at.compareTo(a.at));
      final byTopic = <String, String>{};
      var lookups = 0;
      for (final m in orphans) {
        if (lookups >= maxTopicLookups) break;
        lookups++;
        final peer = await _peerByTopic(db, account.id, m, own, exclude: {for (final x in msgs) x.id});
        if (peer == null) continue;
        final cur = plan.conv[m.id];
        if (cur != null && cur != peer) byTopic[cur] = peer;
      }
      if (byTopic.isNotEmpty) {
        plan = ThreadPlan(
          {for (final e in plan.conv.entries) e.key: byTopic[e.value] ?? e.value},
          {...plan.merge, ...byTopic},
        );
      }

      if (plan.merge.isNotEmpty) await _mergeConversations(db, account.id, plan.merge);
      var changed = 0;
      final out = [
        for (final e in emails)
          if (plan.conv[e.id] != null && plan.conv[e.id] != e.conversationId)
            (() {
              changed++;
              return e.copyWith(conversationId: plan.conv[e.id]);
            })()
          else
            e,
      ];
      if (changed > 0 || plan.merge.isNotEmpty) {
        AppLogger.debug('Беседы: по ссылкам и теме — писем $changed, слито бесед ${plan.merge.length}');
      }
      return out;
    } catch (e) {
      AppLogger.debug('Беседы: раскладка не удалась — $e');
      return emails;
    }
  }

  /// Беседы писем базы по их Message-ID.
  static Future<Map<String, String>> _convByMessageId(AppDatabase db, String accountId, Set<String> ids) async {
    final out = <String, String>{};
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final part = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final rows = await (db.selectOnly(db.emails)
            ..addColumns([db.emails.internetMessageId, db.emails.conversationId])
            ..where(db.emails.accountId.equals(accountId) &
                db.emails.internetMessageId.isIn(part) &
                db.emails.conversationId.isNotNull()))
          .get();
      for (final r in rows) {
        final mid = r.read(db.emails.internetMessageId);
        final conv = r.read(db.emails.conversationId);
        if (mid != null && conv != null && conv.isNotEmpty) out[mid] = conv;
      }
    }
    return out;
  }

  /// Какие из [ids] уже служат беседой писем базы (ответ пришёл раньше).
  static Future<Set<String>> _existingConv(AppDatabase db, String accountId, Set<String> ids) async {
    final out = <String>{};
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final part = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
      final rows = await (db.selectOnly(db.emails, distinct: true)
            ..addColumns([db.emails.conversationId])
            ..where(db.emails.accountId.equals(accountId) & db.emails.conversationId.isIn(part)))
          .get();
      out.addAll(rows.map((r) => r.read(db.emails.conversationId)).whereType<String>());
    }
    return out;
  }

  /// Беседа письма базы с той же темой и тем же собеседником (самое
  /// свежее до [m]).
  static Future<String?> _peerByTopic(AppDatabase db, String accountId, ThreadMsg m, Set<String> own,
      {Set<String> exclude = const {}}) async {
    final topic = SubjectPrefix.strip(m.subject);
    if (topic.length < 2) return null;
    final like = '%${topic.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await db
        .emailsLight(
          (e) =>
              e.accountId.equals(accountId) &
              e.receivedAt.isBetweenValues(m.at.subtract(topicWindow), m.at.add(const Duration(days: 1))) &
              e.subject.like(like, escapeChar: '\\') &
              e.conversationId.isNotNull(),
          orderBy: (e) => [OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)],
          limit: 30,
        )
        .get();
    for (final r in rows) {
      if (exclude.contains(r.id)) continue;
      final c = ThreadMsg(
        id: r.id,
        messageId: r.internetMessageId,
        refs: const [],
        conv: r.conversationId,
        subject: r.subject,
        at: r.receivedAt,
        from: r.fromEmail.trim().toLowerCase(),
        people: {r.fromEmail.trim().toLowerCase(), ..._emails(r.toRecipients), ..._emails(r.ccJson)},
      );
      if (sameTopicPeer(m, c, own)) return r.conversationId;
    }
    return null;
  }

  static Iterable<String> _emails(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final a in (jsonDecode(json) as List).whereType<Map>())
          if ('${a['email'] ?? ''}'.trim().isNotEmpty) '${a['email']}'.trim().toLowerCase(),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Слить беседы в базе: письма бесед-ключей получают беседу-значение.
  static Future<void> _mergeConversations(AppDatabase db, String accountId, Map<String, String> merge) async {
    await db.transaction(() async {
      for (final e in merge.entries) {
        await (db.update(db.emails)
              ..where((x) => x.accountId.equals(accountId) & x.conversationId.equals(e.key)))
            .write(EmailsCompanion(conversationId: Value(e.value)));
      }
    });
  }

  /// [plan] в отдельном изоляте. Отдельная функция: замыкание берёт с собой
  /// только письма, а не базу и другое окружение вызывающего.
  static Future<ThreadPlan> _planApart(List<ThreadMsg> msgs) => Isolate.run(() => plan(msgs));

  /// Разово после обновления (1.8.13): разложить уже загруженные письма
  /// ящика по ссылкам — беседы, разорванные до этой версии, сливаются.
  /// Только заголовки цепочки, без поиска по теме. Возвращает, сколько
  /// писем получили другую беседу.
  static Future<int> relinkAccount(AppDatabase db, AccountModel account) async {
    if (!appliesTo(account)) return 0;
    final rows = await db.customSelect(
      'SELECT id, internet_message_id, references_str, conversation_id, received_at FROM emails '
      'WHERE account_id = ? ORDER BY received_at ASC',
      variables: [Variable.withString(account.id)],
      readsFrom: {db.emails},
    ).get();
    if (rows.isEmpty) return 0;
    final msgs = <ThreadMsg>[];
    for (final r in rows) {
      final refs = (r.data['references_str'] as String?) ?? '';
      msgs.add(ThreadMsg(
        id: r.data['id'] as String,
        messageId: (r.data['internet_message_id'] as String?)?.trim(),
        refs: [for (final x in refs.split(RegExp(r'\s+'))) if (x.startsWith('<') && x.endsWith('>')) x],
        conv: r.data['conversation_id'] as String?,
        subject: '',
        at: r.read<DateTime>('received_at'),
        from: '',
        people: const {},
      ));
    }
    // Все письма ящика — «новые» без базы: связи только между ними. Расчёт
    // — в отдельном изоляте: у большого ящика это десятки тысяч писем.
    final plan = await _planApart(msgs);
    final changed = <String, List<String>>{};
    final before = {for (final m in msgs) m.id: m.conv};
    for (final e in plan.conv.entries) {
      if (before[e.key] != e.value) (changed[e.value] ??= []).add(e.key);
    }
    if (changed.isEmpty) return 0;
    var n = 0;
    await db.transaction(() async {
      for (final e in changed.entries) {
        for (var i = 0; i < e.value.length; i += 400) {
          final part = e.value.sublist(i, i + 400 > e.value.length ? e.value.length : i + 400);
          n += await (db.update(db.emails)..where((x) => x.accountId.equals(account.id) & x.id.isIn(part)))
              .write(EmailsCompanion(conversationId: Value(e.key)));
        }
      }
    });
    return n;
  }
}

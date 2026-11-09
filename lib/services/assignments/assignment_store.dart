// lib/services/assignments/assignment_store.dart
// Поручения в базе (таблицы Assignments, AssignmentParticipants,
// AssignmentEvents — app_database.dart) и разбор писем поручений после
// синхронизации. Без Riverpod: разбор идёт и в фоновой синхронизации.
//
//  · письмо с меткой [OGN-…] и отметкой «ogneliss-task» от другого человека
//    мне — поручение «Мне поручили»; моё такое письмо (с другого
//    устройства) — «Я поручил», поручения видны на всех устройствах;
//  · ответ исполнителя на моё поручение — в историю, статус: по отметке
//    статуса (ответ кнопкой Ogneliss Mail) или по словам «Принято»,
//    «Готово» на 27 языках (assignment_phrases.dart). Словами статус
//    только идёт вперёд: «новое» → «в работе» → «на проверке»;
//  · письмо поручившего мне — новый срок, «принято», «вернул», «снято».
// Каждое письмо разбирается один раз: событие с id «mail:ящик:письмо».

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/logging/app_logger.dart';
import '../../core/utils/quote_splitter.dart';
import '../../data/database/app_database.dart';
import 'assignment_codec.dart';
import 'assignment_phrases.dart';

/// Роли участников.
abstract final class AssignmentRole {
  static const owner = 0;
  static const responsible = 1;
}

/// Поручение для экранов: строка, исполнитель, поручивший, направление.
class AssignmentView {
  final Assignment row;
  final AssignmentParticipant? assignee;
  final AssignmentParticipant? owner;

  /// Я поручил (иначе — мне поручили).
  final bool outgoing;
  const AssignmentView({required this.row, this.assignee, this.owner, required this.outgoing});

  String get id => row.id;
  int get status => row.status;
  bool get active => AssignmentStatus.isActive(row.status);
  DateTime? get due => row.dueAt?.toLocal();

  /// С кем поручение: у моего — исполнитель, у порученного мне — поручивший.
  String get otherName {
    final p = outgoing ? assignee : owner;
    final n = (p?.displayName ?? '').trim();
    return n.isNotEmpty ? n : (p?.email ?? (outgoing ? '' : row.ownerEmail));
  }

  String? get otherEmail => outgoing ? assignee?.email : (owner?.email ?? row.ownerEmail);

  /// Срок прошёл (день срока закончился), а поручение не выполнено.
  bool overdue(DateTime now) {
    final d = due;
    if (d == null || !active) return false;
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
  }
}

abstract final class AssignmentStore {
  static Future<Assignment?> byId(AppDatabase db, String id) =>
      (db.select(db.assignments)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Все поручения ящиков [mine] (ящик → мои адреса), новые сверху.
  static Future<List<AssignmentView>> all(AppDatabase db, Map<String, Set<String>> mine) async {
    if (mine.isEmpty) return const [];
    final rows = await (db.select(db.assignments)
          ..where((a) => a.accountId.isIn(mine.keys) & a.isArchived.equals(false) & a.isTemplate.equals(false))
          ..orderBy([(a) => OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc)])
          ..limit(500))
        .get();
    if (rows.isEmpty) return const [];
    final people = await (db.select(db.assignmentParticipants)
          ..where((p) => p.assignmentId.isIn([for (final r in rows) r.id])))
        .get();
    final byA = <String, List<AssignmentParticipant>>{};
    for (final p in people) {
      byA.putIfAbsent(p.assignmentId, () => []).add(p);
    }
    return [
      for (final r in rows)
        AssignmentView(
          row: r,
          assignee: byA[r.id]?.where((p) => p.role == AssignmentRole.responsible).firstOrNull,
          owner: byA[r.id]?.where((p) => p.role == AssignmentRole.owner).firstOrNull,
          outgoing: (mine[r.accountId] ?? const {}).contains(r.ownerEmail.toLowerCase()),
        ),
    ];
  }

  /// История поручения, по времени.
  static Future<List<AssignmentEvent>> events(AppDatabase db, String id) => (db.select(db.assignmentEvents)
        ..where((e) => e.assignmentId.equals(id))
        ..orderBy([(e) => OrderingTerm(expression: e.createdAt)]))
      .get();

  static Future<void> insert(
    AppDatabase db, {
    required String id,
    required String accountId,
    required String title,
    String? description,
    required String ownerEmail,
    String? ownerName,
    required String assigneeEmail,
    String? assigneeName,
    DateTime? due,
    int priority = 1,
    String? sourceEmailId,
    required DateTime at,
    required bool outgoing,
    String? eventId,
  }) async {
    await db.transaction(() async {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: id,
              accountId: accountId,
              title: title,
              description: Value(description),
              status: const Value(AssignmentStatus.open),
              priority: Value(priority),
              ownerEmail: ownerEmail.toLowerCase(),
              dueAt: Value(due),
              sourceEmailId: Value(sourceEmailId),
              createdAt: at,
              updatedAt: at,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db.into(db.assignmentParticipants).insert(
            AssignmentParticipantsCompanion.insert(
              assignmentId: id,
              email: ownerEmail.toLowerCase(),
              displayName: Value(ownerName),
              role: AssignmentRole.owner,
            ),
            mode: InsertMode.insertOrReplace,
          );
      await db.into(db.assignmentParticipants).insert(
            AssignmentParticipantsCompanion.insert(
              assignmentId: id,
              email: assigneeEmail.toLowerCase(),
              displayName: Value(assigneeName),
              role: AssignmentRole.responsible,
            ),
            mode: InsertMode.insertOrReplace,
          );
      await addEvent(db,
          id: eventId ?? 'created:$id',
          assignmentId: id,
          type: 'created',
          author: ownerEmail,
          at: at,
          outgoing: outgoing,
          payload: {'to': assigneeEmail.toLowerCase(), if (due != null) 'due': due.toIso8601String()},
          sourceEmailId: sourceEmailId);
    });
  }

  static Future<void> addEvent(
    AppDatabase db, {
    required String id,
    required String assignmentId,
    required String type,
    required String author,
    required DateTime at,
    required bool outgoing,
    Map<String, Object?> payload = const {},
    String? sourceEmailId,
  }) =>
      db.into(db.assignmentEvents).insert(
            AssignmentEventsCompanion.insert(
              id: id,
              assignmentId: assignmentId,
              type: type,
              authorEmail: author.toLowerCase(),
              createdAt: at,
              payloadJson: jsonEncode(payload),
              direction: outgoing ? 0 : 1,
              sourceEmailId: Value(sourceEmailId),
            ),
            mode: InsertMode.insertOrIgnore,
          );

  static Future<void> update(AppDatabase db, String id, {int? status, DateTime? due, bool clearDue = false}) =>
      (db.update(db.assignments)..where((a) => a.id.equals(id))).write(AssignmentsCompanion(
        status: status == null ? const Value.absent() : Value(status),
        dueAt: clearDue ? const Value(null) : (due == null ? const Value.absent() : Value(due)),
        updatedAt: Value(DateTime.now()),
      ));

  /// Удалить поручение у себя (письма остаются в почте).
  static Future<void> delete(AppDatabase db, String id) async {
    await db.transaction(() async {
      await (db.delete(db.assignmentEvents)..where((e) => e.assignmentId.equals(id))).go();
      await (db.delete(db.assignmentParticipants)..where((p) => p.assignmentId.equals(id))).go();
      await (db.delete(db.assignments)..where((a) => a.id.equals(id))).go();
    });
  }

  /// Статус по словам ответа идёт только вперёд.
  static bool _forward(int from, int to) =>
      (from == AssignmentStatus.open && (to == AssignmentStatus.inProgress || to == AssignmentStatus.review)) ||
      (from == AssignmentStatus.inProgress && to == AssignmentStatus.review);

  /// Свежая часть письма текстом (без цитаты).
  static String freshText(String? html, String? plain) {
    if ((html ?? '').trim().isNotEmpty) {
      try {
        final fresh = splitQuotedHtml(html!).reply;
        return (html_parser.parse(fresh).body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) {}
    }
    final p = plain ?? '';
    try {
      return splitQuotedPlain(p).reply.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (_) {
      return p.trim();
    }
  }

  /// Разобрать письма поручений, пришедшие после [since]. [mine] — ящик →
  /// все мои адреса (нижний регистр). Возвращает число изменений.
  static Future<int> scan(AppDatabase db, Map<String, Set<String>> mine, {required DateTime since}) async {
    if (mine.isEmpty) return 0;
    var changes = 0;
    try {
      final rows = await (db.select(db.emails)
            ..where((e) =>
                e.accountId.isIn(mine.keys) & e.receivedAt.isBiggerThanValue(since) & e.subject.like('%[OGN-%'))
            ..orderBy([(e) => OrderingTerm(expression: e.receivedAt)])
            ..limit(500))
          .get();
      for (final e in rows) {
        if (await _apply(db, e, mine[e.accountId] ?? const {})) changes++;
      }
    } catch (err) {
      AppLogger.warning('Поручения: разбор писем — $err');
    }
    if (changes > 0) AppLogger.info('Поручения: изменений по письмам — $changes');
    return changes;
  }

  static Future<bool> _apply(AppDatabase db, Email e, Set<String> me) async {
    final id = AssignmentCodec.idFromSubject(e.subject);
    if (id == null) return false;
    var evId = 'mail:${e.accountId}:${e.id}';
    final seen = await (db.select(db.assignmentEvents)
          ..where((x) => x.id.equals(evId) | x.sourceEmailId.equals(e.id))
          ..limit(1))
        .get();
    if (seen.isNotEmpty) return false;
    final from = e.fromEmail.trim().toLowerCase();
    final fromMe = me.contains(from);
    final html = e.bodyHtml ?? '';
    final plain = e.bodyPlain ?? '';
    final task = AssignmentCodec.parseTask(html) ?? AssignmentCodec.parseTask(plain);
    final st = AssignmentCodec.parseStatus(html) ?? AssignmentCodec.parseStatus(plain);
    final at = e.receivedAt;
    // Письмо с id события: уже записано (отправлено отсюда) — только
    // привязать письмо; иначе — записать под этим id (одно и то же событие
    // на всех устройствах).
    final ev = st?.ev ?? task?.ev;
    if (ev != null) {
      final local = await (db.select(db.assignmentEvents)..where((x) => x.id.equals(ev))).getSingleOrNull();
      if (local != null) {
        await (db.update(db.assignmentEvents)..where((x) => x.id.equals(ev)))
            .write(AssignmentEventsCompanion(sourceEmailId: Value(e.id)));
        return false;
      }
      evId = ev;
    }
    final a = await byId(db, id);

    if (a == null) {
      // Новое поручение: отметка с тем же кодом обязательна (метка в теме
      // без отметки — просто письмо).
      if (task == null || task.id != id) return false;
      final to = task.to;
      // Поручено не мне (я в копии) — не моё поручение.
      if (!fromMe && to != null && !me.contains(to)) return false;
      String? toName;
      final assignee = to ?? (fromMe ? _firstTo(e.toRecipients) : me.firstOrNull);
      if (assignee == null) return false;
      try {
        for (final r in (jsonDecode(e.toRecipients) as List).whereType<Map>()) {
          if ('${r['email']}'.toLowerCase() == assignee) toName = r['displayName'] as String?;
        }
      } catch (_) {}
      await insert(db,
          id: id,
          accountId: e.accountId,
          title: (task.title ?? '').trim().isNotEmpty ? task.title!.trim() : assignmentTitleFromSubject(e.subject),
          ownerEmail: from,
          ownerName: e.fromName,
          assigneeEmail: assignee,
          assigneeName: toName,
          due: task.due,
          sourceEmailId: e.id,
          at: at,
          outgoing: fromMe,
          eventId: evId);
      return true;
    }

    final outgoing = me.contains(a.ownerEmail.toLowerCase());
    int? next;
    if (st != null && st.id == id) {
      next = st.status;
    } else if (outgoing && !fromMe) {
      final sig = AssignmentPhrases.classify(freshText(html, plain));
      final want = switch (sig) {
        AssignmentSignal.done => AssignmentStatus.review,
        AssignmentSignal.accepted => AssignmentStatus.inProgress,
        null => null,
      };
      if (want != null && _forward(a.status, want)) next = want;
    }
    // Новый срок — в письме поручившего (у исполнителя) или моём с другого
    // устройства.
    DateTime? due;
    if (task != null && task.id == id && task.due != null && (fromMe || !outgoing)) {
      final d = task.due!;
      final cur = a.dueAt?.toLocal();
      if (cur == null || DateTime(cur.year, cur.month, cur.day) != DateTime(d.year, d.month, d.day)) due = d;
    }
    final text = freshText(html, plain);
    await db.transaction(() async {
      await addEvent(db,
          id: evId,
          assignmentId: id,
          type: 'message',
          author: from,
          at: at,
          outgoing: fromMe,
          payload: {
            'text': text.length > 400 ? '${text.substring(0, 400)}…' : text,
            if (next != null && next != a.status) 'status': next,
            if (due != null) 'due': due.toIso8601String(),
          },
          sourceEmailId: e.id);
      if ((next != null && next != a.status) || due != null) {
        await update(db, id, status: next != a.status ? next : null, due: due);
      }
    });
    return true;
  }

  static String? _firstTo(String toJson) {
    try {
      for (final r in (jsonDecode(toJson) as List).whereType<Map>()) {
        final m = '${r['email'] ?? ''}'.trim().toLowerCase();
        if (m.isNotEmpty) return m;
      }
    } catch (_) {}
    return null;
  }
}

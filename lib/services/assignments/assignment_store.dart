// lib/services/assignments/assignment_store.dart
// Поручения в базе (таблицы Assignments, AssignmentParticipants,
// AssignmentEvents — app_database.dart) и разбор писем поручений после
// синхронизации. Без Riverpod: разбор идёт и в фоновой синхронизации.
//
//  · письмо с тегом OGN-… и отметкой data-ogneliss-task от другого человека
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
import '../../core/utils/subject_prefix.dart';
import '../../data/database/app_database.dart';
import 'assignment_codec.dart';
import 'assignment_phrases.dart';
import 'assignment_project.dart';

export 'assignment_project.dart';

/// Роли участников (столбец assignment_participants.role).
abstract final class AssignmentRole {
  static const owner = 0; // постановщик
  static const responsible = 1; // исполнитель (основной)
  static const co = 2; // соисполнитель
  static const observer = 3; // наблюдатель
  static const controller = 4; // контролирующий — принимает работу
  /// Заместитель постановщика (13.11.2026: смена вахты, начальник и
  /// заместитель) — те же права, что у постановщика.
  static const deputy = 5;
}

/// Поручение для экранов: строка, участники, мои роли.
class AssignmentView {
  final Assignment row;
  final AssignmentParticipant? assignee;
  final AssignmentParticipant? owner;

  /// Я поручил или я заместитель постановщика (иначе — мне поручили или я
  /// контролирую, наблюдаю).
  final bool outgoing;

  /// Я — сам постановщик (не заместитель): автоматические письма проекта
  /// («Можно начинать», ход работ) уходят от него — без повторов.
  final bool iOwn;

  /// Все участники и мои роли в этом поручении.
  final List<AssignmentParticipant> people;
  final Set<int> myRoles;

  const AssignmentView({
    required this.row,
    this.assignee,
    this.owner,
    required this.outgoing,
    bool? iOwn,
    this.people = const [],
    this.myRoles = const {},
  }) : iOwn = iOwn ?? outgoing;

  String get id => row.id;
  int get status => row.status;
  bool get active => AssignmentStatus.isActive(row.status);
  DateTime? get due => row.dueAt?.toLocal();
  DateTime? get start => row.startAt?.toLocal();
  bool get isProject => row.isProject;
  bool get important => row.priority >= AssignmentPriority.important;
  bool get waiting => row.waiting && active;

  /// Код родительского поручения (подзадача, 12.11.2026).
  String? get parentId => row.parentAssignmentId;

  List<ChecklistItem> get checklist => ChecklistItem.decode(row.checklistJson);
  List<AssignmentFile> get files => AssignmentFile.decode(row.filesJson);

  List<AssignmentParticipant> _role(int r) => [for (final p in people) if (p.role == r) p];
  List<AssignmentParticipant> get coExecutors => _role(AssignmentRole.co);
  List<AssignmentParticipant> get observers => _role(AssignmentRole.observer);
  AssignmentParticipant? get controller => _role(AssignmentRole.controller).firstOrNull;
  List<AssignmentParticipant> get deputies => _role(AssignmentRole.deputy);

  /// Я — заместитель постановщика.
  bool get iDeputy => myRoles.contains(AssignmentRole.deputy) && !iOwn;

  /// Видимость проекта: все участники видят план и ход работ.
  bool get planShared => row.visibility == 0;

  /// Мои роли: исполнитель (основной), соисполнитель, контролирующий,
  /// наблюдатель.
  bool get iExecute => myRoles.contains(AssignmentRole.responsible);
  bool get iCoExecute => myRoles.contains(AssignmentRole.co) && !iExecute;
  bool get iControl => myRoles.contains(AssignmentRole.controller);
  bool get iObserve => myRoles.contains(AssignmentRole.observer) && !iExecute && !iCoExecute && !iControl && !outgoing;

  /// Принять работу или вернуть на доработку может контролирующий, а без
  /// него — постановщик.
  bool get iAccept => iControl || (outgoing && controller == null);

  /// Доля выполненного.
  double get progress => stageProgress(row.status, checklist);

  /// С кем поручение: у моего — исполнитель, у порученного мне — поручивший.
  String get otherName {
    final p = outgoing ? assignee : owner;
    final n = (p?.displayName ?? '').trim();
    return n.isNotEmpty ? n : (p?.email ?? (outgoing ? '' : row.ownerEmail));
  }

  String? get otherEmail => outgoing ? assignee?.email : (owner?.email ?? row.ownerEmail);

  /// Срок прошёл (у срока со временем — время, без него — день срока
  /// закончился), а поручение не выполнено.
  bool overdue(DateTime now) {
    final d = due;
    if (d == null || !active) return false;
    if (dueHasTime(d)) return d.isBefore(now);
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// Связь «родитель — подзадача» среди поручений [all]. Родитель и
/// подзадачи — только те, что есть на этом устройстве: у исполнителя
/// подзадачи родительского поручения может не быть.
/// Важность поручения (столбец priority).
abstract final class AssignmentPriority {
  static const normal = 1;
  static const important = 2;
}

extension AssignmentTree on List<AssignmentView> {
  AssignmentView? parentOf(AssignmentView v) {
    final id = v.parentId;
    if (id == null) return null;
    return where((x) => x.id == id).firstOrNull;
  }

  /// Подзадачи: сначала действующие по сроку, затем закрытые.
  List<AssignmentView> childrenOf(String id) {
    final list = [for (final x in this) if (x.parentId == id) x];
    int rank(AssignmentView v) => v.active ? 0 : 1;
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final da = a.due, db = b.due;
      if (da == null && db == null) return a.row.createdAt.compareTo(b.row.createdAt);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
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
      for (final r in rows) view(r, byA[r.id] ?? const [], mine[r.accountId] ?? const {}),
    ];
  }

  /// Вид поручения по строке, участникам и моим адресам.
  static AssignmentView view(Assignment r, List<AssignmentParticipant> people, Set<String> me) {
    final roles = {for (final p in people) if (me.contains(p.email.toLowerCase())) p.role};
    final own = me.contains(r.ownerEmail.toLowerCase());
    return AssignmentView(
      row: r,
      assignee: people.where((p) => p.role == AssignmentRole.responsible).firstOrNull,
      owner: people.where((p) => p.role == AssignmentRole.owner).firstOrNull,
      outgoing: own || roles.contains(AssignmentRole.deputy),
      iOwn: own,
      people: people,
      myRoles: roles,
    );
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
    String? assigneeEmail,
    String? assigneeName,
    DateTime? due,
    int priority = 1,
    String? sourceEmailId,
    required DateTime at,
    required bool outgoing,
    String? eventId,
    String? parentId,
    bool isProject = false,
    DateTime? start,
    String? afterId,
    int order = 0,
    List<ChecklistItem> checklist = const [],
    List<AssignmentFile> files = const [],
    String? planJson,
    int revision = 0,
    int visibility = 0,
    int? status,
    /// Остальные участники: адрес → (роль, имя).
    Map<String, ({int role, String? name})> others = const {},
  }) async {
    await db.transaction(() async {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: id,
              accountId: accountId,
              title: title,
              description: Value(description),
              status: Value(status ?? AssignmentStatus.open),
              priority: Value(priority),
              ownerEmail: ownerEmail.toLowerCase(),
              dueAt: Value(due),
              sourceEmailId: Value(sourceEmailId),
              parentAssignmentId: Value(parentId),
              createdAt: at,
              updatedAt: at,
              isProject: Value(isProject),
              startAt: Value(start),
              afterId: Value(afterId),
              stageOrder: Value(order),
              checklistJson: Value(ChecklistItem.encode(checklist)),
              filesJson: Value(AssignmentFile.encode(files)),
              waiting: Value(afterId != null && (status == null || status == AssignmentStatus.open)),
              planJson: Value(planJson),
              revision: Value(revision),
              visibility: Value(visibility),
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
      if (assigneeEmail != null && assigneeEmail.isNotEmpty) {
        await db.into(db.assignmentParticipants).insert(
              AssignmentParticipantsCompanion.insert(
                assignmentId: id,
                email: assigneeEmail.toLowerCase(),
                displayName: Value(assigneeName),
                role: AssignmentRole.responsible,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      for (final o in others.entries) {
        final email = o.key.toLowerCase();
        if (email == ownerEmail.toLowerCase() || email == assigneeEmail?.toLowerCase()) continue;
        await db.into(db.assignmentParticipants).insert(
              AssignmentParticipantsCompanion.insert(
                assignmentId: id,
                email: email,
                displayName: Value(o.value.name),
                role: o.value.role,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      await addEvent(db,
          id: eventId ?? 'created:$id',
          assignmentId: id,
          type: 'created',
          author: ownerEmail,
          at: at,
          outgoing: outgoing,
          payload: {
            if (assigneeEmail != null) 'to': assigneeEmail.toLowerCase(),
            if (due != null) 'due': due.toIso8601String(),
            if (isProject) 'project': true,
          },
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

  static Future<void> update(
    AppDatabase db,
    String id, {
    int? status,
    DateTime? due,
    bool clearDue = false,
    DateTime? start,
    List<ChecklistItem>? checklist,
    List<AssignmentFile>? files,
    bool? waiting,
    String? planJson,
    bool clearPlan = false,
    String? title,
    String? description,
    bool clearDescription = false,
    bool clearStart = false,
    String? afterId,
    bool clearAfter = false,
    int? order,
    int? revision,
    int? visibility,
    bool? archived,
    String? ownerEmail,
  }) =>
      (db.update(db.assignments)..where((a) => a.id.equals(id))).write(AssignmentsCompanion(
        status: status == null ? const Value.absent() : Value(status),
        dueAt: clearDue ? const Value(null) : (due == null ? const Value.absent() : Value(due)),
        startAt: clearStart ? const Value(null) : (start == null ? const Value.absent() : Value(start)),
        title: title == null || title.trim().isEmpty ? const Value.absent() : Value(title.trim()),
        description: clearDescription
            ? const Value(null)
            : (description == null ? const Value.absent() : Value(description)),
        afterId: clearAfter ? const Value(null) : (afterId == null ? const Value.absent() : Value(afterId)),
        stageOrder: order == null ? const Value.absent() : Value(order),
        revision: revision == null ? const Value.absent() : Value(revision),
        visibility: visibility == null ? const Value.absent() : Value(visibility),
        isArchived: archived == null ? const Value.absent() : Value(archived),
        ownerEmail: ownerEmail == null ? const Value.absent() : Value(ownerEmail.toLowerCase()),
        checklistJson: checklist == null ? const Value.absent() : Value(ChecklistItem.encode(checklist)),
        filesJson: files == null ? const Value.absent() : Value(AssignmentFile.encode(files)),
        waiting: waiting == null ? const Value.absent() : Value(waiting),
        planJson: clearPlan ? const Value(null) : (planJson == null ? const Value.absent() : Value(planJson)),
        updatedAt: Value(DateTime.now()),
      ));

  /// Заменить участников поручения (изменение, передача прав): постановщик,
  /// исполнитель и остальные. Имена — новые, а без них — прежние.
  static Future<void> setParticipants(
    AppDatabase db,
    String id, {
    required String ownerEmail,
    String? ownerName,
    String? assigneeEmail,
    String? assigneeName,
    Map<String, ({int role, String? name})> others = const {},
  }) async {
    await db.transaction(() async {
      final old = {for (final p in await participants(db, id)) p.email.toLowerCase(): p.displayName};
      await (db.delete(db.assignmentParticipants)..where((p) => p.assignmentId.equals(id))).go();
      final owner = ownerEmail.toLowerCase();
      final assignee = assigneeEmail?.toLowerCase();
      Future<void> put(String email, int role, String? name) => db.into(db.assignmentParticipants).insert(
            AssignmentParticipantsCompanion.insert(
              assignmentId: id,
              email: email,
              displayName: Value((name ?? '').trim().isNotEmpty ? name : old[email]),
              role: role,
            ),
            mode: InsertMode.insertOrReplace,
          );
      // Как при создании: постановщик, который сам исполняет этап, — в
      // участниках исполнителем (одна роль на человека).
      await put(owner, AssignmentRole.owner, ownerName);
      if (assignee != null && assignee.isNotEmpty) {
        await put(assignee, AssignmentRole.responsible, assigneeName);
      }
      for (final o in others.entries) {
        final email = o.key.toLowerCase();
        if (email == assignee || !email.contains('@')) continue;
        if (email == owner && o.value.role != AssignmentRole.co && o.value.role != AssignmentRole.controller) continue;
        await put(email, o.value.role, o.value.name);
      }
    });
  }

  /// Заместители поручения [id] — заменить списком [deputies] (у проекта —
  /// и у всех его этапов). Адрес, который у этапа в другой роли
  /// (исполнитель), остаётся в ней.
  static Future<void> setDeputies(AppDatabase db, String id, Map<String, String?> deputies) async {
    final row = await byId(db, id);
    final ids = [id, if (row?.isProject ?? false) for (final r in await stagesOf(db, id)) r.id];
    await db.transaction(() async {
      for (final x in ids) {
        final people = await participants(db, x);
        for (final p in people) {
          if (p.role == AssignmentRole.deputy && !deputies.containsKey(p.email.toLowerCase())) {
            await (db.delete(db.assignmentParticipants)
                  ..where((q) => q.assignmentId.equals(x) & q.email.equals(p.email)))
                .go();
          }
        }
        final taken = {for (final p in people) if (p.role != AssignmentRole.deputy && p.role != AssignmentRole.observer) p.email.toLowerCase()};
        for (final d in deputies.entries) {
          if (taken.contains(d.key)) continue;
          await addParticipant(db, x, d.key, AssignmentRole.deputy, name: d.value);
        }
      }
    });
  }

  /// Добавить участника (или сменить роль).
  static Future<void> addParticipant(AppDatabase db, String id, String email, int role, {String? name}) =>
      db.into(db.assignmentParticipants).insert(
            AssignmentParticipantsCompanion.insert(
              assignmentId: id,
              email: email.toLowerCase(),
              displayName: Value(name),
              role: role,
            ),
            mode: InsertMode.insertOrReplace,
          );

  /// Участники поручения.
  static Future<List<AssignmentParticipant>> participants(AppDatabase db, String id) =>
      (db.select(db.assignmentParticipants)..where((p) => p.assignmentId.equals(id))).get();

  /// Этапы проекта (подзадачи) по порядку; удалённые из проекта — только
  /// с [removed].
  static Future<List<Assignment>> stagesOf(AppDatabase db, String projectId, {bool removed = false}) =>
      (db.select(db.assignments)
        ..where((a) => a.parentAssignmentId.equals(projectId) & (removed ? const Constant(true) : a.isArchived.equals(false)))
        ..orderBy([
          (a) => OrderingTerm(expression: a.stageOrder),
          (a) => OrderingTerm(expression: a.createdAt),
        ]))
      .get();

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
  ///
  /// Письмо поручения — по техническому тегу OGN-… в теле (в ответе — в
  /// цитате) или по цепочке: ответ на письмо поручения (In-Reply-To,
  /// References) и та же беседа сервера — если цитату удалили.
  static Future<int> scan(AppDatabase db, Map<String, Set<String>> mine, {required DateTime since}) async {
    if (mine.isEmpty) return 0;
    var changes = 0;
    try {
      final links = await _threadLinks(db, mine.keys);
      final refs = links.byMessageId.keys.take(100).toList();
      final convs = links.byConversation.keys.map((k) => k.split('|').last).toSet().toList();
      final rows = await (db.select(db.emails)
            ..where((e) {
              Expression<bool> hit = e.bodyHtml.like('%OGN-%') | e.bodyPlain.like('%OGN-%');
              if (convs.isNotEmpty) hit = hit | e.conversationId.isIn(convs);
              for (final r in refs) {
                hit = hit | e.referencesStr.like('%$r%');
              }
              return e.accountId.isIn(mine.keys) & e.receivedAt.isBiggerThanValue(since) & hit;
            })
            ..orderBy([(e) => OrderingTerm(expression: e.receivedAt)])
            ..limit(500))
          .get();
      for (final e in rows) {
        final id = AssignmentCodec.idFromBody(e.bodyHtml) ??
            AssignmentCodec.idFromBody(e.bodyPlain) ??
            links.of(e);
        if (id == null) continue;
        if (await _apply(db, e, mine[e.accountId] ?? const {}, id)) changes++;
      }
      changes += await _recheckReview(db, mine);
    } catch (err) {
      AppLogger.warning('Поручения: разбор писем — $err');
    }
    if (changes > 0) AppLogger.info('Поручения: изменений по письмам — $changes');
    return changes;
  }

  /// Пересмотр (замечание владельца 13.11.2026): у меня поручение «На
  /// проверке», а постановщик уже ответил «Работа принята» — письмо
  /// разобрано раньше, когда сервер вырезал скрытую отметку, а слова
  /// постановщика у исполнителя не разбирались. Его письма после моего
  /// «Готово» проверяются заново: код «D» или «Принято» словами —
  /// выполнено; статус — в ту же запись истории.
  static Future<int> _recheckReview(AppDatabase db, Map<String, Set<String>> mine) async {
    var n = 0;
    final rows = await (db.select(db.assignments)
          ..where((a) =>
              a.accountId.isIn(mine.keys) & a.status.equals(AssignmentStatus.review) & a.isArchived.equals(false)))
        .get();
    for (final a in rows) {
      final me = mine[a.accountId] ?? const <String>{};
      final people = await participants(db, a.id);
      final iExecute = people.any((p) =>
          me.contains(p.email.toLowerCase()) &&
          (p.role == AssignmentRole.responsible || p.role == AssignmentRole.co));
      if (!iExecute) continue;
      final accepters = {
        a.ownerEmail.toLowerCase(),
        for (final p in people)
          if (p.role == AssignmentRole.deputy || p.role == AssignmentRole.controller) p.email.toLowerCase(),
      };
      Map<String, dynamic> payload(AssignmentEvent e) {
        try {
          final j = jsonDecode(e.payloadJson);
          if (j is Map<String, dynamic>) return j;
        } catch (_) {}
        return const {};
      }

      final list = await events(db, a.id);
      final review = list.lastIndexWhere((e) => payload(e)['status'] == AssignmentStatus.review);
      for (final e in list.skip(review < 0 ? 0 : review + 1)) {
        if (e.type != 'message' || e.sourceEmailId == null || !accepters.contains(e.authorEmail.toLowerCase())) continue;
        final mail = await (db.select(db.emails)..where((m) => m.id.equals(e.sourceEmailId!))).getSingleOrNull();
        if (mail == null) continue;
        final text = freshText(mail.bodyHtml, mail.bodyPlain);
        final act = AssignmentCodec.actionFromText(text);
        final ok = act != null
            ? act.id == a.id && act.act == AssignmentAct.accepted
            : AssignmentPhrases.classify(text) != null;
        if (!ok) continue;
        await db.transaction(() async {
          await update(db, a.id, status: AssignmentStatus.done);
          await (db.update(db.assignmentEvents)..where((x) => x.id.equals(e.id)))
              .write(AssignmentEventsCompanion(payloadJson: Value(jsonEncode({...payload(e), 'status': AssignmentStatus.done}))));
        });
        n++;
        break;
      }
    }
    return n;
  }

  /// Письма действующих поручений (отправленное поручение, полученное,
  /// ответы): Message-ID и беседа → код поручения.
  static Future<_Links> _threadLinks(AppDatabase db, Iterable<String> accountIds) async {
    final active = await (db.select(db.assignments)
          ..where((a) =>
              a.accountId.isIn(accountIds) &
              a.status.isIn(const [AssignmentStatus.open, AssignmentStatus.inProgress, AssignmentStatus.review])))
        .get();
    final links = _Links();
    if (active.isEmpty) return links;
    final events = await (db.select(db.assignmentEvents)
          ..where((x) => x.assignmentId.isIn([for (final a in active) a.id]) & x.sourceEmailId.isNotNull()))
        .get();
    final byMail = {for (final x in events) x.sourceEmailId!: x.assignmentId};
    if (byMail.isEmpty) return links;
    final mails = await (db.select(db.emails)..where((e) => e.id.isIn(byMail.keys))).get();
    for (final m in mails) {
      final id = byMail[m.id];
      if (id == null) continue;
      final mid = _msgId(m.internetMessageId);
      if (mid != null) links.byMessageId[mid] = id;
      final conv = (m.conversationId ?? '').trim();
      if (conv.isNotEmpty) links.byConversation['${m.accountId}|$conv'] = id;
    }
    return links;
  }

  static String? _msgId(String? raw) {
    final s = (raw ?? '').trim().replaceAll('<', '').replaceAll('>', '');
    return s.contains('@') ? s.toLowerCase() : null;
  }

  static Future<bool> _apply(AppDatabase db, Email e, Set<String> me, String id) async {
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
    // Отметки — только из свежей части письма: в цитате ответа — отметки
    // прежних писем поручения.
    var freshHtml = html;
    if (html.trim().isNotEmpty) {
      try {
        freshHtml = splitQuotedHtml(html).reply;
      } catch (_) {}
    }
    final task = AssignmentCodec.parseTask(freshHtml);
    final st = AssignmentCodec.parseStatus(freshHtml);
    final pm = AssignmentCodec.parsePeople(freshHtml);
    final at = e.receivedAt;
    // Письмо с id события: уже записано (отправлено отсюда) — только
    // привязать письмо; иначе — записать под этим id (одно и то же событие
    // на всех устройствах).
    final ev = (st?.id == id ? st?.ev : null) ?? (pm?.id == id ? pm?.ev : null) ?? (task?.id == id ? task?.ev : null);
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
      // Новое поручение — по отметке; сервер её убрал — по тегу в свежей
      // части письма, если это не ответ и не пересылка, а я — в «Кому».
      var t = task?.id == id ? task : null;
      final recipients = '${e.toRecipients} ${e.ccJson ?? ''}'.toLowerCase();
      if (t == null) {
        final fresh = freshText(html, plain);
        final isNew = SubjectPrefix.strip(e.subject) == e.subject.trim();
        final toMe = me.firstWhere((m) => e.toRecipients.toLowerCase().contains(m), orElse: () => '');
        if (fromMe || !isNew || toMe.isEmpty || AssignmentCodec.idFromBody(fresh) != id) return false;
        t = (
          id: id,
          due: null,
          to: toMe,
          title: null,
          ev: null,
          parent: null,
          start: null,
          after: null,
          order: null,
          co: const <String>[],
          ctl: null,
          obs: const <String>[],
          checklist: const <String>[],
          project: false,
          plan: null,
          rev: null,
          desc: null,
          owner: null,
          deputies: const <String>[],
          removed: false,
          visibility: null,
          files: null,
          important: false,
        );
      }
      final to = t.to;
      // Участник ли я: исполнитель, соисполнитель, контролирующий,
      // наблюдатель; письмо проекта — если я в получателях. Иначе (я в
      // копии чужого поручения) — не моё поручение.
      final roleMine = {
        if (to != null) to,
        ...t.co,
        if (t.ctl != null) t.ctl!,
        ...t.obs,
        ...t.deputies,
        if (t.owner != null) t.owner!,
      }.any(me.contains);
      final projectMine = t.project && me.any(recipients.contains);
      if (!fromMe && !roleMine && !projectMine) {
        if (to != null || t.project) return false;
      }
      final names = _names(e);
      // Постановщик — из сведений (права переданы: письмо от заместителя),
      // иначе — отправитель.
      final owner = t.owner ?? from;
      final assignee = t.project ? to : (to ?? (fromMe ? _firstTo(e.toRecipients) : me.firstOrNull));
      if (!t.project && assignee == null) return false;
      final others = <String, ({int role, String? name})>{
        for (final c in t.co) c: (role: AssignmentRole.co, name: names[c]),
        for (final o in t.obs) o: (role: AssignmentRole.observer, name: names[o]),
        if (t.ctl != null) t.ctl!: (role: AssignmentRole.controller, name: names[t.ctl!]),
        for (final d in t.deputies) d: (role: AssignmentRole.deputy, name: names[d]),
      };
      // Письмо проекта мне без роли в нём: я — участник его этапов
      // (наблюдатель проекта — чтобы видеть план).
      if (t.project && !fromMe) {
        for (final m in me) {
          if (recipients.contains(m) && !others.containsKey(m) && m != assignee) {
            others[m] = (role: AssignmentRole.observer, name: names[m]);
            break;
          }
        }
      }
      await insert(db,
          id: id,
          accountId: e.accountId,
          title: (t.title ?? '').trim().isNotEmpty ? t.title!.trim() : assignmentTitleFromSubject(e.subject),
          description: (t.desc ?? '').trim().isEmpty ? null : t.desc!.trim(),
          ownerEmail: owner,
          ownerName: owner == from ? e.fromName : names[owner],
          assigneeEmail: assignee,
          assigneeName: assignee == null ? null : names[assignee],
          due: t.due,
          priority: t.important ? AssignmentPriority.important : AssignmentPriority.normal,
          sourceEmailId: e.id,
          at: at,
          outgoing: fromMe,
          eventId: evId,
          parentId: t.parent,
          isProject: t.project,
          start: t.start,
          afterId: t.after,
          order: t.order ?? 0,
          checklist: [for (final c in t.checklist) ChecklistItem(c)],
          files: _mailFiles(e),
          planJson: t.visibility == 1 ? null : t.plan,
          revision: t.rev ?? 0,
          visibility: t.visibility ?? 0,
          others: others);
      if (t.project && t.deputies.isNotEmpty) {
        await setDeputies(db, id, {for (final d in t.deputies) d: names[d]});
      }
      // Мне переданы права постановщика: этапы проекта — из полного плана.
      if (t.project && (me.contains(owner) || t.deputies.any(me.contains))) {
        await _stagesFromPlan(db, e.accountId, id, t, owner: owner, names: names, at: at);
      }
      return true;
    }

    // Письмо относится к поручению, только если оно от участника (поручивший,
    // исполнитель или я с другого устройства): чужое поручение с тем же
    // кодом (почти невозможно, но не исключено) ничего не меняет.
    final people = await participants(db, id);
    if (!fromMe) {
      final known = {a.ownerEmail.toLowerCase(), for (final p in people) p.email.toLowerCase()};
      if (!known.contains(from)) return false;
    }
    final myRoles = {for (final p in people) if (me.contains(p.email.toLowerCase())) p.role};
    // Постановщик и заместители — у них права постановщика.
    final assigners = {
      a.ownerEmail.toLowerCase(),
      for (final p in people) if (p.role == AssignmentRole.deputy) p.email.toLowerCase(),
    };
    final outgoing = me.any(assigners.contains);
    final fromAssigner = fromMe || assigners.contains(from);
    final accepting = outgoing || myRoles.contains(AssignmentRole.controller);
    // Полные сведения — изменение поручения или проекта, удаление этапа,
    // передача прав: от постановщика или заместителя и новее применённых.
    if (task != null && task.id == id && task.rev != null && fromAssigner) {
      if (task.rev! <= a.revision) {
        await addEvent(db,
            id: evId, assignmentId: id, type: 'message', author: from, at: at, outgoing: fromMe,
            payload: {'text': _cut(freshText(html, plain))}, sourceEmailId: e.id);
        return true;
      }
      await _applyRevision(db, e, a, people, task, me, evId: evId, text: freshText(html, plain));
      return true;
    }
    int? next;
    String? checks;
    var go = false;
    // Роль отправителя: код действия и слова принимаются только от того,
    // кто так может ответить (номер из цитаты чужого письма не в счёт).
    final senderRoles = {for (final p in people) if (p.email.toLowerCase() == from) p.role};
    final byAssigner = assigners.contains(from);
    final byController = senderRoles.contains(AssignmentRole.controller);
    final byExecutor = senderRoles.contains(AssignmentRole.responsible) || senderRoles.contains(AssignmentRole.co);
    // Код действия у видимого номера (предложение владельца 13.11.2026):
    // скрытую отметку сервер мог вырезать, номер с кодом — нет.
    final act = st == null ? AssignmentCodec.actionFromText(freshText(html, plain)) : null;
    var dueFromCode = false;
    DateTime? codeDue;
    if (st != null && st.id == id) {
      next = st.status;
      checks = st.checks;
      go = st.go;
    } else if (act != null && act.id == id) {
      switch (act.act) {
        case AssignmentAct.taken when byExecutor && _forward(a.status, AssignmentStatus.inProgress):
          next = AssignmentStatus.inProgress;
        case AssignmentAct.review when byExecutor && _forward(a.status, AssignmentStatus.review):
          next = AssignmentStatus.review;
        case AssignmentAct.accepted when byAssigner || byController:
          next = AssignmentStatus.done;
        case AssignmentAct.returned when byAssigner || byController:
          next = AssignmentStatus.inProgress;
        case AssignmentAct.cancelled when byAssigner:
          next = AssignmentStatus.cancelled;
        case AssignmentAct.go when byAssigner:
          go = true;
        case AssignmentAct.due when byAssigner && (task == null || task.id != id):
          dueFromCode = true;
          codeDue = AssignmentAct.dueFrom(act.arg);
        default:
          break;
      }
    } else if (!fromMe) {
      // Ни отметки, ни кода — ответ из другой почты: по словам.
      final sig = AssignmentPhrases.classify(freshText(html, plain));
      if (accepting && byExecutor) {
        final want = switch (sig) {
          AssignmentSignal.done => AssignmentStatus.review,
          AssignmentSignal.accepted => AssignmentStatus.inProgress,
          null => null,
        };
        if (want != null && _forward(a.status, want)) next = want;
      } else if ((byAssigner || byController) && sig != null && a.status == AssignmentStatus.review) {
        // У исполнителя: «Принято» постановщика на сданную работу — выполнено.
        next = AssignmentStatus.done;
      }
    }
    // «Можно начинать» — статус не меняется, этап больше не ждёт.
    if (go && next == AssignmentStatus.open && a.status != AssignmentStatus.open) next = null;
    // Новый срок и начало — в письме поручившего (у исполнителя) или моём с
    // другого устройства; новые соисполнители, контролирующий, наблюдатели.
    DateTime? due;
    DateTime? start;
    final added = <String, ({int role, String? name})>{};
    final names = _names(e);
    if (task != null && task.id == id && fromAssigner) {
      if (task.due != null) {
        final d = task.due!;
        final cur = a.dueAt?.toLocal();
        // Со временем (13.11.2026): новый час — тоже новый срок.
        if (cur == null || cur != d) due = d;
      }
      if (task.start != null) {
        final d = task.start!;
        final cur = a.startAt?.toLocal();
        if (cur == null || DateTime(cur.year, cur.month, cur.day) != DateTime(d.year, d.month, d.day)) start = d;
      }
      final known = {for (final p in people) p.email.toLowerCase()};
      for (final c in task.co) {
        if (!known.contains(c)) added[c] = (role: AssignmentRole.co, name: names[c]);
      }
    }
    var clearDue = false;
    if (dueFromCode) {
      final cur = a.dueAt?.toLocal();
      if (codeDue == null) {
        clearDue = cur != null;
      } else if (cur == null || cur != codeDue) {
        due = codeDue;
      }
    }
    if (pm != null && pm.id == id && !people.any((p) => p.email.toLowerCase() == pm.email)) {
      added[pm.email] = (role: pm.role, name: pm.name ?? names[pm.email]);
    }
    List<ChecklistItem>? checklist;
    if (checks != null && !fromMe) {
      final cur = ChecklistItem.decode(a.checklistJson);
      if (cur.isNotEmpty) checklist = ChecklistItem.applyBits(cur, checks);
    }
    // Файлы письма — к файлам этапа (поручивший добавил, исполнитель
    // прислал результат).
    final mailFiles = _mailFiles(e);
    final files = mailFiles.isEmpty ? null : [...AssignmentFile.decode(a.filesJson), ...mailFiles];
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
            'text': _cut(text),
            if (next != null && next != a.status) 'status': next,
            if (due != null) 'due': due.toIso8601String(),
            if (go) 'go': true,
            if (added.isNotEmpty) 'added': added.keys.toList(),
            if (mailFiles.isNotEmpty) 'files': [for (final f in mailFiles) f.name],
          },
          sourceEmailId: e.id);
      for (final x in added.entries) {
        await addParticipant(db, id, x.key, x.value.role, name: x.value.name);
      }
      if ((next != null && next != a.status) ||
          due != null ||
          clearDue ||
          start != null ||
          go ||
          checklist != null ||
          files != null) {
        await update(db, id,
            status: next != a.status ? next : null,
            due: due,
            clearDue: clearDue,
            start: start,
            waiting: go ? false : null,
            checklist: checklist,
            files: files);
      }
    });
    return true;
  }

  static String _cut(String text) => text.length > 400 ? '${text.substring(0, 400)}…' : text;

  /// Полные сведения о поручении [a] из письма постановщика или
  /// заместителя (13.11.2026): заменяют название, описание, сроки, порядок,
  /// участников, чек-лист (отметки выполненных пунктов сохраняются) и
  /// файлы. Проект — ещё видимость, план, заместители и постановщик у всех
  /// этапов. Этап удалён или меня в нём больше нет — снят.
  static Future<void> _applyRevision(
    AppDatabase db,
    Email e,
    Assignment a,
    List<AssignmentParticipant> people,
    TaskMarker t,
    Set<String> me, {
    required String evId,
    required String text,
  }) async {
    final from = e.fromEmail.trim().toLowerCase();
    final names = _names(e);
    final oldOwner = a.ownerEmail.toLowerCase();
    final owner = t.owner ?? oldOwner;
    final known = {for (final p in people) p.email.toLowerCase(): p.displayName};
    String? nameOf(String m) => (names[m] ?? '').trim().isNotEmpty ? names[m] : known[m];
    final deputies = {for (final d in t.deputies) d: nameOf(d)};
    final mailFiles = _mailFiles(e);
    List<AssignmentFile>? files;
    if (t.files != null || mailFiles.isNotEmpty) {
      final keep = t.files?.map((n) => n.trim().toLowerCase()).toSet();
      final old = AssignmentFile.decode(a.filesJson);
      final kept = keep == null ? old : [for (final f in old) if (keep.contains(f.name.trim().toLowerCase())) f];
      final have = {for (final f in kept) '${f.name.toLowerCase()}|${f.mailId}'};
      files = [...kept, for (final f in mailFiles) if (have.add('${f.name.toLowerCase()}|${f.mailId}')) f];
    }
    await db.transaction(() async {
      if (a.isProject) {
        final shared = (t.visibility ?? a.visibility) == 0;
        await update(db, a.id,
            title: t.title,
            description: t.desc,
            clearDescription: t.desc == null,
            start: t.start,
            due: t.due,
            visibility: t.visibility,
            revision: t.rev,
            planJson: shared && t.plan != null ? t.plan : null,
            clearPlan: !shared,
            files: files,
            ownerEmail: owner != oldOwner ? owner : null);
        // Участники проекта: постановщик, наблюдатели, общий контролирующий,
        // заместители; я без роли в проекте (участник этапов) — наблюдатель.
        final others = <String, ({int role, String? name})>{
          for (final o in t.obs) o: (role: AssignmentRole.observer, name: nameOf(o)),
          if (t.ctl != null) t.ctl!: (role: AssignmentRole.controller, name: nameOf(t.ctl!)),
          for (final d in deputies.entries) d.key: (role: AssignmentRole.deputy, name: d.value),
        };
        for (final p in people) {
          final m = p.email.toLowerCase();
          if (me.contains(m) && m != owner && !others.containsKey(m)) {
            others[m] = (role: AssignmentRole.observer, name: p.displayName);
          }
        }
        await setParticipants(db, a.id, ownerEmail: owner, ownerName: nameOf(owner), others: others);
        // Этапы проекта у меня: заместители и (после передачи прав) новый
        // постановщик; прежний — наблюдатель.
        await setDeputies(db, a.id, deputies);
        final stages = await stagesOf(db, a.id);
        // Права сняты: у этапов, где у меня не осталось роли, — наблюдатель
        // (иначе этап выглядел бы порученным мне).
        for (final r in stages) {
          final ps = await participants(db, r.id);
          if (ps.any((q) => me.contains(q.email.toLowerCase())) || me.contains(r.ownerEmail.toLowerCase())) continue;
          final mine = people.where((q) => me.contains(q.email.toLowerCase())).firstOrNull;
          if (mine != null) await addParticipant(db, r.id, mine.email, AssignmentRole.observer, name: mine.displayName);
        }
        if (owner != oldOwner) {
          for (final r in stages) {
            await update(db, r.id, ownerEmail: owner);
            final roles = {for (final q in await participants(db, r.id)) q.email.toLowerCase(): q.role};
            bool free(String m) => roles[m] == null || roles[m] == AssignmentRole.observer || roles[m] == AssignmentRole.deputy || roles[m] == AssignmentRole.owner;
            if (free(owner)) await addParticipant(db, r.id, owner, AssignmentRole.owner, name: nameOf(owner));
            if (free(oldOwner)) await addParticipant(db, r.id, oldOwner, AssignmentRole.observer, name: nameOf(oldOwner));
          }
        }
        // Ход работ из плана — у этапов, где я не исполнитель (заместитель,
        // контролирующий): сведения новее моей последней отметки.
        final plan = PlanStage.decode(t.plan);
        for (final p in plan) {
          final r = stages.where((x) => x.id == p.id).firstOrNull;
          if (r == null || p.status == null || p.status == r.status) continue;
          if (r.updatedAt.millisecondsSinceEpoch ~/ 1000 >= t.rev!) continue;
          final roles = {
            for (final q in await participants(db, r.id)) if (me.contains(q.email.toLowerCase())) q.role,
          };
          if (roles.contains(AssignmentRole.responsible) || roles.contains(AssignmentRole.co)) continue;
          await update(db, r.id, status: p.status);
        }
        if (me.contains(owner) || deputies.keys.any(me.contains)) {
          await _stagesFromPlan(db, a.accountId, a.id, t, owner: owner, names: names, at: e.receivedAt);
        }
      } else {
        final inIt = me.contains(owner) ||
            {if (t.to != null) t.to!, ...t.co, if (t.ctl != null) t.ctl!, ...t.obs, ...deputies.keys}.any(me.contains);
        final afterChanged = t.after != a.afterId;
        var waiting = a.waiting;
        if (afterChanged) {
          final prev = t.after == null ? null : await byId(db, t.after!);
          waiting = t.after != null && prev?.status != AssignmentStatus.done && a.status == AssignmentStatus.open;
        }
        final cancel = (t.removed || !inIt) && AssignmentStatus.isActive(a.status);
        await update(db, a.id,
            title: t.title,
            description: t.desc,
            clearDescription: t.desc == null,
            start: t.start,
            clearStart: t.start == null,
            due: t.due,
            clearDue: t.due == null,
            afterId: t.after,
            clearAfter: t.after == null,
            order: t.order,
            checklist: mergeChecklist(ChecklistItem.decode(a.checklistJson), t.checklist),
            files: files,
            waiting: waiting,
            revision: t.rev,
            status: cancel ? AssignmentStatus.cancelled : null,
            archived: t.removed ? true : null,
            ownerEmail: owner != oldOwner ? owner : null);
        await setParticipants(db, a.id,
            ownerEmail: owner,
            ownerName: nameOf(owner),
            assigneeEmail: t.to,
            assigneeName: t.to == null ? null : nameOf(t.to!),
            others: {
              for (final c in t.co) c: (role: AssignmentRole.co, name: nameOf(c)),
              for (final o in t.obs) o: (role: AssignmentRole.observer, name: nameOf(o)),
              if (t.ctl != null) t.ctl!: (role: AssignmentRole.controller, name: nameOf(t.ctl!)),
              for (final d in deputies.entries) d.key: (role: AssignmentRole.deputy, name: d.value),
              if (owner != oldOwner) oldOwner: (role: AssignmentRole.observer, name: nameOf(oldOwner)),
            });
      }
      await addEvent(db,
          id: evId,
          assignmentId: a.id,
          type: t.removed ? 'removed' : 'edited',
          author: from,
          at: e.receivedAt,
          outgoing: me.contains(from),
          payload: {'text': _cut(text)},
          sourceEmailId: e.id);
    });
  }

  /// Этапы проекта [projectId] из полного плана — у нового постановщика и
  /// заместителя (передача прав): каких этапов нет — появляются целиком.
  static Future<void> _stagesFromPlan(
    AppDatabase db,
    String accountId,
    String projectId,
    TaskMarker t, {
    required String owner,
    required Map<String, String?> names,
    required DateTime at,
  }) async {
    final plan = PlanStage.decode(t.plan);
    for (final p in plan) {
      if (await byId(db, p.id) != null) continue;
      String? nm(String m) => p.names[m] ?? names[m];
      await insert(db,
          id: p.id,
          accountId: accountId,
          title: p.title,
          description: (p.description ?? '').trim().isEmpty ? null : p.description,
          ownerEmail: owner,
          ownerName: nm(owner),
          assigneeEmail: p.assignee,
          assigneeName: p.assigneeName ?? (p.assignee == null ? null : nm(p.assignee!)),
          due: p.due,
          start: p.start,
          at: at,
          outgoing: false,
          eventId: 'created:${p.id}',
          parentId: projectId,
          afterId: p.after,
          order: p.order,
          checklist: p.checklist,
          status: p.status,
          revision: t.rev ?? 0,
          others: {
            for (final c in p.co) c: (role: AssignmentRole.co, name: nm(c)),
            for (final o in p.observers) o: (role: AssignmentRole.observer, name: nm(o)),
            if (p.controller != null) p.controller!: (role: AssignmentRole.controller, name: nm(p.controller!)),
            for (final d in t.deputies) d: (role: AssignmentRole.deputy, name: names[d]),
          });
    }
  }

  /// Имена из «Кому» и «Копии» письма: адрес → имя.
  static Map<String, String?> _names(Email e) {
    final out = <String, String?>{};
    for (final raw in [e.toRecipients, e.ccJson ?? '']) {
      try {
        for (final r in (jsonDecode(raw) as List).whereType<Map>()) {
          final m = '${r['email'] ?? ''}'.trim().toLowerCase();
          if (m.isNotEmpty) out[m] = r['displayName'] as String?;
        }
      } catch (_) {}
    }
    final f = e.fromEmail.trim().toLowerCase();
    if (f.isNotEmpty) out[f] = e.fromName;
    return out;
  }

  /// Вложения письма (кроме встроенных картинок) — файлы поручения.
  static List<AssignmentFile> _mailFiles(Email e) {
    final raw = e.attachmentsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List).whereType<Map>())
          if (m['isInline'] != true && '${m['name'] ?? ''}'.trim().isNotEmpty)
            AssignmentFile(
              name: '${m['name']}',
              size: (m['size'] as num?)?.toInt() ?? 0,
              mailId: e.id,
              attachmentId: '${m['id'] ?? ''}',
            ),
      ];
    } catch (_) {
      return const [];
    }
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

class _Links {
  final byMessageId = <String, String>{};
  final byConversation = <String, String>{};

  /// Код поручения по цепочке письма [e]: ответ на его письмо или та же беседа.
  String? of(Email e) {
    for (final r in (e.referencesStr ?? '').split(RegExp(r'[\s,]+'))) {
      final m = r.replaceAll('<', '').replaceAll('>', '').trim().toLowerCase();
      if (!m.contains('@')) continue;
      final id = byMessageId[m];
      if (id != null) return id;
    }
    final conv = (e.conversationId ?? '').trim();
    return conv.isEmpty ? null : byConversation['${e.accountId}|$conv'];
  }
}

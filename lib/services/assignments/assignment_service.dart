// lib/services/assignments/assignment_service.dart
// Действия с поручениями (решения владельца 09.11.2026; описание и макеты —
// docs/design/MOCKUPS_MY_DAY_TASKS.md). Каждое действие — запись у себя и
// письмо другой стороне: поручение исполнителю; «принято», «вернул на
// доработку», «снято», напоминание, новый срок — исполнителю; «Принято»,
// «Готово» исполнителя — поручившему. Письма уходят обычной отправкой
// (без сети — из очереди); разбор ответов — assignment_store.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr, OrderingMode, OrderingTerm, TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/greeting_helper.dart';
import '../../core/utils/person_names.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../mail/offline_send_service.dart';
import '../contacts/person_name_directory.dart';
import '../mail/greeting_mode.dart';
import '../mail/own_addresses.dart';
import '../notifications/reminder_scheduler_service.dart' show reminderSchedulerProvider;
import 'assignment_codec.dart';
import 'assignment_store.dart';

export 'assignment_codec.dart' show AssignmentStatus, AssignmentAct;
export 'assignment_store.dart' show AssignmentView, dueHasTime;

/// Мои адреса по ящикам (нижний регистр).
Map<String, Set<String>> assignmentMine(List<AccountModel> accounts) => {
      for (final a in accounts) a.id: {for (final m in OwnAddresses.of(a)) m.trim().toLowerCase()},
    };

/// Все поручения; перечитываются при изменении таблиц поручений.
final assignmentsProvider = StreamProvider.autoDispose<List<AssignmentView>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final mine = assignmentMine(ref.watch(accountsProvider));
  yield await AssignmentStore.all(db, mine);
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.assignments, db.assignmentParticipants]))) {
    yield await AssignmentStore.all(db, mine);
  }
});

/// История поручения.
final assignmentEventsProvider = StreamProvider.autoDispose.family<List<AssignmentEvent>, String>((ref, id) async* {
  final db = ref.watch(databaseProvider);
  yield await AssignmentStore.events(db, id);
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.assignmentEvents]))) {
    yield await AssignmentStore.events(db, id);
  }
});

final assignmentServiceProvider = Provider<AssignmentService>((ref) => AssignmentService(ref));

class AssignmentService {
  AssignmentService(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);
  AppLocalizations _l10n() => AppLocalizations(_ref.read(settingsProvider).locale);
  String _ev() => 'ev:${const Uuid().v4()}';

  AccountModel? _account(String id) => _ref.read(accountsProvider).where((a) => a.id == id).firstOrNull;

  /// Сроки и статусы поменялись — напоминания о сроках заново (13.11.2026).
  void _reminders() {
    try {
      unawaited(_ref.read(reminderSchedulerProvider).rescheduleAll().catchError((Object _) {}));
    } catch (_) {}
  }

  // Срок со временем — с часами и минутами (13.11.2026).
  String _dueShort(DateTime d) => DateFormat(dueHasTime(d) ? 'dd.MM HH:mm' : 'dd.MM').format(d);
  String _dueLong(DateTime d, AppLocalizations l10n) =>
      DateFormat(dueHasTime(d) ? 'EEEE, d MMMM, HH:mm' : 'EEEE, d MMMM', l10n.localeCode).format(d);

  /// Приветствие письма поручения — то же, что в редакторе письма
  /// (GreetingHelper, 14.11.2026, замечание владельца: было «Ситников,
  /// добрый день!» — одна фамилия): «Добрый день, Дмитрий Александрович,»
  /// по настройке приветствия ящика (нет, без имени, с именем), на языке
  /// письма. ФИО — самое полное из контактов, писем и адресной книги
  /// организации. '' — без приветствия.
  Future<String> _greeting(EmailAddress a, AccountModel? account, AppLocalizations l10n) async {
    var mode = GreetingMode.helloName;
    try {
      mode = _ref.read(greetingModeProvider.notifier).of(account?.id);
    } catch (_) {}
    if (mode == GreetingMode.off) return '';
    var name = a.displayName;
    if (mode == GreetingMode.helloName) {
      try {
        final full = await _ref
            .read(personNameDirectoryProvider)
            .fullName(a.email, account: account)
            .timeout(const Duration(seconds: 4));
        if (full != null && PersonNames.better(name, full)) name = full;
      } catch (_) {}
    }
    final set = GreetingHelper.variants(
      names: [name ?? ''],
      emails: [a.email],
      appLang: l10n.localeCode,
      lang: l10n.localeCode,
      ownDomains: account == null ? const {} : OwnAddresses.domains(account),
    );
    return mode == GreetingMode.hello ? set.hello : set.full;
  }

  /// Поручить: по поручению каждому исполнителю (у каждого — свой статус).
  /// Возвращает коды поручений. [parent] — подзадача этого поручения.
  Future<List<String>> create({
    required AccountModel account,
    required String title,
    String? description,
    required List<EmailAddress> assignees,
    DateTime? due,
    bool important = false,
    List<AssignmentFile> files = const [],
    Email? source,
    AssignmentView? parent,
  }) async {
    final l10n = _l10n();
    final now = DateTime.now();
    final ids = <String>[];
    for (final to in assignees) {
      final id = AssignmentCodec.newId();
      final ev = 'created:$id';
      // Файлы — копией у себя (у каждого поручения свои) и вложениями.
      final kept = await _keepFiles(id, files);
      await AssignmentStore.insert(_db,
          id: id,
          accountId: account.id,
          title: title.trim(),
          description: (description ?? '').trim().isEmpty ? null : description!.trim(),
          ownerEmail: account.email,
          ownerName: account.displayName,
          assigneeEmail: to.email,
          assigneeName: to.displayName,
          due: due,
          priority: important ? AssignmentPriority.important : AssignmentPriority.normal,
          sourceEmailId: source?.id,
          at: now,
          outgoing: true,
          eventId: ev,
          parentId: parent?.id,
          files: kept);
      final srcFrom = source == null ? null : ((source.fromName ?? '').trim().isNotEmpty ? source.fromName! : source.fromEmail);
      final body = AssignmentCodec.body(
        id: id,
        greeting: await _greeting(to, account, l10n),
        whatLabel: l10n.tr('assignWhatLabel'),
        what: title.trim(),
        description: description,
        parent: parent?.id,
        parentLine: parent == null ? null : l10n.tr('assignPartOf').replaceAll('{title}', parent.row.title),
        dueLabel: l10n.tr('assignDueLabel'),
        dueLine: due == null ? null : _dueLong(due, l10n),
        sourceLine: source == null
            ? null
            : l10n
                .tr('assignSource')
                .replaceAll('{subject}', source.subject)
                .replaceAll('{from}', srcFrom!)
                .replaceAll('{date}', DateFormat('d MMMM', l10n.localeCode).format(source.receivedAt.toLocal())),
        sourceText: source == null ? null : AssignmentStore.freshText(source.bodyHtml, source.bodyPlain),
        footer: l10n
            .tr('assignFooter')
            .replaceAll('{accepted}', l10n.tr('assignReplyAccepted'))
            .replaceAll('{done}', l10n.tr('assignReplyDone')),
        extraHtml: kept.isEmpty
            ? null
            : '<p><b>${assignmentEsc(l10n.tr('assignFilesLabel'))}</b> '
                '${assignmentEsc(kept.map((f) => f.name).join(', '))}</p>',
        marker: AssignmentCodec.taskMarker(
            id: id, due: due, to: to.email, title: title.trim(), ev: ev, parent: parent?.id, important: important),
      );
      await _send(account, to,
          subject: AssignmentCodec.subject(
              prefix: l10n.tr(important ? 'assignSubjectImportant' : 'assignSubject'),
              title: title,
              due: due == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(due))),
          html: body,
          files: kept);
      ids.add(id);
    }
    _reminders();
    return ids;
  }

  String _subject(AssignmentView v, AppLocalizations l10n) => 'Re: ${AssignmentCodec.subject(
        prefix: l10n.tr('assignSubject'),
        title: v.row.title,
        due: v.due == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(v.due!)),
      )}';

  Future<void> _send(AccountModel account, EmailAddress to,
      {required String subject,
      required String html,
      String? inReplyTo,
      List<EmailAddress> moreTo = const [],
      List<EmailAddress> cc = const [],
      List<AssignmentFile> files = const []}) async {
    try {
      final atts = <({String name, String? contentType, Uint8List bytes})>[];
      for (final f in files) {
        final path = f.path;
        if (path == null) continue;
        try {
          atts.add((name: f.name, contentType: null, bytes: await File(path).readAsBytes()));
        } catch (e) {
          AppLogger.warning('Поручение: файл не прочитан — $e');
        }
      }
      // Без повторов: один адрес — один раз (в «Кому» важнее, чем в копии).
      final seen = <String>{};
      List<EmailAddress> uniq(Iterable<EmailAddress> l) => [
            for (final a in l)
              if (a.email.trim().isNotEmpty && seen.add(a.email.trim().toLowerCase())) a,
          ];
      final toList = uniq([to, ...moreTo]);
      final ccList = uniq(cc);
      await _ref.read(offlineSendProvider).sendOrQueue(
            accountId: account.id,
            to: toList,
            cc: ccList,
            subject: subject,
            bodyHtml: html,
            inReplyTo: inReplyTo,
            attachments: atts,
          );
    } catch (e) {
      // Не ушло и не встало в очередь — в журнал; поручение у себя уже есть.
      AppLogger.warning('Поручение: письмо не отправлено — $e');
    }
  }

  /// Письмо другой стороне поручения [v] с текстом и отметкой. Кому — по
  /// ролям (проекты, 12.11.2026): от постановщика и контролирующего —
  /// исполнителю и соисполнителям; от исполнителя — постановщику, а если
  /// работу принимает контролирующий — и ему. Остальные участники —
  /// в копии.
  Future<void> _notify(AssignmentView v, String text, String marker,
      {List<AssignmentFile> files = const [], String? act}) async {
    final account = _account(v.row.accountId);
    if (account == null) return;
    final mine = assignmentMine(_ref.read(accountsProvider))[account.id] ?? const <String>{};
    final people = v.people.isEmpty && v.assignee != null ? [v.assignee!, if (v.owner != null) v.owner!] : v.people;
    EmailAddress addr(AssignmentParticipant p) => EmailAddress(email: p.email, displayName: p.displayName);
    final ownerAddr = EmailAddress(email: v.owner?.email ?? v.row.ownerEmail, displayName: v.owner?.displayName);
    final executors = [
      for (final p in people)
        if (p.role == AssignmentRole.responsible || p.role == AssignmentRole.co) addr(p),
    ];
    final controller = [for (final p in people) if (p.role == AssignmentRole.controller) addr(p)];
    final observers = [for (final p in people) if (p.role == AssignmentRole.observer) addr(p)];
    // Постановщик и заместители (13.11.2026) — ответы исполнителя всем им.
    final assigners = [ownerAddr, for (final p in people) if (p.role == AssignmentRole.deputy) addr(p)];
    final fromExecutor = !v.outgoing && !v.iControl && (v.iExecute || v.iCoExecute);
    final to = <EmailAddress>[];
    final cc = <EmailAddress>[];
    if (fromExecutor) {
      to
        ..addAll(assigners)
        ..addAll(controller);
      cc
        ..addAll(executors)
        ..addAll(observers);
    } else {
      to.addAll(executors);
      cc
        ..addAll(assigners)
        ..addAll(controller)
        ..addAll(observers);
    }
    bool notMe(EmailAddress a) => !mine.contains(a.email.trim().toLowerCase());
    final toList = to.where(notMe).toList();
    final ccList = cc.where(notMe).toList();
    if (toList.isEmpty && ccList.isEmpty) return;
    final inReplyTo = await _inReplyTo(v);
    final first = toList.isNotEmpty ? toList.first : ccList.first;
    await _send(account, first,
        moreTo: toList.skip(1).toList(),
        cc: toList.isEmpty ? ccList.skip(1).toList() : ccList,
        subject: _subject(v, _l10n()),
        html: assignmentNoteHtml(text, marker, v.id, act: act),
        inReplyTo: inReplyTo,
        files: files);
  }

  /// Ответ — в ту же цепочку: на последнее письмо поручения (полученное
  /// или своё отправленное, когда оно пришло в «Отправленные»).
  Future<String?> _inReplyTo(AssignmentView v) async {
    try {
      final linked = await (_db.select(_db.assignmentEvents)
            ..where((x) => x.assignmentId.equals(v.id) & x.sourceEmailId.isNotNull())
            ..orderBy([(x) => OrderingTerm(expression: x.createdAt, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();
      final mailId = linked?.sourceEmailId;
      if (mailId != null) {
        return (await _db.getEmailById(mailId, accountId: v.row.accountId))?.internetMessageId;
      }
    } catch (_) {}
    return null;
  }

  /// Мой адрес в поручении [v] (для истории).
  String _myEmail(AssignmentView v) {
    if (v.iOwn) return v.row.ownerEmail;
    final mine = assignmentMine(_ref.read(accountsProvider))[v.row.accountId] ?? const <String>{};
    return v.people.where((p) => mine.contains(p.email.toLowerCase())).firstOrNull?.email ??
        (v.assignee?.email ?? _account(v.row.accountId)?.email ?? '');
  }

  Future<void> _record(AssignmentView v, String ev, String type, Map<String, Object?> payload) =>
      AssignmentStore.addEvent(_db,
          id: ev,
          assignmentId: v.id,
          type: type,
          author: _myEmail(v),
          at: DateTime.now(),
          outgoing: true,
          payload: payload);

  /// Поручивший: принять работу (выполнено), вернуть на доработку, снять.
  /// Исполнитель: «Принято» (в работе), «Готово» (на проверке).
  Future<void> setStatus(AssignmentView v, int status, {String? note, List<AssignmentFile> files = const []}) async {
    if (status == v.status) return;
    final l10n = _l10n();
    final ev = _ev();
    // Вернуть на доработку может постановщик, заместитель и контролирующий.
    final returning = status == AssignmentStatus.inProgress && (v.outgoing || v.iControl);
    final text = switch (status) {
      AssignmentStatus.done => l10n.tr('assignMsgAccepted'),
      AssignmentStatus.inProgress when returning => l10n.tr('assignMsgReturned'),
      AssignmentStatus.inProgress => l10n.tr('assignReplyAccepted'),
      AssignmentStatus.review => l10n.tr('assignReplyDone'),
      AssignmentStatus.cancelled => l10n.tr('assignMsgCancelled'),
      _ => '',
    };
    // Код действия у номера (13.11.2026): статус дойдёт и без скрытой отметки.
    final act = switch (status) {
      AssignmentStatus.done => AssignmentAct.accepted,
      AssignmentStatus.inProgress when returning => AssignmentAct.returned,
      AssignmentStatus.inProgress => AssignmentAct.taken,
      AssignmentStatus.review => AssignmentAct.review,
      AssignmentStatus.cancelled => AssignmentAct.cancelled,
      _ => null,
    };
    final full = [text, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n');
    // Файлы ответа (результат, замечания) — к файлам поручения и вложениями.
    final kept = await _keepFiles(v.id, files);
    await AssignmentStore.update(_db, v.id, status: status, files: kept.isEmpty ? null : [...v.files, ...kept]);
    _reminders();
    await _record(v, ev, 'status', {
      'status': status,
      'text': full,
      if (kept.isNotEmpty) 'files': [for (final f in kept) f.name],
    });
    // Исполнитель — с отметкой чек-листа: у постановщика виден ход работ.
    final checks = (v.iExecute || v.iCoExecute) && v.checklist.isNotEmpty ? ChecklistItem.bits(v.checklist) : null;
    await _notify(v, full, AssignmentCodec.statusMarker(v.id, status, ev: ev, checks: checks), files: kept, act: act);
    // Этап принят — следующим этапам «Можно начинать» (письмо уходит от
    // постановщика; у контролирующего — при следующем разборе почты у
    // постановщика).
    if (v.outgoing) unawaited(dispatchPending(after: status == AssignmentStatus.done ? v.id : null));
  }

  /// Поручивший отмечает статус сам (2.2.1, замечание владельца 10.11.2026:
  /// исполнитель ответил «Приятно» вместо «Принято» — статус не сменился, а
  /// поменять было нечем). Только у себя: письмо исполнителю не уходит;
  /// в истории — «Отмечено вручную».
  Future<void> markLocally(AssignmentView v, int status) async {
    if (status == v.status) return;
    await AssignmentStore.update(_db, v.id, status: status);
    _reminders();
    await _record(v, _ev(), 'status', {'status': status, 'text': _l10n().tr('assignMarkedManually')});
  }

  /// Напомнить исполнителю (письмо со сроком).
  Future<void> remind(AssignmentView v) async {
    final l10n = _l10n();
    final ev = _ev();
    final text = [
      l10n.tr('assignMsgReminder'),
      if (v.due != null) l10n.tr('assignMsgDue').replaceAll('{due}', _dueLong(v.due!, l10n)),
    ].join(' ');
    await _record(v, ev, 'reminder', {'text': text});
    await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: v.due, ev: ev), act: AssignmentAct.reminder);
  }

  /// Новый срок (поручивший — с письмом исполнителю; исполнитель — только
  /// у себя).
  Future<void> reschedule(AssignmentView v, DateTime? due) async {
    await AssignmentStore.update(_db, v.id, due: due, clearDue: due == null);
    _reminders();
    if (!v.outgoing) return;
    final l10n = _l10n();
    final ev = _ev();
    final text = due == null
        ? l10n.tr('assignMsgNoDue')
        : l10n.tr('assignMsgNewDue').replaceAll('{due}', _dueLong(due, l10n));
    await _record(v, ev, 'due', {'text': text, if (due != null) 'due': due.toIso8601String()});
    await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: due, ev: ev), act: AssignmentAct.dueCode(due));
  }

  // ═══════════════ Проекты с этапами (12.11.2026) ═══════════════

  String _dates(DateTime? start, DateTime? due, AppLocalizations l10n) {
    final f = DateFormat('d MMM', l10n.localeCode);
    String end(DateTime d) => dueHasTime(d) ? DateFormat('d MMM, HH:mm', l10n.localeCode).format(d) : f.format(d);
    if (start != null && due != null) return '${f.format(start)} — ${end(due)}';
    if (due != null) return l10n.tr('assignDueShort').replaceAll('{due}', end(due));
    if (start != null) return f.format(start);
    return '';
  }

  static String _who(EmailAddress a) => (a.displayName ?? '').trim().isNotEmpty ? a.displayName!.trim() : a.email;

  /// Создать проект: строка проекта, строки этапов, письмо проекта всем
  /// участникам (план и файлы проекта) и письмо каждого этапа его
  /// исполнителям (соисполнителям), контролирующему и наблюдателям —
  /// сразу, у последовательного этапа — с пометкой «начать после этапа N»
  /// (решение владельца 12.11.2026). Возвращает код проекта.
  Future<String> createProject(AccountModel account, ProjectDraft d) async {
    final l10n = _l10n();
    final now = DateTime.now();
    final pid = AssignmentCodec.newId();
    final ids = [for (final _ in d.stages) AssignmentCodec.newId()];
    final stageDue = [for (final st in d.stages) if (st.due != null) st.due!];
    final projectDue = stageDue.isEmpty ? null : stageDue.reduce((a, b) => a.isAfter(b) ? a : b);
    final stageStart = [for (final st in d.stages) if (st.start != null) st.start!];
    final projectStart = d.start ?? (stageStart.isEmpty ? null : stageStart.reduce((a, b) => a.isBefore(b) ? a : b));
    final plan = [
      for (var i = 0; i < d.stages.length; i++)
        PlanStage(
          id: ids[i],
          title: d.stages[i].title.trim(),
          start: d.stages[i].start,
          due: d.stages[i].due,
          after: d.stages[i].after == null ? null : ids[d.stages[i].after!],
          assignee: d.stages[i].executor.email.toLowerCase(),
          assigneeName: d.stages[i].executor.displayName,
          order: i,
          status: AssignmentStatus.open,
        ),
    ];
    final planJson = PlanStage.encode(plan);
    final shared = d.visibility == 0;
    final projectFiles = await _keepFiles(pid, d.files);
    await AssignmentStore.insert(_db,
        id: pid,
        accountId: account.id,
        title: d.title.trim(),
        description: d.description.trim().isEmpty ? null : d.description.trim(),
        ownerEmail: account.email,
        ownerName: account.displayName,
        due: projectDue,
        start: projectStart,
        at: now,
        outgoing: true,
        eventId: 'created:$pid',
        isProject: true,
        files: projectFiles,
        planJson: planJson,
        visibility: d.visibility,
        others: {
          for (final o in d.observers) o.email: (role: AssignmentRole.observer, name: o.displayName),
          // Общий контролирующий — для этапов, добавленных потом.
          if (d.controller != null) d.controller!.email: (role: AssignmentRole.controller, name: d.controller!.displayName),
        });
    final stageFiles = <List<AssignmentFile>>[];
    for (var i = 0; i < d.stages.length; i++) {
      final st = d.stages[i];
      final files = await _keepFiles(ids[i], st.files);
      stageFiles.add(files);
      final ctl = st.controller ?? d.controller;
      await AssignmentStore.insert(_db,
          id: ids[i],
          accountId: account.id,
          title: st.title.trim(),
          description: st.description.trim().isEmpty ? null : st.description.trim(),
          ownerEmail: account.email,
          ownerName: account.displayName,
          assigneeEmail: st.executor.email,
          assigneeName: st.executor.displayName,
          due: st.due,
          start: st.start,
          at: now,
          outgoing: true,
          eventId: 'created:${ids[i]}',
          parentId: pid,
          afterId: st.after == null ? null : ids[st.after!],
          order: i,
          checklist: [for (final c in st.checklist) if (c.trim().isNotEmpty) ChecklistItem(c.trim())],
          files: files,
          others: {
            for (final c in st.co) c.email: (role: AssignmentRole.co, name: c.displayName),
            for (final o in [...st.observers, ...d.observers]) o.email: (role: AssignmentRole.observer, name: o.displayName),
            if (ctl != null) ctl.email: (role: AssignmentRole.controller, name: ctl.displayName),
          });
    }

    // ── Письмо проекта: план — всем участникам ──
    final executors = <EmailAddress>[];
    final copies = <EmailAddress>[];
    for (final st in d.stages) {
      executors
        ..add(st.executor)
        ..addAll(st.co);
      final ctl = st.controller ?? d.controller;
      if (ctl != null) copies.add(ctl);
      copies.addAll(st.observers);
    }
    copies.addAll(d.observers);
    // План — всем, если участники видят весь план (по умолчанию); иначе
    // каждый узнаёт только свои этапы из их писем.
    final lines = StringBuffer(shared ? _planHtml(plan, l10n, statuses: false) : '');
    if (projectFiles.isNotEmpty) {
      lines.write('<p><b>${assignmentEsc(l10n.tr('assignFilesLabel'))}</b> '
          '${assignmentEsc(projectFiles.map((f) => f.name).join(', '))}</p>');
    }
    final pev = 'ev:${const Uuid().v4()}';
    final projectBody = AssignmentCodec.body(
      id: pid,
      greeting: l10n.tr('assignProjectGreeting'),
      whatLabel: l10n.tr('assignProjectLabel'),
      what: d.title.trim(),
      description: d.description,
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: projectDue == null ? null : _dueLong(projectDue, l10n),
      footer: l10n.tr('assignProjectFooter'),
      extraHtml: lines.toString(),
      marker: AssignmentCodec.taskMarker(
          id: pid,
          due: projectDue,
          start: projectStart,
          title: d.title.trim(),
          ev: pev,
          project: true,
          obs: [for (final o in d.observers) o.email],
          ctl: d.controller?.email,
          plan: shared ? planJson : null,
          visibility: d.visibility == 0 ? null : d.visibility),
    );
    await AssignmentStore.addEvent(_db,
        id: pev, assignmentId: pid, type: 'sent', author: account.email, at: now, outgoing: true);
    if (executors.isNotEmpty || copies.isNotEmpty) {
      final all = [...executors, ...copies];
      await _send(account, all.first,
          moreTo: executors.skip(1).toList(),
          cc: executors.isEmpty ? copies.skip(1).toList() : copies,
          subject: AssignmentCodec.subject(
              prefix: l10n.tr('assignProjectSubject'),
              title: d.title,
              due: projectDue == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(projectDue))),
          html: projectBody,
          files: projectFiles);
    }

    // ── Письма этапов ──
    for (var i = 0; i < d.stages.length; i++) {
      final st = d.stages[i];
      await _sendStage(account, l10n,
          id: ids[i],
          projectId: pid,
          projectTitle: d.title.trim(),
          st: st,
          order: i,
          afterId: st.after == null ? null : ids[st.after!],
          afterTitle: st.after == null ? null : d.stages[st.after!].title.trim(),
          controller: st.controller ?? d.controller,
          observers: [...st.observers, ...d.observers],
          files: stageFiles[i]);
    }
    _reminders();
    return pid;
  }

  /// Сроки, порядок, роли, чек-лист и файлы этапа — текстом письма.
  String _stageExtra(
    AppLocalizations l10n, {
    DateTime? start,
    DateTime? due,
    String? afterTitle,
    EmailAddress? executor,
    List<EmailAddress> co = const [],
    EmailAddress? controller,
    List<EmailAddress> observers = const [],
    List<EmailAddress> deputies = const [],
    List<String> checklist = const [],
    List<String> files = const [],
  }) {
    final extra = StringBuffer();
    final dates = _dates(start, due, l10n);
    if (dates.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignDatesLabel'))}</b> ${assignmentEsc(dates)}</p>');
    }
    if (afterTitle != null) {
      extra.write('<p>${assignmentEsc(l10n.tr('assignStartAfterNote').replaceAll('{title}', afterTitle))}</p>');
    }
    final roles = [
      if (executor != null) '${assignmentEsc(l10n.tr('assignRoleExecutor'))} ${assignmentEsc(_who(executor))}',
      if (co.isNotEmpty) '${assignmentEsc(l10n.tr('assignRoleCo'))} ${assignmentEsc(co.map(_who).join(', '))}',
      if (controller != null) '${assignmentEsc(l10n.tr('assignRoleController'))} ${assignmentEsc(_who(controller))}',
      if (observers.isNotEmpty) '${assignmentEsc(l10n.tr('assignRoleObservers'))} ${assignmentEsc(observers.map(_who).join(', '))}',
      if (deputies.isNotEmpty) '${assignmentEsc(l10n.tr('assignRoleDeputies'))} ${assignmentEsc(deputies.map(_who).join(', '))}',
    ];
    if (roles.isNotEmpty) extra.write('<p>${roles.join('<br>')}</p>');
    if (checklist.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignChecklistLabel'))}</b></p><ul>');
      for (final c in checklist) {
        extra.write('<li>${assignmentEsc(c)}</li>');
      }
      extra.write('</ul>');
    }
    if (files.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignFilesLabel'))}</b> ${assignmentEsc(files.join(', '))}</p>');
    }
    return extra.toString();
  }

  /// Письмо этапа: исполнителю и соисполнителям, в копии — контролирующий и
  /// наблюдатели; файлы этапа — вложениями.
  Future<void> _sendStage(
    AccountModel account,
    AppLocalizations l10n, {
    required String id,
    required String projectId,
    required String projectTitle,
    required StageDraft st,
    required int order,
    String? afterId,
    String? afterTitle,
    EmailAddress? controller,
    List<EmailAddress> observers = const [],
    List<AssignmentFile> files = const [],
    List<EmailAddress> deputies = const [],
    String? owner,
  }) async {
    final ctl = controller;
    final checklist = [for (final c in st.checklist) if (c.trim().isNotEmpty) c.trim()];
    final extra = _stageExtra(l10n,
        start: st.start,
        due: st.due,
        afterTitle: afterTitle,
        executor: st.executor,
        co: st.co,
        controller: ctl,
        observers: observers,
        deputies: deputies,
        checklist: checklist,
        files: [for (final f in files) f.name]);
    final ev = 'created:$id';
    final body = AssignmentCodec.body(
      id: id,
      greeting: await _greeting(st.executor, account, l10n),
      whatLabel: l10n.tr('assignWhatLabel'),
      what: st.title.trim(),
      description: st.description,
      parentLine: l10n.tr('assignPartOf').replaceAll('{title}', projectTitle),
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: st.due == null ? null : _dueLong(st.due!, l10n),
      footer: l10n
          .tr('assignFooter')
          .replaceAll('{accepted}', l10n.tr('assignReplyAccepted'))
          .replaceAll('{done}', l10n.tr('assignReplyDone')),
      extraHtml: extra,
      marker: AssignmentCodec.taskMarker(
        id: id,
        due: st.due,
        start: st.start,
        to: st.executor.email,
        title: st.title.trim(),
        ev: ev,
        parent: projectId,
        after: afterId,
        order: order,
        co: [for (final c in st.co) c.email],
        ctl: ctl?.email,
        obs: [for (final o in observers) o.email],
        checklist: checklist,
        owner: owner,
        deputies: [for (final d in deputies) d.email],
      ),
    );
    await _send(account, st.executor,
        moreTo: st.co,
        cc: [if (owner != null && owner.toLowerCase() != account.email.toLowerCase()) EmailAddress(email: owner), ...deputies, if (ctl != null) ctl, ...observers],
        subject: AssignmentCodec.subject(
            prefix: l10n.tr('assignSubject'),
            title: st.title,
            due: st.due == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(st.due!))),
        html: body,
        files: files);
  }

  /// Добавить этап в созданный проект [project] (постановщик): строка
  /// этапа и письмо его участникам; срок проекта — по последнему этапу.
  /// [afterId] — код этапа, после которого начинать (null — параллельно).
  Future<String?> addStage(AssignmentView project, StageDraft st, {String? afterId, String? id, int? order}) async {
    final account = _account(project.row.accountId);
    if (account == null || !project.outgoing) return null;
    final l10n = _l10n();
    final now = DateTime.now();
    final sid = id ?? AssignmentCodec.newId();
    final existing = await AssignmentStore.stagesOf(_db, project.id);
    final ord = order ?? existing.length;
    final deputies = [for (final p in project.deputies) EmailAddress(email: p.email, displayName: p.displayName)];
    final after = afterId == null ? null : existing.where((x) => x.id == afterId).firstOrNull;
    final files = await _keepFiles(sid, st.files);
    final observers = [
      ...st.observers,
      for (final p in project.observers) EmailAddress(email: p.email, displayName: p.displayName),
    ];
    final pc = project.controller;
    final ctl = st.controller ?? (pc == null ? null : EmailAddress(email: pc.email, displayName: pc.displayName));
    await AssignmentStore.insert(_db,
        id: sid,
        accountId: account.id,
        title: st.title.trim(),
        description: st.description.trim().isEmpty ? null : st.description.trim(),
        ownerEmail: project.row.ownerEmail,
        ownerName: project.owner?.displayName ?? account.displayName,
        assigneeEmail: st.executor.email,
        assigneeName: st.executor.displayName,
        due: st.due,
        start: st.start,
        at: now,
        outgoing: true,
        eventId: 'created:$sid',
        parentId: project.id,
        afterId: after?.id,
        order: ord,
        checklist: [for (final c in st.checklist) if (c.trim().isNotEmpty) ChecklistItem(c.trim())],
        files: files,
        others: {
          for (final c in st.co) c.email: (role: AssignmentRole.co, name: c.displayName),
          for (final o in observers) o.email: (role: AssignmentRole.observer, name: o.displayName),
          if (ctl != null) ctl.email: (role: AssignmentRole.controller, name: ctl.displayName),
          for (final d in deputies) d.email: (role: AssignmentRole.deputy, name: d.displayName),
        });
    await _sendStage(account, l10n,
        id: sid,
        projectId: project.id,
        projectTitle: project.row.title,
        st: st,
        order: ord,
        afterId: after?.id,
        afterTitle: after?.title,
        controller: ctl,
        observers: observers,
        files: files,
        deputies: deputies,
        owner: project.row.ownerEmail);
    final dues = [for (final r in await AssignmentStore.stagesOf(_db, project.id)) if (r.dueAt != null) r.dueAt!];
    if (dues.isNotEmpty) {
      await AssignmentStore.update(_db, project.id, due: dues.reduce((a, b) => a.isAfter(b) ? a : b));
    }
    // Предыдущий этап уже принят — «Можно начинать» сразу.
    if (after != null && after.status == AssignmentStatus.done) await dispatchPending();
    _reminders();
    return sid;
  }

  /// Шаблон из созданного проекта (этапы и роли — как в проекте).
  Future<void> saveProjectAsTemplate(AssignmentView project, String name) async {
    final list = await stages(project.id);
    EmailAddress addr(AssignmentParticipant p) => EmailAddress(email: p.email, displayName: p.displayName);
    final idx = {for (var i = 0; i < list.length; i++) list[i].id: i};
    final d = ProjectDraft(
      title: project.row.title,
      description: project.row.description ?? '',
      start: project.start,
      observers: [for (final p in project.observers) addr(p)],
      stages: [
        for (final v in list)
          if (v.assignee != null)
            StageDraft(
              title: v.row.title,
              description: v.row.description ?? '',
              executor: addr(v.assignee!),
              co: [for (final p in v.coExecutors) addr(p)],
              controller: v.controller == null ? null : addr(v.controller!),
              observers: [
                for (final p in v.observers)
                  if (!project.observers.any((o) => o.email == p.email)) addr(p),
              ],
              start: v.start,
              due: v.due,
              after: v.row.afterId == null ? null : idx[v.row.afterId],
              checklist: [for (final c in v.checklist) c.text],
            ),
      ],
    );
    await saveTemplate(name, d);
  }

  /// Скопировать выбранные файлы в папку поручения (оригинал могут удалить).
  Future<List<AssignmentFile>> _keepFiles(String id, List<AssignmentFile> files) async {
    if (files.isEmpty) return const [];
    final out = <AssignmentFile>[];
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/assignment_files/$id');
    await dir.create(recursive: true);
    for (final f in files) {
      final src = f.path;
      if (src == null) continue;
      try {
        final safe = f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final dst = File('${dir.path}/$safe');
        await File(src).copy(dst.path);
        out.add(AssignmentFile(name: f.name, size: await dst.length(), path: dst.path));
      } catch (e) {
        AppLogger.warning('Поручение: файл не скопирован — $e');
      }
    }
    return out;
  }

  /// Поручение по коду со всеми участниками (для действий из экранов).
  Future<AssignmentView?> load(String id) async {
    final row = await AssignmentStore.byId(_db, id);
    if (row == null) return null;
    final people = await AssignmentStore.participants(_db, id);
    final mine = assignmentMine(_ref.read(accountsProvider))[row.accountId] ?? const <String>{};
    return AssignmentStore.view(row, people, mine);
  }

  /// Передать этап для исполнения: [person] — соисполнитель, я остаюсь
  /// исполнителем (решение владельца 12.11.2026: «Готово» отправляет
  /// основной исполнитель). Письмо — новому соисполнителю (этап целиком),
  /// в копии — постановщик и контролирующий.
  Future<void> delegate(AssignmentView v, EmailAddress person, {String? note}) async {
    final account = _account(v.row.accountId);
    if (account == null) return;
    final l10n = _l10n();
    final ev = _ev();
    await AssignmentStore.addParticipant(_db, v.id, person.email, AssignmentRole.co, name: person.displayName);
    await _record(v, ev, 'delegated', {'to': person.email.toLowerCase(), 'name': person.displayName});
    final fresh = await load(v.id) ?? v;
    final me = _myEmail(v);
    final myName = (account.displayName).trim().isNotEmpty ? account.displayName : me;
    final text = [
      l10n.tr('assignMsgDelegated').replaceAll('{name}', myName),
      if ((note ?? '').trim().isNotEmpty) note!.trim(),
    ].join('\n');
    final extra = StringBuffer()
      ..write('<p>${assignmentEsc(l10n.tr('assignRoleExecutor'))} ${assignmentEsc(fresh.assignee?.displayName ?? fresh.assignee?.email ?? me)}'
          '<br>${assignmentEsc(l10n.tr('assignRoleCo'))} ${assignmentEsc(fresh.coExecutors.map((p) => (p.displayName ?? '').trim().isNotEmpty ? p.displayName! : p.email).join(', '))}</p>');
    final checklist = [for (final c in fresh.checklist) c.text];
    final marker = AssignmentCodec.taskMarker(
          id: v.id,
          due: fresh.due,
          start: fresh.start,
          to: fresh.assignee?.email,
          title: fresh.row.title,
          ev: ev,
          parent: fresh.parentId,
          after: fresh.row.afterId,
          order: fresh.row.stageOrder,
          co: [for (final p in fresh.coExecutors) p.email],
          ctl: fresh.controller?.email,
          obs: [for (final p in fresh.observers) p.email],
          important: fresh.important,
          checklist: checklist,
        ) +
        AssignmentCodec.peopleMarker(v.id, person.email, AssignmentRole.co, name: person.displayName, ev: ev);
    final html = AssignmentCodec.body(
      id: v.id,
      greeting: await _greeting(person, account, l10n),
      whatLabel: l10n.tr('assignWhatLabel'),
      what: fresh.row.title,
      description: [text, if ((fresh.row.description ?? '').trim().isNotEmpty) fresh.row.description!.trim()].join('\n\n'),
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: fresh.due == null ? null : _dueLong(fresh.due!, l10n),
      footer: l10n
          .tr('assignFooter')
          .replaceAll('{accepted}', l10n.tr('assignReplyAccepted'))
          .replaceAll('{done}', l10n.tr('assignReplyDone')),
      extraHtml: extra.toString(),
      marker: marker,
      act: AssignmentAct.added,
    );
    final ownerAddr = EmailAddress(email: v.owner?.email ?? v.row.ownerEmail, displayName: v.owner?.displayName);
    await _send(account, person,
        cc: [
          ownerAddr,
          if (fresh.controller != null) EmailAddress(email: fresh.controller!.email, displayName: fresh.controller!.displayName),
        ],
        subject: _subject(v, l10n),
        html: html,
        files: [for (final f in fresh.files) if (f.path != null) f]);
  }

  /// Отметить пункт чек-листа (у себя; постановщик узнаёт из «Сообщить о
  /// ходе работ» и из «Принято»/«Готово»).
  Future<void> toggleCheck(AssignmentView v, int index) async {
    final items = [...v.checklist];
    if (index < 0 || index >= items.length) return;
    items[index] = items[index].copyWith(done: !items[index].done);
    await AssignmentStore.update(_db, v.id, checklist: items);
  }

  /// Добавить пункт чек-листа (у себя).
  Future<void> addCheck(AssignmentView v, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await AssignmentStore.update(_db, v.id, checklist: [...v.checklist, ChecklistItem(t)]);
  }

  /// Сообщить о ходе работ: выполненные пункты чек-листа и комментарий.
  Future<void> reportProgress(AssignmentView v, {String? note, List<AssignmentFile> files = const []}) async {
    final l10n = _l10n();
    final ev = _ev();
    final items = v.checklist;
    final text = [
      if (items.isNotEmpty)
        l10n
            .tr('assignMsgProgress')
            .replaceAll('{done}', '${items.where((i) => i.done).length}')
            .replaceAll('{total}', '${items.length}'),
      if ((note ?? '').trim().isNotEmpty) note!.trim(),
    ].join('\n');
    if (text.isEmpty && files.isEmpty) return;
    final kept = await _keepFiles(v.id, files);
    if (kept.isNotEmpty) await AssignmentStore.update(_db, v.id, files: [...v.files, ...kept]);
    final body = text.isEmpty ? l10n.tr('assignMsgFiles') : text;
    await _record(v, ev, 'progress', {
      'text': body,
      if (kept.isNotEmpty) 'files': [for (final f in kept) f.name],
    });
    await _notify(
        v,
        body,
        AssignmentCodec.statusMarker(v.id, v.status, ev: ev, checks: items.isEmpty ? null : ChecklistItem.bits(items)),
        files: kept,
        act: AssignmentAct.progress);
  }

  /// Добавить файлы к поручению: у себя и письмом другой стороне.
  Future<void> addFiles(AssignmentView v, List<AssignmentFile> picked, {String? note}) async {
    if (picked.isEmpty) return;
    final kept = await _keepFiles(v.id, picked);
    if (kept.isEmpty) return;
    await AssignmentStore.update(_db, v.id, files: [...v.files, ...kept]);
    final l10n = _l10n();
    final ev = _ev();
    final text = [
      l10n.tr('assignMsgFiles'),
      kept.map((f) => f.name).join(', '),
      if ((note ?? '').trim().isNotEmpty) note!.trim(),
    ].join('\n');
    await _record(v, ev, 'files', {'text': text, 'files': [for (final f in kept) f.name]});
    await _notify(v, text, AssignmentCodec.statusMarker(v.id, v.status, ev: ev), files: kept, act: AssignmentAct.files);
  }

  /// Этапы проекта (виды) по порядку.
  Future<List<AssignmentView>> stages(String projectId) async {
    final rows = await AssignmentStore.stagesOf(_db, projectId);
    final out = <AssignmentView>[];
    for (final r in rows) {
      final v = await load(r.id);
      if (v != null) out.add(v);
    }
    return out;
  }

  /// «Можно начинать»: этапы моих проектов, ждущие принятого этапа, —
  /// письмо их исполнителям, этап больше не ждёт.
  ///
  /// Письмо «Можно начинать» — от самого постановщика, а от заместителя —
  /// когда предыдущий этап [after] принял он сам (без повторов). Затем —
  /// ход работ участникам проектов (_broadcastProjects).
  Future<void> dispatchPending({String? after}) async {
    await _closeDoneProjects();
    final waiting = await (_db.select(_db.assignments)
          ..where((a) => a.waiting.equals(true) & a.afterId.isNotNull() & a.status.isIn(const [1, 2, 3])))
        .get();
    final l10n = _l10n();
    for (final w in waiting) {
      final prev = await AssignmentStore.byId(_db, w.afterId!);
      if (prev == null || prev.status != AssignmentStatus.done) continue;
      final v = await load(w.id);
      if (v == null) continue;
      await AssignmentStore.update(_db, v.id, waiting: false);
      _reminders();
      if (!(v.iOwn || (v.outgoing && after != null && w.afterId == after))) continue;
      final ev = _ev();
      final text = l10n.tr('assignMsgGo').replaceAll('{title}', prev.title);
      await _record(v, ev, 'go', {'text': text});
      await _notify(v, text, AssignmentCodec.statusMarker(v.id, v.status, ev: ev, go: true), act: AssignmentAct.go);
    }
    try {
      await _broadcastProjects();
    } catch (e) {
      AppLogger.warning('Поручения: ход работ проектов — $e');
    }
  }

  /// Свой проект, все этапы которого приняты, — выполнен (у себя; письма
  /// участникам не нужны — каждый свой этап уже получил «Принято»).
  Future<void> _closeDoneProjects() async {
    final open = await (_db.select(_db.assignments)
          ..where((a) => a.isProject.equals(true) & a.status.isIn(const [1, 2, 3])))
        .get();
    for (final p in open) {
      final v = await load(p.id);
      if (v == null || !v.outgoing) continue;
      final stages = await AssignmentStore.stagesOf(_db, p.id);
      if (projectStatus(p.status, [for (final s in stages) s.status]) != AssignmentStatus.done) continue;
      await AssignmentStore.update(_db, p.id, status: AssignmentStatus.done);
    }
  }

  /// Сдвинуть следующие этапы проекта после опоздания (связь «окончание →
  /// начало»): новые сроки у себя и письма их исполнителям. Возвращает
  /// число сдвинутых этапов.
  Future<int> shiftLate(String projectId) async {
    final list = await stages(projectId);
    final moved = shiftSuccessors(planOf(list), DateTime.now());
    if (moved.isEmpty) return 0;
    final l10n = _l10n();
    for (final v in list) {
      final m = moved[v.id];
      if (m == null) continue;
      await AssignmentStore.update(_db, v.id, start: m.start, due: m.due);
      final ev = _ev();
      final text = l10n.tr('assignMsgShift').replaceAll('{dates}', _dates(m.start, m.due, l10n));
      await _record(v, ev, 'due', {'text': text, 'due': m.due.toIso8601String()});
      await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: m.due, start: m.start, ev: ev),
          act: AssignmentAct.dueCode(m.due));
    }
    // Срок проекта — по последнему этапу.
    final dues = [for (final v in await stages(projectId)) if (v.due != null) v.due!];
    if (dues.isNotEmpty) {
      await AssignmentStore.update(_db, projectId, due: dues.reduce((a, b) => a.isAfter(b) ? a : b));
    }
    _reminders();
    return moved.length;
  }

  /// Принятые этапы: когда (по истории) — для «факта» на диаграмме.
  Future<Map<String, DateTime>> doneDates(List<AssignmentView> list) async {
    final out = <String, DateTime>{};
    for (final v in list) {
      if (v.status != AssignmentStatus.done) continue;
      out[v.id] = v.row.updatedAt.toLocal();
    }
    return out;
  }

  // ═══════ Изменение, ход работ, права постановщика (13.11.2026) ═══════
  // Просьба владельца 13.11.2026: участники видят, кто что и после кого
  // делает (видимость можно сузить); поручение и проект можно изменить —
  // текст, этапы, файлы, сроки, удалить этап — и это видно у всех; права
  // постановщика можно передать (смена вахты, начальник и заместитель).

  static String _statusText(int s, AppLocalizations l10n) => l10n.tr(switch (s) {
        AssignmentStatus.inProgress => 'assignStInProgress',
        AssignmentStatus.review => 'assignStReview',
        AssignmentStatus.done => 'assignStDone',
        AssignmentStatus.cancelled => 'assignStCancelled',
        _ => 'assignStNew',
      });

  /// План текстом письма: этап — исполнитель, сроки, «после этапа», статус.
  String _planHtml(List<PlanStage> plan, AppLocalizations l10n, {bool statuses = true}) {
    final byId = {for (final p in plan) p.id: p};
    final b = StringBuffer('<p><b>${assignmentEsc(l10n.tr('assignPlanLabel'))}</b></p><ol>');
    for (final st in plan) {
      final dates = _dates(st.start, st.due, l10n);
      final who = (st.assigneeName ?? '').trim().isNotEmpty ? st.assigneeName!.trim() : (st.assignee ?? '');
      final prev = st.after == null ? null : byId[st.after];
      final parts = [
        if (who.isNotEmpty) who,
        if (dates.isNotEmpty) dates,
        if (prev != null) l10n.tr('assignAfterStage').replaceAll('{title}', prev.title),
        if (statuses && st.status != null) _statusText(st.status!, l10n),
      ];
      b.write('<li><b>${assignmentEsc(st.title)}</b>${parts.isEmpty ? '' : ' — ${assignmentEsc(parts.join(', '))}'}</li>');
    }
    b.write('</ol>');
    return b.toString();
  }

  /// План проекта для письма: имена исполнителей и статусы этапов; [full] —
  /// ещё описание, участники и чек-лист (передача прав постановщика).
  static List<PlanStage> mailPlan(List<AssignmentView> stages, {bool full = false}) => [
        for (final v in stages)
          if (!v.row.isArchived)
            PlanStage(
              id: v.id,
              title: v.row.title,
              start: v.start,
              due: v.due,
              after: v.row.afterId,
              assignee: v.assignee?.email.toLowerCase(),
              assigneeName: v.assignee?.displayName,
              order: v.row.stageOrder,
              status: v.status,
              progress: v.progress,
              doneAt: v.status == AssignmentStatus.done ? v.row.updatedAt.toLocal() : null,
              description: full ? v.row.description : null,
              co: full ? [for (final p in v.coExecutors) p.email.toLowerCase()] : const [],
              controller: full ? v.controller?.email.toLowerCase() : null,
              observers: full ? [for (final p in v.observers) p.email.toLowerCase()] : const [],
              checklist: full ? v.checklist : const [],
              names: full
                  ? {
                      for (final p in v.people)
                        if ((p.displayName ?? '').trim().isNotEmpty) p.email.toLowerCase(): p.displayName!.trim(),
                    }
                  : const {},
            ),
      ];

  /// Время новых сведений: не раньше прежних (два изменения за секунду).
  static int _nextRev(AssignmentView v) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now > v.row.revision ? now : v.row.revision + 1;
  }

  static EmailAddress _addr(AssignmentParticipant p) => EmailAddress(email: p.email, displayName: p.displayName);

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a == null || b == null ? a == b : (a.year == b.year && a.month == b.month && a.day == b.day);

  static String _changesHtml(String title, List<String> changes, String? note) {
    final b = StringBuffer('<p><b>${assignmentEsc(title)}</b></p>');
    if (changes.isNotEmpty) {
      b.write('<ul>');
      for (final c in changes) {
        b.write('<li>${assignmentEsc(c)}</li>');
      }
      b.write('</ul>');
    }
    final n = (note ?? '').trim();
    if (n.isNotEmpty) b.write('<p>${assignmentEsc(n).replaceAll('\n', '<br>')}</p>');
    return b.toString();
  }

  /// Полные сведения о поручении [v] — отметкой письма.
  String _taskSnapshot(AssignmentView v, int rev, String ev, {bool removed = false}) => AssignmentCodec.taskMarker(
        id: v.id,
        due: v.due,
        start: v.start,
        to: v.assignee?.email,
        title: v.row.title,
        ev: ev,
        parent: v.parentId,
        after: v.row.afterId,
        order: v.row.stageOrder,
        co: [for (final p in v.coExecutors) p.email],
        ctl: v.controller?.email,
        obs: [for (final p in v.observers) p.email],
        checklist: [for (final c in v.checklist) c.text],
        rev: rev,
        desc: v.row.description,
        owner: v.row.ownerEmail,
        deputies: [for (final p in v.deputies) p.email],
        removed: removed,
        files: [for (final f in v.files) f.name],
        important: v.important,
      );

  /// Полные сведения о проекте [p]: план — если участники видят весь план
  /// или [full] (передача прав: этапы целиком).
  String _projectSnapshot(AssignmentView p, List<AssignmentView> stages, int rev, String ev, {bool full = false}) =>
      AssignmentCodec.taskMarker(
        id: p.id,
        due: p.due,
        start: p.start,
        title: p.row.title,
        ev: ev,
        project: true,
        ctl: p.controller?.email,
        obs: [for (final o in p.observers) o.email],
        plan: p.planShared || full ? PlanStage.encode(mailPlan(stages, full: full), full: full) : null,
        rev: rev,
        desc: p.row.description,
        owner: p.row.ownerEmail,
        deputies: [for (final d in p.deputies) d.email],
        visibility: p.row.visibility,
        files: [for (final f in p.files) f.name],
      );

  Set<String> _mine(AssignmentView v) => assignmentMine(_ref.read(accountsProvider))[v.row.accountId] ?? const <String>{};

  /// Все участники проекта [p] и его этапов, кроме меня: исполнители и
  /// соисполнители — «Кому», остальные — в копии.
  ({List<EmailAddress> to, List<EmailAddress> cc}) _projectPeople(AssignmentView p, List<AssignmentView> stages,
      {Set<String> skip = const {}}) {
    final mine = _mine(p);
    final to = <String, EmailAddress>{};
    final cc = <String, EmailAddress>{};
    void put(Map<String, EmailAddress> m, String email, String? name) {
      final e = email.trim().toLowerCase();
      if (!e.contains('@') || mine.contains(e) || skip.contains(e) || to.containsKey(e)) return;
      m.putIfAbsent(e, () => EmailAddress(email: email, displayName: name));
    }

    for (final s in stages) {
      for (final x in s.people) {
        if (x.role == AssignmentRole.responsible || x.role == AssignmentRole.co) put(to, x.email, x.displayName);
      }
    }
    put(cc, p.row.ownerEmail, p.owner?.displayName);
    for (final x in [...p.people, for (final s in stages) ...s.people]) {
      put(cc, x.email, x.displayName);
    }
    return (to: to.values.toList(), cc: [for (final e in cc.entries) if (!to.containsKey(e.key)) e.value]);
  }

  Future<void> _sendTo(AccountModel account, ({List<EmailAddress> to, List<EmailAddress> cc}) people,
      {required String subject, required String html, String? inReplyTo, List<AssignmentFile> files = const []}) async {
    if (people.to.isEmpty && people.cc.isEmpty) return;
    final first = people.to.isNotEmpty ? people.to.first : people.cc.first;
    await _send(account, first,
        moreTo: people.to.skip(1).toList(),
        cc: people.to.isEmpty ? people.cc.skip(1).toList() : people.cc,
        subject: subject,
        html: html,
        inReplyTo: inReplyTo,
        files: files);
  }

  String _projectSubject(AssignmentView p, AppLocalizations l10n) => 'Re: ${AssignmentCodec.subject(
        prefix: l10n.tr('assignProjectSubject'),
        title: p.row.title,
        due: p.due == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(p.due!)),
      )}';

  /// Письмо проекта всем участникам: что изменилось ([changes]) или ход
  /// работ, план (если участники видят весь план) и сведения о проекте —
  /// у кого Ogneliss Mail, карточка проекта обновится сама.
  Future<void> _sendProject(AssignmentView p, List<AssignmentView> stages,
      {List<String> changes = const [], String? note, List<AssignmentFile> files = const []}) async {
    final account = _account(p.row.accountId);
    if (account == null) return;
    final l10n = _l10n();
    final rev = _nextRev(p);
    final ev = _ev();
    final plan = mailPlan(stages);
    await AssignmentStore.update(_db, p.id, planJson: PlanStage.encode(plan), revision: rev);
    final head = l10n.tr(changes.isEmpty && (note ?? '').trim().isEmpty ? 'assignProgressIntro' : 'assignProjectEdited');
    await _record(p, ev, changes.isEmpty ? 'plan' : 'edited', {
      'text': [head, ...changes, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n'),
    });
    final extra = StringBuffer();
    if (p.planShared) extra.write(_planHtml(plan, l10n));
    if (p.files.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignFilesLabel'))}</b> '
          '${assignmentEsc(p.files.map((f) => f.name).join(', '))}</p>');
    }
    final html = AssignmentCodec.body(
      id: p.id,
      greeting: l10n.tr('assignProjectGreeting'),
      introHtml: _changesHtml(head, changes, note),
      whatLabel: l10n.tr('assignProjectLabel'),
      what: p.row.title,
      description: p.row.description,
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: p.due == null ? null : _dueLong(p.due!, l10n),
      footer: l10n.tr('assignProjectFooter'),
      extraHtml: extra.toString(),
      marker: _projectSnapshot(p, stages, rev, ev),
      act: changes.isEmpty ? AssignmentAct.progress : AssignmentAct.edited,
    );
    await _sendTo(account, _projectPeople(p, stages),
        subject: _projectSubject(p, l10n), html: html, inReplyTo: await _inReplyTo(p), files: files);
  }

  /// Ход работ по моим проектам: у проекта с общим планом поменялись этапы,
  /// сроки, исполнители или статусы — письмо всем участникам. Уходит от
  /// самого постановщика (не заместителя) — без повторов; изменения
  /// за время между синхронизациями — одним письмом.
  Future<void> _broadcastProjects() async {
    // Действующие проекты и выполненные за последнюю неделю (последний
    // «Ход работ» — «все этапы приняты»).
    final week = DateTime.now().subtract(const Duration(days: 7));
    final rows = await (_db.select(_db.assignments)
          ..where((a) =>
              a.isProject.equals(true) &
              a.isArchived.equals(false) &
              a.visibility.equals(0) &
              (a.status.isIn(const [1, 2, 3]) |
                  (a.status.equals(AssignmentStatus.done) & a.updatedAt.isBiggerThanValue(week)))))
        .get();
    for (final r in rows) {
      final p = await load(r.id);
      if (p == null || !p.iOwn) continue;
      final list = await stages(r.id);
      if (list.isEmpty) continue;
      final plan = mailPlan(list);
      final sent = PlanStage.decode(r.planJson);
      if (PlanStage.signature(plan) == PlanStage.signature(sent)) continue;
      // Проект версии до 2.5 (план без статусов) — запомнить без письма.
      if (sent.isNotEmpty && sent.every((x) => x.status == null)) {
        await AssignmentStore.update(_db, r.id, planJson: PlanStage.encode(plan));
        continue;
      }
      await _sendProject(p, list);
    }
  }

  /// Изменить поручение или этап [v] (постановщик или заместитель):
  /// название, описание, сроки, порядок ([afterId] — после какого этапа),
  /// исполнитель, соисполнители, контролирующий, наблюдатели, чек-лист,
  /// файлы. У себя и письмом его участникам (и тем, кого убрали): что
  /// изменилось и полные сведения. false — ничего не изменилось.
  Future<bool> editTask(AssignmentView v, StageDraft d, {required String? afterId, int? order, String? note}) async {
    final account = _account(v.row.accountId);
    if (account == null || !v.outgoing) return false;
    final l10n = _l10n();
    final fmt = DateFormat('d MMM', l10n.localeCode);
    String day(DateTime? x) => x == null ? l10n.tr('noDueDate') : fmt.format(x);
    String low(String e) => e.trim().toLowerCase();
    String diff(Iterable<EmailAddress> before, Iterable<EmailAddress> after) {
      final b = {for (final x in before) low(x.email): x};
      final a = {for (final x in after) low(x.email): x};
      return [
        for (final e in a.entries)
          if (!b.containsKey(e.key)) '+${_who(e.value)}',
        for (final e in b.entries)
          if (!a.containsKey(e.key)) '−${_who(e.value)}',
      ].join(', ');
    }

    final changes = <String>[];
    final title = d.title.trim().isEmpty ? v.row.title : d.title.trim();
    if (title != v.row.title) changes.add(l10n.tr('assignChTitle').replaceAll('{v}', title));
    final desc = d.description.trim();
    if (desc != (v.row.description ?? '').trim()) changes.add(l10n.tr('assignChDesc'));
    if (!_sameDay(d.start, v.start)) {
      changes.add(l10n.tr('assignChStart').replaceAll('{old}', day(v.start)).replaceAll('{new}', day(d.start)));
    }
    if (!_sameDay(d.due, v.due)) {
      changes.add(l10n.tr('assignChDue').replaceAll('{old}', day(v.due)).replaceAll('{new}', day(d.due)));
    }
    final prev = afterId == null ? null : await AssignmentStore.byId(_db, afterId);
    if (afterId != v.row.afterId) {
      changes.add(prev == null ? l10n.tr('assignChParallel') : l10n.tr('assignChAfter').replaceAll('{title}', prev.title));
    }
    final oldExec = v.assignee == null ? null : _addr(v.assignee!);
    if (low(d.executor.email) != low(oldExec?.email ?? '')) {
      changes.add(l10n
          .tr('assignChExecutor')
          .replaceAll('{old}', oldExec == null ? '—' : _who(oldExec))
          .replaceAll('{new}', _who(d.executor)));
    }
    final co = diff(v.coExecutors.map(_addr), d.co);
    if (co.isNotEmpty) changes.add(l10n.tr('assignChCo').replaceAll('{list}', co));
    final oldCtl = v.controller == null ? null : _addr(v.controller!);
    if (low(d.controller?.email ?? '') != low(oldCtl?.email ?? '')) {
      changes.add(l10n
          .tr('assignChController')
          .replaceAll('{old}', oldCtl == null ? '—' : _who(oldCtl))
          .replaceAll('{new}', d.controller == null ? '—' : _who(d.controller!)));
    }
    final obs = diff(v.observers.map(_addr), d.observers);
    if (obs.isNotEmpty) changes.add(l10n.tr('assignChObservers').replaceAll('{list}', obs));
    final oldCk = [for (final c in v.checklist) c.text];
    final newCk = [for (final c in d.checklist) if (c.trim().isNotEmpty) c.trim()];
    final ck = [
      for (final c in newCk)
        if (!oldCk.contains(c)) '+$c',
      for (final c in oldCk)
        if (!newCk.contains(c)) '−$c',
    ];
    if (ck.isNotEmpty) changes.add(l10n.tr('assignChChecklist').replaceAll('{list}', ck.join(', ')));
    bool same(AssignmentFile a, AssignmentFile b) => a.name == b.name && a.path == b.path && a.mailId == b.mailId;
    final oldFiles = v.files;
    final added = [for (final f in d.files) if (!oldFiles.any((o) => same(o, f))) f];
    final kept = [for (final f in oldFiles) if (d.files.any((x) => same(x, f))) f];
    final removed = [for (final f in oldFiles) if (!d.files.any((x) => same(x, f))) f];
    if (changes.isEmpty && added.isEmpty && removed.isEmpty) {
      if (order != null && order != v.row.stageOrder) await AssignmentStore.update(_db, v.id, order: order);
      return false;
    }
    final newFiles = await _keepFiles(v.id, added);
    if (newFiles.isNotEmpty) {
      changes.add(l10n.tr('assignChFilesAdded').replaceAll('{list}', newFiles.map((f) => f.name).join(', ')));
    }
    if (removed.isNotEmpty) {
      changes.add(l10n.tr('assignChFilesRemoved').replaceAll('{list}', removed.map((f) => f.name).join(', ')));
    }
    final rev = _nextRev(v);
    var waiting = v.row.waiting;
    if (afterId != v.row.afterId) {
      waiting = afterId != null && prev?.status != AssignmentStatus.done && v.status == AssignmentStatus.open;
    }
    await AssignmentStore.update(_db, v.id,
        title: title,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
        start: d.start,
        clearStart: d.start == null,
        due: d.due,
        clearDue: d.due == null,
        afterId: afterId,
        clearAfter: afterId == null,
        order: order,
        checklist: mergeChecklist(v.checklist, newCk),
        files: [...kept, ...newFiles],
        waiting: waiting,
        revision: rev);
    await AssignmentStore.setParticipants(_db, v.id,
        ownerEmail: v.row.ownerEmail,
        ownerName: v.owner?.displayName,
        assigneeEmail: d.executor.email,
        assigneeName: d.executor.displayName,
        others: {
          for (final c in d.co) c.email: (role: AssignmentRole.co, name: c.displayName),
          for (final o in d.observers) o.email: (role: AssignmentRole.observer, name: o.displayName),
          if (d.controller != null) d.controller!.email: (role: AssignmentRole.controller, name: d.controller!.displayName),
          for (final p in v.deputies) p.email: (role: AssignmentRole.deputy, name: p.displayName),
        });
    final fresh = await load(v.id) ?? v;
    final ev = _ev();
    final head = l10n.tr('assignMsgEdited');
    await _record(fresh, ev, 'edited', {
      'text': [head, ...changes, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n'),
    });
    // Кому: новые исполнитель и соисполнители; в копии — постановщик,
    // заместители, контролирующий, наблюдатели и все, кого убрали.
    final mine = _mine(v);
    final to = <String, EmailAddress>{};
    final cc = <String, EmailAddress>{};
    void put(Map<String, EmailAddress> m, EmailAddress a) {
      final e = low(a.email);
      if (!e.contains('@') || mine.contains(e) || to.containsKey(e)) return;
      m.putIfAbsent(e, () => a);
    }

    put(to, d.executor);
    for (final c in d.co) {
      put(to, c);
    }
    for (final p in [...fresh.people, ...v.people]) {
      put(cc, _addr(p));
    }
    final parent = v.parentId == null ? null : await AssignmentStore.byId(_db, v.parentId!);
    final html = AssignmentCodec.body(
      id: v.id,
      greeting: await _greeting(d.executor, _account(v.row.accountId), l10n),
      introHtml: _changesHtml(head, changes, note),
      whatLabel: l10n.tr('assignWhatLabel'),
      what: title,
      description: desc,
      parentLine: parent == null ? null : l10n.tr('assignPartOf').replaceAll('{title}', parent.title),
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: d.due == null ? null : _dueLong(d.due!, l10n),
      footer: l10n
          .tr('assignFooter')
          .replaceAll('{accepted}', l10n.tr('assignReplyAccepted'))
          .replaceAll('{done}', l10n.tr('assignReplyDone')),
      extraHtml: _stageExtra(l10n,
          start: d.start,
          afterTitle: prev?.title,
          executor: d.executor,
          co: d.co,
          controller: d.controller,
          observers: d.observers,
          deputies: [for (final p in fresh.deputies) _addr(p)],
          checklist: newCk,
          files: [for (final f in fresh.files) f.name]),
      marker: _taskSnapshot(fresh, rev, ev),
      act: AssignmentAct.edited,
    );
    await _sendTo(account, (to: to.values.toList(), cc: [for (final e in cc.entries) if (!to.containsKey(e.key)) e.value]),
        subject: _subject(fresh, l10n), html: html, inReplyTo: await _inReplyTo(v), files: newFiles);
    _reminders();
    return true;
  }

  /// Удалить этап [v] из проекта: снят и убран из плана — у себя и у его
  /// участников (письмо «Этап удалён»).
  Future<void> removeStage(AssignmentView v, {String? note}) async {
    if (!v.outgoing) return;
    final l10n = _l10n();
    final rev = _nextRev(v);
    final ev = _ev();
    await AssignmentStore.update(_db, v.id,
        status: AssignmentStatus.cancelled, archived: true, revision: rev, waiting: false);
    final text = [
      l10n.tr('assignMsgStageRemoved').replaceAll('{title}', v.row.title),
      if ((note ?? '').trim().isNotEmpty) note!.trim(),
    ].join('\n');
    await _record(v, ev, 'removed', {'text': text});
    await _notify(v, text, _taskSnapshot(v, rev, ev, removed: true), act: AssignmentAct.cancelled);
    _reminders();
  }

  /// Изменить проект [project] (постановщик или заместитель): название,
  /// описание, начало, видимость плана, наблюдатели, контролирующий,
  /// файлы, этапы — новые, изменённые, удалённые. Этапам — письма их
  /// участникам, всем участникам — письмо проекта: что изменилось и план.
  Future<void> updateProject(AssignmentView project, ProjectDraft d, {String? note}) async {
    final account = _account(project.row.accountId);
    if (account == null || !project.outgoing) return;
    final l10n = _l10n();
    final fmt = DateFormat('d MMM', l10n.localeCode);
    String low(String e) => e.trim().toLowerCase();
    final old = await stages(project.id);
    final changes = <String>[];
    final ids = [for (final st in d.stages) st.id ?? AssignmentCodec.newId()];

    // ── Сам проект ──
    final title = d.title.trim().isEmpty ? project.row.title : d.title.trim();
    if (title != project.row.title) changes.add(l10n.tr('assignChTitle').replaceAll('{v}', title));
    final desc = d.description.trim();
    if (desc != (project.row.description ?? '').trim()) changes.add(l10n.tr('assignChDesc'));
    if (!_sameDay(d.start, project.start)) {
      changes.add(l10n
          .tr('assignChStart')
          .replaceAll('{old}', project.start == null ? l10n.tr('noDueDate') : fmt.format(project.start!))
          .replaceAll('{new}', d.start == null ? l10n.tr('noDueDate') : fmt.format(d.start!)));
    }
    if (d.visibility != project.row.visibility) {
      changes.add(l10n.tr(d.visibility == 0 ? 'assignChVisAll' : 'assignChVisOwn'));
    }
    final oldObs = {for (final p in project.observers) low(p.email): p};
    final newObs = {for (final o in d.observers) low(o.email): o};
    final obs = [
      for (final e in newObs.entries)
        if (!oldObs.containsKey(e.key)) '+${_who(e.value)}',
      for (final e in oldObs.entries)
        if (!newObs.containsKey(e.key)) '−${_who(_addr(e.value))}',
    ];
    if (obs.isNotEmpty) changes.add(l10n.tr('assignChObservers').replaceAll('{list}', obs.join(', ')));
    final oldCtl = project.controller;
    if (low(d.controller?.email ?? '') != low(oldCtl?.email ?? '')) {
      changes.add(l10n
          .tr('assignChController')
          .replaceAll('{old}', oldCtl == null ? '—' : _who(_addr(oldCtl)))
          .replaceAll('{new}', d.controller == null ? '—' : _who(d.controller!)));
    }
    bool same(AssignmentFile a, AssignmentFile b) => a.name == b.name && a.path == b.path && a.mailId == b.mailId;
    final added = [for (final f in d.files) if (!project.files.any((o) => same(o, f))) f];
    final kept = [for (final f in project.files) if (d.files.any((x) => same(x, f))) f];
    final removedFiles = [for (final f in project.files) if (!d.files.any((x) => same(x, f))) f];
    final newFiles = await _keepFiles(project.id, added);
    if (newFiles.isNotEmpty) {
      changes.add(l10n.tr('assignChFilesAdded').replaceAll('{list}', newFiles.map((f) => f.name).join(', ')));
    }
    if (removedFiles.isNotEmpty) {
      changes.add(l10n.tr('assignChFilesRemoved').replaceAll('{list}', removedFiles.map((f) => f.name).join(', ')));
    }
    await AssignmentStore.update(_db, project.id,
        title: title,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
        start: d.start,
        clearStart: d.start == null,
        visibility: d.visibility,
        files: [...kept, ...newFiles]);
    await AssignmentStore.setParticipants(_db, project.id,
        ownerEmail: project.row.ownerEmail,
        ownerName: project.owner?.displayName,
        others: {
          for (final o in d.observers) o.email: (role: AssignmentRole.observer, name: o.displayName),
          if (d.controller != null) d.controller!.email: (role: AssignmentRole.controller, name: d.controller!.displayName),
          for (final p in project.deputies) p.email: (role: AssignmentRole.deputy, name: p.displayName),
        });

    // ── Этапы ──
    for (final o in old) {
      if (ids.contains(o.id)) continue;
      await removeStage(o);
      changes.add(l10n.tr('assignChStageRemoved').replaceAll('{title}', o.row.title));
    }
    final fresh = await load(project.id) ?? project;
    for (var i = 0; i < d.stages.length; i++) {
      final st = d.stages[i];
      final a = st.after;
      final afterId = a == null || a < 0 || a >= ids.length || a == i ? null : ids[a];
      final cur = old.where((o) => o.id == st.id).firstOrNull;
      if (cur == null) {
        await addStage(fresh, st, afterId: afterId, id: ids[i], order: i);
        changes.add(l10n.tr('assignChStageAdded').replaceAll('{title}', st.title.trim()));
      } else if (await editTask(cur, st, afterId: afterId, order: i)) {
        changes.add(l10n.tr('assignChStageEdited').replaceAll('{title}', st.title.trim()));
      }
    }
    final list = await stages(project.id);
    final dues = [for (final v in list) if (v.due != null) v.due!];
    if (dues.isNotEmpty) {
      await AssignmentStore.update(_db, project.id, due: dues.reduce((a, b) => a.isAfter(b) ? a : b));
    }
    if (changes.isNotEmpty || (note ?? '').trim().isNotEmpty) {
      final p2 = await load(project.id) ?? fresh;
      await _sendProject(p2, list, changes: changes, note: note, files: newFiles);
    }
    _reminders();
  }

  /// Права постановщика другому человеку [person] (просьба владельца
  /// 13.11.2026: смена вахты, начальник и заместитель). [handover] —
  /// передать полностью: постановщиком станет он, я — наблюдателем; иначе
  /// он — заместитель с теми же правами, права у обоих. Ему — полные
  /// сведения (у проекта — все этапы целиком), остальным участникам — кто
  /// теперь с правами постановщика.
  Future<void> grantRights(AssignmentView v, EmailAddress person, {bool handover = false, String? note}) async {
    final account = _account(v.row.accountId);
    if (account == null || !v.outgoing) return;
    final l10n = _l10n();
    final email = person.email.trim().toLowerCase();
    if (!email.contains('@')) return;
    final mine = _mine(v);
    final myEmail = _myEmail(v).toLowerCase();
    final deputies = <String, String?>{for (final p in v.deputies) p.email.toLowerCase(): p.displayName};
    final oldOwner = v.row.ownerEmail.toLowerCase();
    var owner = oldOwner;
    if (!handover) {
      deputies[email] = person.displayName;
    } else if (v.iOwn) {
      deputies.remove(email);
      owner = email;
    } else {
      deputies.removeWhere((k, _) => mine.contains(k));
      deputies[email] = person.displayName;
    }
    deputies.remove(owner);
    final ids = [v.id, if (v.isProject) for (final r in await AssignmentStore.stagesOf(_db, v.id)) r.id];
    await AssignmentStore.setDeputies(_db, v.id, deputies);
    if (handover) {
      for (final id in ids) {
        final roles = {for (final p in await AssignmentStore.participants(_db, id)) p.email.toLowerCase(): p.role};
        if (owner != oldOwner) {
          await AssignmentStore.update(_db, id, ownerEmail: owner);
          final r = roles[owner];
          if (r == null || r == AssignmentRole.observer || r == AssignmentRole.deputy) {
            await AssignmentStore.addParticipant(_db, id, owner, AssignmentRole.owner, name: person.displayName);
          }
        }
        // Я — наблюдатель (если в этапе у меня нет другой роли).
        final mr = roles[myEmail];
        if (mr == null || mr == AssignmentRole.owner || mr == AssignmentRole.deputy) {
          await AssignmentStore.addParticipant(_db, id, myEmail, AssignmentRole.observer, name: account.displayName);
        }
      }
    }
    final rev = _nextRev(v);
    await AssignmentStore.update(_db, v.id, revision: rev);
    final fresh = await load(v.id) ?? v;
    final list = v.isProject ? await stages(v.id) : const <AssignmentView>[];
    final ev = _ev();
    final name = _who(person);
    final textAll = l10n.tr(handover ? 'assignRightsOwnerAll' : 'assignRightsDeputyAll').replaceAll('{name}', name);
    await _record(fresh, ev, 'rights', {
      'text': [textAll, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n'),
    });
    // 1) Ему — полные сведения: поручение или проект со всеми этапами.
    final html = AssignmentCodec.body(
      id: v.id,
      greeting: await _greeting(person, account, l10n),
      introHtml: _changesHtml(l10n.tr(handover ? 'assignRightsOwnerYou' : 'assignRightsDeputyYou'), const [], note),
      whatLabel: l10n.tr(v.isProject ? 'assignProjectLabel' : 'assignWhatLabel'),
      what: fresh.row.title,
      description: fresh.row.description,
      dueLabel: l10n.tr('assignDueLabel'),
      dueLine: fresh.due == null ? null : _dueLong(fresh.due!, l10n),
      footer: l10n.tr('assignRightsFooter'),
      extraHtml: v.isProject
          ? _planHtml(mailPlan(list), l10n)
          : _stageExtra(l10n,
              start: fresh.start,
              executor: fresh.assignee == null ? null : _addr(fresh.assignee!),
              co: [for (final p in fresh.coExecutors) _addr(p)],
              controller: fresh.controller == null ? null : _addr(fresh.controller!),
              observers: [for (final p in fresh.observers) _addr(p)],
              deputies: [for (final p in fresh.deputies) _addr(p)],
              checklist: [for (final c in fresh.checklist) c.text],
              files: [for (final f in fresh.files) f.name]),
      marker: v.isProject ? _projectSnapshot(fresh, list, rev, ev, full: true) : _taskSnapshot(fresh, rev, ev),
      act: AssignmentAct.edited,
    );
    await _send(account, person,
        subject: v.isProject ? _projectSubject(fresh, l10n) : _subject(fresh, l10n),
        html: html,
        files: [for (final f in fresh.files) if (f.path != null) f]);
    // 2) Остальным участникам — кто теперь с правами постановщика.
    final people = v.isProject
        ? _projectPeople(fresh, list, skip: {email})
        : (
            to: [
              for (final p in fresh.people)
                if ((p.role == AssignmentRole.responsible || p.role == AssignmentRole.co) &&
                    !mine.contains(p.email.toLowerCase()) &&
                    p.email.toLowerCase() != email)
                  _addr(p),
            ],
            cc: [
              for (final p in fresh.people)
                if (p.role != AssignmentRole.responsible &&
                    p.role != AssignmentRole.co &&
                    !mine.contains(p.email.toLowerCase()) &&
                    p.email.toLowerCase() != email)
                  _addr(p),
            ],
          );
    final marker = v.isProject ? _projectSnapshot(fresh, list, rev, ev) : _taskSnapshot(fresh, rev, ev);
    await _sendTo(account, people,
        subject: v.isProject ? _projectSubject(fresh, l10n) : _subject(fresh, l10n),
        html: assignmentNoteHtml([textAll, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n'), marker, v.id,
            act: AssignmentAct.edited),
        inReplyTo: await _inReplyTo(v));
    _reminders();
  }

  /// Снять права заместителя [email]: он остаётся наблюдателем.
  Future<void> revokeRights(AssignmentView v, String email) async {
    final account = _account(v.row.accountId);
    if (account == null || !v.outgoing) return;
    final l10n = _l10n();
    final e = email.trim().toLowerCase();
    final who = v.deputies.where((p) => p.email.toLowerCase() == e).firstOrNull;
    if (who == null) return;
    await AssignmentStore.setDeputies(
        _db, v.id, {for (final p in v.deputies) if (p.email.toLowerCase() != e) p.email.toLowerCase(): p.displayName});
    await AssignmentStore.addParticipant(_db, v.id, e, AssignmentRole.observer, name: who.displayName);
    final rev = _nextRev(v);
    await AssignmentStore.update(_db, v.id, revision: rev);
    final fresh = await load(v.id) ?? v;
    final list = v.isProject ? await stages(v.id) : const <AssignmentView>[];
    final ev = _ev();
    final text = l10n.tr('assignRightsRevoked').replaceAll('{name}', _who(_addr(who)));
    await _record(fresh, ev, 'rights', {'text': text});
    final mine = _mine(v);
    final people = v.isProject
        ? _projectPeople(fresh, list)
        : (
            to: [
              for (final p in fresh.people)
                if ((p.role == AssignmentRole.responsible || p.role == AssignmentRole.co) && !mine.contains(p.email.toLowerCase()))
                  _addr(p),
            ],
            cc: [
              for (final p in fresh.people)
                if (p.role != AssignmentRole.responsible && p.role != AssignmentRole.co && !mine.contains(p.email.toLowerCase()))
                  _addr(p),
            ],
          );
    await _sendTo(account, people,
        subject: v.isProject ? _projectSubject(fresh, l10n) : _subject(fresh, l10n),
        html: assignmentNoteHtml(text, v.isProject ? _projectSnapshot(fresh, list, rev, ev) : _taskSnapshot(fresh, rev, ev), v.id,
            act: AssignmentAct.edited),
        inReplyTo: await _inReplyTo(v));
  }

  // ── Шаблоны проектов ──

  Future<List<AssignmentTemplate>> templates() =>
      (_db.select(_db.assignmentTemplates)..orderBy([(t) => OrderingTerm(expression: t.name)])).get();

  Future<void> saveTemplate(String name, ProjectDraft d) async {
    final base = d.start ?? d.stages.map((s) => s.start).whereType<DateTime>().fold<DateTime?>(null,
        (a, b) => a == null || b.isBefore(a) ? b : a) ?? DateTime.now();
    await _db.into(_db.assignmentTemplates).insert(
          AssignmentTemplatesCompanion.insert(
            id: const Uuid().v4(),
            name: name.trim(),
            payloadJson: d.toTemplateJson(base),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> deleteTemplate(String id) =>
      (_db.delete(_db.assignmentTemplates)..where((t) => t.id.equals(id))).go();

  /// Убрать поручение у себя (письма остаются в почте).
  Future<void> delete(AssignmentView v) async {
    await AssignmentStore.delete(_db, v.id);
    _reminders();
  }

  /// Разобрать письма поручений после синхронизации (ответы, новые
  /// поручения мне). Не чаще раза в 20 секунд.
  static DateTime? _lastScan;
  static Future<int> scanAfterSync(AppDatabase db, List<AccountModel> accounts) async {
    final now = DateTime.now();
    if (_lastScan != null && now.difference(_lastScan!) < const Duration(seconds: 20)) return 0;
    // Окно — двое суток назад от прошлого разбора (письма приходят с
    // опозданием, повторный разбор письма ничего не меняет).
    final since = (_lastScan ?? now.subtract(const Duration(days: 30))).subtract(const Duration(days: 2));
    _lastScan = now;
    return AssignmentStore.scan(db, assignmentMine(accounts), since: since);
  }
}

/// Срок поручения «до {дата}» для экранов.
String assignmentDueText(DateTime due, AppLocalizations l10n) =>
    DateFormat(dueHasTime(due) ? 'EEE, d MMM, HH:mm' : 'EEE, d MMM', l10n.localeCode).format(due);

/// Срок [day] (дата) с временем прежнего срока [keep] — перенос «на завтра»
/// не теряет назначенный час.
DateTime assignmentDueOn(DateTime day, DateTime? keep) => dueHasTime(keep)
    ? DateTime(day.year, day.month, day.day, keep!.hour, keep.minute)
    : DateTime(day.year, day.month, day.day);

/// Помощник для экранов: unawaited с журналом.
void assignmentFire(Future<void> f) => unawaited(f.catchError((Object e) {
      AppLogger.warning('Поручение: $e');
    }));


/// План проекта по его этапам (для диаграммы и сдвига сроков).
List<PlanStage> planOf(List<AssignmentView> stages, {Map<String, DateTime> doneAt = const {}}) => [
      for (final v in stages)
        PlanStage(
          id: v.id,
          title: v.row.title,
          start: v.start,
          due: v.due,
          after: v.row.afterId,
          assignee: v.assignee?.email,
          order: v.row.stageOrder,
          status: v.status,
          progress: v.progress,
          doneAt: doneAt[v.id] ?? (v.status == AssignmentStatus.done ? v.row.updatedAt.toLocal() : null),
        ),
    ];

/// Этап при создании проекта. [after] — номер предыдущего этапа в списке
/// (последовательно) или null (параллельно).
class StageDraft {
  /// Код этапа — при изменении созданного проекта (null — новый этап).
  String? id;
  String title;
  String description;
  EmailAddress executor;
  List<EmailAddress> co;
  EmailAddress? controller;
  List<EmailAddress> observers;
  DateTime? start;
  DateTime? due;
  int? after;
  List<String> checklist;
  List<AssignmentFile> files;

  StageDraft({
    this.id,
    required this.title,
    required this.executor,
    this.description = '',
    List<EmailAddress>? co,
    this.controller,
    List<EmailAddress>? observers,
    this.start,
    this.due,
    this.after,
    List<String>? checklist,
    List<AssignmentFile>? files,
  })  : co = co ?? [],
        observers = observers ?? [],
        checklist = checklist ?? [],
        files = files ?? [];

  /// Этап или поручение как черновик — для «Изменить».
  factory StageDraft.fromView(AssignmentView v, {int? after}) {
    EmailAddress addr(AssignmentParticipant x) => EmailAddress(email: x.email, displayName: x.displayName);
    return StageDraft(
      id: v.id,
      title: v.row.title,
      description: v.row.description ?? '',
      executor: v.assignee == null ? const EmailAddress(email: '') : addr(v.assignee!),
      co: [for (final p in v.coExecutors) addr(p)],
      controller: v.controller == null ? null : addr(v.controller!),
      observers: [for (final p in v.observers) addr(p)],
      start: v.start,
      due: v.due,
      after: after,
      checklist: [for (final c in v.checklist) c.text],
      files: [...v.files],
    );
  }
}

/// Проект при создании: название, описание, начало, файлы, наблюдатели и
/// контролирующий по умолчанию (для всех этапов), этапы.
class ProjectDraft {
  String title;
  String description;
  DateTime? start;
  List<AssignmentFile> files;
  List<EmailAddress> observers;
  EmailAddress? controller;
  List<StageDraft> stages;

  /// Видимость плана (13.11.2026): 0 — все участники видят весь план и ход
  /// работ, 1 — каждый видит только свои этапы.
  int visibility;

  ProjectDraft({
    this.title = '',
    this.description = '',
    this.start,
    List<AssignmentFile>? files,
    List<EmailAddress>? observers,
    this.controller,
    List<StageDraft>? stages,
    this.visibility = 0,
  })  : files = files ?? [],
        observers = observers ?? [],
        stages = stages ?? [];

  /// Черновик из созданного проекта [p] и его этапов [stages] — для
  /// «Изменить проект» (13.11.2026): у этапа — его код, «после этапа» —
  /// номером в списке.
  static ProjectDraft fromProject(AssignmentView p, List<AssignmentView> stages) {
    EmailAddress addr(AssignmentParticipant x) => EmailAddress(email: x.email, displayName: x.displayName);
    final idx = {for (var i = 0; i < stages.length; i++) stages[i].id: i};
    return ProjectDraft(
      title: p.row.title,
      description: p.row.description ?? '',
      start: p.start,
      files: [...p.files],
      observers: [for (final o in p.observers) addr(o)],
      controller: p.controller == null ? null : addr(p.controller!),
      visibility: p.row.visibility,
      stages: [for (final s in stages) StageDraft.fromView(s, after: idx[s.row.afterId])],
    );
  }

  static Map<String, Object?> _addr(EmailAddress a) => {'e': a.email, if (a.displayName != null) 'n': a.displayName};
  static EmailAddress _fromAddr(Object? m) =>
      m is Map ? EmailAddress(email: '${m['e'] ?? ''}', displayName: m['n'] as String?) : const EmailAddress(email: '');

  /// Шаблон: даты — смещениями в днях от [base]; файлы не сохраняются.
  String toTemplateJson(DateTime base) {
    final b = DateTime(base.year, base.month, base.day);
    int? off(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day).difference(b).inDays;
    return jsonEncode({
      'title': title,
      'description': description,
      'observers': [for (final o in observers) _addr(o)],
      if (controller != null) 'controller': _addr(controller!),
      'stages': [
        for (final s in stages)
          {
            'title': s.title,
            'description': s.description,
            'executor': _addr(s.executor),
            'co': [for (final c in s.co) _addr(c)],
            if (s.controller != null) 'controller': _addr(s.controller!),
            'observers': [for (final o in s.observers) _addr(o)],
            if (off(s.start) != null) 's': off(s.start),
            if (off(s.due) != null) 'e': off(s.due),
            if (s.after != null) 'after': s.after,
            'checklist': s.checklist,
          },
      ],
    });
  }

  /// Проект из шаблона с началом [start].
  static ProjectDraft fromTemplateJson(String json, DateTime start) {
    final m = jsonDecode(json) as Map;
    final b = DateTime(start.year, start.month, start.day);
    DateTime? at(Object? off) => off is num ? b.add(Duration(days: off.toInt())) : null;
    return ProjectDraft(
      title: '${m['title'] ?? ''}',
      description: '${m['description'] ?? ''}',
      start: b,
      observers: [for (final o in (m['observers'] as List? ?? const [])) _fromAddr(o)],
      controller: m['controller'] == null ? null : _fromAddr(m['controller']),
      stages: [
        for (final s in (m['stages'] as List? ?? const []).whereType<Map>())
          StageDraft(
            title: '${s['title'] ?? ''}',
            description: '${s['description'] ?? ''}',
            executor: _fromAddr(s['executor']),
            co: [for (final c in (s['co'] as List? ?? const [])) _fromAddr(c)],
            controller: s['controller'] == null ? null : _fromAddr(s['controller']),
            observers: [for (final o in (s['observers'] as List? ?? const [])) _fromAddr(o)],
            start: at(s['s']),
            due: at(s['e']),
            after: (s['after'] as num?)?.toInt(),
            checklist: [for (final c in (s['checklist'] as List? ?? const [])) '$c'],
          ),
      ],
    );
  }
}

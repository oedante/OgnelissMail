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

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingMode, OrderingTerm, TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../mail/offline_send_service.dart';
import '../mail/own_addresses.dart';
import 'assignment_codec.dart';
import 'assignment_store.dart';

export 'assignment_codec.dart' show AssignmentStatus;
export 'assignment_store.dart' show AssignmentView;

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

  String _dueShort(DateTime d) => DateFormat('dd.MM').format(d);
  String _dueLong(DateTime d, AppLocalizations l10n) => DateFormat('EEEE, d MMMM', l10n.localeCode).format(d);

  static String _firstName(EmailAddress a) {
    final n = (a.displayName ?? '').trim();
    if (n.isNotEmpty) {
      final parts = n.split(RegExp(r'\s+'));
      // «Фамилия Имя Отчество» и «Имя Фамилия»: в обращении — второе слово
      // из трёх, иначе первое.
      return parts.length == 3 ? parts[1] : parts.first;
    }
    return a.email.split('@').first;
  }

  /// Поручить: по поручению каждому исполнителю (у каждого — свой статус).
  /// Возвращает коды поручений. [parent] — подзадача этого поручения.
  Future<List<String>> create({
    required AccountModel account,
    required String title,
    String? description,
    required List<EmailAddress> assignees,
    DateTime? due,
    int priority = 1,
    Email? source,
    AssignmentView? parent,
  }) async {
    final l10n = _l10n();
    final now = DateTime.now();
    final ids = <String>[];
    for (final to in assignees) {
      final id = AssignmentCodec.newId();
      final ev = 'created:$id';
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
          priority: priority,
          sourceEmailId: source?.id,
          at: now,
          outgoing: true,
          eventId: ev,
          parentId: parent?.id);
      final srcFrom = source == null ? null : ((source.fromName ?? '').trim().isNotEmpty ? source.fromName! : source.fromEmail);
      final body = AssignmentCodec.body(
        id: id,
        greeting: l10n.tr('assignGreeting').replaceAll('{name}', _firstName(to)),
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
        due: due,
        to: to.email,
        title: title.trim(),
        ev: ev,
      );
      await _send(account, to,
          subject: AssignmentCodec.subject(
              prefix: l10n.tr('assignSubject'),
              title: title,
              due: due == null ? null : l10n.tr('assignDueShort').replaceAll('{due}', _dueShort(due))),
          html: body);
      ids.add(id);
    }
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
  Future<void> _notify(AssignmentView v, String text, String marker, {List<AssignmentFile> files = const []}) async {
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
    final fromExecutor = !v.outgoing && !v.iControl && (v.iExecute || v.iCoExecute);
    final to = <EmailAddress>[];
    final cc = <EmailAddress>[];
    if (fromExecutor) {
      to
        ..add(ownerAddr)
        ..addAll(controller);
      cc
        ..addAll(executors)
        ..addAll(observers);
    } else {
      to.addAll(executors);
      cc
        ..add(ownerAddr)
        ..addAll(controller)
        ..addAll(observers);
    }
    bool notMe(EmailAddress a) => !mine.contains(a.email.trim().toLowerCase());
    final toList = to.where(notMe).toList();
    final ccList = cc.where(notMe).toList();
    if (toList.isEmpty && ccList.isEmpty) return;
    // Ответ — в ту же цепочку: на последнее письмо поручения (полученное
    // или своё отправленное, когда оно пришло в «Отправленные»).
    String? inReplyTo;
    try {
      final linked = await (_db.select(_db.assignmentEvents)
            ..where((x) => x.assignmentId.equals(v.id) & x.sourceEmailId.isNotNull())
            ..orderBy([(x) => OrderingTerm(expression: x.createdAt, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();
      final mailId = linked?.sourceEmailId;
      if (mailId != null) {
        inReplyTo = (await _db.getEmailById(mailId, accountId: v.row.accountId))?.internetMessageId;
      }
    } catch (_) {}
    final first = toList.isNotEmpty ? toList.first : ccList.first;
    await _send(account, first,
        moreTo: toList.skip(1).toList(),
        cc: toList.isEmpty ? ccList.skip(1).toList() : ccList,
        subject: _subject(v, _l10n()),
        html: assignmentNoteHtml(text, marker, v.id),
        inReplyTo: inReplyTo,
        files: files);
  }

  /// Мой адрес в поручении [v] (для истории).
  String _myEmail(AssignmentView v) {
    if (v.outgoing) return v.row.ownerEmail;
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
  Future<void> setStatus(AssignmentView v, int status, {String? note}) async {
    if (status == v.status) return;
    final l10n = _l10n();
    final ev = _ev();
    final text = switch (status) {
      AssignmentStatus.done => l10n.tr('assignMsgAccepted'),
      AssignmentStatus.inProgress when v.outgoing => l10n.tr('assignMsgReturned'),
      AssignmentStatus.inProgress => l10n.tr('assignReplyAccepted'),
      AssignmentStatus.review => l10n.tr('assignReplyDone'),
      AssignmentStatus.cancelled => l10n.tr('assignMsgCancelled'),
      _ => '',
    };
    final full = [text, if ((note ?? '').trim().isNotEmpty) note!.trim()].join('\n');
    await AssignmentStore.update(_db, v.id, status: status);
    await _record(v, ev, 'status', {'status': status, 'text': full});
    // Исполнитель — с отметкой чек-листа: у постановщика виден ход работ.
    final checks = (v.iExecute || v.iCoExecute) && v.checklist.isNotEmpty ? ChecklistItem.bits(v.checklist) : null;
    await _notify(v, full, AssignmentCodec.statusMarker(v.id, status, ev: ev, checks: checks));
    // Этап принят — следующим этапам «Можно начинать» (письмо уходит от
    // постановщика; у контролирующего — при следующем разборе почты у
    // постановщика).
    if (status == AssignmentStatus.done && v.outgoing) unawaited(dispatchPending());
  }

  /// Поручивший отмечает статус сам (2.2.1, замечание владельца 10.11.2026:
  /// исполнитель ответил «Приятно» вместо «Принято» — статус не сменился, а
  /// поменять было нечем). Только у себя: письмо исполнителю не уходит;
  /// в истории — «Отмечено вручную».
  Future<void> markLocally(AssignmentView v, int status) async {
    if (status == v.status) return;
    await AssignmentStore.update(_db, v.id, status: status);
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
    await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: v.due, ev: ev));
  }

  /// Новый срок (поручивший — с письмом исполнителю; исполнитель — только
  /// у себя).
  Future<void> reschedule(AssignmentView v, DateTime? due) async {
    await AssignmentStore.update(_db, v.id, due: due, clearDue: due == null);
    if (!v.outgoing) return;
    final l10n = _l10n();
    final ev = _ev();
    final text = due == null
        ? l10n.tr('assignMsgNoDue')
        : l10n.tr('assignMsgNewDue').replaceAll('{due}', _dueLong(due, l10n));
    await _record(v, ev, 'due', {'text': text, if (due != null) 'due': due.toIso8601String()});
    await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: due, ev: ev));
  }

  // ═══════════════ Проекты с этапами (12.11.2026) ═══════════════

  String _dates(DateTime? start, DateTime? due, AppLocalizations l10n) {
    final f = DateFormat('d MMM', l10n.localeCode);
    if (start != null && due != null) return '${f.format(start)} — ${f.format(due)}';
    if (due != null) return l10n.tr('assignDueShort').replaceAll('{due}', f.format(due));
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
          order: i,
        ),
    ];
    final planJson = PlanStage.encode(plan);
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
    final lines = StringBuffer('<p><b>${assignmentEsc(l10n.tr('assignPlanLabel'))}</b></p><ol>');
    for (var i = 0; i < d.stages.length; i++) {
      final st = d.stages[i];
      final dates = _dates(st.start, st.due, l10n);
      final after = st.after == null
          ? ''
          : ' (${l10n.tr('assignAfterStage').replaceAll('{title}', d.stages[st.after!].title.trim())})';
      lines.write('<li><b>${assignmentEsc(st.title.trim())}</b> — ${assignmentEsc(_who(st.executor))}'
          '${dates.isEmpty ? '' : ', ${assignmentEsc(dates)}'}${assignmentEsc(after)}</li>');
    }
    lines.write('</ol>');
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
          plan: planJson),
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
    return pid;
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
  }) async {
    final ctl = controller;
    final extra = StringBuffer();
    final dates = _dates(st.start, st.due, l10n);
    if (dates.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignDatesLabel'))}</b> ${assignmentEsc(dates)}</p>');
    }
    if (afterTitle != null) {
      extra.write('<p>${assignmentEsc(l10n.tr('assignStartAfterNote').replaceAll('{title}', afterTitle))}</p>');
    }
    extra.write('<p>${assignmentEsc(l10n.tr('assignRoleExecutor'))} ${assignmentEsc(_who(st.executor))}');
    if (st.co.isNotEmpty) {
      extra.write('<br>${assignmentEsc(l10n.tr('assignRoleCo'))} ${assignmentEsc(st.co.map(_who).join(', '))}');
    }
    if (ctl != null) extra.write('<br>${assignmentEsc(l10n.tr('assignRoleController'))} ${assignmentEsc(_who(ctl))}');
    if (observers.isNotEmpty) {
      extra.write('<br>${assignmentEsc(l10n.tr('assignRoleObservers'))} ${assignmentEsc(observers.map(_who).join(', '))}');
    }
    extra.write('</p>');
    final checklist = [for (final c in st.checklist) if (c.trim().isNotEmpty) c.trim()];
    if (checklist.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignChecklistLabel'))}</b></p><ul>');
      for (final c in checklist) {
        extra.write('<li>${assignmentEsc(c)}</li>');
      }
      extra.write('</ul>');
    }
    if (files.isNotEmpty) {
      extra.write('<p><b>${assignmentEsc(l10n.tr('assignFilesLabel'))}</b> '
          '${assignmentEsc(files.map((f) => f.name).join(', '))}</p>');
    }
    final ev = 'created:$id';
    final body = AssignmentCodec.body(
      id: id,
      greeting: l10n.tr('assignGreeting').replaceAll('{name}', _firstName(st.executor)),
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
      extraHtml: extra.toString(),
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
      ),
    );
    await _send(account, st.executor,
        moreTo: st.co,
        cc: [if (ctl != null) ctl, ...observers],
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
  Future<String?> addStage(AssignmentView project, StageDraft st, {String? afterId}) async {
    final account = _account(project.row.accountId);
    if (account == null || !project.outgoing) return null;
    final l10n = _l10n();
    final now = DateTime.now();
    final id = AssignmentCodec.newId();
    final existing = await AssignmentStore.stagesOf(_db, project.id);
    final after = afterId == null ? null : existing.where((x) => x.id == afterId).firstOrNull;
    final files = await _keepFiles(id, st.files);
    final observers = [
      ...st.observers,
      for (final p in project.observers) EmailAddress(email: p.email, displayName: p.displayName),
    ];
    final pc = project.controller;
    final ctl = st.controller ?? (pc == null ? null : EmailAddress(email: pc.email, displayName: pc.displayName));
    await AssignmentStore.insert(_db,
        id: id,
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
        eventId: 'created:$id',
        parentId: project.id,
        afterId: after?.id,
        order: existing.length,
        checklist: [for (final c in st.checklist) if (c.trim().isNotEmpty) ChecklistItem(c.trim())],
        files: files,
        others: {
          for (final c in st.co) c.email: (role: AssignmentRole.co, name: c.displayName),
          for (final o in observers) o.email: (role: AssignmentRole.observer, name: o.displayName),
          if (ctl != null) ctl.email: (role: AssignmentRole.controller, name: ctl.displayName),
        });
    await _sendStage(account, l10n,
        id: id,
        projectId: project.id,
        projectTitle: project.row.title,
        st: st,
        order: existing.length,
        afterId: after?.id,
        afterTitle: after?.title,
        controller: ctl,
        observers: observers,
        files: files);
    final dues = [for (final r in await AssignmentStore.stagesOf(_db, project.id)) if (r.dueAt != null) r.dueAt!];
    if (dues.isNotEmpty) {
      await AssignmentStore.update(_db, project.id, due: dues.reduce((a, b) => a.isAfter(b) ? a : b));
    }
    // Предыдущий этап уже принят — «Можно начинать» сразу.
    if (after != null && after.status == AssignmentStatus.done) await dispatchPending();
    return id;
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
          checklist: checklist,
        ) +
        AssignmentCodec.peopleMarker(v.id, person.email, AssignmentRole.co, name: person.displayName, ev: ev);
    final html = AssignmentCodec.body(
      id: v.id,
      greeting: l10n.tr('assignGreeting').replaceAll('{name}', _firstName(person)),
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
  Future<void> reportProgress(AssignmentView v, {String? note}) async {
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
    if (text.isEmpty) return;
    await _record(v, ev, 'progress', {'text': text});
    await _notify(v, text,
        AssignmentCodec.statusMarker(v.id, v.status, ev: ev, checks: items.isEmpty ? null : ChecklistItem.bits(items)));
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
    await _notify(v, text, AssignmentCodec.statusMarker(v.id, v.status, ev: ev), files: kept);
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
  Future<void> dispatchPending() async {
    await _closeDoneProjects();
    final waiting = await (_db.select(_db.assignments)
          ..where((a) => a.waiting.equals(true) & a.afterId.isNotNull() & a.status.isIn(const [1, 2, 3])))
        .get();
    if (waiting.isEmpty) return;
    final l10n = _l10n();
    for (final w in waiting) {
      final prev = await AssignmentStore.byId(_db, w.afterId!);
      if (prev == null || prev.status != AssignmentStatus.done) continue;
      final v = await load(w.id);
      if (v == null) continue;
      await AssignmentStore.update(_db, v.id, waiting: false);
      if (!v.outgoing) continue; // письмо — от постановщика
      final ev = _ev();
      final text = l10n.tr('assignMsgGo').replaceAll('{title}', prev.title);
      await _record(v, ev, 'go', {'text': text});
      await _notify(v, text, AssignmentCodec.statusMarker(v.id, v.status, ev: ev, go: true));
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
      await _notify(v, text, AssignmentCodec.taskMarker(id: v.id, due: m.due, start: m.start, ev: ev));
    }
    // Срок проекта — по последнему этапу.
    final dues = [for (final v in await stages(projectId)) if (v.due != null) v.due!];
    if (dues.isNotEmpty) {
      await AssignmentStore.update(_db, projectId, due: dues.reduce((a, b) => a.isAfter(b) ? a : b));
    }
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
  Future<void> delete(AssignmentView v) => AssignmentStore.delete(_db, v.id);

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
    DateFormat('EEE, d MMM', l10n.localeCode).format(due);

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

  ProjectDraft({
    this.title = '',
    this.description = '',
    this.start,
    List<AssignmentFile>? files,
    List<EmailAddress>? observers,
    this.controller,
    List<StageDraft>? stages,
  })  : files = files ?? [],
        observers = observers ?? [],
        stages = stages ?? [];

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

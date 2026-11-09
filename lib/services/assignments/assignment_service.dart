// lib/services/assignments/assignment_service.dart
// Действия с поручениями (решения владельца 09.11.2026; описание и макеты —
// docs/design/MOCKUPS_MY_DAY_TASKS.md). Каждое действие — запись у себя и
// письмо другой стороне: поручение исполнителю; «принято», «вернул на
// доработку», «снято», напоминание, новый срок — исполнителю; «Принято»,
// «Готово» исполнителя — поручившему. Письма уходят обычной отправкой
// (без сети — из очереди); разбор ответов — assignment_store.dart.

import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
  /// Возвращает коды поручений.
  Future<List<String>> create({
    required AccountModel account,
    required String title,
    String? description,
    required List<EmailAddress> assignees,
    DateTime? due,
    int priority = 1,
    Email? source,
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
          eventId: ev);
      final srcFrom = source == null ? null : ((source.fromName ?? '').trim().isNotEmpty ? source.fromName! : source.fromEmail);
      final body = AssignmentCodec.body(
        id: id,
        greeting: l10n.tr('assignGreeting').replaceAll('{name}', _firstName(to)),
        whatLabel: l10n.tr('assignWhatLabel'),
        what: title.trim(),
        description: description,
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
              prefix: l10n.tr('assignSubject'), title: title, due: due == null ? null : _dueShort(due), id: id),
          html: body);
      ids.add(id);
    }
    return ids;
  }

  String _subject(AssignmentView v, AppLocalizations l10n) =>
      'Re: ${AssignmentCodec.subject(prefix: l10n.tr('assignSubject'), title: v.row.title, due: v.due == null ? null : _dueShort(v.due!), id: v.id)}';

  Future<void> _send(AccountModel account, EmailAddress to,
      {required String subject, required String html, String? inReplyTo}) async {
    try {
      await _ref.read(offlineSendProvider).sendOrQueue(
            accountId: account.id,
            to: [to],
            subject: subject,
            bodyHtml: html,
            inReplyTo: inReplyTo,
          );
    } catch (e) {
      // Не ушло и не встало в очередь — в журнал; поручение у себя уже есть.
      AppLogger.warning('Поручение: письмо не отправлено — $e');
    }
  }

  /// Письмо другой стороне поручения [v] с текстом и отметкой.
  Future<void> _notify(AssignmentView v, String text, String marker) async {
    final account = _account(v.row.accountId);
    final email = v.otherEmail;
    if (account == null || email == null || email.isEmpty) return;
    final name = v.outgoing ? v.assignee?.displayName : v.owner?.displayName;
    String? inReplyTo;
    final src = v.row.sourceEmailId;
    if (!v.outgoing && src != null) {
      try {
        inReplyTo = (await _db.getEmailById(src, accountId: v.row.accountId))?.internetMessageId;
      } catch (_) {}
    }
    await _send(account, EmailAddress(email: email, displayName: name),
        subject: _subject(v, _l10n()), html: assignmentNoteHtml(text, marker), inReplyTo: inReplyTo);
  }

  Future<void> _record(AssignmentView v, String ev, String type, Map<String, Object?> payload) =>
      AssignmentStore.addEvent(_db,
          id: ev,
          assignmentId: v.id,
          type: type,
          author: v.outgoing ? v.row.ownerEmail : (v.assignee?.email ?? ''),
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
    await _notify(v, full, AssignmentCodec.statusMarker(v.id, status, ev: ev));
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

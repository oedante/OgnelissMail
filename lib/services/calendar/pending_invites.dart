// lib/services/calendar/pending_invites.dart
// Приглашения на встречи без ответа (1.6.33): «Мой день» и календарь.
//
// Приглашение без ответа — письмо-приглашение (Exchange MeetingRequest или
// .ics по почте, сохранённое как meetingJson) во «Входящих», на встречу,
// которая ещё не закончилась, и на которое не отвечали. Exchange после
// ответа (из Ogneliss, Outlook или веба) убирает приглашение из «Входящих» —
// с ближайшей синхронизацией оно уходит и отсюда; ответ из Ogneliss
// помечает письмо сразу ([markInviteAnswered]).
//
// Раньше список был только в «Моём дне», и только в его запросе; календарь
// о приглашениях не знал (замечание 18.10.2026: «нужно отображение
// неотвеченных приглашений, даже если они не на сегодня»).

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart' show EmailMeeting;
import '../../data/models/folder_model.dart' show FolderType;
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;

/// Приглашения без ответа ящиков [ids], по времени встречи.
Future<List<Email>> loadPendingInvites(AppDatabase db, List<String> ids, {DateTime? now}) async {
  if (ids.isEmpty) return const [];
  final at = now ?? DateTime.now();
  final inboxIds = await (db.selectOnly(db.folders)
        ..addColumns([db.folders.id])
        ..where(db.folders.accountId.isIn(ids) & db.folders.type.equals(FolderType.inbox.index)))
      .map((r) => r.read(db.folders.id)!)
      .get();
  if (inboxIds.isEmpty) return const [];
  final rows = await (db.select(db.emails)
        ..where((e) => e.accountId.isIn(ids))
        ..where((e) => e.folderId.isIn(inboxIds))
        ..where((e) => e.meetingJson.isNotNull())
        ..where((e) => e.isReplied.equals(false))
        ..where((e) => e.receivedAt.isBiggerThanValue(at.subtract(const Duration(days: 90))))
        ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
        ..limit(100))
      .get();
  final out = <({Email mail, DateTime sort})>[];
  for (final m in rows) {
    final meet = EmailMeeting.parse(m.meetingJson);
    if (meet == null || !meet.isRequest || meet.responseKind != 0) continue;
    final when = meet.end ?? meet.start;
    if (when != null && when.isBefore(at)) continue;
    out.add((mail: m, sort: meet.start ?? m.receivedAt));
  }
  out.sort((a, b) => a.sort.compareTo(b.sort));
  return [for (final x in out) x.mail];
}

/// Ответили из Ogneliss — приглашение уходит из списков сразу, не дожидаясь,
/// пока сервер уберёт его из «Входящих».
Future<void> markInviteAnswered(AppDatabase db, {required String accountId, required String emailId}) =>
    (db.update(db.emails)..where((e) => e.id.equals(emailId) & e.accountId.equals(accountId)))
        .write(const EmailsCompanion(isReplied: Value(true)));

/// Ответили на встречу из календаря — письмо-приглашение на неё (та же
/// тема и время начала) тоже уходит из «Ждут ответа» (1.6.34).
Future<void> markInvitesForEvent(AppDatabase db,
    {required String accountId, required String title, required DateTime start}) async {
  final t = title.trim().toLowerCase();
  for (final m in await loadPendingInvites(db, [accountId])) {
    final meet = EmailMeeting.parse(m.meetingJson);
    final s = meet?.start;
    final subj = m.subject.trim().toLowerCase();
    final sameTime = s != null && s.difference(start).inMinutes.abs() <= 1;
    if (sameTime && (t.isEmpty || subj == t || subj.endsWith(t))) {
      await markInviteAnswered(db, accountId: accountId, emailId: m.id);
    }
  }
}

/// Приглашения без ответа всех ящиков — живым списком: пересчёт после
/// изменений писем, не чаще раза в секунду.
final pendingInvitesProvider = StreamProvider.autoDispose<List<Email>>((ref) {
  final db = ref.watch(databaseProvider);
  final ids = [for (final a in ref.watch(accountsProvider)) a.id];
  final c = StreamController<List<Email>>();
  Timer? t;
  var closed = false;
  Future<void> load() async {
    try {
      final list = await loadPendingInvites(db, ids);
      if (!closed) c.add(list);
    } catch (e) {
      if (!closed) c.addError(e);
    }
  }

  unawaited(load());
  final sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.emails, db.folders])).listen((_) {
    t?.cancel();
    t = Timer(const Duration(seconds: 1), load);
  });
  // Встреча закончилась — приглашение уходит и без новых писем.
  final tick = Timer.periodic(const Duration(minutes: 5), (_) => load());
  ref.onDispose(() {
    closed = true;
    t?.cancel();
    tick.cancel();
    sub.cancel();
    c.close();
  });
  return c.stream;
});

// lib/features/calendar/meeting_replies.dart
// Ответы участников на собрание (1.6.7, замечание 13.10.2026: «контроль над
// ответами»).
//
// Сервер Exchange отмечает ответы в копии собрания у организатора
// (Attendee_Status), но не всегда сразу, а комментарий участника и
// предложенное им новое время есть только в письме-ответе
// (IPM.Schedule.Meeting.Resp.Pos / Tent / Neg). Здесь письма-ответы
// сопоставляются со встречей: время начала встречи в ответе совпадает с ней,
// отправитель — один из участников.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';

/// Ответ участника, найденный в почте.
class MeetingReply {
  final String email;
  final String? name;

  /// 1 — принял, 2 — под вопросом, 3 — отклонил.
  final int kind;

  /// Комментарий участника (текст письма-ответа).
  final String comment;
  final DateTime at;
  final DateTime? proposedStart;
  final DateTime? proposedEnd;

  /// Письмо-ответ — открыть, ответить.
  final String emailId;
  const MeetingReply({
    required this.email,
    this.name,
    required this.kind,
    required this.comment,
    required this.at,
    this.proposedStart,
    this.proposedEnd,
    required this.emailId,
  });

  bool get hasProposal => proposedStart != null && proposedEnd != null;
}

/// Сводка ответов собрания: последний ответ каждого участника.
class MeetingReplySummary {
  final int accepted;
  final int tentative;
  final int declined;
  final int none;
  const MeetingReplySummary(this.accepted, this.tentative, this.declined, this.none);

  /// [statuses] — ответ по адресу (0 — нет ответа) для всех участников,
  /// кроме организатора.
  factory MeetingReplySummary.of(Iterable<int> statuses) {
    var a = 0, t = 0, d = 0, n = 0;
    for (final s in statuses) {
      switch (s) {
        case 1:
          a++;
        case 2:
          t++;
        case 3:
          d++;
        default:
          n++;
      }
    }
    return MeetingReplySummary(a, t, d, n);
  }

  int get total => accepted + tentative + declined + none;
}

/// Сопоставить письма-ответы со встречей: начало встречи совпадает (до
/// минуты), отправитель — среди [attendees] (адреса в нижнем регистре).
/// Возвращает последний ответ каждого участника, новые — первыми.
List<MeetingReply> matchReplies(
  Iterable<({String id, String fromEmail, String? fromName, String? preview, DateTime receivedAt, String? meetingJson})> rows, {
  required DateTime start,
  required Set<String> attendees,
}) {
  final latest = <String, MeetingReply>{};
  for (final r in rows) {
    final m = EmailMeeting.parse(r.meetingJson);
    if (m == null || m.responseKind == 0 || m.start == null) continue;
    if ((m.start!.toUtc().difference(start.toUtc())).inSeconds.abs() > 60) continue;
    final from = r.fromEmail.trim().toLowerCase();
    if (!attendees.contains(from)) continue;
    final prev = latest[from];
    if (prev != null && !r.receivedAt.isAfter(prev.at)) continue;
    latest[from] = MeetingReply(
      email: r.fromEmail,
      name: r.fromName,
      kind: m.responseKind,
      comment: cleanReplyComment(r.preview ?? ''),
      at: r.receivedAt,
      proposedStart: m.proposedStart,
      proposedEnd: m.proposedEnd,
      emailId: r.id,
    );
  }
  final out = latest.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// Текст ответа без служебных строк, которые Exchange и Outlook добавляют
/// сами («Когда: …», «Где: …», разделители).
String cleanReplyComment(String text) {
  final lines = text
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) =>
          l.isNotEmpty &&
          !RegExp(r'^(когда|где|when|where|wann|wo|quand|où)\s*:', caseSensitive: false).hasMatch(l) &&
          !RegExp(r'^[-_=*~]{3,}$').hasMatch(l))
      .toList();
  final s = lines.join('\n').trim();
  return s.length > 400 ? '${s.substring(0, 400)}…' : s;
}

/// Ответы на встречу [eventId] ящика [accountId] из писем (последние 1000
/// писем-приглашений и ответов).
final meetingRepliesProvider =
    FutureProvider.autoDispose.family<List<MeetingReply>, ({String accountId, String eventId})>((ref, k) async {
  final db = ref.watch(databaseProvider);
  final ev = await (db.select(db.calendarEvents)
        ..where((e) => e.accountId.equals(k.accountId) & e.id.equals(k.eventId)))
      .getSingleOrNull();
  if (ev == null) return const [];
  final attendees = <String>{};
  try {
    for (final a in EventAttendeesJson.decode(ev.attendeesJson)) {
      attendees.add(a);
    }
  } catch (_) {}
  if (attendees.isEmpty) return const [];
  final rows = await (db.select(db.emails)
        ..where((e) => e.accountId.equals(k.accountId) & e.meetingJson.isNotNull())
        ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
        ..limit(1000))
      .get();
  return matchReplies(
    [
      for (final r in rows)
        (
          id: r.id,
          fromEmail: r.fromEmail,
          fromName: r.fromName,
          preview: r.bodyPlain ?? r.bodyPreview,
          receivedAt: r.receivedAt,
          meetingJson: r.meetingJson,
        ),
    ],
    start: ev.startTime,
    attendees: attendees,
  );
});

/// Адреса участников из attendeesJson события (нижний регистр).
class EventAttendeesJson {
  EventAttendeesJson._();
  static Iterable<String> decode(String? json) sync* {
    if (json == null || json.length < 4) return;
    final list = (jsonDecodeSafe(json) as List?) ?? const [];
    for (final a in list.whereType<Map>()) {
      final e = (a['email'] ?? '').toString().trim().toLowerCase();
      if (e.isNotEmpty) yield e;
    }
  }
}

Object? jsonDecodeSafe(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

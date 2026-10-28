// lib/services/calendar/itip_reply.dart
// Ответ на приглашение письмом (iTIP REPLY / COUNTER, RFC 5546) — для
// Exchange по ActiveSync до 16.0 (1.5.12).
//
// До протокола 16.0 команда MeetingResponse меняет встречу только в нашем
// календаре: отправить ответ организатору должен сам клиент, письмом с
// частью text/calendar. Раньше такого письма не было — организатор так и
// не узнавал, что приглашение принято или отклонено.
//
// UID берётся из GlobalObjId приглашения (см. EasEngine.uidFromGlobalObjId):
// по нему Exchange организатора находит встречу и отмечает ответ.

class ItipReply {
  ItipReply._();

  static String partstat(String response) => switch (response) {
        'accept' => 'ACCEPTED',
        'tentative' => 'TENTATIVE',
        _ => 'DECLINED',
      };

  /// iCalendar ответа. С [proposedStart]/[proposedEnd] — METHOD:COUNTER
  /// («Предложить новое время»), иначе METHOD:REPLY.
  static String build({
    required String uid,
    required String organizer,
    required String attendee,
    String? attendeeName,
    required String response,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    bool occurrence = false,
    String? summary,
    String? comment,
    DateTime? proposedStart,
    DateTime? proposedEnd,
    DateTime? now,
  }) {
    final counter = proposedStart != null && proposedEnd != null;
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'PRODID:-//Ogneliss//Mail//RU',
      'VERSION:2.0',
      'METHOD:${counter ? 'COUNTER' : 'REPLY'}',
      'BEGIN:VEVENT',
      'UID:${_text(uid)}',
      if (occurrence && start != null) 'RECURRENCE-ID:${_utc(start)}',
      'DTSTAMP:${_utc(now ?? DateTime.now())}',
      ..._times(counter ? proposedStart : start, counter ? proposedEnd : end, allDay && !counter),
      if (summary != null && summary.trim().isNotEmpty) 'SUMMARY:${_text(summary.trim())}',
      'ORGANIZER:mailto:${organizer.trim()}',
      'ATTENDEE;PARTSTAT=${partstat(response)}'
          '${attendeeName != null && attendeeName.trim().isNotEmpty ? ';CN=${_param(attendeeName.trim())}' : ''}'
          ':mailto:${attendee.trim()}',
      if (comment != null && comment.trim().isNotEmpty) 'COMMENT:${_text(comment.trim())}',
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return '${lines.map(_fold).join('\r\n')}\r\n';
  }

  /// Адрес организатора из строки вида «Иван Петров <ivan@x.ru>».
  static String? organizerEmail(String? raw) =>
      RegExp(r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+').firstMatch(raw ?? '')?.group(0);

  static List<String> _times(DateTime? s, DateTime? e, bool allDay) {
    if (s == null) return const [];
    if (allDay) {
      return [
        'DTSTART;VALUE=DATE:${_date(s)}',
        if (e != null) 'DTEND;VALUE=DATE:${_date(e)}',
      ];
    }
    return ['DTSTART:${_utc(s)}', if (e != null) 'DTEND:${_utc(e)}'];
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.year}${_two(l.month)}${_two(l.day)}';
  }

  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  /// Текст свойства (RFC 5545 3.3.11).
  static String _text(String v) => v
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll(RegExp(r'\r\n|\r|\n'), '\\n');

  /// Значение параметра: в кавычках, если есть «:;,».
  static String _param(String v) {
    final clean = v.replaceAll('"', "'");
    return RegExp(r'[:;,]').hasMatch(clean) ? '"$clean"' : clean;
  }

  /// Перенос длинных строк: не длиннее 75 октетов, продолжение — с пробела.
  /// Режем по границе символа UTF-8.
  static String _fold(String line) {
    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final n = rune < 0x80 ? 1 : rune < 0x800 ? 2 : rune < 0x10000 ? 3 : 4;
      if (octets + n > 75) {
        out.write('\r\n ');
        octets = 1;
      }
      out.write(ch);
      octets += n;
    }
    return out.toString();
  }
}

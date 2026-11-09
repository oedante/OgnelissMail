// lib/services/assignments/assignment_codec.dart
// Письмо поручения (план 08.11.2026 п. 10, решения владельца 09.11.2026).
// Транспорт — обычная почта: исполнитель читает поручение в любой почте и
// отвечает словами. Связь писем с поручением:
//  · метка в теме «[OGN-7F3K2Q9XHMRT]» — её сохраняют ответы любой почты, даже
//    если цепочка писем у сервера разорвалась;
//  · скрытая строка в HTML «ogneliss-task;v=1;id=…;due=…;to=…» — у
//    исполнителя с Ogneliss Mail поручение появляется само, со сроком;
//  · ответ кнопкой из Ogneliss Mail — строка «ogneliss-status;id=…;s=…»:
//    точнее слов («Принято», «Готово» — assignment_phrases.dart).
// Ничего не прячется от почтовых шлюзов и архива: метка видна в теме,
// строки — обычный текст письма.

import 'dart:math';

/// Статусы поручения (столбец assignments.status).
abstract final class AssignmentStatus {
  static const open = 1; // новое
  static const inProgress = 2; // в работе
  static const review = 3; // на проверке
  static const done = 4; // выполнено
  static const cancelled = 6; // снято

  static bool isActive(int s) => s == open || s == inProgress || s == review;

  /// Код статуса в отметке письма.
  static String code(int s) => switch (s) {
        inProgress => 'work',
        review => 'review',
        done => 'done',
        cancelled => 'cancel',
        _ => 'open',
      };

  static int? fromCode(String c) => switch (c) {
        'open' => open,
        'work' => inProgress,
        'review' => review,
        'done' => done,
        'cancel' => cancelled,
        _ => null,
      };
}

/// Скрытая отметка поручения в письме. [ev] — id события истории: своё
/// отправленное письмо не задваивает историю (и на других устройствах).
typedef TaskMarker = ({String id, DateTime? due, String? to, String? title, String? ev});

/// Отметка статуса в ответе.
typedef StatusMarker = ({String id, int status, String? ev});

abstract final class AssignmentCodec {
  // Без похожих знаков (I, L, O, U, 0, 1) — код читают люди.
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Длина кода поручения.
  static const idLength = 12;

  /// Новый код поручения: 12 случайных знаков из криптостойкого генератора
  /// (30^12 ≈ 5·10^17, около 59 бит). Совпадение кодов двух поручений в
  /// одном ящике — меньше миллионной доли даже при миллионе поручений;
  /// кроме того, письмо относится к поручению, только если пришло от его
  /// участника (assignment_store.dart).
  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(idLength, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  static final _tokenRe = RegExp(r'\[OGN-([2-9A-HJKMNP-TV-Z]{12})\]');

  /// Метка в теме письма.
  static String token(String id) => '[OGN-$id]';

  /// Код поручения из темы (и «Re: …», «Fwd: …»); null — не поручение.
  static String? idFromSubject(String subject) => _tokenRe.firstMatch(subject)?.group(1);

  /// Тема: «Поручение: {что} — до {срок} [OGN-…]».
  static String subject({required String prefix, required String title, String? due, required String id}) {
    final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = t.length > 120 ? '${t.substring(0, 117)}…' : t;
    return [
      '$prefix: $short',
      if (due != null && due.isNotEmpty) ' — $due',
      ' ${token(id)}',
    ].join();
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _clean(String s) => s.replaceAll(RegExp(r'[;\r\n]'), ' ').trim();

  /// Скрытая строка поручения (в HTML письма).
  static String taskMarker({required String id, DateTime? due, String? to, String? title, String? ev}) {
    final parts = [
      'ogneliss-task',
      'v=1',
      'id=$id',
      if (ev != null) 'ev=${_clean(ev)}',
      if (due != null) 'due=${_date(due)}',
      if (to != null && to.isNotEmpty) 'to=${_clean(to.toLowerCase())}',
      if (title != null && title.trim().isNotEmpty) 'ti=${Uri.encodeComponent(title.trim())}',
    ];
    return _hidden(parts.join(';'));
  }

  /// Скрытая строка статуса (в ответе исполнителя или поручившего).
  static String statusMarker(String id, int status, {String? ev}) => _hidden(
      'ogneliss-status;v=1;id=$id;s=${AssignmentStatus.code(status)}${ev == null ? '' : ';ev=${_clean(ev)}'}');

  static String _hidden(String text) =>
      '<div style="display:none;font-size:0;line-height:0;max-height:0;overflow:hidden;mso-hide:all">${_esc(text)}</div>';

  static final _taskRe = RegExp(r'ogneliss-task;v=1;id=([2-9A-HJKMNP-TV-Z]{12})((?:;[a-z]+=[^;<"\s]*)*)');
  static final _statusRe = RegExp(r'ogneliss-status;v=1;id=([2-9A-HJKMNP-TV-Z]{12})((?:;[a-z]+=[^;<"\s]*)*)');

  static Map<String, String> _fields(String? tail) {
    final fields = <String, String>{};
    for (final kv in (tail ?? '').split(';')) {
      final i = kv.indexOf('=');
      if (i > 0) fields[kv.substring(0, i)] = kv.substring(i + 1);
    }
    return fields;
  }

  /// Отметка поручения в тексте письма (HTML или простом).
  static TaskMarker? parseTask(String body) {
    final m = _taskRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(2));
    final due = DateTime.tryParse(fields['due'] ?? '');
    String? title;
    try {
      final t = fields['ti'];
      if (t != null && t.isNotEmpty) title = Uri.decodeComponent(t);
    } catch (_) {}
    return (id: m.group(1)!, due: due, to: fields['to'], title: title, ev: fields['ev']);
  }

  /// Отметка статуса в ответе.
  static StatusMarker? parseStatus(String body) {
    final m = _statusRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(2));
    final s = AssignmentStatus.fromCode(fields['s'] ?? '');
    return s == null ? null : (id: m.group(1)!, status: s, ev: fields['ev']);
  }

  /// Текст письма поручения (HTML). Строки — на языке поручившего.
  static String body({
    required String id,
    required String greeting,
    required String whatLabel,
    required String what,
    String? description,
    String? dueLabel,
    String? dueLine,
    String? sourceLine,
    String? sourceText,
    required String footer,
    DateTime? due,
    String? to,
    String? title,
    String? ev,
  }) {
    final b = StringBuffer()
      ..write('<p>${_esc(greeting)}</p>')
      ..write('<p><b>${_esc(whatLabel)}</b> ${_esc(what)}</p>');
    final desc = (description ?? '').trim();
    if (desc.isNotEmpty) b.write('<p>${_esc(desc).replaceAll('\n', '<br>')}</p>');
    if (dueLine != null) b.write('<p><b>${_esc(dueLabel ?? '')}</b> ${_esc(dueLine)}</p>');
    if (sourceLine != null) {
      b.write('<p>${_esc(sourceLine)}</p>');
      final src = (sourceText ?? '').trim();
      if (src.isNotEmpty) {
        final cut = src.length > 4000 ? '${src.substring(0, 4000)}…' : src;
        b.write('<blockquote style="margin:0 0 0 8px;padding-left:8px;border-left:2px solid #ccc;color:#555">'
            '${_esc(cut).replaceAll('\n', '<br>')}</blockquote>');
      }
    }
    b
      ..write('<p style="color:#888;font-size:smaller">— ${_esc(footer)}</p>')
      ..write(taskMarker(id: id, due: due, to: to, title: title, ev: ev));
    return b.toString();
  }
}

/// Название поручения из темы письма без отметки: «Re: Поручение: собрать
/// даты — до 12.11 [OGN-…]» → «собрать даты».
String assignmentTitleFromSubject(String subject) {
  var s = subject.replaceAll(RegExp(r'\[OGN-[^\]]*\]'), '').trim();
  s = s.replaceFirst(RegExp(r'^((re|fw|fwd|aw|wg|sv|vs|tr|rv|ответ|отв|пересл)\s*(\[\d+\])?\s*:\s*)+', caseSensitive: false), '');
  final colon = s.indexOf(': ');
  if (colon > 0 && colon < 30) s = s.substring(colon + 2);
  final dash = s.lastIndexOf(' — ');
  if (dash > 0) s = s.substring(0, dash);
  return s.trim();
}

/// Короткое письмо по поручению (ответ исполнителя, «принято», «вернул»,
/// напоминание, новый срок): текст и скрытая отметка.
String assignmentNoteHtml(String text, String marker) {
  final esc = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');
  return '<p>$esc</p>$marker';
}

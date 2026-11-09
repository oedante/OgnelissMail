// lib/services/assignments/assignment_codec.dart
// Письмо поручения (план 08.11.2026 п. 10, решения владельца 09.11.2026).
// Транспорт — обычная почта: исполнитель читает поручение в любой почте и
// отвечает словами. Тема — обычная («Поручение: что — до 12.11»), без
// служебных меток (решение владельца 09.11.2026: метка портила вид письма).
// Связь писем с поручением — в теле:
//  · технический тег «OGN-7F3K2Q9XHMRT» мелким серым в подписи письма —
//    его цитирует ответ из любой почты; удалили цитату — ответ находится
//    по цепочке писем (In-Reply-To, References, беседа — assignment_store);
//  · пустой элемент с атрибутом data-ogneliss-task (срок, исполнитель,
//    название) — у исполнителя с Ogneliss Mail поручение появляется само.
//    Текста у него нет: в почте без HTML ничего лишнего не видно;
//  · ответ кнопкой из Ogneliss Mail — атрибут data-ogneliss-status:
//    точнее слов («Принято», «Готово» — assignment_phrases.dart).

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

  static const _code = r'[2-9A-HJKMNP-TV-Z]{12}';
  static final _tagRe = RegExp('OGN-($_code)(?![0-9A-Z])');

  /// Технический тег в теле письма.
  static String tag(String id) => 'OGN-$id';

  /// Код поручения по тегу в теле (HTML или текст, и в цитате ответа);
  /// null — не поручение. Первый тег — самого нового письма цепочки.
  static String? idFromBody(String? body) {
    if (body == null || body.isEmpty) return null;
    final m = _statusRe.firstMatch(body) ?? _taskRe.firstMatch(body);
    if (m != null) {
      final id = _fields(m.group(1))['id'];
      if (id != null && RegExp('^$_code\$').hasMatch(id)) return id;
    }
    return _tagRe.firstMatch(body)?.group(1);
  }

  /// Тема: «Поручение: {что} — до {срок}» — без служебных меток.
  static String subject({required String prefix, required String title, String? due}) {
    final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = t.length > 120 ? '${t.substring(0, 117)}…' : t;
    return [
      '$prefix: $short',
      if (due != null && due.isNotEmpty) ' — $due',
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

  /// Отметка поручения: пустой элемент с атрибутом (в HTML письма).
  static String taskMarker({required String id, DateTime? due, String? to, String? title, String? ev}) {
    final parts = [
      'v=1',
      'id=$id',
      if (ev != null) 'ev=${_clean(ev)}',
      if (due != null) 'due=${_date(due)}',
      if (to != null && to.isNotEmpty) 'to=${_clean(to.toLowerCase())}',
      if (title != null && title.trim().isNotEmpty) 'ti=${Uri.encodeComponent(title.trim())}',
    ];
    return _marker('data-ogneliss-task', parts.join(';'));
  }

  /// Отметка статуса (в ответе исполнителя или поручившего).
  static String statusMarker(String id, int status, {String? ev}) => _marker('data-ogneliss-status',
      'v=1;id=$id;s=${AssignmentStatus.code(status)}${ev == null ? '' : ';ev=${_clean(ev)}'}');

  /// Пустой невидимый элемент: в тексте письма и в его текстовой версии
  /// (почта без HTML) от него ничего нет.
  static String _marker(String attr, String value) =>
      '<span $attr="${_esc(value)}" style="display:none"></span>';

  static final _taskRe = RegExp(r'data-ogneliss-task="([^"]*)"');
  static final _statusRe = RegExp(r'data-ogneliss-status="([^"]*)"');

  static String _unesc(String s) =>
      s.replaceAll('&quot;', '"').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');

  static Map<String, String> _fields(String? value) {
    final fields = <String, String>{};
    for (final kv in _unesc(value ?? '').split(';')) {
      final i = kv.indexOf('=');
      if (i > 0) fields[kv.substring(0, i)] = kv.substring(i + 1);
    }
    return fields;
  }

  /// Отметка поручения в HTML письма.
  static TaskMarker? parseTask(String body) {
    final m = _taskRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(1));
    final id = fields['id'];
    if (id == null || !RegExp('^$_code\$').hasMatch(id)) return null;
    final due = DateTime.tryParse(fields['due'] ?? '');
    String? title;
    try {
      final t = fields['ti'];
      if (t != null && t.isNotEmpty) title = Uri.decodeComponent(t);
    } catch (_) {}
    return (id: id, due: due, to: fields['to'], title: title, ev: fields['ev']);
  }

  /// Отметка статуса в ответе.
  static StatusMarker? parseStatus(String body) {
    final m = _statusRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(1));
    final id = fields['id'];
    final s = AssignmentStatus.fromCode(fields['s'] ?? '');
    if (id == null || s == null || !RegExp('^$_code\$').hasMatch(id)) return null;
    return (id: id, status: s, ev: fields['ev']);
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
      ..write('<p style="color:#888;font-size:smaller">— ${_esc(footer)} ${tag(id)}</p>')
      ..write(taskMarker(id: id, due: due, to: to, title: title, ev: ev));
    return b.toString();
  }
}

/// Название поручения из темы письма: «Re: Поручение: собрать даты — до
/// 12.11» → «собрать даты».
String assignmentTitleFromSubject(String subject) {
  var s = subject.trim();
  s = s.replaceFirst(RegExp(r'^((re|fw|fwd|aw|wg|sv|vs|tr|rv|ответ|отв|пересл)\s*(\[\d+\])?\s*:\s*)+', caseSensitive: false), '');
  final colon = s.indexOf(': ');
  if (colon > 0 && colon < 30) s = s.substring(colon + 2);
  final dash = s.lastIndexOf(' — ');
  if (dash > 0) s = s.substring(0, dash);
  return s.trim();
}

/// Короткое письмо по поручению (ответ исполнителя, «принято», «вернул»,
/// напоминание, новый срок): текст, технический тег и отметка.
String assignmentNoteHtml(String text, String marker, String id) {
  final esc = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');
  return '<p>$esc</p><p style="color:#999;font-size:smaller">${AssignmentCodec.tag(id)}</p>$marker';
}

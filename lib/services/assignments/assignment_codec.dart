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

import 'dart:convert';
import 'dart:math';

import 'assignment_project.dart' show dueStamp;

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

/// Код действия в видимом номере поручения (предложение владельца
/// 13.11.2026): «OGN-7F3K2Q9XHMRT-D». Скрытую отметку сервер может вырезать
/// (пустой элемент с атрибутом), видимый номер — нет. Порядок разбора:
/// скрытая отметка, затем код, и только без них — слова ответа.
abstract final class AssignmentAct {
  static const taken = 'W'; // исполнитель: «Принято», взял в работу
  static const review = 'R'; // исполнитель: «Готово», на проверке
  static const accepted = 'D'; // постановщик или контролирующий: работа принята
  static const returned = 'B'; // постановщик или контролирующий: вернул на доработку
  static const cancelled = 'X'; // постановщик: снято (этап удалён)
  static const go = 'G'; // постановщик: «Можно начинать»
  static const edited = 'E'; // постановщик: поручение изменено, права
  static const reminder = 'N'; // постановщик: напоминание
  static const due = 'T'; // постановщик: новый срок (T + ГГГГММДД[THHMM])
  static const files = 'F'; // файлы
  static const progress = 'P'; // ход работ
  static const added = 'A'; // передан для исполнения (новый соисполнитель)

  /// «T20261114» или со временем «T20261114T1500»; без срока — «T».
  static String dueCode(DateTime? d) {
    if (d == null) return due;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${d.year.toString().padLeft(4, '0')}${two(d.month)}${two(d.day)}';
    final hasTime = d.hour != 0 || d.minute != 0;
    return '$due$date${hasTime ? 'T${two(d.hour)}${two(d.minute)}' : ''}';
  }

  /// Срок из аргумента кода «T»: «20261114» или «20261114T1500».
  static DateTime? dueFrom(String? arg) {
    if (arg == null || arg.length < 8) return null;
    final y = int.tryParse(arg.substring(0, 4));
    final m = int.tryParse(arg.substring(4, 6));
    final d = int.tryParse(arg.substring(6, 8));
    if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
    var h = 0, min = 0;
    if (arg.length >= 13 && arg[8] == 'T') {
      h = int.tryParse(arg.substring(9, 11)) ?? 0;
      min = int.tryParse(arg.substring(11, 13)) ?? 0;
    }
    return DateTime(y, m, d, h.clamp(0, 23), min.clamp(0, 59));
  }
}

/// Скрытая отметка поручения в письме. [ev] — id события истории: своё
/// отправленное письмо не задваивает историю (и на других устройствах).
/// [parent] — код родительского поручения (подзадача, 12.11.2026).
///
/// Проекты с этапами (12.11.2026): [project] — письмо проекта (общей
/// задачи), [plan] — этапы проекта (JSON) для диаграммы у участников;
/// у этапа — [start], [after] (код предыдущего этапа: «начать после»),
/// [order], соисполнители [co], контролирующий [ctl], наблюдатели [obs],
/// пункты чек-листа [checklist].
///
/// Изменение поручения и права постановщика (13.11.2026): [rev] — полные
/// сведения о поручении (время изменения, секунды Unix): название,
/// описание [desc], сроки, порядок, участники, чек-лист, файлы [files] —
/// заменяют прежние; [owner] — постановщик (после передачи прав —
/// новый), [deputies] — заместители (те же права); [removed] — этап
/// удалён; [visibility] — видимость плана проекта.
typedef TaskMarker = ({
  String id,
  DateTime? due,
  String? to,
  String? title,
  String? ev,
  String? parent,
  DateTime? start,
  String? after,
  int? order,
  List<String> co,
  String? ctl,
  List<String> obs,
  List<String> checklist,
  bool project,
  String? plan,
  int? rev,
  String? desc,
  String? owner,
  List<String> deputies,
  bool removed,
  int? visibility,
  List<String>? files,
});

/// Отметка статуса в ответе. [checks] — выполненные пункты чек-листа
/// («0110»), [go] — «Можно начинать» (предыдущий этап принят).
typedef StatusMarker = ({String id, int status, String? ev, String? checks, bool go});

/// Отметка «добавлен участник» (передача исполнения, 12.11.2026).
typedef PeopleMarker = ({String id, String email, int role, String? name, String? ev});

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

  /// Технический тег в теле письма; [act] — код действия (AssignmentAct):
  /// «OGN-7F3K2Q9XHMRT-D».
  static String tag(String id, [String? act]) => act == null || act.isEmpty ? 'OGN-$id' : 'OGN-$id-$act';

  static final _actRe = RegExp('OGN-($_code)-([A-Z])([0-9]{8}(?:T[0-9]{4})?)?(?![0-9A-Za-z])');

  /// Код действия из видимого номера: первый номер текста (самого нового
  /// письма; номер в цитате — ниже). Нет кода у первого номера — null.
  static ({String id, String act, String? arg})? actionFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    final first = _tagRe.firstMatch(text);
    if (first == null) return null;
    final m = _actRe.matchAsPrefix(text, first.start);
    if (m == null) return null;
    return (id: m.group(1)!, act: m.group(2)!, arg: m.group(3));
  }

  /// Код поручения по тегу в теле (HTML или текст, и в цитате ответа);
  /// null — не поручение. Первый тег — самого нового письма цепочки.
  static String? idFromBody(String? body) {
    if (body == null || body.isEmpty) return null;
    final m = _statusRe.firstMatch(body) ?? _peopleRe.firstMatch(body) ?? _taskRe.firstMatch(body);
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

  static String _emails(Iterable<String> list) =>
      list.map((e) => _clean(e.toLowerCase())).where((e) => e.isNotEmpty).join(',');

  /// Отметка поручения: пустой элемент с атрибутом (в HTML письма).
  static String taskMarker({
    required String id,
    DateTime? due,
    String? to,
    String? title,
    String? ev,
    String? parent,
    DateTime? start,
    String? after,
    int? order,
    List<String> co = const [],
    String? ctl,
    List<String> obs = const [],
    List<String> checklist = const [],
    bool project = false,
    String? plan,
    int? rev,
    String? desc,
    String? owner,
    List<String> deputies = const [],
    bool removed = false,
    int? visibility,
    List<String>? files,
  }) {
    final d = (desc ?? '').trim();
    final parts = [
      'v=1',
      'id=$id',
      if (ev != null) 'ev=${_clean(ev)}',
      if (project) 'pj=1',
      if (parent != null) 'pa=$parent',
      if (start != null) 'st=${_date(start)}',
      if (due != null) 'due=${dueStamp(due)}',
      if (after != null && after != id && RegExp('^$_code\$').hasMatch(after)) 'af=$after',
      if (order != null) 'ord=$order',
      if (to != null && to.isNotEmpty) 'to=${_clean(to.toLowerCase())}',
      if (co.isNotEmpty) 'co=${_emails(co)}',
      if (ctl != null && ctl.isNotEmpty) 'ctl=${_clean(ctl.toLowerCase())}',
      if (obs.isNotEmpty) 'obs=${_emails(obs)}',
      if (title != null && title.trim().isNotEmpty) 'ti=${Uri.encodeComponent(title.trim())}',
      if (checklist.isNotEmpty)
        'ck=${checklist.map((t) => Uri.encodeComponent(t.trim())).where((t) => t.isNotEmpty).join('|')}',
      if (plan != null && plan.isNotEmpty) 'pl=${base64Url.encode(utf8.encode(plan))}',
      if (rev != null) 'rv=$rev',
      if (rev != null && d.isNotEmpty) 'de=${base64Url.encode(utf8.encode(d.length > 4000 ? d.substring(0, 4000) : d))}',
      if (owner != null && owner.contains('@')) 'ow=${_clean(owner.toLowerCase())}',
      if (deputies.isNotEmpty) 'dep=${_emails(deputies)}',
      if (removed) 'rm=1',
      if (visibility != null) 'vis=$visibility',
      if (files != null) 'fn=${files.map((n) => Uri.encodeComponent(n.trim())).where((n) => n.isNotEmpty).join('|')}',
    ];
    return _marker('data-ogneliss-task', parts.join(';'));
  }

  /// Отметка статуса (в ответе исполнителя или поручившего). [checks] —
  /// выполненные пункты чек-листа строкой «0110»; [go] — «Можно начинать».
  static String statusMarker(String id, int status, {String? ev, String? checks, bool go = false}) =>
      _marker(
          'data-ogneliss-status',
          [
            'v=1',
            'id=$id',
            's=${AssignmentStatus.code(status)}',
            if (ev != null) 'ev=${_clean(ev)}',
            if (checks != null && RegExp(r'^[01]{1,200}$').hasMatch(checks)) 'ck=$checks',
            if (go) 'go=1',
          ].join(';'));

  /// Отметка «добавлен участник» [email] с ролью [role] (передача
  /// исполнения: соисполнитель — роль 2).
  static String peopleMarker(String id, String email, int role, {String? name, String? ev}) => _marker(
      'data-ogneliss-people',
      [
        'v=1',
        'id=$id',
        'add=${_clean(email.toLowerCase())}',
        'r=$role',
        if (name != null && name.trim().isNotEmpty) 'nm=${Uri.encodeComponent(name.trim())}',
        if (ev != null) 'ev=${_clean(ev)}',
      ].join(';'));

  /// Пустой невидимый элемент: в тексте письма и в его текстовой версии
  /// (почта без HTML) от него ничего нет.
  static String _marker(String attr, String value) =>
      '<span $attr="${_esc(value)}" style="display:none"></span>';

  static final _taskRe = RegExp(r'data-ogneliss-task="([^"]*)"');
  static final _statusRe = RegExp(r'data-ogneliss-status="([^"]*)"');
  static final _peopleRe = RegExp(r'data-ogneliss-people="([^"]*)"');

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
    final pa = fields['pa'];
    final parent = pa != null && pa != id && RegExp('^$_code\$').hasMatch(pa) ? pa : null;
    final af = fields['af'];
    List<String> emails(String? v) =>
        [for (final e in (v ?? '').split(',')) if (e.trim().contains('@')) e.trim().toLowerCase()];
    final checklist = <String>[];
    for (final t in (fields['ck'] ?? '').split('|')) {
      if (t.isEmpty) continue;
      try {
        final x = Uri.decodeComponent(t).trim();
        if (x.isNotEmpty) checklist.add(x.length > 300 ? x.substring(0, 300) : x);
      } catch (_) {}
    }
    String? plan;
    final pl = fields['pl'];
    if (pl != null && pl.isNotEmpty && pl.length < 400000) {
      try {
        plan = utf8.decode(base64Url.decode(base64Url.normalize(pl)));
      } catch (_) {}
    }
    String? desc;
    final de = fields['de'];
    if (de != null && de.isNotEmpty && de.length < 8000) {
      try {
        desc = utf8.decode(base64Url.decode(base64Url.normalize(de))).trim();
      } catch (_) {}
    }
    List<String>? files;
    final fn = fields['fn'];
    if (fn != null) {
      files = [];
      for (final n in fn.split('|')) {
        if (n.isEmpty) continue;
        try {
          files.add(Uri.decodeComponent(n));
        } catch (_) {}
      }
    }
    final ctl = fields['ctl'];
    final ow = fields['ow'];
    return (
      id: id,
      due: due,
      to: fields['to'],
      title: title,
      ev: fields['ev'],
      parent: parent,
      start: DateTime.tryParse(fields['st'] ?? ''),
      after: af != null && af != id && RegExp('^$_code\$').hasMatch(af) ? af : null,
      order: int.tryParse(fields['ord'] ?? ''),
      co: emails(fields['co']),
      ctl: ctl != null && ctl.contains('@') ? ctl.toLowerCase() : null,
      obs: emails(fields['obs']),
      checklist: checklist,
      project: fields['pj'] == '1',
      plan: plan,
      rev: int.tryParse(fields['rv'] ?? ''),
      desc: desc,
      owner: ow != null && ow.contains('@') ? ow.toLowerCase() : null,
      deputies: emails(fields['dep']),
      removed: fields['rm'] == '1',
      visibility: int.tryParse(fields['vis'] ?? ''),
      files: files,
    );
  }

  /// Отметка «добавлен участник».
  static PeopleMarker? parsePeople(String body) {
    final m = _peopleRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(1));
    final id = fields['id'];
    final email = (fields['add'] ?? '').trim().toLowerCase();
    final role = int.tryParse(fields['r'] ?? '');
    if (id == null || !RegExp('^$_code\$').hasMatch(id) || !email.contains('@') || role == null) return null;
    String? name;
    try {
      final n = fields['nm'];
      if (n != null && n.isNotEmpty) name = Uri.decodeComponent(n);
    } catch (_) {}
    return (id: id, email: email, role: role, name: name, ev: fields['ev']);
  }

  /// Отметка статуса в ответе.
  static StatusMarker? parseStatus(String body) {
    final m = _statusRe.firstMatch(body);
    if (m == null) return null;
    final fields = _fields(m.group(1));
    final id = fields['id'];
    final s = AssignmentStatus.fromCode(fields['s'] ?? '');
    if (id == null || s == null || !RegExp('^$_code\$').hasMatch(id)) return null;
    final ck = fields['ck'];
    return (
      id: id,
      status: s,
      ev: fields['ev'],
      checks: ck != null && RegExp(r'^[01]{1,200}$').hasMatch(ck) ? ck : null,
      go: fields['go'] == '1',
    );
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
    String? parent,
    String? parentLine,
    /// Дополнительный текст (этапы проекта, роли, чек-лист) — после срока.
    String? extraHtml,
    /// Что изменилось (письмо «Поручение изменено») — сразу после приветствия.
    String? introHtml,
    /// Своя отметка вместо отметки по [id], [due], [to], [title], [ev], [parent].
    String? marker,
    /// Код действия у номера в подписи (AssignmentAct).
    String? act,
  }) {
    final b = StringBuffer()..write('<p>${_esc(greeting)}</p>');
    if (introHtml != null && introHtml.isNotEmpty) b.write(introHtml);
    b.write('<p><b>${_esc(whatLabel)}</b> ${_esc(what)}</p>');
    // Подзадача: название родительского поручения — словами. Его тег OGN-…
    // в текст не пишем: первый тег в теле — код самого письма (idFromBody).
    if (parentLine != null) b.write('<p>${_esc(parentLine)}</p>');
    final desc = (description ?? '').trim();
    if (desc.isNotEmpty) b.write('<p>${_esc(desc).replaceAll('\n', '<br>')}</p>');
    if (dueLine != null) b.write('<p><b>${_esc(dueLabel ?? '')}</b> ${_esc(dueLine)}</p>');
    if (extraHtml != null && extraHtml.isNotEmpty) b.write(extraHtml);
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
      ..write('<p style="color:#888;font-size:smaller">— ${_esc(footer)} ${tag(id, act)}</p>')
      ..write(marker ?? taskMarker(id: id, due: due, to: to, title: title, ev: ev, parent: parent));
    return b.toString();
  }
}

/// Экранирование текста для HTML письма поручения.
String assignmentEsc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

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
/// напоминание, новый срок): текст, технический тег с кодом действия [act]
/// и отметка.
String assignmentNoteHtml(String text, String marker, String id, {String? act}) {
  final esc = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');
  return '<p>$esc</p><p style="color:#999;font-size:smaller">${AssignmentCodec.tag(id, act)}</p>$marker';
}

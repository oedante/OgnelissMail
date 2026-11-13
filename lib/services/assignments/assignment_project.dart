// lib/services/assignments/assignment_project.dart
// Проекты с этапами (просьба владельца 12.11.2026): чек-лист, файлы, план
// этапов для диаграммы Ганта, прогресс и сдвиг сроков последовательных
// этапов. Чистый Dart — без базы и Flutter: проверяется тестами.
//
// Модель — как в Jira и Bitrix24: проект (общая задача) → этапы (задачи) с
// ролями: исполнитель (основной), соисполнители, контролирующий (принимает
// работу), наблюдатели (получают копии). Последовательный этап — «после
// этапа N» (связь «окончание → начало»), без связи — параллельно.

import 'dart:convert';

/// Пункт чек-листа этапа.
class ChecklistItem {
  final String text;
  final bool done;
  const ChecklistItem(this.text, {this.done = false});

  ChecklistItem copyWith({String? text, bool? done}) => ChecklistItem(text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'t': text, if (done) 'd': true};

  static List<ChecklistItem> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).whereType<Map>())
          if ('${m['t'] ?? ''}'.trim().isNotEmpty) ChecklistItem('${m['t']}'.trim(), done: m['d'] == true),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String? encode(List<ChecklistItem> items) =>
      items.isEmpty ? null : jsonEncode([for (final i in items) i.toJson()]);

  /// Выполненные пункты строкой «0110» — для отметки в письме.
  static String bits(List<ChecklistItem> items) => items.map((i) => i.done ? '1' : '0').join();

  /// Применить строку «0110» к пунктам (лишние знаки не учитываются).
  static List<ChecklistItem> applyBits(List<ChecklistItem> items, String bits) => [
        for (var i = 0; i < items.length; i++) items[i].copyWith(done: i < bits.length ? bits[i] == '1' : items[i].done),
      ];

  /// Доля выполненного (0…1); пустой чек-лист — null.
  static double? fraction(List<ChecklistItem> items) =>
      items.isEmpty ? null : items.where((i) => i.done).length / items.length;
}

/// Файл поручения: свой (путь на устройстве) или из письма (письмо и
/// вложение).
class AssignmentFile {
  final String name;
  final int size;
  final String? path;
  final String? mailId;
  final String? attachmentId;
  const AssignmentFile({required this.name, this.size = 0, this.path, this.mailId, this.attachmentId});

  Map<String, Object?> toJson() => {
        'n': name,
        if (size > 0) 's': size,
        if (path != null) 'p': path,
        if (mailId != null) 'm': mailId,
        if (attachmentId != null) 'a': attachmentId,
      };

  static List<AssignmentFile> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).whereType<Map>())
          if ('${m['n'] ?? ''}'.trim().isNotEmpty)
            AssignmentFile(
              name: '${m['n']}',
              size: (m['s'] as num?)?.toInt() ?? 0,
              path: m['p'] as String?,
              mailId: m['m'] as String?,
              attachmentId: m['a'] as String?,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String? encode(List<AssignmentFile> files) =>
      files.isEmpty ? null : jsonEncode([for (final f in files) f.toJson()]);
}

/// Этап в плане проекта (для диаграммы Ганта).
///
/// План в письме проекта (13.11.2026): у этапа — статус, ход работ и имя
/// исполнителя, чтобы все участники видели, кто что и после кого делает.
/// Полный план (передача прав постановщика) — ещё описание, участники и
/// чек-лист: у заместителя этапы появляются целиком.
class PlanStage {
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? due;
  final String? after;
  final String? assignee;
  final String? assigneeName;
  final int order;

  /// Статус (AssignmentStatus); null — неизвестен (этап другого участника).
  final int? status;

  /// Доля выполненного (чек-лист или статус), 0…1.
  final double progress;

  /// Когда принят (для «факта» на диаграмме).
  final DateTime? doneAt;

  // ── Полный план (передача прав) ──
  final String? description;
  final List<String> co;
  final String? controller;
  final List<String> observers;
  final List<ChecklistItem> checklist;

  /// Имена участников этапа: адрес → имя.
  final Map<String, String> names;

  const PlanStage({
    required this.id,
    required this.title,
    this.start,
    this.due,
    this.after,
    this.assignee,
    this.assigneeName,
    this.order = 0,
    this.status,
    this.progress = 0,
    this.doneAt,
    this.description,
    this.co = const [],
    this.controller,
    this.observers = const [],
    this.checklist = const [],
    this.names = const {},
  });

  PlanStage copyWith({DateTime? start, DateTime? due}) => PlanStage(
        id: id,
        title: title,
        start: start ?? this.start,
        due: due ?? this.due,
        after: after,
        assignee: assignee,
        assigneeName: assigneeName,
        order: order,
        status: status,
        progress: progress,
        doneAt: doneAt,
        description: description,
        co: co,
        controller: controller,
        observers: observers,
        checklist: checklist,
        names: names,
      );

  Map<String, Object?> toJson({bool full = false}) => {
        'id': id,
        't': title,
        if (start != null) 's': _d(start!),
        if (due != null) 'e': dueStamp(due!),
        if (after != null) 'a': after,
        if (assignee != null) 'to': assignee,
        if ((assigneeName ?? '').trim().isNotEmpty) 'nm': assigneeName!.trim(),
        'o': order,
        if (status != null) 'st': status,
        if (status != null) 'p': (progress * 100).round(),
        if (doneAt != null) 'dn': _d(doneAt!),
        if (full) ...{
          if ((description ?? '').trim().isNotEmpty) 'd': description!.trim(),
          if (co.isNotEmpty) 'co': co,
          if (controller != null) 'ctl': controller,
          if (observers.isNotEmpty) 'obs': observers,
          if (checklist.isNotEmpty) 'ck': [for (final c in checklist) c.toJson()],
          if (names.isNotEmpty) 'n': names,
        },
      };

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String encode(List<PlanStage> stages, {bool full = false}) =>
      jsonEncode([for (final s in stages) s.toJson(full: full)]);

  /// Подпись плана для «изменилось ли»: этапы, сроки, исполнители, порядок
  /// и статусы (ход работ по чек-листу — нет: он меняется часто).
  static String signature(List<PlanStage> stages) => [
        for (final s in stages)
          [s.id, s.title, s.start == null ? '' : _d(s.start!), s.due == null ? '' : _d(s.due!), s.after ?? '',
                  s.assignee ?? '', s.order, s.status ?? '']
              .join('|'),
      ].join('\n');

  static List<String> _list(Object? v) =>
      [for (final x in (v is List ? v : const [])) if ('$x'.contains('@')) '$x'.toLowerCase()];

  static List<PlanStage> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).whereType<Map>())
          if (m['id'] is String && m['t'] is String)
            PlanStage(
              id: m['id'] as String,
              title: m['t'] as String,
              start: DateTime.tryParse('${m['s'] ?? ''}'),
              due: DateTime.tryParse('${m['e'] ?? ''}'),
              after: m['a'] as String?,
              assignee: m['to'] as String?,
              assigneeName: m['nm'] as String?,
              order: (m['o'] as num?)?.toInt() ?? 0,
              status: (m['st'] as num?)?.toInt(),
              progress: ((m['p'] as num?)?.toDouble() ?? 0).clamp(0, 100) / 100,
              doneAt: DateTime.tryParse('${m['dn'] ?? ''}'),
              description: m['d'] as String?,
              co: _list(m['co']),
              controller: '${m['ctl'] ?? ''}'.contains('@') ? '${m['ctl']}'.toLowerCase() : null,
              observers: _list(m['obs']),
              checklist: [
                for (final c in (m['ck'] is List ? m['ck'] as List : const []).whereType<Map>())
                  if ('${c['t'] ?? ''}'.trim().isNotEmpty) ChecklistItem('${c['t']}'.trim(), done: c['d'] == true),
              ],
              names: {
                if (m['n'] is Map)
                  for (final e in (m['n'] as Map).entries)
                    if ('${e.key}'.contains('@') && e.value is String) '${e.key}'.toLowerCase(): e.value as String,
              },
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Чек-лист после изменения пунктов постановщиком: у оставшихся пунктов —
/// прежние отметки (по тексту), новые — не выполнены.
List<ChecklistItem> mergeChecklist(List<ChecklistItem> old, List<String> texts) {
  final done = <String, bool>{for (final o in old) o.text.trim().toLowerCase(): o.done};
  return [
    for (final t in texts)
      if (t.trim().isNotEmpty) ChecklistItem(t.trim(), done: done[t.trim().toLowerCase()] ?? false),
  ];
}

/// У срока есть время (13.11.2026, замечание владельца «время очень
/// важно»): срок без времени хранится полуночью.
bool dueHasTime(DateTime? d) => d != null && (d.hour != 0 || d.minute != 0);

/// Срок для отметки и плана: «2026-11-21» или «2026-11-21T15:30».
String dueStamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  return dueHasTime(d) ? '${date}T${two(d.hour)}:${two(d.minute)}' : date;
}

/// Статусы (те же коды, что AssignmentStatus — без зависимости от кодека).
const _done = 4;
const _review = 3;
const _inProgress = 2;
const _cancelled = 6;

/// Доля выполненного этапа: принят — 1; иначе по чек-листу, а без него —
/// по статусу (на проверке — 0.8, в работе — 0.4).
double stageProgress(int status, List<ChecklistItem> checklist) {
  if (status == _done) return 1;
  final f = ChecklistItem.fraction(checklist);
  if (f != null) return status == _review ? (f < 0.9 ? 0.9 : f) : f;
  if (status == _review) return 0.8;
  if (status == _inProgress) return 0.4;
  return 0;
}

/// Прогресс проекта — среднее по этапам (снятые не считаются).
/// Статус проекта по этапам (снятые не считаются): все приняты —
/// выполнено; хоть один начат — в работе; иначе — свой статус проекта.
int projectStatus(int own, List<int> stages) {
  if (own == _cancelled) return own;
  final live = [for (final s in stages) if (s != _cancelled) s];
  if (live.isEmpty) return own;
  if (live.every((s) => s == _done)) return _done;
  if (live.any((s) => s == _inProgress || s == _review || s == _done)) return _inProgress;
  return own;
}

/// План участника: [fromMail] — план из письма проекта, [own] — свои этапы
/// с текущим статусом (заменяют одноимённые по id). По порядку этапов.
List<PlanStage> mergePlan({required List<PlanStage> own, required List<PlanStage> fromMail}) {
  final byId = {for (final p in own) p.id: p};
  final out = [for (final p in fromMail) byId.remove(p.id) ?? p, ...byId.values];
  out.sort((a, b) => a.order.compareTo(b.order));
  return out;
}

double projectProgress(List<PlanStage> stages) {
  final live = [for (final s in stages) if (s.status != _cancelled) s];
  if (live.isEmpty) return 0;
  return live.fold<double>(0, (a, s) => a + s.progress) / live.length;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Окончание этапа для расчёта сдвига: принят — день принятия; не принят и
/// срок прошёл — сегодня (он ещё идёт); иначе — плановый срок.
DateTime? stageEnd(PlanStage s, DateTime today) {
  if (s.status == _done) return s.doneAt == null ? s.due : _day(s.doneAt!);
  final due = s.due;
  if (due == null) return null;
  return _day(due).isBefore(_day(today)) ? _day(today) : _day(due);
}

/// Сдвиг последовательных этапов (как «связь окончание → начало» в MS
/// Project): этап «после X» начинается не раньше следующего дня после
/// окончания X. Возвращает этапы с новыми датами (длительность этапа
/// сохраняется) — только те, что сдвинулись; цепочка — по всем звеньям.
Map<String, ({DateTime start, DateTime due})> shiftSuccessors(List<PlanStage> stages, DateTime today) {
  final byId = {for (final s in stages) s.id: s};
  final out = <String, ({DateTime start, DateTime due})>{};
  DateTime? endOf(String id) {
    final moved = out[id];
    if (moved != null) return moved.due;
    final s = byId[id];
    return s == null ? null : stageEnd(s, today);
  }

  // Несколько проходов — цепочки любой длины (без циклов: ограничено).
  for (var pass = 0; pass < stages.length + 1; pass++) {
    var changed = false;
    for (final s in stages) {
      if (s.after == null || s.status == _done || s.status == _cancelled) continue;
      final prevEnd = endOf(s.after!);
      if (prevEnd == null) continue;
      final earliest = _day(prevEnd).add(const Duration(days: 1));
      final cur = out[s.id];
      final start = cur?.start ?? (s.start == null ? null : _day(s.start!));
      final due = cur?.due ?? (s.due == null ? null : _day(s.due!));
      if (start != null && !start.isBefore(earliest)) continue;
      if (start == null && (due == null || due.isAfter(prevEnd))) continue;
      final length = (start != null && due != null) ? due.difference(start).inDays : 0;
      final ns = earliest;
      final nd = ns.add(Duration(days: length < 0 ? 0 : length));
      if (cur == null || cur.start != ns || cur.due != nd) {
        out[s.id] = (start: ns, due: nd);
        changed = true;
      }
    }
    if (!changed) break;
  }
  return out;
}

/// Сроки этапов по порядку при создании: последовательный этап — со дня
/// после предыдущего, той же длительности (по умолчанию — 3 дня).
({DateTime start, DateTime due}) nextStageDates(DateTime? prevDue, DateTime projectStart, {int days = 3}) {
  final s = prevDue == null ? _day(projectStart) : _day(prevDue).add(const Duration(days: 1));
  return (start: s, due: s.add(Duration(days: days - 1 < 0 ? 0 : days - 1)));
}

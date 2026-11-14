// lib/services/mail/marks/mark_sync.dart
// «На контроле» и «Позже» на всех устройствах (решения владельца
// 13.11.2026). Раньше отметки жили только в базе одного устройства.
//
//  · IMAP (Gmail, Яндекс, Mail.ru и др.) — два постоянных ключевых слова на
//    самом письме: $OgnControl и $OgnLater (в Gmail — два ярлыка). Без дат:
//    срок контроля и время «Позже» остаются на устройстве, где их поставили.
//    Служебных писем и папок не создаём.
//  · Exchange (ActiveSync) — родной флажок «К исполнению»: текст «На
//    контроле · OGN-C» или «Посмотреть позже · OGN-L», срок контроля,
//    напоминание «Позже». В Outlook — обычный флажок с датой; снимут его
//    там — отметка снимется везде.
//
// Сверка письма — с последним разосланным состоянием (снимок по ящику):
// изменилось у себя — уходит на сервер (своё новее); изменилось на
// сервере — применяется у себя. Логика — здесь, без базы и сети.

import 'dart:convert';

/// Отметки письма: [c] — «На контроле» (0 нет, 1 жду ответа, 2 должен
/// ответить, 3 исполнено), [l] — «Позже» (0 нет, 1 отложено или
/// вернулось). [due] — срок контроля, [at] — когда вернуть (только
/// Exchange).
class MarkState {
  final int c;
  final int l;
  final DateTime? due;
  final DateTime? at;
  const MarkState({this.c = 0, this.l = 0, this.due, this.at});

  static const none = MarkState();

  bool get empty => c == 0 && l == 0;

  /// Отметки как флаги IMAP: 1 — «На контроле», 2 — «Позже».
  int get bits => (c > 0 ? 1 : 0) | (l > 0 ? 2 : 0);

  /// Одинаковы ли отметки; [dates] — сравнивать и сроки (Exchange).
  bool same(MarkState o, {bool dates = false}) =>
      c == o.c && l == o.l && (!dates || (_eq(due, o.due) && _eq(at, o.at)));

  static bool _eq(DateTime? a, DateTime? b) =>
      a == null || b == null ? a == b : a.toUtc().difference(b.toUtc()).inMinutes.abs() < 1;

  Map<String, Object?> toJson() => {
        if (c != 0) 'c': c,
        if (l != 0) 'l': l,
        if (due != null) 'd': due!.toUtc().toIso8601String(),
        if (at != null) 'a': at!.toUtc().toIso8601String(),
      };

  static MarkState fromJson(Map m) => MarkState(
        c: (m['c'] as num?)?.toInt().clamp(0, 3) ?? 0,
        l: (m['l'] as num?)?.toInt().clamp(0, 1) ?? 0,
        due: DateTime.tryParse('${m['d'] ?? ''}')?.toLocal(),
        at: DateTime.tryParse('${m['a'] ?? ''}')?.toLocal(),
      );

  /// Отметки строки письма из базы.
  static MarkState of({required int controlState, required int laterState, DateTime? followUpAt, DateTime? remindAt}) =>
      MarkState(
        c: controlState.clamp(0, 3),
        l: laterState > 0 ? 1 : 0,
        due: controlState == 1 || controlState == 2 ? followUpAt?.toLocal() : null,
        at: laterState > 0 ? remindAt?.toLocal() : null,
      );

  @override
  String toString() => 'c$c l$l${due == null ? '' : ' до $due'}${at == null ? '' : ' в $at'}';
}

/// Что сделать с письмом после сверки.
enum MarkAction { none, push, apply }

abstract final class MarkSync {
  /// Сверка флагов IMAP одного письма: [local] — сейчас у себя, [synced] —
  /// последнее разосланное (null — письмо ещё не сверялось), [remote] — на
  /// сервере (null — сервер не сообщил). Изменилось у себя — на сервер;
  /// иначе изменилось на сервере — у себя.
  static MarkAction planBits({required int local, required int? synced, required int? remote}) {
    final s = synced ?? 0;
    if (local != s) return remote == local ? MarkAction.none : MarkAction.push;
    if (remote != null && remote != s) return MarkAction.apply;
    return MarkAction.none;
  }

  /// Сверка флажка Exchange одного письма: то же, но с датами.
  static MarkAction planFlag({required MarkState local, required MarkState? synced, required MarkState? remote}) {
    final s = synced ?? MarkState.none;
    if (!local.same(s, dates: true)) {
      return remote != null && remote.same(local, dates: true) ? MarkAction.none : MarkAction.push;
    }
    if (remote != null && !remote.same(s, dates: true)) return MarkAction.apply;
    return MarkAction.none;
  }

  /// Снимок: письмо → последнее разосланное (IMAP — флаги, Exchange —
  /// отметки с датами).
  static String encodeSnapshot(Map<String, MarkState> s) =>
      jsonEncode({for (final e in s.entries) e.key: e.value.toJson()});

  static Map<String, MarkState> decodeSnapshot(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final m = jsonDecode(json) as Map;
      return {for (final e in m.entries) if (e.value is Map) '${e.key}': MarkState.fromJson(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  /// Отметки по флагам IMAP: «На контроле» — прежний вид у себя или [kind]
  /// (жду ответа или должен ответить — по письму), «Позже» — без даты.
  static MarkState fromBits(int bits, {required MarkState local, required int kind}) => MarkState(
        c: bits & 1 == 0 ? 0 : (local.c > 0 ? local.c : kind),
        l: bits & 2 == 0 ? 0 : 1,
        due: bits & 1 == 0 ? null : local.due,
        at: bits & 2 == 0 ? null : local.at,
      );
}

/// Текст флажка Exchange: «На контроле · OGN-C», «Посмотреть позже ·
/// OGN-L», оба — «… · OGN-CL». По коду OGN-… флажок узнаётся на любом
/// языке; флажок без кода — обычный флажок пользователя.
abstract final class MarkFlag {
  static final _re = RegExp(r'OGN-(CL|C|L)\s*$');

  /// Код флажка: 'C', 'L', 'CL'; null — флажок не наш.
  static String? codeOf(String? flagType) => _re.firstMatch((flagType ?? '').trim())?.group(1);

  static String text(MarkState s, {required String control, required String later}) {
    final code = '${s.c > 0 ? 'C' : ''}${s.l > 0 ? 'L' : ''}';
    return '${s.c > 0 ? control : later} · OGN-$code';
  }

  /// Отметки по флажку: [code] — код из текста, [complete] — флажок
  /// «выполнено» (контроль исполнен), [kind] — вид контроля по письму.
  static MarkState stateOf(String code, {required bool complete, DateTime? due, DateTime? reminder, required MarkState local, required int kind}) {
    final c = code.contains('C') ? (complete ? 3 : (local.c == 1 || local.c == 2 ? local.c : kind)) : 0;
    final l = code.contains('L') && !complete ? 1 : 0;
    return MarkState(c: c, l: l, due: c == 1 || c == 2 ? due : null, at: l == 1 ? reminder : null);
  }
}

// lib/services/mail/imap/imap_reconcile.dart
//
// Сверка папки IMAP (2.3.2): письма, которые есть на сервере, а на
// устройстве их нет.
//
// Журналы Яндекса 10–11.11.2026: письмо лежало во «Входящих» на сервере, а
// приложение его не показывало, пока пользователь не нашёл его поиском.
// Синхронизация запрашивала только письма с UID больше известного: письмо,
// которое сервер не отдал в ответе с новыми письмами (или показал позже —
// с UID меньше уже известного), не загружалось никогда. Теперь каждый
// проход сравнивает номера писем сервера с письмами на устройстве и
// догружает недостающие.
//
// Сверяется только верх папки — [top] самых новых писем сервера, UID больше
// наименьшего UID письма на устройстве в пределах периода синхронизации:
// всё, что ниже, — история за срезом периода, её на устройстве и не должно
// быть.

class ImapReconcile {
  ImapReconcile._();

  /// Сколько самых новых писем папки сверять.
  static const top = 300;

  /// Сколько дней не спрашивать повторно письмо, которое не сохранилось
  /// (старше периода синхронизации при свежем UID — перенесено в папку
  /// недавно; сервер назвал, но не отдал).
  static const skipDays = 7;

  /// Сколько пропусков помнить на папку.
  static const skipCap = 400;

  /// UID писем для догрузки, новые первыми.
  ///
  /// [server] — UID на сервере: проверенное окно папки и письма с
  /// изменёнными флагами. [local] — UID писем, которые есть на устройстве
  /// (в любой папке: письмо могло быть перемещено здесь, а сервер об этом
  /// ещё не знает). [floor] — наименьший UID письма папки на устройстве в
  /// пределах периода синхронизации; null — таких писем нет, сверять не с
  /// чем. [pending] — письма с действием, ждущим отправки на сервер
  /// (удаление, перемещение). [skipped] — см. [skipDays].
  static List<int> missing({
    required Iterable<int> server,
    required Set<int> local,
    required int? floor,
    Set<int> pending = const {},
    Set<int> skipped = const {},
    int limit = 50,
  }) {
    if (floor == null) return const [];
    final cands = server.where((u) => u > floor).toSet().toList()..sort((a, b) => b.compareTo(a));
    final out = <int>[];
    for (final u in cands.take(top)) {
      if (local.contains(u) || pending.contains(u) || skipped.contains(u)) continue;
      out.add(u);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Пропуски из настроек («UID@секунды»): действующие на момент [now].
  static Set<int> readSkipped(List<String>? stored, DateTime now) {
    final out = <int>{};
    final since = now.millisecondsSinceEpoch ~/ 1000 - skipDays * 86400;
    for (final s in stored ?? const <String>[]) {
      final i = s.indexOf('@');
      if (i <= 0) continue;
      final uid = int.tryParse(s.substring(0, i));
      final at = int.tryParse(s.substring(i + 1));
      if (uid != null && at != null && at >= since) out.add(uid);
    }
    return out;
  }

  /// Пропуски для сохранения: действующие прежние и [add] (самые свежие —
  /// не больше [skipCap]).
  static List<String> writeSkipped(List<String>? stored, Iterable<int> add, DateTime now) {
    final sec = now.millisecondsSinceEpoch ~/ 1000;
    final since = sec - skipDays * 86400;
    final byUid = <int, int>{};
    for (final s in stored ?? const <String>[]) {
      final i = s.indexOf('@');
      if (i <= 0) continue;
      final uid = int.tryParse(s.substring(0, i));
      final at = int.tryParse(s.substring(i + 1));
      if (uid != null && at != null && at >= since) byUid[uid] = at;
    }
    for (final u in add) {
      byUid[u] = sec;
    }
    final entries = byUid.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(skipCap)) '${e.key}@${e.value}'];
  }
}

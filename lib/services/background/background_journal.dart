// lib/services/background/background_journal.dart
// Журнал фоновой работы: когда что запускалось, сколько работало и чем
// закончилось — пульс будильника (Android), задача WorkManager / BGTask
// (iOS), таймер в открытом приложении, уход в фон и возврат, причины
// завершения процесса системой.
//
// Пишется в общий журнал (строки «ФОН …») и в короткую историю в
// SharedPreferences (последние 150 записей) — она попадает в пакет
// диагностики: по ней видно, например, что на телефоне с MIUI пульс
// перестал приходить через 40 минут после сворачивания, а WorkManager
// запускался раз в 3 часа.

import '../../core/utils/text_safe.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/platform_diagnostics.dart';

class BackgroundJournal {
  BackgroundJournal._();

  static const _key = 'bg_journal_v1';
  static const _max = 150;

  /// Выполнить [body] с записью начала, длительности и результата.
  /// [describe] — короткий итог для журнала (например, «пропуск: приложение
  /// работает само»).
  static Future<T> track<T>(String kind, Future<T> Function() body,
      {String Function(T result)? describe, bool withState = true}) async {
    final started = DateTime.now();
    var state = '';
    if (withState) {
      state = PlatformDiagnostics.brief(await PlatformDiagnostics.collect(light: true));
    }
    AppLogger.info('ФОН $kind: начало${state.isEmpty ? '' : ' ($state)'}');
    try {
      final r = await body();
      final ms = DateTime.now().difference(started).inMilliseconds;
      final what = describe?.call(r) ?? 'ok';
      AppLogger.info('ФОН $kind: готово за ${_dur(ms)} — $what');
      await _append(kind, started, ms, what, state);
      return r;
    } catch (e) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      AppLogger.warning('ФОН $kind: ошибка через ${_dur(ms)} — $e');
      await _append(kind, started, ms, 'ошибка: ${_short('$e')}', state);
      rethrow;
    } finally {
      AppLogger.flushNow();
    }
  }

  /// Мгновенное событие (уход в фон, возврат, завершение процесса системой).
  static Future<void> note(String kind, String detail, {DateTime? at}) async {
    AppLogger.info('ФОН $kind: $detail');
    await _append(kind, at ?? DateTime.now(), 0, detail, '');
  }

  static String _dur(int ms) => ms < 1000 ? '$ms мс' : '${(ms / 1000).toStringAsFixed(1)} с';

  static String _short(String s) {
    final t = s.split('\n').first;
    return t.length > 120 ? '${cutSafe(t, 120)}…' : t;
  }

  static Future<void> _append(String kind, DateTime at, int ms, String result, String state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Пишут и главный, и фоновый изолят — перечитываем перед записью.
      await prefs.reload();
      final list = prefs.getStringList(_key) ?? <String>[];
      list.add(jsonEncode({'k': kind, 't': at.millisecondsSinceEpoch, 'd': ms, 'r': result, 's': state}));
      while (list.length > _max) {
        list.removeAt(0);
      }
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  /// Виды записей, которые означают проверку почты в фоне (1.6.45).
  static const _checkKinds = {'WorkManager', 'BGTask iOS', 'BGProcessing iOS', 'пульс', 'сигнал iOS'};

  /// Последняя проверка почты в фоне (для «Проверки почты»): когда и какой
  /// механизм. Пропуски и ошибки не в счёт. null — фоновых проверок ещё не было.
  static Future<({DateTime at, String kind})?> lastBackgroundCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key) ?? const <String>[];
      DateTime? best;
      String? bestKind;
      for (final s in list) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final kind = m['k'] as String? ?? '';
        if (!_checkKinds.contains(kind)) continue;
        final r = '${m['r'] ?? ''}';
        if (r.startsWith('пропуск') || r.startsWith('ошибка') || r.contains('проверило приложение: пропуск')) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(m['t'] as int)
            .add(Duration(milliseconds: (m['d'] as int?) ?? 0));
        if (best == null || at.isAfter(best)) {
          best = at;
          bestKind = kind;
        }
      }
      return best == null ? null : (at: best, kind: bestKind!);
    } catch (_) {
      return null;
    }
  }

  /// История для пакета диагностики: по строке на запись, новые снизу, и
  /// сводка — сколько раз и как долго работал каждый вид задач за сутки.
  static Future<String> report() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key) ?? const <String>[];
      final b = StringBuffer();
      final day = DateTime.now().subtract(const Duration(hours: 24));
      final stat = <String, (int, int)>{};
      for (final s in list) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final at = DateTime.fromMillisecondsSinceEpoch(m['t'] as int);
        final d = m['d'] as int;
        if (at.isAfter(day)) {
          final (n, total) = stat[m['k']] ?? (0, 0);
          stat[m['k'] as String] = (n + 1, total + d);
        }
        final ts = at.toIso8601String().substring(5, 19).replaceFirst('T', ' ');
        b.writeln('  $ts  ${m['k']}${d > 0 ? ' ${_dur(d)}' : ''} — ${m['r']}'
            '${(m['s'] as String?)?.isNotEmpty == true ? ' (${m['s']})' : ''}');
      }
      final head = StringBuffer('За сутки: ');
      head.write(stat.isEmpty
          ? 'записей нет'
          : stat.entries.map((e) => '${e.key} ×${e.value.$1}, всего ${_dur(e.value.$2)}').join('; '));
      return '$head\n$b';
    } catch (e) {
      return 'нет данных ($e)';
    }
  }
}

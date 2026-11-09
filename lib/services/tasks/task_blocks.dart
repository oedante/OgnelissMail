// lib/services/tasks/task_blocks.dart
// Время задачи на шкале «Моего дня» (решение владельца 09.11.2026: «блок
// задач держим локально» — задачи бывают и простыми напоминаниями себе).
// Только в приложении: на сервер (Exchange, CalDAV) не уходит, срок задачи
// не меняет, в календаре время не занимает. Хранится в настройках
// телефона: ключ — ящик и id задачи, значение — начало и длительность.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';

@immutable
class TaskBlock {
  final DateTime start;
  final int minutes;
  const TaskBlock(this.start, this.minutes);

  DateTime get end => start.add(Duration(minutes: minutes));

  Map<String, Object> toJson() => {'s': start.toIso8601String(), 'm': minutes};

  static TaskBlock? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = DateTime.tryParse('${j['s']}');
    final m = j['m'];
    if (s == null || m is! int || m <= 0) return null;
    return TaskBlock(s, m);
  }

  @override
  bool operator ==(Object other) => other is TaskBlock && other.start == start && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(start, minutes);
}

/// Ключ задачи: ящик и id.
String taskBlockKey(String accountId, String id) => '$accountId|$id';

class TaskBlocksNotifier extends Notifier<Map<String, TaskBlock>> {
  static const prefKey = 'task_blocks_v1';

  /// Блоки старше двух недель забываются.
  static const keep = Duration(days: 14);

  late SharedPreferences _prefs;

  @override
  Map<String, TaskBlock> build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return decode(_prefs.getString(prefKey), now: DateTime.now());
  }

  @visibleForTesting
  static Map<String, TaskBlock> decode(String? raw, {required DateTime now}) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const {};
      final out = <String, TaskBlock>{};
      for (final e in m.entries) {
        final b = TaskBlock.fromJson(e.value);
        if (b != null && b.start.isAfter(now.subtract(keep))) out['${e.key}'] = b;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Поставить задачу на время [block] или убрать со шкалы (null).
  Future<void> set(String accountId, String id, TaskBlock? block) async {
    final key = taskBlockKey(accountId, id);
    final next = {...state};
    if (block == null) {
      if (next.remove(key) == null) return;
    } else {
      next[key] = block;
    }
    state = next;
    await _prefs.setString(prefKey, jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}));
  }
}

final taskBlocksProvider = NotifierProvider<TaskBlocksNotifier, Map<String, TaskBlock>>(TaskBlocksNotifier.new);

/// Расчёты шкалы (отдельно — для тестов).
abstract final class DayTimeline {
  /// Время в часах от полуночи [day].
  static double hourOf(DateTime t, DateTime day) => t.difference(day).inMinutes / 60;

  /// Время по положению на шкале: [hour] — часы от полуночи, шаг 15 минут,
  /// в пределах суток (последнее начало — 23:45).
  static DateTime snap(DateTime day, double hour) {
    final q = (hour * 4).round().clamp(0, 95);
    return DateTime(day.year, day.month, day.day).add(Duration(minutes: q * 15));
  }

  /// Колонки пересекающихся отрезков [from, to): номер колонки и сколько
  /// колонок в группе — встречи рядом, а не друг на друге.
  static List<({int col, int cols})> columns(List<({double from, double to})> items) {
    final order = [for (var i = 0; i < items.length; i++) i]
      ..sort((a, b) => items[a].from == items[b].from
          ? items[b].to.compareTo(items[a].to)
          : items[a].from.compareTo(items[b].from));
    final out = List<({int col, int cols})>.filled(items.length, (col: 0, cols: 1));
    var group = <int>[];
    var groupEnd = double.negativeInfinity;
    final colEnds = <double>[];
    void close() {
      final n = colEnds.length;
      for (final i in group) {
        out[i] = (col: out[i].col, cols: n == 0 ? 1 : n);
      }
      group = [];
      colEnds.clear();
    }

    for (final i in order) {
      final it = items[i];
      if (it.from >= groupEnd && group.isNotEmpty) close();
      var c = colEnds.indexWhere((e) => e <= it.from);
      if (c < 0) {
        c = colEnds.length;
        colEnds.add(it.to);
      } else {
        colEnds[c] = it.to;
      }
      out[i] = (col: c, cols: 1);
      group.add(i);
      if (it.to > groupEnd) groupEnd = it.to;
    }
    if (group.isNotEmpty) close();
    return out;
  }

  /// Свободные окна не короче [min] минут в [from, to) между занятыми
  /// отрезками [busy] (часы от полуночи).
  static List<({double from, double to})> free(List<({double from, double to})> busy,
      {required double from, required double to, int min = 30}) {
    final sorted = [...busy]..sort((a, b) => a.from.compareTo(b.from));
    final out = <({double from, double to})>[];
    var cur = from;
    for (final b in sorted) {
      if (b.to <= cur) continue;
      if (b.from >= to) break;
      if (b.from - cur >= min / 60) out.add((from: cur, to: b.from));
      if (b.to > cur) cur = b.to;
    }
    if (to - cur >= min / 60) out.add((from: cur, to: to));
    return out;
  }
}

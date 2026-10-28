// lib/features/settings/providers/quiet_hours_provider.dart
// «Тихие часы»: в заданном интервале уведомления о письмах не показываются.
// Хранится в SharedPreferences. Поддерживает интервал через полночь (22:00–08:00).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

class QuietHoursSettings {
  final bool enabled;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  /// Дни недели, в которые действуют тихие часы (1=Пн … 7=Вс, как
  /// `DateTime.weekday`). По умолчанию — все дни, то есть прежнее поведение.
  /// Для интервала через полночь днём считается день НАЧАЛА: «тихо в Пн с 22:00»
  /// охватывает ночь с понедельника на вторник.
  final Set<int> days;

  const QuietHoursSettings({
    this.enabled = false,
    this.startHour = 22,
    this.startMinute = 0,
    this.endHour = 8,
    this.endMinute = 0,
    this.days = const {1, 2, 3, 4, 5, 6, 7},
  });

  QuietHoursSettings copyWith({bool? enabled, int? startHour, int? startMinute,
          int? endHour, int? endMinute, Set<int>? days}) =>
      QuietHoursSettings(
        enabled: enabled ?? this.enabled,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        endHour: endHour ?? this.endHour,
        endMinute: endMinute ?? this.endMinute,
        days: days ?? this.days,
      );

  bool get isEveryDay => days.length >= 7;

  TimeOfDay get start => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get end => TimeOfDay(hour: endHour, minute: endMinute);
}

/// Проверка «сейчас тихий час?» по значениям из prefs (для сервиса уведомлений).
class QuietHours {
  /// Разбор набора дней из prefs. Пустое/отсутствующее значение = все дни
  /// (совместимость с настройками, сохранёнными до появления расписания).
  static Set<int> daysFrom(SharedPreferences p) {
    final raw = p.getString('qh_days');
    if (raw == null || raw.trim().isEmpty) return const {1, 2, 3, 4, 5, 6, 7};
    final set = raw.split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet();
    return set.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : set;
  }

  static bool isQuietNow(SharedPreferences p, {DateTime? now}) {
    if (!(p.getBool('qh_enabled') ?? false)) return false;
    final n = now ?? DateTime.now();
    final cur = n.hour * 60 + n.minute;
    final startMin = (p.getInt('qh_start_h') ?? 22) * 60 + (p.getInt('qh_start_m') ?? 0);
    final endMin = (p.getInt('qh_end_h') ?? 8) * 60 + (p.getInt('qh_end_m') ?? 0);
    if (startMin == endMin) return false;
    final days = daysFrom(p);

    if (startMin < endMin) {
      // Интервал внутри одних суток — проверяем текущий день.
      return days.contains(n.weekday) && cur >= startMin && cur < endMin;
    }
    // Интервал через полночь. Вечерняя часть принадлежит сегодняшнему дню,
    // утренняя (после полуночи) — ВЧЕРАШНЕМУ: «тихо в Пн с 22:00 до 08:00»
    // означает ночь с понедельника на вторник.
    if (cur >= startMin) return days.contains(n.weekday);
    if (cur < endMin) {
      final yesterday = n.weekday == 1 ? 7 : n.weekday - 1;
      return days.contains(yesterday);
    }
    return false;
  }
}

class QuietHoursNotifier extends StateNotifier<QuietHoursSettings> {
  final SharedPreferences _p;
  QuietHoursNotifier(this._p) : super(_load(_p));

  static QuietHoursSettings _load(SharedPreferences p) => QuietHoursSettings(
        enabled: p.getBool('qh_enabled') ?? false,
        startHour: p.getInt('qh_start_h') ?? 22,
        startMinute: p.getInt('qh_start_m') ?? 0,
        endHour: p.getInt('qh_end_h') ?? 8,
        endMinute: p.getInt('qh_end_m') ?? 0,
        days: QuietHours.daysFrom(p),
      );

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _p.setBool('qh_enabled', v);
  }

  Future<void> setStart(TimeOfDay t) async {
    state = state.copyWith(startHour: t.hour, startMinute: t.minute);
    await _p.setInt('qh_start_h', t.hour);
    await _p.setInt('qh_start_m', t.minute);
  }

  /// Задать дни недели. Пустой набор недопустим (иначе тихие часы включены,
  /// но не работают ни в один день) — в этом случае включаем все дни.
  Future<void> setDays(Set<int> days) async {
    final normalized = days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : days;
    state = state.copyWith(days: normalized);
    await _p.setString('qh_days', (normalized.toList()..sort()).join(','));
  }

  Future<void> setEnd(TimeOfDay t) async {
    state = state.copyWith(endHour: t.hour, endMinute: t.minute);
    await _p.setInt('qh_end_h', t.hour);
    await _p.setInt('qh_end_m', t.minute);
  }
}

final quietHoursProvider = StateNotifierProvider<QuietHoursNotifier, QuietHoursSettings>((ref) {
  return QuietHoursNotifier(ref.watch(sharedPrefsProvider));
});

// lib/services/mail/focus_mode_service.dart
// Режим фокусировки:
// - Порционная доставка (10:00, 14:00, 18:00 — настраиваемо)
// - VIP-контакты пробивают фильтр мгновенно
// - Тихий режим между доставками
// - Автоотключение в выходные (опционально)

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../data/models/email_model.dart';

/// Провайдер
final focusModeProvider = StateNotifierProvider<FocusModeNotifier, FocusModeState>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return FocusModeNotifier(prefs);
});

class FocusModeState {
  final bool isEnabled;
  final List<String> deliveryTimes; // ["10:00", "14:00", "18:00"]
  final List<String> vipEmails;     // VIP-отправители (пробивают фильтр)
  final List<String> vipKeywords;   // VIP-ключевые слова в теме
  final bool disableOnWeekends;
  final bool isCurrentlyActive;     // Сейчас между доставками

  const FocusModeState({
    this.isEnabled = false,
    this.deliveryTimes = const ['10:00', '14:00', '18:00'],
    this.vipEmails = const [],
    this.vipKeywords = const [],
    this.disableOnWeekends = true,
    this.isCurrentlyActive = false,
  });

  FocusModeState copyWith({
    bool? isEnabled,
    List<String>? deliveryTimes,
    List<String>? vipEmails,
    List<String>? vipKeywords,
    bool? disableOnWeekends,
    bool? isCurrentlyActive,
  }) {
    return FocusModeState(
      isEnabled: isEnabled ?? this.isEnabled,
      deliveryTimes: deliveryTimes ?? this.deliveryTimes,
      vipEmails: vipEmails ?? this.vipEmails,
      vipKeywords: vipKeywords ?? this.vipKeywords,
      disableOnWeekends: disableOnWeekends ?? this.disableOnWeekends,
      isCurrentlyActive: isCurrentlyActive ?? this.isCurrentlyActive,
    );
  }
}

class FocusModeNotifier extends StateNotifier<FocusModeState> {
  final SharedPreferences _prefs;
  static const _key = 'focus_mode';

  FocusModeNotifier(this._prefs) : super(const FocusModeState()) {
    _load();
  }

  void _load() {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        state = FocusModeState(
          isEnabled: m['isEnabled'] as bool? ?? false,
          deliveryTimes: (m['deliveryTimes'] as List?)?.cast<String>() ?? ['10:00', '14:00', '18:00'],
          vipEmails: (m['vipEmails'] as List?)?.cast<String>() ?? [],
          vipKeywords: (m['vipKeywords'] as List?)?.cast<String>() ?? [],
          disableOnWeekends: m['disableOnWeekends'] as bool? ?? true,
        );
      } catch (_) {}
    }
    _updateActiveStatus();
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode({
      'isEnabled': state.isEnabled,
      'deliveryTimes': state.deliveryTimes,
      'vipEmails': state.vipEmails,
      'vipKeywords': state.vipKeywords,
      'disableOnWeekends': state.disableOnWeekends,
    }));
  }

  void setEnabled(bool v) { state = state.copyWith(isEnabled: v); _save(); _updateActiveStatus(); }
  void setDeliveryTimes(List<String> v) { state = state.copyWith(deliveryTimes: v); _save(); }
  void addVipEmail(String email) { state = state.copyWith(vipEmails: [...state.vipEmails, email]); _save(); }
  void removeVipEmail(String email) { state = state.copyWith(vipEmails: state.vipEmails.where((e) => e != email).toList()); _save(); }
  void addVipKeyword(String kw) { state = state.copyWith(vipKeywords: [...state.vipKeywords, kw]); _save(); }
  void removeVipKeyword(String kw) { state = state.copyWith(vipKeywords: state.vipKeywords.where((e) => e != kw).toList()); _save(); }

  /// Является ли письмо VIP: отправитель в VIP-списке ИЛИ тема содержит
  /// VIP-ключевое слово ИЛИ высокий приоритет.
  bool isVip(EmailModel email) {
    final sender = email.from.email.toLowerCase();
    if (state.vipEmails.any((e) => e.toLowerCase() == sender)) return true;
    final subject = email.subject.toLowerCase();
    if (state.vipKeywords.any((k) => k.isNotEmpty && subject.contains(k.toLowerCase()))) return true;
    return email.priority == EmailPriority.high;
  }
  void setDisableOnWeekends(bool v) { state = state.copyWith(disableOnWeekends: v); _save(); }

  /// Выгрузить VIP-списки (отправители + ключевые слова) в JSON — для обмена
  /// между сотрудниками или переноса на другое устройство.
  String exportVipJson() => const JsonEncoder.withIndent('  ').convert({
        'vipEmails': state.vipEmails,
        'vipKeywords': state.vipKeywords,
      });

  /// Импорт VIP-списков из JSON. `replace` = заменить текущие, иначе — добавить
  /// (с дедупликацией). Возвращает число импортированных записей (0 — ошибка
  /// формата, текущие данные при этом не меняются).
  Future<int> importVipJson(String json, {bool replace = true}) async {
    try {
      final m = jsonDecode(json);
      if (m is! Map) return 0;
      final emails = ((m['vipEmails'] as List?) ?? const [])
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty);
      final keywords = ((m['vipKeywords'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty);
      if (emails.isEmpty && keywords.isEmpty) return 0;
      final newEmails = replace
          ? emails.toSet().toList()
          : {...state.vipEmails, ...emails}.toList();
      final newKeywords = replace
          ? keywords.toSet().toList()
          : {...state.vipKeywords, ...keywords}.toList();
      state = state.copyWith(vipEmails: newEmails, vipKeywords: newKeywords);
      await _save();
      return newEmails.length + newKeywords.length;
    } catch (e) {
      AppLogger.warning('Импорт VIP: $e');
      return 0;
    }
  }

  /// Проверить, нужно ли показывать уведомление
  bool shouldNotify(EmailModel email) {
    if (!state.isEnabled) return true;

    // Выходные — если отключено на выходных
    final now = DateTime.now();
    if (state.disableOnWeekends && (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday)) {
      return true;
    }

    // VIP — всегда уведомлять. Используем ту же проверку, что и для метки VIP
    // (отправитель ИЛИ ключевое слово в теме ИЛИ высокий приоритет), иначе
    // «тихие часы» пробивал только отправитель, а ключевые слова — нет.
    if (isVip(email)) return true;

    // Проверяем, наступило ли время доставки
    return _isDeliveryTime();
  }

  /// Сейчас окно доставки (±15 минут от выбранного времени).
  bool get inDeliveryWindow => _isDeliveryTime();

  bool _isDeliveryTime() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (final time in state.deliveryTimes) {
      final parts = time.split(':');
      final timeMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      // Окно доставки: ±15 минут
      if ((currentMinutes - timeMinutes).abs() <= 15) return true;
    }

    return false;
  }

  void _updateActiveStatus() {
    if (!state.isEnabled) {
      state = state.copyWith(isCurrentlyActive: false);
      return;
    }

    final now = DateTime.now();
    if (state.disableOnWeekends && (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday)) {
      state = state.copyWith(isCurrentlyActive: false);
      return;
    }

    state = state.copyWith(isCurrentlyActive: !_isDeliveryTime());
  }
}

/// Письма, о которых режим фокуса промолчал: в окно доставки приходит одно
/// сводное уведомление «N новых писем» со списком (раньше вне окна писем как
/// будто не было — описание обещало «пакеты», 10.10.2026). Хранится в
/// настройках: копится и в фоновом процессе.
class FocusDigest {
  FocusDigest._();
  static const _kCount = 'focus_held_count';
  static const _kLines = 'focus_held_lines';

  static Future<void> hold(SharedPreferences p, List<String> lines) async {
    if (lines.isEmpty) return;
    await p.setInt(_kCount, (p.getInt(_kCount) ?? 0) + lines.length);
    final cur = p.getStringList(_kLines) ?? const <String>[];
    // Свежие сверху, не больше шести строк (больше уведомление не покажет).
    await p.setStringList(_kLines, [...lines.reversed, ...cur].take(6).toList());
  }

  /// Забрать накопленное (и очистить). null — нечего показывать.
  static Future<({int count, List<String> lines})?> take(SharedPreferences p) async {
    final n = p.getInt(_kCount) ?? 0;
    if (n <= 0) return null;
    final lines = p.getStringList(_kLines) ?? const <String>[];
    await p.remove(_kCount);
    await p.remove(_kLines);
    return (count: n, lines: lines);
  }
}


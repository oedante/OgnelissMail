// lib/services/mail/auto_responder_service.dart
// Автоответчик (Out of Office):
// - Настройка шаблона ответа (ru/en)
// - Дата начала и окончания
// - Отдельные шаблоны для внутренних/внешних
// - Включение/выключение
// - Для Exchange: через EWS SetOofStatus
// - Для IMAP: локальная отправка автоответа при получении

import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers/shared_prefs_provider.dart';

final autoResponderProvider =
    StateNotifierProvider<AutoResponderNotifier, AutoResponderState>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return AutoResponderNotifier(prefs);
});

class AutoResponderState {
  final bool isEnabled;
  final DateTime? startDate;
  final DateTime? endDate;
  final String internalMessage;
  final String externalMessage;
  final bool sendToExternal;
  final String? accountId;

  const AutoResponderState({
    this.isEnabled = false,
    this.startDate,
    this.endDate,
    this.internalMessage = '',
    this.externalMessage = '',
    this.sendToExternal = false,
    this.accountId,
  });

  AutoResponderState copyWith({
    bool? isEnabled,
    DateTime? startDate,
    DateTime? endDate,
    String? internalMessage,
    String? externalMessage,
    bool? sendToExternal,
    String? accountId,
  }) {
    return AutoResponderState(
      isEnabled: isEnabled ?? this.isEnabled,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      internalMessage: internalMessage ?? this.internalMessage,
      externalMessage: externalMessage ?? this.externalMessage,
      sendToExternal: sendToExternal ?? this.sendToExternal,
      accountId: accountId ?? this.accountId,
    );
  }

  bool get isActive {
    if (!isEnabled) return false;
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }
}

class AutoResponderNotifier extends StateNotifier<AutoResponderState> {
  final SharedPreferences _prefs;
  static const _key = 'auto_responder';

  AutoResponderNotifier(this._prefs) : super(const AutoResponderState()) {
    _load();
  }

  void _load() {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        state = AutoResponderState(
          isEnabled: m['isEnabled'] as bool? ?? false,
          startDate: m['startDate'] != null ? DateTime.tryParse(m['startDate'] as String) : null,
          endDate: m['endDate'] != null ? DateTime.tryParse(m['endDate'] as String) : null,
          internalMessage: m['internalMessage'] as String? ?? '',
          externalMessage: m['externalMessage'] as String? ?? '',
          sendToExternal: m['sendToExternal'] as bool? ?? false,
          accountId: m['accountId'] as String?,
        );
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode({
      'isEnabled': state.isEnabled,
      'startDate': state.startDate?.toIso8601String(),
      'endDate': state.endDate?.toIso8601String(),
      'internalMessage': state.internalMessage,
      'externalMessage': state.externalMessage,
      'sendToExternal': state.sendToExternal,
      'accountId': state.accountId,
    }));
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(isEnabled: v);
    await _save();
    // Новое окно отсутствия — прежний список «кому уже ответили» неактуален.
    await _resetReplied();
    AppLogger.info('AutoResponder: ${v ? "enabled" : "disabled"}');
  }

  Future<void> setDates(DateTime? start, DateTime? end) async {
    // Явно, без copyWith: null должен сбрасывать даты (copyWith его игнорирует).
    state = AutoResponderState(
      isEnabled: state.isEnabled,
      startDate: start,
      endDate: end,
      internalMessage: state.internalMessage,
      externalMessage: state.externalMessage,
      sendToExternal: state.sendToExternal,
      accountId: state.accountId,
    );
    await _save();
    await _resetReplied();
  }

  Future<void> setInternalMessage(String msg) async {
    state = state.copyWith(internalMessage: msg);
    await _save();
  }

  Future<void> setExternalMessage(String msg) async {
    state = state.copyWith(externalMessage: msg);
    await _save();
  }

  Future<void> setSendToExternal(bool v) async {
    state = state.copyWith(sendToExternal: v);
    await _save();
  }

  Future<void> setAccountId(String? id) async {
    state = state.copyWith(accountId: id);
    await _save();
  }

  /// Получить текст автоответа для данного отправителя
  String? getAutoReplyFor(String senderEmail, {required bool isInternal}) {
    if (!state.isActive) return null;

    if (isInternal) {
      return state.internalMessage.isNotEmpty ? state.internalMessage : null;
    }

    if (state.sendToExternal && state.externalMessage.isNotEmpty) {
      return state.externalMessage;
    }

    return null;
  }

  // ─────────────────────── Дедуп и защита от петель ───────────────────────
  // Локальный автоответ (IMAP/EAS без серверного OOF) отправляется по факту
  // получения письма в sync_service. Ключевые риски — петли автоответов и
  // повторные ответы одному отправителю; решаются здесь.
  static const _repliedKey = 'auto_responder_replied';

  Set<String> _repliedSet() =>
      (_prefs.getStringList(_repliedKey) ?? const <String>[]).toSet();

  /// Уже отвечали этому отправителю в текущем окне отсутствия?
  bool hasRepliedTo(String sender) =>
      _repliedSet().contains(sender.trim().toLowerCase());

  /// Запомнить, что отправителю уже ответили (в пределах окна).
  Future<void> recordReplied(String sender) async {
    final s = sender.trim().toLowerCase();
    if (s.isEmpty) return;
    final list = (_prefs.getStringList(_repliedKey) ?? <String>[]);
    if (list.contains(s)) return;
    list.add(s);
    // Ограничиваем рост списка (длинное окно + рассылка).
    if (list.length > 2000) list.removeRange(0, list.length - 2000);
    await _prefs.setStringList(_repliedKey, list);
  }

  Future<void> _resetReplied() async => _prefs.remove(_repliedKey);

  /// Автоматический/служебный отправитель или тема, на которую НЕЛЬЗЯ отвечать
  /// (иначе — петля из автоответов). Заголовков RFC 3834 (Auto-Submitted/
  /// Precedence/List-Id) в модели нет, поэтому эвристика по адресу и теме.
  static bool isAutomatedSender(String email, String subject) {
    final local = email.toLowerCase().split('@').first;
    const badLocal = [
      'noreply', 'no-reply', 'no_reply', 'donotreply', 'do-not-reply',
      'mailer-daemon', 'postmaster', 'bounce', 'bounces', 'notification',
      'notifications', 'automated', 'auto', 'newsletter', 'mailer', 'daemon',
    ];
    if (badLocal.any((b) => local == b || local.contains(b))) return true;
    final s = subject.toLowerCase();
    const badSubject = [
      'out of office', 'automatic reply', 'auto-reply', 'autoreply',
      'delivery status', 'undeliverable', 'mail delivery', 'read receipt',
      'автоответ', 'автоматический ответ', 'отсутствие', 'не доставлено',
      'отчёт о доставке', 'отчет о доставке', 'уведомление о прочтении',
    ];
    return badSubject.any((x) => s.contains(x));
  }
}

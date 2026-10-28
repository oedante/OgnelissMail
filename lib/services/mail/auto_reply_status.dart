// lib/services/mail/auto_reply_status.dart
// Включён ли автоответ («Нет на месте») у ящиков — для строки вверху ленты
// «Автоответ включён · до 20 окт · Выключить»: вернувшись из отпуска, о нём
// легко забыть, а коллеги продолжат получать «я в отпуске».
//
// Exchange: состояние с сервера (раз за запуск приложения и после
// сохранения на экране автоответа) — так видно и автоответ, включённый в
// Outlook. Остальные ящики: автоответчик телефона (auto_responder_service).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'auto_responder_service.dart';
import 'engine/mail_engine_service.dart';

class OofStatus {
  final bool on;
  final DateTime? from;
  final DateTime? until;
  const OofStatus({required this.on, this.from, this.until});

  /// Работает сейчас: включён и (если по расписанию) уже начался и не кончился.
  bool activeAt(DateTime now) =>
      on && (from == null || !now.isBefore(from!)) && (until == null || now.isBefore(until!));

  /// Запланирован, но ещё не начался.
  bool plannedAt(DateTime now) => on && from != null && now.isBefore(from!);

  Map<String, Object?> toJson() => {
        'on': on,
        if (from != null) 'from': from!.millisecondsSinceEpoch,
        if (until != null) 'until': until!.millisecondsSinceEpoch,
      };

  static OofStatus fromJson(Map<String, dynamic> m) => OofStatus(
        on: (m['on'] as bool?) ?? false,
        from: m['from'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['from'] as num).toInt()),
        until: m['until'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['until'] as num).toInt()),
      );
}

final autoReplyStatusProvider =
    StateNotifierProvider<AutoReplyStatusNotifier, Map<String, OofStatus>>((ref) => AutoReplyStatusNotifier(ref));

class AutoReplyStatusNotifier extends StateNotifier<Map<String, OofStatus>> {
  static const _key = 'oof_status_v1';
  final Ref _ref;
  static bool _refreshedThisRun = false;

  AutoReplyStatusNotifier(this._ref) : super(_load(_ref));

  static Map<String, OofStatus> _load(Ref ref) {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_key);
      if (raw == null) return const {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: OofStatus.fromJson(Map<String, dynamic>.from(e.value as Map))};
    } catch (_) {
      return const {};
    }
  }

  void set(String accountId, OofStatus? s) {
    final next = {...state};
    if (s == null || !s.on) {
      next.remove(accountId);
    } else {
      next[accountId] = s;
    }
    state = next;
    _ref.read(sharedPrefsProvider).setString(_key, jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}));
  }

  /// Exchange-ящики: спросить сервер (раз за запуск).
  Future<void> refreshOnce(List<AccountModel> accounts) async {
    // Не больше трёх попыток за запуск: если сервер автоответ не отдаёт
    // вовсе, не спрашивать при каждом возврате в приложение.
    if (_refreshedThisRun || _refreshing || _attempts >= 3) return;
    _attempts++;
    _refreshing = true;
    final engine = _ref.read(mailEngineServiceProvider);
    // «Раз за запуск» засчитывается, только если сервер ответил: запуск без
    // сети раньше оставлял устаревшую строку до следующего запуска.
    var answered = true;
    try {
    for (final a in accounts) {
      if (!a.isActive || !a.isMsExchange) continue;
      try {
        final o = await engine.getOof(a);
        if (o == null) {
          answered = false;
          continue;
        }
        set(a.id, OofStatus(on: o.enabled, from: o.scheduled ? o.start : null, until: o.scheduled ? o.end : null));
      } catch (e) {
        answered = false;
        AppLogger.debug('Автоответ ${AppLogger.mask(a.email)}: $e');
      }
    }
    } finally {
      _refreshing = false;
      if (answered) _refreshedThisRun = true;
    }
  }

  bool _refreshing = false;
  int _attempts = 0;

  /// Выключить автоответ ящика (кнопка в строке ленты). false — не удалось.
  Future<bool> turnOff(AccountModel a) async {
    var ok = true;
    if (a.isMsExchange) {
      ok = await _ref.read(mailEngineServiceProvider).setOof(a, enabled: false);
    } else {
      await _ref.read(autoResponderProvider.notifier).setEnabled(false);
    }
    if (ok) set(a.id, null);
    return ok;
  }
}

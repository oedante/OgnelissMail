// lib/services/mail/conversation_counter.dart
// Число писем в беседах для значка в строке списка. Заполняет список писем
// (EmailsNotifier) одним запросом на видимые беседы — по всем папкам
// аккаунта, так что в счёт входят и собственные ответы из «Отправленных».
//
// Раньше счётчик загружался методом, который никто не вызывал, и значок
// не появлялся вовсе.

import 'package:flutter_riverpod/legacy.dart';

/// Ключ — «аккаунт|беседа» (см. [conversationKey]); только беседы из 2+ писем.
final conversationCountProvider =
    StateNotifierProvider<ConversationCountNotifier, Map<String, int>>(
        (ref) => ConversationCountNotifier());

/// Сводка беседы для свёрнутой строки: непрочитанные письма и отметка
/// «На контроле» любого письма беседы (иначе беседа с непрочитанным письмом
/// внутри выглядела прочитанной, а «Исполнено» на моём письме — не видно,
/// когда сверху строки уже ответ).
typedef ConversationStat = ({int count, int unread, int control, String? replied, String? to});

final conversationStatsProvider =
    StateNotifierProvider<ConversationStatsNotifier, Map<String, ConversationStat>>(
        (ref) => ConversationStatsNotifier());

class ConversationStatsNotifier extends StateNotifier<Map<String, ConversationStat>> {
  ConversationStatsNotifier() : super(const {});

  void merge(Map<String, ConversationStat> stats, Set<String> queried) {
    final next = {...state};
    for (final k in queried) {
      next.remove(k);
    }
    next.addAll(stats);
    state = next;
  }
}

String conversationKey(String accountId, String conversationId) =>
    '$accountId|$conversationId';

class ConversationCountNotifier extends StateNotifier<Map<String, int>> {
  ConversationCountNotifier() : super(const {});

  /// Добавить свежие значения. Старые не стираем: при смене папки значки
  /// уже виденных бесед не мигают.
  void merge(Map<String, int> sizes, Set<String> queried) {
    final next = {...state};
    for (final k in queried) {
      next.remove(k);
    }
    next.addAll(sizes);
    state = next;
  }

  int getCount(String accountId, String? conversationId) {
    if (conversationId == null) return 1;
    return state[conversationKey(accountId, conversationId)] ?? 1;
  }
}

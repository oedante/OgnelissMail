// lib/features/mail/providers/conversation_mute.dart
// Беседы без уведомлений (1.8.13) — состояние для экранов: значок в строке
// ленты и пункт «Без уведомлений» / «Включить уведомления». Хранение и
// проверка при новых письмах — ConversationNotify.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/notifications/account_notify_mode.dart' show ConversationNotify;

/// Беседы без уведомлений («ящик|беседа»).
final mutedConversationsProvider =
    NotifierProvider<MutedConversationsNotifier, Set<String>>(MutedConversationsNotifier.new);

class MutedConversationsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ConversationNotify.off(ref.read(sharedPrefsProvider));

  bool isMuted(String accountId, String? conversationId) =>
      conversationId != null && conversationId.isNotEmpty &&
      state.contains(ConversationNotify.key(accountId, conversationId));

  /// Выключить уведомления беседы или включить снова. Возвращает новое
  /// состояние: true — без уведомлений.
  Future<bool> toggle(String accountId, String conversationId) async {
    final mute = !isMuted(accountId, conversationId);
    state = await ConversationNotify.set(ref.read(sharedPrefsProvider), accountId, conversationId, !mute);
    return mute;
  }
}

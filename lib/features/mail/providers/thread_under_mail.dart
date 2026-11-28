// lib/features/mail/providers/thread_under_mail.dart
// Беседа под письмом (2.7.5, просьба владельца 28.11.2026: «беседа под
// письмом работает только при открытии из уведомления, из программы — нет;
// сделаем с возможностью отключения»).
//
// Под письмом — цепочка беседы (шапки и начало текста, касание — письмо).
// При группировке бесед лента открывает беседу из нескольких писем экраном
// беседы, а письмо — уже с него; там цепочка не показывалась: беседа на
// предыдущем экране. Из уведомления, поиска, ссылки письмо открывается
// само по себе — и цепочка под ним была.
//
//   · «Всегда» — и при открытии с экрана беседы;
//   · «При открытии из уведомления» (по умолчанию, как было) — когда письмо
//     открыто не с экрана беседы: уведомление, поиск, ссылка, виджет, лента
//     без группировки;
//   · «Никогда».

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/shared_prefs_provider.dart';

enum ThreadUnderMail { always, standalone, never }

class ThreadUnderMailNotifier extends Notifier<ThreadUnderMail> {
  static const prefKey = 'thread_under_mail';

  @override
  ThreadUnderMail build() {
    final name = ref.read(sharedPrefsProvider).getString(prefKey);
    return ThreadUnderMail.values.where((v) => v.name == name).firstOrNull ?? ThreadUnderMail.standalone;
  }

  Future<void> set(ThreadUnderMail v) async {
    state = v;
    await ref.read(sharedPrefsProvider).setString(prefKey, v.name);
  }
}

final threadUnderMailProvider =
    NotifierProvider<ThreadUnderMailNotifier, ThreadUnderMail>(ThreadUnderMailNotifier.new);

/// Показывать ли цепочку беседы под письмом. [fromConversation] — письмо
/// открыто с экрана беседы (листание писем беседы).
bool showThreadUnderMail(ThreadUnderMail mode, {required bool fromConversation}) => switch (mode) {
      ThreadUnderMail.always => true,
      ThreadUnderMail.standalone => !fromConversation,
      ThreadUnderMail.never => false,
    };

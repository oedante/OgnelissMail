// lib/features/contacts/contact_prefs.dart
// Контакты (1.6.49+95):
//   · звёздочка — VIP одним нажатием: адрес в списке VIP «Фокус-режима»
//     (письма от VIP пробивают тишину, «Только VIP» в уведомлениях ящика);
//     повторное нажатие — убрать. Тот же список — «Настройки → VIP»;
//   · закреплённые контакты — вверху списка, как закреплённые чаты
//     (только на телефоне, не больше [PinnedContactsNotifier.max]).

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' show Contact;
import '../../data/providers/shared_prefs_provider.dart';
import '../../services/mail/focus_mode_service.dart';

/// Ключ контакта: ящик и id (у разных ящиков id совпадают).
String contactPinKey(Contact c) => '${c.accountId ?? ''}|${c.id}';

class PinnedContactsNotifier extends Notifier<List<String>> {
  static const _k = 'contacts_pinned_v1';
  static const max = 10;

  @override
  List<String> build() => ref.read(sharedPrefsProvider).getStringList(_k) ?? const [];

  bool isPinned(Contact c) => state.contains(contactPinKey(c));

  /// Закрепить (новое — первым) или открепить.
  Future<void> toggle(Contact c) async {
    final key = contactPinKey(c);
    final next = state.contains(key) ? [for (final k in state) if (k != key) k] : [key, ...state].take(max).toList();
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(_k, next);
  }
}

final pinnedContactsProvider = NotifierProvider<PinnedContactsNotifier, List<String>>(PinnedContactsNotifier.new);

/// Разделы над буквами (1.10.3): «Закреплённые», под ними «VIP» —
/// закреплённый VIP только в первом. Оба по алфавиту. Раньше это был один
/// раздел, и «Открепить» у VIP ничего видимо не меняло (замечание владельца
/// 03.11.2026). Один контакт (ящик и id) — один раз.
({List<T> pinned, List<T> vip}) splitTopContacts<T>(
  Iterable<T> all, {
  required String Function(T) key,
  required String Function(T) email,
  required String Function(T) name,
  required Set<String> pinKeys,
  required Set<String> vipEmails,
}) {
  final seen = <String>{};
  final pinned = [for (final c in all) if (pinKeys.contains(key(c)) && seen.add(key(c))) c];
  final vip = [
    for (final c in all)
      if (vipEmails.contains(email(c).trim().toLowerCase()) && seen.add(key(c))) c,
  ];
  int byName(T a, T b) => name(a).toLowerCase().compareTo(name(b).toLowerCase());
  return (pinned: pinned..sort(byName), vip: vip..sort(byName));
}

/// Адрес в списке VIP (без учёта регистра).
bool isVipEmail(FocusModeState s, String email) {
  final e = email.trim().toLowerCase();
  return e.isNotEmpty && s.vipEmails.any((v) => v.trim().toLowerCase() == e);
}

/// VIP — добавить или убрать адрес. true — теперь VIP.
bool toggleVipEmail(WidgetRef ref, String email) {
  final e = email.trim().toLowerCase();
  if (!e.contains('@')) return false;
  final n = ref.read(focusModeProvider.notifier);
  final same = [for (final v in ref.read(focusModeProvider).vipEmails) if (v.trim().toLowerCase() == e) v];
  HapticFeedback.selectionClick();
  if (same.isEmpty) {
    n.addVipEmail(e);
    return true;
  }
  for (final v in same) {
    n.removeVipEmail(v);
  }
  return false;
}

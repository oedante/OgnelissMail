// lib/features/mail/providers/pinned_mail.dart
// Закреплённые письма (1.6.49, как закреплённые чаты в Telegram): «Ещё… →
// Закрепить вверху» — письмо стоит над лентой своей папки (письмо из
// «Входящих» — и в общей ленте ящиков), пока его не открепят. Только на
// телефоне (в настройках), не на сервере; не больше [PinnedMailNotifier.max].

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import 'mail_providers.dart' show emailModelFromRow;

class PinRef {
  final String accountId;
  final String emailId;
  final String folderId;

  /// Письмо из «Входящих» — видно и в общей ленте (Хаб, все ящики, группа).
  final bool inbox;

  const PinRef({required this.accountId, required this.emailId, required this.folderId, this.inbox = false});

  String get key => '$accountId|$emailId';

  Map<String, Object> toJson() => {'a': accountId, 'e': emailId, 'f': folderId, 'i': inbox};

  static PinRef? fromJson(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final a = m['a'] as String?, e = m['e'] as String?, f = m['f'] as String?;
      if (a == null || e == null || f == null) return null;
      return PinRef(accountId: a, emailId: e, folderId: f, inbox: m['i'] == true);
    } catch (_) {
      return null;
    }
  }

  /// Видно ли письмо в ленте: папка [folderId] ящика [accountId] либо общая
  /// лента «Входящих» ящиков [accountIds] ([folderId] == null).
  bool shownIn({String? folderId, String? accountId, required Set<String> accountIds}) {
    if (folderId != null) return this.folderId == folderId && this.accountId == accountId;
    return inbox && accountIds.contains(this.accountId);
  }
}

class PinnedMailNotifier extends Notifier<List<PinRef>> {
  static const _k = 'mail_pinned_v1';

  /// Не больше десяти: закреплённые не должны вытеснять ленту.
  static const max = 10;

  @override
  List<PinRef> build() => [
        for (final s in ref.read(sharedPrefsProvider).getStringList(_k) ?? const <String>[])
          if (PinRef.fromJson(s) case final p?) p,
      ];

  bool isPinned(String accountId, String emailId) => state.any((p) => p.accountId == accountId && p.emailId == emailId);

  Future<void> _save(List<PinRef> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).setStringList(_k, [for (final p in list) jsonEncode(p.toJson())]);
  }

  /// Закрепить (новое — первым) или открепить.
  Future<void> toggle(EmailModel e, {required bool inbox}) async {
    if (isPinned(e.accountId, e.id)) {
      await unpin(e.accountId, e.id);
      return;
    }
    final next = [
      PinRef(accountId: e.accountId, emailId: e.id, folderId: e.folderId, inbox: inbox),
      ...state,
    ];
    await _save(next.take(max).toList());
  }

  Future<void> unpin(String accountId, String emailId) =>
      _save([for (final p in state) if (!(p.accountId == accountId && p.emailId == emailId)) p]);
}

final pinnedMailProvider = NotifierProvider<PinnedMailNotifier, List<PinRef>>(PinnedMailNotifier.new);

/// Закреплённые письма из базы — живым потоком (прочитано, флаг). Письма,
/// которых в базе уже нет (удалены, перенесены), просто не показываются.
final pinnedEmailsProvider = StreamProvider.autoDispose<List<(PinRef, EmailModel)>>((ref) {
  final pins = ref.watch(pinnedMailProvider);
  if (pins.isEmpty) return Stream.value(const []);
  final db = ref.watch(databaseProvider);
  final ids = {for (final p in pins) p.emailId};
  // Таблица писем во время синхронизации меняется десятки раз в секунду:
  // дальше пропускаются только изменения самих закреплённых писем.
  String sig(List<dynamic> rows) => [
        for (final r in rows)
          '${r.accountId}|${r.id}|${r.isRead}|${r.isFlagged}|${r.controlState}|${r.laterState}|${r.folderId}|${r.subject.hashCode}',
      ].join(';');
  String? last;
  return (db.select(db.emails)..where((e) => e.id.isIn(ids)))
      .watch()
      .where((rows) {
        final s = sig(rows);
        if (s == last) return false;
        last = s;
        return true;
      })
      .map((rows) {
        final byKey = {for (final r in rows) '${r.accountId}|${r.id}': r};
        return [
          for (final p in pins)
            if (byKey[p.key] case final r?) (p, emailModelFromRow(r)),
        ];
      });
});

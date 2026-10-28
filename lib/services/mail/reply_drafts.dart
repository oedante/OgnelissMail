// lib/services/mail/reply_drafts.dart
// Начатые ответы (1.7.0, как «Черновик:» в списке чатов Telegram): у
// письма, на которое начат и не отправлен ответ (или пересылка), в строке
// ленты вместо начала текста — «Черновик: …» цветом ошибки.
//
// Связь «исходное письмо → черновик» хранится на телефоне: черновик при
// закрытии редактора уходит в серверные «Черновики» под новым id и без
// заголовков ответа — по нему исходное письмо не найти. По этой же связи
// черновик, открытый из «Черновиков», снова знает, на что он отвечает
// (In-Reply-To, отметка «Отвечено» после отправки).
//
// Запись появляется при сохранении черновика ответа, снимается при отправке
// или удалении черновика (в редакторе или из папки «Черновики» — по теме),
// и сама — через 30 дней. Показывается отметка, только пока сам черновик
// есть в «Черновиках» ([draftSubjectsProvider]): удалили его в Outlook или
// отправили с компьютера — «Черновик: …» в ленте пропадает.

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/folder_model.dart' show FolderType;
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';

class ReplyDraft {
  final String accountId;

  /// Исходное письмо (на которое отвечают).
  final String emailId;
  final String? conversationId;

  /// Тема черновика («RE: …») — по ней черновик из «Черновиков» находит
  /// исходное письмо.
  final String subject;

  /// Начало текста черновика (без приветствия, если удалось).
  final String text;
  final bool forward;
  final DateTime at;

  const ReplyDraft({
    required this.accountId,
    required this.emailId,
    this.conversationId,
    required this.subject,
    required this.text,
    this.forward = false,
    required this.at,
  });

  String get key => '$accountId|$emailId';

  Map<String, Object?> toJson() => {
        'a': accountId,
        'e': emailId,
        'c': conversationId,
        's': subject,
        't': text,
        'f': forward,
        'at': at.millisecondsSinceEpoch,
      };

  static ReplyDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final a = raw['a'], e = raw['e'], at = raw['at'];
    if (a is! String || e is! String || at is! int) return null;
    return ReplyDraft(
      accountId: a,
      emailId: e,
      conversationId: raw['c'] as String?,
      subject: (raw['s'] as String?) ?? '',
      text: (raw['t'] as String?) ?? '',
      forward: raw['f'] == true,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReplyDraft &&
      other.accountId == accountId &&
      other.emailId == emailId &&
      other.conversationId == conversationId &&
      other.subject == subject &&
      other.text == text &&
      other.forward == forward &&
      other.at == at;

  @override
  int get hashCode => Object.hash(accountId, emailId, conversationId, subject, text, forward, at);

  /// Тема без «RE:», «FW:», «Отв:» — для сравнения.
  static String bareSubject(String s) {
    var t = s.trim();
    final prefix = RegExp(r'^(re|fw|fwd|aw|wg|tr|отв|пер|ответ)\s*(\[\d+\])?\s*:\s*', caseSensitive: false);
    while (prefix.hasMatch(t)) {
      t = t.replaceFirst(prefix, '');
    }
    return t.trim().toLowerCase();
  }

  /// Начало текста черновика для строки ленты: без тегов, без
  /// приветствия-первой строки («Добрый день, …,»), до 140 знаков.
  static String snippet(String html) {
    final text = html
        .replaceAll(RegExp(r'<(br|/p|/div)[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    final lines = [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) l.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ];
    // Первая строка — приветствие с запятой в конце: пропустить.
    if (lines.length > 1 && lines.first.length < 60 && lines.first.endsWith(',')) lines.removeAt(0);
    final s = lines.join(' ');
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }
}

class ReplyDraftsNotifier extends Notifier<Map<String, ReplyDraft>> {
  static const _k = 'reply_drafts_v1';
  static const _ttl = Duration(days: 30);

  @override
  Map<String, ReplyDraft> build() {
    final out = <String, ReplyDraft>{};
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_k);
      if (raw != null) {
        final now = DateTime.now();
        for (final v in (jsonDecode(raw) as List)) {
          final d = ReplyDraft.fromJson(v);
          if (d != null && now.difference(d.at) < _ttl) out[d.key] = d;
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _save(Map<String, ReplyDraft> m) async {
    state = m;
    await ref.read(sharedPrefsProvider).setString(_k, jsonEncode([for (final d in m.values) d.toJson()]));
  }

  /// Черновик ответа сохранён (пустой текст — запись снимается).
  Future<void> put(ReplyDraft d) async {
    if (d.text.trim().isEmpty) {
      await removeFor(d.accountId, d.emailId);
      return;
    }
    if (state[d.key] == d) return;
    await _save({...state, d.key: d});
  }

  /// Ответ отправлен или черновик удалён.
  Future<void> removeFor(String accountId, String emailId) async {
    if (!state.containsKey('$accountId|$emailId')) return;
    await _save({...state}..remove('$accountId|$emailId'));
  }

  /// Черновик с этой темой отправлен или удалён (открыт из «Черновиков»,
  /// где связи с исходным письмом нет).
  Future<void> removeBySubject(String accountId, String subject) async {
    final bare = ReplyDraft.bareSubject(subject);
    if (bare.isEmpty) return;
    final next = {
      for (final e in state.entries)
        if (!(e.value.accountId == accountId && ReplyDraft.bareSubject(e.value.subject) == bare)) e.key: e.value,
    };
    if (next.length != state.length) await _save(next);
  }

  /// Исходное письмо черновика по его теме (самая свежая запись).
  ReplyDraft? byDraftSubject(String accountId, String subject) {
    final bare = ReplyDraft.bareSubject(subject);
    if (bare.isEmpty) return null;
    ReplyDraft? best;
    for (final d in state.values) {
      if (d.accountId != accountId || ReplyDraft.bareSubject(d.subject) != bare) continue;
      if (best == null || d.at.isAfter(best.at)) best = d;
    }
    return best;
  }
}

final replyDraftsProvider = NotifierProvider<ReplyDraftsNotifier, Map<String, ReplyDraft>>(ReplyDraftsNotifier.new);

/// Начатый ответ на письмо (или на письмо его беседы) — для строки ленты.
ReplyDraft? replyDraftFor(Map<String, ReplyDraft> m, String accountId, String emailId, String? conversationId) {
  final direct = m['$accountId|$emailId'];
  if (direct != null) return direct;
  if (conversationId == null || conversationId.isEmpty) return null;
  for (final d in m.values) {
    if (d.accountId == accountId && d.conversationId == conversationId) return d;
  }
  return null;
}

/// Темы черновиков (без «RE:», в нижнем регистре): свои на телефоне и в
/// серверных папках «Черновики». Черновиков единицы, запрос идёт по индексу
/// папки.
final draftSubjectsProvider = StreamProvider<Set<String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT subject AS s FROM emails WHERE folder_id = 'drafts' "
        'OR folder_id IN (SELECT id FROM folders WHERE type = ?)',
        variables: [Variable.withInt(FolderType.drafts.index)],
        readsFrom: {db.emails, db.folders},
      )
      .watch()
      .map((rows) => {for (final r in rows) ReplyDraft.bareSubject(r.read<String>('s'))});
});

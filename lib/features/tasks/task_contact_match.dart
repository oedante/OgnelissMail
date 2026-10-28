// lib/features/tasks/task_contact_match.dart
// Человек, упомянутый в задаче: «позвонить Смирнову Андрею» → контакт
// «Смирнов Андрей Сергеевич» с телефоном. Фамилия и имя сравниваются с учётом
// русских падежей (Смирнову → Смирнов, Андрею → Андрей, Ивановой → Иванова).
// Совпадение показывается в карточке задачи кнопками «Позвонить»/«Написать».

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';
import '../../data/models/contact_model.dart';

/// Слова с заглавной буквы (кандидаты в фамилию и имя).
List<String> mentionTokens(String title) => [
      for (final m in RegExp(r'[A-ZА-ЯЁ][a-zа-яё]+(?:-[A-ZА-ЯЁ][a-zа-яё]+)?').allMatches(title))
        if (m.group(0)!.length >= 3) m.group(0)!,
    ];

/// Слово [token] — форма имени [name] (падеж): общее начало не короче
/// имени без последней буквы. «Смирнову»~«Смирнов», «Андрею»~«Андрей»,
/// «Ивановой»~«Иванова», «Ольге»~«Ольга». Короткие имена (< 3) — только целиком.
bool nameFormMatches(String token, String name) {
  final t = token.toLowerCase().replaceAll('ё', 'е');
  final n = name.toLowerCase().replaceAll('ё', 'е').trim();
  if (n.length < 3) return t == n;
  var common = 0;
  while (common < t.length && common < n.length && t[common] == n[common]) {
    common++;
  }
  if (common == n.length) return t.length - n.length <= 3; // Смирнов → Смирнову, Смирновым
  return common >= n.length - 1 && common >= 3 && t.length - common <= 3;
}

/// Лучший контакт для названия задачи; null — никого не упомянули или
/// неоднозначно (два человека с одной фамилией без имени).
Future<ContactModel?> findMentionedContact(AppDatabase db, String title) async {
  final tokens = mentionTokens(title);
  if (tokens.isEmpty) return null;
  final stems = {
    for (final t in tokens) t.substring(0, t.length > 4 ? t.length - 2 : t.length - 1),
  };
  final rows = await (db.select(db.contacts)
        ..where((c) {
          Expression<bool>? any;
          for (final s in stems) {
            final e = c.lastName.like('$s%') | c.displayName.like('$s%');
            any = any == null ? e : (any | e);
          }
          return any ?? const Constant(false);
        })
        ..limit(60))
      .get();
  ContactModel? best;
  var bestScore = 0;
  var tie = false;
  for (final c in rows.map(contactFromRow)) {
    if (c.isGroup) continue;
    var last = (c.lastName ?? '').trim();
    var first = (c.firstName ?? '').trim();
    if (last.isEmpty) {
      // «Фамилия Имя Отчество» одной строкой (адресная книга организации).
      final parts = c.displayName.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      last = parts[0];
      first = parts[1];
    }
    if (!tokens.any((t) => nameFormMatches(t, last))) continue;
    var score = 2;
    if (first.isNotEmpty && tokens.any((t) => nameFormMatches(t, first))) score += 2;
    if ((c.phoneMobile ?? '').isNotEmpty || (c.phoneWork ?? '').isNotEmpty) score += 1;
    if (score > bestScore) {
      bestScore = score;
      best = c;
      tie = false;
    } else if (score == bestScore && best != null && best.email.toLowerCase() != c.email.toLowerCase()) {
      tie = true;
    }
  }
  return tie && bestScore < 4 ? null : best;
}

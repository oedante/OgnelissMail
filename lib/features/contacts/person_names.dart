// lib/features/contacts/person_names.dart
// Полные имена людей по адресу почты — из всех мест, где они встречаются:
// другие записи контактов (адресная книга организации, CardDAV) и заголовки
// писем («От», «Кому», «Копия»).
//
// Зачем: карточка Exchange, созданная Outlook автоматически, хранит только
// «Смирнов Андрей», а в письмах тот же человек подписан полностью — «Смирнов
// Андрей Викторович». В ленте писем видно ФИО, а во вкладке «Контакты» — ФИ,
// и полная пересинхронизация этого не исправит: на сервере в карточке
// отчества тоже нет (замечание 09.10.2026).

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/person_names.dart';
import '../../data/providers/database_provider.dart';
import '../../services/contacts/person_name_directory.dart';
import '../mail/providers/mail_providers.dart' show accountsProvider;

/// «Фамилия, Имя Отчество» → «Фамилия Имя Отчество»; кавычки и лишние
/// пробелы убираются.
String normalizePersonName(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'''^["'«]+|["'»]+$'''), '').trim();
  final comma = s.indexOf(',');
  if (comma > 0) s = '${s.substring(0, comma).trim()} ${s.substring(comma + 1).trim()}';
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _words(String s) =>
    s.toLowerCase().replaceAll('ё', 'е').split(' ').where((w) => w.isNotEmpty).toList();

/// [candidate] полнее [base]: слов больше и все слова [base] в нём есть
/// («Смирнов Андрей» → «Смирнов Андрей Викторович», но не «Отдел продаж»).
bool isFullerName(String candidate, String base) {
  final c = _words(candidate);
  final b = _words(base);
  if (c.length <= b.length || b.isEmpty) return false;
  return b.every(c.contains);
}

/// Адрес (нижний регистр) → самое полное имя. Имя-адрес («ivan@x.ru») и
/// однословные имена не берутся.
/// Полное ФИО по адресу (1.6.4): контакты, письма, адресная книга организации
/// ([PersonNameDirectory], результат кэшируется). [accountId] — ящик, в письмах
/// и адресной книге которого искать.
final fullPersonNameProvider =
    FutureProvider.family<String?, ({String email, String? accountId})>((ref, k) {
  final acc = ref.read(accountsProvider).where((a) => a.id == k.accountId).firstOrNull;
  return ref.read(personNameDirectoryProvider).fullName(k.email, account: acc);
});

/// Самое полное из [given] и [candidates] (тот же человек — [PersonNames.better]);
/// адрес вместо имени не берётся. null — имён нет.
String? bestPersonName(String? given, Iterable<String?> candidates) {
  final g = given?.trim();
  String? best = (g != null && g.isNotEmpty && !g.contains('@')) ? g : null;
  for (final c in candidates) {
    final v = c?.trim();
    if (v == null || v.isEmpty || v.contains('@')) continue;
    if (best == null || PersonNames.better(best, v)) best = v;
  }
  return best;
}

/// Контакты изменились (создан, изменён, удалён, синхронизация) — не чаще
/// раза в 2 секунды после серии изменений.
final _contactsTickProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  var n = 0;
  Timer? t;
  final c = StreamController<int>();
  final sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.contacts])).listen((_) {
    t?.cancel();
    t = Timer(const Duration(seconds: 2), () => c.add(++n));
  });
  ref.onDispose(() {
    t?.cancel();
    sub.cancel();
    c.close();
  });
  return c.stream;
});

/// Адрес → самое полное имя. Перечитывается, когда меняются контакты
/// (1.8.0: исправленное в контакте ФИО раньше доходило до писем и встреч
/// только после перезапуска).
final personNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(_contactsTickProvider);
  final db = ref.watch(databaseProvider);
  final out = <String, String>{};
  void offer(String? email, String? name) {
    if (email == null || name == null) return;
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return;
    final n = normalizePersonName(name);
    if (n.isEmpty || n.contains('@') || !n.contains(' ')) return;
    // Битое имя («Ермишин Ол� 5г»: закодированное слово заголовка From
    // разорвано посреди буквы) не берём — иначе оно, «длиннее» на слово,
    // вытесняло правильное и попадало в адресата и приветствие (1.6.33).
    if (n.contains('\uFFFD')) return;
    final prev = out[e];
    if (prev == null || _words(n).length > _words(prev).length) out[e] = n;
  }

  try {
    for (final c in await db.select(db.contacts).get()) {
      final composed = [c.lastName, c.firstName, c.middleName]
          .where((p) => p != null && p.trim().isNotEmpty)
          .map((p) => p!.trim())
          .join(' ');
      offer(c.email, composed);
      offer(c.email, c.displayName);
    }
    final senders = await db
        .customSelect('SELECT from_email AS e, from_name AS n FROM emails '
            "WHERE from_name IS NOT NULL AND from_name != '' "
            'GROUP BY lower(from_email), from_name LIMIT 20000')
        .get();
    for (final r in senders) {
      offer(r.read<String?>('e'), r.read<String?>('n'));
    }
    // Адресаты — из последних писем: по всем письмам разбирать JSON долго.
    final recips = await db
        .customSelect('SELECT to_recipients AS t, cc_json AS c FROM emails ORDER BY received_at DESC LIMIT 4000')
        .get();
    for (final r in recips) {
      for (final js in [r.read<String?>('t'), r.read<String?>('c')]) {
        if (js == null || js.isEmpty) continue;
        try {
          for (final m in (jsonDecode(js) as List).whereType<Map>()) {
            offer(m['email']?.toString(), (m['displayName'] ?? m['name'])?.toString());
          }
        } catch (_) {}
      }
    }
  } catch (_) {
    // Имена — украшение: ошибка запроса не должна ломать список контактов.
  }
  return out;
});

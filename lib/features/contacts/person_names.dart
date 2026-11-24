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
import 'dart:isolate';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/perf_mark.dart';
import '../../core/utils/person_names.dart';
import '../../data/database/app_database.dart' show AppDatabase;
import '../../data/providers/database_provider.dart';
import '../../services/contacts/person_name_directory.dart';
import '../../services/mail/own_addresses.dart';
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
///
/// 2.7.1 (микрофризы 24.11.2026: «Новое сообщение» открылось, но ~1,5 с не
/// реагировало на нажатия): раньше читались ВСЕ поля всех контактов — с
/// фото из CardDAV (Google, iCloud), которые хранятся в базе текстом
/// data:image, это мегабайты; и до 4000 строк JSON адресатов разбирались
/// в главном потоке. Теперь из базы — только адрес и имена (адресаты
/// разбираются самим SQLite), а сборка словаря при большом объёме — в
/// отдельном изоляте. Пересчёт — при смене контактов и имён или адресов
/// своих ящиков, а не при каждом обновлении счётчика непрочитанных.
final personNamesProvider = FutureProvider<Map<String, String>>((ref) {
  ref.watch(_contactsTickProvider);
  final db = ref.watch(databaseProvider);
  // Свои адреса — именем своего ящика (2.3.2): в письмах с подделанным
  // отправителем или получателем «ваш» адрес подписан чужим текстом.
  ref.watch(accountsProvider.select((list) => [
        for (final a in list) '${a.id}|${a.displayName}|${OwnAddresses.of(a).join(',')}',
      ].join('\n')));
  final own = <(List<String>, String)>[];
  try {
    for (final a in ref.read(accountsProvider)) {
      own.add((OwnAddresses.of(a).toList(), a.displayName));
    }
  } catch (_) {}

  return PerfMark.run('имена из контактов и писем', () => _loadPersonNames(db, own));
});

Future<Map<String, String>> _loadPersonNames(AppDatabase db, List<(List<String>, String)> own) async {
  final pairs = <(String?, String?)>[];
  try {
    final contacts = await db
        .customSelect('SELECT email, display_name, first_name, middle_name, last_name FROM contacts')
        .get();
    for (final c in contacts) {
      final email = c.read<String?>('email');
      final composed = [c.read<String?>('last_name'), c.read<String?>('first_name'), c.read<String?>('middle_name')]
          .where((p) => p != null && p.trim().isNotEmpty)
          .map((p) => p!.trim())
          .join(' ');
      pairs.add((email, composed));
      pairs.add((email, c.read<String?>('display_name')));
    }
    // Письма из «Спама» и «Корзины» имён не дают (2.3.2): в них имя
    // отправителя и адресата часто подделано.
    const notJunk = 'NOT EXISTS (SELECT 1 FROM folders f WHERE f.account_id = emails.account_id '
        'AND f.id = emails.folder_id AND f.type IN ($_junkTypes))';
    final senders = await db
        .customSelect('SELECT from_email AS e, from_name AS n FROM emails '
            "WHERE from_name IS NOT NULL AND from_name != '' AND $notJunk "
            'GROUP BY lower(from_email), from_name LIMIT 20000')
        .get();
    for (final r in senders) {
      pairs.add((r.read<String?>('e'), r.read<String?>('n')));
    }
    // Адресаты — из последних писем: JSON разбирает SQLite (json_each),
    // в приложение приходят уже пары «адрес — имя» без повторов.
    String recipients(String column) => 'SELECT json_extract(j.value, \'\$.email\') AS e, '
        'COALESCE(json_extract(j.value, \'\$.displayName\'), json_extract(j.value, \'\$.name\')) AS n '
        'FROM (SELECT $column AS js FROM emails WHERE $notJunk ORDER BY received_at DESC LIMIT 4000) m, '
        "json_each(CASE WHEN json_valid(m.js) THEN m.js ELSE '[]' END) j "
        "WHERE j.type = 'object'";
    final recips = await db
        .customSelect('SELECT e, n FROM (${recipients('to_recipients')} UNION ALL ${recipients('cc_json')}) '
            "WHERE e IS NOT NULL AND n IS NOT NULL AND n != '' GROUP BY lower(e), n")
        .get();
    for (final r in recips) {
      pairs.add((r.data['e']?.toString(), r.data['n']?.toString()));
    }
  } catch (_) {
    // Имена — украшение: ошибка запроса не должна ломать список контактов.
  }
  // Немного — сразу; много (тысячи писем) — в отдельном изоляте, чтобы
  // разбор имён не держал экран.
  if (pairs.length < 3000) return buildPersonNames(pairs, own);
  try {
    return await Isolate.run(() => buildPersonNames(pairs, own));
  } catch (_) {
    return buildPersonNames(pairs, own);
  }
}

/// Словарь «адрес → самое полное имя» из пар «адрес — имя» (контакты,
/// отправители, адресаты — в этом порядке) и своих ящиков ([own]: адреса и
/// имя ящика). Имя-адрес, однословные, «не имя» (текст спама) и битые имена
/// не берутся; из двух — с большим числом слов.
@visibleForTesting
Map<String, String> buildPersonNames(List<(String?, String?)> pairs, List<(List<String>, String)> own) {
  final out = <String, String>{};
  for (final (email, name) in pairs) {
    if (email == null || name == null) continue;
    final e = email.trim().toLowerCase();
    if (e.isEmpty) continue;
    final n = normalizePersonName(name);
    if (n.isEmpty || n.contains('@') || !n.contains(' ')) continue;
    // Текст вместо имени (спам: «Вам перевод … получить тут https://…») —
    // не имя, каким бы «полным» ни был (2.3.2).
    if (!PersonNames.plausible(n)) continue;
    // Битое имя («Ермишин Ол� 5г»: закодированное слово заголовка From
    // разорвано посреди буквы) не берём — иначе оно, «длиннее» на слово,
    // вытесняло правильное и попадало в адресата и приветствие (1.6.33).
    if (n.contains('\uFFFD')) continue;
    final prev = out[e];
    if (prev == null || _words(n).length > _words(prev).length) out[e] = n;
  }
  for (final (addresses, displayName) in own) {
    final name = normalizePersonName(displayName);
    for (final e in addresses) {
      if (name.isNotEmpty && !name.contains('@')) {
        out[e] = name;
      } else {
        out.remove(e);
      }
    }
  }
  return out;
}

/// Типы папок «Спам» и «Корзина» для запросов (индексы [FolderType]).
const _junkTypes = '3, 4';

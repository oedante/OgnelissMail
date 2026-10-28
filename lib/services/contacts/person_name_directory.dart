// lib/services/contacts/person_name_directory.dart
// Полное ФИО человека по адресу (1.5.9): в редакторе получатель показывался
// так, как его записал Exchange в адресной книге или прежнем письме —
// «Смирнов, Андрей». Здесь ищется самое полное написание того же имени:
//  1. контакты на телефоне (фамилия, имя, отчество);
//  2. письма этого человека в ящике (имя отправителя — у корпоративной
//     почты обычно полное ФИО);
//  3. адресная книга организации (Exchange), если выше не нашлось ФИО.
// Результат запоминается на время работы приложения.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/person_names.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import '../mail/engine/mail_engine_service.dart';
import '../mail/own_addresses.dart';

final personNameDirectoryProvider = Provider<PersonNameDirectory>((ref) => PersonNameDirectory(ref));

class PersonNameDirectory {
  PersonNameDirectory(this._ref);
  final Ref _ref;

  /// Адрес (нижний регистр) → найденное ФИО.
  final Map<String, String?> _known = {};
  final Map<String, Future<String?>> _inflight = {};

  /// Самое полное написание имени для [email]; null — не найдено.
  /// [account] — ящик, в письмах и адресной книге которого искать.
  Future<String?> fullName(String email, {AccountModel? account}) {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !e.contains('@')) return Future<String?>.value();
    if (_known.containsKey(e)) return Future<String?>.value(_known[e]);
    return _inflight[e] ??= _lookup(e, email.trim(), account).whenComplete(() => _inflight.remove(e));
  }

  Future<String?> _lookup(String e, String original, AccountModel? account) async {
    String? best;
    void take(String? v) {
      if (v != null && PersonNames.better(best, v)) best = PersonNames.clean(v);
    }

    // Свой адрес (письмо себе, 1.5.10) — имя ящика.
    if (account != null && OwnAddresses.isMine(account, e)) take(account.displayName);

    try {
      final db = _ref.read(databaseProvider);
      final rows = await (db.select(db.contacts)
            ..where((c) => c.email.lower().equals(e))
            ..limit(5))
          .get();
      for (final r in rows) {
        take([r.lastName, r.firstName, r.middleName].where((s) => s != null && s.trim().isNotEmpty).join(' '));
        take(r.displayName);
      }
      if (account != null) {
        // По индексу idx_emails_sender (ящик + адрес отправителя).
        final q = db.selectOnly(db.emails)
          ..addColumns([db.emails.fromName])
          ..where(db.emails.accountId.equals(account.id) &
              db.emails.fromEmail.isIn({e, original}.toList()) &
              db.emails.fromName.isNotNull())
          ..orderBy([OrderingTerm(expression: db.emails.receivedAt, mode: OrderingMode.desc)])
          ..limit(5);
        var found = await q.get();
        // Адрес в письмах записан другим регистром («I.Petrov@…» при
        // вставленном «i.petrov@…», 1.5.10): без индекса, но LIMIT без
        // сортировки останавливает просмотр на первых совпадениях.
        if (found.isEmpty) {
          final q2 = db.selectOnly(db.emails)
            ..addColumns([db.emails.fromName])
            ..where(db.emails.accountId.equals(account.id) &
                db.emails.fromEmail.lower().equals(e) &
                db.emails.fromName.isNotNull())
            ..limit(5);
          found = await q2.get();
        }
        for (final r in found) {
          take(r.read(db.emails.fromName));
        }
      }
    } catch (_) {}

    if (PersonNames.words(best) < 3 &&
        account != null &&
        (account.usesEas || account.hasEwsExtras || account.isExchange)) {
      try {
        final p = await _ref
            .read(mailEngineServiceProvider)
            .lookupPerson(account, e)
            .timeout(const Duration(seconds: 6));
        if (p != null) {
          take(p.fullName);
          take(p.displayName);
        }
      } catch (_) {}
    }
    // Последнее: этому человеку писали — имя из адресатов своих писем
    // («Иванов Иван Иванович <ivanov@…>» в «Кому»). Без индекса, первые
    // совпадения.
    if ((best ?? '').isEmpty && account != null) {
      try {
        final db = _ref.read(databaseProvider);
        final q = db.selectOnly(db.emails)
          ..addColumns([db.emails.toRecipients, db.emails.ccJson])
          ..where(db.emails.accountId.equals(account.id) &
              (db.emails.toRecipients.lower().like('%$e%') | db.emails.ccJson.lower().like('%$e%')))
          ..limit(3);
        for (final r in await q.get()) {
          for (final raw in [r.read(db.emails.toRecipients), r.read(db.emails.ccJson)]) {
            if (raw == null || raw.isEmpty) continue;
            try {
              for (final m in (jsonDecode(raw) as List).whereType<Map>()) {
                if ((m['email'] as String? ?? '').trim().toLowerCase() != e) continue;
                take((m['displayName'] ?? m['name']) as String?);
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    // «Не нашли» не запоминаем (1.5.10): адресная книга могла не ответить
    // (нет сети), а письма этого человека — ещё не загрузиться.
    if (best != null) _known[e] = best;
    return best;
  }
}

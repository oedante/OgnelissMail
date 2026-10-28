// lib/services/mail/own_addresses.dart
// Все адреса владельца ящика — не только тот, под которым вошли.
//
// Частый случай в организациях: вход под одним адресом или логином
// («i.petrov@acmegrp.example»), а ящик на сервере — другой основной адрес
// («i.petrov@acmegroup.example»). Раньше приложение знало только адрес входа, и:
//   · все письма коллег помечались «внешний отправитель, домен похож на
//     поддельный» (acmegroup.example «почти как» acmegrp.example);
//   · в своих приглашениях на встречу появлялись «Принять / Отклонить»;
//   · свои письма не узнавались: ни имя, ни своё фото.
//
// Откуда берутся адреса: адрес входа и общий ящик, «Адреса отправки»
// (алиасы), от сервера Exchange (ActiveSync Settings → UserInformation —
// все адреса и отображаемое имя) и по «Отправленным» (адрес отправителя
// своих писем). Хранится в SharedPreferences; читается синхронно —
// [load] вызывается при запуске приложения и фонового процесса.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/account_model.dart';

class OwnAddresses {
  OwnAddresses._();

  static const _key = 'own_addresses_v1';
  static const _aliasesKey = 'email_aliases';
  static Map<String, List<String>> _learned = {};
  static Map<String, List<String>> _aliases = {};
  static SharedPreferences? _prefs;

  /// Прочитать сохранённое (запуск приложения, фоновый процесс).
  static void load(SharedPreferences prefs) {
    _prefs = prefs;
    _learned = _read(prefs.getString(_key));
    _aliases = _read(prefs.getString(_aliasesKey));
  }

  static Map<String, List<String>> _read(String? raw) {
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: [for (final v in (e.value as List)) '$v'.toLowerCase()]};
    } catch (_) {
      return {};
    }
  }

  /// Алиасы поменялись в настройках — перечитать.
  static void refreshAliases() {
    final p = _prefs;
    if (p != null) _aliases = _read(p.getString(_aliasesKey));
  }

  /// Адреса, узнанные от сервера или по «Отправленным».
  static List<String> learned(String accountId) => _learned[accountId] ?? const [];

  /// Запомнить адреса ящика. true — что-то новое.
  static Future<bool> remember(String accountId, Iterable<String> emails) async {
    final cur = [...learned(accountId)];
    var changed = false;
    for (final e in emails) {
      final v = e.trim().toLowerCase();
      if (!v.contains('@') || cur.contains(v)) continue;
      cur.add(v);
      changed = true;
    }
    if (!changed) return false;
    _learned = {..._learned, accountId: cur};
    await _prefs?.setString(_key, jsonEncode(_learned));
    return true;
  }

  static Future<void> forget(String accountId) async {
    if (!_learned.containsKey(accountId)) return;
    _learned = {..._learned}..remove(accountId);
    await _prefs?.setString(_key, jsonEncode(_learned));
  }

  /// Адреса ящика, кроме адреса входа (с сервера, по «Отправленным», алиасы).
  static Set<String> extraFor(String accountId) => {...learned(accountId), ...?_aliases[accountId]};

  /// Все адреса ящика в нижнем регистре.
  static Set<String> of(AccountModel a) => {
        a.email.trim().toLowerCase(),
        if ((a.sharedMailboxEmail ?? '').isNotEmpty) a.sharedMailboxEmail!.trim().toLowerCase(),
        ...learned(a.id),
        ...?_aliases[a.id],
      }..removeWhere((e) => !e.contains('@'));

  static bool isMine(AccountModel a, String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isNotEmpty && of(a).contains(e);
  }

  /// Домены организации — по всем адресам ящика.
  static Set<String> domains(AccountModel a) => {
        for (final e in of(a)) e.substring(e.lastIndexOf('@') + 1),
      };

  /// Адрес, которым ящик «подписывается» в письмах: основной от сервера, если
  /// он известен, иначе адрес входа.
  static String primary(AccountModel a) {
    final l = learned(a.id);
    return l.isNotEmpty ? l.first : a.email.toLowerCase();
  }
}

// lib/services/contacts/colleague_directory.dart
// Данные коллег из адресной книги организации (1.8.0+118).
//
// Замечание владельца 27.10.2026 по 1.7.2 (114): «прошли сутки, а название
// компании прежнее у контактов». Личный контакт Exchange — копия: когда в
// организации меняют название компании, отдел или должность, копия в папке
// «Контакты» на сервере остаётся прежней (в Outlook так же: новое видно только
// в карточке из адресной книги). Поэтому у коллег — адрес в домене
// организации ящика — эти поля раз в сутки сверяются с адресной книгой
// (`SyncService._refreshColleagues`), хранятся в приложении (`Contacts.dirOrg`)
// и при синхронизации с сервером главнее копии из личных контактов. На сервер
// ничего не пишется. Чистые функции — проверяются тестом
// colleague_directory_test.dart.

import 'dart:convert';

import '../../core/utils/mail_domains.dart';
import '../../data/models/contact_model.dart';

/// Поля, которые у коллег берутся из адресной книги организации, — те же,
/// что в карточке контакта (`_ContactSheetState._load`).
const colleagueOrgFields = ['company', 'department', 'jobTitle', 'office', 'manager', 'phoneWork'];

/// Адрес коллеги: домен организации ящика или его поддомен, не общедоступная
/// почта.
bool isColleagueEmail(String email, String mailboxEmail) {
  final d = mailDomainOf(email);
  return d.isNotEmpty && !isPublicMailDomain(d) && sameOrgDomain(d, mailDomainOf(mailboxEmail));
}

/// Что пришло из адресной книги при последней сверке: адрес, для которого
/// сверяли, и непустые поля из [colleagueOrgFields].
class DirectoryOrg {
  final String email;
  final Map<String, String> values;

  const DirectoryOrg(this.email, this.values);

  factory DirectoryOrg.of(String email, ContactModel p) {
    final raw = <String, String?>{
      'company': p.company,
      'department': p.department,
      'jobTitle': p.jobTitle,
      'office': p.office,
      'manager': p.manager,
      'phoneWork': p.phoneWork,
    };
    final values = <String, String>{};
    raw.forEach((k, v) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty) values[k] = t;
    });
    return DirectoryOrg(email.trim().toLowerCase(), values);
  }

  /// Из столбца `Contacts.dirOrg`; испорченная строка — null (сверится заново).
  static DirectoryOrg? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      final email = m['email'];
      final v = m['v'];
      if (email is! String || v is! Map) return null;
      final values = <String, String>{};
      v.forEach((k, val) {
        if (k is String && val is String && colleagueOrgFields.contains(k) && val.trim().isNotEmpty) {
          values[k] = val.trim();
        }
      });
      return DirectoryOrg(email, values);
    } catch (_) {
      return null;
    }
  }

  String toJson() => jsonEncode({'email': email, 'v': values});

  /// Сверяли ли для этого адреса: у контакта на сервере мог смениться адрес.
  bool matches(String contactEmail) => email == contactEmail.trim().toLowerCase();

  /// Значение поля: из адресной книги, если там оно есть, иначе — с сервера.
  String? pick(String field, String? server) => values[field] ?? server;

  /// Поля, которые нужно поменять у контакта: в адресной книге значение есть
  /// и отличается от сохранённого. Пустое в адресной книге не стирает своё.
  Map<String, String> changesFor(Map<String, String?> current) {
    final out = <String, String>{};
    values.forEach((k, v) {
      if ((current[k] ?? '').trim() != v) out[k] = v;
    });
    return out;
  }
}

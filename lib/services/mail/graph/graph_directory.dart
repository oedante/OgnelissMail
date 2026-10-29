// lib/services/mail/graph/graph_directory.dart
// Адресная книга Exchange Online через Microsoft Graph (1.8.10): то, что у
// ящика Exchange Online шло по EWS (см. graph_client.dart). Права:
//   • своя карточка и фото — User.Read (/me);
//   • должность, отдел, кабинет и телефоны коллег — People.Read (/me/people);
//     с правом каталога (User.Read.All, если его выдал администратор) — ещё
//     и полная карточка с руководителем (/users);
//   • фото коллег — User.ReadBasic.All (/users/{адрес}/photos);
//   • подсказки MailTips — Mail.Read / Mail.ReadWrite (/me/getMailTips);
//   • переговорные — Place.Read.All (согласие администратора, /places);
//   • состав рассылок — GroupMember.Read.All (согласие администратора).
// Нет права — GraphException.forbidden: вызывающий берёт то же из EWS
// (пока EWS открыт) или обходится без этого.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/account_model.dart';
import '../../../data/models/contact_model.dart';
import '../ews/ews_directory_extras.dart' show DirectoryRoom;
import '../ews/ews_mail_tips.dart' show EwsMailTips, MailTip;
import 'graph_client.dart';

final graphDirectoryProvider = Provider<GraphDirectory>((ref) => GraphDirectory(ref.watch(graphClientProvider)));

class GraphDirectory {
  final GraphClient _g;
  GraphDirectory(this._g);

  bool supports(AccountModel a) => _g.supports(a);

  static const userSelect =
      'displayName,givenName,surname,mail,userPrincipalName,jobTitle,department,companyName,officeLocation,'
      'businessPhones,mobilePhone,city';

  /// Своя карточка (User.Read).
  Future<ContactModel?> me(AccountModel a) async {
    final m = await _g.get(a, '/me', query: {r'$select': userSelect});
    return m is Map<String, dynamic> ? contactFromUser(m, accountId: a.id) : null;
  }

  /// Карточка коллеги: люди организации (People.Read — должность, отдел,
  /// кабинет, телефоны), поверх — каталог (/users), если право на него есть
  /// (тогда и руководитель, [withManager]). null — такого адреса не нашлось.
  Future<ContactModel?> person(AccountModel a, String email, {bool withManager = true}) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return null;
    ContactModel? out;
    try {
      final list = await _g.list(a, '/me/people', query: {r'$search': '"$e"', r'$top': '10'}, maxPages: 1);
      out = pickPerson(list, e, accountId: a.id);
    } on GraphException catch (err) {
      if (!err.forbidden && !err.notFound && err.status != 400) rethrow;
    }
    try {
      final m = await _g.get(a, GraphClient.userPath(e), query: {r'$select': userSelect});
      if (m is Map<String, dynamic>) {
        final u = contactFromUser(m, accountId: a.id);
        if (u != null) out = out == null ? u : merge(out, u);
      }
      if (withManager && out != null) {
        final mgr = await _g.get(a, '${GraphClient.userPath(e)}/manager', query: {r'$select': 'displayName,mail'});
        final name = mgr is Map ? '${mgr['displayName'] ?? ''}'.trim() : '';
        if (name.isNotEmpty) out = merge(out, ContactModel(id: out.id, email: out.email, displayName: out.displayName, manager: name));
      }
    } on GraphException catch (err) {
      // Нет права на каталог (только User.ReadBasic.All) или руководителя нет.
      if (!err.forbidden && !err.notFound && err.status != 400) rethrow;
    }
    return out;
  }

  /// Фото в высоком качестве (User.ReadBasic.All; своё — User.Read). null —
  /// фото нет.
  Future<Uint8List?> photo(AccountModel a, String email) async {
    final e = email.trim().toLowerCase();
    final own = e == a.email.trim().toLowerCase();
    final root = own ? '/me' : GraphClient.userPath(e);
    final big = await _g.getBytes(a, '$root/photos/240x240/\$value');
    if (big != null) return big;
    return _g.getBytes(a, '$root/photo/\$value');
  }

  /// Подсказки Exchange (MailTips) для адресатов.
  Future<List<MailTip>> mailTips(AccountModel a, List<String> emails) async {
    final r = await _g.post(a, '/me/getMailTips', {
      'EmailAddresses': emails,
      'MailTipsOptions': 'automaticReplies, mailboxFullStatus, totalMemberCount, externalMemberCount',
    });
    return parseMailTips(r);
  }

  /// Списки переговорных (здания, этажи) — Place.Read.All.
  Future<List<DirectoryRoom>> roomLists(AccountModel a) async =>
      parsePlaces(await _g.list(a, '/places/microsoft.graph.roomlist', query: {r'$top': '100'}));

  /// Переговорные списка [listEmail].
  Future<List<DirectoryRoom>> rooms(AccountModel a, String listEmail) async => parsePlaces(await _g.list(
      a, '/places/${Uri.encodeComponent(listEmail.trim())}/microsoft.graph.roomlist/rooms',
      query: {r'$top': '100'}));

  /// Участники рассылки [email] (GroupMember.Read.All). null — такой группы
  /// в каталоге нет.
  Future<List<ContactModel>?> groupMembers(AccountModel a, String email) async {
    final e = email.trim().toLowerCase().replaceAll("'", "''");
    final groups = await _g.list(a, '/groups', query: {r'$filter': "mail eq '$e'", r'$select': 'id'}, maxPages: 1);
    final id = groups.firstOrNull?['id'];
    if (id is! String || id.isEmpty) return null;
    final members = await _g.list(a, '/groups/${Uri.encodeComponent(id)}/transitiveMembers',
        query: {r'$select': 'displayName,mail,jobTitle,department,officeLocation', r'$top': '999'});
    return [
      for (final m in members)
        if (contactFromUser(m, accountId: a.id) case final c?) c,
    ];
  }

  /// Главный список категорий Outlook (MailboxSettings.Read): имена и
  /// цвета (preset0…preset24 — те же номера, что у Outlook и EWS; -1 — без
  /// цвета).
  Future<List<({String name, int color})>> masterCategories(AccountModel a) async =>
      parseCategories(await _g.list(a, '/me/outlook/masterCategories', maxPages: 2));

  static List<({String name, int color})> parseCategories(List<Map<String, dynamic>> list) => [
        for (final c in list)
          if (_s(c['displayName']) case final name?)
            (name: name, color: int.tryParse('${c['color'] ?? ''}'.replaceFirst('preset', '')) ?? -1),
      ];

  // ── разбор ответов (отдельно — для тестов) ──

  static String? _s(Object? v) {
    final t = v is String ? v.trim() : '';
    return t.isEmpty ? null : t;
  }

  /// Пользователь каталога (/me, /users) → контакт. null — без адреса.
  static ContactModel? contactFromUser(Map<String, dynamic> m, {String? accountId}) {
    final email = (_s(m['mail']) ?? _s(m['userPrincipalName']) ?? '').toLowerCase();
    if (!email.contains('@')) return null;
    final phones = m['businessPhones'];
    final work = phones is List ? phones.whereType<String>().map((p) => p.trim()).where((p) => p.isNotEmpty).firstOrNull : null;
    return ContactModel(
      id: 'gal_${email.hashCode}',
      accountId: accountId,
      email: email,
      displayName: _s(m['displayName']) ?? email,
      firstName: _s(m['givenName']),
      lastName: _s(m['surname']),
      jobTitle: _s(m['jobTitle']),
      department: _s(m['department']),
      company: _s(m['companyName']),
      office: _s(m['officeLocation']),
      phoneWork: work,
      phoneMobile: _s(m['mobilePhone']),
      city: _s(m['city']),
      source: ContactSource.exchangeGal,
    );
  }

  /// Человек из /me/people с адресом [email]: сначала сотрудник организации.
  static ContactModel? pickPerson(List<Map<String, dynamic>> people, String email, {String? accountId}) {
    final e = email.trim().toLowerCase();
    Map<String, dynamic>? hit;
    for (final p in people) {
      final addrs = p['scoredEmailAddresses'];
      final has = addrs is List &&
          addrs.whereType<Map>().any((x) => '${x['address'] ?? ''}'.trim().toLowerCase() == e);
      if (!has) continue;
      final type = p['personType'];
      final org = type is Map && type['subclass'] == 'OrganizationUser';
      if (hit == null || org) hit = p;
      if (org) break;
    }
    if (hit == null) return null;
    String? phone(String type) {
      final list = hit!['phones'];
      if (list is! List) return null;
      for (final x in list.whereType<Map>()) {
        if (x['type'] == type) return _s(x['number']);
      }
      return null;
    }

    return ContactModel(
      id: 'gal_${e.hashCode}',
      accountId: accountId,
      email: e,
      displayName: _s(hit['displayName']) ?? e,
      firstName: _s(hit['givenName']),
      lastName: _s(hit['surname']),
      jobTitle: _s(hit['jobTitle']),
      department: _s(hit['department']),
      company: _s(hit['companyName']),
      office: _s(hit['officeLocation']),
      phoneWork: phone('business'),
      phoneMobile: phone('mobile'),
      source: ContactSource.exchangeGal,
    );
  }

  /// Дополнить карточку [a] полями [b] (пустые поля [a]).
  static ContactModel merge(ContactModel a, ContactModel b) {
    String? pick(String? x, String? y) => (x ?? '').trim().isNotEmpty ? x : y;
    return ContactModel(
      id: a.id,
      accountId: a.accountId ?? b.accountId,
      email: a.email,
      displayName: a.displayName.split(' ').length >= b.displayName.split(' ').length ? a.displayName : b.displayName,
      firstName: pick(a.firstName, b.firstName),
      lastName: pick(a.lastName, b.lastName),
      middleName: pick(a.middleName, b.middleName),
      jobTitle: pick(a.jobTitle, b.jobTitle),
      department: pick(a.department, b.department),
      company: pick(a.company, b.company),
      phoneWork: pick(a.phoneWork, b.phoneWork),
      phoneMobile: pick(a.phoneMobile, b.phoneMobile),
      office: pick(a.office, b.office),
      manager: pick(a.manager, b.manager),
      city: pick(a.city, b.city),
      avatarUrl: pick(a.avatarUrl, b.avatarUrl),
      source: ContactSource.exchangeGal,
    );
  }

  /// Ответ /me/getMailTips → подсказки.
  static List<MailTip> parseMailTips(Object? r) {
    final list = r is Map ? r['value'] : null;
    if (list is! List) return const [];
    final out = <MailTip>[];
    for (final t in list.whereType<Map>()) {
      final addr = t['emailAddress'];
      final email = (addr is Map ? '${addr['address'] ?? ''}' : '').trim().toLowerCase();
      if (!email.contains('@')) continue;
      final ar = t['automaticReplies'];
      final text = ar is Map ? EwsMailTips.plain('${ar['message'] ?? ''}') : '';
      int? n(Object? v) => v is num ? v.toInt() : null;
      out.add(MailTip(
        email: email,
        name: addr is Map ? '${addr['name'] ?? ''}'.trim() : '',
        autoReply: text.isEmpty ? null : text,
        mailboxFull: t['mailboxFull'] == true,
        totalMembers: n(t['totalMemberCount']),
        externalMembers: n(t['externalMemberCount']),
      ));
    }
    return out;
  }

  /// Места (/places) → переговорные или их списки.
  static List<DirectoryRoom> parsePlaces(List<Map<String, dynamic>> list) => [
        for (final p in list)
          if (_s(p['emailAddress']) case final email?)
            DirectoryRoom(name: _s(p['displayName']) ?? email, email: email),
      ];
}

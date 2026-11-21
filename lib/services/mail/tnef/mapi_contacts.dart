// lib/services/mail/tnef/mapi_contacts.dart
//
// Контакт и группа контактов Outlook из свойств MAPI (просьба владельца
// 21.11.2026: пересланные контакты и группы нельзя было сохранить себе).
//
// Группа (IPM.DistList): участники — в PidLidDistributionListOneOffMembers
// (0x8054, набор PSETID_Address): у каждого «одноразовый» EntryID
// ([MS-OXCDATA] 2.2.5.1) с именем, типом адреса и адресом. Если его нет —
// PidLidDistributionListMembers (0x8055): обёрнутые EntryID, из них годятся
// только одноразовые (у сотрудников из адресной книги Exchange там лишь
// X500-адрес, без почтового).
//
// Контакт (IPM.Contact): ФИО, организация, должность, телефоны и до трёх
// адресов (Email1…3, [MS-OXOCNTC] 2.2.1.2).

import 'dart:convert';
import 'dart:typed_data';

import '../dav/vcard_parser.dart';

/// Свойства MAPI письма — из TNEF (winmail.dat) или из файла Outlook .msg.
abstract interface class MapiPropSource {
  /// Класс письма: IPM.Note, IPM.Contact, IPM.DistList…
  String? get messageClass;

  /// Строковое свойство по номеру.
  String? string(int id);

  /// Строковое именованное свойство набора PSETID_Address.
  String? namedString(int lid);

  /// Многозначное двоичное именованное свойство набора PSETID_Address.
  List<Uint8List> namedBinaries(int lid);
}

/// Пересланная группа контактов: имя и участники.
class ContactGroupCard {
  final String name;
  final List<({String name, String email})> members;
  const ContactGroupCard({required this.name, required this.members});
}

class MapiContacts {
  MapiContacts._();

  static const _lidDlName = 0x8053;
  static const _lidDlOneOff = 0x8054;
  static const _lidDlMembers = 0x8055;

  static const _oneOffUid = [0x81, 0x2B, 0x1F, 0xA4, 0xBE, 0xA3, 0x10, 0x19, 0x9D, 0x6E, 0x00, 0xDD, 0x01, 0x0F, 0x54, 0x02];
  static const _wrappedUid = [0xC0, 0x91, 0xAD, 0xD3, 0x51, 0x9D, 0xCF, 0x11, 0xA4, 0xA9, 0x00, 0xAA, 0x00, 0x47, 0xFA, 0xA4];

  static bool isGroup(String? messageClass) =>
      (messageClass ?? '').toLowerCase().startsWith('ipm.distlist');
  static bool isContact(String? messageClass) =>
      (messageClass ?? '').toLowerCase().startsWith('ipm.contact');

  /// Группа контактов из свойств письма; не группа или пустая — null.
  static ContactGroupCard? group(MapiPropSource p) {
    if (!isGroup(p.messageClass)) return null;
    final name = [p.namedString(_lidDlName), p.string(0x3001), p.string(0x0037)]
            .firstWhere((s) => s != null && s.trim().isNotEmpty, orElse: () => null)
            ?.trim() ??
        '';
    final members = <({String name, String email})>[];
    final seen = <String>{};
    void add(({String name, String type, String email})? e) {
      if (e == null) return;
      final email = e.email.trim();
      if (!_isSmtp(email) || !seen.add(email.toLowerCase())) return;
      final n = e.name.trim();
      members.add((name: n == email ? '' : n, email: email));
    }

    for (final b in p.namedBinaries(_lidDlOneOff)) {
      add(oneOff(b));
    }
    if (members.isEmpty) {
      for (final b in p.namedBinaries(_lidDlMembers)) {
        add(_wrapped(b));
      }
    }
    if (members.isEmpty) return null;
    return ContactGroupCard(name: name, members: members);
  }

  /// Контакт из свойств письма; не контакт или без адреса и телефона — null.
  static VCardData? contact(MapiPropSource p) {
    if (!isContact(p.messageClass)) return null;
    String? s(int id) {
      final v = p.string(id)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final emails = <String>[];
    for (final (addr, original) in const [(0x8083, 0x8084), (0x8093, 0x8094), (0x80A3, 0x80A4)]) {
      final candidates = [p.namedString(addr), p.namedString(original)];
      for (final c in candidates) {
        final e = c?.trim() ?? '';
        if (_isSmtp(e) && !emails.any((x) => x.toLowerCase() == e.toLowerCase())) {
          emails.add(e);
          break;
        }
      }
    }
    final card = VCardData(
      fn: s(0x3001),
      given: s(0x3A06),
      family: s(0x3A11),
      middle: s(0x3A44),
      email: emails.isEmpty ? '' : emails.first,
      emails: emails,
      phoneWork: s(0x3A08),
      phoneMobile: s(0x3A1C) ?? s(0x3A09),
      org: s(0x3A16),
      title: s(0x3A17),
    );
    if (card.email.isEmpty && card.phoneWork == null && card.phoneMobile == null) return null;
    return card;
  }

  static bool _isSmtp(String e) =>
      e.contains('@') && !e.startsWith('/') && !e.contains(' ') && e.indexOf('@') > 0;

  static bool _starts(Uint8List b, int at, List<int> uid) {
    if (b.length < at + uid.length) return false;
    for (var i = 0; i < uid.length; i++) {
      if (b[at + i] != uid[i]) return false;
    }
    return true;
  }

  /// «Одноразовый» EntryID: имя, тип адреса и адрес; не он — null.
  static ({String name, String type, String email})? oneOff(Uint8List b) {
    if (!_starts(b, 4, _oneOffUid) || b.length < 24) return null;
    final flags = b[22] | (b[23] << 8);
    final unicode = flags & 0x8000 != 0;
    var p = 24;
    String read() {
      if (unicode) {
        final codes = <int>[];
        while (p + 1 < b.length) {
          final c = b[p] | (b[p + 1] << 8);
          p += 2;
          if (c == 0) break;
          codes.add(c);
        }
        return String.fromCharCodes(codes);
      }
      final start = p;
      while (p < b.length && b[p] != 0) {
        p++;
      }
      final raw = Uint8List.sublistView(b, start, p);
      if (p < b.length) p++;
      return utf8.decode(raw, allowMalformed: true);
    }

    final name = read();
    final type = read();
    final email = read();
    return (name: name, type: type, email: email);
  }

  /// Обёрнутый EntryID участника группы: внутри одноразового — адрес.
  static ({String name, String type, String email})? _wrapped(Uint8List b) {
    if (_starts(b, 4, _oneOffUid)) return oneOff(b);
    if (!_starts(b, 4, _wrappedUid) || b.length < 21) return null;
    if (b[20] & 0x0F != 0) return null;
    return oneOff(Uint8List.sublistView(b, 21));
  }

  // ── vCard: группа и контакты файлом .vcf ──
  //
  // Вложенное письмо Outlook (.msg внутри .msg) показывается как .eml:
  // группа и контакты едут в нём файлом .vcf (формат — как у «Переслать
  // группу», contact_groups_screen.dart), а EmlReader читает их обратно.

  static String _esc(String v) =>
      v.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');

  static String toVcf({ContactGroupCard? group, List<VCardData> contacts = const []}) {
    final b = StringBuffer();
    if (group != null) {
      b
        ..write('BEGIN:VCARD\r\nVERSION:4.0\r\nKIND:group\r\n')
        ..write('FN:${_esc(group.name)}\r\n');
      for (final m in group.members) {
        b.write('MEMBER:mailto:${m.email}\r\n');
      }
      b.write('END:VCARD\r\n');
      for (final m in group.members) {
        b
          ..write('BEGIN:VCARD\r\nVERSION:4.0\r\n')
          ..write('FN:${_esc(m.name.isEmpty ? m.email : m.name)}\r\n')
          ..write('EMAIL;TYPE=work:${m.email}\r\n')
          ..write('END:VCARD\r\n');
      }
    }
    for (final c in contacts) {
      b
        ..write('BEGIN:VCARD\r\nVERSION:4.0\r\n')
        ..write('FN:${_esc(c.displayName)}\r\n');
      if ((c.family ?? '').isNotEmpty || (c.given ?? '').isNotEmpty) {
        b.write('N:${_esc(c.family ?? '')};${_esc(c.given ?? '')};${_esc(c.middle ?? '')};;\r\n');
      }
      for (final e in c.emails.isEmpty && c.email.isNotEmpty ? [c.email] : c.emails) {
        b.write('EMAIL;TYPE=work:$e\r\n');
      }
      if ((c.phoneWork ?? '').isNotEmpty) b.write('TEL;TYPE=work:${c.phoneWork}\r\n');
      if ((c.phoneMobile ?? '').isNotEmpty) b.write('TEL;TYPE=cell:${c.phoneMobile}\r\n');
      if ((c.org ?? '').isNotEmpty) b.write('ORG:${_esc(c.org!)}\r\n');
      if ((c.title ?? '').isNotEmpty) b.write('TITLE:${_esc(c.title!)}\r\n');
      b.write('END:VCARD\r\n');
    }
    return b.toString();
  }

  /// Группа (карточка KIND:group) и контакты из .vcf. В файле с группой
  /// карточки участников — её часть, отдельными контактами не считаются.
  static ({ContactGroupCard? group, List<VCardData> contacts}) fromVcf(String text) {
    final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final cards = RegExp(r'BEGIN:VCARD(.*?)END:VCARD', dotAll: true, caseSensitive: false)
        .allMatches(unfolded)
        .map((m) => m.group(1)!)
        .toList();
    final groupCard = cards.where((c) => RegExp(r'^KIND:group', multiLine: true, caseSensitive: false).hasMatch(c)).firstOrNull;
    if (groupCard == null) {
      final contacts = VCardParser.parse(text)
          .where((c) => c.email.isNotEmpty || (c.phoneMobile ?? '').isNotEmpty || (c.phoneWork ?? '').isNotEmpty)
          .toList();
      return (group: null, contacts: contacts);
    }
    String? prop(String card, String name) {
      final m = RegExp('^$name(?:;[^:\\n]*)?:(.*)\$', multiLine: true, caseSensitive: false).firstMatch(card);
      return m?.group(1)?.trim().replaceAll('\\,', ',').replaceAll('\\;', ';').replaceAll('\\n', ' ');
    }

    final names = <String, String>{};
    for (final c in cards) {
      if (identical(c, groupCard)) continue;
      final e = prop(c, 'EMAIL')?.toLowerCase();
      final fn = prop(c, 'FN');
      if (e != null && fn != null && fn.toLowerCase() != e) names[e] = fn;
    }
    final members = <({String name, String email})>[];
    final seen = <String>{};
    for (final m in RegExp(r'^MEMBER(?:;[^:\n]*)?:(?:mailto:)?(.+)$', multiLine: true, caseSensitive: false)
        .allMatches(groupCard)) {
      final e = m.group(1)!.trim();
      if (_isSmtp(e) && seen.add(e.toLowerCase())) members.add((name: names[e.toLowerCase()] ?? '', email: e));
    }
    if (members.isEmpty) return (group: null, contacts: const <VCardData>[]);
    return (group: ContactGroupCard(name: prop(groupCard, 'FN') ?? '', members: members), contacts: const <VCardData>[]);
  }
}

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
import 'tnef_props.dart';

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
  static ContactGroupCard? group(TnefProps p) {
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
  static VCardData? contact(TnefProps p) {
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
}

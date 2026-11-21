// Пересланные группы контактов и контакты Outlook (winmail.dat внутри
// вложенного письма), вложенное письмо base64 без Content-Transfer-Encoding
// и отправка вложенного письма как message/rfc822 (21.11.2026).

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/eml_reader.dart';
import 'package:ogneliss/services/mail/mime_attach.dart';
import 'package:ogneliss/services/mail/tnef/mapi_contacts.dart';
import 'package:ogneliss/services/mail/tnef/tnef_props.dart';

// ── Сборка TNEF для тестов ──

class _Props {
  final _b = BytesBuilder();
  int count = 0;

  void _u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void _u32(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void _pad(int len) {
    for (var i = len; i % 4 != 0; i++) {
      _b.addByte(0);
    }
  }

  static Uint8List utf16z(String s) {
    final out = <int>[];
    for (final c in s.codeUnits) {
      out..add(c & 0xFF)..add(c >> 8);
    }
    return Uint8List.fromList([...out, 0, 0]);
  }

  void _value(Uint8List v) {
    _u32(v.length);
    _b.add(v);
    _pad(v.length);
  }

  void unicode(int id, String s) {
    count++;
    _u16(0x001F);
    _u16(id);
    _u32(1);
    _value(utf16z(s));
  }

  void _namedHead(int type, int lid) {
    count++;
    _u16(type);
    _u16(0x8000 + count);
    _b.add(const [0x04, 0x20, 0x06, 0, 0, 0, 0, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0x46]);
    _u32(0);
    _u32(lid);
  }

  void namedUnicode(int lid, String s) {
    _namedHead(0x001F, lid);
    _u32(1);
    _value(utf16z(s));
  }

  void namedBinaries(int lid, List<Uint8List> values) {
    _namedHead(0x1102, lid);
    _u32(values.length);
    for (final v in values) {
      _value(v);
    }
  }

  Uint8List build() {
    final body = _b.toBytes();
    return Uint8List.fromList([count & 0xFF, (count >> 8) & 0xFF, 0, 0, ...body]);
  }
}

Uint8List oneOff(String name, String email) => Uint8List.fromList([
      0, 0, 0, 0,
      0x81, 0x2B, 0x1F, 0xA4, 0xBE, 0xA3, 0x10, 0x19, 0x9D, 0x6E, 0x00, 0xDD, 0x01, 0x0F, 0x54, 0x02,
      0, 0, 0x01, 0x80,
      ..._Props.utf16z(name),
      ..._Props.utf16z('SMTP'),
      ..._Props.utf16z(email),
    ]);

Uint8List tnef(Uint8List props) {
  final b = BytesBuilder()
    ..add(const [0x78, 0x9F, 0x3E, 0x22, 0x01, 0x00]);
  void attr(int level, int id, Uint8List data) {
    b
      ..addByte(level)
      ..add([id & 0xFF, (id >> 8) & 0xFF, (id >> 16) & 0xFF, (id >> 24) & 0xFF])
      ..add([data.length & 0xFF, (data.length >> 8) & 0xFF, (data.length >> 16) & 0xFF, (data.length >> 24) & 0xFF])
      ..add(data)
      ..add(const [0, 0]);
  }

  attr(1, 0x00069007, Uint8List.fromList([0xE3, 0x04, 0, 0, 0, 0, 0, 0])); // 1251
  attr(1, 0x00069003, props);
  return b.toBytes();
}

Uint8List groupTnef() {
  final p = _Props()
    ..unicode(0x001A, 'IPM.DistList')
    ..unicode(0x0037, 'Каталогеры')
    ..namedUnicode(0x8053, 'Каталогеры')
    ..namedBinaries(0x8054, [
      oneOff('Иванов Иван Иванович', 'i.ivanov@example.com'),
      oneOff('Петров Пётр', 'p.petrov@example.com'),
      oneOff('Петров Пётр', 'P.Petrov@example.com'), // повтор
    ]);
  return tnef(p.build());
}

Uint8List contactTnef() {
  final p = _Props()
    ..unicode(0x001A, 'IPM.Contact')
    ..unicode(0x3001, 'Сидорова Анна')
    ..unicode(0x3A06, 'Анна')
    ..unicode(0x3A11, 'Сидорова')
    ..unicode(0x3A16, 'ООО «Пример»')
    ..unicode(0x3A17, 'Инженер')
    ..unicode(0x3A1C, '+7 900 000-00-00')
    ..namedUnicode(0x8083, 'a.sidorova@example.com');
  return tnef(p.build());
}

/// Вложенное письмо Outlook: всё содержимое — winmail.dat.
Uint8List innerMail(String subject, Uint8List winmail) {
  final b64 = base64.encode(winmail).replaceAllMapped(RegExp('.{1,76}'), (m) => '${m[0]}\r\n');
  return Uint8List.fromList(utf8.encode('Content-Type: application/ms-tnef; name="winmail.dat"\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      'From: Sender <sender@example.com>\r\n'
      'Subject: =?utf-8?B?${base64.encode(utf8.encode(subject))}?=\r\n'
      'Date: Mon, 20 Jan 2025 10:49:40 +0000\r\n'
      'MIME-Version: 1.0\r\n'
      '\r\n'
      '$b64'));
}

void main() {
  test('группа Outlook: имя и участники без повторов', () {
    final p = TnefProps.parse(groupTnef())!;
    expect(p.messageClass, 'IPM.DistList');
    final g = MapiContacts.group(p)!;
    expect(g.name, 'Каталогеры');
    expect(g.members.map((m) => m.email), ['i.ivanov@example.com', 'p.petrov@example.com']);
    expect(g.members.first.name, 'Иванов Иван Иванович');
    expect(MapiContacts.contact(p), isNull);
  });

  test('контакт Outlook: ФИО, адрес, телефон, организация', () {
    final c = MapiContacts.contact(TnefProps.parse(contactTnef())!)!;
    expect(c.displayName, 'Сидорова Анна');
    expect(c.given, 'Анна');
    expect(c.family, 'Сидорова');
    expect(c.email, 'a.sidorova@example.com');
    expect(c.phoneMobile, '+7 900 000-00-00');
    expect(c.org, 'ООО «Пример»');
    expect(c.title, 'Инженер');
  });

  test('вложенное письмо с winmail.dat: группа вместо файла', () {
    final m = EmlReader.parse(innerMail('Каталогеры', groupTnef()));
    expect(m.subject, 'Каталогеры');
    expect(m.contactGroup?.members, hasLength(2));
    expect(m.attachments, isEmpty);
  });

  test('вложенное письмо, закодированное base64 без заголовка, читается', () {
    final raw = innerMail('Контакт', contactTnef());
    final wrapped = Uint8List.fromList(utf8.encode(
        base64.encode(raw).replaceAllMapped(RegExp('.{1,76}'), (m) => '${m[0]}\r\n')));
    expect(EmlReader.unwrap(wrapped), raw);
    final m = EmlReader.parse(wrapped);
    expect(m.subject, 'Контакт');
    expect(m.contacts.single.email, 'a.sidorova@example.com');
    // Обычный файл не трогаем.
    final text = Uint8List.fromList(utf8.encode('QUJD'));
    expect(EmlReader.unwrap(text), text);
  });

  test('вложенное письмо уходит как message/rfc822 без base64', () {
    final inner = innerMail('Каталогеры', groupTnef());
    final b = MessageBuilder.prepareMultipartMixedMessage()
      ..addMultipartAlternative(plainText: 'см. вложение', htmlText: '<p>см. вложение</p>')
      ..from = [const MailAddress('Я', 'me@example.com')]
      ..to = [const MailAddress('Ты', 'you@example.com')]
      ..subject = 'Группа';
    addFileAttachment(b, inner, MediaType.fromText('message/rfc822'), 'Каталогеры.eml');
    final rendered = b.buildMimeMessage().renderMessage();
    expect(rendered, contains('message/rfc822'));
    expect(rendered, contains('Content-Type: application/ms-tnef'));

    // Письмо внутри — как есть (IMAP отдаёт его по BODY[n] целиком).
    final raw = sevenBitMessage(inner)!.trimRight();
    expect(rendered, contains(raw));
    final head = rendered.substring(0, rendered.indexOf(raw));
    final partHead = head.substring(head.lastIndexOf('Content-Type: message/rfc822'));
    expect(partHead, isNot(contains('Content-Transfer-Encoding')));
    final m = EmlReader.parse(Uint8List.fromList(utf8.encode(raw)));
    expect(m.subject, 'Каталогеры');
    expect(m.contactGroup?.members, hasLength(2));
  });

  test('8-битное вложенное письмо уходит файлом .eml (base64)', () {
    final inner = Uint8List.fromList(utf8.encode('Subject: тест\r\nFrom: a@b.c\r\n\r\nтекст'));
    expect(sevenBitMessage(inner), isNull);
    final b = MessageBuilder.prepareMultipartMixedMessage()
      ..addMultipartAlternative(plainText: 'x', htmlText: '<p>x</p>')
      ..from = [const MailAddress('Я', 'me@example.com')]
      ..subject = 'x';
    addFileAttachment(b, inner, MediaType.fromText('message/rfc822'), 'тест.eml');
    final rendered = b.buildMimeMessage().renderMessage();
    expect(rendered, contains('application/octet-stream'));
    expect(rendered, contains('Content-Transfer-Encoding: base64'));
  });
}

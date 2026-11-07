// Письмо Outlook (.msg) как письмо (1.12.x, просьба владельца 05.11.2026):
// тема, отправитель с SMTP-адресом (и Exchange без него), получатели из
// хранилищ, дата, HTML в кодировке письма (KOI8-R), 8-битные строки в
// Windows-1251, сжатый RTF (LZFu по MS-OXRTFCP, пример из спецификации) и
// HTML внутри RTF, вложения, встроенная картинка по Content-ID, вложенное
// письмо — файлом .eml; испорченные и нарочно сделанные файлы — без падения.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/mail/eml_reader.dart';
import 'package:ogneliss/services/mail/msg_reader.dart';

import 'cfb_writer.dart';
import 'msg_builder.dart';

Matcher _error(OfficeDocError kind) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', kind));

/// «Сжатие» LZFu без ссылок: управляющий байт 0 и восемь знаков как есть,
/// в конце — ссылка на текущее место словаря (конец данных).
Uint8List _lzfu(List<int> raw) {
  final out = <int>[];
  var w = 207;
  var i = 0;
  while (true) {
    var control = 0;
    final body = <int>[];
    var bit = 0;
    for (; bit < 8 && i < raw.length; bit++, i++) {
      body.add(raw[i]);
      w = (w + 1) & 0xFFF;
    }
    if (bit < 8) {
      control |= 1 << bit;
      body.addAll([w >> 4, (w & 0xF) << 4]);
      out
        ..add(control)
        ..addAll(body);
      break;
    }
    out
      ..add(control)
      ..addAll(body);
  }
  final h = ByteData(16)
    ..setUint32(0, out.length + 12, Endian.little)
    ..setUint32(4, raw.length, Endian.little)
    ..setUint32(8, 0x75465A4C, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...out]);
}

/// KOI8-R для «Привет» (как пишет почта на русском).
const _koiPrivet = [0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4];

/// Windows-1251 для «Отчёт».
const _cp1251Report = [0xCE, 0xF2, 0xF7, 0xB8, 0xF2];

MsgBuilder _sample() {
  final m = MsgBuilder();
  m.props
    ..str(0x0037, 'Отчёт за ноябрь')
    ..str(0x0C1A, 'Отдел продаж')
    ..str(0x0C1E, 'EX')
    ..str(0x0C1F, '/O=ORG/OU=EXCHANGE/CN=RECIPIENTS/CN=SALES')
    ..str(0x5D01, 'sales@example.org')
    ..time(0x0039, DateTime.utc(2026, 11, 5, 9, 30))
    ..i32(0x3FDE, 20866)
    ..bin(0x1013, [
      ...ascii.encode('<html><body><p>'),
      ..._koiPrivet,
      ...ascii.encode('</p><img src="cid:logo@x"></body></html>'),
    ])
    ..str(0x1000, 'Привет');
  m.recipients
    ..add(
      MsgProps()
        ..i32(0x0C15, 1)
        ..str(0x3001, 'Бухгалтерия')
        ..str(0x3002, 'SMTP')
        ..str(0x3003, 'buh@example.org'),
    )
    ..add(
      MsgProps()
        ..i32(0x0C15, 2)
        ..str(0x3001, 'Склад')
        ..str(0x3002, 'EX')
        ..str(0x3003, '/O=ORG/CN=STORE')
        ..str(0x39FE, 'store@example.org'),
    )
    ..add(
      MsgProps()
        ..i32(0x0C15, 3)
        ..str(0x3001, 'Скрытая копия')
        ..str(0x39FE, 'bcc@example.org'),
    );
  // Вложение файлом, встроенная картинка, вложенное письмо.
  m.attachments.add((
    MsgProps()
      ..i32(0x3705, 1)
      ..str(0x3707, 'Смета.pdf')
      ..str(0x370E, 'application/pdf')
      ..bin(0x3701, ascii.encode('%PDF-1.4 test')),
    null,
  ));
  m.attachments.add((
    MsgProps()
      ..i32(0x3705, 1)
      ..str(0x3707, 'logo.png')
      ..str(0x3712, '<logo@x>')
      ..bin(0x3701, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]),
    null,
  ));
  final inner = MsgBuilder();
  inner.props
    ..str(0x0037, 'Пересланное письмо')
    ..str(0x0C1A, 'Коллега')
    ..str(0x5D01, 'colleague@example.org')
    ..str(0x1000, 'Текст вложенного письма');
  m.attachments.add((
    MsgProps()
      ..i32(0x3705, 5)
      ..str(0x3001, 'Пересланное письмо'),
    inner,
  ));
  return m;
}

void main() {
  test('письмо: тема, отправитель, получатели, дата, HTML в KOI8-R, вложения', () {
    final m = MsgReader.read(_sample().build());
    expect(m.subject, 'Отчёт за ноябрь');
    expect(m.from.single.label, 'Отдел продаж <sales@example.org>');
    expect(m.to.single.label, 'Бухгалтерия <buh@example.org>');
    expect(m.cc.single.label, 'Склад <store@example.org>');
    expect(m.date, DateTime.utc(2026, 11, 5, 9, 30));
    expect(m.html, contains('<p>Привет</p>'));
    expect(m.plain, 'Привет');
    expect(m.inlineImages.keys, ['logo@x']);
    expect(m.inlineImages['logo@x'], startsWith('data:image/png;base64,'));
    expect(m.attachments.map((a) => a.name), ['Смета.pdf', 'Пересланное письмо.eml']);
    expect(m.attachments.first.contentType, 'application/pdf');
    // Вложенное письмо — настоящий .eml: его читает тот же EmlReader.
    final eml = m.attachments[1];
    expect(eml.contentType, 'message/rfc822');
    final inner = EmlReader.parse(eml.bytes);
    expect(inner.subject, 'Пересланное письмо');
    expect(inner.from.single.email, 'colleague@example.org');
    expect(inner.plain?.trim(), 'Текст вложенного письма');
  });

  test('8-битные строки — в кодовой странице письма; Exchange без SMTP — из заголовков', () {
    final m = MsgBuilder();
    m.props
      ..i32(0x3FFD, 1251)
      ..str8(0x0037, _cp1251Report)
      ..str8(0x0C1A, _cp1251Report)
      ..str(0x0C1E, 'EX')
      ..str(0x0C1F, '/O=ORG/CN=X')
      ..str(
        0x007D,
        'From: =?utf-8?B?0J7RgtGH0ZHRgg==?= <report@example.org>\r\nTo: a@example.org\r\n'
        'Subject: x\r\nDate: Thu, 05 Nov 2026 10:00:00 +0300\r\n',
      )
      ..str(0x0E04, 'Иванов; Петров');
    final r = MsgReader.read(m.build());
    expect(r.subject, 'Отчёт');
    expect(r.from.single.email, 'report@example.org');
    expect(r.to.single.email, 'a@example.org', reason: 'без хранилищ получателей — из заголовков');
    expect(r.date!.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 7)), isTrue);
    expect(r.html, isNull);
    expect(r.hasBody, isFalse);
  });

  test('LZFu: пример из MS-OXRTFCP, «MELA» без сжатия, предел размера', () {
    final spec = Uint8List.fromList([
      0x2d, 0x00, 0x00, 0x00, 0x2b, 0x00, 0x00, 0x00, 0x4c, 0x5a, 0x46, 0x75, 0xf1, 0xc5, 0xc7, 0xa7, //
      0x03, 0x00, 0x0a, 0x00, 0x72, 0x63, 0x70, 0x67, 0x31, 0x32, 0x35, 0x42, 0x32, 0x0a, 0xf3, 0x20,
      0x68, 0x65, 0x6c, 0x09, 0x00, 0x20, 0x62, 0x77, 0x05, 0xb0, 0x6c, 0x64, 0x7d, 0x0a, 0x80, 0x0f, 0xa0,
    ]);
    expect(latin1.decode(MsgReader.decompressRtf(spec)), '{\\rtf1\\ansi\\ansicpg1252\\pard hello world}\r\n');
    final raw = ascii.encode('{\\rtf1 plain}');
    final mela = ByteData(16)
      ..setUint32(4, raw.length, Endian.little)
      ..setUint32(8, 0x414C454D, Endian.little);
    expect(MsgReader.decompressRtf(Uint8List.fromList([...mela.buffer.asUint8List(), ...raw])), raw);
    expect(MsgReader.decompressRtf(_lzfu(raw)), raw);
    // Объявлено 4 ГБ, данных — немного: не больше предела и без лишней памяти.
    final bomb = _lzfu(List.filled(5000, 0x41));
    ByteData.sublistView(bomb).setUint32(4, 0xFFFFFFFF, Endian.little);
    expect(MsgReader.decompressRtf(bomb, max: 1000).length, 1000);
    expect(() => MsgReader.decompressRtf(Uint8List(8)), throwsFormatException);
    expect(() => MsgReader.decompressRtf(Uint8List(20)..[8] = 1), throwsFormatException);
  });

  test('HTML внутри RTF (\\fromhtml1) и обычный RTF — в HTML', () {
    final rtf = latin1.encode(
      '{\\rtf1\\ansi\\ansicpg1251\\fromhtml1\\deff0{\\fonttbl{\\f0\\fswiss Arial;}}'
      '{\\*\\htmltag19 <html>}{\\*\\htmltag34 <body>}{\\*\\htmltag64 <p class="x">}'
      '\\htmlrtf {\\htmlrtf0 \\\'cf\\\'f0\\\'e8\\\'e2\\\'e5\\\'f2 \\u8212?\\htmlrtf\\par}\\htmlrtf0'
      '{\\*\\htmltag72 </p>}{\\*\\htmltag42 </body>}{\\*\\htmltag27 </html>}}',
    );
    expect(MsgReader.htmlFromRtf(rtf), '<html><body><p class="x">Привет —</p></body></html>');
    expect(MsgReader.htmlFromRtf(latin1.encode('{\\rtf1\\ansi plain}')), isNull);

    final m = MsgBuilder();
    m.props
      ..str(0x0037, 'RTF')
      ..bin(0x1009, _lzfu(rtf));
    expect(MsgReader.read(m.build()).html, contains('<p class="x">Привет —</p>'));

    final plainRtf = MsgBuilder();
    plainRtf.props.bin(
      0x1009,
      _lzfu(latin1.encode('{\\rtf1\\ansi\\ansicpg1251 {\\b \\\'c6\\\'e8\\\'f0\\\'ed\\\'fb\\\'e9} text\\par}')),
    );
    final h = MsgReader.read(plainRtf.build()).html!;
    expect(h, contains('Жирный'));
    expect(h, contains('font-weight:bold'));
  });

  test('не письмо, испорчено, вложенность без конца — без падения', () {
    expect(
      () => MsgReader.read(Uint8List.fromList(utf8.encode('From: x\r\n\r\nтекст'))),
      _error(OfficeDocError.damaged),
    );
    expect(() => MsgReader.read((CfbWriter()..add('WordDocument', [1, 2, 3])).build()), _error(OfficeDocError.damaged));

    // Поток свойств — мусор, длины значений врут, RTF испорчен.
    final w = CfbWriter()
      ..add('__properties_version1.0', List.filled(1000, 0xFF))
      ..add('__substg1.0_0037001F', [0x41, 0x00, 0x42])
      ..add('__substg1.0_10090102', List.filled(64, 0x33));
    final junk = MsgReader.read(w.build());
    expect(junk.subject, 'A');
    expect(junk.html, isNull);

    // Письмо во вложении письма… на 12 уровней: глубже предела — без них.
    var inner = MsgBuilder()..props.str(0x0037, 'дно');
    for (var i = 0; i < 12; i++) {
      final outer = MsgBuilder()..props.str(0x0037, 'уровень $i');
      outer.attachments.add((MsgProps()..i32(0x3705, 5), inner));
      inner = outer;
    }
    var m = MsgReader.read(inner.build());
    var depth = 0;
    while (m.attachments.isNotEmpty) {
      m = EmlReader.parse(m.attachments.single.bytes);
      depth++;
    }
    expect(depth, MsgReader.maxDepth);
  });

  // Настоящие письма Outlook из тестовых данных Apache POI (Apache-2.0,
  // test/fixtures/msg/README.md), а не собранные msg_builder.dart.
  group('настоящие письма Outlook (Apache POI)', () {
    EmlMessage read(String name) => MsgReader.read(File('test/fixtures/msg/$name').readAsBytesSync(), lang: 'ru');

    test('8-битные строки в Windows-1251 (кодовая страница письма), получатель с адресом', () {
      final m = read('poi_cyrillic_message.msg');
      expect(m.subject, 'Автоматический ответ подсистемы обмена данными ФГУП "Почта России".');
      expect(m.from.single.email, 'no-reply@niips.ru');
      expect(m.to.single.name, 'Свиридов Дмитрий Владимирович');
      expect(m.to.single.email, 'sviridov@niips.ru');
      expect(m.plain, startsWith('Ваше сообщение с темой "FW: RTM" было успешно получено'));
      expect(m.date, DateTime.utc(2010, 5, 18, 7, 38, 39));
    });

    test('французская тема, два вложения, имя без кавычек Outlook', () {
      final m = read('poi_attachment_test_msg.msg');
      expect(m.subject, 'test pièce jointe 1');
      expect(m.from.single.label, 'Nicolas1 23456 <nicolas1.23456@free.fr>');
      expect(m.to.single.name, 'nicolas1.23456@free.fr', reason: 'кавычки вокруг имени убраны');
      expect(m.plain?.trim(), 'contenu');
      final names = {for (final a in m.attachments) a.name: a};
      expect(names.keys, containsAll(['pj1.txt', 'test-unicode.doc']));
      expect(names['pj1.txt']!.contentType, 'text/plain');
      expect(names['test-unicode.doc']!.bytes.length, 24064);
    });

    test('Unicode, HTML из RTF и картинка в тексте по Content-ID', () {
      final m = read('poi_example_received_unicode.msg');
      expect(m.subject, 'This is a test message please ignore');
      expect(m.to.map((a) => a.name), ['Ashutosh Dandavate', 'Paul Holmes-Higgin', 'Mike Farman']);
      expect(m.html, contains('cid:716052216@11012010-3410'));
      expect(m.inlineImages.keys, ['716052216@11012010-3410']);
      expect(m.attachments, isEmpty, reason: 'картинка — в тексте, не вложением');
    });

    test('Exchange: отправитель без SMTP в свойствах — адрес из заголовков или только имя', () {
      final o = read('poi_outlook_30_msg.msg');
      expect(o.from.single.label, 'Cramer, Nick <nick.cramer@pnl.gov>');
      expect(o.to.length, 18);
      expect(o.html, isNotNull);
      expect(o.plain, contains('I am shutting down the IN-SPIRE servers'));
      final q = read('poi_quick.msg');
      expect(q.subject, 'Test the content transformer');
      expect(q.from.single.name, 'Kevin Roast');
      expect(q.plain?.trim(), 'The quick brown fox jumps over the lazy dog');
    });

    test('в .eml и обратно: тема, адреса и вложения сохраняются', () {
      final m = read('poi_attachment_test_msg.msg');
      final back = EmlReader.parse(MsgReader.toEml(m));
      expect(back.subject, m.subject);
      expect(back.from.single.email, 'nicolas1.23456@free.fr');
      expect(back.attachments.map((a) => a.name), containsAll(['pj1.txt', 'test-unicode.doc']));
    });
  });
}

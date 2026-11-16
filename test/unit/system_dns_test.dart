// Записи DNS через DNS устройства (2.6.0): разбор ответа (RFC 1035) — MX,
// SRV, TXT, сжатие имён, NXDOMAIN и испорченные сообщения.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/net/system_dns.dart';

/// Сообщение DNS: вопрос [qname]/[qtype] и ответы.
class _Msg {
  final b = BytesBuilder();
  final int rcode;
  final List<List<int>> answers = [];
  final String qname;
  final int qtype;
  _Msg(this.qname, this.qtype, {this.rcode = 0});

  static List<int> name(String n) => [
        for (final l in n.split('.').where((x) => x.isNotEmpty)) ...[l.length, ...ascii.encode(l)],
        0,
      ];
  static List<int> u16(int v) => [(v >> 8) & 0xff, v & 0xff];

  /// Ответ с именем-ссылкой на вопрос (0xC00C) и данными [rdata].
  void answer(int type, List<int> rdata) =>
      answers.add([0xC0, 0x0C, ...u16(type), ...u16(1), 0, 0, 0x0e, 0x10, ...u16(rdata.length), ...rdata]);

  Uint8List build() => Uint8List.fromList([
        ...u16(0x1234), 0x81, 0x80 | rcode, ...u16(1), ...u16(answers.length), ...u16(0), ...u16(0),
        ...name(qname), ...u16(qtype), ...u16(1),
        for (final a in answers) ...a,
      ]);
}

void main() {
  test('MX: предпочтение и узел; сортировка по предпочтению', () {
    final m = _Msg('corp.ru', 15)
      ..answer(15, [..._Msg.u16(20), ..._Msg.name('mx2.corp.ru')])
      ..answer(15, [..._Msg.u16(10), ..._Msg.name('MX.Yandex.NET')]);
    final r = SystemDns.parseMessage(m.build(), DnsType.mx)!;
    expect(r, [
      const DnsRecord(DnsType.mx, 'mx2.corp.ru', priority: 20),
      const DnsRecord(DnsType.mx, 'MX.Yandex.NET', priority: 10),
    ]);
    expect(SystemDns.mxHosts(r), ['mx.yandex.net', 'mx2.corp.ru']);
  });

  test('SRV со сжатым именем цели (ссылка на имя вопроса)', () {
    // _imaps._tcp.corp.ru → цель «mail» + ссылка на «corp.ru» (смещение
    // 12 + 7 + 5 = 24: после «_imaps» и «_tcp»).
    final m = _Msg('_imaps._tcp.corp.ru', 33)
      ..answer(33, [..._Msg.u16(0), ..._Msg.u16(5), ..._Msg.u16(993), 4, ...ascii.encode('mail'), 0xC0, 24]);
    final r = SystemDns.parseMessage(m.build(), DnsType.srv)!;
    expect(r.single, const DnsRecord(DnsType.srv, 'mail.corp.ru', priority: 0, weight: 5, port: 993));
  });

  test('TXT: части склеиваются, UTF-8', () {
    final a = utf8.encode('path=/dav/'), b = utf8.encode('ёж');
    final m = _Msg('_caldavs._tcp.corp.ru', 16)..answer(16, [a.length, ...a, b.length, ...b]);
    expect(SystemDns.parseMessage(m.build(), DnsType.txt)!.single.target, 'path=/dav/ёж');
  });

  test('записи другого типа (CNAME) пропускаются', () {
    final m = _Msg('corp.ru', 15)
      ..answer(5, _Msg.name('alias.corp.ru'))
      ..answer(15, [..._Msg.u16(5), ..._Msg.name('mx.corp.ru')]);
    expect(SystemDns.parseMessage(m.build(), DnsType.mx)!.map((e) => e.target), ['mx.corp.ru']);
  });

  test('NXDOMAIN — пусто; SERVFAIL и обрезанное сообщение — null', () {
    expect(SystemDns.parseMessage(_Msg('nope.ru', 15, rcode: 3).build(), DnsType.mx), isEmpty);
    expect(SystemDns.parseMessage(_Msg('x.ru', 15, rcode: 2).build(), DnsType.mx), isNull);
    final full = (_Msg('corp.ru', 15)..answer(15, [..._Msg.u16(10), ..._Msg.name('mx.corp.ru')])).build();
    expect(SystemDns.parseMessage(Uint8List.sublistView(full, 0, full.length - 4), DnsType.mx), isNull);
    expect(SystemDns.parseMessage(Uint8List(5), DnsType.mx), isNull);
  });

  test('петля ссылок в имени — null, а не зависание', () {
    final m = _Msg('corp.ru', 15)..answer(15, [..._Msg.u16(10), 0xC0, 0x0C + 0]);
    final bytes = m.build();
    // Имя вопроса указывает само на себя.
    bytes[12] = 0xC0;
    bytes[13] = 0x0C;
    expect(SystemDns.parseMessage(bytes, DnsType.mx), isNull);
  });

  test('лучшая запись SRV: приоритет, затем вес; «.» — службы нет', () {
    const a = DnsRecord(DnsType.srv, 'b.corp.ru', priority: 10, weight: 1, port: 993);
    const b = DnsRecord(DnsType.srv, 'a.corp.ru', priority: 0, weight: 1, port: 993);
    const c = DnsRecord(DnsType.srv, 'c.corp.ru', priority: 0, weight: 50, port: 993);
    expect(SystemDns.bestSrv([a, b, c]), c);
    expect(SystemDns.bestSrv(const [DnsRecord(DnsType.srv, '', port: 0)]), isNull);
    expect(SystemDns.bestSrv(null), isNull);
  });

  test('неверное имя не уходит в DNS — null без запроса', () async {
    final r = await SystemDns.lookup(const [DnsQuestion('bad name;', DnsType.mx)]);
    expect(r, [null]);
  });
}

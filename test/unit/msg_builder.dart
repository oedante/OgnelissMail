// Письмо Outlook (.msg, MS-OXMSG) для тестов (1.12.x, просьба владельца
// 05.11.2026): свойства письма, получатели, вложения и вложенные письма —
// в составной файл через CfbWriter. LibreOffice .msg не пишет, поэтому
// образцы собираются здесь, по спецификации.

import 'dart:convert';
import 'dart:typed_data';

import 'cfb_writer.dart';

/// Свойства одного уровня (письмо, получатель, вложение).
class MsgProps {
  final Map<int, Object> values = {};

  /// Строка UTF-16 (тип 001F).
  void str(int id, String v) => values[(id << 16) | 0x001F] = v;

  /// 8-битная строка (тип 001E) — уже байтами в нужной кодовой странице.
  void str8(int id, List<int> bytes) => values[(id << 16) | 0x001E] = Uint8List.fromList(bytes);
  void bin(int id, List<int> bytes) => values[(id << 16) | 0x0102] = Uint8List.fromList(bytes);
  void i32(int id, int v) => values[(id << 16) | 0x0003] = v;
  void time(int id, DateTime t) =>
      values[(id << 16) | 0x0040] = (t.toUtc().microsecondsSinceEpoch + 11644473600000000) * 10;

  /// Поток свойств и потоки значений в хранилище [prefix] («» — корень).
  void write(CfbWriter w, String prefix, int header) {
    final props = BytesBuilder()..add(Uint8List(header));
    values.forEach((tag, v) {
      final e = ByteData(16)
        ..setUint32(0, tag, Endian.little)
        ..setUint32(4, 6, Endian.little);
      final type = tag & 0xFFFF;
      final hex = tag.toRadixString(16).padLeft(8, '0').toUpperCase();
      switch (type) {
        case 0x001F:
          final s = v as String;
          final b = Uint8List((s.length + 1) * 2);
          for (var i = 0; i < s.length; i++) {
            b[i * 2] = s.codeUnitAt(i) & 0xFF;
            b[i * 2 + 1] = s.codeUnitAt(i) >> 8;
          }
          w.add('${prefix}__substg1.0_$hex', b);
          e.setUint32(8, b.length, Endian.little);
        case 0x001E || 0x0102:
          final b = v as Uint8List;
          w.add('${prefix}__substg1.0_$hex', type == 0x001E ? [...b, 0] : b);
          e.setUint32(8, b.length, Endian.little);
        case 0x0040:
          e.setInt64(8, v as int, Endian.little);
        default:
          e.setUint32(8, v as int, Endian.little);
      }
      props.add(e.buffer.asUint8List());
    });
    w.add('${prefix}__properties_version1.0', props.toBytes());
  }
}

/// Письмо: свои свойства, получатели, вложения (у вложения — свойства и,
/// для вложенного письма, само письмо).
class MsgBuilder {
  final props = MsgProps();
  final recipients = <MsgProps>[];
  final attachments = <(MsgProps, MsgBuilder?)>[];

  Uint8List build() {
    final w = CfbWriter();
    _write(w, '', 32);
    return w.build();
  }

  void _write(CfbWriter w, String prefix, int header) {
    props.write(w, prefix, header);
    for (var i = 0; i < recipients.length; i++) {
      recipients[i].write(w, '${prefix}__recip_version1.0_#${i.toRadixString(16).padLeft(8, '0').toUpperCase()}/', 8);
    }
    for (var i = 0; i < attachments.length; i++) {
      final at = '${prefix}__attach_version1.0_#${i.toRadixString(16).padLeft(8, '0').toUpperCase()}/';
      attachments[i].$1.write(w, at, 8);
      attachments[i].$2?._write(w, '${at}__substg1.0_3701000D/', 24);
    }
  }
}

/// Байты строки в UTF-8 (для двоичных свойств вроде PidTagHtml).
List<int> utf8Bytes(String s) => utf8.encode(s);

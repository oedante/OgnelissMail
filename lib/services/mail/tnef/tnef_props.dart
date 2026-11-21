// lib/services/mail/tnef/tnef_props.dart
//
// Свойства MAPI самого письма из TNEF (winmail.dat) — просьба владельца
// 21.11.2026: «не обрабатываются пересылаемые контакты и группы контактов
// (нельзя сохранить себе)». Outlook пересылает контакт и группу контактов
// вложенным письмом, всё содержимое которого — winmail.dat: класс
// IPM.Contact или IPM.DistList, поля контакта, участники группы, текст.
//
// Здесь — только свойства уровня письма (attMAPIProps, уровень 1);
// файлы-вложения из того же потока достаёт TnefDecoder. Формат — [MS-OXTNEF]
// 2.1.3.4 (MsgPropertyList): число свойств, для каждого — тип и номер,
// у именованных (номер от 0x8000) — GUID набора и номер или имя, затем
// значение, выровненное до 4 байт.

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' show MailCodec;

/// Свойства MAPI письма из TNEF.
class TnefProps {
  TnefProps._();

  /// Обычные свойства: номер → значение (String, Uint8List, int, bool,
  /// DateTime, List<…> у многозначных).
  final Map<int, Object> props = {};

  /// Именованные свойства по номеру (LID): «guid:lid» → значение. GUID —
  /// 16 байт как в потоке, шестнадцатерично строчными.
  final Map<String, Object> named = {};

  /// Кодовая страница строк PT_STRING8 (attOemCodepage).
  int? codepage;

  /// Набор свойств адресов и контактов (PSETID_Address,
  /// {00062004-0000-0000-C000-000000000046}).
  static const psetidAddress = '0420060000000000c000000000000046';

  static const _signature = 0x223E9F78;
  static const _attMapiProps = 0x9003;
  static const _attOemCodepage = 0x9007;
  static const _attAttachRendData = 0x9002;

  /// Предел числа свойств — защита от испорченного потока.
  static const _maxProps = 20000;

  String? string(int id) => _asString(props[id]);
  String? namedString(int lid, {String guid = psetidAddress}) => _asString(named['$guid:$lid']);
  List<Uint8List> namedBinaries(int lid, {String guid = psetidAddress}) {
    final v = named['$guid:$lid'];
    if (v is List) return v.whereType<Uint8List>().toList();
    if (v is Uint8List) return [v];
    return const [];
  }

  Uint8List? binary(int id) {
    final v = props[id];
    return v is Uint8List ? v : null;
  }

  /// Класс письма: IPM.Note, IPM.Contact, IPM.DistList…
  String? get messageClass => string(0x001A);

  static String? _asString(Object? v) {
    if (v is String) return v;
    if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
    return null;
  }

  /// Разобрать поток TNEF; не TNEF или испорчен — null (или то, что
  /// успело разобраться).
  static TnefProps? parse(Uint8List bytes) {
    if (bytes.length < 6) return null;
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != _signature) return null;
    final out = TnefProps._();
    var pos = 6;
    final n = bytes.length;
    var inAttachment = false;
    while (pos + 9 <= n) {
      final level = bytes[pos];
      if (level != 1 && level != 2) break;
      final attr = bd.getUint32(pos + 1, Endian.little);
      final len = bd.getUint32(pos + 5, Endian.little);
      final start = pos + 9;
      if (start + len + 2 > n) break;
      final id = attr & 0xFFFF;
      if (id == _attAttachRendData) inAttachment = true;
      if (level == 1 && id == _attOemCodepage && len >= 4) {
        out.codepage = bd.getUint32(start, Endian.little);
      }
      if (level == 1 && !inAttachment && id == _attMapiProps) {
        try {
          out._readProps(Uint8List.sublistView(bytes, start, start + len));
        } catch (_) {
          // Испорченный хвост — оставляем то, что прочиталось.
        }
      }
      pos = start + len + 2;
    }
    return out;
  }

  static int _pad(int len) => (len + 3) & ~3;

  static int? _fixedSize(int type) => switch (type) {
        0x0002 => 2, // PT_SHORT
        0x0003 => 4, // PT_LONG
        0x0004 => 4, // PT_FLOAT
        0x0005 => 8, // PT_DOUBLE
        0x0006 => 8, // PT_CURRENCY
        0x0007 => 8, // PT_APPTIME
        0x000A => 4, // PT_ERROR
        0x000B => 2, // PT_BOOLEAN (2 байта + выравнивание)
        0x0014 => 8, // PT_I8
        0x0040 => 8, // PT_SYSTIME
        0x0048 => 16, // PT_CLSID
        _ => null,
      };

  void _readProps(Uint8List d) {
    final bd = ByteData.sublistView(d);
    var p = 0;
    int u32() {
      final v = bd.getUint32(p, Endian.little);
      p += 4;
      return v;
    }

    final count = u32();
    if (count > _maxProps) return;
    for (var k = 0; k < count && p + 4 <= d.length; k++) {
      final type = bd.getUint16(p, Endian.little);
      final id = bd.getUint16(p + 2, Endian.little);
      p += 4;
      String? namedKey;
      if (id >= 0x8000) {
        final guid = _hex(Uint8List.sublistView(d, p, p + 16));
        p += 16;
        final kind = u32();
        if (kind == 0) {
          namedKey = '$guid:${u32()}';
        } else {
          final len = u32();
          final name = _utf16(Uint8List.sublistView(d, p, p + len));
          p += _pad(len);
          namedKey = '$guid:$name';
        }
      }
      final multi = type & 0x1000 != 0;
      final base = type & 0x0FFF;
      final fixed = _fixedSize(base);
      Object value;
      if (fixed != null && !multi) {
        value = _fixed(base, Uint8List.sublistView(d, p, p + fixed));
        p += _pad(fixed);
      } else {
        final values = <Object>[];
        final m = u32();
        if (m > _maxProps) return;
        for (var j = 0; j < m; j++) {
          if (fixed != null) {
            values.add(_fixed(base, Uint8List.sublistView(d, p, p + fixed)));
            p += _pad(fixed);
          } else {
            final len = u32();
            if (p + len > d.length) return;
            final raw = Uint8List.sublistView(d, p, p + len);
            p += _pad(len);
            values.add(switch (base) {
              0x001F => _utf16(raw),
              0x001E => _string8(raw),
              _ => Uint8List.fromList(raw),
            });
          }
        }
        value = multi ? values : (values.isEmpty ? '' : values.first);
      }
      if (namedKey != null) {
        named[namedKey] = value;
      } else {
        props[id] = value;
      }
    }
  }

  Object _fixed(int type, Uint8List b) {
    final bd = ByteData.sublistView(b);
    switch (type) {
      case 0x0002:
        return bd.getInt16(0, Endian.little);
      case 0x0003:
      case 0x000A:
        return bd.getInt32(0, Endian.little);
      case 0x000B:
        return bd.getUint16(0, Endian.little) != 0;
      case 0x0014:
        return bd.getInt64(0, Endian.little);
      case 0x0040:
        // FILETIME: сотни наносекунд с 1601 года.
        final t = bd.getInt64(0, Endian.little);
        return DateTime.utc(1601).add(Duration(microseconds: t ~/ 10));
      default:
        return Uint8List.fromList(b);
    }
  }

  static String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static String _utf16(Uint8List b) {
    final codes = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      final c = b[i] | (b[i + 1] << 8);
      if (c == 0) break;
      codes.add(c);
    }
    return String.fromCharCodes(codes);
  }

  String _string8(Uint8List b) {
    var end = b.indexOf(0);
    if (end < 0) end = b.length;
    final raw = Uint8List.sublistView(b, 0, end);
    if (raw.every((c) => c < 0x80)) return ascii.decode(raw);
    final cp = codepage;
    if (cp == null || cp == 65001) return utf8.decode(raw, allowMalformed: true);
    try {
      return MailCodec.decodeAsText(raw, null, 'windows-$cp');
    } catch (_) {
      return latin1.decode(raw);
    }
  }
}

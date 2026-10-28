// lib/services/mail/tnef/tnef_decoder.dart
// Декодер TNEF (Transport Neutral Encapsulation Format) — формат вложения
// Microsoft Exchange/Outlook «winmail.dat» (MIME application/ms-tnef).
// Извлекает вложенные файлы (имя + байты). Базовая, но рабочая реализация:
// читает поток атрибутов и собирает attachments по RENDDATA/TITLE/DATA.
//
// Использование:
//   if (TnefDecoder.isTnef(bytes)) {
//     final files = TnefDecoder.decode(bytes); // List<TnefAttachment>
//   }

import 'dart:typed_data';

class TnefAttachment {
  String filename;
  Uint8List? data;
  TnefAttachment({this.filename = '', this.data});

  int get size => data?.length ?? 0;
}

class TnefDecoder {
  static const int _signature = 0x223E9F78; // TNEF_SIGNATURE (LE)

  // Идентификаторы атрибутов (младшие 16 бит attribute-поля)
  static const int _idAttachRendData = 0x9002; // начало нового вложения
  static const int _idAttachTitle = 0x8010;    // имя файла (8.3)
  static const int _idAttachData = 0x800F;      // байты вложения
  static const int _idAttachment = 0x9005;      // MAPI-свойства (вкл. длинное имя)

  /// Является ли поток TNEF (по сигнатуре).
  static bool isTnef(Uint8List bytes) {
    if (bytes.length < 6) return false;
    final sig = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
    return sig == _signature;
  }

  /// Похоже ли вложение на winmail.dat по имени/типу (без байтов).
  static bool looksLikeWinmail(String? filename, String? mimeType) {
    final name = (filename ?? '').toLowerCase();
    final mime = (mimeType ?? '').toLowerCase();
    return name == 'winmail.dat' ||
        mime == 'application/ms-tnef' ||
        mime == 'application/vnd.ms-tnef';
  }

  /// Декодировать вложения из TNEF-потока. При ошибке/неполноте возвращает то,
  /// что успело распарситься.
  static List<TnefAttachment> decode(Uint8List bytes) {
    final result = <TnefAttachment>[];
    if (!isTnef(bytes)) return result;

    final bd = ByteData.sublistView(bytes);
    int pos = 4; // после сигнатуры
    pos += 2;    // ключ (2 байта)

    TnefAttachment? current;
    final n = bytes.length;

    while (pos + 9 <= n) {
      final lvl = bytes[pos]; pos += 1;
      if (lvl != 1 && lvl != 2) break; // повреждённый поток
      final attribute = bd.getUint32(pos, Endian.little); pos += 4;
      final length = bd.getUint32(pos, Endian.little); pos += 4;
      if (pos + length + 2 > n) break; // не хватает данных/контрольной суммы

      final data = Uint8List.sublistView(bytes, pos, pos + length);
      pos += length;
      pos += 2; // checksum (не проверяем)

      final id = attribute & 0xFFFF;
      switch (id) {
        case _idAttachRendData:
          // Завершаем предыдущее и начинаем новое вложение
          if (current != null) result.add(current);
          current = TnefAttachment();
          break;
        case _idAttachTitle:
          current ??= TnefAttachment();
          current.filename = _cString(data);
          break;
        case _idAttachData:
          current ??= TnefAttachment();
          current.data = Uint8List.fromList(data);
          break;
        case _idAttachment:
          // MAPI-свойства: пробуем вытащить длинное имя (PR_ATTACH_LONG_FILENAME).
          current ??= TnefAttachment();
          final longName = _extractLongFilename(data);
          if (longName != null && longName.isNotEmpty) current.filename = longName;
          break;
        default:
          break;
      }
    }
    if (current != null) result.add(current);
    // Оставляем только вложения с данными
    return result.where((a) => (a.data?.isNotEmpty ?? false)).toList();
  }

  /// Строка с отсечением хвостового нуля.
  static String _cString(Uint8List data) {
    int end = data.length;
    while (end > 0 && data[end - 1] == 0) {
      end--;
    }
    return String.fromCharCodes(data.sublist(0, end)).trim();
  }

  /// Грубое извлечение PR_ATTACH_LONG_FILENAME (0x3707) из MAPI-блока attAttachment.
  /// Формат MAPI в TNEF: [uint32 count] затем свойства; здесь — упрощённый поиск
  /// тега 0x3707 с типом PT_UNICODE(0x001F)/PT_STRING8(0x001E) и чтением значения.
  static String? _extractLongFilename(Uint8List data) {
    try {
      final bd = ByteData.sublistView(data);
      if (data.length < 4) return null;
      int pos = 0;
      final count = bd.getUint32(pos, Endian.little); pos += 4;
      for (int i = 0; i < count && pos + 8 <= data.length; i++) {
        final type = bd.getUint16(pos, Endian.little);
        final id = bd.getUint16(pos + 2, Endian.little);
        pos += 4;
        // Для строковых типов далее идёт count значений и длины
        final isUnicode = type == 0x001F;
        final isString = type == 0x001E;
        if (isUnicode || isString) {
          if (pos + 4 > data.length) break;
          final valCount = bd.getUint32(pos, Endian.little); pos += 4;
          String? found;
          for (int v = 0; v < valCount && pos + 4 <= data.length; v++) {
            final len = bd.getUint32(pos, Endian.little); pos += 4;
            if (pos + len > data.length) return found;
            final raw = Uint8List.sublistView(data, pos, pos + len);
            // выравнивание по 4 байта
            final padded = (len + 3) & ~3;
            pos += padded;
            final str = isUnicode
                ? String.fromCharCodes(_utf16le(raw))
                : _cString(raw);
            if (id == 0x3707) found = str.replaceAll('\x00', '').trim();
          }
          if (id == 0x3707 && found != null) return found;
        } else {
          // Прочие типы — пропускаем фиксированный размер (приблизительно)
          final skip = _mapiFixedSize(type);
          if (skip == null) break; // неизвестный тип — выходим
          pos += skip;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static List<int> _utf16le(Uint8List raw) {
    final out = <int>[];
    for (int i = 0; i + 1 < raw.length; i += 2) {
      final ch = raw[i] | (raw[i + 1] << 8);
      if (ch == 0) break;
      out.add(ch);
    }
    return out;
  }

  static int? _mapiFixedSize(int type) {
    switch (type) {
      case 0x0002: return 2; // PT_SHORT
      case 0x0003: return 4; // PT_LONG
      case 0x0004: return 4; // PT_FLOAT
      case 0x0005: return 8; // PT_DOUBLE
      case 0x000B: return 4; // PT_BOOLEAN (выровнено)
      case 0x0014: return 8; // PT_I8
      case 0x0040: return 8; // PT_SYSTIME
      default: return null;  // переменная длина/неизвестно
    }
  }
}

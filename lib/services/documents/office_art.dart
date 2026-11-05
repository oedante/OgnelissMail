// lib/services/documents/office_art.dart
// Записи OfficeArt (рисунки старых .doc и .ppt, [MS-ODRAW]) — общее для
// doc_reader.dart и ppt_reader.dart (1.12.x, просьба владельца 04.11.2026:
// старые форматы Office в предпросмотре).
//
// Запись — заголовок 8 байт (версия и «экземпляр» в одном слове, тип,
// длина) и данные; версия 0xF — контейнер с записями внутри. Картинки —
// записи BLIP: PNG и JPEG — как есть, DIB (растр без заголовка файла) —
// с заголовком BMP; EMF, WMF, PICT, TIFF не показываются (их не рисуют ни
// окно письма, ни Flutter). Длины и вложенность — из чужого файла: всё
// проверяется по границам данных, глубина — не больше [OfficeLimits.maxDepth].

import 'dart:typed_data';

import 'office_package.dart';

/// Заголовок записи OfficeArt (и записи PowerPoint — у них тот же вид).
class ArtRecord {
  final int ver;
  final int inst;
  final int type;

  /// Начало данных записи и их длина (уже в пределах буфера).
  final int at;
  final int len;
  const ArtRecord(this.ver, this.inst, this.type, this.at, this.len);

  bool get isContainer => ver == 0xF;
  int get end => at + len;
}

class OfficeArt {
  OfficeArt._();

  /// Запись с [at] в [data] (не дальше [end]); null — не умещается.
  static ArtRecord? record(Uint8List data, int at, [int? end]) {
    final stop = end ?? data.length;
    if (at < 0 || at + 8 > stop) return null;
    final bd = ByteData.sublistView(data);
    final vi = bd.getUint16(at, Endian.little);
    final type = bd.getUint16(at + 2, Endian.little);
    final len = bd.getUint32(at + 4, Endian.little);
    if (at + 8 + len > stop) return null;
    return ArtRecord(vi & 0xF, vi >> 4, type, at + 8, len);
  }

  /// Записи подряд в [from, to).
  static Iterable<ArtRecord> children(Uint8List data, int from, int to) sync* {
    var p = from;
    while (true) {
      final r = record(data, p, to);
      if (r == null) return;
      yield r;
      p = r.end;
    }
  }

  /// Первая показываемая картинка в записях [from, to) — с обходом
  /// контейнеров и записей хранилища картинок (FBSE со встроенной BLIP).
  static OfficeImage? firstBlip(Uint8List data, int from, int to, {int depth = 0}) {
    if (depth > OfficeLimits.maxDepth) return null;
    for (final r in children(data, from, to)) {
      if (r.isContainer) {
        final img = firstBlip(data, r.at, r.end, depth: depth + 1);
        if (img != null) return img;
      } else if (r.type == 0xF007) {
        // OfficeArtFBSE: 36 байт, имя, затем сама BLIP.
        if (r.len < 36) continue;
        final cbName = data[r.at + 33];
        final img = firstBlip(data, r.at + 36 + cbName, r.end, depth: depth + 1);
        if (img != null) return img;
      } else {
        final img = blip(data, r);
        if (img != null) return img;
      }
    }
    return null;
  }

  /// Картинка записи BLIP [r]; null — не картинка или не показывается.
  static OfficeImage? blip(Uint8List data, ArtRecord r) {
    final int uids;
    switch ((r.type, r.inst)) {
      case (0xF01E, 0x6E0) || (0xF01D, 0x46A) || (0xF01D, 0x6E2) || (0xF01F, 0x7A8):
        uids = 1;
      case (0xF01E, 0x6E1) || (0xF01D, 0x46B) || (0xF01D, 0x6E3) || (0xF01F, 0x7A9):
        uids = 2;
      default:
        return null;
    }
    final start = r.at + uids * 16 + 1;
    if (start >= r.end || r.end - start > OfficeLimits.maxImageBytes) return null;
    var bytes = Uint8List.fromList(Uint8List.sublistView(data, start, r.end));
    if (r.type == 0xF01F) {
      final bmp = _bmp(bytes);
      if (bmp == null) return null;
      bytes = bmp;
    }
    final mime = OfficeImage.sniff(bytes);
    return mime == null ? null : OfficeImage(mime, bytes);
  }

  /// Растр DIB (BITMAPINFOHEADER и точки) → файл BMP: заголовок файла с
  /// местом начала точек (после таблицы цветов).
  static Uint8List? _bmp(Uint8List dib) {
    if (dib.length < 40) return null;
    final bd = ByteData.sublistView(dib);
    final size = bd.getUint32(0, Endian.little);
    if (size < 12 || size > dib.length) return null;
    var colors = 0;
    var masks = 0;
    if (size >= 40) {
      final bits = bd.getUint16(14, Endian.little);
      final used = bd.getUint32(32, Endian.little);
      colors = used != 0 ? used : (bits <= 8 ? 1 << bits : 0);
      if (bd.getUint32(16, Endian.little) == 3 && size == 40) masks = 12;
    }
    final offset = 14 + size + masks + colors * 4;
    if (offset > dib.length + 14) return null;
    final out = Uint8List(14 + dib.length);
    final h = ByteData.sublistView(out);
    out[0] = 0x42;
    out[1] = 0x4D;
    h.setUint32(2, out.length, Endian.little);
    h.setUint32(10, offset, Endian.little);
    out.setRange(14, out.length, dib);
    return out;
  }
}

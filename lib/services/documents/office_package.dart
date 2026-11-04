// lib/services/documents/office_package.dart
// Пакет документа: DOCX, XLSX, PPTX (Office Open XML) и ODT, ODS, ODP
// (OpenDocument) — это ZIP с XML внутри (1.11.x, предпросмотр документов
// Office, план владельца 04.11.2026).
//
// Почему свой читатель ZIP, а не пакет archive, как в zip_view.dart: архив
// там распаковывается в файл по одной записи, и предел — объявленный в
// оглавлении размер (2 ГБ). Документ разбирается в памяти, из него берутся
// десятки частей, а объявленным размерам верить нельзя: «ZIP-бомба» — это
// как раз запись, которая в оглавлении маленькая, а распаковывается в
// гигабайты. Здесь пределы — на то, что действительно распаковано:
//  · файл документа — не больше [OfficeLimits.maxFileBytes];
//  · одна часть (XML листа, текст документа) — [OfficeLimits.maxPartBytes];
//  · все прочитанные части вместе — [OfficeLimits.maxTotalBytes];
//  · картинки — по одной и вместе ([OfficeLimits.maxImageBytes],
//    [OfficeLimits.maxImagesTotal]).
// Распаковка (zlib из dart:io) идёт кусками и прерывается, как только
// предел превышен, — раньше, чем распакованное займёт память. Для больших
// листов есть [OfficeZip.readHead]: начало части (первые строки таблицы)
// вместо отказа.
//
// Имена частей: «\» — «/», без корня, «.» и «..»; часть ищется и без учёта
// регистра (так пишут некоторые программы). Документ с паролем на открытие
// — не ZIP, а составной файл OLE, как старый .doc: [OfficeDocError.encrypted]
// (у OpenDocument с паролем — запись encryption-data в манифесте).
//
// XML разбирается пакетом xml (уже в проекте, MIT): внешние сущности и DTD
// он не загружает, объявленные в документе сущности не раскрывает
// («billion laughs» не страшен) — только стандартные (&amp; …) и числовые.

import 'dart:convert';
import 'dart:io' show RawZLibFilter;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Почему документ не показан.
enum OfficeDocError {
  /// Пароль на открытие (зашифрованный OOXML или OpenDocument).
  encrypted,

  /// Двоичный формат Office 97–2003 (.doc, .xls, .ppt) — пока не показывается.
  legacy,

  /// Файл повреждён или это не документ этого формата.
  damaged,

  /// Больше пределов [OfficeLimits].
  tooLarge,

  /// Документ в порядке, но в нём то, чего предпросмотр не умеет
  /// (способ сжатия ZIP, неизвестный вариант формата).
  unsupported,
}

class OfficeDocException implements Exception {
  final OfficeDocError kind;
  final String detail;
  const OfficeDocException(this.kind, [this.detail = '']);

  @override
  String toString() => 'OfficeDocException(${kind.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// Пределы разбора. Документ из письма — чужой файл: всё, что из него
/// читается, ограничено, иначе один файл может занять всю память телефона.
class OfficeLimits {
  OfficeLimits._();

  /// Файл больше — не разбирается (предложение открыть в другом приложении).
  static const maxFileBytes = 64 * 1024 * 1024;

  /// Записей в ZIP больше — документ не разбирается.
  static const maxEntries = 20000;

  /// Одна часть, распакованная целиком.
  static const maxPartBytes = 32 * 1024 * 1024;

  /// Все прочитанные части вместе (одна и та же часть, прочитанная дважды,
  /// считается дважды).
  static const maxTotalBytes = 128 * 1024 * 1024;

  /// Одна картинка; больше — вместо неё пустое место.
  static const maxImageBytes = 8 * 1024 * 1024;

  /// Все картинки документа вместе.
  static const maxImagesTotal = 32 * 1024 * 1024;

  /// Текст документа для показа: знаки текста плюс [blockWeight] на каждый
  /// абзац, ячейку таблицы и строку. Окно письма не выше 60 000 точек
  /// (MailHtmlView), а 100 000 знаков — это ~40 000 точек на телефоне
  /// (MailClip). Дальше — «показано начало» ([OfficeTextDoc.truncated]).
  static const maxTextWeight = 100000;
  static const blockWeight = 40;

  /// Глубина вложенности, до которой обходится XML и RTF (таблица в таблице
  /// в надписи…). Глубже — пропускается: обход не уходит в переполнение стека.
  static const maxDepth = 64;
}

/// Связь части OOXML (_rels/*.rels): картинка, ссылка, лист, слайд.
class OfficeRel {
  final String id;

  /// Тип связи — полный адрес (…/relationships/image); сравнивать по концу.
  final String type;

  /// Для внутренней — полное имя части в пакете («word/media/image1.png»),
  /// для внешней (TargetMode="External") — адрес как есть.
  final String target;
  final bool external;
  const OfficeRel(this.id, this.type, this.target, {this.external = false});

  /// Тип связи заканчивается на «/[kind]» (image, hyperlink, worksheet …).
  bool isType(String kind) => type.endsWith('/$kind');
}

/// Картинка из пакета, которую можно показать (PNG, JPEG, GIF, WebP, BMP).
class OfficeImage {
  final String mime;
  final Uint8List bytes;
  const OfficeImage(this.mime, this.bytes);

  String get dataUri => 'data:$mime;base64,${base64Encode(bytes)}';

  /// Тип по первым байтам; EMF, WMF, TIFF, SVG и прочее — null: окно письма
  /// и Flutter их не рисуют (SVG ещё и не нужен — в нём бывают скрипты).
  static String? sniff(Uint8List b) {
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return 'image/gif';
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'image/bmp';
    return null;
  }
}

class _Entry {
  final String name;
  final int method;
  final int flags;
  final int compressedSize;
  final int size;
  final int localOffset;
  const _Entry(this.name, this.method, this.flags, this.compressedSize, this.size, this.localOffset);
}

/// Документ-пакет, открытый из байтов файла.
class OfficeZip {
  OfficeZip._(this._data, this._entries) {
    for (final e in _entries.values) {
      _lower.putIfAbsent(e.name.toLowerCase(), () => e.name);
    }
  }

  final Uint8List _data;
  final Map<String, _Entry> _entries;
  final Map<String, String> _lower = {};
  int _readTotal = 0;
  int _imagesTotal = 0;

  /// Начало файла — ZIP (документ OOXML или OpenDocument).
  static bool isZip(Uint8List head) =>
      head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B && (head[2] == 0x03 || head[2] == 0x05) &&
      (head[3] == 0x04 || head[3] == 0x06);

  /// Составной файл OLE (Compound File Binary): старые .doc/.xls/.ppt и
  /// документы OOXML с паролем.
  static bool isOle(Uint8List head) =>
      head.length >= 8 &&
      head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0 &&
      head[4] == 0xA1 && head[5] == 0xB1 && head[6] == 0x1A && head[7] == 0xE1;

  /// Открыть пакет: прочитать оглавление (центральный каталог ZIP).
  static OfficeZip open(Uint8List data) {
    if (data.length > OfficeLimits.maxFileBytes) throw const OfficeDocException(OfficeDocError.tooLarge, 'file');
    if (isOle(data)) throw const OfficeDocException(OfficeDocError.encrypted, 'ole');
    if (data.length < 22) throw const OfficeDocException(OfficeDocError.damaged, 'short');
    final bd = ByteData.sublistView(data);
    var eocd = -1;
    final stop = math.max(0, data.length - 22 - 0xFFFF);
    for (var i = data.length - 22; i >= stop; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const OfficeDocException(OfficeDocError.damaged, 'no zip directory');
    var count = bd.getUint16(eocd + 10, Endian.little);
    var cdSize = bd.getUint32(eocd + 12, Endian.little);
    var cdOffset = bd.getUint32(eocd + 16, Endian.little);
    if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      // ZIP64: локатор — за 20 байт до конца каталога.
      final loc = eocd - 20;
      if (loc < 0 || bd.getUint32(loc, Endian.little) != 0x07064b50) {
        throw const OfficeDocException(OfficeDocError.damaged, 'zip64');
      }
      final rec = bd.getUint64(loc + 8, Endian.little);
      if (rec < 0 || rec + 56 > data.length || bd.getUint32(rec, Endian.little) != 0x06064b50) {
        throw const OfficeDocException(OfficeDocError.damaged, 'zip64');
      }
      count = bd.getUint64(rec + 32, Endian.little);
      cdSize = bd.getUint64(rec + 40, Endian.little);
      cdOffset = bd.getUint64(rec + 48, Endian.little);
    }
    if (count > OfficeLimits.maxEntries) throw const OfficeDocException(OfficeDocError.tooLarge, 'entries');
    if (cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > data.length) {
      throw const OfficeDocException(OfficeDocError.damaged, 'zip directory');
    }
    final entries = <String, _Entry>{};
    var p = cdOffset;
    final end = cdOffset + cdSize;
    while (p + 46 <= end && entries.length < count) {
      if (bd.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = bd.getUint16(p + 8, Endian.little);
      final method = bd.getUint16(p + 10, Endian.little);
      var csize = bd.getUint32(p + 20, Endian.little);
      var usize = bd.getUint32(p + 24, Endian.little);
      final nameLen = bd.getUint16(p + 28, Endian.little);
      final extraLen = bd.getUint16(p + 30, Endian.little);
      final commentLen = bd.getUint16(p + 32, Endian.little);
      var offset = bd.getUint32(p + 42, Endian.little);
      final nameStart = p + 46;
      final extraStart = nameStart + nameLen;
      final next = extraStart + extraLen + commentLen;
      if (next > end) break;
      // ZIP64: настоящие размеры и смещение — в доп. поле 0x0001, по порядку
      // только для тех, что в основной записи 0xFFFFFFFF.
      if (csize == 0xFFFFFFFF || usize == 0xFFFFFFFF || offset == 0xFFFFFFFF) {
        var x = extraStart;
        while (x + 4 <= extraStart + extraLen) {
          final id = bd.getUint16(x, Endian.little);
          final len = bd.getUint16(x + 2, Endian.little);
          if (id == 0x0001) {
            var q = x + 4;
            int take() {
              if (q + 8 > x + 4 + len) return -1;
              final v = bd.getUint64(q, Endian.little);
              q += 8;
              return v;
            }
            if (usize == 0xFFFFFFFF) usize = take();
            if (csize == 0xFFFFFFFF) csize = take();
            if (offset == 0xFFFFFFFF) offset = take();
            break;
          }
          x += 4 + len;
        }
      }
      // Имена частей пакета — латиница (OPC: UTF-8 с %-кодированием); без
      // флага UTF-8 читаем как Latin-1, кириллица в именах частей не бывает.
      final rawName = Uint8List.sublistView(data, nameStart, extraStart);
      final name = normalize(flags & 0x800 != 0 ? utf8.decode(rawName, allowMalformed: true) : latin1.decode(rawName));
      if (name.isNotEmpty && !name.endsWith('/')) {
        entries.putIfAbsent(name, () => _Entry(name, method, flags, csize, usize, offset));
      }
      p = next;
    }
    if (entries.isEmpty) throw const OfficeDocException(OfficeDocError.damaged, 'empty zip');
    return OfficeZip._(data, entries);
  }

  /// Имя части без корня, «.» и «..», с «/»; «%20» и т. п. раскодированы
  /// (так имена пишутся в связях OOXML).
  static String normalize(String raw) {
    var s = raw.replaceAll('\\', '/');
    if (s.contains('%')) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }
    final out = <String>[];
    for (final part in s.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(part);
    }
    final joined = out.join('/');
    return s.endsWith('/') && joined.isNotEmpty ? '$joined/' : joined;
  }

  /// Цель связи [target] относительно части [sourcePart]
  /// («word/document.xml» + «media/image1.png» → «word/media/image1.png»;
  /// «/xl/worksheets/sheet1.xml» — от корня).
  static String resolveTarget(String sourcePart, String target) {
    if (target.startsWith('/')) return normalize(target);
    final slash = sourcePart.lastIndexOf('/');
    final dir = slash < 0 ? '' : sourcePart.substring(0, slash + 1);
    return normalize('$dir$target');
  }

  /// Имена всех частей пакета.
  Iterable<String> get names => _entries.keys;

  /// Настоящее имя части [name] (точное или без учёта регистра); null — нет.
  String? find(String name) {
    final n = normalize(name);
    if (_entries.containsKey(n)) return n;
    return _lower[n.toLowerCase()];
  }

  bool has(String name) => find(name) != null;

  /// Объявленный размер части (только для решений «читать ли»: верить ему
  /// нельзя, пределы — при распаковке).
  int? declaredSize(String name) {
    final n = find(name);
    return n == null ? null : _entries[n]!.size;
  }

  /// Часть [name] целиком; null — нет такой. Больше [OfficeLimits.maxPartBytes]
  /// (или [max]) — [OfficeDocError.tooLarge].
  Uint8List? read(String name, {int? max}) {
    final r = _read(name, max ?? OfficeLimits.maxPartBytes, truncate: false);
    return r?.bytes;
  }

  /// Начало части [name] — не больше [max] байт: [truncated] — часть
  /// длиннее. Для листов таблиц: показать первые строки, а не отказать.
  ({Uint8List bytes, bool truncated})? readHead(String name, int max) =>
      _read(name, math.min(max, OfficeLimits.maxPartBytes), truncate: true);

  ({Uint8List bytes, bool truncated})? _read(String name, int cap, {required bool truncate}) {
    final n = find(name);
    if (n == null) return null;
    final e = _entries[n]!;
    if (e.flags & 0x1 != 0) throw const OfficeDocException(OfficeDocError.encrypted, 'zip entry');
    final bd = ByteData.sublistView(_data);
    final lh = e.localOffset;
    if (lh < 0 || lh + 30 > _data.length || bd.getUint32(lh, Endian.little) != 0x04034b50) {
      throw OfficeDocException(OfficeDocError.damaged, 'local header $n');
    }
    final start = lh + 30 + bd.getUint16(lh + 26, Endian.little) + bd.getUint16(lh + 28, Endian.little);
    final stop = start + e.compressedSize;
    if (stop > _data.length || e.compressedSize < 0) throw OfficeDocException(OfficeDocError.damaged, 'entry $n');
    final budget = OfficeLimits.maxTotalBytes - _readTotal;
    final limit = math.min(cap, budget);
    Uint8List out;
    var truncated = false;
    switch (e.method) {
      case 0:
        final len = stop - start;
        if (len > limit) {
          if (!truncate || limit < 0) throw OfficeDocException(OfficeDocError.tooLarge, n);
          out = Uint8List.fromList(Uint8List.sublistView(_data, start, start + limit));
          truncated = true;
        } else {
          out = Uint8List.fromList(Uint8List.sublistView(_data, start, stop));
        }
      case 8:
        final r = _inflate(start, stop, limit, n, truncate: truncate);
        out = r.bytes;
        truncated = r.truncated;
      default:
        throw OfficeDocException(OfficeDocError.unsupported, 'zip method ${e.method}');
    }
    _readTotal += out.length;
    return (bytes: out, truncated: truncated);
  }

  /// Распаковка deflate кусками с пределом [limit] на результат.
  ({Uint8List bytes, bool truncated}) _inflate(int start, int stop, int limit, String name,
      {required bool truncate}) {
    if (limit <= 0) {
      if (truncate) return (bytes: Uint8List(0), truncated: true);
      throw OfficeDocException(OfficeDocError.tooLarge, name);
    }
    final filter = RawZLibFilter.inflateFilter(raw: true);
    final out = BytesBuilder(copy: false);
    var total = 0;
    var full = false;
    // Кусок на входе маленький: распакованный кусок deflate бывает в 1000
    // раз больше сжатого, и проверка предела не должна запаздывать.
    const step = 16 * 1024;
    bool drain({bool end = false}) {
      while (true) {
        final List<int>? chunk;
        try {
          chunk = filter.processed(flush: false, end: end);
        } catch (e) {
          throw OfficeDocException(OfficeDocError.damaged, 'inflate $name');
        }
        if (chunk == null || chunk.isEmpty) return true;
        if (total + chunk.length > limit) {
          if (!truncate) throw OfficeDocException(OfficeDocError.tooLarge, name);
          out.add(chunk.sublist(0, limit - total));
          total = limit;
          full = true;
          return false;
        }
        out.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
        total += chunk.length;
      }
    }

    for (var i = start; i < stop && !full; i += step) {
      try {
        filter.process(_data, i, math.min(i + step, stop));
      } catch (e) {
        throw OfficeDocException(OfficeDocError.damaged, 'inflate $name');
      }
      if (!drain()) break;
    }
    if (!full) {
      try {
        drain(end: true);
      } on OfficeDocException catch (e) {
        // Хвост потока бывает обрезан (документ сохранён не до конца) —
        // распакованного хватает, это не причина не показывать.
        if (e.kind != OfficeDocError.damaged || total == 0) rethrow;
      }
    }
    return (bytes: out.takeBytes(), truncated: full);
  }

  /// Текст части: UTF-8 (UTF-16 — по метке порядка байтов), неверные
  /// последовательности — заменой, не ошибкой. [max] — только начало.
  String? readText(String name, {int? max}) {
    final Uint8List? b;
    if (max != null) {
      b = readHead(name, max)?.bytes;
    } else {
      b = read(name);
    }
    return b == null ? null : decodeText(b);
  }

  static String decodeText(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return utf8.decode(Uint8List.sublistView(b, 3), allowMalformed: true);
    }
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      final le = b[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < b.length; i += 2) {
        units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(b, allowMalformed: true);
  }

  /// Часть как дерево XML; null — нет такой. Не XML — [OfficeDocError.damaged].
  /// Для частей в десятки мегабайт (листы) лучше события
  /// (`parseEvents` из package:xml/xml_events.dart) по [readHead]: дерево
  /// занимает в памяти в разы больше самого текста.
  XmlDocument? readXml(String name) {
    final t = readText(name);
    if (t == null) return null;
    try {
      return XmlDocument.parse(t);
    } on XmlException catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, '$name: ${e.message}');
    }
  }

  /// Связи части OOXML: «word/document.xml» → «word/_rels/document.xml.rels»;
  /// «» — связи пакета (_rels/.rels). id → связь.
  Map<String, OfficeRel> rels(String part) {
    final slash = part.lastIndexOf('/');
    final relsName = slash < 0 ? '_rels/$part.rels' : '${part.substring(0, slash)}/_rels/${part.substring(slash + 1)}.rels';
    final XmlDocument? doc;
    try {
      doc = readXml(part.isEmpty ? '_rels/.rels' : relsName);
    } on OfficeDocException catch (e) {
      // Испорченные связи — без картинок и ссылок, но с текстом.
      if (e.kind == OfficeDocError.damaged) return const {};
      rethrow;
    }
    if (doc == null) return const {};
    final out = <String, OfficeRel>{};
    for (final r in doc.rootElement.childElements) {
      if (r.name.local != 'Relationship') continue;
      final id = r.getAttribute('Id') ?? '';
      final target = r.getAttribute('Target') ?? '';
      if (id.isEmpty || target.isEmpty) continue;
      final external = (r.getAttribute('TargetMode') ?? '').toLowerCase() == 'external';
      out[id] = OfficeRel(id, r.getAttribute('Type') ?? '', external ? target : resolveTarget(part, target),
          external: external);
    }
    return out;
  }

  /// Главная часть документа OOXML по связи officeDocument пакета
  /// («word/document.xml», «xl/workbook.xml», «ppt/presentation.xml»).
  String? officeDocumentPart() {
    for (final r in rels('').values) {
      if (!r.external && r.isType('officeDocument') && has(r.target)) return find(r.target);
    }
    return null;
  }

  /// MIME-тип OpenDocument из записи «mimetype»
  /// («application/vnd.oasis.opendocument.text» …); null — не OpenDocument.
  String? get odfMimeType {
    final b = read('mimetype', max: 256);
    if (b == null) return null;
    return latin1.decode(b).trim();
  }

  /// OpenDocument с паролем: части зашифрованы, в манифесте —
  /// manifest:encryption-data.
  bool get odfEncrypted {
    final t = readText('META-INF/manifest.xml');
    return t != null && t.contains('encryption-data');
  }

  /// Картинка [name], если её можно показать и она укладывается в пределы
  /// ([OfficeLimits.maxImageBytes], [OfficeLimits.maxImagesTotal]); иначе null
  /// (EMF/WMF, слишком большая, нет такой части, повреждена).
  OfficeImage? image(String name) {
    final size = declaredSize(name);
    if (size == null) return null;
    if (_imagesTotal >= OfficeLimits.maxImagesTotal) return null;
    try {
      final cap = math.min(OfficeLimits.maxImageBytes, OfficeLimits.maxImagesTotal - _imagesTotal);
      final b = read(name, max: cap);
      if (b == null) return null;
      final mime = OfficeImage.sniff(b);
      if (mime == null) return null;
      _imagesTotal += b.length;
      return OfficeImage(mime, b);
    } on OfficeDocException catch (e) {
      // Слишком большая или испорченная картинка — без неё, но документ
      // показывается; пределы всего документа — по-прежнему ошибка.
      if (e.kind == OfficeDocError.tooLarge && _readTotal >= OfficeLimits.maxTotalBytes) rethrow;
      return null;
    }
  }
}

/// Обход XML документа по локальным именам: префиксы (w:, a:, text:) у
/// разных программ одни и те же, но пространства имён у «строгого» OOXML
/// (ISO 29500 Strict) другие — по локальному имени читаются оба варианта.
extension OfficeXml on XmlElement {
  String get local => name.local;

  /// Атрибут по локальному имени (w:val, r:id, text:style-name — «val»,
  /// «id», «style-name»). [ns] — часть адреса пространства имён, когда
  /// локальное имя неоднозначно («relationships» для r:id; у w:id — другое).
  String? attr(String local, {String? ns}) {
    for (final a in attributes) {
      if (a.name.local != local) continue;
      if (ns != null && !(a.name.namespaceUri ?? '').contains(ns)) continue;
      return a.value;
    }
    return null;
  }

  /// Дочерние элементы с локальным именем [local].
  Iterable<XmlElement> kids(String local) => childElements.where((e) => e.name.local == local);

  /// Первый дочерний элемент с локальным именем [local].
  XmlElement? kid(String local) {
    for (final e in childElements) {
      if (e.name.local == local) return e;
    }
    return null;
  }

  /// Первый потомок с локальным именем [local] (поиск в глубину, не глубже
  /// [OfficeLimits.maxDepth]).
  XmlElement? descendant(String local, {int depth = 0}) {
    if (depth > OfficeLimits.maxDepth) return null;
    for (final e in childElements) {
      if (e.name.local == local) return e;
      final d = e.descendant(local, depth: depth + 1);
      if (d != null) return d;
    }
    return null;
  }
}

// lib/services/mail/msg_reader.dart
// Письмо Outlook (.msg) — вложением письма или файлом — показывается как
// письмо, так же как .eml (1.12.x, просьба владельца 05.11.2026: «Msg делай
// сразу»). По открытым спецификациям Microsoft [MS-OXMSG] (устройство
// файла), [MS-OXPROPS] (номера свойств), [MS-OXRTFCP] (сжатие RTF «LZFu»)
// и [MS-OXRTFEX] (HTML внутри RTF) — Open Specification Promise; без
// сторонних библиотек. Контейнер — составной файл OLE (cfb_reader.dart с
// его пределами).
//
// Устройство: свойства письма — в потоке «__properties_version1.0»
// (номер и тип свойства, значение; у строк и двоичных — только длина, сами
// данные — в потоке «__substg1.0_ННННТТТТ»). Получатели — хранилища
// «__recip_version1.0_#…», вложения — «__attach_version1.0_#…»; вложенное
// письмо — хранилище «__substg1.0_3701000D» внутри вложения, того же
// устройства. Строки — UTF-16 (тип 001F) или 8-битные (001E) в кодовой
// странице письма (PidTagMessageCodepage, PidTagInternetCodepage).
//
// Что берётся: тема; отправитель — имя и SMTP-адрес (у адреса Exchange
// «/O=…» — SMTP из своих свойств или из заголовков письма); получатели
// «Кому» и «Копия» из хранилищ получателей (нет их — имена из Display To/
// Cc); дата отправки или получения; тело — HTML (PidTagHtml в кодировке
// письма), иначе сжатый RTF: HTML, вложенный Outlook'ом в RTF (\fromhtml1),
// или сам RTF, переведённый в HTML (rtf_reader.dart), иначе простой текст;
// вложения с именами, встроенные картинки — по Content-ID для «cid:» в
// HTML, вложенные письма — файлом .eml (открываются тем же просмотром).
// Пределы: вложенность писем — [maxDepth], получателей и вложений — по
// [maxItems], распакованный RTF — [OfficeLimits.maxPartBytes].

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/utils/charset_handler.dart';
import '../documents/cfb_reader.dart';
import '../documents/doc_codepages.dart';
import '../documents/office_package.dart';
import '../documents/rtf_reader.dart';
import 'eml_reader.dart';

class MsgReader {
  MsgReader._();

  /// Вложенных писем глубже — без них.
  static const maxDepth = 8;

  /// Получателей и вложений больше — остальные не показываются.
  static const maxItems = 1000;

  /// Встроенная картинка крупнее — обычным вложением (как у EmlReader).
  static const _maxInlineBytes = 3 * 1024 * 1024;

  /// Письмо Outlook: составной файл со свойствами письма.
  static bool isMsg(CfbFile cfb) =>
      cfb.hasStream('__properties_version1.0') &&
      cfb.root.children.any((e) => e.name.toLowerCase().startsWith('__substg1.0_'));

  /// Файл .msg по имени или типу из письма.
  static bool isMsgName(String fileName, {String? mimeType}) {
    final n = fileName.trim().toLowerCase();
    final mt = (mimeType ?? '').toLowerCase();
    return n.endsWith('.msg') || mt.contains('vnd.ms-outlook');
  }

  /// Разбор вне UI-изолята, если письмо крупное.
  static Future<EmlMessage> readAsync(Uint8List data, {String lang = 'en'}) async {
    if (kIsWeb || data.length < EmlReader.isolateThreshold) return read(data, lang: lang);
    try {
      return await Isolate.run(() => read(data, lang: lang));
    } on UnsupportedError {
      return read(data, lang: lang);
    }
  }

  /// Разобрать письмо. Ошибки — только [OfficeDocException]: не письмо
  /// Outlook или испорчено — [OfficeDocError.damaged], больше пределов —
  /// [OfficeDocError.tooLarge].
  static EmlMessage read(Uint8List data, {String lang = 'en'}) {
    try {
      final cfb = CfbFile.open(data);
      if (!isMsg(cfb)) throw const OfficeDocException(OfficeDocError.damaged, 'not a msg');
      return _Msg(cfb, cfb.root, 32, lang, 0, _Budget()).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, 'msg: $e');
    }
  }

  // ── Сжатый RTF ([MS-OXRTFCP]) ──

  /// Начало словаря LZFu — 207 знаков, которыми он заполнен до распаковки.
  static const _prebuf =
      '{\\rtf1\\ansi\\mac\\deff0\\deftab720{\\fonttbl;}{\\f0\\fnil \\froman \\fswiss \\fmodern '
      '\\fscript \\fdecor MS Sans SerifSymbolArialTimes New RomanCourier{\\colortbl\\red0\\green0\\blue0\r\n\\par '
      '\\pard\\plain\\f0\\fs20\\b\\i\\u\\tab\\tx';

  /// Распаковать PidTagRtfCompressed: «MELA» — без сжатия, «LZFu» — словарь
  /// 4096 байт. Объявленному размеру не верим: не больше [max]; испорчено —
  /// [FormatException].
  static Uint8List decompressRtf(Uint8List data, {int max = OfficeLimits.maxPartBytes}) {
    if (data.length < 16) throw const FormatException('short rtf');
    final bd = ByteData.sublistView(data);
    final raw = bd.getUint32(4, Endian.little);
    final type = bd.getUint32(8, Endian.little);
    final cap = math.min(raw, max);
    if (type == 0x414C454D) {
      return Uint8List.fromList(Uint8List.sublistView(data, 16, math.min(data.length, 16 + cap)));
    }
    if (type != 0x75465A4C) throw const FormatException('rtf compression');
    final dict = Uint8List(4096);
    for (var i = 0; i < _prebuf.length; i++) {
      dict[i] = _prebuf.codeUnitAt(i);
    }
    var w = _prebuf.length;
    final out = BytesBuilder(copy: false);
    final chunk = Uint8List(64 * 1024);
    var n = 0;
    var total = 0;
    void emit(int b) {
      chunk[n++] = b;
      if (n == chunk.length) {
        out.add(Uint8List.fromList(chunk));
        n = 0;
      }
      total++;
    }

    var p = 16;
    outer:
    while (p < data.length && total < cap) {
      final control = data[p++];
      for (var bit = 0; bit < 8; bit++) {
        if (total >= cap) break outer;
        if (control & (1 << bit) == 0) {
          if (p >= data.length) break outer;
          final b = data[p++];
          emit(b);
          dict[w] = b;
          w = (w + 1) & 0xFFF;
        } else {
          if (p + 1 >= data.length) break outer;
          final ref = (data[p] << 8) | data[p + 1];
          p += 2;
          final offset = ref >> 4;
          final len = (ref & 0xF) + 2;
          // Ссылка на текущее место записи — конец данных.
          if (offset == w) break outer;
          for (var k = 0; k < len && total < cap; k++) {
            final b = dict[(offset + k) & 0xFFF];
            emit(b);
            dict[w] = b;
            w = (w + 1) & 0xFFF;
          }
        }
      }
    }
    out.add(Uint8List.sublistView(chunk, 0, n));
    return out.takeBytes();
  }

  // ── HTML внутри RTF ([MS-OXRTFEX]) ──

  /// HTML, вложенный Outlook'ом в RTF (\fromhtml1): теги — в группах
  /// {\*\htmltag…}, текст — обычным текстом RTF, а то, что только для RTF,
  /// — между \htmlrtf и \htmlrtf0. null — RTF не из HTML.
  static String? htmlFromRtf(Uint8List rtf, {String lang = 'en'}) {
    final head = latin1.decode(Uint8List.sublistView(rtf, 0, math.min(rtf.length, 2048)), allowInvalid: true);
    if (!head.contains('\\fromhtml')) return null;
    final out = StringBuffer();
    var codePage = DocCodePages.forLanguage(lang);
    // Состояние группы: внутри тега, пропускать (служебная группа),
    // подавлено \htmlrtf; число знаков после \uN.
    final stack = <(bool tag, bool skip, bool rtfOnly, int uc)>[];
    var tag = false, skip = false, rtfOnly = false;
    var uc = 1;
    var pendingSkip = 0;
    var skipNextTag = -1;
    final bytes = <int>[];

    bool visible() => !skip && (tag || !rtfOnly);
    void flushBytes() {
      if (bytes.isEmpty) return;
      out.write(DocCodePages.decode(bytes, codePage));
      bytes.clear();
    }

    var i = 0;
    var depth = 0;
    while (i < rtf.length && out.length < OfficeLimits.maxPartBytes) {
      final c = rtf[i];
      if (c == 0x7B) {
        flushBytes();
        if (depth < OfficeLimits.maxDepth * 4) stack.add((tag, skip, rtfOnly, uc));
        depth++;
        i++;
        // Служебная группа {\*\назначение …}: теги HTML — показываются,
        // остальное — нет.
        if (i + 1 < rtf.length && rtf[i] == 0x5C && rtf[i + 1] == 0x2A) {
          var j = i + 2;
          while (j < rtf.length && (rtf[j] == 0x20 || rtf[j] == 0x0D || rtf[j] == 0x0A)) {
            j++;
          }
          if (j < rtf.length && rtf[j] == 0x5C) j++;
          final m = _word(rtf, j);
          if (m != null && (m.word == 'htmltag' || m.word == 'mhtmltag')) {
            final n = m.param ?? -1;
            if (m.word == 'mhtmltag') {
              skipNextTag = n;
              tag = true;
            } else if (n == skipNextTag && n >= 0) {
              // Тег с адресом файла после того же тега с «cid:» — второй раз
              // не нужен.
              skip = true;
              skipNextTag = -1;
            } else {
              tag = true;
              skipNextTag = -1;
            }
            i = m.end;
            if (i < rtf.length && rtf[i] == 0x20) i++;
          } else {
            skip = true;
            i = m?.end ?? j;
          }
        } else {
          final m = i < rtf.length && rtf[i] == 0x5C ? _word(rtf, i + 1) : null;
          if (m != null && const {'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object'}.contains(m.word)) {
            skip = true;
          }
        }
        continue;
      }
      if (c == 0x7D) {
        flushBytes();
        depth--;
        if (stack.isNotEmpty) (tag, skip, rtfOnly, uc) = stack.removeLast();
        i++;
        continue;
      }
      if (c == 0x5C && i + 1 < rtf.length) {
        final n = rtf[i + 1];
        if (n == 0x5C || n == 0x7B || n == 0x7D) {
          if (pendingSkip > 0) {
            pendingSkip--;
          } else if (visible()) {
            bytes.add(n);
          }
          i += 2;
          continue;
        }
        if (n == 0x27 && i + 3 < rtf.length) {
          final v = int.tryParse(latin1.decode(rtf.sublist(i + 2, i + 4)), radix: 16);
          i += 4;
          if (pendingSkip > 0) {
            pendingSkip--;
          } else if (v != null && visible()) {
            bytes.add(v);
          }
          continue;
        }
        final m = _word(rtf, i + 1);
        if (m == null) {
          i += 2;
          continue;
        }
        i = m.end;
        if (i < rtf.length && rtf[i] == 0x20) i++;
        switch (m.word) {
          case 'htmlrtf':
            rtfOnly = m.param != 0;
          case 'ansicpg':
            if (m.param != null && DocCodePages.known(m.param!)) codePage = m.param!;
          case 'uc':
            uc = (m.param ?? 1).clamp(0, 8);
          case 'u':
            flushBytes();
            if (visible() && m.param != null) out.writeCharCode(m.param! < 0 ? m.param! + 65536 : m.param!);
            pendingSkip = uc;
          case 'par' || 'line':
            if (visible()) {
              flushBytes();
              out.write('\r\n');
            }
          case 'tab':
            if (visible()) {
              flushBytes();
              out.write('\t');
            }
        }
        continue;
      }
      i++;
      if (c == 0x0D || c == 0x0A) continue;
      if (pendingSkip > 0) {
        pendingSkip--;
        continue;
      }
      if (visible()) bytes.add(c);
    }
    flushBytes();
    final html = out.toString();
    return html.trim().isEmpty ? null : html;
  }

  static ({String word, int? param, int end})? _word(Uint8List b, int at) {
    var i = at;
    while (i < b.length && ((b[i] >= 0x61 && b[i] <= 0x7A) || (b[i] >= 0x41 && b[i] <= 0x5A)) && i - at < 32) {
      i++;
    }
    if (i == at) return null;
    final word = latin1.decode(b.sublist(at, i));
    var j = i;
    if (j < b.length && b[j] == 0x2D) j++;
    while (j < b.length && b[j] >= 0x30 && b[j] <= 0x39 && j - i < 10) {
      j++;
    }
    final param = j > i ? int.tryParse(latin1.decode(b.sublist(i, j))) : null;
    return (word: word, param: param, end: j);
  }

  // ── Вложенное письмо — файлом .eml ──

  /// Письмо [m] в формате RFC 5322 (MIME): чтобы вложенное письмо Outlook
  /// открывалось тем же просмотром писем, что и .eml.
  static Uint8List toEml(EmlMessage m) {
    final out = StringBuffer();
    String enc(String s) {
      if (s.codeUnits.every((c) => c >= 0x20 && c < 0x7F)) return s;
      // Закодированные слова по 30 знаков: строка заголовка не длиннее 76.
      final parts = <String>[];
      final runes = s.runes.toList();
      for (var k = 0; k < runes.length; k += 30) {
        final piece = String.fromCharCodes(runes.sublist(k, math.min(runes.length, k + 30)));
        parts.add('=?UTF-8?B?${base64Encode(utf8.encode(piece))}?=');
      }
      return parts.join('\r\n ');
    }

    String addr(List<EmlAddress> list) => list
        .map(
          (a) => a.name.isEmpty || a.name == a.email
              ? (a.email.isEmpty ? enc(a.name) : '<${a.email}>')
              : '${enc(a.name.replaceAll('"', "'"))} <${a.email}>',
        )
        .join(',\r\n ');

    void b64(List<int> bytes) {
      final s = base64Encode(bytes);
      for (var k = 0; k < s.length; k += 76) {
        out.write('${s.substring(k, math.min(s.length, k + 76))}\r\n');
      }
    }

    if (m.from.isNotEmpty) out.write('From: ${addr(m.from)}\r\n');
    if (m.to.isNotEmpty) out.write('To: ${addr(m.to)}\r\n');
    if (m.cc.isNotEmpty) out.write('Cc: ${addr(m.cc)}\r\n');
    out.write('Subject: ${enc(m.subject)}\r\n');
    if (m.date != null) out.write('Date: ${_rfcDate(m.date!.toUtc())}\r\n');
    const boundary = '----=_ogneliss_msg_part';
    if (m.html == null && m.plain == null && m.inlineImages.isEmpty && m.attachments.isEmpty) {
      // Пустое письмо — простым текстом: «multipart» без частей читается
      // как странное вложение.
      out.write('MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n');
      return Uint8List.fromList(utf8.encode(out.toString()));
    }
    out.write('MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary="$boundary"\r\n\r\n');
    void part(String type, List<int> bytes, {String? name, String? cid, bool inline = false}) {
      out.write('--$boundary\r\nContent-Type: $type');
      if (name != null) out.write('; name="${enc(name)}"');
      out.write('\r\nContent-Transfer-Encoding: base64\r\n');
      if (cid != null) out.write('Content-ID: <$cid>\r\n');
      if (name != null) {
        out.write('Content-Disposition: ${inline ? 'inline' : 'attachment'}; filename="${enc(name)}"\r\n');
      }
      out.write('\r\n');
      b64(bytes);
    }

    if (m.html != null) part('text/html; charset=utf-8', utf8.encode(m.html!));
    if (m.plain != null && m.html == null) part('text/plain; charset=utf-8', utf8.encode(m.plain!));
    m.inlineImages.forEach((cid, uri) {
      final comma = uri.indexOf(',');
      final semi = uri.indexOf(';');
      if (comma < 0 || semi < 5) return;
      part(uri.substring(5, semi), base64Decode(uri.substring(comma + 1)), cid: cid);
    });
    for (final a in m.attachments) {
      part(a.contentType.isEmpty ? 'application/octet-stream' : a.contentType, a.bytes, name: a.name);
    }
    out.write('--$boundary--\r\n');
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  static String _rfcDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} ${d.year} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)} +0000';
  }
}

/// Байты вложений, которые письмо отдаёт наружу (с вложенными письмами,
/// перекодированными в .eml, — на каждом уровне заново): без предела
/// вложенность умножала бы один и тот же файл.
class _Budget {
  int left = 64 * 1024 * 1024;
  bool take(int n) {
    if (n > left) return false;
    left -= n;
    return true;
  }
}

/// Одно письмо: корень файла или вложенное (хранилище вложения).
class _Msg {
  _Msg(this.cfb, this.storage, this.headerSize, this.lang, this.depth, this.budget) {
    _props = _readProps(storage, headerSize);
  }

  final CfbFile cfb;
  final CfbEntry storage;
  final int headerSize;
  final String lang;
  final int depth;
  final _Budget budget;
  late final Map<int, int> _props;

  // Номера свойств ([MS-OXPROPS]).
  static const _subject = 0x0037;
  static const _senderName = 0x0C1A;
  static const _senderEmail = 0x0C1F;
  static const _senderType = 0x0C1E;
  static const _senderSmtp = 0x5D01;
  static const _reprName = 0x0042;
  static const _reprEmail = 0x0065;
  static const _reprType = 0x0064;
  static const _reprSmtp = 0x5D02;
  static const _displayTo = 0x0E04;
  static const _displayCc = 0x0E03;
  static const _submitTime = 0x0039;
  static const _deliveryTime = 0x0E06;
  static const _headers = 0x007D;
  static const _body = 0x1000;
  static const _html = 0x1013;
  static const _rtf = 0x1009;
  static const _internetCp = 0x3FDE;
  static const _messageCp = 0x3FFD;
  static const _recipType = 0x0C15;
  static const _displayName = 0x3001;
  static const _addrType = 0x3002;
  static const _email = 0x3003;
  static const _smtp = 0x39FE;
  static const _attachData = 0x3701;
  static const _attachFilename = 0x3704;
  static const _attachMethod = 0x3705;
  static const _attachLongName = 0x3707;
  static const _attachMime = 0x370E;
  static const _attachCid = 0x3712;

  /// Свойства постоянной длины: (номер << 16 | тип) → младшие 32 бита
  /// значения; время — отдельно (64 бита).
  final Map<int, int> _times = {};

  Map<int, int> _readProps(CfbEntry st, int header) {
    final out = <int, int>{};
    final e = st.child('__properties_version1.0');
    if (e == null || !e.isStream) return out;
    final b = cfb.readEntry(e, max: 4 * 1024 * 1024);
    final bd = ByteData.sublistView(b);
    for (var p = header; p + 16 <= b.length; p += 16) {
      final tag = bd.getUint32(p, Endian.little);
      final type = tag & 0xFFFF;
      if (type == 0x0040) {
        _times[tag >> 16] = bd.getInt64(p + 8, Endian.little);
      } else {
        out[tag] = bd.getUint32(p + 8, Endian.little);
      }
    }
    return out;
  }

  int? _int(int id) => _props[(id << 16) | 0x0003];

  int get _codePage {
    final cp = _int(_messageCp) ?? _int(_internetCp);
    if (cp != null && cp > 0) return cp;
    return DocCodePages.forLanguage(lang);
  }

  Uint8List? _stream(CfbEntry st, int id, int type) {
    String hex(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
    final e = st.child('__substg1.0_${hex(id)}${hex(type)}');
    if (e == null || !e.isStream) return null;
    return cfb.readEntry(e);
  }

  /// Строка свойства [id] хранилища [st]: UTF-16 или 8-битная в кодовой
  /// странице письма.
  String? _string(int id, [CfbEntry? st]) {
    final s = st ?? storage;
    final w = _stream(s, id, 0x001F);
    if (w != null) return _trimNul(_utf16(w));
    final a = _stream(s, id, 0x001E);
    if (a != null) return _trimNul(_decode(a, _codePage));
    return null;
  }

  static String _trimNul(String s) {
    var end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return s.substring(0, end);
  }

  static String _utf16(Uint8List b) {
    final units = Uint16List(b.length ~/ 2);
    final bd = ByteData.sublistView(b);
    for (var i = 0; i < units.length; i++) {
      units[i] = bd.getUint16(i * 2, Endian.little);
    }
    return String.fromCharCodes(units);
  }

  /// Байты в кодовой странице Windows [cp] (65001 — UTF-8, 1200 — UTF-16,
  /// 20866 — KOI8-R, 28595 — ISO-8859-5, 125x и 874 — свои таблицы).
  static String _decode(Uint8List b, int cp) {
    switch (cp) {
      case 65001:
        return utf8.decode(b, allowMalformed: true);
      case 1200:
        return _utf16(b);
      case 20866 || 21866:
        return CharsetHandler.decode(b, 'koi8-r');
      case 28595:
        return CharsetHandler.decode(b, 'iso-8859-5');
      case 28591 || 20127:
        return latin1.decode(b, allowInvalid: true);
    }
    if (DocCodePages.known(cp)) return DocCodePages.decode(b, cp);
    // Неизвестная страница: UTF-8, если он правильный, иначе 1252.
    try {
      return utf8.decode(b);
    } on FormatException {
      return DocCodePages.decode(b, 1252);
    }
  }

  DateTime? _time(int id) {
    final ft = _times[id];
    if (ft == null || ft <= 0) return null;
    // FILETIME: сотни наносекунд от 1601 года.
    final us = ft ~/ 10 - 11644473600000000;
    if (us < -62135596800000000 || us > 253402300799000000) return null;
    return DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
  }

  List<CfbEntry> _storages(String prefix) {
    final list = storage.children.where((e) => e.isStorage && e.name.toLowerCase().startsWith(prefix)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list.length > MsgReader.maxItems ? list.sublist(0, MsgReader.maxItems) : list;
  }

  EmlMessage read() {
    final headers = _string(_headers);
    EmlMessage? fromHeaders;
    if (headers != null && headers.trim().isNotEmpty) {
      try {
        fromHeaders = EmlReader.parse(Uint8List.fromList(utf8.encode('${headers.trim()}\r\n\r\n')));
      } catch (_) {
        fromHeaders = null;
      }
    }

    // Отправитель.
    final name = _string(_senderName) ?? _string(_reprName) ?? '';
    String? email = _string(_senderSmtp) ?? _string(_reprSmtp);
    if (email == null) {
      final type = (_string(_senderType) ?? '').toUpperCase();
      final raw = _string(_senderEmail);
      if (raw != null && (type == 'SMTP' || (type.isEmpty && raw.contains('@')))) email = raw;
    }
    if (email == null) {
      final type = (_string(_reprType) ?? '').toUpperCase();
      final raw = _string(_reprEmail);
      if (raw != null && type == 'SMTP') email = raw;
    }
    var from = <EmlAddress>[];
    if (email != null || name.isNotEmpty) {
      from = [EmlAddress(name, email ?? '')];
    }
    if ((email == null || email.isEmpty) && (fromHeaders?.from.isNotEmpty ?? false)) from = fromHeaders!.from;

    // Получатели.
    final to = <EmlAddress>[];
    final cc = <EmlAddress>[];
    final recips = _storages('__recip_version1.0_');
    for (final r in recips) {
      final props = _readProps(r, 8);
      final kind = props[(_recipType << 16) | 0x0003] ?? 1;
      final n = _string(_displayName, r) ?? '';
      var e = _string(_smtp, r);
      if (e == null) {
        final type = (_string(_addrType, r) ?? '').toUpperCase();
        final raw = _string(_email, r);
        if (raw != null && (type == 'SMTP' || raw.contains('@'))) e = raw;
      }
      final a = EmlAddress(n, e ?? '');
      if (n.isEmpty && (e ?? '').isEmpty) continue;
      if (kind == 2) {
        cc.add(a);
      } else if (kind == 1) {
        to.add(a);
      }
    }
    if (recips.isEmpty) {
      List<EmlAddress> names(String? s) => [
        for (final p in (s ?? '').split(';'))
          if (p.trim().isNotEmpty) EmlAddress(p.trim(), ''),
      ];
      to.addAll(fromHeaders?.to.isNotEmpty ?? false ? fromHeaders!.to : names(_string(_displayTo)));
      cc.addAll(fromHeaders?.cc.isNotEmpty ?? false ? fromHeaders!.cc : names(_string(_displayCc)));
    } else {
      // Адрес Exchange без SMTP — из заголовков, если там тот же человек.
      for (final list in [to, cc]) {
        for (var k = 0; k < list.length; k++) {
          if (list[k].email.isNotEmpty) continue;
          final hit = [...?fromHeaders?.to, ...?fromHeaders?.cc].where((h) => h.name == list[k].name);
          if (hit.isNotEmpty) list[k] = hit.first;
        }
      }
    }

    // Тело.
    final plain = _string(_body);
    String? html;
    final htmlBin = _stream(storage, _html, 0x0102);
    if (htmlBin != null) {
      html = _decode(htmlBin, _int(_internetCp) ?? _codePage);
    } else {
      html = _string(_html);
    }
    final inline = <String, String>{};
    if ((html == null || html.trim().isEmpty)) {
      final rtfZ = _stream(storage, _rtf, 0x0102);
      if (rtfZ != null) {
        try {
          final rtf = MsgReader.decompressRtf(rtfZ);
          html = MsgReader.htmlFromRtf(rtf, lang: lang);
          // Свой RTF (не из HTML и не из простого текста) — в HTML.
          if (html == null && !_fromText(rtf) && RtfReader.looksLikeRtf(rtf)) {
            final doc = RtfReader.read(rtf, lang: lang);
            if (!doc.isEmpty) {
              html = doc.html;
              inline.addAll({for (final e in doc.images.entries) e.key.toLowerCase(): e.value});
            }
          }
        } on FormatException {
          html = null;
        } on OfficeDocException catch (e) {
          if (e.kind == OfficeDocError.tooLarge) rethrow;
          html = null;
        }
      }
    }
    if (html != null && html.trim().isEmpty) html = null;

    // Вложения.
    final attachments = <EmlPart>[];
    final inlineNames = <String, String>{};
    var n = 0;
    for (final a in _storages('__attach_version1.0_')) {
      n++;
      final props = _readProps(a, 8);
      final method = props[(_attachMethod << 16) | 0x0003] ?? 1;
      final fileName =
          _string(_attachLongName, a) ?? _string(_attachFilename, a) ?? _string(_displayName, a) ?? 'attachment$n';
      final mime = (_string(_attachMime, a) ?? '').trim().toLowerCase();
      final cid = _normCid(_string(_attachCid, a));
      final obj = a.child('__substg1.0_3701000D');
      if (method == 5 || (obj != null && obj.isStorage && obj.child('__properties_version1.0') != null)) {
        if (obj == null || !obj.isStorage || depth + 1 > MsgReader.maxDepth) continue;
        try {
          final inner = _Msg(cfb, obj, 24, lang, depth + 1, budget).read();
          final title = inner.subject.trim().isEmpty ? fileName : inner.subject.trim();
          final eml = MsgReader.toEml(inner);
          if (budget.take(eml.length)) {
            attachments.add(EmlPart(name: '${_safeName(title)}.eml', contentType: 'message/rfc822', bytes: eml));
          }
        } on OfficeDocException catch (e) {
          if (e.kind == OfficeDocError.tooLarge) rethrow;
        }
        continue;
      }
      final data = _stream(a, _attachData, 0x0102);
      if (data == null || !budget.take(data.length)) continue;
      final type = mime.isNotEmpty ? mime : _mimeOf(fileName);
      if (cid != null && type.startsWith('image/') && data.length <= MsgReader._maxInlineBytes) {
        inline[cid] = 'data:$type;base64,${base64Encode(data)}';
        inlineNames[cid] = fileName;
        continue;
      }
      attachments.add(EmlPart(name: fileName, contentType: type, bytes: data));
    }

    // Картинки, на которые HTML не ссылается, — обычные вложения (как у
    // EmlReader): иначе вставленные «в тело» фотографии пропадали бы.
    var body = (html ?? '').toLowerCase();
    try {
      body = Uri.decodeFull(body);
    } catch (_) {}
    for (final k in inline.keys.where((k) => !body.contains(k)).toList()) {
      final uri = inline.remove(k)!;
      final comma = uri.indexOf(',');
      final mime = uri.substring(5, uri.indexOf(';'));
      attachments.add(
        EmlPart(name: inlineNames[k] ?? k, contentType: mime, bytes: base64Decode(uri.substring(comma + 1))),
      );
    }

    return EmlMessage(
      subject: (_string(_subject) ?? fromHeaders?.subject ?? '').trim(),
      from: from,
      to: to,
      cc: cc,
      date: _time(_submitTime) ?? _time(_deliveryTime) ?? fromHeaders?.date,
      html: html,
      plain: plain,
      attachments: attachments,
      inlineImages: inline,
    );
  }

  /// RTF, сделанный Outlook'ом из простого текста (\fromtext): тело — PidTagBody.
  static bool _fromText(Uint8List rtf) {
    final head = latin1.decode(Uint8List.sublistView(rtf, 0, math.min(rtf.length, 1024)), allowInvalid: true);
    return head.contains('\\fromtext');
  }

  static String? _normCid(String? raw) {
    if (raw == null) return null;
    var c = raw.trim();
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    c = c.trim().toLowerCase();
    return c.isEmpty ? null : c;
  }

  static String _safeName(String s) {
    final n = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    return n.length > 100 ? n.substring(0, 100) : n;
  }

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    final dot = n.lastIndexOf('.');
    final ext = dot < 0 ? '' : n.substring(dot + 1);
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'eml' => 'message/rfc822',
      'msg' => 'application/vnd.ms-outlook',
      _ => 'application/octet-stream',
    };
  }
}

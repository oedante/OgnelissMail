// lib/services/mail/eml_reader.dart
// Чтение вложенного письма (.eml, message/rfc822) для показа как письма.
//
// Прежде вложение .eml открывалось как текстовый файл: пользователь видел
// сырой MIME — заголовки Received, «=?koi8-r?B?…?=», quoted-printable.
// Здесь письмо разбирается enough_mail (кодировки, в том числе koi8-r и
// windows-1251, base64 и quoted-printable) в заголовки, тело, встроенные
// картинки и собственные вложения, а экран просмотра показывает его так же,
// как обычное письмо.
//
// Разбор — чистая функция над байтами: крупное письмо уходит в отдельный
// изолят, мелкое разбирается сразу (как MailBodyProcessor).

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Адрес из заголовка письма.
class EmlAddress {
  final String name;
  final String email;
  const EmlAddress(this.name, this.email);

  /// «Имя <адрес>» или только адрес.
  String get label {
    if (name.isEmpty || name == email) return email;
    if (email.isEmpty) return name;
    return '$name <$email>';
  }

  @override
  String toString() => label;
}

/// Вложение внутри письма.
class EmlPart {
  final String name;
  final String contentType;
  final Uint8List bytes;
  const EmlPart({required this.name, required this.contentType, required this.bytes});
}

/// Разобранное письмо.
class EmlMessage {
  final String subject;
  final List<EmlAddress> from;
  final List<EmlAddress> to;
  final List<EmlAddress> cc;
  final DateTime? date;
  final String? html;
  final String? plain;
  final List<EmlPart> attachments;

  /// Content-ID (без «<>», строчными) → data URI — для `cid:` в HTML.
  final Map<String, String> inlineImages;

  const EmlMessage({
    required this.subject,
    this.from = const [],
    this.to = const [],
    this.cc = const [],
    this.date,
    this.html,
    this.plain,
    this.attachments = const [],
    this.inlineImages = const {},
  });

  bool get hasBody => (html?.trim().isNotEmpty ?? false) || (plain?.trim().isNotEmpty ?? false);
}

class EmlReader {
  EmlReader._();

  /// Порог, после которого разбор уходит в отдельный изолят (байт).
  static const isolateThreshold = 64 * 1024;

  /// Встроенные картинки крупнее этого в data URI не превращаем: письмо
  /// показывается без них, а сами файлы остаются в списке вложений.
  static const _maxInlineBytes = 3 * 1024 * 1024;

  /// Похоже ли начало файла на письмо RFC 822 (для вложений без расширения
  /// .eml — так Exchange отдаёт вложенные письма).
  static bool looksLikeEml(Uint8List head) {
    final text = latin1.decode(head.length > 4096 ? head.sublist(0, 4096) : head, allowInvalid: true);
    final end = text.indexOf(RegExp(r'\r?\n\r?\n'));
    final headers = (end < 0 ? text : text.substring(0, end)).toLowerCase();
    // Заголовки начинаются с первой строки — иначе это не письмо.
    if (!RegExp(r'^[a-z0-9-]+:').hasMatch(headers)) return false;
    bool has(String h) => RegExp('(^|\\n)$h:').hasMatch(headers);
    final mailHeaders = ['from', 'subject', 'date', 'to', 'message-id', 'mime-version', 'received']
        .where(has)
        .length;
    return mailHeaders >= 2;
  }

  /// Разбор вне UI-изолята, если письмо крупное.
  static Future<EmlMessage> parseAsync(Uint8List data) async {
    if (kIsWeb || data.length < isolateThreshold) return parse(data);
    try {
      return await Isolate.run(() => parse(data));
    } on UnsupportedError {
      return parse(data);
    }
  }

  static EmlMessage parse(Uint8List data) {
    final msg = MimeMessage.parseFromData(repairHeaders(data));

    String? html;
    String? plain;
    final attachments = <EmlPart>[];
    final inline = <String, String>{};
    var n = 0;

    void walk(MimePart part) {
      final type = part.mediaType;
      final children = part.parts;
      if (type.top == MediaToptype.multipart && children != null) {
        for (final c in children) {
          walk(c);
        }
        return;
      }
      final disposition = part.getHeaderContentDisposition()?.disposition;
      final isAttachment = disposition == ContentDisposition.attachment;
      final fileName = _fileName(part);
      final sub = type.sub;

      // Тело письма — первый text/html и первый text/plain, которые не
      // помечены вложением (тот же порядок, что у enough_mail).
      if (!isAttachment && fileName == null && type.top == MediaToptype.text) {
        if (sub == MediaSubtype.textHtml && html == null) {
          html = _text(part);
          return;
        }
        if (sub == MediaSubtype.textPlain && plain == null) {
          plain = _text(part);
          return;
        }
      }

      final bytes = _binary(part);
      if (bytes == null) return;

      // Встроенная картинка подписи или тела (cid:).
      final cid = _normCid(part.getHeaderValue('content-id'));
      if (cid != null && !isAttachment && type.top == MediaToptype.image) {
        if (bytes.length <= _maxInlineBytes) {
          inline[cid] = 'data:${type.text};base64,${base64Encode(bytes)}';
          return;
        }
      }

      n++;
      attachments.add(EmlPart(
        name: fileName ?? _defaultName(type, n),
        contentType: type.text,
        bytes: bytes,
      ));
    }

    walk(msg);

    // Картинки, на которые HTML не ссылается, — обычные вложения: иначе
    // фотографии, вставленные в письмо Outlook'ом «в тело», пропадали бы.
    var body = (html ?? '').toLowerCase();
    try {
      body = Uri.decodeFull(body);
    } catch (_) {}
    final unused = inline.keys.where((k) => !body.contains(k)).toList();
    for (final k in unused) {
      final uri = inline.remove(k)!;
      final comma = uri.indexOf(',');
      final mime = uri.substring(5, uri.indexOf(';'));
      n++;
      attachments.add(EmlPart(
        name: _defaultName(MediaType.fromText(mime), n),
        contentType: mime,
        bytes: base64Decode(uri.substring(comma + 1)),
      ));
    }

    return EmlMessage(
      subject: fix8bit((_safe(msg.decodeSubject) ?? '').trim()),
      from: _addresses(() => msg.from),
      to: _addresses(() => msg.to),
      cc: _addresses(() => msg.cc),
      date: _safeDate(msg),
      html: html,
      plain: plain,
      attachments: attachments,
      inlineImages: inline,
    );
  }

  // ─────────────────── закодированные слова, разрезанные переносом ───────────────────
  //
  // Некоторые почтовые шлюзы переносят длинные заголовки по ширине, не
  // глядя на границы закодированных слов RFC 2047 (замечание 12.10.2026,
  // письмо «RE: МТР с датами вовлечения…»):
  //   From: "=?utf8?Q?=D0=9C…=D1=82=D0=B
  //   \t5?=
  //   To: "=?utf8?Q?…=D0=B3=D0=B5?
  //   \t= =?utf8?Q?…
  // Перенос оказывался внутри «=D0=B5» или между «?» и «=» конца слова —
  // слово не раскодировалось: «Арт�5м», «Серге?  =?utf8?Q?=D0=B9…». Внутри
  // закодированного слова пробелов не бывает, поэтому перенос там —
  // артефакт: убираем его и собираем слово обратно. Только заголовки
  // письма, побайтно (latin1 сохраняет байты как есть).

  static final _ewStart = RegExp(r'=\?[A-Za-z0-9_\-*.:]+\?[QqBb]\?');

  /// Заголовки письма с восстановленными закодированными словами; без
  /// разрезанных слов — те же байты.
  static Uint8List repairHeaders(Uint8List data) {
    final scan = data.length > 512 * 1024 ? data.sublist(0, 512 * 1024) : data;
    final text = latin1.decode(scan);
    var end = text.indexOf('\r\n\r\n');
    if (end < 0) end = text.indexOf('\n\n');
    if (end < 0) return data;
    final head = text.substring(0, end);
    if (!head.contains('=?')) return data;
    final fixed = repairEncodedWords(head);
    if (fixed == head) return data;
    final b = BytesBuilder(copy: false)
      ..add(latin1.encode(fixed))
      ..add(Uint8List.sublistView(data, end));
    return b.takeBytes();
  }

  /// Перенос строки с отступом (CRLF или LF, затем пробелы/табуляции),
  /// начиная с [k]: индекс после него или [k], если переноса нет.
  static int _skipFold(String h, int k) {
    var j = k;
    if (j < h.length && h[j] == '\r') j++;
    if (j < h.length && h[j] == '\n') {
      j++;
      if (j < h.length && (h[j] == ' ' || h[j] == '\t')) {
        while (j < h.length && (h[j] == ' ' || h[j] == '\t')) {
          j++;
        }
        return j;
      }
    }
    return k;
  }

  static String repairEncodedWords(String h) {
    final out = StringBuffer();
    var i = 0;
    while (i < h.length) {
      final m = _ewStart.allMatches(h, i).firstOrNull;
      if (m == null) {
        out.write(h.substring(i));
        break;
      }
      out.write(h.substring(i, m.end));
      var j = m.end;
      final word = StringBuffer();
      var ok = false;
      while (j < h.length && j - m.end < 2000) {
        final c = h[j];
        if (c == '\r' || c == '\n') {
          final k = _skipFold(h, j);
          if (k == j) break; // конец заголовка — слово не закончено
          j = k;
          continue;
        }
        if (c == ' ' || c == '\t') break;
        if (c == '?') {
          final k = _skipFold(h, j + 1);
          if (k < h.length && h[k] == '=') {
            word.write('?=');
            j = k + 1;
            ok = true;
          }
          break;
        }
        word.write(c);
        j++;
      }
      if (ok) {
        out.write(word);
        i = j;
      } else {
        // Не закодированное слово (или испорчено иначе) — как было.
        i = m.end;
      }
    }
    return out.toString();
  }

  // ─────────────────────────── вспомогательное ───────────────────────────

  /// Заголовки «8 бит» (RFC 6532): Exchange кладёт во вложенное письмо
  /// тему и имена в UTF-8 без кодирования, а разбор MIME читает их как
  /// Latin-1 — «Ð¡ÐµÑ€Ð³ÐµÐ¹» вместо «Сергей» (владелец 28.10.2026).
  /// Строка только из символов до U+00FF, которая как байты — правильный
  /// UTF-8, раскодируется заново; иначе остаётся как есть.
  static String fix8bit(String s) {
    var high = false;
    for (final c in s.codeUnits) {
      if (c > 0xFF) return s;
      if (c >= 0x80) high = true;
    }
    if (!high) return s;
    try {
      return utf8.decode(latin1.encode(s));
    } catch (_) {
      return s;
    }
  }

  static String? _safe(String? Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  static DateTime? _safeDate(MimeMessage m) {
    try {
      return m.decodeDate()?.toLocal();
    } catch (_) {
      return null;
    }
  }

  static List<EmlAddress> _addresses(List<MailAddress>? Function() f) {
    try {
      return [
        for (final a in f() ?? const <MailAddress>[])
          EmlAddress(fix8bit((a.personalName ?? '').trim()), a.email.trim()),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String? _text(MimePart part) {
    try {
      return part.decodeContentText();
    } catch (_) {
      // Неизвестная кодировка: показываем как UTF-8 с заменой битых символов.
      final b = _binary(part);
      return b == null ? null : utf8.decode(b, allowMalformed: true);
    }
  }

  static Uint8List? _binary(MimePart part) {
    try {
      return part.decodeContentBinary();
    } catch (_) {
      return null;
    }
  }

  /// Имя файла: Content-Disposition filename, затем Content-Type name.
  /// Кириллица в именах приходит закодированной по RFC 2047.
  static String? _fileName(MimePart part) {
    try {
      final raw = part.getHeaderContentDisposition()?.filename ??
          part.getHeaderContentType()?.parameters['name'];
      if (raw == null) return null;
      var v = raw.trim();
      if (v.length > 1 && v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
      if (v.contains('=?')) v = MailCodec.decodeHeader(v) ?? v;
      v = fix8bit(v);
      v = v.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static String _defaultName(MediaType type, int n) {
    final t = type.text.toLowerCase();
    if (t == 'message/rfc822') return 'message_$n.eml';
    if (t == 'text/calendar') return 'invite_$n.ics';
    const ext = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'application/pdf': 'pdf',
      'text/plain': 'txt',
      'text/html': 'html',
    };
    return 'attachment_$n.${ext[t] ?? 'bin'}';
  }

  /// Content-ID к виду, в котором его ищет MailHtmlDocument: без «<>»,
  /// строчными.
  static String? _normCid(String? raw) {
    if (raw == null) return null;
    var c = raw.trim();
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    c = c.trim().toLowerCase();
    return c.isEmpty ? null : c;
  }
}

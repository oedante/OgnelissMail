// lib/services/search/attachment_text.dart
// Текст вложения для поиска (1.12.x, поиск по тексту вложений, просьба
// владельца 04.11.2026): письмо находится по слову, которое есть только во
// вложенном документе, таблице, презентации, текстовом файле или вложенном
// письме.
//
// Документы Office и OpenDocument разбирает тот же OfficeReader, что и
// предпросмотр (по содержимому, а не по расширению; в своём изоляте с
// пределом времени и пределами OfficeLimits), — новые форматы, добавленные
// туда, ищутся без изменений здесь. Из результата берётся только текст:
// абзацы документа (HTML → текст), ячейки таблицы строка за строкой, надписи
// слайдов. Текстовые файлы, HTML и вложенные письма (.eml) читаются здесь.
// PDF (1.15.1) — свой разбор текста PDF (pdf_text.dart), без сторонних
// библиотек: по тексту страниц, и защищённые без пароля на открытие.
//
// Файл — из чужого письма: всё делается в отдельном изоляте ([extractFile]),
// который останавливается по пределу времени; текст — не длиннее
// [AttachmentText.maxChars], управляющие символы из него убраны (ими
// размечаются части текста вложений в поисковом индексе —
// attachment_text_index.dart).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/utils/text_safe.dart';
import '../documents/doc_sheets.dart';
import '../documents/doc_slides.dart' show OfficeSlidesDoc;
import '../documents/office_document.dart';
import '../documents/office_package.dart';
import '../documents/office_reader.dart';
import '../documents/pdf_text.dart';
import '../documents/text_doc_reader.dart';
import '../mail/eml_reader.dart';
import '../mail/msg_reader.dart';

/// Как читается вложение.
enum AttachmentTextKind {
  /// Документ, таблица, презентация — OfficeReader.
  office,

  /// Простой текст.
  text,

  /// Страница HTML.
  html,

  /// Вложенное письмо.
  eml,

  /// Без расширения: письмо (так Exchange отдаёт вложенные письма) или
  /// документ — по началу файла.
  sniff,

  /// PDF (1.15.1).
  pdf,
}

/// Извлечённый текст. [retryLater] — текста сейчас не получить, но позже
/// он может появиться (файла нет на месте; старый формат Office, который
/// эта версия ещё не читает): попытку не запоминать.
class ExtractedText {
  final String text;
  final bool retryLater;
  const ExtractedText(this.text, {this.retryLater = false});

  static const none = ExtractedText('');
  static const later = ExtractedText('', retryLater: true);
}

class AttachmentText {
  AttachmentText._();

  /// Текста с одного вложения — знаков (примерно 100 КБ).
  static const maxChars = 100 * 1024;

  /// Текста со всех вложений письма — знаков.
  static const maxMessageChars = 300 * 1024;

  /// Вложенное письмо крупнее — не читается (его вложения разбираются в
  /// памяти целиком).
  static const maxEmlBytes = 20 * 1024 * 1024;

  /// Глубина вложенных писем (письмо во вложении письма во вложении).
  static const maxDepth = 2;

  /// Предел времени изолята. Больше предела OfficeReader: тот сам
  /// останавливает свой изолят с разбором документа, а этот — только если
  /// зависло остальное (вложенное письмо).
  static const timeout = Duration(seconds: 45);

  static const _textExt = {
    'txt',
    'text',
    'log',
    'md',
    'markdown',
    'ini',
    'cfg',
    'conf',
    'json',
    'xml',
    'yaml',
    'yml',
    'ics',
    'vcf',
  };
  static const _htmlExt = {'htm', 'html', 'xhtml'};

  /// Как читать вложение [fileName] с MIME-типом [mimeType]; null — текста
  /// из такого файла не извлечь (картинки, архивы…).
  static AttachmentTextKind? kindOf(String fileName, {String? mimeType}) {
    final mtPdf = (mimeType ?? '').toLowerCase().split(';').first.trim();
    if (OfficeFormats.extOf(fileName) == 'pdf' || mtPdf == 'application/pdf' || mtPdf == 'application/x-pdf') {
      return AttachmentTextKind.pdf;
    }
    if (OfficeFormats.of(fileName, mimeType: mimeType) != null || OfficeFormats.isLegacy(fileName)) {
      return AttachmentTextKind.office;
    }
    final ext = OfficeFormats.extOf(fileName);
    final mt = (mimeType ?? '').toLowerCase().split(';').first.trim();
    // Письмо Outlook .msg (1.14.0) разбирается в то же письмо, что .eml.
    if (ext == 'eml' || mt == 'message/rfc822' || MsgReader.isMsgName(fileName, mimeType: mimeType)) {
      return AttachmentTextKind.eml;
    }
    if (_htmlExt.contains(ext)) return AttachmentTextKind.html;
    if (_textExt.contains(ext)) return AttachmentTextKind.text;
    if (ext.isEmpty || ext.length > 8) {
      if (mt == 'text/html') return AttachmentTextKind.html;
      if (mt.startsWith('text/')) return AttachmentTextKind.text;
      return AttachmentTextKind.sniff;
    }
    return null;
  }

  /// Текст файла [path] — в отдельном изоляте с пределом [timeout]. Ошибок
  /// не бросает: нечитаемый файл — пустой текст.
  static Future<ExtractedText> extractFile(String path, String fileName, {String? mimeType, String lang = 'en'}) async {
    if (kindOf(fileName, mimeType: mimeType) == null) return ExtractedText.none;
    final port = RawReceivePort();
    final done = Completer<Object?>();
    port.handler = (Object? m) {
      if (!done.isCompleted) done.complete(m);
    };
    Isolate? isolate;
    try {
      try {
        isolate = await Isolate.spawn(
          _work,
          (port.sendPort, path, fileName, mimeType, lang),
          onError: port.sendPort,
          onExit: port.sendPort,
          errorsAreFatal: true,
          debugName: 'attachment-text',
        );
      } on UnsupportedError {
        return await extractPath(path, fileName, mimeType: mimeType, lang: lang);
      }
      final r = await done.future.timeout(timeout);
      // null — изолят завершился без ответа (нехватка памяти), список —
      // необработанная ошибка: такой файл не пробуем снова.
      return r is ExtractedText ? r : ExtractedText.none;
    } on TimeoutException {
      isolate?.kill(priority: Isolate.immediate);
      return ExtractedText.none;
    } catch (_) {
      return ExtractedText.none;
    } finally {
      port.close();
    }
  }

  static Future<void> _work((SendPort, String, String, String?, String) m) async {
    ExtractedText r;
    try {
      r = await extractPath(m.$2, m.$3, mimeType: m.$4, lang: m.$5);
    } catch (_) {
      r = ExtractedText.none;
    }
    Isolate.exit(m.$1, r);
  }

  /// То же в текущем изоляте (тело [extractFile]; тесты).
  static Future<ExtractedText> extractPath(String path, String fileName, {String? mimeType, String lang = 'en'}) async {
    var kind = kindOf(fileName, mimeType: mimeType);
    if (kind == null) return ExtractedText.none;
    final file = File(path);
    final int len;
    try {
      len = file.lengthSync();
    } on FileSystemException {
      return ExtractedText.later;
    }
    if (kind == AttachmentTextKind.sniff) {
      final head = _head(file, 4096);
      kind = EmlReader.looksLikeEml(head)
          ? AttachmentTextKind.eml
          : (PdfText.looksLikePdf(head) ? AttachmentTextKind.pdf : AttachmentTextKind.office);
    }
    switch (kind) {
      case AttachmentTextKind.pdf:
        if (len > PdfText.maxBytes) return ExtractedText.none;
        return ExtractedText(clean(PdfText.extract(file.readAsBytesSync(), maxChars: maxChars)));
      case AttachmentTextKind.office:
      case AttachmentTextKind.sniff:
        try {
          final doc = await OfficeReader.readFile(path, fileName, mimeType: mimeType, lang: lang);
          return ExtractedText(textOfDoc(doc));
        } on OfficeDocException {
          // С 1.14.0 .doc/.xls/.ppt читаются; «legacy» — только Office 95 и
          // раньше, читателя для них не будет: текста нет.
          return ExtractedText.none;
        }
      case AttachmentTextKind.text:
        return ExtractedText(clean(_decode(_head(file, _textBytes), lang, len > _textBytes)));
      case AttachmentTextKind.html:
        return ExtractedText(htmlToText(_decode(_head(file, _htmlBytes), lang, len > _htmlBytes)));
      case AttachmentTextKind.eml:
        if (len > maxEmlBytes) return ExtractedText.none;
        return ExtractedText(textOfEml(_mail(file.readAsBytesSync(), fileName, mimeType, lang), lang: lang));
    }
  }

  /// Сколько читать от начала текстового файла и HTML: на [maxChars] знаков
  /// с запасом (кириллица в UTF-8 — два байта на знак, у HTML — разметка).
  static const _textBytes = maxChars * 4;
  static const _htmlBytes = 4 * 1024 * 1024;

  static Uint8List _head(File f, int n) {
    final raf = f.openSync();
    try {
      return raf.readSync(n);
    } finally {
      raf.closeSync();
    }
  }

  /// Вложенное письмо: .msg — читателем Outlook, остальное — как .eml.
  static EmlMessage _mail(Uint8List bytes, String fileName, String? mimeType, String lang) =>
      MsgReader.isMsgName(fileName, mimeType: mimeType) ? MsgReader.read(bytes, lang: lang) : EmlReader.parse(bytes);

  // Та же кодировка, что в предпросмотре (UTF-8, 1251, KOI8-R, DOS 866).
  static String _decode(Uint8List b, String lang, bool truncated) =>
      TextDocReader.decode(b, lang: lang, truncated: truncated);

  // ─────────────────────────── из разобранного ───────────────────────────

  /// Текст разобранного документа: абзацы, ячейки строка за строкой,
  /// надписи слайдов.
  static String textOfDoc(OfficeDoc doc, {int max = maxChars}) {
    final out = _Out(max);
    if (doc is OfficeTextDoc) {
      out.add(htmlToText(doc.html, max: max));
    } else if (doc is OfficeSheetsDoc) {
      for (final s in doc.sheets) {
        if (out.full) break;
        out.line(s.name);
        List<DocCell>? prev;
        for (final row in s.rows) {
          if (out.full) break;
          // Повторённые строки ODS — один и тот же список: текст — один раз.
          if (row.isEmpty || identical(row, prev)) continue;
          prev = row;
          out.line(row.map((c) => c.text).where((t) => t.trim().isNotEmpty).join(' '));
        }
      }
    } else if (doc is OfficeSlidesDoc) {
      // Надписи образца и макета (колонтитулы, логотип) повторяются на
      // каждом слайде — в текст один раз.
      final seen = <String>{};
      for (final slide in doc.slides) {
        if (out.full) break;
        for (final shape in slide.shapes) {
          final t = shape.plainText.trim();
          if (t.isEmpty || !seen.add(t)) continue;
          out.line(t);
          if (out.full) break;
        }
      }
    }
    return out.result;
  }

  /// Вложенное письмо: тема, адреса, текст и текст его вложений (до
  /// [maxDepth] писем вглубь).
  static String textOfEml(EmlMessage m, {int max = maxChars, String lang = 'en', int depth = 1}) {
    final out = _Out(max);
    out.line(m.subject);
    for (final a in [...m.from, ...m.to, ...m.cc]) {
      out.line(a.label);
    }
    final plain = m.plain ?? '';
    out.line(plain.trim().isNotEmpty ? plain : htmlToText(m.html ?? '', max: max));
    for (final p in m.attachments) {
      if (out.full) break;
      out.line(textOfBytes(p.bytes, p.name, mimeType: p.contentType, lang: lang, depth: depth, max: out.left));
    }
    return out.result;
  }

  /// Текст вложения внутри вложенного письма — в текущем изоляте (он уже
  /// отдельный и с пределом времени).
  static String textOfBytes(
    Uint8List bytes,
    String fileName, {
    String? mimeType,
    String lang = 'en',
    int depth = 1,
    int max = maxChars,
  }) {
    if (max <= 0) return '';
    try {
      var kind = kindOf(fileName, mimeType: mimeType);
      if (kind == AttachmentTextKind.sniff) {
        final head = _cut(bytes, 4096);
        kind = EmlReader.looksLikeEml(head)
            ? AttachmentTextKind.eml
            : (PdfText.looksLikePdf(head) ? AttachmentTextKind.pdf : AttachmentTextKind.office);
      }
      switch (kind) {
        case null:
          return '';
        case AttachmentTextKind.pdf:
          return clean(PdfText.extract(bytes, maxChars: max), max: max);
        case AttachmentTextKind.text:
          return clean(_decode(_cut(bytes, _textBytes), lang, bytes.length > _textBytes), max: max);
        case AttachmentTextKind.html:
          return htmlToText(_decode(_cut(bytes, _htmlBytes), lang, bytes.length > _htmlBytes), max: max);
        case AttachmentTextKind.eml:
          if (depth >= maxDepth || bytes.length > maxEmlBytes) return '';
          return textOfEml(_mail(bytes, fileName, mimeType, lang), max: max, lang: lang, depth: depth + 1);
        case AttachmentTextKind.office:
        case AttachmentTextKind.sniff:
          if (bytes.length > OfficeLimits.maxFileBytes) return '';
          return textOfDoc(
            OfficeReader.readBytes(bytes, fileName, mimeType: mimeType, lang: lang),
            max: max,
          );
      }
    } catch (_) {
      // Повреждённая часть вложенного письма — без её текста.
      return '';
    }
  }

  static Uint8List _cut(Uint8List b, int n) => b.length > n ? Uint8List.sublistView(b, 0, n) : b;

  // ─────────────────────────── HTML и чистка ───────────────────────────

  static const _blockTags = {
    'p',
    'div',
    'br',
    'li',
    'ul',
    'ol',
    'tr',
    'td',
    'th',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'caption',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'blockquote',
    'pre',
    'section',
    'article',
    'header',
    'footer',
    'dt',
    'dd',
    'dl',
    'figcaption',
    'address',
    'center',
  };
  static const _skipTags = {'script', 'style', 'head', 'title', 'template', 'noscript', 'svg', 'object'};

  /// HTML → текст за один проход: блоки — с новой строки, строчные теги
  /// (фрагменты слова с разным оформлением) — без пробела, сущности —
  /// знаками; скрипты, стили, комментарии — без текста.
  static String htmlToText(String html, {int max = maxChars}) {
    final out = StringBuffer();
    final n = html.length;
    var i = 0;
    var text = 0;
    void emit(String s) {
      out.write(s);
      text += s.length;
    }

    while (i < n && text < max * 2) {
      final lt = html.indexOf('<', i);
      final end = lt < 0 ? n : lt;
      if (end > i) emit(cleanPreviewText(html.substring(i, end)));
      if (lt < 0) break;
      if (html.startsWith('<!--', lt)) {
        final c = html.indexOf('-->', lt + 4);
        i = c < 0 ? n : c + 3;
        continue;
      }
      // «<» не перед буквой, «/», «!» или «?» — знак в тексте («a < b»).
      final next = lt + 1 < n ? html.codeUnitAt(lt + 1) | 0x20 : 0;
      if (!((next >= 0x61 && next <= 0x7A) || next == 0x2F || next == 0x21 || next == 0x3F)) {
        emit('<');
        i = lt + 1;
        continue;
      }
      final gt = html.indexOf('>', lt + 1);
      if (gt < 0) break;
      final name = _tagName(html, lt + 1, gt);
      i = gt + 1;
      if (name == null) continue;
      if (_skipTags.contains(name) && html.codeUnitAt(lt + 1) != 0x2F && html.codeUnitAt(gt - 1) != 0x2F) {
        // До закрывающего тега; незакрытый — до конца.
        final close = _indexOfIgnoreCase(html, '</$name', i);
        if (close < 0) break;
        final g = html.indexOf('>', close);
        i = g < 0 ? n : g + 1;
        continue;
      }
      if (_blockTags.contains(name)) emit('\n');
    }
    return clean(out.toString(), max: max);
  }

  /// Имя тега строчными буквами («/p» → «p»); null — не тег (объявление,
  /// «<» в тексте).
  static String? _tagName(String s, int from, int to) {
    var i = from;
    if (i < to && s.codeUnitAt(i) == 0x2F) i++;
    final start = i;
    while (i < to) {
      final c = s.codeUnitAt(i) | 0x20;
      final digit = s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39;
      if (!((c >= 0x61 && c <= 0x7A) || (digit && i > start))) break;
      i++;
    }
    if (i == start) return null;
    return s.substring(start, i).toLowerCase();
  }

  static int _indexOfIgnoreCase(String s, String needle, int from) {
    final lower = needle.toLowerCase();
    var i = from;
    while (true) {
      i = s.indexOf('<', i);
      if (i < 0 || i + lower.length > s.length) return -1;
      if (s.substring(i, i + lower.length).toLowerCase() == lower) return i;
      i++;
    }
  }

  static final _ctl = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F￾￿]');
  static final _hspace = RegExp(r'[ \t  -​  　]+');
  static final _newlines = RegExp(r'\s*[\r\n  ]\s*');

  /// Текст для индекса: без управляющих символов (ими размечен текст
  /// вложений в индексе), пробелы подряд — одним, пустые строки убраны, не
  /// длиннее [max] знаков без разрыва суррогатной пары.
  static String clean(String s, {int max = maxChars}) {
    var t = s.length > max * 2 ? cutSafe(s, max * 2) : s;
    t = fixUtf16(t).replaceAll(_ctl, ' ').replaceAll(_hspace, ' ').replaceAll(_newlines, '\n').trim();
    return cutSafe(t, max);
  }
}

/// Текст с пределом длины: строки через перевод строки.
class _Out {
  _Out(this.max);
  final int max;
  final StringBuffer _b = StringBuffer();

  bool get full => _b.length >= max;
  int get left => max - _b.length;

  void line(String s) {
    if (full) return;
    final t = AttachmentText.clean(s, max: left);
    if (t.isEmpty) return;
    if (_b.isNotEmpty) _b.write('\n');
    _b.write(t);
  }

  void add(String s) => line(s);

  String get result => cutSafe(_b.toString(), max);
}

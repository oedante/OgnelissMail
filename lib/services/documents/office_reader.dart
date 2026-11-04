// lib/services/documents/office_reader.dart
// Разбор документа для просмотра вложений (1.11.x, предпросмотр документов
// Office, план владельца 04.11.2026): какой это на самом деле формат и
// какой читатель его разбирает.
//
// Формат определяется по содержимому, а не только по расширению: файл из
// письма бывает назван неправильно («отчёт.doc», который на деле RTF или
// DOCX; таблица OpenDocument с расширением .xlsx). Расширение — подсказка,
// решает начало файла (ZIP, OLE, «{\rtf») и устройство пакета (запись
// mimetype у OpenDocument, главная часть у Office Open XML).
//
// Разбор идёт в отдельном изоляте с пределом времени: документ из чужого
// письма может быть сделан так, чтобы разбор шёл бесконечно долго, — такой
// изолят просто останавливается ([readFile]), а экран предлагает открыть
// файл в другом приложении. Пределы памяти — OfficeLimits.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'csv_reader.dart';
import 'docx_reader.dart';
import 'odp_reader.dart';
import 'ods_reader.dart';
import 'odt_reader.dart';
import 'office_document.dart';
import 'office_package.dart';
import 'pptx_reader.dart';
import 'rtf_reader.dart';
import 'xlsx_reader.dart';

class OfficeReader {
  OfficeReader._();

  /// Сколько ждать разбора. Обычный документ разбирается за доли секунды,
  /// таблица в десятки мегабайт на медленном телефоне — за несколько секунд.
  static const timeout = Duration(seconds: 30);

  /// Начало файла — RTF.
  static bool isRtf(Uint8List head) =>
      head.length >= 5 && head[0] == 0x7B && head[1] == 0x5C && head[2] == 0x72 && head[3] == 0x74 && head[4] == 0x66;

  /// Показывается ли файл предпросмотром документа: известный формат по
  /// имени или MIME-типу, а старый .doc — если внутри на деле RTF или DOCX
  /// ([head] — начало файла; без него старые форматы — нет).
  static bool previews(String fileName, {String? mimeType, Uint8List? head}) {
    if (OfficeFormats.of(fileName, mimeType: mimeType) != null) return true;
    if (head == null || !OfficeFormats.isLegacy(fileName)) return false;
    return isRtf(head) || OfficeZip.isZip(head);
  }

  /// Разобрать файл [path] в отдельном изоляте. [lang] — язык приложения
  /// (разделители чисел и даты в таблицах, кодовая страница RTF и CSV без
  /// объявленной). Ошибки — только [OfficeDocException].
  static Future<OfficeDoc> readFile(String path, String fileName, {String? mimeType, String lang = 'en'}) async {
    final job = _Job(path, fileName, mimeType, lang);
    final port = RawReceivePort();
    final done = Completer<Object?>();
    port.handler = (Object? m) {
      if (!done.isCompleted) done.complete(m);
    };
    Isolate? isolate;
    try {
      try {
        isolate = await Isolate.spawn(_work, (port.sendPort, job),
            onError: port.sendPort, onExit: port.sendPort, errorsAreFatal: true, debugName: 'office-preview');
      } on UnsupportedError {
        return _readPath(job);
      }
      final r = await done.future.timeout(timeout);
      if (r is OfficeDoc) return r;
      if (r is OfficeDocException) throw r;
      // null — изолят завершился без ответа (нехватка памяти), список —
      // необработанная ошибка в изоляте.
      throw OfficeDocException(OfficeDocError.damaged, r == null ? 'no result' : '$r');
    } on TimeoutException {
      isolate?.kill(priority: Isolate.immediate);
      throw const OfficeDocException(OfficeDocError.tooLarge, 'timeout');
    } finally {
      port.close();
    }
  }

  static void _work((SendPort, _Job) msg) {
    Object result;
    try {
      result = _readPath(msg.$2);
    } on OfficeDocException catch (e) {
      result = e;
    } catch (e) {
      result = OfficeDocException(OfficeDocError.damaged, '$e');
    }
    // Без копирования: листы и картинки бывают десятками мегабайт.
    Isolate.exit(msg.$1, result);
  }

  static OfficeDoc _readPath(_Job j) {
    final f = File(j.path);
    final int len;
    try {
      len = f.lengthSync();
    } on FileSystemException {
      throw const OfficeDocException(OfficeDocError.damaged, 'no file');
    }
    final format = OfficeFormats.of(j.fileName, mimeType: j.mimeType);
    if (len > OfficeLimits.maxFileBytes) {
      // CSV — текст: начало большой выгрузки показать можно (первые строки),
      // остальное читатель отметит как «показано начало».
      if (format != OfficeFormat.csv) throw const OfficeDocException(OfficeDocError.tooLarge, 'file');
      final raf = f.openSync();
      try {
        return CsvReader.read(raf.readSync(OfficeLimits.maxFileBytes), fileName: j.fileName, lang: j.lang);
      } finally {
        raf.closeSync();
      }
    }
    return readBytes(f.readAsBytesSync(), j.fileName, mimeType: j.mimeType, lang: j.lang);
  }

  /// Разобрать документ из памяти (в изоляте вызывающего).
  static OfficeDoc readBytes(Uint8List bytes, String fileName, {String? mimeType, String lang = 'en'}) {
    final format = OfficeFormats.of(fileName, mimeType: mimeType);
    final legacy = OfficeFormats.isLegacy(fileName);
    if (format == OfficeFormat.csv) return CsvReader.read(bytes, fileName: fileName, lang: lang);
    if (isRtf(bytes)) return RtfReader.read(bytes, lang: lang);
    if (OfficeZip.isOle(bytes)) {
      // Составной файл OLE: у DOCX, XLSX, PPTX — документ с паролем на
      // открытие (EncryptedPackage), у остальных (.doc, переименованный в
      // .rtf или .odt) — старый формат Office.
      const ooxml = {OfficeFormat.docx, OfficeFormat.xlsx, OfficeFormat.pptx};
      throw OfficeDocException(ooxml.contains(format) && !legacy ? OfficeDocError.encrypted : OfficeDocError.legacy);
    }
    if (!OfficeZip.isZip(bytes)) {
      throw OfficeDocException(legacy ? OfficeDocError.legacy : OfficeDocError.damaged, 'not a package');
    }
    final zip = OfficeZip.open(bytes);
    switch (_packageFormat(zip) ?? format) {
      case OfficeFormat.docx:
        return DocxReader.read(zip);
      case OfficeFormat.xlsx:
        return XlsxReader.read(zip, lang: lang);
      case OfficeFormat.pptx:
        return PptxReader.read(zip);
      case OfficeFormat.odt:
        return OdtReader.read(zip);
      case OfficeFormat.ods:
        return OdsReader.read(zip, lang: lang);
      case OfficeFormat.odp:
        return OdpReader.read(zip);
      case OfficeFormat.csv:
      case OfficeFormat.rtf:
      case null:
        throw const OfficeDocException(OfficeDocError.unsupported, 'package');
    }
  }

  /// Формат по устройству пакета: mimetype у OpenDocument, главная часть у
  /// Office Open XML. null — не понять (тогда — по расширению).
  static OfficeFormat? _packageFormat(OfficeZip zip) {
    final mt = zip.odfMimeType;
    if (mt != null) {
      if (mt.startsWith('application/vnd.oasis.opendocument.text')) return OfficeFormat.odt;
      if (mt.startsWith('application/vnd.oasis.opendocument.spreadsheet')) return OfficeFormat.ods;
      if (mt.startsWith('application/vnd.oasis.opendocument.presentation')) return OfficeFormat.odp;
      return null;
    }
    final main = (zip.officeDocumentPart() ?? '').toLowerCase();
    if (main.startsWith('word/') || zip.has('word/document.xml')) return OfficeFormat.docx;
    if (main.startsWith('xl/') || zip.has('xl/workbook.xml')) return OfficeFormat.xlsx;
    if (main.startsWith('ppt/') || zip.has('ppt/presentation.xml')) return OfficeFormat.pptx;
    return null;
  }
}

class _Job {
  final String path;
  final String fileName;
  final String? mimeType;
  final String lang;
  const _Job(this.path, this.fileName, this.mimeType, this.lang);
}

// lib/services/documents/office_document.dart
// Документы Office и OpenDocument в просмотре вложений (1.11.x, план
// владельца 04.11.2026): какие форматы показываются и что получается после
// разбора.
//
// Разбор — свой, по открытым спецификациям форматов (ECMA-376 / ISO/IEC
// 29500 — Office Open XML; OASIS OpenDocument / ISO/IEC 26300; RTF 1.9.1;
// RFC 4180 — CSV; с 1.12.x и старые двоичные Office 97–2003 — [MS-CFB],
// [MS-DOC], [MS-XLS], [MS-PPT], [MS-ODRAW] по Open Specification Promise),
// без сторонних библиотек; патентные условия — в docs/LICENSING.md. Только чтение: документ не меняется и не сохраняется,
// макросы не выполняются (их предпросмотр просто не читает).
//
// Что получается:
//  · текстовый документ (DOCX, ODT, RTF, DOC) — HTML ([OfficeTextDoc]): его
//    показывает то же защищённое окно, что и письмо (без JavaScript и сети,
//    очистка санитайзером, тёмная тема, масштаб), на компьютере — виджетами;
//  · таблица (XLSX, ODS, CSV, XLS) — листы ячеек (doc_sheets.dart), сеткой;
//  · презентация (PPTX, ODP, PPT) — слайды с фигурами (doc_slides.dart).

/// Формат документа по способу разбора. [doc], [xls], [ppt] — двоичные
/// Office 97–2003 (составной файл OLE): какой из трёх на самом деле, решает
/// содержимое файла (OfficeReader), а не расширение.
enum OfficeFormat { docx, odt, rtf, xlsx, ods, csv, pptx, odp, doc, xls, ppt }

/// Разобранный документ.
abstract class OfficeDoc {
  const OfficeDoc();

  /// Показана только часть: документ больше пределов предпросмотра
  /// ([OfficeLimits]) — экран предлагает открыть его целиком в другом
  /// приложении.
  bool get truncated;
}

/// Текстовый документ — HTML для окна письма.
class OfficeTextDoc extends OfficeDoc {
  /// Фрагмент HTML (содержимое <body>, без <html> и <head>). При показе он
  /// проходит санитайзер (HtmlSanitizer.sanitizeKeepingStyles), поэтому
  /// оформление — встроенными стилями и тегами, которые тот оставляет
  /// (p, h1–h6, b/i/u/s, sub/sup, span style, table/tr/td colspan rowspan,
  /// ul/ol/li, a href, img, br, hr).
  final String html;

  /// Картинки документа: ключ → data URI. В HTML — `<img src="cid:ключ">`,
  /// как встроенные картинки письма (MailHtmlDocument.build подставляет их
  /// после очистки; на компьютере — DesktopMailBody.images).
  final Map<String, String> images;

  @override
  final bool truncated;

  const OfficeTextDoc(this.html, {this.images = const {}, this.truncated = false});

  bool get isEmpty => html.trim().isEmpty;
}

class OfficeFormats {
  OfficeFormats._();

  static const _byExt = {
    // Word: документ, с макросами, шаблоны.
    'docx': OfficeFormat.docx, 'docm': OfficeFormat.docx, 'dotx': OfficeFormat.docx, 'dotm': OfficeFormat.docx,
    'odt': OfficeFormat.odt, 'ott': OfficeFormat.odt,
    'rtf': OfficeFormat.rtf,
    'xlsx': OfficeFormat.xlsx, 'xlsm': OfficeFormat.xlsx, 'xltx': OfficeFormat.xlsx, 'xltm': OfficeFormat.xlsx,
    'ods': OfficeFormat.ods, 'ots': OfficeFormat.ods,
    'csv': OfficeFormat.csv, 'tsv': OfficeFormat.csv,
    'pptx': OfficeFormat.pptx, 'pptm': OfficeFormat.pptx, 'ppsx': OfficeFormat.pptx, 'ppsm': OfficeFormat.pptx,
    'potx': OfficeFormat.pptx, 'potm': OfficeFormat.pptx,
    'odp': OfficeFormat.odp, 'otp': OfficeFormat.odp,
    // Office 97–2003 (1.12.x, просьба владельца 04.11.2026).
    'doc': OfficeFormat.doc, 'dot': OfficeFormat.doc,
    'xls': OfficeFormat.xls, 'xlt': OfficeFormat.xls,
    'ppt': OfficeFormat.ppt, 'pps': OfficeFormat.ppt, 'pot': OfficeFormat.ppt,
  };

  static const _byMime = {
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': OfficeFormat.docx,
    'application/vnd.ms-word.document.macroenabled.12': OfficeFormat.docx,
    'application/vnd.oasis.opendocument.text': OfficeFormat.odt,
    'application/rtf': OfficeFormat.rtf,
    'text/rtf': OfficeFormat.rtf,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': OfficeFormat.xlsx,
    'application/vnd.ms-excel.sheet.macroenabled.12': OfficeFormat.xlsx,
    'application/vnd.oasis.opendocument.spreadsheet': OfficeFormat.ods,
    'text/csv': OfficeFormat.csv,
    'text/tab-separated-values': OfficeFormat.csv,
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': OfficeFormat.pptx,
    'application/vnd.openxmlformats-officedocument.presentationml.slideshow': OfficeFormat.pptx,
    'application/vnd.ms-powerpoint.presentation.macroenabled.12': OfficeFormat.pptx,
    'application/vnd.oasis.opendocument.presentation': OfficeFormat.odp,
    'application/msword': OfficeFormat.doc,
    'application/vnd.ms-excel': OfficeFormat.xls,
    'application/vnd.ms-powerpoint': OfficeFormat.ppt,
  };

  /// Двоичные форматы Office 97–2003. С 1.12.x показываются (Word 97+,
  /// Excel 97+ — BIFF8, PowerPoint 97+); более старые версии (Word 6/95,
  /// Excel 5/95) — строкой «старый формат».
  static const legacyExt = {'doc', 'dot', 'xls', 'xlt', 'ppt', 'pps', 'pot'};

  static String extOf(String fileName) {
    final n = fileName.trim().toLowerCase();
    final dot = n.lastIndexOf('.');
    return dot < 0 || dot == n.length - 1 ? '' : n.substring(dot + 1);
  }

  /// Формат по имени файла, а без известного расширения — по MIME-типу из
  /// письма; null — не документ.
  static OfficeFormat? of(String fileName, {String? mimeType}) {
    final byExt = _byExt[extOf(fileName)];
    if (byExt != null) return byExt;
    final mt = (mimeType ?? '').toLowerCase().split(';').first.trim();
    return _byMime[mt];
  }

  /// Старый двоичный документ Office (по расширению).
  static bool isLegacy(String fileName) => legacyExt.contains(extOf(fileName));

  /// Текстовый документ, таблица, презентация.
  static bool isText(OfficeFormat f) =>
      f == OfficeFormat.docx || f == OfficeFormat.odt || f == OfficeFormat.rtf || f == OfficeFormat.doc;
  static bool isSheet(OfficeFormat f) =>
      f == OfficeFormat.xlsx || f == OfficeFormat.ods || f == OfficeFormat.csv || f == OfficeFormat.xls;
  static bool isSlides(OfficeFormat f) => f == OfficeFormat.pptx || f == OfficeFormat.odp || f == OfficeFormat.ppt;
}

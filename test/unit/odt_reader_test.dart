// Текстовый документ OpenDocument в просмотре вложений (1.11.x, предпросмотр
// документов, план владельца 04.11.2026): ODT → HTML. Образец —
// test/fixtures/office/text_sample.odt (тот же документ, что text_sample.docx,
// пересохранённый LibreOffice), враждебные файлы собираются здесь.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/services/documents/odt_reader.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';

const _ns =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" '
    'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
    'xmlns:loext="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0"';

const _png64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, data) {
    final f = ArchiveFile.bytes(name, data);
    if (name == 'mimetype') f.compression = CompressionType.none;
    a.add(f);
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Uint8List _pkg(
  String body, {
  String auto = '',
  String? styles,
  String mime = 'application/vnd.oasis.opendocument.text',
  String manifestExtra = '',
  Map<String, List<int>> extra = const {},
}) => _zip({
  'mimetype': utf8.encode(mime),
  'META-INF/manifest.xml': utf8.encode(
    '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">'
    '<manifest:file-entry manifest:full-path="content.xml">$manifestExtra</manifest:file-entry></manifest:manifest>',
  ),
  'content.xml': utf8.encode(
    '<office:document-content $_ns><office:automatic-styles>$auto</office:automatic-styles>'
    '<office:body><office:text>$body</office:text></office:body></office:document-content>',
  ),
  if (styles != null)
    'styles.xml': utf8.encode(
      '<office:document-styles $_ns><office:styles>$styles</office:styles></office:document-styles>',
    ),
  ...extra,
});

OfficeTextDoc _odt(String body, {String auto = '', String? styles, Map<String, List<int>> extra = const {}}) =>
    OdtReader.read(OfficeZip.open(_pkg(body, auto: auto, styles: styles, extra: extra)));

Matcher _kind(OfficeDocError k) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', k));

void main() {
  group('образец text_sample.odt (LibreOffice)', () {
    late OfficeTextDoc doc;
    setUpAll(() {
      doc = OdtReader.read(OfficeZip.open(File('test/fixtures/office/text_sample.odt').readAsBytesSync()));
    });

    test('заголовки и оформление', () {
      final h = doc.html;
      expect(doc.truncated, isFalse);
      expect(RegExp(r'<h1[^>]*>Отчёт о работе отдела</h1>').hasMatch(h), isTrue, reason: 'стиль Title — h1');
      expect(RegExp(r'<h1[^>]*>.*Списки').hasMatch(h), isTrue);
      expect(RegExp(r'<h2[^>]*>.*Таблица').hasMatch(h), isTrue);
      expect(h, contains('<span style="font-weight:bold">жирный</span>'));
      expect(h, contains('<span style="font-style:italic">курсив</span>'));
      expect(h, contains('text-decoration:underline">подчёркнутый'));
      expect(h, contains('color:#c00000">красный'));
      expect(h, contains('background-color:#ffff00">выделенный'));
      expect(h, contains('line-through">зачёркнутый'));
      expect(h, isNot(contains('font-family')));
    });

    test('списки по стилю списка: маркеры и номера уровней, без интервала между пунктами', () {
      final h = doc.html;
      for (final label in ['•', '◦', '1.', '1.1.', '1.2.', '2.']) {
        expect(h, contains('text-indent:0">$label\u00A0</span>'), reason: label);
      }
      expect(
        h,
        contains(
          '<p style="margin:0 0 0 36pt;text-indent:-18pt"><span style="display:inline-block;min-width:18pt;'
          'text-indent:0">•\u00A0</span>Первый пункт',
        ),
      );
      expect(h, isNot(contains('\uF0B7')));
    });

    test('таблица: объединения, заливка, рамки, ширины колонок', () {
      final h = doc.html;
      expect(h, contains('colspan="2"'));
      expect(h, contains('rowspan="2"'));
      expect(h, contains('background-color:#d9e2f3'));
      expect(h, contains('border-top:1px solid #000000'));
      expect(h, contains('width:33.333%'));
      final third = h.substring(h.lastIndexOf('<tr>'));
      expect('<td'.allMatches(third).length, 2);
    });

    test('картинка, ссылки, сноска, разрыв страницы; санитайзер и окно письма', () {
      final h = doc.html;
      expect(h, contains('<img src="cid:img1" width="32" height="32" alt="Клетка"'));
      expect(doc.images['img1'], startsWith('data:image/png;base64,'));
      expect(h, contains('<a href="https://example.org/">'));
      expect(h, contains('<a href="mailto:info@example.org">'));
      expect(h, contains('текст.<sup>1</sup>'));
      expect(h, contains('border-top:1px dashed'));
      expect(h.substring(h.lastIndexOf('<hr')), contains('<sup>1</sup> Данные условные.'));
      final clean = HtmlSanitizer.sanitizeKeepingStyles(h);
      expect(clean, contains('rowspan="2"'));
      expect(clean, contains('src="cid:img1"'));
      final built = MailHtmlDocument.build(clean, allowRemoteImages: false, inlineImages: doc.images);
      expect(built.html, contains('src="data:image/png;base64,'));
      expect(built.declaredWidth, isNull);
    });
  });

  group('содержимое', () {
    test('стили: по умолчанию, цепочка родителей, размер в %, пробелы ODF', () {
      final d = _odt(
        '<text:p text:style-name="P1">Обычный текст абзаца, его больше всего.</text:p>'
        '<text:p>  Два <text:span text:style-name="T1">крупный</text:span>  пробела<text:s text:c="3"/>три'
        '<text:tab/><text:tab/>таб<text:line-break/>строка</text:p>',
        auto:
            '<style:style style:name="P1" style:family="paragraph" style:parent-style-name="Body"/>'
            '<style:style style:name="T1" style:family="text"><style:text-properties fo:font-size="150%" '
            'fo:font-weight="bold" style:text-position="super 58%"/></style:style>',
        styles:
            '<style:default-style style:family="paragraph"><style:text-properties fo:font-size="12pt"/>'
            '</style:default-style>'
            '<style:style style:name="Body" style:family="paragraph"><style:paragraph-properties '
            'fo:margin-bottom="0.5cm" fo:text-align="justify" fo:text-indent="1.25cm"/></style:style>',
      );
      final h = d.html;
      expect(h, contains('<p style="margin:0 0 14.2pt 0;text-indent:35.4pt;text-align:justify">Обычный'));
      // Пробелы схлопываются, text:s — нет; две табуляции — один промежуток.
      expect(
        h,
        contains(
          'Два <sup><span style="font-weight:bold">крупный</span></sup> пробела\u00A0\u00A0\u00A0три'
          '\u2003\u2003таб<br>строка',
        ),
      );
    });

    test('нумерация заголовков по outline-style, продолжение списка, буквы', () {
      final d = _odt(
        '<text:h text:outline-level="1">Общие положения</text:h><text:h text:outline-level="2">Термины</text:h>'
        '<text:h text:outline-level="1">Порядок</text:h>'
        '<text:list text:style-name="L1"><text:list-item><text:p>первый</text:p></text:list-item></text:list>'
        '<text:p>между</text:p>'
        '<text:list text:style-name="L1" text:continue-numbering="true"><text:list-item><text:p>второй</text:p>'
        '<text:p>ещё абзац пункта</text:p></text:list-item><text:list-header><text:p>без номера</text:p>'
        '</text:list-header></text:list>'
        '<text:list text:style-name="L1"><text:list-item text:start-value="7"><text:p>заново</text:p></text:list-item>'
        '</text:list>',
        styles:
            '<text:outline-style style:name="Outline">'
            '<text:outline-level-style text:level="1" style:num-format="1" style:num-suffix="."/>'
            '<text:outline-level-style text:level="2" style:num-format="1" style:num-suffix="." text:display-levels="2"/>'
            '</text:outline-style>'
            '<text:list-style style:name="L1"><text:list-level-style-number text:level="1" style:num-format="а" '
            'style:num-suffix=")"><style:list-level-properties text:list-level-position-and-space-mode="label-alignment">'
            '<style:list-level-label-alignment fo:margin-left="1.27cm" fo:text-indent="-0.635cm"/>'
            '</style:list-level-properties></text:list-level-style-number></text:list-style>',
      );
      final h = d.html;
      expect(h, contains('>1. Общие положения</h1>'));
      expect(h, contains('>1.1. Термины</h2>'));
      expect(h, contains('>2. Порядок</h1>'));
      expect(h, contains('а)\u00A0</span>первый'));
      expect(h, contains('б)\u00A0</span>второй'));
      expect(h, contains('<p style="margin:0 0 0 36pt">ещё абзац пункта'));
      expect(h, contains('<p style="margin:0 0 0 36pt">без номера'));
      expect(h, contains('ж)\u00A0</span>заново'));
    });

    test('исправления, примечания, закладки и скрытый текст не показываются; поля — их текст', () {
      final d = _odt(
        '<text:tracked-changes><text:changed-region text:id="c1"><text:deletion><text:p>удалённое</text:p>'
        '</text:deletion></text:changed-region></text:tracked-changes>'
        '<text:p>Текст<text:change text:change-id="c1"/><office:annotation><text:p>примечание</text:p>'
        '</office:annotation> <text:bookmark text:name="x"/>дата: <text:date>04.11.2026</text:date>'
        '<text:span text:style-name="H">скрытое</text:span></text:p>',
        auto:
            '<style:style style:name="H" style:family="text"><style:text-properties text:display="none"/></style:style>',
      );
      final h = d.html;
      expect(h, contains('Текст дата: 04.11.2026'));
      expect(h, isNot(contains('удалённое')));
      expect(h, isNot(contains('примечание')));
      expect(h, isNot(contains('скрытое')));
    });

    test('рамки: картинка из пакета и встроенная, надпись; внешняя картинка не загружается; ссылки', () {
      final d = _odt(
        '<text:p>Рисунки: <draw:frame svg:width="1in" svg:height="0.5in"><draw:image xlink:href="Pictures/a.png"/>'
        '<svg:desc>Схема</svg:desc></draw:frame>'
        '<draw:frame svg:width="10mm" svg:height="10mm"><draw:image><office:binary-data>$_png64</office:binary-data>'
        '</draw:image></draw:frame>'
        '<draw:frame><draw:image xlink:href="https://tracker.example/p.png"/></draw:frame>'
        '<draw:frame><draw:text-box><text:p>Текст надписи</text:p></draw:text-box></draw:frame>'
        '<text:a xlink:href="javascript:alert(1)">опасная</text:a> <text:a xlink:href="https://example.org">сайт</text:a>'
        '</text:p>',
        extra: {'Pictures/a.png': base64Decode(_png64)},
      );
      final h = d.html;
      expect(h, contains('<img src="cid:img1" width="96" height="48" alt="Схема"'));
      expect(h, contains('<img src="cid:img2" width="38" height="38"'));
      expect(d.images.length, 2);
      expect(h, isNot(contains('tracker.example')));
      expect(h.indexOf('Текст надписи'), greaterThan(h.indexOf('сайт')));
      expect(h, contains('опасная'));
      expect('<a '.allMatches(h).length, 1);
      expect(h, contains('<a href="https://example.org">сайт</a>'));
    });

    test('без styles.xml и без mimetype — читается', () {
      final bytes = _zip({
        'content.xml': utf8.encode(
          '<office:document-content $_ns><office:body><office:text><text:p>Привет</text:p>'
          '</office:text></office:body></office:document-content>',
        ),
      });
      expect(OdtReader.read(OfficeZip.open(bytes)).html, contains('Привет'));
    });
  });

  group('враждебные и испорченные файлы', () {
    test('пароль (encryption-data в манифесте) — encrypted', () {
      final bytes = _pkg(
        '<text:p>x</text:p>',
        manifestExtra: '<manifest:encryption-data manifest:checksum-type="SHA1/1K"/>',
      );
      expect(() => OdtReader.read(OfficeZip.open(bytes)), _kind(OfficeDocError.encrypted));
    });

    test('таблица OpenDocument под видом .odt, не XML, нет content.xml — повреждён', () {
      expect(
        () => OdtReader.read(OfficeZip.open(_pkg('', mime: 'application/vnd.oasis.opendocument.spreadsheet'))),
        _kind(OfficeDocError.damaged),
      );
      final broken = _zip({
        'mimetype': utf8.encode('application/vnd.oasis.opendocument.text'),
        'content.xml': utf8.encode('<office:document-content $_ns><office:body><office:text><text:p <<< '),
      });
      expect(() => OdtReader.read(OfficeZip.open(broken)), _kind(OfficeDocError.damaged));
      expect(
        () =>
            OdtReader.read(OfficeZip.open(_zip({'mimetype': utf8.encode('application/vnd.oasis.opendocument.text')}))),
        _kind(OfficeDocError.damaged),
      );
    });

    test('огромные «повторы» колонок, строк и ячеек не раздуваются', () {
      final rows = _odt(
        '<table:table><table:table-column table:number-columns-repeated="16384"/>'
        '<table:table-row table:number-rows-repeated="1048576"><table:table-cell><text:p>я</text:p></table:table-cell>'
        '</table:table-row></table:table><text:p>после</text:p>'
        '<text:p>пробелы<text:s text:c="1000000000"/>конец</text:p>',
      );
      expect('<tr>'.allMatches(rows.html).length, 50);
      expect(rows.html, contains('после'));
      expect(rows.html, contains('конец'));
      expect(rows.html.length, lessThan(20000));
      final cells = _odt(
        '<table:table><table:table-row><table:table-cell table:number-columns-repeated="1048576">'
        '<text:p>я</text:p></table:table-cell></table:table-row></table:table>',
      );
      expect('<td'.allMatches(cells.html).length, 64);
    });

    test('глубокая вложенность списков и разделов — без переполнения стека', () {
      var x = '<text:p>дно</text:p>';
      for (var i = 0; i < 400; i++) {
        x = '<text:list><text:list-item>$x</text:list-item></text:list>';
      }
      var s = '<text:p>глубоко</text:p>';
      for (var i = 0; i < 400; i++) {
        s = '<text:section>$s</text:section>';
      }
      final d = _odt('$x$s<text:p>после</text:p>');
      expect(d.html, contains('после'));
    });

    test('огромный документ — начало, теги закрыты', () {
      final p = '<text:p>${'Длинная строка документа OpenDocument с кириллицей. ' * 5}</text:p>';
      final d = _odt(p * 5000);
      expect(d.truncated, isTrue);
      expect(d.html, endsWith('</p>'));
      expect('<p'.allMatches(d.html).length, '</p>'.allMatches(d.html).length);
    });
  });
}

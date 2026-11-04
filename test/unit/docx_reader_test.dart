// Документ Word в просмотре вложений (1.11.x, предпросмотр документов, план
// владельца 04.11.2026): DOCX → HTML для окна письма. Образец —
// test/fixtures/office/text_sample.docx (tool/dev/office_fixtures/text_fixtures.py),
// враждебные файлы собираются здесь.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/services/documents/docx_reader.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, data) => a.add(ArchiveFile.bytes(name, data)));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

/// Документ из тела [body] (содержимое w:body) и, по желанию, стилей,
/// нумерации и связей.
OfficeTextDoc _docx(
  String body, {
  String? styles,
  String? numbering,
  String rels = '',
  Map<String, List<int>> extra = const {},
  String ns = _w,
}) {
  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/></Relationships>',
    ),
    'word/document.xml': utf8.encode(
      '<w:document xmlns:w="$ns" xmlns:r="$_r" '
      'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:v="urn:schemas-microsoft-com:vml"><w:body>$body</w:body></w:document>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rN" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
      '$rels</Relationships>',
    ),
    if (styles != null) 'word/styles.xml': utf8.encode('<w:styles xmlns:w="$ns">$styles</w:styles>'),
    if (numbering != null) 'word/numbering.xml': utf8.encode('<w:numbering xmlns:w="$ns">$numbering</w:numbering>'),
    ...extra,
  };
  return DocxReader.read(OfficeZip.open(_zip(files)));
}

String _p(String text, [String rpr = '', String ppr = '']) =>
    '<w:p>${ppr.isEmpty ? '' : '<w:pPr>$ppr</w:pPr>'}<w:r>${rpr.isEmpty ? '' : '<w:rPr>$rpr</w:rPr>'}'
    '<w:t xml:space="preserve">$text</w:t></w:r></w:p>';

Matcher _kind(OfficeDocError k) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', k));

void main() {
  group('образец text_sample.docx', () {
    late OfficeTextDoc doc;
    setUpAll(() {
      doc = DocxReader.read(OfficeZip.open(File('test/fixtures/office/text_sample.docx').readAsBytesSync()));
    });

    test('заголовки, оформление, кириллица', () {
      final h = doc.html;
      expect(doc.truncated, isFalse);
      expect(h, contains('<h1'));
      expect(h, contains('Отчёт о работе отдела'));
      expect(RegExp(r'<h1[^>]*>.*Списки', dotAll: true).hasMatch(h), isTrue);
      expect(RegExp(r'<h2[^>]*>.*Таблица').hasMatch(h), isTrue);
      expect(h, contains('<span style="font-weight:bold">жирный</span>'));
      expect(h, contains('<span style="font-style:italic">курсив</span>'));
      expect(h, contains('text-decoration:underline">подчёркнутый'));
      expect(h, contains('color:#c00000">красный'));
      expect(h, contains('background-color:#ffff00">выделенный'));
      expect(h, contains('line-through">зачёркнутый'));
      // Шрифт документа не задаётся, у «авто» текста нет цвета.
      expect(h, isNot(contains('font-family')));
      expect(h, isNot(contains('Calibri')));
    });

    test('списки: маркеры Symbol/Courier и номера в два уровня', () {
      final h = doc.html;
      // Номер — в рамке шириной с выступ, после него неразрывный пробел.
      for (final label in ['•', '◦', '1.', '1.1.', '1.2.', '2.']) {
        expect(h, contains('text-indent:0">$label\u00A0</span>'), reason: label);
      }
      expect(h.indexOf('1.2.\u00A0</span>Проверка'), greaterThan(h.indexOf('1.1.\u00A0</span>Сбор данных')));
      expect(h, contains('2.\u00A0</span>Выпуск'));
      expect(h, isNot(contains('\uF0B7')));
    });

    test('таблица: colspan, rowspan, заливка, рамки «Сетка таблицы»', () {
      final h = doc.html;
      expect(h, contains('colspan="2"'));
      expect(h, contains('rowspan="2"'));
      expect(h, contains('background-color:#d9e2f3'));
      expect(h, contains('border-top:1px solid #000000'));
      expect(h, contains('vertical-align:middle'));
      // «Февраль» — во второй строке объединения: ячейки «Период» там нет.
      final third = h.substring(h.lastIndexOf('<tr>'));
      expect(third, isNot(contains('Период')));
      expect('<td'.allMatches(third).length, 2);
      // Ширины — в %, не в px: окно письма не уменьшает документ.
      expect(h, contains('width:100%'));
      expect(h, isNot(contains(RegExp(r'width:\d+px'))));
    });

    test('картинка, ссылки, сноска, разрыв страницы, пустой абзац', () {
      final h = doc.html;
      expect(h, contains('<img src="cid:img1" width="32" height="32" alt="Клетка"'));
      expect(doc.images['img1'], startsWith('data:image/png;base64,'));
      expect(h, contains('<a href="https://example.org/">'));
      expect(h, contains('<a href="mailto:info@example.org">'));
      expect(h, contains('написать письмо'));
      expect(h, isNot(contains('HYPERLINK')));
      expect(h, contains('текст.<sup>1</sup>'));
      expect(h, contains('border-top:1px dashed'));
      expect(h, contains('&nbsp;</p>'));
      final notes = h.substring(h.lastIndexOf('<hr'));
      expect(notes, contains('<sup>1</sup> Данные условные.'));
    });

    test('переживает санитайзер и сборку окна письма; виджеты компьютера рисуют таблицу', () {
      final clean = HtmlSanitizer.sanitizeKeepingStyles(doc.html);
      expect(clean, contains('colspan="2"'));
      expect(clean, contains('rowspan="2"'));
      expect(clean, contains('src="cid:img1"'));
      expect(clean, contains('<span style="font-weight:bold">'));
      expect(clean, contains('href="https://example.org/"'));
      final built = MailHtmlDocument.build(clean, allowRemoteImages: false, inlineImages: doc.images);
      expect(built.html, contains('src="data:image/png;base64,'));
      expect(built.declaredWidth, isNull, reason: 'документ не шире экрана');
      expect(built.linkTexts['https://example.org/'], 'example.org');
      final native = buildNativeMailDesktop(clean);
      expect(native, isNotNull);
      expect(native!.blocks.any((b) => b.kind == NBlockKind.table), isTrue);
      expect(native.blocks.any((b) => b.spans.any((s) => s.image == 'cid:img1')), isTrue);
    });
  });

  group('содержимое', () {
    test('стили: цепочка basedOn, docDefaults, размер в em от основного, заголовок по outlineLvl', () {
      final d = _docx(
        '${_p('Основной текст абзаца, его больше всего.')}${_p('Крупно', '<w:sz w:val="56"/>')}'
        '${_p('Подзаголовок', '', '<w:pStyle w:val="Sub"/>')}${_p('Раздел', '', '<w:outlineLvl w:val="2"/>')}',
        styles:
            '<w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="28"/></w:rPr></w:rPrDefault></w:docDefaults>'
            '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
            '<w:style w:type="paragraph" w:styleId="Base"><w:name w:val="Base"/><w:rPr><w:i/><w:color w:val="00FF00"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Sub"><w:name w:val="Sub"/><w:basedOn w:val="Base"/><w:rPr><w:b/></w:rPr></w:style>',
      );
      final h = d.html;
      // Основной размер 14 pt — без font-size; 28 pt — вдвое крупнее.
      expect(h, contains('<p style="margin:0">Основной текст'));
      expect(h, contains('font-size:2em">Крупно'));
      expect(h, contains('font-weight:bold;font-style:italic;color:#00ff00">Подзаголовок'));
      expect(h, contains('<h3'));
    });

    test('поля: инструкция скрыта, результат виден; вложенное поле; простое поле', () {
      final d = _docx(
        '<w:p>'
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> IF </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>MERGEFIELD x</w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>внутри</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>Итог</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
        '<w:fldSimple w:instr=" HYPERLINK &quot;https://example.com/a b&quot; \\o &quot;подсказка&quot;">'
        '<w:r><w:t> ссылка</w:t></w:r></w:fldSimple>'
        '<w:fldSimple w:instr="HYPERLINK \\l &quot;_Toc1&quot;"><w:r><w:t> закладка</w:t></w:r></w:fldSimple>'
        '</w:p>',
      );
      expect(d.html, isNot(contains('IF')));
      expect(d.html, isNot(contains('MERGEFIELD')));
      expect(d.html, isNot(contains('внутри')));
      expect(d.html, contains('Итог'));
      expect(d.html, contains('<a href="https://example.com/a%20b"> ссылка</a>'));
      expect(d.html, contains(' закладка'));
      expect('<a '.allMatches(d.html).length, 1);
    });

    test('исправления: вставленное видно, удалённое и скрытое — нет; табуляция, разрывы, символы', () {
      final d = _docx(
        '<w:p><w:ins><w:r><w:t>новое</w:t></w:r></w:ins><w:del><w:r><w:delText>старое</w:delText></w:r></w:del>'
        '<w:r><w:rPr><w:vanish/></w:rPr><w:t>скрытое</w:t></w:r>'
        '<w:r><w:tab/><w:tab/><w:t>после</w:t><w:br/><w:t>строка</w:t><w:noBreakHyphen/>'
        '<w:sym w:font="Wingdings" w:char="F0E0"/><w:sym w:font="Symbol" w:char="F061"/></w:r>'
        '<w:r><w:rPr><w:caps/></w:rPr><w:t>заглавные</w:t></w:r>'
        '<w:r><w:rPr><w:rFonts w:ascii="Courier New"/></w:rPr><w:t>код</w:t></w:r></w:p>',
      );
      final h = d.html;
      expect(h, contains('новое'));
      expect(h, isNot(contains('старое')));
      expect(h, isNot(contains('скрытое')));
      // Две табуляции подряд — один промежуток.
      expect(h, contains('новое\u2003\u2003после<br>строка\u2011→α'));
      expect(h, contains('ЗАГЛАВНЫЕ'));
      expect(h, contains('font-family:monospace">код'));
    });

    test('mc:AlternateContent: Choice, а Fallback — только когда Choice пуст', () {
      final d = _docx(
        '<w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wp:inline>'
        '<wp:extent cx="9525" cy="9525"/><a:graphic><a:graphicData><w:txbxContent>${_p('в надписи')}</w:txbxContent>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></mc:Choice>'
        '<mc:Fallback><w:pict><v:shape><v:textbox><w:txbxContent>${_p('в надписи')}</w:txbxContent></v:textbox></v:shape>'
        '</w:pict></mc:Fallback></mc:AlternateContent></w:r><w:r><w:t>Текст абзаца</w:t></w:r></w:p>'
        '<w:p><mc:AlternateContent><mc:Choice Requires="w14"><w:r><w:t></w:t></w:r></mc:Choice>'
        '<mc:Fallback><w:r><w:t>запасной</w:t></w:r></mc:Fallback></mc:AlternateContent></w:p>',
      );
      expect('в надписи'.allMatches(d.html).length, 1);
      expect(d.html.indexOf('в надписи'), greaterThan(d.html.indexOf('Текст абзаца')));
      expect(d.html, contains('запасной'));
    });

    test('ссылки: только http, https, mailto; внешняя картинка не загружается; EMF — без картинки', () {
      final d = _docx(
        '<w:p><w:hyperlink r:id="rJ"><w:r><w:t>опасная</w:t></w:r></w:hyperlink>'
        '<w:hyperlink r:id="rF"><w:r><w:t>файл</w:t></w:r></w:hyperlink>'
        '<w:hyperlink w:anchor="x"><w:r><w:t>закладка</w:t></w:r></w:hyperlink>'
        '<w:r><w:drawing><wp:inline><wp:extent cx="95250" cy="95250"/><a:graphic><a:graphicData><a:blip r:embed="rExt"/>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
        '<w:r><w:drawing><wp:inline><wp:extent cx="95250" cy="95250"/><a:graphic><a:graphicData><a:blip r:embed="rEmf"/>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
        '<w:r><w:pict><v:shape style="width:30pt;height:15pt"><v:imagedata r:id="rPng"/></v:shape></w:pict></w:r></w:p>',
        rels:
            '<Relationship Id="rJ" Type="x/hyperlink" Target="javascript:alert(1)" TargetMode="External"/>'
            '<Relationship Id="rF" Type="x/hyperlink" Target="file:///etc/passwd" TargetMode="External"/>'
            '<Relationship Id="rExt" Type="x/image" Target="https://tracker.example/p.png" TargetMode="External"/>'
            '<Relationship Id="rEmf" Type="x/image" Target="media/a.emf"/>'
            '<Relationship Id="rPng" Type="x/image" Target="media/b.png"/>',
        extra: {
          'word/media/a.emf': [1, 0, 0, 0, 0x6C, 0, 0, 0, 0, 0, 0, 0],
          'word/media/b.png': _png,
        },
      );
      final h = d.html;
      expect(h, isNot(contains('<a ')));
      expect(h, contains('опасная'));
      expect(h, isNot(contains('tracker.example')));
      expect(d.images.length, 1);
      expect(h, contains('<img src="cid:img1" width="40" height="20"'));
    });

    test('нумерация: русские буквы, римские, начало с N, пункт без списка', () {
      final d = _docx(
        [
          for (final t in ['а', 'б'])
            '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>пункт $t</w:t></w:r></w:p>',
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>римский</w:t></w:r></w:p>',
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>с пяти</w:t></w:r></w:p>',
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="9"/></w:numPr></w:pPr><w:r><w:t>нет списка</w:t></w:r></w:p>',
        ].join(),
        numbering:
            '<w:abstractNum w:abstractNumId="0">'
            '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="russianLower"/><w:lvlText w:val="%1)"/>'
            '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
            '<w:lvl w:ilvl="1"><w:start w:val="3"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1.%2"/><w:suff w:val="space"/></w:lvl>'
            '</w:abstractNum>'
            '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
            '<w:num w:numId="2"><w:abstractNumId w:val="0"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride></w:num>',
      );
      final h = d.html;
      expect(h, contains('а)\u00A0</span>пункт а'));
      expect(h, contains('б)\u00A0</span>пункт б'));
      expect(h, contains('б.III римский'));
      expect(h, contains('д)\u00A0</span>с пяти'));
      expect(h, contains('<p style="margin:0">нет списка'));
    });

    test('строгий OOXML (ISO 29500 Strict): те же элементы в другом пространстве имён', () {
      final d = _docx(_p('Строгий', '<w:b w:val="true"/>'), ns: 'http://purl.oclc.org/ooxml/wordprocessingml/main');
      expect(d.html, contains('font-weight:bold">Строгий'));
    });

    test('пустой документ', () {
      final d = _docx('<w:sectPr/>');
      expect(d.isEmpty, isTrue);
      expect(d.truncated, isFalse);
    });
  });

  group('враждебные и испорченные файлы', () {
    test('не XML и нет главной части — повреждён', () {
      expect(
        () => DocxReader.read(
          OfficeZip.open(
            _zip({'word/document.xml': utf8.encode('<w:document xmlns:w="$_w"><w:body><w:p><<<w:t>текст</w:p>')}),
          ),
        ),
        _kind(OfficeDocError.damaged),
      );
      expect(
        () => DocxReader.read(OfficeZip.open(_zip({'a.txt': utf8.encode('привет')}))),
        _kind(OfficeDocError.damaged),
      );
      expect(
        () => DocxReader.read(
          OfficeZip.open(_zip({'word/document.xml': utf8.encode('<x:root xmlns:x="urn:x"><x:p/></x:root>')})),
        ),
        _kind(OfficeDocError.damaged),
      );
    });

    test('испорченные стили и нумерация — текст без них', () {
      final d = _docx(
        _p('Текст на месте', '', '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'),
        styles: '<w:style <<<',
        numbering: '<<<',
      );
      expect(d.html, contains('Текст на месте'));
    });

    test('глубокая вложенность таблиц и групп — без переполнения стека', () {
      var cell = _p('дно');
      for (var i = 0; i < 300; i++) {
        cell = '<w:tbl><w:tr><w:tc>$cell</w:tc></w:tr></w:tbl>';
      }
      var sdt = _p('глубоко');
      for (var i = 0; i < 300; i++) {
        sdt = '<w:sdt><w:sdtContent>$sdt</w:sdtContent></w:sdt>';
      }
      final d = _docx('$cell$sdt${_p('после')}');
      expect('<table'.allMatches(d.html).length, lessThanOrEqualTo(OfficeLimits.maxDepth));
      expect(d.html, contains('после'));
    });

    test('огромный документ — начало и «показано не всё»; закрывающие теги на месте', () {
      final para = _p('Строка большого документа с кириллицей и цифрами 1234567890. ' * 4);
      final body = StringBuffer();
      for (var i = 0; i < 4000; i++) {
        body.write(para);
        if (i % 500 == 0) body.write('<w:tbl><w:tr><w:tc>${_p('ячейка')}</w:tc></w:tr></w:tbl>');
      }
      final sw = Stopwatch()..start();
      final d = _docx(body.toString());
      sw.stop();
      expect(d.truncated, isTrue);
      expect(d.html.length, lessThan(OfficeLimits.maxTextWeight * 3));
      expect(d.html, endsWith('</p>'));
      expect('<p'.allMatches(d.html).length, '</p>'.allMatches(d.html).length);
      expect('<table'.allMatches(d.html).length, '</table>'.allMatches(d.html).length);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('огромная таблица — обрезается внутри неё', () {
      final row = '<w:tr><w:tc>${_p('ячейка таблицы с текстом')}</w:tc><w:tc>${_p('вторая')}</w:tc></w:tr>';
      final d = _docx(
        '<w:tbl><w:tblGrid><w:gridCol w:w="1000"/><w:gridCol w:w="1000"/></w:tblGrid>'
        '${row * 20000}</w:tbl>${_p('после таблицы')}',
      );
      expect(d.truncated, isTrue);
      expect(d.html, isNot(contains('после таблицы')));
      expect('<tr>'.allMatches(d.html).length, '</tr>'.allMatches(d.html).length);
    });

    test('огромные объявленные числа не раздувают вывод', () {
      final d = _docx(
        '<w:tbl><w:tblGrid><w:gridCol w:w="99999999999"/></w:tblGrid><w:tr><w:trPr>'
        '<w:gridBefore w:val="1000000"/></w:trPr><w:tc><w:tcPr><w:gridSpan w:val="1048576"/></w:tcPr>'
        '${_p('x', '<w:sz w:val="999999"/>', '<w:ind w:left="99999999" w:hanging="99999999"/>'
            '<w:spacing w:before="9999999"/>')}</w:tc></w:tr></w:tbl>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>н</w:t></w:r></w:p>',
        numbering:
            '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="100000"/>'
            '<w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%1%1%1%1%1%1%1%1%1"/></w:lvl></w:abstractNum>'
            '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>',
      );
      expect(d.html.length, lessThan(4000));
      expect(d.html, contains('colspan="64"'));
    });
  });
}

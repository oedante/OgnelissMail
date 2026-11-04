// Презентация ODP в просмотре вложения (1.11.x, предпросмотр документов,
// план владельца 04.11.2026): та же презентация, что slides.pptx, сохранённая
// LibreOffice, — слайды, стили образца, списки, картинка, таблица, группа,
// поворот, скрытый слайд; чужие и испорченные файлы — без падения и в пределах.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/odp_reader.dart';
import 'package:ogneliss/services/documents/office_package.dart';

DocShape _withText(DocSlide s, String text) => s.shapes.firstWhere((sh) => sh.plainText.contains(text));

const _ns =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" '
    'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
    'xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"';

const _mime = 'application/vnd.oasis.opendocument.presentation';

String _content(String pages, {String styles = ''}) =>
    '<office:document-content $_ns><office:automatic-styles>$styles</office:automatic-styles>'
    '<office:body><office:presentation>$pages</office:presentation></office:body></office:document-content>';

String _frame(String text, {String x = '1cm', String extra = ''}) =>
    '<draw:frame svg:x="$x" svg:y="1cm" svg:width="5cm" svg:height="2cm" $extra>'
    '<draw:text-box><text:p>$text</text:p></draw:text-box></draw:frame>';

Uint8List _odp(String? content, {String mime = _mime, String? manifest, String? styles}) {
  final a = Archive();
  void add(String name, String text) => a.add(ArchiveFile.bytes(name, utf8.encode(text)));
  add('mimetype', mime);
  if (content != null) add('content.xml', content);
  if (styles != null) add('styles.xml', styles);
  add('META-INF/manifest.xml', manifest ?? '<manifest:manifest/>');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

OfficeSlidesDoc _read(Uint8List bytes) => OdpReader.read(OfficeZip.open(bytes));

Matcher _kind(OfficeDocError k) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', k));

void main() {
  group('фикстура (slides.pptx, сохранённая LibreOffice)', () {
    final doc = OdpReader.read(OfficeZip.open(File('test/fixtures/office/slides.odp').readAsBytesSync()));

    test('размер из макета страницы образца, порядок, скрытый слайд пропущен', () {
      expect(doc.width, closeTo(720, 0.1));
      expect(doc.height, closeTo(540, 0.1));
      expect(doc.truncated, isFalse);
      expect(doc.slides, hasLength(6));
      final all = doc.slides.map((s) => s.shapes.map((sh) => sh.plainText).join('|')).join('\n');
      expect(all, contains('Квартальный отчёт'));
      expect(all, isNot(contains('Скрытый слайд')));
      // Заполнители образца («Click to edit…») не рисуются.
      expect(all, isNot(contains('Click to edit')));
    });

    test('заголовок: стиль заполнителя и рамка', () {
      final title = _withText(doc.slides[0], 'Квартальный отчёт');
      expect(title.x, closeTo(54, 0.1));
      expect(title.y, closeTo(167.8, 0.1));
      final run = title.text!.paragraphs.single.runs.single;
      expect(run.size, 44);
      expect(run.font, 'Calibri');
      expect(title.text!.anchor, DocAnchor.middle);
      expect(title.text!.paragraphs.single.align, DocAlign.center);
    });

    test('список структуры: уровни, маркеры, отступы', () {
      final ps = _withText(doc.slides[1], 'Выручка').text!.paragraphs;
      expect(ps.map((p) => p.text), [
        'Выручка выросла на 12 %',
        'Москва — плюс 15 %',
        'Новосибирск — плюс 9 %',
        'Новые клиенты: 48',
        'Планы на следующий год',
      ]);
      expect(ps.map((p) => p.level), [0, 1, 1, 0, 0]);
      expect(ps.map((p) => p.bullet?.text), ['•', '–', '–', '•', '•']);
      expect(ps.map((p) => p.runs.first.size), [32, 28, 28, 32, 32]);
      expect(ps[0].marginLeft, closeTo(27, 0.1));
      expect(ps[0].indent, closeTo(-27, 0.1));
      expect(ps[1].marginLeft, closeTo(58.5, 0.1));
    });

    test('картинка, фигуры, поворот draw:transform', () {
      final s = doc.slides[2];
      expect(s.shapes.where((sh) => sh.picture?.image.mime == 'image/png'), hasLength(1));
      final box = _withText(s, 'Оранжевая плашка');
      expect(box.geom, DocGeom.roundRect);
      expect(box.adjust, closeTo(0.16667, 0.001));
      expect(box.fill!.color, 0xFFE06C2A);
      expect(box.line!.color, 0xFF803010);
      expect(box.text!.paragraphs.single.runs.single.bold, isTrue);
      expect(box.text!.paragraphs.single.runs.single.color, 0xFFFFFFFF);
      expect(s.shapes.where((sh) => sh.geom == DocGeom.ellipse), hasLength(1));
      final tilted = _withText(s, 'Повёрнуто');
      expect(tilted.rotation, closeTo(30, 0.01));
      expect(tilted.x, closeTo(504, 0.2));
      expect(tilted.y, closeTo(270, 0.2));
      expect(tilted.w, closeTo(162, 0.2));
    });

    test('таблица: объединение и оформление ячеек', () {
      final t = doc.slides[3].shapes.firstWhere((sh) => sh.table != null).table!;
      expect(t.columns, hasLength(3));
      expect(t.columns.first, closeTo(216, 0.1));
      expect(t.rows, hasLength(4));
      expect(t.cells, hasLength(11));
      final head = t.cells.firstWhere((c) => c.row == 0 && c.col == 1);
      expect(head.colSpan, 2);
      expect(head.text!.paragraphs.single.text, 'Квартал');
      expect(head.fill!.color, 0xFF4F81BD);
      expect(head.top!.color, 0xFFFFFFFF);
      expect(t.cells.firstWhere((c) => c.row == 3 && c.col == 2).text!.paragraphs.single.text, '205');
    });

    test('группа (координаты детей — уже на слайде) и надпись без переноса', () {
      final s = doc.slides[4];
      expect(_withText(s, 'В группе').x, closeTo(47.3, 0.2));
      expect(s.shapes.firstWhere((sh) => sh.geom == DocGeom.ellipse).x, closeTo(342.5, 0.2));
      expect(_withText(s, 'Надпись вне группы').text!.wrap, isFalse);
    });

    test('фон слайда и образца', () {
      expect(doc.slides[5].background!.color, 0xFFFFF4D6);
      expect(doc.slides[0].background!.color, 0xFFFFFFFF);
    });
  });

  group('чужие и испорченные файлы', () {
    test('не презентация (mimetype) — повреждён; с паролем — encrypted', () {
      final ok = _content('<draw:page>${_frame('A')}</draw:page>');
      expect(() => _read(_odp(ok, mime: 'application/vnd.oasis.opendocument.text')), _kind(OfficeDocError.damaged));
      expect(
        () => _read(
          _odp(
            ok,
            manifest:
                '<manifest:manifest><manifest:file-entry manifest:full-path="content.xml">'
                '<manifest:encryption-data/></manifest:file-entry></manifest:manifest>',
          ),
        ),
        _kind(OfficeDocError.encrypted),
      );
    });

    test('нет content.xml или он не XML — повреждён', () {
      expect(() => _read(_odp(null)), _kind(OfficeDocError.damaged));
      expect(() => _read(_odp('<office:document-content')), _kind(OfficeDocError.damaged));
    });

    test('без styles.xml — слайды со своим оформлением, размер по умолчанию', () {
      final doc = _read(
        _odp(
          _content(
            '<draw:page>${_frame('Привет  <text:s text:c="3"/>мир')}</draw:page>'
            '<draw:page presentation:visibility="hidden">${_frame('Скрыт')}</draw:page>',
          ),
        ),
      );
      expect(doc.width, 720);
      expect(doc.slides, hasLength(1));
      final s = doc.slides.single.shapes.single;
      expect(s.plainText, 'Привет    мир', reason: 'пробелы подряд — один, text:s — сколько указано');
      expect(s.x, closeTo(28.35, 0.01));
      expect(s.text!.paragraphs.single.runs.first.size, 18);
    });

    test('огромные повторы строк и столбцов таблицы — в пределах', () {
      const tbl =
          '<draw:frame svg:x="0cm" svg:y="0cm" svg:width="20cm" svg:height="5cm"><table:table>'
          '<table:table-column table:number-columns-repeated="1048576"/>'
          '<table:table-row table:number-rows-repeated="1048576">'
          '<table:table-cell table:number-columns-repeated="16384" table:number-columns-spanned="99999">'
          '<text:p>x</text:p></table:table-cell></table:table-row></table:table></draw:frame>';
      final sw = Stopwatch()..start();
      final doc = _read(_odp(_content('<draw:page>$tbl</draw:page>')));
      final t = doc.slides.single.shapes.single.table!;
      expect(t.columns.length, OdpReader.maxTableCols);
      expect(t.rows.length, OdpReader.maxTableRows);
      expect(doc.truncated, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('глубокая вложенность групп и тысячи фигур', () {
      final deep = '${List.filled(300, '<draw:g>').join()}${_frame('Глубоко')}${List.filled(300, '</draw:g>').join()}';
      final many = List.generate(1500, (i) => _frame('$i')).join();
      final doc = _read(_odp(_content('<draw:page>$deep</draw:page><draw:page>$many</draw:page>')));
      expect(doc.slides, hasLength(2));
      expect(doc.slides[1].shapes, hasLength(OfficeSlidesDoc.maxShapes));
      expect(doc.truncated, isTrue);
    });

    test('внешняя картинка не загружается, испорченный draw:transform не ломает слайд', () {
      final doc = _read(
        _odp(
          _content(
            '<draw:page>'
            '<draw:frame svg:x="0cm" svg:y="0cm" svg:width="5cm" svg:height="5cm">'
            '<draw:image xlink:href="https://example.com/tracker.png"/></draw:frame>'
            '${_frame('Текст', extra: 'draw:transform="rotate (abc) translate (1cm"')}'
            '</draw:page>',
          ),
        ),
      );
      final shapes = doc.slides.single.shapes;
      expect(shapes.where((s) => s.picture != null), isEmpty);
      expect(_withText(doc.slides.single, 'Текст').rotation, 0);
    });

    test('ссылки — только http, https, mailto', () {
      final doc = _read(
        _odp(
          _content(
            '<draw:page>'
            '${_frame('<text:a xlink:href="https://example.com/">Сайт</text:a>')}'
            '${_frame('<text:a xlink:href="javascript:alert(1)">Скрипт</text:a>', x: '8cm')}'
            '</draw:page>',
          ),
        ),
      );
      expect(_withText(doc.slides.single, 'Сайт').text!.paragraphs.single.runs.single.href, 'https://example.com/');
      expect(_withText(doc.slides.single, 'Скрипт').text!.paragraphs.single.runs.single.href, isNull);
    });
  });
}

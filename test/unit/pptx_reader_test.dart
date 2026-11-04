// Презентация PPTX в просмотре вложения (1.11.x, предпросмотр документов,
// план владельца 04.11.2026): порядок и размер слайдов, наследование
// заполнителей от макета и образца, маркеры, картинка, таблица, группа,
// скрытый слайд; файл от LibreOffice (другое устройство пакета); чужие и
// испорченные файлы — без падения и в пределах.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/doc_slides.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/pptx_reader.dart';

OfficeSlidesDoc _fixture(String name) =>
    PptxReader.read(OfficeZip.open(File('test/fixtures/office/$name').readAsBytesSync()));

/// Фигура слайда с текстом [text] (первая).
DocShape _withText(DocSlide s, String text) => s.shapes.firstWhere((sh) => sh.plainText.contains(text));

const _ns =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

String _rels(Map<String, String> targets, {String type = 'slide'}) =>
    '<Relationships '
    'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${targets.entries.map((e) => '<Relationship Id="${e.key}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type" Target="${e.value}"/>').join()}'
    '</Relationships>';

String _sp(String text, {int x = 914400, int y = 914400, int w = 1828800, int h = 914400, String extra = ''}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="t"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"/>'
    '<a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></p:spPr>'
    '<p:txBody><a:bodyPr/><a:p><a:r>$extra<a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>';

String _slide(String tree) =>
    '<p:sld $_ns><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/>'
    '<p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>$tree</p:spTree></p:cSld></p:sld>';

/// Минимальный пакет PPTX без макетов и образцов: [slides] — XML слайдов,
/// [files] — другие части (поверх).
Uint8List _pptx(List<String> slides, {Map<String, String> files = const {}, String size = ''}) {
  final a = Archive();
  void add(String name, String text) => a.add(ArchiveFile.bytes(name, utf8.encode(text)));
  add('_rels/.rels', _rels({'rId1': 'ppt/presentation.xml'}, type: 'officeDocument'));
  add(
    'ppt/presentation.xml',
    '<p:presentation $_ns><p:sldIdLst>'
        '${[for (var i = 0; i < slides.length; i++) '<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>'].join()}'
        '</p:sldIdLst><p:sldSz ${size.isEmpty ? 'cx="9144000" cy="6858000"' : size}/></p:presentation>',
  );
  add(
    'ppt/_rels/presentation.xml.rels',
    _rels({for (var i = 0; i < slides.length; i++) 'rId${i + 1}': 'slides/slide${i + 1}.xml'}),
  );
  for (var i = 0; i < slides.length; i++) {
    add('ppt/slides/slide${i + 1}.xml', slides[i]);
  }
  files.forEach(add);
  return Uint8List.fromList(ZipEncoder().encode(a));
}

OfficeSlidesDoc _read(Uint8List bytes) => PptxReader.read(OfficeZip.open(bytes));

Matcher _kind(OfficeDocError k) => throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', k));

void main() {
  group('фикстура python-pptx', () {
    final doc = _fixture('slides.pptx');

    test('размер, порядок, скрытый слайд пропущен', () {
      expect(doc.width, 720);
      expect(doc.height, 540);
      expect(doc.truncated, isFalse);
      expect(doc.slides, hasLength(6));
      final all = doc.slides.map((s) => s.shapes.map((sh) => sh.plainText).join('|')).toList();
      expect(all[0], contains('Квартальный отчёт'));
      expect(all[1], contains('Итоги квартала'));
      expect(all[3], contains('Продажи по городам'));
      expect(all[5], contains('Спасибо!'));
      expect(all.join(), isNot(contains('Скрытый слайд')));
    });

    test('заголовок без своей рамки — рамка и размер от макета и образца', () {
      final title = _withText(doc.slides[0], 'Квартальный отчёт');
      // Макет «Титульный слайд»: off 685800, 2130425; ext 7772400 × 1470025.
      expect(title.x, closeTo(54, 0.01));
      expect(title.y, closeTo(167.75, 0.01));
      expect(title.w, closeTo(612, 0.01));
      expect(title.h, closeTo(115.75, 0.01));
      final run = title.text!.paragraphs.single.runs.single;
      expect(run.size, 44, reason: 'titleStyle образца');
      expect(run.font, 'Calibri', reason: 'шрифт заголовков темы (+mj-lt)');
      expect(run.color, 0xFF000000);
      expect(title.text!.anchor, DocAnchor.middle);
      expect(title.text!.paragraphs.single.align, DocAlign.center);
      final sub = _withText(doc.slides[0], 'Отдел продаж').text!.paragraphs.single;
      expect(sub.bullet, isNull, reason: 'buNone в макете перекрывает маркер bodyStyle');
      expect(sub.runs.single.size, 32);
      expect(sub.runs.single.color, 0xFF898989, reason: 'tx1 с tint 75 %');
    });

    test('маркированный список двух уровней', () {
      final body = _withText(doc.slides[1], 'Выручка').text!;
      final ps = body.paragraphs;
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
      expect(ps[0].marginLeft, closeTo(27, 0.01));
      expect(ps[0].indent, closeTo(-27, 0.01));
      expect(ps[1].marginLeft, closeTo(58.5, 0.01));
      expect(body.shrink, isTrue, reason: 'normAutofit образца без сохранённого множителя');
    });

    test('картинка и цветные фигуры, поворот, цвет текста из p:style', () {
      final s = doc.slides[2];
      final pic = s.shapes.firstWhere((sh) => sh.picture != null);
      expect(pic.picture!.image.mime, 'image/png');
      expect(pic.x, closeTo(36, 0.01));
      final box = _withText(s, 'Оранжевая плашка');
      expect(box.geom, DocGeom.roundRect);
      expect(box.fill!.color, 0xFFE06C2A);
      expect(box.line!.color, 0xFF803010);
      expect(box.line!.width, closeTo(2, 0.01));
      final run = box.text!.paragraphs.single.runs.single;
      expect(run.bold, isTrue);
      expect(run.size, 24);
      expect(run.color, 0xFFFFFFFF, reason: 'fontRef lt1 стиля фигуры');
      expect(s.shapes.where((sh) => sh.geom == DocGeom.ellipse), hasLength(1));
      final tilted = _withText(s, 'Повёрнуто');
      expect(tilted.rotation, closeTo(30, 0.001));
      expect(tilted.x, closeTo(504, 0.01));
    });

    test('таблица: объединённая ячейка, стиль «Средний 2 — акцент 1»', () {
      final t = doc.slides[3].shapes.firstWhere((sh) => sh.table != null).table!;
      expect(t.columns, [216, 216, 216]);
      expect(t.rows, hasLength(4));
      expect(t.cells, hasLength(11), reason: '12 ячеек, одна закрыта объединением');
      final head = t.cells.firstWhere((c) => c.row == 0 && c.col == 1);
      expect(head.colSpan, 2);
      expect(head.text!.paragraphs.single.text, 'Квартал');
      expect(head.fill!.color, 0xFF4F81BD);
      expect(head.text!.paragraphs.single.runs.single.bold, isTrue);
      expect(head.text!.paragraphs.single.runs.single.color, 0xFFFFFFFF);
      final moscow = t.cells.firstWhere((c) => c.row == 1 && c.col == 0);
      expect(moscow.text!.paragraphs.single.text, 'Москва');
      expect(moscow.fill!.color, 0xFFD0D8E8, reason: 'accent1 tint 40 %');
      expect(t.cells.firstWhere((c) => c.row == 2 && c.col == 0).fill!.color, 0xFFE9EDF4);
      expect(moscow.text!.paragraphs.single.runs.single.size, 18);
    });

    test('группа растянута в 1.5 раза — дети в координатах слайда', () {
      final s = doc.slides[4];
      final rect = _withText(s, 'В группе');
      expect(rect.x, closeTo(600000 / 12700, 0.01));
      expect(rect.y, closeTo(1200000 / 12700, 0.01));
      expect(rect.w, closeTo(3000000 / 12700, 0.01));
      expect(rect.h, closeTo(1500000 / 12700, 0.01));
      final oval = s.shapes.firstWhere((sh) => sh.geom == DocGeom.ellipse);
      expect(oval.x, closeTo(4350000 / 12700, 0.01));
      expect(oval.w, closeTo(1500000 / 12700, 0.01));
      expect(_withText(s, 'Надпись вне группы').text!.wrap, isFalse);
    });

    test('свой фон слайда', () {
      expect(doc.slides[5].background!.color, 0xFFFFF4D6);
      expect(doc.slides[0].background!.color, 0xFFFFFFFF, reason: 'bgRef образца');
    });
  });

  test('PPTX, сохранённый LibreOffice, — то же содержимое', () {
    final doc = _fixture('slides_lo.pptx');
    expect(doc.slides, hasLength(6));
    expect(doc.width, 720);
    expect(_withText(doc.slides[0], 'Квартальный отчёт').text!.paragraphs.single.runs.single.size, 44);
    final body = _withText(doc.slides[1], 'Выручка').text!.paragraphs;
    expect(body.map((p) => p.level), [0, 1, 1, 0, 0]);
    expect(body.map((p) => p.bullet?.text), ['•', '–', '–', '•', '•']);
    expect(doc.slides[2].shapes.where((sh) => sh.picture != null), hasLength(1));
    expect(_withText(doc.slides[2], 'Повёрнуто').rotation, closeTo(30, 0.001));
    final t = doc.slides[3].shapes.firstWhere((sh) => sh.table != null).table!;
    expect(t.cells.firstWhere((c) => c.row == 0 && c.col == 1).colSpan, 2);
    expect(t.cells.firstWhere((c) => c.row == 0 && c.col == 0).fill!.color, 0xFF4F81BD);
    expect(_withText(doc.slides[4], 'В группе').x, closeTo(47.2, 0.5));
    expect(doc.slides[5].background!.color, 0xFFFFF4D6);
  });

  group('чужие и испорченные файлы', () {
    test('нет макета и образца: фигуры со своей рамкой показываются', () {
      final doc = _read(_pptx([_slide(_sp('Привет'))]));
      expect(doc.slides, hasLength(1));
      final s = doc.slides.single.shapes.single;
      expect(s.plainText, 'Привет');
      expect(s.x, 72);
      expect(s.fill!.color, 0xFFFF0000);
      expect(s.text!.paragraphs.single.runs.single.size, 18, reason: 'размер по умолчанию');
    });

    test('испорченный слайд и испорченные связи — остальное показывается', () {
      final doc = _read(
        _pptx(
          [
            '<p:sld $_ns><p:cSld><p:spTree>', // не закрыт
            _slide(_sp('Второй')),
          ],
          files: {'ppt/slides/_rels/slide2.xml.rels': '<Relationships><oops'},
        ),
      );
      expect(doc.slides, hasLength(1));
      expect(doc.slides.single.shapes.single.plainText, 'Второй');
    });

    test('связь на несуществующий макет — без макета', () {
      final doc = _read(
        _pptx(
          [_slide(_sp('Текст'))],
          files: {
            'ppt/slides/_rels/slide1.xml.rels': _rels({'rId1': '../slideLayouts/nope.xml'}, type: 'slideLayout'),
          },
        ),
      );
      expect(doc.slides.single.shapes.single.plainText, 'Текст');
    });

    test('нет presentation.xml или он не XML — повреждён', () {
      final a = Archive()..add(ArchiveFile.bytes('ppt/slides/slide1.xml', utf8.encode(_slide(''))));
      expect(() => _read(Uint8List.fromList(ZipEncoder().encode(a))), _kind(OfficeDocError.damaged));
      expect(() => _read(_pptx([], files: {'ppt/presentation.xml': '<p:presentation'})), _kind(OfficeDocError.damaged));
    });

    test('глубокая вложенность групп — без переполнения стека', () {
      const depth = 400;
      final open = List.filled(
        depth,
        '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="3" name="g"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>',
      ).join();
      final close = List.filled(depth, '</p:grpSp>').join();
      final doc = _read(_pptx([_slide('$open${_sp('Глубоко')}$close'), _slide(_sp('Рядом'))]));
      expect(doc.slides, hasLength(2));
      expect(doc.truncated, isTrue);
      expect(doc.slides[1].shapes.single.plainText, 'Рядом');
    });

    test('тысячи фигур — не больше предела', () {
      final many = List.generate(2000, (i) => _sp('$i')).join();
      final sw = Stopwatch()..start();
      final doc = _read(_pptx([_slide(many)]));
      expect(doc.slides.single.shapes, hasLength(OfficeSlidesDoc.maxShapes));
      expect(doc.truncated, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('неправдоподобные размеры и счётчики не превращаются в память', () {
      final tbl =
          '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="5" name="t"/><p:cNvGraphicFramePr/><p:nvPr/>'
          '</p:nvGraphicFramePr><p:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="914400"/></p:xfrm><a:graphic>'
          '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblGrid>'
          '${List.filled(500, '<a:gridCol w="99999999999"/>').join()}</a:tblGrid>'
          '<a:tr h="-5"><a:tc gridSpan="1000000" rowSpan="99999"><a:txBody><a:bodyPr/><a:p><a:r><a:t>Ячейка</a:t>'
          '</a:r></a:p></a:txBody><a:tcPr/></a:tc></a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
      final doc = _read(_pptx([_slide(tbl + _sp('x', w: -5, h: 999999999999))], size: 'cx="999999999999" cy="-1"'));
      expect(doc.width, 720, reason: 'размер слайда по умолчанию');
      final t = doc.slides.single.shapes.firstWhere((s) => s.table != null).table!;
      expect(t.columns.length, PptxReader.maxTableCols);
      expect(t.cells.single.colSpan, PptxReader.maxTableCols);
      expect(t.cells.single.rowSpan, 1);
      expect(doc.truncated, isTrue);
    });

    test('ссылки — только http, https, mailto', () {
      String link(String id) => '<a:rPr><a:hlinkClick r:id="$id"/></a:rPr>';
      final doc = _read(
        _pptx(
          [_slide(_sp('Сайт', extra: link('rId7')) + _sp('Скрипт', extra: link('rId8')))],
          files: {
            'ppt/slides/_rels/slide1.xml.rels':
                '<Relationships '
                'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
                'Target="https://example.com/" TargetMode="External"/>'
                '<Relationship Id="rId8" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
                'Target="javascript:alert(1)" TargetMode="External"/></Relationships>',
          },
        ),
      );
      final shapes = doc.slides.single.shapes;
      expect(_withText(doc.slides.single, 'Сайт').text!.paragraphs.single.runs.single.href, 'https://example.com/');
      expect(_withText(doc.slides.single, 'Скрипт').text!.paragraphs.single.runs.single.href, isNull);
      expect(shapes, hasLength(2));
    });

    test('mc:AlternateContent: одно из двух, запасное — когда в нём картинка', () {
      const alt =
          '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
          '<mc:Choice Requires="x">CHOICE</mc:Choice><mc:Fallback>FALLBACK</mc:Fallback></mc:AlternateContent>';
      final doc = _read(
        _pptx([_slide(alt.replaceFirst('CHOICE', _sp('Новое')).replaceFirst('FALLBACK', _sp('Старое')))]),
      );
      expect(doc.slides.single.shapes.map((s) => s.plainText), ['Новое']);
    });

    test('нумерованный список и индексы', () {
      String p(String t, {String rPr = ''}) =>
          '<a:p><a:pPr marL="457200" indent="-457200"><a:buAutoNum type="romanUcPeriod" startAt="3"/></a:pPr>'
          '<a:r>$rPr<a:t>$t</a:t></a:r></a:p>';
      final sp =
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="t"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
          '<a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/>'
          '${p('Один')}${p('Два', rPr: '<a:rPr baseline="30000"/>')}</p:txBody></p:sp>';
      final ps = _read(_pptx([_slide(sp)])).slides.single.shapes.single.text!.paragraphs;
      expect(ps.map((p) => p.bullet?.text), ['III.', 'IV.']);
      expect(ps[1].runs.single.baseline, 30);
    });
  });
}

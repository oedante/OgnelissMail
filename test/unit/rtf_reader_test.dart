// Документ RTF в просмотре вложений (1.11.x, предпросмотр документов, план
// владельца 04.11.2026): RTF → HTML. Образцы — test/fixtures/office
// (text_cp1251.rtf «как из русского Word», text_unicode.rtf с \uN,
// text_sample.rtf — DOCX-образец, пересохранённый LibreOffice).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/services/documents/doc_codepages.dart';
import 'package:ogneliss/services/documents/office_document.dart';
import 'package:ogneliss/services/documents/office_package.dart';
import 'package:ogneliss/services/documents/rtf_reader.dart';

Uint8List _f(String name) => File('test/fixtures/office/$name').readAsBytesSync();

/// Документ из текста: буквы вне ASCII — \uN, как их пишет Word.
OfficeTextDoc _rtf(String s, {String lang = 'en'}) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r < 0x80) {
      out.writeCharCode(r);
    } else {
      for (final u in String.fromCharCode(r).codeUnits) {
        out.write('\\u${u > 32767 ? u - 65536 : u}?');
      }
    }
  }
  return RtfReader.read(Uint8List.fromList(latin1.encode(out.toString())), lang: lang);
}

void main() {
  group('Word, Windows-1251 (text_cp1251.rtf)', () {
    late OfficeTextDoc doc;
    setUpAll(() => doc = RtfReader.read(_f('text_cp1251.rtf'), lang: 'en'));

    test('кириллица по \\ansicpg1251 и \\fcharset204, оформление', () {
      final h = doc.html;
      expect(doc.truncated, isFalse);
      expect(
        RegExp(
          r'<h1[^>]*text-align:center[^>]*><span style="font-weight:bold">Служебная записка</span></h1>',
        ).hasMatch(h),
        isTrue,
      );
      expect(h, contains('text-indent:35.5pt">Прошу рассмотреть <span style="font-weight:bold">вопрос</span>'));
      expect(h, contains('<span style="font-style:italic">оборудования</span>'));
      expect(h, contains('<span style="text-decoration:underline">сообщить</span>'));
      expect(h, contains('<span style="color:#c00000">пятницы</span>'));
      expect(h, contains('<span style="background-color:#ffff00">срочно</span>'));
      expect(h, contains('Ёлка и съёмка: Ёё'));
      expect(h, isNot(contains('Колонтитул')), reason: 'колонтитул не показывается');
      expect(h, isNot(contains('Ogneliss fixtures')), reason: '\\*\\generator');
      expect(h, isNot(contains('Times New Roman')));
      expect(h, isNot(contains('Arial')));
    });

    test('списки \\listtext/\\pntext, таблица, ссылка, картинка, перевод строки', () {
      final h = doc.html;
      expect(h, contains('text-indent:0">•\u00A0</span>Пункт первый'));
      expect(h, contains('text-indent:0">•\u00A0</span>Пункт второй'));
      expect(h, contains('text-indent:0">1.\u00A0</span>Нумерованный пункт'));
      expect('<tr>'.allMatches(h).length, 3);
      expect(h, contains('<p style="margin:0;text-align:right">Количество</p>'));
      expect(h, contains('Казань'));
      expect(h, contains('border-top:1px solid #000000'));
      expect(
        h,
        contains(
          '<a href="https://example.org/"><span style="text-decoration:underline;color:#0000ff">'
          'example.org</span></a>',
        ),
      );
      expect(h, contains('<img src="cid:img1" width="32" height="32"'));
      expect(doc.images['img1'], startsWith('data:image/png;base64,'));
      expect(h, contains('font-family:monospace">code()'));
      expect(h, contains('<br>'));
      expect(h, contains('новая строка\u2003\u2003после табуляции'));
    });

    test('переживает санитайзер и окно письма', () {
      final clean = HtmlSanitizer.sanitizeKeepingStyles(doc.html);
      expect(clean, contains('src="cid:img1"'));
      expect(clean, contains('href="https://example.org/"'));
      final built = MailHtmlDocument.build(clean, allowRemoteImages: false, inlineImages: doc.images);
      expect(built.html, contains('src="data:image/png;base64,'));
      expect(built.declaredWidth, isNull);
    });
  });

  test('\\uN и \\ucN: кириллица, греческий, евро, пара суррогатов, над- и подстрочный', () {
    final h = RtfReader.read(_f('text_unicode.rtf')).html;
    expect(h, contains('Привет, мир'));
    expect(h, contains('Греческий: Ωμέγα; € — евро, <span style="color:#008000">зелёный</span>'));
    expect(h, contains('знак 😀 и «кавычки».'));
    expect(h, isNot(contains('?')));
    expect(h, contains('<sup>2</sup> H<sub>2</sub>O'));
  });

  test('LibreOffice (text_sample.rtf): заголовки, списки, объединения, сноска', () {
    final d = RtfReader.read(_f('text_sample.rtf'));
    final h = d.html;
    expect(RegExp(r'<h1[^>]*>Отчёт о работе отдела</h1>').hasMatch(h), isTrue);
    expect(RegExp(r'<h2[^>]*>.*Таблица').hasMatch(h), isTrue);
    expect(h, contains('<span style="font-weight:bold">жирный</span>'));
    for (final label in ['•', '◦', '1.', '1.1.', '1.2.', '2.']) {
      expect(h, contains('text-indent:0">$label\u00A0</span>'), reason: label);
    }
    expect(h, isNot(contains('\uF0B7')));
    expect(h, contains('colspan="2"'));
    expect(h, contains('rowspan="2"'));
    expect(h, contains('background-color:#d9e2f3'));
    expect(h, contains('<a href="mailto:info@example.org">'));
    expect(h, contains('текст.<sup>1</sup>'));
    expect(h.substring(h.lastIndexOf('<hr')), contains('Данные условные.'));
    expect(h, contains('border-top:1px dashed'));
    expect(d.images.length, 1);
  });

  group('кодовая страница без \\ansicpg', () {
    const body = r"{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0 \'cf\'f0\'e8\'e2\'e5\'f2\par}";
    test('по языку приложения', () {
      expect(_rtf(body, lang: 'ru').html, contains('Привет'));
      expect(_rtf(body, lang: 'uk').html, contains('Привет'));
      expect(_rtf(body).html, contains('Ïðèâåò'));
    });
    test('по языку документа (\\deflang1049) и набору символов шрифта', () {
      expect(_rtf(body.replaceFirst(r'\ansi', r'\ansi\deflang1049')).html, contains('Привет'));
      expect(
        _rtf(
          r'{\rtf1\ansi\ansicpg1252{\fonttbl{\f0\fcharset204 Arial;}{\f1\fcharset238 Arial;}}'
          r"\f0 \'cf\'f0\'e8\'e2\'e5\'f2 \f1 \'9a\'e8\par}",
        ).html,
        contains('Привет šč'),
      );
    });
    test('таблицы страниц', () {
      expect(DocCodePages.decode([0xC0, 0xFF, 0xA8, 0xB9], 1251), 'АяЁ№');
      expect(DocCodePages.decode([0xE0, 0xE8], 1257), 'ąč');
      expect(DocCodePages.decode([0xA1], 874), 'ก');
      expect(DocCodePages.decode([0x80], 1252), '€');
      expect(DocCodePages.forCharset(204), 1251);
      expect(DocCodePages.forLanguage('ru-RU'), 1251);
    });
  });

  group('содержимое', () {
    test('поля: ссылка только http/https/mailto, результат поля без инструкции', () {
      final h = _rtf(
        r'{\rtf1\ansi {\field{\*\fldinst {HYPERLINK "javascript:alert(1)"}}{\fldrslt опасная}} '
        r'{\field{\*\fldinst PAGE}{\fldrslt 7}} '
        r'{\field{\*\fldinst {HYPERLINK \\l "_Toc1"}}{\fldrslt закладка}}\par}',
      ).html;
      expect(h, isNot(contains('<a ')));
      expect(h, contains('7'));
      expect(h, isNot(contains('PAGE')));
      expect(h, isNot(contains('HYPERLINK')));
    });

    test('скрытый текст, примечание, колонтитул и неизвестные \\* не показываются', () {
      final h = _rtf(
        r'{\rtf1\ansi {\v скрыто}видно{\*\annotation примечание}'
        r'{\footer {\field{\*\fldinst PAGE}{\fldrslt 99}}}{\*\unknowndest мусор} конец\par}',
      ).html;
      expect(h, contains('видно конец'));
      expect(h, isNot(contains('скрыто')));
      expect(h, isNot(contains('примечание')));
      expect(h, isNot(contains('99')));
      expect(h, isNot(contains('мусор')));
    });

    test('картинка: WMF пропускается, \\binN, JPEG по сигнатуре', () {
      final h = _rtf(
        r'{\rtf1\ansi до {\pict\wmetafile8\picw100\pich100 0102030405}'
        r'{\*\shppict{\pict\jpegblip\picwgoal300\pichgoal150 ffd8ffe000104a46494600}}'
        r'{\nonshppict{\pict\wmetafile8 0102}} после\par}',
      ).html;
      expect(h, contains('до <img src="cid:img1" width="20" height="10"'));
      expect(h, contains('после'));
      expect('<img'.allMatches(h).length, 1);
    });

    test('сноски: номер в тексте, текст под чертой; концевая (\\ftnalt) — тоже', () {
      final h = _rtf(
        r'{\rtf1\ansi Текст{\super\chftn}{\footnote\pard\plain{\super\chftn} Первая.}'
        r' и ещё{\super\chftn}{\footnote\ftnalt\pard\plain{\super\chftn} Вторая.}\par}',
      ).html;
      expect(h, contains('Текст<sup>1</sup> и ещё<sup>2</sup></p>'));
      final notes = h.substring(h.indexOf('<hr'));
      expect(notes, contains('<sup>1</sup> Первая.'));
      expect(notes, contains('<sup>2</sup> Вторая.'));
    });

    test('объединение ячеек по горизонтали (\\clmgf/\\clmrg) и по вертикали', () {
      final h = _rtf(
        r'{\rtf1\ansi '
        r'\trowd\clmgf\cellx2000\clmrg\cellx4000\pard\intbl шапка\cell\cell\row '
        r'\trowd\clvmgf\cellx2000\cellx4000\pard\intbl слева\cell справа\cell\row '
        r'\trowd\clvmrg\cellx2000\cellx4000\pard\intbl \cell ниже\cell\row '
        r'\pard после\par}',
      ).html;
      expect(h, contains('colspan="2"'));
      expect(h, contains('rowspan="2"'));
      expect(h, contains('ниже'));
      expect(h.indexOf('после'), greaterThan(h.indexOf('</table>')));
    });
  });

  group('враждебные и испорченные файлы', () {
    test('не RTF — повреждён; слишком большой — tooLarge', () {
      expect(
        () => RtfReader.read(Uint8List.fromList(utf8.encode('просто текст'))),
        throwsA(isA<OfficeDocException>().having((e) => e.kind, 'kind', OfficeDocError.damaged)),
      );
      expect(() => _rtf(''), throwsA(isA<OfficeDocException>()));
    });

    test('незакрытые и лишние скобки — показано, что есть', () {
      expect(_rtf(r'{\rtf1\ansi {\b жирный начало абзаца {\i курсив').html, contains('начало абзаца'));
      expect(_rtf(r'{\rtf1\ansi раз}}}} два\par}').html, contains('раз'));
    });

    test('глубокая вложенность групп — без переполнения стека и лишней памяти', () {
      final h = _rtf(
        r'{\rtf1\ansi '
        '${'{' * 200000}глубоко${'}' * 200000} после\\par}',
      ).html;
      expect(h, contains('после'));
      expect(h, isNot(contains('глубоко')));
    });

    test('огромный документ — начало, теги закрыты', () {
      const para = r'\pard Строка большого документа RTF с текстом и цифрами 1234567890.\par ';
      final h = _rtf('{\\rtf1\\ansi ${para * 5000}}');
      expect(h.truncated, isTrue);
      expect(h.html, endsWith('</p>'));
      expect('<p'.allMatches(h.html).length, '</p>'.allMatches(h.html).length);
    });

    test('огромная таблица — начало, строки закрыты', () {
      const row = r'\trowd\cellx1000\cellx2000\pard\intbl ячейка\cell вторая\cell\row ';
      final d = _rtf('{\\rtf1\\ansi ${row * 30000}\\pard после\\par}');
      expect(d.truncated, isTrue);
      expect('<tr>'.allMatches(d.html).length, '</tr>'.allMatches(d.html).length);
      expect(d.html, endsWith('</table>'));
    });

    test('\\bin с огромной длиной, мусорные \\u и \\\'hh, переполнение чисел', () {
      final h = _rtf(r'{\rtf1\ansi раз\bin99999999999 два}').html;
      expect(h, contains('раз'));
      final g = _rtf(r"{\rtf1\ansi 香9999999 \u-99999 \'zz\'4 \fs99999999 \cellx-99999999 текст\par}").html;
      expect(g, contains('текст'));
    });

    test('картинка больше предела — пропускается', () {
      final big = 'ab' * (OfficeLimits.maxImageBytes + 10);
      final h = _rtf('{\\rtf1\\ansi до {\\pict\\pngblip 89504e470d0a1a0a$big} после\\par}').html;
      expect(h, isNot(contains('<img')));
      expect(h, contains('после'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/symbol_fonts.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

String _body(String html) {
  final out = MailHtmlDocument.build(html, allowRemoteImages: false).html;
  return out.substring(out.indexOf('<body>') + 6, out.lastIndexOf('</body>'));
}

void main() {
  group('SymbolFonts.map', () {
    test('стрелки Wingdings', () {
      expect(SymbolFonts.map('à', SymbolFont.wingdings), '→');
      expect(SymbolFonts.map('ß', SymbolFont.wingdings), '←');
      expect(SymbolFonts.map('è', SymbolFont.wingdings), '➔');
      expect(SymbolFonts.map('ü', SymbolFont.wingdings), '✔');
    });

    test('символ в области частного использования (U+F0E0)', () {
      expect(SymbolFonts.map('', SymbolFont.wingdings), '→');
    });

    test('Symbol: греческие буквы и маркер списка', () {
      expect(SymbolFonts.map('a', SymbolFont.symbol), 'α');
      expect(SymbolFonts.map('·', SymbolFont.symbol), '•');
    });

    test('неизвестные символы не меняются', () {
      const s = 'Привет';
      expect(identical(SymbolFonts.map(s, SymbolFont.wingdings), s), isTrue);
    });
  });

  group('HTML письма', () {
    test('Outlook: «->» шрифтом Wingdings становится стрелкой', () {
      final b = _body('<p>11:40 <span style="font-family:Wingdings">à</span> 10:30</p>');
      expect(b, contains('11:40 <span style="font-family:Wingdings">→</span> 10:30'));
    });

    test('mso-symbol-font-family и кавычки в имени шрифта', () {
      final b = _body('<p><span style=\'font-family:"Calibri",sans-serif;'
          'mso-symbol-font-family:Wingdings\'>à</span></p>');
      expect(b, contains('→'));
      expect(b, isNot(contains('à')));
    });

    test('<font face="Symbol">', () {
      expect(_body('<p><font face="Symbol">p</font> = 3,14</p>'), contains('π'));
    });

    test('обычный шрифт внутри символьного — текст не трогается', () {
      final b = _body('<div style="font-family:Wingdings"><span style="font-family:Arial">à la carte</span></div>');
      expect(b, contains('à la carte'));
    });

    test('без символьных шрифтов «à» остаётся', () {
      expect(_body('<p>Rendez-vous à Paris</p>'), contains('à Paris'));
    });
  });

  group('SymbolFonts.fixPlain', () {
    test('превью русского письма', () {
      expect(SymbolFonts.fixPlain('11:40 à 10:30 СБТ-МСК'), '11:40 → 10:30 СБТ-МСК');
      expect(SymbolFonts.fixPlain('Москва ß Казань'), 'Москва ← Казань');
    });

    test('французский текст не меняется', () {
      const s = 'Rendez-vous à Paris';
      expect(SymbolFonts.fixPlain(s), s);
    });

    test('буква внутри слова не меняется', () {
      const s = 'На десерт crème brûlée';
      expect(SymbolFonts.fixPlain(s), s);
    });
  });
}

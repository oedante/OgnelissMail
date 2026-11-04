// Числа и даты ячеек таблиц — как их показывает Excel (1.11.x, предпросмотр
// документов): форматы из файла, «Общий» без «шума» дробей, разделители и
// краткая дата по языку приложения.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/documents/sheet_format.dart';

String f(String code, double v, {String lang = 'ru', bool date1904 = false}) =>
    SheetNumberFormat(code).format(v, SheetLocale.of(lang), date1904: date1904).text;

String g(double v, {String lang = 'ru'}) => SheetNumberFormat.generalText(v, SheetLocale.of(lang));

const nb = ' ';

void main() {
  group('«Общий»', () {
    test('без шума двоичных дробей', () {
      expect(g(0.1 + 0.2), '0,3');
      expect(g(0.1 + 0.2, lang: 'en'), '0.3');
      expect(g(1 / 3), '0,333333333');
      expect(g(3.14159265358979), '3,141592654');
      expect(g(-2.5), '-2,5');
      expect(g(0), '0');
    });

    test('целые до 15 цифр — полностью, большие и мелкие — экспонентой', () {
      expect(g(123456789012), '123456789012');
      expect(g(1e20), '1E+20');
      expect(g(1.5e20, lang: 'en'), '1.5E+20');
      expect(g(0.00001234), '1,234E-05');
      expect(g(0.0001234), '0,0001234');
      expect(g(123456.789012), '123456,789');
    });
  });

  group('числовые форматы', () {
    test('разряды и десятичные — по языку', () {
      expect(f('#,##0.00', 1234.5), '1${nb}234,50');
      expect(f('#,##0.00', 1234.5, lang: 'en'), '1,234.50');
      expect(f('#,##0.00', 1234.5, lang: 'de'), '1.234,50');
      expect(f('#,##0', 1234567.4), '1${nb}234${nb}567');
      expect(f('0', 2.5), '3');
      expect(f('0.00', 1.005), '1,01');
      expect(f('0.0', -0.04), '-0,0');
    });

    test('проценты, экспонента, деление на тысячу', () {
      expect(f('0%', 0.125), '13%');
      expect(f('0.00%', 0.125), '12,50%');
      expect(f('0.00E+00', 12345), '1,23E+04');
      expect(f('0.00E+00', 0.00012), '1,20E-04');
      expect(f('##0.0E+0', 12345, lang: 'en'), '12.3E+3');
      expect(f('#,##0,', 1234567, lang: 'en'), '1,235');
      expect(f('0.0,,"M"', 1234567, lang: 'en'), '1.2M');
    });

    test('разделы, цвет, ноль, подписи', () {
      final fmt = SheetNumberFormat('#,##0.00;[Red]-#,##0.00;"—"');
      expect(fmt.format(-5, SheetLocale.of('ru')).text, '-5,00');
      expect(fmt.format(-5, SheetLocale.of('ru')).color, 0xFFFF0000);
      expect(fmt.format(0, SheetLocale.of('ru')).text, '—');
      expect(fmt.format(5, SheetLocale.of('ru')).color, isNull);
      expect(f('0.00;(0.00)', -3.5, lang: 'en'), '(3.50)');
      expect(f('0;-0;;@', 0), '');
      expect(f('[<100]"мало";"много"', 50), 'мало');
      expect(f('[<100]"мало";"много"', 500), 'много');
    });

    test('валюта [\$₽-419] и подписи в кавычках', () {
      expect(f('#,##0.00\\ [\$₽-419]', 1500), '1${nb}500,00 ₽');
      expect(f('[\$\$-409]#,##0.00', 12.5, lang: 'en'), '\$12.50');
      expect(f('#,##0" руб."', 99), '99 руб.');
      expect(f('_-* #,##0.00\\ "₽"_-;\\-* #,##0.00\\ "₽"_-;_-* "-"??\\ "₽"_-;_-@_-', -1234.5), '-1${nb}234,50 ₽ ');
    });

    test('цифры по местам: телефоны и коды', () {
      expect(f('000-00-00', 1234567), '123-45-67');
      expect(f('00000', 42), '00042');
      expect(f('#.##', 0.5, lang: 'en'), '.5');
      expect(f('0.0#', 2, lang: 'en'), '2.0');
      expect(f('0.0#', 2.345, lang: 'en'), '2.35');
    });

    test('дроби', () {
      expect(f('# ?/?', 1.5, lang: 'en'), '1 1/2');
      expect(f('# ??/??', 0.333333, lang: 'en'), '  1/3 ');
      expect(f('# ?/8', 2.25, lang: 'en'), '2 2/8');
      expect(f('?/?', 0.75, lang: 'en'), '3/4');
    });

    test('текстовый раздел', () {
      expect(SheetNumberFormat('0;-0;0;"Код: "@').formatText('АБ'), 'Код: АБ');
      expect(SheetNumberFormat('@').formatText('x'), 'x');
      expect(SheetNumberFormat('0.00').formatText('x'), isNull);
    });

    test('встроенные форматы', () {
      final ru = SheetLocale.of('ru');
      expect(SheetNumberFormat.builtin(14, ru), 'dd.mm.yyyy');
      expect(SheetNumberFormat.builtin(14, SheetLocale.of('en')), 'm/d/yyyy');
      expect(SheetNumberFormat.builtin(4, ru), '#,##0.00');
      expect(SheetNumberFormat.builtin(200, ru), isNull);
    });
  });

  group('даты', () {
    test('краткая дата по языку', () {
      expect(f(SheetNumberFormat.builtin(14, SheetLocale.of('ru'))!, 46331), '05.11.2026');
      expect(f(SheetNumberFormat.builtin(14, SheetLocale.of('en'))!, 46331, lang: 'en'), '11/5/2026');
      expect(f('dd.mm.yyyy', 46331), '05.11.2026');
      expect(f('DD.MM.YYYY', 46331), '05.11.2026');
    });

    test('месяцы, дни недели, родительный падеж', () {
      expect(f('d mmmm yyyy', 46331), '5 ноября 2026');
      expect(f('mmmm yyyy', 46331), 'Ноябрь 2026');
      expect(f('d mmm yy', 46331), '5 ноя 26');
      expect(f('dddd', 46331), 'четверг');
      expect(f('[\$-409]d mmmm yyyy', 46331), '5 November 2026');
      expect(f('[\$-F800]dddd, mmmm dd, yyyy', 46331), '5 ноября 2026 г.');
      expect(f('mmmmm', 46331, lang: 'en'), 'N');
    });

    test('время, AM/PM, часы сверх суток, доли секунды', () {
      expect(f('h:mm', 0.5 + 1 / 1440 * 5), '12:05');
      expect(f('hh:mm:ss', 46331.75), '18:00:00');
      expect(f('h:mm AM/PM', 46331.75, lang: 'en'), '6:00 PM');
      expect(f('[h]:mm', 1.5), '36:00');
      expect(f('mm:ss.0', 1 / 86400 * 61.25), '01:01,3');
      expect(f('dd.mm.yyyy hh:mm', 46331.5), '05.11.2026 12:00');
      expect(f('yyyy-mm-dd', 0), '1900-01-00');
    });

    test('1900 (с 29 февраля) и 1904', () {
      expect(f('dd.mm.yyyy', 60), '29.02.1900');
      expect(f('dd.mm.yyyy', 61), '01.03.1900');
      expect(f('dd.mm.yyyy', 1), '01.01.1900');
      expect(f('dd.mm.yyyy', 0, date1904: true), '01.01.1904');
      expect(f('dd.mm.yyyy', -1), '########');
      expect(ExcelDate.serial(DateTime(2026, 11, 5)), 46331);
    });
  });
}

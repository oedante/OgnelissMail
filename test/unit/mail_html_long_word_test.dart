// Длинное слово в ячейке таблицы (08.11.2026, письмо владельца «О
// ограничении движения на АД к Кусту газовых скважин №30»): Outlook
// обрамляет предупреждение «Это сообщение от внешнего отправителя!» строками
// из 83 знаков «=». Ячейка раздвигалась под такую строку, таблица выходила
// шире экрана, и после «Показать цитируемую переписку» письмо уходило за
// правый край (объявленных размеров нет — на Android вписать нечем).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

String _build(String html) => MailHtmlDocument.build(html, allowRemoteImages: false).html;

void main() {
  final rule = '=' * 83;

  test('разделитель «=====» в ячейке — одной строкой по ширине (og-rule)', () {
    final html = _build('<p>Текст</p><table class="MsoNormalTable" cellpadding="0" border="0"><tbody>'
        '<tr><td><p>$rule</p></td></tr>'
        '<tr><td><p><span style="color:red">Это сообщение от внешнего отправителя!</span></p></td></tr>'
        '<tr><td><p>$rule</p></td></tr></tbody></table><p>Добрый день.</p>');
    expect(RegExp('<span class="og-rule">$rule</span>').allMatches(html).length, 2);
    expect(html, contains('.og-rule{display:block;width:0;min-width:100%'));
  });

  test('разделитель вне таблицы — тоже одной строкой', () {
    final html = _build('<p>Начало</p><p>${'-' * 40}</p><p>Конец</p>');
    expect(html, contains('<span class="og-rule">${'-' * 40}</span>'));
  });

  test('разделитель посреди фразы — не блок', () {
    final html = _build('<table><tr><td>Итого $rule конец</td></tr></table>');
    expect(html, isNot(contains('class="og-rule"')));
    expect(html, contains('<span class="og-wrap">$rule</span>'));
  });

  test('длинное слово в ячейке переносится (og-wrap), вне таблицы — без изменений', () {
    const path = r'\\fileserver\Отдел_планирования\2026\Ноябрь\Схема_КГС30.pdf';
    final inCell = _build('<table><tr><td>Схема: $path</td></tr></table>');
    expect(inCell, contains('<span class="og-wrap">'));
    expect(inCell, contains('.og-wrap{word-break:break-word;overflow-wrap:anywhere'));
    final outside = _build('<p>Схема: $path</p>');
    expect(outside, isNot(contains('class="og-wrap"')));
  });

  test('короткие слова и ссылки в ячейке не трогаются', () {
    const long = 'https://drive.google.com/file/d/1VkfQ0GsU0beNOkmcAbCdEf/view';
    final html = _build('<table><tr><td>Обычный текст ячейки <a href="$long">$long</a></td></tr></table>');
    expect(html, isNot(contains('class="og-wrap"')));
    expect(html, contains('class="og-brk"'));
  });
}

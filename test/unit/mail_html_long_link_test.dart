// Длинный адрес текстом ссылки переносится где угодно (1.8.12): неразрывный
// адрес раздвигал ячейку таблицы шире вёрстки письма, и вписанное по ширине
// письмо обрезалось справа (рассылка со ссылками drive.google.com/…).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

void main() {
  test('длинная ссылка-адрес — og-brk, обычная ссылка — без него', () {
    const long = 'https://drive.google.com/file/d/1VkfQ0GsU0beNOkmcAbCdEf/view?usp=sharing';
    final doc = MailHtmlDocument.build(
        '<table width="600"><tr><td>Презентация: <a href="$long">$long</a> · '
        '<a href="https://example.com/a">Подробнее о курсе</a> · <a class="btn" href="$long">$long</a></td></tr></table>',
        allowRemoteImages: false);
    expect(RegExp(r'class="og-brk"').allMatches(doc.html).length, 1);
    expect(doc.html, contains('class="btn og-brk"'));
    expect(doc.html, contains('<a href="https://example.com/a">Подробнее о курсе</a>'));
    expect(doc.html, contains('.og-brk{overflow-wrap:anywhere'));
  });

  test('длинный токен — без пробелов и не короче 24 знаков', () {
    expect(MailHtmlDocument.isLongToken('https://drive.google.com/file/d/1Vkf'), isTrue);
    expect(MailHtmlDocument.isLongToken('Подробнее о программе обучения'), isFalse);
    expect(MailHtmlDocument.isLongToken('https://ya.ru'), isFalse);
  });
}

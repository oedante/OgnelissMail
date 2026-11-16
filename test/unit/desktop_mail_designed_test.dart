// Компьютер: письмо с оформлением — в окне браузера, обычная переписка —
// без окна (16.11.2026: рассылки Ozon на Mac рисовались упрощённо, и
// выключатель окна ничего не менял).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/desktop_mail_web_view.dart';

void main() {
  test('рассылка: таблицы с фоном или шириной ячеек, цветной фон, несколько картинок — оформление', () {
    expect(mailLooksDesigned('<table bgcolor="#f2f2f2"><tr><td>Скидки</td></tr></table>'), isTrue);
    expect(mailLooksDesigned('<table><tr><td width="300">A</td><td width="300">B</td></tr></table>'), isTrue);
    expect(mailLooksDesigned('<div style="background-color: #005BFF; color: white">Ozon</div>'), isTrue);
    expect(mailLooksDesigned('<p><img src="a.png"><img src="b.png"></p>'), isTrue);
  });

  test('обычная переписка: текст, цитата, белый фон, подпись с одним логотипом — без окна', () {
    expect(mailLooksDesigned('<div>Добрый день!<br>Договор во вложении.</div>'), isFalse);
    expect(mailLooksDesigned('<blockquote>Цитата</blockquote><p style="background:#fff">Ответ</p>'), isFalse);
    expect(mailLooksDesigned('<p>С уважением</p><img src="cid:logo">'), isFalse);
    expect(mailLooksDesigned('<table><tr><td>Простая таблица</td></tr></table>'), isFalse);
  });
}

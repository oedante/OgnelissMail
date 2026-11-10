// Прехедер рассылки (2.2.0, вопрос владельца 10.11.2026): скрытый текст в
// начале HTML-письма — превью в ленте и уведомлении, как в Gmail и Почте
// Apple. Скрытое мобильное меню и блоки дальше от начала — не прехедер.

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show Preheader;
import 'package:ogneliss/core/security/mail_body_processor.dart';

const _filler = '&zwnj;&nbsp;&#847; &zwnj;&nbsp;&#847; &zwnj;&nbsp;&#847; &zwnj;&nbsp;&#847; ';

void main() {
  test('Mailchimp: mcnPreviewText', () {
    const html = '<html><head><style>.x{color:red}</style></head><body>'
        '<span class="mcnPreviewText" style="display:none; font-size:0px; line-height:0px; max-height:0px; '
        'max-width:0px; opacity:0; overflow:hidden; visibility:hidden; mso-hide:all;">'
        'Скидки до 50% — только до воскресенья</span>'
        '<table><tr><td>Если письмо не отображается, откройте его в браузере</td></tr></table></body></html>';
    expect(Preheader.of(html), 'Скидки до 50% — только до воскресенья');
  });

  test('шаблон рассылки: div со стилями и заполнителем &zwnj;&nbsp;', () {
    const html = '<body><div style="display:none;max-height:0;overflow:hidden;mso-hide:all">'
        'Ваш заказ №123 передан в доставку$_filler$_filler</div>'
        '<p>Здравствуйте, Анна!</p></body>';
    expect(Preheader.of(html), 'Ваш заказ №123 передан в доставку');
  });

  test('только класс preheader (стиль в <style>), вложенные теги', () {
    const html = '<head><style>.preheader{display:none!important}</style></head><body>'
        '<a href="#">Открыть в браузере</a>'
        '<div class="email-preheader"><span>Новый <b>вебинар</b>:</span> 12 ноября в 11:00</div>'
        '<h1>Приглашение</h1></body>';
    expect(Preheader.of(html), 'Новый вебинар: 12 ноября в 11:00');
  });

  test('не прехедер: одно display:none (мобильное меню), блок далеко от начала, обычное письмо', () {
    expect(
        Preheader.of('<body><div class="mobile-menu" style="display:none">Каталог Акции Контакты</div>'
            '<p>Добрый день!</p></body>'),
        isNull);
    final far = '<body><p>${'Очень длинное начало письма, которое видит читатель. ' * 3}</p>'
        '<span class="preheader" style="display:none">Поздний текст</span></body>';
    expect(Preheader.of(far), isNull);
    expect(Preheader.of('<body><p>Привет! Встречаемся завтра в 10.</p></body>'), isNull);
    expect(Preheader.of('Просто текст без разметки'), isNull);
    expect(Preheader.of(null), isNull);
  });

  test('только заполнитель без букв — не прехедер', () {
    const html = '<body><div class="preheader" style="display:none">$_filler$_filler</div><p>Текст</p></body>';
    expect(Preheader.of(html), isNull);
  });

  test('превью, достроенное по тексту письма, — прехедер вместо начала текста', () async {
    final r = await MailBodyProcessor.previewAll({
      'a': (
        plain: 'Если письмо не отображается, откройте его в браузере',
        html: '<body><span class="preheader" style="display:none;mso-hide:all">Ваша подборка на неделю</span>'
            '<p>Если письмо не отображается, откройте его в браузере</p></body>',
      ),
      'b': (plain: 'Привет! Встречаемся завтра.', html: null),
    });
    expect(r['a'], 'Ваша подборка на неделю');
    expect(r['b'], 'Привет! Встречаемся завтра.');
  });

  test('уже загруженные письма: пересчёт пачкой — только с прехедером', () async {
    final r = await MailBodyProcessor.preheaderAll({
      '1': '<body><div class="preheader" style="display:none">Итоги недели</div><p>Текст</p></body>',
      '2': '<body><p>Обычное письмо</p></body>',
    });
    expect(r, {'1': 'Итоги недели'});
  });
}

// Длинные подписи и юридические уведомления — свёрнутыми (2.0.0, план
// 08.11.2026, п. 5). Короткая подпись и обычные письма — как были.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';

const _disclaimerRu = 'Данное сообщение и любые приложения к нему являются конфиденциальными и предназначены '
    'исключительно для адресата. Если вы получили это сообщение по ошибке, пожалуйста, сообщите отправителю '
    'и удалите его. Любое использование, распространение или копирование сообщения запрещено.';
const _disclaimerEn = 'This e-mail and any attachments are confidential and intended solely for the addressee. '
    'If you have received this e-mail in error, please notify the sender and delete it. Any use, disclosure '
    'or copying of this message is prohibited.';
final _longSig = List.filled(12, 'Иванов Иван Иванович, ведущий инженер, отдел эксплуатации, тел. +7 495 000-00-00').join('<br>');

void main() {
  test('уведомление в конце письма — свёрнуто, кнопка «подпись и уведомление»', () {
    final s = splitQuotedHtml('<p>Добрый день! Высылаю отчёт за октябрь, прошу посмотреть до пятницы.</p>'
        '<p>С уважением, Иван</p><p>$_disclaimerRu</p>');
    expect(s.hasQuote, isTrue);
    expect(s.tailOnly, isTrue);
    expect(s.reply, contains('Высылаю отчёт'));
    expect(s.reply, isNot(contains('конфиденциальными')));
    expect(s.quoted, contains('конфиденциальными'));
  });

  test('английский дисклеймер перед цитатой — свёрнут вместе с цитатой', () {
    final s = splitQuotedHtml('<div>Please find the report attached, thanks for the quick reply.</div>'
        '<div>$_disclaimerEn</div>'
        '<blockquote>Старое письмо коллеги с вопросом про отчёт.</blockquote>');
    expect(s.hasQuote, isTrue);
    expect(s.tailOnly, isFalse, reason: 'спрятана и цитата — кнопка прежняя');
    expect(s.reply, isNot(contains('confidential')));
    expect(s.quoted, contains('Старое письмо'));
  });

  test('длинная подпись Gmail — свёрнута; короткая — видна', () {
    final long = splitQuotedHtml('<div>Привет! Документы во вложении, посмотри, пожалуйста, сегодня.</div>'
        '<div class="gmail_signature">$_longSig</div>');
    expect(long.tailOnly, isTrue);
    expect(long.reply, isNot(contains('ведущий инженер')));
    final short = splitQuotedHtml('<div>Привет! Документы во вложении, посмотри, пожалуйста, сегодня.</div>'
        '<div class="gmail_signature">Иван, тел. 1234</div>');
    expect(short.hasQuote, isFalse);
  });

  test('уведомление не в конце (после него свежий текст) — не сворачивается', () {
    final s = splitQuotedHtml('<p>$_disclaimerRu</p><p>А теперь сам ответ: встречаемся завтра в десять утра в переговорной.</p>');
    expect(s.hasQuote, isFalse);
  });

  test('письмо — одно уведомление — показывается целиком', () {
    final s = splitQuotedHtml('<p>$_disclaimerEn</p>');
    expect(s.hasQuote, isFalse);
  });

  test('таблица-вёрстка с ответом и уведомлением — не прячется целиком', () {
    final s = splitQuotedHtml('<table><tr><td><p>Добрый день! Счёт во вложении, оплатите, пожалуйста, до среды.</p>'
        '<p>$_disclaimerRu</p></td></tr></table>');
    expect(s.reply, contains('Счёт во вложении'));
  });

  test('простой текст: длинная подпись «-- » без цитаты — tailOnly', () {
    final s = splitQuotedPlain('Привет!\nОтчёт во вложении.\n-- \nИван\nинженер\nтел. 1\nтел. 2\nадрес\nсайт');
    expect(s.hasQuote, isTrue);
    expect(s.tailOnly, isTrue);
  });
}

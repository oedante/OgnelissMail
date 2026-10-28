// test/unit/eas_headers_test.dart
// ActiveSync: заголовки рассылки и проверки отправителя — из начала MIME.

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  test('заголовки: перенос строк, повторы, регистр', () {
    const mime = 'Received: from a\r\n'
        'Authentication-Results: mx.example; dkim=pass\r\n'
        '\theader.d=shop.ru\r\n'
        'List-Unsubscribe: <https://shop.ru/u?id=1>,\r\n'
        ' <mailto:u@shop.ru>\r\n'
        'List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n'
        'Authentication-Results: mx2.example; dmarc=pass\r\n'
        'Subject: Акции\r\n'
        '\r\n'
        'List-Id: это уже тело письма\r\n';
    final h = EasEngine.parseMimeHeaders(mime);
    expect(h['list-unsubscribe'], '<https://shop.ru/u?id=1>, <mailto:u@shop.ru>');
    expect(h['list-unsubscribe-post'], 'List-Unsubscribe=One-Click');
    expect(h['authentication-results'], 'mx.example; dkim=pass header.d=shop.ru; mx2.example; dmarc=pass');
    expect(h.containsKey('list-id'), isFalse);
  });

  test('пусто — пустой набор', () {
    expect(EasEngine.parseMimeHeaders(''), isEmpty);
  });
}

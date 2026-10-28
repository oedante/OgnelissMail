// Ссылки mailto из других приложений: адресаты — в «Кому», а не в текст.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/integration/mailto_service.dart';

void main() {
  test('адрес, тема, копия и текст', () {
    final r = MailtoRequest.parse('mailto:respon@yandex.ru,b@x.ru?subject=%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82'
        '&cc=c@x.ru&bcc=d@x.ru&body=Line%201%0ALine+2')!;
    expect(r.to, ['respon@yandex.ru', 'b@x.ru']);
    expect(r.cc, ['c@x.ru']);
    expect(r.bcc, ['d@x.ru']);
    expect(r.subject, 'Привет');
    expect(r.body, 'Line 1\nLine+2');
    final q = r.toQuery();
    expect(q['to'], 'respon@yandex.ru,b@x.ru');
    expect(q['quick'], 'Line 1\nLine+2');
  });

  test('только адрес', () {
    expect(MailtoRequest.parse('MAILTO:a@b.ru')!.to, ['a@b.ru']);
  });

  test('не mailto и пустой', () {
    expect(MailtoRequest.parse('https://x.ru'), isNull);
    expect(MailtoRequest.parse('mailto:'), isNull);
  });
}

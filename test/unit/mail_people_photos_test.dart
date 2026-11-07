// Фото людей в плашках цитаты в окне браузера (1.15.1, замечание владельца
// 07.11.2026: в широком письме у плашек были только буквы).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_people.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

const _photo = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD';

MailHtmlDocument _doc() {
  const html =
      '<p>Ответ</p><div>'
      '<p><b>От:</b> Петров Иван &lt;ivan.petrov@corp.example&gt;</p>'
      '<p><b>Кому:</b> Сидорова Анна &lt;anna@corp.example&gt;; Петров Иван &lt;ivan.petrov@corp.example&gt;</p>'
      '<p><b>Копия:</b> Хабиров Ренат Фанильевич</p>'
      '<p><b>Тема:</b> Смета</p></div>';
  return MailHtmlDocument.build(QuotePeople.enrich(html), allowRemoteImages: false);
}

void main() {
  test('адреса плашек: без повторов, строчными', () {
    expect(_doc().peopleEmails..sort(), ['anna@corp.example', 'ivan.petrov@corp.example']);
  });

  test('фото — правилом на человека один раз, буква скрыта; без фото — документ тот же', () {
    final d = _doc();
    expect(d.withPeoplePhotos(const {}), same(d));
    expect(d.withPeoplePhotos(const {'other@corp.example': _photo}), same(d));
    final out = d.withPeoplePhotos(const {'ivan.petrov@corp.example': _photo}).html;
    expect(out, contains('<style id="og-people">'));
    expect('url("$_photo")'.allMatches(out).length, 1, reason: 'два упоминания — одно правило');
    expect(out, contains('a[href^="ogperson:ivan.petrov%40corp.example?" i][data-i]::before'));
    expect(out, contains('color:transparent'));
    expect(out.indexOf('og-people'), lessThan(out.indexOf('</head>')));
  });

  test('только data:image — адрес в сети и мусор не вставляются', () {
    final d = _doc();
    expect(d.withPeoplePhotos(const {'anna@corp.example': 'https://example.com/a.jpg'}), same(d));
    expect(d.withPeoplePhotos(const {'anna@corp.example': 'data:image/png;base64,AA");}*{x:url("y'}), same(d));
  });

  test('тёмная тема инверсией — фото в плашках возвращаются обратно', () {
    final d = _doc().withPeoplePhotos(const {'anna@corp.example': _photo});
    final dark = MailHtmlView.composeHtml(d, viewWidth: 400, fitWidth: null, dark: true, pageColor: null, textScale: 1);
    expect(dark, contains('--og-ph:invert(1)'));
    final light = MailHtmlView.composeHtml(
      d,
      viewWidth: 400,
      fitWidth: null,
      dark: false,
      pageColor: null,
      textScale: 1,
    );
    expect(light, isNot(contains('--og-ph:invert')));
  });
}

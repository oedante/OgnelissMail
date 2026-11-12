// Имена из заголовков, где шлюз разрезал закодированное слово переносом
// (замечание владельца 12.11.2026: «Олег Ермиши? ?utf8?QD0=BD?=»).

import 'package:enough_mail/enough_mail.dart' show MailCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/encoded_words.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/contacts/mail_contacts_service.dart';

void main() {
  const q = '=D0=9E=D0=BB=D0=B5=D0=B3_=D0=95=D1=80=D0=BC=D0=B8=D1=88=D0=B8';

  test('слово Q, разрезанное между «?» и «=» конца: как отдаёт разбор почты и как было на экране', () {
    // Так сервер IMAP отдаёт имя, а библиотека его раскодирует.
    final parsed = MailCodec.decodeHeader('=?utf8?Q?$q? = =?utf8?Q?=D0=BD?=')!;
    expect(parsed, isNot('Олег Ермишин'), reason: 'сама библиотека такое не собирает');
    expect(repairEncodedWordText(parsed), 'Олег Ермишин');
    // Как на снимке владельца (после чистки имени — без «=» и с одним пробелом).
    expect(repairEncodedWordText('Олег Ермиши? ?utf8?QD0=BD?='), 'Олег Ермишин');
    expect(repairedDisplayName('Олег Ермиши?  =?utf8?QD0=BD?='), 'Олег Ермишин');
    // Продолжение из нескольких букв и латиницы.
    expect(repairEncodedWordText('Иванов Ив?  =?utf-8?QD0=B0=D0=BD_Jr?='), 'Иванов Иван Jr');
  });

  test('обычный текст и целые имена не меняются', () {
    for (final s in ['Олег Ермишин', 'Что нового? Отвечаю', 'a = b? да', "'aho@engicom.ru'", 'Тест?=', '']) {
      expect(repairEncodedWordText(s), s);
    }
    expect(repairedDisplayName(null), isNull);
    expect(repairedDisplayName('Вера Белова'), 'Вера Белова');
  });

  test('слово разрезано посреди буквы или не собирается — имени нет', () {
    final midChar = MailCodec.decodeHeader('=?utf8?Q?$q=D0? = =?utf8?Q?=BD?=')!;
    expect(repairedDisplayName(midChar), isNull);
    expect(repairedDisplayName('Имя =?utf8?Q?=D0'), isNull, reason: 'остаток слова — не имя');
    expect(repairedDisplayName('Имя ?koi8-r?Bxx?='), isNull);
    expect(hasEncodedWordLeftovers('Олег Ермиши? ?utf8?QD0=BD?='), isTrue);
    expect(hasEncodedWordLeftovers('Олег Ермишин'), isFalse);
  });

  test('кодировка B с разорванным концом слова', () {
    // Библиотека на таком слове падает (FormatException) — в приложение оно
    // приходит нераскодированным; конец слова собирается, и оно читается.
    const raw = '=?utf-8?B?0J7Qu9C10LMg0JXRgNC80LjRiNC4? = =?utf-8?B?0L0=?=';
    expect(() => MailCodec.decodeHeader(raw), throwsFormatException);
    expect(repairEncodedWordText(raw), 'Олег Ермишин');
    expect(repairedDisplayName(raw), 'Олег Ермишин');
    // Не собирается — без имени, а не мусором.
    expect(repairedDisplayName('=?utf-8?B?0J7Qu9C1? x =?utf-8?B?0L0=?='), isNull);
  });

  test('сохранённые получатели письма читаются с восстановленным именем', () {
    final a = EmailAddress.fromMap(const {'email': 'o@example.ru', 'displayName': 'Олег Ермиши?  =?utf8?QD0=BD?='});
    expect(a.displayName, 'Олег Ермишин');
    expect(EmailAddress.fromMap(const {'email': 'o@example.ru', 'name': 'Вера'}).displayName, 'Вера');
    expect(EmailAddress.fromMap(const {'email': 'o@example.ru'}).displayName, isNull);
  });

  test('в контакты из переписки такое имя не попадает', () {
    expect(MailContactsService.usableName('Олег Ермиши? ?utf8?QD0=BD?='), isFalse);
    expect(MailContactsService.usableName('Олег Ермишин'), isTrue);
  });
}

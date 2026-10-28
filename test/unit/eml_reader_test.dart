// Вложенное письмо .eml разбирается в письмо: тема и имена в koi8-r,
// тело в quoted-printable, встроенная картинка по cid, вложенный файл.
// Прежде такое вложение показывалось сырым MIME-текстом.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/eml_reader.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Uint8List _eml(List<String> lines) => Uint8List.fromList(latin1.encode(lines.join('\r\n')));

final _exchangeReply = _eml([
  'Received: from mx.corp.ru by exch01.corp.ru',
  'From: =?koi8-r?B?6dfBzs/XIOnXwc4=?= <ivanov@corp.ru>',
  'To: me@corp.ru',
  'Cc: boss@corp.ru',
  'Subject: =?koi8-r?B?79TXxdQ6IM/U3qPUINDPINLFzc/O1MHN?=',
  'Date: Mon, 5 Oct 2026 10:15:00 +0300',
  'Message-ID: <abc@corp.ru>',
  'MIME-Version: 1.0',
  'Content-Type: multipart/mixed; boundary="mix"',
  '',
  '--mix',
  'Content-Type: multipart/related; boundary="rel"',
  '',
  '--rel',
  'Content-Type: multipart/alternative; boundary="alt"',
  '',
  '--alt',
  'Content-Type: text/plain; charset="koi8-r"',
  'Content-Transfer-Encoding: quoted-printable',
  '',
  '=E4=CF=C2=D2=D9=CA =C4=C5=CE=D8!',
  '=EF=D4=DE=A3=D4 =D7=CF =D7=CC=CF=D6=C5=CE=C9=C9.',
  '',
  '--alt',
  'Content-Type: text/html; charset="koi8-r"',
  'Content-Transfer-Encoding: quoted-printable',
  '',
  '<html><body><p>=E4=CF=C2=D2=D9=CA =C4=C5=CE=D8!</p><img src=3D"cid:logo@cor=',
  'p"></body></html>',
  '',
  '--alt--',
  '',
  '--rel',
  'Content-Type: image/png',
  'Content-Transfer-Encoding: base64',
  'Content-ID: <logo@corp>',
  'Content-Disposition: inline',
  '',
  _png,
  '',
  '--rel--',
  '',
  '--mix',
  'Content-Type: text/plain; charset="utf-8"; name="=?utf-8?B?0J7RgtGH0ZHRgi50eHQ=?="',
  'Content-Transfer-Encoding: base64',
  'Content-Disposition: attachment; filename="=?utf-8?B?0J7RgtGH0ZHRgi50eHQ=?="',
  '',
  base64Encode(utf8.encode('строка отчёта')),
  '',
  '--mix--',
  '',
]);

void main() {
  group('EmlReader', () {
    test('заголовки в koi8-r раскодированы', () {
      final m = EmlReader.parse(_exchangeReply);
      expect(m.subject, 'Ответ: отчёт по ремонтам');
      expect(m.from.single.name, 'Иванов Иван');
      expect(m.from.single.email, 'ivanov@corp.ru');
      expect(m.to.single.email, 'me@corp.ru');
      expect(m.cc.single.email, 'boss@corp.ru');
      expect(m.date, isNotNull);
      expect(m.date!.toUtc(), DateTime.utc(2026, 10, 5, 7, 15));
    });

    test('тело: HTML и текст из quoted-printable', () {
      final m = EmlReader.parse(_exchangeReply);
      expect(m.html, contains('Добрый день!'));
      expect(m.html, contains('cid:logo@corp'));
      expect(m.plain, contains('Отчёт во вложении.'));
      expect(m.hasBody, isTrue);
    });

    test('картинка по cid — встроенная, файл — вложение', () {
      final m = EmlReader.parse(_exchangeReply);
      expect(m.inlineImages.keys, ['logo@corp']);
      expect(m.inlineImages['logo@corp'], startsWith('data:image/png;base64,'));
      expect(m.attachments, hasLength(1));
      expect(m.attachments.single.name, 'Отчёт.txt');
      expect(utf8.decode(m.attachments.single.bytes), 'строка отчёта');
    });

    test('простое письмо без MIME-частей', () {
      final m = EmlReader.parse(_eml([
        'From: a@b.ru',
        'Subject: Hello',
        '',
        'Plain body',
        '',
      ]));
      expect(m.subject, 'Hello');
      expect(m.plain?.trim(), 'Plain body');
      expect(m.html, isNull);
      expect(m.attachments, isEmpty);
    });

    test('распознавание письма по началу файла', () {
      expect(EmlReader.looksLikeEml(_exchangeReply), isTrue);
      expect(EmlReader.looksLikeEml(Uint8List.fromList(utf8.encode('%PDF-1.7\n...'))), isFalse);
      expect(EmlReader.looksLikeEml(Uint8List.fromList(utf8.encode('Привет: как дела?\nПока'))), isFalse);
    });
  });

  group('Закодированные слова, разрезанные переносом (1.5.10)', () {
    final broken = _eml([
      'From: "=?utf8?Q?=D0=9C=D0=B8=D1=81=D1=8E=D1=80=D0=B0_=D0=90=D1=80=D1=82=D0=B',
      '\t5?=',
      '\t=?utf8?Q?=D0=BC?=" <a.misura@corp.ru>',
      'To: "=?utf8?Q?=D0=A8=D1=83=D0=BB=D0=BE=D0=B2_=D0=A1=D0=B5=D1=80=D0=B3=D0=B5?',
      '\t= =?utf8?Q?=D0=B9?=" <s.shulov@corp.ru>',
      'Subject: =?utf8?Q?=D0=9C=D0=A2=D0=A0?=',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset="utf-8"',
      '',
      'x',
    ]);

    test('имена отправителя и получателя раскодированы', () {
      final m = EmlReader.parse(broken);
      expect(m.from.single.name, 'Мисюра Артем');
      expect(m.to.single.name, 'Шулов Сергей');
      expect(m.subject, 'МТР');
    });

    test('обычные заголовки не меняются', () {
      const ok = 'Subject: =?utf-8?Q?=D0=90?=\r\n =?utf-8?Q?=D0=91?=\r\nTo: a@b.ru';
      expect(EmlReader.repairEncodedWords(ok), ok);
      expect(EmlReader.repairEncodedWords('Subject: =?broken'), 'Subject: =?broken');
    });
  });

  group('Заголовки в UTF-8 без кодирования (1.8.6)', () {
    test('тема и имена — кириллицей, а не «Ð¡Ðµ…»', () {
      final eml = utf8.encode('From: Иванов Сергей <s.ivanov@corp.example>\r\n'
          'To: Петрова Анна <a.petrova@corp.example>\r\n'
          'Subject: RE: Работы с установкой\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'Коллеги, доброе утро!\r\n');
      final m = EmlReader.parse(Uint8List.fromList(eml));
      expect(m.subject, 'RE: Работы с установкой');
      expect(m.from.first.name, 'Иванов Сергей');
      expect(m.to.first.name, 'Петрова Анна');
    });

    test('fix8bit не трогает правильный текст', () {
      expect(EmlReader.fix8bit('Сергей'), 'Сергей');
      expect(EmlReader.fix8bit('Café'), 'Café');
      expect(EmlReader.fix8bit('plain'), 'plain');
    });
  });
}

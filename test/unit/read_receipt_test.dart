// Отчёты о прочтении (2.2.0, план 08.11.2026 «из мессенджеров»: ✓/✓✓
// «прочитано» по отчётам о прочтении). Образцы — по форме настоящих
// отчётов RFC 8098 (Thunderbird, Outlook) и «Прочитано:» Exchange (адреса
// вымышленные).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/services/mail/delivery/delivery_report.dart';

String _crlf(String s) => s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

final _mdn = _crlf('''
From: Anna Smirnova <anna@partner.example>
To: me@corp.example
Subject: Read: Contract draft
Date: Mon, 9 Nov 2026 09:12:00 +0300
Message-ID: <mdn-1@partner.example>
In-Reply-To: <orig-42@corp.example>
MIME-Version: 1.0
Content-Type: multipart/report; report-type=disposition-notification;
	boundary="MDN"

--MDN
Content-Type: text/plain; charset=utf-8

This is a Return Receipt for the mail that you sent to anna@partner.example.

--MDN
Content-Type: message/disposition-notification

Reporting-UA: partner.example; Thunderbird
Final-Recipient: rfc822;anna@partner.example
Original-Message-ID: <Orig-42@corp.example>
Disposition: manual-action/MDN-sent-manually; displayed

--MDN--
''');

final _deleted = _mdn.replaceAll('; displayed', '; deleted');

final _exchange = _crlf('''
From: =?utf-8?B?0JjQstCw0L0g0J/QtdGC0YDQvtCy?= <ivan@corp.example>
To: me@corp.example
Subject: =?utf-8?B?0J/RgNC+0YfQuNGC0LDQvdC+OiDQodC80LXRgtCw?=
Message-ID: <rr-7@corp.example>
In-Reply-To: <orig-7@corp.example>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Ваше сообщение
  Кому: Иван Петров
  Тема: Смета
было прочитано 09.11.2026 9:30.
''');

void main() {
  test('RFC 8098: «открыл» — прочитано, письмо — по Original-Message-ID', () {
    final r = DeliveryReportParser.parse(_mdn, own: const ['me@corp.example'])!;
    expect(r.originalMessageId, 'orig-42@corp.example');
    expect(r.recipients.single.recipient, 'anna@partner.example');
    expect(r.recipients.single.action, DeliveryAction.read);
    expect(r.recipients.single.reason, DeliveryReason.read);
  });

  test('«удалено, не читая» — не отметка', () {
    expect(DeliveryReportParser.parse(_deleted, own: const ['me@corp.example']), isNull);
  });

  test('Exchange «Прочитано: тема» без машинной части — по In-Reply-To', () {
    final r = DeliveryReportParser.parse(_exchange, own: const ['me@corp.example'])!;
    expect(r.originalMessageId, 'orig-7@corp.example');
    expect(r.recipients.single.recipient, 'ivan@corp.example');
    expect(r.recipients.single.action, DeliveryAction.read);
  });

  test('кандидаты: тема «Прочитано:» и report-type disposition-notification', () {
    expect(DeliveryReportParser.isCandidate(fromEmail: 'ivan@corp.example', subject: 'Прочитано: Смета'), isTrue);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'anna@partner.example', subject: 'Read: Contract draft'), isTrue);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'anna@partner.example', subject: 'Readme: план'), isFalse);
    expect(DeliveryReportHints.isReportType('multipart/report', 'disposition-notification'), isTrue);
  });

  test('обычное письмо «Прочитано: …» без ссылки на письмо — не отчёт', () {
    final plain = _exchange.replaceAll('In-Reply-To: <orig-7@corp.example>\r\n', '');
    expect(DeliveryReportParser.parse(plain, own: const ['me@corp.example']), isNull);
  });

  group('база', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('«прочитано» поздний «доставлено» не отменяет; ✓ и ✓✓ по письмам', () async {
      await db.saveDeliveryStatuses('a1', 'm1@x', [(recipient: 'a@x', action: 'read', status: null, diagnostic: null)]);
      await db.saveDeliveryStatuses('a1', 'm1@x',
          [(recipient: 'a@x', action: 'delivered', status: '2.0.0', diagnostic: null)]);
      await db.saveDeliveryStatuses('a1', 'm2@x',
          [(recipient: 'b@x', action: 'delivered', status: '2.0.0', diagnostic: null)]);
      await db.saveDeliveryStatuses('a1', 'm3@x',
          [(recipient: 'c@x', action: 'failed', status: '5.1.1', diagnostic: null)]);
      final ticks = await db.watchDeliveryTicks().first;
      expect(ticks, {'a1|m1@x': true, 'a1|m2@x': false});
    });
  });
}

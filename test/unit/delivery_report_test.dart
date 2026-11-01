// test/unit/delivery_report_test.dart
// Отчёты о доставке (1.9.x, просьба владельца 31.10.2026): разбор DSN
// RFC 3464 и нестандартных «недоставленных» — образцы по форме настоящих
// отчётов Postfix, Exim, Gmail, Exchange, Яндекса и Mail.ru (адреса и имена
// вымышленные).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/delivery/delivery_report.dart';

String _crlf(String s) => s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

String _b64(String s) => base64.encode(utf8.encode(s));

String _word(String s) => '=?utf-8?B?${_b64(s)}?=';

final _postfix = _crlf('''
Return-Path: <>
From: MAILER-DAEMON@mail.example.org (Mail Delivery System)
Subject: Undelivered Mail Returned to Sender
To: me@example.com
Auto-Submitted: auto-replied
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status;
	boundary="ABC123"
Message-Id: <20261031101500.ABC@mail.example.org>

This is a MIME-encapsulated message.

--ABC123
Content-Description: Notification
Content-Type: text/plain; charset=us-ascii

This is the mail system at host mail.example.org.

I'm sorry to have to inform you that your message could not
be delivered to one or more recipients. It's attached below.

<nobody@example.net>: host mx.example.net[192.0.2.1] said: 550 5.1.1
    <nobody@example.net>: Recipient address rejected: User unknown in virtual
    mailbox table (in reply to RCPT TO command)

--ABC123
Content-Description: Delivery report
Content-Type: message/delivery-status

Reporting-MTA: dns; mail.example.org
X-Postfix-Queue-ID: ABC
X-Postfix-Sender: rfc822; me@example.com
Arrival-Date: Sat, 31 Oct 2026 10:14:58 +0300 (MSK)

Final-Recipient: rfc822; nobody@example.net
Original-Recipient: rfc822;nobody@example.net
Action: failed
Status: 5.1.1
Remote-MTA: dns; mx.example.net
Diagnostic-Code: smtp; 550 5.1.1 <nobody@example.net>: Recipient address
    rejected: User unknown in virtual mailbox table

--ABC123
Content-Description: Undelivered Message Headers
Content-Type: text/rfc822-headers

Return-Path: <me@example.com>
From: Me <me@example.com>
To: nobody@example.net
Subject: Hello
Message-ID: <Orig-1@example.com>
Date: Sat, 31 Oct 2026 10:14:50 +0300

--ABC123--
''');

final _exim = _crlf('''
From: Mail Delivery System <Mailer-Daemon@exim.example.org>
To: me@example.com
Subject: Mail delivery failed: returning message to sender
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

This message was created automatically by mail delivery software.

A message that you sent could not be delivered to one or more of its
recipients. This is a permanent error. The following address(es) failed:

  ghost@example.net
    host mx.example.net [192.0.2.7]
    SMTP error from remote mail server after RCPT TO:<ghost@example.net>:
    552 5.2.2 Mailbox full

------ This is a copy of the message, including all the headers. ------

Return-path: <me@example.com>
Received: from [192.0.2.10] by exim.example.org
Message-ID: <orig-2@example.com>
From: me@example.com
To: ghost@example.net, other@example.net
Subject: Test

Body
''');

final _gmail = _crlf('''
From: Mail Delivery Subsystem <mailer-daemon@googlemail.com>
To: me@gmail.com
Subject: Delivery Status Notification (Failure)
In-Reply-To: <orig-3@mail.gmail.com>
References: <orig-3@mail.gmail.com>
MIME-Version: 1.0
Content-Type: multipart/report; boundary="000"; report-type=delivery-status

--000
Content-Type: multipart/related; boundary="111"

--111
Content-Type: multipart/alternative; boundary="222"

--222
Content-Type: text/plain; charset="UTF-8"

** Address not found **

Your message wasn't delivered to nouser@example.org because the address couldn't be found.

--222--
--111--
--000
Content-Type: message/delivery-status

Reporting-MTA: dns; googlemail.com
Received-From-MTA: dns; me@gmail.com
Arrival-Date: Sat, 31 Oct 2026 01:02:03 -0700 (PDT)

Final-Recipient: rfc822; nouser@example.org
Action: failed
Status: 5.1.1
Remote-MTA: dns; mx.example.org. (192.0.2.9, the server for the domain example.org.)
Diagnostic-Code: smtp; 550-5.1.1 The email account that you tried to reach does
 not exist.
Last-Attempt-Date: Sat, 31 Oct 2026 01:02:04 -0700 (PDT)

--000
Content-Type: message/rfc822

Message-ID: <orig-3@mail.gmail.com>
Subject: Hi
From: me@gmail.com
To: nouser@example.org

hi
--000--
''');

final _exchange = _crlf('''
From: Microsoft Outlook <MicrosoftExchange329e71ec88ae4615bbc36ab6ce41109e@contoso.onmicrosoft.com>
To: me@contoso.example
Subject: Undeliverable: Report
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status;
	boundary="_b_"

--_b_
Content-Type: multipart/alternative; boundary="_a_"

--_a_
Content-Type: text/plain; charset="us-ascii"

Your message to blocked@fabrikam.example couldn't be delivered.

--_a_
Content-Type: text/html; charset="us-ascii"

<html><body><p>Your message to blocked@fabrikam.example couldn't be delivered.</p></body></html>
--_a_--

--_b_
Content-Type: message/delivery-status

Reporting-MTA: dns;AM0PR01MB1234.eurprd01.prod.exchangelabs.com
Arrival-Date: Sat, 31 Oct 2026 08:00:00 +0000

Original-Recipient: rfc822;blocked@fabrikam.example
Final-Recipient: rfc822;blocked@fabrikam.example
Action: failed
Status: 5.7.1
Diagnostic-Code: smtp;550 5.7.1 Service unavailable, Client host [192.0.2.3] blocked using Spamhaus
Remote-MTA: dns;mx.fabrikam.example

Original-Recipient: rfc822;me@contoso.example
Final-Recipient: rfc822;me@contoso.example
Action: failed
Status: 5.1.1

--_b_
Content-Type: message/rfc822

Message-ID: <AM0PR01MB1234ABC@AM0PR01MB1234.eurprd01.prod.exchangelabs.com>
From: Me <me@contoso.example>
To: blocked@fabrikam.example
Subject: Report

text
--_b_--
''');

final _yandex = _crlf('''
From: mailer-daemon@yandex.ru
To: me@yandex.ru
Subject: ${_word('Недоставленное сообщение')}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="y"

--y
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64

${_b64('Это письмо отправлено вам роботом почтовой службы Яндекса.\n\n'
    'Ваше письмо не удалось доставить по одному или нескольким адресам.\n\n'
    '<petrov@example.ru>: host mx.example.ru[192.0.2.5] said: 550 5.1.1 No such user\n')}
--y
Content-Type: message/rfc822

Message-ID: <12345@mail.yandex.ru>
From: me@yandex.ru
To: petrov@example.ru
Subject: Hi

text
--y--
''');

final _mailru = _crlf('''
From: Mail Delivery System <mailer-daemon@corp.mail.ru>
To: me@mail.ru
Subject: ${_word('Сообщение не доставлено')}
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64

${_b64('Это письмо создано автоматически сервером Mail.ru.\n\n'
    'Не удалось доставить письмо следующим адресатам:\n\n'
    '  spamtrap@example.com\n'
    '    SMTP error from remote mail server after end of data:\n'
    '    550 5.7.1 Message rejected as spam\n\n'
    '------ This is a copy of the message, including all the headers. ------\n\n'
    'Message-ID: <77@mail.ru>\n'
    'From: me@mail.ru\n'
    'To: spamtrap@example.com\n\n'
    'Привет\n')}
''');

final _delayed = _crlf('''
From: MAILER-DAEMON@mail.example.org (Mail Delivery System)
To: me@example.com
Subject: Delayed Mail (still being retried)
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status; boundary="D"

--D
Content-Type: text/plain

This is the mail system at host mail.example.org.
Your message could not be delivered for more than 4 hour(s). It will be retried.

--D
Content-Type: message/delivery-status

Reporting-MTA: dns; mail.example.org

Final-Recipient: rfc822; slow@example.net
Action: delayed
Status: 4.4.1
Diagnostic-Code: X-Postfix; connect to mx.example.net[192.0.2.2]:25: Connection timed out
Will-Retry-Until: Wed, 4 Nov 2026 10:00:00 +0300

--D
Content-Type: text/rfc822-headers

Message-ID: <orig-7@example.com>
From: me@example.com
To: slow@example.net

--D--
''');

final _success = _crlf('''
From: MAILER-DAEMON@mail.example.org (Mail Delivery System)
To: me@example.com
Subject: Successful Mail Delivery Report
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status; boundary="S"

--S
Content-Type: text/plain

Your message was successfully delivered to the destination(s) listed below.

--S
Content-Type: message/delivery-status

Reporting-MTA: dns; mail.example.org
Original-Envelope-Id: orig-8+2Bx@example.com

Final-Recipient: rfc822; ok@example.net
Action: relayed
Status: 2.0.0
Remote-MTA: dns; mx.example.net

--S--
''');

void main() {
  test('Postfix (RFC 3464): адресат, код, ответ сервера, исходное письмо', () {
    final r = DeliveryReportParser.parse(_postfix)!;
    expect(r.standard, isTrue);
    expect(r.originalMessageId, 'orig-1@example.com');
    final x = r.recipients.single;
    expect(x.recipient, 'nobody@example.net');
    expect(x.action, DeliveryAction.failed);
    expect(x.status, '5.1.1');
    expect(x.diagnostic, contains('User unknown in virtual mailbox table'));
    expect(x.reason, DeliveryReason.noSuchUser);
  });

  test('Exim (только текст): адресат до копии письма, ящик переполнен', () {
    final r = DeliveryReportParser.parse(_exim, own: ['me@example.com'])!;
    expect(r.standard, isFalse);
    expect(r.originalMessageId, 'orig-2@example.com');
    // other@example.net — только в копии письма, это не адресат отчёта.
    expect(r.recipients.map((e) => e.recipient), ['ghost@example.net']);
    expect(r.recipients.single.status, '5.2.2');
    expect(r.recipients.single.reason, DeliveryReason.mailboxFull);
    expect(r.recipients.single.diagnostic, contains('552 5.2.2 Mailbox full'));
  });

  test('Gmail: продолжение строки ответа и вложенное письмо', () {
    final r = DeliveryReportParser.parse(_gmail)!;
    expect(r.originalMessageId, 'orig-3@mail.gmail.com');
    expect(r.recipients.single.recipient, 'nouser@example.org');
    expect(r.recipients.single.diagnostic, contains('does not exist'));
    expect(r.recipients.single.reason, DeliveryReason.noSuchUser);
  });

  test('Exchange NDR: блокировка как спам, свой адрес не адресат', () {
    final r = DeliveryReportParser.parse(_exchange, own: ['me@contoso.example'])!;
    expect(r.originalMessageId, 'am0pr01mb1234abc@am0pr01mb1234.eurprd01.prod.exchangelabs.com');
    expect(r.recipients.map((e) => e.recipient), ['blocked@fabrikam.example']);
    expect(r.recipients.single.reason, DeliveryReason.blocked);
  });

  test('Яндекс: русский текст в base64, адресат и код', () {
    final r = DeliveryReportParser.parse(_yandex, own: ['me@yandex.ru'])!;
    expect(r.originalMessageId, '12345@mail.yandex.ru');
    expect(r.recipients.single.recipient, 'petrov@example.ru');
    expect(r.recipients.single.action, DeliveryAction.failed);
    expect(r.recipients.single.status, '5.1.1');
  });

  test('Mail.ru: письмо отклонено как спам, исходное письмо из копии в тексте', () {
    final r = DeliveryReportParser.parse(_mailru, own: ['me@mail.ru'])!;
    expect(r.originalMessageId, '77@mail.ru');
    expect(r.recipients.single.recipient, 'spamtrap@example.com');
    expect(r.recipients.single.reason, DeliveryReason.blocked);
  });

  test('Задержка: действие delayed, причина — повтор', () {
    final r = DeliveryReportParser.parse(_delayed)!;
    expect(r.originalMessageId, 'orig-7@example.com');
    expect(r.recipients.single.action, DeliveryAction.delayed);
    expect(r.recipients.single.reason, DeliveryReason.delayed);
    expect(r.recipients.single.isFinal, isFalse);
  });

  test('Успешная доставка: ENVID в xtext — ключ к исходному письму', () {
    final r = DeliveryReportParser.parse(_success)!;
    expect(r.originalMessageId, isNull);
    expect(r.envelopeId, 'orig-8+x@example.com');
    expect(r.messageIds, ['orig-8+x@example.com']);
    expect(r.recipients.single.action, DeliveryAction.relayed);
    expect(r.recipients.single.reason, DeliveryReason.delivered);
  });

  test('Обычное письмо со словами «не доставлено» отчётом не считается', () {
    final mail = _crlf('''
From: Colleague <colleague@example.com>
To: me@example.com
Subject: ${_word('Письмо не доставлено?')}
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64

${_b64('Похоже, моё письмо не доставлено до client@example.org — проверь, пожалуйста.')}
''');
    expect(
        DeliveryReportParser.isCandidate(
            fromEmail: 'colleague@example.com', subject: 'Письмо не доставлено?'),
        isTrue);
    expect(DeliveryReportParser.parse(mail), isNull);
  });

  test('Кандидаты: робот-отправитель, тема отчёта, структура multipart/report', () {
    expect(DeliveryReportParser.isCandidate(fromEmail: 'MAILER-DAEMON@x.org', subject: 'x'), isTrue);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'a@b.c', fromName: 'Mail Delivery Subsystem', subject: 'x'),
        isTrue);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'a@b.c', subject: 'Undeliverable: Отчёт'), isTrue);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'a@b.c', subject: 'Отчёт за октябрь'), isFalse);
    expect(DeliveryReportParser.isCandidate(fromEmail: 'a@b.c', subject: 'x', reportType: true), isTrue);
    expect(DeliveryReportHints.isReportType('multipart/report', 'delivery-status'), isTrue);
    expect(DeliveryReportHints.isReportType('multipart/report', 'disposition-notification'), isFalse);
  });

  test('Причины по коду и тексту ответа', () {
    DeliveryReason r(String? s, String? d) => DeliveryReport.reasonOf(DeliveryAction.failed, s, d);
    expect(r('5.1.2', null), DeliveryReason.domainNotFound);
    expect(r('5.4.4', null), DeliveryReason.domainNotFound);
    expect(r('5.2.2', null), DeliveryReason.mailboxFull);
    expect(r('5.3.4', null), DeliveryReason.tooLarge);
    expect(r(null, '552 Requested action aborted: exceeded storage allocation, quota exceeded'),
        DeliveryReason.mailboxFull);
    expect(r(null, 'Host or domain name not found'), DeliveryReason.domainNotFound);
    expect(r('5.0.0', 'something odd'), DeliveryReason.other);
    expect(DeliveryReport.normalizeMessageId(' <AbC@Example.COM> '), 'abc@example.com');
    expect(DeliveryReport.normalizeMessageId('no-at-sign'), isNull);
  });
}

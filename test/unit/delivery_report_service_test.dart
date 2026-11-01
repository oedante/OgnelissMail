// test/unit/delivery_report_service_test.dart
// Отчёты о доставке в синхронизации (1.9.x, просьба владельца 31.10.2026):
// отчёт находит своё отправленное письмо по Message-ID, статусы адресатов
// сохраняются, о свежей недоставке — одно уведомление, обычное «новое
// письмо» о письме робота не нужно.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/delivery/delivery_report.dart';
import 'package:ogneliss/services/mail/delivery/delivery_report_service.dart';

String _dsn(String action, String status, {String mid = '<orig-1@example.com>'}) => '''
From: MAILER-DAEMON@mail.example.org (Mail Delivery System)
To: me@example.com
Subject: Undelivered Mail Returned to Sender
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status; boundary="B"

--B
Content-Type: text/plain

Your message could not be delivered.

--B
Content-Type: message/delivery-status

Reporting-MTA: dns; mail.example.org

Final-Recipient: rfc822; nobody@example.net
Action: $action
Status: $status
Diagnostic-Code: smtp; 550 $status User unknown

--B
Content-Type: text/rfc822-headers

Message-ID: $mid
From: me@example.com
To: nobody@example.net

--B--
'''
    .replaceAll('\n', '\r\n');

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 10, 31, 12);
  final account = AccountModel(
      id: 'a1', type: AccountType.imap, email: 'me@example.com', displayName: 'Me', username: 'me', createdAt: now);

  EmailModel bounce(String id, {String from = 'MAILER-DAEMON@mail.example.org', String subject = 'Undelivered Mail Returned to Sender'}) =>
      EmailModel(
        id: id,
        accountId: 'a1',
        folderId: 'INBOX',
        from: EmailAddress(email: from),
        to: const [EmailAddress(email: 'me@example.com')],
        subject: subject,
        receivedAt: now,
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@example.com', displayName: 'Me', username: 'me', createdAt: now));
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'Sent:5',
          accountId: 'a1',
          folderId: 'Sent',
          fromEmail: 'me@example.com',
          toRecipients: '[{"email":"nobody@example.net"}]',
          subject: 'Отчёт за октябрь',
          receivedAt: now.subtract(const Duration(hours: 1)),
          sentAt: Value(now.subtract(const Duration(hours: 1))),
          internetMessageId: const Value('<orig-1@example.com>'),
        ));
  });

  tearDown(() => db.close());

  test('недоставка: статус у своего письма, одно уведомление, отчёт без обычного уведомления', () async {
    final failures = <DeliveryFailure>[];
    final fetched = <String>[];
    final handled = await DeliveryReportService.process(
      db: db,
      account: account,
      fresh: [
        bounce('INBOX:9'),
        // Обычное письмо не скачивается.
        bounce('INBOX:10', from: 'boss@example.com', subject: 'План'),
      ],
      isNew: {'INBOX:9', 'INBOX:10'},
      fetchRaw: (e) async {
        fetched.add(e.id);
        return _dsn('failed', '5.1.1');
      },
      onFailure: (f) async => failures.add(f),
      now: now,
    );
    expect(fetched, ['INBOX:9']);
    expect(handled, {'INBOX:9'});
    expect(failures.single.original.id, 'Sent:5');
    expect(failures.single.failed.single.recipient, 'nobody@example.net');
    expect(failures.single.failed.single.reason, DeliveryReason.noSuchUser);
    final rows = await db.watchDeliveryStatuses('a1', 'orig-1@example.com').first;
    expect(rows.single.action, 'failed');
    expect(rows.single.status, '5.1.1');
    expect(rows.single.reportEmailId, 'INBOX:9');
    expect(await db.watchUndelivered().first, {'a1|orig-1@example.com'});

    // Тот же отчёт во второй папке — повторного уведомления нет.
    final again = await DeliveryReportService.process(
      db: db,
      account: account,
      fresh: [bounce('All:3')],
      isNew: {'All:3'},
      fetchRaw: (_) async => _dsn('failed', '5.1.1'),
      onFailure: (f) async => failures.add(f),
      now: now,
    );
    expect(again, {'All:3'});
    expect(failures, hasLength(1));
  });

  test('задержка: без уведомления, обычное уведомление о письме робота не нужно', () async {
    final failures = <DeliveryFailure>[];
    final handled = await DeliveryReportService.process(
      db: db,
      account: account,
      fresh: [bounce('INBOX:11', subject: 'Delayed Mail (still being retried)')],
      isNew: {'INBOX:11'},
      fetchRaw: (_) async => _dsn('delayed', '4.4.1'),
      onFailure: (f) async => failures.add(f),
      now: now,
    );
    expect(handled, {'INBOX:11'});
    expect(failures, isEmpty);
    expect((await db.watchDeliveryStatuses('a1', 'orig-1@example.com').first).single.action, 'delayed');
    expect(await db.watchUndelivered().first, isEmpty);
  });

  test('своего письма нет: статус сохраняется, уведомление — обычное', () async {
    final handled = await DeliveryReportService.process(
      db: db,
      account: account,
      fresh: [bounce('INBOX:12')],
      isNew: {'INBOX:12'},
      fetchRaw: (_) async => _dsn('failed', '5.2.2', mid: '<unknown@example.com>'),
      now: now,
    );
    expect(handled, isEmpty);
    expect((await db.watchDeliveryStatuses('a1', 'unknown@example.com').first).single.status, '5.2.2');
  });

  test('сбой скачивания не мешает остальным письмам', () async {
    final handled = await DeliveryReportService.process(
      db: db,
      account: account,
      fresh: [bounce('INBOX:13')],
      fetchRaw: (_) async => throw StateError('нет связи'),
      now: now,
    );
    expect(handled, isEmpty);
  });
}

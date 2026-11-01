// test/unit/imap_notify_test.dart
// Push IMAP по NOTIFY (RFC 5465; 1.9.x, просьба владельца 31.10.2026): одно
// соединение сообщает об изменениях во всех синхронизируемых папках.
// В enough_mail команды NOTIFY нет — её отправляет NotifyImapClient
// (наследник ImapClient, без правок пакета). Сервер — поддельный
// (fake_imap_server.dart).

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show ImapNotifyChange, NotifyImapClient;
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

const _events = '(MessageNew MessageExpunge FlagChange)';

void main() {
  group('команда и разбор ответов', () {
    test('NOTIFY SET: выбранная папка и остальные списком', () {
      expect(NotifyImapClient.notifySetCommand(['Archive', 'Lists/Dev']),
          'NOTIFY SET (SELECTED $_events) (MAILBOXES ("Archive" "Lists/Dev") $_events)');
      expect(NotifyImapClient.notifySetCommand(const []), 'NOTIFY SET (SELECTED $_events)');
      expect(NotifyImapClient.notifySetCommand(['A'], flagChanges: false),
          'NOTIFY SET (SELECTED (MessageNew MessageExpunge)) (MAILBOXES ("A") (MessageNew MessageExpunge))');
    });

    test('кавычки экранируются, не-ASCII пропускается, много папок — PERSONAL', () {
      expect(NotifyImapClient.notifySetCommand([r'a"b\c', 'Папка', '&BB8EMARABDoEMA-']),
          'NOTIFY SET (SELECTED $_events) (MAILBOXES ("a\\"b\\\\c" "&BB8EMARABDoEMA-") $_events)');
      final many = [for (var i = 0; i < NotifyImapClient.maxMailboxes + 1; i++) 'F$i'];
      expect(NotifyImapClient.notifySetCommand(many), 'NOTIFY SET (SELECTED $_events) (PERSONAL $_events)');
    });

    test('STATUS другой папки и переполнение', () {
      ImapNotifyChange? p(String s) => NotifyImapClient.parseNotifyLine(s);
      expect(p('* STATUS "Archive" (MESSAGES 4 UIDNEXT 5)')!.mailbox, 'Archive');
      expect(p(r'* STATUS "a\"b" (MESSAGES 1)')!.mailbox, 'a"b');
      expect(p('* status Lists/Dev (UNSEEN 2)')!.mailbox, 'Lists/Dev');
      expect(p('* OK [NOTIFICATIONOVERFLOW] too many')!.overflow, isTrue);
      expect(p('* 3 EXISTS'), isNull);
      expect(p('* OK still here'), isNull);
      expect(p('a5 OK done'), isNull);
      expect(p('* STATUS "unterminated (MESSAGES 1)'), isNull);
    });
  });

  group('push (ImapService.startIdle)', () {
    late FakeImapServer srv;
    late ImapService imap;
    late List<ImapPushEvent> events;
    StreamSubscription<ImapPushEvent>? sub;

    AccountModel account() => AccountModel(
          id: 'a1',
          type: AccountType.imap,
          email: 'me@example.com',
          displayName: 'Me',
          username: 'me@example.com',
          imapServer: '127.0.0.1',
          imapPort: srv.port,
          imapEncryption: EncryptionType.none,
          createdAt: DateTime(2026),
        );

    Future<void> serve(String caps) async {
      srv = FakeImapServer(caps: caps);
      srv.box('INBOX');
      srv.box('Archive');
      await srv.start();
    }

    void listen({List<String> watch = const ['Archive']}) {
      events = [];
      sub = imap.startIdle(account(), 'INBOX', watch: () async => watch).listen(events.add);
    }

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({'pwd_a1': 'secret'});
      imap = ImapService(SecureStorageService());
    });

    tearDown(() async {
      await imap.stopIdle('a1');
      await sub?.cancel();
      sub = null;
      imap.dispose();
      await srv.close();
    });

    test('сервер с NOTIFY: изменения в других папках и флаги — по одному соединению', () async {
      await serve('IMAP4rev1 IDLE NOTIFY');
      listen();
      await srv.waitIdle();
      expect(srv.commands, contains('NOTIFY SET (SELECTED $_events) (MAILBOXES ("Archive") $_events)'));
      expect(srv.commands.indexOf('IDLE'), greaterThan(srv.commands.indexWhere((c) => c.startsWith('NOTIFY'))));

      srv.pushToIdle('* STATUS "Archive" (MESSAGES 1 UIDNEXT 2)');
      await waitFor(() => events.isNotEmpty);
      expect(events.single.folderId, 'Archive');
      expect(events.single.count, ImapPushEvent.changed);

      srv.pushToIdle('* 1 EXISTS');
      await waitFor(() => events.length == 2);
      expect(events[1].folderId, 'INBOX');
      expect(events[1].count, 1);

      // Флаги письма во «Входящих» (FlagChange).
      srv.pushToIdle(r'* 1 FETCH (FLAGS (\Seen))');
      await waitFor(() => events.length == 3);
      expect(events[2].folderId, 'INBOX');
      expect(events[2].count, ImapPushEvent.changed);
    });

    test('письмо, о котором сервер сообщил в ответ на NOTIFY, не теряется', () async {
      await serve('IMAP4rev1 IDLE NOTIFY');
      srv.beforeNotifyOk.add('* 1 EXISTS');
      listen();
      await srv.waitIdle();
      await waitFor(() => events.isNotEmpty);
      expect(events.single.folderId, 'INBOX');
      expect(events.single.count, ImapPushEvent.changed);
    });

    test('переполнение: синхронизировать всё и включить NOTIFY заново', () async {
      await serve('IMAP4rev1 IDLE NOTIFY');
      listen(watch: ['Archive', 'Sent']);
      await srv.waitIdle();
      srv.pushToIdle('* OK [NOTIFICATIONOVERFLOW] notifications lost');
      await waitFor(() => events.length == 3);
      expect(events.map((e) => e.folderId), ['INBOX', 'Archive', 'Sent']);
      await waitFor(() => srv.commands.where((c) => c.startsWith('NOTIFY')).length == 2);
      // Соединение снова в IDLE: остановка между NOTIFY и IDLE ждала ответа
      // на DONE до тайм-аута (в CI тест упирался в 30 с).
      await srv.waitIdle();
    });

    test('NOTIFY отклонён — обычный IDLE, письма во «Входящих» по-прежнему видны', () async {
      await serve('IMAP4rev1 IDLE NOTIFY');
      srv.rejectNotify = true;
      listen();
      await srv.waitIdle();
      // С изменением флагов и без него — затем обычный IDLE.
      expect(srv.commands.where((c) => c.startsWith('NOTIFY')), hasLength(2));
      srv.pushToIdle('* STATUS "Archive" (MESSAGES 1)');
      srv.pushToIdle('* 1 EXISTS');
      await waitFor(() => events.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events.map((e) => (e.folderId, e.count)), [('INBOX', 1)]);
    });

    test('сервер без NOTIFY — команда не отправляется, IDLE как раньше', () async {
      await serve('IMAP4rev1 IDLE');
      listen();
      await srv.waitIdle();
      expect(srv.commands.where((c) => c.startsWith('NOTIFY')), isEmpty);
      srv.pushToIdle(r'* 1 FETCH (FLAGS (\Seen))');
      srv.pushToIdle('* 1 EXISTS');
      await waitFor(() => events.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Изменение флагов без NOTIFY не будит синхронизацию — как раньше.
      expect(events.map((e) => (e.folderId, e.count)), [('INBOX', 1)]);
    });
  });
}

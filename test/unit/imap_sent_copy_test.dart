// test/unit/imap_sent_copy_test.dart
// Копия отправленного письма в «Отправленных» (2.3.2). Журналы двух ящиков
// Яндекса 10–11.11.2026: после отправки копии в папке нет; пользователь —
// «перехожу в папку отправленные и там нет писем отправленных через
// огнелисс». Раньше считалось, что Яндекс, Mail.ru и Yahoo кладут копию
// сами, и приложение её не сохраняло.
//
// Сервер IMAP — поддельный (fake_imap_server.dart): копии нет — приложение
// кладёт её; копия уже есть (сервер положил сам) — второй не появляется.

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeImapServer srv;
  late ImapService imap;
  late FakeMailbox sent;

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

  MimeMessage letter() => ImapService.buildOutgoingMessage(
        fromName: 'Me',
        fromEmail: 'me@example.com',
        to: const [EmailAddress(email: 'anna@example.com', displayName: 'Anna')],
        subject: 'Test',
        bodyHtml: '<p>Hello</p>',
      );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'pwd_a1': 'secret'});
    imap = ImapService(SecureStorageService());
    ImapService.sentCopyWait = const Duration(milliseconds: 20);
    srv = FakeImapServer(caps: 'IMAP4rev1 IDLE', capsAtLogin: true);
    srv.box('INBOX');
    sent = srv.box('Sent', listFlags: r'\Sent');
    await srv.start();
  });

  tearDown(() async {
    imap.dispose();
    await srv.close();
  });

  test('кому нужна проверка: Яндекс, Mail.ru, Yahoo', () {
    expect(ImapService.sentCopyNeedsCheck(AccountType.yandex), isTrue);
    expect(ImapService.sentCopyNeedsCheck(AccountType.mailru), isTrue);
    expect(ImapService.sentCopyNeedsCheck(AccountType.yahoo), isTrue);
    expect(ImapService.sentCopyNeedsCheck(AccountType.google), isFalse, reason: 'Gmail кладёт копию всегда');
    expect(ImapService.sentCopyNeedsCheck(AccountType.imap), isFalse, reason: 'сохраняем сразу, без проверки');
  });

  test('сервер копию не положил (как Яндекс) — приложение сохраняет её само', () async {
    final m = letter();
    final id = m.getHeaderValue('message-id')!;
    await imap.saveSentCopy(account(), m, verify: true);
    expect(sent.messages, hasLength(1));
    expect(sent.messages.single.messageId, id);
    expect(sent.messages.single.flags, contains(r'\Seen'));
    expect(srv.commands.where((c) => c.startsWith('UID SEARCH HEADER Message-ID')), hasLength(2),
        reason: 'две проверки до сохранения');
    expect(srv.commands.where((c) => c.startsWith('APPEND Sent')), hasLength(1));
  });

  test('сервер положил копию сам — второй не появляется', () async {
    final m = letter();
    sent.add('Test', messageId: m.getHeaderValue('message-id'));
    await imap.saveSentCopy(account(), m, verify: true);
    expect(sent.messages, hasLength(1));
    expect(srv.commands.where((c) => c.startsWith('APPEND ')), isEmpty);
  });

  test('обычный IMAP — копия сохраняется сразу, без поиска', () async {
    await imap.saveSentCopy(account(), letter(), verify: false);
    expect(sent.messages, hasLength(1));
    expect(srv.commands.where((c) => c.startsWith('UID SEARCH')), isEmpty);
  });
}

// «На контроле» и «Позже» на IMAP-сервере (решение владельца 13.11.2026):
// ключевые слова $OgnControl и $OgnLater на письме — записываются командой
// UID STORE и читаются при синхронизации папки; сервер без своих флагов
// (PERMANENTFLAGS без «\*») — отметки остаются на устройстве.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeImapServer srv;
  late ImapService imap;
  late FakeMailbox inbox;

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

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'pwd_a1': 'secret'});
    imap = ImapService(SecureStorageService());
    srv = FakeImapServer(caps: 'IMAP4rev1 IDLE', capsAtLogin: true);
    inbox = srv.box('INBOX');
    await srv.start();
  });

  tearDown(() async {
    imap.dispose();
    await srv.close();
  });

  test('флаги ставятся и снимаются на письме', () async {
    srv.permanentFlags = r'(\Seen \Flagged \Deleted \*)';
    final m = inbox.add('Отчёт');
    expect(await imap.setMarks(account(), folderId: 'INBOX', uid: '${m.uid}', control: true, later: true), isTrue);
    expect(m.flags, containsAll([ImapService.kwControl, ImapService.kwLater]));
    await imap.setMarks(account(), folderId: 'INBOX', uid: '${m.uid}', control: false);
    expect(m.flags, isNot(contains(ImapService.kwControl)));
    expect(m.flags, contains(ImapService.kwLater));
  });

  test('сервер без своих флагов — false, на письме ничего', () async {
    srv.permanentFlags = r'(\Seen \Flagged \Deleted)';
    final m = inbox.add('Отчёт');
    expect(await imap.setMarks(account(), folderId: 'INBOX', uid: '${m.uid}', control: true), isFalse);
    expect(m.flags, isNot(contains(ImapService.kwControl)));
  });

  test('синхронизация: отметки новых писем и изменённые флаги прежних', () async {
    final a = inbox.add('Первое')..flags.add(ImapService.kwLater);
    final b = inbox.add('Второе');
    final first = await imap.syncFolderDelta(account(), folderId: 'INBOX');
    expect(first.added.length, 2);
    final hints = ImapMarkHints.take('a1');
    expect(hints, {'INBOX:${a.uid}': 2});
    // На другом устройстве поставили «На контроле» второму письму.
    b.flags.add(ImapService.kwControl);
    b.modSeq++;
    final next = await imap.syncFolderDelta(account(), folderId: 'INBOX', known: first.state);
    expect(next.flags[b.uid]?.marks, 1);
    expect(next.flags[a.uid]?.marks, 2);
    expect(ImapService.marksOf([r'\Seen', r'$ognlater', r'$OgnControl']), 3, reason: 'без учёта регистра');
  });
}

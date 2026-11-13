// Фото «inline» без Content-ID — по настоящему ответу сервера (13.11.2026:
// письмо «Fwd: Занавеси», переслано из веб-почты Яндекса; у пользователя на
// ящике Яндекса и у владельца на Gmail — оба вход через OAuth, IMAP).
// Структура письма — как её отдают Gmail и Яндекс на UID FETCH BODYSTRUCTURE;
// разбор — разборщиком почтовой библиотеки, а не собранной вручную частью.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';

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

  // Gmail: строчными, у картинки — MD5 NIL, затем disposition.
  const gmail = '(("text" "html" ("charset" "utf-8") NIL NIL "8bit" 612 14 NIL NIL NIL NIL)'
      '("image" "jpeg" ("name" "image0.jpeg") NIL NIL "base64" 225786 NIL ("inline" ("filename" "image0.jpeg")) NIL NIL)'
      ' "mixed" ("boundary" "----==--bound.209540") NIL NIL NIL)';
  // Яндекс: заглавными, без языка и места.
  const yandex = '(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "8BIT" 612 14)'
      '("IMAGE" "JPEG" ("NAME" "image0.jpeg") NIL NIL "BASE64" 225786 NIL ("INLINE" ("FILENAME" "image0.jpeg")))'
      ' "MIXED" ("BOUNDARY" "----==--bound.209540"))';

  for (final (name, bs) in const [('Gmail', gmail), ('Яндекс', yandex)]) {
    test('$name: image0.jpeg — вложение (список с сервера и при открытии)', () async {
      final m = inbox.add('Fwd: Занавеси')..bodyStructure = bs;
      final list = await imap.fetchAttachmentList(account(), folderId: 'INBOX', uid: m.uid);
      expect(list, isNotNull);
      final files = [for (final a in list!) if (!a.isInline) a];
      expect(files.map((a) => a.name), ['image0.jpeg']);
      expect(files.single.mimeType, 'image/jpeg');

      final full = await imap.getEmailDetail(account(), folderId: 'INBOX', uid: m.uid);
      expect([for (final a in full!.attachments) if (!a.isInline) a.name], ['image0.jpeg']);
    });
  }
}

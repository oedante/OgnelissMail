// Дата письма IMAP — время прихода на сервер (INTERNALDATE), а не заголовок
// Date (14.11.2026, замечание владельца: «перемешиваются данные по датам»).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('разбор и правило', () {
    test('INTERNALDATE → момент UTC, с поясом и без кавычек', () {
      expect(ImapService.parseInternalDate('14-Nov-2026 10:38:00 +0300'), DateTime.utc(2026, 11, 14, 7, 38));
      expect(ImapService.parseInternalDate(' 4-Nov-2026 23:10:05 -0500'), DateTime.utc(2026, 11, 5, 4, 10, 5));
      expect(ImapService.parseInternalDate('"01-Jan-2027 00:00:00 +0000"'), DateTime.utc(2027));
      expect(ImapService.parseInternalDate('вчера'), isNull);
      expect(ImapService.parseInternalDate(null), isNull);
    });

    test('время прихода важнее даты из письма; перенос ящика — дата письма', () {
      final header = DateTime.utc(2026, 11, 14, 8);
      final arrived = DateTime.utc(2026, 11, 14, 8, 40);
      expect(ImapService.arrivalDate(internal: arrived, header: header), arrived);
      // Отправитель поставил время в будущем — по приходу.
      expect(ImapService.arrivalDate(internal: arrived, header: DateTime.utc(2026, 11, 20)), arrived);
      // Пришло через неделю после даты письма — перенос или импорт ящика.
      final moved = DateTime.utc(2026, 11, 21);
      expect(ImapService.arrivalDate(internal: moved, header: header), header);
      expect(ImapService.arrivalDate(internal: null, header: header), header);
      expect(ImapService.arrivalDate(internal: arrived, header: null), arrived);
    });
  });

  group('сервер', () {
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
      srv = FakeImapServer(caps: 'IMAP4rev1', capsAtLogin: true);
      inbox = srv.box('INBOX');
      await srv.start();
    });

    tearDown(() async {
      imap.dispose();
      await srv.close();
    });

    test('новые письма — по времени прихода; без него и при переносе — дата письма', () async {
      // Заголовок Date у писем тестового сервера — 26.10.2026 10:00 UTC.
      final a = inbox.add('Пришло через 5 минут')..internalDate = '26-Oct-2026 13:05:00 +0300';
      final b = inbox.add('Без времени прихода');
      final c = inbox.add('Перенесено через месяц')..internalDate = '26-Nov-2026 09:00:00 +0000';
      final delta = await imap.syncFolderDelta(account(), folderId: 'INBOX');
      final at = {for (final e in delta.added) e.id: e.receivedAt.toUtc()};
      expect(at['INBOX:${a.uid}'], DateTime.utc(2026, 10, 26, 10, 5));
      expect(at['INBOX:${b.uid}'], DateTime.utc(2026, 10, 26, 10));
      expect(at['INBOX:${c.uid}'], DateTime.utc(2026, 10, 26, 10));
    });

    test('время прихода окна писем — для исправления уже загруженных', () async {
      final a = inbox.add('Первое')..internalDate = '26-Oct-2026 13:05:00 +0300';
      final b = inbox.add('Второе');
      final dates = await imap.arrivalDates(account(), folderId: 'INBOX', minUid: a.uid, maxUid: b.uid);
      expect(dates, {a.uid: DateTime.utc(2026, 10, 26, 10, 5)});
    });
  });
}

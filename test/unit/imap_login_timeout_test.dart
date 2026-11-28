// Ответ на вход потерялся (2.7.5, журнал пользователя 27.11.2026: на
// мобильном интернете Яндекс не ответил на вход, проверка ящика ждала общий
// срок ответа — 3 минуты — и обрывалась через 90 с). Теперь на вход — свой
// срок и одно новое подключение.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/dav/dav_credentials.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeImapServer srv;
  late ImapService imap;
  final saved = ImapService.loginTimeout;

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
    ImapService.loginTimeout = const Duration(seconds: 1);
    srv = FakeImapServer();
    srv.box('INBOX');
    await srv.start();
    imap = ImapService(SecureStorageService());
  });

  tearDown(() async {
    ImapService.loginTimeout = saved;
    imap.dispose();
    await srv.close();
  });

  test('сервер не ответил на вход — новое подключение, папки получены', () async {
    srv.hangOnceOn.add('LOGIN');
    final sw = Stopwatch()..start();
    final folders = await imap.getFolders(account());
    expect(folders, isNotEmpty);
    expect(srv.commands.where((c) => c.startsWith('LOGIN')).length, 2);
    expect(srv.connectionCount, greaterThanOrEqualTo(2));
    expect(sw.elapsed, lessThan(const Duration(seconds: 20)), reason: 'не ждём общий срок ответа');
  });

  test('Gmail по паролю приложения: календарь и контакты Google не запрашиваются', () async {
    FlutterSecureStorage.setMockInitialValues({'pwd_g1': 'app-password'});
    final gmail = AccountModel(
      id: 'g1',
      type: AccountType.imap,
      email: 'someone@gmail.com',
      displayName: 'G',
      username: 'someone@gmail.com',
      imapServer: 'imap.gmail.com',
      createdAt: DateTime(2026),
    );
    expect(await DavCredentials.authorization(gmail, SecureStorageService()), isNull);
    // Яндекс по паролю — по-прежнему с паролем.
    FlutterSecureStorage.setMockInitialValues({'pwd_y1': 'pw'});
    final yandex = AccountModel(
      id: 'y1',
      type: AccountType.imap,
      email: 'someone@yandex.ru',
      displayName: 'Y',
      username: 'someone@yandex.ru',
      imapServer: 'imap.yandex.ru',
      createdAt: DateTime(2026),
    );
    expect(await DavCredentials.authorization(yandex, SecureStorageService()), startsWith('Basic '));
  });
}

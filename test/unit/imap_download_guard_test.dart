// Вложения при плохой связи (2.7.2, журнал владельца 23.11.2026: «при
// плохом интернете скачивание вложений идёт долго и не заканчивается,
// мешает синхронизации, при восстановлении доступа скачивание не
// начинается — пришлось закрывать приложение»).
//
// enough_mail при закрытом сокете не завершает команды, ждущие ответа, —
// они висели до тайм-аута операции (у вложения — 20 минут). Теперь операция
// идёт наперегонки с обрывом соединения и с остановкой приёма.
import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show TolerantImapClient;
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('сервер-заглушка: вложение «встало»', () {
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
      ImapService.attachmentStall = const Duration(milliseconds: 600);
      ImapService.stallCheck = const Duration(milliseconds: 100);
      imap = ImapService(SecureStorageService());
      srv = FakeImapServer(caps: 'IMAP4rev1 IDLE', capsAtLogin: true);
      inbox = srv.box('INBOX');
      await srv.start();
    });

    tearDown(() async {
      ImapService.attachmentStall = const Duration(seconds: 60);
      ImapService.stallCheck = const Duration(seconds: 5);
      imap.dispose();
      await srv.close();
    });

    test('синхронизация ящика не ждёт вложение; встало — повтор на новом соединении и ошибка связи', () async {
      final m = inbox.add('Договор');
      srv.hangOn.add('BODY.PEEK[2]');
      final sw = Stopwatch()..start();
      final download = imap.fetchAttachment(account(), folderId: 'INBOX', uid: m.uid, partNumber: '2');
      // Пока вложение «качается», список папок — сразу (раньше — в очереди
      // за вложением до 20 минут).
      final folders = await imap.getFolders(account()).timeout(const Duration(seconds: 3));
      expect(folders, isNotEmpty);
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 600)));
      await expectLater(download, throwsA(isA<SocketException>()));
      // Основное соединение + вложения + повтор вложения на новом.
      expect(srv.connectionCount, 3);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('смена сети посреди скачивания — повтор на новом соединении сразу, без ожидания', () async {
      final m = inbox.add('Договор');
      srv.hangOn.add('BODY.PEEK[2]');
      // Остановка приёма — через 30 с: повтор раньше неё — значит, по обрыву.
      ImapService.attachmentStall = const Duration(seconds: 30);
      int fetches() => srv.commands.where((c) => c.contains('BODY.PEEK[2]')).length;
      // Ждём событий, а не фиксированные доли секунды (2.7.5: при
      // параллельном прогоне тестов машина занята и 300 мс не хватало).
      Future<void> until(bool Function() ok, String what) async {
        final sw = Stopwatch()..start();
        while (!ok()) {
          if (sw.elapsed > const Duration(seconds: 10)) fail('не дождались: $what');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      final download = imap.fetchAttachment(account(), folderId: 'INBOX', uid: m.uid, partNumber: '2');
      await until(() => fetches() == 1, 'запрос вложения');
      expect(srv.connectionCount, 1);
      final sw = Stopwatch()..start();
      imap.dropConnections(reason: 'смена сети');
      // Обрыв замечен сразу: новое соединение и повтор запроса — не через
      // 30 с остановки приёма.
      await until(() => srv.connectionCount >= 2 && fetches() == 2, 'повтор на новом соединении');
      expect(srv.connectionCount, 2);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
      imap.dropConnections(reason: 'смена сети');
      await expectLater(download.timeout(const Duration(seconds: 10)), throwsA(isA<SocketException>()));
    });
  });

  test('обрыв соединения (смена сети) — ждущая команда сразу с ошибкой связи', () async {
    final client = TolerantImapClient();
    final never = Completer<int>().future; // команда, ответ на которую не придёт
    final op = ImapService.guarded(client, never);
    final sw = Stopwatch()..start();
    unawaited(client.abort('смена сети'));
    await expectLater(op, throwsA(isA<SocketException>()));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(client.isLost, isTrue);
  });

  test('приём встал — соединение закрывается, операция падает обрывом', () async {
    final client = TolerantImapClient();
    final never = Completer<int>().future;
    final op = ImapService.guarded(client, never,
        stall: const Duration(milliseconds: 300), check: const Duration(milliseconds: 50));
    await expectLater(op, throwsA(isA<SocketException>()));
    expect(client.isLost, isTrue);
  });

  test('операция завершилась — результат как есть, соединение живо', () async {
    final client = TolerantImapClient();
    final op = ImapService.guarded(client, Future<int>.delayed(const Duration(milliseconds: 20), () => 42),
        stall: const Duration(seconds: 5), check: const Duration(milliseconds: 50));
    expect(await op, 42);
    expect(client.isLost, isFalse);
  });

  test('ошибка самой команды — та же ошибка, не обрыв', () async {
    final client = TolerantImapClient();
    final op = ImapService.guarded(client, Future<int>.error(StateError('Part not found: 3')));
    await expectLater(op, throwsA(isA<StateError>()));
    expect(client.isLost, isFalse);
  });

  test('обрыв без ждущих — не считается необработанной ошибкой', () async {
    final client = TolerantImapClient();
    await client.abort('закрыто');
    expect(client.isLost, isTrue);
    await expectLater(client.lost, throwsA(isA<SocketException>()));
  });

  test('что повторяется, когда сеть вернётся: связь — да, отказ сервера — нет', () {
    expect(MailEngineService.isNetworkFailure(const SocketException('Connection reset by peer')), isTrue);
    expect(MailEngineService.isNetworkFailure(TimeoutException('x')), isTrue);
    expect(MailEngineService.isNetworkFailure(const SocketException('IMAP: соединение потеряно — смена сети')), isTrue);
    expect(MailEngineService.isNetworkFailure(StateError('EAS: вложение не получено (HTTP 0)')), isTrue);
    expect(MailEngineService.isNetworkFailure(Exception('Failed host lookup: imap.gmail.com')), isTrue);
    expect(MailEngineService.isNetworkFailure(StateError('EAS: ItemOperations Fetch Status=6')), isFalse);
    expect(MailEngineService.isNetworkFailure(Exception('Part not found: 3')), isFalse);
  });
}

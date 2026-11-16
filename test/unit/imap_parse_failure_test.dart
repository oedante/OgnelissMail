// Письмо, структуру которого почтовая библиотека не разобрала (2.6.0;
// журнал Samsung S24 16.11.2026, Mail.ru и Яндекс).
//
// В enough_mail 2.1.7 RangeError при разборе BODYSTRUCTURE (список
// параметров нечётной длины) вылетал из обработчика данных сокета: ответ
// «OK» на команду оставался в буфере, и FETCH ждал до тайм-аута — 5 мин на
// каждой проверке, папка не синхронизировалась. Теперь
// (TolerantImapClient) сбой одной строки не останавливает разбор остальных,
// команда завершается в срок, а такое письмо загружается ещё раз без
// структуры. Сервер — поддельный (fake_imap_server.dart).

import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart' show ImapException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show TolerantImapClient;
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

import 'fake_imap_server.dart';

/// Multipart с нечётным списком параметров: разборщик enough_mail 2.1.7
/// берёт parameters[i + 1] за концом списка — RangeError, как в журнале.
const _broken = '(("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 10 1 NIL NIL NIL NIL)'
    ' "MIXED" ("BOUNDARY" "b1" "A" "1" "B" "2" "C" "3" "D" "4" "E"))';

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

  test('синхронизация папки не зависает: письмо с неразобранной структурой — без неё, остальные как обычно', () async {
    inbox.add('Первое');
    inbox.add('Чек').bodyStructure = _broken;
    inbox.add('Третье');
    final d = await imap
        .syncFolderDelta(account(), folderId: 'INBOX', backfill: 0)
        .timeout(const Duration(seconds: 20), onTimeout: () => fail('FETCH завис'));
    expect([for (final e in d.added) e.subject]..sort(), ['Первое', 'Третье', 'Чек']);
    expect(d.state.maxUid, 3);
    expect(
        srv.commands.where((c) => c.contains('FETCH') && c.contains('ENVELOPE') && !c.contains('BODYSTRUCTURE')),
        isNotEmpty,
        reason: 'письмо 2 загружено ещё раз без структуры');
  });

  test('открытие письма и список вложений — ответ в срок', () async {
    final m = inbox.add('Чек')..bodyStructure = _broken;
    final list = await imap
        .fetchAttachmentList(account(), folderId: 'INBOX', uid: m.uid)
        .timeout(const Duration(seconds: 20), onTimeout: () => fail('FETCH завис'));
    expect(list, isEmpty);
    final full = await imap
        .getEmailDetail(account(), folderId: 'INBOX', uid: m.uid)
        .timeout(const Duration(seconds: 20), onTimeout: () => fail('FETCH завис'));
    expect(full?.subject, 'Чек');
  });

  test('открытое письмо — целиком: текст, вложение с русским именем и его скачивание', () async {
    final m = inbox.add('Чек')
      ..bodyStructure = _broken
      ..raw = 'From: shop@example.com\n'
          'To: me@example.com\n'
          'Subject: Chek\n'
          'MIME-Version: 1.0\n'
          'Content-Type: multipart/mixed; boundary="b1"\n'
          '\n'
          '--b1\n'
          'Content-Type: text/plain; charset=utf-8\n'
          'Content-Transfer-Encoding: 8bit\n'
          '\n'
          'Ваш чек во вложении.\n'
          '--b1\n'
          'Content-Type: application/pdf; name="=?utf-8?B?0KfQtdC6LnBkZg==?="\n'
          'Content-Disposition: attachment; filename="=?utf-8?B?0KfQtdC6LnBkZg==?="\n'
          'Content-Transfer-Encoding: base64\n'
          '\n'
          'JVBERi0xLjQK\n'
          '--b1--\n';
    final full = await imap
        .getEmailDetail(account(), folderId: 'INBOX', uid: m.uid)
        .timeout(const Duration(seconds: 20), onTimeout: () => fail('FETCH завис'));
    expect(full?.bodyPlain, contains('Ваш чек во вложении.'));
    final files = [for (final a in full!.attachments) if (!a.isInline) a];
    expect(files.map((a) => a.name), ['Чек.pdf']);
    final data = await imap
        .fetchAttachment(account(), folderId: 'INBOX', uid: m.uid, partNumber: files.single.id)
        .timeout(const Duration(seconds: 20), onTimeout: () => fail('FETCH завис'));
    expect(String.fromCharCodes(data), '%PDF-1.4\n');
  });

  test('запрос без BODYSTRUCTURE', () {
    expect(ImapService.withoutStructure('(UID FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE)'),
        '(UID FLAGS ENVELOPE RFC822.SIZE)');
    expect(ImapService.withoutStructure('(UID BODYSTRUCTURE)'), '(UID)');
    expect(ImapService.withoutStructure('(BODYSTRUCTURE BODY.PEEK[2])'), '(BODY.PEEK[2])');
  });

  test('вход XOAUTH2: тайм-аут и обрыв связи — не отказ (токен не обновляется принудительно)', () {
    final c = TolerantImapClient();
    expect(ImapService.isAuthRejection(ImapException(c, 'timeout')), isFalse);
    expect(ImapService.isAuthRejection(TimeoutException('x')), isFalse);
    expect(ImapService.isAuthRejection(const SocketException('Connection reset by peer')), isFalse);
    expect(ImapService.isAuthRejection(ImapException(c, 'onDone not expected')), isFalse);
    expect(ImapService.isAuthRejection(ImapException(c, 'AUTHENTICATIONFAILED Invalid credentials')), isTrue);
  });
}
